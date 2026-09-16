## CardFrame — the theme grammar's frame component (T-UI-01).
##
## A cheap print-block card: flat paper quad with a chamfered cut, an ink
## border carrying STATE BY LINE FORM (solid ready / dashed in progress /
## struck lost — the design brief's first kept raise, colorblind-safe by
## construction because form, never hue, encodes state), a regime-secondary
## inner hairline (data-driven recolor), a red corner seal, and a seeded
## misprint (small rotation + registration offset — the world's "deliberate
## misprint for comedy", deterministic per seed).
##
## NO gold trim, NO gradients, NO rounded-luxe corners: the chamfer is cut
## paper. Everything is drawn with CanvasItem primitives (R6 option C:
## texture-free, resolution-independent, antialiased) — draw_polygon /
## draw_polyline / draw_line / draw_dashed_line.
##
## Focus (controller nav, Daredevil parity): a focused frame re-prints its
## border offset in revolution red — a second ink pass that missed
## registration, readable without hover and without color dependence (the
## offset form itself is the focus mark).
##
## Content (CardFace et al.) is composed as children; the frame reserves
## FRAME_INSET + edge width around the rect for the print. Minimum size
## honors the touch grip (>= 48 design units, PRODUCT.md accessibility).
extends Control

## The card's state edge line form. Set from sim state via
## Inks.edge_form_for_state().
@export var edge_form: Inks.EdgeForm = Inks.EdgeForm.SOLID:
	set(value):
		if edge_form != value:
			edge_form = value
			queue_redraw()

## Regime flavor id — tints the inner hairline with the regime's second
## ink (data-driven; &"" = neutral ink-soft).
@export var regime_id: StringName = &"":
	set(value):
		if regime_id != value:
			regime_id = value
			queue_redraw()

## Misprint seed — 0 disables (a clean print; used for chrome cards where
## wobble would read as noise). Deterministic per seed (Inks FNV-1a).
@export var misprint_seed: int = 0:
	set(value):
		if misprint_seed != value:
			misprint_seed = value
			queue_redraw()

## Print the red corner seal (the deck's stamp dot). Off for plate-only
## frames (e.g. the chronicle's paper strips).
@export var show_seal: bool = true:
	set(value):
		if show_seal != value:
			show_seal = value
			queue_redraw()


func _get_minimum_size() -> Vector2:
	## The touch grip floor: a card can never shrink below 2x grip
	## (96x96 design units) even before its parent slots give it aspect.
	return Vector2.ONE * (Inks.TOUCH_GRIP_MIN * 2.0)


func _draw() -> void:
	var grip_ok := size.x >= Inks.TOUCH_GRIP_MIN and size.y >= Inks.TOUCH_GRIP_MIN
	if not grip_ok:
		return  # never print a frame too small to grip
	var mp := Inks.misprint_params(misprint_seed) if misprint_seed != 0 else {"rotation_deg": 0.0, "offset": Vector2.ZERO}
	var outer := _chamfered_quad(Rect2(Vector2.ZERO, size).grow(-Inks.FRAME_INSET), Inks.FRAME_CHAMFER, mp)
	var inner := _chamfered_quad(Rect2(Vector2.ZERO, size).grow(-(Inks.FRAME_INSET + Inks.EDGE_WIDTH + 4.0)), maxf(2.0, Inks.FRAME_CHAMFER - 4.0), mp)

	# Focus ghost FIRST (behind the paper): a second ink pass that missed
	# registration — the frame's focus ring in the world's own grammar.
	if has_focus():
		var ghost := PackedVector2Array()
		ghost.resize(outer.size())
		for i in outer.size():
			ghost[i] = outer[i] + Vector2(3.5, 2.5)
		_draw_closed_path(ghost, Inks.RED, Inks.EDGE_WIDTH)

	# Paper — the card is the world's light source: flat, bright, ungradiented.
	draw_colored_polygon(outer, Inks.PAPER)

	# Inner hairline — the regime's second ink (data-driven recolor).
	var secondary := Inks.regime_secondary(regime_id) if regime_id != &"" else Inks.INK_SOFT
	draw_polyline(inner, secondary, 1.5, true)

	# The state edge — LINE FORM carries state, never hue. Always the ink.
	match edge_form:
		Inks.EdgeForm.SOLID:
			_draw_closed_path(outer, Inks.INK, Inks.EDGE_WIDTH)
		Inks.EdgeForm.DASHED:
			_draw_dashed_frame(outer, Inks.INK, Inks.EDGE_WIDTH)
		Inks.EdgeForm.STRUCK:
			_draw_closed_path(outer, Inks.INK, Inks.EDGE_WIDTH * 0.5)
			_draw_strike(mp)

	# Corner seal — revolution red, the press's stamp.
	if show_seal:
		var seal_center := _xform(Vector2(Inks.FRAME_INSET + 12.0, Inks.FRAME_INSET + 12.0), size * 0.5, mp)
		draw_rect(Rect2(seal_center - Vector2(4, 4), Vector2(8, 8)), Inks.RED)


