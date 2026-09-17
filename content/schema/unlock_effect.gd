## One legacy-unlock effect — the value object UnlockNodeDef carries (L1,
## the post-MVP legacy unlock tree). Exactly one effect per node, mirroring
## RegimeModifier's one-modifier-per-regime discipline: a node says ONE
## thing, the tree composes breadth.
##
## The kind registry lives in `sim/legacy_modifiers.gd` (LegacyModifiers.
## EFFECT_KINDS — the resolution engine owns the vocabulary it consumes)
## and is enforced by ContentValidator.LEGACY_EFFECT_KINDS. Additive entries
## are forward-compatible exactly like the regime modifier registry
## (docs/content-schema.md §6): append to the registry, no format bump.
##
## Kinds (all multipliers on the run's boot economy; value > 0):
##   recruit_arrival_interval_multiplier — units-system arrival cadence
##     (normal interval, jitter, and the opening-rush ramp scale together;
##     < 1.0 = a busier road)
##   building_cost_multiplier  — production-system upgrade/construction cost
##   training_time_multiplier  — units-system training durations (< 1.0 =
##     faster drills; zero-hour trainings stay zero-hour)
##   gear_cost_multiplier     — units-system gear recipe payments
##   stipend_bonus            — the run-start `grant_resources` stipend
##     (value 1.25 = +25% starting resources)
class_name UnlockEffect
extends Resource

## Operator kind. See the class header; the authoritative registry is
## LegacyModifiers.EFFECT_KINDS (mirrored by ContentValidator).
@export var kind: StringName = &""

## Multiplier value (must be > 0 — e.g. 0.9 cheaper walls, 1.25 stipend
## bonus). Crosses `SimFixed.milli_from_float` once, at resolution.
@export var value: float = 1.0
