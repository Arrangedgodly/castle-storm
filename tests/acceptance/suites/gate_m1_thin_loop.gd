## M1 milestone gate — the thin end-to-end loop through the UI seam
## (T-SCOPE-01; findings: docs/ultron/m1-findings.md; content since T-DATA-02:
## the FULL MVP pack, content/mvp/pack.tres).
##
## THE GATE: the whole loop — recruit -> assign -> train/gear -> assault ->
## restart, twice (victory path, then defeat path) — driven exactly the way a
## future UI/CLI host must drive it, so mistaken assumptions surface while
## they are still cheap. The seam contract this gate enforces ON ITSELF:
##
##   - WRITES go through ONE entry point: `engine.submit_command(...)`. The
##     assault is the raw `resolve_victory` command (what T-SIM-06 will
##     submit), never the system method. No system write/internals are
##     touched; no test backdoors. The STARTING GRANT is now a real verb
##     (finding F1, resolved by T-DATA-02): `grant_resources` pays the pack's
##     stipend from content, once per run — the gate still PROVES the
##     zero-grant bootstrap impossible (an honest build attempt is refused
##     first, `upgrade_denied` reason 4), then boots through the verb. ZERO
##     set_resource calls remain (that method is a documented test
##     construction seam only).
##   - READS use the systems' documented UI-query surfaces (offer_ids,
##     idle_units, upgrade_cost, army_power, leader_name, ...) only.
##   - EVENTS arrive by BOTH documented UI paths: run 1 is driven by live
##     `tick()` and captured from the `event_logged` signal (a mounted UI);
##     run 2 is driven by `fast_forward()` (no per-tick signals by design)
##     and captured by polling the ring tail (`next_seq()`/`get_event`) —
##     the exact catch-up path T-UI-09/T-PERF-01 must implement. Both feeds
##     merge into ONE session log.
##
## The session log copies every event at receipt (pooled SimEvents must
## never be cached) and is asserted to read coherently end-to-end (monotone
## seq, causally ordered transitions, hour cadence). Its digest print is the
## first UX copy reference.
##
## Replay: the identical script re-run fast-forward-only (no signals) must
## reproduce the same hash, identities, bank and event count — the live UI
## drive and the catch-up drive see the same deterministic world.
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const GATE_SEED := 20260916
const BUDGET_SECONDS := 10.0
const BATCH_TICKS := 60  # management cadence: one batch per sim-hour
const RUN1_CAP_TICKS := 60 * SimEngine.TICKS_PER_SIM_HOUR  # 60h to the floor
const RUN2_BATCHES := 18  # 18h of honest production before the losing assault
const RUN_BEAT_TYPES: Array[StringName] = [
	&"run_started", &"run_restarted", &"run_won", &"run_lost",
	&"recruit_arrived", &"unit_promoted", &"gear_equipped", &"building_built",
]


# --- Session log (the UI's event-stream capture) -----------------------------


## Copies events at receipt from either documented feed. Held SimEvent
## references are only valid until the ring slot is reused — copy, never
## cache (docs/sim-engine.md §3).
class SessionLog:
	extends RefCounted

	var entries: Array[Dictionary] = []  # {seq, tick, type, subject, value, value2, source}
	var lines: Array[String] = []
	var _ring_seq := 0  # next seq to pull from the ring (catch-up path)

	func capture_signal(event: SimEvent) -> void:
		_push(event, "signal")

	## Pulls everything recorded since the last drain — the fast-forward
	## catch-up path (no per-tick signals during fast_forward).
	func drain_ring(log: SimEventLog) -> void:
		while _ring_seq < log.next_seq():
			var event := log.get_event(_ring_seq)
			if event != null:
				_push(event, "ring")
			_ring_seq += 1

	## Marks the ring as fully consumed (used when switching from the signal
	## feed to the ring feed so no event is captured twice).
	func mark_ring_consumed(log: SimEventLog) -> void:
		_ring_seq = log.next_seq()

	func count_type(type: StringName) -> int:
		var total := 0
		for entry in entries:
			if entry["type"] == type:
				total += 1
		return total

	func count_source(source: String) -> int:
		var total := 0
		for entry in entries:
			if entry["source"] == source:
				total += 1
		return total

	func first_index(type: StringName) -> int:
		for i in entries.size():
			if entries[i]["type"] == type:
				return i
		return -1

	func histogram() -> String:
		var counts := {}
		for entry in entries:
			counts[entry["type"]] = int(counts.get(entry["type"], 0)) + 1
		var keys: Array = counts.keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s=%d" % [key, counts[key]])
		return " ".join(parts)

	func _push(event: SimEvent, source: String) -> void:
		entries.append({
			"seq": event.seq,
			"tick": event.tick,
			"type": event.type,
			"subject": event.subject,
			"value": event.value,
			"value2": event.value2,
			"source": source,
		})
		lines.append(
			"[h %6.2f] #%-4d t=%-5d %-16s %-14s v=%-4d v2=%d (%s)"
			% [
				float(event.tick) / SimEngine.TICKS_PER_SIM_HOUR, event.seq, event.tick,
				event.type, event.subject, event.value, event.value2, source,
			]
		)


