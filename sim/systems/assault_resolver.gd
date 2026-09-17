## Assault resolver (T-SIM-06): army score vs castle garrison, odds
## computation, player-chosen commit, replayable resolution beats.
##
## A RESOLVER, not a system that ticks: `on_tick` is a hard no-op (stated
## below, the RunLifecycleSystem precedent) and the system holds ZERO state
## between commands — every persistent effect lives in the siblings it hands
## its result to (units roster, suspicion meter, run frame). It sits on the
## SimSystem seam anyway because the commit must be a COMMAND (tick-aligned
## write contract, docs/sim-engine.md §5): `commit_assault` queues exactly
## like every other player verb and resolves at the next tick's drain, so two
## engines that receive the same commands between the same ticks resolve
## identically. Consequences of statelessness, all deliberate:
##   - `to_dict()` is `{}` / `state_hash()` constant — nothing to save, so
##     NOTHING survives a restart by construction (run-scoped assault memory
##     does not exist; a restart clears the army through the units system's
##     reset contract and the next assault starts from the new roster).
##   - no `reset_run` — the run system's `has_method` guard skips absent
##     siblings (docs/sim-engine.md §12).
##
## Mechanics (town-hall + this task's contract):
##
##   odds (pure query, no RNG draws, callable any time — the odds screen's
##   data contract, displayed BEFORE commit):
##     army_score    = units.army_power() (def + gear tiers, incl. archer
##                     support values) x army_score_multiplier (regime)
##                     x veterans_multiplier (the run's APPLIED legacy
##                     bundle — L1-B2, read from the run system exactly
##                     the way the regime is; 1000 = identity. The floor
##                     and score banking read the RAW army_power: a
##                     veterans bonus raises the odds line, never the
##                     commit gate or the banked lp)
##     garrison      = tunables.assault_garrison_base_power
##                     x garrison_multiplier (regime)
##                     — OR, when the shared meta carries an L2 ESCALATION
##                     snapshot and this resolver was wired with content
##                     (docs/sim-engine.md §19): the SNAPSHOT's army-power-
##                     equivalent x the escalation curve x the SNAPSHOT
##                     regime's garrison modifier ("your previous knights
##                     are the enemy"). No snapshot — or an unwired
##                     resolver — runs the static branch above,
##                     byte-identical to the pre-L2 build.
##     win_permille  = army_milli * 1000 / (army_milli + garrison_milli)
##                     — floor-truncated, monotone: more power NEVER lowers
##                     odds (unit-tested across the growth curve and all 4
##                     regime flavors). At parity 500; the floor assault
##                     (power 23 vs garrison 60) opens at 277.
##     The regime's ONE combat modifier is applied on exactly one side
##     (garrison_multiplier scales the castle, army_score_multiplier the
##     army — the schema allots one combat modifier per flavor). A
##     regime-less run (restore edge, warned loudly by the run system) uses
##     neutral x1.000 multipliers on both sides. The veterans multiplier
##     compounds on the ARMY side after the regime multiplier (one exact
##     int division per hop) — a veteran roster under a strong-leader
##     regime fights with both.
##
##   commit (`commit_assault` command, resolved AT the drain):
##     guards   -> `assault_denied` (value = reason, value2 = live army
##                 power): 1 no running run, 2 no units system, 3 below the
##                 knight floor (army power < tunable). The floor is a FLOOR:
##                 meeting it unlocks the commit, never triggers one;
##                 surplus/quality only raise the visible odds.
##     roll     -> ONE draw from engine.rng: randi_range(0, 999) <
##                 win_permille wins. Fixed draw sequence per path (see
##                 below) — same seed + same command timing => same outcome
##                 AND same beat sequence.
##     beats    -> 4 `assault_beat` events (the T-UI-07 vignette contract:
##                 replayable from events alone; value = army score
##                 remaining in milli, value2 = garrison strength remaining
##                 in milli, subject = phase): advance -> skirmish -> gate
##                 -> throne (win) | rout (loss). Army remaining is
##                 NON-INCREASING across beats and ends at the TRUE
##                 post-battle state.
##     win      -> `assault_won` + run.resolve_victory(engine, true, power)
##                 — the resolve command is queued from inside this drain,
##                 so it lands in the SAME tick (the queue drains until
##                 empty). Victory applies no roster losses: the roster is
##                 terminal at victory (restart clears it; the L2 snapshot
##                 reads whatever stands). The beats still narrate attrition.
##     loss     -> set-back, NEVER instant run death (R4 philosophy):
##                 (a) ceil(assault_loss_fraction x army units) ARMY units
##                     fall (newest first, gear and all) via the units
##                     system's apply_army_losses seam -> `assault_lost` +
##                     `assault_casualties`; the run KEEPS RUNNING and the
##                     assault can be re-attempted after rebuilding past the
##                     floor again.
##                 (b) +assault_failure_suspicion through the suspicion
##                     system's external-bump seam (relief-damped, clamped;
##                     `suspicion_rose`) — loud, so it also pauses decay
##                     above warn. A spike that reaches the meter max CAN
##                     crush the run at this tick (an assault thrown away at
##                     the meter's edge is fatal — the set-back rule bends
##                     only there, mirroring the crackdown design).
##
## Event order per commit (the vignette's replay script):
##   win:  4 beats, assault_won, run_won (same tick)
##   loss: 4 beats, assault_casualties, suspicion_rose, assault_lost
##
## RNG draw count per commit (documented for stream reasoning): 1 roll +
## 4 attrition draws on the win path, 1 + 3 on the loss path. Content floats
## cross the single SimFixed.milli_from_float boundary at use (regime
## modifier values; the loss fraction converts once at construction); after
## that everything is integer milli.
class_name AssaultResolver
extends SimSystem

