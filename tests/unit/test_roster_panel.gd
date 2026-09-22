## Unit tests for RosterPanel (T-04) — recruitment, peasant allocation, and military armory.
extends GdUnitTestSuite

const RosterPanel := preload("res://ui/screens/gameplay/roster_panel.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_roster_tests")


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
	var root := "user://cs_roster_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_roster_panel_instantiation() -> void:
	var panel := RosterPanel.new()
	assert_object(panel.title_label).is_not_null()
	assert_object(panel.gate_header_label).is_not_null()
	assert_object(panel.offers_container).is_not_null()
	assert_object(panel.peasant_summary_label).is_not_null()
	assert_object(panel.assign_worker_btn).is_not_null()
	assert_object(panel.assign_militia_btn).is_not_null()
	assert_object(panel.army_summary_label).is_not_null()
	assert_object(panel.training_container).is_not_null()
	assert_object(panel.soldiers_container).is_not_null()
	panel.free()


func test_bind_roster_data_populates_sections() -> void:
	var panel := RosterPanel.new()
	var data := {
		"offers": [
			{"id": 101, "display_name": "Wandering Farmhand"},
			{"id": 102, "display_name": "Refugee Craftsman"}
		],
		"idle_peasants": [201, 202],
		"workers": [203],
		"militia_count": 2,
		"training_units": [
			{"unit_id": 204, "training_target": &"archer", "progress_percent": 65.0}
		],
		"soldiers": [
			{"id": 205, "display_name": "Knight", "combat_power": 12}
		],
		"total_combat_power": 14,
	}

	panel.bind_roster_data(data)

	# Offers
	assert_str(panel.gate_header_label.text).is_equal("Gate Arrivals (2 Available)")
	assert_int(panel.offer_rows.size()).is_equal(2)
	assert_bool(panel.offer_rows.has(101)).is_true()
	assert_bool(panel.offer_rows.has(102)).is_true()

	# Peasants
	assert_str(panel.peasant_summary_label.text).is_equal("Idle Peasants: 2")
	assert_bool(panel.assign_worker_btn.disabled).is_false()
	assert_bool(panel.assign_militia_btn.disabled).is_false()

	# Military
	assert_bool(panel.army_summary_label.text.contains("Power: 14")).is_true()
	assert_bool(panel.army_summary_label.text.contains("Militia: 2")).is_true()
	assert_bool(panel.army_summary_label.text.contains("Trained Soldiers: 1")).is_true()

	panel.free()


func test_offer_interaction_and_peasant_allocation() -> void:
	var panel := RosterPanel.new()

	var offer_accepted_calls: Array = []
	var offer_dismissed_calls: Array = []
	var peasant_worker_calls: Array = []
	var peasant_militia_calls: Array = []

	panel.offer_accepted.connect(func(id: int) -> void: offer_accepted_calls.append(id))
	panel.offer_dismissed.connect(func(id: int) -> void: offer_dismissed_calls.append(id))
	panel.peasant_promoted_to_worker.connect(func(id: int) -> void: peasant_worker_calls.append(id))
	panel.peasant_promoted_to_militia.connect(func(id: int) -> void: peasant_militia_calls.append(id))

	panel.bind_roster_data({
		"offers": [
			{"id": 101, "display_name": "Recruit A"},
			{"id": 102, "display_name": "Recruit B"}
		],
		"idle_peasants": [555],
		"workers": [],
		"militia_count": 0,
		"training_units": [],
		"soldiers": [],
		"total_combat_power": 0
	})

	# Test accept offer click
	var row1: Dictionary = panel.offer_rows[101]
	row1["accept_btn"].pressed.emit()
	assert_int(offer_accepted_calls.size()).is_equal(1)
	assert_int(offer_accepted_calls[0]).is_equal(101)

	# Test dismiss offer click
	var row2: Dictionary = panel.offer_rows[102]
	row2["dismiss_btn"].pressed.emit()
	assert_int(offer_dismissed_calls.size()).is_equal(1)
	assert_int(offer_dismissed_calls[0]).is_equal(102)

	# Test peasant assignments
	assert_bool(panel.assign_worker_btn.disabled).is_false()
	panel.assign_worker_btn.pressed.emit()
	assert_int(peasant_worker_calls.size()).is_equal(1)
	assert_int(peasant_worker_calls[0]).is_equal(555)

	assert_bool(panel.assign_militia_btn.disabled).is_false()
	panel.assign_militia_btn.pressed.emit()
	assert_int(peasant_militia_calls.size()).is_equal(1)
	assert_int(peasant_militia_calls[0]).is_equal(555)

	panel.free()


func test_update_from_host_reads_live_state() -> void:
	var host := _fresh_host()
	var panel := RosterPanel.new()
	panel.update_from_host(host)

	assert_str(panel.title_label.text).is_not_empty()
	assert_str(panel.gate_header_label.text).is_not_empty()
	assert_str(panel.peasant_summary_label.text).is_not_empty()
	assert_str(panel.army_summary_label.text).is_not_empty()

	panel.free()