# --- Suite contract ----------------------------------------------------------


func suite_name() -> String:
	return "gate_m1_thin_loop"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var engine := _build()
	var session := SessionLog.new()
	engine.event_logged.connect(session.capture_signal)
	var report := _gate_script(engine, true, session)
	report["grant_lines"] = session.count_type(&"resources_granted")
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	report["wall"] = wall
	_print_digest(report, session)

	# --- The loop completed, in accelerated CI time, through the seam.
	harness.check(bool(report["floor_met"]), "run 1 reached the thin knight floor (1 knight + 1 archer) within %dh (army %d @ %.1fh)" % [RUN1_CAP_TICKS / 60, report["army1"], float(report["run1_ticks"]) / 60.0])
	harness.check(wall < BUDGET_SECONDS, "gate loop (2 runs + 2 restarts) in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- F1, executable then resolved: the zero-grant bootstrap is still
	# impossible. The honest build attempt was refused BEFORE the grant verb
	# drained; every write — the stipend included — went through the one
	# entry point (queue empty at the end, grants counted, zero backdoor).
	harness.check(session.first_index(&"upgrade_denied") != -1 and session.first_index(&"upgrade_denied") < session.first_index(&"building_built"), "bootstrap gap proven: upgrade_denied (reason %d) precedes the first building_built" % ProductionSystem.REASON_UNAFFORDABLE)
	harness.check(int(report["grants"]) == 2, "starting grants: exactly 2 grant_resources commands (1 per run — F1 resolved by the verb; zero set_resource calls)")
	harness.check(int(report["grant_lines"]) == 2 * int(MVP.starting_grants().size()), "stipend events in the log: %d lines for %d runs (pack stipend %s)" % [int(report["grant_lines"]), 2, str(MVP.starting_grants())])
	harness.check(engine.pending_command_count() == 0, "every gameplay write went through submit_command (queue drained)")

	# --- The session log reads coherently end to end.
	harness.check(session.entries.size() > 50, "session log captured the stream (%d events)" % session.entries.size())
	var ordered := true
	for i in range(1, session.entries.size()):
		if int(session.entries[i]["seq"]) != int(session.entries[i - 1]["seq"]) + 1:
			ordered = false
			break
	harness.check(ordered, "session seq strictly +1 across BOTH feeds (signal + ring merge lossless)")
	var ticks_sane := true
	for i in range(1, session.entries.size()):
		if int(session.entries[i]["tick"]) < int(session.entries[i - 1]["tick"]):
			ticks_sane = false
			break
	harness.check(ticks_sane, "session ticks non-decreasing (causal order)")
	harness.check(session.count_source("signal") > 0 and session.count_source("ring") > 0, "both UI event paths proven: %d signal-captured + %d ring-polled" % [session.count_source("signal"), session.count_source("ring")])
	harness.check(session.count_type(&"hour_struck") == engine.tick_count / SimEngine.TICKS_PER_SIM_HOUR, "hour cadence legible: %d hour_struck for %d ticks" % [session.count_type(&"hour_struck"), engine.tick_count])

	# --- Run-frame events: exactly one of each, in causal order.
	harness.check(session.count_type(&"run_started") == 1 and session.count_type(&"run_restarted") == 2, "run frame: 1 run_started + 2 run_restarted in the log")
	harness.check(session.count_type(&"run_won") == 1 and session.count_type(&"run_lost") == 1, "assaults: 1 run_won + 1 run_lost in the log")
	harness.check(session.first_index(&"run_started") < session.first_index(&"recruit_arrived"), "run_started precedes the first recruit_arrived")
	harness.check(session.first_index(&"run_won") < session.first_index(&"run_restarted"), "run_won precedes the first restart")
	var outcome_values := []
	for entry in session.entries:
		if entry["type"] == &"run_restarted":
			outcome_values.append(int(entry["value2"]))
	harness.check(outcome_values == [RunLifecycleSystem.OUTCOME_VICTORY, RunLifecycleSystem.OUTCOME_DEFEAT], "run_restarted carries the previous outcome for the UI: %s" % str(outcome_values))

	# --- Transition causality per unit (the log alone tells each unit's story).
	harness.check(_accepted_had_arrival(session), "every recruit_accepted uid has an earlier recruit_arrived")
	harness.check(_promoted_had_training(session), "every unit_promoted uid has an earlier training_started")
	harness.check(_promoted_had_gear(session), "every knight/archer unit_promoted uid has the required gear_equipped first (knight >= 2, archer >= 1)")

	# --- Restart emptied run state exactly; identities folded fresh.
	harness.check(bool(report["restart_emptied"]), "restart emptied resources/production/units (read APIs all zero)")
	harness.check(str(report["leader1"]).length() > 3 and str(report["leader2"]).length() > 3, "identities generated: %s -> %s" % [report["leader1"], report["leader2"]])
	harness.check(report["leader2"] != report["leader1"], "restart folded a FRESH identity")
	harness.check(report["regime_ids"].has(report["regime1"]) and report["regime_ids"].has(report["regime2"]), "regimes drawn from the pack: %s, %s" % [report["regime1"], report["regime2"]])

	# --- Honest economy ran run 2 from the restarted, granted pool.
	harness.check(int(report["run2_food"]) > 0 and int(report["run2_timber"]) > 0 and int(report["run2_iron"]) > 0, "run 2 produced food +%d / timber +%d / iron +%d in %dh (iron mined — none granted)" % [report["run2_food"], report["run2_timber"], report["run2_iron"], RUN2_BATCHES])

	# --- Both outcomes banked (failure banks full progress); score formula
	# holds inside the loop (thin stub, T-SIM-08 owns the real curve).
	harness.check(int(report["score2"]) > 0, "run 2 defeat banked full progress (score %d)" % report["score2"])
	harness.check(int(report["chronicle"]) == 2, "chronicle holds both ended runs: %d" % report["chronicle"])
	harness.check(int(report["points"]) == int(report["score1"]) + int(report["score2"]), "bank == win %d + loss %d (banked %d)" % [report["score1"], report["score2"], report["points"]])
	var entry1: Dictionary = report["entry1"]
	harness.check(int(entry1["duration_ticks"]) / SimEngine.TICKS_PER_SIM_HOUR + int(entry1["army_power"]) + RunLifecycleSystem.WIN_BONUS == int(report["score1"]), "run 1 score = duration %dh + army %d + bonus %d == %d" % [int(entry1["duration_ticks"]) / 60, int(entry1["army_power"]), RunLifecycleSystem.WIN_BONUS, report["score1"]])

	# --- Replay through the catch-up drive only: same world, same story.
	var replay_engine := _build()
	var replay := _gate_script(replay_engine, false, null)
	harness.check(replay["final_hash"] == report["final_hash"], "replay (fast-forward only): identical final hash (%d)" % report["final_hash"])
	harness.check(replay["leader1"] == report["leader1"] and replay["leader2"] == report["leader2"], "replay: identical identities")
	harness.check(replay["points"] == report["points"], "replay: identical bank (%d)" % report["points"])
	harness.check(replay["next_seq"] == report["next_seq"], "replay: identical event count (%d) — the session log was the truth" % report["next_seq"])


# --- The gate script (pure function of engine + seed) -------------------------


## Runs the two-run loop. `live_run1` selects the advance mode for run 1:
## tick() per minute (live UI, signal feed) or fast_forward (catch-up, ring
## feed) — behavior-identical per the engine contract, which the replay
## check turns into the gate's determinism statement.
func _gate_script(engine: SimEngine, live_run1: bool, session: SessionLog) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var report := {"grants": 0, "regime_ids": _regime_ids()}

	# --- Run 1: start, honest bootstrap attempt (refused), grant verb, build.
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"upgrade_building", &"farm", 1)  # zero-grant: refused (F1 proof)
	_advance(engine, 1, live_run1, session)
	engine.submit_command(&"grant_resources", &"", 0)  # the stipend, from pack content
	report["grants"] = report["grants"] + 1
	_advance(engine, 1, live_run1, session)
	for id in MVP.building_ids():
		engine.submit_command(&"upgrade_building", id, 1)  # all 4 buildings
	_advance(engine, 1, live_run1, session)
	var boot := {
		&"food": engine.get_resource(&"food"),
		&"timber": engine.get_resource(&"timber"),
		&"iron": engine.get_resource(&"iron"),
	}

	# --- Recruit -> assign -> produce -> train/gear/promote to the floor.
	var ran := 0
	while ran < RUN1_CAP_TICKS and not _floor_met(engine):
		_manage(engine)
		_advance(engine, BATCH_TICKS, live_run1, session)
		ran += BATCH_TICKS
		_measure_firsts(engine, report, boot)
	report["floor_met"] = _floor_met(engine)
	report["run1_ticks"] = ran + 2
	report["army1"] = (engine.get_system(&"units") as UnitLifecycleSystem).army_power()
	report["leader1"] = run.leader_name()
	report["regime1"] = run.regime_id()

	# --- Assault (thin: the raw resolve command T-SIM-06 will submit).
	engine.submit_command(&"resolve_victory", &"win", -1)
	_advance(engine, 1, live_run1, session)
	report["score1"] = run.last_run_score()
	report["entry1"] = run.meta.chronicle[0]

	# --- Restart: fresh identity, emptied run state (victory redraws regime).
	engine.submit_command(&"run_restart", &"", 0)
	_advance(engine, 1, live_run1, session)
	report["restart_emptied"] = _run_state_empty(engine)
	report["leader2"] = run.leader_name()
	report["regime2"] = run.regime_id()
	# Run 1's stream arrived via the signal feed; mark the ring consumed so
	# the catch-up feed below picks up only run 2's events (no double capture).
	if session != null:
		session.mark_ring_consumed(engine.events)

	# --- Run 2: honest production from a fresh stipend, then a losing assault.
	engine.submit_command(&"grant_resources", &"", 0)
	report["grants"] = report["grants"] + 1
	for id in MVP.building_ids():
		engine.submit_command(&"upgrade_building", id, 1)
	_advance(engine, 1, false, session)  # from here on: the catch-up drive
	var boot2 := {
		&"food": engine.get_resource(&"food"),
		&"timber": engine.get_resource(&"timber"),
		&"iron": engine.get_resource(&"iron"),
	}
	for _i in RUN2_BATCHES:
		_manage(engine)
		_advance(engine, BATCH_TICKS, false, session)
	report["run2_food"] = engine.get_resource(&"food") - int(boot2[&"food"])
	report["run2_timber"] = engine.get_resource(&"timber") - int(boot2[&"timber"])
	report["run2_iron"] = engine.get_resource(&"iron") - int(boot2[&"iron"])
	engine.submit_command(&"resolve_victory", &"loss", -1)
	_advance(engine, 1, false, session)
	report["score2"] = run.last_run_score()

	# --- Restart again: the loop can continue (fresh identity, bare hands).
	engine.submit_command(&"run_restart", &"", 0)
	_advance(engine, 1, false, session)
	report["leader3"] = run.leader_name()
	report["restart2_emptied"] = _run_state_empty(engine)

	report["chronicle"] = run.meta.chronicle.size()
	report["points"] = run.meta.legacy_points
	report["ticks"] = engine.tick_count
	report["next_seq"] = engine.events.next_seq()
	report["final_hash"] = engine.state_hash()
	return report


