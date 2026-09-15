## One regime modifier — the value object RegimeDef composes its combat
## modifier and economy quirk from (town-hall: exactly one of each per
## regime flavor). T-DATA-01 schema (docs/content-schema.md §RegimeModifier
## for the kind registry). Consumed by: T-SIM-06 (combat kinds), T-SIM-02
## (economy kinds), T-UI-01 (flavor surfacing).
class_name RegimeModifier
extends Resource

## Operator kind. Combat: garrison_multiplier, army_score_multiplier.
## Economy: production_multiplier, building_cost_multiplier. The validator
## keeps the authoritative registry; additive entries are forward-compatible
## (schema doc §6).
@export var kind: StringName = &""

## Operand the kind applies to: a resource id for economy kinds
## (e.g. &"timber"), &"all" for every resource, or &"" when the kind
## implies its target (combat kinds).
@export var target: StringName = &""

## Modifier value (multiplier; must be > 0 — e.g. 0.85 timber tax,
## 1.2 garrison archers bonus).
@export var value: float = 1.0
