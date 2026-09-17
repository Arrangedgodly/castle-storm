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
##     untouched — a refused petition never arms), retreat is free,
##     focus seeds on RETREAT (the safe verb) and COMMIT is a TWO-PRESS
##     raise — the first press only ARMS (the printed caution, the
##     re-labeled chip, nothing submitted), the second casts the die
##     (the harden round's P1: one mispressed Enter or pad-A never
##     decides the run; the x3 input-mode legs live in the parity
##     matrix, section D);
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
##
## WAITING STRATEGY (T-UI-05 fix round — the harness budget): the
## vignette's authored pacing is real SceneTreeTimers + Tweens living in
## GAME code (untouchable here), so this suite INJECTS TIME instead of
## waiting the wall clock: `Engine.time_scale = WATCH_SCALE` makes every
## beat timer, march tween and wash tween advance ~60x per frame, and a
## watched ~10s paced replay costs ~0.17s of wall while the REAL paced
## path still runs end to end (every await, tween, generation guard and
## signal order — the settled-state contract is separately pinned by the
## cold-twin test, which needs no time at all). The scale stays below
## every pinned in-flight window (nothing here asserts mid-motion against
## frame counts; all waits are state polls with generous frame caps), and
## after() restores 1.0 so no sibling suite ever sees the fast clock.
## (Finishing #5 re-dispatch: 20 -> 60 — the polls-only premise is
## unchanged, the same trim the harness budget demanded.)
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const AssaultScreenScript := preload("res://ui/screens/assault/assault_screen.gd")

## Injected-time scale for watched pacing (see WAITING STRATEGY above).
const WATCH_SCALE := 60.0

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


func before_test() -> void:
	Engine.time_scale = WATCH_SCALE


func after() -> void:
	Engine.time_scale = 1.0  # never leak the injected fast clock
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


## L2-B: when a CAPTURED garrison stands, the castle card's composition
## line names WHOSE veterans hold the wall and which cycle — through the
## CopyDeck escalation key, the leader's FIRST name (the single-line pool
## rule), the numbers the resolver derived. A static wall keeps the
## regime arithmetic line, and the view carries the transparency set only
## when escalation is active.
func test_escalation_garrison_line_names_the_veterans() -> void:
	var host := _test_host(20261201)  # gilded_crown: snapshot garrison x1.2
	host.meta.escalation_garrison = {
		"regime_id": "gilded_crown", "captured_at_run": 3, "cycle": 2,
		"leader": "Bartholomew the Unbearable", "crest_id": "crest_gilded_crown",
		"roster": {"knight": {"count": 1, "gear_tiers": {"weapon": {"1": 1}}}},
	}
	host.meta.escalation_cycle = 2
	var odds := host.assault().assault_odds(host.engine)
	var view := AssaultPresenter.odds_view(odds)
	# The transparency set rides the view (L2-C's data), additive-only.
	assert_str(String(view["garrison_source"])).is_equal("escalation")
	assert_int(view["garrison_cycle"]).is_equal(2)
	assert_int(view["garrison_snapshot_power"]).is_equal(12)  # knight 10 + t1 weapon 2
	assert_int(view["garrison_base"]).is_equal(13)  # 12 x 1.10 (one hop), floored
	assert_str(String(view["garrison_leader"])).is_equal("Bartholomew the Unbearable")
	assert_str(String(view["garrison_crest_id"])).is_equal("crest_gilded_crown")
	assert_int(view["garrison_captured_at_run"]).is_equal(3)
	# The line: whose veterans, which cycle — first name only.
	assert_str(AssaultPresenter.garrison_line(view, "The Gilded Crown")) \
		.is_equal("garrison 13 · Bartholomew's veterans — cycle 2")
	# The static wall keeps the regime arithmetic line (no escalation keys).
	var plain := _test_host(20261200)
	var plain_view := AssaultPresenter.odds_view(plain.assault().assault_odds(plain.engine))
	assert_bool(not plain_view.has("garrison_source")).is_true()
	assert_str(AssaultPresenter.garrison_line(plain_view, "The Gilded Crown")).contains("walls")


