## Acceptance marathon — the full thin run loop (T-SIM-04; content: the
## T-DATA-02 MVP pack).
##
## Pre-stages the T-SCOPE-01 gate: start run -> recruit -> assign -> produce
## -> train/gear/promote -> resolve_victory -> restart, twice, in
## accelerated time on the full system stack (heartbeat + run + units +
## production), all content loaded from content/mvp/pack.tres through the
## loud gate and bootstrapped through the grant_resources command (F1: no
## set_resource anywhere). Run 1 plays the real management script (the
## marathon_units cadence, cheapest-tier gear + next-tier refits so every
## gear tier's recipe is exercised) until the army clears the thin victory
## line, wins, and banks; run 2 restarts under a FRESH identity with emptied
## run-scoped state, produces, and loses — failure banks full progress; run 3
## is folded and save-round-tripped mid-run. Proves: identity generation
## inside the accelerated loop, victory AND failure both accruing the meta
## bank, the chronicle growing across restarts (meta domain, survives its own
## dict round-trip), restart emptying resources/production/units exactly, and
## the whole script reproducing bit-for-bit from the seed. Measures the
## loop's wall time so T-SIM-04's weight stays visible in CI output.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const RUN1_CAP_TICKS := 600 * SimEngine.TICKS_PER_SIM_HOUR  # 600h ceiling
const VICTORY_ARMY_POWER := 100  # thin line (the real floor is T-SIM-06/08)
const RUN2_TICKS := 100 * SimEngine.TICKS_PER_SIM_HOUR


