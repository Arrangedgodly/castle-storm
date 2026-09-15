## Acceptance marathon — 1000 sim-hours of units flowing (T-SIM-03; content:
## the T-DATA-02 MVP pack).
##
## Full stack (heartbeat + run + units + production): a run starts, the
## stipend arrives through the grant_resources command (F1), peasants arrive
## on the seeded-jitter cadence, get accepted, branch worker/military, train,
## gear up (cheapest tier first) and promote across 60,000 one-minute ticks
## while the farm/lumber_camp/smithy economy runs underneath — then fielded
## ranks refit to the next gear tier each batch, so every tier's recipe
## crosses the economy. Proves: the arrival band is sane and REPRODUCIBLE
## (same seed -> same arrival count and hash), the worker handoff feeds
## production's pool exactly (assigned + idle == bootstrap + worker
## promotions), army ranks emerge on both branches at every gear tier, the
## arrivals == offers + units conservation law holds, and a mid-run (500h)
## save round-trip resumes in lockstep with in-flight training and partial
## gear. Measures and reports the marathon rate so T-SIM-03's weight on the
## engine stays visible in CI output.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const SIM_HOURS := 1000
const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const BOOTSTRAP_WORKERS := 4  # pre-arrival starting crew via add_worker
const MAX_TIER := 3

## Gear tiers fielded during the MAIN run (observed host-side across the
## management batches + the final roster): proves every tier's recipe was
## actually PAID, not merely present in content. A t3 holder also proves its
## t2 refit happened (re-equips require a strictly higher tier), so the set
## is evidence even when no unit happens to rest at t2 at the snapshot.
var _tiers_fielded := {}


func suite_name() -> String:
	return "marathon_units_1000h"