## THE COMPOSITION LINE NEVER DOUBLES THE ARTICLE (the closing critique's
## P2, "Against the The Paper Crown"): regime display names carry their own
## "The", so the odds screen's opening print composes through the article
## seam (Inks.regime_with_article). Pinned on the REAL template for EVERY
## shipped regime name — the four known seed->regime draws — plus the
## garrison fallback branch and the article seam's own fallbacks.
func test_composition_line_never_doubles_the_article() -> void:
	# One seed per regime flavor (the balance band's own fixed map).
	var regime_seeds := {
		"gilded_crown": 20261201, "velvet_fist": 20261202,
		"paper_crown": 20261203, "iron_rotunda": 20261207,
	}
	var drawn: Array[String] = []
	for regime_id in regime_seeds.keys():
		var host := _test_host(int(regime_seeds[regime_id]))
		assert_str(String(host.run().regime_id())).is_equal(regime_id)
		drawn.append(regime_id)
		var assault: AssaultScreenScript = AssaultScreenScript.new()
		assault.host = host
		assault._view = AssaultPresenter.odds_view(host.assault().assault_odds(host.engine))
		var line: String = assault._composition_line()
		var name := Inks.regime_name(host.run().regime_id())
		# The real print names the regime exactly once, article and all…
		assert_str(line).contains("Against %s" % Inks.regime_with_article(name))
		# …and the doubled-article bug is gone at ANY casing.
		assert_bool(line.to_lower().contains("the the")).is_false()
		assert_bool(line.contains("Against The ")).is_true()  # every shipped name carries "The "
		assault.free()
	assert_int(drawn.size()).is_equal(4)  # the whole regime pool was audited
	# The garrison fallback branch (no combat modifier — dead with shipped
	# content, kept honest for the same reason it exists) composes through
	# the same seam.
	var bare := {
		"garrison_multiplier_milli": 1000, "garrison_modifier_kind": "none",
		"garrison_base": 50, "army_multiplier_milli": 1000,
	}
	assert_str(AssaultPresenter.garrison_line(bare, "The Paper Crown")) \
		.is_equal("garrison of The Paper Crown — 50 strong")
	# The seam's own fallbacks read with exactly one article.
	assert_str(Inks.regime_with_article("")).is_equal("the Crown")
	assert_str(Inks.regime_with_article("Crown")).is_equal("the Crown")


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


## The player's two-step raise (the confirm step): arm, then cast. The
## programmatic seam for every test that pins the storm itself — the
## input-mode legs (Enter / pad A / touch tap) live in the parity matrix.
func _confirmed_commit(assault) -> void:
	assault.commit()  # arms: the printed caution, nothing submitted
	assault.commit()  # casts the die


func test_odds_screen_binds_live_parity_and_seeds_retreat() -> void:
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
	# THE SAFE SEED (the harden P1): focus lands on RETREAT — the free
	# verb — so a mispress on open retreats at no cost, never commits.
	# The chips keep grips.
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_str(String(focus.action.get("id", ""))).is_equal("retreat")
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
	# A REFUSED PETITION NEVER ARMS: a second press refuses again — the
	# two-step raise exists to guard the die, never to sneak it past the
	# floor with a double-tap.
	assault.commit()
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


func test_commit_is_two_presses_the_die_never_one_mispress() -> void:
	## THE HARDEN P1: the first COMMIT only ARMS — the clerk's printed
	## caution, the re-labeled chip, NOTHING submitted; the second press
	## casts. One mispress (Enter or pad-A on a stray focus) can never
	## decide the run.
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	# FIRST PRESS — arms. Nothing storm-shaped moves.
	var kinds: Array = []
	host.event_observed.connect(func(event: Dictionary) -> void: kinds.append(event["type"]))
	var hash_before := host.engine.state_hash()
	assault.commit()
	assert_int(assault.state).is_equal(assault.State.ODDS)
	var printed := assault.stage().printed_lines()
	assert_str(String(printed[printed.size() - 1]["text"])).contains("die is cast")
	# The chip NAMES its next press (state in text, never hue alone) and
	# focus returns to the armed verb — the confirming press lands there.
	assert_str(String(assault.stage().chips()[0].action["label"])).contains("die is cast")
	await get_tree().process_frame
	var focus := get_viewport().gui_get_focus_owner()
	assert_str(String(focus.action.get("id", ""))).is_equal("commit")
	host.fast_forward(3)
	var assault_kinds := kinds.filter(func(kind): return String(kind).begins_with("assault"))
	assert_int(assault_kinds.size()).is_zero()  # no roll, no beat, nothing
	assert_int(host.engine.state_hash()).is_not_equal(hash_before)  # only time passed
	# SECOND PRESS — the die is cast.
	assault.commit()
	assert_int(assault.state).is_not_equal(assault.State.ODDS)
	# One settle frame: the cast clears the chips (their queue_free needs
	# an idle before the suite's orphan audit).
	await get_tree().process_frame
	screen.queue_free()


