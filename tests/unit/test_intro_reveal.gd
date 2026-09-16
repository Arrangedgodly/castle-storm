## Unit tests for the leader intro / restart reveal (T-UI-05) —
## Daredevil lane.
##
## Mirrors ui/screens/intro/ + the spread seams. What is pinned:
##   - THE PRESENTER: the reveal is DATA-DRIVEN from the run lifecycle
##     (leader name/epithet/tags/regime == the sim's read APIs, exactly),
##     the chronicle CONTEXT reads the ACTUAL previous run's chronicle
##     entry (win-restart: the regime-swap beat referencing both regime
##     names + the banked-legacy line + the previous leader's line;
##     loss-restart: the SAME regime + "the regime remembers"; first run:
##     fresh copy, no bank), abort folds into the loss variant, the view
##     hash is deterministic per seed;
##   - THE SCREEN: a fresh boot opens the FIRST HAND focused on the ONE
##     GESTURE (>= 48 grip), a resumed session does NOT re-deal, the one
##     gesture works from ALL THREE input modes and unfolds to the
##     spread in <= MAX_INTERACTIONS (the honest count: exactly 1),
##     reduced motion lands synchronously, full motion completes inside
##     the 1-3s band;
##   - THE SEAMS: the assault's finished("win") mounts the win restart
##     (the new leader REALLY dealt — run 2 running under the redrawn
##     regime), a run lost by failure mounts the loss restart under the
##     SAME regime with the crushing beat still printed beneath;
##   - LAYOUT: the pure reveal rects are inside bounds at five sizes,
##     the regime card is strictly larger than the leader card
##     (Major-Arcana scale), and the mounted reveal is unclipped at the
##     four common sizes with focus never stranded.
##
## WAITING STRATEGY (T-UI-05 fix round — the harness budget): the unfold
## is a PURE function of t advanced by IntroPacket._process(delta), so
## the full-motion test steps the packet's own clock directly with
## synthesized authored-duration strides (never the wall clock); the
## remaining frame waits are state-settle polls of a handful of frames
## each (the orientation-dwell loop is frame-bound by the router's
## hysteresis, not by timers), and the win-seam watch runs under reduced
## motion by design (the paced vignette path is T-UI-07 suite's, under
## ITS injected clock).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const IntroScreenScript := preload("res://ui/screens/intro/intro_screen.gd")

## Probed deterministic floor-assault outcome (2 t1 knights, power 30):
## 20261207 WINS (the T-UI-07 probe — re-probe if content moves).
const WIN_SEED := 20261207

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]
const EXPECTED_PORTRAIT := [true, false, false, true]

var _dir_seq := 0


func after() -> void:
	MotionProfile.forced = -1
	_erase_dir("user://cs_ui05_tests")
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
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _test_host(run_seed: int = 20261103) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_ui05_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


