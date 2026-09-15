## Declarative gear definition — one smithy-craftable equipment card.
## T-DATA-01 schema (docs/content-schema.md). Consumed by: T-SIM-03 (gear
## gating: required slots filled at any tier), T-SIM-06 (gear tiers raise
## assault odds), T-SIM-05 (crafting above tolerance is a loud act).
class_name GearDef
extends Resource

## Stable content id (saves cross-reference by id, never file path).
@export var id: StringName = &""

## Localization-ready display name.
@export var display_name: String = ""

## Slot this gear occupies; must be one of the pack's declared gear_slots
## (MVP: weapon, armor).
@export var slot: StringName = &""

## Tier within the slot (MVP: 1..3; top tier NOT required for knights).
@export var tier: int = 1

## Crafting recipe: resource id -> int amount (timber + iron per town-hall).
@export var recipe: Dictionary[StringName, int] = {}

## Army-score contribution while equipped (T-SIM-06 odds input).
@export var combat_power: int = 0

## Sim-hours the smithy takes to craft one item.
@export var craft_time_hours: float = 0.0

## Art manifest key for this gear's icon (R6 asset-key rule).
@export var icon_id: StringName = &""
