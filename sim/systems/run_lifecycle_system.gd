## Run lifecycle system (T-SIM-04): randomized leader/regime generation at
## run start, victory/failure resolution, restart with a new identity,
## chronicle entries and the meta bank reserve.
##
## Third real system on the T-SIM-01 seam after production (§10) and units
## (§11); registers via `register_system()`, the core never changes. Full
## contract in docs/sim-engine.md §12. Determinism rules apply in full:
##   - every generation draw comes from `engine.rng` INSIDE on_command (the
##     sanctioned draw site), in a fixed documented order — identical seeds
##     + identical command timing => identical identities, and `rng.state`
##     is hashed by the engine
##   - identity/regime CONTENT (RegimeDef flavors, IdentityPools) is
##     boot-injected and never serialized — saves carry ids only, exactly
##     like every other system; same pack at boot reproduces the defs
##   - no floats anywhere (names, tags, ints — there is nothing to convert)
##
## Run frame:
##
##   run_start            draw leader (first + epithet + 2 distinct tags +
##                        trait stub) + regime (uniform over the flavors),
##                        status UNSTARTED -> RUNNING, `run_started`
##   grant_resources      pays the pack's starting stipend (boot-injected
##                        content) into the pool, ONCE per run — the F1 fix:
##                        hosts bootstrap runs through this command, never
##                        backdoor set_resource; `resources_granted` per line
##   resolve_victory      entry point for the assault outcome (T-SIM-06 owns
##                        the odds; here the outcome arrives as win/loss) —
##                        banks the run score to RunMeta, appends the
##                        chronicle entry, `run_won` / `run_lost`
##   run_abort            explicit surrender — the THIN failure path for
##                        testing (suspicion-driven failure lands in
##                        T-SIM-05); same banking, `run_aborted`
##   run_restart          fold a NEW identity, reset run-scoped state
##                        (engine resource pool + sibling systems via the
##                        reset contract), `run_restarted`
##
## Failure banks FULL progress (town-hall decision): every ended run —
## victory, defeat, abort, even an unresolved running run that gets
## restarted — accrues its score into RunMeta.legacy_points.
##
## Meta-domain rule: the chronicle + bank live in the META save domain
## (RunMeta), never in this system's engine-side to_dict()/state_hash() —
## they must survive restarts and must not be forkable from a run save.
class_name RunLifecycleSystem
extends SimSystem

## Run status (serialized; read via run_status()).
const STATUS_UNSTARTED := 0
const STATUS_RUNNING := 1
const STATUS_ENDED := 2

## How the last run ended (serialized; read via run_outcome()).
const OUTCOME_NONE := 0
const OUTCOME_VICTORY := 1
const OUTCOME_DEFEAT := 2  # suspicion crushing — T-SIM-05 resolves this
const OUTCOME_ABORTED := 3  # explicit surrender (thin failure path)

## Denial reason codes for `run_denied` events (value payload).
const REASON_ALREADY_STARTED := 1
const REASON_NOT_STARTED := 2
const REASON_NOT_RUNNING := 3
const REASON_NO_CONTENT := 4
const REASON_STIPEND_PAID := 5  # grant_resources: this run already took its stipend

## Thin run-score stub: score = duration_hours + army_power + win bonus.
## Documented placeholder — T-SIM-08's balance pass owns the real formula.
const WIN_BONUS := 100

## Leader trait stub labels — the code-side floor for the trait slot
## (T-COPY-01: the pack's IdentityPools.leader_traits replaces them when
## declared; a generated leader carries the INDEX — drawn, serialized,
## hashed — and the EFFECTIVE pool renders it, one draw either way).
const TRAIT_STUB_LABELS: Array[String] = [
	"Iron-fisted",
	"Silver-tongued",
	"Ink-fingered",
	"Battle-scarred",
]

## The meta bank this run composes into (meta save domain — survives
## restarts; see RunMeta). Public: the host reads it for the meta save and
## hands the SAME instance to every engine it builds.
var meta: RunMeta

## Current run status (STATUS_*).
var status := STATUS_UNSTARTED

## Engine-local run number (1-based; restarts increment). The chronicle's
## monotonic run number is meta.runs_recorded — engines can be re-inited.
var run_index := 0

## How the current/last run ended (OUTCOME_*).
var outcome := OUTCOME_NONE

## Score banked by the last ended run (0 while running).
var last_score := 0

## Tick the current/last run started at (0 before the first run_start).
var start_tick := 0