func test_armed_die_walks_away_free_and_reopens_unarmed() -> void:
	## The armed confirmation never traps: BACK retreats at no cost from
	## the armed table, and a re-open starts the pen fresh — one press
	## ARMS again, it does not cast.
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _open_assault(screen)
	var assault := screen._assault
	assault.commit()  # arm
	assert_int(assault.state).is_equal(assault.State.ODDS)
	assault._unhandled_input(_action_event(&"back"))  # the input path
	await get_tree().process_frame
	assert_bool(assault.is_open()).is_false()
	await _open_assault(screen)
	assert_int(assault.state).is_equal(assault.State.ODDS)
	assault.commit()
	assert_int(assault.state).is_equal(assault.State.ODDS)
	var printed := assault.stage().printed_lines()
	assert_str(String(printed[printed.size() - 1]["text"])).contains("die is cast")
	# One settle frame (the arm re-laid the chips this same frame).
	await get_tree().process_frame
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
	_confirmed_commit(assault)
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
	_confirmed_commit(assault)
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
	_confirmed_commit(assault)
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
	_confirmed_commit(assault)
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
	_confirmed_commit(assault)
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


## Finishing #4 (the portrait odds lane's dead band): the vertical reserve
## is SPENT — the tally prints mid-lane between the castle and the host,
## the corridor below the castle is the battle line's reserved field, the
## ranks stack taller at the foot. The occupancy measure: the largest
## contiguous barren vertical band between the title and the chronicle
## foot (the odds state's visible ground, the quote band included since
## the outcome print owns it but the odds state leaves it empty) must
## stay under 25% at every roster — small rosters are the critique's case.
func test_portrait_lane_spends_the_vertical_reserve() -> void:
	for bounds in [Vector2(720, 1280), Vector2(800, 1280)]:
		var layout := AssaultStage.lane_layout(true, bounds)
		var castle: Rect2 = layout["castle"]
		var meter: Rect2 = layout["meter"]
		var army: Rect2 = layout["army"]
		var line: Rect2 = layout["line"]
		# The tally is MID-LANE: strictly between the castle and the host.
		assert_float(meter.position.y).is_greater(castle.end.y)
		assert_float(meter.end.y).is_less(army.position.y)
		# The corridor is the battle line's field: standoff gap off the
		# castle walls, centered on the castle, clear of the tally.
		assert_float(line.position.y).is_equal_approx(castle.end.y + 10.0, 0.01)
		assert_float(line.end.y).is_less_equal(meter.position.y)
		assert_float(line.get_center().x).is_equal_approx(castle.get_center().x, 0.01)
		assert_float(line.position.x).is_greater_equal(13.5)
		assert_float(line.end.x).is_less_equal(float(bounds.x) - 13.5)
		# The taller-ranks lever actually delivered at small rosters.
		var tall := AssaultStage.army_card_size(army, 6, AssaultStage.RANK_MAX_H_PORTRAIT)
		var cap := AssaultStage.army_card_size(army, 6)
		assert_float(tall.y).is_greater(cap.y)
		# Occupancy: no contiguous barren vertical band over 25% at ANY
		# roster (small rosters are the finding; large ones for honesty).
		var title: Rect2 = layout["title"]
		var chronicle: Rect2 = layout["chronicle"]
		var top := title.end.y + 10.0
		var bottom := chronicle.position.y - 10.0
		for count in [1, 2, 3, 4, 5, 6, 8, 11, 24]:
			var seats: Array[Vector2] = AssaultStage.army_seats(army, count, AssaultStage.RANK_MAX_H_PORTRAIT)
			var card := AssaultStage.army_card_size(army, count, AssaultStage.RANK_MAX_H_PORTRAIT)
			var intervals: Array = []
			for rect in [castle, meter]:
				if (rect as Rect2).position.y < bottom and (rect as Rect2).end.y > top:
					intervals.append([maxf((rect as Rect2).position.y, top), minf((rect as Rect2).end.y, bottom)])
			for seat in seats:
				intervals.append([seat.y, seat.y + card.y])
			intervals.sort_custom(func(a, b): return a[0] < b[0])
			var merged: Array = []
			for interval in intervals:
				if merged.is_empty() or interval[0] > merged[merged.size() - 1][1]:
					merged.append([interval[0], interval[1]])
				else:
					merged[merged.size() - 1][1] = maxf(merged[merged.size() - 1][1], interval[1])
			var worst := 0.0
			var cursor := top
			for interval in merged:
				worst = maxf(worst, interval[0] - cursor)
				cursor = maxf(cursor, interval[1])
			worst = maxf(worst, bottom - cursor)
			assert_float(100.0 * worst / (bottom - top)).is_less_equal(25.0)


