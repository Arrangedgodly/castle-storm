## Acceptance marathon — 1000 sim-hours of units flowing (T-SIM-03).
##
## Full stack (heartbeat + units + production): peasants arrive on the
## seeded-jitter cadence, get accepted, branch worker/military, train,
## gear up and promote across 60,000 one-minute ticks while the farm/
## camp/mine economy runs underneath. Proves: the arrival band is sane and
## REPRODUCIBLE (same seed -> same arrival count and hash), the worker
## handoff feeds production's pool exactly (assigned + idle == bootstrap +
## worker promotions), army ranks emerge on both branches, the
## arrivals == offers + units conservation law holds, and a mid-run
## (500h) save round-trip resumes in lockstep with in-flight training and
## partial gear. Measures and reports the marathon rate so T-SIM-03's
## weight on the engine stays visible in CI output.
extends RefCounted

const SIM_HOURS := 1000
const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const BOOTSTRAP_WORKERS := 4  # pre-arrival starting crew via add_worker


func suite_name() -> String:
	return "marathon_units_1000h"


func run(harness) -> void:
	var total_ticks := SIM_HOURS * SimEngine.TICKS_PER_SIM_HOUR

	# --- Main run: arrivals + assignments + promotions, timed.
	var first := _build()
	_seed_run(first)
	var clock_start := Time.get_ticks_msec()
	var ran := _run_script(first, total_ticks)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var rate := float(total_ticks) / wall
	var units := first.get_system(&"units") as UnitLifecycleSystem
	var production := first.get_system(&"production") as ProductionSystem

	print(
		"[marathon_units_1000h] %d ticks (%d sim-hours, %d arrivals, %d workers, %d knights, %d archers, army power %d) in %.3fs — %.0f ticks/s; state_hash=%d"
		% [
			total_ticks, SIM_HOURS, units.arrivals_total, units.unit_count(&"worker"),
			units.unit_count(&"knight"), units.unit_count(&"archer"), units.army_power(),
			wall, rate, first.state_hash(),
		]
	)

	harness.check(ran == total_ticks, "fast_forward ran all %d ticks" % total_ticks)
	harness.check(wall < BUDGET_SECONDS, "1000h units flow in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Determinism: same construction, seed, command script -> same hash.
	var second := _build()
	_seed_run(second)
	_run_script(second, total_ticks)
	var second_units := second.get_system(&"units") as UnitLifecycleSystem
	harness.check(first.state_hash() == second.state_hash(), "same seed + script -> same 1000h units hash")
	harness.check(
		units.arrivals_total == second_units.arrivals_total,
		"arrival count reproducible: %d" % units.arrivals_total
	)
	harness.check(first.rng.state == second.rng.state, "rng stream identical (arrival jitters only)")

	# --- Arrival band: 2h +/- 0.25h cadence over 1000h -> [440, 575].
	harness.check(
		units.arrivals_total >= 440 and units.arrivals_total <= 575,
		"arrivals within the cadence band [440, 575]: %d" % units.arrivals_total
	)

	# --- Units flowed: workers fed the economy, both branches promoted.
	harness.check(units.unit_count(&"worker") > 250, "workers emerged: %d" % units.unit_count(&"worker"))
	harness.check(units.unit_count(&"knight") > 20, "knights emerged: %d" % units.unit_count(&"knight"))
	harness.check(units.unit_count(&"archer") > 20, "archers emerged: %d" % units.unit_count(&"archer"))
	harness.check(units.army_power() > 0, "army power positive: %d" % units.army_power())
	harness.check(units.pending_offers() >= 0, "gate never negative: %d" % units.pending_offers())

	# --- Conservation: every arrival is either waiting or accepted.
	harness.check(
		units.arrivals_total == units.pending_offers() + units.total_units(),
		"arrivals (%d) == offers (%d) + units (%d)"
		% [units.arrivals_total, units.pending_offers(), units.total_units()]
	)

	# --- Cross-system invariant: the worker handoff fed production EXACTLY
	# (no leaks, no double-counting; nothing removed at this stage).
	var employed: int = production.idle_workers() \
		+ production.assigned_workers(&"farm") \
		+ production.assigned_workers(&"camp") \
		+ production.assigned_workers(&"mine")
	harness.check(
		employed == BOOTSTRAP_WORKERS + units.unit_count(&"worker"),
		"production pool == bootstrap %d + worker promotions %d (got %d)"
		% [BOOTSTRAP_WORKERS, units.unit_count(&"worker"), employed]
	)

	# --- Economy actually ran under the unit flow: every promoted rank is
	# walking around in paid-for gear (recipes were charged at equip time).
	var geared := 0
	for uid in units.unit_ids():
		if units.gear_tier(uid, &"weapon") > 0 or units.gear_tier(uid, &"armor") > 0:
			geared += 1
	harness.check(
		geared >= units.unit_count(&"knight") + units.unit_count(&"archer"),
		"every knight/archer holds paid gear: %d geared vs %d promoted" % [geared, units.unit_count(&"knight") + units.unit_count(&"archer")]
	)
	for id in [&"food", &"timber", &"iron"]:
		harness.check(first.get_resource(id) > 0, "%s pool positive: %d" % [id, first.get_resource(id)])

	# --- Mid-run save round-trip at 500h: in-flight training + partial
	# gear cross the boundary; twin resumes in lockstep to 1000h.
	var half := _build()
	_seed_run(half)
	_run_script(half, total_ticks / 2)
	var captured := half.to_dict()
	var resumed := _build()
	harness.check(resumed.apply_state_dict(captured), "state dict applies at 500h")
	harness.check(resumed.state_hash() == half.state_hash(), "restored hash == original at 500h")
	_run_script(half, total_ticks)
	_run_script(resumed, total_ticks)
	harness.check(
		half.state_hash() == resumed.state_hash(),
		"500h save round-trip lockstep to 1000h (hash %d vs %d)" % [half.state_hash(), resumed.state_hash()]
	)


# --- Run scripting ----------------------------------------------------------


## Grants the pool and queues the boot commands (drained at tick 1):
## bootstrap crew, build all three producers.
func _seed_run(engine: SimEngine) -> void:
	engine.set_resource(&"food", 1_000_000_000)
	engine.set_resource(&"timber", 1_000_000_000)
	engine.set_resource(&"iron", 1_000_000_000)
	engine.submit_command(&"add_worker", &"production", BOOTSTRAP_WORKERS)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.submit_command(&"upgrade_building", &"camp", 1)
	engine.submit_command(&"upgrade_building", &"mine", 1)


## One deterministic management batch: accept the gate, branch the idle
## peasants (every third takes the military path), advance the military
## path, gear + promote the held ranks (cheapest option per missing slot;
## unaffordable attempts deny loudly and retry next batch), and keep the
## growing worker pool employed. Pure reads -> commands; no RNG.
func _manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	var index := 0
	for uid in units.idle_units(&"peasant"):
		index += 1
		engine.submit_command(&"assign_role", &"militia" if index % 3 == 0 else &"worker", uid)
	for uid in units.idle_units(&"militia"):
		engine.submit_command(&"start_training", &"trainee", uid)
	# Branch the trainees toward the CURRENTLY FEWER committed rank
	# (state-derived, not batch-local: a lone trainee still alternates
	# across batches). Committed = promoted + awaiting + mid-training.
	var knight_committed := units.unit_count(&"knight")
	var archer_committed := units.unit_count(&"archer")
	for uid in units.unit_ids():
		var target := units.training_target(uid)
		if target == &"knight":
			knight_committed += 1
		elif target == &"archer":
			archer_committed += 1
	for uid in units.idle_units(&"trainee"):
		if knight_committed <= archer_committed:
			knight_committed += 1
			engine.submit_command(&"start_training", &"knight", uid)
		else:
			archer_committed += 1
			engine.submit_command(&"start_training", &"archer", uid)
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			var options := units.gear_ids_for_slot(slot)
			if not options.is_empty():
				engine.submit_command(&"equip_gear", options[0], uid)
		engine.submit_command(&"promote", &"", uid)
	for id in [&"farm", &"camp", &"mine"]:
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


## Runs total_ticks in 10h chunks with a management batch between chunks
## (commands drain at the next chunk's first tick — identical boundaries
## on every rerun). Returns ticks run.
func _run_script(engine: SimEngine, total_ticks: int) -> int:
	var ran := 0
	while ran < total_ticks:
		var chunk: int = mini(CHUNK_TICKS, total_ticks - ran)
		if ran > 0:
			_manage(engine)
		ran += engine.fast_forward(chunk)
	return ran


# --- Fixtures ----------------------------------------------------------------


func _build() -> SimEngine:
	# Registration order mirrors causality: recruits flow units ->
	# production. Heartbeat first (engine marathon convention).
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), EconomyTunables.new()))
	engine.register_system(ProductionSystem.new(_building_defs(), EconomyTunables.new(), null))
	return engine


