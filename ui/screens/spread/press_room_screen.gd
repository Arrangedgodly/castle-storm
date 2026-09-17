## PressRoomScreen — the game's settings card (finishing refinement #5).
##
## THE PRESS-ROOM (in-world: where the press's own adjustments are made).
## The closing critique's P3: the engine's accessibility seams existed —
## the type scale (TypeScale, 1.0–1.3, the audited range) and reduced
## motion (MotionProfile) — but no surface exposed them, so a player who
## needed either had to edit project.godot. This card is that surface,
## built as the chronicle/day-sheet's sibling paper, not as settings
## chrome:
##
##   - PAPER over a veiled table (the composition rule every full-rect
##     sheet keeps — never modal chrome, never popup);
##   - the KEPT rule prints SOLID in ink (settled fact — the preferences
##     are persisted), where the day-sheet's count rule prints dashed
##     (its page is work in progress): the same line-form vocabulary;
##   - THE HAND — the letter size, as four numeral steps (1.0× … 1.3×);
##   - THE PRESSWORK — the motion, as two steps (Full turn / Steady
##     hand = reduced motion);
##   - the step IN FORCE carries the DOUBLE red rule — the ActionChip's
##     own signature mark — so state reads by line form, never hue alone
##     (the same grammar as the armed plate and the victory chip).
##
## LIVE + PERSISTED: a step press emits `preference_changed`; the SPREAD
## owns the applying (TypeScale.apply_factor + the whole-view rebind, or
## MotionProfile.forced — motion is live by construction, every motion
## owner asks the profile at motion time), writes the preference into
## the META domain (RunMeta.preferences, additive-optional), and saves
## the meta file at once — the choice survives restarts and crashes by
## construction, and the boot seam re-applies it before any chrome bakes
## sizes. Pressing the step already in force is a quiet no-op (no meta
## churn). NO show-fps/debug here: that is dev chrome and stays gated on
## CS_DEBUG_CHROME.
##
## RULES WITH THE OTHER PAPER (documented): the press-room is mutually
## exclusive with the chronicle ledger and the day-sheet (whichever
## opens folds the others — one paper at a time owns the table), and
## STORY PAPER outranks it exactly as it outranks the other papers: a
## suspicion choice card, the crush beat, the reveal, or the assault
## vignette folds it (the story never waits on the press-room); the
## player returns to it from the header chip.
##
## INPUT PARITY (Daredevil): touch (step presses, chip presses),
## keyboard (arrows walk the steps — left/right inside a row, up/down
## across rows; Enter activates; Esc closes), pad (d-pad walks, A
## activates, B closes). Back is accepted from anywhere on the card.
## Reached from the spread header's verbs row (The Press-Room chip),
## one per slot, focus-equivalent across orientation swaps.
class_name PressRoomScreen
extends Control

## The card folded away (the spread owns the table again).
signal closed()

## A step was pressed and is NOT the one already in force. The spread
## owns what the verb does: apply the preference live, persist it into
## the meta domain, save. `kind` is &"type_scale" (value: float factor)
## or &"motion" (value: bool, true = reduced).
signal preference_changed(kind: StringName, value: Variant)

## The veil's opacity over the table beneath (every full-rect paper's
## candle-lit rule).
const VEIL_ALPHA := 0.90

## The card's letterpress (code-side, like the chronicle's own title).
const TITLE := "THE PRESS-ROOM"

## The type-scale steps: the audited 1.0–1.3 range (docs/
## acceptance-sweep.md §9), one meaningful jump each — a 0.05 step is
## invisible; a 0.1 step is a real decision. Motion is two steps.
const TYPE_STEPS: Array[float] = [1.0, 1.1, 1.2, 1.3]

enum State { CLOSED, OPEN }

var host: GameHost
var state: int = State.CLOSED

## Instrumentation (tests assert the open/close + step contract).
var stats := {
	&"opens": 0,
	&"step_presses": 0,
	&"quiet_presses": 0,
}

