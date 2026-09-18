## Type-scale tests (T-QA-05 — PRODUCT.md accessibility: font scaling).
##
## The seam is ui/theme/type_scale.gd: a project setting
## (castle_storm/type/scale, 1.0 default) multiplies the shared theme's
## font ladder from its AUTHORED base, plus the local size overrides and
## the text panel budgets that grow with text. Pinned here:
##   1. RANGE — the factor clamps to [1.0, 1.3] from the setting/apply.
##   2. THE LADDER — every scaled type + the default grows exactly round(
##      base*factor); repeated applies never compound; reset() restores
##      the AUTHORED values bit-exact.
##   3. MINIMUMS GROW — a mounted label's minimum size grows with the
##      factor (layouts accommodate: containers re-flow, nothing shrinks).
##   4. BUDGETS GROW — the blockquote/choice panel widths (the audited
##      no-clip surfaces) scale by the same factor.
##   5. NO-CLIP AT MAX — the widest catch-up rows composed by the real
##      print, measured in the theme's real face at 1.3, fit the LIVE
##      quote label with margin (the T-UI-06/T-UI-09 font-metric standard,
##      re-run at the top of the supported range).
##   6. LOCAL OVERRIDES — a local add_theme_font_size_override site
##      (the intro title) renders scaled, not fixed.
extends GdUnitTestSuite

const THEME_PATH := "res://ui/theme/spread_theme.tres"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.tscn")
## The AUTHORED ladder (spread_theme.tres) — drift here is a product
## decision and must update this table and docs/acceptance-sweep.md.
## (The readability pass raised every rung one coherent step: see
## DESIGN.md's Typography and the production log's readability entry.)
const AUTHORED := {
	&"Heading": 44, &"CardTitle": 36, &"Body": 24, &"RoleLine": 22,
	&"Numerals": 28, &"ChronicleLine": 24, &"PipLabel": 18, &"Button": 24,
}
const AUTHORED_DEFAULT := 26


func before_test() -> void:
	TypeScale.reset()


func after_test() -> void:
	TypeScale.reset()


func _theme() -> Theme:
	var theme := load(THEME_PATH) as Theme
	assert_that(theme).is_not_null()
	return theme


# --- 1. Range ---------------------------------------------------------------------------


func test_factor_defaults_to_one_and_clamps_to_the_supported_range() -> void:
	assert_float(TypeScale.factor()).is_equal(1.0)  # project setting default
	TypeScale.apply_factor(2.0)
	assert_float(TypeScale.factor()).is_equal(TypeScale.MAX_SCALE)
	TypeScale.apply_factor(0.5)
	assert_float(TypeScale.factor()).is_equal(TypeScale.MIN_SCALE)
	TypeScale.apply_factor(1.15)
	assert_float(TypeScale.factor()).is_equal(1.15)


func test_scaled_rounds_local_overrides() -> void:
	assert_int(TypeScale.scaled(34)).is_equal(34)
	TypeScale.apply_factor(1.3)
	assert_int(TypeScale.scaled(34)).is_equal(44)  # 44.2 -> 44
	assert_int(TypeScale.scaled(15)).is_equal(20)  # 19.5 -> 20 (half away)


# --- 2. The ladder ----------------------------------------------------------------------


func test_apply_factor_scales_every_type_from_the_authored_base() -> void:
	var theme := _theme()
	if theme == null:
		return
	TypeScale.apply_factor(1.25, theme)
	for type_name: StringName in AUTHORED:
		var want: int = int(round(float(AUTHORED[type_name]) * 1.25))
		assert_int(theme.get_font_size(&"font_size", type_name)).is_equal(want) \
			.override_failure_message("type %s did not scale" % type_name)
	assert_int(theme.default_font_size).is_equal(int(round(float(AUTHORED_DEFAULT) * 1.25)))


func test_repeated_applies_never_compound_and_reset_restores_authored() -> void:
	var theme := _theme()
	if theme == null:
		return
	TypeScale.apply_factor(1.3, theme)
	TypeScale.apply_factor(1.3, theme)  # idempotent
	TypeScale.apply_factor(1.1, theme)  # re-scale from base, not compounded
	assert_int(theme.get_font_size(&"font_size", &"ChronicleLine")).is_equal(26)  # 24*1.1 (raised ladder)
	TypeScale.reset(theme)
	for type_name: StringName in AUTHORED:
		assert_int(theme.get_font_size(&"font_size", type_name)).is_equal(AUTHORED[type_name])
	assert_int(theme.default_font_size).is_equal(AUTHORED_DEFAULT)


# --- 3. Minimums grow -------------------------------------------------------------------


func test_label_minimums_grow_with_the_factor() -> void:
	var label := Label.new()
	label.theme_type_variation = &"Body"
	label.text = "The crown takes notice of the yard."
	auto_free(label)
	add_child(label)
	await get_tree().process_frame
	TypeScale.apply_factor(1.0)
	await get_tree().process_frame
	var base_min: Vector2 = label.get_combined_minimum_size()
	TypeScale.apply_factor(1.3)
	await get_tree().process_frame
	await get_tree().process_frame
	var scaled_min: Vector2 = label.get_combined_minimum_size()
	assert_float(scaled_min.x).is_greater(base_min.x + 5.0)
	assert_float(scaled_min.y).is_greater(base_min.y + 1.0)
	remove_child(label)


