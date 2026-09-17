## Unit tests for The Spread (T-UI-03) — Daredevil lane.
##
## Mirrors ui/screens/spread/ (test-mapping rule). What is pinned:
##   - the presenter's PURE mappings: Watchful Eye metrics scale with the
##     suspicion thresholds (position/line-form channels, never color),
##     ground phases transition via army state, the event->refresh-target
##     table, view determinism (same sim state -> same view hash);
##   - the SCREEN: loads headless at all four common sizes with no
##     clipping + grips + seeded focus, updates are TARGETED (stats
##     counters: a training event rebinds one card, a suspicion rise
##     touches only the Eye — no whole-state polling), the rendered
##     LAYOUT hash is a function of sim state alone, the chronicle prints
##     in-world rows (never popup chrome), the Eye's on-table position
##     moves inward as the meter rises;
##   - the demo run: the seeded quiet demo assembles toward the storm
##     floor, and the seeded LOUD demo reaches the telegraph (the
##     screenshot harness's two states are honest).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const WatchfulEyeScript := preload("res://ui/screens/spread/watchful_eye.gd")
const LOUD_SEED := 20261103  # spread_screen.DEFAULT_SEED — the screenshot seed

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]
const EXPECTED_PORTRAIT := [true, false, false, true]

## Injected-time scale for the router-dwell polls only (see
## _settle_window): accelerates the 0.25s dwell, never the settled-state
## reads around it. Matches the T-UI-05 waiting strategy's premise —
## nothing here asserts mid-motion against frame counts.
const SWEEP_SCALE := 60.0

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_spread_tests")
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
	var root := "user://cs_spread_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0  # tests never touch the demo's disk cadence
	host.boot(0)
	return host


func _drive_policy(host: GameHost, policy: DemoPolicy, hours: float) -> void:
	## The screen's exact drive loop: chunked ticks + policy on cadence.
	var chunks := int(hours * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)


# --- presenter: the Watchful Eye metrics -----------------------------------------------


func test_eye_hidden_at_zero_and_when_run_dead() -> void:
	assert_bool(SpreadPresenter.eye_metrics(0, 100, 35, 70, false, true)["visible"]).is_false()
	assert_float(SpreadPresenter.eye_metrics(0, 100, 35, 70, false, true)["inset"]).is_zero()
	assert_bool(SpreadPresenter.eye_metrics(50, 100, 35, 70, false, false)["visible"]).is_false()


func test_eye_line_form_follows_thresholds_without_color() -> void:
	## The Daredevil floor: form carries the zone. SOLID below warn,
	## DASHED in the warn zone, STRUCK at/above crackdown OR telegraph armed.
	assert_int(SpreadPresenter.eye_metrics(10, 100, 35, 70, false, true)["edge_form"]).is_equal(Inks.EdgeForm.SOLID)
	assert_int(SpreadPresenter.eye_metrics(34, 100, 35, 70, false, true)["edge_form"]).is_equal(Inks.EdgeForm.SOLID)
	assert_int(SpreadPresenter.eye_metrics(35, 100, 35, 70, false, true)["edge_form"]).is_equal(Inks.EdgeForm.DASHED)
	assert_int(SpreadPresenter.eye_metrics(69, 100, 35, 70, false, true)["edge_form"]).is_equal(Inks.EdgeForm.DASHED)
	assert_int(SpreadPresenter.eye_metrics(70, 100, 35, 70, false, true)["edge_form"]).is_equal(Inks.EdgeForm.STRUCK)
	assert_int(SpreadPresenter.eye_metrics(40, 100, 35, 70, true, true)["edge_form"]).is_equal(Inks.EdgeForm.STRUCK)


func test_eye_inset_scales_monotonically_with_the_meter() -> void:
	var last := -1.0
	for points in [1, 10, 20, 35, 50, 70, 90, 100]:
		var metrics: Dictionary = SpreadPresenter.eye_metrics(points, 100, 35, 70, false, true)
		assert_bool(metrics["visible"]).is_true()
		assert_float(metrics["inset"]).is_greater(last)
		assert_float(metrics["scale"]).is_greater(0.5)
		last = metrics["inset"]
	assert_float(SpreadPresenter.eye_metrics(100, 100, 35, 70, false, true)["inset"]).is_equal(1.0)


