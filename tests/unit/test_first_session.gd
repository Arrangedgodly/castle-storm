## Unit tests for the first-session flow (T-UI-10) — Daredevil lane,
## Prof X consulted.
##
## The contract under test (the worker brief + journey 1): the first
## session teaches through the world's grammar — five printed cues
## (gate / assign / build / trickle / train), each appearing ONCE,
## dismissing on action, never repeating across sessions; zero modal
## dialogs or text pages (the game is playable instantly); a returning
## player (persisted flag) sees nothing; the build-order choice is a
## real affordance (staked plot cards with the raise verb); and the
## pacing is measured HONESTLY at 1x (1 sim tick == 1 wall minute):
##
##   THE PACING TRUTH (pinned here, mirrors docs/balance.md's opening
##   rows — the T-SIM-08 follow-up retune): the T-SIM-08 early-arrival
##   boost puts the first recruit at minute 7; the CHOICE arc (gate
##   answered, role chosen, plot raised — every loop verb surfaced, the
##   "I get it" window) completes by minute ~9; the first PAYOFF print —
##   the food trickle — lands at minute 12 (the trickle retune: chores are
##   zero-hour, the farm pours 24 food/h), INSIDE the town-hall's 10–15
##   min first session; the trainee hop stays at ~minute 141 (the 2h
##   militia drills are the band's pacing — measured: cutting them to
##   1.0h/1.5h pushed the first-win tail to 169h past the 132h bound, so
##   the drill time stands and the trainee rides the idle cadence the
##   check-in flow serves).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")

## 1x pacing bounds (sim ticks == wall minutes). See the header: the
## gate pin is T-SIM-08's own "first recruit 7 min exact"; the choice
## arc's <15 bound is journey 1's "I get it" window; the TRICKLE pin is
## the retune's goal (visible inside the first 10-15 min session, with
## headroom for arrival/production drift); the trainee bound guards
## drift, not aspiration.
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
	# Round-trip through the save payload.
	var restored := RunMeta.new()
	assert_bool(restored.apply_dict(meta.to_dict())).is_true()
	assert_bool(restored.first_session_flag(&"gate")).is_true()
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


# --- the screen beats: once, on action, focused ------------------------------------------


## The gate beat: the first arrival prints ONE hint naming the card's
## touch, parks focus on the OFFER card (the affordance highlight is the
## focus ring — the same ring pad/keyboard play sees), and persists the
## flag to disk. The second arrival never re-prints.
func test_gate_hint_prints_once_focuses_the_offer_and_persists() -> void:
	var host := _host(20261002)
	var screen: SpreadScreen = await _mounted(host, false)
	while int(screen.stats[&"first_nudges"]) < 1:
		host.fast_forward(1)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(1)
	assert_bool(host.meta.first_session_flag(&"gate")).is_true()
	# The row is the world's own paper: a strip row in the buffer, its
	# copy from the pack's table, naming the arrival's touch (both
	# variants carry the teach — "touch"/"Touch the card").
	var rows := (screen.presenter.chronicle as Array[Dictionary]) \
		.filter(func(row: Dictionary) -> bool:
			return String(row["text"]).to_lower().contains("touch"))
	assert_int(rows.size()).is_equal(1)
	assert_int(int(rows[0]["class"])).is_equal(Inks.LineClass.PLAIN)
	# Focus moved (deferred past the arrival's own rebind) to the offer
	# card — part of the focus chain (focus_id meta: the router's
	# swap-equivalence key), reachable by pad/keyboard; touch taps the
	# same card. The hint itself owns NO node: the layer is data (a
	# RefCounted, never a Node in the tree — nothing to dismiss, nothing
	# to block input).
	await get_tree().process_frame
	var focus := screen.get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_str(String(focus.get_meta(&"spread_card_id", ""))).is_equal("offer_1")
	assert_bool(focus.has_meta(&"focus_id")).is_true()
	assert_bool(screen.first_session is RefCounted).is_true()
	assert_bool(screen.first_session.get_class() == "RefCounted").is_true()
	# The flag is ON DISK (the once-only guarantee survives a crash one
	# print later): parse the meta save's bytes back — the envelope's
	# payload carries the first-session block.
	var disk := _read_meta_json(host)
	assert_bool(bool((((disk.get("payload", {}) as Dictionary)
		.get("first_session", {}) as Dictionary)
		.get("gate", false)))).is_true()
	# The second arrival (tick 19 on the rush cadence) never re-prints.
	while host.units().arrivals_total < 2:
		host.fast_forward(1)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(1)
	await _free_screen(screen)


