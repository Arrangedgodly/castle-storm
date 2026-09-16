extends SceneTree

## Vendor asset pipeline (T-ARCH-04, per R6) — the Godot-side stage of
## scripts/vendor_assets.sh. Run via `make vendor-assets` (or directly:
## `godot --headless --path . -s res://scripts/vendor_assets.gd`).
##
## Responsibilities (in order):
##   1. STAGE    — copy/extract every file declared in assets/vendor/
##                 manifest.json into assets/vendor/<pack>/..., verifying
##                 the sha256 recorded in the manifest. Idempotent: a file
##                 already staged with the right hash is left untouched; a
##                 mismatched staged file is a hard error (vendored bytes
##                 must never be edited locally).
##   2. RENDER   — pre-render every staged SVG to a sibling @2x PNG
##                 (foo.svg -> foo@2x.png) via Image.load_svg_from_buffer
##                 (ThorVG). "2x" = 2x display-ready: the global render
##                 scale (manifest render.scale, default 2.0) applies unless
##                 a pack overrides render_scale (e.g. Kenney characters,
##                 whose natural 864x640 already exceeds 2x any card-figure
##                 display size — see the manifest's render_scale_note).
##                 Renderer decision of record: no Inkscape /
##                 rsvg-convert / ImageMagick on the target machines and
##                 ffmpeg lacks an SVG decoder; the R1-pinned engine binary
##                 rasterizes deterministically with zero new dependencies.
##                 Limitation (R6): ThorVG's SVG support is limited —
##                 decode errors and zero-sized renders fail loudly here.
##   3. ATTRIBUT — generate assets/vendor/ATTRIBUTIONS.md: CC-BY entries
##                 with artist + license + link (credits-ready), CC0 packs
##                 listed for provenance, OFL font families with their
##                 license links, pending packs noted. Deterministic
##                 content (sorted, no timestamps) so re-runs are no-ops.
##                 Font files skip the @2x render step (not SVG) but stage
##                 and checksum exactly like art (T-UI-01 extension).
##
## Downloads are deliberately NOT done here (scripts/vendor_assets.sh
## --fetch does them with curl): game code stays network-free per
## docs/security-policy.md §2 (the CI tripwire scans res://scripts for
## network APIs — this file must never gain any).
##
## Inputs: assets/vendor/manifest.json; optional cache dir with downloaded
## artifacts (env CS_VENDOR_CACHE, default ~/.cache/castle-storm/vendor,
## populated by `scripts/vendor_assets.sh --fetch`). Zip archives are
## extracted in-process via ZIPReader; url-fetched files are copied from
## cache/<pack-id>/<dest>.
##
## Exit codes: 0 = staged + rendered (or already staged); 1 = manifest
## parse error, checksum failure, or render failure.

const MANIFEST_PATH := "res://assets/vendor/manifest.json"
const ATTRIBUTIONS_PATH := "res://assets/vendor/ATTRIBUTIONS.md"

var _failures: Array[String] = []
var _staged_ok := 0
var _staged_missing: Array[String] = []
var _rendered := 0


func _initialize() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		quit(1)
		return
	var scale_default: float = float(manifest.get("render", {}).get("scale", 2.0))
	var cache_root := _cache_root()

	# Per-pack render scale overrides (deepest matching pack dir wins; files
	# outside any pack dir use the global scale).
	var scales: Dictionary = {}
	for pack: Dictionary in manifest.get("packs", []):
		var dir := String(pack.get("dir", ""))
		if not dir.is_empty() and pack.has("render_scale"):
			scales["res://%s" % dir.trim_suffix("/")] = float(pack.get("render_scale"))

	# --- 1. stage ----------------------------------------------------------
	for pack: Dictionary in manifest.get("packs", []):
		if String(pack.get("status", "")) == "pending":
			print("[vendor] pack '%s' PENDING (not vendored yet): %s" % [pack.get("id", "?"), pack.get("note", "")])
			continue
		_stage_pack(pack, cache_root)

	# --- 2. render (every staged .svg under assets/vendor) ------------------
	_render_tree("res://assets/vendor", scale_default, scales)

	# --- 3. attributions -----------------------------------------------------
	_write_attributions(manifest)

	# --- summary --------------------------------------------------------------
	print("")
	print("[vendor] staged ok: %d, missing (run scripts/vendor_assets.sh --fetch): %d, svg->@2x rendered: %d" % [
		_staged_ok, _staged_missing.size(), _rendered])
	if not _staged_missing.is_empty():
		for m in _staged_missing:
			print("[vendor]   missing: %s" % m)
	if not _failures.is_empty():
		for f in _failures:
			print("[vendor] FAILURE: %s" % f)
		print("[vendor] FAILED (%d failure(s))" % _failures.size())
		quit(1)
		return
	print("[vendor] green")
	quit(0)