func run(harness) -> void:
	var total_ticks := SIM_HOURS * SimEngine.TICKS_PER_SIM_HOUR

	# --- Main run: arrivals + assignments + promotions, timed.
	var first := _build()
	_seed_run(first)
	var clock_start := Time.get_ticks_msec()
	var ran := _run_script(first, total_ticks)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var rate := float(total_ticks) / wall
	var units := first.get_system(&"units") as UnitLifecycleSystem
	var production := first.get_system(&"production") as ProductionSystem
	# The final roster completes the tier observation (the last cohort was
	# equipped after the final management batch).
	for uid in units.unit_ids():
		for slot in MVP.load_mvp().gear_slots:
			var tier: int = units.gear_tier(uid, slot)
			if tier > 0:
				_tiers_fielded[tier] = true

	print(
		"[marathon_units_1000h] %d ticks (%d sim-hours, %d arrivals, %d workers, %d knights, %d archers, army power %d) in %.3fs — %.0f ticks/s; state_hash=%d"
		% [
			total_ticks, SIM_HOURS, units.arrivals_total, units.unit_count(&"worker"),
			units.unit_count(&"knight"), units.unit_count(&"archer"), units.army_power(),
			wall, rate, first.state_hash(),
		]
	)

	harness.check(ran == total_ticks, "fast_forward ran all %d ticks" % total_ticks)
	harness.check(wall < BUDGET_SECONDS, "1000h units flow in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Determinism: same construction, seed, command script -> same hash.
	var second := _build()
	_seed_run(second)
	_run_script(second, total_ticks)
	var second_units := second.get_system(&"units") as UnitLifecycleSystem
	harness.check(first.state_hash() == second.state_hash(), "same seed + script -> same 1000h units hash")
	harness.check(
		units.arrivals_total == second_units.arrivals_total,
		"arrival count reproducible: %d" % units.arrivals_total
	)
	harness.check(first.rng.state == second.rng.state, "rng stream identical (arrival jitters + run draws only)")

	# --- Arrival band: 2h +/- 0.25h cadence over 1000h -> [440, 575].
	harness.check(
		units.arrivals_total >= 440 and units.arrivals_total <= 575,
		"arrivals within the cadence band [440, 575]: %d" % units.arrivals_total
	)

	# --- Units flowed: workers fed the economy, both branches promoted.
	harness.check(units.unit_count(&"worker") > 250, "workers emerged: %d" % units.unit_count(&"worker"))
	harness.check(units.unit_count(&"knight") > 20, "knights emerged: %d" % units.unit_count(&"knight"))
	harness.check(units.unit_count(&"archer") > 20, "archers emerged: %d" % units.unit_count(&"archer"))
	harness.check(units.army_power() > 0, "army power positive: %d" % units.army_power())
	harness.check(units.pending_offers() >= 0, "gate never negative: %d" % units.pending_offers())

	# --- Conservation: every arrival is either waiting or accepted.
	harness.check(
		units.arrivals_total == units.pending_offers() + units.total_units(),
		"arrivals (%d) == offers (%d) + units (%d)"
		% [units.arrivals_total, units.pending_offers(), units.total_units()]
	)

	# --- Cross-system invariant: the worker handoff fed production EXACTLY
	# (no leaks, no double-counting; nothing removed at this stage).
	var employed: int = production.idle_workers() \
		+ production.assigned_workers(&"farm") \
		+ production.assigned_workers(&"lumber_camp") \
		+ production.assigned_workers(&"smithy")
	harness.check(
		employed == BOOTSTRAP_WORKERS + units.unit_count(&"worker"),
		"production pool == bootstrap %d + worker promotions %d (got %d)"
		% [BOOTSTRAP_WORKERS, units.unit_count(&"worker"), employed]
	)

	# --- Economy actually ran under the unit flow: every promoted rank is
	# walking around in paid-for gear (recipes were charged at equip time),
	# and every TIER 1..3 was equipped at least once (the full pack's gear
	# ladder is exercised end to end).
	var geared := 0
	for uid in units.unit_ids():
		if units.gear_tier(uid, &"weapon") > 0 or units.gear_tier(uid, &"armor") > 0:
			geared += 1
	harness.check(
		geared >= units.unit_count(&"knight") + units.unit_count(&"archer"),
		"every knight/archer holds paid gear: %d geared vs %d promoted" % [geared, units.unit_count(&"knight") + units.unit_count(&"archer")]
	)
	for tier in range(1, MAX_TIER + 1):
		harness.check(_tiers_fielded.has(tier), "gear tier %d fielded during the run (tiers seen: %s — all tiers' recipes exercised)" % [tier, str(_tiers_fielded.keys())])
	for id: StringName in MVP.load_mvp().resources:
		harness.check(first.get_resource(id) > 0, "%s pool positive: %d" % [id, first.get_resource(id)])

	# --- Mid-run save round-trip at 500h: in-flight training + partial
	# gear cross the boundary; twin resumes in lockstep to 1000h.
	var half := _build()
	_seed_run(half)
	_run_script(half, total_ticks / 2)
	var captured := half.to_dict()
	var resumed := _build()
	harness.check(resumed.apply_state_dict(captured), "state dict applies at 500h")
	harness.check(resumed.state_hash() == half.state_hash(), "restored hash == original at 500h")
	_run_script(half, total_ticks)
	_run_script(resumed, total_ticks)
	harness.check(
		half.state_hash() == resumed.state_hash(),
		"500h save round-trip lockstep to 1000h (hash %d vs %d)" % [half.state_hash(), resumed.state_hash()]
	)


# --- Run scripting ----------------------------------------------------------


## Queues the boot commands (drained at tick 1): run_start, stipend via the
## grant verb (F1), bootstrap crew, build the producers.
func _seed_run(engine: SimEngine) -> void:
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.submit_command(&"add_worker", &"production", BOOTSTRAP_WORKERS)
	for id in MVP.producer_ids():
		engine.submit_command(&"upgrade_building", id, 1)


## One deterministic management batch: accept the gate, branch the idle
## peasants (every third takes the military path), advance the military
## path, gear + promote the held ranks (cheapest option per missing slot),
## refit fielded ranks to the next gear tier (every tier's recipe paid),
## and keep the growing worker pool employed. Pure reads -> commands; no RNG.
func _manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	var index := 0
	for uid in units.idle_units(&"peasant"):
		index += 1
		engine.submit_command(&"assign_role", &"militia" if index % 3 == 0 else &"worker", uid)
	for uid in units.idle_units(&"militia"):
		engine.submit_command(&"start_training", &"trainee", uid)
	# Branch the trainees toward the CURRENTLY FEWER committed rank
	# (state-derived, not batch-local: a lone trainee still alternates
	# across batches). Committed = promoted + awaiting + mid-training.
	var knight_committed := units.unit_count(&"knight")
	var archer_committed := units.unit_count(&"archer")
	for uid in units.unit_ids():
		var target := units.training_target(uid)
		if target == &"knight":
			knight_committed += 1
		elif target == &"archer":
			archer_committed += 1
	for uid in units.idle_units(&"trainee"):
		if knight_committed <= archer_committed:
			knight_committed += 1
			engine.submit_command(&"start_training", &"knight", uid)
		else:
			archer_committed += 1
			engine.submit_command(&"start_training", &"archer", uid)
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			var options := units.gear_ids_for_slot(slot)
			if not options.is_empty():
				engine.submit_command(&"equip_gear", options[0], uid)
		engine.submit_command(&"promote", &"", uid)
	# Tier refits: fielded ranks step up to the next tier when one exists
	# (options are tier-sorted, index = tier-1; marathon funds cover it).
	for rank in [&"knight", &"archer"]:
		for uid in units.idle_units(rank):
			for slot in MVP.load_mvp().gear_slots:
				var tier: int = units.gear_tier(uid, slot)
				if tier > 0:
					_tiers_fielded[tier] = true
				var options := units.gear_ids_for_slot(slot)
				if tier > 0 and tier < options.size():
					engine.submit_command(&"equip_gear", options[tier], uid)
	for id in MVP.producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


## Runs total_ticks in 10h chunks with a management batch between chunks
## (commands drain at the next chunk's first tick — identical boundaries
## on every rerun). Returns ticks run.
func _run_script(engine: SimEngine, total_ticks: int) -> int:
	var ran := 0
	while ran < total_ticks:
		var chunk: int = mini(CHUNK_TICKS, total_ticks - ran)
		if ran > 0:
			_manage(engine)
		ran += engine.fast_forward(chunk)
	return ran


# --- Fixtures ----------------------------------------------------------------


func _build() -> SimEngine:
	# Registration order mirrors causality: the run frame exists before the
	# recruits/economy it governs. Heartbeat first (engine marathon
	# convention). Marathon funds flow through the grant verb (F1).
	return MVP.full_stack(RUN_SEED, MVP.MARATHON_STIPEND)
