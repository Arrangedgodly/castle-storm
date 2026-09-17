## Theme grammar tests (T-UI-01).
##
## Headless proof of the component system's contracts:
##   1. THEME RESOURCE loads and mirrors the token vocabulary (core
##      palette + grammar constants + type variations with real fonts).
##   2. PALETTE COMPLETENESS PER REGIME — the theme's regime tokens
##      equal the content .tres inks (data-driven recolor), for all 4.
##   3. STATE -> EDGE-FORM MAPPING — solid ready / dashed in progress /
##      struck lost, over the documented sim vocabulary; unknown states
##      fail loudly to SOLID.
##   4. PHASE-DEEPENING GROUNDS — monotone darkening recruiting ->
##      training -> ready across all regimes; aftermath light + cool;
##      text ink passes contrast on every ground (the print rule).
##   5. COMPONENT MINIMUM SIZES — the touch grip floor (>= 48 units)
##      on CardFrame, CardFace, PipMark, ChronicleLine.
##   6. MISPRINT — deterministic, bounded, and actually varying.
##   7. COLORBLIND-SAFE RESOURCES — shape + glyph + label channels all
##      distinct; numerals abbreviate at idle scale.
##   8. FONT LICENSING — OFL families vendored with license texts and
##      present in the generated ATTRIBUTIONS.md.
##   9. GALLERY — the demo scene instantiates headless, error-free,
##      with every section's components present.
##  10. FACE PLATES — landed faces are SINGLE-CELL AtlasTexture crops per
##      the manifest's atlas_region (the round-1 verifier FAIL's regression
##      guard: never the whole pose sheet), printed through the two-ink
##      pass; pending/unknown keys keep the honest placeholder.
##  11. FLIP SEAM — CardFrame's explicit promotion-flip contract for
##      T-UI-04 (signals + state + back-side content hiding).
extends GdUnitTestSuite

const THEME_PATH := "res://ui/theme/spread_theme.tres"
const GALLERY_PATH := "res://ui/theme/theme_gallery.tscn"
const ATTRIBUTIONS_PATH := "res://assets/vendor/ATTRIBUTIONS.md"
const FONT_REGULAR := "res://assets/vendor/fonts/alegreya-sans/AlegreyaSans-Regular.ttf"
const FONT_DISPLAY := "res://assets/vendor/fonts/im-fell-english-sc/IMFellEnglishSC-Regular.ttf"
const VARIATIONS: Array[StringName] = [&"Heading", &"CardTitle", &"Body", &"RoleLine", &"Numerals", &"ChronicleLine", &"PipLabel"]


func _theme() -> Theme:
	var theme := load(THEME_PATH) as Theme
	assert_that(theme).is_not_null()
	return theme


# --- 1. The theme resource --------------------------------------------------------


func test_theme_loads_with_default_font_and_sizes() -> void:
	var theme := _theme()
	if theme == null:
		return
	assert_that(theme.default_font).is_not_null()
	assert_int(theme.default_font_size).is_greater_equal(20)
	# The workhorse face is the default; the display face is a variation.
	assert_bool(theme.default_font.resource_path == FONT_REGULAR).is_true()


func test_theme_type_variations_carry_distinct_fonts() -> void:
	var theme := _theme()
	if theme == null:
		return
	var fonts: Array[Font] = []
	for variation in VARIATIONS:
		assert_bool(theme.get_type_variation_base(variation) == &"Label").is_true()
		var font := theme.get_font("font", variation) as Font
		assert_that(font).is_not_null()
		assert_int(theme.get_font_size("font_size", variation)).is_greater_equal(15)
		if font is FontVariation or font is FontFile:
			fonts.append(font)
	# Display and workhorse faces both present among the variations.
	var paths := fonts.map(func(f: Font) -> String: return f.resource_path)
	assert_bool(paths.has(FONT_DISPLAY)).is_true()
	assert_bool(paths.has(FONT_REGULAR)).is_true()
	# A real scale ladder, not one size stamped everywhere.
	var sizes: Array[int] = []
	for variation in VARIATIONS:
		sizes.append(theme.get_font_size("font_size", variation))
	assert_int(sizes.min()).is_less(sizes.max())