# --- 4. Panel budgets -------------------------------------------------------------------


func test_quote_and_choice_budgets_grow_with_the_factor() -> void:
	var bounds := Vector2(1152.0, 720.0)
	TypeScale.apply_factor(1.0)
	TypeScale.apply_factor(1.0)
	var base_quote: Rect2 = SuspicionEvents.quote_rect(bounds, Vector2(300, 200), 600.0)
	var base_choice: Rect2 = SuspicionEvents.choice_rect(bounds, Vector2(280, 200))
	TypeScale.apply_factor(1.3)
	var scaled_quote: Rect2 = SuspicionEvents.quote_rect(bounds, Vector2(300, 200), 600.0)
	var scaled_choice: Rect2 = SuspicionEvents.choice_rect(bounds, Vector2(280, 200))
	assert_float(scaled_quote.size.x).is_equal_approx(minf(560.0 * 1.3, bounds.x - 12.0), 0.01)
	assert_float(scaled_quote.size.x).is_greater(base_quote.size.x + 100.0)
	assert_float(scaled_choice.size.x).is_equal_approx(minf(312.0 * 1.3, bounds.x - 12.0), 0.01)
	assert_float(scaled_choice.size.x).is_greater(base_choice.size.x + 60.0)
	# Narrow windows still clamp inside the bounds at any scale.
	var narrow: Rect2 = SuspicionEvents.quote_rect(Vector2(500, 900), Vector2(300, 200), 800.0)
	assert_float(narrow.size.x).is_less_equal(500.0 - 12.0)


# --- 5. No-clip at the top of the range -------------------------------------------------


## The widest rows the while-you-were-away print can compose (the
## test_catch_up_ux maximal report), through the REAL seam onto a LIVE
## mounted quote at 1.3 — every row measured in the theme's real
## ChronicleLine face against the label it must fit.
func test_the_widest_catch_up_rows_fit_the_quote_label_at_max_scale() -> void:
	MotionProfile.forced = 1
	TypeScale.apply_factor(1.3)
	var host := _host(20261122)
	var screen := await _mounted(host)
	var report := {
		"capped": true, "clamped_seconds": 8 * 3600,
		"arrivals": 5, "training_completions": 4, "promotions": 3,
		"resource_delta": {&"food": -2345, &"timber": 1999, &"iron": 1777},
		"suspicion_before": 5, "suspicion_after": 95, "suspicion_delta": 90,
		"crackdowns": 2, "run_endings": 1,
	}
	var rows: Array[Dictionary] = []
	rows.assign(CatchUpPrint.rows(report))
	var bounds: Vector2 = screen._design_bounds().size
	screen._suspicion.open_quote_rows(rows, bounds, screen._quote_floor(), 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var want_label := minf(560.0 * 1.3, bounds.x - 12.0) - 84.0
	var checked := 0
	for line: Control in screen._suspicion._quote._lines:
		var label := _chronicle_label_of(line)
		if label == null or String(label.text).is_empty():
			continue
		assert_float(label.size.x).is_equal_approx(want_label, 0.5)
		# The resolved render size (the declared ChronicleLine at this
		# factor) — the honest seam since the readability pass; the
		# "font"-item fallback would measure at the theme DEFAULT (33.8
		# at 1.3) and over-measure honest rows.
		var size := label.get_theme_font_size(&"font_size")
		assert_int(size).is_greater_equal(28)  # 24 * 1.3
		var width := label.get_theme_font("font").get_string_size(
			String(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		assert_float(width).is_less_equal(label.size.x - 30.0) \
			.override_failure_message("row clips at 1.3: %s (%.0fpx > %.0fpx)"
				% [String(label.text), width, label.size.x - 30.0])
		checked += 1
	assert_int(checked).is_greater_equal(5)
	screen.queue_free()


# --- 6. Local overrides scale -----------------------------------------------------------


func test_local_font_overrides_follow_the_scale() -> void:
	TypeScale.apply_factor(1.3)  # BEFORE the build: overrides compute at _ready
	var packet := IntroPacket.new()
	auto_free(packet)
	get_tree().root.add_child(packet)
	packet.size = Vector2(720, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var title := _label_with_variation(packet, &"CardTitle")
	assert_that(title).is_not_null()
	if title != null:
		# The authored override is 34 (intro_packet.gd); at 1.3 it renders 44.
		assert_int(title.get_theme_font_size("font_size")).is_equal(44)
	remove_child(packet)
	packet.queue_free()


# --- helpers ----------------------------------------------------------------------------


func _label_with_variation(root: Node, variation: StringName) -> Label:
	if root is Label and (root as Label).theme_type_variation == variation:
		return root
	for child in root.get_children():
		var found := _label_with_variation(child, variation)
		if found != null:
			return found
	return null


func _chronicle_label_of(row: Node) -> Label:
	if row is Label:
		return row
	for child in row.get_children():
		if child is HBoxContainer:
			for leaf in child.get_children():
				if leaf is Label:
					return leaf
	return null


func _host(run_seed: int) -> GameHost:
	var root := "user://cs_type_scale/host-%d" % run_seed
	_erase(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _mounted(host: GameHost) -> Node:
	var screen := SpreadScreen.instantiate()
	screen.host = host
	screen.intro_enabled = false
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _erase(path: String) -> void:
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
		_erase(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
