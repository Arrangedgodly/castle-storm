## Acceptance suite (T-QA-02) — a COMPLETE run in CI-accelerated time.
##
## The town-hall criterion, machine-encoded: "A complete run (start -> storm
## -> restart) is completable in CI in accelerated time — the economy is
## deterministic and simulatable headlessly." Driven ENTIRELY through the
## command surface on the canonical composition (`_full_stack.gd` — the
## reference host T-UI-03 consumes), honest pack stipend, no test seams:
##
##   recruit -> economy build -> army assembly -> FAILED first assault
##   (set-back survived, not death) -> [AWAY WINDOW: the catch-up service
##   resolves a foreground gap MID-RUN] -> rebuilt army -> VICTORY ->
##   chronicle + meta banking -> restart (fresh identity, emptied estate,
##   bank carried) -> host-side engine re-init (the T-UI-03 restart form).
##
## Determinism strategy (the storm-suite precedent): the arc is a pure
## function of the seed; a deterministic seed search picks a seed whose
## story is "floor assault lost, rebuilt assault won" so the FAILED first
## assault (optional per the task, included because set-back survival is
## the player loop's core resilience claim) is replayed honestly every CI
## run — the odds screen decides, nothing is forced.
##
## Also asserts: the failed assault's exact set-back rules (casualties,
## suspicion spike, run keeps running, floor re-arms), the catch-up window's
## cap/summary semantics (applied exactly 480 ticks, capped flag, arrivals
## stacked as gate offers, production accrued while away), same-tick
## victory wiring, banking math, restart reset, and a bit-identical replay.
extends RefCounted

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const BASE_SEED := 20261031
const SEED_CANDIDATES := 30
const BATCH_TICKS := 120  # one management batch per 2h sim time
const FLOOR_CAP_BATCHES := 90  # ~180h to the floor line (M1 measured ~27h)
const REBUILD_CAP_BATCHES := 360  # generous honest-funds rebuild window
const REBUILD_TARGET_POWER := 75  # ~3.2x floor: visible odds lift
const BUDGET_SECONDS := 30.0

# A fixed injected UTC epoch for the away window (determinism: the engine
# never sees wall time; the host injects timestamps per docs/catch-up.md).
const AWAY_ANCHOR_EPOCH := 1_750_000_000
const AWAY_SECONDS := 8 * 3600 + 37 * 60  # 8h37m: capped at exactly 8h


