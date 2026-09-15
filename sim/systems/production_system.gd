## Resource production system (T-SIM-02): worker assignment -> building
## production rates -> upgrade multipliers for food/timber/iron.
##
## The first real system on the T-SIM-01 seam: registers on SimEngine via
## `register_system()`, the core never changes. Determinism contract
## (docs/sim-engine.md §2) applies in full:
##   - content floats (rates per hour, cost growth r, milestone/regime
##     multipliers) cross ONE boundary — `SimFixed.milli_from_float` at
##     construction; after that every rate and cost is integer math in
##     milli-units (per-hour) and milli-unit-seconds (accumulators)
##   - no wall clock, no scene tree, no RNG draws (production is exact)
##   - all external writes arrive as commands drained at tick start
##
## Curves (full reference: docs/sim-engine.md §10):
##   - level 0 = not yet built (no slots, no production). Upgrading 0->1
##     CONSTRUCTS the building for exactly base_cost (`building_built`)
##   - upgrade cost to reach level L:
##       base_cost[res] x growth_milli[L] x milestone_milli[L] x cost_quirk
##     where growth_milli compounds r per level and milestone_milli
##     compounds the tunables milestone_multiplier (x2 at levels 10/20 per
##     R4) once per milestone level <= L — single floored integer division
##     at the end, min 1 per resource line
##   - production per worker per sim-hour at level L:
##       base_rate_milli x L x milestone_milli[L] x production_quirk
##   - worker slots at level L: worker_slots_base + L - 1 (producing
##     buildings only; non-producing buildings have 0 slots)
##
## Worker identity is COUNT-level on purpose: T-SIM-03 owns units and feeds
## this system `add_worker`/`remove_worker` commands as recruits promote or
## scatter. The regime economy quirk (production_multiplier /
## building_cost_multiplier, e.g. timber x0.85) is derived from content when
## the regime is known (constructor / set_regime) AND the APPLIED multipliers
## are serialized + hashed state (T-ARCH-03 verifier fix): a save made under
## a quirked regime resumes under the same quirk even though no run_start
## drain re-applies it, and the determinism oracle can see the difference.
class_name ProductionSystem
extends SimSystem

## Denial reason codes shared by the *_denied events (value payload).
## Documented contract for the future UI (T-UI-04) and T-SIM-03/05.
const REASON_UNKNOWN_BUILDING := 1
const REASON_NOT_BUILT := 2
const REASON_MAX_LEVEL := 3
const REASON_UNAFFORDABLE := 4
const REASON_NO_IDLE_WORKERS := 5
const REASON_NO_FREE_SLOTS := 6
const REASON_NOT_ENOUGH_ASSIGNED := 7
const REASON_INVALID_COUNT := 8

## Workers available for assignment (idle pool). Assigned workers are
## counted per building state; total = idle + sum(assigned).
var workers_idle := 0

var _states: Array[BuildingState] = []
var _by_id: Dictionary = {}  # StringName -> BuildingState
var _prod_quirk_all_milli := SimFixed.MILLI
var _prod_quirk_milli: Dictionary = {}  # StringName resource -> int milli
var _cost_quirk_all_milli := SimFixed.MILLI
var _cost_quirk_milli: Dictionary = {}  # StringName resource -> int milli


## Per-building mutable state. Everything derived from content (def,
## base_rate_milli, curve tables) is re-created at construction and never
## serialized — saves carry the four ints only.
class BuildingState extends RefCounted:
	var def: BuildingDef
	var level := 0  # 0 = not yet built
	var assigned := 0
	var accum := 0  # SimFixed milli-units x seconds remainder
	var base_rate_milli := 0  # milli_from_float(base_production_per_worker_hour), once
	var growth_table: Array[int] = []  # index by target level, [0] unused
	var milestone_table: Array[int] = []  # index by level, [0] unused