var _veil: ColorRect
var _sheet: PressRoomSheet
var _view := {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_sheet = PressRoomSheet.new()
	_sheet.name = "PressRoomSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	_sheet.step_pressed.connect(_on_step)
	_sheet.back_pressed.connect(close)


# --- open / close -----------------------------------------------------------------------


## Open the press-room card. `p_router` is the spread's router
## (orientation seam — the sheet relays on window resizes through
## NOTIFICATION_RESIZED of this full-rect control, the papers' pattern).
func open(p_host: GameHost, p_router: LayoutRouter) -> void:
	host = p_host
	state = State.OPEN
	visible = true
	stats[&"opens"] += 1
	# The veil carries the live regime's ground tone (candle-lit paper
	# over the table — the composition rule every full-rect paper keeps).
	var regime_id := p_host.run().regime_id() if p_host.is_run_running() else &""
	_veil.color = Color(Inks.ground_for(regime_id, Inks.Phase.RECRUITING), VEIL_ALPHA)
	_view = view_for(p_host)
	_sheet.bind(_view)
	_seed_focus()


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	visible = false
	closed.emit()


func is_open() -> bool:
	return state != State.CLOSED


## The bound view model (tests read the mapped data).
func view() -> Dictionary:
	return _view


## The composed sheet (tests + the capture hook).
func sheet() -> PressRoomSheet:
	return _sheet


## A step press landed. The quiet no-op first (the step already in
## force: no signal, no meta churn), then the verb goes to the spread
## through `preference_changed` — SYNCHRONOUS, so by the time the mark
## below runs, TypeScale.factor()/MotionProfile.reduced() already tell
## the new truth (the spread applied it); the mark only re-inks the
## steps' rules, never rebuilding the row (focus stays on the pressed
## step — the walk is not interrupted by the card's own verb).
func _on_step(kind: StringName, value: Variant) -> void:
	stats[&"step_presses"] += 1
	if kind == &"type_scale":
		if is_equal_approx(TypeScale.factor(), float(value)):
			stats[&"quiet_presses"] += 1
			return
		preference_changed.emit(&"type_scale", float(value))
	elif kind == &"motion":
		if MotionProfile.reduced() == bool(value):
			stats[&"quiet_presses"] += 1
			return
		preference_changed.emit(&"motion", bool(value))
	_view = view_for(host)
	_sheet.mark_engaged(float(_view["type_scale"]), bool(_view["reduced_motion"]))


## Focus seeds the walk: the step IN FORCE on the hand row (the walk
## starts at the truth, and the engaged step is visible by its rule).
## A screen must seed itself, the router's rule; the seed waits one
## settled frame (the card is fixed-height — no scroll to settle).
func _seed_focus() -> void:
	var seed: Control = _sheet.engaged_type_step()
	if seed == null:
		seed = _sheet.first_focusable()
	if seed == null:
		return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(seed) or not seed.is_visible_in_tree():
		return
	seed.grab_focus()


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return
	if event.is_action_pressed(&"back"):
		close()
		get_viewport().set_input_as_handled()
		return
	# PAD PARITY: a non-positional primary the engine did not route to the
	# focused step as ui_accept activates it here (the papers' shared
	# fallback — acting on the card is reachable identically from touch,
	# keyboard, and pad, exactly once each).
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		if activate_focused():
			get_viewport().set_input_as_handled()


## Activate the step/chip that holds focus, if any (the pad fallback).
## Returns true when something was activated.
func activate_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and _sheet != null and _sheet.is_ancestor_of(focus):
		(focus as BaseButton).pressed.emit()
		return true
	return false


# --- the pure view ------------------------------------------------------------------------


## The whole card as data. Pure: reads only the seams' live truth (the
## type factor, the motion profile) + the copy deck — the host itself is
## deliberately unread (the seams ARE the truth; the meta's copy is the
## spread's business), the signature keeps the papers' view_for shape.
## Same seams => same view. The engaged type step derives from the LIVE
## factor (the boot seam already applied the persisted preference), so a
## player who set 1.2 last session opens on 1.2.
static func view_for(_p_host: GameHost) -> Dictionary:
	var copy := Inks.pack().copy
	return {
		"title": TITLE,
		"type_scale": TypeScale.factor(),
		"reduced_motion": MotionProfile.reduced(),
		"steps": TYPE_STEPS.duplicate(),
		"kept_line": CopyDeck.line(copy, &"prefs_kept", 0),
		"type_label": "THE HAND",
		"type_note": CopyDeck.line(copy, &"prefs_type_note", 0),
		"motion_label": "THE PRESSWORK",
		"motion_note": CopyDeck.line(copy, &"prefs_motion_note", 0),
		"motion_full_label": CopyDeck.line(copy, &"prefs_motion_full", 0),
		"motion_steady_label": CopyDeck.line(copy, &"prefs_motion_steady", 0),
	}


# --- the sheet (the paper itself) ------------------------------------------------------------


## PressRoomSheet — the card ON THE TABLE: a paper quad (the choice
## card's cut stock), the letterpress title, the SOLID kept rule, the
## two preference rows (header, note, steps), and the back verb. All
## T-UI-01 grammar, nothing forked; every step is a full grip.
class PressRoomSheet:
	extends Control

	const BACK_ACTION := {
		"id": &"back", "label": "Back to the table", "command": &"",
		"subject": &"", "value": 0, "enabled": true, "reason": "",
		"signature": false,
	}

	## Paper margins (design units; the papers' own).
	const MARGIN := 14.0
	const PAD := 12.0
	## The card is a CARD, not a page: narrower than the day-sheet's
	## column cap (a preferences card sits on the table like the choice
	## card does).
	const SHEET_MAX_WIDTH := 560.0
	const TITLE_H := 54.0
	const KEPT_H := 26.0
	const LABEL_H := 30.0
	const NOTE_H := 24.0
	const CHIP_H := 48.0
	const TYPE_STEP_W := 92.0
	const MOTION_STEP_W := 150.0
	const ROW_SEP := 18.0

	## A step was activated (kind: &"type_scale" / &"motion"; value: the
	## factor / the bool). The screen owns what the verb does.
	signal step_pressed(kind: StringName, value: Variant)
	## The back verb.
	signal back_pressed()

	var _title_label: Label
	var _kept_row: HBoxContainer
	var _kept_rule: Control
	var _kept_label: Label
	var _type_label: Label
	var _type_note: Label
	var _type_row: HBoxContainer
	var _motion_label: Label
	var _motion_note: Label
	var _motion_row: HBoxContainer
	var _back_chip: Control
	var _type_steps: Array[StepChip] = []
	var _motion_steps: Array[StepChip] = []
	var _sheet_rect := Rect2()


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compose()
		_relaid()


	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_relaid()


	func _draw() -> void:
		## The paper quad + its ink border (the choice card's stock: cheap
		## print, chamfered by hand — cut paper, never rounded luxe).
		if _sheet_rect.size.x < 4.0:
			return
		var rect := _sheet_rect.grow(-2.0)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
		var c := 9.0
		draw_line(Vector2(c, rect.position.y), Vector2(rect.position.x, rect.position.y + c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.position.y), Vector2(rect.end.x, rect.position.y + c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(c, rect.end.y), Vector2(rect.position.x, rect.end.y - c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 5.0, true)

	# --- composition ---------------------------------------------------------------------


	func _compose() -> void:
		_title_label = Label.new()
		_title_label.theme_type_variation = &"CardTitle"
		_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_title_label)

		_kept_row = HBoxContainer.new()
		_kept_row.add_theme_constant_override("separation", 10)
		_kept_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kept_rule = preload("res://ui/theme/rule_mark.tscn").instantiate()
		_kept_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_kept_rule.focus_mode = Control.FOCUS_NONE
		# SETTLED, not in progress: SOLID ink — the press-room's facts are
		# kept (persisted), where the day-sheet's count rule prints DASHED
		# red because its page is work in hand. Line form carries it.
		_kept_rule.set("form", 0)  # RuleMark.RuleForm.SOLID
		_kept_rule.set("rule_ink", Inks.INK)
		_kept_row.add_child(_kept_rule)
		_kept_label = Label.new()
		_kept_label.theme_type_variation = &"PipLabel"
		_kept_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_kept_label.clip_text = true
		_kept_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kept_row.add_child(_kept_label)
		add_child(_kept_row)

		_type_label = _row_header()
		add_child(_type_label)
		_type_note = _row_note()
		add_child(_type_note)
		_type_row = HBoxContainer.new()
		_type_row.add_theme_constant_override("separation", 10)
		_type_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_type_row)

		_motion_label = _row_header()
		add_child(_motion_label)
		_motion_note = _row_note()
		add_child(_motion_note)
		_motion_row = HBoxContainer.new()
		_motion_row.add_theme_constant_override("separation", 10)
		_motion_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_motion_row)

		var back := ActionFan.ActionChip.new()
		back.action = BACK_ACTION
		back.custom_minimum_size = Vector2(196.0, CHIP_H)
		back.pressed.connect(func() -> void: back_pressed.emit())
		add_child(back)
		_back_chip = back


	func _row_header() -> Label:
		var label := Label.new()
		label.theme_type_variation = &"RoleLine"
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return label


	func _row_note() -> Label:
		var label := Label.new()
		label.theme_type_variation = &"PipLabel"
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return label


	## Bind the view: same view => same card.
	func bind(view: Dictionary) -> void:
		_title_label.text = String(view["title"])
		_title_label.add_theme_color_override("font_color", Inks.INK)
		_kept_label.text = String(view["kept_line"])
		_kept_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		_type_label.text = String(view["type_label"])
		_type_label.add_theme_color_override("font_color", Inks.INK)
		_type_note.text = String(view["type_note"])
		_type_note.add_theme_color_override("font_color", Inks.INK_SOFT)
		_motion_label.text = String(view["motion_label"])
		_motion_label.add_theme_color_override("font_color", Inks.INK)
		_motion_note.text = String(view["motion_note"])
		_motion_note.add_theme_color_override("font_color", Inks.INK_SOFT)
		_build_steps(view)
		mark_engaged(float(view["type_scale"]), bool(view["reduced_motion"]))
		_wire_focus_chains()
		_relaid()


	## (Re)build the step chips. Called from bind — a fresh bind (a new
	## open, or a scale change that re-composes the card) rebuilds them
	## so the chips' OWN baked sizes (the numeral plates read
	## TypeScale.scaled) always follow the live factor.
	func _build_steps(view: Dictionary) -> void:
		for chip in _type_steps:
			_type_row.remove_child(chip)
			chip.queue_free()
		_type_steps.clear()
		for chip in _motion_steps:
			_motion_row.remove_child(chip)
			chip.queue_free()
		_motion_steps.clear()
		var steps: Array = view["steps"]
		for i in steps.size():
			var factor := float(steps[i])
			var chip := StepChip.new(_type_step_text(factor), true, factor)
			chip.custom_minimum_size = Vector2(TYPE_STEP_W, CHIP_H)
			chip.pressed.connect(_on_step.bind(&"type_scale", factor))
			_type_row.add_child(chip)
			_type_steps.append(chip)
		var full := StepChip.new(String(view["motion_full_label"]), false, false)
		full.custom_minimum_size = Vector2(MOTION_STEP_W, CHIP_H)
		full.pressed.connect(_on_step.bind(&"motion", false))
		_motion_row.add_child(full)
		_motion_steps.append(full)
		var steady := StepChip.new(String(view["motion_steady_label"]), false, true)
		steady.custom_minimum_size = Vector2(MOTION_STEP_W, CHIP_H)
		steady.pressed.connect(_on_step.bind(&"motion", true))
		_motion_row.add_child(steady)
		_motion_steps.append(steady)


	static func _type_step_text(factor: float) -> String:
		## The numeral-plate form: "1.1x" — the multiplication sign of the
		## press's own arithmetic ("x600 — running" prints the same).
		return "%.1fx" % factor


	## Re-ink the engaged rules WITHOUT rebuilding (the live mark after a
	## step press: focus stays on the pressed step, the rules move).
	func mark_engaged(type_scale: float, reduced_motion: bool) -> void:
		for chip in _type_steps:
			chip.engaged = is_equal_approx(float(chip.step_value), type_scale)
			chip.queue_redraw()
		for chip in _motion_steps:
			chip.engaged = (bool(chip.step_value) == reduced_motion)
			chip.queue_redraw()


	func _on_step(kind: StringName, value: Variant) -> void:
		step_pressed.emit(kind, value)


	# --- focus ----------------------------------------------------------------------------


	## THE WALK: left/right cycle inside a row (the steps are a rail),
	## the column runs header-row to header-row and ends at the back
	## verb, cyclic (the fan's own column rule, vertical form).
	func _wire_focus_chains() -> void:
		var column: Array[Control] = []
		column.append_array(_type_steps)
		column.append_array(_motion_steps)
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
		_wire_rail(_type_steps)
		_wire_rail(_motion_steps)


	func _wire_rail(rail: Array[StepChip]) -> void:
		if rail.is_empty():
			return
		var count := rail.size()
		if count < 2:
			rail[0].focus_neighbor_left = rail[0].get_path_to(rail[0])
			rail[0].focus_neighbor_right = rail[0].get_path_to(rail[0])
			return
		for i in count:
			var node: Control = rail[i]
			node.focus_neighbor_left = node.get_path_to(rail[wrapi(i - 1, 0, count)])
			node.focus_neighbor_right = node.get_path_to(rail[wrapi(i + 1, 0, count)])


	## The engaged step on the hand row (the focus seed).
	func engaged_type_step() -> Control:
		for chip in _type_steps:
			if chip.engaged:
				return chip
		return null


	## Any focusable, in walk order (the fallback seed).
	func first_focusable() -> Control:
		if not _type_steps.is_empty():
			return _type_steps[0]
		return _back_chip


	## The step chips in walk order + the back verb (tests).
	func focusables() -> Array[Control]:
		var found: Array[Control] = []
		found.append_array(_type_steps)
		found.append_array(_motion_steps)
		found.append(_back_chip)
		return found


	func back_chip() -> Control:
		return _back_chip


	func type_steps() -> Array[Control]:
		var found: Array[Control] = []
		found.append_array(_type_steps)
		return found


	func motion_steps() -> Array[Control]:
		var found: Array[Control] = []
		found.append_array(_motion_steps)
		return found


	# --- layout (pure statics) --------------------------------------------------------------


	func _relaid() -> void:
		if _title_label == null or size.x < 8.0 or size.y < 8.0:
			return
		var rects := sheet_rects(size)
		_sheet_rect = rects["sheet"]
		var inner := Rect2(_sheet_rect.position + Vector2(PAD, PAD),
			_sheet_rect.size - Vector2(2.0 * PAD, 2.0 * PAD))
		var y := 0.0
		_fit(_title_label, _row(inner, y, TITLE_H))
		y += TITLE_H
		_fit(_kept_row, _row(inner, y, KEPT_H))
		y += KEPT_H + ROW_SEP
		_fit(_type_label, _row(inner, y, LABEL_H))
		y += LABEL_H
		_fit(_type_note, _row(inner, y, NOTE_H))
		y += NOTE_H
		_fit(_type_row, _row(inner, y, CHIP_H))
		y += CHIP_H + ROW_SEP
		_fit(_motion_label, _row(inner, y, LABEL_H))
		y += LABEL_H
		_fit(_motion_note, _row(inner, y, NOTE_H))
		y += NOTE_H
		_fit(_motion_row, _row(inner, y, CHIP_H))
		y += CHIP_H + ROW_SEP
		_fit(_back_chip, _row(inner, y, CHIP_H))
		queue_redraw()


	func _row(inner: Rect2, offset: float, height: float) -> Rect2:
		return Rect2(inner.position + Vector2(0.0, offset), Vector2(inner.size.x, height))


	## The card's layout rect: fixed-height content, capped width,
	## centered in the bounds (a card on the table, like the choice
	## card). Pure: same bounds => same rect.
	static func sheet_rects(bounds: Vector2) -> Dictionary:
		var wide := minf(bounds.x - 2.0 * MARGIN, SHEET_MAX_WIDTH)
		var fixed := TITLE_H + KEPT_H + 2.0 * ROW_SEP \
			+ 2.0 * (LABEL_H + NOTE_H + CHIP_H) + CHIP_H + 2.0 * PAD
		var sheet_h := minf(fixed, maxf(float(Inks.TOUCH_GRIP_MIN) * 3.0, bounds.y - 2.0 * MARGIN))
		var sheet := Rect2(Vector2((bounds.x - wide) * 0.5, (bounds.y - sheet_h) * 0.5),
			Vector2(wide, sheet_h))
		return {"sheet": sheet, "sheet_h": sheet_h}


	func _fit(control: Control, rect: Rect2) -> void:
		control.position = rect.position
		control.size = rect.size


