## Unit tests for the Spread's suspicion event layer (T-UI-06) —
## Daredevil lane, Prof X consulted (the failure feel).
##
## Mirrors ui/screens/spread/suspicion_events.gd + the watchful_eye /
## table_ground pure params + the screen wiring. What is pinned:
##   - THE CHOICE MODEL (pure): warn vs telegraph framing, the honest
##     chip vocabulary (the REAL dismiss_offer verb when the gate is
##     crowded; the no-command acknowledge; never an invented "lay low"
##     sim verb), the telegraph countdown, determinism;
##   - THE BLOCKQUOTE CONTENT from the event payloads: the struck
##     headline, per-resource seizure counts, the scatter line's NAMES
##     (reconstructed from the pre-crackdown view per the sim's
##     offers-first rule);
##   - THE CRUSH BEAT: the honest greed drive ends the run through
##     run_crushed, the table is struck + swept, the crushing quote
##     prints the REAL bank, and T-UI-05's loss-restart reveal mounts
##     only after the beat resolves (skip lands it synchronously);
##   - THE BEAT-PATH QUOTE PLACEMENT (round-1 verifier FAIL, re-dispatch):
##     on a FIRST crush with no prior crackdown the quote is PLACED —
##     designed width, centered over the cleared table, inside the table
##     region below the header — in BOTH orientations, with landscape
##     pinned center-bottom (never the round-1 top-center clamp) and
##     portrait pinned above the bottom chronicle strip;
##   - INPUT PARITY on the choice card (touch press / pad primary /
##     routed Enter), skippable non-urgent cards (the table stays live),
##     focus never stranded, offline (catch-up) beats never slide stale
##     cards, and zero popup chrome anywhere in these flows.
##
## WAITING STRATEGY (the T-UI-05 harness fix, same shape): the beat's
## strike/sweep/dwell and the Eye's pulses are SceneTreeTimers + Tweens
## in GAME code — this suite INJECTS TIME via Engine.time_scale = 20 (a
## watched ~4s beat costs ~0.2s of wall while the REAL paced path runs
## end to end); after() restores 1.0 so no sibling sees the fast clock.
##
## Meter states are constructed through the documented set_suspicion
## test seam (mirrors SimEngine.set_resource — the sim's own suite owns
## the honest act-driven drives; here we pin the UI layer's triggers).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const SuspicionEventsScript := preload("res://ui/screens/spread/suspicion_events.gd")
const WatchfulEyeScript := preload("res://ui/screens/spread/watchful_eye.gd")
const TableGroundScript := preload("res://ui/theme/table_ground.gd")

## Injected-time scale for watched timers/tweens (see WAITING STRATEGY).
const MOTION_SCALE := 20.0
## The screenshot seed's greed policy crushes reliably (the T-UI-05 loss
## drive measured it < 120h; this suite's cap is 200).
const CRUSH_SEED := 20261103

var _warn_threshold: int
var _crackdown_threshold: int
var _dir_seq := 0


func before_test() -> void:
	Engine.time_scale = MOTION_SCALE
	var tunables: EconomyTunables = Inks.pack().tunables
	_warn_threshold = tunables.suspicion_warn_threshold
	_crackdown_threshold = tunables.suspicion_crackdown_threshold


func after() -> void:
	Engine.time_scale = 1.0  # never leak the injected fast clock
	MotionProfile.forced = -1
	_erase_dir("user://cs_ui06_tests")
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


func _test_host(run_seed: int = 20261205) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_ui06_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _mounted_screen(host: GameHost, intro_on := false) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## Arm the crackdown telegraph through the documented meter seam: the
## next tick crosses the threshold rising and arms with the validator's
## >= 4h countdown (a warn fires first — hysteresis is honest, the
## telegraph card supersedes it, which these tests also pin).
func _arm_telegraph(host: GameHost) -> Dictionary:
	var telegraph := {}
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"suspicion_telegraph":
			telegraph["event"] = event)
	host.suspicion().set_suspicion(_crackdown_threshold + 2)
	host.fast_forward(1)
	return telegraph.get("event", {})


## Hold the meter inside the crackdown zone across the telegraph window
## (presence alone would decay it out — the R4 tension mechanic); the
## land tick arrives and the strike fires.
func _land_telegraph(host: GameHost) -> void:
	for i in 6:
		host.suspicion().set_suspicion(_crackdown_threshold + 5)
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)


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


func _assert_no_popup_chrome(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)


func _unfold_boot_intro(screen: SpreadScreen) -> void:
	if screen._intro != null and screen._intro.is_open():
		screen._intro.unfold()
		for i in 300:
			await get_tree().process_frame
			if not screen._intro.is_open():
				break