## One host holding `count` fully-geared, promoted knights (t1 kit) —
## the deterministic above-floor army (the assault suite's recipe).
func _knight_host(run_seed: int, count: int) -> GameHost:
	var host := _test_host(run_seed)
	var knights: Array[int] = []
	while knights.size() < count:
		while host.units().pending_offers() == 0:
			host.fast_forward(30)
		host.submit(&"recruit_accept", &"", host.units().offer_ids()[0])
		host.fast_forward(10)
		var idle := host.units().idle_units(host.units().base_unit_id())
		host.submit(&"assign_role", &"militia", idle[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		host.submit(&"start_training", &"trainee", host.units().idle_units(&"militia")[0])
		host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
		var trainee := host.units().idle_units(&"trainee")[0]
		host.submit(&"start_training", &"knight", trainee)
		host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
		knights.append(trainee)
	host.engine.set_resource(&"food", 500)
	host.engine.set_resource(&"timber", 500)
	host.engine.set_resource(&"iron", 500)
	for uid in knights:
		for slot in host.units().missing_gear_slots(uid):
			host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
	host.fast_forward(5)
	for uid in knights:
		if host.units().is_awaiting_promotion(uid) and host.units().missing_gear_slots(uid).is_empty():
			host.submit(&"promote", &"", uid)
	host.fast_forward(5)
	return host


# --- input event helpers ---------------------------------------------------------------


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _enter_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	return key


func _screen_touch() -> InputEventScreenTouch:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(360, 360)
	return touch


# --- presenter: the identity is the sim's own -----------------------------------------------


func test_first_run_view_reads_the_actual_identity() -> void:
	var host := _test_host()
	var view := IntroPresenter.reveal_view(host)
	assert_str(String(view["variant"])).is_equal(String(IntroPresenter.VARIANT_FIRST_RUN))
	assert_int(int(view["run_number"])).is_equal(1)
	# The leader plates are the sim's read APIs, verbatim.
	var leader: Dictionary = view["leader"]
	assert_str(String(leader["name"])).is_equal(host.run().leader_name())
	assert_str(String(leader["epithet"])).is_equal(host.run().leader_epithet())
	assert_int((leader["tags"] as Array).size()).is_equal(host.run().leader_tags().size())
	for i in (leader["tags"] as Array).size():
		assert_str(String((leader["tags"] as Array)[i])).is_equal(String(host.run().leader_tags()[i]))
	assert_str(String(leader["trait"])).is_equal(host.run().leader_trait_label())
	# The regime face card is the drawn regime, whole.
	var regime: Dictionary = view["regime"]
	assert_str(String(regime["id"])).is_equal(String(host.run().regime_id()))
	assert_str(String(regime["name"])).is_equal(Inks.regime_name(host.run().regime_id()))
	# The leader's face: the pack's base-unit face (a peasant begins).
	var base_face := &""
	for def: UnitDef in Inks.pack().units:
		if def.id == host.units().base_unit_id():
			base_face = def.face_id
	assert_str(String(leader["face_key"])).is_equal(String(base_face))


func test_first_run_lines_are_fresh_copy_no_bank() -> void:
	var host := _test_host()
	var view := IntroPresenter.reveal_view(host)
	var lines: Array = view["lines"]
	assert_int(lines.size()).is_equal(3)
	var joined := ""
	for line: Dictionary in lines:
		joined += String(line["text"]) + " "
	# Fresh copy: the regime named, the leader's marks printed, no bank
	# line (there is nothing banked and no previous hand to remember).
	assert_bool(joined.contains(String(view["regime"]["name"]))).is_true()
	assert_bool(joined.contains(String((view["leader"]["tags"] as Array)[0]))).is_true()
	assert_bool(joined.contains("bank")).is_false()
	assert_bool((view["previous"] as Dictionary).is_empty()).is_true()


# --- presenter: the restart variants ---------------------------------------------------------


func _win_a_hand(host: GameHost) -> void:
	## Ends the running hand as a VICTORY through the real resolution verb
	## (some hours in so duration/score are non-trivial), then deals the
	## next hand exactly as the intro screen does.
	host.fast_forward(10 * SimEngine.TICKS_PER_SIM_HOUR)
	host.submit(&"resolve_victory", &"win", 30)
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)


func test_win_restart_swap_beat_reads_the_actual_chronicle() -> void:
	var host := _test_host()
	var previous_regime := host.run().regime_id()
	var previous_leader := host.run().leader_name()
	_win_a_hand(host)
	var view := IntroPresenter.reveal_view(host)
	assert_str(String(view["variant"])).is_equal(String(IntroPresenter.VARIANT_WIN_RESTART))
	assert_int(int(view["run_number"])).is_equal(2)
	# The regime card is the NEWLY DRAWN regime (the sim's victory rule),
	# and the leader plates are the NEW identity.
	assert_str(String(view["regime"]["id"])).is_equal(String(host.run().regime_id()))
	assert_str(String(view["leader"]["name"])).is_equal(host.run().leader_name())
	var lines: Array = view["lines"]
	# The regime-swap beat: VICTORY class, both inks named (yours over
	# theirs — or the banner-never-left form when the redraw held).
	var swap := String(lines[0]["text"])
	assert_int(int(lines[0]["class"])).is_equal(Inks.LineClass.VICTORY)
	assert_bool(swap.contains(Inks.regime_name(previous_regime)) \
		or previous_regime == host.run().regime_id()).is_true()
	assert_bool(swap.contains(String(view["regime"]["name"]))).is_true()
	# The banked-legacy line: the ACTUAL bank after the win banked.
	var bank_line := String(lines[1]["text"])
	assert_bool(bank_line.contains("%d" % host.meta.legacy_points)).is_true()
	# The chronicle context: the PREVIOUS leader's line (who they were,
	# how long they held the standard).
	var context := String(lines[2]["text"])
	assert_bool(context.contains(previous_leader)).is_true()
	var previous: Dictionary = view["previous"]
	assert_str(String(previous["leader"])).is_equal(previous_leader)
	assert_str(String(previous["outcome"])).is_equal("victory")


func test_loss_restart_keeps_the_regime_and_remembers() -> void:
	var host := _test_host()
	var regime_before := host.run().regime_id()
	var previous_leader := host.run().leader_name()
	host.fast_forward(6 * SimEngine.TICKS_PER_SIM_HOUR)
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)
	var view := IntroPresenter.reveal_view(host)
	assert_str(String(view["variant"])).is_equal(String(IntroPresenter.VARIANT_LOSS_RESTART))
	# SAME regime (the sim's defeat rule) — the face card shows the very
	# crest that crushed the last dream.
	assert_str(String(view["regime"]["id"])).is_equal(String(regime_before))
	assert_str(String(view["regime"]["id"])).is_equal(String(host.run().regime_id()))
	var lines: Array = view["lines"]
	var joined := ""
	for line: Dictionary in lines:
		joined += String(line["text"]) + " "
	assert_int(int(lines[0]["class"])).is_equal(Inks.LineClass.STRIKE)
	# The clerk's shorthand after a defeat: the FIRST name ("crushed
	# Bran's dream") — the full plate stays in the chronicle beneath.
	assert_bool(joined.contains(previous_leader.split(" ")[0])).is_true()
	assert_bool(joined.contains("regime remembers")).is_true()
	assert_bool(joined.contains("%d" % host.meta.legacy_points)).is_true()


