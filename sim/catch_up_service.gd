## Offline catch-up (T-SIM-07) — timestamp math at the foreground boundary.
##
## A plain RefCounted HOST SERVICE (the SaveManager discipline: no scene
## tree, no autoload, no wall-clock reads — every timestamp is INJECTED by
## the platform host per docs/catch-up.md's away-time semantics; sim/ never
## touches a clock, gdscript-conventions "Determinism rules"). The full
## contract is documented in docs/catch-up.md; the shape:
##
##   - ANCHOR: `RunMeta.last_seen_epoch` (UTC epoch seconds, META save
##     domain). 0 = first-launch sentinel — no anchor, no catch-up.
##   - MATH (pure, fuzzable — T-QA-04's target): elapsed = now − anchor;
##     clamped to [0, cap]; applied_ticks = clamped ÷ 60 (floor). R4:
##     cap 8h @100% linear accrual, seeded from EconomyTunables.
##   - REPLAY: the clamped gap runs through the REAL engine's
##     `fast_forward` — arrivals, training, production and suspicion all
##     advance by the actual deterministic rules, never a parallel
##     accrual formula (Thor: computed from timestamps, never real-time
##     simulation of the gap). 8h = 480 ticks — synchronous, bounded,
##     measured far under the 100ms budget.
##   - SUMMARY: one `catch_up_applied` ring event + the returned report
##     (per-type resource deltas, arrivals, completions, promotions,
##     suspicion delta); the raw ring tail stays for detail (§3).
##   - CLAMPS (Hulk): backwards clock → 0 accrual, ZERO state change, a
##     `catch_up_clock_rewound` event + a wry chronicle line; forward
##     jumps cap at 8h; DST/timezone are structurally invisible (UTC
##     epoch everywhere, local time never stored).
##   - FREEZE: an in-app-PAUSED engine accrues nothing — pause is a
##     world freeze, and playing sessions never count as away time.
##   - CRASH SAFETY: apply() is synchronous before gameplay resumes; a
##     kill mid-catch-up leaves the pre-catch-up save valid and the next
##     load simply recomputes from the anchor (bounded by the cap).
class_name CatchUpService
extends RefCounted

## `RunMeta.last_seen_epoch` value meaning "no anchor yet" (first launch /
## pre-T-SIM-07 meta): never accrue off it, whatever `now` claims.
const FIRST_LAUNCH_SENTINEL := 0

## Timestamp magnitudes are clamped to ±this before any subtraction
## (2^40 seconds ≈ ±34,000 years around the 1970 epoch; real platform
## clocks sit near 1.8e9). The pure math can therefore be fuzzed with
## int64 extremes — the widest representable gap is 2^41 seconds and no
## subtraction can overflow.
const TIMESTAMP_LIMIT := 1 << 40

## Accrual ceiling in seconds, from `EconomyTunables.offline_cap_hours`
## (R4: 8h default; validator band 4–24h). Linear at 100% —
## `offline_rate` is pinned 1.0 by the validator (premium stance), so
## there is deliberately no rate term in the math.
var cap_seconds: int


func _init(tunables: EconomyTunables = null) -> void:
	var t := tunables if tunables != null else EconomyTunables.new()
	cap_seconds = int(round(t.offline_cap_hours * 3600.0))


# --- Pure accrual math (the T-QA-04 fuzz surface) --------------------------
#
# Zero engine state, zero clocks, zero allocation-heavy work: integer
# clamp + integer divide. Every property test needs is stated here —
# output is NEVER negative, NEVER uncapped, and the mapping is monotone
# in elapsed for a fixed cap.


## elapsed clamped into [0, cap]. A non-positive cap yields 0 (defensive:
# the validator band makes real caps 4–24h, but fuzzers throw anything).
static func clamp_elapsed_seconds(elapsed_seconds: int, p_cap_seconds: int) -> int:
	return clampi(elapsed_seconds, 0, maxi(p_cap_seconds, 0))


