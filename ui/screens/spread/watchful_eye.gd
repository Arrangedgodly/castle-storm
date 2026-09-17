## WatchfulEye — the Crown's card creeping into the spread (T-UI-03).
##
## The design brief's signature tension visual: suspicion is not a bar, it
## is a CARD — the Watchful Eye entering the spread's periphery as the
## meter rises. The presenter's pure eye_metrics drives everything:
##   POSITION — inset 0..1 slides the card in from its right-edge perch
##     toward the table's heart (the screen positions this control);
##   LINE FORM — the frame's edge prints solid (watching) / dashed
##     (closing) / struck (the telegraph is armed: the verdict is being
##     printed) — readable without color AND without position, the
##     Daredevil floor doubled;
##   DREAD — scale and ink coverage rise with the meter;
##   COUNTDOWN — an armed telegraph prints its landing hours on the plate.
## The card is deliberately NOT focusable/interactive here — T-UI-06
## (suspicion events as choice cards) owns its interaction.
##
## THE ARMED PLATE (finishing refinement #3, the closing critique's P2:
## the armed state was low-salience — a 19px countdown on a periphery
## stub, and the perch crowded the fan's end card): when the telegraph
## arms, the Eye GROWS to a full plate (ARMED_CARD_MIN), the countdown
## escalates from one quiet role line to the world's numeral-plate grammar
## — the choice card's own urgent vocabulary: a DOUBLE REVOLUTION-RED
## rule, a small red caption ("lands in") and the landing hours as the
## plate's largest mark (form + position + SIZE, never hue alone). The
## table itself makes way: the screen reserves the armed lane
## (armed_lane) so the card field never crowds the seat. The RESTING
## creep is untouched — unarmed binds are exactly the authored quiet
## forms (the creep is the design; only the armed state is loud).
extends Control

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

## The armed plate's minimum (design units): a real card at phone scale,
## not a periphery stub — the countdown must read from across the table.
const ARMED_CARD_MIN := Vector2(Inks.TOUCH_GRIP_MIN * 3.0, Inks.TOUCH_GRIP_MIN * 4.2)
## The armed seat's margin box inside the table's right edge (8 each
## side) — the width the LANDED seat occupies against the slot's right
## edge; the fan's rotation swing joins it where cards rotate (landscape).
const ARMED_SEAT_MARGIN := 8.0
## The armed caption's font size (base; TypeScale-carried) and the armed
## numeral's — the plate's largest mark. The ACCENT BUDGET (the brief's
## red-carries-30-60%-of-accents commitment, measured on the armed
## capture): the hours print IN INK at numeral-plate size — the SIZE is
## the escalation, exactly the pip numerals' grammar (red carries the
## countdown TEXT and the rule, not the big mark; salience never leans on
## hue alone).
const ARMED_CAPTION_SIZE := 17
const ARMED_NUMERAL_SIZE := 40
## The armed rule's width: a short centered stamp, not a banner (the
## double form is the urgent signature; the plate stays inside the accent
## budget).
const ARMED_RULE_WIDTH := 64.0
## The strike wash prints past the card onto the ground around it (the
## closing critique's "wider strike wash"): the wash rect is the card
## rect grown to this multiple, centered — one inked impression wider
## than the plate that made it.
const WASH_EXTENT := 2.2

var _frame: Control
var _pupil: Control
var _countdown: Label
var _numeral: Label
var _rule: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The strike wash (T-UI-06): a translucent red pass around the whole
	# card while the strike pulse plays — an inked impression, not a glow.
	# A SIBLING below the frame (not a child inside it) so it can print
	# PAST the card onto the ground — wider than the plate (WASH_EXTENT).
	_wash = ColorRect.new()
	_wash.color = Color(Inks.RED_CANDLE, 0.0)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wash)

	_frame = FRAME_SCENE.instantiate() as Control
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.set("show_seal", false)  # the red seal is the revolution's stamp, not the Crown's
	_frame.focus_mode = Control.FOCUS_NONE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	var plate := MarginContainer.new()
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.offset_left = 14.0
	plate.offset_top = 12.0
	plate.offset_right = -14.0
	plate.offset_bottom = -12.0
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(plate)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)

	_pupil = EyeGlyph.new()
	_pupil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pupil.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_pupil)

	# THE ARMED PLATE (finishing refinement #3): the choice card's urgent
	# vocabulary on the Eye itself — the DOUBLE red rule leading a small
	# red caption and the landing hours as the plate's largest mark, in
	# INK (the numeral-plate grammar — size carries the escalation, never
	# hue alone). Hidden at rest (the quiet creep carries no red).
	_rule = RULE_SCENE.instantiate()
	_rule.set("form", 3)  # RuleMark.RuleForm.DOUBLE
	_rule.set("rule_ink", Inks.RED)
	_rule.custom_minimum_size = Vector2(ARMED_RULE_WIDTH, 22.0)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.visible = false
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_rule)

	_countdown = Label.new()
	_countdown.theme_type_variation = &"RoleLine"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_countdown)

	_numeral = Label.new()
	_numeral.theme_type_variation = &"Numerals"
	_numeral.add_theme_font_size_override("font_size", TypeScale.scaled(ARMED_NUMERAL_SIZE))
	_numeral.add_theme_color_override("font_color", Inks.INK)
	_numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numeral.visible = false
	column.add_child(_numeral)