func _unit_defs() -> Array[UnitDef]:
	# The content-schema example chain (6 units, full promotion graph).
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"worker")
	peasant.promotion_paths.append(&"militia")
	defs.append(peasant)

	var worker := UnitDef.new()
	worker.id = &"worker"
	worker.display_name = "Worker"
	worker.can_work = true
	worker.training_time_hours = 0.5
	defs.append(worker)

	var militia := UnitDef.new()
	militia.id = &"militia"
	militia.display_name = "Militia"
	militia.training_time_hours = 2.0
	militia.promotion_paths.append(&"trainee")
	militia.combat_power = 1
	militia.suspicion_on_train = 8
	defs.append(militia)

	var trainee := UnitDef.new()
	trainee.id = &"trainee"
	trainee.display_name = "Trainee"
	trainee.training_time_hours = 4.0
	trainee.promotion_paths.append(&"knight")
	trainee.promotion_paths.append(&"archer")
	trainee.combat_power = 2
	defs.append(trainee)

	var knight := UnitDef.new()
	knight.id = &"knight"
	knight.display_name = "Knight"
	knight.training_time_hours = 12.0
	knight.required_gear_slots.append(&"weapon")
	knight.required_gear_slots.append(&"armor")
	knight.combat_power = 10
	knight.suspicion_on_train = 8
	defs.append(knight)

	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.required_gear_slots.append(&"weapon")
	archer.combat_power = 6
	archer.suspicion_on_train = 4
	defs.append(archer)
	return defs


