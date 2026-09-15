## Acceptance marathon — the suspicion pressure curve (T-SIM-05; content:
## the T-DATA-02 MVP pack, suspicion system registered LAST per §14).
##
## The pressure-system shape from R4 §C proven at full-stack scale, honestly
## driven (no test seams — every point arrives through real acts):
##
##   RUN A (forced loud): accept every recruit, EVERY peasant into the
##   military pipeline, gear + promote aggressively, upgrade buildings every
##   chunk — the reckless profile. Must cross warn (35) and the crackdown
##   telegraph (70), and finally get CRUSHED at 100 mid-growth: the run
##   fails through the T-SIM-04 defeat path (run_crushed -> run_lost),
##   banks FULL progress, and a restart resets every suspicion field; the
##   follow-up run stays quiet (no instant re-crush).
##
##   RUN B (lay low): grow loud until the telegraph arms, then go QUIET
##   (accept-to-worker, no military, no upgrades). Passive decay must drag
##   the meter below 70 and CANCEL the telegraph — the R4 tension mechanic:
##   the crackdown is a warning you can still heed. No crackdown ever fires.
##
##   Determinism: the whole Run A script replays bit-for-bit (same identities
##   via the run system, same bank, same crush tick, same hash).
##
## Every `crackdown_seized` event in the stream is re-derived exactly from
## its own payload (seized == floor((seized + remaining) x 0.4)) — the
## floor-40% rule checked against real marathon data, not a fixture.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const RUN_SEED := 20260917
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const CAP_TICKS := 600 * SimEngine.TICKS_PER_SIM_HOUR  # 600h ceiling
const QUIET_TICKS := 36 * SimEngine.TICKS_PER_SIM_HOUR  # 36h lay-low window