func _get_minimum_size() -> Vector2:
	## The Eye keeps a full card's grip floor — it must read at phone
	## scale even while it crouches at the periphery.
	return Vector2(Inks.TOUCH_GRIP_MIN * 1.6, Inks.TOUCH_GRIP_MIN * 2.0)


## Bind the presenter's eye_metrics dict (see SpreadPresenter.eye_metrics).
func bind(metrics: Dictionary, hours_left: int) -> void:
	if _frame == null:
		return
	visible = bool(metrics["visible"])
	_frame.set("edge_form", int(metrics["edge_form"]))
	var scale_value: float = metrics["scale"]
	_base_scale = scale_value
	pivot_offset = size * 0.5
	scale = Vector2.ONE * scale_value
	(_pupil as EyeGlyph).dread = float(metrics["dread"])
	var armed := bool(metrics["armed"]) and hours_left >= 0
	if armed:
		# THE ARMED PLATE: full-size card + the numeral countdown under the
		# double red rule (the choice card's urgent vocabulary — the state
		# carried by form and SIZE, not hue alone).
		custom_minimum_size = ARMED_CARD_MIN
		_countdown.text = "lands in"
		_countdown.add_theme_font_size_override("font_size", TypeScale.scaled(ARMED_CAPTION_SIZE))
		_countdown.add_theme_color_override("font_color", Inks.RED)
		_numeral.text = "%dh" % hours_left
		_numeral.visible = true
		_rule.visible = true
	else:
		# The resting creep, EXACTLY as authored: periphery stub, one quiet
		# role line, no red on the plate (the creep is the design).
		custom_minimum_size = Vector2.ZERO
		_countdown.remove_theme_font_size_override("font_size")
		var share := int(round(float(metrics["points"]) / float(maxi(1, int(metrics["max_points"]))) * 100.0))
		_countdown.text = "the Crown watches — %d" % share
		_countdown.add_theme_color_override("font_color", Inks.INK_SOFT)
		_numeral.visible = false
		_rule.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_wash()


## The wash rect for a card rect: grown to WASH_EXTENT, centered — pure
## (the strike's ground footprint; test-pinned).
static func wash_rect(card_rect: Rect2) -> Rect2:
	var size := card_rect.size * WASH_EXTENT
	return Rect2(card_rect.get_center() - size * 0.5, size)


func _layout_wash() -> void:
	## Keep the wider wash centered on the card through growth and pulses,
	## CLAMPED to the table (the slot's rect) — ink never prints past the
	## table's edge, and no control rect leaves the design bounds.
	if _wash == null:
		return
	var extent: Rect2 = wash_rect(Rect2(Vector2.ZERO, size))
	var table := get_parent_control()
	if table != null:
		extent = extent.intersection(Rect2(-position, table.size))
	_wash.position = extent.position
	_wash.size = extent.size


# --- the strike / retreat pulses (T-UI-06) -------------------------------------------
#
# THE EYE STRIKES when a telegraph lands (and at the crush): a scale
# punch + a red ink wash WIDER than the card (it prints past the plate
# onto the ground — WASH_EXTENT), one printed impression. THE EYE
# RETREATS on relief (the telegraph cancelled — the riders stood down):
# a flinch-scale pulse while the state-driven inset slides it back to
# its perch. Both are PURE functions of t (test-pinned); the tween only
# advances t.

## The pulse progress 0..1 (rests at 1; a pulse plays 0 -> 1).
var strike_t := 1.0:
	set(value):
		strike_t = clampf(value, 0.0, 1.0)
		_apply_pulse()

## The retreat pulse progress (same shape).
var retreat_t := 1.0:
	set(value):
		retreat_t = clampf(value, 0.0, 1.0)
		_apply_pulse()

## The meter-driven scale from the last bind (the pulse multiplies it).
var _base_scale := 1.0
var _wash: ColorRect

## Authored pulse pacing (MotionProfile-routed: reduced motion skips the
## flourish entirely — the blockquote carries the event).
const STRIKE_SECONDS := 0.55
const RETREAT_SECONDS := 0.45

## Instrumentation (the screen's stats mirror reads these).
var strikes_played := 0
var retreats_played := 0


## The strike's render params at t: a rising-falling scale punch (peak
## 1.18x at the middle) and a red wash that peaks with it. Pure.
static func strike_params(t: float) -> Dictionary:
	var bell := sin(PI * clampf(t, 0.0, 1.0))
	return {"scale_mult": 1.0 + 0.18 * bell, "wash": 0.38 * bell}


