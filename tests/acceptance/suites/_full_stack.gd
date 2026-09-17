## The canonical game-host composition (T-QA-02) — THE REFERENCE HOST.
##
## This file is where the "real game" composition is defined once, so CI and
## the UI cannot drift apart:
##
##   - T-UI-03 (The Spread) builds its live engine from THIS shape — the
##     registration order, the meta wiring and the catch-up wiring below are
##     the contract, not a test-only convenience.
##   - The T-QA-02 suites (`economy_stability_1000h`, `full_run_ci`) drive
##     exactly this composition, so "CI green" means "the composition the
##     player runs is stable".
##   - The `save_debug` tool and any future host shell compose the same way.
##
## COMPOSITION (all six registrations; five gameplay systems + the heartbeat
## placeholder), in the ONE contractual order (docs/sim-engine.md §4/§14/§15):
##
##   1. HeartbeatSystem   — placeholder cadence
##   2. RunLifecycleSystem — the run frame (identity/regime, banking, reset)
##   3. UnitLifecycleSystem — recruits, training, gear, army
##   4. ProductionSystem  — buildings, workers, the resource pool
##   5. AssaultResolver   — stateless resolver (no tick state by design)
##   6. SuspicionSystem   — LAST: it audits siblings at the tick boundary
##
## Host wiring beyond the engine (the part a bare `SimEngine` does not have):
## one `RunMeta` (the meta save domain — chronicle + bank + catch-up anchor)
## shared by EVERY engine the session builds, and one `CatchUpService`
## constructed from the pack's tunables. `HostSession.build_engine()`
## re-inits the engine around the same meta — the host-side form of restart
## (docs/sim-engine.md §12: both restart forms are equivalent; the meta
## survives either).
##
## SIBLING IMPACT ZERO (the standing rule): the shared `full_stack` fixture
## in `_mvp_pack.gd` stays suspicion/assault-free so every pre-T-SIM-05/06
## marathon hash stays byte-identical. THIS file is the opt-in full stack —
## nothing that hashes against `_mvp_pack.full_stack` touches it.
##
## Also here: `manage()` — the scripted sensible-play policy (build order,
## staffing, training queues, gear crafting; a simple greedy driver issuing
## ONLY engine commands). It is shared by both T-QA-02 suites so "the policy
## CI asserts stability under" is one audited function, not two drifting
## copies. Determinism: pure reads -> commands, zero test-side RNG.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")


## The canonical five-system engine (see the header — THIS is the reference
## composition T-UI-03 consumes). `meta` is the shared meta-domain bank the
## host hands to every engine it builds; `stipend` overrides the pack's
## starting grants (pass MVP.MARATHON_STIPEND for marathon funds; the
## default `{}` boots the honest pack stipend — what the shipped game does).
## `p_tunables` overrides the pack's tunables — used ONLY by the T-SIM-08
## balance sweep (`scripts/balance_sweep.gd`) to evaluate candidate values
## against exactly this composition; the default `null` runs the pack's
## tuned content, which is what CI asserts and what ships. `p_legacy`
## (additive, L1) wires the legacy unlock-tree provider exactly the way
## GameHost does — null/empty-owned resolves identity modifiers and the
## engine stays byte-identical to the pre-L1 build (pinned by
## test_legacy_run_effects); the balance sweep's full-tree probe passes a
## purchase-everything LegacySystem. `p_escalation` (additive, L2) wires
## the assault resolver's escalation content exactly the way GameHost
## does — DEFAULT FALSE: the shared suites' recorded digests and the
## balance-band pins are measured against the STATIC garrison ladder, so
## they stay unwired until the L2-B balance pass re-sweeps with escalation
## on (a fresh meta behaves identically either way — the zero-impact rule,
## docs/sim-engine.md §19; GameHost itself always wires, so the shipped
## game escalates).
static func game_stack(run_seed: int, meta: RunMeta, stipend: Dictionary = {}, p_tunables: EconomyTunables = null, p_legacy: LegacySystem = null, p_escalation := false) -> SimEngine:
	var pack := MVP.load_mvp()
	var tunables := p_tunables if p_tunables != null else pack.tunables
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, meta, stipend if not stipend.is_empty() else pack.starting_grants, p_legacy))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, tunables, null))
	if p_escalation:
		engine.register_system(AssaultResolver.new(tunables, pack.units, pack.gear, pack.regimes))
	else:
		engine.register_system(AssaultResolver.new(tunables))
	engine.register_system(SuspicionSystem.new(tunables, pack.units, pack.copy))
	return engine


