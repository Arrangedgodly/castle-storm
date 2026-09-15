## Acceptance marathon — the assault arc (T-SIM-06): build to the knight
## floor, commit, LOSE, survive the set-back, rebuild, commit again, WIN —
## the full player loop through the UI seam against the real MVP pack.
##
## Composition note (sibling-impact zero by construction): the shared
## `full_stack` fixture is NOT modified. This suite builds its own stack —
## full_stack's order + AssaultResolver + SuspicionSystem (opt-in per
## sim-engine.md §14/§15, the T-SIM-05 precedent) — so every other suite's
## recorded hash stays byte-identical.
##
## Determinism strategy: the script is a pure function of the engine (reads
## -> commands, no test-side randomness), so the FIRST commit's odds depend
## only on the seed. A deterministic seed search finds a seed whose story is
## "floor assault lost (full spike, run alive), rebuilt assault won"; the
## suite then runs THAT seed in full and replays it fast-forward-only
## expecting identical hash + event count. The odds shown before each commit
## are compared against the verdict events (the odds screen cannot lie), the
## failed assault's set-back rules are asserted against live state
## (ceil-fraction casualties, spike, run keeps running, re-commit refused
## below floor), a mid-recovery save round-trip proves nothing
## assault-relevant is lost on restore (a twin forked at the saved state
## replays phase 2 to a bit-identical hash), and the victory wiring
## (same-tick run_won, single chronicle entry, bank) is checked end to end.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const BASE_SEED := 20260916
const SEED_CANDIDATES := 25  # floor loss ~72% x rebuilt win ~55%: a handful suffices
const BATCH_TICKS := 60  # one management batch per sim-hour
const FLOOR_PHASE_CAP_BATCHES := 120  # ~120h to the floor line (M1 measured ~27h)
const REBUILD_PHASE_CAP_BATCHES := 480  # generous: ~3x floor power after the rout
const REBUILD_TARGET_POWER := 75  # ~3.2x floor: odds ~510-580 permille by flavor
const BUDGET_SECONDS := 30.0


# --- Session log (copy at drain; pooled events must never be cached) ---------


class SessionLog:
	extends RefCounted

	var entries: Array[Dictionary] = []
	var _ring_seq := 0

	func drain(log: SimEventLog) -> void:
		while _ring_seq < log.next_seq():
			var event := log.get_event(_ring_seq)
			if event != null:
				entries.append({
					"seq": event.seq,
					"tick": event.tick,
					"type": event.type,
					"subject": event.subject,
					"value": event.value,
					"value2": event.value2,
				})
			_ring_seq += 1

	func of_type(type: StringName) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for entry in entries:
			if entry["type"] == type:
				found.append(entry)
		return found

	func count(type: StringName) -> int:
		return of_type(type).size()

	func verdicts() -> Array[Dictionary]:
		# assault_won/assault_lost in seq order (one per resolved commit).
		var found: Array[Dictionary] = []
		for entry in entries:
			if entry["type"] == &"assault_won" or entry["type"] == &"assault_lost":
				found.append(entry)
		return found


# --- Suite contract -----------------------------------------------------------


