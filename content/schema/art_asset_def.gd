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
