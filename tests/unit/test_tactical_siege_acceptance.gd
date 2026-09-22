## Acceptance suite for Epic 2: Tactical Siege Combat (TS-05).
##
## Validates the complete tactical breach lifecycle: phase transitions,
## tactical stances, casualty resolution, orderly retreat preservation,
## and final castle conquest.
extends GdUnitTestSuite

const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")
const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")
const TacticalSiegePresenter := preload("res://ui/screens/gameplay/tactical_siege_presenter.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_siege_acceptance_tests")


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


func _fresh_host(run_seed: int = 9090) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_siege_acceptance_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_tactical_siege_end_to_end_conquest() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	get_tree().root.add_child(screen)
	screen.host = host

	# 1. Trigger tactical breach operation
	screen.siege_panel.tactical_siege_initiated.emit()

	var siege: TacticalSiegeResolver = screen.tactical_siege
	assert_object(siege).is_not_null()
	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.IN_PROGRESS)

	# Grant a strong vanguard army for the assault
	siege.initial_army_power = 120
	siege.current_army_power = 120

	# 2. Battle through Phase 1: Outer Gate (Safe archery suppression)
	var safety_loop := 0
	while siege.current_phase == TacticalSiegeResolver.Phase.OUTER_GATE and safety_loop < 30:
		safety_loop += 1
		screen.tactical_view.tactic_selected.emit(&"archer_suppression")

	assert_int(siege.current_phase).is_equal(TacticalSiegeResolver.Phase.COURTYARD)

	# 3. Battle through Phase 2: Courtyard (Shield wall formation)
	safety_loop = 0
	while siege.current_phase == TacticalSiegeResolver.Phase.COURTYARD and safety_loop < 30:
		safety_loop += 1
		screen.tactical_view.tactic_selected.emit(&"shield_wall")

	assert_int(siege.current_phase).is_equal(TacticalSiegeResolver.Phase.KEEP)

	# 4. Battle through Phase 3: The Keep (Decisive storm or demand surrender)
	safety_loop = 0
	while siege.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS and safety_loop < 30:
		safety_loop += 1
		if siege.phase_defender_hp <= int(round(siege.phase_defender_max_hp * 0.40)):
			screen.tactical_view.tactic_selected.emit(&"demand_surrender")
		else:
			screen.tactical_view.tactic_selected.emit(&"decisive_storm")

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.VICTORY)
	assert_bool(screen.event_ticker_label.text.contains("Chronicle")).is_true()

	get_tree().root.remove_child(screen)
	screen.free()


func test_tactical_siege_retreat_preserves_conspirators() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	get_tree().root.add_child(screen)
	screen.host = host

	# Trigger tactical breach operation
	screen.siege_panel.tactical_siege_initiated.emit()
	var siege: TacticalSiegeResolver = screen.tactical_siege
	siege.current_army_power = 80

	# Execute a round of archer suppression (safe)
	screen.tactical_view.tactic_selected.emit(&"archer_suppression")
	var power_before_retreat: int = siege.current_army_power

	# Signal retreat
	screen.tactical_view.retreat_requested.emit()

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.RETREATED)
	assert_int(siege.current_army_power).is_equal(power_before_retreat)
	assert_bool(screen.event_ticker_label.text.to_lower().contains("retreat")).is_true()

	get_tree().root.remove_child(screen)
	screen.free()


func test_tactical_siege_defeat_when_forces_routed() -> void:
	var host := _fresh_host()
	var screen := GameplayScreen.new()
	get_tree().root.add_child(screen)
	screen.host = host

	# Trigger tactical breach operation
	screen.siege_panel.tactical_siege_initiated.emit()
	var siege: TacticalSiegeResolver = screen.tactical_siege

	# Force army power down to 0
	siege.current_army_power = 0
	screen.tactical_view.tactic_selected.emit(&"ram_charge")

	assert_int(siege.status).is_equal(TacticalSiegeResolver.SiegeStatus.REPELLED)
	assert_bool(screen.event_ticker_label.text.to_lower().contains("repelled")).is_true()

	get_tree().root.remove_child(screen)
	screen.free()
