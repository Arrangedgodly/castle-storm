## Unit tests for the assault vignette (T-UI-07) — Daredevil lane,
## Dr Strange consulted (the payoff test).
##
## Mirrors ui/screens/assault/ + the spread seam. What is pinned:
##   - THE PURE LAYERS: confidence bands + meter blocks (permille ->
##     readable confidence), the odds view's parity with the resolver's
##     query (the breakdown sums), BeatScript's fold of a REAL commit's
##     event slice (4 beats, monotone, outcome, casualties) and its
##     hash determinism;
##   - THE ODDS SCREEN: binds live odds with blocks that equal the
##     query's permille, the knight-floor gate refuses BELOW the floor
##     with a printed reason and WITHOUT submitting (no events, hash
##     untouched), retreat is free, focus lands on COMMIT;
##   - THE VIGNETTE: replays from the event stream alone — the same
##     battle driven through two stages produces the SAME authored
##     visual sequence hash, skip (one input) lands the exact states
##     pacing reaches, reduced motion completes near-instantly with the
##     printed summaries carrying the story;
##   - THE SEAMS: loss = blockquote + aftermath wash + the run still
##     alive with casualties gone from the roster; win = the victory
##     print + the finished("win") handoff (T-UI-05's seam) with the
##     run ended; the storm action opens the table from an army card;
##   - LAYOUT: the pure siege-lane rects (castle at the head/edge) and
##     the mounted screen unclipped at the four common sizes with grips.
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")

## Probed deterministic floor-assault outcomes (2 t1 knights, power 30):
## 20261207 iron_rotunda WINS (army-side modifier); 20261200
## gilded_crown LOSES (garrison-side modifier); 20261203 paper_crown
## LOSES. Probed against the real resolver — re-probe if content moves.
const WIN_SEED := 20261207
const LOSS_SEED := 20261200
const LOSS_SEED_PAPER := 20261203

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
	_erase_dir("user://cs_ui07_tests")
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


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_ui07_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


