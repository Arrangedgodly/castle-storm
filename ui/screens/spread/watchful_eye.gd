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
extends Control

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")

var _frame: Control
var _pupil: Control
var _countdown: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	_countdown = Label.new()
	_countdown.theme_type_variation = &"RoleLine"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_countdown)


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
	pivot_offset = size * 0.5
	scale = Vector2.ONE * scale_value
	(_pupil as EyeGlyph).dread = float(metrics["dread"])
	if bool(metrics["armed"]) and hours_left >= 0:
		_countdown.text = "lands in %dh" % hours_left
		_countdown.add_theme_color_override("font_color", Inks.RED)
	else:
		var share := int(round(float(metrics["points"]) / float(maxi(1, int(metrics["max_points"]))) * 100.0))
		_countdown.text = "the Crown watches — %d" % share
		_countdown.add_theme_color_override("font_color", Inks.INK_SOFT)


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
