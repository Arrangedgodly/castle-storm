## Unit tests for the boot shell (the front door fix) — the post-
## acceptance lane.
##
## Pins ui/main.gd (test-mapping rule): the ROUTE TABLE (fresh / live
## run / ended meta), the title card's affordances per route (one BEGIN
## vs CONTINUE primary + NEW RUN secondary, seeded focus, full grips,
## the pad's primary fallback), CONTINUE restoring the EXACT run state
## (engine state_hash equality: the load vs the pre-exit save, and the
## foreground-resolved state vs a twin host resolving the same window),
## the NEW-RUN TWO-STEP CONFIRM (the first press only arms; the second
## banks the hand through the REAL run_abort — chronicle "aborted",
## meta banked — then deals the new hand through the intro's restart),
## and the spread mounted from boot matching the STANDALONE mount's
## rendered layout hash (the screen's external-mount contract).
extends GdUnitTestSuite

const MAIN_SCENE := "res://ui/main.tscn"
const MainShell := preload("res://ui/main.gd")
const SpreadScene := preload("res://ui/screens/spread/spread_screen.tscn")
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")

## A synthetic platform epoch for the away-window seams (never the OS clock).
const T0 := 1_800_000_000

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_boot_tests")
	get_window().size = Vector2i(720, 720)


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
	for file_name in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _scratch() -> String:
	_dir_seq += 1
	var root := "user://cs_boot_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	return root


## A host that played `hours` sim hours of its (only) run and saved both
## domains at the background boundary (anchor T0).
func _played_host(root: String, hours: int, seed_value := 20261103) -> GameHost:
	var host := GameHost.new(seed_value, root)
	host.autosave_interval_ticks = 0  # tests never touch the disk cadence
	host.boot(0)
	if hours > 0:
		host.fast_forward(hours * SimEngine.TICKS_PER_SIM_HOUR)
	return host