func suite_name() -> String:
	return "marathon_suspicion_pressure"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var report := _crush_run(_build())
	var quiet := _cancel_run(_build())
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var total_ticks: int = report["ticks"] + quiet["ticks"]

	print(
		"[marathon_suspicion_pressure] run A crushed at %dh (warn %d, telegraphs %d, crackdowns %d, banked %d lp); run B cancelled the telegraph at %dh and never fired; %d ticks total in %.3fs — %.0f ticks/s; final hashes %d / %d"
		% [
			report["crush_tick"] / SimEngine.TICKS_PER_SIM_HOUR, report["warns"],
			report["telegraphs"], report["crackdowns"], report["points"],
			quiet["cancel_tick"] / SimEngine.TICKS_PER_SIM_HOUR, total_ticks, wall,
			float(total_ticks) / wall, report["final_hash"], quiet["final_hash"],
		]
	)

	# --- Run A: reckless growth is crushed mid-run, banks meta, restarts clean.
	harness.check(bool(report["crushed"]), "forced-loud run CRUSHED at 100 within %dh (crush tick %d)" % [CAP_TICKS / 60, report["crush_tick"]])
	harness.check(report["warns"] >= 1, "warn zone crossed on the way up (%d warn events)" % report["warns"])
	harness.check(report["telegraphs"] >= 1, "crackdown telegraph fired at >= 70 (%d armed)" % report["telegraphs"])
	harness.check(report["seize_math_ok"], "every crackdown_seized event satisfies floor(40%%) exactly (%d events)" % report["seized_events"])
	harness.check(bool(report["run_lost"]), "crush resolved through the run system: run_lost banked %d lp (score %d, outcome %s)" % [report["points"], report["score"], report["outcome"]])
	harness.check(report["score"] > 0, "failure banked FULL progress (army %d power at crush, duration %dh)" % [report["army_power"], report["duration_hours"]])
	harness.check(str(report["outcome"]) == "defeat", "chronicle records the suspicion defeat")
	harness.check(bool(report["restart_reset"]), "restart after the crush reset every suspicion field")
	harness.check(report["post_restart_suspicion"] <= 5, "follow-up run stays quiet for 24h (suspicion %d)" % report["post_restart_suspicion"])

	# --- Run B: the telegraph is a warning you can still heed.
	harness.check(quiet["telegraphs"] >= 1, "run B armed a crackdown telegraph (%d)" % quiet["telegraphs"])
	harness.check(bool(quiet["cancelled"]), "laying low cancelled the telegraph (tick %d)" % quiet["cancel_tick"])
	harness.check(quiet["crackdowns"] == 0, "no crackdown ever fired in run B (%d)" % quiet["crackdowns"])
	harness.check(bool(quiet["landed_past"]), "run B ran WELL past the original landing tick before stopping")
	harness.check(quiet["suspicion_end"] < 70, "the meter kept falling while quiet (%d)" % quiet["suspicion_end"])

	# --- Determinism: the whole Run A script replays bit-for-bit.
	var replay := _crush_run(_build())
	harness.check(replay["crush_tick"] == report["crush_tick"], "replay: identical crush tick (%d)" % replay["crush_tick"])
	harness.check(replay["points"] == report["points"], "replay: identical bank (%d)" % replay["points"])
	harness.check(replay["final_hash"] == report["final_hash"], "replay: identical final hash (%d)" % replay["final_hash"])
	harness.check(wall < BUDGET_SECONDS, "both pressure runs + replay in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])


# --- Run A: the forced-loud crush ------------------------------------------------


## Full MVP pack stack + suspicion registered LAST (the §14 order).
func _build() -> SimEngine:
	var pack := MVP.load_mvp()
	var engine := MVP.full_stack(RUN_SEED, MVP.MARATHON_STIPEND)
	engine.register_system(SuspicionSystem.new(pack.tunables, pack.units))
	return engine


func _crush_run(engine: SimEngine) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	var report := {}
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()

	# Loud growth loop: manage every 10h until the Crown wins.
	var upgrade_index := 0
	var producers := MVP.producer_ids()
	while run.is_running() and engine.tick_count < CAP_TICKS:
		_loud_manage(engine, producers, upgrade_index)
		upgrade_index += 1
		engine.fast_forward(CHUNK_TICKS)
	report["crushed"] = not run.is_running() and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT
	report["crush_tick"] = _last_of(engine, &"run_crushed")
	report["warns"] = _count(engine, &"suspicion_warn")
	report["telegraphs"] = _count(engine, &"suspicion_telegraph")
	report["crackdowns"] = heat.crackdowns_total
	report["seized_events"] = _count(engine, &"crackdown_seized")
	report["seize_math_ok"] = _seize_math_exact(engine)
	report["run_lost"] = _count(engine, &"run_lost") == 1
	report["points"] = run.meta.legacy_points
	report["score"] = run.last_run_score()
	report["outcome"] = String(run.meta.chronicle[0]["outcome"]) if not run.meta.chronicle.is_empty() else "?"
	report["army_power"] = int(run.meta.chronicle[0]["army_power"]) if not run.meta.chronicle.is_empty() else -1
	report["duration_hours"] = int(run.meta.chronicle[0]["duration_ticks"]) / 60 if not run.meta.chronicle.is_empty() else -1

	# Restart after the crush: the reset contract empties every field.
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	report["restart_reset"] = heat.suspicion == 0 and heat.crackdowns_total == 0 \
		and heat.crackdown_land_tick == -1 and heat.relief_until_tick == 0 \
		and run.is_running() and run.current_run_index() == 2
	# 24h of quiet follow-up: accept-to-worker keeps the gate clear; the new
	# run must not be anywhere near death.
	var quiet_ticks := 24 * SimEngine.TICKS_PER_SIM_HOUR
	while quiet_ticks > 0:
		_quiet_manage(engine)
		var chunk: int = mini(CHUNK_TICKS, quiet_ticks)
		engine.fast_forward(chunk)
		quiet_ticks -= chunk
	report["post_restart_suspicion"] = heat.suspicion
	report["ticks"] = engine.tick_count
	report["final_hash"] = engine.state_hash()
	return report


## The reckless profile: every recruit accepted, EVERY peasant into the
## military pipeline, every hop trained, cheapest gear + promote, one
## building level per chunk (round-robin). Pure reads -> commands.
func _loud_manage(engine: SimEngine, producers: Array[StringName], upgrade_index: int) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	for uid in units.idle_units(&"peasant"):
		engine.submit_command(&"assign_role", &"militia", uid)
	for uid in units.idle_units(&"militia"):
		engine.submit_command(&"start_training", &"trainee", uid)
	for uid in units.idle_units(&"trainee"):
		engine.submit_command(&"start_training", &"archer", uid)
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			var options := units.gear_ids_for_slot(slot)
			if not options.is_empty():
				engine.submit_command(&"equip_gear", options[0], uid)
		engine.submit_command(&"promote", &"", uid)
	engine.submit_command(&"upgrade_building", producers[upgrade_index % producers.size()], 0)


## The lay-low profile: keep the gate clear (accepts), everyone farming
## (quiet 0-suspicion worker trainings), no military, no upgrades.
func _quiet_manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	for uid in units.idle_units(&"peasant"):
		engine.submit_command(&"assign_role", &"worker", uid)
	var production := engine.get_system(&"production") as ProductionSystem
	for id in MVP.producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


# --- Run B: arm the telegraph, then lay low and cancel it -------------------------


func _cancel_run(engine: SimEngine) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	var report := {}
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()

	# Loud phase at 1h granularity, the CAREFUL-loud profile: militia
	# trainings (+8 per completion) + one building upgrade per hour (+4)
	# climb ~8/h gross vs -5/h decay, with commitments tapering near the
	# threshold — militia only below 60, instant upgrades only below 68 —
	# so the meter crosses 70 on residual heat with NOTHING committed
	# behind it (a training committed during a telegraph cannot be
	# un-committed; committing recklessly is run A's job). The telegraph
	# arms at ~70-74; a quiet estate (followers ~1.2/h vs tier-2 decay
	# -2.5/h) dips below 70 well inside the 4h countdown.
	var producers := MVP.producer_ids()
	var upgrade_index := 0
	while run.is_running() and heat.crackdown_land_tick < 0 and engine.tick_count < CAP_TICKS:
		var units := engine.get_system(&"units") as UnitLifecycleSystem
		for uid in units.offer_ids():
			engine.submit_command(&"recruit_accept", &"", uid)
		if heat.suspicion < 60:
			for uid in units.idle_units(&"peasant"):
				engine.submit_command(&"assign_role", &"militia", uid)
		if heat.suspicion < 68:
			engine.submit_command(&"upgrade_building", producers[upgrade_index % producers.size()], 0)
			upgrade_index += 1
		engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	report["telegraphs"] = _count(engine, &"suspicion_telegraph")
	var land := heat.crackdown_land_tick

	# Quiet phase: accept everyone into the WORKER role (quiet trainings),
	# keep the gate clear, no upgrades, no military. Quiet presence (a dozen
	# followers x 0.1/h, buildings dial default 0) loses to the tier-2 decay
	# (-2.5/h): the meter dips below 70 and the riders stand down — then
	# keeps falling under the -5/h low-tier rate.
	var quiet_ticks := QUIET_TICKS
	while quiet_ticks > 0 and heat.crackdowns_total == 0:
		_quiet_manage(engine)
		var chunk: int = mini(CHUNK_TICKS, quiet_ticks)
		engine.fast_forward(chunk)
		quiet_ticks -= chunk
	report["cancelled"] = _count(engine, &"crackdown_cancelled") >= 1
	report["cancel_tick"] = _last_of(engine, &"crackdown_cancelled")
	report["crackdowns"] = heat.crackdowns_total
	report["suspicion_end"] = heat.suspicion
	report["ticks"] = engine.tick_count
	report["final_hash"] = engine.state_hash()
	report["landed_past"] = engine.tick_count > land + 10 * SimEngine.TICKS_PER_SIM_HOUR if land > 0 else false
	return report


# --- Event-stream helpers ---------------------------------------------------------


func _count(engine: SimEngine, type: StringName) -> int:
	var total := 0
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			total += 1
	return total


func _last_of(engine: SimEngine, type: StringName) -> int:
	var last := -1
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			last = event.tick
	return last


## Every crackdown_seized event re-derives itself: seized == floor((seized +
## remaining) x 0.4) — the remaining field IS stock-before minus seized, so
## the pair carries its own proof.
func _seize_math_exact(engine: SimEngine) -> bool:
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event == null or event.type != &"crackdown_seized":
			continue
		var stock := event.value + event.value2
		if event.value != stock * 400 / 1000:
			return false
	return true