# --- the armed seat (finishing refinement #3 — pure, test-pinned) ----------------------
#
# When the telegraph arms, the Eye COMMITS to a dedicated seat deep in the
# table's right lane: the card field reserves the lane (CardSpread's
# right_reserve), so the armed plate never crowds the fan's end card. The
# seat's left edge sits ARMED_SEAT_MARGIN inside the table — DEEPER than
# the resting perch (which hugs the outer edge) — the inset slide made
# honest by the table itself making way.


## The width against the SLOT's right edge the armed seat owns: the plate
## plus its margin box, plus the fan's rotation swing where cards rotate
## (the landscape fan's end-card corners swing past their rects by up to
## CardSpread.ROTATION_SLACK — the lane absorbs it so nothing crosses).
static func armed_lane(portrait: bool) -> float:
	return ARMED_CARD_MIN.x + 2.0 * ARMED_SEAT_MARGIN \
		+ (0.0 if portrait else CardSpread.ROTATION_SLACK)


## The armed seat's top-left position: centered in the reserved lane
## (8 in from the slot's right edge — deeper than the perch), vertically
## centered in the spread band under the perch's own clamp. Pure. The
## UNARMED placement stays the screen's authored perch formula (untouched
## by this refinement).
static func armed_seat(slot_rect: Rect2, spread_rect: Rect2,
		card_size: Vector2, portrait: bool) -> Vector2:
	var lane := armed_lane(portrait)
	var x := slot_rect.end.x - lane + (lane - card_size.x) * 0.5
	var y := clampf(spread_rect.get_center().y - card_size.y * 0.5,
		slot_rect.position.y + 4.0, slot_rect.end.y - card_size.y - 4.0)
	return Vector2(x, y)


## The retreat's render params at t: a dip (0.88x at the middle) — the
## eye flinches back toward its perch. Pure.
static func retreat_params(t: float) -> Dictionary:
	var bell := sin(PI * clampf(t, 0.0, 1.0))
	return {"scale_mult": 1.0 - 0.12 * bell, "wash": 0.0}


func play_strike() -> void:
	strikes_played += 1
	var duration := MotionProfile.duration(STRIKE_SECONDS)
	if duration <= 0.05:
		strike_t = 1.0
		return
	strike_t = 0.0
	var tween := create_tween()
	tween.tween_property(self, "strike_t", 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func play_retreat() -> void:
	retreats_played += 1
	var duration := MotionProfile.duration(RETREAT_SECONDS)
	if duration <= 0.05:
		retreat_t = 1.0
		return
	retreat_t = 0.0
	var tween := create_tween()
	tween.tween_property(self, "retreat_t", 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Compose the pulses with the bound scale (the last pulse to move wins
## the multiplier — they never co-occur in practice: a strike ends runs
## and windows, a retreat follows a cancel).
func _apply_pulse() -> void:
	if _frame == null or _wash == null:
		return
	var strike_p := strike_params(strike_t)
	var retreat_p := retreat_params(retreat_t)
	var mult: float = strike_p["scale_mult"] * retreat_p["scale_mult"]
	pivot_offset = size * 0.5
	scale = Vector2.ONE * _base_scale * mult
	_layout_wash()
	_wash.color = Color(Inks.RED_CANDLE, float(strike_p["wash"]))


## The eye glyph: almond outline + iris, ink on paper, its gaze widening
## (pupil grows, lids close in) as dread rises — a drawn mark, no texture.
class EyeGlyph:
	extends Control

	## 0..1 — how open/reported the eye is (drives pupil + lid coverage).
	var dread: float = 0.5:
		set(value):
			dread = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var w := size.x * 0.5
		var h := size.y * (0.16 + 0.10 * dread)
		var ink := Inks.INK
		# The almond: two arcs meeting at points (lids).
		var pts := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			var t := float(i) / float(steps)
			var x := center.x - w + t * w * 2.0
			# Upper lid.
			var y_u: float = center.y - sin(PI * t) * h
			pts.append(Vector2(x, y_u))
		for i in steps + 1:
			var t := 1.0 - float(i) / float(steps)
			var x := center.x - w + t * w * 2.0
			var y_l: float = center.y + sin(PI * t) * h * 0.9
			pts.append(Vector2(x, y_l))
		draw_polyline(pts, ink, 3.0, true)
		# The iris: a circle that dilates with dread.
		var iris_r: float = (4.0 + 6.0 * dread) * (size.x / 64.0)
		draw_circle(center, iris_r, ink)
		draw_circle(center, iris_r * 0.42, Inks.PAPER)
		# Lashes: radiating ticks above the upper lid — the "watchful" tell.
		var lash_count := 5
		for i in lash_count:
			var t := (float(i) + 0.5) / float(lash_count)
			var x := center.x - w + t * w * 2.0
			var y: float = center.y - sin(PI * t) * h
			var dir := (Vector2(x, y) - center).normalized() if (Vector2(x, y) - center).length() > 0.5 else Vector2.UP
			draw_line(Vector2(x, y), Vector2(x, y) + dir * 7.0, ink, 2.0, true)
