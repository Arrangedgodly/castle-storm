## Unit tests for CovertOpsPanel (CO-03).
extends GdUnitTestSuite

const CovertOpsPanel := preload("res://ui/screens/gameplay/covert_ops_panel.gd")
const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_covert_panel_tests")


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
	var root := "user://cs_covert_panel_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_covert_ops_panel_instantiation_and_nodes() -> void:
	var panel := CovertOpsPanel.new()
	assert_object(panel.title_label).is_not_null()
	assert_object(panel.network_status_label).is_not_null()
	assert_object(panel.operations_container).is_not_null()
	assert_object(panel.history_container).is_not_null()
	panel.free()


func test_covert_ops_panel_bind_operations_data() -> void:
	var panel := CovertOpsPanel.new()

	var mock_vm := {
		"network_active": true,
		"active_perks_count": 1,
		"operations": [
			{
				"id": &"bribe_gatekeeper",
				"title": "Bribe Outer Gatekeeper",
				"desc": "Pay off the gate guards.",
				"perk": "Halves Outer Gate Fortification HP",
				"cost_text": "25 Gold",
				"chance_text": "75% Success Rate",
				"risk_text": "+12 Suspicion if Exposed",
				"is_active": true,
				"can_afford": true,
				"can_launch": false,
				"status_label": "ESTABLISHED"
			},
			{
				"id": &"poison_wells",
				"title": "Poison Castle Cisterns",
				"desc": "Taint the water supply.",
				"perk": "-25% Castle Garrison Strength",
				"cost_text": "15 Gold, 20 Food",
				"chance_text": "65% Success Rate",
				"risk_text": "+18 Suspicion if Exposed",
				"is_active": false,
				"can_afford": false,
				"can_launch": false,
				"status_label": "INSUFFICIENT RESOURCES"
			}
		],
		"history": [
			{"success": true, "text": "The gatekeeper took the coin."}
		]
	}

	panel.bind_operations_data(mock_vm)
	assert_bool(panel.network_status_label.text.contains("1 Infiltrations Established")).is_true()
	assert_int(panel.operation_cards.size()).is_equal(2)

	var gate_card: Dictionary = panel.operation_cards[&"bribe_gatekeeper"]
	var gate_btn: Button = gate_card["button"]
	assert_bool(gate_btn.disabled).is_true()
	assert_str(gate_btn.text).is_equal("ESTABLISHED")

	panel.free()


func test_covert_ops_panel_host_setup_and_button_press() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()
	var panel := CovertOpsPanel.new()

	host.engine.set_resource(&"gold", 100)
	panel.setup_host(host, covert)

	assert_int(panel.operation_cards.size()).is_equal(4)
	var gate_card: Dictionary = panel.operation_cards[&"bribe_gatekeeper"]
	var gate_btn: Button = gate_card["button"]
	assert_bool(gate_btn.disabled).is_false()

	var req_fired: Array = []
	var exec_fired: Array = []
	panel.operation_requested.connect(func(id: StringName) -> void: req_fired.append(id))
	panel.operation_executed.connect(func(res: Dictionary) -> void: exec_fired.append(res))

	gate_btn.pressed.emit()

	assert_int(req_fired.size()).is_equal(1)
	assert_str(String(req_fired[0])).is_equal("bribe_gatekeeper")
	assert_int(exec_fired.size()).is_equal(1)
	assert_bool(bool(covert.get_bonuses().get("gatekeeper_bribed", false))).is_true()

	panel.free()
