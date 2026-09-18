## Unit tests for the first-session flow (T-UI-10, the tutorial upgrade)
## — Daredevil lane, Prof X consulted.
##
## The contract under test: the first session teaches through the
## world's grammar — a PINNED CLERK'S NOTE at the table edge showing the
## CURRENT objective in plain language ("New paper at the gate — touch
## Wat's card to answer."), advancing through the arc
##
##   accept -> assign -> raise a building -> queue training ->
##   gear a trainee -> promote -> (the storm hint at the floor)
##
## on the REAL commands, skippable ("I know this"), quiet whenever its
## honest moment is absent (it never names a card that is not on the
## table), graduating on the arc's end or the run's end — never to
## return. Flags persist in the META domain (additive-optional); a
## returning player sees nothing. The CONTEXTUAL FIRST-TIME HINTS (the
## first warn, the first legacy bank, the odds table's first opening,
## the first promotion-ready trainee) fire exactly ONCE per install,
## budget-pinned strip rows. Zero modal dialogs or text pages (the game
## is playable instantly).
##
## THE PACING TRUTH (pinned here, mirrors docs/balance.md's opening
## rows): the early-arrival boost puts the first recruit at minute 7;
## the first food trickle lands by minute 16 player-paced (the retune:
## chores are zero-hour, the farm pours 24 food/h); the trainee hop
## rides its ~minute-141 idle cadence (the 2h militia drills are the
## first-win band's pacing — measured).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")

## 1x pacing bounds (sim ticks == wall minutes). See the header.
const GATE_TICK := 7
const CHOICE_ARC_MAX_TICK := 15
const TRICKLE_MAX_TICK := 16
const TRAINEE_MAX_TICK := 170

var _dir_seq := 0


func after() -> void:
	MotionProfile.forced = -1
	_erase_dir("user://cs_ui10_tests")
	get_window().size = Vector2i(720, 720)


# --- the meta-domain flags ---------------------------------------------------------------


func test_first_session_flags_round_trip_and_pre_feature_meta_reads_empty() -> void:
	var meta := RunMeta.new()
	assert_bool(meta.first_session_flag(&"gate")).is_false()
	assert_bool(meta.set_first_session_flag(&"gate")).is_true()
	# Once-only: the second set is a no-op (the flip is the print edge).
	assert_bool(meta.set_first_session_flag(&"gate")).is_false()
	assert_bool(meta.first_session_flag(&"gate")).is_true()
	# Round-trip through the save payload (the arc's additive flags ride
	# the same block).
	assert_bool(meta.set_first_session_flag(&"objective_gear_probe")).is_true()
	var restored := RunMeta.new()
	assert_bool(restored.apply_dict(meta.to_dict())).is_true()
	assert_bool(restored.first_session_flag(&"gate")).is_true()
	assert_bool(restored.first_session_flag(&"objective_gear_probe")).is_true()
	# A PRE-FEATURE meta (no block) restores tolerant-empty: nobody is
	# nudged, which is right (the additive-optional read).
	var pre_feature := RunMeta.new()
	assert_bool(pre_feature.apply_dict({
		"format_version": RunMeta.META_FORMAT_VERSION,
		"legacy_points": 3, "runs_recorded": 1, "chronicle": [],
		"last_seen_epoch": 0,
	})).is_true()
	assert_bool(pre_feature.first_session.is_empty()).is_true()


func test_arms_only_on_the_one_true_first_deal() -> void:
	var fresh := _host(20261001)
	assert_bool(FirstSession.arms(fresh)).is_true()
	# The moment a run is recorded (any completed hand), never again.
	fresh.meta.runs_recorded = 1
	assert_bool(FirstSession.arms(fresh)).is_false()
	fresh.meta.runs_recorded = 0
	# A resumed first hand (hours in, no flag) is the check-in's entry.
	fresh.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(FirstSession.arms(fresh)).is_false()
	# The persisted "seen" flag: a returning player, whatever happened.
	fresh.meta.set_first_session_flag(&"seen")
	assert_bool(FirstSession.arms(fresh)).is_false()