## Tick the last run ended at (0 while running/unstarted).
var end_tick := 0

var _leader_first := ""
var _leader_epithet := ""
var _leader_tags: Array[StringName] = []
var _trait_stub := 0
var _regime: RegimeDef = null
var _regimes: Array[RegimeDef] = []
var _identity: IdentityPools = null
var _starting_grants: Dictionary = {}  # StringName resource id -> int amount (boot-injected content, never serialized)
var _stipend_run := 0  # run_index that already took its stipend (0 = none; serialized + hashed)


func _init(
	p_regimes: Array[RegimeDef],
	p_identity: IdentityPools = null,
	p_meta: RunMeta = null,
	p_starting_grants: Dictionary = {}
) -> void:
	var seen: Dictionary = {}
	for regime in p_regimes:
		if regime == null:
			continue
		if seen.has(regime.id):
			push_warning("run: duplicate regime id '%s' — keeping first" % regime.id)
			continue
		seen[regime.id] = true
		_regimes.append(regime)
	if _regimes.is_empty():
		push_warning("run: no regimes in pack — run_start will be refused (reason %d)" % REASON_NO_CONTENT)
	_identity = p_identity
	if _identity == null:
		push_warning("run: no identity pools in pack — run_start will be refused (reason %d)" % REASON_NO_CONTENT)
	_starting_grants = p_starting_grants.duplicate()
	meta = p_meta if p_meta != null else RunMeta.new()


func system_name() -> StringName:
	return &"run"


# --- Read API (UI queries; pure, deterministic, no state writes) ----------


func is_running() -> bool:
	return status == STATUS_RUNNING


func run_status() -> int:
	return status


func current_run_index() -> int:
	return run_index


func run_outcome() -> int:
	return outcome


## Score banked by the last ended run (0 while running).
func last_run_score() -> int:
	return last_score


func run_start_tick() -> int:
	return start_tick


func run_end_tick() -> int:
	return end_tick


## Generated leader's full display name ("Bran the Unbearable"; "" before
## the first run_start).
func leader_name() -> String:
	if _leader_first.is_empty():
		return ""
	return "%s %s" % [_leader_first, _leader_epithet]


func leader_first_name() -> String:
	return _leader_first


func leader_epithet() -> String:
	return _leader_epithet


## Copy of the leader's personality tags (drawn distinct, from the pools).
func leader_tags() -> Array[StringName]:
	return _leader_tags.duplicate()


## Index into the effective trait pool (the T-COPY-01 trait slot).
func leader_trait_stub() -> int:
	return _trait_stub


func leader_trait_label() -> String:
	var pool := _trait_labels()
	return pool[_trait_stub % pool.size()]


## The effective trait pool: the pack's leader_traits when declared, the
## code-side stub labels otherwise (T-COPY-01's additive content seam).
func _trait_labels() -> Array[String]:
	if _identity != null and not _identity.leader_traits.is_empty():
		return _identity.leader_traits
	return TRAIT_STUB_LABELS


## The run's RegimeDef — combat modifier + economy quirk for later systems
## (T-SIM-06 reads combat; production already applied the quirk at drain).
## Null before the first run_start or if the saved id left the pack.
func current_regime() -> RegimeDef:
	return _regime


func regime_id() -> StringName:
	return &"" if _regime == null else _regime.id


# --- Victory / failure entry point -----------------------------------------


## Resolves the assault outcome for the running run. T-SIM-06 owns the odds
## and calls this with its result; the thin loop calls it directly. Banks
## the run score (win OR loss — failure banks full progress), appends the
## chronicle entry, emits `run_won`/`run_lost`. The resolution itself is
## tick-aligned: this submits the `resolve_victory` command (subject
## `&"win"`/`&"loss"`, value = army power override, -1 = read the units
## system's army_power() at drain) and it applies at the next tick's drain.
## Returns false (loud, nothing queued) when no run is active.
func resolve_victory(engine: SimEngine, win: bool, army_power: int = -1) -> bool:
	if status != STATUS_RUNNING:
		push_error("run: resolve_victory refused — no run is active (status %d)" % status)
		return false
	engine.submit_command(&"resolve_victory", &"win" if win else &"loss", army_power)
	return true


# --- Tick ---------------------------------------------------------------------

## Run-scoped time is tick arithmetic (start_tick/end_tick) — nothing to do
## per tick. Exists to state that explicitly: no RNG draws here either; all
## generation happens at the run_start/run_restart command drains.
func on_tick(_engine: SimEngine) -> void:
	pass