## Denial reason codes for `assault_denied` events (value payload).
const REASON_NOT_RUNNING := 1
const REASON_NO_UNITS := 2
const REASON_BELOW_FLOOR := 3

## Beat phases, in narration order (subject of `assault_beat` events).
const PHASE_ADVANCE := &"advance"
const PHASE_SKIRMISH := &"skirmish"
const PHASE_GATE := &"gate"
const PHASE_THRONE := &"throne"
const PHASE_ROUT := &"rout"

## Per-mille scale for the odds and every attrition draw (1000 = certainty).
const PERMILLE := 1000

var _floor_power := 0
var _garrison_base := 0
var _loss_milli := 0  # assault_loss_fraction, converted once at construction
var _failure_suspicion := 0
# --- L2 escalation wiring (additive, default unwired = pre-L2 behavior) ---
# Content the snapshot's ids resolve against at odds time (rule §3.2: ids,
# not objects). An UNWIRED resolver (no defs passed — the pre-L2
# construction sites) can derive no snapshot power and falls back to the
# static garrison for every odds read: byte-identical to the pre-L2 build
# by construction, so every existing suite digest stands.
var _unit_defs: Array[UnitDef] = []
var _gear_defs: Array[GearDef] = []
var _regimes_by_id: Dictionary = {}  # String id -> RegimeDef
var _escalation_step_milli := SimFixed.MILLI  # curve step, converted once
# Ids already warned about while resolving a snapshot (unknown content):
# the odds query runs per frame — one warning per id, not one per frame.
# Deliberately NOT serialized/hashed: it is a log damper, not state.
var _escalation_warned := {}


func _init(
	p_tunables: EconomyTunables = null,
	p_units: Array[UnitDef] = [],
	p_gear: Array[GearDef] = [],
	p_regimes: Array[RegimeDef] = []
) -> void:
	var tunables := p_tunables if p_tunables != null else EconomyTunables.new()
	_floor_power = maxi(1, tunables.assault_knight_floor_power)
	_garrison_base = maxi(1, tunables.assault_garrison_base_power)
	_loss_milli = clampi(
		SimFixed.milli_from_float(tunables.assault_loss_fraction), 1, SimFixed.MILLI
	)
	_failure_suspicion = maxi(0, tunables.assault_failure_suspicion)
	_escalation_step_milli = clampi(
		SimFixed.milli_from_float(tunables.escalation_garrison_cycle_step),
		SimFixed.MILLI, 3999
	)
	_unit_defs = p_units.duplicate()
	_gear_defs = p_gear.duplicate()
	for regime in p_regimes:
		if regime != null:
			_regimes_by_id[String(regime.id)] = regime


func system_name() -> StringName:
	return &"assault"


# --- Read API (the odds screen's data contract; pure, no draws, no writes) ---


## Content reads for the UI: the knight floor (army power needed to commit)
## and the pack's base garrison strength (before the regime modifier).
func knight_floor_power() -> int:
	return _floor_power


