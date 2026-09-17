## Responsive layout foundation tests (T-UI-02).
##
## Headless proof of the R3 contracts:
##   1. DEADBAND PURITY — orientation_for_aspect: outside the band picks
##      the topology, inside keeps current (square-ish never swaps).
##   2. HYSTERESIS + DWELL — a FLAPPING aspect (crossing the threshold
##      faster than dwell_seconds) never swaps; a sustained out-of-band
##      aspect swaps exactly once at the dwell boundary.
##   3. FORCE/CLEAR — forced topology ignores aspect until cleared.
##   4. FOCUS EQUIVALENCE — find_focusable_element resolves the same
##      focus_id in BOTH slots; a live swap keeps the controller's place
##      (focus owner carries the same focus_id after the swap) and the
##      hidden slot's focusables are focus-disabled.
##   5. CARDSPREAD MATH — pure arrangement for N cards in BOTH
##      topologies: bounded, non-overlapping grid (portrait), centered
##      arc with capped rotation (landscape), aspect-true card sizes.
##   6. MINIMUM SIZES — the spread's honest floor per topology, the
##      slot's stacked floor, the touch-grip on every focusable.
##   7. LAB SCENE — instantiates headless with both slots, the router,
##      and the debug panel fully populated.
extends GdUnitTestSuite

const LAB_PATH := "res://ui/layout/responsive_lab.tscn"
const FRAME_SCENE := "res://ui/theme/card_frame.tscn"


# --- 1. Deadband purity ---------------------------------------------------------------


func test_orientation_for_aspect_deadband() -> void:
	# Clearly outside the band decides regardless of current.
	assert_int(LayoutRouter.orientation_for_aspect(0.5625, LayoutRouter.ScreenOrientation.LANDSCAPE)).is_equal(LayoutRouter.ScreenOrientation.PORTRAIT)
	assert_int(LayoutRouter.orientation_for_aspect(1.777, LayoutRouter.ScreenOrientation.PORTRAIT)).is_equal(LayoutRouter.ScreenOrientation.LANDSCAPE)
	# Inside the band keeps the current topology either way.
	assert_int(LayoutRouter.orientation_for_aspect(1.0, LayoutRouter.ScreenOrientation.LANDSCAPE)).is_equal(LayoutRouter.ScreenOrientation.LANDSCAPE)
	assert_int(LayoutRouter.orientation_for_aspect(1.0, LayoutRouter.ScreenOrientation.PORTRAIT)).is_equal(LayoutRouter.ScreenOrientation.PORTRAIT)
	assert_int(LayoutRouter.orientation_for_aspect(0.97, LayoutRouter.ScreenOrientation.LANDSCAPE)).is_equal(LayoutRouter.ScreenOrientation.LANDSCAPE)
	assert_int(LayoutRouter.orientation_for_aspect(1.03, LayoutRouter.ScreenOrientation.PORTRAIT)).is_equal(LayoutRouter.ScreenOrientation.PORTRAIT)
	# The band edges themselves are inside (strict inequalities).
	assert_int(LayoutRouter.orientation_for_aspect(0.95, LayoutRouter.ScreenOrientation.PORTRAIT)).is_equal(LayoutRouter.ScreenOrientation.PORTRAIT)
	assert_int(LayoutRouter.orientation_for_aspect(1.05, LayoutRouter.ScreenOrientation.LANDSCAPE)).is_equal(LayoutRouter.ScreenOrientation.LANDSCAPE)


# --- 2. Hysteresis + dwell (pure router, aspect probe injected) -----------------------


func _router_with_probe() -> LayoutRouter:
	var router := LayoutRouter.new()
	auto_free(router)
	router.aspect_probe = func() -> float: return 1.777
	return router


func test_flapping_aspect_never_swaps() -> void:
	var router := _router_with_probe()
	# GDScript lambdas capture by VALUE: hold the counter in an array.
	var swaps := [0]
	router.orientation_changed.connect(func(_o: int) -> void: swaps[0] += 1)
	router._current = LayoutRouter.ScreenOrientation.LANDSCAPE
	# Aspect crosses the threshold EVERY poll, faster than dwell: each
	# crossing re-arms the candidate and resets its age.
	var flapping: Array[float] = [0.75, 1.3, 0.75, 1.3, 0.75, 1.3, 0.75, 1.3]
	for aspect in flapping:
		router.aspect_probe = func() -> float: return aspect
		router.poll(0.1)
	assert_int(swaps[0]).is_zero()
	assert_bool(router.is_portrait()).is_false()


