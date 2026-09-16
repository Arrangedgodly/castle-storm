## Unit lifecycle system (T-SIM-03): recruit arrival, role assignment,
## training timers, gear requirements, promotion to the knight and archer
## branches.
##
## Second real system on the T-SIM-01 seam after production (§10): it
## registers via `register_system()`, the core never changes. Full
## contract in docs/sim-engine.md §11. Determinism rules apply in full:
##   - content floats (training hours, arrival interval/jitter, the opening
##     rush ramp) cross ONE boundary — `SimFixed.milli_from_float` at
##     construction; after that every timer is integer math in MILLI-TICKS
##   - the ONLY RNG draws are the arrival-interval jitters, drawn inside
##     `on_tick` (the sanctioned site) — identical run seeds produce
##     identical arrival sequences, and `rng.state` is hashed by the engine.
##     The opening rush (T-SIM-08) is metronome: its intervals draw NOTHING,
##     so the eager cadence is exact and the first-recruit time has zero
##     variance
##   - all external writes arrive as commands drained at tick start; the
##     one system-to-system handoff (recruit -> worker) flows through the
##     same command queue: worker promotion submits `add_worker` to
##     ProductionSystem, which drains at the next tick's start
##
## Lifecycle (per town-hall + UnitDef data):
##
##   recruit_arrived (RNG cadence)          stable: offers wait at the gate
##     -> recruit_accept                    peasant joins (base unit)
##     -> assign_role worker | militia      starts that def's training timer
##          worker  (0.5h example)  -> unit_promoted + add_worker to pool
##          militia (2h)            -> unit_promoted (militia)
##     -> start_training trainee            militia -> trainee (4h)
##     -> start_training knight | archer    trainee -> branch (12h / 6h)
##          training_complete (held)        stable: trainee awaiting gear
##     -> equip_gear (per required slot)    pays GearDef recipe, any tier
##     -> promote                           knight / archer (army roster)
##
## Promotion into a def with `required_gear_slots` REQUIRES training
## complete + every required slot equipped (any tier — top tier not
## required; tiers are recorded per unit for T-SIM-06 odds). An
## unequipped trainee awaiting gear is a stable state, not an error.
## Promotion into gear-free defs (worker, militia, trainee) completes
## automatically when the timer runs out.
class_name UnitLifecycleSystem
extends SimSystem

## Denial reason codes shared by the `lifecycle_denied` events (value
## payload). Documented contract for the future UI (T-UI-04) and T-SIM-05.
const REASON_UNKNOWN_UNIT := 1
const REASON_UNKNOWN_RECRUIT := 2
const REASON_UNKNOWN_GEAR := 3
const REASON_UNKNOWN_TARGET := 4
const REASON_INVALID_TARGET := 5
const REASON_ALREADY_TRAINING := 6
const REASON_AWAITING_PROMOTION := 7
const REASON_SLOT_NOT_NEEDED := 8
const REASON_SLOT_OCCUPIED := 9
const REASON_UNAFFORDABLE := 10
const REASON_NOT_AWAITING_PROMOTION := 11
const REASON_TRAINING_INCOMPLETE := 12
const REASON_GEAR_INCOMPLETE := 13

## Total arrivals since boot (offers created, accepted or not). Serialized
## and hashed — the marathon's arrival-band assertion reads it.
var arrivals_total := 0

## Next unit identity handed out (uids are engine-lifetime unique and
## stable from gate arrival through knighthood — the chronicle's key).
var next_uid := 1

var _base_unit: StringName = &""  # def that arrives (peasant)
var _interval_milli := 0  # arrival interval in milli-ticks
var _jitter_milli := 0  # +/- jitter in milli-ticks (0 = no RNG draws)
var _early_intervals_milli: Array[int] = []  # opening rush (T-SIM-08); empty = none
var _gate_capacity := 0  # max concurrent offers; 0 = uncapped (T-SIM-08)
var _arrival_countdown_milli := -1  # -1 = not yet scheduled (first tick schedules)
var _units: Array[UnitState] = []
var _by_uid: Dictionary = {}  # int uid -> UnitState
var _offers: Array[int] = []  # recruit uids waiting at the gate
var _training: Array[UnitState] = []  # units with a running training timer
var _counts: Dictionary = {}  # StringName def id -> live unit count
var _units_by_id: Dictionary = {}  # StringName -> UnitDef
var _gear_by_id: Dictionary = {}  # StringName -> GearDef
var _duration_milli: Dictionary = {}  # StringName def id -> training duration in milli-ticks
var _quarter_milli: Dictionary = {}  # StringName def id -> Array[int] 25/50/75% thresholds
var _army_defs: Dictionary = {}  # StringName def id -> true for army-roster defs