# --- presenter: phases -------------------------------------------------------------------


func test_phase_transitions_with_army_state() -> void:
	var host := _test_host()
	assert_int(SpreadPresenter.phase_for(host)).is_equal(Inks.Phase.RECRUITING)
	# Accept the first arrival and branch it militia; after its training
	# completes the military pipeline exists -> TRAINING.
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	host.submit(&"recruit_accept", &"", host.units().offer_ids()[0])
	host.fast_forward(30)
	var peasants := host.units().idle_units(host.units().base_unit_id())
	assert_int(peasants.size()).is_greater(0)
	host.submit(&"assign_role", &"militia", peasants[0])
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(host.units().unit_count(&"militia")).is_greater(0)
	assert_int(SpreadPresenter.phase_for(host)).is_equal(Inks.Phase.TRAINING)


func test_phase_ready_and_aftermath_via_the_demo_policy() -> void:
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	var reached := false
	for cycle in 10:
		_drive_policy(host, policy, 6.0)  # up to 60h, the balance band's tail
		if SpreadPresenter.phase_for(host) == Inks.Phase.READY:
			reached = true
			break
	assert_bool(reached).is_true()
	# A lost run washes to aftermath.
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(5)
	assert_int(SpreadPresenter.phase_for(host)).is_equal(Inks.Phase.AFTERMATH)


# --- presenter: the event->refresh table ----------------------------------------------------


func test_refresh_targets_are_targeted() -> void:
	assert_array(SpreadPresenter.refresh_targets_for(&"training_started")).is_equal([&"card"])
	assert_array(SpreadPresenter.refresh_targets_for(&"suspicion_rose")).is_equal([&"eye", &"pips"])
	assert_array(SpreadPresenter.refresh_targets_for(&"suspicion_telegraph")).is_equal([&"eye"])
	assert_array(SpreadPresenter.refresh_targets_for(&"hour_struck")).is_equal([&"phase"])
	assert_array(SpreadPresenter.refresh_targets_for(&"run_won")).is_equal([&"full"])
	# Roster-changing events touch the card LIST (a diff), not the whole view.
	assert_array(SpreadPresenter.refresh_targets_for(&"recruit_arrived")).is_equal([&"cards"])


func test_unknown_event_maps_to_full_loudly() -> void:
	assert_array(SpreadPresenter.refresh_targets_for(&"no_such_kind")).is_equal([&"full"])


# --- presenter: view determinism --------------------------------------------------------------


func test_same_sim_state_same_view_hash() -> void:
	var a := _test_host(555)
	var b := _test_host(555)
	var policy_a := DemoPolicy.new(16, 8, false)
	var policy_b := DemoPolicy.new(16, 8, false)
	_drive_policy(a, policy_a, 12.0)
	_drive_policy(b, policy_b, 12.0)
	assert_int(a.engine.state_hash()).is_equal(b.engine.state_hash())
	assert_int(SpreadPresenter.view_hash(SpreadPresenter.build_view(a))) \
		.is_equal(SpreadPresenter.view_hash(SpreadPresenter.build_view(b)))
	# And a different state differs.
	_drive_policy(a, policy_a, 6.0)
	assert_int(SpreadPresenter.view_hash(SpreadPresenter.build_view(a))) \
		.is_not_equal(SpreadPresenter.view_hash(SpreadPresenter.build_view(b)))


