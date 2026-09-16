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
class_name TableGround
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

## THE HALFTONE TILE (T-PERF-02's Deck-profile measurement find): the
## paper grain used to draw ~1,250 `draw_circle` commands PER GROUND
## PER FRAME (the Compatibility renderer re-submits every canvas item
## every frame — a 44x28 dot grid over the 1152x720 design was the
## single biggest draw-call cost on the table, measured 1487 calls /
## 8.8ms mean frame on the M-series host at the Deck window). The same
## grain now bakes ONCE into a one-cell ImageTexture (the grid's jitter
## is applied by PLACEMENT, not baking — one 26x26 tile serves every
## phase and the assault stage's wash drift alike) and covers the ground
## in ONE tiled draw. Same dots, same jitter grammar, same alpha.
static var _dot_tile_cache: ImageTexture


## The shared one-cell grain tile (26x26, one paper-colored dot). The
## grid offset argument documents the placement contract — the tile
## itself is offset-independent.
static func dot_tile_for(_grid_offset: int) -> ImageTexture:
	if _dot_tile_cache == null:
		var cell := int(DOT_SPACING)
		var image := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var center := Vector2(cell, cell) * 0.5
		var dot_color := Color(Inks.PAPER.r, Inks.PAPER.g, Inks.PAPER.b, DOT_ALPHA)
		for y in cell:
			for x in cell:
				if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) <= DOT_RADIUS + 0.45:
					image.set_pixel(x, y, dot_color)
		_dot_tile_cache = ImageTexture.create_from_image(image)
	return _dot_tile_cache

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
	# Halftone: the paper grain, one tiled draw off the shared baked tile.
	# The tile is placed so the grid's origin lands on the phase's own
	# jitter — each phase's grain is its own, exactly as the per-circle
	# grid was.
	var jitter := Vector2(float((phase * 7) % int(DOT_SPACING)), float((phase * 11) % int(DOT_SPACING)))
	draw_texture_rect(dot_tile_for(phase), Rect2(jitter - Vector2.ONE * DOT_SPACING,
		size + Vector2.ONE * (2.0 * DOT_SPACING)), true, Color(1, 1, 1, 1))