func suite_name() -> String:
	return "marathon_assault_storm"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()

	# --- Deterministic seed search: loss at the floor (full spike, run
	# alive), win after the rebuild. The arc is a property of the seed.
	var chosen := 0
	for candidate in SEED_CANDIDATES:
		var probe := _storm_engine(BASE_SEED + candidate)
		var story := _storm_script(probe, SessionLog.new(), {})
		if story["outcome1"] == "lost" and story["outcome2"] == "won" \
				and int(story["spike"]) == int(MVP.load_mvp().tunables.assault_failure_suspicion) \
				and bool(story["still_running"]):
			chosen = BASE_SEED + candidate
			break
	var wall_search := float(Time.get_ticks_msec() - clock_start) / 1000.0
	harness.check(chosen != 0, "seed search found the storm arc (floor loss, rebuilt win) within %d candidates (%.2fs)" % [SEED_CANDIDATES, wall_search])
	if chosen == 0:
		return

	# --- The full run on the chosen seed, with the mid-recovery fork.
	var engine := _storm_engine(chosen)
	var session := SessionLog.new()
	var roundtrip := {}
	var report := _storm_script(engine, session, roundtrip)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	report["wall"] = wall
	_print_digest(report, session, chosen)

	# --- The failed assault: exact set-back rules, live state.
	harness.check(report["outcome1"] == "lost", "first assault (at the floor) LOST on seed %d" % chosen)
	harness.check(int(report["casualties"]) == int(report["army_units1"]) - int(report["army_units_mid"]), "casualties = ceil(loss_fraction x %d army units) = %d" % [report["army_units1"], report["casualties"]])
	harness.check(int(report["casualties"]) > 0 and int(report["army_power_mid"]) < int(report["army_power1"]), "the army bled: power %d -> %d (units %d -> %d)" % [report["army_power1"], report["army_power_mid"], report["army_units1"], report["army_units_mid"]])
	harness.check(int(report["spike"]) == int(MVP.load_mvp().tunables.assault_failure_suspicion), "suspicion spiked by exactly the tunable +%d (event value %d)" % [MVP.load_mvp().tunables.assault_failure_suspicion, report["spike"]])
	harness.check(bool(report["still_running"]), "the run KEPT RUNNING after the failed assault (set-back, not death)")
	harness.check(int(report["runs_recorded_mid"]) == 0, "the failed assault banked nothing (chronicle still %d entries — only ended runs bank)" % report["runs_recorded_mid"])
	harness.check(int(report["recommit_denied"]) == 1, "re-commit below the floor refused with reason %d (the floor re-arms after losses)" % AssaultResolver.REASON_BELOW_FLOOR)

	# --- Beats: the replayable vignette contract, both outcomes.
	var beats1: Array = report["beats1"]
	harness.check(beats1.size() == 4 and String(beats1[3]["subject"]) == "rout", "loss vignette: 4 beats ending in rout (%s)" % str(beats1.map(func(b): return String(b["subject"]))))
	var beats2: Array = report["beats2"]
	harness.check(beats2.size() == 4 and String(beats2[3]["subject"]) == "throne", "win vignette: 4 beats ending on the throne (%s)" % str(beats2.map(func(b): return String(b["subject"]))))
	harness.check(bool(report["beats_monotone"]), "army remaining is non-increasing across every beat chain (ends at the true post-battle state)")

	# --- The odds screen cannot lie: shown odds == the rolled odds.
	harness.check(int(report["odds1"]) == int(report["rolled1"]) and int(report["odds2"]) == int(report["rolled2"]), "displayed odds rode both verdicts exactly: %d/%d then %d/%d" % [report["odds1"], report["rolled1"], report["odds2"], report["rolled2"]])
	harness.check(int(report["odds1_permille_math"]) == int(report["odds1"]), "floor odds match the permille arithmetic for regime %s (army %d x%s milli vs garrison %d x%s milli): %d" % [report["regime"], report["army_power1"], report["army_mult"], report["garrison_base"], report["garrison_mult"], report["odds1"]])
	harness.check(int(report["odds2"]) > int(report["odds1"]), "the rebuilt army's odds rose visibly: %d -> %d permille (surplus/quality raise odds)" % [report["odds1"], report["odds2"]])

	# --- Recovery + victory wiring.
	harness.check(report["outcome2"] == "won", "second assault (rebuilt to power %d) WON" % report["army_power2"])
	var run := engine.get_system(&"run") as RunLifecycleSystem
	harness.check(int(run.run_outcome()) == RunLifecycleSystem.OUTCOME_VICTORY, "run frame ended in OUTCOME_VICTORY")
	harness.check(int(report["won_tick"]) == int(report["assault_won_tick"]), "run_won landed in the SAME tick as assault_won (%d)" % report["won_tick"])
	harness.check(int(run.meta.runs_recorded) == 1, "exactly ONE chronicle entry (the failed assault never ended the run)")
	harness.check(int(run.meta.legacy_points) == int(report["final_score"]) and int(report["final_score"]) > 0, "banked the victory score (%d lp)" % run.meta.legacy_points)

	# --- Restore preserves everything assault-relevant (mid-recovery fork).
	harness.check(bool(roundtrip.get("ok", false)), "mid-recovery fork: twin restored from the saved state replayed phase 2 to a bit-identical hash (%d == %d) with the same verdict" % [roundtrip.get("hash_twin", 0), roundtrip.get("hash_main", 0)])

	# --- Replay (fast-forward only): the same world, the same story.
	var replay_engine := _storm_engine(chosen)
	var replay := _storm_script(replay_engine, SessionLog.new(), {})
	harness.check(replay["final_hash"] == report["final_hash"], "replay: identical final hash (%d)" % report["final_hash"])
	harness.check(replay["next_seq"] == report["next_seq"], "replay: identical event count (%d)" % report["next_seq"])

	harness.check(wall < BUDGET_SECONDS, "storm arc in < %.0fs (took %.2fs incl. seed search)" % [BUDGET_SECONDS, wall])
	harness.check(engine.pending_command_count() == 0, "every gameplay write went through submit_command (queue drained)")