func garrison_base_power() -> int:
	return _garrison_base


## True when the army meets the knight floor (commit gate; power is the units
## system's live army_power()). The floor is a floor, not a trigger: this
## flag UNLOCKS the commit button, nothing more.
func floor_met(engine: SimEngine) -> bool:
	var units: Variant = engine.get_system(&"units")
	if units == null or not units.has_method("army_power"):
		return false
	return int(units.army_power()) >= _floor_power


## The full odds breakdown, computed live from sibling state + content:
##
##   {
##     "floor_power": int,           # the knight floor (content)
##     "floor_met": bool,            # army power >= floor
##     "win_permille": int,          # displayed odds, 0..1000
##     "army": {
##       "power": int,               # raw army_power() (def + gear tiers)
##       "units": int,               # army unit count
##       "def_power_sum": int,       # sum of per-unit def power
##       "gear_power_sum": int,      # sum of per-unit gear power
##       "regime_multiplier_milli": int,   # 1000 = neutral
##       "score_milli": int,         # power x multiplier — one side of the fight
##       "per_unit": [ {uid: int, def: StringName, def_power: int,
##                      gear_power: int, total: int}, ... ]  # roster order
##     },
##     "garrison": {
##       "base_power": int,          # content
##       "modifier_kind": StringName,  # the regime combat kind, or &"" neutral
##       "regime_multiplier_milli": int,
##       "strength_milli": int,      # base x multiplier — the other side
##       # ...when an L2 escalation snapshot is ACTIVE, the same four keys
##       # carry the DERIVED base/kind/mult/strength plus: "source"
##       # (&"escalation"), "escalation_cycle", "snapshot_power",
##       # "curve_multiplier_milli", "regime_id", "leader",
##       # "captured_at_run", "roster" (the snapshot's tier mix) — L2-C's
##       # "whose army, what tier mix" data. No snapshot -> exactly the
##       # four static keys, byte-identical to pre-L2.
##     },
##   }
##
## The breakdown SUMS to the displayed probability: win_permille is exactly
## army.score_milli * 1000 / (army.score_milli + garrison.strength_milli),
## and army.score_milli is exactly (sum of per_unit totals) x the multiplier
## (unit-tested). "modifier_kind" reports which side the regime's combat
## modifier landed on — the odds screen's composition line.
func assault_odds(engine: SimEngine) -> Dictionary:
	var per_unit: Array[Dictionary] = []
	var def_power_sum := 0
	var gear_power_sum := 0
	var units: Variant = engine.get_system(&"units")
	if units != null and units.has_method("army_contributions"):
		for entry in units.army_contributions():
			var total := int(entry["def_power"]) + int(entry["gear_power"])
			def_power_sum += int(entry["def_power"])
			gear_power_sum += int(entry["gear_power"])
			per_unit.append({
				"uid": int(entry["uid"]),
				"def": entry["def"],
				"def_power": int(entry["def_power"]),
				"gear_power": int(entry["gear_power"]),
				"total": total,
			})
	var army_power := def_power_sum + gear_power_sum
	var army_mult := _army_multiplier_milli(engine)
	var garrison_mult := _garrison_multiplier_milli(engine)
	# The L1-B2 veterans hop (one exact int division): army side of the
	# odds math only — `power` and `floor_met` above stay RAW.
	var veterans_mult := _veterans_multiplier_milli(engine)
	var army_milli := army_power * army_mult * veterans_mult / SimFixed.MILLI
	# L2 escalation (docs/sim-engine.md §19): when the meta carries a
	# garrison snapshot AND this resolver is wired to resolve it, the
	# castle side derives from the SNAPSHOT (army-power-equivalent x the
	# escalation curve) instead of the static base — the regime-static
	# branch below stays byte-identical for every no-snapshot engine (the
	# zero-impact rule).
	var garrison: Dictionary = _escalation_garrison(engine)
	if garrison.is_empty():
		garrison = {
			"base_power": _garrison_base,
			"modifier_kind": _combat_kind(engine),
			"regime_multiplier_milli": garrison_mult,
			"strength_milli": _garrison_base * garrison_mult,
		}
	var garrison_milli := int(garrison["strength_milli"])
	return {
		"floor_power": _floor_power,
		"floor_met": army_power >= _floor_power,
		"win_permille": _win_permille(army_milli, garrison_milli),
		"army": {
			"power": army_power,
			"units": per_unit.size(),
			"def_power_sum": def_power_sum,
			"gear_power_sum": gear_power_sum,
			"regime_multiplier_milli": army_mult,
			"veterans_multiplier_milli": veterans_mult,
			"score_milli": army_milli,
			"per_unit": per_unit,
		},
		"garrison": garrison,
	}


