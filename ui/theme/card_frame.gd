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
## FLIP SEAM (the promotion flip): flip_to()/set_face_up()/
## is_face_up() + flip_started/flip_completed — the explicit contract the
## card-turn animation mounts on (pivot = center; the back face is the
## paper stock itself). Full contract documented at flip_to(). T-UI-04's
## AUTHORED turn lives here too: play_promotion_flip() — the scale-x
## squeeze about the center pivot, the content swap at the 90-degree
## crossing, and the landing flourish (see play_promotion_flip).
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

# --- the flip seam (the promotion flip — the design brief's signature
# --- interaction; T-UI-04 owns the animation, this is the contract) ---------------

## Emitted when a flip STARTS; carries the side the card will land on.
signal flip_started(face_up: bool)
## Emitted when the flip COMPLETES; the card now shows that side.
signal flip_completed(face_up: bool)

## True while the card shows its FACE (content children); false = the BACK
## (the paper stock itself: same quad, state edge and seal — a cheap deck's
## unprinted side needs no second scene).
@export var face_up: bool = true:
	set(value):
		set_face_up(value)
	get:
		return _face_up

## Content children this frame hid for the back side (restored on return).
var _hidden_by_flip: Array[CanvasItem] = []
var _face_up := true


## THE FLIP SEAM for T-UI-04. Contract every consumer may rely on:
##   - flip_to(up) on the other side fires flip_started(up), swaps the
##     shown side, then fires flip_completed(up) — exactly once per flip;
##     a request for the side already shown is a silent no-op;
##   - the BASE grammar performs the flip INSTANTLY (a print laid on the
##     table does not animate) and hides the frame's content children on
##     the back, restoring them (with their prior visibility) on return —
##     so after flip_completed the card genuinely shows the requested side;
##   - T-UI-04's promotion-flip animation interposes on this seam: turn
##     THIS node (pivot_offset = size * 0.5 is the turn axis; rotation or
##     an x-scale squeeze both read as a card turn), call set_face_up() at
##     the 90-degree crossing (where neither side shows — the silent swap
##     helper), swap/rebuild the content between flip_started and the
##     crossing (trainee plates out, knight plates in), and emit the same
##     two signals around the tween. One contract, one grammar.
func flip_to(up: bool) -> void:
	if up == _face_up:
		return
	flip_started.emit(up)
	set_face_up(up)
	flip_completed.emit(up)


## Instant, SILENT side swap — the 90-degree-crossing helper an animation
## calls mid-turn. Use flip_to() for the announced contract.
func set_face_up(up: bool) -> void:
	if up == _face_up:
		return
	_face_up = up
	if up:
		for child in _hidden_by_flip:
			if is_instance_valid(child):
				child.visible = true
		_hidden_by_flip.clear()
	else:
		for child in get_children():
			if child is CanvasItem and child.visible:
				_hidden_by_flip.append(child)
				child.visible = false
	queue_redraw()


func is_face_up() -> bool:
	return _face_up


# --- the authored promotion flip (T-UI-04 — the signature interaction) --------

## Transient landing flourish 0..1: a printed DOUBLE rule in revolution
## red inside the regime hairline, fading like a press impression lifting
## (driven by _stamp_flourish after a promotion flip lands — the world's
## grammar, never particle sparkle).
var flourish := 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if flourish != clamped:
			flourish = clamped
			queue_redraw()

var _flip_tween: Tween
var _flip_pending_swap := Callable()
var _flip_swapped := false
var _flip_crossed := false


