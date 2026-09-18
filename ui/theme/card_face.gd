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

## THE READABILITY FLOOR (readability r2 — grow, don't shrink): the
## round-1 shrink-to-full-fit converted CLIP into TINY (the verifier's
## find: card titles fitted to 8px). The fit now operates ONLY between
## the authored base and the FLOOR — a print never renders below it:
##
##   MIN_FIT_SIZE (12)  — the hard readability floor, every plate.
##   TITLE_FLOOR (18)   — card-name plates (the display face); clears
##                        the audit's <17px TINY bar with margin.
##
## When the WHOLE text cannot fit the plate even at the floor, THE PLATE
## GROWS: `custom_minimum_size.x` rises to the floor-size print + air
## (the card/panel minimums follow it up through the containers), and
## the print stays whole at the floor. Card TITLES have a wider move
## first: they WRAP to the plate like every long print in this world
## (the letterhead's own move — the epithet drops a line), one-line fit
## preferred, the widest word carried whole. clip_text stays only as the
## render fail-safe at the plate edge (never past the card) — the floor
## + wrap + grow chain keeps real copy off it. The fit measures the
## WIDEST LINE (a "\n" split is two plates of print, never one long
## line — the round-1 fit measured the castle's wrapped garrison line
## concatenated and over-stepped it). The fit also keeps AIR inside the
## plate (FIT_MARGIN a side) so glyphs never print edge-to-edge.
const MIN_FIT_SIZE := 12
const TITLE_FLOOR := 18
const WRAP_BELOW := 17  # one-line prints landing under this wrap first
const FIT_STEP := 2
const FIT_MARGIN := 2.0

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
		var wrap := _plates_may_wrap()
		var key := "%s@%.1f@%d@%s" % [_name_label.text, _name_label.size.x, title_base, wrap]
		if key != _name_fit_key:
			_name_fit_key = key
			# Titles: the display face keeps its plate down to TITLE_FLOOR
			# and wraps (paper flow) before any grow.
			fit_label_to_width(_name_label, 0.0, FIT_STEP, title_base, TITLE_FLOOR, wrap)
	if _role_label != null:
		var wrap := _plates_may_wrap()
		var key := "%s@%.1f@%s" % [_role_label.text, _role_label.size.x, wrap]
		if key != _role_fit_key:
			_role_fit_key = key
			# Roles wrap under the small-print line too (the plate's
			# height permitting — see the fit's wrap contract).
			fit_label_to_width(_role_label, 0.0, FIT_STEP, -1, MIN_FIT_SIZE, wrap)


## Whether the plates may take a second line: the face must hold the art
## slot's grip PLUS a two-line plate — a roomy card wraps (paper flow);
## a sliver cell (the density answer) keeps one-line prints at the floor
## so the card's honest minimum stays within its row. Read off the FACE's
## own granted height — one level above the labels — so the fit's outcome
## can never feed its own input (the label-height version re-entered
## `resized` mid-sort and recursed; the suite's stack-overflow find).
func _plates_may_wrap() -> bool:
	return size.y >= float(Inks.TOUCH_GRIP_MIN) + 2.0 * float(TypeScale.scaled(24))


## THE PLATE FIT, shared by every card grammar surface (the spread's card
## faces, the castle card, the assault roster's rank plates): step the
## label's font down from its base (THEMED — override cleared, so the
## TypeScale factor stays authoritative — or `p_base` when pinned) toward
## `p_floor` (the readability floor; -1 = MIN_FIT_SIZE) until the WHOLE
## text fits the plate with air (FIT_MARGIN a side). The step-down NEVER
## passes the floor: below it the plate GROWS (custom_minimum_size.x to
## the floor-size print + air — the containers carry the plate's minimum
## up to the card/panel) and the print stays whole at the floor.
##
## `allow_wrap` (card TITLES): before growing, a multi-word title wraps
## to the plate (the letterhead's own move) — one-line fit preferred;
## only when even the WIDEST WORD cannot fit at the floor does the plate
## grow. Pure given text + theme + width: same state -> same size, so
## view hashes stay deterministic. Returns the applied size (0 when the
## label is not measurable yet).
static func fit_label_to_width(label: Label, _floor_ratio := 0.0, step := 2,
		p_base := -1, p_floor := -1, allow_wrap := false) -> int:
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
	var floor_size := TypeScale.scaled(
		p_floor if p_floor > 0 else MIN_FIT_SIZE)  # authored units -> live factor
	var target := width - 2.0 * FIT_MARGIN
	# One-line pass: the largest size at/above the floor whose widest
	# LINE (" plates" split prints) fits the target.
	var size := base
	while size > floor_size and _line_width(font, label.text, size) > target:
		size = maxi(size - step, floor_size)  # the last step lands ON the floor
	var one_line_fits := _line_width(font, label.text, size) <= target
	if one_line_fits and size >= TypeScale.scaled(WRAP_BELOW):
		_apply_size(label, size, base, p_base > 0)
		return size
	# The one-line print is unwritable at a readable size (it cannot fit
	# its floor, or it only fits BELOW the small-print line). Titles and
	# roles wrap first (paper flow — every line whole, the widest word
	# carried) when the CALLER granted wrap room (`allow_wrap` — the
	# caller reads its own stable geometry, never this label's height, so
	# the fit's outcome cannot feed its own input). Without wrap room the
	# honest print is the one-line floor.
	var word_size := base
	while word_size > floor_size and _word_width(font, label.text, word_size) > target:
		word_size = maxi(word_size - step, floor_size)
	if allow_wrap and _word_width(font, label.text, word_size) <= target:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_size(label, word_size, base, p_base > 0)
		return word_size
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# GROW, NOT CLIP (readability r2): the plate's minimum rises to the
	# floor-size print + air; the print renders whole at the floor. A
	# one-line print that FITS at its floor stays whole (never grown for
	# air it already has) — grow only rescues a print that cannot fit.
	if one_line_fits:
		_apply_size(label, size, base, p_base > 0)
		return size
	var need := _line_width(font, label.text, floor_size) + 2.0 * FIT_MARGIN
	label.custom_minimum_size.x = maxf(label.custom_minimum_size.x, need)
	_apply_size(label, floor_size, base, p_base > 0)
	return floor_size


static func _apply_size(label: Label, size: int, base: int, pinned: bool) -> void:
	if size != base or pinned:
		label.add_theme_font_size_override(&"font_size", size)


## The widest LINE of a (possibly "\n"-split) print at one size.
static func _line_width(font: Font, text: String, size: int) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
	return widest


## The widest WORD of a print at one size (the wrap-atomic unit).
static func _word_width(font: Font, text: String, size: int) -> float:
	var widest := 0.0
	for line in text.split("\n"):
		for word in line.split(" "):
			widest = maxf(widest,
				font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x)
	return widest