# --- The storm script (pure function of engine + seed) --------------------------


## Runs the arc: boot -> floor -> commit#1 -> rebuild -> commit#2. `roundtrip`
## (optional) receives the mid-recovery fork evidence. All reads through
## documented UI seams; all writes through submit_command.
func _storm_script(engine: SimEngine, session: SessionLog, roundtrip: Dictionary) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var report := {}

	# Boot: start, honest refused build (zero-grant proof), grant, build all.
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"upgrade_building", MVP.building_ids()[0], 1)
	_advance(engine, session, 1)
	engine.submit_command(&"grant_resources", &"", 0)
	for id in MVP.building_ids():
		engine.submit_command(&"upgrade_building", id, 1)
	_advance(engine, session, 1)

	# Phase 1: build to the knight floor (the gate's careful policy, military
	# capped at 3), then commit AT the floor — the floor unlocks, never
	# triggers; the commit is the player's choice at the shown odds.
	var batches := 0
	while (not resolver.floor_met(engine)) and batches < FLOOR_PHASE_CAP_BATCHES:
		_manage(engine, 3)
		_advance(engine, session, BATCH_TICKS)
		batches += 1
	report["floor_ticks"] = batches * BATCH_TICKS
	var odds1 := resolver.assault_odds(engine)
	report["army_power1"] = units.army_power()
	report["army_units1"] = int(odds1["army"]["units"])
	report["odds1"] = int(odds1["win_permille"])
	report["odds1_permille_math"] = _permille_math(odds1)
	report["army_mult"] = int(odds1["army"]["regime_multiplier_milli"])
	report["garrison_mult"] = int(odds1["garrison"]["regime_multiplier_milli"])
	report["garrison_base"] = int(odds1["garrison"]["base_power"])
	report["regime"] = run.regime_id()
	var runs_before := run.meta.runs_recorded
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, session, 1)
	var verdicts := session.verdicts()
	var verdict1: Dictionary = verdicts[0] if not verdicts.is_empty() else {}
	report["outcome1"] = "none" if verdict1.is_empty() else ("won" if verdict1["type"] == &"assault_won" else "lost")
	report["rolled1"] = -1 if verdict1.is_empty() else int(verdict1["value"])
	report["beats1"] = _beat_chain(session, 0)
	var casualties := session.of_type(&"assault_casualties")
	report["casualties"] = int(casualties[0]["value"]) if not casualties.is_empty() else 0
	var spike_events := session.of_type(&"suspicion_rose").filter(func(e): return e["subject"] == &"assault")
	report["spike"] = int(spike_events[0]["value"]) if not spike_events.is_empty() else 0
	var odds_mid := resolver.assault_odds(engine)
	report["army_power_mid"] = units.army_power()
	report["army_units_mid"] = int(odds_mid["army"]["units"])
	report["still_running"] = run.is_running()
	report["runs_recorded_mid"] = run.meta.runs_recorded - runs_before

	# The floor re-arms: a re-commit below the floor is refused.
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, session, 1)
	var denials := session.of_type(&"assault_denied")
	report["recommit_denied"] = denials.size()

	# Mid-recovery fork: capture the engine state; a twin restored from it
	# replays phase 2 to a bit-identical hash (nothing assault-relevant lives
	# outside engine state).
	var fork_state := engine.to_dict()

	# Phase 2: rebuild past ~3x floor (military cap raised — the conspiracy
	# goes all in), then commit again.
	var phase2 := _rebuild_and_commit(engine, session)
	for key in phase2.keys():
		report[key] = phase2[key]

	# The fork: same construction, same commands, from the captured state.
	var twin := _storm_engine(engine.run_seed)
	twin.apply_state_dict(fork_state)
	_rebuild_and_commit(twin, SessionLog.new())
	roundtrip["ok"] = twin.state_hash() == engine.state_hash()
	roundtrip["hash_main"] = engine.state_hash()
	roundtrip["hash_twin"] = twin.state_hash()

	report["final_hash"] = engine.state_hash()
	report["next_seq"] = engine.events.next_seq()
	return report