## THE PROMOTION FLIP — the authored card turn on the T-UI-01 seam (design
## brief §3: "turning a trainee card over to reveal its Knight face ... the
## one the game is remembered by").
##
## The turn is authored as a 3D-ish scale-x squeeze about the center pivot
## (the T-UI-01 contract's documented turn axis), in contract order:
##   1. flip_started(true) fires;
##   2. scale.x sweeps 1 -> 0 (QUAD in: the card tips away);
##   3. at the 90-degree crossing (scale.x == 0, where neither side shows)
##      the frame goes to its BACK via the silent set_face_up(false) and
##      `swap` re-prints the hidden plates EXACTLY ONCE (trainee out,
##      knight in);
##   4. the return sweep 0 -> 1 (BACK out: one registration overshoot —
##      the card settles past true and comes back, the misprint character
##      in motion) reveals the new face via set_face_up(true);
##   5. the landing stamps the flourish and flip_completed(true) fires.
##
## Reduced motion (MotionProfile): near-instant — same signals, same swap
## order, same end state; the flip still reads as a turn, never a hard cut.
## A flip already in flight is SNAP-FINISHED first, in contract order (its
## swap runs, its flip_completed fires) — one flip at a time on a card, and
## every started flip completes exactly once.
func play_promotion_flip(swap: Callable) -> void:
	flip_started.emit(true)
	_snap_finish_flip()
	_flip_pending_swap = swap
	_flip_swapped = false
	_flip_crossed = false
	var duration := MotionProfile.duration(MotionProfile.FLIP_SECONDS)
	if duration <= 0.05:
		_run_crossing()
		_land_flip()
		return
	pivot_offset = size * 0.5
	var away := duration * 0.42
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.0, away) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(_run_crossing)
	_flip_tween.tween_callback(func() -> void:
		set_face_up(true))  # coming off the crossing: the new face reveals
	_flip_tween.tween_property(self, "scale:x", 1.0, duration - away) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_land_flip)


## The 90-degree crossing: neither side shows — back face, then the ONE
## content swap between flip_started and the reveal.
func _run_crossing() -> void:
	set_face_up(false)
	_flip_crossed = true
	if not _flip_swapped:
		_flip_swapped = true
		_flip_pending_swap.call()


## The landing: reveal, stamp the flourish, complete the contract.
func _land_flip() -> void:
	scale = Vector2.ONE
	set_face_up(true)
	_flip_pending_swap = Callable()
	_stamp_flourish()
	flip_completed.emit(true)


## Finish an in-flight flip synchronously (a new flip or tree exit demands
## a settled card): run the crossing if it had not happened, then land.
func _snap_finish_flip() -> void:
	if _flip_tween != null and _flip_tween.is_valid() and _flip_tween.is_running():
		_flip_tween.kill()
		if not _flip_swapped:
			_run_crossing()
		_land_flip()
	elif not _flip_swapped and _flip_pending_swap.is_valid():
		# Reduced-mode flip interrupted between start and crossing.
		_run_crossing()
		_land_flip()
	scale = Vector2.ONE


## True while an authored flip is mid-turn (the squeeze is in flight).
func is_flipping() -> bool:
	return _flip_tween != null and _flip_tween.is_valid() and _flip_tween.is_running()


## True once the in-flight flip has crossed its 90-degree point (the new
## face is being revealed) — the capture hook's mid-reveal probe.
func flip_crossed() -> bool:
	return _flip_crossed


## The landing's ink burst: a fresh press impression in revolution red,
## fading over the flourish window. Reduced motion prints nothing (the
## flourish is pure celebration; the reveal already landed).
func _stamp_flourish() -> void:
	var duration := MotionProfile.duration(MotionProfile.FLOURISH_SECONDS)
	if duration <= 0.05:
		flourish = 0.0
		return
	flourish = 1.0
	var tween := create_tween()
	tween.tween_property(self, "flourish", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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

	# The promotion flourish — the flip's landing ink: a DOUBLE rule in
	# revolution red inside the hairline (the chronicle's own victory
	# flourish, reprinted on the card), fading like a press impression
	# lifting. A second ink pass, never particles.
	if flourish > 0.01:
		var burst := Color(Inks.RED, flourish)
		var rule := PackedVector2Array()
		rule.resize(inner.size())
		for i in inner.size():
			rule[i] = inner[i] + Vector2(0.0, -4.5)
		_draw_closed_path(rule, burst, 2.0)
		for i in inner.size():
			rule[i] = inner[i] + Vector2(0.0, 4.5)
		_draw_closed_path(rule, burst, 2.0)

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