## The beat starts DEFERRED (after the ending drain's full refresh) —
## poll it into view before asserting on the beat itself.
func _await_beat_active(screen: SpreadScreen) -> bool:
	for i in 30:
		await get_tree().process_frame
		if screen._suspicion.beat_active():
			return true
	return screen._suspicion.beat_active()


# --- the choice model (pure) ---------------------------------------------------------------


func test_warn_model_skippable_framing_and_honest_chips() -> void:
	var host := _test_host()
	var model := SuspicionEventsScript.choice_card_for(host, {
		"seq": 1, "tick": 10, "type": &"suspicion_warn",
		"subject": &"suspicion", "value": _warn_threshold, "value2": _warn_threshold,
	})
	assert_bool(model["urgent"]).is_false()
	assert_str(String(model["title"])).is_equal("THE CROWN TAKES NOTICE")
	# The acknowledge chip carries NO command (nothing to invent).
	var keep_close: Dictionary = {}
	for chip: Dictionary in model["chips"]:
		if String(chip["id"]) == "keep_close":
			keep_close = chip
	assert_bool(keep_close.is_empty()).is_false()
	assert_str(String(keep_close.get("command", &"x"))).is_empty()
	# A quiet gate (offers within tolerance) offers no crowd to send home.
	var offers: int = host.units().pending_offers()
	var tolerance: int = Inks.pack().tunables.suspicion_recruit_tolerance
	if offers <= tolerance:
		for chip: Dictionary in model["chips"]:
			assert_str(String(chip["id"])).is_not_equal("thin_the_gate")


func test_telegraph_model_urgent_countdown_and_the_real_verb() -> void:
	var host := _test_host()
	# Let the eager arrival rush stack a real crowd at the gate.
	for i in 6:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	var event := _arm_telegraph(host)
	assert_bool(event.is_empty()).is_false()
	var model := SuspicionEventsScript.choice_card_for(host, event)
	assert_bool(model["urgent"]).is_true()
	assert_str(String(model["title"])).is_equal("RIDERS IN THE YARD")
	assert_int(int(model["hours_left"])).is_greater_equal(4)  # the validator's telegraph floor
	# The one real quieting verb: dismiss_offer per loitering offer.
	var offers: int = host.units().pending_offers()
	var tolerance: int = Inks.pack().tunables.suspicion_recruit_tolerance
	if offers > tolerance:
		var thin: Dictionary = {}
		for chip: Dictionary in model["chips"]:
			if String(chip["id"]) == "thin_the_gate":
				thin = chip
		assert_bool(thin.is_empty()).is_false()
		assert_str(String(thin.get("multi_command", &""))).is_equal("dismiss_offer")
		assert_int((thin.get("subjects", []) as Array).size()).is_equal(offers)


func test_choice_model_is_deterministic_and_state_sensitive() -> void:
	var a := _test_host(777)
	var b := _test_host(777)
	var warn := {"seq": 1, "tick": 5, "type": &"suspicion_warn", "subject": &"suspicion", "value": 35, "value2": 35}
	assert_int(SuspicionEventsScript.choice_model_hash(SuspicionEventsScript.choice_card_for(a, warn))) \
		.is_equal(SuspicionEventsScript.choice_model_hash(SuspicionEventsScript.choice_card_for(b, warn)))
	# A crowd at the gate changes the card (the chip count is state).
	for i in 6:
		a.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(SuspicionEventsScript.choice_model_hash(SuspicionEventsScript.choice_card_for(a, warn))) \
		.is_not_equal(SuspicionEventsScript.choice_model_hash(SuspicionEventsScript.choice_card_for(b, warn)))


func test_scatter_names_follow_the_offers_first_rule() -> void:
	var pre_cards: Array = [
		{"kind": &"offer", "name": "Osric"},
		{"kind": &"offer", "name": "Broom"},
		{"kind": &"offer", "name": "Hilda"},
		{"kind": &"offer", "name": "Maud"},
		{"kind": &"unit", "name": "Wilmot"},
	]
	# 4 offers, 3 swept, 1 left: the FIRST 3 names in gate order went.
	var info := SuspicionEventsScript.scatter_names(pre_cards, 3, 1)
	assert_array(info["names"]).is_equal(["Osric", "Broom", "Hilda"])
	assert_int(int(info["peasants"])).is_zero()
	# A thin gate: 2 offers both swept + 1 peasant followed.
	var thin_cards: Array = [
		{"kind": &"offer", "name": "Osric"},
		{"kind": &"offer", "name": "Broom"},
		{"kind": &"unit", "name": "Wilmot"},
	]
	info = SuspicionEventsScript.scatter_names(thin_cards, 3, 0)
	assert_array(info["names"]).is_equal(["Osric", "Broom"])
	assert_int(int(info["peasants"])).is_equal(1)
	# Nobody swept: the mud line.
	var row := SuspicionEventsScript.scatter_line(pre_cards, {"value": 0, "value2": 4})
	assert_str(String(row["text"])).contains("mud")