func _gear_defs() -> Array[GearDef]:
	# Both slots x two tiers: t1 = the example pack recipes, t2 stronger.
	var defs: Array[GearDef] = []
	var weapon_t1 := GearDef.new()
	weapon_t1.id = &"gear_weapon_t1"
	weapon_t1.display_name = "Borrowed Sword"
	weapon_t1.slot = &"weapon"
	weapon_t1.tier = 1
	weapon_t1.combat_power = 2
	weapon_t1.recipe[&"iron"] = 10
	weapon_t1.recipe[&"timber"] = 5
	defs.append(weapon_t1)

	var weapon_t2 := GearDef.new()
	weapon_t2.id = &"gear_weapon_t2"
	weapon_t2.display_name = "Ground Sword"
	weapon_t2.slot = &"weapon"
	weapon_t2.tier = 2
	weapon_t2.combat_power = 4
	weapon_t2.recipe[&"iron"] = 20
	weapon_t2.recipe[&"timber"] = 10
	defs.append(weapon_t2)

	var armor_t1 := GearDef.new()
	armor_t1.id = &"gear_armor_t1"
	armor_t1.display_name = "Padded Jack"
	armor_t1.slot = &"armor"
	armor_t1.tier = 1
	armor_t1.combat_power = 3
	armor_t1.recipe[&"iron"] = 15
	defs.append(armor_t1)

	var armor_t2 := GearDef.new()
	armor_t2.id = &"gear_armor_t2"
	armor_t2.display_name = "Riveted Jack"
	armor_t2.slot = &"armor"
	armor_t2.tier = 2
	armor_t2.combat_power = 6
	armor_t2.recipe[&"iron"] = 30
	defs.append(armor_t2)
	return defs


func _building_defs() -> Array[BuildingDef]:
	# The production marathon trio (farm/camp/mine at the R4 band spread).
	var milestones: Array[int] = [10, 20]
	var farm := BuildingDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.resource_produced = &"food"
	farm.base_production_per_worker_hour = 6.0
	farm.worker_slots_base = 2
	farm.base_cost[&"timber"] = 15
	farm.cost_growth = 1.08
	farm.milestone_levels = milestones
	farm.max_level = 30

	var camp := BuildingDef.new()
	camp.id = &"camp"
	camp.display_name = "Lumber Camp"
	camp.resource_produced = &"timber"
	camp.base_production_per_worker_hour = 6.0
	camp.worker_slots_base = 2
	camp.base_cost[&"food"] = 10
	camp.cost_growth = 1.10
	camp.milestone_levels = milestones
	camp.max_level = 30

	var mine := BuildingDef.new()
	mine.id = &"mine"
	mine.display_name = "Iron Mine"
	mine.resource_produced = &"iron"
	mine.base_production_per_worker_hour = 3.0
	mine.worker_slots_base = 3
	mine.base_cost[&"timber"] = 40
	mine.base_cost[&"food"] = 20
	mine.cost_growth = 1.12
	mine.milestone_levels = milestones
	mine.max_level = 30

	var defs: Array[BuildingDef] = [farm, camp, mine]
	return defs