func test_in_band_flapping_never_even_arms() -> void:
	var router := _router_with_probe()
	router._current = LayoutRouter.ScreenOrientation.LANDSCAPE
	# Square-ish chatter inside the deadband: desired == current every step.
	for aspect in [0.96, 1.04, 0.98, 1.02]:
		router.aspect_probe = func() -> float: return aspect
		router.poll(1.0)  # arbitrarily long dwell would not matter
	assert_bool(router.is_portrait()).is_false()


func test_sustained_aspect_swaps_exactly_at_dwell() -> void:
	var router := _router_with_probe()
	# GDScript lambdas capture by VALUE: hold the counter in an array.
	var swaps := [0]
	router.orientation_changed.connect(func(_o: int) -> void: swaps[0] += 1)
	router._current = LayoutRouter.ScreenOrientation.LANDSCAPE
	router.aspect_probe = func() -> float: return 0.5625
	router.poll(0.0)   # arms the candidate (age 0)
	router.poll(0.1)   # age 0.1 < 0.25
	assert_bool(router.is_portrait()).is_false()
	router.poll(0.1)   # age 0.2 < 0.25
	assert_bool(router.is_portrait()).is_false()
	router.poll(0.1)   # age 0.3 >= 0.25 -> lands
	assert_bool(router.is_portrait()).is_true()
	assert_int(swaps[0]).is_equal(1)
	# Staying portrait: no further signals.
	for i in 5:
		router.poll(0.2)
	assert_int(swaps[0]).is_equal(1)


func test_brief_out_of_band_excursion_does_not_swap() -> void:
	var router := _router_with_probe()
	router._current = LayoutRouter.ScreenOrientation.LANDSCAPE
	# A 0.2s portrait blip inside a landscape window: under dwell.
	router.aspect_probe = func() -> float: return 0.5625
	router.poll(0.0)
	router.poll(0.1)
	router.poll(0.1)
	router.aspect_probe = func() -> float: return 1.6
	router.poll(0.1)
	assert_bool(router.is_portrait()).is_false()


# --- 3. Force / clear ------------------------------------------------------------------


func test_force_overrides_aspect_until_cleared() -> void:
	var router := _router_with_probe()
	router._current = LayoutRouter.ScreenOrientation.LANDSCAPE
	router.force_orientation(LayoutRouter.ScreenOrientation.PORTRAIT)
	assert_bool(router.is_portrait()).is_true()
	assert_bool(router.is_forced()).is_true()
	# While forced, aspect polls are ignored entirely.
	router.aspect_probe = func() -> float: return 1.777
	for i in 10:
		router.poll(0.5)
	assert_bool(router.is_portrait()).is_true()
	# Clearing resumes automatic detection (with the normal dwell).
	router.clear_forced()
	assert_bool(router.is_forced()).is_false()
	router.poll(0.0)
	router.poll(0.25)
	router.poll(0.05)
	assert_bool(router.is_portrait()).is_false()


# --- 4. Focus equivalence + swap preservation (mounted scene) -------------------------


func _mounted_lab() -> ResponsiveScreen:
	## Mounted to the tree ROOT (not the suite node): a full-rect screen
	## must size against the viewport's design rect exactly as in
	## production — under the suite's scaffolding Control the anchors
	## would track that container instead.
	var lab := (load(LAB_PATH) as PackedScene).instantiate() as ResponsiveScreen
	auto_free(lab)
	get_tree().root.add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	return lab