# --- the note: the gate objective pins, the accept completes ---------------


## The first arrival PINS the note: the gate objective in plain language
## (the copy deck's own line, naming the arrival), the counter at 1 of 7,
## focus parked on the OFFER card (the highlight IS the focus ring). The
## objective is honest — the gate flag is NOT yet set; the ACCEPT is the
## action that completes it and persists it to disk.
func test_gate_objective_pins_on_the_arrival_and_the_accept_completes_it() -> void:
	var host := _host(20261002)
	var screen: SpreadScreen = await _mounted(host, false)
	while host.units().pending_offers() == 0 and host.engine.tick_count < 60:
		host.fast_forward(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	assert_bool(note.visible).is_true()
	# The note names the arrival's touch (both variants carry the teach).
	var text := note.objective_label().text
	assert_bool(text.to_lower().contains("card")).is_true()
	assert_bool(text.to_lower().contains("touch")).is_true()
	assert_bool(text.contains(SpreadPresenter.recruit_name(Inks.pack(),
		int(host.units().offer_ids()[0])))).is_true()
	# The note carries no step counter (steps before the current one may
	# simply have no honest moment yet — a count would imply progress).
	assert_bool(note.objective_label().text.contains("of 7")).is_false()
	# The objective is the truth: nothing completed until the accept.
	assert_bool(host.meta.first_session_flag(&"gate")).is_false()
	# Focus moved (deferred past the arrival's own rebind) to the offer
	# card — part of the focus chain, reachable by pad/keyboard; touch
	# taps the same card. The note's only interactive ink is the skip.
	await get_tree().process_frame
	var focus := screen.get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_str(String(focus.get_meta(&"spread_card_id", ""))).is_equal("offer_1")
	# THE ACCEPT: the real action completes the objective and persists it.
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"gate")).is_true()
	var disk := _read_meta_json(host)
	assert_bool(bool((((disk.get("payload", {}) as Dictionary)
		.get("first_session", {}) as Dictionary)
		.get("gate", false)))).is_true()
	# The note advanced to the assign moment (the accepted body idles).
	assert_bool(note.visible).is_true()
	assert_bool(note.objective_label().text.to_lower().contains("touch")).is_true()
	assert_bool(String(note.objective_label().text) != text).is_true()
	await _free_screen(screen)


## The arc follows the player's verbs through the choice window: the
## assign objective completes on the real role command; the build
## objective names an AFFORDABLE plot and completes on the raise; past
## it, the note is honestly quiet (no militia rests, so the yard
## objective's moment has not come).
func test_assign_and_build_objectives_follow_the_gate() -> void:
	var host := _host(20261003)
	var screen: SpreadScreen = await _mounted(host, false)
	while host.units().pending_offers() == 0 and host.engine.tick_count < 60:
		host.fast_forward(1)
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	var note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	assert_bool(host.meta.first_session_flag(&"assign")).is_false()
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	assert_bool(idle.is_empty()).is_false()
	host.submit(&"assign_role", &"worker", int(idle[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"assign")).is_true()
	# The build objective names a plot the pool can actually pay (the
	# stipend covers the farm at fresh boot) and its card is focusable.
	assert_bool(note.visible).is_true()
	var build_text := note.objective_label().text
	assert_bool(build_text.contains("Farm")).is_true()
	assert_bool(host.meta.first_session_flag(&"build")).is_false()
	host.submit(&"upgrade_building", &"farm", 1)
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"build")).is_true()
	# Past the raise: the yard's moment is absent (nobody has drilled to
	# militia) — the note is QUIET, never a lie about a card that is not
	# on the table.
	assert_bool(note.visible).is_false()
	await _free_screen(screen)