func test_theme_core_tokens_mirror_inks() -> void:
	var theme := _theme()
	if theme == null:
		return
	for token: String in Inks.CORE_TOKENS:
		assert_bool(theme.has_color(token, "")).is_true()
		if theme.has_color(token, ""):
			assert_that(theme.get_color(token, "")).is_equal(Inks.CORE_TOKENS[token])
	for token: String in Inks.GRAMMAR_TOKENS:
		assert_bool(theme.has_constant(token, "")).is_true()
		if theme.has_constant(token, ""):
			assert_int(theme.get_constant(token, "")).is_equal(int(Inks.GRAMMAR_TOKENS[token]))


func test_theme_phase_ground_tokens_are_the_inks_grounds() -> void:
	var theme := _theme()
	if theme == null:
		return
	var names := ["ground_recruiting", "ground_training", "ground_ready", "ground_aftermath"]
	for phase: int in [Inks.Phase.RECRUITING, Inks.Phase.TRAINING, Inks.Phase.READY, Inks.Phase.AFTERMATH]:
		assert_bool(theme.has_color(names[phase], "")).is_true()
		assert_that(theme.get_color(names[phase], "")).is_equal(Inks.ground_for(&"", phase))


# --- 2. Palette completeness per regime (data-driven recolor) ----------------------


func test_regime_ink_tokens_complete_and_equal_to_content() -> void:
	var theme := _theme()
	var pack := ContentValidator.load_pack("res://content/mvp/pack.tres")
	if theme == null or pack == null:
		assert_that(theme).is_not_null()
		assert_that(pack).is_not_null()
		return
	assert_int(pack.regimes.size()).is_equal(4)
	for regime: RegimeDef in pack.regimes:
		var ground_token := "regime_ground_%s" % regime.id
		var secondary_token := "regime_secondary_%s" % regime.id
		assert_bool(theme.has_color(ground_token, "")).is_true()
		assert_bool(theme.has_color(secondary_token, "")).is_true()
		assert_that(theme.get_color(ground_token, "")).is_equal(regime.ink_ground)
		assert_that(theme.get_color(secondary_token, "")).is_equal(regime.ink_secondary)
		# The static lookups agree with the content resources.
		assert_that(Inks.regime_ground(regime.id)).is_equal(regime.ink_ground)
		assert_that(Inks.regime_secondary(regime.id)).is_equal(regime.ink_secondary)


func test_regime_secondaries_are_pairwise_distinct() -> void:
	var ids := Inks.regime_ids()
	assert_int(ids.size()).is_equal(4)
	var secondaries := ids.map(func(id: StringName) -> Color: return Inks.regime_secondary(id))
	var grounds := ids.map(func(id: StringName) -> Color: return Inks.regime_ground(id))
	for i in secondaries.size():
		for j in range(i + 1, secondaries.size()):
			assert_bool(secondaries[i] == secondaries[j]).is_false()
			assert_bool(grounds[i] == grounds[j]).is_false()


# --- 3. State -> edge-form mapping (form, never hue) --------------------------------


