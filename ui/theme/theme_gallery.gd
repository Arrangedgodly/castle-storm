## theme_gallery — every component in every state (T-UI-01).
##
## The visual inspection scene for the theme grammar, runnable via
## `make run-gallery`: line-form edge states x card types x regime inks
## x phase grounds x both orientations, at the 720x720 design base (R3).
## Built in code so the coverage loops (4 regimes, 4 phases, 3 states,
## 3 resources) are complete by construction — a component state that
## exists but is not shown here is a gallery bug, not a judgment call.
##
## Also loaded headless by tests/unit/test_theme_grammar.gd — the scene
## must instantiate without errors before it is allowed to be pretty.
extends Control

const GROUND_SCENE := preload("res://ui/theme/table_ground.tscn")
const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const FACE_SCENE := preload("res://ui/theme/card_face.tscn")
const PIP_SCENE := preload("res://ui/theme/pip_mark.tscn")
const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")

const FACE_TEXTURES: Dictionary = {
	&"peasant": "res://assets/vendor/kenney/toon-characters/male-person/vector/character_malePerson@2x.png",
	&"worker": "res://assets/vendor/kenney/toon-characters/female-person/vector/character_femalePerson@2x.png",
	&"trainee": "res://assets/vendor/kenney/toon-characters/male-adventurer/vector/character_maleAdventurer@2x.png",
}

var _column: VBoxContainer


func _ready() -> void:
	# The gallery sits on the recruiting ground; deeper phases are shown
	# as strips in their own section.
	var ground := GROUND_SCENE.instantiate() as Control
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.set("phase", Inks.Phase.RECRUITING)
	add_child(ground)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 18)
	margin.add_child(_column)

	_section_header()
	_section_grounds()
	_section_regimes()
	_section_edge_states()
	_section_chronicle()
	_section_cards()
	_section_pips()
	_section_typography()
	_section_focus()
	_maybe_capture()


## Dev inspection hook (not a game path): CS_GALLERY_SHOT=/path/out.png
## renders a few frames and saves a screenshot of the gallery, then quits —
## used by the T-UI-01 build/verification pass to eyeball the grammar
## without a human at the window.
func _maybe_capture() -> void:
	var shot := OS.get_environment("CS_GALLERY_SHOT")
	if shot.is_empty():
		return
	_capture_later.call_deferred(shot)


func _capture_later(path: String) -> void:
	for i in 5:
		await get_tree().process_frame
	# Optional scroll offset (CS_GALLERY_SHOT_SCROLL, design units) so the
	# lower sections can be captured too.
	var scroll_str := OS.get_environment("CS_GALLERY_SHOT_SCROLL")
	if not scroll_str.is_empty() and scroll_str.is_valid_float():
		var scroller := _find_scroll(self)
		if scroller != null:
			scroller.scroll_vertical = int(float(scroll_str))
			for i in 3:
				await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[gallery] screenshot %s (%s)" % [path, "ok" if err == OK else "FAILED %d" % err])
	get_tree().quit(0 if err == OK else 1)


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll(child)
		if found != null:
			return found
	return null


# --- section builders -----------------------------------------------------------


func _section_header() -> void:
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.add_theme_color_override("font_color", Inks.ground_text_ink(Inks.ground_for(&"", Inks.Phase.RECRUITING)))
	title.text = "The Conspiracy's Spread"
	_column.add_child(title)
	var caption := Label.new()
	caption.theme_type_variation = &"ChronicleLine"
	caption.add_theme_color_override("font_color", Inks.PAPER)
	caption.text = "Theme grammar gallery — every component, every state, both orientations (720x720 base)."
	_column.add_child(caption)


func _section_header_label(text: String) -> void:
	var head := Label.new()
	head.theme_type_variation = &"CardTitle"
	# On the ground, headers print bright (the print rule); the CardTitle
	# variation's INK default belongs to name plates on paper cards.
	head.add_theme_color_override("font_color", Inks.ground_text_ink(Inks.ground_for(&"", Inks.Phase.RECRUITING)))
	head.text = text
	_column.add_child(head)