## One unit's mutable state. Everything derived from content (def tables,
## gear defs) is re-created at construction and never serialized — saves
## carry ids only (content-schema §7).
class UnitState extends RefCounted:
	var uid: int
	var def_id: StringName = &""
	var target: StringName = &""  # training target def; "" while resting
	var progress_milli := 0  # milli-ticks elapsed toward the target's duration
	var awaiting_promotion := false  # training complete, gear-gated promote pending
	var gear: Dictionary = {}  # StringName slot -> StringName gear id


func _init(
	p_units: Array[UnitDef],
	p_gear: Array[GearDef],
	p_tunables: EconomyTunables = null,
	p_base_unit: StringName = &""
) -> void:
	var tunables := p_tunables if p_tunables != null else EconomyTunables.new()
	_interval_milli = SimFixed.milli_from_float(tunables.recruit_arrival_interval_hours) * SimEngine.TICKS_PER_SIM_HOUR
	_jitter_milli = SimFixed.milli_from_float(tunables.recruit_arrival_jitter_hours) * SimEngine.TICKS_PER_SIM_HOUR
	_gate_capacity = maxi(0, tunables.recruit_gate_capacity)
	# The opening rush (T-SIM-08, M1 finding F2): the run's first N arrivals
	# use a metronome cadence ramping up to the base interval. The ramp is
	# precomputed at the construction float boundary (pow HERE, integers
	# after); each entry is capped at the normal interval, and the table is
	# keyed by the RUN's arrival counter — reset_run re-opens the rush.
	var early_count := maxi(0, tunables.recruit_arrival_early_count)
	if early_count > 0:
		var first_milli := SimFixed.milli_from_float(tunables.recruit_arrival_early_interval_hours) * SimEngine.TICKS_PER_SIM_HOUR
		for i in early_count:
			var interval := mini(_interval_milli, int(first_milli * pow(tunables.recruit_arrival_early_step, i)))
			_early_intervals_milli.append(maxi(SimFixed.MILLI, interval))
	var incoming: Dictionary = {}  # def ids reachable via any promotion path
	for def in p_units:
		if def == null:
			continue
		if _units_by_id.has(def.id):
			push_warning("units: duplicate unit id '%s' — keeping first" % def.id)
			continue
		_units_by_id[def.id] = def
		for path in def.promotion_paths:
			incoming[path] = true
	for def in p_gear:
		if def == null:
			continue
		if _gear_by_id.has(def.id):
			push_warning("units: duplicate gear id '%s' — keeping first" % def.id)
			continue
		_gear_by_id[def.id] = def
	for id in _units_by_id.keys():
		var def := _units_by_id[id] as UnitDef
		_duration_milli[id] = SimFixed.milli_from_float(def.training_time_hours) * SimEngine.TICKS_PER_SIM_HOUR
		var quarters: Array[int] = [
			int(_duration_milli[id]) / 4,
			int(_duration_milli[id]) / 2,
			int(_duration_milli[id]) * 3 / 4,
		]
		_quarter_milli[id] = quarters
		# Army roster rule (data-driven): terminal combat units — combat
		# power contributes AND no further promotion path. Knight/archer
		# qualify; militia/trainee still have paths; workers cannot fight.
		if def.combat_power > 0 and def.promotion_paths.is_empty():
			_army_defs[id] = true
	_base_unit = p_base_unit
	if _base_unit == &"":
		# Auto-detect: the root def no other def promotes into (the
		# peasant). Ambiguous packs must pass p_base_unit explicitly.
		var roots: Array[StringName] = []
		for id in _units_by_id.keys():
			if not incoming.has(id):
				roots.append(id)
		roots.sort()
		if roots.size() == 1:
			_base_unit = roots[0]
		else:
			push_warning(
				"units: %d candidate base units (%s) — pass p_base_unit; using '%s'"
				% [roots.size(), ", ".join(PackedStringArray(roots.map(func(id): return String(id)))), String(roots[0]) if not roots.is_empty() else ""]
			)
			if not roots.is_empty():
				_base_unit = roots[0]