## One host holding `count` fully-geared, PROMOTED knights (t1 kit) —
## the deterministic floor-state army (power 15 each; 2 = above the
## floor 23, 1 = below it).
func _knight_host(run_seed: int, count: int) -> GameHost:
	var host := _test_host(run_seed)
	var knights: Array[int] = []
	while knights.size() < count:
		while host.units().pending_offers() == 0:
			host.fast_forward(30)
		var uid := host.units().offer_ids()[0]
		host.submit(&"recruit_accept", &"", uid)
		host.fast_forward(10)
		var idle := host.units().idle_units(host.units().base_unit_id())
		assert_int(idle.size()).is_greater(0)
		host.submit(&"assign_role", &"militia", idle[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var militia := host.units().idle_units(&"militia")
		assert_int(militia.size()).is_greater(0)
		host.submit(&"start_training", &"trainee", militia[0])
		host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
		var trainee := host.units().idle_units(&"trainee")
		assert_int(trainee.size()).is_greater(0)
		host.submit(&"start_training", &"knight", trainee[0])
		host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
		assert_bool(host.units().is_awaiting_promotion(trainee[0])).is_true()
		knights.append(trainee[0])
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


func _mounted_screen(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = false  # this suite pins the vignette; the intro's suite owns the restart seam
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _open_assault(screen: SpreadScreen) -> void:
	screen.open_assault()
	await get_tree().process_frame
	await get_tree().process_frame


func _await_assault_state(screen: SpreadScreen, want: int, max_frames := 1500) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if screen._assault.state == want:
			return true
	return false


## The outcome is READY when the wash settled, the chips are laid, and
## the state landed (the paced path sets state before the wash tween
## finishes — the seams must be read settled, not mid-light).
func _await_outcome(screen: SpreadScreen, max_frames := 1500) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		var assault := screen._assault
		if assault.state == assault.State.OUTCOME \
				and assault.stage().chips().size() > 0 \
				and assault.stage().wash > 0.99:
			return true
	return false


func _capture_assault_events(host: GameHost, into: Array) -> void:
	host.event_observed.connect(func(event: Dictionary) -> void: into.append(event))


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- the pure layers ----------------------------------------------------------------------


func test_confidence_bands_and_meter_blocks() -> void:
	assert_str(AssaultPresenter.confidence_words(0)).is_equal("forlorn odds")
	assert_str(AssaultPresenter.confidence_words(199)).is_equal("forlorn odds")
	assert_str(AssaultPresenter.confidence_words(277)).is_equal("poor odds")
	assert_str(AssaultPresenter.confidence_words(500)).is_equal("even odds")
	assert_str(AssaultPresenter.confidence_words(649)).is_equal("even odds")
	assert_str(AssaultPresenter.confidence_words(650)).is_equal("favourable odds")
	assert_str(AssaultPresenter.confidence_words(999)).is_equal("crushing odds")
	assert_str(AssaultPresenter.confidence_line(277)).contains("277 in 1000")
	# Blocks: the meter IS the permille at block resolution, monotone.
	assert_int(AssaultPresenter.meter_blocks(0)).is_zero()
	assert_int(AssaultPresenter.meter_blocks(1000)).is_equal(AssaultPresenter.METER_BLOCKS)
	var last := -1
	for permille in [0, 50, 277, 333, 500, 649, 700, 850, 1000]:
		var blocks := AssaultPresenter.meter_blocks(permille)
		assert_int(blocks).is_greater_equal(last)
		last = blocks
	assert_int(AssaultPresenter.meter_blocks(277)).is_equal(6)


func test_odds_view_parity_with_the_resolver_breakdown() -> void:
	var host := _knight_host(20261213, 2)
	var odds := host.assault().assault_odds(host.engine)
	var view := AssaultPresenter.odds_view(odds)
	assert_int(view["win_permille"]).is_equal(int(odds["win_permille"]))
	assert_int(view["floor_power"]).is_equal(host.assault().knight_floor_power())
	assert_bool(view["floor_met"]).is_true()
	assert_int(view["army_units"]).is_equal(2)
	assert_int(view["army_power"]).is_equal(host.units().army_power())
	# THE BREAKDOWN SUMS: per-unit totals == army power; score == power x
	# multiplier; the two sides reproduce the permille to the digit.
	var total := 0
	for entry: Dictionary in view["roster"]:
		assert_int(int(entry["total"])).is_equal(int(entry["def_power"]) + int(entry["gear_power"]))
		total += int(entry["total"])
	assert_int(total).is_equal(int(view["army_power"]))
	assert_int(int(view["army_score_milli"])).is_equal(
		int(view["army_power"]) * int(view["army_multiplier_milli"]))
	assert_int(int(odds["win_permille"])).is_equal(
		int(view["army_score_milli"]) * 1000
		/ (int(view["army_score_milli"]) + int(view["garrison_strength_milli"])))
	assert_int(view["roster"].size()).is_greater(0)


func test_garrison_and_floor_lines() -> void:
	var host := _knight_host(20261200, 2)  # gilded_crown: garrison x1.2
	var view := AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
	assert_str(AssaultPresenter.garrison_line(view, Inks.regime_name(host.run().regime_id()))) \
		.contains("walls")
	assert_str(AssaultPresenter.floor_line(view)).contains("floor is met")
	# Below the floor the line refuses in print.
	var thin_host := _knight_host(20261200, 1)  # power 15 < 23
	var thin_view := AssaultPresenter.odds_view(thin_host.assault().assault_odds(thin_host.engine))
	assert_bool(thin_view["floor_met"]).is_false()
	assert_str(AssaultPresenter.floor_line(thin_view)).contains("15 mustered")
	assert_str(AssaultPresenter.floor_line(thin_view)).contains("23")


func test_beat_script_folds_a_real_commit() -> void:
	var host := _knight_host(LOSS_SEED, 2)
	var events: Array = []
	_capture_assault_events(host, events)
	host.submit(&"commit_assault")
	host.fast_forward(2)
	var script := BeatScript.build(events)
	assert_bool(BeatScript.holds(script)).is_true()
	assert_str(String(script["outcome"])).is_equal("loss")
	var beats: Array = script["beats"]
	assert_int(beats.size()).is_equal(4)
	assert_str(String(beats[0]["phase"])).is_equal("advance")
	assert_str(String(beats[3]["phase"])).is_equal("rout")
	assert_int(script["casualties"]).is_equal(1)
	# Monotone army milli ending at the TRUE survivors the roster holds
	# (survivor power x the regime's army multiplier, to the milli).
	assert_int(int(beats[3]["army_milli"])).is_less(int(beats[0]["army_milli"]))
	var survivor_mult := int(host.assault().assault_odds(host.engine)["army"]["regime_multiplier_milli"])
	assert_int(int(script["final_army_milli"])) \
		.is_equal(host.units().army_power() * survivor_mult)
	# A malformed stream (3 beats) must not stage.
	var truncated: Array = events.duplicate()
	for i in range(events.size() - 1, -1, -1):
		if events[i]["type"] == &"assault_beat":
			truncated.remove_at(i)
			break
	assert_bool(BeatScript.holds(BeatScript.build(truncated))).is_false()


func test_beat_script_hash_is_event_determined() -> void:
	var events_a := _battle_events(LOSS_SEED)
	var events_b := _battle_events(LOSS_SEED)
	var win_events := _battle_events(WIN_SEED)
	assert_int(BeatScript.visual_sequence_hash(BeatScript.build(events_a))) \
		.is_equal(BeatScript.visual_sequence_hash(BeatScript.build(events_b)))
	assert_int(BeatScript.visual_sequence_hash(BeatScript.build(events_a))) \
		.is_not_equal(BeatScript.visual_sequence_hash(BeatScript.build(win_events)))


func _battle_events(run_seed: int) -> Array:
	var host := _knight_host(run_seed, 2)
	var events: Array = []
	_capture_assault_events(host, events)
	host.submit(&"commit_assault")
	host.fast_forward(2)
	return events


# --- the odds screen -------------------------------------------------------------------------


func test_odds_screen_binds_live_parity_and_focuses_commit() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	assert_bool(assault.is_open()).is_true()
	assert_int(assault.state).is_equal(assault.State.ODDS)
	var odds := host.assault().assault_odds(host.engine)
	assert_int(assault._view["win_permille"]).is_equal(int(odds["win_permille"]))
	assert_int(assault._view["army_power"]).is_equal(host.units().army_power())
	# The meter blocks ARE the permille; the ranked cards ARE the roster.
	assert_int(assault.stage()._army_blocks.filled) \
		.is_equal(AssaultPresenter.meter_blocks(int(odds["win_permille"])))
	assert_int(assault.stage().ranks().size()).is_equal(int(odds["army"]["units"]))
	# No popup chrome anywhere in the vignette.
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	# Focus lands on COMMIT (the bold verb) and the chips keep grips.
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_str(String(focus.action.get("id", ""))).is_equal("commit")
	for chip in assault.stage().chips():
		var min_size: Vector2 = chip.get_combined_minimum_size()
		assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
	screen.queue_free()


func test_knight_floor_gate_refuses_in_print_without_submitting() -> void:
	var host := _knight_host(LOSS_SEED, 1)  # power 15 < floor 23
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	var kinds: Array = []
	host.event_observed.connect(func(event: Dictionary) -> void: kinds.append(event["type"]))
	# The chip prints struck with the floor reason; COMMIT refuses in print.
	var commit_chip: Button = assault.stage().chips()[0]
	assert_bool(bool(commit_chip.action["enabled"])).is_false()
	assert_str(String(commit_chip.action["reason"])).contains("15 mustered")
	assault.commit()
	await get_tree().process_frame
	assert_int(assault.state).is_equal(assault.State.ODDS)
	# Time may pass, but NOTHING assault-shaped was submitted or rolled.
	host.fast_forward(3)
	var assault_kinds := kinds.filter(func(kind): return String(kind).begins_with("assault"))
	assert_int(assault_kinds.size()).is_zero()
	# And the refusal printed on the table (never popup chrome).
	var printed := assault.stage().printed_lines()
	var joined := ""
	for row: Dictionary in printed:
		joined += String(row["text"])
	assert_str(joined).contains("knight floor")
	screen.queue_free()


func test_retreat_from_odds_is_free() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var hash_before := host.engine.state_hash()
	var finished: Array = []
	screen._assault.finished.connect(func(outcome: StringName, _script: Dictionary) -> void:
		finished.append(String(outcome)))
	# BACK retreats (the input path), at no cost.
	screen._assault._unhandled_input(_action_event(&"back"))
	await get_tree().process_frame
	assert_bool(screen._assault.is_open()).is_false()
	assert_array(finished).is_equal([""])
	host.fast_forward(2)
	assert_int(host.engine.state_hash()).is_not_equal(hash_before)  # only time passed
	assert_bool(host.is_run_running()).is_true()
	assert_int(host.units().unit_count(&"knight")).is_equal(2)
	screen.queue_free()


# --- the vignette ------------------------------------------------------------------------------


func test_commit_replays_the_beats_and_lands_the_win_seam() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	var landed: Array = []
	assault.beat_landed.connect(func(_beat: Dictionary, index: int) -> void: landed.append(index))
	var finished: Array = []
	assault.finished.connect(func(outcome: StringName, script: Dictionary) -> void:
		finished.append([String(outcome), BeatScript.visual_sequence_hash(script)]))
	assault.commit()
	assert_bool(await _await_outcome(screen)).is_true()
	# Every beat landed in order; the outcome sealed.
	assert_array(landed).is_equal([0, 1, 2, 3])
	var script: Dictionary = assault._script
	assert_str(String(script["outcome"])).is_equal("win")
	assert_int(int(script["final_garrison_milli"])).is_zero()
	# The aftermath wash settled; the victory print is on the table.
	assert_float(assault.stage().wash).is_greater(0.99)
	assert_str(assault.stage()._outcome_quote.text).contains("THE CASTLE FALLS")
	# THE HANDOFF SEAM: the run ended; closing emits finished("win").
	assert_bool(host.is_run_running()).is_false()
	var chips := assault.stage().chips()
	assert_int(chips.size()).is_equal(1)
	assert_str(String(chips[0].action["label"])).is_equal("Deal the next hand")
	chips[0].pressed.emit()
	await get_tree().process_frame
	assert_array(finished).is_equal([["win", BeatScript.visual_sequence_hash(script)]])
	assert_bool(assault.is_open()).is_false()
	# The spread's ground washed to aftermath under the closed vignette.
	assert_int(SpreadPresenter.phase_for(host)).is_equal(Inks.Phase.AFTERMATH)
	screen.queue_free()


func test_loss_seam_blockquote_and_survivors() -> void:
	var host := _knight_host(LOSS_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	var power_before := host.units().army_power()
	var knights_before: int = host.units().unit_count(&"knight")
	assault.commit()
	assert_bool(await _await_outcome(screen)).is_true()
	var script: Dictionary = assault._script
	assert_str(String(script["outcome"])).is_equal("loss")
	assert_int(script["casualties"]).is_equal(1)
	# The printed blockquote: struck-class record + the aftermath wash.
	assert_str(assault.stage()._outcome_quote.text).contains("THE ASSAULT IS BROKEN")
	assert_float(assault.stage().wash).is_greater(0.99)
	# THE RUN KEEPS RUNNING: casualties real, the conspiracy alive.
	assert_bool(host.is_run_running()).is_true()
	assert_int(host.units().unit_count(&"knight")).is_equal(knights_before - 1)
	assert_int(host.units().army_power()).is_less(power_before)
	# Closing returns to a living spread (TRAINING or READY — never AFTERMATH).
	var chips := assault.stage().chips()
	assert_str(String(chips[0].action["label"])).is_equal("Return to the table")
	chips[0].pressed.emit()
	await get_tree().process_frame
	assert_bool(assault.is_open()).is_false()
	assert_int(SpreadPresenter.phase_for(host)).is_not_equal(Inks.Phase.AFTERMATH)
	screen.queue_free()


func test_vignette_replays_deterministically_from_events_alone() -> void:
	## THE REPLAY CONTRACT: the same battle's events, staged twice,
	## produce the SAME authored visual sequence (the screen's own run
	## vs a twin stage driven beat-by-beat from the same folded script).
	var host := _knight_host(LOSS_SEED_PAPER, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	assault.commit()
	assert_bool(await _await_outcome(screen)).is_true()
	var script: Dictionary = assault._script
	var roster: Array = assault._roster_snapshot
	# The twin: a fresh stage at the SAME geometry (the authored sequence
	# is a function of events + stage geometry — both pinned), the same
	# script + roster, applied cold.
	var twin := AssaultStage.new()
	get_tree().root.add_child(twin)
	twin.regime_id = host.run().regime_id()
	twin.portrait = assault.stage().portrait
	twin.size = assault.stage().size
	twin.position = assault.stage().position
	await get_tree().process_frame
	twin.begin_battle(script, roster)
	for i in (script["beats"] as Array).size():
		twin.apply_beat(i)
	twin.apply_outcome(true)
	twin.wash = 1.0
	twin.seal_sequence()
	var screen_hashes := assault.stage().sequence_hashes()
	var twin_hashes := twin.sequence_hashes()
	assert_int(screen_hashes.size()).is_equal(twin_hashes.size())
	for i in twin_hashes.size():
		assert_int(screen_hashes[i]).is_equal(twin_hashes[i])
	twin.queue_free()
	screen.queue_free()


func test_skip_lands_the_same_states_pacing_reaches() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	assault.commit()
	# Let the first beat land, then ONE INPUT skips the whole vignette.
	assert_bool(await _beat_reached(assault, 0)).is_true()
	assault._unhandled_input(_action_event(&"back"))
	await get_tree().process_frame
	assert_int(assault.state).is_equal(assault.State.OUTCOME)
	# The authored sequence is EXACTLY as long as the paced one (4 beats
	# + outcome + seal) — the skip landed states, it did not skip states.
	assert_int(assault.stage().sequence_hashes().size()).is_equal(6)
	# Every summary printed (skip keeps the story in the record).
	var printed := assault.stage().printed_lines()
	assert_int(printed.size()).is_greater_equal(4)
	for i in 4:
		assert_str(String(printed[printed.size() - 4 + i]["text"])).is_not_empty()
	assert_float(assault.stage().wash).is_greater(0.99)
	assert_str(String(assault._script["outcome"])).is_equal("win")
	screen.queue_free()


func test_reduced_motion_collapses_beats_with_printed_summaries() -> void:
	MotionProfile.forced = 1
	var host := _knight_host(LOSS_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	assault.commit()
	assert_bool(await _await_outcome(screen, 240)).is_true()
	assert_str(String(assault._script["outcome"])).is_equal("loss")
	var printed := assault.stage().printed_lines()
	var joined := ""
	for row: Dictionary in printed:
		joined += String(row["text"]) + "\n"
	assert_str(joined).contains("advances")
	assert_str(joined).contains("tree line")  # the rout summary
	assert_str(assault.stage()._outcome_quote.text).contains("THE ASSAULT IS BROKEN")
	screen.queue_free()


func _beat_reached(assault, index: int, max_frames := 400) -> bool:
	for i in max_frames:
		await get_tree().process_frame
		if assault.current_beat_index() >= index:
			return true
	return false


# --- the storm action + layout ------------------------------------------------------------------


func test_army_cards_carry_the_storm_action_and_it_opens_the_table() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var knight_uid: int = host.units().unit_ids() \
		.filter(func(uid): return host.units().unit_def(uid) == &"knight")[0]
	var card := SpreadPresenter.unit_card_view(host, Inks.pack(), knight_uid)
	var actions := CardActions.actions_for(host, card)
	assert_int(actions.size()).is_equal(1)
	assert_str(String(actions[0]["id"])).is_equal("storm")
	assert_bool(bool(actions[0]["enabled"])).is_true()
	assert_bool(bool(actions[0]["signature"])).is_true()  # the double-rule chip
	# Through the spread's interception: choosing it opens the table.
	var screen: SpreadScreen = await _mounted_screen(host)
	screen._on_action_chosen(actions[0])
	await get_tree().process_frame
	assert_int(screen.stats[&"assaults_opened"]).is_equal(1)
	assert_bool(screen._assault.is_open()).is_true()
	screen.queue_free()


func test_siege_lane_layout_rects() -> void:
	var portrait := AssaultStage.lane_layout(true, Vector2(720, 1280))
	var landscape := AssaultStage.lane_layout(false, Vector2(1280, 800))
	# Portrait: the castle at the HEAD of the table (above the army band).
	var castle_p: Rect2 = portrait["castle"]
	var army_p: Rect2 = portrait["army"]
	assert_float(castle_p.end.y).is_less_equal(army_p.position.y + 0.01)
	# Landscape: the castle on the Crown's edge (right of the army band).
	var castle_l: Rect2 = landscape["castle"]
	var army_l: Rect2 = landscape["army"]
	assert_float(castle_l.position.x).is_greater_equal(army_l.end.x - 0.01)
	# Both: meter at the head, actions at the foot, everything inside.
	for layout in [portrait, landscape]:
		var meter: Rect2 = layout["meter"]
		var actions: Rect2 = layout["actions"]
		assert_float(meter.position.y).is_less(float(actions.position.y))
		for key in ["title", "meter", "castle", "army", "chronicle", "quote", "actions"]:
			var rect: Rect2 = layout[key]
			assert_float(rect.position.x).is_greater_equal(0.0)
			assert_float(rect.position.y).is_greater_equal(0.0)
			assert_float(rect.end.x).is_greater(0.0)
	# Seats: deterministic grid in (band, count) alone.
	var band := Rect2(Vector2(20, 400), Vector2(600, 500))
	assert_int(AssaultStage.army_seats(band, 6).size()).is_equal(6)
	assert_int(AssaultStage.army_seats(band, 6).size()).is_equal(AssaultStage.army_seats(band, 6).size())
	var card_size := AssaultStage.army_card_size(band, 6)
	assert_float(card_size.y).is_greater_equal(63.9)


func test_open_table_unclipped_at_four_sizes() -> void:
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	var router: LayoutRouter = screen.get_router()
	for i in TEST_SIZES.size():
		get_window().size = TEST_SIZES[i]
		for f in 240:
			await get_tree().process_frame
			if router.is_portrait() == EXPECTED_PORTRAIT[i] and router.design_size().x > 1.0:
				break
		if i == 0:
			await _open_assault(screen)
		await get_tree().process_frame
		var design := router.design_size()
		var offenders := _clipped_controls(screen._assault as Control, design)
		for offender in offenders:
			assert_str(offender).is_equal("<no clipping expected>")
		assert_bool(screen._assault.is_open()).is_true()
	# The chips keep their grips at every size; focus never strands.
	for chip in screen._assault.stage().chips():
		var min_size: Vector2 = chip.get_combined_minimum_size()
		assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()


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