func _caption(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"PipLabel"
	# Captions sit ON THE GROUND, not on paper: the print rule picks the
	# bright ink for dark stocks (Inks.ground_text_ink) — the PipLabel
	# variation's default ink is the on-paper channel and would sink.
	label.add_theme_color_override("font_color", Inks.ground_text_ink(Inks.ground_for(&"", Inks.Phase.RECRUITING)))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	_column.add_child(label)


func _section_grounds() -> void:
	_section_header_label("Phase-Deepening Ground")
	_caption("The table deepens through the run before any number is read — neutral ground shown; regimes tint it (below).")
	var names := {
		Inks.Phase.RECRUITING: "Recruiting", Inks.Phase.TRAINING: "Training",
		Inks.Phase.READY: "Ready to storm", Inks.Phase.AFTERMATH: "Aftermath",
	}
	for phase: int in [Inks.Phase.RECRUITING, Inks.Phase.TRAINING, Inks.Phase.READY, Inks.Phase.AFTERMATH]:
		var strip := GROUND_SCENE.instantiate() as Control
		strip.custom_minimum_size = Vector2(0, 64)
		strip.set("phase", phase)
		var tone := Inks.ground_for(&"", phase)
		var label := Label.new()
		label.theme_type_variation = &"ChronicleLine"
		label.add_theme_color_override("font_color", Inks.ground_text_ink(tone))
		label.text = "%s  —  %s" % [names[phase], tone.to_html(false)]
		label.position = Vector2(12, 18)
		strip.add_child(label)
		_column.add_child(strip)


func _section_regimes() -> void:
	_section_header_label("Regime Inks (data-driven)")
	_caption("One ground + one secondary per flavor, read from content/mvp/regimes — a regime swap recolors the table by data.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_column.add_child(row)
	for id: StringName in Inks.regime_ids():
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 6)
		var frame := FRAME_SCENE.instantiate() as Control
		frame.custom_minimum_size = Vector2(120, 160)
		frame.set("regime_id", id)
		frame.set("misprint_seed", 100 + Inks.regime_ids().find(id))
		var plate := PanelContainer.new()
		plate.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.offset_left = 20.0
		plate.offset_top = 22.0
		plate.offset_right = -20.0
		plate.offset_bottom = -20.0
		var swatch := ColorRect.new()
		swatch.color = Inks.regime_secondary(id)
		plate.add_child(swatch)
		frame.add_child(plate)
		holder.add_child(frame)
		var label := Label.new()
		label.theme_type_variation = &"PipLabel"
		label.custom_minimum_size = Vector2(120, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = Inks.regime_name(id)
		holder.add_child(label)
		row.add_child(holder)


func _section_edge_states() -> void:
	_section_header_label("Line-Form States (form, never hue)")
	_caption("Card edges carry state by line form — solid ready / dashed in progress / struck lost. Colorblind-safe by construction.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_column.add_child(row)
	var states := [
		[Inks.EdgeForm.SOLID, "Ready", &"peasant"],
		[Inks.EdgeForm.DASHED, "In progress", &"trainee"],
		[Inks.EdgeForm.STRUCK, "Lost", &"worker"],
	]
	for i in states.size():
		var entry: Array = states[i]
		row.add_child(_sample_card(168, 252, entry[0], entry[2], "Conspirator %d" % (i + 1), entry[1], 900 + i))


func _section_chronicle() -> void:
	_section_header_label("Chronicle — States Print Themselves")
	_caption("Events write themselves onto the table as chronicle lines, never popup chrome. Rule form carries the class; ink follows the stock.")
	var panel := GROUND_SCENE.instantiate() as Control
	panel.custom_minimum_size = Vector2(0, 236)
	panel.set("phase", Inks.Phase.TRAINING)
	_column.add_child(panel)
	var lines := VBoxContainer.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.offset_top = 8.0
	lines.offset_bottom = -8.0
	lines.add_theme_constant_override("separation", 4)
	panel.add_child(lines)
	var samples := [
		[Inks.LineClass.PLAIN, "The gate offers a recruit with believable hands."],
		[Inks.LineClass.WARN, "A neighbor asks polite questions about the smithy."],
		[Inks.LineClass.STRIKE, "The Watch seized 40 percent of the timber."],
		[Inks.LineClass.VICTORY, "The castle gate stands open. The Crown does not."],
	]
	for entry: Array in samples:
		var line := CHRONICLE_SCENE.instantiate() as Control
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.set("ground", Inks.ground_for(&"", Inks.Phase.TRAINING))
		line.set("line_class", entry[0])
		line.set("text", entry[1])
		lines.add_child(line)


func _section_cards() -> void:
	_section_header_label("Card Types x Orientations")
	_caption("Portrait 5:7 and landscape 7:5 from one CardFace (aspect reflow); knight/archer faces print the authored placeholder until the art manifest lands them.")
	var portrait := HBoxContainer.new()
	portrait.add_theme_constant_override("separation", 14)
	_column.add_child(portrait)
	portrait.add_child(_sample_card(168, 252, Inks.EdgeForm.SOLID, &"peasant", "Brann", "Peasant — at the gate", 21))
	portrait.add_child(_sample_card(168, 252, Inks.EdgeForm.DASHED, &"trainee", "Wilmot", "Trainee — drilling", 22))
	var knight := _sample_card(168, 252, Inks.EdgeForm.SOLID, &"", "Ser Adela", "Knight — awaiting face art", 23)
	knight.set("regime_id", &"velvet_fist")
	portrait.add_child(knight)
	var eye := _sample_card(168, 252, Inks.EdgeForm.SOLID, &"", "The Watchful Eye", "Suspicion — creeping in", 24)
	portrait.add_child(eye)
	var landscape := HBoxContainer.new()
	landscape.add_theme_constant_override("separation", 14)
	_column.add_child(landscape)
	landscape.add_child(_sample_card(252, 168, Inks.EdgeForm.SOLID, &"worker", "Marga", "Worker — farm detail", 31))
	var regime_card := _sample_card(252, 168, Inks.EdgeForm.SOLID, &"", "The Gilded Crown", "Regime — crest pending", 32)
	regime_card.set("regime_id", &"gilded_crown")
	landscape.add_child(regime_card)
	landscape.add_child(_sample_card(252, 168, Inks.EdgeForm.DASHED, &"", "A Choice of Loyalties", "Event — suspicion choice", 33))


func _section_pips() -> void:
	_section_header_label("Resource Pips (shape + glyph + label)")
	_caption("Colorblind-safe by construction: container shape, inner glyph, and label text all differ per resource; color is redundant only.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_column.add_child(row)
	var samples: Array = [
		[Inks.ResourceKind.FOOD, 999], [Inks.ResourceKind.TIMBER, 15400],
		[Inks.ResourceKind.IRON, 2300000],
	]
	for i in samples.size():
		var entry: Array = samples[i]
		var pip := PIP_SCENE.instantiate() as HBoxContainer
		pip.set("kind", entry[0])
		pip.set("amount", entry[1])
		pip.set("glyph_ink", Inks.RED if i == 0 else Inks.INK)
		row.add_child(pip)
	var tight := PIP_SCENE.instantiate() as HBoxContainer
	tight.set("kind", Inks.ResourceKind.FOOD)
	tight.set("amount", 4800)
	tight.set("show_label", false)
	row.add_child(tight)


func _section_typography() -> void:
	_section_header_label("Typography")
	_caption("Display: IM Fell English SC (OFL) — the misprint lives in the letterforms. Workhorse: Alegreya Sans (OFL). Sizes ride the theme, so UI scale is one knob.")
	var specimens := [
		[&"Heading", "Heading — The Revolution Will Be Typeset"],
		[&"CardTitle", "CardTitle — Conspirator of the Third Hour"],
		[&"RoleLine", "RoleLine — Worker, assigned to the farm"],
		[&"Numerals", "Numerals — 0 1 2 3 4 5 6 7 8 9  999  1.2K  15K  2.3M"],
		[&"PipLabel", "PipLabel — FOOD  TIMBER  IRON"],
	]
	for entry: Array in specimens:
		var label := Label.new()
		label.theme_type_variation = entry[0]
		label.text = entry[1]
		_column.add_child(label)
	var chron := CHRONICLE_SCENE.instantiate() as Control
	chron.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chron.set("ground", Inks.ground_for(&"", Inks.Phase.TRAINING))
	chron.set("text", "ChronicleLine — the italic workhorse, printed on the training ground.")
	_column.add_child(chron)


func _section_focus() -> void:
	_section_header_label("Focus (controller / keyboard)")
	_caption("Focus re-prints the border offset in revolution red — a second ink pass that missed registration. Tab or D-pad through the cards and chip below.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_column.add_child(row)
	for i in 3:
		var frame := _sample_card(120, 168, Inks.EdgeForm.SOLID, &"peasant", "Focus %d" % (i + 1), "grip >= 48", 40 + i)
		row.add_child(frame)
	var chip := Button.new()
	chip.text = "A Printed Chip"
	chip.focus_mode = Control.FOCUS_ALL
	row.add_child(chip)


# --- helpers --------------------------------------------------------------------


func _sample_card(w: float, h: float, form: int, face: StringName, card_name: String, role: String, seed: int) -> Control:
	## A composed specimen: CardFrame + inset CardFace. Frame focusable
	## (controller nav parity); misprint seeded for stable review.
	var frame := FRAME_SCENE.instantiate() as Control
	frame.custom_minimum_size = Vector2(w, h)
	frame.set("edge_form", form)
	frame.set("misprint_seed", seed)
	frame.focus_mode = Control.FOCUS_ALL
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16.0
	margin.offset_top = 18.0
	margin.offset_right = -16.0
	margin.offset_bottom = -16.0
	var face_plate := FACE_SCENE.instantiate() as BoxContainer
	face_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face_plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	face_plate.set("card_name", card_name)
	face_plate.set("role_line", role)
	if FACE_TEXTURES.has(face):
		face_plate.set("face_texture", load(FACE_TEXTURES[face]))
	margin.add_child(face_plate)
	frame.add_child(margin)
	return frame