func system_name() -> StringName:
	return &"units"


# --- Read API (UI queries; pure, deterministic, no state writes) ----------


## Recruit offers currently waiting at the gate (never expire — a full gate
## is a stable state; tolerance pressure is T-SIM-05's call).
func pending_offers() -> int:
	return _offers.size()


## The gate's concurrent-offer capacity (T-SIM-08; 0 = uncapped). While
## `pending_offers() >= gate_capacity()` the arrival countdown is paused —
## the UI's "the gate is full; the road home has gone quiet" state.
func gate_capacity() -> int:
	return _gate_capacity


## Offer uids in arrival order (for accept buttons / marathon scripting).
func offer_ids() -> Array[int]:
	return _offers.duplicate()


## All tracked unit uids in arrival order (the roster list; workers stay
## tracked so identity mapping lives here, counts live in ProductionSystem).
func unit_ids() -> Array[int]:
	var ids: Array[int] = []
	for unit in _units:
		ids.append(unit.uid)
	return ids


## Live units currently of def_id (peasants, workers, knights, ...).
func unit_count(def_id: StringName) -> int:
	return int(_counts.get(def_id, 0))


## All tracked units (accepted recruits; workers stay tracked so identity
## mapping lives here, counts live in ProductionSystem).
func total_units() -> int:
	return _units.size()


## Current def id of a unit (&"" when unknown).
func unit_def(uid: int) -> StringName:
	var unit := _by_uid.get(uid) as UnitState
	return &"" if unit == null else unit.def_id


## Training target def id (&"" while resting / after promotion).
func training_target(uid: int) -> StringName:
	var unit := _by_uid.get(uid) as UnitState
	return &"" if unit == null else unit.target


## Training progress in milli-ticks (0 when not training).
func training_progress_milli(uid: int) -> int:
	var unit := _by_uid.get(uid) as UnitState
	return 0 if unit == null else unit.progress_milli


## Training duration in milli-ticks for a def id (0 when unknown).
func training_duration_milli(def_id: StringName) -> int:
	return int(_duration_milli.get(def_id, 0))


## True while the unit finished training and is held awaiting gear + the
## promote command (the stable "waiting for gear" state).
func is_awaiting_promotion(uid: int) -> bool:
	var unit := _by_uid.get(uid) as UnitState
	return unit != null and unit.awaiting_promotion


## Copy of the unit's equipped gear (slot id -> gear id). Per-unit gear
## data in state; tier/combat resolve from content at read time.
func unit_gear(uid: int) -> Dictionary:
	var unit := _by_uid.get(uid) as UnitState
	return {} if unit == null else unit.gear.duplicate()


## Equipped tier in a slot (0 = empty). T-SIM-06's odds input.
func gear_tier(uid: int, slot: StringName) -> int:
	var unit := _by_uid.get(uid) as UnitState
	if unit == null:
		return 0
	var gear_id: StringName = unit.gear.get(slot, &"")
	var gear := _gear_by_id.get(gear_id) as GearDef
	return 0 if gear == null else gear.tier


## Required slots of the unit's training target not yet equipped.
func missing_gear_slots(uid: int) -> Array[StringName]:
	var missing: Array[StringName] = []
	var unit := _by_uid.get(uid) as UnitState
	if unit == null or unit.target == &"":
		return missing
	var target := _units_by_id.get(unit.target) as UnitDef
	if target == null:
		return missing
	for slot in target.required_gear_slots:
		if unit.gear.get(slot, &"") == &"":
			missing.append(slot)
	return missing


## Uids of units of def_id resting (no running training, no pending
## promotion — ready for assign_role / start_training), in arrival order.
func idle_units(def_id: StringName) -> Array[int]:
	var ids: Array[int] = []
	for unit in _units:
		if unit.def_id == def_id and unit.target == &"" and not unit.awaiting_promotion:
			ids.append(unit.uid)
	return ids


