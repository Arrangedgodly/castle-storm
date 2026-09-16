## One sourced art asset — the single place a vendor file path may appear
## (R6: content references art by asset key, never by path). T-DATA-01
## schema (docs/content-schema.md). Consumed by: T-ARCH-04 (vendor pipeline
## pre-renders source_path to @2x PNG + tracks licenses), T-UI-01 (theme
## resolves keys to textures), T-DATA-02 (pack ships the manifest).
class_name ArtAssetDef
extends Resource

## Stable asset key referenced by content defs (face_id / crest_id / icon_id).
@export var id: StringName = &""

## Vendor source path under assets/vendor/<pack>/... (existence is checked
## from T-ARCH-04 onward, once packs are vendored).
@export var source_path: String = ""

## License label, e.g. "CC0", "CC-BY-3.0", "commercial" (Armorial).
## CC-BY family licenses REQUIRE a non-empty attribution (validator).
@export var license: String = ""

## Attribution line for CC-BY assets (e.g. game-icons.net: "Lorc, CC BY 3.0").
@export var attribution: String = ""

## True while the vendor pack backing this asset is not yet vendored
## (T-ARCH-04: `make vendor-assets`). The validator SKIPS the path-existence
## check for pending entries so packs can land incrementally (T-UI-01 fills
## faces without red CI) — every entry MUST flip to pending=false (real
## staged file) before ship; the acceptance sweep greps for strays.
@export var pending: bool = false

## Sub-rectangle of the RENDERED @2x PNG (pixels, y-down) that is the whole
## asset — the atlas crop for multi-pose source sheets (T-UI-01 round-2 fix).
## Zero-size (default) = the rendered texture is already a single asset and
## is used whole (icons, crests, single-pose faces). For a sheet, the UI
## composes an AtlasTexture with exactly this region, so ONE staged file can
## serve many faces and the crop is content data, never UI hardcoding.
##
## GRID MATH OF RECORD (Kenney Toon Characters, verified by pixel probe
## 2026-09-15): every sheet is 864x640 px = a uniform 9-col x 5-row grid of
## 96x128 cells (9*96 = 864, 5*128 = 640); cell (0,0) — the top-left — is
## the neutral front-facing standing pose on all three staged sheets
## (male-person, female-person, male-adventurer), so landed faces declare
## Rect2(0, 0, 96, 128). The validator checks well-formedness (positive
## size, non-negative origin); tests pin that the region tiles the real
## sheet exactly (tests/unit/test_theme_grammar.gd).
@export var atlas_region: Rect2 = Rect2()
