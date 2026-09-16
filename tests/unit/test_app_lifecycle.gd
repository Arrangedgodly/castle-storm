## Unit tests for AppLifecycle (T-PERF-01) — Thor lane.
##
## Mirrors ui/host/app_lifecycle.gd (test-mapping rule). The lifecycle
## layer is the platform boundary policy: OS notifications (simulated
## headlessly — handle_notification() called directly with injected UTC
## epochs, no windowing system) map onto the GameHost's
## background/foreground seams with docs/catch-up.md §2 semantics:
##   - mobile PAUSED backgrounds: pacing gate closes, anchor taken, the
##     boundary autosave flushes to disk;
##   - RESUMED foregrounds: the away window resolves EXACTLY (twin parity
##     on the determinism oracle), pacing reopens;
##   - desktop focus loss keeps the world running (the decision of record)
##     unless the host opts in;
##   - both edges idempotent: no anchor stretch, no double resolution;
##   - the lifecycle core reads no clock (the security-policy inventory:
##     only the node seam injects "now").
extends GdUnitTestSuite

const RUN_SEED := 20261103

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_lifecycle_tests")


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


func _fresh_host() -> GameHost:
	_dir_seq += 1
	var root := "user://cs_lifecycle_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(RUN_SEED, root)
	host.boot(0)
	return host


func _lifecycle(host: GameHost, desktop_backgrounds := false) -> AppLifecycle:
	var policy := AppLifecycle.new()
	policy.host = host
	policy.desktop_backgrounds_on_focus_loss = desktop_backgrounds
	return policy


# --- the background edge ---------------------------------------------------------------


func test_paused_notification_backgrounds_pauses_pacing_and_flushes_a_save() -> void:
	var host := _fresh_host()
	host.advance_ticks(60)
	var policy := _lifecycle(host)
	var action := policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 2000)
	assert_str(String(action)).is_equal("backgrounded")
	assert_bool(policy.backgrounded).is_true()
	assert_bool(host.driving).is_false()  # the pacing gate closed
	# The autosave-on-background fired: BOTH domains are on disk, and the
	# saved anchor is exactly the boundary's injected epoch.
	var probe := GameHost.new(RUN_SEED, host.save_manager.root_dir)
	assert_bool(probe.boot(0)).is_true()  # a run save existed to load
	assert_int(probe.meta.last_seen_epoch).is_equal(2000)
	assert_int(probe.engine.tick_count).is_equal(host.engine.tick_count)


func test_window_close_flushes_the_boundary_save() -> void:
	var host := _fresh_host()
	var policy := _lifecycle(host)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_WM_CLOSE_REQUEST, 9000))).is_equal("backgrounded")
	assert_bool(policy.backgrounded).is_true()
	var probe := GameHost.new(RUN_SEED, host.save_manager.root_dir)
	probe.boot(0)
	assert_int(probe.meta.last_seen_epoch).is_equal(9000)


# --- the pacing gate --------------------------------------------------------------------


func test_sim_never_ticks_while_backgrounded_and_gate_reopens_on_resume() -> void:
	var host := _fresh_host()
	host.advance_ticks(30)
	var policy := _lifecycle(host)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 5000)
	var frozen_tick: int = host.engine.tick_count
	var frozen_hash: int = host.engine.state_hash()
	# Pump "frames" while hidden: huge deltas, direct tick calls — nothing
	# moves. advance_ticks is gated on driving too (the live paths), and on
	# mobile the suspended process could not have run anything anyway.
	assert_int(host.advance(3600.0)).is_zero()
	assert_int(host.advance(3600.0)).is_zero()
	assert_int(host.advance_ticks(10)).is_zero()
	assert_int(host.engine.tick_count).is_equal(frozen_tick)
	assert_int(host.engine.state_hash()).is_equal(frozen_hash)
	# Resume 2h later: exactly 120 ticks through the catch-up, then the
	# gate is open again for live pacing.
	var reports: Array[Dictionary] = []
	host.catch_up_resolved.connect(func(report: Dictionary) -> void: reports.append(report))
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_RESUMED, 5000 + 2 * 3600))).is_equal("foregrounded")
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(120)
	assert_int(host.engine.tick_count).is_equal(frozen_tick + 120)
	assert_bool(host.driving).is_true()
	assert_int(host.advance(60.0)).is_equal(1)  # the gate reopened
	assert_int(reports.size()).is_equal(1)