## The gate hint dismisses on action and the arc follows the player's
## verbs: accepting prints the assign hint (focus on the estate card),
## and the build-order hint surfaces on the next batch with focus on
## the AFFORDABLE plot — the whole choice arc inside the "I get it"
## window.
func test_assign_and_build_hints_follow_the_gate() -> void:
	var host := _host(20261003)
	var screen: SpreadScreen = await _mounted(host, false)
	while int(screen.stats[&"first_nudges"]) < 1:
		host.fast_forward(1)
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	while int(screen.stats[&"first_nudges"]) < 3:
		host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"assign")).is_true()
	assert_bool(host.meta.first_session_flag(&"build")).is_true()
	var focus := screen.get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	# The build hint highlights the PLOT (the build-order choice's card).
	assert_str(String(focus.get_meta(&"spread_card_id", ""))).is_equal("bld_farm")
	# The printed build hint names a building the pool can actually pay
	# (the stipend covers the farm at fresh boot).
	var build_row := _last_row_containing(screen, "raise")
	assert_bool(String(build_row).contains("Farm")).is_true()
	await _free_screen(screen)


## The trickle beat prints the REAL first increase of the staffed
## producer's resource — amount and resource from the world, never
## invented.
func test_trickle_prints_the_real_first_increase() -> void:
	var host := _host(20261004)
	var screen: SpreadScreen = await _mounted(host, false)
	while int(screen.stats[&"first_nudges"]) < 1:
		host.fast_forward(1)
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	while int(screen.stats[&"first_nudges"]) < 3:
		host.fast_forward(1)
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	host.submit(&"assign_role", &"worker", int(idle[0]))
	host.submit(&"upgrade_building", &"farm", 1)
	# The worker joins the pool at the zero-hour chores hop; the hand goes down
	# the moment one stands ready; +1 food lands ~10 min later.
	while int(screen.stats[&"first_nudges"]) < 4:
		if host.production().idle_workers() > 0:
			host.submit(&"assign_worker", &"farm", 1)
		host.fast_forward(1)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"trickle")).is_true()
	# Both variants carry the real facts: the amount and the resource
	# (the reveal cannot lie about the trickle it just counted).
	var row := _last_row_containing(screen, "+1")
	assert_bool(row.contains("food")).is_true()
	await _free_screen(screen)


## The trainee hop closes the arc: the print lands, the layer
## graduates, and NOTHING prints after (a later arrival stays quiet).
func test_train_hint_closes_the_arc_and_graduates() -> void:
	var host := _host(20261005)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_trickle(host, screen)
	# The second arrival (already waiting at the gate by the trickle,
	# tick 19 < 49) drills; the trainee hop is queued the moment the 2h
	# drills complete.
	while host.units().idle_units(host.units().base_unit_id()).is_empty() \
			and host.engine.tick_count < 200:
		for uid in host.units().offer_ids():
			host.submit(&"recruit_accept", &"", int(uid))
		host.fast_forward(1)
	for body in host.units().idle_units(host.units().base_unit_id()):
		host.submit(&"assign_role", &"militia", int(body))
	var nudges := int(screen.stats[&"first_nudges"])
	while host.units().idle_units(&"militia").is_empty() \
			and host.engine.tick_count < 400:
		host.fast_forward(1)
	host.submit(&"start_training", &"trainee",
		int(host.units().idle_units(&"militia")[0]))
	host.fast_forward(1)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(nudges + 1)
	assert_bool(host.meta.first_session_flag(&"train")).is_true()
	assert_bool(host.meta.first_session_flag(&"done")).is_true()
	# Graduated: a third arrival prints the world's own row, no nudge.
	var before := int(screen.stats[&"first_nudges"])
	while host.units().arrivals_total < 3:
		host.fast_forward(1)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(before)
	await _free_screen(screen)


# --- the no-tutorial-wall contract ---------------------------------------------------------


