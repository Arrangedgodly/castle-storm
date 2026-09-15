## Declarative regime definition — the ruling face card of a run.
## T-DATA-01 schema (docs/content-schema.md). Consumed by: T-SIM-04 (run
## generation picks a regime), T-SIM-06 (combat modifier scales garrison),
## T-SIM-02 (economy quirk bends production/costs), T-UI-01 (ink pair +
## crest recolor the theme), T-UI-05 (regime reveal).
class_name RegimeDef
extends Resource

## Stable content id (saves and the L2 snapshot reference it, never paths).
@export var id: StringName = &""

## Localization-ready display name (e.g. "The Gilded Crown").
@export var display_name: String = ""

## Exactly one combat modifier per flavor (town-hall MVP boundary).
@export var combat_modifier: RegimeModifier

## Exactly one economy quirk per flavor (town-hall MVP boundary).
@export var economy_quirk: RegimeModifier

## Art manifest key for the regime's heraldry crest (R6: Armorial pack).
@export var crest_id: StringName = &""

## First ink: the table ground tone this regime tints (R6 two-ink rule).
@export var ink_ground: Color = Color.BLACK

## Second ink: the regime secondary accent (design brief: one secondary per
## flavor; revolution red stays global). Must differ from ink_ground.
@export var ink_secondary: Color = Color.WHITE

## One-line flavor text for the reveal card (T-COPY-01 refines the voice).
@export var flavor_text: String = ""
