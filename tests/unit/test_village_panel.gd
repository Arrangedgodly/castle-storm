## Unit tests for VillagePanel (T-03) — village production and worker management.
extends GdUnitTestSuite

const VillagePanel := preload("res://ui/screens/gameplay/village_panel.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_village_tests")


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
	var root := "user://cs_village_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_village_panel_instantiation() -> void:
	var panel := VillagePanel.new()
	assert_object(panel.title_label).is_not_null()
	assert_object(panel.idle_workers_label).is_not_null()
	assert_object(panel.buildings_container).is_not_null()
	panel.free()


func test_bind_village_data_creates_rows_and_button_states() -> void:
	var panel := VillagePanel.new()
	var data := {
		"idle_workers": 2,
		"buildings": [
			{
				"id": &"woodcutter",
				"display_name": "Woodcutter's Camp",
				"level": 1,
				"max_level": 3,
				"assigned_workers": 1,
				"worker_slots": 2,
				"production_rate_per_hour": 10.0,
				"resource_produced": "timber",
				"upgrade_cost": {&"timber": 50},
				"can_afford_upgrade": true,
			},
			{
				"id": &"quarry",
				"display_name": "Stone Quarry",
				"level": 3,
				"max_level": 3,
				"assigned_workers": 0,
				"worker_slots": 4,
				"production_rate_per_hour": 0.0,
				"resource_produced": "iron",
				"upgrade_cost": {},
				"can_afford_upgrade": false,
			}
		]
	}

	panel.bind_village_data(data)

	assert_str(panel.idle_workers_label.text).is_equal("Idle Workers: 2")
	assert_int(panel.building_rows.size()).is_equal(2)

	# Woodcutter row assertions
	var wc_row: Dictionary = panel.building_rows[&"woodcutter"]
	assert_str(wc_row["name_label"].text).is_equal("Woodcutter's Camp (Lv 1/3)")
	assert_str(wc_row["worker_label"].text).is_equal("Workers: 1 / 2")
	assert_bool(wc_row["assign_btn"].disabled).is_false()
	assert_bool(wc_row["unassign_btn"].disabled).is_false()
	assert_bool(wc_row["upgrade_btn"].disabled).is_false()

	# Quarry row assertions (Max level, 0 assigned)
	var q_row: Dictionary = panel.building_rows[&"quarry"]
	assert_str(q_row["name_label"].text).is_equal("Stone Quarry (Lv 3/3)")
	assert_str(q_row["worker_label"].text).is_equal("Workers: 0 / 4")
	assert_bool(q_row["assign_btn"].disabled).is_false()
	assert_bool(q_row["unassign_btn"].disabled).is_true()
	assert_bool(q_row["upgrade_btn"].disabled).is_true()

	panel.free()


func test_button_clicks_emit_signals_and_queue_commands() -> void:
	var host := _fresh_host()
	var panel := VillagePanel.new()
	panel.update_from_host(host)

	var signal_assigned: Array = []
	var signal_unassigned: Array = []
	var signal_upgraded: Array = []

	panel.assign_worker_clicked.connect(func(id: StringName) -> void: signal_assigned.append(id))
	panel.unassign_worker_clicked.connect(func(id: StringName) -> void: signal_unassigned.append(id))
	panel.upgrade_building_clicked.connect(func(id: StringName) -> void: signal_upgraded.append(id))

	# First building in panel
	var b_ids: Array = panel.building_rows.keys()
	assert_bool(b_ids.size() > 0).is_true()
	var first_id: StringName = b_ids[0]
	var row: Dictionary = panel.building_rows[first_id]

	# Click assign
	row["assign_btn"].pressed.emit()
	assert_int(signal_assigned.size()).is_equal(1)
	assert_str(signal_assigned[0]).is_equal(String(first_id))

	# Click unassign
	row["unassign_btn"].pressed.emit()
	assert_int(signal_unassigned.size()).is_equal(1)
	assert_str(signal_unassigned[0]).is_equal(String(first_id))

	# Click upgrade
	row["upgrade_btn"].pressed.emit()
	assert_int(signal_upgraded.size()).is_equal(1)
	assert_str(signal_upgraded[0]).is_equal(String(first_id))

	# Verify commands in host engine
	var pending_cmds: Array = host.engine._pending
	var kinds: Array[StringName] = []
	for cmd in pending_cmds:
		kinds.append(cmd.kind)

	assert_bool(kinds.has(&"assign_worker")).is_true()
	assert_bool(kinds.has(&"unassign_worker")).is_true()
	assert_bool(kinds.has(&"upgrade_building")).is_true()

	panel.free()