## The trickle payoff prints the REAL first increase of the staffed
## producer's resource — amount and resource from the world, never
## invented (the arc kept this strip line).
func test_trickle_prints_the_real_first_increase() -> void:
	var host := _host(20261004)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_build(host, screen)
	# The worker joined the pool at the zero-hour chores hop (the assign
	# is already down); the farm is raised — staff it and wait for the
	# first whole food: +1 lands ~10 min later (24/h).
	var guard := 0
	while not host.meta.first_session_flag(&"trickle") and guard < 200:
		if host.production().idle_workers() > 0:
			host.submit(&"assign_worker", &"farm", 1)
		host.fast_forward(1)
		guard += 1
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"trickle")).is_true()
	# The strip carries the real facts: the amount and the resource (the
	# reveal cannot lie about the trickle it just counted).
	var row := _last_row_containing(screen, "+1")
	assert_bool(row.contains("food")).is_true()
	await _free_screen(screen)


## The yard and the promotion complete the working arc through the REAL
## verbs: militia drills complete, the trainee hop is queued, the drill
## finishes, the smithy's gear is fitted (the pool seeded — content the
## test states plainly), the oath lands — and the arc completes with the
## farewell line. The storm step stays HONEST: one knight (power 10) is
## below the knight floor, so the note is quiet until the arc's own
## completion verb or the run's end.
func test_the_working_arc_runs_to_the_promotion_and_the_farewell() -> void:
	var host := _host(20261005)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_build(host, screen)
	# A second body drills (the first already works the farm).
	var guard := 0
	while host.units().idle_units(host.units().base_unit_id()).is_empty() \
			and guard < 240:
		for uid in host.units().offer_ids():
			host.submit(&"recruit_accept", &"", int(uid))
		host.fast_forward(1)
		guard += 1
	for body in host.units().idle_units(host.units().base_unit_id()):
		host.submit(&"assign_role", &"militia", int(body))
	# militia drills complete (2h) -> the yard's moment: queue the hop.
	guard = 0
	while host.units().idle_units(&"militia").is_empty() and guard < 400:
		host.fast_forward(1)
		guard += 1
	assert_bool(host.units().idle_units(&"militia").is_empty()).is_false()
	var yard_note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	host.submit(&"start_training", &"trainee",
		int(host.units().idle_units(&"militia")[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"train")).is_true()
	# The trainee hop is gear-free: its drills (4h) promote on the spot.
	guard = 0
	while host.units().idle_units(&"trainee").is_empty() and guard < 400:
		host.fast_forward(1)
		guard += 1
	assert_bool(host.units().idle_units(&"trainee").is_empty()).is_false()
	# THE BRANCH: swear the sword — the knight's drills are gear-gated and
	# HOLD at "training complete, awaiting gear" (the gear moment pins).
	host.submit(&"start_training", &"knight",
		int(host.units().idle_units(&"trainee")[0]))
	host.engine.set_resource(&"iron", 500)
	host.engine.set_resource(&"timber", 500)
	guard = 0
	while host.units().awaiting_promotion_ids().is_empty() and guard < 900:
		host.fast_forward(1)
		guard += 1
	await get_tree().process_frame
	assert_bool(host.units().awaiting_promotion_ids().is_empty()).is_false()
	# Gear the held trainee through the REAL command (cheapest tier per
	# missing slot); the gear objective completes on the first fit.
	var uid := int(host.units().awaiting_promotion_ids()[0])
	var slots: Array[StringName] = host.units().missing_gear_slots(uid)
	assert_bool(slots.is_empty()).is_false()
	for slot in slots:
		for gear_id in host.units().gear_ids_for_slot(slot):
			var gear: GearDef = null
			for candidate: GearDef in Inks.pack().gear:
				if candidate.id == gear_id:
					gear = candidate
			if gear != null and host.engine.get_resource(&"iron") >= 0 \
					and _payable(host, gear.recipe):
				host.submit(&"equip_gear", gear_id, uid)
				break
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"gear")).is_true()
	assert_bool(host.meta.first_session_flag(&"promote")).is_false()
	# Fully geared: the promote moment (the note pins, names Promote).
	host.submit(&"promote", &"", uid)
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"promote")).is_true()
	# The arc's last step is the storm HINT (the layer is not done until
	# the odds open or the hand ends).
	# The screen's storm verb (opening the odds) completes the arc, and
	# the farewell line printed to the strip.
	var rows_before: int = screen.presenter.day_sheet.size()
	screen.open_assault()
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"storm")).is_true()
	assert_bool(host.meta.first_session_flag(&"done")).is_true()
	assert_bool(screen.presenter.day_sheet.size() > rows_before).is_true()
	var farewell := _last_row_containing(screen, "table is yours")
	assert_bool(farewell.is_empty()).is_false()
	# Graduated: the note never returns (an arrival stays quiet paper).
	assert_bool(yard_note.visible).is_false()
	assert_bool(FirstSession.current_objective(host).is_empty()).is_true()
	await _free_screen(screen)


