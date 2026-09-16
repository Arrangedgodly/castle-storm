## Engine-level catch-up property suite (T-QA-04) — away windows under a
## bounded fuzz, through the REAL engine.
##
## The pure-function properties live in `tests/property/test_catch_up_properties.gd`
## (gdUnit4 fuzzer); this suite is their ENGINE-level form and runs in the
## marathon runner (no framework timeout — the T-QA-03 precedent for fuzz
## cycles that drive full engines). One full MVP stack (suspicion LAST per
## §14) plays an honest prefix, then a PINNED-SEED bounded fuzz of away
## windows — durations from 30 seconds to 100 years, backwards windows
## included — each window resolved through `CatchUpService.apply` with
## INJECTED UTC timestamps only, and checked against a TWIN ENGINE that
## runs the same away ticks LIVE (tick() loop, never fast_forward):
##
##   W1  every window applies EXACTLY clamp(elapsed, 0, cap) ÷ 60 ticks
##       (expected value computed by an independent restatement of the
##       spec, not by calling the service);
##   W2  twin parity EVERY window: state_hash + per-type resources equal
##       the live twin after the same tick count;
##   W3  idempotence at the host boundary: re-applying the SAME foreground
##       timestamp immediately after a window applies zero ticks and
##       changes nothing (the anchor snapped to now — away time never
##       double-counts across foregrounds);
##   W4  a rewind window (now < anchor, down to −100 years) changes
##       NOTHING: zero ticks, state_hash bit-identical, rewound flag set,
##       and the anchor still follows (docs/catch-up.md §4).
##
## Deterministic boundary windows are driven first (59s / 60s / 2h /
## cap−60 / cap−59 / exactly cap / cap+59 / cap+60), then FUZZ_WINDOWS=40
## seeded draws over six bands (sub-tick, minutes-scale, normal, exact
## tick multiples, capped, rewind). Seed pinned below and echoed in the
## digest — replays exactly. Between windows both engines play the same
## LIVE ticks (playing sessions are marked seen, so none of that time is
## away time — and parity must survive the interleaving).
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const RUN_SEED := 20261002
const WINDOW_SEED := 20261102
const FUZZ_WINDOWS := 40
const T0 := 1_790_000_000  # injected UTC epoch; any value works — DST-safe by design
const HUNDRED_YEARS := 3153600000  # 100 * 365 * 86400 s
const TOTAL_BUDGET_SECONDS := 30.0


func suite_name() -> String:
	return "catch_up_property_windows"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = WINDOW_SEED

	var pack := MVP.load_mvp()
	var cap_seconds: int = int(round(pack.tunables.offline_cap_hours * 3600.0))
	var service := CatchUpService.new(pack.tunables)
	harness.check(service.cap_seconds == cap_seconds and service.cap_ticks() == 480, "R4 default cap is 8h = 480 ticks (cap %d s -> %d ticks)" % [service.cap_seconds, service.cap_ticks()])

	# --- Honest prefix on both engines, twins bit-identical ------------------
	var engine := _build()
	var meta := _meta_of(engine)
	var twin := _build()
	_play_prefix(engine)
	_play_prefix(twin)
	harness.check(engine.state_hash() == twin.state_hash(), "prefix leaves the twins bit-identical (hash %d)" % engine.state_hash())

	# --- Deterministic boundary windows, then the seeded fuzz -----------------
	var windows: Array = []  # [label: String, away_seconds: int]
	windows.append(["boundary_59s", 59])                     # sub-tick: 0 ticks
	windows.append(["boundary_60s", 60])                     # exactly one tick
	windows.append(["boundary_2h", 2 * 3600])                # plain window
	windows.append(["boundary_cap_minus_60", cap_seconds - 60])  # one tick short of cap
	windows.append(["boundary_cap_minus_59", cap_seconds - 59])  # one second short of cap edge
	windows.append(["boundary_cap_exact", cap_seconds])      # exactly the cap
	windows.append(["boundary_cap_plus_59", cap_seconds + 59])   # over the cap, still 480
	windows.append(["boundary_cap_plus_60", cap_seconds + 60])   # a full minute over, still 480
	for i in FUZZ_WINDOWS:
		windows.append(_draw_window(rng, cap_seconds))

	var now_epoch := T0
	var applied_total := 0
	for i in windows.size():
		var label: String = windows[i][0]
		var away: int = windows[i][1]

		# A playing stretch between windows: BOTH engines live-tick it (the
		# host marks the session seen, so none of it is away time — and the
		# twins must survive the interleaving of live and away advancement).
		var play_ticks := rng.randi_range(0, 300)
		now_epoch += play_ticks * SimEngine.TICK_SECONDS
		engine.fast_forward(play_ticks)
		twin.fast_forward(play_ticks)
		service.mark_seen(meta, now_epoch)
		var foreground := now_epoch + away

		# W4 pre-state for rewind windows.
		var hash_before := engine.state_hash()

		var report := service.apply(engine, meta, foreground)

		# W1 — exactly clamp(elapsed) ÷ TICK ticks, by the independent model.
		var expected: int = clampi(away, 0, cap_seconds) / SimEngine.TICK_SECONDS
		applied_total += expected
		harness.check(
			int(report["applied_ticks"]) == expected,
			"window %d [%s] (%+d s) applies exactly clamp(elapsed)/TICK = %d ticks (got %d)"
			% [i, label, away, expected, int(report["applied_ticks"])]
		)
		harness.check(
			bool(report["rewound"]) == (away < 0),
			"window %d [%s] (%+d s) flags rewind exactly when now < anchor" % [i, label, away]
		)

		# W2 — twin parity, every window: the same away ticks, LIVE.
		for j in expected:
			twin.tick()
		harness.check(
			engine.state_hash() == twin.state_hash(),
			"window %d [%s] (%+d s) keeps twin parity (hash %d vs %d)"
			% [i, label, away, engine.state_hash(), twin.state_hash()]
		)
		harness.check(_resources_equal(engine, twin), "window %d [%s] (%+d s) keeps per-type resource parity" % [i, label, away])

		# W4 — a rewind window changes NOTHING (hash bit-identical; only the
		# announcement event + the anchor move).
		if away < 0:
			harness.check(engine.state_hash() == hash_before, "rewind window %d [%s] (%+d s) changes no state (hash identical)" % [i, label, away])
			harness.check(int(report["applied_ticks"]) == 0, "rewind window %d [%s] applies zero ticks" % [i, label])

		# W3 — idempotence at the host boundary: re-applying the SAME
		# foreground timestamp applies nothing and changes nothing (the
		# anchor snapped; away time never double-counts).
		var hash_after := engine.state_hash()
		var ticks_after: int = engine.tick_count
		var again := service.apply(engine, meta, foreground)
		harness.check(int(again["applied_ticks"]) == 0, "window %d [%s]: re-applying the same foreground applies 0 ticks (got %d)" % [i, label, int(again["applied_ticks"])])
		harness.check(engine.tick_count == ticks_after and engine.state_hash() == hash_after, "window %d [%s]: re-apply changes no state" % [i, label])

		now_epoch = foreground

	# --- Accounting: the twins never drifted, the model total matches --------
	var model_total := 0
	for w in windows:
		model_total += clampi(int(w[1]), 0, cap_seconds) / SimEngine.TICK_SECONDS
	harness.check(applied_total == model_total, "applied-tick total equals the independent model's total (%d vs %d)" % [applied_total, model_total])
	harness.check(engine.tick_count == twin.tick_count, "engine and twin tick counts identical after %d windows (%d)" % [windows.size(), engine.tick_count])

	var tally := {}
	for w in windows:
		tally[w[0]] = int(tally.get(w[0], 0)) + 1
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	print(
		"[catch_up_property_windows] seed %d | %d windows (8 boundary + %d fuzz) | bands %s | %d away ticks applied | hashes %d / %d | %.3fs"
		% [WINDOW_SEED, windows.size(), FUZZ_WINDOWS, str(tally), applied_total, engine.state_hash(), twin.state_hash(), wall]
	)
	harness.check(wall < TOTAL_BUDGET_SECONDS, "whole suite in < %.0fs (took %.3fs)" % [TOTAL_BUDGET_SECONDS, wall])


