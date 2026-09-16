## Vendor asset pipeline tests (T-ARCH-04).
##
## Proves the pipeline end-to-end against the REAL staged tree (not fixtures):
##   1. ART MANIFEST ON DISK — every non-pending MVP art entry's source_path
##      exists with a sibling @2x PNG (the validator's path-existence check is
##      the gate; these tests prove the staged bytes behind it).
##   2. RENDER EXACTNESS — every staged SVG's @2x PNG decodes and matches
##      natural size x the manifest's render scale (2.0 global; per-pack
##      overrides like the Kenney characters are honored), with actual ink
##      (non-transparent pixels) — a silently empty render cannot pass.
##   3. ATTRIBUTIONS — assets/vendor/ATTRIBUTIONS.md carries every CC-BY
##      artist/license/link (R6's credits requirement) plus CC0 provenance
##      and the pending packs.
##   4. ONE REAL ASSET VERTICALLY — icon_smithy (game-icons.net anvil,
##      CC-BY): manifest key -> staged SVG -> @2x decode -> attribution line.
##
## Pending entries are tolerated (the T-UI-01 incremental-landing hatch) but
## never silently: test 1 pins the current staged floor (>= 13) so a deleted
## vendor file fails here, not at art review.
extends GdUnitTestSuite

const PACK_PATH := "res://content/mvp/pack.tres"
const VENDOR_MANIFEST_PATH := "res://assets/vendor/manifest.json"
const ATTRIBUTIONS_PATH := "res://assets/vendor/ATTRIBUTIONS.md"

## Keys that MUST be staged for real (the T-ARCH-04 landed set: 3 Kenney
## faces, 3 Kenney building icons, 7 game-icons CC-BY icons).
const MUST_BE_STAGED: Array[StringName] = [
	&"face_peasant", &"face_worker", &"face_trainee",
	&"icon_farm", &"icon_lumber_camp", &"icon_training_grounds",
	&"icon_smithy", &"icon_sword", &"icon_longsword", &"icon_greatsword",
	&"icon_padded", &"icon_riveted", &"icon_plate",
]


func _art() -> ArtManifest:
	var pack := ContentValidator.load_pack(PACK_PATH)
	assert_that(pack).is_not_null()
	if pack == null:
		return null
	return pack.art


func _by_id(manifest: ArtManifest) -> Dictionary:
	var map := {}
	for asset: ArtAssetDef in manifest.assets:
		map[asset.id] = asset
	return map


func _vendor_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(VENDOR_MANIFEST_PATH)
	assert_that(text).is_not_empty()
	return JSON.parse_string(text) as Dictionary


## Longest-prefix pack lookup: source_path -> { "scale": float } per the
## vendor manifest's render config (global render.scale, per-pack overrides).
func _render_scale_for(path: String, vendor: Dictionary) -> float:
	var best_dir := ""
	var best_scale := float(vendor.get("render", {}).get("scale", 2.0))
	for pack: Dictionary in vendor.get("packs", []):
		var dir := "res://%s/" % String(pack.get("dir", "")).trim_suffix("/")
		if path.begins_with(dir) and dir.length() > best_dir.length():
			best_dir = dir
			best_scale = float(pack.get("render_scale", vendor.get("render", {}).get("scale", 2.0)))
	return best_scale


func _png_path_for(svg_path: String) -> String:
	return svg_path.trim_suffix(".svg") + "@2x.png"


