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
class_name ActionFan
extends VBoxContainer

## A chip was activated while enabled: submit it (one real command).
signal action_chosen(action: Dictionary)
## A DISABLED chip was activated: print the refusal (chronicle hint).
signal action_refused(action: Dictionary)

## The view-model card id this fan is fanned out from ("" while closed).
var card_id := ""

var _chips: Array[ActionChip] = []
var _hint: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	visible = false
	_hint = Label.new()
	_hint.theme_type_variation = &"RoleLine"
	_hint.text = "choose — act — back"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The hint's baked size (the readability pass raised it 16 -> 18; it is
	# a caption, kept one rung under its RoleLine variation).
	_hint.add_theme_font_size_override("font_size", TypeScale.scaled(18))
	_hint.add_theme_color_override("font_color", Inks.INK_SOFT)
	add_child(_hint)


## Fan out over a card: rebuild the chips from the action model, trap the
## focus, and seed it on the first chip. Deferred focus grab — chips need
## one frame in the tree before focus lands.
func open(for_card_id: String, actions: Array[Dictionary]) -> void:
	card_id = for_card_id
	# The hint's baked size re-applies on every open — the press-room's
	# live type-scale change (finishing refinement #5) re-flows a fan
	# composed at another factor the next time it opens.
	_hint.add_theme_font_size_override("font_size", TypeScale.scaled(18))
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
