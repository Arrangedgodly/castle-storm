## Acceptance marathon — 1000 sim-hours of real production (T-SIM-02).
##
## Proves the production system accrues food/timber/iron across 60,000
## one-minute ticks without drift or blowup: exact closed-form totals for
## fixed-rate runs (including the x0.85 regime quirk at 1000h scale),
## bounded remainders after an upgrade-heavy scripted run, live-loop ==
## fast-forward equivalence through the production path, and the determinism
## oracle (same construction + seed + command script -> same state_hash;
## different regime -> diverges). Measures and reports the marathon rate so
## T-SIM-02's weight on the engine-only marathon stays visible in CI output.
extends RefCounted

const SIM_HOURS := 1000
const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0
const UPGRADE_CHUNK_TICKS := 600  # one upgrade attempt per building / 10h


func suite_name() -> String:
	return "marathon_production_1000h"


func run(harness) -> void:
	var total_ticks := SIM_HOURS * SimEngine.TICKS_PER_SIM_HOUR

	# --- Main run: 3 producing buildings, upgrade attempts every 10h, timed.
	var first := _build(RUN_SEED, null)
	_seed_run(first)
	var clock_start := Time.get_ticks_msec()
	var ran := _run_script(first, total_ticks)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var rate := float(total_ticks) / wall

	print(
		"[marathon_production_1000h] %d ticks (%d sim-hours, 3 buildings + upgrade cadence) in %.3fs — %.0f ticks/s; state_hash=%d"
		% [total_ticks, SIM_HOURS, wall, rate, first.state_hash()]
	)

	harness.check(ran == total_ticks, "fast_forward ran all %d ticks" % total_ticks)
	harness.check(wall < BUDGET_SECONDS, "1000h production in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Determinism: same construction, seed, command script -> same hash.
	var second := _build(RUN_SEED, null)
	_seed_run(second)
	_run_script(second, total_ticks)
	harness.check(first.state_hash() == second.state_hash(), "same seed + script -> same 1000h production hash")
	harness.check(first.rng.state == second.rng.state, "rng state identical (production draws nothing)")

	# --- Regime quirk run: timber x0.85 diverges, and is itself reproducible.
	var quirk_a := _build(RUN_SEED, _timber_tax_regime())
	_seed_run(quirk_a)
	_run_script(quirk_a, total_ticks)
	harness.check(quirk_a.state_hash() != first.state_hash(), "x0.85 timber tax changes the run")
	var quirk_b := _build(RUN_SEED, _timber_tax_regime())
	_seed_run(quirk_b)
	_run_script(quirk_b, total_ticks)
	harness.check(quirk_a.state_hash() == quirk_b.state_hash(), "quirk run reproducible from seed")

	# --- No drift, no blowup: remainders bounded, levels capped, pool sound.
	var production := first.get_system(&"production") as ProductionSystem
	harness.check(production.building_level(&"farm") == 30, "farm upgraded to max_level 30")
	harness.check(production.building_level(&"camp") == 30, "camp upgraded to max_level 30")
	harness.check(production.building_level(&"mine") == 30, "mine upgraded to max_level 30")
	harness.check(
		production.assigned_workers(&"farm") == 2
			and production.assigned_workers(&"camp") == 2
			and production.assigned_workers(&"mine") == 3,
		"assignments held for the whole run"
	)
	harness.check(production.idle_workers() == 5, "idle pool = 12 - 7 assigned")
	for id in [&"farm", &"camp", &"mine"]:
		var remainder: int = production.accumulated_milli_unit_seconds(id)
		harness.check(
			remainder >= 0 and remainder < SimFixed.UNIT_ACCUM,
			"%s accumulator bounded (no drift/blowup): %d" % [id, remainder]
		)
	for id in [&"food", &"timber", &"iron"]:
		var amount: int = first.get_resource(id)
		harness.check(amount > 0 and amount < 4_611_686_018_427_387_904, "%s pool positive and far from int64 bounds: %d" % [id, amount])

	# --- Exact closed-form: fixed rates accrue EXACTLY over 1000 hours
	# (no upgrades): 2x6/h food, 2x6/h timber, 3x3/h iron, minus build costs
	# from the granted billion.
	var plain := _build(RUN_SEED, null)
	_seed_run(plain)
	plain.fast_forward(total_ticks)
	harness.check(plain.get_resource(&"food") == 1_000_000_000 - 10 - 20 + 12_000, "food exact after 1000h: %d" % plain.get_resource(&"food"))
	harness.check(plain.get_resource(&"timber") == 1_000_000_000 - 15 - 40 + 12_000, "timber exact after 1000h: %d" % plain.get_resource(&"timber"))
	harness.check(plain.get_resource(&"iron") == 1_000_000_000 + 9_000, "iron exact after 1000h: %d" % plain.get_resource(&"iron"))

	# --- Exact closed-form at 1000h with the x0.85 quirk: 2 workers x 6/h
	# x 0.85 = 10.2/h -> 10,200 timber produced exactly (minus the farm+mine
	# build costs paid from the grant), remainder 0 (the carry never drifts).
	var taxed := _build(RUN_SEED, _timber_tax_regime())
	_seed_run(taxed)
	taxed.fast_forward(total_ticks)
	var taxed_expected := 1_000_000_000 - 15 - 40 + 10_200
	harness.check(
		taxed.get_resource(&"timber") == taxed_expected,
		"quirked timber exact: %d (expected %d)" % [taxed.get_resource(&"timber"), taxed_expected]
	)
	harness.check(
		(taxed.get_system(&"production") as ProductionSystem).accumulated_milli_unit_seconds(&"camp") == 0,
		"quirked accumulator empty after 1000h (exact)"
	)

	# --- Live-loop equivalence through the production path: 24h of tick()
	# equals one fast_forward, commands at the same boundaries.
	var looped := _build(RUN_SEED, null)
	_seed_run(looped)
	_command_batch(looped)
	for i in 600:
		looped.tick()
	_command_batch(looped)
	for i in 840:
		looped.tick()
	var skipped := _build(RUN_SEED, null)
	_seed_run(skipped)
	_command_batch(skipped)
	skipped.fast_forward(600)
	_command_batch(skipped)
	skipped.fast_forward(840)
	harness.check(looped.state_hash() == skipped.state_hash(), "tick() x 1440 == fast_forward(1440) with mid-run commands")


# --- Run scripting ----------------------------------------------------------


## Grants the pool and queues the boot commands (drained at tick 1):
## 12 workers, build all three, assign 2/2/3.
func _seed_run(engine: SimEngine) -> void:
	engine.set_resource(&"food", 1_000_000_000)
	engine.set_resource(&"timber", 1_000_000_000)
	engine.set_resource(&"iron", 1_000_000_000)
	engine.submit_command(&"add_worker", &"production", 12)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.submit_command(&"upgrade_building", &"camp", 1)
	engine.submit_command(&"upgrade_building", &"mine", 1)
	engine.submit_command(&"assign_worker", &"farm", 2)
	engine.submit_command(&"assign_worker", &"camp", 2)
	engine.submit_command(&"assign_worker", &"mine", 3)


## One upgrade attempt per building per 10h chunk (deterministic cadence;
## denials at max level are events — cheap and identical across reruns).
func _command_batch(engine: SimEngine) -> void:
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.submit_command(&"upgrade_building", &"camp", 1)
	engine.submit_command(&"upgrade_building", &"mine", 1)


## Runs total_ticks in 10h chunks with a command batch between chunks
## (commands drain at the next chunk's first tick — identical boundaries on
## every rerun). Returns ticks run.
func _run_script(engine: SimEngine, total_ticks: int) -> int:
	var ran := 0
	while ran < total_ticks:
		var chunk: int = mini(UPGRADE_CHUNK_TICKS, total_ticks - ran)
		if ran > 0:
			_command_batch(engine)
		ran += engine.fast_forward(chunk)
	return ran


# --- Fixtures ----------------------------------------------------------------


func _timber_tax_regime() -> RegimeDef:
	# The town-hall example flavor: garrison x1.2 + timber x0.85.
	var regime := RegimeDef.new()
	regime.id = &"gilded_crown"
	regime.display_name = "The Gilded Crown"
	var combat := RegimeModifier.new()
	combat.kind = &"garrison_multiplier"
	combat.value = 1.2
	regime.combat_modifier = combat
	var quirk := RegimeModifier.new()
	quirk.kind = &"production_multiplier"
	quirk.target = &"timber"
	quirk.value = 0.85
	regime.economy_quirk = quirk
	return regime


func _build(run_seed: int, regime: RegimeDef) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(ProductionSystem.new(_defs(), EconomyTunables.new(), regime))
	return engine


func _defs() -> Array[BuildingDef]:
	# The R4 band spread: cheapest r=1.08 (farm), mid 1.10 (camp), dearest
	# r=1.12 (mine, multi-resource cost line); milestones [10, 20], max 30.
	var farm := BuildingDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.resource_produced = &"food"
	farm.base_production_per_worker_hour = 6.0
	farm.worker_slots_base = 2
	var farm_cost: Dictionary[StringName, int] = {}
	farm_cost[&"timber"] = 15
	farm.base_cost = farm_cost
	farm.cost_growth = 1.08
	var farm_milestones: Array[int] = [10, 20]
	farm.milestone_levels = farm_milestones
	farm.max_level = 30

	var camp := BuildingDef.new()
	camp.id = &"camp"
	camp.display_name = "Lumber Camp"
	camp.resource_produced = &"timber"
	camp.base_production_per_worker_hour = 6.0
	camp.worker_slots_base = 2
	var camp_cost: Dictionary[StringName, int] = {}
	camp_cost[&"food"] = 10
	camp.base_cost = camp_cost
	camp.cost_growth = 1.10
	var camp_milestones: Array[int] = [10, 20]
	camp.milestone_levels = camp_milestones
	camp.max_level = 30

	var mine := BuildingDef.new()
	mine.id = &"mine"
	mine.display_name = "Iron Mine"
	mine.resource_produced = &"iron"
	mine.base_production_per_worker_hour = 3.0
	mine.worker_slots_base = 3
	var mine_cost: Dictionary[StringName, int] = {}
	mine_cost[&"timber"] = 40
	mine_cost[&"food"] = 20
	mine.base_cost = mine_cost
	mine.cost_growth = 1.12
	var mine_milestones: Array[int] = [10, 20]
	mine.milestone_levels = mine_milestones
	mine.max_level = 30

	var defs: Array[BuildingDef] = []
	defs.append(farm)
	defs.append(camp)
	defs.append(mine)
	return defs