# --- Commands (the only external write path; drained at tick start) -------


func on_command(engine: SimEngine, command: SimCommand) -> bool:
	match command.kind:
		&"run_start":
			_handle_run_start(engine)
		&"run_restart":
			_handle_run_restart(engine)
		&"run_abort":
			_handle_run_abort(engine)
		&"resolve_victory":
			_handle_resolve(engine, command)
		&"grant_resources":
			_handle_grant(engine, command)
		_:
			return false
	return true


func _handle_run_start(engine: SimEngine) -> void:
	if status != STATUS_UNSTARTED:
		_deny(engine, &"run_start", REASON_ALREADY_STARTED)
		return
	if not _content_ready():
		_deny(engine, &"run_start", REASON_NO_CONTENT)
		return
	_fold_new_run(engine, true)
	engine.events.record(engine.tick_count, &"run_started", regime_id(), run_index)


func _handle_run_restart(engine: SimEngine) -> void:
	if status == STATUS_UNSTARTED:
		_deny(engine, &"run_restart", REASON_NOT_STARTED)
		return
	if not _content_ready():
		_deny(engine, &"run_restart", REASON_NO_CONTENT)
		return
	var previous_outcome := outcome
	if status == STATUS_RUNNING:
		# Restart before resolution: the run still banks (abandoned) — failure
		# banks full progress, and an abandoned run is a failure. The event
		# reports the EFFECTIVE outcome (abandoned), not the stale field.
		previous_outcome = OUTCOME_ABORTED
		_end_run(engine, OUTCOME_ABORTED, -1)
	# The engine resource pool is run-scoped: a new run starts bare-handed.
	for id in engine.resources.keys():
		engine.set_resource(id, 0)
	# Reset contract (docs/sim-engine.md §12): sibling systems that own
	# run-scoped state implement reset_run(regime) and are reset here,
	# synchronously at the drain — no half-reset tick. Absent siblings are
	# skipped (an engine without production is legitimate). T-SIM-05's
	# suspicion system joined this list at landing: its meter, telegraph,
	# relief/re-arm windows and watch counters are all run-scoped.
	var production := engine.get_system(&"production")
	if production != null and production.has_method("reset_run"):
		production.reset_run(_regime)
	var units := engine.get_system(&"units")
	if units != null and units.has_method("reset_run"):
		units.reset_run(_regime)
	var suspicion := engine.get_system(&"suspicion")
	if suspicion != null and suspicion.has_method("reset_run"):
		suspicion.reset_run(_regime)
	# New identity always; new regime only after a VICTORY (town-hall
	# journeys: defeat/abort restarts under the SAME regime, victory swaps).
	_fold_new_run(engine, previous_outcome == OUTCOME_VICTORY)
	engine.events.record(
		engine.tick_count, &"run_restarted", regime_id(), run_index, previous_outcome
	)


func _handle_run_abort(engine: SimEngine) -> void:
	if status != STATUS_RUNNING:
		_deny(engine, &"run_abort", REASON_NOT_RUNNING)
		return
	_end_run(engine, OUTCOME_ABORTED, -1)


func _handle_resolve(engine: SimEngine, command: SimCommand) -> void:
	if status != STATUS_RUNNING:
		_deny(engine, &"resolve_victory", REASON_NOT_RUNNING)
		return
	var win := command.subject == &"win"
	_end_run(engine, OUTCOME_VICTORY if win else OUTCOME_DEFEAT, command.value)


# --- Starting stipend (F1 fix, T-DATA-02) ------------------------------------


## Read API: the pack's starting stipend (resource id -> amount). Content is
## boot-injected and never serialized; the PAID flag below is the run state.
func starting_grants() -> Dictionary:
	return _starting_grants.duplicate()


## Read API: the run index that already took its stipend (0 = none).
func stipend_paid_run() -> int:
	return _stipend_run