# --- Tick -------------------------------------------------------------------


## The resolver does not tick. No per-tick state exists, no per-tick work is
## scheduled, no RNG is drawn here — ALL resolution happens at the
## `commit_assault` command drain (stated explicitly; the RunLifecycleSystem
## precedent, docs/sim-engine.md §12).
func on_tick(_engine: SimEngine) -> void:
	pass


# --- Commands (the only external write path; drained at tick start) ---------


func on_command(engine: SimEngine, command: SimCommand) -> bool:
	if command.kind != &"commit_assault":
		return false
	_resolve(engine)
	return true


# --- Determinism oracle + save hooks ------------------------------------------
#
# Stateless by design (class header): there is nothing to hash beyond the
# system name the engine already mixes, and nothing to serialize. A save
# carries `"assault": {}`; a restore needs nothing; no assault state survives
# a restart because none exists between commands.


func state_hash() -> int:
	return 0


func to_dict() -> Dictionary:
	return {}


func from_dict(_state: Dictionary) -> void:
	pass


# --- Resolution internals -------------------------------------------------------


## The whole battle, at one command drain. Guard -> breakdown -> one roll ->
## beats -> outcome. See the class header for the exact rules and draw order.
func _resolve(engine: SimEngine) -> void:
	var run: Variant = engine.get_system(&"run")
	if run == null or not run.has_method("is_running") or not run.is_running():
		_deny(engine, REASON_NOT_RUNNING)
		return
	var units: Variant = engine.get_system(&"units")
	if units == null or not units.has_method("army_power") or not units.has_method("apply_army_losses"):
		_deny(engine, REASON_NO_UNITS)
		return
	var odds := assault_odds(engine)
	var army: Dictionary = odds["army"]
	var army_power := int(army["power"])
	if army_power < _floor_power:
		_deny(engine, REASON_BELOW_FLOOR)
		return
	var army_milli := int(army["score_milli"])
	var garrison_milli := int((odds["garrison"] as Dictionary)["strength_milli"])
	var win_permille := int(odds["win_permille"])
	# The one decisive draw. roll < permille wins; >= loses.
	var roll := engine.rng.randi_range(0, PERMILLE - 1)
	var win := roll < win_permille
	if win:
		_narrate_win(engine, army_milli, garrison_milli)
		engine.events.record(engine.tick_count, &"assault_won", _regime_id(engine), win_permille, army_power)
		# Queued from inside this drain -> resolves in the SAME tick (the
		# queue drains until empty). Army power override = the army that
		# fought; the resolve_victory contract (docs/sim-engine.md §12).
		run.resolve_victory(engine, true, army_power)
		return
	# Loss: apply the roster casualties FIRST (the rout beat must end at the
	# true survivor state), narrate the battle, then the outcome events.
	var army_units := int(army["units"])
	var losses := (army_units * _loss_milli + SimFixed.MILLI - 1) / SimFixed.MILLI  # ceil
	var removed: Array = units.apply_army_losses(losses)
	var survivors_milli := int(units.army_power()) * int(army["regime_multiplier_milli"]) \
		* _veterans_multiplier_milli(engine) / SimFixed.MILLI
	_narrate_loss(engine, army_milli, garrison_milli, survivors_milli)
	if not removed.is_empty():
		engine.events.record(
			engine.tick_count, &"assault_casualties", &"assault", removed.size(), int(units.army_power())
		)
	var suspicion: Variant = engine.get_system(&"suspicion")
	if suspicion != null and suspicion.has_method("apply_external_bump") and _failure_suspicion > 0:
		# Loud: the Crown watched the whole army break and run home.
		suspicion.apply_external_bump(engine, &"assault", _failure_suspicion, true)
	engine.events.record(engine.tick_count, &"assault_lost", _regime_id(engine), win_permille, army_power)