func test_edge_form_mapping_matches_sim_vocabulary() -> void:
	# The emission-line rail raise: solid=ready, dashed=in-progress, struck=lost.
	assert_int(Inks.edge_form_for_state(&"ready")).is_equal(Inks.EdgeForm.SOLID)
	assert_int(Inks.edge_form_for_state(&"idle")).is_equal(Inks.EdgeForm.SOLID)
	assert_int(Inks.edge_form_for_state(&"working")).is_equal(Inks.EdgeForm.SOLID)
	assert_int(Inks.edge_form_for_state(&"assigned")).is_equal(Inks.EdgeForm.SOLID)
	assert_int(Inks.edge_form_for_state(&"in_progress")).is_equal(Inks.EdgeForm.DASHED)
	assert_int(Inks.edge_form_for_state(&"training")).is_equal(Inks.EdgeForm.DASHED)
	assert_int(Inks.edge_form_for_state(&"awaiting_gear")).is_equal(Inks.EdgeForm.DASHED)
	assert_int(Inks.edge_form_for_state(&"lost")).is_equal(Inks.EdgeForm.STRUCK)
	assert_int(Inks.edge_form_for_state(&"scattered")).is_equal(Inks.EdgeForm.STRUCK)
	assert_int(Inks.edge_form_for_state(&"crushed")).is_equal(Inks.EdgeForm.STRUCK)
	assert_int(Inks.edge_form_for_state(&"seized")).is_equal(Inks.EdgeForm.STRUCK)
	# All three forms actually occur (a two-form mapping is a silent regression).
	var forms: Array[int] = []
	for state: StringName in Inks.EDGE_FORM_STATES:
		if not forms.has(Inks.EDGE_FORM_STATES[state]):
			forms.append(Inks.EDGE_FORM_STATES[state])
	assert_int(forms.size()).is_equal(3)


func test_edge_form_unknown_state_fails_loudly_to_solid() -> void:
	assert_int(Inks.edge_form_for_state(&"definitely_not_a_state")).is_equal(Inks.EdgeForm.SOLID)


func test_chronicle_class_mapping_matches_event_vocabulary() -> void:
	assert_int(Inks.line_class_for_event(&"suspicion_warn")).is_equal(Inks.LineClass.WARN)
	assert_int(Inks.line_class_for_event(&"suspicion_telegraph")).is_equal(Inks.LineClass.WARN)
	assert_int(Inks.line_class_for_event(&"crackdown_struck")).is_equal(Inks.LineClass.STRIKE)
	assert_int(Inks.line_class_for_event(&"crackdown_seized")).is_equal(Inks.LineClass.STRIKE)
	assert_int(Inks.line_class_for_event(&"run_crushed")).is_equal(Inks.LineClass.STRIKE)
	assert_int(Inks.line_class_for_event(&"run_won")).is_equal(Inks.LineClass.VICTORY)
	assert_int(Inks.line_class_for_event(&"assault_won")).is_equal(Inks.LineClass.VICTORY)
	assert_int(Inks.line_class_for_event(&"suspicion_rose")).is_equal(Inks.LineClass.PLAIN)
	assert_int(Inks.line_class_for_event(&"catch_up_applied")).is_equal(Inks.LineClass.PLAIN)
	assert_int(Inks.line_class_for_event(&"building_built")).is_equal(Inks.LineClass.PLAIN)
	assert_int(Inks.line_class_for_event(&"no_such_event")).is_equal(Inks.LineClass.PLAIN)


# --- 4. Phase-deepening grounds ----------------------------------------------------


func test_ground_deepens_monotonically_to_ready_then_washes_aftermath() -> void:
	var ids := Inks.regime_ids()
	ids.append(&"")  # the neutral ground too
	for id: StringName in ids:
		var recruiting := Inks.ground_for(id, Inks.Phase.RECRUITING)
		var training := Inks.ground_for(id, Inks.Phase.TRAINING)
		var ready := Inks.ground_for(id, Inks.Phase.READY)
		var aftermath := Inks.ground_for(id, Inks.Phase.AFTERMATH)
		assert_float(Inks.relative_luminance(training)).is_less(Inks.relative_luminance(recruiting))
		assert_float(Inks.relative_luminance(ready)).is_less(Inks.relative_luminance(training))
		# Aftermath: lighter than ready (the morning after) and cool (blue > red).
		assert_float(Inks.relative_luminance(aftermath)).is_greater(Inks.relative_luminance(ready))
		assert_bool(aftermath.b > aftermath.r).is_true()