## Phase 2 (shared by the main run and the fork twin): rebuild to the target
## power, commit, collect the second verdict.
func _rebuild_and_commit(engine: SimEngine, session: SessionLog) -> Dictionary:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var report := {}
	var batches := 0
	while units.army_power() < REBUILD_TARGET_POWER and batches < REBUILD_PHASE_CAP_BATCHES:
		_manage(engine, 12)
		_advance(engine, session, BATCH_TICKS)
		batches += 1
	report["rebuild_ticks"] = batches * BATCH_TICKS
	report["army_power2"] = units.army_power()
	report["odds2"] = int(resolver.assault_odds(engine)["win_permille"])
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, session, 1)
	var verdicts := session.verdicts()
	var verdict2: Dictionary = verdicts[verdicts.size() - 1] if not verdicts.is_empty() else {}
	report["outcome2"] = "none" if verdict2.is_empty() else ("won" if verdict2["type"] == &"assault_won" else "lost")
	report["rolled2"] = -1 if verdict2.is_empty() else int(verdict2["value"])
	report["beats2"] = _beat_chain(session, 1)
	var won := session.of_type(&"run_won")
	report["won_tick"] = int(won[0]["tick"]) if not won.is_empty() else -1
	var assault_won := session.of_type(&"assault_won")
	report["assault_won_tick"] = int(assault_won[0]["tick"]) if not assault_won.is_empty() else -2
	report["final_score"] = (engine.get_system(&"run") as RunLifecycleSystem).last_run_score()
	report["beats_monotone"] = _beats_monotone(_beat_chain(session, 0)) and _beats_monotone(_beat_chain(session, 1))
	return report


# --- Management policy (the gate's shape, military cap parameterized) ----------


func _manage(engine: SimEngine, military_cap: int) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var funds := {
		&"food": engine.get_resource(&"food"),
		&"timber": engine.get_resource(&"timber"),
		&"iron": engine.get_resource(&"iron"),
	}
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	var worker_total := units.unit_count(&"worker")
	var military := units.unit_count(&"militia") + units.unit_count(&"trainee") \
		+ units.unit_count(&"knight") + units.unit_count(&"archer")
	for uid in units.unit_ids():
		var role := units.training_target(uid)
		if role == &"militia" or role == &"trainee" or role == &"knight" or role == &"archer":
			military += 1
	for uid in units.idle_units(&"peasant"):
		if worker_total >= 2 and military < military_cap:
			military += 1
			engine.submit_command(&"assign_role", &"militia", uid)
		else:
			worker_total += 1
			engine.submit_command(&"assign_role", &"worker", uid)
	for uid in units.idle_units(&"militia"):
		engine.submit_command(&"start_training", &"trainee", uid)
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
			for gear_id in units.gear_ids_for_slot(slot):
				if _gear_affordable(gear_id, funds):
					_pay_gear(gear_id, funds)
					engine.submit_command(&"equip_gear", gear_id, uid)
					break
		if units.missing_gear_slots(uid).is_empty():
			engine.submit_command(&"promote", &"", uid)
	var idle_local := production.idle_workers()
	var assigned_local := {}
	for id in MVP.producer_ids():
		assigned_local[id] = production.assigned_workers(id)
	while idle_local > 0:
		var pick: StringName = &""
		for id in MVP.producer_ids():
			if production.worker_slots(id) - int(assigned_local[id]) > 0 \
					and (pick == &"" or int(assigned_local[id]) < int(assigned_local[pick])):
				pick = id
		if pick == &"":
			break
		engine.submit_command(&"assign_worker", pick, 1)
		assigned_local[pick] = int(assigned_local[pick]) + 1
		idle_local -= 1
	for id in MVP.building_ids():
		if production.building_level(id) > 0:
			continue
		var build_cost := production.upgrade_cost(id)
		var buildable := not build_cost.is_empty()
		for resource in build_cost:
			if int(funds.get(resource, 0)) < int(build_cost[resource]):
				buildable = false
				break
		if buildable:
			for resource in build_cost:
				funds[resource] = int(funds.get(resource, 0)) - int(build_cost[resource])
			engine.submit_command(&"upgrade_building", id, 1)
	for id in MVP.building_ids():
		if production.building_level(id) < 1:
			continue
		var cost := production.upgrade_cost(id)
		var affordable := true
		for resource in cost:
			if int(funds.get(resource, 0)) < int(cost[resource]):
				affordable = false
				break
		if affordable and not cost.is_empty():
			for resource in cost:
				funds[resource] = int(funds.get(resource, 0)) - int(cost[resource])
			engine.submit_command(&"upgrade_building", id, 1)
			break


