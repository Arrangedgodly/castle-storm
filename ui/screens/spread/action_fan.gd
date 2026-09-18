## ActionFan — the contextual action fan at a card's edge (T-UI-04).
##
## THE AFFORDANCE IS IN-WORLD: pressing or tapping a card fans a column of
## small print-styled chips out from the card's edge — paper strips, each
## carrying an action label, a leading rule in the line-form grammar
## (SOLID enabled / STRUCK disabled-with-reason; the signature promote
## action prints a DOUBLE rule — the chronicle's victory flourish), and,
## for disabled chips, the refusal reason as a second soft-ink line. NO
## modal dialog, NO popup chrome (the brief's second kept raise): the fan
## is paper on the same table.
##
## INPUT PARITY (Daredevil):
##   - TOUCH: every chip is a >=48dp grip (custom_minimum_size floor) and
##     a whole-chip press target (Button);
##   - CONTROLLER/KEYBOARD: the fan is a FOCUS TRAP — opening it grabs the
##     first chip, all four direction neighbors + focus_next/previous
##     resolve INSIDE the fan (cyclic, no dead ends), and closing it
##     (the screen's `back` handling) returns focus to the card that
##     opened it;
##   - DISABLED ACTIONS ARE FOCUSABLE BUT MARKED (the documented, kept-
##     consistent choice): a pad player can walk onto a struck chip and
##     READ why it is refused — the reason prints on the chip, and
##     activating it emits action_refused so the screen can print the
##     chronicle hint. Skipping disabled chips would hide the economy's
##     edges behind silence.
##
## The hint strip at the fan's foot is the intercepted hint (the
## controller's face-button hint slot, printed rather than overlaid):
## "choose — act — back" in the soft ink.
##
## THE FAN'S OWN SHEET (readability r3 — the choice-card/veil pattern):
## the whole fan (chips + hint) prints on ONE localized paper sheet laid
## over the table, because covering text is legitimate ONLY when the
## covering paper is a designed surface. Before the sheet the fan's
## separate strips sliced FOREIGN titles into fragments (the verifier's
## co-mount find, invisible to the r2 audit's standalone fan walk: the
## "Send them home" chip crossed "Hob"'s title glyph tops and the hint
## strip printed straight across "Hob"/"Nell", the Eye's numeral plate
## under it too). With the sheet, a fan opened over a neighbor's title
## hides it cleanly UNDER one designed paper edge — the same move as any
## card laid over this table — and no glyph fragments peek between the
## strips. The audit's co-mount rule reads sheet_rect(): a fan print may
## overlap foreign text ONLY inside the sheet.
class_name ActionFan
extends VBoxContainer

## A chip was activated while enabled: submit it (one real command).
signal action_chosen(action: Dictionary)
## A DISABLED chip was activated: print the refusal (chronicle hint).
signal action_refused(action: Dictionary)

## The sheet's air around the chips + hint (design units). The fan is
## placed >= 8px inside the screen bounds, so the sheet always stays on
## the table.
const SHEET_PAD := 8.0

## The view-model card id this fan is fanned out from ("" while closed).
var card_id := ""

var _chips: Array[ActionChip] = []
var _hint: Control


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	visible = false
	# THE HINT IS PAPER (readability r2): the round-1 hint was a bare
	# soft-ink Label — over a card's paper it read, but the fan sits ON
	# the table and its foot overhangs the card edge, where soft ink on
	# the dark ground VANISHED ("ose — act — back"; the verifier's
	# occlusion find). The strip is the fan's own paper stock: the hint
	# legible over any ground, and the VBox contract reserves its row —
	# grown chips stack ABOVE it, never onto it.
	_hint = HintStrip.new()
	add_child(_hint)


## Open re-bakes the hint's print (the press-room's live type-scale step
## re-flows a fan composed at another factor the next time it opens).
func _sync_hint() -> void:
	(_hint as HintStrip).reprint()


## Fan out over a card: rebuild the chips from the action model, trap the
## focus, and seed it on the first chip. Deferred focus grab — chips need
## one frame in the tree before focus lands.
func open(for_card_id: String, actions: Array[Dictionary]) -> void:
	card_id = for_card_id
	# The hint's baked size re-applies on every open — the press-room's
	# live type-scale change (finishing refinement #5) re-flows a fan
	# composed at another factor the next time it opens.
	_sync_hint()
	for chip in _chips:
		chip.queue_free()
	_chips.clear()
	for action in actions:
		var chip := ActionChip.new()
		chip.action = action
		chip.pressed.connect(_on_chip_pressed.bind(chip))
		add_child(chip)
		_chips.append(chip)
	move_child(_hint, get_child_count() - 1)
	visible = true
	size = get_combined_minimum_size()
	_wire_focus_trap()
	if not _chips.is_empty():
		_chips[0].grab_focus.call_deferred()