## THE WALL CHECK: zero modal dialogs, zero text pages — no Popup,
## Window or AcceptDialog anywhere on the screen across the whole arc,
## and the game stays playable throughout (cards keep their focus chain;
## the hint rows are printed paper, never interactive chrome).
func test_zero_popup_chrome_over_the_first_session() -> void:
	var host := _host(20261006)
	var screen: SpreadScreen = await _mounted(host, false)
	_drive_to_trickle(host, screen)
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	# Skippable by construction: the nudge added no focusable node and
	# consumed no input — every beat fired while the table kept its
	# card focus chain intact.
	assert_int(_focusable_count(screen)).is_greater_equal(4)
	await _free_screen(screen)


## A returning player sees NOTHING: the first install's boot persisted
## "seen" (with a coherent run save — both domains exist from arm on);
## a later session boots through the real save and prints no nudges,
## even as new offers arrive.
func test_returning_player_boots_nudge_free() -> void:
	var root := _root()
	var first := GameHost.new(20261007, root)
	first.autosave_interval_ticks = 0
	first.boot(0)
	var layer := FirstSession.new()
	layer.begin(first)
	assert_bool(layer.active).is_true()
	# The fresh-boot pair is coherent on disk (no meta-without-run edge).
	assert_bool(first.save_manager.save_run(first.engine)).is_true()
	var returning := GameHost.new(20261008, root)
	returning.autosave_interval_ticks = 0
	assert_bool(returning.boot(0)).is_true()  # loaded the real save
	var screen: SpreadScreen = await _mounted(returning, false)
	while returning.units().arrivals_total < 2:
		returning.fast_forward(1)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(0)
	assert_bool(returning.meta.first_session_flag(&"seen")).is_true()
	await _free_screen(screen)


## A run that ends before the arc completes graduates the layer too —
## the player has engaged; a new hand in the same session is not
## re-taught.
func test_run_ending_graduates_the_layer() -> void:
	var host := _host(20261009)
	var screen: SpreadScreen = await _mounted(host, false)
	while int(screen.stats[&"first_nudges"]) < 1:
		host.fast_forward(1)
	host.submit(&"run_abort")
	host.fast_forward(2)
	await get_tree().process_frame
	assert_bool(host.meta.first_session_flag(&"done")).is_true()
	var before := int(screen.stats[&"first_nudges"])
	host.restart_run()
	host.fast_forward(30)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"first_nudges"])).is_equal(before)
	await _free_screen(screen)


# --- the build-order affordance (the empty spread's menu) ----------------------------------


## The empty spread carries the build order as paper: every unbuilt
## building stakes a plot card (same id the built card keeps — the plot
## RISES in place), and the farm's plot is RAISABLE from the stipend at
## fresh boot.
func test_plot_cards_surface_the_build_order_choice() -> void:
	var host := _host(20261010)
	var cards := SpreadPresenter.cards_view(host)
	var plots: Array[Dictionary] = []
	for card: Dictionary in cards:
		if card["kind"] == &"building":
			plots.append(card)
	assert_int(plots.size()).is_equal(4)  # the pack's whole build order
	for plot in plots:
		assert_str(String(plot["role"])).contains("staked plot")
		assert_bool(Inks.EDGE_FORM_STATES.has(plot["edge_state"])).is_true()
	var farm := {}
	for plot in plots:
		if String(plot["building_id"]) == "farm":
			farm = plot
	var actions := CardActions.actions_for(host, farm)
	assert_array(_ids(actions)).is_equal(["build"])
	assert_bool(bool(actions[0]["enabled"])).is_true()
	assert_str(String(actions[0]["label"])).contains("Raise")
	assert_str(String(actions[0]["command"])).is_equal("upgrade_building")
	# The raise goes down the real write path and the card becomes the
	# building IN PLACE (same spread id, level plate).
	CardActions.submit(host, actions[0])
	host.fast_forward(1)
	var raised := {}
	for card: Dictionary in SpreadPresenter.cards_view(host):
		if String(card["id"]) == "bld_farm":
			raised = card
	assert_bool(raised.is_empty()).is_false()
	assert_str(String(raised["role"])).contains("level 1")
	# An unpayable plot keeps its verb struck-but-visible (the fan's
	# grammar): the smithy costs 40 timber the fresh pool does hold, so
	# use the poor man's probe — strip the pool and read the reason.
	host.engine.set_resource(&"timber", 0)
	var smithy := {}
	for card: Dictionary in SpreadPresenter.cards_view(host):
		if String(card["id"]) == "bld_smithy":
			smithy = card
	var broke := CardActions.actions_for(host, smithy)
	assert_bool(bool(broke[0]["enabled"])).is_false()
	assert_str(String(broke[0]["reason"])).contains("short")


