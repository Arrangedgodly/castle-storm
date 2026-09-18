## Unit tests for the FIRST-DEAL COVERAGE FIX — the report "you can click
## cards in the opening hand but raising actions don't work".
##
## Root cause, confirmed by real-click walkthrough: the first deal slid
## 2-3 recruit OFFER cards in a fan directly OVER the staked PLOT cards
## (in the default desktop's panoramic fan every plot's CENTER was buried
## under its neighbor — a ~45px clickable strip each), and the once-only
## how-to OFFER paper covered the whole table at the same moment. Raise
## itself always worked when reachable. What is pinned here:
##
##   - THE GATE LANE (CardSpread.gate_lane): after a fresh deal (3 offers
##     + 4 staked plots) NO offer card's rect covers any plot card's
##     center, in BOTH slots (portrait and landscape);
##   - RAISE REACHABLE: a real input-pipeline click (Input.parse_input_
##     event at the design-mapped point — the T-UI-04 method) on each
##     plot's center opens its action fan containing the raise chip;
##   - THE STAGED FIRST MOMENTS: while the how-to offer paper stands on
##     the fresh first deal, arriving deals WAIT (no offer nodes on the
##     table); the paper's dismissal releases them;
##   - THE ADAPTIVE BUILD NOTE: while offers stand at the gate, the build
##     objective names the intermediate action (answer the gate) instead
##     of pointing at a plot.
##
## WAITING STRATEGY: layout settles through deferred binds + the bounded
## finalization loop — each settle waits frames until the spread's child
## count stops moving (a bounded spin), never a wall sleep. The deals-
## hold test drives the sim with fast_forward (the harness seam).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const SETTLE_FRAMES := 24


func after() -> void:
	get_window().size = Vector2i(720, 720)
	_erase_dir("user://cs_first_deal_tests")


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


var _dir_seq := 0


func _first_deal_host(run_seed: int = 20261103) -> GameHost:
	# A FRESH save root per host (the test_howto pattern): a reused root
	# resumes the previous test's run — tick > 1, "seen" flagged — and the
	# fresh-first-deal state under test never arms.
	_dir_seq += 1
	var host := GameHost.new(run_seed,
		"user://cs_first_deal_tests/host-%02d" % _dir_seq)
	host.boot(0)
	return host


func _deal_three_offers(host: GameHost) -> void:
	# The opening rush's first three arrivals (6/12/24 wall minutes at 1x):
	# the first deal as the reporter met it.
	var guard := 0
	while host.units().pending_offers() < 3 and guard < 4000:
		host.fast_forward(30)
		guard += 1
	assert_int(host.units().pending_offers()).is_greater_equal(3)


func _mounted(host: GameHost, intro_on := false) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	await _settle(screen)
	return screen


## Wait until the screen's active-slot spread stops changing (the deferred
## binds, the column ladder and the bounded finalization pass all land).
func _settle(screen: SpreadScreen) -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var spread := (screen.get_active_slot() as OrientationSlot).get_spread()
	var stable := 0
	var last := spread.get_child_count()
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		var now := spread.get_child_count()
		if now == last:
			stable += 1
			if stable >= 4:
				break
		else:
			stable = 0
			last = now


func _plot_nodes(slot: OrientationSlot) -> Array[Control]:
	var out: Array[Control] = []
	for child in slot.get_spread().get_children():
		var card := child as Control
		if card != null and String(card.get_meta(&"spread_card_id", "")).begins_with("bld_"):
			out.append(card)
	return out


func _offer_nodes(slot: OrientationSlot) -> Array[Control]:
	var out: Array[Control] = []
	for child in slot.get_spread().get_children():
		var card := child as Control
		if card != null and String(card.get_meta(&"spread_card_id", "")).begins_with("offer_"):
			out.append(card)
	return out


## A real click through the input pipeline at a design-space point (the
## T-UI-04 method: parse_input_event at the stretch-mapped window point).
func _click_design(point: Vector2) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var factor := float(get_window().size.x) / vs.x
	var p := point * factor
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p
	press.global_position = p
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _screen_at(size: Vector2i, intro_on := false) -> SpreadScreen:
	get_window().size = size
	var host := _first_deal_host()
	_deal_three_offers(host)
	return await _mounted(host, intro_on)


# --- the gate lane: offers never bury plots -------------------------------------------------


func test_offers_never_bury_plot_centers_in_both_slots() -> void:
	for size: Vector2i in [Vector2i(720, 1280), Vector2i(1280, 800)]:
		var screen := await _screen_at(size)
		for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
			var plots := _plot_nodes(slot)
			var offers := _offer_nodes(slot)
			assert_int(plots.size()).is_equal(4)
			assert_int(offers.size()).is_greater_equal(3)
			for plot in plots:
				var center: Vector2 = plot.get_global_rect().get_center()
				for offer in offers:
					var offer_rect: Rect2 = offer.get_global_rect()
					assert_bool(offer_rect.has_point(center)).override_failure_message(
						"%s: offer %s covers %s's center %s" % [str(size),
						offer.get_meta(&"spread_card_id"),
						plot.get_meta(&"spread_card_id"), center]).is_false()
		screen.queue_free()
		await get_tree().process_frame