func test_find_focusable_element_equivalence_across_slots() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	for id in ["spread_card_0", "spread_card_4", "chronicle_1"]:
		var in_portrait: Control = router.find_focusable_element(lab.get_portrait_slot(), id)
		var in_landscape: Control = router.find_focusable_element(lab.get_landscape_slot(), id)
		assert_that(in_portrait).is_not_null()
		assert_that(in_landscape).is_not_null()
		assert_str(String(in_portrait.get_meta(&"focus_id"))).is_equal(id)
		assert_str(String(in_landscape.get_meta(&"focus_id"))).is_equal(id)
	# The pip rail is informational (not a controller target): pip ids do
	# not resolve as focusables -- by design, asserted.
	assert_that(router.find_focusable_element(lab.get_portrait_slot(), "pip_0")).is_null()
	# Unknown id: null. Empty id: the first focusable (the seed rule).
	assert_that(router.find_focusable_element(lab.get_portrait_slot(), "nope")).is_null()
	var first := router.find_focusable_element(lab.get_landscape_slot(), "")
	assert_that(first).is_not_null()


func test_swap_preserves_focus_target() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	# Square headless seed -> landscape. Focus the 4th card there.
	var card := router.find_focusable_element(lab.get_landscape_slot(), "spread_card_3")
	card.grab_focus()
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(card)
	# Swap: the controller player must not lose their place.
	router.force_orientation(LayoutRouter.ScreenOrientation.PORTRAIT)
	await get_tree().process_frame
	await get_tree().process_frame
	var owner_after: Control = get_viewport().gui_get_focus_owner()
	assert_that(owner_after).is_not_null()
	assert_bool(lab.get_portrait_slot().is_ancestor_of(owner_after)).is_true()
	assert_str(String(owner_after.get_meta(&"focus_id"))).is_equal("spread_card_3")
	# And back — equivalence survives the round-trip.
	router.force_orientation(LayoutRouter.ScreenOrientation.LANDSCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	var owner_back: Control = get_viewport().gui_get_focus_owner()
	assert_str(String(owner_back.get_meta(&"focus_id"))).is_equal("spread_card_3")


func test_hidden_slot_is_focus_disabled_and_invisible() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	router.force_orientation(LayoutRouter.ScreenOrientation.PORTRAIT)
	await get_tree().process_frame
	assert_bool(lab.get_landscape_slot().visible).is_false()
	assert_bool(lab.get_portrait_slot().visible).is_true()
	# Focusables() only collects focus_mode != NONE: the hidden slot has
	# NONE everywhere (Tab chains cannot route through it), the visible
	# slot keeps its focusables.
	assert_int((lab.get_landscape_slot() as OrientationSlot).focusables().size()).is_zero()
	assert_int((lab.get_portrait_slot() as OrientationSlot).focusables().size()).is_greater_equal(7)


func test_focus_outside_slots_is_left_alone() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	var debug_button: Control = router.find_focusable_element(lab, "debug_orientation")
	assert_that(debug_button).is_not_null()
	debug_button.grab_focus()
	await get_tree().process_frame
	router.force_orientation(LayoutRouter.ScreenOrientation.PORTRAIT)
	await get_tree().process_frame
	await get_tree().process_frame
	# The debug panel kept focus through the swap.
	assert_that(get_viewport().gui_get_focus_owner()).is_same(debug_button)


# --- 5. CardSpread arrangement math -----------------------------------------------------


func test_stacked_layout_math_for_n_cards() -> void:
	var bounds := Vector2(720, 1280)
	for n in range(1, 8):
		var rects := CardSpread.stacked_layout(n, bounds, 2, Vector2(20, 20))
		assert_int(rects.size()).is_equal(n)
		for rect in rects:
			# Inside the table.
			assert_bool(rect.position.x >= 0.0 and rect.position.y >= 0.0).is_true()
			assert_bool(rect.end.x <= bounds.x + 0.001 and rect.end.y <= bounds.y + 0.001).is_true()
			# Aspect-true card.
			assert_float(rect.size.x / rect.size.y).is_equal_approx(CardSpread.CARD_ASPECT, 0.001)
		# Grid: cards in the same row share y; rows step down; no overlaps.
		var rows := int(ceil(float(n) / 2.0))
		for i in n:
			var col := i % 2
			var row := i / 2
			assert_float(rects[i].position.y).is_equal_approx(rects[0].position.y + float(row) * (rects[0].size.y + 20.0), 0.01)
			if col == 1:
				assert_float(rects[i].position.x).is_equal_approx(rects[0].position.x + rects[0].size.x + 20.0, 0.01)
		for i in n:
			for j in range(i + 1, n):
				assert_bool(rects[i].intersects(rects[j])).is_false()
		# Grid centered in bounds.
		var grid_w := 2.0 * rects[0].size.x + 20.0
		assert_float(rects[0].position.x).is_equal_approx((bounds.x - grid_w) * 0.5, 0.01)


func test_stacked_layout_height_cap_and_odd_columns() -> void:
	# A very tall table cannot grow cards past the cap.
	var rects := CardSpread.stacked_layout(1, Vector2(720, 4000), 1, Vector2(20, 20))
	assert_float(rects[0].size.y).is_equal_approx(CardSpread.MAX_CARD_HEIGHT, 0.01)
	# Three columns with 5 cards: 2 rows, third column empty in row 2.
	var grid := CardSpread.stacked_layout(5, Vector2(1152, 720), 3, Vector2(16, 16))
	assert_int(grid.size()).is_equal(5)
	assert_float(grid[3].position.y).is_greater(grid[0].position.y)
	# Zero cards -> no rects, no crash.
	assert_int(CardSpread.stacked_layout(0, Vector2(720, 1280), 2, Vector2(20, 20)).size()).is_zero()


func test_panoramic_layout_math_for_n_cards() -> void:
	var bounds := Vector2(1280, 720)
	for n in range(1, 13):
		var entries := CardSpread.panoramic_layout(n, bounds, Vector2(20, 20), 24.0, 10.0)
		assert_int(entries.size()).is_equal(n)
		for entry in entries:
			var rect: Rect2 = entry["rect"]
			# Inside the table.
			assert_bool(rect.position.x >= 0.0 and rect.position.y >= 0.0).is_true()
			assert_bool(rect.end.x <= bounds.x + 0.001 and rect.end.y <= bounds.y + 0.001).is_true()
			# Rotation bounded by the fan swing.
			assert_float(absf(float(entry["rotation"]))).is_less_equal(10.0 + 0.001)
		# Span centered: first card's left gap == last card's right gap.
		var first: Rect2 = entries[0]["rect"]
		var last: Rect2 = entries[n - 1]["rect"]
		assert_float(first.position.x).is_equal_approx(bounds.x - (last.position.x + last.size.x), 0.01)
		# The arc lifts the center above the ends.
		if n >= 3:
			var center: Rect2 = entries[n / 2]["rect"]
			var end: Rect2 = entries[0]["rect"]
			assert_float(center.position.y).is_less(end.position.y)
	# Single card: centered, unrotated.
	var solo := CardSpread.panoramic_layout(1, bounds, Vector2(20, 20), 24.0, 10.0)
	assert_float(solo[0]["rect"].position.x).is_equal_approx((bounds.x - solo[0]["rect"].size.x) * 0.5, 0.01)
	assert_float(float(solo[0]["rotation"])).is_zero()
	# Many cards overlap rather than overflow (compact, still bounded).
	var crowd := CardSpread.panoramic_layout(24, Vector2(1152, 720), Vector2(20, 20), 24.0, 10.0)
	var rightmost: Rect2 = crowd[23]["rect"]
	assert_float(rightmost.end.x).is_less_equal(1152.0 + 0.001)


func test_spread_mode_flags() -> void:
	var spread := CardSpread.new()
	auto_free(spread)
	spread.set_portrait(true)
	assert_bool(spread.is_portrait()).is_true()
	assert_int(spread.mode).is_equal(CardSpread.Mode.STACKED)
	spread.set_portrait(false)
	assert_bool(spread.is_portrait()).is_false()
	assert_int(spread.mode).is_equal(CardSpread.Mode.PANORAMIC)


# --- 5b. The armed Eye's lane reserve (finishing refinement #3) --------------------------


## The additive-param pattern (the header insert's own backward-exactness
## rule): a zero reserve reproduces the pre-refinement rects EXACTLY —
## the resting table's layout is pinned, only the armed state narrows it.
func test_lane_reserve_zero_is_backward_exact() -> void:
	for n in [1, 5, 11]:
		var default_stacked := CardSpread.stacked_layout(n, Vector2(720, 955), 3, Vector2(20, 20))
		var zero_stacked := CardSpread.stacked_layout(n, Vector2(720, 955), 3, Vector2(20, 20), 0.0)
		assert_int(zero_stacked.size()).is_equal(default_stacked.size())
		for i in zero_stacked.size():
			assert_bool(zero_stacked[i] == default_stacked[i]) \
				.override_failure_message("stacked reserve=0 moved a resting card")
		var default_pan := CardSpread.panoramic_layout(n, Vector2(1104, 395), Vector2(20, 20), 24.0, 10.0)
		var zero_pan := CardSpread.panoramic_layout(n, Vector2(1104, 395), Vector2(20, 20), 24.0, 10.0, 0.0)
		assert_int(zero_pan.size()).is_equal(default_pan.size())
		for i in zero_pan.size():
			assert_bool((zero_pan[i]["rect"] as Rect2) == (default_pan[i]["rect"] as Rect2)) \
				.override_failure_message("panoramic reserve=0 moved a resting card")
			assert_float(float(zero_pan[i]["rotation"])).is_equal(float(default_pan[i]["rotation"]))


## A standing reserve keeps EVERY card rect clear of the table's right
## lane — the armed Watchful Eye's seat (the perch must not crowd the
## fan's end card; the table itself makes way). Both topologies, at a
## real reserve (the armed lane) and crowded rosters.
func test_lane_reserve_keeps_cards_clear_of_the_armed_seat() -> void:
	var reserve := 184.0  # the landscape armed lane net of the spread margin
	for n in [1, 5, 11, 24]:
		var stacked := CardSpread.stacked_layout(n, Vector2(1104, 395), 3, Vector2(20, 20), reserve)
		for rect in stacked:
			assert_float(rect.end.x).is_less_equal(1104.0 - reserve + 0.5) \
				.override_failure_message("a stacked card entered the armed lane")
		var panoramic := CardSpread.panoramic_layout(n, Vector2(1104, 395), Vector2(20, 20), 24.0, 10.0, reserve)
		for entry in panoramic:
			assert_float((entry["rect"] as Rect2).end.x).is_less_equal(1104.0 - reserve + 0.5) \
				.override_failure_message("the fan's end card entered the armed lane")


## The reserve joins the honest minimum (a parent sizing the spread below
## cards-plus-lane would squeeze cards under the grip).
func test_lane_reserve_joins_the_minimum_size() -> void:
	# Two fresh spreads (the min cache computes once per instance — the
	# existing min-size tests' own pattern: configure, then read).
	var bare_spread := _spread_with_cards(5)
	bare_spread.columns = 2
	bare_spread.space = Vector2(20, 20)
	var bare: float = bare_spread.get_combined_minimum_size().x
	var reserved := _spread_with_cards(5)
	reserved.columns = 2
	reserved.space = Vector2(20, 20)
	reserved.right_reserve = 160.0
	assert_float(reserved.get_combined_minimum_size().x).is_equal_approx(bare + 160.0, 0.01)
	# And back to bare when the lane lifts.
	var relifted := _spread_with_cards(5)
	relifted.columns = 2
	relifted.space = Vector2(20, 20)
	relifted.right_reserve = 160.0
	relifted.right_reserve = 0.0
	assert_float(relifted.get_combined_minimum_size().x).is_equal_approx(bare, 0.01)


# --- 6. Minimum sizes -------------------------------------------------------------------


func _spread_with_cards(n: int) -> CardSpread:
	var spread := CardSpread.new()
	auto_free(spread)
	for i in n:
		var frame := (load(FRAME_SCENE) as PackedScene).instantiate() as Control
		auto_free(frame)
		spread.add_child(frame)
	return spread


func test_stacked_minimum_size_is_the_grid_of_card_minimums() -> void:
	var spread := _spread_with_cards(5)
	spread.columns = 2
	spread.space = Vector2(20, 20)
	var min_size: Vector2 = spread.get_combined_minimum_size()
	# 3 rows x 2 cols of 96x96 frames + separations.
	assert_float(min_size.x).is_equal_approx(2.0 * 96.0 + 20.0, 0.01)
	assert_float(min_size.y).is_equal_approx(3.0 * 96.0 + 2.0 * 20.0, 0.01)


func test_panoramic_minimum_size_is_the_overlap_packed_span() -> void:
	var spread := _spread_with_cards(5)
	spread.mode = CardSpread.Mode.PANORAMIC
	spread.space = Vector2(20, 20)
	var min_size: Vector2 = spread.get_combined_minimum_size()
	assert_float(min_size.x).is_equal_approx(96.0 + 4.0 * 96.0 * CardSpread.PANORAMA_MIN_ADVANCE, 0.01)
	assert_float(min_size.y).is_greater_equal(96.0)


func test_slot_topology_rects_follow_the_brief() -> void:
	var bounds := Vector2(720, 1280)
	var portrait := OrientationSlot.topology_rects(true, bounds, Vector2(216, 48), Vector2(400, 102), 12)
	# Portrait: pips on the TOP rail, chronicle at the bottom.
	assert_float(portrait["rail"].position.y).is_equal(12.0)
	assert_float(portrait["chronicle"].position.y + portrait["chronicle"].size.y).is_equal_approx(bounds.y - 12.0, 0.01)
	var landscape := OrientationSlot.topology_rects(false, Vector2(1152, 720), Vector2(216, 48), Vector2(600, 102), 12)
	# Landscape: pips along the BOTTOM edge.
	assert_float(landscape["rail"].position.y + landscape["rail"].size.y).is_equal_approx(720.0 - 12.0, 0.01)
	assert_float(landscape["chronicle"].position.y).is_equal(12.0)
	# The spread stays BETWEEN the rails, non-negative, no overlap, in
	# both topologies (portrait: rail above; landscape: rail below).
	assert_float(portrait["spread"].position.y).is_greater_equal(portrait["rail"].position.y + portrait["rail"].size.y)
	assert_float(portrait["spread"].position.y + portrait["spread"].size.y).is_less_equal(portrait["chronicle"].position.y)
	assert_float(landscape["spread"].position.y).is_greater_equal(landscape["chronicle"].position.y + landscape["chronicle"].size.y)
	assert_float(landscape["spread"].position.y + landscape["spread"].size.y).is_less_equal(landscape["rail"].position.y)
	for rects in [portrait, landscape]:
		assert_float(rects["spread"].size.y).is_greater_equal(0.0)


func test_every_focusable_in_the_lab_meets_the_grip_floor() -> void:
	var lab := await _mounted_lab()
	for slot: OrientationSlot in [lab.get_portrait_slot(), lab.get_landscape_slot()]:
		for focusable in slot.focusables():
			var min_size: Vector2 = focusable.get_combined_minimum_size()
			assert_float(min_size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
			assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)


# --- 7. The lab scene --------------------------------------------------------------------


func test_lab_scene_instantiates_headless_with_all_sections() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	assert_that(router).is_not_null()
	assert_int(router.current_orientation()).is_equal(LayoutRouter.ScreenOrientation.LANDSCAPE)
	assert_bool(lab.get_portrait_slot().visible).is_false()
	assert_bool(lab.get_landscape_slot().visible).is_true()
	# Both slots carry the same demo content (same component scenes).
	assert_int((lab.get_portrait_slot() as OrientationSlot).card_count()).is_equal(5)
	assert_int((lab.get_landscape_slot() as OrientationSlot).card_count()).is_equal(5)
	assert_that(lab.get_portrait_slot().get_pip(2)).is_not_null()
	assert_that(lab.get_landscape_slot().get_chronicle_line(1)).is_not_null()
	# Debug panel present with its two controls.
	assert_that(router.find_focusable_element(lab, "debug_orientation")).is_not_null()
	assert_that(router.find_focusable_element(lab, "debug_size")).is_not_null()
	# Focus seeded on the visible slot (a screen must seed itself).
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_not_null()


# --- 8. The lab at the four common test sizes (real window resizes) ------------------
# NOTE: these run under gdUnit4 (not the acceptance runner): its coroutine
# support resumes multi-await tests correctly — the acceptance runner's
# Variant-invoked suite coroutines resume only their FIRST suspension
# (measured, 4.7.2 headless), so frame-driven checks live here.

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]
const EXPECTED_PORTRAIT := [true, false, false, true]


