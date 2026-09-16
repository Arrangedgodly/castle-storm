## CardFace — the card's face plate: art slot + name plate + role line
## (T-UI-01).
##
## Sized for BOTH orientations (the design brief's responsive topology):
## the box reflows — portrait cards stack (art above, plates below),
## landscape cards run the art left and the plates right — one
## component, same grammar, aspect-switched with a hysteresis band so
## square-ish resizes do not flap. The name prints in the display face
## (IM Fell English SC — the pairing rationale lives in inks.gd's header
## and the production log); the role line prints in the soft ink.
##
## Compose inside a CardFrame; the face never draws its own border.
extends BoxContainer

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## Face art key in the pack's art manifest (e.g. &"face_peasant"). Empty
## or pending keys print FaceSlot's authored placeholder mark. Data-driven
## end to end: the manifest's atlas_region + FaceArt own the single-pose
## crop and two-ink print, so landing or re-posing face art is a content
## edit, never a UI code change (R6: no vendor paths in UI code).
@export var face_key: StringName = &"":
	set(value):
		face_key = value
		if _slot != null:
			_slot.face_key = value

## The card's name (name plate, display face).
@export var card_name: String = "":
	set(value):
		card_name = value
		if _name_label != null:
			_name_label.text = value

## The role line (unit role / regime flavor — the soft-ink caption).
@export var role_line: String = "":
	set(value):
		role_line = value
		if _role_label != null:
			_role_label.text = value

var _slot: TextureRect
var _name_label: Label
var _role_label: Label
var _rule: Control

## Aspect hysteresis: flip to landscape above 1.15, back to portrait
## below 1.0 — the deadband R3 prescribes for orientation decisions.
const LANDSCAPE_ON := 1.15
const LANDSCAPE_OFF := 1.0


func _ready() -> void:
	vertical = true
	add_theme_constant_override("separation", 6)
	_slot = load("res://ui/theme/face_slot.tscn").instantiate()
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slot.custom_minimum_size = Vector2.ONE * Inks.TOUCH_GRIP_MIN
	_slot.face_key = face_key
	add_child(_slot)
	_name_label = Label.new()
	_name_label.theme_type_variation = &"CardTitle"
	_name_label.text = card_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.clip_text = true  # T-UI-03: roster-scale columns never let a name widen the card past the table
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	_rule = RULE_SCENE.instantiate()
	_rule.set("form", 0)  # solid
	_rule.set("rule_ink", Inks.INK)
	_rule.set("rule_width", 2.0)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rule)
	_role_label = Label.new()
	_role_label.theme_type_variation = &"RoleLine"
	_role_label.text = role_line
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.clip_text = true  # T-UI-03: countdown/role plates clip, never overflow
	_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_role_label)
	_apply_arrangement()


func _init() -> void:
	## Grip floor via custom_minimum_size (NOT a _get_minimum_size
	## override — that would shadow BoxContainer's child accounting).
	custom_minimum_size = Vector2.ONE * Inks.TOUCH_GRIP_MIN


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_arrangement()


func _apply_arrangement() -> void:
	## Portrait stacks (vertical), landscape runs horizontal; hysteresis
	## deadband between LANDSCAPE_OFF and LANDSCAPE_ON holds the current
	## arrangement. NOTIFICATION_RESIZED can arrive before _ready has
	## built the plates, so unbuilt means nothing to arrange yet.
	if _name_label == null or _role_label == null:
		return
	var aspect := size.x / maxf(size.y, 1.0)
	if not vertical and aspect < LANDSCAPE_OFF:
		vertical = true
	elif vertical and aspect > LANDSCAPE_ON:
		vertical = false
	var center_plates := not vertical
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if center_plates else Control.SIZE_FILL
	_role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if center_plates else Control.SIZE_FILL
	_rule.visible = vertical  # the under-title rule is a portrait plate cue
