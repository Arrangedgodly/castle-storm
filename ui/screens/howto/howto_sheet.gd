## HowToSheet — the pamphlet ON THE TABLE: a paper quad (the choice
## card's cut stock), the letterpress title, and one SCROLLED column —
## THE GOAL first (under the signature's double red rule), THE TABLE,
## THE EDGES (the line-form legend with three LIVE mini card-frames:
## solid ready / dashed work in hand / struck lost), THE STORES, THE
## WATCHFUL EYE, THE LONG GAME — then the back verb at the foot.
##
## All T-UI-01 grammar, nothing forked. The scroll's content is laid by
## MEASURED text (the letterhead's rule): every body label's height is
## its own shaped wrapped print at the settled content width — the
## honest heights the readability audit grades — recomputed on every
## bind and every resize (the type factor re-flows the page).
class_name HowToSheet
extends Control

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## Paper margins (design units; the papers' own).
const MARGIN := 14.0
const PAD := 14.0
## The pamphlet's readable width cap (the ledger rule).
const SHEET_MAX_WIDTH := 620.0
const TITLE_H := 54.0
const CHIP_H := 48.0
const SECTION_GAP := 16.0
const LEGEND_FRAME := 96.0
const LEGEND_GAP := 10.0

## The back verb.
signal back_pressed()

var _title_label: Label
var _scroll: ScrollContainer
var _content: Control
var _back_chip: ActionFan.ActionChip
var _sheet_rect := Rect2()
var _content_width := 0.0

## Section structure, composed once, text-bound per bind (each entry:
## {heading, bodies: [Label], rule}). The reading ORDER is flat and
## explicit — the edge legend's live frames sit under THE EDGES, in the
## sequence a reader meets them.
var _sections: Array[Dictionary] = []
var _headings: Array[Label] = []
var _legend_rows: Array[Dictionary] = []
var _order: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compose()
	_relaid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relaid()


func _draw() -> void:
	## The paper quad + its ink border (cut paper, never rounded luxe).
	if _sheet_rect.size.x < 4.0:
		return
	var rect := _sheet_rect.grow(-2.0)
	draw_rect(rect, Inks.PAPER)
	draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
	# The cut corners: a 9-unit chamfer ACROSS each corner of the paper
	# itself (the day-sheet's cut grammar, scoped to the sub-rect — the
	# cut runs corner-to-adjacent-edge, never across the sheet).
	var c := 9.0
	draw_line(Vector2(rect.position.x, rect.position.y + c), Vector2(rect.position.x + c, rect.position.y), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.end.x - c, rect.position.y), Vector2(rect.end.x, rect.position.y + c), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x + c, rect.end.y), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 5.0, true)


# --- composition ---------------------------------------------------------------------------


func _compose() -> void:
	_title_label = Label.new()
	_title_label.theme_type_variation = &"CardTitle"
	_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)

	_sections.clear()
	_headings.clear()
	_legend_rows.clear()
	_order.clear()
	_order.append({"kind": &"section", "index": _section("THE GOAL", 1, true)})
	_order.append({"kind": &"section", "index": _section("THE TABLE", 2, false)})
	_order.append({"kind": &"section", "index": _section("THE EDGES", 0, false)})
	_add_legend_rows()
	_order.append({"kind": &"legend"})
	_order.append({"kind": &"section", "index": _section("THE STORES", 1, false)})
	_order.append({"kind": &"section", "index": _section("THE WATCHFUL EYE", 1, false)})
	_order.append({"kind": &"section", "index": _section("THE LONG GAME", 2, false)})

	_back_chip = ActionFan.ActionChip.new()
	_back_chip.action = {
		"id": &"back", "label": "Back to the table", "command": &"",
		"subject": &"", "value": 0, "enabled": true, "reason": "",
		"signature": true,
	}
	_back_chip.custom_minimum_size = Vector2(196.0, CHIP_H)
	_back_chip.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back_chip)
	_wire_pad_column()


## Compose one section; returns its index in _sections.
func _section(heading_text: String, body_count: int, p_signature: bool) -> int:
	var heading := Label.new()
	heading.theme_type_variation = &"RoleLine"
	heading.text = heading_text
	heading.add_theme_color_override("font_color", Inks.INK)
	heading.focus_mode = Control.FOCUS_ALL
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.focus_entered.connect(_ensure_visible.bind(heading))
	_content.add_child(heading)
	_headings.append(heading)
	var bodies: Array[Label] = []
	for i in body_count:
		var body := Label.new()
		body.theme_type_variation = &"ChronicleLine"
		body.add_theme_color_override("font_color", Inks.INK)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(body)
		bodies.append(body)
	var rule: Control = null
	if p_signature:
		# THE GOAL carries the signature mark: the DOUBLE red rule (the
		# victory flourish's own grammar — the one fact underlined twice).
		rule = RULE_SCENE.instantiate()
		rule.set("form", 3)  # RuleMark.RuleForm.DOUBLE
		rule.set("rule_ink", Inks.RED)
		rule.focus_mode = Control.FOCUS_NONE
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(rule)
	_sections.append({"heading": heading, "bodies": bodies, "rule": rule})
	return _sections.size() - 1


