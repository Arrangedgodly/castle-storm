## Unit tests for GameplayScreen (T-06) — unified playable game viewport.
extends GdUnitTestSuite

const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_gameplay_tests")


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
	var root := "user://cs_gameplay_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_gameplay_screen_instantiation() -> void:
	var screen := GameplayScreen.new()
	assert_object(screen.hud_bar).is_not_null()
	assert_object(screen.village_panel).is_not_null()
	assert_object(screen.roster_panel).is_not_null()
	assert_object(screen.siege_panel).is_not_null()
	assert_object(screen.tab_container).is_not_null()
	assert_object(screen.event_ticker_label).is_not_null()
	screen.free()


func test_gameplay_screen_bind_host_and_refresh() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	screen.host = host

	# Child panels should now have updated data from host
	assert_str(screen.hud_bar.leader_label.text).is_not_empty()
	assert_str(screen.village_panel.idle_workers_label.text).is_not_empty()
	assert_str(screen.roster_panel.gate_header_label.text).is_not_empty()
	assert_str(screen.siege_panel.garrison_label.text).is_not_empty()

	screen.free()


func test_advancing_simulation_updates_hud_and_panels() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	screen.host = host

	var initial_time_str := screen.hud_bar.time_label.text

	# Advance by 1 hour (60 ticks)
	screen._on_advance_1h()

	var new_time_str := screen.hud_bar.time_label.text
	assert_str(new_time_str).is_not_equal(initial_time_str)
	assert_bool(new_time_str.contains("01:00")).is_true()

	screen.free()