## HostSession factory (the ONLY supported construction path — it injects
## the canonical composition, so a session can never be built from a stale
## copy of the system order).
static func session(run_seed: int, stipend: Dictionary = {}, p_tunables: EconomyTunables = null, p_legacy: LegacySystem = null, p_escalation := false) -> HostSession:
	var factory := func(p_seed: int, p_meta: RunMeta, p_stipend: Dictionary) -> SimEngine:
		return game_stack(p_seed, p_meta, p_stipend, p_tunables, p_legacy, p_escalation)
	return HostSession.new(run_seed, stipend, factory, p_tunables)


## One host session: the meta bank + the catch-up service + the current
## engine. This is the object the UI host owns one of (T-UI-03/T-PERF-01).
## Construct via the `session()` factory (GDScript inner classes cannot call
## the outer script's statics, so the canonical composition is INJECTED as
## the factory closure — defined once, in `game_stack`, never duplicated).
class HostSession:
	extends RefCounted

	## The meta save domain (chronicle + legacy bank + catch-up anchor).
	## Shared by every engine this session builds — the bank must survive
	## restarts and must never be forked from a run save.
	var meta: RunMeta

	## The foreground-boundary service (docs/catch-up.md). Timestamps are
	## ALWAYS injected by the platform host; sim/ reads no clock.
	var catch_up: CatchUpService

	## The current engine (replaced wholesale by `build_engine()` on the
	## host-side restart form; `run_restart` in-engine is the other form).
	var engine: SimEngine

	var _run_seed: int
	var _stipend: Dictionary
	var _factory: Callable


	func _init(p_run_seed: int, p_stipend: Dictionary, p_factory: Callable, p_tunables: EconomyTunables = null) -> void:
		meta = RunMeta.new()
		catch_up = CatchUpService.new(p_tunables if p_tunables != null else MVP.load_mvp().tunables)
		_run_seed = p_run_seed
		_stipend = p_stipend
		_factory = p_factory
		engine = _factory.call(_run_seed, meta, _stipend)


	## Builds a FRESH engine bound to the same meta — the host-side restart
	## (identical to the in-engine `run_restart` by design; the meta domain
	## survives both). Also the "process restart" shape for save/load tests.
	func build_engine() -> SimEngine:
		engine = _factory.call(_run_seed, meta, _stipend)
		return engine


	## Foreground boundary: resolves one away window through the real
	## engine. `now_epoch` is an injected UTC timestamp (determinism: the
	## engine state never sees it; only the anchor does).
	func foreground(now_epoch: int) -> Dictionary:
		return catch_up.apply(engine, meta, now_epoch)


	## Background/save hook: refresh the anchor so away time is measured
	## from here (docs/catch-up.md §2).
	func mark_seen(now_epoch: int) -> void:
		catch_up.mark_seen(meta, now_epoch)


