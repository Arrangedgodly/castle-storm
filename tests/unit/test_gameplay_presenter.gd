## Unit tests for GameplayPresenter (T-01) — validating the typed view adapter
## and command dispatcher for Castle Storm's redesigned playable interfaces.
extends GdUnitTestSuite

const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_presenter_tests")


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


func _fresh_host(run_seed: int = 424242) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_presenter_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_get_hud_data_returns_expected_fields() -> void:
	var host := _fresh_host()
	var hud: Dictionary = GameplayPresenter.get_hud_data(host)

	assert_bool(hud.is_empty()).is_false()
	assert_str(hud["leader_name"]).is_not_empty()
	assert_bool(hud["is_running"]).is_true()
	assert_float(hud["sim_hours"]).is_greater(0.0)
	var resources: Dictionary = hud["resources"]
	assert_bool(resources.has(&"food")).is_true()
	assert_bool(resources.has(&"timber")).is_true()
	assert_bool(resources.has(&"iron")).is_true()
	assert_int(hud["suspicion_points"]).is_greater_equal(0)


func test_get_village_data_reflects_buildings() -> void:
	var host := _fresh_host()
	var village: Dictionary = GameplayPresenter.get_village_data(host)

	assert_bool(village.is_empty()).is_false()
	assert_int(village["idle_workers"]).is_greater_equal(0)
	var buildings: Array = village["buildings"]
	assert_int(buildings.size()).is_greater(0)

	var first: Dictionary = buildings[0]
	assert_bool(first.has("id")).is_true()
	assert_bool(first.has("name")).is_true()
	assert_bool(first.has("level")).is_true()
	assert_bool(first.has("max_slots")).is_true()
	assert_bool(first.has("can_upgrade")).is_true()


func test_get_roster_data_reflects_population() -> void:
	var host := _fresh_host()
	var roster: Dictionary = GameplayPresenter.get_roster_data(host)

	assert_bool(roster.is_empty()).is_false()
	assert_bool(roster.has("offers")).is_true()
	assert_bool(roster.has("idle_peasants")).is_true()
	assert_bool(roster.has("workers")).is_true()
	assert_bool(roster.has("militia")).is_true()
	assert_bool(roster.has("soldiers")).is_true()
	assert_int(roster["total_population"]).is_greater_equal(0)


func test_get_siege_data_reflects_odds() -> void:
	var host := _fresh_host()
	var siege: Dictionary = GameplayPresenter.get_siege_data(host)

	assert_bool(siege.is_empty()).is_false()
	assert_bool(siege.has("win_odds_percent")).is_true()
	assert_bool(siege.has("floor_met")).is_true()
	assert_bool(siege.has("can_assault")).is_true()
	assert_int(siege["garrison_power"]).is_greater(0)


func test_command_dispatchers_submit_to_host() -> void:
	var host := _fresh_host()
	var production := host.production()
	var b_id: StringName = production.building_ids()[0]

	# Test upgrade building command submission
	GameplayPresenter.upgrade_building(host, b_id)
	assert_int(host.engine._pending.size()).is_equal(1)
	var cmd: SimCommand = host.engine._pending[0]
	assert_str(cmd.kind).is_equal("upgrade_building")
	assert_str(cmd.subject).is_equal(String(b_id))
