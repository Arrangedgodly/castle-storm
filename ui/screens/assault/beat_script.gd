## BeatScript — the assault vignette's REPLAY contract (T-UI-07).
##
## The vignette is driven ENTIRELY from the event stream (docs/sim-engine.md
## §15, the T-SIM-06 contract): one commit produces 4 `assault_beat` events
## (subject = phase advance->skirmish->gate->throne|rout, value = army score
## remaining in milli, value2 = garrison strength remaining in milli) plus
## the outcome chain. This class is the PURE fold of that stream into the
## staged script the table renders:
##
##   { "beats":   [ {phase, army_milli, garrison_milli}, ... ] in order,
##     "outcome": &"win" | &"loss" (from assault_won / assault_lost),
##     "win_permille": the odds that were shown at the commit,
##     "casualties":   army units that fell (assault_casualties value; 0 on
##                     win — the roster is terminal at victory),
##     "initial_army_milli", "final_army_milli", "final_garrison_milli",
##     "settled_tick": the tick the battle resolved in }
##
## Same events -> same script -> same visual_sequence_hash() (the
## determinism oracle tests pin: any assault replays identically from its
## events alone — replay value is the point of the beats being data-light
## int payloads). The fold is order-preserving and TRUSTS the resolver's
## documented invariants (monotone army milli, garrison 0 on throne) but
## records them in `holds()` so a future resolver regression fails the UI
## test loudly instead of rendering a nonsensical march.
##
## Used by the screen at commit time AND usable by any future chronicle
## replay: the script carries no UI state, no roster, no timing.
class_name BeatScript
extends RefCounted

## How the march fraction per phase is derived for the stage (pure data:
## the stage turns these into card positions).
const MARCH_FRACTIONS: Dictionary = {
	&"advance": 0.45,
	&"skirmish": 0.78,
	&"gate": 1.0,
	&"throne": 1.0,
	&"rout": 0.12,
}


## Fold one assault's event slice into the staged script. `events` are the
## host's delivered dicts ({seq, tick, type, subject, value, value2}) in seq
## order — typically the slice captured between the commit's submission and
## its outcome. Extra kinds are ignored; a stream with no assault shape
## yields {"outcome": &""} and the caller refuses to stage it.
static func build(events: Array) -> Dictionary:
	var beats: Array[Dictionary] = []
	var outcome := &""
	var win_permille := -1
	var casualties := -1
	var settled_tick := -1
	for event: Dictionary in events:
		match event["type"]:
			&"assault_beat":
				beats.append({
					"phase": event["subject"],
					"army_milli": int(event["value"]),
					"garrison_milli": int(event["value2"]),
				})
			&"assault_won":
				outcome = &"win"
				win_permille = int(event["value"])
				settled_tick = int(event["tick"])
			&"assault_lost":
				outcome = &"loss"
				win_permille = int(event["value"])
				settled_tick = int(event["tick"])
			&"assault_casualties":
				casualties = int(event["value"])
	var initial_army := int(beats[0]["army_milli"]) if not beats.is_empty() else 0
	return {
		"beats": beats,
		"outcome": outcome,
		"win_permille": win_permille,
		"casualties": casualties if casualties >= 0 else 0,
		"initial_army_milli": initial_army,
		"final_army_milli": int(beats[beats.size() - 1]["army_milli"]) if not beats.is_empty() else 0,
		"final_garrison_milli": int(beats[beats.size() - 1]["garrison_milli"]) if not beats.is_empty() else 0,
		"settled_tick": settled_tick,
	}


## True when the folded stream is stageable: 4 beats ending in throne (win)
## or rout (loss), with the documented §15 invariants intact. The screen
## refuses to play anything else (loudly — a malformed script is a resolver
## regression, not a rendering problem).
static func holds(script: Dictionary) -> bool:
	var beats: Array = script["beats"]
	if beats.size() != 4:
		return false
	var outcome: StringName = script["outcome"]
	if outcome != &"win" and outcome != &"loss":
		return false
	var phases := []
	var last_army := int(script["initial_army_milli"]) + 1
	for beat: Dictionary in beats:
		phases.append(beat["phase"])
		if int(beat["army_milli"]) > last_army:
			return false  # army remaining must be NON-INCREASING
		last_army = int(beat["army_milli"])
	if phases != [&"advance", &"skirmish", &"gate", &"throne"] \
			and phases != [&"advance", &"skirmish", &"gate", &"rout"]:
		return false
	if outcome == &"win" and int(script["final_garrison_milli"]) != 0:
		return false
	return true


## The march fraction for a phase (0 = home seat, 1 = the castle line).
## Rout retreats toward home — the army breaks and runs.
static func march_fraction(phase: StringName) -> float:
	return float(MARCH_FRACTIONS.get(phase, 0.0))


## Determinism oracle over the script's CONTENT: same events -> same hash.
## Mixed the same FNV shape every oracle in the codebase uses.
static func visual_sequence_hash(script: Dictionary) -> int:
	var h := 0x811C9DC5
	h = _mix(h, String(script["outcome"]).hash())
	h = _mix(h, int(script["win_permille"]))
	h = _mix(h, int(script["casualties"]))
	h = _mix(h, int(script["initial_army_milli"]))
	for beat: Dictionary in script["beats"]:
		h = _mix(h, String(beat["phase"]).hash())
		h = _mix(h, int(beat["army_milli"]))
		h = _mix(h, int(beat["garrison_milli"]))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
