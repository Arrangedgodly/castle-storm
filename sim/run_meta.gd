## Meta-progression bank reserve (T-SIM-04) — the data structure only.
##
## Owns everything that must SURVIVE a restart: the legacy-points bank
## (town-hall: failure banks FULL progress — every run, win or loss, accrues)
## and the chronicle, the append-only record of past runs (leader, regime,
## outcome, duration, army stats) that T-UI-08 lists as spread history.
## No spending yet — Layer 1's unlock tree is a post-MVP phase by the
## Ant-Man layer gate; at MVP the reserve only accumulates.
##
## Save-domain contract (docs/sim-engine.md §12): this object lives in the
## META save domain, NEVER in the run save. RunLifecycleSystem composes
## entries into it but deliberately excludes it from its engine-side
## `to_dict()`/`state_hash()` — a run-save restore must not be able to fork
## or rewind the bank. T-ARCH-03 persists it separately (meta save slot);
## the host hands the SAME instance to each engine it builds, so the bank
## also survives the engine-reinit form of restart.
class_name RunMeta
extends RefCounted

## Version of the meta state dict (T-ARCH-03 bumps on change; refusal rule
## mirrors SimEngine.apply_state_dict — loud, never half-applied).
const META_FORMAT_VERSION: int = 1

## Total banked legacy points across every recorded run (win or loss).
var legacy_points := 0

## Runs recorded into the chronicle so far — the monotonic run number the
## chronicle displays (engine-local run indexes restart with each engine;
## this counter does not).
var runs_recorded := 0

## Append-only run records, oldest first. Entries are plain JSON-safe
## dictionaries composed by RunLifecycleSystem (schema in docs/sim-engine.md
## §12): leader name/tags/trait, regime id, outcome, duration, army stats,
## banked score. Unbounded by design — one small entry per completed run.
var chronicle: Array[Dictionary] = []


func to_dict() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry in chronicle:
		entries.append(entry.duplicate(true))
	return {
		"format_version": META_FORMAT_VERSION,
		"legacy_points": legacy_points,
		"runs_recorded": runs_recorded,
		"chronicle": entries,
	}


## Restores a to_dict() payload. Returns false (and refuses, state
## untouched) on a format_version mismatch — same refusal discipline as the
## engine's apply_state_dict.
func apply_dict(state: Dictionary) -> bool:
	var version := int(state.get("format_version", -1))
	if version != META_FORMAT_VERSION:
		push_error(
			"run-meta: state format %d is not supported (expected %d) — refusing"
			% [version, META_FORMAT_VERSION]
		)
		return false
	legacy_points = int(state.get("legacy_points", 0))
	runs_recorded = int(state.get("runs_recorded", 0))
	chronicle.clear()
	for entry in state.get("chronicle", []):
		chronicle.append(entry)
	return true