## Advances `ticks` sim-minutes. Live mode calls tick() per minute (per-event
## signals — the session captures from the signal feed); catch-up mode uses
## one fast_forward (no per-tick signals by design — the session then drains
## the ring tail, the documented UI catch-up path). Never both for the same
## advance: each event lands in the session exactly once.
func _advance(engine: SimEngine, ticks: int, live: bool, session: SessionLog) -> void:
	if live:
		for _i in range(ticks):
			engine.tick()
	else:
		engine.fast_forward(ticks)
		if session != null:
			session.drain_ring(engine.events)


# --- Management policy (deterministic, pure reads -> commands) ---------------


## One management batch, the way a UI host scripts the loop: accept the gate,
## branch peasants (economy first: two workers before any military, then up
## to three military tracks — a roster decision, not a batch-index decision),
## advance the military chain, gear + promote the held ranks when affordable,
## keep workers balanced across producers (fewest-assigned first), upgrade
## the first affordable building. Affordability and idle counts are tracked
## host-side per batch so the queue never carries a doomed command (a careful
## UI does the same — denial events stay for genuinely contested states).
func _manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var funds := {
		&"food": engine.get_resource(&"food"),
		&"timber": engine.get_resource(&"timber"),
		&"iron": engine.get_resource(&"iron"),
	}
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	# Branch peasants: economy first (two workers), then up to three military.
	var worker_total := units.unit_count(&"worker")
	var military := units.unit_count(&"militia") + units.unit_count(&"trainee") \
		+ units.unit_count(&"knight") + units.unit_count(&"archer")
	for uid in units.unit_ids():
		var role := units.training_target(uid)
		if role == &"militia" or role == &"trainee" or role == &"knight" or role == &"archer":
			military += 1
	for uid in units.idle_units(&"peasant"):
		if worker_total >= 2 and military < 3:
			military += 1
			engine.submit_command(&"assign_role", &"militia", uid)
		else:
			worker_total += 1
			engine.submit_command(&"assign_role", &"worker", uid)
	for uid in units.idle_units(&"militia"):
		engine.submit_command(&"start_training", &"trainee", uid)
	# Branch trainees toward the currently fewer committed rank.
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
	# Gear the held ranks cheapest-first, then promote the fully geared (the
	# equip commands drain BEFORE the promote command in the same tick).
	for uid in units.awaiting_promotion_ids():
		for slot in units.missing_gear_slots(uid):
			for gear_id in units.gear_ids_for_slot(slot):
				if _gear_affordable(gear_id, funds):
					_pay_gear(gear_id, funds)
					engine.submit_command(&"equip_gear", gear_id, uid)
					break
		if units.missing_gear_slots(uid).is_empty():
			engine.submit_command(&"promote", &"", uid)
	# Balance idle workers across producers: fewest-assigned first, one at a
	# time (host-side idle/assigned mirrors so no assign can be denied).
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
	# Construct any still-unbuilt building when affordable (the 4th card must
	# exist even under a cost-quirk regime's tighter boot), then upgrade the
	# first affordable built one.
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