func test_offer_rects_are_disjoint_from_plot_rects_on_the_active_table() -> void:
	# Stronger than the center rule at the shipped default window: the
	# gate row keeps the gate paper wholly clear of the estate band.
	get_window().size = Vector2i(1280, 800)
	var host := _first_deal_host()
	_deal_three_offers(host)
	var screen := await _mounted(host)
	var slot := screen.get_active_slot() as OrientationSlot
	for offer in _offer_nodes(slot):
		var offer_rect: Rect2 = offer.get_global_rect()
		for plot in _plot_nodes(slot):
			var plot_rect: Rect2 = plot.get_global_rect()
			assert_bool(offer_rect.intersects(plot_rect)).override_failure_message(
				"offer %s intersects plot %s" % [offer.get_meta(&"spread_card_id"),
				plot.get_meta(&"spread_card_id")]).is_false()
	screen.queue_free()
	await get_tree().process_frame


# --- raise reachable by real click ----------------------------------------------------------


func test_clicking_each_plot_center_opens_a_raise_fan() -> void:
	# 1280x800 landscape — the orientation whose packed fan buried the
	# plots' centers before the fix.
	get_window().size = Vector2i(1280, 800)
	var host := _first_deal_host()
	_deal_three_offers(host)
	var screen := await _mounted(host)
	var slot := screen.get_active_slot() as OrientationSlot
	for plot in _plot_nodes(slot):
		var building_id := String(plot.get_meta(&"spread_card_id")).trim_prefix("bld_")
		await _click_design(plot.get_global_rect().get_center())
		assert_bool(screen._fan.is_open()).override_failure_message(
			"fan never opened for %s" % building_id).is_true()
		assert_str(String(screen._fan.card_id)).is_equal("bld_%s" % building_id)
		var raise_found := false
		for chip in screen._fan.chips():
			if String(chip.action["id"]) == "build" \
					and String(chip.action["command"]) == "upgrade_building":
				raise_found = true
				break
		assert_bool(raise_found).override_failure_message(
			"no raise chip in %s's fan" % building_id).is_true()
		screen.close_fan()
		await get_tree().process_frame
	screen.queue_free()
	await get_tree().process_frame


# --- the staged first moments ---------------------------------------------------------------


func test_deals_wait_behind_the_howto_offer_and_slide_in_after_dismissal() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _first_deal_host()
	var screen := await _mounted(host, true)
	# the boot reveal opens on the fresh first deal; its fold offers the
	# pamphlet once (the tutorial's own flow)
	var waited := 0
	while not screen._intro.is_open() and waited < 240:
		await get_tree().process_frame
		waited += 1
	assert_bool(screen._intro.is_open()).is_true()
	screen._intro.unfold()
	waited = 0
	while screen._intro.is_open() and waited < 600:
		await get_tree().process_frame
		waited += 1
	waited = 0
	while int(screen.stats[&"howto_offers"]) == 0 and waited < 240:
		await get_tree().process_frame
		waited += 1
	assert_int(int(screen.stats[&"howto_offers"])).is_equal(1)
	await _settle(screen)
	var slot := screen.get_active_slot() as OrientationSlot
	assert_int(_plot_nodes(slot).size()).is_equal(4)
	# the opening rush arrives BEHIND the paper: no offer deals onto the
	# table while the how-to offer stands
	_deal_three_offers(host)
	await _settle(screen)
	assert_int(_offer_nodes(slot).size()).override_failure_message(
		"offers dealt onto the table under the how-to offer paper").is_zero()
	# the dismissal releases the held deals (the real decline verb)
	screen._howto.offer_panel().decline_chip().pressed.emit()
	waited = 0
	while _offer_nodes(slot).size() < 3 and waited < 240:
		await get_tree().process_frame
		waited += 1
	assert_int(_offer_nodes(slot).size()).override_failure_message(
		"held deals never slid in after the paper folded").is_greater_equal(3)
	assert_int(_plot_nodes(slot).size()).is_equal(4)
	screen.queue_free()
	await get_tree().process_frame


# --- the adaptive build note ----------------------------------------------------------------


func test_build_note_names_the_gate_while_offers_stand() -> void:
	# Mount FIRST (the once-only layer arms at tick 1), then deal, so the
	# arc's flags advance through the REAL event path; read the note the
	# player would see.
	get_window().size = Vector2i(720, 1280)
	var host := _first_deal_host()
	var screen := await _mounted(host)
	_deal_three_offers(host)
	await _settle(screen)
	# complete the arc's first two steps so the BUILD objective pins while
	# two offers still stand at the gate (the reporter's exact moment)
	var offers := host.units().offer_ids()
	host.submit(&"recruit_accept", &"", offers[0])
	host.fast_forward(5)
	await get_tree().process_frame
	var idle := host.units().idle_units(host.units().base_unit_id())
	assert_int(idle.size()).is_greater(0)
	host.submit(&"assign_role", &"worker", idle[0])
	host.fast_forward(5)
	await get_tree().process_frame
	var objective := FirstSession.current_objective(host)
	assert_dict(objective).is_not_empty()
	assert_str(StringName(String(objective["id"]))).is_equal(&"build")
	var wait_text := String(objective["text"])
	assert_bool(wait_text.to_lower().contains("gate")).override_failure_message(
		"build note ignored the standing offers: '%s'" % wait_text).is_true()
	# the gate drains: the same objective reads the plain raise line
	for uid in host.units().offer_ids():
		host.submit(&"dismiss_offer", &"", uid)
		host.fast_forward(2)
	await get_tree().process_frame
	var plain := FirstSession.current_objective(host)
	assert_dict(plain).is_not_empty()
	assert_str(StringName(String(plain["id"]))).is_equal(&"build")
	assert_bool(String(plain["text"]).to_lower().contains("gate")).override_failure_message(
		"build note still names the gate with the gate empty: '%s'" % plain["text"]).is_false()
	screen.queue_free()
	await get_tree().process_frame
