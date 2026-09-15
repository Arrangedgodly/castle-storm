## Base class for every simulation system registered on SimEngine (T-SIM-01).
##
## This is the seam T-SIM-02..08 build on: production, training, run
## lifecycle, suspicion, assault, catch-up each subclass SimSystem and are
## registered on the engine — the core never changes to add a system.
##
## Contract (docs/sim-engine.md §4, enforced by determinism rules):
##   - `system_name()` must be unique per engine and stable across saves
##     (serialization keys systems by it)
##   - `on_tick()` runs once per processed tick, in REGISTRATION order —
##     the one and only place randomness may be drawn (`engine.rng`)
##   - `on_command()` is offered queued commands in registration order;
##     return true if consumed, false to pass on
##   - `state_hash()` must contribute an int derived ONLY from state that
##     changes gameplay; it is mixed with the system name by the engine
##   - `to_dict()/from_dict()` are the save hooks (T-ARCH-03): plain
##     Dictionary of JSON-safe scalars keyed by stable names — ids only,
##     never resource references or float-critical economy state that can
##     live as integers instead
##   - no scene tree, no wall clock, no unseeded randomness
##     (docs/gdscript-conventions.md)
class_name SimSystem
extends RefCounted


## Unique, stable id for this system (serialized key, event subject).
func system_name() -> StringName:
	return &""


## Called once when registered on the engine. Do NOT draw from
## `engine.rng` here — registration sites may vary; determinism covers
## on_tick/on_command only.
func on_register(_engine: SimEngine) -> void:
	pass


## Advance this system one tick. The ONLY sanctioned RNG draw site.
func on_tick(_engine: SimEngine) -> void:
	pass


## Offer a queued command. Return true if this system consumed it.
func on_command(_engine: SimEngine, _command: SimCommand) -> bool:
	return false


## Deterministic int over gameplay-visible state (int fields only).
func state_hash() -> int:
	return 0


## Save hook: JSON-safe Dictionary (T-ARCH-03 composes these).
func to_dict() -> Dictionary:
	return {}


## Save hook: restore from a to_dict() payload.
func from_dict(_state: Dictionary) -> void:
	pass