## The accrual rule: applied_ticks = clamp(elapsed, 0, cap) ÷ tick_seconds,
## floored. Sub-tick remainders never tick (a 59-second foreground applies
## nothing; the anchor then snaps to `now`, discarding the remainder —
## bounded error < 1 sim-minute per away window, documented).
static func applied_ticks_for(
	elapsed_seconds: int,
	p_cap_seconds: int,
	tick_seconds: int = SimEngine.TICK_SECONDS
) -> int:
	if tick_seconds <= 0:
		push_warning("catch-up: tick_seconds must be > 0 (got %d) — no accrual" % tick_seconds)
		return 0
	return clamp_elapsed_seconds(elapsed_seconds, p_cap_seconds) / tick_seconds


## now − anchor, computed overflow-safely: both operands are clamped to
## ±TIMESTAMP_LIMIT first, so the widest subtraction is 2^41 and int64
## extremes cannot wrap (DST/timezone are invisible by construction —
## these are UTC epoch seconds, never local time).
static func elapsed_between(last_seen_epoch: int, now_epoch: int) -> int:
	var anchor := clampi(last_seen_epoch, -TIMESTAMP_LIMIT, TIMESTAMP_LIMIT)
	var now_clamped := clampi(now_epoch, -TIMESTAMP_LIMIT, TIMESTAMP_LIMIT)
	return now_clamped - anchor


## The cap expressed in ticks (8h → 480; the compute bound Thor asserted).
func cap_ticks() -> int:
	return cap_seconds / SimEngine.TICK_SECONDS


# --- The service -------------------------------------------------------------


## Resolves one away window SYNCHRONOUSLY (the host calls this on
## foreground/load, before gameplay resumes). Fast-forwards the engine by
## the clamped gap, records the summary event(s), refreshes the anchor to
## `now_epoch` (ALWAYS — rewound clocks included; the service consumes
## platform timestamps and never extrapolates), and returns the catch-up
## report Dictionary for T-UI-09:
##
##   first_launch, rewound, capped, skipped_paused : bool
##   elapsed_seconds (raw, post-overflow-clamp), clamped_seconds        : int
##   applied_ticks, from_tick, to_tick, cap_seconds, cap_ticks          : int
##   events_in_window, arrivals, training_completions,
##   promotions, run_endings, crackdowns                                : int
##   resources_before / resources_after / resource_delta : Dictionary (int)
##   suspicion_present : bool; suspicion_before/after/delta : int
##
## Anchor refresh rule: `meta.last_seen_epoch = now_epoch` on EVERY call —
## away time is bounded by foreground-to-foreground gaps, never
## accumulates across them.
func apply(engine: SimEngine, meta: RunMeta, now_epoch: int) -> Dictionary:
	var first_launch := meta == null or meta.last_seen_epoch == FIRST_LAUNCH_SENTINEL
	var raw_elapsed := 0
	if not first_launch:
		raw_elapsed = elapsed_between(meta.last_seen_epoch, now_epoch)
	var clamped := clamp_elapsed_seconds(raw_elapsed, cap_seconds)
	var applied := applied_ticks_for(raw_elapsed, cap_seconds)
	var rewound := raw_elapsed < 0
	var capped := raw_elapsed > cap_seconds
	# FREEZE: an in-app-paused engine accrues nothing — the player froze
	# the world on purpose and playing sessions are not away time. The
	# engine's own fast_forward refuses while paused; we make that a
	# REPORTED outcome instead of a silent zero-return.
	var skipped_paused := applied > 0 and engine.paused
	if skipped_paused:
		applied = 0

	# Before-snapshot (presentation/report data only — never hashed).
	var from_tick := engine.tick_count
	var seq_before := engine.events.next_seq()
	var resources_before := _snapshot_resources(engine)
	var suspicion_before := _suspicion_of(engine)

	# The gap, replayed through the REAL engine (deterministic, includes
	# arrivals/training/production/suspicion — Thor's directive).
	if applied > 0:
		engine.fast_forward(applied)

	# After-snapshot + window scan. The summary events are recorded AFTER
	# seq_after so the window counts only gap events; the ring tail keeps
	# the raw detail for T-UI-09 (§3 of the event-log contract).
	var seq_after := engine.events.next_seq()
	var resources_after := _snapshot_resources(engine)
	var suspicion_after := _suspicion_of(engine)
	if applied > 0:
		engine.events.record(
			engine.tick_count, &"catch_up_applied", &"catch_up", applied, clamped
		)
	if rewound:
		# NO resource loss, NO state change — the rewind is announced, not
		# punished (docs/catch-up.md §4, Cap's no-DRM stance). The payload
		# is the rewound magnitude in seconds.
		engine.events.record(
			engine.tick_count, &"catch_up_clock_rewound", &"catch_up", -raw_elapsed, 0
		)

	if meta != null:
		meta.last_seen_epoch = now_epoch

	return {
		"first_launch": first_launch,
		"rewound": rewound,
		"capped": capped,
		"skipped_paused": skipped_paused,
		"elapsed_seconds": raw_elapsed,
		"clamped_seconds": clamped,
		"applied_ticks": applied,
		"cap_seconds": cap_seconds,
		"cap_ticks": cap_ticks(),
		"from_tick": from_tick,
		"to_tick": engine.tick_count,
		"events_in_window": seq_after - seq_before,
		"arrivals": _count_events(engine, seq_before, seq_after, &"recruit_arrived"),
		"training_completions": _count_events(engine, seq_before, seq_after, &"training_complete"),
		"promotions": _count_events(engine, seq_before, seq_after, &"unit_promoted"),
		"run_endings": _count_events(engine, seq_before, seq_after, &"run_won")
			+ _count_events(engine, seq_before, seq_after, &"run_lost"),
		# Crackdowns that LANDED inside the window (rare — the telegraph must
		# have been armed before the player left): T-UI-09 prints these with
		# weight, so the summary carries the count (docs/catch-up.md §7).
		"crackdowns": _count_events(engine, seq_before, seq_after, &"crackdown_struck"),
		"resources_before": resources_before,
		"resources_after": resources_after,
		"resource_delta": _resource_delta(resources_before, resources_after),
		"suspicion_present": engine.get_system(&"suspicion") != null,
		"suspicion_before": suspicion_before,
		"suspicion_after": suspicion_after,
		"suspicion_delta": suspicion_after - suspicion_before,
	}