func _load_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	if text.is_empty():
		_failures.append("cannot read %s" % MANIFEST_PATH)
		return {}
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		_failures.append("%s is not valid JSON" % MANIFEST_PATH)
		return {}
	return parsed


func _cache_root() -> String:
	var override := OS.get_environment("CS_VENDOR_CACHE")
	if not override.is_empty():
		return override
	return OS.get_environment("HOME").path_join(".cache/castle-storm/vendor")


# --- 1. staging ---------------------------------------------------------------


func _stage_pack(pack: Dictionary, cache_root: String) -> void:
	var pack_id := String(pack.get("id", ""))
	var pack_dir := String(pack.get("dir", ""))
	if pack_id.is_empty() or pack_dir.is_empty():
		_failures.append("pack entry without id/dir: %s" % str(pack))
		return
	var download: Dictionary = pack.get("download", {})
	var zip_cache := ""
	if not download.is_empty() and String(download.get("format", "")) == "zip":
		zip_cache = cache_root.path_join(pack_id).path_join(String(download.get("url", "").get_file()))
		var zip_digest := _sha256_file(zip_cache)
		if zip_digest.is_empty():
			_staged_missing.append("%s (cache archive %s absent)" % [pack_id, zip_cache])
			zip_cache = ""  # only report once per pack
	for file: Dictionary in pack.get("files", []):
		_stage_file(pack_id, pack_dir, file, zip_cache, cache_root)


func _stage_file(pack_id: String, pack_dir: String, file: Dictionary, zip_cache: String, cache_root: String) -> void:
	var dest_rel := String(file.get("dest", ""))
	var want := String(file.get("sha256", ""))
	if dest_rel.is_empty() or want.is_empty():
		_failures.append("file entry without dest/sha256 in pack '%s': %s" % [pack_id, str(file)])
		return
	var dest := "res://%s/%s" % [pack_dir.trim_suffix("/"), dest_rel]
	var have := _sha256_file(dest)
	if not have.is_empty():
		if have != want:
			_failures.append("staged file %s hashes %s but manifest says %s — vendored bytes must match the manifest exactly (re-run --fetch into a clean state)" % [dest, have, want])
		else:
			_staged_ok += 1
		return
	# Not staged yet: source it from the cache (zip member or copied file).
	var bytes := PackedByteArray()
	if not zip_cache.is_empty():
		bytes = _zip_member(zip_cache, String(file.get("member", "")))
		if bytes.is_empty():
			_failures.append("member '%s' not found in %s" % [file.get("member", ""), zip_cache])
			return
	else:
		var cache_path := cache_root.path_join(pack_id).path_join(dest_rel)
		if not FileAccess.file_exists(cache_path):
			_staged_missing.append(dest)
			return
		bytes = FileAccess.get_file_as_bytes(cache_path)
	var got := _sha256_bytes(bytes)
	if got != want:
		_failures.append("%s (from cache) hashes %s but manifest says %s — bad download or stale manifest" % [dest, got, want])
		return
	if _write_bytes(dest, bytes):
		_staged_ok += 1
		print("[vendor] staged %s" % dest)


func _zip_member(zip_path: String, member: String) -> PackedByteArray:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		_failures.append("cannot open zip %s" % zip_path)
		return PackedByteArray()
	var want := member.replace("\\", "/").to_lower()
	for entry in reader.get_files():
		if String(entry).replace("\\", "/").to_lower() == want:
			return reader.read_file(entry)
	return PackedByteArray()


# --- 2. @2x pre-render ---------------------------------------------------------


func _render_tree(root: String, scale_default: float, scales: Dictionary) -> void:
	var scale := scale_default
	for pack_dir in scales:
		if root.begins_with(String(pack_dir)):
			scale = float(scales[pack_dir])
	var dir := DirAccess.open(root)
	if dir == null:
		_failures.append("cannot open %s" % root)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := root.path_join(name)
		if dir.current_is_dir():
			if name != ".godot":
				_render_tree(path, scale_default, scales)
		elif name.to_lower().ends_with(".svg"):
			_render_svg(path, scale)
		name = dir.get_next()
	dir.list_dir_end()


func _render_svg(svg_path: String, scale: float) -> void:
	var svg := FileAccess.get_file_as_bytes(svg_path)
	if svg.is_empty():
		_failures.append("cannot read %s" % svg_path)
		return
	var image := Image.new()
	if image.load_svg_from_buffer(svg, scale) != OK:
		_failures.append("SVG decode failed: %s (ThorVG could not rasterize it — see manifest.json render note)" % svg_path)
		return
	if image.get_width() <= 0 or image.get_height() <= 0:
		_failures.append("SVG rendered zero-sized: %s" % svg_path)
		return
	var png_path := svg_path.trim_suffix(".svg") + "@2x.png"
	if image.save_png(ProjectSettings.globalize_path(png_path)) != OK:
		_failures.append("PNG write failed: %s" % png_path)
		return
	_rendered += 1
	print("[vendor] rendered %s -> %s (%dx%d)" % [svg_path, png_path, image.get_width(), image.get_height()])