## Uids of units held awaiting the promote command, in arrival order.
func awaiting_promotion_ids() -> Array[int]:
	var ids: Array[int] = []
	for unit in _units:
		if unit.awaiting_promotion:
			ids.append(unit.uid)
	return ids


## Uids with a RUNNING training timer (the suspicion system's T-SIM-05 seam:
## set-diffing this list between ticks detects training completions exactly —
## a uid that leaves the list completed its timer that tick, whatever the
## pack's promotion graph looks like). Roster order.
func training_uids() -> Array[int]:
	var ids: Array[int] = []
	for unit in _training:
		ids.append(unit.uid)
	return ids


## The def id that arrives at the gate (peasant; auto-detected at
## construction). Read seam for systems/UIs that must not hardcode content
## ids — T-SIM-05's scatter pool (idle base units) drives off it.
func base_unit_id() -> StringName:
	return _base_unit


## Army roster: count per army-eligible def id (terminal combat units).
func army_roster() -> Dictionary[StringName, int]:
	var roster: Dictionary[StringName, int] = {}
	for id in _army_defs.keys():
		var count := int(_counts.get(id, 0))
		if count > 0:
			roster[id] = count
	return roster


## Army score: sum over army units of def combat power + equipped gear
## combat power (gear tiers raise odds — the T-SIM-06 seam).
func army_power() -> int:
	var power := 0
	for unit in _units:
		if not _army_defs.has(unit.def_id):
			continue
		var def := _units_by_id[unit.def_id] as UnitDef
		power += def.combat_power
		for slot in unit.gear.keys():
			var gear := _gear_by_id.get(unit.gear[slot]) as GearDef
			if gear != null:
				power += gear.combat_power
	return power


## Per-unit combat contribution breakdown (the T-SIM-06 odds-screen seam):
## roster order, one {uid, def, def_power, gear_power} per ARMY unit. Pure
## read; the odds screen sums these for its "where does my power come from"
## panel and the resolver re-reads them to narrate attrition. gear_power is
## the sum of the unit's equipped GearDef combat values (tiers included).
func army_contributions() -> Array[Dictionary]:
	var contributions: Array[Dictionary] = []
	for unit in _units:
		if not _army_defs.has(unit.def_id):
			continue
		var def := _units_by_id[unit.def_id] as UnitDef
		var gear_power := 0
		for slot in unit.gear.keys():
			var gear := _gear_by_id.get(unit.gear[slot]) as GearDef
			if gear != null:
				gear_power += gear.combat_power
		contributions.append({
			"uid": unit.uid,
			"def": unit.def_id,
			"def_power": def.combat_power,
			"gear_power": gear_power,
		})
	return contributions


## Army-loss seam (T-SIM-06 failed assault): remove up to `count` ARMY units —
## gear and all (the kit is lost with its wearer) — newest-commissioned first
## (reverse roster order: the vanguard holds, the newest ranks break), never
## touching workers, pipeline, offers or any non-army unit. Returns the removed
## uids in removal order; the caller records the events. Pure roster mutation,
## the same direct-synchronous-call shape as scatter_recruits (T-SIM-05).
func apply_army_losses(count: int) -> Array[int]:
	var removed: Array[int] = []
	if count <= 0:
		return removed
	var index := _units.size() - 1
	while removed.size() < count and index >= 0:
		var unit := _units[index]
		if _army_defs.has(unit.def_id):
			_units.remove_at(index)
			_by_uid.erase(unit.uid)
			_counts[unit.def_id] = int(_counts.get(unit.def_id, 1)) - 1
			removed.append(unit.uid)
		index -= 1
	return removed