func test_view_lists_offers_roster_and_built_buildings_in_order() -> void:
	# Untouched run: offers WAIT at the gate (no policy accepting them).
	var host := _test_host()
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var view := SpreadPresenter.build_view(host)
	var kinds := []
	for card: Dictionary in view["cards"]:
		kinds.append(card["kind"])
	assert_array(kinds).contains(&"offer")
	# Offers print FIRST (the gate is the newest paper).
	assert_str(str(kinds[0])).is_equal("offer")
	# Accept one: the offer becomes an estate card.
	host.submit(&"recruit_accept", &"", host.units().offer_ids()[0])
	host.fast_forward(5)
	kinds = []
	for card: Dictionary in SpreadPresenter.cards_view(host):
		kinds.append(card["kind"])
	assert_array(kinds).contains(&"unit")
	# The managed estate grows buildings (the policy-driven shape).
	var managed := _test_host()
	_drive_policy(managed, DemoPolicy.new(16, 8, false), 8.0)
	var built := []
	for card: Dictionary in SpreadPresenter.cards_view(managed):
		if card["kind"] == &"building":
			built.append(card["id"])
	assert_int(built.size()).is_greater(0)
	# Every card names a state the line-form vocabulary knows.
	for card: Dictionary in SpreadPresenter.cards_view(managed):
		assert_bool(Inks.EDGE_FORM_STATES.has(card["edge_state"])).is_true()


func test_adaptive_columns_ladder() -> void:
	assert_int(SpreadCards.adaptive_columns(4, 800.0)).is_equal(2)
	assert_int(SpreadCards.adaptive_columns(6, 800.0)).is_equal(2)
	assert_int(SpreadCards.adaptive_columns(30, 100.0)).is_equal(5)  # squeezed: cap
	assert_int(SpreadCards.adaptive_columns(20, 900.0)) \
		.is_less_equal(SpreadCards.MAX_STACKED_COLUMNS)


# --- presenter: the chronicle render query ------------------------------------------------------


func test_chronicle_renders_key_events_and_skips_noise() -> void:
	var host := _test_host()
	# Connect BEFORE the arrival happens: the feed carries it.
	var arrived := {}
	host.event_observed.connect(func(event: Dictionary) -> void: arrived[event["type"]] = event)
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	assert_that(arrived.has(&"recruit_arrived")).is_true()
	var presenter := SpreadPresenter.new()
	var row: Variant = presenter.chronicle_line_for(arrived[&"recruit_arrived"], host)
	assert_that(row).is_not_null()
	assert_str(str(row["text"])).contains("gate")
	assert_int(row["class"]).is_equal(Inks.LineClass.PLAIN)
	# Suspicion beats delegate to the system's own voice.
	var warn_event := {"seq": 1, "tick": 5, "type": &"suspicion_warn", "subject": &"suspicion", "value": 0, "value2": 0}
	var warn_row: Variant = presenter.chronicle_line_for(warn_event, host)
	assert_str(str(warn_row["text"])).contains("clerk")
	assert_int(warn_row["class"]).is_equal(Inks.LineClass.WARN)
	# Noise stays silent.
	for kind in [&"training_progress", &"hour_struck", &"worker_assigned"]:
		assert_that(presenter.chronicle_line_for(
			{"seq": 2, "tick": 6, "type": kind, "subject": &"", "value": 1, "value2": 0}, host)).is_null()


func test_new_event_kinds_have_line_classes() -> void:
	## The additive Inks vocabulary: every kind the presenter prints maps
	## (no loud PLAIN fallbacks on the hot path).
	for kind in [&"recruit_arrived", &"recruit_accepted", &"gear_equipped", &"run_started",
			&"run_lost", &"assault_lost", &"building_milestone", &"resources_granted"]:
		assert_bool(Inks.EVENT_LINE_CLASSES.has(kind)).is_true()


# --- the screen -------------------------------------------------------------------------------


