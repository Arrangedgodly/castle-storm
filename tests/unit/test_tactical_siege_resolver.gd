## Unit tests for TacticalSiegeResolver (TS-01).
extends GdUnitTestSuite

const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_tactical_siege_tests")


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var dirs: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				dirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _fresh_host(run_seed: int = 4242) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_tactical_siege_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_tactical_siege_initialization() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	var start_event := siege.start_siege(host.engine)

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.IN_PROGRESS)
	assert_int(siege.current_phase).is_equal(TacticalSiegeResolver.Phase.OUTER_GATE)
	assert_int(siege.phase_defender_hp).is_greater(0)
	assert_int(siege.phase_defender_max_hp).is_greater(0)
	assert_str(str(start_event.get("phase"))).is_equal("Outer Gate")


func test_tactical_siege_available_tactics_per_phase() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var phase1_tactics := siege.get_available_tactics()
	assert_int(phase1_tactics.size()).is_equal(3)
	assert_str(str(phase1_tactics[0]["id"])).is_equal("ram_charge")
	assert_str(str(phase1_tactics[1]["id"])).is_equal("archer_suppression")
	assert_str(str(phase1_tactics[2]["id"])).is_equal("sapper_tunnel")


func test_archer_suppression_inflicts_damage_without_casualty() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var initial_hp := siege.phase_defender_hp
	var result := siege.execute_tactic(&"archer_suppression")

	assert_bool(result.get("casualty", true)).is_false()
	assert_int(siege.phase_defender_hp).is_less(initial_hp)
	assert_int(siege.casualties_suffered).is_equal(0)


func test_tactical_retreat_preserves_army() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var initial_army := siege.current_army_power
	var retreat_result := siege.order_retreat()

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.RETREATED)
	assert_int(siege.current_army_power).is_equal(initial_army)
	assert_bool(retreat_result.get("casualties_avoided", false)).is_true()


func test_full_siege_victory_progression() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	# Bounded battle progression
	var rounds: int = 0
	var max_rounds: int = 40
	while siege.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS and rounds < max_rounds:
		rounds += 1
		match siege.current_phase:
			TacticalSiegeResolver.Phase.OUTER_GATE:
				siege.execute_tactic(&"ram_charge")
			TacticalSiegeResolver.Phase.COURTYARD:
				siege.execute_tactic(&"knight_assault")
			TacticalSiegeResolver.Phase.KEEP:
				siege.execute_tactic(&"decisive_storm")

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.VICTORY)
	assert_bool(siege.combat_log.is_empty()).is_false()
