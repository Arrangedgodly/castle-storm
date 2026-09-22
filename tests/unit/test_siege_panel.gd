## Unit tests for SiegePanel (T-05) — siege intelligence and assault controls.
extends GdUnitTestSuite

const SiegePanel := preload("res://ui/screens/gameplay/siege_panel.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_siege_tests")


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


func _fresh_host(run_seed: int = 12345) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_siege_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_siege_panel_instantiation() -> void:
	var panel := SiegePanel.new()
	assert_object(panel.title_label).is_not_null()
	assert_object(panel.garrison_label).is_not_null()
	assert_object(panel.army_label).is_not_null()
	assert_object(panel.floor_label).is_not_null()
	assert_object(panel.odds_meter).is_not_null()
	assert_object(panel.odds_label).is_not_null()
	assert_object(panel.assessment_label).is_not_null()
	assert_object(panel.assault_button).is_not_null()
	panel.free()


func test_bind_siege_data_updates_meters_and_assessments() -> void:
	var panel := SiegePanel.new()

	# Scenario 1: Below Floor
	var data_unmet := {
		"garrison_power": 50,
		"army_power": 10,
		"floor_power": 25,
		"floor_met": false,
		"win_odds_percent": 15.0,
		"can_assault": false
	}
	panel.bind_siege_data(data_unmet)

	assert_str(panel.garrison_label.text).is_equal("Castle Garrison: 50 Power")
	assert_str(panel.army_label.text).is_equal("Conspirator Army: 10 Power")
	assert_bool(panel.floor_label.text.contains("Needs 15 More Power")).is_true()
	assert_bool(panel.assault_button.disabled).is_true()
	assert_str(panel.assessment_label.text).is_equal("Below Assault Floor")
	assert_float(panel.odds_meter.value).is_equal(15.0)

	# Scenario 2: Floor Met, Favorable
	var data_favorable := {
		"garrison_power": 50,
		"army_power": 60,
		"floor_power": 25,
		"floor_met": true,
		"win_odds_percent": 68.5,
		"can_assault": true
	}
	panel.bind_siege_data(data_favorable)

	assert_bool(panel.floor_label.text.contains("Floor Met")).is_true()
	assert_bool(panel.assault_button.disabled).is_false()
	assert_str(panel.assessment_label.text).is_equal("Favorable Position")
	assert_str(panel.odds_label.text).is_equal("Calculated Win Odds: 68.5%")
	assert_float(panel.odds_meter.value).is_equal(68.5)

	panel.free()


func test_assault_button_interaction_and_command() -> void:
	var host := _fresh_host()
	var panel := SiegePanel.new()
	panel.update_from_host(host)

	var assault_fired: Array = []
	panel.assault_committed.connect(func() -> void: assault_fired.append(true))

	# Enable assault artificially to test button click & dispatch
	panel.bind_siege_data({
		"garrison_power": 10,
		"army_power": 20,
		"floor_power": 5,
		"floor_met": true,
		"win_odds_percent": 80.0,
		"can_assault": true
	})

	assert_bool(panel.assault_button.disabled).is_false()
	panel.assault_button.pressed.emit()

	assert_int(assault_fired.size()).is_equal(1)

	# Check command in engine
	var pending_cmds: Array = host.engine._pending
	var kinds: Array[StringName] = []
	for cmd in pending_cmds:
		kinds.append(cmd.kind)
	assert_bool(kinds.has(&"commit_assault")).is_true()

	panel.free()
