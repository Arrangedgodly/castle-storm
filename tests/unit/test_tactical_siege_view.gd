## Unit tests for TacticalSiegeView (TS-03).
extends GdUnitTestSuite

const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")
const TacticalSiegePresenter := preload("res://ui/screens/gameplay/tactical_siege_presenter.gd")
const TacticalSiegeView := preload("res://ui/screens/gameplay/tactical_siege_view.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_siege_view_tests")


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


func _fresh_host(run_seed: int = 6060) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_siege_view_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_tactical_siege_view_renders_active_state() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var view_data := TacticalSiegePresenter.format_siege_view(siege)
	var ui := TacticalSiegeView.new()
	ui.bind_view(view_data)

	assert_str(ui.status_label.text).is_equal("Breach in Progress")
	assert_bool(ui.army_power_label.text.contains("Active Army Power")).is_true()
	assert_bool(ui.defender_name_label.text.contains("OUTER GATE")).is_true()
	assert_int(ui.tactics_container.get_child_count()).is_equal(3)
	assert_int(ui.phase_steps_container.get_child_count()).is_equal(3)
	assert_bool(ui.retreat_button.disabled).is_false()

	ui.free()


func test_tactical_siege_view_signal_emission() -> void:
	var host := _fresh_host()
	var siege := TacticalSiegeResolver.new(host.engine)
	siege.start_siege(host.engine)

	var view_data := TacticalSiegePresenter.format_siege_view(siege)
	var ui := TacticalSiegeView.new()
	ui.bind_view(view_data)

	var received_tactic: Array[StringName] = []
	ui.tactic_selected.connect(func(t_id: StringName): received_tactic.append(t_id))

	# First tactic button in tactics_container
	var tactic_card: PanelContainer = ui.tactics_container.get_child(0) as PanelContainer
	var hbox: HBoxContainer = tactic_card.get_child(0) as HBoxContainer
	var exec_btn: Button = hbox.get_child(1) as Button
	exec_btn.pressed.emit()

	assert_int(received_tactic.size()).is_equal(1)
	assert_str(String(received_tactic[0])).is_equal("ram_charge")

	var retreat_events: Array[bool] = []
	ui.retreat_requested.connect(func(): retreat_events.append(true))
	ui.retreat_button.pressed.emit()
	assert_int(retreat_events.size()).is_equal(1)

	var close_events: Array[bool] = []
	ui.siege_closed.connect(func(): close_events.append(true))
	ui.close_button.pressed.emit()
	assert_int(close_events.size()).is_equal(1)

	ui.free()
