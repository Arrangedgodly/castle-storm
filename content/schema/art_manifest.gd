## Art manifest — the validated content file mapping asset keys to vendored
## sources and licenses (R6 implementation consequence: the pack ships with
## the license manifest). T-DATA-01 schema (docs/content-schema.md).
## Consumed by: T-ARCH-04 (pipeline + attribution file), T-UI-01 (key ->
## texture resolution), CREDITS.md generation.
class_name ArtManifest
extends Resource

## All sourced assets. Every face_id / crest_id / icon_id used by the pack
## must resolve to an ArtAssetDef id here (validator cross-check).
@export var assets: Array[ArtAssetDef] = []
