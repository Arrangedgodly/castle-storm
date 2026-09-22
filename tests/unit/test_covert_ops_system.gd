## Unit tests for CovertOpsSystem (CO-01).
extends GdUnitTestSuite

const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_covert_ops_tests")


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
	var root := "user://cs_covert_ops_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_covert_ops_descriptor_and_query() -> void:
	var covert := CovertOpsSystem.new()
	var ops := covert.get_all_operations()

	assert_int(ops.size()).is_equal(4)

	var gate := covert.get_operation(&"bribe_gatekeeper")
	assert_str(str(gate.get("title"))).is_equal("Bribe Outer Gatekeeper")
	assert_bool(covert.is_operation_active(&"bribe_gatekeeper")).is_false()

	var bonuses := covert.get_bonuses()
	assert_bool(bool(bonuses.get("gatekeeper_bribed", false))).is_false()


func test_covert_ops_can_afford_and_cost_deduction() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	# Empty out resources
	host.engine.set_resource(&"gold", 5)
	assert_bool(covert.can_afford(&"bribe_gatekeeper", host.engine)).is_false()

	# Give enough gold
	host.engine.set_resource(&"gold", 50)
	assert_bool(covert.can_afford(&"bribe_gatekeeper", host.engine)).is_true()


func test_covert_ops_success_grants_bonus() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	host.engine.set_resource(&"gold", 100)
	host.engine.set_resource(&"food", 100)

	var signal_received: Array = []
	covert.operation_completed.connect(func(res: Dictionary) -> void: signal_received.append(res))

	# Execute bribe_gatekeeper (base 75% success)
	var result := covert.execute_operation(&"bribe_gatekeeper", host.engine)

	assert_bool(result.has("op_id")).is_true()
	assert_bool(covert.is_operation_active(&"bribe_gatekeeper")).is_true()
	assert_int(host.engine.get_resource(&"gold")).is_equal(75)  # 100 - 25
	assert_int(signal_received.size()).is_equal(1)

	# Trying again should be rejected as already active
	var repeat := covert.execute_operation(&"bribe_gatekeeper", host.engine)
	assert_bool(bool(repeat.get("success", false))).is_false()


func test_covert_ops_failure_applies_suspicion() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	host.engine.set_resource(&"gold", 50)
	host.engine.set_resource(&"food", 50)

	# Force RNG to roll failure (draw > 65)
	var mock_rng = RandomNumberGenerator.new()
	mock_rng.seed = 12345
	host.engine.rng = mock_rng

	var result := covert.execute_operation(&"poison_wells", host.engine)

	# Cost was paid
	assert_int(host.engine.get_resource(&"gold")).is_equal(35)
	assert_int(host.engine.get_resource(&"food")).is_equal(30)
	assert_bool(result.has("text")).is_true()


func test_covert_ops_reset() -> void:
	var host := _fresh_host()
	var covert := CovertOpsSystem.new()

	host.engine.set_resource(&"gold", 100)
	covert.execute_operation(&"bribe_gatekeeper", host.engine)
	assert_bool(covert.is_operation_active(&"bribe_gatekeeper")).is_true()

	covert.reset()
	assert_bool(covert.is_operation_active(&"bribe_gatekeeper")).is_false()
	assert_int(covert.operation_history.size()).is_equal(0)