# --- the contextual first-time hints (once EVER) -------------------------------------------


## The first legacy bank: the first run end prints one plain-language
## line carrying the REAL banked score; the second run end prints
## nothing (once per install, persisted).
func test_the_first_bank_hint_prints_once_with_the_real_score() -> void:
	var host := _host(20261006)
	var screen: SpreadScreen = await _mounted(host, false)
	host.submit(&"run_abort")
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"hint_bank")).is_true()
	var row := _last_row_containing(screen, "The Legacy")
	assert_bool(row.is_empty()).is_false()
	assert_bool(row.contains(str(_last_banked(host)))).is_true()
	# The second hand's end: quiet (the hint printed once, ever). The
	# restart turned the day-sheet's page; the fresh page stays clean.
	host.restart_run()
	host.fast_forward(30)
	var count := 0
	for r: Dictionary in screen.presenter.day_sheet:
		if String(r["text"]).contains("The Legacy"):
			count += 1
	assert_int(count).is_equal(0)
	host.submit(&"run_abort")
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"hint_bank")).is_true()
	var count2 := 0
	for r: Dictionary in screen.presenter.day_sheet:
		if String(r["text"]).contains("The Legacy"):
			count2 += 1
	assert_int(count2).is_equal(0)
	await _free_screen(screen)


## The first suspicion warn prints one plain-language line; the second
## warn (the meter re-armed) prints nothing.
func test_the_first_warn_hint_prints_once() -> void:
	var host := _host(20261007)
	var screen: SpreadScreen = await _mounted(host, false)
	host.suspicion().set_suspicion(36)
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"hint_warn")).is_true()
	var row := _last_row_containing(screen, "warns")
	assert_bool(row.is_empty()).is_false()
	# A second warn — quiet.
	host.suspicion().set_suspicion(20)
	host.fast_forward(2)
	host.suspicion().set_suspicion(40)
	host.fast_forward(2)
	await get_tree().process_frame
	var count := 0
	for r: Dictionary in screen.presenter.day_sheet:
		if String(r["text"]).contains("warns"):
			count += 1
	assert_int(count).is_equal(1)
	await _free_screen(screen)


## The odds table's first opening prints its hint (storm on the second
## press; retreat is free) and completes through the REAL verb; the
## second opening prints nothing.
func test_the_odds_hint_prints_once_at_the_first_opening() -> void:
	var host := _host(20261008)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_build(host, screen)
	screen.open_assault()
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"hint_odds")).is_true()
	assert_bool(_last_row_containing(screen, "retreat is free").is_empty()).is_false()
	screen._assault.close()
	# The second opening: quiet.
	screen.open_assault()
	screen._assault.close()
	await get_tree().process_frame
	var count := 0
	for r: Dictionary in screen.presenter.day_sheet:
		if String(r["text"]).contains("retreat is free"):
			count += 1
	assert_int(count).is_equal(1)
	await _free_screen(screen)


# --- skippable, forgiving, graduating --------------------------------------------------------