## `grant_resources` (subject/value intentionally unused): pays the pack's
## starting stipend into the engine pool, once per run. This is the
## host-facing bootstrap verb that replaces backdoor `set_resource` calls
## (M1 finding F1): the amounts live in CONTENT (boot-injected here), never in
## the command, so the verb cannot carry arbitrary amounts — it is a stipend,
## not a cheat vector. Denied loudly when no run is running (3), the pack
## declares no stipend (4), or this run already took it (5). Emits one
## `resources_granted` event per resource line (sorted resource order — the
## dict's file order is not canonical across hand edits), value = amount
## granted, value2 = new pool total.
func _handle_grant(engine: SimEngine, command: SimCommand) -> void:
	if status != STATUS_RUNNING:
		_deny(engine, command.kind, REASON_NOT_RUNNING)
		return
	if _starting_grants.is_empty():
		_deny(engine, command.kind, REASON_NO_CONTENT)
		return
	if _stipend_run == run_index:
		_deny(engine, command.kind, REASON_STIPEND_PAID)
		return
	var ids: Array = _starting_grants.keys()
	# Sort by STRING text, not the StringName variants themselves: plain
	# sort() on StringNames is not reliably text-ordered across processes
	# (observed: same dict, different event order in two runs).
	ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for id in ids:
		var amount := int(_starting_grants[id])
		engine.add_resource(id, amount)
		engine.events.record(engine.tick_count, &"resources_granted", id, amount, engine.get_resource(id))
	_stipend_run = run_index


# --- Generation + resolution internals ---------------------------------------

## Draws a fresh leader identity (and, when draw_regime, a regime) from
## engine.rng and opens run N+1. Draw order is contractual for the stream:
## first name, epithet, tag, tag 2 (distinct via draw-then-skip), trait
## stub, then the regime when drawn.
func _fold_new_run(engine: SimEngine, draw_regime: bool) -> void:
	_leader_first = _identity.leader_first_names[
		engine.rng.randi_range(0, _identity.leader_first_names.size() - 1)
	]
	_leader_epithet = _identity.leader_epithets[
		engine.rng.randi_range(0, _identity.leader_epithets.size() - 1)
	]
	var pool := _identity.personality_tags
	_leader_tags = [pool[engine.rng.randi_range(0, pool.size() - 1)]]
	if pool.size() > 1:
		# Draw over the n-1 OTHER tags (index past the first on collision —
		# pool values are unique, so one shift is exact): uniform, distinct,
		# no redraw loop, constant draw count.
		var second := engine.rng.randi_range(0, pool.size() - 2)
		if pool[second] == _leader_tags[0]:
			second += 1
		_leader_tags.append(pool[second])
	_trait_stub = engine.rng.randi_range(0, _trait_labels().size() - 1)
	if draw_regime:
		_regime = _regimes[engine.rng.randi_range(0, _regimes.size() - 1)]
	status = STATUS_RUNNING
	run_index += 1
	outcome = OUTCOME_NONE
	last_score = 0
	start_tick = engine.tick_count
	end_tick = 0
	# The economy-quirk handoff (T-SIM-02's documented seam): production is
	# constructed before the regime exists, so the quirk is (re)applied the
	# moment the regime is known — synchronously at the same drain.
	var production := engine.get_system(&"production")
	if production != null and production.has_method("set_regime"):
		production.set_regime(_regime)


## Closes the running run: banks the score into RunMeta (win OR loss),
## appends the chronicle entry, emits the outcome event. Returns the score.
##
## Army power: `army_override >= 0` uses it (the assault outcome contract,
## T-SIM-06); -1 reads the units system's live army_power(). The roster
## snapshot rides along into the chronicle entry.
##
## Score (thin stub, T-SIM-08 owns the real curve):
##   duration_hours + army_power + WIN_BONUS (victory only)
func _end_run(engine: SimEngine, p_outcome: int, army_override: int) -> int:
	var army_power := maxi(0, army_override)
	var roster: Dictionary = {}
	var units := engine.get_system(&"units")
	if units != null:
		if units.has_method("army_roster"):
			roster = units.army_roster()
		if army_override < 0 and units.has_method("army_power"):
			army_power = maxi(0, units.army_power())
	var duration := engine.tick_count - start_tick
	var score := duration / SimEngine.TICKS_PER_SIM_HOUR + army_power
	if p_outcome == OUTCOME_VICTORY:
		score += WIN_BONUS
	status = STATUS_ENDED
	outcome = p_outcome
	last_score = score
	end_tick = engine.tick_count
	meta.legacy_points += score
	meta.runs_recorded += 1
	meta.chronicle.append(_chronicle_entry(roster, army_power, duration, score))
	match p_outcome:
		OUTCOME_VICTORY:
			engine.events.record(engine.tick_count, &"run_won", regime_id(), score, run_index)
		OUTCOME_DEFEAT:
			engine.events.record(engine.tick_count, &"run_lost", regime_id(), score, run_index)
		_:
			engine.events.record(engine.tick_count, &"run_aborted", regime_id(), score, run_index)
	return score


