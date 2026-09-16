## FaceArt — resolves art-manifest face keys into printed face textures
## (T-UI-01 round-2 fix: single-pose atlas crops + the two-ink print).
##
## Round-1 landed whole Kenney Toon Character pose SHEETS (864x640, ~45
## poses per file) straight into FaceSlot, which rendered them uncropped —
## a tiny-sprite grid on the card (the verifier FAIL). This resolver sits
## between the manifest and the slot:
##   1. the manifest entry's `atlas_region` names ONE cell of the rendered
##      sheet (grid math of record in art_asset_def.gd: uniform 9x5 grid
##      of 96x128 px; cell (0,0) = the neutral front-facing standing pose,
##      pixel-probe verified on all three staged sheets), composed here as
##      an AtlasTexture — the slot's final texture IS the crop, never the
##      sheet, and the crop is content data (a content edit re-poses a
##      face with zero UI changes);
##   2. the sheets' ground is fully TRANSPARENT (pixel-probe verified —
##      the round-1 "black plate" was the 45 tiny sprites reading as one
##      dark mass), so the crop composites straight onto the paper card;
##      the two-ink print pass (face_print.gdshader, applied by FaceSlot)
##      maps source luminance to ink coverage so the portrait reads as a
##      cheap-print ink pass: dark lines solid, light areas a thin wash,
##      paper showing through the unprinted stock.
## Entries without a region (single-pose art: icons, crests, the future
## tzunghaor faces) resolve to the whole rendered texture. Pending or
## unknown keys resolve to null — FaceSlot prints its authored placeholder
## (the honest state until the pack lands). Everything is cached per key:
## one sheet texture, one AtlasTexture per face, one shared print material
## for the whole spread.
class_name FaceArt
extends RefCounted

const PRINT_SHADER := preload("res://ui/theme/face_print.gdshader")

static var _texture_cache: Dictionary = {}
static var _print_material: ShaderMaterial


static func print_material() -> ShaderMaterial:
	## The shared two-ink print pass. One ShaderMaterial serves every face
	## slot — its uniforms are palette constants (ink from Inks, the single
	## source the theme equality-tests against).
	if _print_material == null:
		_print_material = ShaderMaterial.new()
		_print_material.shader = PRINT_SHADER
		_print_material.set_shader_parameter("ink_color", Inks.INK)
	return _print_material


static func face_texture(face_key: StringName) -> Texture2D:
	## Resolve a face key through the pack's art manifest to the printed
	## face texture (cached). Returns null when there is nothing honest to
	## show (empty/pending/unknown key, missing render) — the caller
	## prints the authored placeholder instead of guessing.
	if face_key == &"":
		return null
	if _texture_cache.has(face_key):
		return _texture_cache[face_key]
	var pack := Inks.pack()
	if pack == null or pack.art == null:
		return null
	var asset: ArtAssetDef = null
	for entry: ArtAssetDef in pack.art.assets:
		if entry != null and entry.id == face_key:
			asset = entry
			break
	if asset == null:
		push_error("FaceArt.face_texture: face key '%s' not in the art manifest" % face_key)
		return null
	if asset.pending:
		return null
	var rendered := rendered_path(asset.source_path)
	if not FileAccess.file_exists(rendered):
		push_error("FaceArt.face_texture: rendered art '%s' for key '%s' is missing (run make vendor-assets or mark the entry pending)" % [rendered, face_key])
		return null
	var source := load(rendered) as Texture2D
	if source == null:
		push_error("FaceArt.face_texture: cannot load rendered art '%s' for key '%s'" % [rendered, face_key])
		return null
	var face: Texture2D = source
	var region := asset.atlas_region
	if region.size.x > 0.0 and region.size.y > 0.0:
		if not Rect2(Vector2.ZERO, Vector2(source.get_width(), source.get_height())).encloses(region):
			push_error("FaceArt.face_texture: atlas_region %s escapes the rendered sheet '%s' (%dx%d) for key '%s'" % [region, rendered, source.get_width(), source.get_height()])
			return null
		var crop := AtlasTexture.new()
		crop.atlas = source
		crop.region = region
		face = crop
	_texture_cache[face_key] = face
	return face


static func rendered_path(source_path: String) -> String:
	## The vendor pipeline pre-renders staged SVGs to sibling @2x PNGs
	## (foo.svg -> foo@2x.png — scripts/vendor_assets.gd's render step);
	## already-raster sources pass through unchanged.
	if source_path.get_extension() == "svg":
		return source_path.get_basename() + "@2x.png"
	return source_path