func test_abort_folds_into_the_loss_variant() -> void:
	var host := _test_host()
	host.fast_forward(2 * SimEngine.TICKS_PER_SIM_HOUR)
	host.submit(&"run_abort")
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)
	assert_str(String(IntroPresenter.variant_for(host))).is_equal(
		String(IntroPresenter.VARIANT_LOSS_RESTART))


func test_variant_derives_from_a_blank_chronicle_on_first_run() -> void:
	var host := _test_host()
	assert_str(String(IntroPresenter.variant_for(host))).is_equal(
		String(IntroPresenter.VARIANT_FIRST_RUN))


func test_view_hash_deterministic_and_seed_sensitive() -> void:
	var a := IntroPresenter.reveal_view(_test_host(20261201))
	var b := IntroPresenter.reveal_view(_test_host(20261201))
	assert_int(IntroPresenter.view_hash(a)).is_equal(IntroPresenter.view_hash(b))
	var c := IntroPresenter.reveal_view(_test_host(20261202))
	assert_int(IntroPresenter.view_hash(a)).is_not_equal(IntroPresenter.view_hash(c))


# --- the pacing band ---------------------------------------------------------------------------


func test_unfold_pacing_inside_the_band_reduced_near_instant() -> void:
	assert_float(IntroPresenter.UNFOLD_SECONDS).is_greater_equal(1.0)
	assert_float(IntroPresenter.UNFOLD_SECONDS).is_less_equal(3.0)
	MotionProfile.forced = -1
	assert_float(IntroPresenter.unfold_seconds()).is_equal(IntroPresenter.UNFOLD_SECONDS)
	MotionProfile.forced = 1
	assert_float(IntroPresenter.unfold_seconds()).is_less_equal(0.15)