## Win-path beats: advance -> skirmish -> gate -> throne (the garrison
## breaks). Flavor attrition only — the roster is terminal at victory (class
## header). Draws: bleed, garrison hit, bleed, garrison crack = 4 after the
## roll.
func _narrate_win(engine: SimEngine, army_milli: int, garrison_milli: int) -> void:
	_beat(engine, PHASE_ADVANCE, army_milli, garrison_milli)
	var army_after := _bleed(engine, army_milli, 100, 300)
	var garrison_after := _bleed(engine, garrison_milli, 100, 400)
	_beat(engine, PHASE_SKIRMISH, army_after, garrison_after)
	army_after = _bleed(engine, army_after, 100, 300)
	garrison_after = _bleed(engine, garrison_after, 400, 700)
	_beat(engine, PHASE_GATE, army_after, garrison_after)
	_beat(engine, PHASE_THRONE, army_after, 0)


## Loss-path beats: advance -> skirmish -> gate -> rout (the army breaks).
## The army's TOTAL applied loss (army_milli - survivors_milli) is split
## across skirmish/gate by one drawn share, so the beat chain is monotone and
## ends exactly at the survivors the roster really holds. Draws: loss share,
## garrison hit, garrison bleed = 3 after the roll.
func _narrate_loss(engine: SimEngine, army_milli: int, garrison_milli: int, survivors_milli: int) -> void:
	_beat(engine, PHASE_ADVANCE, army_milli, garrison_milli)
	var loss_total := maxi(0, army_milli - survivors_milli)
	var share := engine.rng.randi_range(300, 600)  # per-mille of the loss at the skirmish
	var skirmish_drop := loss_total * share / PERMILLE
	var garrison_after := _bleed(engine, garrison_milli, 50, 200)
	_beat(engine, PHASE_SKIRMISH, army_milli - skirmish_drop, garrison_after)
	garrison_after = _bleed(engine, garrison_after, 50, 150)
	_beat(engine, PHASE_GATE, survivors_milli, garrison_after)
	_beat(engine, PHASE_ROUT, survivors_milli, garrison_after)


func _beat(engine: SimEngine, phase: StringName, army_milli: int, garrison_milli: int) -> void:
	engine.events.record(engine.tick_count, &"assault_beat", phase, army_milli, garrison_milli)


## Draws a per-mille attrition in [from_permille, to_permille] and returns
## the remainder. One RNG draw per call — the draw-count contract above.
func _bleed(engine: SimEngine, value_milli: int, from_permille: int, to_permille: int) -> int:
	var hit := engine.rng.randi_range(from_permille, to_permille)
	return value_milli * (PERMILLE - hit) / PERMILLE


func _win_permille(army_milli: int, garrison_milli: int) -> int:
	var total := army_milli + garrison_milli
	if total <= 0:
		return 0
	return clampi(army_milli * PERMILLE / total, 0, PERMILLE)


## The regime's ONE combat modifier, resolved to its kind (&"" when the run
## is regime-less — neutral multipliers both sides).
func _combat_kind(engine: SimEngine) -> StringName:
	var regime := _regime(engine)
	if regime == null or regime.combat_modifier == null:
		return &""
	return regime.combat_modifier.kind


func _army_multiplier_milli(engine: SimEngine) -> int:
	var regime := _regime(engine)
	if regime == null or regime.combat_modifier == null:
		return SimFixed.MILLI
	if regime.combat_modifier.kind != &"army_score_multiplier":
		return SimFixed.MILLI
	return SimFixed.milli_from_float(regime.combat_modifier.value)


func _garrison_multiplier_milli(engine: SimEngine) -> int:
	var regime := _regime(engine)
	if regime == null or regime.combat_modifier == null:
		return SimFixed.MILLI
	if regime.combat_modifier.kind != &"garrison_multiplier":
		return SimFixed.MILLI
	return SimFixed.milli_from_float(regime.combat_modifier.value)


# --- L2 escalation internals ---------------------------------------------------