# --- Session coherence helpers ------------------------------------------------


func _accepted_had_arrival(session: SessionLog) -> bool:
	var arrivals := {}
	for entry in session.entries:
		if entry["type"] == &"recruit_arrived":
			arrivals[int(entry["value"])] = true
		elif entry["type"] == &"recruit_accepted" and not arrivals.has(int(entry["value"])):
			return false
	return true


func _promoted_had_training(session: SessionLog) -> bool:
	var started := {}
	for entry in session.entries:
		if entry["type"] == &"training_started":
			started[int(entry["value"])] = true
		elif entry["type"] == &"unit_promoted" and not started.has(int(entry["value"])):
			return false
	return true


func _promoted_had_gear(session: SessionLog) -> bool:
	# Example-pack rule: knight requires weapon + armor (2 slots), archer
	# requires weapon (1). The log alone must show the equips before the rank.
	var gear_count := {}
	for entry in session.entries:
		var uid := int(entry["value"])
		if entry["type"] == &"gear_equipped":
			gear_count[uid] = int(gear_count.get(uid, 0)) + 1
		elif entry["type"] == &"unit_promoted":
			var required := 2 if entry["subject"] == &"knight" else 1
			if (entry["subject"] == &"knight" or entry["subject"] == &"archer") \
					and int(gear_count.get(uid, 0)) < required:
				return false
	return true