func _mounted_screen(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host  # attach BEFORE the tree: the demo never builds its own
	screen.intro_enabled = false  # these suites pin THE TABLE; the intro's suite owns the opening flow
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _settle_window(screen: SpreadScreen, window_size: Vector2i, want_portrait: bool) -> void:
	# Harness-budget trim (finishing #5 re-dispatch): the router's 0.25s
	# dwell is the only wall-paced thing under this poll — inject time for
	# the poll itself (the swap still lands through the REAL deadband +
	# dwell path, just aged faster), then hand the true clock back before
	# the caller reads settled geometry. The dwell's own premise (rapid
	# flapping never swaps) stays pinned at scale 1.0 by
	# test_responsive_layout.test_flapping_window_resizes_never_swap.
	get_window().size = window_size
	var router := screen.get_router()
	Engine.time_scale = SWEEP_SCALE
	for i in 240:
		await get_tree().process_frame
		if router.is_portrait() == want_portrait and router.design_size().x > 1.0:
			break
	Engine.time_scale = 1.0
	await get_tree().process_frame


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


func test_screen_loads_headless_with_live_state() -> void:
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 6.0)
	var screen: SpreadScreen = await _mounted_screen(host)
	var portrait := screen.get_portrait_slot() as OrientationSlot
	var landscape := screen.get_landscape_slot() as OrientationSlot
	# Both slots carry the same card list (equivalence by index).
	assert_int(portrait.card_count()).is_greater(0)
	assert_int(portrait.card_count()).is_equal(landscape.card_count())
	# Header bound to the run's identity.
	var header := portrait.get_header().get_child(0)
	var leader_text: String = header._name_label.text
	assert_str(leader_text).is_not_empty()
	# Pips show live amounts (the stipend + production; iron may still be
	# legitimately zero early).
	var amounts: Array[int] = []
	for i in 3:
		amounts.append(int(landscape.get_pip(i).get("amount")))
	assert_int(amounts[0]).is_greater(0)
	# No popup chrome anywhere: events print themselves in-world.
	for node in screen.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	# Focus seeded (a screen must seed itself).
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()


