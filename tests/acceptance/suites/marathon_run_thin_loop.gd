## Acceptance marathon — the full thin run loop (T-SIM-04).
##
## Pre-stages the T-SCOPE-01 gate: start run -> recruit -> assign -> produce
## -> train/gear/promote -> resolve_victory -> restart, twice, in
## accelerated time on the full system stack (heartbeat + run + units +
## production). Run 1 plays the real management script (the marathon_units
## cadence) until the army clears the thin victory line, wins, and banks;
## run 2 restarts under a FRESH identity with emptied run-scoped state,
## produces, and loses — failure banks full progress; run 3 is folded and
## save-round-tripped mid-run. Proves: identity generation inside the
## accelerated loop, victory AND failure both accruing the meta bank, the
## chronicle growing across restarts (meta domain, survives its own dict
## round-trip), restart emptying resources/production/units exactly, and
## the whole script reproducing bit-for-bit from the seed. Measures the
## loop's wall time so T-SIM-04's weight stays visible in CI output.
extends RefCounted

const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const RUN1_CAP_TICKS := 600 * SimEngine.TICKS_PER_SIM_HOUR  # 600h ceiling
const VICTORY_ARMY_POWER := 100  # thin line (the real floor is T-SIM-06/08)
const RUN2_TICKS := 100 * SimEngine.TICKS_PER_SIM_HOUR