func test_crush_lines_read_the_regime_and_the_real_bank() -> void:
	var host := _test_host()
	host.meta.legacy_points = 231
	var lines := SuspicionEventsScript.crush_lines(host)
	assert_int(lines.size()).is_equal(3)
	assert_str(String(lines[0]["text"])).contains(Inks.regime_name(host.run().regime_id()))
	assert_int(int(lines[2]["class"])).is_equal(Inks.LineClass.PLAIN)
	assert_str(String(lines[2]["text"])).contains("231")
	# LINE BUDGET: the quote panel's rows clip past the label edge — every
	# line fits the panel even at the worst regime name (the mounted
	# placement tests pin the REAL font-metric no-clip guarantee).
	for line: Dictionary in lines:
		assert_int(String(line["text"]).length()).is_less_equal(62)


func test_panel_rects_stay_inside_the_design() -> void:
	for bounds: Vector2 in [Vector2(720, 720), Vector2(720, 1280), Vector2(1280, 800), Vector2(1920, 1080)]:
		var choice := SuspicionEventsScript.choice_rect(bounds, Vector2(312, 320))
		assert_float(choice.position.x).is_greater_equal(0.0)
		assert_float(choice.position.y).is_greater_equal(0.0)
		assert_float(choice.end.x).is_less_equal(bounds.x)
		assert_float(choice.end.y).is_less_equal(bounds.y)
		# The quote prints ABOVE the chronicle strip (its floor is the
		# strip's top, less a breath), never past the table's edge.
		var chronicle_top := bounds.y - 110.0
		var quote := SuspicionEventsScript.quote_rect(bounds, Vector2(560, 260), chronicle_top)
		assert_float(quote.end.y).is_less_equal(chronicle_top + 0.5)
		assert_float(quote.end.x).is_less_equal(bounds.x)
		assert_float(quote.position.y).is_greater_equal(0.0)


# --- the pure pulse params (Eye strike/retreat, ground flash) --------------------------------


func test_eye_and_ground_pulse_params_are_pure_functions() -> void:
	# The strike: rest at both ends, a single bell between.
	assert_float(float(WatchfulEyeScript.strike_params(0.0)["scale_mult"])).is_equal(1.0)
	assert_float(float(WatchfulEyeScript.strike_params(1.0)["wash"])).is_zero()
	var peak := WatchfulEyeScript.strike_params(0.5)
	assert_float(float(peak["scale_mult"])).is_greater(1.15)
	assert_float(float(peak["wash"])).is_greater(0.3)
	# Monotone up to the middle.
	var last := -1.0
	for i in 6:
		var t := float(i) / 10.0
		var value := float(WatchfulEyeScript.strike_params(t)["scale_mult"])
		assert_float(value).is_greater(last)
		last = value
	# The retreat: a dip, never a growth.
	assert_float(float(WatchfulEyeScript.retreat_params(0.0)["scale_mult"])).is_equal(1.0)
	assert_float(float(WatchfulEyeScript.retreat_params(0.5)["scale_mult"])).is_less(0.95)
	# The ground flash lerps toward cold ash, monotone in the flash.
	var base := Inks.ground_for(&"paper_crown", Inks.Phase.TRAINING)
	assert_float(_color_distance(base, TableGroundScript.flash_color(base, 0.0))).is_zero()
	for i in 5:
		var a := TableGroundScript.flash_color(base, float(i) / 5.0)
		var b := TableGroundScript.flash_color(base, float(i + 1) / 5.0)
		assert_float(_color_distance(b, Inks.ASH)).is_less(_color_distance(a, Inks.ASH))


func _color_distance(a: Color, b: Color) -> float:
	var d := a - b
	return sqrt(d.r * d.r + d.g * d.g + d.b * d.b)


# --- the screen: choice cards ---------------------------------------------------------------


func test_warn_event_slides_a_skippable_choice_card() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	host.suspicion().set_suspicion(_warn_threshold + 5)
	host.fast_forward(1)
	await get_tree().process_frame
	assert_int(screen.stats[&"choice_cards"]).is_equal(1)
	assert_bool(screen._suspicion.choice_is_open()).is_true()
	assert_bool(bool(screen._suspicion.choice_model()["urgent"])).is_false()
	_assert_no_popup_chrome(screen as Node)
	# SKIPPABLE: the table beneath stays live — a card still fans, the
	# sim still advances, nothing is blocked.
	var before_ticks := host.engine.tick_count
	var cards := (screen.get_active_slot() as OrientationSlot).get_spread().get_children()
	if not cards.is_empty():
		var card := cards[0] as Control
		card.grab_focus()
		screen.open_fan_for_card(card)
		if screen._fan.is_open():
			screen.close_fan()
	host.fast_forward(30)
	assert_int(host.engine.tick_count).is_greater(before_ticks)
	assert_bool(screen._suspicion.choice_is_open()).is_true()  # un-answered, un-blocking
	# Back folds it; focus returns to the table.
	screen._unhandled_input(_action_event(&"back"))
	assert_bool(screen._suspicion.choice_is_open()).is_false()
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()
	await get_tree().process_frame


