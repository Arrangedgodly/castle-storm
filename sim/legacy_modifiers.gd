## LegacyModifiers — the resolved legacy-unlock modifier bundle (L1).
##
## A pure, data-derived value object: what the persistent set of purchased
## unlock nodes MEANS to a run, as one integer-milli bundle. Resolution
## (from_nodes) multiplies each purchased node's UnlockEffect into the
## matching field — content floats cross `SimFixed.milli_from_float` ONCE
## per effect and compound as exact integer milli chains (the growth-table
## pattern), so the bundle is deterministic and order-independent
## (multiplication of exact ints is associative).
##
## Application contract (the regime-quirk pattern, docs/sim-engine.md §18):
## RunLifecycleSystem resolves ONE bundle at every run_start/run_restart
## drain and hands it to production (building costs) + units (arrival
## cadence, training durations, gear costs) synchronously, and applies the
## stipend field to `grant_resources` itself. Each consumer then carries
## its APPLIED multipliers as serialized + hashed state, emitted ONLY when
## non-identity (1000 = x1.0): an engine with no unlocks serializes and
## hashes byte-identically to the pre-L1 build — the escalation_garrison
## reserve's emit-when-non-null discipline.
##
## Identity defaults make a bare `LegacyModifiers.new()` the no-op bundle
## (proven by test).
class_name LegacyModifiers
extends RefCounted

## Effect-kind registry (L1 vocabulary — the authoritative list; the
## content validator mirrors it as LEGACY_EFFECT_KINDS). Additive entries
## are forward-compatible: a future kind resolves nowhere here and is
## ignored by old builds' resolution rather than crashing (unknown kinds in
## ATTACHED packs are still a validator error — this leniency is only the
## runtime resolution's defense).
const EFFECT_KINDS: Array[StringName] = [
	&"recruit_arrival_interval_multiplier",
	&"building_cost_multiplier",
	&"training_time_multiplier",
	&"gear_cost_multiplier",
	&"stipend_bonus",
]

## The whole arrival cadence scales together — normal interval, jitter AND
## the opening-rush ramp — so a faster road is faster everywhere and the
## rush cap logic stays coherent. Milli multiplier (1000 = identity).
var recruit_arrival_interval_milli := SimFixed.MILLI

## Building construction/upgrade cost multiplier (production system).
var building_cost_milli := SimFixed.MILLI

## Training-duration multiplier (units system; zero-hour stays zero-hour).
var training_time_milli := SimFixed.MILLI

## Gear recipe payment multiplier (units system).
var gear_cost_milli := SimFixed.MILLI

## Run-start stipend multiplier (the `grant_resources` verb; 1250 = +25%).
var stipend_milli := SimFixed.MILLI


## The no-op bundle (all fields identity 1000).
static func identity() -> LegacyModifiers:
	return LegacyModifiers.new()


## Resolve a bundle from purchased nodes' effects. Pure and total: null
## nodes, null effects, and unknown kinds are skipped (validated content
## never hits those paths; the skips are the runtime defense for hand-built
## or future-vocabulary trees).
static func from_nodes(nodes: Array) -> LegacyModifiers:
	var mods := LegacyModifiers.new()
	for node in nodes:
		var def := node as UnlockNodeDef
		if def == null or def.effect == null:
			continue
		mods._apply_kind(def.effect.kind, SimFixed.milli_from_float(def.effect.value))
	return mods


func is_identity() -> bool:
	return recruit_arrival_interval_milli == SimFixed.MILLI \
		and building_cost_milli == SimFixed.MILLI \
		and training_time_milli == SimFixed.MILLI \
		and gear_cost_milli == SimFixed.MILLI \
		and stipend_milli == SimFixed.MILLI


## JSON-safe form (the five ints) — consumers emit it ONLY when
## `is_identity()` is false, and restore verbatim (absent key = identity,
## the tolerant-reader rule).
func to_dict() -> Dictionary:
	return {
		"arrival_milli": recruit_arrival_interval_milli,
		"building_cost_milli": building_cost_milli,
		"training_milli": training_time_milli,
		"gear_cost_milli": gear_cost_milli,
		"stipend_milli": stipend_milli,
	}


## Restore from a to_dict() payload (tolerant: missing keys read identity).
static func from_dict(state: Dictionary) -> LegacyModifiers:
	var mods := LegacyModifiers.new()
	mods.recruit_arrival_interval_milli = int(state.get("arrival_milli", SimFixed.MILLI))
	mods.building_cost_milli = int(state.get("building_cost_milli", SimFixed.MILLI))
	mods.training_time_milli = int(state.get("training_milli", SimFixed.MILLI))
	mods.gear_cost_milli = int(state.get("gear_cost_milli", SimFixed.MILLI))
	mods.stipend_milli = int(state.get("stipend_milli", SimFixed.MILLI))
	return mods


## Compound one milli multiplier into a field (exact int chain, the
## growth-table rescale pattern).
func _apply_kind(kind: StringName, value_milli: int) -> void:
	match kind:
		&"recruit_arrival_interval_multiplier":
			recruit_arrival_interval_milli = recruit_arrival_interval_milli * value_milli / SimFixed.MILLI
		&"building_cost_multiplier":
			building_cost_milli = building_cost_milli * value_milli / SimFixed.MILLI
		&"training_time_multiplier":
			training_time_milli = training_time_milli * value_milli / SimFixed.MILLI
		&"gear_cost_multiplier":
			gear_cost_milli = gear_cost_milli * value_milli / SimFixed.MILLI
		&"stipend_bonus":
			stipend_milli = stipend_milli * value_milli / SimFixed.MILLI