# --- the screen: boot, focus, the one gesture ---------------------------------------------------


func _mounted_screen(host: GameHost, intro_on := true) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func test_boot_opens_the_first_hand_focused_on_the_one_gesture() -> void:
	MotionProfile.forced = 1
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var intro := screen._intro
	assert_bool(intro.is_open()).is_true()
	assert_int(intro.state).is_equal(IntroScreenScript.State.REVEAL)
	assert_str(String(intro.view()["variant"])).is_equal(String(IntroPresenter.VARIANT_FIRST_RUN))
	assert_int(intro.interactions).is_equal(0)
	# Focus lands on THE gesture immediately (the single affordance), and
	# it carries the grip floor.
	var chip := intro._packet._chip as Control
	assert_that(get_viewport().gui_get_focus_owner()).is_same(chip)
	var min_size: Vector2 = chip.get_combined_minimum_size()
	assert_float(min_size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# The intro is paper on the table, never popup chrome.
	for node in screen.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	# The reveal render is a function of the view (determinism pinned).
	assert_int(intro.snapshot_hash()).is_equal(intro.snapshot_hash())
	screen.queue_free()


func test_resumed_session_does_not_redeal() -> void:
	MotionProfile.forced = 1
	var host := _test_host()
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)  # hours in — a resumed first run
	var screen: SpreadScreen = await _mounted_screen(host)
	await get_tree().process_frame
	assert_bool(screen._intro.is_open()).is_false()  # T-UI-09's check-in owns that entry
	screen.queue_free()


func test_enter_key_unfolds_in_one_interaction_reduced_synchronous() -> void:
	MotionProfile.forced = 1
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var intro := screen._intro
	# Enter through the REAL input pipeline (the viewport routes it to the
	# focused chip as ui_accept — the frames are the routing's).
	Input.parse_input_event(_enter_key())
	for i in 6:
		await get_tree().process_frame
	# Reduced motion: once the press lands, the sweep completed
	# SYNCHRONOUSLY inside the press — no further frames needed.
	assert_int(intro.state).is_equal(IntroScreenScript.State.CLOSED)
	assert_bool(intro.visible).is_false()
	assert_int(intro.interactions).is_equal(1)
	assert_int(intro.interactions).is_less_equal(IntroScreenScript.MAX_INTERACTIONS)
	# The sync land reports COMPLETE (progress 1.0, nothing in flight) —
	# the round-1 verifier's reporting nit, pinned.
	assert_float(intro.unfold_progress()).is_equal(1.0)
	assert_bool(intro.is_unfolding()).is_false()
	# The table took focus back (a screen must seed itself).
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()


func test_all_three_input_modes_are_the_same_one_gesture() -> void:
	MotionProfile.forced = 1
	# (a) touch: a tap on the intro paper (not on the chip).
	var host_a := _test_host()
	var screen_a: SpreadScreen = await _mounted_screen(host_a)
	screen_a._intro._gui_input(_screen_touch())
	assert_int(screen_a._intro.interactions).is_equal(1)
	assert_int(screen_a._intro.state).is_equal(IntroScreenScript.State.CLOSED)
	screen_a.queue_free()
	# (b) pad: the non-positional primary through the unhandled path.
	var host_b := _test_host()
	var screen_b: SpreadScreen = await _mounted_screen(host_b)
	screen_b._intro._unhandled_input(_action_event(&"primary"))
	assert_int(screen_b._intro.interactions).is_equal(1)
	assert_int(screen_b._intro.state).is_equal(IntroScreenScript.State.CLOSED)
	screen_b.queue_free()
	# (c) back: the alternate forward (the intro has nothing to dismiss into).
	var host_c := _test_host()
	var screen_c: SpreadScreen = await _mounted_screen(host_c)
	screen_c._intro._unhandled_input(_action_event(&"back"))
	assert_int(screen_c._intro.interactions).is_equal(1)
	assert_int(screen_c._intro.state).is_equal(IntroScreenScript.State.CLOSED)
	screen_c.queue_free()