## Fold the fan away (the screen returns focus to the card).
func close() -> void:
	visible = false
	card_id = ""


## The fan's paper sheet in the fan's LOCAL space (the audit's co-mount
## occlusion rule reads it: a fan print may overlap foreign text ONLY
## inside this designed surface). The fan is never rotated or scaled on
## the screen, so local == global axes.
func sheet_rect() -> Rect2:
	return Rect2(Vector2(-SHEET_PAD, -SHEET_PAD),
		size + Vector2(SHEET_PAD, SHEET_PAD) * 2.0)


func _draw() -> void:
	# THE SHEET (see the header): one paper quad under the whole fan —
	# the chips' stock, ink-edged like the hint strip's foot rule. Drawn
	# behind the children (a CanvasItem's own draw runs under them), and
	# the fan is invisible while closed, so nothing prints while folded.
	var sheet := sheet_rect()
	draw_rect(sheet, Inks.PAPER)
	draw_rect(sheet, Inks.INK, false, 1.0)


## The fan's chips in print order (tests + the screen's grip audit).
func chips() -> Array[ActionChip]:
	return _chips


func is_open() -> bool:
	return visible


func _on_chip_pressed(chip: ActionChip) -> void:
	if bool(chip.action.get("enabled", false)):
		action_chosen.emit(chip.action)
	else:
		action_refused.emit(chip.action)


## Activate whichever chip holds focus (the pad's A button when the engine
## does not route it as ui_accept — a parity guarantee: acting on a fan is
## reachable from keyboard Enter, pad A, and touch alike, exactly once
## each, because the natively-routed form never reaches the screen).
func activate_focused() -> void:
	if not visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and focus is ActionChip and focus.get_parent() == self:
		_on_chip_pressed(focus as ActionChip)


## THE TRAP: every direction from every chip resolves to another chip in
## this fan, cyclically — pad/kb navigation cannot leave the fan except by
## acting or backing out (both handled), so there are no focus dead ends.
func _wire_focus_trap() -> void:
	var count := _chips.size()
	if count == 0:
		return
	for i in count:
		var chip := _chips[i]
		var prev: Control = _chips[wrapi(i - 1, 0, count)]
		var next: Control = _chips[wrapi(i + 1, 0, count)]
		chip.focus_neighbor_left = chip.get_path_to(prev)
		chip.focus_neighbor_top = chip.get_path_to(prev)
		chip.focus_neighbor_right = chip.get_path_to(next)
		chip.focus_neighbor_bottom = chip.get_path_to(next)
		chip.focus_previous = chip.get_path_to(prev)
		chip.focus_next = chip.get_path_to(next)