func test_ground_text_ink_passes_contrast_on_every_ground() -> void:
	## The print rule keeps chronicle text legible on every phase x regime:
	## paper-bright ink on dark grounds, near-black ink on the light
	## aftermath — both channels >= 4.5:1 (WCAG body floor).
	var ids := Inks.regime_ids()
	ids.append(&"")
	for id: StringName in ids:
		for phase: int in [Inks.Phase.RECRUITING, Inks.Phase.TRAINING, Inks.Phase.READY, Inks.Phase.AFTERMATH]:
			var ground := Inks.ground_for(id, phase)
			assert_float(Inks.contrast_ratio(Inks.ground_text_ink(ground), ground)).is_greater_equal(4.5)


func test_core_ink_contrast_floors() -> void:
	assert_float(Inks.contrast_ratio(Inks.INK, Inks.PAPER)).is_greater_equal(4.5)
	assert_float(Inks.contrast_ratio(Inks.INK_SOFT, Inks.PAPER)).is_greater_equal(4.5)
	assert_float(Inks.contrast_ratio(Inks.RED, Inks.PAPER)).is_greater_equal(4.5)
	# The ground accent red stays a mark (>= 3:1) on every dark ground.
	var ids := Inks.regime_ids()
	ids.append(&"")
	for id: StringName in ids:
		for phase: int in [Inks.Phase.RECRUITING, Inks.Phase.TRAINING, Inks.Phase.READY]:
			var ground := Inks.ground_for(id, phase)
			assert_float(Inks.contrast_ratio(Inks.RED_CANDLE, ground)).is_greater_equal(3.0)


# --- 5. Component minimum sizes (the touch grip floor) ------------------------------


func test_card_frame_minimum_size_honors_touch_grip() -> void:
	var frame := (load("res://ui/theme/card_frame.tscn") as PackedScene).instantiate() as Control
	auto_free(frame)
	var minimum := frame.get_combined_minimum_size()
	assert_float(minimum.x).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_float(minimum.y).is_greater_equal(Inks.TOUCH_GRIP_MIN)


func test_face_plate_minimum_size_honors_touch_grip() -> void:
	## BoxContainer minimums compute from children, so the component must
	## be mounted (the container grammar's real world) before measuring.
	var face := (load("res://ui/theme/card_face.tscn") as PackedScene).instantiate() as Control
	auto_free(face)
	add_child(face)
	await get_tree().process_frame
	var minimum := face.get_combined_minimum_size()
	assert_float(minimum.x).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_float(minimum.y).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	remove_child(face)