# --- catch-up exactness -------------------------------------------------------------------


func test_foreground_resolves_exactly_the_away_window() -> void:
	var host := _fresh_host()
	var twin := _fresh_host()
	host.advance_ticks(37)
	twin.advance_ticks(37)
	var policy := _lifecycle(host)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 2000)
	# 7h30m away -> exactly 450 ticks, replayed through the real engine:
	# the lived host lands bit-identical to a twin that simply ran them.
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 2000 + 7 * 3600 + 30 * 60)
	twin.fast_forward(450)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(450)
	assert_int(host.engine.tick_count).is_equal(twin.engine.tick_count)
	assert_int(host.engine.state_hash()).is_equal(twin.engine.state_hash())


func test_away_windows_exact_across_three_cycles() -> void:
	var host := _fresh_host()
	var policy := _lifecycle(host)
	var tick_base: int = host.engine.tick_count
	# Cycle 1: one clean hour.
	host.advance_ticks(5)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 10_000)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 10_000 + 3600)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(60)
	# Cycle 2: seven hours.
	host.advance_ticks(5)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 20_000)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 20_000 + 7 * 3600)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(420)
	# Cycle 3: a sub-tick window — 59 seconds apply nothing, the remainder
	# is discarded, the anchor snaps to now (docs/catch-up.md §1).
	var resolves := [0]  # lambdas capture by VALUE — counters ride arrays
	host.catch_up_resolved.connect(func(_report: Dictionary) -> void: resolves[0] += 1)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 30_000)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 30_000 + 59)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_zero()
	assert_int(host.meta.last_seen_epoch).is_equal(30_000 + 59)
	assert_int(resolves[0]).is_zero()  # a nothing-happened foreground stays silent
	# Each window resolved exactly its own gap: nothing bled across cycles.
	assert_int(host.engine.tick_count - tick_base).is_equal(5 + 60 + 5 + 420)


func test_anchor_is_the_background_moment_not_sim_progress() -> void:
	## The ordering contract (T-PERF-01): mark_seen lands at the platform
	## moment the session left — sim progress before the boundary never
	## bleeds into the anchor, and the window opens exactly at the epoch the
	## OS notification carried.
	var host := _fresh_host()
	host.advance_ticks(130)  # 2h10m of sim before the boundary
	assert_int(host.meta.last_seen_epoch).is_zero()  # playing never marks
	var policy := _lifecycle(host)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 5000)
	assert_int(host.meta.last_seen_epoch).is_equal(5000)
	# ...and the window measures from that moment: +10 minutes = 10 ticks,
	# neither the 130 pre-boundary ticks nor any hidden-time guess involved.
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 5000 + 600)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(10)


# --- idempotency ----------------------------------------------------------------------------


func test_double_cycles_are_idempotent_no_double_resolution() -> void:
	var host := _fresh_host()
	var twin := _fresh_host()
	host.advance_ticks(11)
	twin.advance_ticks(11)
	var policy := _lifecycle(host)
	var resolves := [0]  # lambdas capture by VALUE — counters ride arrays
	host.catch_up_resolved.connect(func(_report: Dictionary) -> void: resolves[0] += 1)
	# A second PAUSED with a LATER epoch must not stretch the window: the
	# anchor stays at the first boundary (mobile never re-pauses, but the
	# surface must be safe against duplicate notifications).
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 4000)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 4000 + 999)
	assert_int(policy.background_count).is_equal(1)
	assert_int(host.meta.last_seen_epoch).is_equal(4000)
	# Triple foreground (RESUMED + stray FOCUS_IN + RESUMED again): one
	# resolution only — the twin ran the window exactly once.
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 4000 + 1800)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN, 4000 + 1800)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 4000 + 1800)
	assert_int(policy.foreground_count).is_equal(1)
	assert_int(resolves[0]).is_equal(1)
	twin.fast_forward(30)  # 1800s = 30 ticks, applied once
	assert_int(host.engine.state_hash()).is_equal(twin.engine.state_hash())
	assert_int(host.engine.tick_count).is_equal(twin.engine.tick_count)