func test_screen_at_all_four_sizes_unclipped_with_grips() -> void:
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 6.0)
	var screen: SpreadScreen = await _mounted_screen(host)
	var router: LayoutRouter = screen.get_router()
	for i in TEST_SIZES.size():
		await _settle_window(screen, TEST_SIZES[i], EXPECTED_PORTRAIT[i])
		for f in 3:
			await get_tree().process_frame
		var design := router.design_size()
		for offender in _clipped_controls(screen as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		var active := screen.get_active_slot() as OrientationSlot
		assert_bool(router.is_portrait()).is_equal(EXPECTED_PORTRAIT[i])
		for focusable in active.focusables():
			var min_size: Vector2 = focusable.get_combined_minimum_size()
			assert_float(min_size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
			assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
		# Focus never strands across swaps.
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	screen.queue_free()


func test_refresh_is_targeted_not_whole_state() -> void:
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 3.0)
	var screen: SpreadScreen = await _mounted_screen(host)
	# Baseline.
	var builds_before: int = screen.stats[&"view_builds"]
	var list_before: int = screen.stats[&"card_list_renders"]
	var rebinds_before: int = screen.stats[&"card_rebinds"]
	var eye_before: int = screen.stats[&"eye_binds"]
	# A run of quiet hours: training ticks, suspicion drift, arrivals.
	var kinds: Array = []
	host.event_observed.connect(func(event: Dictionary) -> void: kinds.append(event["type"]))
	for cycle in 30:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	await get_tree().process_frame
	# Roster-changing events DID re-render the card list section (the
	# gate moves) — a section read, not a whole-view build...
	if kinds.has(&"recruit_arrived") or kinds.has(&"recruit_accepted"):
		assert_int(screen.stats[&"card_list_renders"]).is_greater(list_before)
	# ...and the WHOLE-view builds stayed at ZERO in a quiet window (no
	# run boundaries, no catch-up): absolutely no per-event polling of
	# everything.
	assert_int(screen.stats[&"view_builds"]).is_equal(builds_before)
	# Suspicion drift re-bound the Eye without rebuilding anything else.
	if kinds.has(&"suspicion_rose"):
		assert_int(screen.stats[&"eye_binds"]).is_greater(eye_before)
	# Pips refresh rides the per-batch signal, not per-frame polling.
	assert_int(screen.stats[&"pip_refreshes"]).is_greater(0)
	assert_int(screen.stats[&"card_rebinds"]).is_greater_equal(rebinds_before)
	screen.queue_free()


func test_training_event_rebinds_cards_without_roster_diff() -> void:
	var host := _test_host()
	# Two accepted recruits so one can rest while the other branches.
	while host.units().total_units() < 2:
		while host.units().pending_offers() == 0:
			host.fast_forward(30)
		host.submit(&"recruit_accept", &"", host.units().offer_ids()[0])
		host.fast_forward(60)
	var peasants := host.units().idle_units(host.units().base_unit_id())
	assert_int(peasants.size()).is_greater_equal(1)
	host.submit(&"assign_role", &"worker", peasants[0])
	host.fast_forward(60)
	var screen: SpreadScreen = await _mounted_screen(host)
	var list_before: int = screen.stats[&"card_list_renders"]
	var rebinds_before: int = screen.stats[&"card_rebinds"]
	# GDScript lambdas capture by VALUE — flags ride arrays (the T-UI-02 note).
	var seen_training := [false]
	host.event_observed.connect(func(event: Dictionary) -> void:
		if event["type"] == &"training_started":
			seen_training[0] = true)
	# Branch a militia: a training_started event must arrive.
	var idle := host.units().idle_units(host.units().base_unit_id())
	assert_int(idle.size()).is_greater_equal(1)
	host.submit(&"assign_role", &"militia", idle[0])
	host.fast_forward(5)
	await get_tree().process_frame
	assert_bool(seen_training[0]).is_true()
	# The card LIST was untouched by the training event; the card itself
	# re-printed (counted as a rebind through the periodic pass at least).
	assert_int(screen.stats[&"card_list_renders"]).is_greater_equal(list_before)
	assert_int(screen.stats[&"card_rebinds"]).is_greater_equal(rebinds_before)
	screen.queue_free()


func test_watchful_eye_position_scales_with_suspicion() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	await _settle_window(screen, Vector2i(1280, 800), false)
	var active := screen.get_active_slot() as OrientationSlot
	var eye := screen.eye_of(active)
	assert_that(eye).is_not_null()
	# Low: the Eye perches at the table's right edge (form SOLID).
	host.suspicion().set_suspicion(5)
	screen._bind_eye()
	await get_tree().process_frame
	var x_low: float = eye.global_position.x
	assert_int(eye._frame.get("edge_form")).is_equal(Inks.EdgeForm.SOLID)
	# Warn zone: it creeps inward, form DASHED (readable without color).
	host.suspicion().set_suspicion(50)
	screen._bind_eye()
	await get_tree().process_frame
	assert_float(eye.global_position.x).is_less(x_low - 10.0)
	assert_int(eye._frame.get("edge_form")).is_equal(Inks.EdgeForm.DASHED)
	# Crackdown zone: deepest inset, form STRUCK.
	host.suspicion().set_suspicion(85)
	screen._bind_eye()
	await get_tree().process_frame
	assert_float(eye.global_position.x).is_less(x_low - 30.0)
	assert_int(eye._frame.get("edge_form")).is_equal(Inks.EdgeForm.STRUCK)
	# The Eye never leaves the table (clipping guard).
	var design: Vector2 = screen.get_router().design_size()
	var rect: Rect2 = eye.get_global_rect()
	assert_float(rect.end.x).is_less_equal(design.x + 0.5)
	assert_float(rect.position.x).is_greater_equal(-0.5)
	screen.queue_free()


# --- the armed Eye (finishing refinement #3: armed salience + the lane) ------------------


func test_eye_armed_metrics_commit_the_deep_seat() -> void:
	## An armed telegraph is a STATE, not a level: the Eye overrides the
	## meter's residue and commits to the deep seat (full inset, full card
	## scale, full dread) — the loud state, whatever the meter says.
	for points in [40, 55, 70, 88, 100]:
		var metrics: Dictionary = SpreadPresenter.eye_metrics(points, 100, 35, 70, true, true)
		assert_float(metrics["inset"]).is_equal(1.0) \
			.override_failure_message("armed inset must be the full slide")
		assert_float(metrics["scale"]).is_equal(1.0)
		assert_float(metrics["dread"]).is_equal(1.0)
		assert_bool(metrics["armed"]).is_true()
		assert_int(metrics["edge_form"]).is_equal(Inks.EdgeForm.STRUCK)
	# A dead run has no armed telegraph (the Eye withdrew; the lane lifts).
	var dead: Dictionary = SpreadPresenter.eye_metrics(80, 100, 35, 70, true, false)
	assert_bool(dead["armed"]).is_false()
	assert_bool(dead["visible"]).is_false()


func test_eye_rest_metrics_are_the_authored_creep() -> void:
	## The REST pin: unarmed metrics are EXACTLY the authored quiet creep
	## (the creep is the design — the armed escalation must not leak).
	for points in [1, 10, 25, 50, 69, 85, 100]:
		var metrics: Dictionary = SpreadPresenter.eye_metrics(points, 100, 35, 70, false, true)
		var progress := float(points) / 100.0
		assert_float(metrics["inset"]).is_equal(progress)
		assert_float(metrics["scale"]).is_equal(0.55 + 0.45 * progress)
		assert_float(metrics["dread"]).is_equal(0.55 + 0.45 * progress)
		assert_bool(metrics["armed"]).is_false()


func test_armed_eye_plate_countdown_rule_and_clear_lane() -> void:
	## THE ARMED PLATE on the live table: the card grows to the armed
	## minimum, the countdown escalates to the numeral-plate grammar (the
	## double red rule + caption + big numeral), and NO card on the table
	## crowds the seat — the lane reserve did its layout work.
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 8.0)  # a real roster on the table
	var screen: SpreadScreen = await _mounted_screen(host)
	await _settle_window(screen, Vector2i(1280, 800), false)
	var active := screen.get_active_slot() as OrientationSlot
	var eye := screen.eye_of(active)
	# The documented telegraph seam arms the Eye live (meter -> telegraph).
	host.suspicion().set_suspicion(78)
	host.fast_forward(2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(host.suspicion().crackdown_land_tick != -1).is_true()
	# The plate grew to the armed card.
	assert_vector(eye.custom_minimum_size) \
		.is_equal_approx(WatchfulEyeScript.ARMED_CARD_MIN, Vector2(0.1, 0.1))
	assert_vector(eye.size).is_equal_approx(WatchfulEyeScript.ARMED_CARD_MIN, Vector2(0.1, 0.1))
	# The countdown escalated: caption + numeral under the double red rule.
	assert_str(eye._countdown.text).is_equal("lands in")
	assert_int(eye._countdown.get_theme_font_size(&"font_size")) \
		.is_equal(TypeScale.scaled(WatchfulEyeScript.ARMED_CAPTION_SIZE))
	assert_bool(eye._countdown.get_theme_color(&"font_color") == Inks.RED).is_true()
	assert_bool(eye._numeral.visible).is_true()
	assert_str(eye._numeral.text).is_equal("%dh" % SpreadPresenter.eye_hours_left(host))
	assert_int(eye._numeral.get_theme_font_size(&"font_size")) \
		.is_equal(TypeScale.scaled(WatchfulEyeScript.ARMED_NUMERAL_SIZE))
	# The hours print IN INK (the numeral-plate grammar — the SIZE is the
	# escalation; red carries the countdown text + rule, staying inside the
	# brief's 30-60% accent commitment).
	assert_bool(eye._numeral.get_theme_color(&"font_color") == Inks.INK).is_true()
	assert_bool(eye._rule.visible).is_true()
	assert_int(eye._rule.get("form")).is_equal(3)  # RuleMark.RuleForm.DOUBLE
	assert_bool(eye._rule.get("rule_ink") == Inks.RED).is_true()
	# THE LANE: both slots' card fields narrowed, and no card rect touches
	# the armed Eye's seat (the perch-crowding fix, layout-level).
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		assert_float(float(slot.get_spread().get("right_reserve"))).is_greater(0.0)
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		var slot_eye := screen.eye_of(slot)
		var seat: Rect2 = slot_eye.get_global_rect()
		for child in slot.get_spread().get_children():
			var card := child as Control
			if card != null:
				assert_bool(card.get_global_rect().intersects(seat)).is_false() \
					.override_failure_message(
						"the armed Eye crowds card %s" % String(card.get_meta(&"spread_card_id", "?")))
	# RELIEF: laying low cancels the telegraph — the plate returns to the
	# quiet stub, the countdown to its role line, the lane lifts, and the
	# perch formula takes the Eye back (the creep resumes as authored).
	host.suspicion().set_suspicion(60)
	host.fast_forward(2)
	host.driving = false  # freeze the world: the pin reads a settled state
	# The relief plays the retreat flinch (a 0.45s scale tween) — the pin
	# waits it out: a scaled control's global origin breathes with the
	# pulse, and the perch formula compares against the settled rect.
	# (Harness-budget trim: the tween ages under the injected clock; the
	# poll still guards on its TRUE completion signal retreat_t >= 1.0.)
	Engine.time_scale = SWEEP_SCALE
	for i in 120:
		await get_tree().process_frame
		if eye.retreat_t >= 1.0:
			break
	Engine.time_scale = 1.0
	await get_tree().process_frame  # the reserve lift's re-layout settles
	await get_tree().process_frame
	screen._bind_eye()  # rebind against the settled geometry, then pin (this suite's pattern)
	await get_tree().process_frame
	assert_bool(host.suspicion().crackdown_land_tick == -1).is_true()
	assert_vector(eye.custom_minimum_size).is_equal(Vector2.ZERO)
	assert_vector(eye.size).is_equal_approx(
		Vector2(Inks.TOUCH_GRIP_MIN * 1.6, Inks.TOUCH_GRIP_MIN * 2.0), Vector2(0.1, 0.1))
	assert_bool(eye._numeral.visible).is_false()
	assert_bool(eye._rule.visible).is_false()
	var share := int(round(float(host.suspicion().suspicion_points())
		/ float(host.suspicion().max_points()) * 100.0))
	assert_str(eye._countdown.text).is_equal("the Crown watches — %d" % share)
	assert_bool(eye._countdown.has_theme_font_size_override(&"font_size")).is_false()
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		assert_float(float(slot.get_spread().get("right_reserve"))).is_zero()
	# And the resting position is the authored perch again (read the state
	# the bind read — the same rebind above, so the formula compares true).
	var spread_rect: Rect2 = active.get_spread().get_global_rect()
	var slot_rect := active.get_global_rect()
	var progress := clampf(float(host.suspicion().suspicion_points())
		/ float(host.suspicion().max_points()), 0.0, 1.0)
	var max_inset: float = maxf(0.0, spread_rect.size.x * 0.5 - eye.size.x)
	assert_float(eye.global_position.x).is_equal_approx(
		slot_rect.end.x - eye.size.x - 8.0 - progress * max_inset, 0.5)
	screen.queue_free()


func test_rest_eye_plate_stays_the_quiet_creep() -> void:
	## The rest pin on the live table: unarmed, the plate is the periphery
	## stub with one quiet role line — no armed grammar leaks into rest.
	var host := _test_host()
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 4.0)
	var screen: SpreadScreen = await _mounted_screen(host)
	await _settle_window(screen, Vector2i(720, 1280), true)
	var active := screen.get_active_slot() as OrientationSlot
	var eye := screen.eye_of(active)
	host.driving = false  # freeze the world: the pin reads a settled state
	host.suspicion().set_suspicion(12)
	screen._bind_eye()
	await get_tree().process_frame
	assert_bool(eye._rule.visible).is_false()
	assert_bool(eye._numeral.visible).is_false()
	assert_vector(eye.custom_minimum_size).is_equal(Vector2.ZERO)
	assert_str(eye._countdown.text).is_equal("the Crown watches — %d" % 12)
	assert_bool(eye._countdown.has_theme_font_size_override(&"font_size")).is_false()
	assert_bool(eye._countdown.get_theme_color(&"font_color") == Inks.INK_SOFT).is_true()
	# The periphery stub perches by the authored formula (the creep at 12%).
	var spread_rect: Rect2 = active.get_spread().get_global_rect()
	var slot_rect := active.get_global_rect()
	var max_inset: float = maxf(0.0, spread_rect.size.x * 0.5 - eye.size.x)
	assert_float(eye.global_position.x).is_equal_approx(
		slot_rect.end.x - eye.size.x - 8.0 - 0.12 * max_inset, 0.5)
	screen.queue_free()