func _init(
	p_buildings: Array[BuildingDef],
	p_tunables: EconomyTunables,
	p_regime: RegimeDef = null
) -> void:
	var tunables := p_tunables if p_tunables != null else EconomyTunables.new()
	var milestone_base := SimFixed.milli_from_float(tunables.milestone_multiplier)
	for def in p_buildings:
		if def == null:
			continue
		if _by_id.has(def.id):
			push_warning("production: duplicate building id '%s' — keeping first" % def.id)
			continue
		var state := BuildingState.new()
		state.def = def
		state.base_rate_milli = SimFixed.milli_from_float(def.base_production_per_worker_hour)
		state.growth_table = _build_growth_table(def)
		state.milestone_table = _build_milestone_table(def, milestone_base)
		_states.append(state)
		_by_id[def.id] = state
	_apply_regime(p_regime)


func system_name() -> StringName:
	return &"production"


# --- Read API (UI queries; pure, deterministic, no state writes) ----------


func idle_workers() -> int:
	return workers_idle


## All building ids in pack order (M1 finding F5 gap, closed for T-SIM-05's
## heat profile: a system or UI that knows only the engine can now discover
## what exists instead of mirroring content ids host-side).
func building_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for state in _states:
		ids.append(state.def.id)
	return ids


func building_level(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	return 0 if state == null else state.level


func assigned_workers(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	return 0 if state == null else state.assigned


## Worker slots at the building's CURRENT level (0 when unbuilt or
## non-producing — the T-SIM-02 slot curve: base + level - 1).
func worker_slots(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	if state == null or state.level < 1 or state.def.resource_produced == &"":
		return 0
	return state.def.worker_slots_base + state.level - 1


## Milli-units of resource_produced per worker per sim-hour at the current
## level (0 when unbuilt/non-producing). Integer; display code divides by
## SimFixed.MILLI at its own boundary.
func production_rate_milli_per_worker(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	if state == null or state.level < 1 or state.def.resource_produced == &"":
		return 0
	return _rate_milli_per_worker(state)


## Total milli-units/hour at current assignment (per-worker rate x count).
func production_rate_milli(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	if state == null:
		return 0
	return _rate_milli_per_worker(state) * state.assigned


## Milli-unit-seconds carried toward the next whole unit (the SimFixed
## remainder: bounded in [0, UNIT_ACCUM), never lost — the UI's
## progress-to-next-pip meter).
func accumulated_milli_unit_seconds(id: StringName) -> int:
	var state := _by_id.get(id) as BuildingState
	return 0 if state == null else state.accum


## Cost to reach the NEXT level, per resource. Empty dictionary when the
## building is unknown or already at max_level. Level 0 -> 1 costs exactly
## base_cost (construction).
func upgrade_cost(id: StringName) -> Dictionary[StringName, int]:
	var cost: Dictionary[StringName, int] = {}
	var state := _by_id.get(id) as BuildingState
	if state == null or state.level >= state.def.max_level:
		return cost
	var target := state.level + 1
	var growth: int = state.growth_table[target]
	var milestone: int = state.milestone_table[target]
	for resource in state.def.base_cost:
		var quirk: int = _cost_quirk_milli.get(resource, _cost_quirk_all_milli)
		var line: int = int(state.def.base_cost[resource]) * growth * milestone * quirk / 1_000_000_000
		cost[resource] = maxi(1, line)
	return cost


# --- Tick -----------------------------------------------------------------


func on_tick(engine: SimEngine) -> void:
	# Allocation-free steady state: int math + in-place accumulator + the
	# engine's int resource pool. Remainders carry toward the next unit.
	for state in _states:
		if state.level < 1 or state.assigned < 1:
			continue
		state.accum += _rate_milli_per_worker(state) * state.assigned * SimEngine.TICK_SECONDS
		var units := state.accum / SimFixed.UNIT_ACCUM
		if units > 0:
			state.accum -= units * SimFixed.UNIT_ACCUM
			engine.add_resource(state.def.resource_produced, units)


# --- Commands (the only external write path; drained at tick start) -------


func on_command(engine: SimEngine, command: SimCommand) -> bool:
	match command.kind:
		&"add_worker":
			_handle_add_worker(engine, command)
		&"remove_worker":
			_handle_remove_worker(engine, command)
		&"assign_worker":
			_handle_assign_worker(engine, command)
		&"unassign_worker":
			_handle_unassign_worker(engine, command)
		&"upgrade_building":
			_handle_upgrade_building(engine, command)
		_:
			return false
	return true


func _handle_add_worker(engine: SimEngine, command: SimCommand) -> void:
	if command.value < 1:
		_deny_pool(engine, command, REASON_INVALID_COUNT)
		return
	workers_idle += command.value
	engine.events.record(engine.tick_count, &"worker_added", &"production", workers_idle)


func _handle_remove_worker(engine: SimEngine, command: SimCommand) -> void:
	if command.value < 1:
		_deny_pool(engine, command, REASON_INVALID_COUNT)
		return
	if command.value > workers_idle:
		_deny_pool(engine, command, REASON_NO_IDLE_WORKERS)
		return
	workers_idle -= command.value
	engine.events.record(engine.tick_count, &"worker_removed", &"production", workers_idle)


func _handle_assign_worker(engine: SimEngine, command: SimCommand) -> void:
	var state := _by_id.get(command.subject) as BuildingState
	if state == null:
		_deny_assignment(engine, command, REASON_UNKNOWN_BUILDING)
		return
	if state.level < 1:
		_deny_assignment(engine, command, REASON_NOT_BUILT)
		return
	if command.value < 1:
		_deny_assignment(engine, command, REASON_INVALID_COUNT)
		return
	if command.value > workers_idle:
		_deny_assignment(engine, command, REASON_NO_IDLE_WORKERS)
		return
	if state.assigned + command.value > worker_slots(state.def.id):
		_deny_assignment(engine, command, REASON_NO_FREE_SLOTS)
		return
	workers_idle -= command.value
	state.assigned += command.value
	engine.events.record(
		engine.tick_count, &"worker_assigned", state.def.id, state.assigned, workers_idle
	)


func _handle_unassign_worker(engine: SimEngine, command: SimCommand) -> void:
	var state := _by_id.get(command.subject) as BuildingState
	if state == null:
		_deny_assignment(engine, command, REASON_UNKNOWN_BUILDING)
		return
	if command.value < 1:
		_deny_assignment(engine, command, REASON_INVALID_COUNT)
		return
	if command.value > state.assigned:
		_deny_assignment(engine, command, REASON_NOT_ENOUGH_ASSIGNED)
		return
	state.assigned -= command.value
	workers_idle += command.value
	engine.events.record(
		engine.tick_count, &"worker_unassigned", state.def.id, state.assigned, workers_idle
	)


func _handle_upgrade_building(engine: SimEngine, command: SimCommand) -> void:
	var state := _by_id.get(command.subject) as BuildingState
	if state == null:
		engine.events.record(engine.tick_count, &"upgrade_denied", command.subject, REASON_UNKNOWN_BUILDING)
		return
	if state.level >= state.def.max_level:
		engine.events.record(engine.tick_count, &"upgrade_denied", state.def.id, REASON_MAX_LEVEL)
		return
	var cost := upgrade_cost(state.def.id)
	for resource in cost:
		if engine.get_resource(resource) < cost[resource]:
			engine.events.record(engine.tick_count, &"upgrade_denied", state.def.id, REASON_UNAFFORDABLE)
			return
	for resource in cost:
		engine.add_resource(resource, -cost[resource])
	state.level += 1
	if state.level == 1:
		engine.events.record(engine.tick_count, &"building_built", state.def.id, 1)
	else:
		engine.events.record(engine.tick_count, &"building_upgraded", state.def.id, state.level)
	if state.def.milestone_levels.has(state.level):
		# Production milestone (R4 x2 at 10/20): the discrete spike on the
		# rate curve — value2 carries the multiplier in milli for the UI.
		engine.events.record(
			engine.tick_count,
			&"building_milestone",
			state.def.id,
			state.level,
			state.milestone_table[state.level]
		)


func _deny_pool(engine: SimEngine, command: SimCommand, reason: int) -> void:
	engine.events.record(engine.tick_count, &"worker_pool_denied", &"production", reason, command.value)


func _deny_assignment(engine: SimEngine, command: SimCommand, reason: int) -> void:
	engine.events.record(engine.tick_count, &"assignment_denied", command.subject, reason, command.value)


# --- Determinism oracle + save hooks (fully overridden, never `{}`) --------


func state_hash() -> int:
	var hash_value := 0x811C9DC5
	hash_value = _mix(hash_value, workers_idle)
	# The APPLIED economy config is state, not boot context: a hash blind to
	# it called an engine that had lost its regime quirk on restore "identical"
	# and diverged on the next tick (the T-ARCH-03 verifier FAIL). Mix the
	# effective multipliers so a serialization gap of this class can never
	# hide from the oracle again.
	hash_value = _mix(hash_value, _prod_quirk_all_milli)
	hash_value = _mix(hash_value, _cost_quirk_all_milli)
	for resource in _prod_quirk_milli:
		hash_value = _mix(hash_value, String(resource).hash())
		hash_value = _mix(hash_value, int(_prod_quirk_milli[resource]))
	for resource in _cost_quirk_milli:
		hash_value = _mix(hash_value, String(resource).hash())
		hash_value = _mix(hash_value, int(_cost_quirk_milli[resource]))
	for state in _states:
		hash_value = _mix(hash_value, String(state.def.id).hash())
		hash_value = _mix(hash_value, state.level)
		hash_value = _mix(hash_value, state.assigned)
		hash_value = _mix(hash_value, state.accum)
	return hash_value


func to_dict() -> Dictionary:
	var buildings: Array[Dictionary] = []
	for state in _states:
		buildings.append({
			"id": String(state.def.id),
			"level": state.level,
			"assigned": state.assigned,
			"accum": state.accum,
		})
	var prod_milli := {}
	for resource in _prod_quirk_milli:
		prod_milli[String(resource)] = int(_prod_quirk_milli[resource])
	var cost_milli := {}
	for resource in _cost_quirk_milli:
		cost_milli[String(resource)] = int(_cost_quirk_milli[resource])
	return {
		"workers_idle": workers_idle,
		"buildings": buildings,
		# Applied regime economy multipliers (T-ARCH-03 verifier fix): a
		# restore must resume under the quirk the save was made under — the
		# quirks are run state, not boot-time reconstruction (from_dict runs
		# with no run_start drain to re-apply them).
		"regime_quirks": {
			"prod_all_milli": _prod_quirk_all_milli,
			"prod_milli": prod_milli,
			"cost_all_milli": _cost_quirk_all_milli,
			"cost_milli": cost_milli,
		},
	}


func from_dict(state: Dictionary) -> void:
	workers_idle = int(state.get("workers_idle", 0))
	if state.has("regime_quirks"):
		# Restore the exact applied multipliers (serialized since the
		# T-ARCH-03 verifier fix). A dict WITHOUT the key is a pre-fix save:
		# keep the constructed quirks (the old boot-reconstruction contract).
		var quirks: Dictionary = state["regime_quirks"]
		_prod_quirk_all_milli = int(quirks.get("prod_all_milli", SimFixed.MILLI))
		_prod_quirk_milli = _quirk_milli_from_json(quirks.get("prod_milli", {}))
		_cost_quirk_all_milli = int(quirks.get("cost_all_milli", SimFixed.MILLI))
		_cost_quirk_milli = _quirk_milli_from_json(quirks.get("cost_milli", {}))
	for entry in state.get("buildings", []):
		var restored := _by_id.get(StringName(entry["id"])) as BuildingState
		if restored == null:
			push_warning("production: saved building '%s' not in pack — skipped" % entry["id"])
			continue
		restored.level = int(entry.get("level", 0))
		restored.assigned = int(entry.get("assigned", 0))
		restored.accum = int(entry.get("accum", 0))


## JSON-safe String-keyed quirk dict -> the system's StringName-keyed form
## (insertion order preserved by both the writer and the parser).
static func _quirk_milli_from_json(encoded: Dictionary) -> Dictionary:
	var decoded := {}
	for resource in encoded:
		decoded[StringName(String(resource))] = int(encoded[resource])
	return decoded


# --- Curve construction (integer milli-space; the single float boundary) ---


## growth_milli[L]: compounding r per level, rescaled to milli each step so
## values stay small and every op is an exact int (r_milli = r x 1000 once).
static func _build_growth_table(def: BuildingDef) -> Array[int]:
	var table: Array[int] = [0]  # index 0 unused (level 0 = unbuilt)
	var growth_milli := SimFixed.MILLI
	var r_milli := SimFixed.milli_from_float(def.cost_growth)
	for level in range(1, def.max_level + 1):
		if level > 1:
			growth_milli = growth_milli * r_milli / SimFixed.MILLI
		table.append(growth_milli)
	return table


## milestone_milli[L]: the milestone multiplier compounded once per
## milestone level <= L (x2 at 10/20 => 1000, 2000, 4000...).
static func _build_milestone_table(def: BuildingDef, milestone_base_milli: int) -> Array[int]:
	var table: Array[int] = [0]
	var multiplier_milli := SimFixed.MILLI
	var fired := 0
	for level in range(1, def.max_level + 1):
		while fired < def.milestone_levels.size() and def.milestone_levels[fired] <= level:
			fired += 1
			multiplier_milli = multiplier_milli * milestone_base_milli / SimFixed.MILLI
		table.append(multiplier_milli)
	return table


func _apply_regime(regime: RegimeDef) -> void:
	_prod_quirk_all_milli = SimFixed.MILLI
	_prod_quirk_milli.clear()
	_cost_quirk_all_milli = SimFixed.MILLI
	_cost_quirk_milli.clear()
	if regime == null or regime.economy_quirk == null:
		return
	var quirk := regime.economy_quirk
	var value_milli := SimFixed.milli_from_float(quirk.value)
	match quirk.kind:
		&"production_multiplier":
			if quirk.target == &"all":
				_prod_quirk_all_milli = value_milli
			else:
				_prod_quirk_milli[quirk.target] = value_milli
		&"building_cost_multiplier":
			if quirk.target == &"all":
				_cost_quirk_all_milli = value_milli
			else:
				_cost_quirk_milli[quirk.target] = value_milli


## Public regime seam (T-SIM-04, docs/sim-engine.md §12): (re)apply a
## regime's economy quirk mid-engine-lifetime — the exact code path the
## constructor argument takes. RunLifecycleSystem calls this synchronously
## at the run_start/run_restart command drains, because production is
## constructed before the run's regime has been drawn.
func set_regime(p_regime: RegimeDef) -> void:
	_apply_regime(p_regime)


## Run-reset seam (T-SIM-04 reset contract, docs/sim-engine.md §12): every
## run-scoped field back to constructed-boot values — buildings unbuilt, no
## workers, no carried remainders — then apply the new run's regime quirk.
## Called synchronously by the run system at the run_restart drain.
func reset_run(p_regime: RegimeDef = null) -> void:
	workers_idle = 0
	for state in _states:
		state.level = 0
		state.assigned = 0
		state.accum = 0
	_apply_regime(p_regime)


## Per-worker milli-units/hour at the state's current level. Called on the
## tick path: pure int math, no allocation, no float anywhere.
func _rate_milli_per_worker(state: BuildingState) -> int:
	if state.level < 1 or state.def.resource_produced == &"":
		return 0
	var rate := state.base_rate_milli * state.level
	rate = rate * state.milestone_table[state.level] / SimFixed.MILLI
	return rate * int(_prod_quirk_milli.get(state.def.resource_produced, _prod_quirk_all_milli)) / SimFixed.MILLI


## FNV-flavored 32-bit-safe mix (same shape as SimEngine._mix —
## docs/sim-engine.md §2: no signed overflow, no platform-sensitive ops).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
