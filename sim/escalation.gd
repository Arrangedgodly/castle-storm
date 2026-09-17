## Escalation — the L2 enemy-escalation math as pure functions (post-MVP
## Layer 2, docs/sim-engine.md §19; town-hall L2: "on victory, a snapshot of
## your winning army becomes the next cycle's castle garrison — your
## previous knights are the enemy").
##
## NO STATE, NO SYSTEM, NO TICKS: like LegacyModifiers this is a pure
## data-derived helper, not a SimSystem and not a host service. Two sites
## own the two halves:
##
##   - CAPTURE (RunLifecycleSystem._end_run, victory only): `capture()`
##     walks the units system's terminal army roster through its documented
##     read API (army_contributions + unit_gear/gear_tier — the same
##     terminal-roster walk that feeds the chronicle's `army` line) and
##     composes the JSON-safe snapshot dict carried by RunMeta
##     (`escalation_garrison`, meta save domain, docs/save-schema.md §6).
##
##   - DERIVATION (AssaultResolver.assault_odds, stateless): when a
##     snapshot exists, `roster_power()` resolves its ids against boot
##     content (rule §3.2: ids, not objects — combat values are NEVER
##     re-serialized) into the snapshot's army-power-equivalent, and
##     `curve_multiplier_milli()` scales it by the escalation curve
##     (EconomyTunables.escalation_garrison_cycle_step compounded per
##     cycle — the L2-A placeholder curve, tuned by the L2-B balance pass).
##
## Snapshot shape (docs/save-schema.md §6 — the T-DATA-03 reserve, now
## live; versioned by META_FORMAT_VERSION, no nested version field):
##
##   {
##     "regime_id": "gilded_crown",       # the WINNING run's regime pack id
##     "captured_at_run": 7,              # meta-monotonic run number
##     "cycle": 1,                        # the escalation cycle this opens
##     "leader": "Bran the Unbearable",   # the winning leader ("regime remembers")
##     "crest_id": "crest_gilded_crown",  # the regime's crest (L2-C flavor)
##     "roster": {
##       "knight": {"count": 12, "gear_tiers": {"weapon": {"1": 2, "3": 10}}},
##       "archer": {"count": 9, "gear_tiers": {"weapon": {"1": 9}}}
##     }
##   }
##
## Determinism: capture walks the roster in roster order (dict insertion
## order is the def's first appearance — ordered state, rule §3.5); power
## sums are exact integer math (content floats cross SimFixed.milli_from_float
## ONCE, in the resolver's constructor). Zero RNG draws anywhere.
class_name Escalation
extends RefCounted

## Cap on curve compounding hops (cycle - 1). Cycles are a ladder the
## player climbs one victory at a time — 63 hops of any legal step (< x4)
## stays far inside int64 while making the ladder effectively unbounded.
const MAX_CURVE_HOPS := 63


## Composes the garrison snapshot from the units system's LIVE terminal
## roster (victory capture — the roster is terminal at victory; restart
## clears it, this reads whatever stands). Returns {} when there is no
## standing army: a victory over an empty roster writes NO snapshot (an
## empty castle garrisons nothing) and the prior garrison — the regime
## that beat you — stays until beaten, exactly as the fantasy demands.
##
## `p_units` is the units system (Variant: probed through has_method at the
## call sites' pattern); `p_regime` may be null (regime-less victory — the
## snapshot carries empty ids and the reader resolves neutral multipliers).
## `p_captured_at_run` is the meta-monotonic run number (the chronicle
## entry's own); `p_cycle` is the escalation cycle this snapshot OPENS
## (previous count + 1).
static func capture(
	p_units: Variant,
	p_regime: RegimeDef,
	p_leader: String,
	p_captured_at_run: int,
	p_cycle: int
) -> Dictionary:
	if p_units == null or not p_units.has_method("army_contributions"):
		return {}
	var roster := {}
	for entry in p_units.army_contributions():
		var def_id := String(entry["def"])
		if not roster.has(def_id):
			roster[def_id] = {"count": 0, "gear_tiers": {}}
		var line: Dictionary = roster[def_id]
		line["count"] = int(line["count"]) + 1
		var uid := int(entry["uid"])
		var gear_tiers: Dictionary = line["gear_tiers"]
		for slot in p_units.unit_gear(uid).keys():
			var tier := int(p_units.gear_tier(uid, slot))
			if tier <= 0:
				continue  # a gear id that left the pack: the body counts, the kit does not
			var slot_key := String(slot)
			if not gear_tiers.has(slot_key):
				gear_tiers[slot_key] = {}
			var tiers: Dictionary = gear_tiers[slot_key]
			var tier_key := str(tier)
			tiers[tier_key] = int(tiers.get(tier_key, 0)) + 1
	if roster.is_empty():
		return {}
	return {
		"regime_id": "" if p_regime == null else String(p_regime.id),
		"captured_at_run": p_captured_at_run,
		"cycle": p_cycle,
		"leader": p_leader,
		"crest_id": "" if p_regime == null else String(p_regime.crest_id),
		"roster": roster,
	}