func test_full_motion_unfold_completes_inside_the_band() -> void:
	MotionProfile.forced = -1
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var intro := screen._intro
	intro.unfold()
	assert_bool(intro.is_unfolding()).is_true()
	assert_float(intro.last_unfold_seconds).is_equal(IntroPresenter.UNFOLD_SECONDS)
	# INJECTED DELTAS (T-UI-05 fix round): the sweep is a pure function
	# of t advanced by the packet's own _process(delta) — the test steps
	# the packet's clock directly in authored-duration eighths, never the
	# wall clock. Eight strides = exactly UNFOLD_SECONDS of injected time
	# (the in-band completion), with headroom in the guard for rounding.
	var strides := 0
	while intro.is_open() and strides < 32:
		intro._packet._process(intro.last_unfold_seconds / 8.0)
		strides += 1
	# The authored duration is REACHED in exactly eight injected eighths
	# (at most one extra stride from float rounding — never more).
	assert_int(strides).is_greater_equal(8)
	assert_int(strides).is_less_equal(9)
	assert_bool(intro.is_open()).is_false()
	assert_float(intro.unfold_progress()).is_equal(1.0)
	assert_bool(intro.is_unfolding()).is_false()
	# A DIRECT code call is not a player input — the counter stays 0 (the
	# one-gesture count is pinned by the input-mode tests).
	assert_int(intro.interactions).is_equal(0)
	# The tree carries the deferred focus re-seed (the minimum real
	# frames genuinely needed — batched here, not per stride).
	for i in 2:
		await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()


# --- the seams ------------------------------------------------------------------------------------


func test_win_mounts_from_the_assault_seam_and_deals_the_new_leader() -> void:
	MotionProfile.forced = 1
	var host := _knight_host(WIN_SEED, 2)
	assert_bool(host.assault().floor_met(host.engine)).is_true()
	var screen: SpreadScreen = await _mounted_screen(host)
	screen.open_assault()
	await get_tree().process_frame
	await get_tree().process_frame
	screen._assault.commit()
	for i in 1500:
		await get_tree().process_frame
		if screen._assault.state == 4:  # OUTCOME
			break
	assert_str(String(screen._assault._script.get("outcome", &""))).is_equal("win")
	# "Deal the next hand" — the finished("win") seam mounts the intro.
	screen._assault.close()
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])).is_equal(
		String(IntroPresenter.VARIANT_WIN_RESTART))
	# The intro DEALT the new hand itself: run 2 RUNNING under the
	# redrawn regime, the reveal printing the sim's own new identity.
	assert_int(host.run().run_index).is_equal(2)
	assert_bool(host.is_run_running()).is_true()
	assert_str(String(screen._intro.view()["leader"]["name"])).is_equal(host.run().leader_name())
	assert_str(String(screen._intro.view()["regime"]["id"])).is_equal(String(host.run().regime_id()))
	# From the outcome screen the real path is close (1) + unfold (2) —
	# inside the budget; this direct unfold call is the code path, so the
	# intro's own player-input counter reads 0 (the gesture count is
	# pinned by the input-mode tests at exactly 1).
	screen._intro.unfold()
	for i in 300:
		await get_tree().process_frame
		if not screen._intro.is_open():
			break
	assert_int(screen._intro.interactions).is_equal(0)
	assert_bool(screen._intro.is_open()).is_false()
	# The spread beneath is the NEW hand (full refresh already landed).
	var header := (screen.get_active_slot() as OrientationSlot).get_header().get_child(0)
	assert_str(String(header._name_label.text)).is_equal(host.run().leader_name())
	screen.queue_free()