func suite_name() -> String:
	return "marathon_run_thin_loop"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var report := _thin_loop(_build())
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var total_ticks: int = report["ticks"]

	print(
		"[marathon_run_thin_loop] 3 runs / %d ticks (%.0fh) in %.3fs — %.0f ticks/s; run1 %s beat %s under %s; banked %d lp across %d chronicle runs; final hash %d"
		% [
			total_ticks, float(report["ticks"]) / SimEngine.TICKS_PER_SIM_HOUR, wall,
			float(total_ticks) / wall, report["leader1"], report["leader2"],
			report["regime2"], report["points"], report["chronicle"],
			report["final_hash"],
		]
	)

	harness.check(bool(report.get("ran1_to_victory")), "run 1 reached army power %d within %dh (got %d @ %dh)" % [VICTORY_ARMY_POWER, RUN1_CAP_TICKS / 60, report["run1_power"], report["run1_ticks"] / 60])
	harness.check(wall < BUDGET_SECONDS, "thin loop (3 runs) in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Generation inside the accelerated loop: identities + regimes.
	harness.check(str(report["leader1"]).length() > 3, "run 1 leader generated: %s" % report["leader1"])
	harness.check(str(report["leader2"]).length() > 3, "run 2 leader generated: %s" % report["leader2"])
	harness.check(report["leader2"] != report["leader1"], "restart folded a FRESH identity")
	harness.check(report["regime_ids"].has(report["regime1"]), "run 1 regime is a pack flavor: %s" % report["regime1"])
	harness.check(report["regime_ids"].has(report["regime2"]), "run 2 regime is a pack flavor: %s" % report["regime2"])

	# --- Victory + failure both banked; chronicle grew across restarts.
	harness.check(report["chronicle"] == 2, "chronicle holds run 1 (victory) + run 2 (defeat): %d" % report["chronicle"])
	harness.check(report["points"] == report["score1"] + report["score2"], "bank == run1 %d + run2 %d (banked %d)" % [report["score1"], report["score2"], report["points"]])
	harness.check(report["score1"] > 0 and report["score2"] > 0, "failure banked full progress too (run 2 score %d)" % report["score2"])
	harness.check(report["army1_knights"] + report["army1_archers"] > 0, "run 1 chronicle snapshot carries army stats: %d knights + %d archers" % [report["army1_knights"], report["army1_archers"]])
	harness.check(int(report["produced_run2"]) > 0, "run 2 PRODUCED under the restarted economy (+%d food in %dh)" % [report["produced_run2"], RUN2_TICKS / 60])

	# --- Restart emptied run-scoped state exactly (asserted inside the
	# loop; the folded run 3 proves it kept producing afterwards).
	harness.check(bool(report.get("restart_emptied")), "restart emptied resources/production/units")

	# --- Save round-trip: run 3 mid-run crosses the engine boundary in
	# lockstep, and the meta bank crosses its own dict boundary intact.
	harness.check(bool(report.get("roundtrip_lockstep")), "mid-run save round-trip lockstep (hash %d)" % report["final_hash"])
	harness.check(bool(report.get("meta_roundtrip")), "meta bank + chronicle survive their own dict round-trip")

	# --- Determinism: same construction + seed + script -> same identities,
	# same bank, same final hash (fresh meta, so hashes are comparable).
	var replay := _thin_loop(_build())
	harness.check(replay["leader1"] == report["leader1"], "replay: run 1 identity identical")
	harness.check(replay["leader2"] == report["leader2"], "replay: run 2 identity identical")
	harness.check(replay["points"] == report["points"], "replay: bank identical (%d)" % report["points"])
	harness.check(replay["final_hash"] == report["final_hash"], "replay: final hash identical (%d)" % report["final_hash"])


# --- The thin loop script (pure function of the engine + seed) -------------


## Runs the 3-run script and returns a report dictionary of checkpoints.
func _thin_loop(engine: SimEngine) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var report := {"ticks": 0, "regime_ids": _regime_ids()}

	# --- Run 1: start, recruit, produce, train/gear/promote, win.
	engine.submit_command(&"run_start", &"", 0)
	_seed_run(engine)
	var ran1 := _run_managed_until(engine, VICTORY_ARMY_POWER, RUN1_CAP_TICKS)
	report["ran1_to_victory"] = units.army_power() >= VICTORY_ARMY_POWER
	report["run1_power"] = units.army_power()
	report["run1_ticks"] = ran1
	report["leader1"] = run.leader_name()
	report["regime1"] = run.regime_id()
	run.resolve_victory(engine, true)
	engine.fast_forward(1)  # resolve_victory is tick-aligned: drain it
	report["score1"] = run.last_run_score()
	var entry1: Dictionary = run.meta.chronicle[0]
	report["army1_knights"] = int(entry1["army"].get("knight", 0))
	report["army1_archers"] = int(entry1["army"].get("archer", 0))

	# --- Restart: fresh identity, emptied state, second run.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	report["restart_emptied"] = units.total_units() == 0 \
		and units.arrivals_total == 0 \
		and production.idle_workers() == 0 \
		and production.building_level(&"farm") == 0 \
		and engine.get_resource(&"food") == 0 \
		and engine.get_resource(&"timber") == 0 \
		and engine.get_resource(&"iron") == 0
	report["leader2"] = run.leader_name()
	report["regime2"] = run.regime_id()

	# --- Run 2: rebuild thin, produce, LOSE — failure banks full progress.
	_seed_run(engine, 2)
	engine.submit_command(&"assign_worker", &"farm", 2)  # same drain as the builds
	engine.fast_forward(RUN2_TICKS)
	report["produced_run2"] = engine.get_resource(&"food") - 1_000_000_000
	run.resolve_victory(engine, false)
	engine.fast_forward(1)
	report["score2"] = run.last_run_score()

	# --- Run 3: fold a third identity; round-trip BOTH save domains mid-run.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	report["leader3"] = run.leader_name()
	engine.fast_forward(CHUNK_TICKS)
	var captured := engine.to_dict()
	var meta_captured := run.meta.to_dict()
	var twin := _build()
	var twin_ok := twin.apply_state_dict(captured)
	var twin_run := twin.get_system(&"run") as RunLifecycleSystem
	var twin_meta := RunMeta.new()
	twin_meta.apply_dict(meta_captured)
	engine.fast_forward(CHUNK_TICKS)
	twin.fast_forward(CHUNK_TICKS)
	report["roundtrip_lockstep"] = twin_ok and twin.state_hash() == engine.state_hash()
	report["meta_roundtrip"] = twin_meta.chronicle.size() == 2 \
		and twin_meta.legacy_points == run.meta.legacy_points \
		and twin_run.leader_name() == run.leader_name()

	report["chronicle"] = run.meta.chronicle.size()
	report["points"] = run.meta.legacy_points
	report["ticks"] = engine.tick_count
	report["final_hash"] = engine.state_hash()
	return report


# --- Run scripting ----------------------------------------------------------


## Grants the pool and queues the boot commands (drained at the next tick):
## bootstrap crew, build the producers. Run 2 gets a thinner grant/crew.
func _seed_run(engine: SimEngine, crew := 4) -> void:
	engine.set_resource(&"food", 1_000_000_000)
	engine.set_resource(&"timber", 1_000_000_000)
	engine.set_resource(&"iron", 1_000_000_000)
	engine.submit_command(&"add_worker", &"production", crew)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.submit_command(&"upgrade_building", &"camp", 1)
	engine.submit_command(&"upgrade_building", &"mine", 1)


## The marathon_units management batch: accept the gate, branch peasants
## (every third military), advance the military path, gear + promote held
## ranks (cheapest per missing slot), keep the workers employed. Pure
## reads -> commands; no RNG outside the engine.
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
	# Branch trainees toward the CURRENTLY FEWER committed rank.
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


## 10h chunks with a management batch between them until army power crosses
## the line or the cap hits. Returns ticks run.
func _run_managed_until(engine: SimEngine, army_power_line: int, cap_ticks: int) -> int:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var ran := 0
	while ran < cap_ticks and units.army_power() < army_power_line:
		var chunk: int = mini(CHUNK_TICKS, cap_ticks - ran)
		if ran > 0:
			_manage(engine)
		ran += engine.fast_forward(chunk)
	return ran


# --- Fixtures ----------------------------------------------------------------


func _regime_ids() -> Array[String]:
	var ids: Array[String] = []
	for regime in _regimes():
		ids.append(String(regime.id))
	return ids


func _regimes() -> Array[RegimeDef]:
	var make := func(
		id: StringName,
		combat_kind: StringName,
		combat_value: float,
		quirk_kind: StringName,
		quirk_target: StringName,
		quirk_value: float
	) -> RegimeDef:
		var regime := RegimeDef.new()
		regime.id = id
		regime.display_name = "Regime %s" % id
		var combat := RegimeModifier.new()
		combat.kind = combat_kind
		combat.value = combat_value
		regime.combat_modifier = combat
		var quirk := RegimeModifier.new()
		quirk.kind = quirk_kind
		quirk.target = quirk_target
		quirk.value = quirk_value
		regime.economy_quirk = quirk
		return regime

	var regimes: Array[RegimeDef] = [
		make.call(&"gilded_crown", &"garrison_multiplier", 1.2, &"production_multiplier", &"timber", 0.85),
		make.call(&"iron_rotunda", &"army_score_multiplier", 1.1, &"building_cost_multiplier", &"all", 1.2),
		make.call(&"velvet_fist", &"garrison_multiplier", 0.9, &"production_multiplier", &"all", 1.15),
		make.call(&"paper_crown", &"army_score_multiplier", 0.95, &"building_cost_multiplier", &"timber", 0.75),
	]
	return regimes


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = [
		"Bran", "Ottilie", "Wick", "Mabel", "Godfrey", "Petronella", "Aldous", "Sybil",
	]
	pools.leader_epithets = [
		"the Unbearable", "the Almost Wise", "of the Leaky Barn", "the Twice-Fooled",
		"the Modest Avalanche", "of Fine Debt", "the Whispering Shout", "the Patient Torch",
	]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous", &"paranoid", &"romantic", &"vengeful"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick", "Bess", "Gil", "Meg", "Ralph", "Joan", "Sim"]
	return pools


func _build() -> SimEngine:
	# Registration order mirrors causality: the run frame exists before the
	# recruits/economy it governs. Heartbeat first (engine convention).
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(_regimes(), _identity()))
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
	defs.append(knight)

	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.required_gear_slots.append(&"weapon")
	archer.combat_power = 6
	defs.append(archer)
	return defs


func _gear_defs() -> Array[GearDef]:
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

	var armor_t1 := GearDef.new()
	armor_t1.id = &"gear_armor_t1"
	armor_t1.display_name = "Padded Jack"
	armor_t1.slot = &"armor"
	armor_t1.tier = 1
	armor_t1.combat_power = 3
	armor_t1.recipe[&"iron"] = 15
	defs.append(armor_t1)
	return defs


func _building_defs() -> Array[BuildingDef]:
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
