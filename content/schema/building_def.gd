## Declarative building definition — one production card on the table.
## T-DATA-01 schema (docs/content-schema.md). Consumed by: T-SIM-02 (worker
## assignment -> building rates -> upgrade multipliers), T-SIM-08 (cost curve
## band + milestones), T-SIM-05 (upgrade acts feed suspicion).
class_name BuildingDef
extends Resource

## Stable content id (saves cross-reference by id, never file path).
@export var id: StringName = &""

## Localization-ready display name.
@export var display_name: String = ""

## Resource produced by assigned workers (e.g. &"food"). Empty StringName
## (&"") marks a non-producing building (training grounds).
@export var resource_produced: StringName = &""

## Units of resource_produced per worker per sim-hour at building level 1.
@export var base_production_per_worker_hour: float = 0.0

## Worker slots at level 1 (grows with level per T-SIM-02's curve).
@export var worker_slots_base: int = 1

## Cost of the first building level: resource id -> int amount.
@export var base_cost: Dictionary[StringName, int] = {}

## Cost growth r in cost_next = base_cost * r^level (R4: 1.08-1.12 per
## building, cheapest 1.08 / dearest 1.12; validated against the tunables
## band).
@export var cost_growth: float = 1.08

## Levels where the milestone production multiplier fires (R4: [10, 20],
## multiplier x2.0 from EconomyTunables). Validated non-empty, ascending,
## below max_level.
@export var milestone_levels: Array[int] = []

## Hard level cap (R4 band targets ~30 with milestones at 10/20).
@export var max_level: int = 30

## Art manifest key for this building's table icon (R6 asset-key rule).
@export var icon_id: StringName = &""