# --- the step chip ---------------------------------------------------------------------------


## StepChip — one step of a preference rail: the ActionChip's own stock
## and mark grammar (paper strip, focus ghost, leading rule) with a
## numeral/word plate. The step IN FORCE prints its rule DOUBLE in red
## (the signature mark); the others print a single ink rule — state by
## line form, never hue alone.
class StepChip:
	extends Button

	## The value this step sets (float factor for the hand, bool for the
	## presswork) — carried untyped so one chip serves both rails.
	var step_value: Variant
	var engaged := false

	var _label_text := ""
	var _numeral := false
	var _label: Label


	func _init(label_text: String, numeral: bool, value: Variant = null) -> void:
		_label_text = label_text
		_numeral = numeral
		step_value = value
		flat = true
		focus_mode = Control.FOCUS_ALL


	func _ready() -> void:
		custom_minimum_size = Vector2(92.0, float(Inks.TOUCH_GRIP_MIN))
		_label = Label.new()
		_label.theme_type_variation = &"Numerals" if _numeral else &"RoleLine"
		_label.text = _label_text
		_label.clip_text = true
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		# Anchors AND offsets — the preset call alone leaves the offsets
		# at zero-relative and the plate collapses to a 1px sliver (the
		# first press-open capture's find: four unlabeled chips). The
		# left inset clears the leading rule (the ActionChip's own
		# geometry), so the centered plate reads clear of its mark.
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.offset_left = 14.0


	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		# Paper strip — the chip is the same stock as the cards.
		draw_rect(rect.grow(-2.0), Inks.PAPER)
		# Focus ghost FIRST (behind the paper): the registration-miss mark.
		if has_focus():
			draw_rect(Rect2(Vector2(6.0, 3.0), size - Vector2(11.0, 9.0)), Inks.RED, false, 2.5)
		# The leading rule — the step IN FORCE prints DOUBLE (the
		# signature mark); the rest print a single ink rule.
		if engaged:
			draw_rect(Rect2(Vector2(7.0, 7.0), Vector2(3.0, size.y - 14.0)), Inks.RED)
			draw_rect(Rect2(Vector2(12.0, 7.0), Vector2(3.0, size.y - 14.0)), Inks.RED)
			_label.add_theme_color_override("font_color", Inks.INK)
		else:
			draw_rect(Rect2(Vector2(8.0, 7.0), Vector2(5.0, size.y - 14.0)), Inks.INK)
			_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		# The pressed chip re-inks its edge (the press's impression).
		if pressed:
			draw_rect(rect.grow(-2.0), Inks.INK, false, 2.0)