# --- Read-API helpers ----------------------------------------------------------


## The thin victory line (the REAL knight floor is T-SIM-06/08): one knight
## AND one archer fielded — both promotion branches proven through gear.
func _floor_met(engine: SimEngine) -> bool:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	return units.unit_count(&"knight") >= 1 and units.unit_count(&"archer") >= 1


func _run_state_empty(engine: SimEngine) -> bool:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var all_empty := units.total_units() == 0 \
		and units.pending_offers() == 0 \
		and units.arrivals_total == 0 \
		and production.idle_workers() == 0 \
		and engine.get_resource(&"food") == 0 \
		and engine.get_resource(&"timber") == 0 \
		and engine.get_resource(&"iron") == 0
	for id in MVP.building_ids():
		all_empty = all_empty and production.building_level(id) == 0
	return all_empty


## First-time markers for the pacing digest (m1-findings cites these).
func _measure_firsts(engine: SimEngine, report: Dictionary, boot: Dictionary) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	if not report.has("first_worker_h") and units.unit_count(&"worker") > 0:
		report["first_worker_h"] = engine.sim_hours()
	if not report.has("first_food_h") and engine.get_resource(&"food") > int(boot[&"food"]):
		report["first_food_h"] = engine.sim_hours()
	if not report.has("first_iron_h") and engine.get_resource(&"iron") > int(boot[&"iron"]):
		report["first_iron_h"] = engine.sim_hours()
	if not report.has("first_knight_h") and units.unit_count(&"knight") > 0:
		report["first_knight_h"] = engine.sim_hours()
	if not report.has("first_archer_h") and units.unit_count(&"archer") > 0:
		report["first_archer_h"] = engine.sim_hours()
	if not report.has("upgrades_done") :
		report["upgrades_done"] = 0
	var production := engine.get_system(&"production") as ProductionSystem
	var levels := 0
	for id in MVP.building_ids():
		levels += production.building_level(id)
	report["upgrades_done"] = levels - MVP.building_ids().size()  # the initial constructions