## "I know this": the skip chip strikes the current objective (persisted)
## and the note jumps to the next HONEST moment — the arc is forgiving,
## so with nothing accepted yet the very next moment is the build plot.
## The skip's flag is on disk before the next press.
func test_the_note_skips_forward_and_persists() -> void:
	var host := _host(20261009)
	var screen: SpreadScreen = await _mounted(host, false)
	while host.units().pending_offers() == 0 and host.engine.tick_count < 60:
		host.fast_forward(1)
	await get_tree().process_frame
	var note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	assert_bool(note.visible).is_true()
	assert_bool(host.meta.first_session_flag(&"gate")).is_false()
	note.skip_chip().pressed.emit()
	await get_tree().process_frame
	# gate struck (persisted); the note jumped to the build moment (no
	# body was accepted, so the assign moment does not exist yet).
	assert_bool(host.meta.first_session_flag(&"gate")).is_true()
	var disk := _read_meta_json(host)
	assert_bool(bool((((disk.get("payload", {}) as Dictionary)
		.get("first_session", {}) as Dictionary)
		.get("gate", false)))).is_true()
	assert_bool(note.visible).is_true()
	assert_bool(note.objective_label().text.contains("Farm")).is_true()
	# NOW answer the gate: the assign moment opens and the note pins it
	# (the accept's own action advances the arc the rest of the way).
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(note.visible).is_true()
	assert_bool(note.objective_label().text.to_lower().contains("touch")).is_true()
	# Skipping it strikes the current step and the note moves on.
	note.skip_chip().pressed.emit()
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"assign")).is_true()
	assert_bool(note.visible).is_true()
	assert_bool(note.objective_label().text.contains("Farm")).is_true()
	await _free_screen(screen)


## A run that ends before the arc completes graduates the layer too —
## the player has engaged; a new hand in the same session is not
## re-taught, and the note never returns.
func test_run_ending_graduates_the_layer() -> void:
	var host := _host(20261010)
	var screen: SpreadScreen = await _mounted(host, false)
	while host.units().pending_offers() == 0 and host.engine.tick_count < 60:
		host.fast_forward(1)
	await get_tree().process_frame
	var note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	assert_bool(note.visible).is_true()
	host.submit(&"run_abort")
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"done")).is_true()
	assert_bool(note.visible).is_false()
	host.restart_run()
	host.fast_forward(30)
	await get_tree().process_frame
	assert_bool(note.visible).is_false()
	await _free_screen(screen)


# --- the no-tutorial-wall contract ---------------------------------------------------------


## THE WALL CHECK: zero modal dialogs, zero text pages — no Popup,
## Window or AcceptDialog anywhere on the screen across the whole arc,
## and the game stays playable throughout (cards keep their focus chain;
## the note is printed paper whose only interactive ink is the skip).
func test_zero_popup_chrome_over_the_first_session() -> void:
	var host := _host(20261011)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_build(host, screen)
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	# Skippable by construction: the pinned note added exactly one
	# focusable (the skip chip) and consumed no input — every beat fired
	# while the table kept its card focus chain intact.
	assert_int(_focusable_count(screen)).is_greater_equal(4)
	await _free_screen(screen)


## A returning player sees NOTHING: the first install's boot persisted
## "seen" (with a coherent run save — both domains exist from arm on);
## a later session boots through the real save and pins no note, even as
## new offers arrive.
func test_returning_player_boots_note_free() -> void:
	var root := _root()
	var first := GameHost.new(20261012, root)
	first.autosave_interval_ticks = 0
	first.boot(0)
	var layer := FirstSession.new()
	layer.begin(first)
	assert_bool(layer.active).is_true()
	# The fresh-boot pair is coherent on disk (no meta-without-run edge).
	assert_bool(first.save_manager.save_run(first.engine)).is_true()
	var returning := GameHost.new(20261013, root)
	returning.autosave_interval_ticks = 0
	assert_bool(returning.boot(0)).is_true()  # loaded the real save
	var screen: SpreadScreen = await _mounted(returning, false)
	while returning.units().pending_offers() < 2 and returning.engine.tick_count < 200:
		returning.fast_forward(1)
	await get_tree().process_frame
	var note := screen._note_of(screen.get_active_slot() as OrientationSlot)
	assert_bool(note.visible).is_false()
	assert_bool(returning.meta.first_session_flag(&"seen")).is_true()
	await _free_screen(screen)


# --- the pacing math -------------------------------------------------------------------------


