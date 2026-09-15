## Manual save/load debug run (T-ARCH-03) — NOT a test; a human-facing probe.
##
##     make save-debug                      # 100h session into user://saves
##     CS_SAVE_HOURS=500 make save-debug    # a longer session
##     CS_SAVE_ROOT=res://saves make save-debug   # write into the repo's saves/ dir
##
## Behavior models a real game process (content: the T-DATA-02 MVP pack,
## loaded through the loud gate; bootstrap through the grant_resources
## command — the F1 verb, no set_resource):
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

const PACK_PATH := "res://content/mvp/pack.tres"
const MARATHON_STIPEND: Dictionary = {
	&"food": 1_000_000_000,
	&"timber": 1_000_000_000,
	&"iron": 1_000_000_000,
}


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


# --- Full-stack fixture (the MVP pack; compact form of the suites' helper) ---


func _register_stack(engine: SimEngine) -> void:
	var pack := ContentValidator.load_pack(PACK_PATH)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, null, MARATHON_STIPEND))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))


func _build(run_seed: int) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	_register_stack(engine)
	return engine


func _producer_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for building: BuildingDef in ContentValidator.load_pack(PACK_PATH).buildings:
		if building.resource_produced != &"":
			ids.append(building.id)
	return ids


func _seed_run(engine: SimEngine, crew := 4) -> void:
	engine.submit_command(&"grant_resources", &"", 0)
	engine.submit_command(&"add_worker", &"production", crew)
	for id in _producer_ids():
		engine.submit_command(&"upgrade_building", id, 1)


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
	for id in _producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


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
