## Unit tests for Tactical Siege Integration (TS-04).
extends GdUnitTestSuite

const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")
const SiegePanel := preload("res://ui/screens/gameplay/siege_panel.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_tactical_integration_tests")


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


func _fresh_host(run_seed: int = 7070) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_tactical_integration_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_siege_panel_tactical_button_state() -> void:
	var panel := SiegePanel.new()
	assert_object(panel.tactical_button).is_not_null()
	assert_str(panel.tactical_button.text).is_equal("COMMAND TACTICAL BREACH")
	assert_bool(panel.tactical_button.disabled).is_true()

	panel.bind_siege_data({
		"can_assault": true,
		"floor_met": true,
		"army_power": 50,
		"garrison_power": 60,
		"win_odds_percent": 45.4
	})
	assert_bool(panel.tactical_button.disabled).is_false()

	var initiated: Array[bool] = []
	panel.tactical_siege_initiated.connect(func(): initiated.append(true))
	panel.tactical_button.pressed.emit()
	assert_int(initiated.size()).is_equal(1)

	panel.free()


func test_gameplay_screen_tactical_siege_launch_and_tactic_flow() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	get_tree().root.add_child(screen)
	screen.host = host

	# Trigger tactical siege
	screen.siege_panel.tactical_siege_initiated.emit()

	assert_object(screen.tactical_siege).is_not_null()
	assert_int(screen.tab_container.current_tab).is_equal(1)
	assert_bool(screen.event_ticker_label.text.contains("war horns")).is_true()

	# Execute tactic via tactical view
	screen.tactical_view.tactic_selected.emit(&"archer_suppression")
	assert_bool(screen.event_ticker_label.text.contains("Archer volleys")).is_true()

	# Order retreat
	screen.tactical_view.retreat_requested.emit()
	assert_bool(screen.event_ticker_label.text.contains("retreat")).is_true()

	# Close siege view
	screen.tactical_view.siege_closed.emit()
	assert_int(screen.tab_container.current_tab).is_equal(0)

	get_tree().root.remove_child(screen)
	screen.free()
