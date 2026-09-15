## Declarative unit definition — one card type in the conspiracy's spread.
## T-DATA-01 schema (docs/content-schema.md). Consumed by: T-SIM-03 (training
## timers, gear gating, promotion branches), T-SIM-04 (promotion graph),
## T-SIM-06 (combat_power feeds assault odds), T-COPY-01 (display names).
class_name UnitDef
extends Resource

## Stable content id. Saves, cross-references and the future L2 escalation
## snapshot use this key — never file paths (docs/content-schema.md §7).
@export var id: StringName = &""

## Localization-ready display name.
@export var display_name: String = ""

## True if this unit may be assigned to a producing building (worker role).
@export var can_work: bool = false

## Sim-hours to promote INTO this unit from any promotion-path source
## (0 = base unit that arrives rather than trains).
@export var training_time_hours: float = 0.0

## Unit ids this unit may be promoted into (peasant -> worker/militia,
## militia -> trainee, trainee -> knight/archer). Validated to resolve and
## to be acyclic.
@export var promotion_paths: Array[StringName] = []

## Gear slots that must be filled (any tier) for the unit to count as fully
## geared. Knight requires every slot; top tier is NOT required (town-hall).
@export var required_gear_slots: Array[StringName] = []

## Army-score contribution at assault time (T-SIM-06 odds input).
@export var combat_power: int = 0

## Suspicion points added when this unit's training completes (R4 loud acts:
## militia training, knight harness). 0 = quiet.
@export var suspicion_on_train: int = 0

## Art manifest key for this unit's face (R6: content references art by key,
## never by file path).
@export var face_id: StringName = &""