## Gear ids occupying a slot, lowest tier first (deterministic order).
func gear_ids_for_slot(slot: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _gear_by_id.keys():
		var gear := _gear_by_id[id] as GearDef
		if gear.slot == slot:
			ids.append(id)
	_ids_sort_by_tier(ids)
	return ids


# --- Tick -----------------------------------------------------------------


func on_tick(engine: SimEngine) -> void:
	# Arrival scheduling: the FIRST tick schedules (draws the interval);
	# every later tick counts down, fires the offer, draws the next
	# interval. While the gate is at capacity (T-SIM-08) the countdown
	# PAUSES — a crowded gate draws no new peasants — and resumes the tick
	# a slot frees (accept / dismiss / scatter); the pause is visible to
	# the UI as pending_offers() == gate capacity (no state, no event
	# spam). The only RNG draws in this system are the jittered NORMAL
	# intervals; the opening rush is metronome.
	if _arrival_countdown_milli < 0:
		_arrival_countdown_milli = _next_interval_milli(engine)
	elif not _gate_full():
		_arrival_countdown_milli -= SimFixed.MILLI
		if _arrival_countdown_milli <= 0:
			_spawn_offer(engine)
			_arrival_countdown_milli = _next_interval_milli(engine)
	# Training timers: one milli-tick per tick, quarter progress events,
	# completion when the target def's duration is reached.
	for i in range(_training.size() - 1, -1, -1):
		var unit := _training[i]
		var before := unit.progress_milli
		unit.progress_milli += SimFixed.MILLI
		var quarters: Array[int] = _quarter_milli[unit.target]
		for q in range(3):
			var threshold: int = quarters[q]
			if before < threshold and unit.progress_milli >= threshold:
				engine.events.record(
					engine.tick_count, &"training_progress", unit.target, unit.uid, (q + 1) * 250
				)
		if unit.progress_milli >= int(_duration_milli[unit.target]):
			_training.remove_at(i)
			_complete_training(engine, unit)


# --- Commands (the only external write path; drained at tick start) -------


func on_command(engine: SimEngine, command: SimCommand) -> bool:
	match command.kind:
		&"recruit_accept":
			_handle_recruit_accept(engine, command)
		&"dismiss_offer":
			_handle_dismiss_offer(engine, command)
		&"assign_role", &"start_training":
			# assign_role is the peasant's branch-choice semantic (worker vs
			# militia); start_training is the same mechanic for every later
			# hop (trainee, knight/archer). One implementation, two verbs.
			_handle_start_training(engine, command)
		&"equip_gear":
			_handle_equip_gear(engine, command)
		&"promote":
			_handle_promote(engine, command)
		_:
			return false
	return true


func _handle_recruit_accept(engine: SimEngine, command: SimCommand) -> void:
	var uid := command.value
	if not _offers.has(uid):
		_deny(engine, command, REASON_UNKNOWN_RECRUIT)
		return
	_offers.erase(uid)
	var unit := UnitState.new()
	unit.uid = uid
	unit.def_id = _base_unit
	_units.append(unit)
	_by_uid[uid] = unit
	_counts[_base_unit] = int(_counts.get(_base_unit, 0)) + 1
	engine.events.record(
		engine.tick_count, &"recruit_accepted", _base_unit, uid, int(_counts[_base_unit])
	)


## Dismiss a pending gate offer (T-SIM-08, the refusal affordance): the
## recruit is sent home — no cost, no suspicion act (turning someone away is
## the QUIET option; that is the point), the gate slot frees (arrivals
## resume if the gate was at capacity). The unit never exists; uid is never
## reused. Unknown uid (never an offer / already dismissed) denied with the
## same reason code as accept.
func _handle_dismiss_offer(engine: SimEngine, command: SimCommand) -> void:
	var uid := command.value
	if not _offers.has(uid):
		_deny(engine, command, REASON_UNKNOWN_RECRUIT)
		return
	_offers.erase(uid)
	engine.events.record(
		engine.tick_count, &"recruit_dismissed", _base_unit, uid, _offers.size()
	)


func _handle_start_training(engine: SimEngine, command: SimCommand) -> void:
	var unit := _by_uid.get(command.value) as UnitState
	if unit == null:
		_deny(engine, command, REASON_UNKNOWN_UNIT)
		return
	var target := _units_by_id.get(command.subject) as UnitDef
	if target == null:
		_deny(engine, command, REASON_UNKNOWN_TARGET)
		return
	var def := _units_by_id[unit.def_id] as UnitDef
	if def == null or not def.promotion_paths.has(target.id):
		_deny(engine, command, REASON_INVALID_TARGET)
		return
	if unit.awaiting_promotion:
		_deny(engine, command, REASON_AWAITING_PROMOTION)
		return
	if unit.target != &"":
		_deny(engine, command, REASON_ALREADY_TRAINING)
		return
	unit.target = target.id
	unit.progress_milli = 0
	var duration := int(_duration_milli[target.id])
	engine.events.record(
		engine.tick_count, &"training_started", target.id, unit.uid, duration
	)
	if duration <= 0:
		# Zero-hour training promotes within the same command drain.
		_complete_training(engine, unit)
	else:
		_training.append(unit)


func _handle_equip_gear(engine: SimEngine, command: SimCommand) -> void:
	var gear := _gear_by_id.get(command.subject) as GearDef
	if gear == null:
		_deny(engine, command, REASON_UNKNOWN_GEAR)
		return
	var unit := _by_uid.get(command.value) as UnitState
	if unit == null:
		_deny(engine, command, REASON_UNKNOWN_UNIT)
		return
	if not _slot_required(unit, gear.slot):
		_deny(engine, command, REASON_SLOT_NOT_NEEDED)
		return
	var equipped_id: StringName = unit.gear.get(gear.slot, &"")
	if equipped_id != &"":
		var equipped := _gear_by_id.get(equipped_id) as GearDef
		if equipped != null and gear.tier <= equipped.tier:
			_deny(engine, command, REASON_SLOT_OCCUPIED)
			return
	for resource in gear.recipe:
		if engine.get_resource(resource) < int(gear.recipe[resource]):
			_deny(engine, command, REASON_UNAFFORDABLE)
			return
	for resource in gear.recipe:
		engine.add_resource(resource, -int(gear.recipe[resource]))
	unit.gear[gear.slot] = gear.id
	engine.events.record(engine.tick_count, &"gear_equipped", gear.id, unit.uid, gear.tier)


func _handle_promote(engine: SimEngine, command: SimCommand) -> void:
	var unit := _by_uid.get(command.value) as UnitState
	if unit == null:
		_deny(engine, command, REASON_UNKNOWN_UNIT)
		return
	if not unit.awaiting_promotion:
		if unit.target != &"":
			_deny(engine, command, REASON_TRAINING_INCOMPLETE)
		else:
			_deny(engine, command, REASON_NOT_AWAITING_PROMOTION)
		return
	var missing := missing_gear_slots(unit.uid)
	if not missing.is_empty():
		# The loud gate: promotion without required gear is refused, never
		# silently defaulted (town-hall q#4 spirit).
		_deny(engine, command, REASON_GEAR_INCOMPLETE)
		return
	_promote_into(engine, unit, _units_by_id[unit.target] as UnitDef)


# --- Determinism oracle + save hooks (fully overridden, never `{}`) --------


func state_hash() -> int:
	var hash_value := 0x811C9DC5
	hash_value = _mix(hash_value, next_uid)
	hash_value = _mix(hash_value, arrivals_total)
	hash_value = _mix(hash_value, _arrival_countdown_milli)
	for uid in _offers:
		hash_value = _mix(hash_value, uid)
	for unit in _units:
		hash_value = _mix(hash_value, unit.uid)
		hash_value = _mix(hash_value, String(unit.def_id).hash())
		hash_value = _mix(hash_value, String(unit.target).hash())
		hash_value = _mix(hash_value, unit.progress_milli)
		hash_value = _mix(hash_value, 1 if unit.awaiting_promotion else 0)
		hash_value = _mix(hash_value, unit.gear.size())
		for slot in unit.gear.keys():  # insertion order — deterministic
			hash_value = _mix(hash_value, String(slot).hash())
			hash_value = _mix(hash_value, String(unit.gear[slot]).hash())
	return hash_value


func to_dict() -> Dictionary:
	var offers: Array[int] = []
	for uid in _offers:
		offers.append(uid)
	var units: Array[Dictionary] = []
	for unit in _units:
		var gear_state := {}
		for slot in unit.gear.keys():
			gear_state[String(slot)] = String(unit.gear[slot])
		units.append({
			"uid": unit.uid,
			"def": String(unit.def_id),
			"target": String(unit.target),
			"progress": unit.progress_milli,
			"awaiting": unit.awaiting_promotion,
			"gear": gear_state,
		})
	return {
		"next_uid": next_uid,
		"arrivals_total": arrivals_total,
		"arrival_countdown_milli": _arrival_countdown_milli,
		"offers": offers,
		"units": units,
	}


func from_dict(state: Dictionary) -> void:
	_units.clear()
	_by_uid.clear()
	_offers.clear()
	_training.clear()
	_counts.clear()
	next_uid = int(state.get("next_uid", 1))
	arrivals_total = int(state.get("arrivals_total", 0))
	_arrival_countdown_milli = int(state.get("arrival_countdown_milli", -1))
	for uid in state.get("offers", []):
		_offers.append(int(uid))
	for entry in state.get("units", []):
		var def_id := StringName(entry.get("def", ""))
		if not _units_by_id.has(def_id):
			push_warning("units: saved unit '%s' has unknown def '%s' — skipped" % [entry.get("uid", "?"), def_id])
			continue
		var unit := UnitState.new()
		unit.uid = int(entry.get("uid", 0))
		unit.def_id = def_id
		unit.target = StringName(entry.get("target", ""))
		unit.progress_milli = int(entry.get("progress", 0))
		unit.awaiting_promotion = bool(entry.get("awaiting", false))
		if unit.target != &"" and not _units_by_id.has(unit.target):
			# Content mismatch (save from another pack): keep the unit,
			# drop the unreachable training loudly — never crash on_tick.
			push_warning(
				"units: unit %d training target '%s' unknown — training dropped"
				% [unit.uid, unit.target]
			)
			unit.target = &""
			unit.awaiting_promotion = false
			unit.progress_milli = 0
		var gear_state: Dictionary = entry.get("gear", {})
		for slot in gear_state.keys():
			var gear_id := StringName(gear_state[slot])
			if not _gear_by_id.has(gear_id):
				push_warning("units: saved gear '%s' not in pack — dropped from unit %d" % [gear_id, unit.uid])
				continue
			unit.gear[StringName(slot)] = gear_id
		_units.append(unit)
		_by_uid[unit.uid] = unit
		_counts[def_id] = int(_counts.get(def_id, 0)) + 1
		# Rebuild the in-flight training list in roster order. Order inside
		# _training is not hash-relevant (state_hash walks _units; same-tick
		# completions touch no shared state), so arrival order restores an
		# equivalent engine — proven lockstep by the round-trip test.
		if unit.target != &"" and not unit.awaiting_promotion:
			_training.append(unit)


# --- Internals ---------------------------------------------------------------


## Interval for the run's NEXT arrival (milli-ticks): the opening-rush entry
## when the run's arrival counter is still inside the rush (metronome — no
## RNG draw), otherwise the jittered normal cadence. Zero jitter draws
## nothing — a metronome cadence leaves rng.state untouched.
func _next_interval_milli(engine: SimEngine) -> int:
	if arrivals_total < _early_intervals_milli.size():
		return _early_intervals_milli[arrivals_total]
	return _draw_interval_milli(engine)


## True while the gate holds its full capacity of concurrent offers (the
## T-SIM-08 arrivals pause; 0 capacity = never full = uncapped gate).
func _gate_full() -> bool:
	return _gate_capacity > 0 and _offers.size() >= _gate_capacity


## Draw the next arrival interval from the engine RNG (milli-ticks). Zero
## jitter draws nothing — a metronome cadence leaves rng.state untouched.
## Normal cadence only; the opening rush never calls this.
func _draw_interval_milli(engine: SimEngine) -> int:
	if _jitter_milli <= 0:
		return _interval_milli
	var drawn := engine.rng.randi_range(-_jitter_milli, _jitter_milli)
	return maxi(SimFixed.MILLI, _interval_milli + drawn)


func _spawn_offer(engine: SimEngine) -> void:
	var uid := next_uid
	next_uid += 1
	_offers.append(uid)
	arrivals_total += 1
	engine.events.record(engine.tick_count, &"recruit_arrived", _base_unit, uid, _offers.size())


func _complete_training(engine: SimEngine, unit: UnitState) -> void:
	var target := _units_by_id[unit.target] as UnitDef
	if target == null:
		push_warning("units: training target '%s' vanished from pack — unit %d rests" % [unit.target, unit.uid])
		unit.target = &""
		return
	# Gear-gated ranks (required_gear_slots non-empty: knight, archer) hold
	# at "training complete, awaiting gear + promote"; gear-free ranks
	# (worker, militia, trainee) promote the moment the timer runs out.
	var held := not target.required_gear_slots.is_empty()
	engine.events.record(
		engine.tick_count, &"training_complete", target.id, unit.uid, 1 if held else 0
	)
	if held:
		unit.awaiting_promotion = true
	else:
		_promote_into(engine, unit, target)


func _promote_into(engine: SimEngine, unit: UnitState, def: UnitDef) -> void:
	_counts[unit.def_id] = int(_counts.get(unit.def_id, 0)) - 1
	unit.def_id = def.id
	unit.target = &""
	unit.progress_milli = 0
	unit.awaiting_promotion = false
	_counts[def.id] = int(_counts.get(def.id, 0)) + 1
	engine.events.record(engine.tick_count, &"unit_promoted", def.id, unit.uid, int(_counts[def.id]))
	if def.can_work:
		# The recruit -> worker handoff: same command surface the UI uses,
		# drained at the next tick's start (docs/sim-engine.md §11).
		engine.submit_command(&"add_worker", &"production", 1)


## A slot may be filled only where it is required — by the unit's current
## def (post-promotion tier refits) or its training target (gearing a
## trainee up for knight/archer).
func _slot_required(unit: UnitState, slot: StringName) -> bool:
	var def := _units_by_id.get(unit.def_id) as UnitDef
	if def != null and def.required_gear_slots.has(slot):
		return true
	if unit.target != &"":
		var target := _units_by_id.get(unit.target) as UnitDef
		if target != null and target.required_gear_slots.has(slot):
			return true
	return false


## Run-reset seam (T-SIM-04 reset contract, docs/sim-engine.md §12): the
## roster, the gate and the arrival cadence back to boot state. The next
## tick re-schedules the first arrival with a fresh RNG draw — the new
## run's stream, identical in shape to a freshly constructed engine. The
## opening rush (T-SIM-08) re-opens too: it is keyed on the run's own
## arrival counter, which this reset zeroes — every restart starts eager.
## Called synchronously by the run system at the run_restart drain.
func reset_run(_p_regime: RegimeDef = null) -> void:
	_units.clear()
	_by_uid.clear()
	_offers.clear()
	_training.clear()
	_counts.clear()
	next_uid = 1
	arrivals_total = 0
	_arrival_countdown_milli = -1


## Scatter seam (T-SIM-05 crackdown): remove up to `count` UNASSIGNED
## recruits — gate offers first (arrival order), then idle base units
## (accepted peasants resting without a role, roster order). NEVER touches
## committed units: militia/trainee pipeline, awaiting promotions, workers,
## the trained army, or anything else. Returns how many were scattered
## (0 when the pool is empty / count <= 0). The caller (the suspicion
## system, mid-on_tick) records the event — this is a pure mutation, the
## same direct-synchronous-call shape as the reset contract.
func scatter_recruits(count: int) -> int:
	if count <= 0:
		return 0
	var scattered := 0
	while scattered < count and not _offers.is_empty():
		_offers.pop_front()
		scattered += 1
	var index := 0
	while scattered < count and index < _units.size():
		var unit := _units[index]
		if unit.def_id == _base_unit and unit.target == &"" and not unit.awaiting_promotion:
			_units.remove_at(index)  # do not advance: next unit shifted here
			_by_uid.erase(unit.uid)
			_counts[unit.def_id] = int(_counts.get(unit.def_id, 1)) - 1
			scattered += 1
		else:
			index += 1
	return scattered


func _deny(engine: SimEngine, command: SimCommand, reason: int) -> void:
	var subject := command.subject if command.subject != &"" else &"units"
	engine.events.record(engine.tick_count, &"lifecycle_denied", subject, reason, command.value)


func _ids_sort_by_tier(ids: Array[StringName]) -> void:
	# Insertion sort (tiny N): stable, deterministic, by tier then id.
	for i in range(1, ids.size()):
		var key: StringName = ids[i]
		var key_tier := (_gear_by_id[key] as GearDef).tier
		var j := i - 1
		while j >= 0:
			var other := _gear_by_id[ids[j]] as GearDef
			if other.tier > key_tier or (other.tier == key_tier and String(ids[j]) > String(key)):
				ids[j + 1] = ids[j]
				j -= 1
			else:
				break
		ids[j + 1] = key


## FNV-flavored 32-bit-safe mix (same shape as SimEngine._mix —
## docs/sim-engine.md §2: no signed overflow, no platform-sensitive ops).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