## Finishing #4's other half: the landscape lane is UNTOUCHED — every
## rect bit-identical to the pre-refinement formulas (probed at the two
## landscape common sizes and pinned here so any drift fails loudly).
func test_landscape_lane_rects_pinned_bit_identical() -> void:
	var pinned: Array[Dictionary] = [
		{
			"bounds": Vector2(1280, 800),
			"title": Rect2(Vector2(14.0, 16.0), Vector2(1252.0, 46.0)),
			"meter": Rect2(Vector2(14.0, 72.0), Vector2(1252.0, 86.0)),
			"castle": Rect2(Vector2(1056.0, 200.0), Vector2(210.0, 272.0)),
			"army": Rect2(Vector2(14.0, 168.0), Vector2(1022.0, 336.0)),
			"chronicle": Rect2(Vector2(14.0, 616.0), Vector2(1252.0, 96.0)),
			"quote": Rect2(Vector2(14.0, 514.0), Vector2(1252.0, 92.0)),
			"actions": Rect2(Vector2(14.0, 726.0), Vector2(1252.0, 60.0)),
		},
		{
			"bounds": Vector2(1920, 1080),
			"title": Rect2(Vector2(14.0, 16.0), Vector2(1892.0, 46.0)),
			"meter": Rect2(Vector2(14.0, 72.0), Vector2(1892.0, 86.0)),
			"castle": Rect2(Vector2(1696.0, 340.0), Vector2(210.0, 272.0)),
			"army": Rect2(Vector2(14.0, 168.0), Vector2(1662.0, 616.0)),
			"chronicle": Rect2(Vector2(14.0, 896.0), Vector2(1892.0, 96.0)),
			"quote": Rect2(Vector2(14.0, 794.0), Vector2(1892.0, 92.0)),
			"actions": Rect2(Vector2(14.0, 1006.0), Vector2(1892.0, 60.0)),
		},
	]
	for pin in pinned:
		var layout := AssaultStage.lane_layout(false, pin["bounds"])
		for key in ["title", "meter", "castle", "army", "chronicle", "quote", "actions"]:
			var rect: Rect2 = layout[key]
			var want: Rect2 = pin[key]
			assert_float(rect.position.x).is_equal_approx(want.position.x, 0.01)
			assert_float(rect.position.y).is_equal_approx(want.position.y, 0.01)
			assert_float(rect.size.x).is_equal_approx(want.size.x, 0.01)
			assert_float(rect.size.y).is_equal_approx(want.size.y, 0.01)
	# The landscape rank fit keeps the shared print-scale cap (the taller
	# portrait cap must not leak across topologies).
	var band := Rect2(Vector2(14, 168), Vector2(1022, 336))
	assert_float(AssaultStage.army_card_size(band, 6).y).is_equal(132.0)
	assert_float(AssaultStage.army_card_size(band, 6, 132.0).y).is_equal(
		AssaultStage.army_card_size(band, 6).y)


## Finishing #4, the re-layout's focus contract: an orientation swap
## while the odds table is open re-lays the siege lane WITHOUT touching
## the chips — focus stays on the safe verb, the chain stays cyclic.
func test_odds_focus_chain_survives_the_relayout() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _knight_host(WIN_SEED, 2)
	var screen: SpreadScreen = await _mounted_screen(host)
	var router: LayoutRouter = screen.get_router()
	for i in 240:
		await get_tree().process_frame
		if router.is_portrait():
			break
	assert_bool(router.is_portrait()).is_true()
	await _open_assault(screen)
	var assault := screen._assault
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_str(String((focus as BaseButton).action.get("id", ""))).is_equal("retreat")
	# The chain is a cyclic trap across the chips in print order.
	var walked: Array[String] = []
	var cursor: Control = focus
	for i in 4:
		walked.append(String((cursor as BaseButton).action.get("id", "")))
		var next: Control = cursor.get_node(cursor.focus_next) as Control
		assert_that(next).is_not_null()
		cursor = next
	assert_str(",".join(walked)).is_equal("retreat,commit,retreat,commit")
	# Swap topology under the open table: rects re-lay, focus never strands.
	for orientation in [1, 0, 1]:  # landscape, portrait, landscape
		router.force_orientation(orientation)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(assault.is_open()).is_true()
		var owner: Control = get_viewport().gui_get_focus_owner()
		assert_that(owner).is_not_null()
		assert_str(String((owner as BaseButton).action.get("id", ""))).is_equal("retreat")
		assert_int(assault.stage().chips().size()).is_equal(2)
		# The lane actually re-laid per topology (the structure flipped).
		var relaid: Dictionary = assault.stage()._layout
		var castle_r: Rect2 = relaid["castle"]
		var army_r: Rect2 = relaid["army"]
		if orientation == 1:
			assert_float(castle_r.position.x).is_greater_equal(army_r.end.x - 0.01)
		else:
			assert_float(army_r.position.y).is_greater((relaid["meter"] as Rect2).end.y)
			assert_float(castle_r.end.y).is_less((relaid["meter"] as Rect2).position.y)
	router.clear_forced()
	screen.queue_free()


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