func suite_name() -> String:
	return "full_run_ci"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()

	# --- Deterministic seed search: the arc is a property of the seed.
	var chosen := 0
	for candidate in SEED_CANDIDATES:
		var probe_session: Variant = HOST.session(BASE_SEED + candidate)
		var story := _arc(probe_session, {}, SessionLog.new())
		if story["outcome1"] == "lost" and story["outcome2"] == "won":
			chosen = BASE_SEED + candidate
			break
	var wall_search := float(Time.get_ticks_msec() - clock_start) / 1000.0
	harness.check(chosen != 0, "seed search found the full-run arc (floor loss -> rebuilt win) within %d candidates (%.2fs)" % [SEED_CANDIDATES, wall_search])
	if chosen == 0:
		return

	# --- The full run on the chosen seed (with the catch-up evidence bag).
	var session: Variant = HOST.session(chosen)
	var session_log := SessionLog.new()
	var evidence := {}
	var story := _arc(session, evidence, session_log)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	_print_digest(story, evidence, session_log, chosen, wall)
	var run := session.engine.get_system(&"run") as RunLifecycleSystem
	var meta: RunMeta = session.meta

	# --- The complete-run criterion: recruit -> build -> FAILED assault ->
	# survive -> away window -> rebuild -> victory -> restart, all in CI.
	harness.check(story["built_all_four"], "the economy built all four buildings from the honest stipend (no set_resource)")
	harness.check(story["outcome1"] == "lost", "first assault (at the floor, power %d) LOST on seed %d" % [story["power1"], chosen])
	harness.check(int(story["casualties"]) > 0 and int(story["power_mid"]) < int(story["power1"]), "the set-back bled the army: power %d -> %d (%d casualties)" % [story["power1"], story["power_mid"], story["casualties"]])
	harness.check(bool(story["still_running"]), "the run KEPT RUNNING after the failed assault (set-back, never death)")
	harness.check(int(story["spike"]) == int(MVP.load_mvp().tunables.assault_failure_suspicion), "suspicion spiked exactly the tunable +%d" % MVP.load_mvp().tunables.assault_failure_suspicion)
	harness.check(int(story["recommit_denied"]) >= 1, "re-commit below the floor refused (the floor re-arms)")
	harness.check(int(story["runs_recorded_mid"]) == 0, "the failed assault banked nothing (chronicle still empty mid-run)")

	# --- The away window, mid-run: the catch-up service on the canonical
	# host composition (mark_seen -> foreground; clamps + summary events).
	harness.check(int(evidence["applied_ticks"]) == 480, "away window resolved through the REAL engine: exactly the 8h cap = 480 ticks (8h37m injected)" % [])
	harness.check(bool(evidence["capped"]), "the 37m over the cap was clamped, not granted")
	harness.check(int(evidence["arrivals"]) >= 1, "arrivals stacked as gate offers while away (%d in the window)" % evidence["arrivals"])
	var food_delta: int = int((evidence["resource_delta"] as Dictionary).get(&"food", 0))
	harness.check(food_delta > 0, "production accrued while away (+%d food in 8h — timestamp math, no simulation loop)" % food_delta)
	harness.check(int(evidence["anchor"]) == AWAY_ANCHOR_EPOCH + AWAY_SECONDS, "the anchor snapped to the foreground timestamp (windows never bank)")

	# --- Victory wiring: the second assault won; the run frame closed the
	# same tick; the chronicle + bank recorded it.
	harness.check(story["outcome2"] == "won", "second assault (rebuilt to power %d) WON" % story["power2"])
	harness.check(int(story["won_tick"]) == int(story["assault_won_tick"]), "run_won landed in the SAME tick as assault_won (%d)" % story["won_tick"])
	harness.check(meta.runs_recorded == 1, "exactly ONE chronicle entry (the failed assault never ended the run)")
	harness.check(meta.legacy_points == int(story["final_score"]) and int(story["final_score"]) > 0, "victory banked the run score (%d lp)" % meta.legacy_points)
	var entry: Dictionary = meta.chronicle[0]
	harness.check(str(entry["outcome"]) == "victory" and str(entry["leader"]).length() > 3 and str(entry["regime"]) == String(story["regime"]), "chronicle entry carries outcome + identity + regime (%s / %s / %s)" % [entry["outcome"], entry["leader"], entry["regime"]])

	# --- Restart: fresh identity, emptied run-scoped state, meta carried.
	harness.check(bool(story["restart_reset"]), "in-engine restart emptied resources/roster/estate and reset the meter")
	harness.check(str(story["leader2"]) != str(story["leader1"]), "restart folded a FRESH identity (%s -> %s)" % [story["leader1"], story["leader2"]])
	harness.check(meta.legacy_points == int(story["final_score"]) and meta.runs_recorded == 1, "the meta bank + chronicle SURVIVED the restart (meta domain, never run state)")

	# --- The host-side restart form (engine re-init around the same meta —
	# the T-UI-03/T-PERF-01 shape): a fresh engine sees the carried bank.
	var fresh: SimEngine = session.build_engine()
	var fresh_run := fresh.get_system(&"run") as RunLifecycleSystem
	harness.check(fresh_run.run_status() == RunLifecycleSystem.STATUS_UNSTARTED and fresh_run.meta == meta, "host re-init: fresh engine, UNSTARTED run, SAME meta instance (bank %d lp intact)" % meta.legacy_points)

	# --- Replay: the whole arc (away window included) is a pure function of
	# the seed — bit-identical hash at the victory checkpoint + same bank.
	var replay_session: Variant = HOST.session(chosen)
	var replay := _arc(replay_session, {}, SessionLog.new())
	harness.check(int(replay["victory_hash"]) == int(story["victory_hash"]), "replay: identical hash at the victory checkpoint (%d)" % story["victory_hash"])
	harness.check(int(replay["final_score"]) == int(story["final_score"]), "replay: identical banked score (%d)" % story["final_score"])
	harness.check(int(replay["away_tick_jump"]) == int(story["away_tick_jump"]), "replay: identical away-window tick jump (%d)" % story["away_tick_jump"])

	harness.check(wall < BUDGET_SECONDS, "full run in CI < %.0fs incl. seed search (took %.2fs)" % [BUDGET_SECONDS, wall])
	harness.check(session.engine.pending_command_count() == 0, "every gameplay write went through submit_command (queue drained)")