func _add_legend_rows() -> void:
	# THE LIVE EXAMPLES: real card frames in the three edge states —
	# the primer for line-form states, taught with pictures. Clean
	# prints (misprint seed 0 — chrome cards), seals on (the deck's
	# stamp), the lesson entirely in the edge's line form.
	for form in [Inks.EdgeForm.SOLID, Inks.EdgeForm.DASHED, Inks.EdgeForm.STRUCK]:
		var frame := FRAME_SCENE.instantiate() as Control
		frame.set("edge_form", form)
		frame.set("misprint_seed", 0)
		frame.set("show_seal", true)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(frame)
		var caption := Label.new()
		caption.theme_type_variation = &"ChronicleLine"
		caption.add_theme_color_override("font_color", Inks.INK)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(caption)
		_legend_rows.append({"form": form, "frame": frame, "caption": caption})


## Bind the view: same view => same render (snapshot_hash pins it). The
## title's baked size re-applies on every bind — the live type-scale
## change re-flows the page the next time it opens (the papers' rule).
func bind(view: Dictionary) -> void:
	_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
	_title_label.text = String(view["title"])
	_title_label.add_theme_color_override("font_color", Inks.INK)
	var goal_section: Dictionary = _sections[0]
	(goal_section["bodies"] as Array)[0].text = String(view["goal_line"])
	var table_section: Dictionary = _sections[1]
	var table_bodies: Array = table_section["bodies"]
	var table_lines: Array = view["table_lines"]
	for i in table_bodies.size():
		(table_bodies[i] as Label).text = String(table_lines[i])
	for i in _legend_rows.size():
		var row: Dictionary = _legend_rows[i]
		var caption: Label = row["caption"]
		caption.text = String((view["edge_rows"] as Array)[i]["caption"])
	var stores_section: Dictionary = _sections[3]
	(stores_section["bodies"] as Array)[0].text = String(view["stores_line"])
	var eye_section: Dictionary = _sections[4]
	(eye_section["bodies"] as Array)[0].text = String(view["eye_line"])
	var long_section: Dictionary = _sections[5]
	var long_bodies: Array = long_section["bodies"]
	var long_lines: Array = view["long_lines"]
	for i in long_bodies.size():
		(long_bodies[i] as Label).text = String(long_lines[i])
	_relaid()
	# The settle: re-measure once the frame's sizes are real (a bind that
	# lands mid-resize never leaves a transient stack behind).
	_relaid.call_deferred()


# --- focus ---------------------------------------------------------------------------------


## THE PAD COLUMN: the section headings then the back verb as one cyclic
## vertical chain (the fan's own rule, vertical form) — the walk IS the
## scroll (a focused heading is always scrolled into view).
func _wire_pad_column() -> void:
	var column: Array[Control] = []
	column.append_array(_headings)
	column.append(_back_chip)
	var count := column.size()
	if count == 0:
		return
	for i in count:
		var node := column[i]
		var prev: Control = column[wrapi(i - 1, 0, count)]
		var next: Control = column[wrapi(i + 1, 0, count)]
		node.focus_neighbor_top = node.get_path_to(prev)
		node.focus_neighbor_bottom = node.get_path_to(next)


func _ensure_visible(row: Control) -> void:
	if _scroll == null or row == null or not is_instance_valid(row):
		return
	_scroll.ensure_control_visible.call_deferred(row)


## The open settle: the page opens at the TOP with the seeded focus
## ON-SCREEN (the chronicle's round-1 lesson, the day-sheet's shape).
func seed_focus() -> void:
	_settle_seed.call_deferred()


func _settle_seed() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_scroll.scroll_vertical = 0
	if not _headings.is_empty() and is_instance_valid(_headings[0]) \
			and _headings[0].is_visible_in_tree():
		_headings[0].grab_focus()


func back_chip() -> ActionFan.ActionChip:
	return _back_chip


func headings() -> Array[Label]:
	return _headings.duplicate()


func legend_rows() -> Array[Dictionary]:
	return _legend_rows.duplicate()


func scroll() -> ScrollContainer:
	return _scroll


# --- layout (measured text, the letterhead's rule) ------------------------------------------