func test_telegraph_card_frames_urgently_and_seeds_focus() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	_arm_telegraph(host)
	await get_tree().process_frame
	assert_bool(screen._suspicion.choice_is_open()).is_true()
	assert_bool(bool(screen._suspicion.choice_model()["urgent"])).is_true()
	# Urgent emphasis is framing, never a block: focus seeds on a chip
	# and the countdown prints; back still folds it.
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_bool(focus is ActionFan.ActionChip).is_true()
	var countdown := screen._suspicion._choice._countdown as Label
	assert_bool(countdown.visible).is_true()
	assert_str(countdown.text).contains("lands in")
	screen._unhandled_input(_action_event(&"back"))
	assert_bool(screen._suspicion.choice_is_open()).is_false()
	screen.queue_free()
	await get_tree().process_frame


func test_thin_the_gate_choice_submits_the_real_commands() -> void:
	var host := _test_host()
	for i in 6:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # the eager rush crowds the gate
	var offers: int = host.units().pending_offers()
	assert_int(offers).is_greater(Inks.pack().tunables.suspicion_recruit_tolerance)
	var screen: SpreadScreen = await _mounted_screen(host)
	_arm_telegraph(host)
	await get_tree().process_frame
	var model := screen._suspicion.choice_model()
	var thin: Dictionary = {}
	for chip: Dictionary in model["chips"]:
		if String(chip["id"]) == "thin_the_gate":
			thin = chip
	assert_bool(thin.is_empty()).is_false()
	# Choose it: one REAL dismiss_offer command per loiterer, down the
	# host's one write path.
	var dismissed: Array = []
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"recruit_dismissed":
			dismissed.append(int(event["value"])))
	screen._on_suspicion_choice(thin)
	host.fast_forward(2)
	assert_int(dismissed.size()).is_equal(offers)
	assert_int(host.units().pending_offers()).is_zero()
	assert_bool(screen._suspicion.choice_is_open()).is_false()  # answered: folds
	assert_int(screen.stats[&"choices_made"]).is_equal(1)
	# The choice printed its acknowledgment in the chronicle (in-world;
	# the rolling buffer keeps it past the dismissals' own rows).
	var printed := false
	for row: Dictionary in screen.presenter.chronicle:
		if String(row["text"]).contains("gate thins"):
			printed = true
	assert_bool(printed).is_true()
	screen.queue_free()
	await get_tree().process_frame


func test_keep_close_prints_and_submits_nothing() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	host.suspicion().set_suspicion(_warn_threshold + 5)
	host.fast_forward(1)
	await get_tree().process_frame
	var keep_close: Dictionary = {}
	for chip: Dictionary in screen._suspicion.choice_model()["chips"]:
		if String(chip["id"]) == "keep_close":
			keep_close = chip
	var commands_before := (host.engine.to_dict()["pending_commands"] as Array).size()
	screen._on_suspicion_choice(keep_close)
	assert_int((host.engine.to_dict()["pending_commands"] as Array).size()) \
		.is_equal(commands_before)
	assert_bool(screen._suspicion.choice_is_open()).is_false()
	var printed := false
	for row: Dictionary in screen.presenter.chronicle_strip():
		if String(row["text"]).contains("cards close"):
			printed = true
	assert_bool(printed).is_true()
	screen.queue_free()
	await get_tree().process_frame


