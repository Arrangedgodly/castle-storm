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
class_name CardFace
extends BoxContainer

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## THE PLATE FIT (the readability pass — the 55%/70% clip floors are GONE):
## a plate's print steps its font DOWN to the plate's width until the
## WHOLE text fits — shrink-to-full-fit, never a floored clip. The base
## is re-read from the live theme on every fit (override cleared first),
## so the TypeScale factor and any whole-view rebind stay authoritative;
## `p_base` > 0 pins the base instead (plates that bake a LOCAL size —
## the castle's one-size-down title, the odds roster's rank plates).
## The only remaining floor is ABSOLUTE (MIN_FIT_SIZE) so a degenerate
## string cannot step a plate into unreadable nothing: below it the
## label's clip_text stays as the documented LAST resort (fail-SAFE —
## the print stops at the plate edge, never past the card). Real content
## never reaches it: at every roster density the layout grants, pool
## names and role lines fit whole above the floor (the readability
## audit, scripts/readability_audit.gd, runs this inventory headless).
## At extreme roster density the table's arithmetic bounds how wide any
## card can print; the honest answer there is whole-but-small — a clipped
## print is a bug, a small whole print is density.
const MIN_FIT_SIZE := 8
const FIT_STEP := 2

## The castle title's one-size-down base is a PROPERTY of the face now
## (the old _ready override was silently WIPED by the fit's base re-read
## — the audit found the castle title fitting from the full themed base).
## 0 = the themed base (every normal card).
@export var title_base := 0:
	set(value):
		title_base = maxi(0, value)
		if _name_label != null:
			_refit_plates()

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
			_refit_plates()

## The role line (unit role / regime flavor — the soft-ink caption).
@export var role_line: String = "":
	set(value):
		role_line = value
		if _role_label != null:
			_role_label.text = value
			_refit_plates()

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
	_name_label.clip_text = true  # T-UI-03 fail-safe — now BELOW the plate fit's floor, never the default
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.resized.connect(_refit_plates)
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
	_role_label.clip_text = true  # T-UI-03 fail-safe — below the plate fit's floor
	_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_label.resized.connect(_refit_plates)
	add_child(_role_label)
	_apply_arrangement()
	_refit_plates()


func _init() -> void:
	## Grip floor via custom_minimum_size (NOT a _get_minimum_size
	## override — that would shadow BoxContainer's child accounting).
	custom_minimum_size = Vector2.ONE * Inks.TOUCH_GRIP_MIN


## Test/measurement seam: the two plates (the fit's subjects).
func name_plate() -> Label:
	return _name_label


func role_plate() -> Label:
	return _role_label


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


## Refit both plates for their CURRENT widths (the plate fit — see the
## header const block). Called on text change and on the labels' own
## `resized`. GUARDED by text+width: the fit itself changes the label's
## minimum HEIGHT, which re-lays the row and re-fires `resized` — without
## the guard that would ping-pong forever. A not-yet-laid label (width
## <= 1) is skipped — its `resized` fires when the layout grants a width.
var _name_fit_key := ""
var _role_fit_key := ""


func _refit_plates() -> void:
	if _name_label != null:
		var key := "%s@%.1f@%d" % [_name_label.text, _name_label.size.x, title_base]
		if key != _name_fit_key:
			_name_fit_key = key
			fit_label_to_width(_name_label, 0.0, FIT_STEP, title_base)
	if _role_label != null:
		var key := "%s@%.1f" % [_role_label.text, _role_label.size.x]
		if key != _role_fit_key:
			_role_fit_key = key
			fit_label_to_width(_role_label, 0.0, FIT_STEP)


## THE PLATE FIT, shared by every card grammar surface (the spread's card
## faces, the castle card, the assault roster's rank plates): step the
## label's font down from its base (THEMED — override cleared, so the
## TypeScale factor stays authoritative — or `p_base` when pinned) until
## the WHOLE text fits the label's width. `floor_ratio` is retained in
## the signature for call-site compatibility and is IGNORED (the old
## 55%/70% floors clipped; the readability pass replaced them with
## shrink-to-full-fit). The absolute MIN_FIT_SIZE bounds the step-down;
## below it the label's clip_text is the last-resort fail-safe (never
## past the card). Returns the applied size (0 when the label is not
## measurable yet). Pure given text + theme + width: same state -> same
## size, so view hashes stay deterministic.
static func fit_label_to_width(label: Label, _floor_ratio := 0.0, step := 2,
		p_base := -1) -> int:
	if label == null or not is_instance_valid(label):
		return 0
	var width := label.size.x
	if width <= 1.0 or label.text.is_empty():
		return 0
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return 0
	var base := p_base
	if base <= 0:
		label.remove_theme_font_size_override(&"font_size")
		base = label.get_theme_font_size(&"font_size")
	if base <= 0:
		return 0
	var size := base
	while size > MIN_FIT_SIZE:
		if font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x <= width:
			break  # the WHOLE text fits at this size — done
		size = maxi(size - step, MIN_FIT_SIZE)  # the last step lands ON the floor
	if size != base or p_base > 0:
		label.add_theme_font_size_override(&"font_size", size)
	return size