func _relaid() -> void:
	if _title_label == null or size.x < 8.0 or size.y < 8.0:
		return
	var rects := sheet_rects(size)
	_sheet_rect = rects["sheet"]
	var inner := Rect2(_sheet_rect.position + Vector2(PAD, PAD),
		_sheet_rect.size - Vector2(2.0 * PAD, 2.0 * PAD))
	_title_label.position = inner.position
	_title_label.size = Vector2(inner.size.x, TITLE_H * TypeScale.factor())
	var chip_h := CHIP_H * TypeScale.factor()
	var band := Rect2(Vector2(inner.position.x, inner.position.y + TITLE_H * TypeScale.factor() + 6.0),
		Vector2(inner.size.x, inner.size.y - TITLE_H * TypeScale.factor() - 6.0 - chip_h - 6.0))
	_scroll.position = band.position
	_scroll.size = band.size
	_back_chip.position = Vector2(inner.position.x, inner.end.y - chip_h)
	_back_chip.size = Vector2(196.0 * TypeScale.factor(), chip_h)
	_layout_content(band.size.x)
	queue_redraw()


## The scroll's content: stack the sections by MEASURED heights at the
## settled content width (a body label holds its shaped wrapped print —
## never a crush, never a clip). Same view + same width => same stack.
func _layout_content(band_width: float) -> void:
	if band_width <= 8.0:
		return
	var f := TypeScale.factor()
	var width := band_width
	_content_width = width
	var y := 4.0 * f
	for item: Dictionary in _order:
		match StringName(String(item["kind"])):
			&"section":
				var section: Dictionary = _sections[int(item["index"])]
				var heading: Label = section["heading"]
				heading.position = Vector2(0.0, y)
				heading.size = Vector2(width, 26.0 * f)
				heading.custom_minimum_size = heading.size
				y += 26.0 * f + 6.0 * f
				for body: Label in section["bodies"]:
					y = _place_body(body, Vector2(0.0, y), Vector2(width, 0.0))
				var rule: Control = section["rule"]
				if rule != null:
					rule.position = Vector2(0.0, y)
					rule.size = Vector2(width * 0.6, 12.0 * f)
					y += 12.0 * f + SECTION_GAP * f
				y += SECTION_GAP * f
			&"legend":
				# The LIVE EXAMPLES: the frames with their captions beside.
				for row: Dictionary in _legend_rows:
					var frame: Control = row["frame"]
					frame.position = Vector2(0.0, y)
					frame.size = Vector2(LEGEND_FRAME, LEGEND_FRAME)
					var caption: Label = row["caption"]
					var caption_x := LEGEND_FRAME + LEGEND_GAP
					var shaped := _shaped_height(caption, width - caption_x)
					caption.position = Vector2(caption_x, y + (LEGEND_FRAME - shaped) * 0.5)
					caption.size = Vector2(width - caption_x, maxf(shaped, 30.0 * f))
					caption.custom_minimum_size = caption.size
					y += LEGEND_FRAME + SECTION_GAP * f
	_content.size = Vector2(width, y)
	_content.custom_minimum_size = _content.size


## One wrapped body at (pos, width): the plate holds its shaped print.
## Returns the advanced y.
func _place_body(body: Label, pos: Vector2, size_hint: Vector2) -> float:
	var shaped := _shaped_height(body, size_hint.x)
	body.position = pos
	body.size = Vector2(size_hint.x, shaped)
	body.custom_minimum_size = body.size
	return pos.y + shaped + 6.0 * TypeScale.factor()


## The honest wrapped height of a label's text at the given width, in
## the label's own theme face and size (the card_face fit's measure).
func _shaped_height(label: Label, width: float) -> float:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return 30.0
	var shaped := font.get_multiline_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
	return maxf(shaped.y, 30.0)


## The pamphlet's layout rect: the capped column, centered in the
## bounds (the day-sheet's shape, narrower band). Pure statics.
static func sheet_rects(bounds: Vector2) -> Dictionary:
	var wide := minf(bounds.x - 2.0 * MARGIN, SHEET_MAX_WIDTH * TypeScale.factor())
	var sheet := Rect2(Vector2((bounds.x - wide) * 0.5, MARGIN),
		Vector2(wide, bounds.y - 2.0 * MARGIN))
	return {"sheet": sheet}


# --- render oracle --------------------------------------------------------------------------


func snapshot_hash() -> int:
	var h := 0x811C9DC5
	h = _mix(h, _title_label.text.hash())
	for heading in _headings:
		h = _mix(h, heading.text.hash())
	for section: Dictionary in _sections:
		for body: Label in section["bodies"]:
			h = _mix(h, body.text.hash())
	for row: Dictionary in _legend_rows:
		h = _mix(h, int(row["form"]))
		h = _mix(h, (row["caption"] as Label).text.hash())
	h = _mix(h, String(_back_chip.action.get("label", "")).hash())
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
