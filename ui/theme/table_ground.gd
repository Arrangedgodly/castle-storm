## TableGround — the spread's ground (T-UI-01).
##
## The phase-deepening raise (design brief's 4th kept raise): the table's
## ground tone deepens through run phases (recruiting -> training ->
## ready-to-storm) so ambient progress reads before any number; aftermath
## washes cold and light — the morning after the storm. Tones are
## data-driven: Inks.ground_for blends the regime's first ink
## (RegimeDef.ink_ground) with the phase depth — a regime swap recolors
## the table by content, never by code.
##
## The surface is a flat print world: one solid tone plus a whisper of
## halftone dots (the cheap-paper texture, drawn procedurally — no
## gradients, no luxe finishes; the dots are the paper's grain, not a
## decoration layer).
extends Control

## Regime flavor id tinting the ground (&"" = neutral).
@export var regime_id: StringName = &"":
	set(value):
		if regime_id != value:
			regime_id = value
			queue_redraw()

## Run phase (Inks.Phase).
@export var phase: Inks.Phase = Inks.Phase.RECRUITING:
	set(value):
		if phase != value:
			phase = value
			queue_redraw()

## Halftone spacing in design units (deterministic grid, phase-jittered).
const DOT_SPACING := 26.0
const DOT_RADIUS := 1.15
const DOT_ALPHA := 0.055

## The aftermath flash (T-UI-06): when a crackdown lands the ground
## flashes cold aftermath ink for a beat — the morning-after wash paid as
## an instant of light, then the phase tone returns. 0 = no flash (the
## default; renders EXACTLY as before).
@export var flash: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if flash != clamped:
			flash = clamped
			queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2.ONE * Inks.TOUCH_GRIP_MIN


## The flashed ground color: the base tone lerped toward cold ash. Pure —
## tests pin the mapping; _draw only consumes it.
static func flash_color(base: Color, flash: float) -> Color:
	return base.lerp(Inks.ASH, clampf(flash, 0.0, 1.0) * 0.55)


func _draw() -> void:
	var ground := flash_color(Inks.ground_for(regime_id, phase), flash)
	draw_rect(Rect2(Vector2.ZERO, size), ground)
	# Halftone: the paper grain. A light paper-colored dot grid, offset
	# deterministically per phase so each phase's grain is its own.
	var jitter := Vector2(float((phase * 7) % int(DOT_SPACING)), float((phase * 11) % int(DOT_SPACING)))
	var dot_color := Color(Inks.PAPER.r, Inks.PAPER.g, Inks.PAPER.b, DOT_ALPHA)
	var y := jitter.y - DOT_SPACING
	while y < size.y + DOT_SPACING:
		var x := jitter.x - DOT_SPACING
		while x < size.x + DOT_SPACING:
			draw_circle(Vector2(x, y), DOT_RADIUS, dot_color)
			x += DOT_SPACING
		y += DOT_SPACING