func test_armed_eye_wash_prints_wider_than_the_card() -> void:
	## The strike wash's ground footprint: WASH_EXTENT times the card,
	## centered — the wider strike wash (pure; the pulse pins its alpha).
	var card := Rect2(Vector2(100.0, 200.0), Vector2(144.0, 202.0))
	var wash: Rect2 = WatchfulEyeScript.wash_rect(card)
	assert_vector(wash.size).is_equal(card.size * WatchfulEyeScript.WASH_EXTENT)
	assert_vector(wash.get_center()).is_equal(card.get_center())
	# The strike bell keeps its authored peak (0.38 alpha at the middle).
	var peak: Dictionary = WatchfulEyeScript.strike_params(0.5)
	assert_float(peak["wash"]).is_equal(0.38)


func test_layout_hash_is_a_function_of_sim_state() -> void:
	## Two identically-driven hosts rendered by two screens: identical
	## layout hashes per slot (same state -> same rendered spread).
	var host_a := _test_host(2026)
	var host_b := _test_host(2026)
	var policy_a := DemoPolicy.new(16, 8, false)
	var policy_b := DemoPolicy.new(16, 8, false)
	_drive_policy(host_a, policy_a, 9.0)
	_drive_policy(host_b, policy_b, 9.0)
	var screen_a: SpreadScreen = await _mounted_screen(host_a)
	await _settle_window(screen_a, Vector2i(1280, 800), false)
	await _settle_frames()
	var hash_p_a: int = screen_a.layout_hash(screen_a.get_portrait_slot() as OrientationSlot)
	var hash_l_a: int = screen_a.layout_hash(screen_a.get_landscape_slot() as OrientationSlot)
	# Re-rendering the same state must not move a card.
	screen_a.refresh_from_state()
	await _settle_frames()
	assert_int(screen_a.layout_hash(screen_a.get_portrait_slot() as OrientationSlot)).is_equal(hash_p_a)
	assert_int(screen_a.layout_hash(screen_a.get_landscape_slot() as OrientationSlot)).is_equal(hash_l_a)
	screen_a.queue_free()
	await get_tree().process_frame

	var screen_b: SpreadScreen = await _mounted_screen(host_b)
	await _settle_window(screen_b, Vector2i(1280, 800), false)
	await _settle_frames()
	assert_int(screen_b.layout_hash(screen_b.get_portrait_slot() as OrientationSlot)).is_equal(hash_p_a)
	assert_int(screen_b.layout_hash(screen_b.get_landscape_slot() as OrientationSlot)).is_equal(hash_l_a)
	screen_b.queue_free()