func _mounted_shell(root: String) -> MainShell:
	var shell := (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	shell.save_root = root
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame
	return shell


## Retire a mounted shell before the test ends: the free FLUSHES (two
## frames) so no screen outlives the case (the orphan discipline).
func _retire(shell: MainShell) -> void:
	if shell == null or not is_instance_valid(shell):
		return
	shell.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


# --- the route table (pure) -------------------------------------------------------------


func test_route_table_covers_fresh_live_and_ended_sessions() -> void:
	# Fresh install: nothing loaded, nothing recorded.
	assert_str(String(MainShell.route_for(false, false, 0))).is_equal(
		String(MainShell.ROUTE_BEGIN_FRESH))
	# Live run save: CONTINUE.
	assert_str(String(MainShell.route_for(true, true, 1))).is_equal(
		String(MainShell.ROUTE_CONTINUE))
	assert_str(String(MainShell.route_for(true, true, 7))).is_equal(
		String(MainShell.ROUTE_CONTINUE))
	# Meta exists, run ended: the cleared-table BEGIN.
	assert_str(String(MainShell.route_for(true, false, 1))).is_equal(
		String(MainShell.ROUTE_BEGIN_NEXT))
	# A save that loads but never recorded a run (edge) still BEGINS fresh.
	assert_str(String(MainShell.route_for(true, false, 0))).is_equal(
		String(MainShell.ROUTE_BEGIN_FRESH))


func test_entry_for_routes_the_spread_opening_correctly() -> void:
	# Fresh + continue let the spread's own boot rule decide (the first
	# deal reveal / the resumed check-in); the ended meta DEALS the next
	# hand through the intro's restart.
	assert_str(String(MainShell.entry_for(MainShell.ROUTE_BEGIN_FRESH))).is_equal(
		String(SpreadScreen.ENTRY_AUTO))
	assert_str(String(MainShell.entry_for(MainShell.ROUTE_CONTINUE))).is_equal(
		String(SpreadScreen.ENTRY_AUTO))
	assert_str(String(MainShell.entry_for(MainShell.ROUTE_BEGIN_NEXT))).is_equal(
		String(SpreadScreen.ENTRY_NEW_HAND))


# --- the title card per route -------------------------------------------------------------


func test_fresh_boot_mounts_the_title_card_with_a_single_begin() -> void:
	var shell: MainShell = await _mounted_shell(_scratch())
	assert_str(String(shell.route)).is_equal(String(MainShell.ROUTE_BEGIN_FRESH))
	assert_bool(shell._title_layer != null).is_true()
	assert_bool(shell._begin_chip != null).is_true()
	assert_bool(shell._continue_chip != null).is_false()
	assert_bool(shell._new_run_chip != null).is_false()
	# The letterpress name + one flavor line + seeded primary focus.
	assert_str(shell._card.get_child(0).get_child(0).text).is_equal("CASTLE STORM")
	assert_bool(not shell._flavor_label.text.is_empty()).is_true()
	assert_bool(shell.primary_chip() == shell._begin_chip).is_true()
	assert_bool(shell._begin_chip.has_focus()).is_true()
	# The chip's label is the copy deck's BEGIN (never a stub).
	assert_bool(shell._begin_chip._label.text == CopyDeck.line(
		Inks.pack().copy, &"title_begin", 0)).is_true()
	await _retire(shell)


func test_live_run_save_mounts_continue_primary_and_new_run_secondary() -> void:
	var root := _scratch()
	var played := _played_host(root, 5)
	played.background(T0)  # anchor + flush both domains
	var leader := played.run().leader_first_name()
	var shell: MainShell = await _mounted_shell(root)
	assert_str(String(shell.route)).is_equal(String(MainShell.ROUTE_CONTINUE))
	assert_bool(shell._continue_chip != null).is_true()
	assert_bool(shell._new_run_chip != null).is_true()
	assert_bool(shell._begin_chip == null).is_true()
	# CONTINUE is the seeded primary; the live-hand line names the leader.
	assert_bool(shell._continue_chip.has_focus()).is_true()
	assert_bool(String(shell._flavor_label.text).contains(leader)).is_true()
	# The two doors cycle focus between themselves (pad never escapes).
	assert_bool(shell._continue_chip.focus_neighbor_bottom
		== shell._new_run_chip.get_path()).is_true()
	assert_bool(shell._new_run_chip.focus_neighbor_bottom
		== shell._continue_chip.get_path()).is_true()
	await _retire(shell)


func test_ended_meta_boots_the_cleared_table_title_with_single_begin() -> void:
	var root := _scratch()
	var played := _played_host(root, 4)
	played.submit(&"run_abort")
	played.advance_ticks(1)
	assert_bool(played.save_all()).is_true()
	var shell: MainShell = await _mounted_shell(root)
	assert_str(String(shell.route)).is_equal(String(MainShell.ROUTE_BEGIN_NEXT))
	assert_bool(shell._begin_chip != null).is_true()
	assert_bool(shell._continue_chip == null).is_true()
	# The cleared table's flavor, not the fresh install's.
	assert_bool(shell._flavor_label.text == CopyDeck.line(
		Inks.pack().copy, &"title_flavor_return", 1)).is_true()
	await _retire(shell)


# --- the gestures: continue restores, new-run confirms -----------------------------------


func test_continue_restores_the_exact_run_state() -> void:
	var root := _scratch()
	var played := _played_host(root, 6)
	var pre_exit := played.engine.state_hash()
	var leader := played.run().leader_first_name()
	played.background(T0)  # save + anchor
	# Boot: the LOAD itself is exact (the pre-continue state == pre-exit).
	var shell: MainShell = await _mounted_shell(root)
	assert_int(shell.host.engine.state_hash()).is_equal(pre_exit)
	assert_str(shell.host.run().leader_first_name()).is_equal(leader)
	# CONTINUE = the foreground press: a 2h window resolves through the
	# real service, then the spread opens the resumed check-in. The disk
	# cadence stays off here so the TWIN below loads the T0-anchored save
	# (the autosave seams are the spread's own suites' business).
	shell.host.autosave_interval_ticks = 0
	var gap := 2 * 3600
	shell.injected_now_epoch = T0 + gap
	shell._continue_chip.pressed.emit()
	assert_bool(shell.spread != null).is_true()
	for i in 6:
		await get_tree().process_frame
	assert_int(shell.host.last_catch_up_report.get("applied_ticks", -1)) \
		.is_equal(2 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(shell.spread._intro.is_open()).is_true()
	assert_str(String(shell.spread._intro.view()["variant"])) \
		.is_equal(String("resumed"))
	# The resolved state is exactly a twin host's: same save, same window.
	var twin := GameHost.new(20261103, root)
	twin.autosave_interval_ticks = 0
	twin.boot(0)
	twin.foreground(T0 + gap)
	assert_int(shell.host.engine.state_hash()).is_equal(twin.engine.state_hash())
	await _retire(shell)


func test_new_run_two_step_confirm_banks_and_records_the_abandon() -> void:
	var root := _scratch()
	var played := _played_host(root, 5)
	var banked_before := played.meta.legacy_points
	played.background(T0)
	var shell: MainShell = await _mounted_shell(root)
	var chronicle_before := shell.host.meta.chronicle.size()
	# FIRST PRESS: arms only — the chip re-labels, the caution prints,
	# the hand is untouched (one mispress never ends a run).
	shell._new_run_chip.pressed.emit()
	assert_bool(shell.spread == null).is_true()
	assert_bool(shell.host.is_run_running()).is_true()
	assert_int(shell.host.meta.chronicle.size()).is_equal(chronicle_before)
	assert_bool(shell._caution_label.visible).is_true()
	assert_bool(not shell._caution_label.text.is_empty()).is_true()
	assert_bool(shell._new_run_chip._label.text == CopyDeck.line(
		Inks.pack().copy, &"title_new_run_armed", 0)).is_true()
	# SECOND PRESS: the REAL run_abort — chronicle "aborted", the bank
	# grows by the banked score, the save flushes, the new hand deals.
	shell.injected_now_epoch = T0 + 60
	var running_engine := shell.host.engine
	shell._new_run_chip.pressed.emit()
	assert_bool(not shell.host.is_run_running()).is_true()
	assert_int(shell.host.meta.chronicle.size()).is_equal(chronicle_before + 1)
	var entry: Dictionary = shell.host.meta.chronicle[chronicle_before]
	assert_str(String(entry["outcome"])).is_equal("aborted")
	assert_int(shell.host.meta.legacy_points - banked_before) \
		.is_equal(int(entry["score"]))
	assert_bool(shell.host.save_manager.load_meta() != null).is_true()
	# The spread mounts the NEW HAND: the intro derives the loss-restart
	# variant from the chronicle and restarts the run itself.
	assert_bool(shell.spread != null).is_true()
	assert_str(String(shell.spread.entry_mode)).is_equal(
		String(SpreadScreen.ENTRY_NEW_HAND))
	for i in 6:
		await get_tree().process_frame
	assert_bool(shell.spread._intro.is_open()).is_true()
	assert_str(String(shell.spread._intro.view()["variant"])) \
		.is_equal(String("loss_restart"))
	assert_bool(shell.host.is_run_running()).is_true()
	assert_bool(running_engine == shell.host.engine).is_true()
	await _retire(shell)


func test_ended_meta_begin_deals_the_new_hand_under_the_ruling_regime() -> void:
	var root := _scratch()
	var played := _played_host(root, 4)
	var regime := played.run().regime_id()
	played.submit(&"run_abort")
	played.advance_ticks(1)
	assert_bool(played.save_all()).is_true()
	var shell: MainShell = await _mounted_shell(root)
	shell._begin_chip.pressed.emit()
	assert_bool(shell.spread != null).is_true()
	assert_str(String(shell.spread.entry_mode)).is_equal(
		String(SpreadScreen.ENTRY_NEW_HAND))
	for i in 6:
		await get_tree().process_frame
	# The intro derived the restart from the ACTUAL chronicle and dealt
	# the new hand (the defeat-keeps rule: the same regime).
	assert_bool(shell.spread._intro.is_open()).is_true()
	assert_str(String(shell.spread._intro.view()["variant"])) \
		.is_equal(String("loss_restart"))
	assert_bool(shell.host.is_run_running()).is_true()
	assert_str(String(shell.host.run().regime_id())).is_equal(String(regime))
	await _retire(shell)


# --- input parity + the standalone equivalence -------------------------------------------


func test_title_parity_three_routes_one_gesture_every_mode() -> void:
	# FRESH: the primary chip is a full-grip BaseButton with seeded
	# focus; the pad's primary action (NOT ui_accept) activates it.
	var fresh: MainShell = await _mounted_shell(_scratch())
	var chip := fresh.primary_chip()
	assert_bool(chip is BaseButton).is_true()
	assert_int(int(chip.custom_minimum_size.y)).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_bool(chip.focus_mode != Control.FOCUS_NONE).is_true()
	var pad := InputEventAction.new()
	pad.action = &"primary"
	pad.pressed = true
	fresh._unhandled_input(pad)
	assert_bool(fresh.spread != null).is_true()
	# Each shell is retired before the next mounts — one screen owns
	# focus at a time (the spread's intro seeds its own chip).
	await _retire(fresh)

	# LIVE RUN: same floor for both doors, and the pad press CONTINUES.
	var root := _scratch()
	var played := _played_host(root, 3)
	played.background(T0)
	var live: MainShell = await _mounted_shell(root)
	assert_int(int(live._continue_chip.custom_minimum_size.y)) \
		.is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_int(int(live._new_run_chip.custom_minimum_size.y)) \
		.is_greater_equal(Inks.TOUCH_GRIP_MIN)
	live.injected_now_epoch = T0 + 60
	live._unhandled_input(pad.duplicate())
	assert_bool(live.spread != null).is_true()
	await _retire(live)

	# ENDED META: the same single-gesture floor as fresh.
	var ended_root := _scratch()
	var ended_played := _played_host(ended_root, 2)
	ended_played.submit(&"run_abort")
	ended_played.advance_ticks(1)
	assert_bool(ended_played.save_all()).is_true()
	var ended: MainShell = await _mounted_shell(ended_root)
	var ended_chip := ended.primary_chip()
	assert_int(int(ended_chip.custom_minimum_size.y)) \
		.is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_bool(ended_chip.has_focus()).is_true()
	ended._unhandled_input(pad.duplicate())
	assert_bool(ended.spread != null).is_true()
	await _retire(ended)


func test_spread_from_boot_renders_like_the_standalone_mount() -> void:
	# The screen's external-mount contract (host attached before the
	# tree): mounted through the shell, the first bind renders the same
	# layout as the standalone mount of an identically-booted host.
	get_window().size = Vector2i(1280, 800)
	await get_tree().process_frame
	await get_tree().process_frame

	var standalone := SpreadScene.instantiate()
	var standalone_host := GameHost.new(20261103, _scratch())
	standalone_host.autosave_interval_ticks = 0
	standalone_host.boot(0)
	standalone.host = standalone_host
	get_tree().root.add_child(standalone)
	for i in 4:
		await get_tree().process_frame

	var shell: MainShell = await _mounted_shell(_scratch())
	shell._begin_chip.pressed.emit()
	for i in 4:
		await get_tree().process_frame

	var solo := standalone.get_active_slot() as OrientationSlot
	var booted := shell.spread.get_active_slot() as OrientationSlot
	assert_bool(solo != null and booted != null).is_true()
	assert_int(shell.spread.layout_hash(booted)) \
		.is_equal(standalone.layout_hash(solo))
	# The same view, not just the same table shape.
	assert_int(shell.spread.stats[&"view_builds"]).is_greater_equal(1)
	assert_bool(shell.spread._intro.is_open()).is_true()
	assert_bool(standalone._intro.is_open()).is_true()
	assert_str(String(shell.spread._intro.view()["leader"]["name"])) \
		.is_equal(String(standalone._intro.view()["leader"]["name"]))