# --- 3. attributions ------------------------------------------------------------


func _write_attributions(manifest: Dictionary) -> void:
	var lines: Array[String] = []
	lines.append("# Attributions — vendored art packs")
	lines.append("")
	lines.append("Generated by `scripts/vendor_assets.gd` (`make vendor-assets`) from")
	lines.append("`assets/vendor/manifest.json` — do not edit by hand; edit the manifest")
	lines.append("and regenerate. License texts per pack live beside the files they cover")
	lines.append("(see each pack's LICENSE.txt where the pack ships one).")
	lines.append("")
	var ccby: Array[String] = []
	var cc0: Array[String] = []
	var ofl: Array[String] = []
	var commercial: Array[String] = []
	var pending: Array[String] = []
	for pack: Dictionary in manifest.get("packs", []):
		var license := String(pack.get("license", ""))
		var files := pack.get("files", []) as Array
		if String(pack.get("status", "")) == "pending":
			pending.append("- %s — %s — %s (NOT YET VENDORED: %s)" % [
				String(pack.get("artist", "?")), license, String(pack.get("homepage", "?")), String(pack.get("note", ""))])
			continue
		var file_list := ", ".join(files.map(func(f: Dictionary) -> String: return String(f.get("dest", ""))))
		if license.to_upper().contains("BY"):
			# Per-file lines carry the EXACT attribution string the art manifest
			# entries use (test-asserted substring-for-substring) plus the pack
			# umbrella entry for human credits.
			ccby.append("- %s — %s" % [
				String(pack.get("attribution", pack.get("artist", "?"))),
				String(pack.get("license_url", pack.get("homepage", "")))])
			for f: Dictionary in files:
				ccby.append("    - `%s` — %s" % [
					String(f.get("dest", "")),
					String(f.get("attribution", pack.get("attribution", pack.get("artist", "?"))))])
		elif license.to_lower() == "cc0" or license.to_lower().contains("public domain"):
			cc0.append("- %s — CC0 — %s — files: %s" % [
				String(pack.get("artist", "?")), String(pack.get("homepage", "?")), file_list])
		elif license.to_upper().contains("OFL"):
			# Open Font License families (T-UI-01): OFL.txt is vendored beside
			# the font files, so the section points at it rather than inlining
			# terms; family + artist + specimen homepage + file list for
			# credits (the family name is the string tests and the credits
			# screen key on — human-spelled, not URL-encoded).
			ofl.append("- %s — %s — OFL-1.1 — %s — files: %s (full license text: `OFL.txt` beside the fonts)" % [
				String(pack.get("family", pack.get("artist", "?"))),
				String(pack.get("artist", "?")),
				String(pack.get("homepage", "?")), file_list])
		else:
			commercial.append("- %s — %s — %s — files: %s" % [
				String(pack.get("artist", "?")), license, String(pack.get("homepage", "?")), file_list])
	lines.append("## CC-BY (attribution REQUIRED — keep this section in credits)")
	lines.append("")
	lines.append_array(ccby if not ccby.is_empty() else ["- (none)"])
	lines.append("")
	lines.append("## CC0 / public domain (credited for provenance, not required)")
	lines.append("")
	lines.append_array(cc0 if not cc0.is_empty() else ["- (none)"])
	lines.append("")
	lines.append("## Open Font License (OFL-1.1 — license text vendored beside each family)")
	lines.append("")
	lines.append_array(ofl if not ofl.is_empty() else ["- (none)"])
	lines.append("")
	lines.append("## Commercial (license terms in the pack's LICENSE.txt)")
	lines.append("")
	lines.append_array(commercial if not commercial.is_empty() else ["- (none)"])
	lines.append("")
	if not pending.is_empty():
		lines.append("## Pending packs (planned, not yet vendored)")
		lines.append("")
		lines.append_array(pending)
		lines.append("")
	var text := "\n".join(lines)
	var file := FileAccess.open(ATTRIBUTIONS_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write %s" % ATTRIBUTIONS_PATH)
		return
	file.store_string(text)
	file.close()
	print("[vendor] wrote %s (%d bytes)" % [ATTRIBUTIONS_PATH, text.length()])


# --- helpers --------------------------------------------------------------------


func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return _sha256_bytes(FileAccess.get_file_as_bytes(path))


func _sha256_bytes(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write %s" % path)
		return false
	file.store_buffer(bytes)
	file.close()
	return true