## THE PLATE FIT (the backlog sweep's phone-scale clip pass): at
## roster-scale widths a plate's print steps its font DOWN to fit the plate
## before the T-UI-03 clip fail-safe ever engages — pinned on the longest
## single-word recruit name at a 5-column phone-roster plate width. The
## STRUCTURAL RESIDUE is pinned too: at a width where even the floor
## cannot fit the text, the applied size IS the floor and the label keeps
## its fail-safe clip (documented, never past the card).
func test_face_plates_step_down_to_fit_before_clipping() -> void:
	var face := (load("res://ui/theme/card_face.tscn") as PackedScene).instantiate() as CardFace
	auto_free(face)
	face.card_name = "Stitches"  # the longest single-word pool name
	face.role_line = "level 1 · 1/2 workers"
	add_child(face)
	face.size = Vector2(108.0, 150.0)  # a 5-column phone-roster plate
	await get_tree().process_frame
	await get_tree().process_frame
	var theme: Theme = load("res://ui/theme/spread_theme.tres") as Theme
	var title_base: int = theme.get_font_size(&"font_size", &"CardTitle")
	var title: Label = face.name_plate()
	var applied: int = title.get_theme_font_size(&"font_size")
	# The fit actually stepped down from the themed base…
	assert_int(applied).is_less(title_base)
	# …never below the floor…
	assert_int(applied).is_greater_equal(int(round(float(title_base) * CardFace.TITLE_FIT_FLOOR)) - 1)
	# …and the WHOLE title now fits the plate in real font metrics (no
	# mid-word clip at phone roster scale — the critique's P3 residue).
	var font: Font = title.get_theme_font(&"font")
	var width: float = font.get_string_size(title.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, applied).x
	assert_float(width).is_less_equal(title.size.x + 0.5)
	# The role plate fits its own floor the same way.
	var role_base: int = theme.get_font_size(&"font_size", &"RoleLine")
	var role: Label = face.role_plate()
	var role_applied: int = role.get_theme_font_size(&"font_size")
	assert_int(role_applied).is_less(role_base)
	var role_font: Font = role.get_theme_font(&"font")
	var role_width: float = role_font.get_string_size(role.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, role_applied).x
	assert_float(role_width).is_less_equal(role.size.x + 0.5)
	remove_child(face)
	# THE STRUCTURAL RESIDUE, pinned honestly: a plate too narrow for even
	# the floor keeps the fail-safe (clip at the plate edge) — the fit stops
	# at the floor and the label stays clip_text (never past the card).
	var stub := CardFace.new()
	auto_free(stub)
	stub.card_name = "Stitches"
	add_child(stub)
	stub.size = Vector2(60.0, 150.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var stub_title: Label = stub.name_plate()
	assert_int(stub_title.get_theme_font_size(&"font_size")) \
		.is_equal(int(round(float(title_base) * CardFace.TITLE_FIT_FLOOR)))
	assert_bool(stub_title.clip_text).is_true()  # the documented fail-safe remains
	remove_child(stub)


func test_pip_mark_minimum_size_honors_touch_grip() -> void:
	var pip := (load("res://ui/theme/pip_mark.tscn") as PackedScene).instantiate() as Control
	auto_free(pip)
	add_child(pip)
	await get_tree().process_frame
	var minimum := pip.get_combined_minimum_size()
	assert_float(minimum.x).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	assert_float(minimum.y).is_greater_equal(Inks.TOUCH_GRIP_MIN)
	remove_child(pip)


func test_chronicle_line_minimum_size_honors_touch_grip() -> void:
	var line := (load("res://ui/theme/chronicle_line.tscn") as PackedScene).instantiate() as Control
	auto_free(line)
	var minimum := line.get_combined_minimum_size()
	assert_float(minimum.y).is_greater_equal(Inks.TOUCH_GRIP_MIN)


# --- 6. Misprint character ----------------------------------------------------------


func test_misprint_is_deterministic_and_bounded() -> void:
	var first := Inks.misprint_params(7)
	var second := Inks.misprint_params(7)
	assert_float(float(first.rotation_deg)).is_equal(float(second.rotation_deg))
	assert_vector(Vector2(first.offset)).is_equal(Vector2(second.offset))
	for seed in 24:
		var mp := Inks.misprint_params(seed * 31 + 5)
		assert_float(absf(float(mp.rotation_deg))).is_less_equal(Inks.MISPRINT_MAX_DEG + 0.0001)
		assert_float(absf(Vector2(mp.offset).x)).is_less_equal(Inks.MISPRINT_MAX_OFFSET + 0.0001)
		assert_float(absf(Vector2(mp.offset).y)).is_less_equal(Inks.MISPRINT_MAX_OFFSET + 0.0001)


func test_misprint_varies_across_seeds() -> void:
	var rotations: Array[float] = []
	for seed in 16:
		var mp := Inks.misprint_params(seed * 101 + 3)
		rotations.append(float(mp.rotation_deg))
	var distinct: Array[float] = []
	for rotation in rotations:
		if not distinct.has(rotation):
			distinct.append(rotation)
	assert_int(distinct.size()).is_greater_equal(3)


# --- 7. Colorblind-safe resources + idle-scale numerals -----------------------------


func test_resource_channels_are_triple_encoded() -> void:
	## Shape + glyph + label text all differ per resource; color never
	## carries the distinction alone (it is a redundant channel).
	var shapes: Array[int] = []
	var labels: Array[String] = []
	for kind: int in [Inks.ResourceKind.FOOD, Inks.ResourceKind.TIMBER, Inks.ResourceKind.IRON]:
		shapes.append(Inks.pip_shape(kind))
		labels.append(Inks.pip_label(kind))
	assert_int(shapes.size()).is_equal(3)
	for i in shapes.size():
		for j in range(i + 1, shapes.size()):
			assert_bool(shapes[i] == shapes[j]).is_false()
			assert_bool(labels[i] == labels[j]).is_false()
		assert_bool(labels[i].is_empty()).is_false()


func test_pip_mark_label_channel_defaults_on() -> void:
	var pip := (load("res://ui/theme/pip_mark.tscn") as PackedScene).instantiate() as HBoxContainer
	auto_free(pip)
	add_child(pip)
	await get_tree().process_frame
	assert_bool(pip.show_label).is_true()
	var has_text := false
	for child in pip.get_children():
		if child is VBoxContainer:
			for grandchild in child.get_children():
				if grandchild is Label and not (grandchild as Label).text.is_empty():
					has_text = true
	assert_bool(has_text).is_true()
	remove_child(pip)


func test_amounts_abbreviate_at_idle_scale() -> void:
	assert_str(Inks.abbreviate_amount(0)).is_equal("0")
	assert_str(Inks.abbreviate_amount(999)).is_equal("999")
	assert_str(Inks.abbreviate_amount(1000)).is_equal("1K")
	assert_str(Inks.abbreviate_amount(1234)).is_equal("1.2K")
	assert_str(Inks.abbreviate_amount(15400)).is_equal("15K")
	assert_str(Inks.abbreviate_amount(1250000)).is_equal("1.3M")
	assert_str(Inks.abbreviate_amount(3400000000)).is_equal("3.4B")


# --- 8. Font licensing ----------------------------------------------------------------


func test_fonts_vendored_with_ofl_licenses_and_attributions() -> void:
	for path: String in [
		"res://assets/vendor/fonts/im-fell-english-sc/IMFellEnglishSC-Regular.ttf",
		"res://assets/vendor/fonts/im-fell-english-sc/OFL.txt",
		"res://assets/vendor/fonts/alegreya-sans/AlegreyaSans-Regular.ttf",
		"res://assets/vendor/fonts/alegreya-sans/AlegreyaSans-Medium.ttf",
		"res://assets/vendor/fonts/alegreya-sans/AlegreyaSans-Bold.ttf",
		"res://assets/vendor/fonts/alegreya-sans/AlegreyaSans-Italic.ttf",
		"res://assets/vendor/fonts/alegreya-sans/OFL.txt",
	]:
		assert_bool(FileAccess.file_exists(path)).is_true()
	var text := FileAccess.get_file_as_string(ATTRIBUTIONS_PATH)
	assert_bool(text.contains("OFL-1.1")).is_true()
	assert_bool(text.contains("Igino Marini")).is_true()
	assert_bool(text.contains("Juan Pablo del Peral")).is_true()
	assert_bool(text.contains("IM Fell English SC")).is_true()
	assert_bool(text.contains("Alegreya Sans")).is_true()


func test_theme_fonts_have_glyph_coverage() -> void:
	var theme := _theme()
	if theme == null:
		return
	var display := theme.get_font("font", &"CardTitle") as Font
	var workhorse := theme.get_font("font", &"Numerals") as Font
	assert_that(display).is_not_null()
	assert_that(workhorse).is_not_null()
	# The display face must actually draw letters (an empty/broken font
	# load would size everything zero).
	assert_vector(display.get_string_size("CONSPIRATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 34)).is_not_equal(Vector2.ZERO)
	for digit: String in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		assert_vector(workhorse.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)).is_not_equal(Vector2.ZERO)


# --- 9. The gallery loads headless ----------------------------------------------------


func test_gallery_scene_instantiates_headless_with_all_sections() -> void:
	var packed := load(GALLERY_PATH) as PackedScene
	assert_that(packed).is_not_null()
	if packed == null:
		return
	var gallery := packed.instantiate() as Control
	auto_free(gallery)
	gallery.set_size(Vector2(720, 720))
	add_child(gallery)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(gallery.is_inside_tree()).is_true()
	# Every grammar component is on stage (counted by script attachment,
	# robust to sibling auto-renaming).
	assert_int(_count_script(gallery, "res://ui/theme/card_frame.gd")).is_greater_equal(10)
	assert_int(_count_script(gallery, "res://ui/theme/card_face.gd")).is_greater_equal(10)
	assert_int(_count_script(gallery, "res://ui/theme/table_ground.gd")).is_greater_equal(5)
	assert_int(_count_script(gallery, "res://ui/theme/pip_mark.gd")).is_greater_equal(4)
	assert_int(_count_script(gallery, "res://ui/theme/chronicle_line.gd")).is_greater_equal(5)
	remove_child(gallery)


func _count_script(node: Node, script_path: String) -> int:
	var total := 0
	if node.get_script() != null and String(node.get_script().resource_path) == script_path:
		total += 1
	for child in node.get_children():
		total += _count_script(child, script_path)
	return total


# --- 10. Face plates: single-cell atlas prints (round-1 verifier fix) ---------------


const LANDED_FACE_KEYS: Array[StringName] = [&"face_peasant", &"face_worker", &"face_trainee"]


func _face_asset(key: StringName) -> ArtAssetDef:
	var pack := ContentValidator.load_pack("res://content/mvp/pack.tres")
	if pack == null or pack.art == null:
		return null
	for asset: ArtAssetDef in pack.art.assets:
		if asset != null and asset.id == key:
			return asset
	return null


func test_face_slot_texture_is_single_cell_atlas_per_manifest() -> void:
	## THE round-1 regression guard: FaceSlot's final texture for every
	## landed face is an AtlasTexture whose region is exactly the ONE cell
	## the manifest declares — never the whole 45-pose sheet.
	for key: StringName in LANDED_FACE_KEYS:
		var asset := _face_asset(key)
		assert_that(asset).is_not_null()
		if asset == null:
			continue
		var slot := (load("res://ui/theme/face_slot.tscn") as PackedScene).instantiate() as TextureRect
		auto_free(slot)
		slot.set("face_key", key)
		var face: Texture2D = slot.texture
		assert_bool(face is AtlasTexture).is_true()
		if not (face is AtlasTexture):
			continue
		var at := face as AtlasTexture
		# The crop is the manifest's data, verbatim (data-driven, not UI math).
		assert_bool(at.region == asset.atlas_region).is_true()
		assert_bool(at.region.has_area()).is_true()
		# The region is ONE CELL, not the sheet (the round-1 defect shape).
		var sheet := Vector2(at.atlas.get_width(), at.atlas.get_height())
		assert_bool(at.region.size == sheet).is_false()
		assert_bool(Rect2(Vector2.ZERO, sheet).encloses(at.region)).is_true()
		# The documented grid math (art_asset_def.gd) tiles the real sheet
		# EXACTLY: 9 cols x 5 rows of this cell = 864x640.
		assert_int(int(sheet.x)).is_equal(9 * int(at.region.size.x))
		assert_int(int(sheet.y)).is_equal(5 * int(at.region.size.y))
		# Two-ink print pass mounted (no raw colored sprite on the paper).
		assert_bool(slot.material is ShaderMaterial).is_true()


func test_face_slot_caches_one_atlas_per_key() -> void:
	## Many cards share one spread: the resolver hands out the same cached
	## AtlasTexture per key (one sheet, one crop object, no churn).
	var first := FaceArt.face_texture(&"face_peasant")
	var second := FaceArt.face_texture(&"face_peasant")
	assert_that(first).is_not_null()
	assert_bool(first == second).is_true()


func test_pending_and_unknown_face_keys_print_the_placeholder() -> void:
	## The honest-state contract: pending (tzunghaor not vendored) and
	## unknown keys resolve to NO texture — the authored placeholder draws
	## (FaceSlot._draw), never a guess. The unknown key is loud (push_error).
	var pending_slot := (load("res://ui/theme/face_slot.tscn") as PackedScene).instantiate()
	auto_free(pending_slot)
	pending_slot.face_key = &"face_knight"
	assert_that(pending_slot.texture).is_null()
	assert_that(pending_slot.material).is_null()
	var unknown_slot := (load("res://ui/theme/face_slot.tscn") as PackedScene).instantiate()
	auto_free(unknown_slot)
	unknown_slot.face_key = &"face_nope"
	assert_that(unknown_slot.texture).is_null()
	assert_that(unknown_slot.material).is_null()


func test_card_face_wires_its_key_into_the_slot() -> void:
	## CardFace is the composing seam T-UI-03 mounts: its face_key export
	## must reach the inner FaceSlot as the resolved single-cell atlas.
	var plate := (load("res://ui/theme/card_face.tscn") as PackedScene).instantiate() as Control
	auto_free(plate)
	plate.face_key = &"face_worker"
	add_child(plate)
	await get_tree().process_frame
	var slot := _find_script(plate, "res://ui/theme/face_slot.gd")
	assert_that(slot).is_not_null()
	if slot is TextureRect:
		assert_bool((slot as TextureRect).texture is AtlasTexture).is_true()
	remove_child(plate)


func _find_script(node: Node, script_path: String) -> Node:
	if node.get_script() != null and String(node.get_script().resource_path) == script_path:
		return node
	for child in node.get_children():
		var found := _find_script(child, script_path)
		if found != null:
			return found
	return null


# --- 11. The flip seam (T-UI-04's promotion flip mounts here) -----------------------


func test_card_frame_flip_seam_signals_state_and_noop() -> void:
	var frame := (load("res://ui/theme/card_frame.tscn") as PackedScene).instantiate() as Control
	auto_free(frame)
	add_child(frame)
	assert_bool(frame.is_face_up()).is_true()
	var events: Array = []
	frame.flip_started.connect(func(up: bool) -> void: events.append(["started", up])
	)
	frame.flip_completed.connect(func(up: bool) -> void: events.append(["completed", up])
	)
	frame.flip_to(false)
	assert_bool(frame.is_face_up()).is_false()
	assert_int(events.size()).is_equal(2)
	assert_bool(events[0] == ["started", false]).is_true()
	assert_bool(events[1] == ["completed", false]).is_true()
	# Same-side request is a silent no-op; the silent swap helper emits nothing.
	frame.flip_to(false)
	assert_int(events.size()).is_equal(2)
	frame.set_face_up(true)
	assert_bool(frame.is_face_up()).is_true()
	assert_int(events.size()).is_equal(2)
	frame.flip_to(true)
	assert_int(events.size()).is_equal(2)
	remove_child(frame)


func test_card_frame_back_side_hides_content_and_restores_it() -> void:
	## The base instant flip genuinely shows the BACK (bare paper stock):
	## content children hide on flip down and come back (with their prior
	## visibility) on flip up — the contract T-UI-04 animates around.
	var frame := (load("res://ui/theme/card_frame.tscn") as PackedScene).instantiate() as Control
	auto_free(frame)
	add_child(frame)
	var shown := ColorRect.new()
	auto_free(shown)
	frame.add_child(shown)
	var hidden := ColorRect.new()
	auto_free(hidden)
	hidden.visible = false
	frame.add_child(hidden)
	assert_bool(shown.visible).is_true()
	frame.flip_to(false)
	assert_bool(shown.visible).is_false()
	assert_bool(hidden.visible).is_false()  # never resurrected by the frame
	frame.flip_to(true)
	assert_bool(shown.visible).is_true()
	assert_bool(hidden.visible).is_false()  # prior-visibility respected
	remove_child(frame)