## The scripted sensible-play policy — the T-QA-02 "player". Greedy, audits
## the estate through documented read APIs and issues ONLY engine commands
## (never set_resource / set_suspicion). Runs once per management batch;
## commands drain at the first tick of the following window (the engine's
## tick-aligned contract), so reads describe the world as of the batch.
##
## `military_cap` bounds the army pipeline (workers are the default branch).
## `opts`:
##   &"laying_low"      bool  — the R4 tension response: while the meter is
##                              in the crackdown zone (>= 70) the conspiracy
##                              starts no new trainings and raises no new
##                              walls (the loud acts); the gate still thins
##                              (accepting is not a loud act and a crowd at
##                              the gate IS presence) and the forge still
##                              crafts (gear equips are not acts).
##   &"population_cap"  int   — 0 = accept every arrival; > 0 = stop
##                              accepting once total units reach the cap
##                              (a small conspiracy is a quiet conspiracy —
##                              but see the gate-crowd presence trade the
##                              stability suite measures).
##   &"no_dismiss"       bool  — true = the pre-T-SIM-08 player: never uses
##                              the dismissal affordance (the balance
##                              sweep's "before" decomposition row; CI
##                              suites leave it off — sensible play sends
##                              the loiterers home).
##
## Returns the spend LEDGER for the batch — {resource id -> int spent} for
## every upgrade cost + gear recipe the submitted commands will pay when
## they drain — so suites can account window spending exactly (production
## = stock delta + spent + seized - granted). Grants are NOT included.
static func manage(engine: SimEngine, military_cap: int, opts: Dictionary = {}) -> Dictionary:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var laying_low := bool(opts.get(&"laying_low", false))
	var population_cap := int(opts.get(&"population_cap", 0))
	var no_dismiss := bool(opts.get(&"no_dismiss", false))
	var funds := {}
	for id in engine.resources.keys():
		funds[id] = int(engine.resources[id])
	var ledger := {}

	# 1) Gate: keep it thin — pending offers are presence (0.25/h each) and
	#    a crowded gate turns every arrival into a loud act. Accepting is
	#    quiet; a cap only slows the estate's growth. ROOM is counted
	#    locally: the accepts are commands that drain NEXT tick, so reading
	#    total_units() inside the loop would see stale state and overshoot
	#    the cap by up to the offer count (measured by the T-SIM-08 sweep:
	#    26 units under a 24 cap). At the cap the remaining loiterers are
	#    SENT HOME (T-SIM-08's dismissal affordance): turning a recruit
	#    away is the quiet lever — it costs nothing, drops the gate's
	#    presence to zero, and unfreezes the arrival countdown if the gate
	#    was full.
	var room := maxi(0, population_cap - units.total_units()) if population_cap > 0 else units.pending_offers()
	var accepted := {}
	for uid in units.offer_ids():
		if room <= 0:
			break
		engine.submit_command(&"recruit_accept", &"", uid)
		accepted[uid] = true
		room -= 1
	if not no_dismiss and population_cap > 0 \
			and units.total_units() + units.pending_offers() > population_cap:
		for uid in units.offer_ids():
			if not accepted.has(uid):
				engine.submit_command(&"dismiss_offer", &"", uid)

	# 2) Roles: peasants branch — military up to the cap (never while laying
	#    low), everyone else into the workforce.
	var military := _military_total(units)
	var workers := units.unit_count(&"worker")
	for uid in units.idle_units(&"peasant"):
		if not laying_low and workers >= 2 and military < military_cap:
			military += 1
			engine.submit_command(&"assign_role", &"militia", uid)
		else:
			workers += 1
			engine.submit_command(&"assign_role", &"worker", uid)

	# 3) Training queues: militia -> trainee, trainee -> the currently
	#    thinner army rank (a balanced assembly line; never while laying low).
	if not laying_low:
		for uid in units.idle_units(&"militia"):
			engine.submit_command(&"start_training", &"trainee", uid)
		var knights := units.unit_count(&"knight")
		var archers := units.unit_count(&"archer")
		for uid in units.unit_ids():
			var target := units.training_target(uid)
			if target == &"knight":
				knights += 1
			elif target == &"archer":
				archers += 1
		for uid in units.idle_units(&"trainee"):
			if knights <= archers:
				knights += 1
				engine.submit_command(&"start_training", &"knight", uid)
			else:
				archers += 1
				engine.submit_command(&"start_training", &"archer", uid)

	# 4) Gear crafting + promotion: cheapest affordable gear per missing
	#    slot, then promote once the kit is complete. The forge works even
	#    while laying low — equipping gear is not a loud act.
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			for gear_id in units.gear_ids_for_slot(slot):
				if _affordable(gear_id, funds):
					_pay_gear(gear_id, funds, ledger)
					engine.submit_command(&"equip_gear", gear_id, uid)
					break
		if units.missing_gear_slots(uid).is_empty():
			engine.submit_command(&"promote", &"", uid)

	# 5) Staffing: idle workers onto the least-assigned producer with a free
	#    slot (spread the crew across the estate).
	var idle := production.idle_workers()
	var assigned := {}
	for id in MVP.producer_ids():
		assigned[id] = production.assigned_workers(id)
	while idle > 0:
		var pick: StringName = &""
		for id in MVP.producer_ids():
			if production.worker_slots(id) - int(assigned[id]) > 0 \
					and (pick == &"" or int(assigned[id]) < int(assigned[pick])):
				pick = id
		if pick == &"":
			break
		engine.submit_command(&"assign_worker", pick, 1)
		assigned[pick] = int(assigned[pick]) + 1
		idle -= 1

	# 6) Build order: construct every unbuilt (affordable) building first,
	#    then one upgrade per batch — the lowest-level producer whose cost is
	#    affordable (grow the estate evenly). Both are loud acts (+4/level):
	#    suspended while laying low.
	if not laying_low:
		for id in MVP.building_ids():
			if production.building_level(id) > 0:
				continue
			var build_cost := production.upgrade_cost(id)
			if _try_pay(build_cost, funds, ledger):
				engine.submit_command(&"upgrade_building", id, 1)
		var pick: StringName = &""
		var pick_level := -1
		for id in MVP.producer_ids():
			var level: int = production.building_level(id)
			if level < 1:
				continue
			if (pick_level < 0 or level < pick_level) \
					and _affordable_cost(production.upgrade_cost(id), funds):
				pick = id
				pick_level = level
		if pick != &"":
			if _try_pay(production.upgrade_cost(pick), funds, ledger):
				engine.submit_command(&"upgrade_building", pick, 1)
	return ledger


