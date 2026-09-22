## Unit tests for Roguelite Cycle, Legacy Points & Enemy Escalation (CY-01).
extends GdUnitTestSuite

const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_cycle_tests")


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
	var root := "user://cs_cycle_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.boot(0)
	return host


func test_tactical_siege_victory_awards_legacy_and_captures_garrison() -> void:
	var host := _fresh_host(42)
	var engine := host.engine
	var initial_points: int = host.meta.legacy_points
	assert_int(initial_points).is_equal(0)
	assert_int(host.meta.escalation_cycle).is_equal(0)
	assert_bool(host.meta.escalation_garrison.is_empty()).is_true()

	var resolver := TacticalSiegeResolver.new(engine)
	resolver.start_siege(engine)
	resolver.initial_army_power = 100
	resolver.current_army_power = 100

	# Phase 0: Outer Gate
	var safety_loop := 0
	while resolver.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS and resolver.current_phase == TacticalSiegeResolver.Phase.OUTER_GATE and safety_loop < 30:
		safety_loop += 1
		resolver.execute_tactic(&"archer_suppression")

	assert_int(resolver.current_phase).is_equal(TacticalSiegeResolver.Phase.COURTYARD)

	# Phase 1: Courtyard
	safety_loop = 0
	while resolver.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS and resolver.current_phase == TacticalSiegeResolver.Phase.COURTYARD and safety_loop < 30:
		safety_loop += 1
		resolver.execute_tactic(&"shield_wall")

	assert_int(resolver.current_phase).is_equal(TacticalSiegeResolver.Phase.KEEP)

	# Phase 2: Keep -> Victory
	safety_loop = 0
	while resolver.status == TacticalSiegeResolver.SiegeStatus.IN_PROGRESS and resolver.current_phase == TacticalSiegeResolver.Phase.KEEP and safety_loop < 30:
		safety_loop += 1
		resolver.execute_tactic(&"decisive_storm")

	assert_int(resolver.status).is_equal(TacticalSiegeResolver.SiegeStatus.VICTORY)

	# Verify climax summary
	var summary: Dictionary = resolver.get_climax_summary()
	assert_str(summary.get("outcome", "")).is_equal("victory")
	assert_int(int(summary.get("status", 0))).is_equal(TacticalSiegeResolver.SiegeStatus.VICTORY)

	# Legacy points must have been awarded to meta bank (> 100 due to WIN_BONUS)
	assert_int(host.meta.legacy_points).is_greater(100)
	assert_int(int(summary.get("banked_legacy_points", 0))).is_equal(host.meta.legacy_points)

	# Run state should be marked ended
	var run = engine.get_system(&"run")
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_VICTORY)


func test_tactical_siege_defeat_when_forces_routed_banks_consolation_points() -> void:
	var host := _fresh_host(999)
	var engine := host.engine

	# Advance 2 hours so the run registers non-zero duration score
	host.advance_ticks(120)

	var resolver := TacticalSiegeResolver.new(engine)
	resolver.start_siege(engine)

	# Manually deplete army to 0 to simulate total battlefield wipeout
	resolver.current_army_power = 1
	resolver._apply_army_loss(1)
	assert_int(resolver.current_army_power).is_equal(0)

	# Execute tactic to trigger defeat check
	resolver.execute_tactic(&"ram_charge")

	assert_int(resolver.status).is_equal(TacticalSiegeResolver.SiegeStatus.REPELLED)

	var summary: Dictionary = resolver.get_climax_summary()
	assert_str(summary.get("outcome", "")).is_equal("repelled")

	# Run lifecycle should be ended with defeat
	var run = engine.get_system(&"run")
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_DEFEAT)

	# Failure banks consolation points
	assert_int(host.meta.legacy_points).is_greater(0)


func test_restarting_run_preserves_meta_and_derives_next_cycle_garrison() -> void:
	var host := _fresh_host(777)
	var engine := host.engine

	# Setup an escalation snapshot in meta
	host.meta.legacy_points = 250
	host.meta.escalation_cycle = 1
	host.meta.escalation_garrison = {
		"regime_id": "gilded_crown",
		"captured_at_run": 1,
		"cycle": 1,
		"leader": "Sir Valerius the Bold",
		"crest_id": "crest_gilded_crown",
		"roster": {
			"knight": {"count": 4, "gear_tiers": {}}
		}
	}

	# Check assault odds against this captured garrison
	var assault = engine.get_system(&"assault")
	var odds: Dictionary = assault.assault_odds(engine)
	var garrison: Dictionary = odds.get("garrison", {})
	assert_int(int(garrison.get("escalation_cycle", 0))).is_equal(1)
	assert_str(str(garrison.get("leader", ""))).is_equal("Sir Valerius the Bold")

	# Restart run
	host.restart_run()
	host.advance_ticks(1)

	# Verify meta domain survived intact
	assert_int(host.meta.legacy_points).is_equal(250)
	assert_int(host.meta.escalation_cycle).is_equal(1)
	assert_str(str(host.meta.escalation_garrison.get("leader", ""))).is_equal("Sir Valerius the Bold")

	# And new run is fresh running
	assert_bool(host.is_run_running()).is_true()