func _settle_window(lab: ResponsiveScreen, window_size: Vector2i, want_portrait: bool) -> void:
	get_window().size = window_size
	var router := lab.get_router()
	for i in 240:
		await get_tree().process_frame
		if router.is_portrait() == want_portrait and router.design_size().x > 1.0:
			return


func test_lab_at_all_four_test_sizes() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	for i in TEST_SIZES.size():
		await _settle_window(lab, TEST_SIZES[i], EXPECTED_PORTRAIT[i])
		for f in 3:
			await get_tree().process_frame
		var design := router.design_size()
		var want := Vector2(TEST_SIZES[i])
		# Square-base expand: scale = min axis ratio -> short axis == 720.
		var scale: float = minf(want.x, want.y) / 720.0
		var expected := Vector2(want.x / scale, want.y / scale)
		assert_str("%d x %d" % [design.x, design.y]).is_equal("%d x %d" % [expected.x, expected.y])
		assert_bool(router.is_portrait()).is_equal(EXPECTED_PORTRAIT[i])
		# No control clipped: every visible Control's global rect fits the
		# design rect (0.5 design-unit tolerance).
		for offender in _clipped_controls(lab, design):
			assert_str(offender).is_equal("<no clipping expected>")
		# Touch grips preserved at every size on the active slot.
		var active := lab.get_active_slot() as OrientationSlot
		for focusable in active.focusables():
			var min_size: Vector2 = focusable.get_combined_minimum_size()
			assert_float(min_size.x).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
			assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN) - 0.01)
		# Focus seeded (a screen must seed itself).
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
	# R3 smoke evidence: the size_changed count is echoed for the record.
	print("[responsive] size_changed fired %d time(s) across %d resizes (R3 risk probe; swaps landed via signal+poll either way)"
		% [router.size_changed_count(), TEST_SIZES.size()])
	assert_int(router.size_changed_count()).is_greater_equal(1)
	# Restore the square headless window for the other suites.
	get_window().size = Vector2i(720, 720)


