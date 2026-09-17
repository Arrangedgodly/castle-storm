## Unit tests for the press-room card (finishing refinement #5) — the
## accessibility surface. Mirrors ui/screens/spread/press_room_screen.gd +
## the meta-domain preferences + the spread seams (the header verbs row,
## the boot seam, the live re-flow, the paper rules). What is pinned:
##   - THE PREFERENCES (meta domain): additive round-trip, the
##     pre-feature tolerant read (no block -> project defaults), the
##     clamp on write AND read (a tampered meta degrades to a legal
##     preference);
##   - THE CARD: the Press-Room chip opens it (focus seeds the engaged
##     step, no popup chrome), back closes and returns focus to the
##     chip, both orientations carry the chip;
##   - LIVE APPLY: a type step re-flows the table NOW (the theme
##     rewrites, the letterhead rebuilds at the new size) and persists
##     into the meta domain + onto disk at once; the steady-hand step
##     flips reduced motion without a restart; the step already in
##     force is a quiet no-op (no meta churn);
##   - PERSISTENCE: the choices survive a full session boundary (a new
##     host + a fresh screen on the same save root re-apply them at
##     boot, before any chrome bakes sizes);
##   - THE PAPER RULES: mutual exclusion with the chronicle + day-sheet
##     (whichever opens folds the others) and story paper outranking
##     the card (the assault vignette, the reveal);
##   - The card opens in the aftermath too (a dead run still has a
##     player with preferences);
##   - Unclipped at the four common sizes, focus never stranded.
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const PressRoomScreenScript := preload("res://ui/screens/spread/press_room_screen.gd")

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]

var _dir_seq := 0


func before_test() -> void:
	TypeScale.reset()
	MotionProfile.forced = -1


func after_test() -> void:
	get_window().size = Vector2i(720, 720)
	TypeScale.reset()
	MotionProfile.forced = -1
	OS.set_environment("CS_TYPE_SCALE", "")
	_erase_dir("user://cs_press_tests")


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