func _print_digest(report: Dictionary, session: SessionLog) -> void:
	print(
		"[gate_m1_thin_loop] M1 thin loop via the UI seam: run 1 '%s' (%s) hit the floor 1K+1A @ %.1fh (army %d); run 2 '%s' produced F%d/T%d/I%d in %dh then lost; banked %d lp (win %d + loss %d); grants %d via grant_resources (stipend %s); %d events (%d signal / %d ring); firsts: worker %.1fh food %.1fh iron %.1fh knight %.1fh archer %.1fh; %d upgrades; wall %.3fs; hash %d"
		% [
			report["leader1"], report["regime1"], float(report["run1_ticks"]) / 60.0, report["army1"],
			report["leader2"], report["run2_food"], report["run2_timber"], report["run2_iron"], RUN2_BATCHES,
			report["points"], report["score1"], report["score2"], report["grants"], str(MVP.starting_grants()),
			session.entries.size(), session.count_source("signal"), session.count_source("ring"),
			report.get("first_worker_h", -1.0), report.get("first_food_h", -1.0), report.get("first_iron_h", -1.0),
			report.get("first_knight_h", -1.0), report.get("first_archer_h", -1.0),
			report.get("upgrades_done", 0), report["wall"], report["final_hash"],
		]
	)
	print("[gate_m1_thin_loop] event histogram: %s" % session.histogram())
	# The UX copy reference: the run-beat lines of the session log.
	var beats: Array[String] = []
	for i in session.entries.size():
		if RUN_BEAT_TYPES.has(session.entries[i]["type"]):
			beats.append(session.lines[i])
	var shown := beats.size()
	if shown > 60:
		print("[gate_m1_thin_loop] session beats (first 30 of %d):" % shown)
		for line in beats.slice(0, 30):
			print("  %s" % line)
		print("  ... (%d more) ..." % (shown - 36))
		for line in beats.slice(shown - 6, shown):
			print("  %s" % line)
	else:
		print("[gate_m1_thin_loop] session beats (%d):" % shown)
		for line in beats:
			print("  %s" % line)


# --- Fixtures (the T-DATA-02 MVP pack; the host holds content) -----------------


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


func _build() -> SimEngine:
	# Host boot composition (registration order mirrors causality); the
	# stipend is the pack's own starting grant — the honest boot, paid
	# through the grant verb.
	return MVP.full_stack(GATE_SEED)


# --- Host-side affordability (content is host-held; no engine quote for gear)


func _gear_recipe(gear_id: StringName) -> Dictionary:
	for gear in _gear_defs():
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