func test_mid_session_orientation_roundtrip_keeps_place() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	await _settle_window(lab, Vector2i(1280, 800), false)
	var card := router.find_focusable_element(lab.get_landscape_slot(), "spread_card_3")
	card.grab_focus()
	await get_tree().process_frame
	await _settle_window(lab, Vector2i(720, 1280), true)
	await get_tree().process_frame
	var owner_p: Control = get_viewport().gui_get_focus_owner()
	assert_that(owner_p).is_not_null()
	if owner_p != null:
		assert_str(String(owner_p.get_meta(&"focus_id", "<lost>"))).is_equal("spread_card_3")
		assert_bool(lab.get_portrait_slot().is_ancestor_of(owner_p)).is_true()
	await _settle_window(lab, Vector2i(1920, 1080), false)
	await get_tree().process_frame
	var owner_l: Control = get_viewport().gui_get_focus_owner()
	assert_that(owner_l).is_not_null()
	if owner_l != null:
		assert_str(String(owner_l.get_meta(&"focus_id", "<lost>"))).is_equal("spread_card_3")
	get_window().size = Vector2i(720, 720)


func test_flapping_window_resizes_never_swap() -> void:
	var lab := await _mounted_lab()
	var router := lab.get_router()
	await _settle_window(lab, Vector2i(1280, 800), false)
	# GDScript lambdas capture by VALUE: hold the counter in an array.
	var swaps := [0]
	router.orientation_changed.connect(func(_o: int) -> void: swaps[0] += 1)
	for i in 12:
		get_window().size = Vector2i(720, 1280) if i % 2 == 0 else Vector2i(1280, 800)
		await get_tree().process_frame
	assert_int(swaps[0]).is_zero()
	assert_bool(router.is_portrait()).is_false()
	get_window().size = Vector2i(720, 720)


## Visible Controls whose global rect escapes the design rect.
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