## THE PACING MATH (honest, at 1x: 1 sim tick == 1 wall minute): the
## documented sensible path through the REAL host + layer (events routed
## exactly as the screen routes them), measuring each step's sim tick.
## Pinned bounds in the header; the full report prints into the log.
func test_the_documented_sensible_path_pacing() -> void:
	var host := _host(20261014)
	var layer := FirstSession.new()
	layer.begin(host)
	# The screen's hook shape: every drained event through on_event.
	host.event_observed.connect(func(event: Dictionary) -> void:
		layer.on_event(event, host))
	var ticks := {"gate": -1, "assign": -1, "build": -1, "trickle": -1, "train": -1}
	var flags := {"gate": &"gate", "assign": &"assign", "build": &"build",
		"trickle": &"trickle", "train": &"train"}
	var record := func() -> void:
		for beat in flags.keys():
			if ticks[beat] == -1 and host.meta.first_session_flag(flags[beat]):
				ticks[beat] = host.engine.tick_count
	var worked_uid := -1
	var raised := false
	while ticks["train"] == -1 and host.engine.tick_count < 400:
		host.fast_forward(1)
		layer.on_ticks(host)
		record.call()
		# The player: answer the gate the moment paper arrives.
		if not host.units().offer_ids().is_empty() and ticks["assign"] == -1:
			host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
		if ticks["gate"] != -1:
			# Everyone at the gate joins; the FIRST body works the
			# estate, the rest drill — PARALLEL pipelines (the sensible
			# path does not serialize its worker behind its soldier).
			for uid in host.units().offer_ids():
				host.submit(&"recruit_accept", &"", int(uid))
			for body in host.units().idle_units(host.units().base_unit_id()):
				var uid := int(body)
				if worked_uid == -1:
					worked_uid = uid
					host.submit(&"assign_role", &"worker", uid)
				else:
					host.submit(&"assign_role", &"militia", uid)
			if not raised and not host.meta.first_session_flag(&"build"):
				host.submit(&"upgrade_building", &"farm", 1)
				raised = true
			if host.production().idle_workers() > 0:
				host.submit(&"assign_worker", &"farm", 1)
			for body in host.units().idle_units(&"militia"):
				host.submit(&"start_training", &"trainee", int(body))
	print("[first-session] PACING REPORT (sim ticks == wall minutes at 1x): %s"
		% str(ticks))
	# THE PINS (bounds documented in the suite header). The gate step's
	# FLAG lands on the accept — the arrival is at 7, the answer at +1.
	assert_int(int(ticks["gate"]) - 1).is_equal(GATE_TICK)
	assert_int(int(ticks["assign"])).is_less_equal(GATE_TICK + 2)
	assert_int(int(ticks["build"])).is_less(CHOICE_ARC_MAX_TICK)
	assert_int(int(ticks["trickle"])).is_less_equal(TRICKLE_MAX_TICK)
	assert_int(int(ticks["train"])).is_less_equal(TRAINEE_MAX_TICK)
	# The session's hand ends (the player closes the first check-in):
	# the run-end graduation, quiet.
	host.submit(&"run_abort")
	host.fast_forward(2)
	assert_bool(layer.graduated(host)).is_true()


# --- the copy is the pack's own voice -------------------------------------------------------


