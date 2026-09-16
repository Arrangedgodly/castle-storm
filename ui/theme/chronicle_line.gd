## ChronicleLine — an event printed onto the table (T-UI-01).
##
## The design brief's second kept raise, "states print themselves":
## crackdowns, warnings, and victories write themselves into the spread
## as chronicle lines on the table ground — never popup chrome. The line
## is a RuleMark prefix (the line-form grammar at text scale: solid
## plain / dashed warn / struck crackdown / double victory) plus the
## italic workhorse face. Ink choice follows the print rule: dark
## grounds print paper-bright ink, light grounds (aftermath) print
## near-black — a press choosing ink per stock, and the reason both
## channels pass contrast on every ground (tested).
##
## Focusable (controller/keyboard can walk the history): a focused row
## re-prints its baseline rule offset in red — the same misregistration
## focus grammar as the card frame.
extends Control

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## Which line-form class this event prints as (Inks.line_class_for_event).
@export var line_class: Inks.LineClass = Inks.LineClass.PLAIN:
	set(value):
		if line_class != value:
			line_class = value
			_sync_form()

## The printed text (already human-readable: the sim's chronicle_line
## render query supplies it; this component only prints).
@export var text: String = "":
	set(value):
		if text != value:
			text = value
			if _label != null:
				_label.text = value

## Ground the line prints onto — picks the ink channel (paper-bright on
## dark, ink on light). Defaults to the neutral recruiting ground.
@export var ground: Color = Inks.NEUTRAL_GROUND:
	set(value):
		if ground != value:
			ground = value
			_sync_inks()

var _row: HBoxContainer
var _rule: Control
var _label: Label

const _CLASS_TO_FORM: Dictionary = {
	Inks.LineClass.PLAIN: 0,   # RuleMark.RuleForm.SOLID
	Inks.LineClass.WARN: 1,    # DASHED
	Inks.LineClass.STRIKE: 2,  # STRUCK
	Inks.LineClass.VICTORY: 3, # DOUBLE
}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = 8.0
	_row.offset_right = -8.0
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_rule = RULE_SCENE.instantiate()
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_rule)
	_label = Label.new()
	_label.theme_type_variation = &"ChronicleLine"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.text = text
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_label)
	_sync_form()
	_sync_inks()


func _get_minimum_size() -> Vector2:
	## A chronicle row is a focusable walking target: grip-height rows
	## (>= 48 design units) keep controller nav comfortable.
	return Vector2(Inks.TOUCH_GRIP_MIN * 4.0, Inks.TOUCH_GRIP_MIN)


func _sync_form() -> void:
	if _rule != null:
		_rule.set("form", int(_CLASS_TO_FORM[line_class]))


func _sync_inks() -> void:
	if _rule == null or _label == null:
		return
	var text_ink := Inks.ground_text_ink(ground)
	_rule.set("rule_ink", text_ink)
	_label.add_theme_color_override("font_color", text_ink)


func _draw() -> void:
	## Focus: the row's baseline re-printed offset in the ground's red —
	## misregistration, the world's focus ring (form, not hue).
	if not has_focus():
		return
	var ink := Inks.ground_accent_ink(ground)
	draw_line(Vector2(10.0, size.y - 9.0), Vector2(size.x - 10.0, size.y - 9.0), ink, 3.0, true)
	draw_line(Vector2(13.0, size.y - 7.0), Vector2(size.x - 7.0, size.y - 7.0), ink, 3.0, true)