func test_paused_engine_freezes_through_the_boundary() -> void:
	## The in-app pause is a WORLD FREEZE, not away time (catch-up.md §2):
	## a player who froze the world and hid the app accrues nothing on
	## return — the boundary must not force the frozen engine forward.
	var host := _fresh_host()
	var policy := _lifecycle(host)
	host.engine.pause()
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 2000)
	var resolves := [0]  # lambdas capture by VALUE — counters ride arrays
	host.catch_up_resolved.connect(func(_report: Dictionary) -> void: resolves[0] += 1)
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, 2000 + 8 * 3600)
	assert_bool(bool(host.last_catch_up_report["skipped_paused"])).is_true()
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_zero()
	assert_int(resolves[0]).is_zero()
	host.engine.resume()
	assert_int(host.advance_ticks(10)).is_equal(10)  # alive after the freeze


# --- the desktop focus decision ----------------------------------------------------------


func test_desktop_focus_loss_keeps_running_by_default() -> void:
	## The DECISION OF RECORD: an unfocused desktop window keeps pacing —
	## the idle game keeps making progress while tabbed away, the anchor is
	## NOT taken (the session never stopped, nothing is owed on return).
	var host := _fresh_host()
	var policy := _lifecycle(host)  # desktop_backgrounds_on_focus_loss = false
	var resolves := [0]  # lambdas capture by VALUE — counters ride arrays
	host.catch_up_resolved.connect(func(_report: Dictionary) -> void: resolves[0] += 1)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_FOCUS_OUT, 7000))).is_equal("ignored")
	assert_bool(policy.backgrounded).is_false()
	assert_bool(host.driving).is_true()
	assert_int(host.meta.last_seen_epoch).is_zero()  # no premature anchor
	assert_int(host.advance(600.0)).is_equal(10)  # the world kept pacing
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_FOCUS_IN, 7600))).is_equal("ignored")
	assert_int(resolves[0]).is_zero()  # nothing to resolve: it never left
	assert_bool(policy.backgrounded).is_false()


func test_desktop_focus_policy_backgrounds_when_opted_in() -> void:
	var host := _fresh_host()
	var policy := _lifecycle(host, true)  # the opt-in (kiosk/battery builds)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_FOCUS_OUT, 3000))).is_equal("backgrounded")
	assert_bool(policy.backgrounded).is_true()
	assert_bool(host.driving).is_false()
	assert_int(host.advance(600.0)).is_zero()
	assert_int(host.meta.last_seen_epoch).is_equal(3000)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_FOCUS_IN, 3000 + 600))).is_equal("foregrounded")
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(10)
	assert_bool(host.driving).is_true()


func test_focus_in_foregrounds_a_paused_platform_window_even_unopted() -> void:
	## Android orderings deliver FOCUS_IN around RESUMED; if the window is
	## genuinely open again (a PAUSED preceded), the focus edge may close
	## it — whichever edge arrives first wins, the latch absorbs the other.
	var host := _fresh_host()
	var policy := _lifecycle(host)  # default desktop policy
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 2000)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_FOCUS_IN, 2000 + 120))).is_equal("foregrounded")
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(2)
	assert_str(String(policy.handle_notification(
		Node.NOTIFICATION_APPLICATION_RESUMED, 2000 + 120))).is_equal("ignored")


# --- safety / discipline ---------------------------------------------------------------------


func test_notifications_before_host_assignment_are_ignored() -> void:
	var policy := AppLifecycle.new()
	assert_str(String(policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, 1))).is_equal("ignored")
	assert_bool(policy.backgrounded).is_false()
	assert_int(policy.background_count).is_zero()


func test_unknown_notifications_are_ignored() -> void:
	var host := _fresh_host()
	var policy := _lifecycle(host)
	assert_str(String(policy.handle_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST, 1))).is_equal("ignored")
	assert_str(String(policy.handle_notification(Node.NOTIFICATION_PAUSED, 1))).is_equal("ignored")
	assert_bool(policy.backgrounded).is_false()
	assert_int(policy.background_count).is_zero()
	assert_bool(host.driving).is_true()


func test_lifecycle_core_reads_no_clock() -> void:
	## The security-policy clock inventory: AppLifecycle is the POLICY, not
	## the platform clock — timestamps arrive injected (the node seam in
	## spread_screen.gd owns the one permitted read). Comment-stripped
	## scan, the test_game_host pattern.
	var source := FileAccess.get_file_as_string("res://ui/host/app_lifecycle.gd")
	var stripped := source.replace("\n#", "\n").replace("\t#", "\t")
	for banned in ["OS.", "Time.get_unix", "Time.get_system", "Time.get_ticks", "SceneTreeTimer"]:
		var at := stripped.find(banned)
		assert_int(at).is_equal(-1)