# --- print-path helpers ------------------------------------------------------------


func _chamfered_quad(rect: Rect2, chamfer: float, mp: Dictionary) -> PackedVector2Array:
	## An 8-point cut-paper quad (clockwise from the top edge), then the
	## misprint transform (rotate about center + registration offset).
	var c: float = minf(minf(chamfer, rect.size.x * 0.25), rect.size.y * 0.25)
	var pts := PackedVector2Array([
		rect.position + Vector2(c, 0),
		rect.position + Vector2(rect.size.x - c, 0),
		rect.position + Vector2(rect.size.x, c),
		rect.position + Vector2(rect.size.x, rect.size.y - c),
		rect.position + Vector2(rect.size.x - c, rect.size.y),
		rect.position + Vector2(c, rect.size.y),
		rect.position + Vector2(0, rect.size.y - c),
		rect.position + Vector2(0, c),
	])
	var center := rect.get_center()
	for i in pts.size():
		pts[i] = _xform(pts[i], center, mp)
	return pts


func _xform(p: Vector2, center: Vector2, mp: Dictionary) -> Vector2:
	## Misprint transform: rotate about the card center, then offset.
	var rotated := (p - center).rotated(deg_to_rad(float(mp.rotation_deg))) + center
	return rotated + Vector2(mp.offset)


func _draw_closed_path(pts: PackedVector2Array, color: Color, width: float) -> void:
	## Draw_polyline over a closed chamfered path (antialiased).
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, color, width, true)


func _draw_dashed_frame(pts: PackedVector2Array, color: Color, width: float) -> void:
	## The in-progress form: the four long edges print dashed (dash/gap
	## rhythm from the grammar constants); the four chamfers stay solid —
	## the paper is still cut, only the ink runs out along the run.
	for i in pts.size():
		var next := (i + 1) % pts.size()
		var is_long_edge := i % 2 == 0  # pts 0-1, 2-3, 4-5, 6-7 are the long edges
		if is_long_edge:
			_draw_dashed_line(pts[i], pts[next], color, width)
		else:
			draw_line(pts[i], pts[next], color, width, true)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	## Custom dash rhythm (draw_dashed_line's engine gap is fixed == dash
	## length; the grammar wants an explicit longer gap so the form reads
	## at card scale).
	var dir := (to - from)
	var length := dir.length()
	if length <= 0.0:
		return
	dir /= length
	var t := 0.0
	while t < length:
		var dash_end := minf(t + Inks.EDGE_DASH, length)
		draw_line(from + dir * t, from + dir * dash_end, color, width, true)
		t += Inks.EDGE_DASH + Inks.EDGE_DASH_GAP


func _draw_strike(mp: Dictionary) -> void:
	## The lost form: a bold diagonal strike across the card, corner to
	## corner with a misprint jitter — a body struck from the ledger.
	var center := size * 0.5
	var reach := Vector2(size.x * 0.40, size.y * 0.40)
	var jitter := Vector2(float((int(center.x) % 7) - 3) * 0.5, 0.0)
	var a := _xform(center - reach + jitter, center, mp)
	var b := _xform(center + reach + jitter, center, mp)
	draw_line(a, b, Inks.INK, Inks.STRIKE_WIDTH, true)