# --- Window drawing -------------------------------------------------------------


## One fuzzed window as [band label, duration seconds] (negative = backwards
## clock), across six bands so every behavior class is exercised every run:
##   sub_tick 30..59 | minutes 60..3600 | normal 60..cap−1
##   exact_tick multiples of 60 up to cap | capped cap..100y | rewind −100y..−30
##
## HARNESS NOTE (measured, Godot 4.7.2): `RandomNumberGenerator.randi_range`
## silently corrupts ranges beyond int32 (a 100y span returns negatives) —
## spans that wide are composed from two int32-safe draws instead.
func _draw_window(rng: RandomNumberGenerator, cap_seconds: int) -> Array:
	match rng.randi_range(0, 5):
		0:
			return ["fuzz_sub_tick", rng.randi_range(30, 59)]
		1:
			return ["fuzz_minutes", rng.randi_range(60, 3600)]
		2:
			return ["fuzz_normal", rng.randi_range(60, cap_seconds - 1)]
		3:
			return ["fuzz_exact_tick", rng.randi_range(1, cap_seconds / 60) * 60]
		4:
			return ["fuzz_capped", cap_seconds + _span_years(rng)]
		_:
			return ["fuzz_rewind", -(30 + _span_years(rng))]


## A fuzzed non-negative span in [0, 100 years) from two int32-safe draws
## (100y = 3.1536e9 s > 2^31 — not directly drawable, see note above).
func _span_years(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 31535) * 100000 + rng.randi_range(0, 99999)


# --- Builders (the marathon_catch_up_gap shapes) ------------------------------


## Full MVP stack + suspicion (§14 order): the away window advances the real
## economy AND the real pressure curve.
func _build() -> SimEngine:
	var pack := MVP.load_mvp()
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, null, pack.starting_grants))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))
	engine.register_system(SuspicionSystem.new(pack.tunables, pack.units))
	return engine


func _meta_of(engine: SimEngine) -> RunMeta:
	return (engine.get_system(&"run") as RunLifecycleSystem).meta


## 12h of honest play: start + grant, construct every producer, then one
## managed stretch so the estate is staffed before the first window.
func _play_prefix(engine: SimEngine) -> void:
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	for id in MVP.producer_ids():
		engine.submit_command(&"upgrade_building", id, 0)  # construct at base cost
	_quiet_manage(engine)
	engine.fast_forward(12 * SimEngine.TICKS_PER_SIM_HOUR)


func _quiet_manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	for uid in units.idle_units(&"peasant"):
		engine.submit_command(&"assign_role", &"worker", uid)
	var production := engine.get_system(&"production") as ProductionSystem
	for id in MVP.producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


func _resources_equal(a: SimEngine, b: SimEngine) -> bool:
	var ids: Array = a.resources.keys()
	for id in b.resources.keys():
		if not ids.has(id):
			ids.append(id)
	for id in ids:
		if a.get_resource(id) != b.get_resource(id):
			return false
	return true