## Host hook for "the session is leaving the foreground / just saved":
## refreshes the anchor so the time that follows is measured from HERE.
## Call on background notifications, on saves, and after every apply()
## (apply refreshes internally).
func mark_seen(meta: RunMeta, now_epoch: int) -> void:
	if meta != null:
		meta.last_seen_epoch = now_epoch


## Prof X placeholder voice (the chronicle_line render-query pattern,
## T-COPY-01 deepens): pure report → String, no engine access. Empty string
## for nothing-worthy-happened (zero-accrual foregrounds stay silent).
static func chronicle_line(report: Dictionary) -> String:
	if bool(report.get("rewound", false)):
		return (
			"The castle clock was found wound backwards. "
			+ "The steward said nothing, and the stores kept their count."
		)
	if bool(report.get("skipped_paused", false)):
		return "Time itself stood at the gate and was not admitted."
	if int(report.get("applied_ticks", 0)) <= 0:
		return ""
	if bool(report.get("capped", false)):
		var cap_hours := int(report.get("cap_seconds", 0)) / 3600
		return (
			"The conspiracy worked the full watch and then some; "
			+ "only the first %d hours are remembered." % cap_hours
		)
	return "While the leader was away, the conspiracy kept the fires lit."


# --- Internals ----------------------------------------------------------------


static func _snapshot_resources(engine: SimEngine) -> Dictionary:
	var snapshot := {}
	for id in engine.resources.keys():
		snapshot[id] = int(engine.resources[id])
	return snapshot


static func _resource_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta := {}
	for id in before.keys():
		delta[id] = int(after.get(id, 0)) - int(before[id])
	for id in after.keys():
		if not delta.has(id):
			delta[id] = int(after[id])  # a resource that appeared mid-window
	return delta


static func _suspicion_of(engine: SimEngine) -> int:
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	return suspicion.suspicion if suspicion != null else 0


static func _count_events(engine: SimEngine, from_seq: int, to_seq: int, type: StringName) -> int:
	var total := 0
	for seq in range(from_seq, to_seq):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			total += 1
	return total
