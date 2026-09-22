## Unit tests for HUDBar (T-02) — top navigation and vital status bar.
extends GdUnitTestSuite

const HUDBar := preload("res://ui/screens/gameplay/hud_bar.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_hud_tests")


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
	var root := "user://cs_hud_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_hud_bar_instantiation_and_nodes() -> void:
	var bar := HUDBar.new()
	assert_object(bar.leader_label).is_not_null()
	assert_object(bar.regime_label).is_not_null()
	assert_object(bar.time_label).is_not_null()
	assert_object(bar.food_label).is_not_null()
	assert_object(bar.timber_label).is_not_null()
	assert_object(bar.iron_label).is_not_null()
	assert_object(bar.suspicion_meter).is_not_null()
	assert_object(bar.suspicion_label).is_not_null()
	assert_object(bar.warn_badge).is_not_null()
	bar.free()


func test_bind_hud_data_updates_labels_and_meters() -> void:
	var bar := HUDBar.new()
	var data := {
		"leader_name": "Alden",
		"leader_epithet": "the Silent",
		"regime_name": "Baron's Reach",
		"run_index": 2,
		"sim_hours": 28.5,
		"resources": {
			&"food": {"amount": 150, "rate_per_hour": 12.0},
			&"timber": {"amount": 80, "rate_per_hour": 4.5},
			&"iron": {"amount": 25, "rate_per_hour": 0.0},
		},
		"suspicion_points": 45,
		"suspicion_max": 100,
		"is_warned": true,
	}

	bar.bind_hud_data(data)

	assert_str(bar.leader_label.text).is_equal("Alden, the Silent")
	assert_bool(bar.regime_label.text.contains("Baron's Reach")).is_true()
	assert_bool(bar.time_label.text.contains("Day 2")).is_true()
	assert_bool(bar.food_label.text.contains("150")).is_true()
	assert_bool(bar.food_label.text.contains("+12.0/h")).is_true()
	assert_bool(bar.timber_label.text.contains("80")).is_true()
	assert_bool(bar.iron_label.text.contains("25")).is_true()
	assert_float(bar.suspicion_meter.value).is_equal(45.0)
	assert_str(bar.suspicion_label.text).is_equal("45 / 100")
	assert_bool(bar.warn_badge.visible).is_true()

	bar.free()


func test_update_from_host_reads_live_state() -> void:
	var host := _fresh_host()
	var bar := HUDBar.new()

	bar.update_from_host(host)

	assert_str(bar.leader_label.text).is_not_empty()
	assert_bool(bar.food_label.text.is_empty()).is_false()
	assert_bool(bar.timber_label.text.is_empty()).is_false()
	assert_bool(bar.iron_label.text.is_empty()).is_false()
	assert_float(bar.suspicion_meter.max_value).is_equal(100.0)

	bar.free()