## Army pipeline size: committed ranks plus every unit training toward one.
static func _military_total(units: UnitLifecycleSystem) -> int:
	var total := units.unit_count(&"militia") + units.unit_count(&"trainee") \
		+ units.unit_count(&"knight") + units.unit_count(&"archer")
	for uid in units.unit_ids():
		var target := units.training_target(uid)
		if target == &"militia" or target == &"trainee" \
				or target == &"knight" or target == &"archer":
			total += 1
	return total


static func _gear_recipe(gear_id: StringName) -> Dictionary:
	for gear in MVP.load_mvp().gear:
		if gear.id == gear_id:
			return gear.recipe
	return {}


static func _affordable(gear_id: StringName, funds: Dictionary) -> bool:
	return _affordable_cost(_gear_recipe(gear_id), funds)


static func _affordable_cost(cost: Dictionary, funds: Dictionary) -> bool:
	if cost.is_empty():
		return false
	for resource in cost:
		if int(funds.get(resource, 0)) < int(cost[resource]):
			return false
	return true


static func _pay_gear(gear_id: StringName, funds: Dictionary, ledger: Dictionary) -> void:
	_pay_cost(_gear_recipe(gear_id), funds, ledger)


static func _try_pay(cost: Dictionary, funds: Dictionary, ledger: Dictionary) -> bool:
	if not _affordable_cost(cost, funds):
		return false
	_pay_cost(cost, funds, ledger)
	return true


static func _pay_cost(cost: Dictionary, funds: Dictionary, ledger: Dictionary) -> void:
	for resource in cost:
		funds[resource] = int(funds.get(resource, 0)) - int(cost[resource])
		ledger[resource] = int(ledger.get(resource, 0)) + int(cost[resource])