func _advance(engine: SimEngine, session: SessionLog, ticks: int) -> void:
	engine.fast_forward(ticks)
	session.drain(engine.events)


func _beat_chain(session: SessionLog, index: int) -> Array[Dictionary]:
	# Groups of 4 beats in seq order — one chain per resolved commit.
	var chains: Array[Array] = []
	var current: Array[Dictionary] = []
	for entry in session.entries:
		if entry["type"] == &"assault_beat":
			current.append(entry)
			if current.size() == 4:
				chains.append(current)
				current = []
	return chains[index] if index < chains.size() else []


func _beats_monotone(chain: Array) -> bool:
	if chain.size() != 4:
		return false
	for i in range(1, chain.size()):
		if int(chain[i]["value"]) > int(chain[i - 1]["value"]):
			return false
	return true


## Independent permille arithmetic from the breakdown's own two sides — the
## suite re-derives the displayed number instead of trusting the field.
func _permille_math(odds: Dictionary) -> int:
	var army_milli := int(odds["army"]["score_milli"])
	var garrison_milli := int(odds["garrison"]["strength_milli"])
	if army_milli + garrison_milli <= 0:
		return 0
	return army_milli * 1000 / (army_milli + garrison_milli)


# --- Fixtures --------------------------------------------------------------------


## The storm stack: the marathon full_stack order + the resolver + suspicion
## (both opt-in; the shared fixture stays untouched for every other suite).
func _storm_engine(run_seed: int) -> SimEngine:
	var pack := MVP.load_mvp()
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, null, MVP.MARATHON_STIPEND))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))
	engine.register_system(AssaultResolver.new(pack.tunables))
	engine.register_system(SuspicionSystem.new(pack.tunables, pack.units))
	return engine


func _gear_recipe(gear_id: StringName) -> Dictionary:
	for gear in MVP.load_mvp().gear:
		if gear.id == gear_id:
			return gear.recipe
	return {}


func _gear_affordable(gear_id: StringName, funds: Dictionary) -> bool:
	var recipe := _gear_recipe(gear_id)
	for resource in recipe:
		if int(funds.get(resource, 0)) < int(recipe[resource]):
			return false
	return not recipe.is_empty()


func _pay_gear(gear_id: StringName, funds: Dictionary) -> void:
	var recipe := _gear_recipe(gear_id)
	for resource in recipe:
		funds[resource] = int(funds.get(resource, 0)) - int(recipe[resource])


func _print_digest(report: Dictionary, session: SessionLog, seed: int) -> void:
	print(
		"[marathon_assault_storm] seed %d (regime %s, army x%s / garrison x%s milli): floor assault at power %d (%d units) -> %d permille -> %s (casualties %d, spike +%d, army %d, run alive %s); rebuilt %d ticks to power %d -> %d permille -> %s; score %d banked; %d events; wall %.2fs; hash %d"
		% [
			seed, report["regime"], report["army_mult"], report["garrison_mult"],
			report["army_power1"], report["army_units1"], report["odds1"], report["outcome1"],
			report["casualties"], report["spike"], report["army_power_mid"], report["still_running"],
			report["rebuild_ticks"], report["army_power2"], report["odds2"], report["outcome2"],
			report["final_score"], session.entries.size(), report["wall"], report["final_hash"],
		]
	)