## The snapshot's army-power-equivalent: sum over the roster of
##   count x UnitDef.combat_power          (per army-eligible def)
## + tier_count x GearDef.combat_power     (per slot x tier line)
## — exactly the units system's army_power() arithmetic recomputed from the
## compact snapshot. Ids resolve against boot content (same pack at boot);
## an id that left the pack is skipped LOUDLY (once per id per caller —
## pass a shared `warned` set; the resolver reuses one across its queries
## so a per-frame odds read never floods the log) and never silently
## defaulted. Unknown ids skipping to 0 total is the caller's static-
## garrison fallback contract.
static func roster_power(
	p_snapshot: Dictionary,
	p_unit_defs: Array[UnitDef],
	p_gear_defs: Array[GearDef],
	p_warned: Dictionary = {}
) -> int:
	var power := 0
	var roster: Dictionary = p_snapshot.get("roster", {})
	for def_id in roster.keys():
		var line: Dictionary = roster.get(def_id, {})
		var count := int(line.get("count", 0))
		var unit := _unit_def(String(def_id), p_unit_defs)
		if unit == null:
			_warn_once(p_warned, "escalation: snapshot unit '%s' not in pack — body skipped" % def_id)
			count = 0
		else:
			power += count * unit.combat_power
		var gear_tiers: Dictionary = line.get("gear_tiers", {})
		for slot in gear_tiers.keys():
			var tiers: Dictionary = gear_tiers.get(slot, {})
			for tier in tiers.keys():
				var tier_count := int(tiers.get(tier, 0))
				var gear_power := gear_combat_power(String(slot), int(tier), p_gear_defs)
				if gear_power < 0:
					_warn_once(
						p_warned,
						"escalation: snapshot gear (slot '%s', tier %s) not in pack — kit skipped"
						% [slot, tier]
					)
					continue
				power += tier_count * gear_power
	return power


## GearDef combat power for a (slot, tier) pair, or -1 when the pack has no
## such gear. First pack-order match wins (a pack may carry several gear
## lines per slot+tier; deterministic boot order is the tiebreak).
static func gear_combat_power(p_slot: String, p_tier: int, p_gear_defs: Array[GearDef]) -> int:
	for gear in p_gear_defs:
		if gear == null:
			continue
		if String(gear.slot) == p_slot and gear.tier == p_tier:
			return gear.combat_power
	return -1


## The escalation curve, as exact integer milli: step_milli compounded
## (cycle - 1) times — cycle 1 (the first snapshot) is identity x1.000
## because the SNAPSHOT ITSELF is the first escalation (a typical winning
## army power ~100 already doubles the static 50 wall); every later
## captured cycle compounds the step. One floored int division per hop
## (the growth-table pattern); hops capped at MAX_CURVE_HOPS.
static func curve_multiplier_milli(p_step_milli: int, p_cycle: int) -> int:
	var multiplier := SimFixed.MILLI
	var hops := clampi(p_cycle - 1, 0, MAX_CURVE_HOPS)
	for _i in hops:
		multiplier = multiplier * p_step_milli / SimFixed.MILLI
	return multiplier


static func _unit_def(p_id: String, p_defs: Array[UnitDef]) -> UnitDef:
	for unit in p_defs:
		if unit != null and String(unit.id) == p_id:
			return unit
	return null


static func _warn_once(p_warned: Dictionary, p_message: String) -> void:
	var key := p_message.split(" — ")[0]
	if p_warned.has(key):
		return
	p_warned[key] = true
	push_warning(p_message)