func test_choice_card_answers_from_all_three_input_modes() -> void:
	# (a) TOUCH: a chip press is the gesture.
	var host_a := _test_host()
	var screen_a: SpreadScreen = await _mounted_screen(host_a)
	host_a.suspicion().set_suspicion(_warn_threshold + 5)
	host_a.fast_forward(1)
	await get_tree().process_frame
	var chosen: Array = []
	screen_a._suspicion.choice_made.connect(func(action: Dictionary) -> void: chosen.append(action["id"]))
	(screen_a._suspicion._choice.chips()[0] as BaseButton).pressed.emit()
	assert_array(chosen).is_equal(["keep_close"])  # a quiet gate: acknowledge is the only chip
	screen_a.queue_free()
	await get_tree().process_frame
	# (b) PAD: non-positional primary activates the FOCUSED chip.
	var host_b := _test_host()
	var screen_b: SpreadScreen = await _mounted_screen(host_b)
	host_b.suspicion().set_suspicion(_warn_threshold + 5)
	host_b.fast_forward(1)
	await get_tree().process_frame
	await get_tree().process_frame  # the deferred focus seed lands
	var chosen_b: Array = []
	screen_b._suspicion.choice_made.connect(func(action: Dictionary) -> void: chosen_b.append(action["id"]))
	screen_b._unhandled_input(_action_event(&"primary"))
	assert_array(chosen_b).is_equal(["keep_close"])
	screen_b.queue_free()
	await get_tree().process_frame
	# (c) KEYBOARD: Enter through the real input pipeline on the focused chip.
	var host_c := _test_host()
	var screen_c: SpreadScreen = await _mounted_screen(host_c)
	host_c.suspicion().set_suspicion(_warn_threshold + 5)
	host_c.fast_forward(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var chosen_c: Array = []
	screen_c._suspicion.choice_made.connect(func(action: Dictionary) -> void: chosen_c.append(action["id"]))
	Input.parse_input_event(_enter_key())
	for i in 6:
		await get_tree().process_frame
	assert_array(chosen_c).is_equal(["keep_close"])
	screen_c.queue_free()
	await get_tree().process_frame


func test_offline_windows_never_slide_stale_choice_cards() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# An away window whose first ticks cross the warn threshold: the beat
	# prints in the chronicle but slides NO card (the moment passed).
	host.suspicion().set_suspicion(_warn_threshold + 1)
	host.background(1_000_000)
	var tick_before := host.engine.tick_count
	host.foreground(1_000_000 + 9 * 3600)
	assert_int(host.engine.tick_count).is_greater(tick_before)
	assert_int(screen.stats[&"choice_cards"]).is_zero()
	var printed := false
	for row: Dictionary in screen.presenter.chronicle:  # the rolling buffer (12 rows)
		if String(row["text"]).contains("clerk"):
			printed = true
	assert_bool(printed).is_true()  # states print themselves — even away
	# The NEXT live warn slides the card (the feed is honest, not muted).
	host.suspicion().set_suspicion(10)
	host.fast_forward(1)  # silent exit below warn (hysteresis re-prime)
	host.suspicion().set_suspicion(_warn_threshold + 5)
	host.fast_forward(1)
	await get_tree().process_frame
	assert_int(screen.stats[&"choice_cards"]).is_equal(1)
	screen.queue_free()
	await get_tree().process_frame


# --- the crackdown landing ------------------------------------------------------------------


func test_crackdown_lands_as_blockquote_strike_and_flash() -> void:
	var host := _test_host()
	for i in 6:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # a crowd for the scatter
	var seized_events: Array = []
	var scattered_event := {}
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"crackdown_seized":
			seized_events.append(event)
		elif event["type"] == &"crackdown_scattered":
			scattered_event["event"] = event)
	_arm_telegraph(host)
	var screen: SpreadScreen = await _mounted_screen(host)
	_land_telegraph(host)
	await get_tree().process_frame
	assert_int(host.suspicion().crackdowns_total).is_greater(0)
	assert_int(screen.stats[&"quotes_printed"]).is_greater_equal(1)
	assert_bool(screen._suspicion.quote_is_open()).is_true()
	var rows := screen._suspicion.quote_rows()
	var joined := ""
	for row: Dictionary in rows:
		joined += String(row["text"]) + "\n"
	# The headline + every SEIZED COUNT from the real payloads.
	assert_str(joined).contains("CRACKDOWN")
	for event: Dictionary in seized_events:
		assert_str(joined).contains("%d %s" % [int(event["value"]), String(event["subject"])])
	# The scatter line names the swept gate crowd (offers-first rule),
	# reconstructed from the SAME pre-crackdown record the screen kept.
	if not scattered_event.is_empty():
		var scattered: Dictionary = scattered_event["event"]
		if int(scattered["value"]) > 0:
			var info := SuspicionEventsScript.scatter_names(
				screen._pre_crackdown_cards, int(scattered["value"]), int(scattered["value2"]))
			var names: Array = info["names"]
			if not names.is_empty():
				assert_str(joined).contains(String(names[0]))
	# The Eye struck and the ground flashed (state-driven pulses).
	var eye := screen.eye_of(screen.get_active_slot() as OrientationSlot)
	assert_int(int(eye.get("retreats_played"))).is_zero()
	assert_int(screen.stats[&"eye_strikes"]).is_greater_equal(1)
	assert_int(screen.stats[&"ground_flashes"]).is_greater_equal(1)
	# The telegraph choice card is gone (the moment chose itself).
	assert_bool(screen._suspicion.choice_is_open()).is_false()
	_assert_no_popup_chrome(screen as Node)
	screen.queue_free()
	await get_tree().process_frame