## One print-styled action strip: paper quad, a leading rule whose FORM
## carries the action's state (solid ready / struck refused / double the
## signature promote), the label, and the disabled reason. The focus mark
## is the frame grammar's own: a revolution-red offset pass that missed
## registration. Struck chips also carry the strike diagonal — the same
## form language as a struck card edge, readable without color.
class ActionChip:
	extends Button

	## The action-model dict this chip prints (see CardActions).
	var action: Dictionary = {}

	var _label: Label
	var _reason: Label


	const CHROME := 30.0  # the leading rule + the label's side offsets
	const MAX_CHIP_W := 320.0  # past this the clip fail-safe stays (never reached by real copy)

	func _init() -> void:
		custom_minimum_size = Vector2(152.0, float(Inks.TOUCH_GRIP_MIN))
		focus_mode = Control.FOCUS_ALL
		flat = true


	func _ready() -> void:
		var has_reason := not String(action.get("reason", "")).is_empty()
		if has_reason:
			custom_minimum_size = Vector2(152.0, float(Inks.TOUCH_GRIP_MIN) + 14.0)
		_label = Label.new()
		_label.theme_type_variation = &"RoleLine"
		_label.text = String(action.get("label", ""))
		_label.clip_text = true  # last resort only — the plate grows first (below)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(_label)
		if has_reason:
			_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_label.offset_left = 22.0
			_label.offset_top = 5.0
			_label.offset_right = -8.0
			_label.offset_bottom = 24.0
			_reason = Label.new()
			_reason.theme_type_variation = &"RoleLine"
			_reason.add_theme_font_size_override("font_size", TypeScale.scaled(16))
			_reason.add_theme_color_override("font_color", Inks.INK_SOFT)
			_reason.text = String(action.get("reason", ""))
			_reason.clip_text = true  # last resort only — the plate grows first
			_reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_reason)
			_reason.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			_reason.offset_left = 22.0
			_reason.offset_top = -22.0
			_reason.offset_right = -8.0
			_reason.offset_bottom = -4.0
		else:
			_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_label.offset_left = 22.0
			_label.offset_top = 2.0
			_label.offset_right = -8.0
			_label.offset_bottom = -2.0
		if bool(action.get("signature", false)):
			_label.add_theme_color_override("font_color", Inks.RED)
		_grow_to_text()


	## THE PLATE GROWS, NOT THE CLIP (the readability pass): the chip's
	## minimum width is its own measured print — the wider of the label
	## and the refusal reason at their applied sizes, plus the rule/side
	## chrome — so a long verb ("Send them home", +6px at 1.0x, +24px at
	## 1.3x on the old 152px plate) never clips. Pure function of the
	## action model + the type factor (the same determinism contract as
	## the header's measured plates). MAX_CHIP_W is the honest ceiling
	## where growth would crowd the table; real copy stays far below it.
	func _grow_to_text() -> void:
		var need := 0.0
		for plate: Label in [_label, _reason]:
			if plate == null or plate.text.is_empty():
				continue
			var font: Font = plate.get_theme_font(&"font")
			if font == null:
				continue
			var text_w := font.get_string_size(plate.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, plate.get_theme_font_size(&"font_size")).x
			need = maxf(need, text_w + CHROME)
		if need > 0.0:
			custom_minimum_size.x = clampf(need, 152.0, MAX_CHIP_W)


	func _draw() -> void:
		var enabled_action := bool(action.get("enabled", false))
		var signature := bool(action.get("signature", false))
		var rect := Rect2(Vector2.ZERO, size)
		# Paper strip — the chip is the same stock as the cards.
		draw_rect(rect.grow(-2.0), Inks.PAPER)
		# Focus ghost FIRST (behind the paper): the registration-miss mark.
		if has_focus():
			draw_rect(Rect2(Vector2(6.0, 3.0), size - Vector2(11.0, 9.0)), Inks.RED, false, 2.5)
		# The leading rule — FORM carries the action's state, never hue.
		var ink := Inks.INK if enabled_action else Inks.INK_SOFT
		if enabled_action and signature:
			# The signature action prints DOUBLE (the victory flourish).
			draw_rect(Rect2(Vector2(7.0, 7.0), Vector2(3.0, size.y - 14.0)), Inks.RED)
			draw_rect(Rect2(Vector2(12.0, 7.0), Vector2(3.0, size.y - 14.0)), Inks.RED)
		elif enabled_action:
			draw_rect(Rect2(Vector2(8.0, 7.0), Vector2(5.0, size.y - 14.0)), ink)
		else:
			# Struck: a thinned rule plus the strike diagonal across the chip.
			draw_rect(Rect2(Vector2(8.0, 7.0), Vector2(5.0, size.y - 14.0)), ink)
			draw_line(Vector2(6.0, size.y - 8.0), Vector2(size.x - 6.0, 8.0), ink, 2.5, true)
		# The pressed chip re-inks its edge (the press's impression).
		if pressed:
			draw_rect(rect.grow(-2.0), Inks.INK, false, 2.0)


## The fan hint's own paper strip (readability r2 — see _ready): the
## "choose — act — back" caption on a small paper quad in the chips'
## stock, soft ink, printed whole at its baked caption size. The strip's
## minimum is its measured print + air (a plate grows, never clips);
## the VBox reserves its row BELOW the chips — grown chips stack above,
## never onto it (the fan-vs-hint layout contract).
class HintStrip:
	extends Control

	const PAD_H := 10.0
	const STRIP_H := 26.0

	var _label: Label

	func _init() -> void:
		custom_minimum_size = Vector2(120.0, STRIP_H)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_label = Label.new()
		_label.theme_type_variation = &"RoleLine"
		_label.text = "choose — act — back"
		_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.clip_text = true  # render fail-safe only — the strip grows first
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.offset_left = PAD_H
		_label.offset_right = -PAD_H
		add_child(_label)
		reprint()

	## The strip's minimum is its measured print + air, at the CURRENT
	## type factor (the open-time re-bake seam).
	func reprint() -> void:
		if _label == null:
			return
		_label.add_theme_font_size_override("font_size", TypeScale.scaled(18))
		var font: Font = _label.get_theme_font(&"font")
		var text_w := 120.0
		if font != null:
			text_w = font.get_string_size(_label.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				_label.get_theme_font_size(&"font_size")).x
		custom_minimum_size = Vector2(text_w + 2.0 * PAD_H, STRIP_H)
		queue_redraw()

	func _draw() -> void:
		# The chips' paper stock, ink-edged — the fan's foot rule.
		draw_rect(Rect2(Vector2.ZERO, size), Inks.PAPER)
		draw_rect(Rect2(Vector2.ZERO, size), Inks.INK, false, 1.0)
