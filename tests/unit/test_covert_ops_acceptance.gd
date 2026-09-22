## Acceptance test suite for Clandestine Operations & Infiltration (CO-04).
extends GdUnitTestSuite

const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")
const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")
const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_covert_acceptance_tests")


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
	var root := "user://cs_covert_acceptance_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_covert_ops_in_gameplay_screen_end_to_end() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	get_tree().root.add_child(screen)
	screen.setup_host(host)

	assert_int(screen.tab_container.get_tab_count()).is_greater_equal(3)
	assert_object(screen.covert_panel).is_not_null()

	# Give enough resources for operations
	host.engine.set_resource(&"gold", 100)
	screen.refresh()

	var gate_card: Dictionary = screen.covert_panel.operation_cards[&"bribe_gatekeeper"]
	var gate_btn: Button = gate_card["button"]
	assert_bool(gate_btn.disabled).is_false()

	# Launch bribe operation
	gate_btn.pressed.emit()

	# Resource deducted (100 - 25 = 75)
	assert_int(host.engine.get_resource(&"gold")).is_equal(75)
	assert_bool(screen.event_ticker_label.text.contains("Chronicle:")).is_true()
	assert_bool(bool(screen.covert_system.get_bonuses().get("gatekeeper_bribed", false))).is_true()

	screen.queue_free()


func test_tactical_siege_synergy_with_bribed_gatekeeper() -> void:
	var host := _fresh_host()

	# 1. Base siege without bribery
	var base_siege := TacticalSiegeResolver.new(host.engine)
	base_siege.start_siege(host.engine)
	var base_gate_hp: int = base_siege.phase_defender_max_hp

	# 2. Siege with gatekeeper bribery
	var covert := CovertOpsSystem.new()
	host.engine.set_resource(&"gold", 100)
	covert.execute_operation(&"bribe_gatekeeper", host.engine)

	var bribed_siege := TacticalSiegeResolver.new(host.engine)
	bribed_siege.start_siege(host.engine, covert)
	var bribed_gate_hp: int = bribed_siege.phase_defender_max_hp

	assert_int(bribed_gate_hp).is_less(base_gate_hp)
	assert_int(bribed_gate_hp).is_equal(maxi(2, int(round(float(base_gate_hp) * 0.50))))


func test_tactical_siege_synergy_with_poisoned_cisterns_and_smuggled_arms() -> void:
	var host := _fresh_host()

	var covert := CovertOpsSystem.new()
	host.engine.set_resource(&"gold", 100)
	host.engine.set_resource(&"food", 100)
	host.engine.set_resource(&"iron", 100)

	# Execute both ops
	covert.execute_operation(&"poison_wells", host.engine)
	covert.execute_operation(&"smuggle_arms", host.engine)

	var siege := TacticalSiegeResolver.new(host.engine)
	var start_info := siege.start_siege(host.engine, covert)

	# Garrison strength weakened by 25%
	assert_int(siege.total_garrison_power).is_less(60)
	# Army power increased by +15
	assert_int(siege.current_army_power).is_greater_equal(35)