func test_relief_folds_the_card_and_retreats_the_eye() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	_arm_telegraph(host)
	await get_tree().process_frame
	assert_bool(screen._suspicion.choice_is_open()).is_true()
	# Lay low: the meter drops below the threshold -> the riders stand down.
	host.suspicion().set_suspicion(_crackdown_threshold - 20)
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(screen._suspicion.choice_is_open()).is_false()
	var eye := screen.eye_of(screen.get_active_slot() as OrientationSlot)
	assert_int(int(eye.get("retreats_played"))).is_greater_equal(1)
	assert_int(host.suspicion().crackdowns_total).is_zero()  # cancelled, not landed
	var calm := false
	for row: Dictionary in screen.presenter.chronicle_strip():
		if String(row["text"]).contains("riders turn back"):
			calm = true
	assert_bool(calm).is_true()
	screen.queue_free()
	await get_tree().process_frame


# --- the crushed beat (the failure vignette) --------------------------------------------------


## The honest greed drive: never lays low, gets crushed (the balance
## band's own failure-mode probe — the T-UI-05 loss drive measured the
## same shape < 120h; this suite's cap is 200h).
func _drive_to_crush(host: GameHost, max_hours := 200.0) -> float:
	var policy := DemoPolicy.new(40, 40, true)
	var hours := 0.0
	while host.is_run_running() and hours < max_hours:
		host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		if policy.on_ticks(SimEngine.TICKS_PER_SIM_HOUR):
			policy.apply(host)
		hours += 1.0
	await get_tree().process_frame
	return hours


func test_crush_plays_the_beat_then_mounts_the_loss_reveal() -> void:
	var host := _test_host(CRUSH_SEED)
	var screen: SpreadScreen = await _mounted_screen(host, true)
	await _unfold_boot_intro(screen)
	var hours := await _drive_to_crush(host)
	assert_bool(host.is_run_running()).is_false()  # the crush landed
	assert_int(screen.stats[&"crushes_played"]).is_equal(1)
	assert_bool(await _await_beat_active(screen)).is_true()  # the beat owns the table
	assert_bool(screen._intro.is_open()).is_false()  # the reveal waits (paper on paper)
	# Mid-beat: wait for the crushing quote (the story's voice).
	for i in 300:
		await get_tree().process_frame
		if screen._suspicion.beat_phase == SuspicionEvents.BeatPhase.QUOTE:
			break
	var rows := screen._suspicion.quote_rows()
	assert_int(rows.size()).is_equal(3)
	assert_str(String(rows[0]["text"])).contains(
		Inks.regime_name(host.run().regime_id()))
	assert_str(String(rows[2]["text"])).contains(str(host.meta.legacy_points))
	# PLACEMENT holds on this path too (the round-1 suite gap: the CRUSH_SEED
	# drive lands a crackdown first, whose quote placed the control — the
	# beat quote must be placed on its OWN, fresh OR inherited session).
	_assert_quote_placed_over_the_table(screen)
	print("[ui06] crush beat after %.0fh — bank %d, quote read end to end"
		% [hours, host.meta.legacy_points])
	# The beat resolves on its own pacing (injected time): the reveal is
	# dealt under the SAME regime (the sim's defeat-keeps rule) — the
	# restart ran (run 2), and the fresh table deals its first cards as
	# the world moves (the unfreeze came before the reveal).
	for i in 600:
		await get_tree().process_frame
		if screen._intro.is_open():
			break
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])).is_equal(
		String(IntroPresenter.VARIANT_LOSS_RESTART))
	assert_int(host.run().current_run_index()).is_equal(2)
	screen._intro.unfold()
	for i in 300:
		await get_tree().process_frame
		if not screen._intro.is_open():
			break
	for i in 400:
		host.fast_forward(30)
		if (screen.get_active_slot() as OrientationSlot).card_count() > 0:
			break
	assert_int((screen.get_active_slot() as OrientationSlot).card_count()).is_greater(0)
	_assert_no_popup_chrome(screen as Node)
	screen.queue_free()
	await get_tree().process_frame


func test_crush_beat_is_skippable_with_one_input() -> void:
	var host := _test_host(CRUSH_SEED)
	var screen: SpreadScreen = await _mounted_screen(host, true)
	await _unfold_boot_intro(screen)
	await _drive_to_crush(host)
	assert_bool(await _await_beat_active(screen)).is_true()
	# ANY input skips: the settled state lands NOW (cards swept, quote
	# printed, completion fired) — the reveal mounts over the new deal.
	screen._unhandled_input(_action_event(&"primary"))
	assert_bool(screen._suspicion.beat_active()).is_false()
	for i in 6:
		await get_tree().process_frame
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])).is_equal(
		String(IntroPresenter.VARIANT_LOSS_RESTART))
	screen.queue_free()
	await get_tree().process_frame