## The escalation garrison breakdown (the odds screen's castle-side data),
## or {} when the STATIC baseline rules — the zero-impact gate. Escalation
## is active only when ALL hold: the run system exposes the shared meta, a
## non-empty snapshot stands there, and this resolver can resolve it to a
## positive power (an UNWIRED resolver — no content passed at construction,
## the pre-L2 sites — or a snapshot whose every id left the pack — derives
## 0 and falls back to the static garrison rather than a zero-strength
## castle that would auto-win every assault).
##
## The math (exact integers, two floored divisions — pinned by test):
##   snapshot_power = Escalation.roster_power(snapshot, unit+gear defs)
##   curve_milli    = Escalation.curve_multiplier_milli(step, cycle)
##   base_power     = snapshot_power * curve_milli / 1000
##   mult           = the SNAPSHOT regime's garrison_multiplier milli
##                    (save-schema §6: the reader resolves the winning
##                    regime's combat modifier; unknown/absent/army-kind
##                    regime -> neutral x1000. The CURRENT run's regime
##                    still scales the ARMY side only.)
##   strength_milli = base_power * mult
##
## Transparency (L2-C's data): the dict carries the static four keys FIRST
## (base_power/modifier_kind/regime_multiplier_milli/strength_milli — same
## invariants: strength == base x mult, and the two sides reproduce
## win_permille to the digit) plus `source: &"escalation"`, the cycle, the
## snapshot's raw + curved power, and WHOSE army stands on the wall —
## regime id, leader, captured-at run, and the full roster/tier mix.
func _escalation_garrison(engine: SimEngine) -> Dictionary:
	var run: Variant = engine.get_system(&"run")
	if run == null or not run.has_method("escalation_garrison"):
		return {}
	var snapshot: Dictionary = run.escalation_garrison()
	if snapshot.is_empty():
		return {}
	var snapshot_power := Escalation.roster_power(
		snapshot, _unit_defs, _gear_defs, _escalation_warned
	)
	if snapshot_power <= 0:
		return {}
	var cycle := maxi(1, int(run.escalation_cycle()))
	var curve_milli := Escalation.curve_multiplier_milli(_escalation_step_milli, cycle)
	var base_power := snapshot_power * curve_milli / SimFixed.MILLI
	var regime := _snapshot_regime(snapshot)
	var mult := SimFixed.MILLI
	var kind := &""
	if regime != null and regime.combat_modifier != null:
		kind = regime.combat_modifier.kind
		if kind == &"garrison_multiplier":
			mult = SimFixed.milli_from_float(regime.combat_modifier.value)
	var roster: Dictionary = snapshot.get("roster", {})
	return {
		"base_power": base_power,
		"modifier_kind": kind,
		"regime_multiplier_milli": mult,
		"strength_milli": base_power * mult,
		"source": &"escalation",
		"escalation_cycle": cycle,
		"snapshot_power": snapshot_power,
		"curve_multiplier_milli": curve_milli,
		"regime_id": String(snapshot.get("regime_id", "")),
		"leader": String(snapshot.get("leader", "")),
		"captured_at_run": int(snapshot.get("captured_at_run", 0)),
		"roster": roster.duplicate(true),
	}


## The SNAPSHOT's regime def, resolved against the wired pack (null when
## unresolvable — the meta-domain reader's neutral fallback, mirroring the
## run system's unknown-regime rule without the per-query warning spam).
func _snapshot_regime(snapshot: Dictionary) -> RegimeDef:
	var id := String(snapshot.get("regime_id", ""))
	if id.is_empty():
		return null
	return _regimes_by_id.get(id)


## The run's APPLIED veterans multiplier (L1-B2), read through the run
## system — the stateless resolver's window onto run-scoped legacy config,
## exactly the `_regime` shape. Identity (1000) for regime-less runs, runs
## without a legacy provider, and any run whose bundle bought no veterans
## node — the pre-L1-B2 odds to the digit.
func _veterans_multiplier_milli(engine: SimEngine) -> int:
	var run: Variant = engine.get_system(&"run")
	if run == null or not run.has_method("legacy_veterans_milli"):
		return SimFixed.MILLI
	return int(run.legacy_veterans_milli())


func _regime(engine: SimEngine) -> RegimeDef:
	var run: Variant = engine.get_system(&"run")
	if run == null or not run.has_method("current_regime"):
		return null
	var regime: RegimeDef = run.current_regime()
	return regime


func _regime_id(engine: SimEngine) -> StringName:
	var regime := _regime(engine)
	return &"" if regime == null else regime.id


func _deny(engine: SimEngine, reason: int) -> void:
	# value2 = live army power (the UI's "you need X more" line).
	var power := 0
	var units: Variant = engine.get_system(&"units")
	if units != null and units.has_method("army_power"):
		power = int(units.army_power())
	engine.events.record(engine.tick_count, &"assault_denied", &"assault", reason, power)
