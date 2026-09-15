## Manual save/load debug run (T-ARCH-03) — NOT a test; a human-facing probe.
##
##     make save-debug                      # 100h session into user://saves
##     CS_SAVE_HOURS=500 make save-debug    # a longer session
##     CS_SAVE_ROOT=res://saves make save-debug   # write into the repo's saves/ dir
##
## Behavior models a real game process:
##   - FIRST invocation: builds the full system stack, starts a run, plays
##     CS_SAVE_HOURS hours in 10h chunks (managed like the marathon suites),
##     saving BOTH domains after every chunk (the ring rotates live), then
##     prints the slot table, the meta bank, and hashes.
##   - SECOND invocation: finds the previous process's saves, LOADS the
##     newest good slot + meta ("continue"), plays on, saves again — proving
##     cross-process persistence by hand.
##   - After it exits you can corrupt files under the save root (truncate,
##     empty, mangle) and re-run: the loader will quarantine the bad slot,
##     fall back, and say so. The deliberate corruption probes are listed in
##     docs/save-format.md §9.
extends SceneTree

const CHUNK_HOURS := 10
const SAVE_EVERY_CHUNK := true


func _initialize() -> void:
	var hours := maxi(1, OS.get_environment("CS_SAVE_HOURS").to_int() if OS.get_environment("CS_SAVE_HOURS") != "" else 100)
	var run_seed := 20260915 if OS.get_environment("CS_SAVE_SEED") == "" else OS.get_environment("CS_SAVE_SEED").to_int()
	var root := "user://saves" if OS.get_environment("CS_SAVE_ROOT") == "" else OS.get_environment("CS_SAVE_ROOT")
	var code := _demo(root, run_seed, hours)
	quit(code)


func _demo(root: String, run_seed: int, hours: int) -> int:
	var manager := SaveManager.new(root)
	var engine := _build(run_seed)
	var run := engine.get_system(&"run") as RunLifecycleSystem

	# Try to continue from the previous process's saves (disk only).
	var probe := SimEngine.new(1)
	_register_stack(probe)
	if manager.load_run(probe):
		print("[save-debug] CONTINUED from disk (%s): tick %d, hash %d, rng %d" % [
			root, probe.tick_count, probe.state_hash(), probe.rng.state,
		])
		engine = probe
		run = engine.get_system(&"run") as RunLifecycleSystem
		run.meta = SaveManager.new(root).load_meta()
	else:
		print("[save-debug] FRESH session under %s (seed %d)" % [root, run_seed])
		engine.submit_command(&"run_start", &"", 0)
		_seed_run(engine)

	# `hours` is time to play THIS invocation (a continuation adds on top of
	# whatever the loaded run already carried).
	var chunks := int(ceil(float(hours) / CHUNK_HOURS))
	for chunk: int in chunks:
		if engine.tick_count > 0:
			_manage(engine)
		engine.fast_forward(CHUNK_HOURS * SimEngine.TICKS_PER_SIM_HOUR)
		if SAVE_EVERY_CHUNK:
			manager.save_run(engine)
			manager.save_meta(run.meta)
	var final_hash := engine.state_hash()

	# --- Report: slot table, meta, verification reload.
	print("[save-debug] session done: %dh total (tick %d), hash %d, rng %d" % [
		engine.sim_hours(), engine.tick_count, final_hash, engine.rng.state,
	])
	print("[save-debug] meta: %d legacy points, %d chronicle run(s)" % [run.meta.legacy_points, run.meta.chronicle.size()])
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		var path := manager.run_slot_path(slot)
		if FileAccess.file_exists(path):
			var envelope := _parse(path)
			print("[save-debug]   slot %d: seq %d, %d bytes, checksum %s..." % [
				slot, int(envelope.get("save_seq", -1)), _size(path), String(envelope.get("checksum", "")).substr(0, 12),
			])
		elif FileAccess.file_exists(path + ".corrupt"):
			print("[save-debug]   slot %d: QUARANTINED (%s.corrupt)" % [slot, path.get_file()])
	var verifier := SimEngine.new(1)
	_register_stack(verifier)
	var reloaded := SaveManager.new(root).load_run(verifier)
	print("[save-debug] verify reload: %s (hash %s)" % ["OK" if reloaded else "FAILED", str(verifier.state_hash())])
	print("[save-debug] run `make save-debug` again to continue this session; corrupt a slot file to watch quarantine + fallback")
	return 0 if reloaded else 1


# --- Full-stack fixture (compact form of the marathon suite fixture) --------


func _register_stack(engine: SimEngine) -> void:
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(_regimes(), _identity()))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), EconomyTunables.new()))
	engine.register_system(ProductionSystem.new(_building_defs(), EconomyTunables.new(), null))


func _build(run_seed: int) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	_register_stack(engine)
	return engine


func _seed_run(engine: SimEngine, crew := 4) -> void:
	engine.set_resource(&"food", 1_000_000_000)
	engine.set_resource(&"timber", 1_000_000_000)
	engine.set_resource(&"iron", 1_000_000_000)
	engine.submit_command(&"add_worker", &"production", crew)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.submit_command(&"upgrade_building", &"camp", 1)
	engine.submit_command(&"upgrade_building", &"mine", 1)


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


func _regimes() -> Array[RegimeDef]:
	var make := func(
		id: StringName, combat_kind: StringName, combat_value: float,
		quirk_kind: StringName, quirk_target: StringName, quirk_value: float
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
	return [
		make.call(&"gilded_crown", &"garrison_multiplier", 1.2, &"production_multiplier", &"timber", 0.85),
		make.call(&"iron_rotunda", &"army_score_multiplier", 1.1, &"building_cost_multiplier", &"all", 1.2),
		make.call(&"velvet_fist", &"garrison_multiplier", 0.9, &"production_multiplier", &"all", 1.15),
		make.call(&"paper_crown", &"army_score_multiplier", 0.95, &"building_cost_multiplier", &"timber", 0.75),
	]


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel", "Godfrey", "Petronella", "Aldous", "Sybil"]
	pools.leader_epithets = [
		"the Unbearable", "the Almost Wise", "of the Leaky Barn", "the Twice-Fooled",
		"the Modest Avalanche", "of Fine Debt", "the Whispering Shout", "the Patient Torch",
	]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous", &"paranoid", &"romantic", &"vengeful"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick", "Bess", "Gil", "Meg", "Ralph", "Joan", "Sim"]
	return pools


func _unit_defs() -> Array[UnitDef]:
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
	return [farm, camp, mine]


func _parse(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var ok := parser.parse(file.get_as_text())
	file.close()
	return parser.data if ok == OK else {}


func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := int(file.get_length())
	file.close()
	return length