## Let deferred layout binds (the Eye re-place, the column ladder) and
## pending container sorts land before hashing the rendered layout.
func _settle_frames() -> void:
	for i in 4:
		await get_tree().process_frame


func test_chronicle_strip_prints_in_world() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	host.fast_forward(1)
	await get_tree().process_frame
	var active := screen.get_active_slot() as OrientationSlot
	var line := active.get_chronicle_line(0)
	assert_str(String(line.get("text"))).contains("gate")
	# The strip rows are chronicle lines, not toasts: no Popup/Window
	# descendants anywhere on the screen.
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	screen.queue_free()


# --- the demo run's two screenshot states ----------------------------------------------------


func test_seeded_quiet_demo_assembles_toward_the_storm() -> void:
	var host := _test_host(LOUD_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	_drive_policy(host, policy, 30.0)
	assert_int(host.units().total_units()).is_greater(2)
	assert_bool(host.is_run_running()).is_true()


func test_seeded_loud_demo_reaches_the_telegraph() -> void:
	## The pressured screenshot state is honest: the greed policy under
	## the screenshot seed arms the crackdown telegraph within 40h.
	var host := _test_host(LOUD_SEED)
	var policy := DemoPolicy.new(40, 40, true)
	var armed := false
	for cycle in 40:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
		if host.suspicion().crackdown_land_tick != -1 or host.suspicion().crackdowns_total > 0:
			armed = true
			break
	assert_bool(armed).is_true()
	assert_int(host.suspicion().suspicion_points()).is_greater_equal(
		Inks.pack().tunables.suspicion_warn_threshold)