func test_run_lost_mounts_the_loss_reveal_under_the_same_regime() -> void:
	MotionProfile.forced = 1
	var host := _test_host()
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)  # no boot deal — hours in
	var regime_before := host.run().regime_id()
	var screen: SpreadScreen = await _mounted_screen(host)
	assert_bool(screen._intro.is_open()).is_false()
	# The failure verb (the crush resolves through this exact event kind).
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])).is_equal(
		String(IntroPresenter.VARIANT_LOSS_RESTART))
	assert_str(String(screen._intro.view()["regime"]["id"])).is_equal(String(regime_before))
	assert_bool(host.is_run_running()).is_true()  # the new hand is dealt
	assert_int(host.run().run_index).is_equal(2)
	# The crushing beat stayed printed beneath (states print themselves).
	var chronicle := screen.presenter.chronicle
	var printed_loss := false
	for row: Dictionary in chronicle:
		if String(row["text"]).contains("collapses"):
			printed_loss = true
	assert_bool(printed_loss).is_true()
	screen.queue_free()


# --- layout -----------------------------------------------------------------------------------------


func test_reveal_rects_inside_bounds_major_arcana_both_topologies() -> void:
	var sizes := [Vector2(720, 1280), Vector2(1280, 800), Vector2(1920, 1080),
		Vector2(800, 1280), Vector2(720, 720)]
	for bounds: Vector2 in sizes:
		var rects := IntroPacket.reveal_rects(bounds)
		assert_bool(bool(rects["stacked"])).is_equal(bounds.y > bounds.x)
		for key in ["title", "regime", "leader", "lines", "chip"]:
			var rect: Rect2 = rects[key]
			assert_bool(rect.position.x >= -0.5 and rect.position.y >= -0.5 \
				and rect.end.x <= bounds.x + 0.5 and rect.end.y <= bounds.y + 0.5).is_true()
		for back: Rect2 in rects["backs"]:
			assert_bool(back.position.x >= -0.5 and back.position.y >= -0.5).is_true()
			assert_bool(back.end.x <= bounds.x + 0.5 and back.end.y <= bounds.y + 0.5).is_true()
		# Major-Arcana scale: the regime's face card is strictly larger.
		var regime: Rect2 = rects["regime"]
		var leader: Rect2 = rects["leader"]
		assert_float(regime.size.x).is_greater(leader.size.x)
		assert_float(regime.size.y).is_greater(leader.size.y)
		# The one gesture keeps the grip floor.
		var chip: Rect2 = rects["chip"]
		assert_float(chip.size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
		assert_float(chip.size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))


func _clipped_controls(root: Control, design: Vector2) -> Array[String]:
	var offenders: Array[String] = []
	var queue: Array[Control] = [root]
	while not queue.is_empty():
		var node: Control = queue.pop_front()
		if not node.is_visible_in_tree():
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.size.x > 0.5 and rect.size.y > 0.5:
			if rect.position.x < -0.5 or rect.position.y < -0.5 \
					or rect.end.x > design.x + 0.5 or rect.end.y > design.y + 0.5:
				offenders.append("%s@%s" % [node.name, rect])
		for child in node.get_children():
			if child is Control:
				queue.append(child)
	return offenders


func test_reveal_unclipped_at_four_sizes_focus_never_stranded() -> void:
	MotionProfile.forced = 1
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var router: LayoutRouter = screen.get_router()
	for i in TEST_SIZES.size():
		get_window().size = TEST_SIZES[i]
		for f in 240:
			await get_tree().process_frame
			if router.is_portrait() == EXPECTED_PORTRAIT[i] and router.design_size().x > 1.0:
				break
		for f in 3:
			await get_tree().process_frame
		assert_bool(screen._intro.is_open()).is_true()
		assert_bool(router.is_portrait()).is_equal(EXPECTED_PORTRAIT[i])
		var design := router.design_size()
		for offender in _clipped_controls(screen as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		# Focus stays on the one gesture across swaps.
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()
