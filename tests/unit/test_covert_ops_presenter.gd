## Unit tests for CovertOpsPresenter (CO-02).
extends GdUnitTestSuite

const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")
const CovertOpsPresenter := preload("res://ui/screens/gameplay/covert_ops_presenter.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_covert_ops_pres_tests")


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
	var root := "user://cs_covert_ops_pres_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_format_null_covert_returns_safe_defaults() -> void:
	var vm := CovertOpsPresenter.format_operations_view(null, null)
	assert_bool(vm.get("network_active")).is_false()
	assert_int(vm.get("active_perks_count")).is_equal(0)
	var ops: Array = vm.get("operations", [])
	assert_int(ops.size()).is_equal(0)


func test_format_operations_view_model() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	host.engine.set_resource(&"gold", 100)
	host.engine.set_resource(&"food", 50)
	host.engine.set_resource(&"iron", 50)

	var vm := CovertOpsPresenter.format_operations_view(covert, host.engine)
	assert_bool(vm.get("network_active")).is_false()
	assert_int(vm.get("active_perks_count")).is_equal(0)

	var ops: Array = vm.get("operations", [])
	assert_int(ops.size()).is_equal(4)

	var gate_op: Dictionary = ops[0]
	assert_str(str(gate_op.get("title"))).is_equal("Bribe Outer Gatekeeper")
	assert_bool(bool(gate_op.get("can_afford"))).is_true()
	assert_bool(bool(gate_op.get("can_launch"))).is_true()
	assert_str(str(gate_op.get("status_label"))).is_equal("READY TO LAUNCH")


func test_launch_operation_via_presenter() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	host.engine.set_resource(&"gold", 100)

	var res := CovertOpsPresenter.launch_operation(covert, host.engine, &"bribe_gatekeeper")
	assert_bool(res.has("op_id")).is_true()

	var vm := CovertOpsPresenter.format_operations_view(covert, host.engine)
	assert_bool(vm.get("network_active")).is_true()
	assert_int(vm.get("active_perks_count")).is_equal(1)

	var ops: Array = vm.get("operations", [])
	var gate_op: Dictionary = ops[0]
	assert_str(str(gate_op.get("status_label"))).is_equal("ESTABLISHED")
	assert_bool(bool(gate_op.get("can_launch"))).is_false()