## JSON-safe append-only record (docs/sim-engine.md §12 schema). The "run"
## number is the META-monotonic counter (survives engine re-inits); "army"
## is the terminal-roster snapshot for the chronicle screen (T-UI-08).
func _chronicle_entry(roster: Dictionary, army_power: int, duration: int, score: int) -> Dictionary:
	var army := {}
	for def_id in roster.keys():
		army[String(def_id)] = int(roster[def_id])
	var tags: Array[String] = []
	for tag in _leader_tags:
		tags.append(String(tag))
	return {
		"run": meta.runs_recorded,
		"leader": leader_name(),
		"tags": tags,
		"trait": leader_trait_label(),
		"regime": String(regime_id()),
		"outcome": _outcome_name(outcome),
		"duration_ticks": duration,
		"army_power": army_power,
		"army": army,
		"score": score,
	}


func _outcome_name(p_outcome: int) -> String:
	match p_outcome:
		OUTCOME_VICTORY:
			return "victory"
		OUTCOME_DEFEAT:
			return "defeat"
		_:
			return "aborted"


func _content_ready() -> bool:
	if _regimes.is_empty() or _identity == null:
		return false
	return not _identity.leader_first_names.is_empty() \
		and not _identity.leader_epithets.is_empty() \
		and not _identity.personality_tags.is_empty()


func _deny(engine: SimEngine, kind: StringName, reason: int) -> void:
	engine.events.record(engine.tick_count, &"run_denied", kind, reason)


# --- Determinism oracle + save hooks (fully overridden, never `{}`) --------
#
# Run-scoped state ONLY. The meta bank + chronicle are deliberately absent:
# they live in the meta save domain (RunMeta.to_dict) and must not be
# forkable from a run save, nor perturb run determinism (two engines with
# the same seed hash identically regardless of carried-over meta).


func state_hash() -> int:
	var hash_value := 0x811C9DC5
	hash_value = _mix(hash_value, status)
	hash_value = _mix(hash_value, run_index)
	hash_value = _mix(hash_value, outcome)
	hash_value = _mix(hash_value, last_score)
	hash_value = _mix(hash_value, start_tick)
	hash_value = _mix(hash_value, end_tick)
	hash_value = _mix(hash_value, _trait_stub)
	hash_value = _mix(hash_value, _stipend_run)
	hash_value = _mix(hash_value, _leader_first.hash())
	hash_value = _mix(hash_value, _leader_epithet.hash())
	hash_value = _mix(hash_value, String(regime_id()).hash())
	for tag in _leader_tags:
		hash_value = _mix(hash_value, String(tag).hash())
	return hash_value


func to_dict() -> Dictionary:
	var tags: Array[String] = []
	for tag in _leader_tags:
		tags.append(String(tag))
	return {
		"status": status,
		"run_index": run_index,
		"leader_first": _leader_first,
		"leader_epithet": _leader_epithet,
		"leader_tags": tags,
		"trait_stub": _trait_stub,
		"regime_id": String(regime_id()),
		"start_tick": start_tick,
		"end_tick": end_tick,
		"outcome": outcome,
		"last_score": last_score,
		"stipend_run": _stipend_run,
	}


func from_dict(state: Dictionary) -> void:
	status = int(state.get("status", STATUS_UNSTARTED))
	run_index = int(state.get("run_index", 0))
	_leader_first = String(state.get("leader_first", ""))
	_leader_epithet = String(state.get("leader_epithet", ""))
	_leader_tags = []
	for tag in state.get("leader_tags", []):
		_leader_tags.append(StringName(tag))
	_trait_stub = int(state.get("trait_stub", 0))
	var saved_id := StringName(String(state.get("regime_id", "")))
	_regime = null
	for regime in _regimes:
		if regime.id == saved_id:
			_regime = regime
			break
	if _regime == null and saved_id != &"":
		push_warning("run: saved regime '%s' not in pack — running regime-less" % saved_id)
	start_tick = int(state.get("start_tick", 0))
	end_tick = int(state.get("end_tick", 0))
	outcome = int(state.get("outcome", OUTCOME_NONE))
	last_score = int(state.get("last_score", 0))
	# The stipend PAID flag is run state (the amounts themselves are
	# boot-injected content, like every def): without it, a restore would
	# allow a second grant of the stipend and silently double the boot pool.
	_stipend_run = int(state.get("stipend_run", 0))


## FNV-flavored 32-bit-safe mix (same shape as SimEngine._mix —
## docs/sim-engine.md §2: no signed overflow, no platform-sensitive ops).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