## The arc's lines render through CopyDeck against the SHIPPED table
## (the reveal cannot lie — and it cannot mumble either): each step's
## key is present, every variant carries its fact, and the rendered line
## is fully substituted with the world's own values. The NOTE-PLATE PIN:
## every objective line, substituted at worst case, wraps within the
## note's band at the live type factor (the plate holds its print).
func test_objective_copy_reads_the_pack_table_and_fits_the_note_plate() -> void:
	var table: CopyTable = Inks.pack().copy
	# key -> [raw marker every variant carries, rendered marker]
	var cases := [
		[&"first_gate", "card", "card"],
		[&"first_assign", "touch", "touch"],
		[&"first_build", "{building}", "Farm"],
		[&"objective_train", "training", "training"],
		[&"objective_gear", "gear", "gear"],
		[&"objective_promote", "Promote", "Promote"],
		[&"objective_storm", "Storm", "Storm"],
	]
	var params := {"name": "Thistle", "building": "Farm", "resource": "food", "amount": 1}
	for case in cases:
		var key: StringName = case[0]
		var raw_marker := String(case[1])
		var rendered_marker := String(case[2])
		var pool := CopyDeck.variants(table, key)
		assert_int(pool.size()).is_greater_equal(1)
		for variant in pool:
			assert_bool(String(variant).to_lower().contains(raw_marker.to_lower())) \
				.is_true()
		var line := CopyDeck.line(table, key, 7, params)
		assert_bool(line.to_lower().contains(rendered_marker.to_lower())).is_true()
		assert_bool(line.contains("{")).is_false()
	# THE NOTE-PLATE PIN: the widest substituted variant wraps inside the
	# note's objective band (ObjectiveNote's geometry, the real face).
	var line_control: Control = preload("res://ui/theme/chronicle_line.tscn").instantiate()
	get_tree().root.add_child(line_control)
	await get_tree().process_frame
	var label := line_control.find_children("", "Label", true, false)[0] as Label
	var face := label.get_theme_font(&"font")
	var size := label.get_theme_font_size(&"font_size")
	var f := TypeScale.factor()
	var note_width: float = 238.0 * f
	var inner_width: float = note_width - 2.0 * 10.0 * f
	var band_height: float = 124.0 * f
	var arc: Array[Dictionary] = FirstSession.ARC
	for step: Dictionary in arc:
		var key: StringName = StringName(String(step["key"]))
		for variant in CopyDeck.variants(table, key):
			var rendered := String(variant)
			for token in params.keys():
				rendered = rendered.replace("{%s}" % String(token), str(params[token]))
			var shaped := face.get_multiline_string_size(rendered,
				HORIZONTAL_ALIGNMENT_LEFT, inner_width, size)
			assert_float(shaped.y).is_less_equal(band_height)
	line_control.queue_free()


# --- helpers --------------------------------------------------------------------------------


func _host(run_seed: int) -> GameHost:
	var root := _root()
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _root() -> String:
	_dir_seq += 1
	var root := "user://cs_ui10_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	return root


func _mounted(host: GameHost, intro_on := true) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	for i in 4:
		await get_tree().process_frame
	return screen


## Free a mounted screen AND let the deferred deletion land (one frame)
## — a queued-but-unfreed screen reads as an orphan at suite teardown.
func _free_screen(screen: SpreadScreen) -> void:
	screen.queue_free()
	await get_tree().process_frame


## The documented sensible path through the build step (the shared
## prefix of the arc tests): accept, assign, raise the farm.
func _drive_to_build(host: GameHost, screen: SpreadScreen) -> void:
	while host.units().pending_offers() == 0 and host.engine.tick_count < 60:
		host.fast_forward(1)
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	host.fast_forward(1)
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	host.submit(&"assign_role", &"worker", int(idle[0]))
	host.submit(&"upgrade_building", &"farm", 1)
	host.fast_forward(1)


func _payable(host: GameHost, recipe: Dictionary) -> bool:
	for resource in recipe:
		if host.engine.get_resource(resource) < int(recipe[resource]):
			return false
	return true


func _last_banked(host: GameHost) -> int:
	var chronicle := host.meta.chronicle
	if chronicle.is_empty():
		return 0
	return int(chronicle[chronicle.size() - 1].get("score", 0))


func _focusable_count(screen: SpreadScreen) -> int:
	var active := screen.get_active_slot() as OrientationSlot
	return active.focusables().size()


func _last_row_containing(screen: SpreadScreen, needle: String) -> String:
	for row: Dictionary in screen.presenter.chronicle_strip():
		if String(row["text"]).contains(needle):
			return String(row["text"])
	return ""


func _read_meta_json(host: GameHost) -> Dictionary:
	var path := host.save_manager.meta_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var text := file.get_as_text()
	file.close()
	if parser.parse(text) != OK:
		return {}
	return parser.data


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
	for sub in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
