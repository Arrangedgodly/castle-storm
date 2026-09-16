## TypeScale — the font-scaling seam (T-QA-05, per PRODUCT.md accessibility).
##
## Godot 4.7's Theme has no default_font_scale, so the scale is applied the
## way this project's theme is built: by rewriting the SHARED theme
## resource's font sizes (the default font size + every type variation's
## `font_size` item) from the AUTHORED base values, captured once on the
## first apply. Every control that resolves its type through the project
## theme follows; the handful of `add_theme_font_size_override` sites that
## pin a local size call `TypeScale.scaled(base)` so local intent survives
## at any scale.
##
## The supported range is 1.0 – 1.3 (documented in docs/acceptance-sweep.md
## with the evidence): panel budgets that carry text (the blockquote's
## QUOTE_WIDTH, the choice card's CHOICE_WIDTH) grow by the same factor, so
## the audited no-clip surfaces stay no-clip at 1.3; at larger factors the
## fixed strip/rail plates (the chronicle strip, the pip rail) would clip
## their text — the labels fail SAFE (clip at the plate edge, never past
## the table), but the print stops being whole, so the range is capped.
##
## Setting (mirrors the motion seam in project.godot):
##     castle_storm/type/scale = 1.0   (float, clamped to [MIN, MAX])
##
## Applied at BOOT (main scene, the spread screen's _ready, and the test
## runners) — a live settings toggle would need a whole-view rebind and is
## deferred with the settings screen (recorded deviation, acceptance-sweep).
class_name TypeScale
extends RefCounted

## Project setting path (see project.godot [castle_storm] section).
const SETTING := "castle_storm/type/scale"
## The supported range (see class header for why the cap is 1.3).
const MIN_SCALE := 1.0
const MAX_SCALE := 1.3
const DEFAULT_SCALE := 1.0

const THEME_PATH := "res://ui/theme/spread_theme.tres"

## Type variations whose `font_size` theme item scales (the theme's whole
## ladder — Label itself has no per-type size item, the default covers it).
const SCALED_TYPES: Array[StringName] = [
	&"Heading", &"CardTitle", &"Body", &"RoleLine", &"Numerals",
	&"ChronicleLine", &"PipLabel", &"Button",
]

static var _factor := 0.0
static var _applied := false
static var _base_default_size := -1
static var _base_sizes: Dictionary = {}


static func factor() -> float:
	## The active scale (read once from the project settings, clamped).
	## CS_TYPE_SCALE=<float> overrides (the capture/inspection hook — the
	## same pattern as the CS_SPREAD_* hooks: windowed spot-checks without
	## editing project.godot).
	if _factor <= 0.0:
		var value := float(ProjectSettings.get_setting(SETTING, DEFAULT_SCALE))
		var env := OS.get_environment("CS_TYPE_SCALE")
		if not env.is_empty() and env.is_valid_float():
			value = env.to_float()
		_factor = clampf(value, MIN_SCALE, MAX_SCALE)
	return _factor


## A local font-size override at scale (int sizes, round half-away).
static func scaled(base: int) -> int:
	return maxi(1, int(round(float(base) * factor())))


## Rewrite the shared theme's font sizes to the given factor. Idempotent:
## base sizes are captured from the AUTHORED theme once, so repeated calls
## (and factor changes — the test suites exercise both) always compute
## from the authored values, never compounding.
static func apply_factor(new_factor: float, theme: Theme = null) -> void:
	if theme == null:
		var loaded := load(THEME_PATH)
		if loaded == null:
			push_error("TypeScale: cannot load %s" % THEME_PATH)
			return
		theme = loaded as Theme
	_factor = clampf(new_factor, MIN_SCALE, MAX_SCALE)
	if _base_default_size < 0:
		_base_default_size = theme.default_font_size
		for type_name: StringName in SCALED_TYPES:
			if theme.has_theme_item(Theme.DATA_TYPE_FONT_SIZE, &"font_size", type_name):
				_base_sizes[type_name] = theme.get_font_size(&"font_size", type_name)
	theme.default_font_size = scaled(_base_default_size)
	for type_name: StringName in _base_sizes:
		theme.set_font_size(&"font_size", type_name, scaled(int(_base_sizes[type_name])))
	_applied = true


## Boot seam: apply the project setting's factor (no-op when already at it).
static func ensure_applied(theme: Theme = null) -> void:
	var want := factor()
	if _applied and is_equal_approx(_factor, want):
		return
	apply_factor(want, theme)


## Test seam: restore the authored 1.0 theme (leaves no scaled sizes behind
## for the suites that pin pixel budgets at 1.0).
static func reset(theme: Theme = null) -> void:
	_factor = 0.0
	apply_factor(DEFAULT_SCALE, theme)