func _decode_png(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_that(bytes).is_not_empty()
	var image := Image.new()
	assert_int(image.load_png_from_buffer(bytes)).is_equal(0)
	return image


func _has_ink(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a8 > 0:
				return true
	return false


# --- 1. The staged tree backs the art manifest ---------------------------------


func test_non_pending_art_entries_resolve_on_disk() -> void:
	var manifest := _art()
	assert_that(manifest).is_not_null()
	if manifest == null:
		return
	var staged := 0
	for asset: ArtAssetDef in manifest.assets:
		if asset.pending:
			continue  # the incremental-landing hatch (validator-tested in test_content_schema)
		staged += 1
		assert_bool(FileAccess.file_exists(asset.source_path)).is_true()
		assert_bool(FileAccess.file_exists(_png_path_for(asset.source_path))).is_true()
	assert_int(staged).is_greater_equal(13)  # deleted vendor files fail HERE, not at art review


func test_must_be_staged_keys_are_landed_and_real() -> void:
	var assets := _by_id(_art())
	for key in MUST_BE_STAGED:
		assert_bool(assets.has(key)).is_true()
		var asset: ArtAssetDef = assets.get(key)
		assert_bool(asset.pending).is_false()  # landed keys may not regress to pending


# --- 2. Render exactness --------------------------------------------------------


func test_every_staged_svg_prerenders_at_manifest_scale_with_ink() -> void:
	var manifest := _art()
	var vendor := _vendor_manifest()
	for asset: ArtAssetDef in manifest.assets:
		if asset.pending:
			continue
		var scale := _render_scale_for(asset.source_path, vendor)
		var natural := Image.new()
		var svg := FileAccess.get_file_as_bytes(asset.source_path)
		assert_int(natural.load_svg_from_buffer(svg, 1.0)).is_equal(0)
		var rendered := _decode_png(_png_path_for(asset.source_path))
		assert_int(rendered.get_width()).is_equal(int(natural.get_width() * scale))
		assert_int(rendered.get_height()).is_equal(int(natural.get_height() * scale))
		assert_bool(_has_ink(rendered)).is_true()  # an empty render is a broken render


# --- 3. Attributions --------------------------------------------------------------


func test_attribution_file_carries_ccby_cc0_and_pending() -> void:
	var text := FileAccess.get_file_as_string(ATTRIBUTIONS_PATH)
	assert_that(text).is_not_empty()
	# CC-BY: artist + license + link, per R6 credits requirement.
	assert_bool(text.contains("CC BY 3.0")).is_true()
	assert_bool(text.contains("Lorc")).is_true()
	assert_bool(text.contains("Delapouite")).is_true()
	assert_bool(text.contains("game-icons.net")).is_true()
	# CC0 provenance for Kenney.
	assert_bool(text.contains("Kenney")).is_true()
	assert_bool(text.contains("CC0")).is_true()
	assert_bool(text.contains("kenney.nl")).is_true()
	# Pending packs are visible, not silently absent.
	assert_bool(text.contains("NOT YET VENDORED")).is_true()
	assert_bool(text.contains("armorial")).is_true()


func test_every_ccby_art_entry_appears_in_attributions() -> void:
	var manifest := _art()
	var text := FileAccess.get_file_as_string(ATTRIBUTIONS_PATH)
	for asset: ArtAssetDef in manifest.assets:
		if asset.license.to_upper().contains("BY"):
			assert_bool(text.contains(asset.attribution)).is_true()


# --- 4. One real asset, vertically -------------------------------------------------


func test_icon_smithy_end_to_end() -> void:
	# The contract's "at least one real staged asset end-to-end": manifest key
	# -> validator-clean entry -> staged SVG bytes -> @2x PNG decode at exact
	# size with ink -> attribution present. game-icons.net anvil (Lorc, CC-BY).
	var assets := _by_id(_art())
	var asset: ArtAssetDef = assets.get(&"icon_smithy")
	assert_that(asset).is_not_null()
	assert_str(asset.license).is_equal("CC-BY-3.0")
	assert_bool(FileAccess.file_exists(asset.source_path)).is_true()
	var rendered := _decode_png(_png_path_for(asset.source_path))
	assert_int(rendered.get_width()).is_equal(1024)  # 512 viewBox x render.scale 2.0
	assert_int(rendered.get_height()).is_equal(1024)
	assert_bool(_has_ink(rendered)).is_true()
	assert_bool(FileAccess.get_file_as_string(ATTRIBUTIONS_PATH).contains(asset.attribution)).is_true()