func test_crush_without_the_intro_keeps_the_cleared_table() -> void:
	var host := _test_host(CRUSH_SEED)
	var screen: SpreadScreen = await _mounted_screen(host, false)
	await _drive_to_crush(host)
	assert_bool(await _await_beat_active(screen)).is_true()
	screen._suspicion.skip_beat()
	await get_tree().process_frame
	assert_bool(screen._suspicion.beat_active()).is_false()
	assert_int(screen.stats[&"intros_opened"]).is_zero()
	var active := screen.get_active_slot() as OrientationSlot
	assert_int(active.get_spread().get_child_count()).is_equal(0)  # the hand is over
	# The quote folds itself after its dwell (content pacing).
	for i in 200:
		await get_tree().process_frame
		if not screen._suspicion.quote_is_open():
			break
	assert_bool(screen._suspicion.quote_is_open()).is_false()
	screen.queue_free()
	await get_tree().process_frame


# --- the beat-path quote PLACEMENT (round-1 verifier FAIL, re-dispatch) -----------------------


## The FRESH first-death path the round-1 verifier caught: NO prior
## crackdown in the session ever placed the quote control, so the beat's
## quote rendered at the control's unplaced default corner at raw min
## size (probe: position (0,0), size (220,180)) with text spilling over
## the header. The meter jumps to the crush line through the documented
## seam — on_tick checks the crush BEFORE the telegraph/landing checks,
## so the run dies with ZERO crackdowns (the premise, asserted).
func _crush_now(host: GameHost) -> void:
	host.suspicion().set_suspicion(host.suspicion().max_points())
	# Tick 1 fires run_crushed (the crush check runs BEFORE the telegraph/
	# landing checks, so no crackdown ever lands — the premise); the defeat
	# resolution command drains run_lost a tick later, tick-aligned like
	# every write. A few ticks settle both.
	host.fast_forward(5)


## Resize + wait for the router to land the topology (deadband + dwell
## under the injected fast clock), then let the slot's deferred layout
## settle — the quote's floor reads the SETTLED slot geometry.
func _settle_orientation(window_size: Vector2i, want_portrait: bool, screen: SpreadScreen) -> void:
	get_window().size = window_size
	var router := screen.get_router()
	for i in 240:
		await get_tree().process_frame
		if router.is_portrait() == want_portrait and router.design_size().x > 1.0:
			break
	for i in 6:
		await get_tree().process_frame