## THE PACING MATH (honest, at 1x: 1 sim tick == 1 wall minute): the
## documented sensible path through the REAL host + layer (events routed
## exactly as the screen routes them), measuring each beat's sim tick.
## Pinned bounds in the header; the full report prints into the log for
## the production record.
func test_the_documented_sensible_path_pacing() -> void:
	var host := _host(20261011)
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
		if ticks["assign"] != -1:
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
			if not raised:
				host.submit(&"upgrade_building", &"farm", 1)
				raised = true
			if host.production().idle_workers() > 0:
				host.submit(&"assign_worker", &"farm", 1)
			for body in host.units().idle_units(&"militia"):
				host.submit(&"start_training", &"trainee", int(body))
	print("[first-session] PACING REPORT (sim ticks == wall minutes at 1x): %s"
		% str(ticks))
	# THE PINS (bounds documented in the suite header).
	assert_int(int(ticks["gate"])).is_equal(GATE_TICK)
	assert_int(int(ticks["assign"])).is_less_equal(GATE_TICK + 2)
	assert_int(int(ticks["build"])).is_less(CHOICE_ARC_MAX_TICK)
	assert_int(int(ticks["trickle"])).is_less_equal(TRICKLE_MAX_TICK)
	assert_int(int(ticks["train"])).is_less_equal(TRAINEE_MAX_TICK)
	assert_bool(layer.graduated(host)).is_true()


# --- the copy is the pack's own voice -------------------------------------------------------


## Every nudge renders through CopyDeck against the SHIPPED table (the
## reveal cannot lie — and it cannot mumble either): each beat's key is
## present, every variant carries its fact, and the rendered line is
## fully substituted with the world's own values. (The font-metric
## budget pin lives in test_copy_voice.gd's KEY_BUDGETS.)
func test_nudge_copy_reads_the_pack_table_with_markers() -> void:
	var table: CopyTable = Inks.pack().copy
	# key -> [raw marker every variant carries, rendered marker]
	var cases := [
		[&"first_gate", "card", "card"],
		[&"first_assign", "touch", "touch"],
		[&"first_build", "{building}", "Farm"],
		[&"first_trickle", "+{amount}", "+1"],
		[&"first_train", "{name}", "Thistle"],
	]
	var params := {"name": "Thistle", "building": "Farm", "resource": "food", "amount": 1}
	for case in cases:
		var key: StringName = case[0]
		var raw_marker := String(case[1])
		var rendered_marker := String(case[2])
		var pool := CopyDeck.variants(table, key)
		assert_int(pool.size()).is_greater_equal(1)
		# Every variant carries its fact (variety changes the tail,
		# never the teach — the marker-phrase rule).
		for variant in pool:
			assert_bool(String(variant).to_lower().contains(raw_marker.to_lower())) \
				.is_true()
		var line := CopyDeck.line(table, key, 7, params)
		assert_bool(line.to_lower().contains(rendered_marker.to_lower())).is_true()
		assert_bool(line.contains("{")).is_false()


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


## The documented sensible path up to and including the trickle beat
## (the shared prefix of the arc tests).
func _drive_to_trickle(host: GameHost, screen: SpreadScreen) -> void:
	while int(screen.stats[&"first_nudges"]) < 1:
		host.fast_forward(1)
	host.submit(&"recruit_accept", &"", int(host.units().offer_ids()[0]))
	while int(screen.stats[&"first_nudges"]) < 3:
		host.fast_forward(1)
	var idle: Array = host.units().idle_units(host.units().base_unit_id())
	host.submit(&"assign_role", &"worker", int(idle[0]))
	host.submit(&"upgrade_building", &"farm", 1)
	while int(screen.stats[&"first_nudges"]) < 4:
		if host.production().idle_workers() > 0:
			host.submit(&"assign_worker", &"farm", 1)
		host.fast_forward(1)


func _focusable_count(screen: SpreadScreen) -> int:
	var active := screen.get_active_slot() as OrientationSlot
	return active.focusables().size()


func _last_row_containing(screen: SpreadScreen, needle: String) -> String:
	for row: Dictionary in screen.presenter.chronicle_strip():
		if String(row["text"]).contains(needle):
			return String(row["text"])
	return ""


func _ids(actions: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for action in actions:
		ids.append(String(action["id"]))
	return ids


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
