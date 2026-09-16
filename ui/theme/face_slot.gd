## FaceSlot — the card's face-art plate (T-UI-01).
##
## Holds vendored face art when the art manifest has landed a face for
## the unit (R6: pack faces recolored/composed into the two-ink world —
## the frame dominates perception), and prints an authored placeholder
## when it has not (knight/archer faces are pending vendoring): a flat
## silhouette mark — circle head, shoulders block — in ink on paper,
## honestly generic rather than falsely rich. Placeholder and art share
## one slot contract, so landing art is a key swap with zero layout
## change.
##
## ROUND-2 (verifier fix): landed art arrives as a SINGLE CROPPED POSE —
## an AtlasTexture over the vendor pose sheet, region = the manifest
## entry's atlas_region, resolved by FaceArt (round-1 rendered whole
## 864x640 45-pose sheets uncropped; this slot now structurally cannot
## repeat that — its texture IS the crop). The crop prints through the
## two-ink pass (face_print.gdshader: source luminance -> ink coverage,
## transparent ground preserved), so the face reads as a cheap-print
## portrait on the paper stock — no colored plate, no black plate.
extends TextureRect

## Placeholder mark scale (fraction of the slot's short side).
const MARK_FRACTION := 0.55

## Art-manifest face key (e.g. &"face_peasant"). Resolved through FaceArt
## on set: landed entries become cropped single-pose atlas prints; empty
## or pending keys clear the texture so the authored placeholder draws.
@export var face_key: StringName = &"":
	set(value):
		if face_key == value:
			return
		face_key = value
		_apply_face()


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_face() -> void:
	## Landed art: the single-cell atlas through the two-ink print pass.
	## Anything else: bare slot + the placeholder mark below (never the
	## print material over a drawn mark — the shader is for art only).
	texture = FaceArt.face_texture(face_key)
	material = FaceArt.print_material() if texture != null else null


func _draw() -> void:
	## Only prints when there is no art: the drawn silhouette stands in
	## for the face, never decorates over one.
	if texture != null:
		return
	var center := size * 0.5
	var scale_unit := minf(size.x, size.y) * MARK_FRACTION
	# Head.
	draw_circle(center + Vector2(0, -scale_unit * 0.22), scale_unit * 0.24, Inks.INK_SOFT)
	# Shoulders: a flat trapezoid block.
	var shoulder_top := center.y + scale_unit * 0.06
	var shoulder_bottom := center.y + scale_unit * 0.5
	var half_top := scale_unit * 0.26
	var half_bottom := scale_unit * 0.46
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x - half_top, shoulder_top),
		Vector2(center.x + half_top, shoulder_top),
		Vector2(center.x + half_bottom, shoulder_bottom),
		Vector2(center.x - half_bottom, shoulder_bottom),
	]), Inks.INK_SOFT)
	# A thin paper rule under the mark — the plate's resting line.
	draw_line(Vector2(center.x - scale_unit * 0.5, shoulder_bottom + 6.0),
		Vector2(center.x + scale_unit * 0.5, shoulder_bottom + 6.0), Inks.INK_SOFT, 1.5, true)