func suite_name() -> String:
	return "marathon_run_thin_loop"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var report := _thin_loop(_build())
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var total_ticks: int = report["ticks"]

	print(
		"[marathon_run_thin_loop] 3 runs / %d ticks (%.0fh) in %.3fs — %.0f ticks/s; run1 %s beat %s under %s; banked %d lp across %d chronicle runs; final hash %d"
		% [
			total_ticks, float(report["ticks"]) / SimEngine.TICKS_PER_SIM_HOUR, wall,
			float(total_ticks) / wall, report["leader1"], report["leader2"],
			report["regime2"], report["points"], report["chronicle"],
			report["final_hash"],
		]
	)

	harness.check(bool(report.get("ran1_to_victory")), "run 1 reached army power %d within %dh (got %d @ %dh)" % [VICTORY_ARMY_POWER, RUN1_CAP_TICKS / 60, report["run1_power"], report["run1_ticks"] / 60])
	harness.check(wall < BUDGET_SECONDS, "thin loop (3 runs) in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Generation inside the accelerated loop: identities + regimes.
	harness.check(str(report["leader1"]).length() > 3, "run 1 leader generated: %s" % report["leader1"])
	harness.check(str(report["leader2"]).length() > 3, "run 2 leader generated: %s" % report["leader2"])
	harness.check(report["leader2"] != report["leader1"], "restart folded a FRESH identity")
	harness.check(report["regime_ids"].has(report["regime1"]), "run 1 regime is a pack flavor: %s" % report["regime1"])
	harness.check(report["regime_ids"].has(report["regime2"]), "run 2 regime is a pack flavor: %s" % report["regime2"])

	# --- Victory + failure both banked; chronicle grew across restarts.
	harness.check(report["chronicle"] == 2, "chronicle holds run 1 (victory) + run 2 (defeat): %d" % report["chronicle"])
	harness.check(report["points"] == report["score1"] + report["score2"], "bank == run1 %d + run2 %d (banked %d)" % [report["score1"], report["score2"], report["points"]])
	harness.check(report["score1"] > 0 and report["score2"] > 0, "failure banked full progress too (run 2 score %d)" % report["score2"])
	harness.check(report["army1_knights"] + report["army1_archers"] > 0, "run 1 chronicle snapshot carries army stats: %d knights + %d archers" % [report["army1_knights"], report["army1_archers"]])
	harness.check(int(report["produced_run2"]) > 0, "run 2 PRODUCED under the restarted economy (+%d food in %dh)" % [report["produced_run2"], RUN2_TICKS / 60])

	# --- Restart emptied run-scoped state exactly (asserted inside the
	# loop; the folded run 3 proves it kept producing afterwards).
	harness.check(bool(report.get("restart_emptied")), "restart emptied resources/production/units")

	# --- Save round-trip: run 3 mid-run crosses the engine boundary in
	# lockstep, and the meta bank crosses its own dict boundary intact.
	harness.check(bool(report.get("roundtrip_lockstep")), "mid-run save round-trip lockstep (hash %d)" % report["final_hash"])
	harness.check(bool(report.get("meta_roundtrip")), "meta bank + chronicle survive their own dict round-trip")

	# --- Determinism: same construction + seed + script -> same identities,
	# same bank, same final hash (fresh meta, so hashes are comparable).
	var replay := _thin_loop(_build())
	harness.check(replay["leader1"] == report["leader1"], "replay: run 1 identity identical")
	harness.check(replay["leader2"] == report["leader2"], "replay: run 2 identity identical")
	harness.check(replay["points"] == report["points"], "replay: bank identical (%d)" % report["points"])
	harness.check(replay["final_hash"] == report["final_hash"], "replay: final hash identical (%d)" % report["final_hash"])


# --- The thin loop script (pure function of the engine + seed) -------------


## Runs the 3-run script and returns a report dictionary of checkpoints.
func _thin_loop(engine: SimEngine) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var report := {"ticks": 0, "regime_ids": _regime_ids()}

	# --- Run 1: start, recruit, produce, train/gear/promote, win.
	engine.submit_command(&"run_start", &"", 0)
	_seed_run(engine)
	var ran1 := _run_managed_until(engine, VICTORY_ARMY_POWER, RUN1_CAP_TICKS)
	report["ran1_to_victory"] = units.army_power() >= VICTORY_ARMY_POWER
	report["run1_power"] = units.army_power()
	report["run1_ticks"] = ran1
	report["leader1"] = run.leader_name()
	report["regime1"] = run.regime_id()
	run.resolve_victory(engine, true)
	engine.fast_forward(1)  # resolve_victory is tick-aligned: drain it
	report["score1"] = run.last_run_score()
	var entry1: Dictionary = run.meta.chronicle[0]
	report["army1_knights"] = int(entry1["army"].get("knight", 0))
	report["army1_archers"] = int(entry1["army"].get("archer", 0))

	# --- Restart: fresh identity, emptied state, second run.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	report["restart_emptied"] = units.total_units() == 0 \
		and units.arrivals_total == 0 \
		and production.idle_workers() == 0 \
		and production.building_level(&"farm") == 0 \
		and engine.get_resource(&"food") == 0 \
		and engine.get_resource(&"timber") == 0 \
		and engine.get_resource(&"iron") == 0
	report["leader2"] = run.leader_name()
	report["regime2"] = run.regime_id()

	# --- Run 2: rebuild thin, produce, LOSE — failure banks full progress.
	_seed_run(engine, 2)
	engine.submit_command(&"assign_worker", &"farm", 2)  # same drain as the builds
	engine.fast_forward(RUN2_TICKS)
	report["produced_run2"] = engine.get_resource(&"food") - int(MVP.MARATHON_STIPEND[&"food"])
	run.resolve_victory(engine, false)
	engine.fast_forward(1)
	report["score2"] = run.last_run_score()

	# --- Run 3: fold a third identity; round-trip BOTH save domains mid-run.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	report["leader3"] = run.leader_name()
	engine.fast_forward(CHUNK_TICKS)
	var captured := engine.to_dict()
	var meta_captured := run.meta.to_dict()
	var twin := _build()
	var twin_ok := twin.apply_state_dict(captured)
	var twin_run := twin.get_system(&"run") as RunLifecycleSystem
	var twin_meta := RunMeta.new()
	twin_meta.apply_dict(meta_captured)
	engine.fast_forward(CHUNK_TICKS)
	twin.fast_forward(CHUNK_TICKS)
	report["roundtrip_lockstep"] = twin_ok and twin.state_hash() == engine.state_hash()
	report["meta_roundtrip"] = twin_meta.chronicle.size() == 2 \
		and twin_meta.legacy_points == run.meta.legacy_points \
		and twin_run.leader_name() == run.leader_name()

	report["chronicle"] = run.meta.chronicle.size()
	report["points"] = run.meta.legacy_points
	report["ticks"] = engine.tick_count
	report["final_hash"] = engine.state_hash()
	return report


# --- Run scripting ----------------------------------------------------------


## Queues the boot commands (drained at the next tick): the stipend through
## the grant verb (F1 — marathon funds, same command the honest boot uses),
## bootstrap crew, build the producers. Run 2 gets a thinner crew.
func _seed_run(engine: SimEngine, crew := 4) -> void:
	engine.submit_command(&"grant_resources", &"", 0)
	engine.submit_command(&"add_worker", &"production", crew)
	for id in MVP.producer_ids():
		engine.submit_command(&"upgrade_building", id, 1)


## The management batch: accept the gate, branch peasants (every third
## military), advance the military path, gear + promote held ranks (cheapest
## per missing slot), refit equipped ranks to the next gear tier (every
## tier's recipe crosses the economy), keep the workers employed. Pure
## reads -> commands; no RNG outside the engine.
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
	# Branch trainees toward the CURRENTLY FEWER committed rank.
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
	# (strictly-higher-tier rule; options are tier-sorted, index = tier-1).
	for rank in [&"knight", &"archer"]:
		for uid in units.idle_units(rank):
			for slot in _gear_slots():
				var tier: int = units.gear_tier(uid, slot)
				var options := units.gear_ids_for_slot(slot)
				if tier > 0 and tier < options.size():
					engine.submit_command(&"equip_gear", options[tier], uid)
	for id in MVP.producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


## 10h chunks with a management batch between them until army power crosses
## the line or the cap hits. Returns ticks run.
func _run_managed_until(engine: SimEngine, army_power_line: int, cap_ticks: int) -> int:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var ran := 0
	while ran < cap_ticks and units.army_power() < army_power_line:
		var chunk: int = mini(CHUNK_TICKS, cap_ticks - ran)
		if ran > 0:
			_manage(engine)
		ran += engine.fast_forward(chunk)
	return ran


# --- Fixture accessors (content = the MVP pack; save_marathon preloads this
# --- suite and composes its single-regime sweep from these) ------------------


func _regime_ids() -> Array[String]:
	var ids: Array[String] = []
	for regime in _regimes():
		ids.append(String(regime.id))
	return ids


func _regimes() -> Array[RegimeDef]:
	return MVP.load_mvp().regimes


func _identity() -> IdentityPools:
	return MVP.load_mvp().identity


func _unit_defs() -> Array[UnitDef]:
	return MVP.load_mvp().units


func _gear_defs() -> Array[GearDef]:
	return MVP.load_mvp().gear


func _building_defs() -> Array[BuildingDef]:
	return MVP.load_mvp().buildings


func _gear_slots() -> Array[StringName]:
	return MVP.load_mvp().gear_slots


func _build() -> SimEngine:
	return MVP.full_stack(RUN_SEED, MVP.MARATHON_STIPEND)