## The arc (pure function of the session's seed). `evidence` receives the
## away-window report; `log` collects the session event tail.
func _arc(session: Variant, evidence: Dictionary, log: SessionLog) -> Dictionary:
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var story := {}

	# Boot: run + honest stipend; the estate builds land through the
	# policy's build-order rule over the next management batches.
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	_advance(engine, log, 1)
	story["leader1"] = run.leader_name()
	story["regime"] = run.regime_id()

	# Phase 1: measured growth (military capped at 3) to the knight floor.
	var batches := 0
	while not resolver.floor_met(engine) and batches < FLOOR_CAP_BATCHES:
		HOST.manage(engine, 3, {})
		_advance(engine, log, BATCH_TICKS)
		batches += 1
	story["floor_ticks"] = batches * BATCH_TICKS
	story["power1"] = units.army_power()
	story["odds1"] = int(resolver.assault_odds(engine)["win_permille"])
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, log, 1)
	var verdicts := log.verdicts()
	story["outcome1"] = "none" if verdicts.is_empty() else ("won" if verdicts[0]["type"] == &"assault_won" else "lost")
	var casualties := log.of_type(&"assault_casualties")
	story["casualties"] = int(casualties[0]["value"]) if not casualties.is_empty() else 0
	story["power_mid"] = units.army_power()
	story["still_running"] = run.is_running()
	story["runs_recorded_mid"] = run.meta.runs_recorded
	var spike_events := log.of_type(&"suspicion_rose").filter(func(e): return e["subject"] == &"assault")
	story["spike"] = int(spike_events[0]["value"]) if not spike_events.is_empty() else 0
	# The floor re-arms below it.
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, log, 1)
	story["recommit_denied"] = log.of_type(&"assault_denied").size()

	# The AWAY WINDOW, mid-run (the player closed the game after the rout):
	# background marks the session seen; the next foreground resolves the
	# gap through the catch-up service — the REAL engine fast-forwards.
	session.mark_seen(AWAY_ANCHOR_EPOCH)
	var before_tick: int = engine.tick_count
	var report: Dictionary = session.foreground(AWAY_ANCHOR_EPOCH + AWAY_SECONDS)
	story["away_tick_jump"] = engine.tick_count - before_tick
	evidence["applied_ticks"] = int(report["applied_ticks"])
	evidence["capped"] = bool(report["capped"])
	evidence["arrivals"] = int(report["arrivals"])
	evidence["resource_delta"] = report["resource_delta"]
	evidence["anchor"] = session.meta.last_seen_epoch
	_advance(engine, log, 0)  # drain the ring tail into the session log

	# Phase 2: the conspiracy goes all in (military cap raised), rebuilds
	# past ~3x the floor, and commits again.
	batches = 0
	while units.army_power() < REBUILD_TARGET_POWER and batches < REBUILD_CAP_BATCHES:
		HOST.manage(engine, 12, {})
		_advance(engine, log, BATCH_TICKS)
		batches += 1
	story["rebuild_ticks"] = batches * BATCH_TICKS
	story["power2"] = units.army_power()
	story["odds2"] = int(resolver.assault_odds(engine)["win_permille"])
	story["victory_hash"] = engine.state_hash()
	engine.submit_command(&"commit_assault", &"", 0)
	_advance(engine, log, 1)
	verdicts = log.verdicts()
	var verdict2: Dictionary = verdicts[verdicts.size() - 1] if not verdicts.is_empty() else {}
	story["outcome2"] = "none" if verdict2.is_empty() else ("won" if verdict2["type"] == &"assault_won" else "lost")
	var won := log.of_type(&"run_won")
	story["won_tick"] = int(won[0]["tick"]) if not won.is_empty() else -1
	var assault_won := log.of_type(&"assault_won")
	story["assault_won_tick"] = int(assault_won[assault_won.size() - 1]["tick"]) if not assault_won.is_empty() else -2
	story["final_score"] = run.last_run_score()

	# The estate check now that the builds have had their drains.
	var built := 0
	for id in MVP.building_ids():
		if production.building_level(id) > 0:
			built += 1
	story["built_all_four"] = built == MVP.building_ids().size()

	# Restart: fresh identity, emptied state, carried bank.
	engine.submit_command(&"run_restart", &"", 0)
	_advance(engine, log, 1)
	story["leader2"] = run.leader_name()
	story["restart_reset"] = units.total_units() == 0 \
		and production.building_level(&"farm") == 0 \
		and engine.get_resource(&"food") == 0 \
		and engine.get_resource(&"timber") == 0 \
		and engine.get_resource(&"iron") == 0 \
		and (engine.get_system(&"suspicion") as SuspicionSystem).suspicion_points() == 0
	return story


func _advance(engine: SimEngine, log: SessionLog, ticks: int) -> void:
	if ticks > 0:
		engine.fast_forward(ticks)
	log.drain(engine.events)


# --- Session log (copy at drain; pooled events must never be cached) --------


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

	func verdicts() -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for entry in entries:
			if entry["type"] == &"assault_won" or entry["type"] == &"assault_lost":
				found.append(entry)
		return found


func _print_digest(story: Dictionary, evidence: Dictionary, log: SessionLog, seed: int, wall: float) -> void:
	print(
		"[full_run_ci] seed %d (regime %s): floor %dh at power %d -> %d permille -> LOST (casualties %d, spike +%d, run alive) -> away 8h37m capped to 480 ticks (+%d food, %d arrivals) -> rebuilt %dh to power %d -> %d permille -> WON at tick %d; score %d banked; restart folded %s; %d events; wall %.2fs incl. seed search"
		% [
			seed, story["regime"], story["floor_ticks"] / 60, story["power1"],
			story["odds1"], story["casualties"], story["spike"],
			int((evidence["resource_delta"] as Dictionary).get(&"food", 0)),
			evidence["arrivals"], story["rebuild_ticks"] / 60, story["power2"],
			story["odds2"], story["won_tick"], story["final_score"],
			story["leader2"], log.entries.size(), wall,
		]
	)
