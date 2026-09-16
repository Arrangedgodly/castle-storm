## PipGlyph — one resource pip's drawn mark (T-UI-01).
##
## The colorblind-safe resource notation (PRODUCT.md accessibility:
## "icon + shape + text, never color alone"): each resource's pip is a
## distinct CONTAINER SHAPE (food = circle, timber = square, iron =
## hexagon) carrying a distinct authored GLYPH (grain fan / stacked
## chevrons / anvil), both drawn in ink — color is redundant tertiary
## encoding only, applied to the glyph fill. The PipMark row adds the
## name label + abbreviated amount as the textual channel.
##
## Authored with CanvasItem primitives per R6 option C (in-engine
## grammar, texture-free); the vendored icon packs (Kenney board-game
## icons) remain the upgrade path for richer marks.
extends Control

@export var kind: Inks.ResourceKind = Inks.ResourceKind.FOOD:
	set(value):
		if kind != value:
			kind = value
			queue_redraw()

## Glyph ink: the redundant color channel (PipMark sets it from context).
@export var glyph_ink: Color = Inks.RED:
	set(value):
		if glyph_ink != value:
			glyph_ink = value
			queue_redraw()

const GLYPH_SIZE := 26.0
const CONTAINER_MARGIN := 5.0


func _get_minimum_size() -> Vector2:
	return Vector2.ONE * (Inks.TOUCH_GRIP_MIN - 18.0)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - CONTAINER_MARGIN
	if radius < 4.0:
		return
	# Container: paper fill + ink outline, shape distinct per resource.
	var pts := _container_points(kind, center, radius)
	draw_colored_polygon(pts, Inks.PAPER)
	draw_polyline(_closed(pts), Inks.INK, 3.0, true)
	# Inner glyph: the icon channel, inked in the pip's redundant color.
	draw_set_transform(center, 0.0, Vector2.ONE)
	match kind:
		Inks.ResourceKind.FOOD:
			_draw_grain(glyph_ink)
		Inks.ResourceKind.TIMBER:
			_draw_chevrons(glyph_ink)
		Inks.ResourceKind.IRON:
			_draw_anvil(glyph_ink)
	draw_set_transform(Vector2.ZERO)


func _container_points(kind: Inks.ResourceKind, center: Vector2, radius: float) -> PackedVector2Array:
	## Circle (food) / square (timber) / hexagon (iron) — distinct by
	## construction; tests pin one distinct vertex-count/shape per kind.
	match kind:
		Inks.ResourceKind.FOOD:
			var circle := PackedVector2Array()
			for i in 20:
				var angle := TAU * i / 20.0
				circle.append(center + Vector2(cos(angle), sin(angle)) * radius)
			return circle
		Inks.ResourceKind.TIMBER:
			var half := radius * 0.88
			return PackedVector2Array([
				center + Vector2(-half, -half), center + Vector2(half, -half),
				center + Vector2(half, half), center + Vector2(-half, half),
			])
		_:
			var hexagon := PackedVector2Array()
			for i in 6:
				var angle := TAU * i / 6.0 - PI / 6.0
				hexagon.append(center + Vector2(cos(angle), sin(angle)) * radius)
			return hexagon


# Glyphs draw around the local origin (draw_set_transform centers them).


func _draw_grain(ink: Color) -> void:
	## Food: a grain fan — three strokes off a base point.
	var base := Vector2(0.0, 9.0)
	draw_line(Vector2(0.0, 9.0), Vector2(0.0, -9.0), ink, 2.5, true)
	for angle in [-0.7, 0.7]:
		var tip := base + Vector2(sin(angle) * 11.0, -16.0)
		draw_line(Vector2(0.0, 2.0), tip, ink, 2.5, true)


func _draw_chevrons(ink: Color) -> void:
	## Timber: stacked cut chevrons (tally marks for boards).
	draw_line(Vector2(-8.0, -2.0), Vector2(0.0, -9.0), ink, 3.0, true)
	draw_line(Vector2(0.0, -9.0), Vector2(8.0, -2.0), ink, 3.0, true)
	draw_line(Vector2(-8.0, 7.0), Vector2(0.0, 0.0), ink, 3.0, true)
	draw_line(Vector2(0.0, 0.0), Vector2(8.0, 7.0), ink, 3.0, true)


func _draw_anvil(ink: Color) -> void:
	## Iron: anvil silhouette — body, horn, base.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9.0, -5.0), Vector2(7.0, -5.0), Vector2(9.0, -1.0),
		Vector2(-4.0, -1.0), Vector2(-4.0, 2.0), Vector2(-9.0, 2.0),
	]), ink)
	draw_rect(Rect2(Vector2(-7.0, 4.0), Vector2(14.0, 4.0)), ink)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	return closed