func _test_host(run_seed: int = 20270120) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_press_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _mounted_screen(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = false  # these suites pin THE TABLE + the card
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## Poll until the card's seed lands (the focus owner is one of the
## card's own walkables) — the settle pattern, not a fixed frame count.
func _await_seeded(press_room: PressRoomScreenScript) -> void:
	for i in 24:
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner() as Control
		if focus != null and press_room.sheet().is_ancestor_of(focus):
			return


func _step_chip(press_room: PressRoomScreenScript, value: float) -> Control:
	for chip in press_room.sheet().type_steps():
		if is_equal_approx(float(chip.step_value), value):
			return chip
	return null


func _motion_chip(press_room: PressRoomScreenScript, steady: bool) -> Control:
	for chip in press_room.sheet().motion_steps():
		if bool(chip.step_value) == steady:
			return chip
	return null


# --- the preferences (meta domain) -------------------------------------------------------


func test_preferences_round_trip_and_tolerant_read() -> void:
	var meta := RunMeta.new()
	# A pre-feature payload (no preferences block) reads as defaults —
	# the project settings rule, no migration, no refusal.
	var legacy := RunMeta.new()
	legacy.apply_dict({
		"format_version": 1, "legacy_points": 5, "runs_recorded": 1,
		"chronicle": [], "last_seen_epoch": 0, "first_session": {},
	})
	assert_float(legacy.type_scale_preference()).is_equal(-1.0)
	assert_int(legacy.reduced_motion_preference()).is_equal(-1)
	# The write/read round-trip through the real dict seam.
	meta.set_type_scale_preference(1.2)
	meta.set_reduced_motion_preference(true)
	var payload := meta.to_dict()
	var restored := RunMeta.new()
	assert_bool(restored.apply_dict(payload)).is_true()
	assert_float(restored.type_scale_preference()).is_equal(1.2)
	assert_int(restored.reduced_motion_preference()).is_equal(1)
	# The clamp holds on write AND on a tampered read (a hand-edited or
	# foreign meta degrades to a legal preference, never a 9.0x hand).
	meta.set_type_scale_preference(9.0)
	assert_float(meta.type_scale_preference()).is_equal(TypeScale.MAX_SCALE)
	var tampered := RunMeta.new()
	tampered.apply_dict({
		"format_version": 1, "legacy_points": 0, "runs_recorded": 0,
		"chronicle": [], "preferences": {"type_scale": 0.1, "reduced_motion": 7},
	})
	assert_float(tampered.type_scale_preference()).is_equal(TypeScale.MIN_SCALE)
	assert_int(tampered.reduced_motion_preference()).is_equal(1)


# --- the card: open, walk, close -----------------------------------------------------------


func test_press_chip_opens_card_back_returns_focus_no_popup() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# The chip exists on BOTH slots' verbs rows, full grips.
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		var chip := SpreadScreen.header_chip(slot, "press_room_chip")
		assert_that(chip).is_not_null()
		assert_float(chip.get_combined_minimum_size().y) \
			.is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	var chip := SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip")
	chip.pressed.emit()
	var press_room: PressRoomScreenScript = screen._press_room
	await _await_seeded(press_room)
	assert_bool(press_room.is_open()).is_true()
	assert_int(int(screen.stats[&"press_rooms_opened"])).is_equal(1)
	# Focus seeds the ENGAGED hand step (the walk starts at the truth).
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_that(focus).is_not_null()
	assert_bool(focus == _step_chip(press_room, 1.0)).is_true()
	# No popup chrome anywhere on the card.
	var stack: Array[Node] = [press_room]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	# BACK closes the card and returns focus to the chip that opened it.
	press_room._unhandled_input(_action_event(&"back"))
	assert_bool(press_room.is_open()).is_false()
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(chip as Object)
	assert_int(int(screen.stats[&"press_rooms_closed"])).is_equal(1)
	screen.queue_free()


# --- live apply -----------------------------------------------------------------------------


func test_type_step_reflows_live_and_persists_at_once() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var theme: Theme = load(TypeScale.THEME_PATH) as Theme
	# Open the card through the player's verb first.
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	await _await_seeded(screen._press_room)
	var press_room: PressRoomScreenScript = screen._press_room
	var pressed := _step_chip(press_room, 1.2)
	assert_that(pressed).is_not_null()
	# The authored base default, captured at the live factor (1.0 here).
	var base_default := int(round(float(theme.default_font_size) / TypeScale.factor()))
	pressed.pressed.emit()
	await get_tree().process_frame
	# LIVE: the seam's factor, the shared theme, and the rebuilt
	# letterhead all tell the new size in the same breath.
	assert_float(TypeScale.factor()).is_equal(1.2)
	assert_int(theme.default_font_size).is_equal(TypeScale.scaled(base_default))
	var header := (screen.get_active_slot() as OrientationSlot).get_header().get_child(0)
	assert_int(int(header._name_label.get_theme_font_size(&"font_size"))).is_equal(TypeScale.scaled(28))
	# The engaged rule moved to the pressed step (line form carries it).
	assert_bool(bool(_step_chip(press_room, 1.2).engaged)).is_true()
	assert_bool(bool(_step_chip(press_room, 1.0).engaged)).is_false()
	# PERSISTED: the meta domain holds the preference and the FILE on
	# disk round-trips it (the card saved at once — no autosave needed).
	assert_float(host.meta.type_scale_preference()).is_equal(1.2)
	assert_int(int(screen.stats[&"type_scale_changes"])).is_equal(1)
	var reloaded: RunMeta = host.save_manager.load_meta()
	assert_float(reloaded.type_scale_preference()).is_equal(1.2)
	# The card still owns focus after its own verb (the walk is not
	# interrupted by the re-flow).
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_bool(press_room.sheet().is_ancestor_of(focus)).is_true()
	press_room.close()
	screen.queue_free()


func test_steady_hand_flips_reduced_motion_without_restart() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	var press_room: PressRoomScreenScript = screen._press_room
	await _await_seeded(press_room)
	_motion_chip(press_room, true).pressed.emit()
	await get_tree().process_frame
	# LIVE by construction: the profile answers the new truth now, with
	# no restart and no re-mount.
	assert_bool(MotionProfile.reduced()).is_true()
	assert_bool(MotionProfile.entrances_enabled()).is_false()
	assert_float(MotionProfile.duration(MotionProfile.FLIP_SECONDS)) \
		.is_less(MotionProfile.FLIP_SECONDS * 0.2)
	assert_int(host.meta.reduced_motion_preference()).is_equal(1)
	assert_int(int(screen.stats[&"motion_changes"])).is_equal(1)
	# And back: the full-turn step restores full motion the same way.
	_motion_chip(press_room, false).pressed.emit()
	await get_tree().process_frame
	assert_bool(MotionProfile.reduced()).is_false()
	assert_bool(MotionProfile.entrances_enabled()).is_true()
	assert_int(host.meta.reduced_motion_preference()).is_equal(0)
	press_room.close()
	screen.queue_free()


func test_engaged_step_is_a_quiet_no_op() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	var press_room: PressRoomScreenScript = screen._press_room
	await _await_seeded(press_room)
	# The step already in force (1.0): pressed, but nothing changes — no
	# signal, no meta key, no save churn.
	_step_chip(press_room, 1.0).pressed.emit()
	await get_tree().process_frame
	assert_int(int(screen.stats[&"type_scale_changes"])).is_equal(0)
	assert_int(int(press_room.stats[&"quiet_presses"])).is_equal(1)
	assert_bool(host.meta.preferences.has("type_scale")).is_false()
	press_room.close()
	screen.queue_free()


# --- persistence across a session boundary ---------------------------------------------------


func test_preferences_survive_a_full_restart() -> void:
	get_window().size = Vector2i(720, 1280)
	var root := "user://cs_press_tests/restart"
	_erase_dir(root)
	var first := GameHost.new(20270121, root)
	first.autosave_interval_ticks = 0
	first.boot(0)
	var screen: SpreadScreen = await _mounted_screen(first)
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	await _await_seeded(screen._press_room)
	_step_chip(screen._press_room, 1.3).pressed.emit()
	_motion_chip(screen._press_room, true).pressed.emit()
	await get_tree().process_frame
	assert_float(TypeScale.factor()).is_equal(1.3)
	assert_bool(MotionProfile.reduced()).is_true()
	screen.queue_free()
	await get_tree().process_frame
	# The session ends; the globals forget (a fresh process's truth).
	TypeScale.reset()
	MotionProfile.forced = -1
	# A NEW process on the same save root: the host's boot loads the meta
	# domain, and the screen's BOOT SEAM applies the preferences before
	# any chrome bakes sizes. (No run slot was ever written — autosave
	# off — so boot() falls through to a fresh run; the META domain is
	# what carries the preferences, which is exactly the seam under
	# test.)
	var second := GameHost.new(20270121, root)
	second.autosave_interval_ticks = 0
	second.boot(0)
	assert_float(second.meta.type_scale_preference()).is_equal(1.3)
	assert_int(second.meta.reduced_motion_preference()).is_equal(1)
	var screen2: SpreadScreen = await _mounted_screen(second)
	assert_float(TypeScale.factor()).is_equal(1.3)
	assert_bool(MotionProfile.reduced()).is_true()
	# The card opens ON the persisted truth (the engaged steps mark it).
	var press_room: PressRoomScreenScript = screen2._press_room
	SpreadScreen.header_chip(screen2.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	await _await_seeded(press_room)
	assert_bool(bool(_step_chip(press_room, 1.3).engaged)).is_true()
	assert_bool(bool(_motion_chip(press_room, true).engaged)).is_true()
	press_room.close()
	screen2.queue_free()


func test_boot_preference_yields_to_the_capture_env_hook() -> void:
	# CS_TYPE_SCALE (the inspection hook) wins over the stored hand: an
	# inspection drive pins what it pins. The factor reads its setting
	# lazily (first call after the cache is cold), so the test zeroes the
	# cache the way a fresh process would boot it.
	OS.set_environment("CS_TYPE_SCALE", "1.1")
	TypeScale._factor = 0.0  # the cold-cache seam a fresh process boots with
	TypeScale.apply_preference(1.3)
	assert_float(TypeScale.factor()).is_equal(1.1)
	OS.set_environment("CS_TYPE_SCALE", "")
	TypeScale.reset()
	TypeScale._factor = 0.0
	TypeScale.apply_preference(1.3)
	assert_float(TypeScale.factor()).is_equal(1.3)
	TypeScale.reset()


# --- the paper rules --------------------------------------------------------------------------


func test_mutual_exclusion_and_story_paper_outranks_the_card() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var press_room: PressRoomScreenScript = screen._press_room
	# The chronicle folds an open card (whichever paper opens owns the table).
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	await _await_seeded(press_room)
	screen.open_chronicle()
	assert_bool(press_room.is_open()).is_false()
	assert_bool(screen._chronicle.is_open()).is_true()
	# The day-sheet folds the chronicle the same way; the card folds both.
	screen.open_press_room()
	assert_bool(screen._chronicle.is_open()).is_false()
	assert_bool(press_room.is_open()).is_true()
	screen.open_day_sheet()
	assert_bool(press_room.is_open()).is_false()
	assert_bool(screen._day_sheet.is_open()).is_true()
	# STORY PAPER outranks the card: the assault vignette folds it.
	screen.open_press_room()
	await _await_seeded(press_room)
	assert_bool(press_room.is_open()).is_true()
	screen.open_assault()
	assert_bool(press_room.is_open()).is_false()
	assert_bool(screen._assault.is_open()).is_true()
	# And the reveal folds it too (the story never waits on the papers).
	screen._assault.close()
	screen.open_press_room()
	await _await_seeded(press_room)
	screen._open_intro()
	assert_bool(press_room.is_open()).is_false()
	assert_bool(screen._intro.is_open()).is_true()
	# Fold the reveal without waiting out its authored pacing — the
	# assertion is the fold of the card, not the unfold's watchability
	# (the intro suite owns that).
	screen._intro.unfold()
	for i in 3:
		await get_tree().process_frame
	screen.queue_free()


func test_card_opens_in_the_aftermath_too() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(2)
	assert_bool(host.is_run_running()).is_false()
	screen.open_press_room()
	assert_bool(screen._press_room.is_open()).is_true()
	screen._press_room.close()
	screen.queue_free()


# --- layout -------------------------------------------------------------------------------------


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


func test_unclipped_at_both_orientations_and_sheet_rects_pin_all_sizes() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var press_room: PressRoomScreenScript = screen._press_room
	var router: LayoutRouter = screen.get_router()
	# PURE half first (the house pattern — the assault lane's statics
	# sweep): the sheet's layout math pinned at every common size AND at
	# degenerate small bounds, ~free.
	for size in TEST_SIZES + [Vector2i(480, 800)]:
		var rects: Dictionary = PressRoomScreenScript.PressRoomSheet.sheet_rects(Vector2(size))
		var sheet: Rect2 = rects["sheet"]
		assert_bool(sheet.position.x >= -0.5 and sheet.position.y >= -0.5).is_true()
		assert_float(sheet.end.x).is_less_equal(float(size.x) + 0.5)
		assert_float(sheet.end.y).is_less_equal(float(size.y) + 0.5)
		assert_float(sheet.size.x).is_less_equal(
			minf(float(size.x) - 28.0, PressRoomScreenScript.PressRoomSheet.SHEET_MAX_WIDTH) + 0.5)
	# LIVE half: one portrait iteration (chip reachable on the active
	# header, the card opens unclipped, focus never strands) and one
	# landscape iteration, plus the orientation swap UNDER the open card.
	var live := [Vector2i(720, 1280), Vector2i(1280, 800)]
	var live_portrait := [true, false]
	for i in live.size():
		get_window().size = live[i]
		for f in 240:
			await get_tree().process_frame
			if router.is_portrait() == live_portrait[i] and router.design_size().x > 1.0:
				break
		for f in 2:
			await get_tree().process_frame
		var chip := SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip")
		assert_that(chip).is_not_null()
		assert_float(chip.get_combined_minimum_size().y) \
			.is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
		chip.pressed.emit()
		await _await_seeded(press_room)
		assert_bool(press_room.is_open()).is_true()
		var design := router.design_size()
		for offender in _clipped_controls(press_room as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
		if live_portrait[i]:
			# Swap orientation UNDER the open card — the paper relays, the
			# focus never strands (the papers' own contract, one leg pins it).
			get_window().size = Vector2i(1280, 800)
			for f in 240:
				await get_tree().process_frame
				if not router.is_portrait() and router.design_size().x > 1.0:
					break
			for f in 2:
				await get_tree().process_frame
			assert_bool(press_room.is_open()).is_true()
			assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
		press_room.close()
		await get_tree().process_frame
	screen.queue_free()


# --- input basics (kb/pad fallbacks; the real three-pipeline legs live in the parity matrix §G)


func test_pad_primary_activates_the_focused_step() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "press_room_chip").pressed.emit()
	var press_room: PressRoomScreenScript = screen._press_room
	await _await_seeded(press_room)
	# Walk the rail with focus neighbors (the pad's dpad ride), then A.
	var target := _step_chip(press_room, 1.1)
	target.grab_focus()
	press_room._unhandled_input(_action_event(&"primary"))
	await get_tree().process_frame
	assert_int(int(screen.stats[&"type_scale_changes"])).is_equal(1)
	assert_float(host.meta.type_scale_preference()).is_equal(1.1)
	# B closes (the pad's back).
	press_room._unhandled_input(_action_event(&"back"))
	assert_bool(press_room.is_open()).is_false()
	screen.queue_free()