## The beat quote must be PLACED like every blockquote this layer prints:
## content-sized to the DESIGNED width, centered over the cleared table,
## inside the table region — below the header, above the quote's floor —
## and never the unplaced (0,0) corner at the raw min size.
func _assert_quote_placed_over_the_table(screen: SpreadScreen) -> void:
	var quote := screen._suspicion._quote as Control
	var bounds := screen._design_bounds().size
	var rect := quote.get_global_rect()
	# NOT the unplaced defect: neither axis parked at the origin corner.
	assert_float(rect.position.x).is_greater(1.0)
	assert_float(rect.position.y).is_greater(1.0)
	# The designed panel width, horizontally centered in the design.
	var want_width := minf(560.0, bounds.x - 12.0)
	assert_float(rect.size.x).is_equal(want_width)
	assert_float(rect.position.x).is_equal((bounds.x - want_width) * 0.5)
	# Content-sized height (never the raw ~180 min-size stub).
	assert_float(rect.size.y).is_greater_equal(quote.get_combined_minimum_size().y - 0.5)
	# Inside the table region: below the header strip...
	var header := (screen.get_active_slot() as OrientationSlot).get_header()
	if header != null:
		assert_float(rect.position.y).is_greater_equal(header.get_global_rect().end.y)
	# ...above the floor (portrait: the bottom chronicle strip's top;
	# landscape: the table's bottom edge), and inside the design bounds.
	assert_float(rect.end.y).is_less_equal(screen._quote_floor() + 0.5)
	assert_float(rect.end.x).is_less_equal(bounds.x + 0.5)
	assert_float(rect.position.y).is_greater_equal(0.0)
	# NOTHING CLIPPED MID-SENTENCE: every printed row's text fits its label
	# measured in the REAL theme font (the round-2 capture find — the first
	# placeholder lines ran past the panel's right border).
	for line: Control in screen._suspicion._quote._lines:
		var label := _chronicle_label_of(line)
		if label == null:
			continue
		var width := label.get_theme_font("font").get_string_size(
			String(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font")).x
		assert_float(width).is_less_equal(label.size.x + 0.5)


## The printed row's Label (ChronicleLine -> HBox -> [rule, label]).
func _chronicle_label_of(row: Control) -> Label:
	for child in row.get_children():
		if child is HBoxContainer:
			for leaf in child.get_children():
				if leaf is Label:
					return leaf
	return null


func _await_beat_quote(screen: SpreadScreen) -> void:
	for i in 300:
		await get_tree().process_frame
		if screen._suspicion.beat_phase == SuspicionEvents.BeatPhase.QUOTE:
			break
	assert_int(screen._suspicion.beat_phase).is_equal(SuspicionEvents.BeatPhase.QUOTE)


func test_first_crush_quote_places_over_the_cleared_table_portrait() -> void:
	get_window().size = Vector2i(720, 1280)  # resize before the mount: the first layout is portrait
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host, false)
	await _settle_orientation(Vector2i(720, 1280), true, screen)
	assert_bool(screen.get_router().is_portrait()).is_true()
	_crush_now(host)
	assert_int(host.suspicion().crackdowns_total).is_zero()  # the fresh-path premise
	assert_bool(await _await_beat_active(screen)).is_true()
	await _await_beat_quote(screen)
	_assert_quote_placed_over_the_table(screen)
	# PORTRAIT: parked bottom-center ABOVE the bottom chronicle strip.
	var strip_top := ((screen.get_active_slot() as OrientationSlot) \
		.get_chronicle_line(0) as Control).get_global_rect().position.y
	assert_float((screen._suspicion._quote as Control).get_global_rect().end.y) \
		.is_less_equal(strip_top + 0.5)
	screen._suspicion.skip_beat()
	screen.queue_free()
	await get_tree().process_frame


func test_first_crush_quote_places_over_the_cleared_table_landscape() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host, false)
	await _settle_orientation(Vector2i(1280, 800), false, screen)
	assert_bool(screen.get_router().is_portrait()).is_false()
	_crush_now(host)
	assert_int(host.suspicion().crackdowns_total).is_zero()  # the fresh-path premise
	assert_bool(await _await_beat_active(screen)).is_true()
	await _await_beat_quote(screen)
	_assert_quote_placed_over_the_table(screen)
	# LANDSCAPE (the round-1 secondary find): the strip is at the TOP, so
	# the quote parks CENTER-BOTTOM of the table — never the old top-center
	# clamp — above the table's bottom edge, clear of the pips rail.
	var bounds := screen._design_bounds().size
	var rect := (screen._suspicion._quote as Control).get_global_rect()
	assert_float(rect.position.y).is_greater_equal(bounds.y * 0.5)
	var spread_end := (screen.get_active_slot() as OrientationSlot) \
		.get_spread().get_global_rect().end.y
	assert_float(rect.end.y).is_less_equal(spread_end + 0.5)
	screen._suspicion.skip_beat()
	screen.queue_free()
	await get_tree().process_frame


func test_a_loss_without_crush_skips_the_beat() -> void:
	## The thin abort (resolve_victory) is NOT a crush: no beat, the
	## reveal mounts on the old deferred path (T-UI-05's seam unchanged).
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host, true)
	await _unfold_boot_intro(screen)
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(5)
	for i in 30:
		await get_tree().process_frame
		if screen._intro.is_open():
			break
	assert_int(screen.stats[&"crushes_played"]).is_zero()
	assert_bool(screen._intro.is_open()).is_true()
	screen.queue_free()
	await get_tree().process_frame


func test_a_crush_behind_an_open_reveal_waits_for_its_fold() -> void:
	## The world crushed beneath the boot reveal (an away-window death,
	## or the dev drive): paper never stacks on paper — the beat waits
	## for the reveal's fold, THEN tells the story.
	var host := _test_host(CRUSH_SEED)
	var screen: SpreadScreen = await _mounted_screen(host, true)
	assert_bool(screen._intro.is_open()).is_true()  # the boot reveal, untouched
	await _drive_to_crush(host)
	for i in 30:
		await get_tree().process_frame
	# Still papered: the beat has NOT started under the reveal.
	assert_bool(screen._suspicion.beat_active()).is_false()
	assert_int(screen.stats[&"crushes_played"]).is_zero()
	# The one gesture folds the boot reveal — the beat owns the table now.
	screen._intro.unfold()
	for i in 300:
		await get_tree().process_frame
		if not screen._intro.is_open():
			break
	assert_bool(await _await_beat_active(screen)).is_true()
	screen._suspicion.skip_beat()
	for i in 6:
		await get_tree().process_frame
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])).is_equal(
		String(IntroPresenter.VARIANT_LOSS_RESTART))
	screen.queue_free()
	await get_tree().process_frame
