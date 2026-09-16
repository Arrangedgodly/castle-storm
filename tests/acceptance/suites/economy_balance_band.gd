## Acceptance suite (T-SIM-08) — the economy balance band, pinned in CI.
##
## The tuned content pack (docs/balance.md — the sweep, the values, the
## reasoning) must keep the town-hall targets reachable, machine-checked on
## the CANONICAL host composition (`_full_stack.gd`):
##
##   OPENING (journey 1)   first recruit <= 15 real minutes of the first
##                         session (sim-min == real min at 1 tick = 1
##                         sim-min); first assignment/worker and first food
##                         trickle visible fast (M1 finding F2's fix: the
##                         opening rush).
##   FIRST WIN (2-4 days)  at a CASUAL cadence — 4 check-ins/day (6h apart,
##                         3-minute sessions, away windows through the REAL
##                         catch-up service) — every measured seed wins, the
##                         mean sits inside 48-96 sim-hours (~2-4 wall days
##                         at ~24 sim-h/day), and the multi-loss tail stays
##                         bounded (assault losses are the variance, by
##                         design: set-back, never death).
##   RECOVERY (~day-scale) after a failed assault the run keeps running and
##                         re-crosses the commit line within ~3 days.
##   GREED (the failure    an all-in conspiracy that never lays low IS
##           mode)         crushed — crushes come from greed, not from
##                         existing (the T-QA-02 finding's inversion).
##   CHECK-IN VALUE        a mid-run 5-minute live window sees gross
##                         production move; a full cycle resolves events and
##                         banks away accrual (the 3-5 min ritual pays).
##
## The player model matches scripts/balance_sweep.gd exactly (the same
## functions, fixed seeds — this suite is the sweep's chosen-configuration
## row made permanent). Deterministic: fixed seeds, zero test-side RNG.
extends RefCounted

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

## Four fixed seeds, one per regime flavor (measured 2026-09-15; the sweep's
## BASE_SEED block: 20261201 gilded_crown, 20261202 velvet_fist,
## 20261203 paper_crown, 20261207 iron_rotunda).
const SEEDS: Array[int] = [20261201, 20261202, 20261203, 20261207]
const GREED_SEED := 20261201

const CADENCE_HOURS := 6  # 4 check-ins/day: ~24 sim-h per wall day
const LIVE_SESSION_TICKS := 3  # the 3-5 minute session, minute-grained
const COMMIT_PERMILLE := 450  # the sensible player's commit line
const WIN_CAP_HOURS := 240  # no seed may need longer than this
const WIN_TAIL_HOURS := 132  # measured slowest 127h + headroom (loss churn)
const WIN_MEAN_MIN_HOURS := 48  # the band's floor: not trivially fast
const WIN_MEAN_MAX_HOURS := 96  # the band's ceiling: 4 days at 24h/day
const RECOVERY_CAP_HOURS := 72  # failed-assault recovery is ~day scale
const BUDGET_SECONDS := 60.0


func suite_name() -> String:
	return "economy_balance_band"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()

	# --- Opening: journey 1 on the shipped content.
	var opening := _measure_opening(SEEDS[0])
	harness.check(int(opening["recruit"]) > 0 and int(opening["recruit"]) <= 15, "journey 1: first recruit within 15 real minutes (measured %d min — the opening rush, M1 finding F2 fixed)" % opening["recruit"])
	harness.check(int(opening["worker"]) > 0 and int(opening["worker"]) <= 60, "first worker promoted within the hour (measured %d min: rush + assignment + 30-min training)" % opening["worker"])
	harness.check(int(opening["food"]) > 0 and int(opening["food"]) <= 75, "first food trickle visible fast (measured %d min: staffed farm producing)" % opening["food"])
	harness.check(int(opening["arrivals_2h"]) >= 3, "the rush is real: %d arrivals within the first 2h (then the normal cadence)" % opening["arrivals_2h"])

	# --- First win at the casual cadence, one seed per regime.
	var wins := 0
	var hours_total := 0
	var slowest := 0
	var warns := 0
	var telegraphs := 0
	var hours_per_seed: Array[int] = []
	var recoveries: Array[int] = []
	for seed in SEEDS:
		var story := _measure_first_win(seed)
		var hours := int(story["win_tick"]) / 60
		hours_per_seed.append(hours if bool(story["won"]) else -1)
		warns += int(story["warns"])
		telegraphs += int(story["telegraphs"])
		if bool(story["won"]):
			wins += 1
			hours_total += hours
			slowest = maxi(slowest, hours)
		if int(story["losses"]) > 0 and bool(story["won"]):
			recoveries.append((int(story["win_tick"]) - int(story["first_loss_tick"])) / 60)
	harness.check(wins == SEEDS.size(), "every regime wins within %dh at 4 check-ins/day (won %d/%d; hours %s)" % [WIN_CAP_HOURS, wins, SEEDS.size(), str(hours_per_seed)])
	harness.check(hours_total / maxi(1, wins) >= WIN_MEAN_MIN_HOURS and hours_total / maxi(1, wins) <= WIN_MEAN_MAX_HOURS, "first-win mean inside the 2-4 day band (mean %dh over %d regimes; slowest %dh — assault-loss churn, the designed variance)" % [hours_total / maxi(1, wins), wins, slowest])
	harness.check(slowest <= WIN_TAIL_HOURS, "the multi-loss tail stays bounded (slowest %dh <= %dh)" % [slowest, WIN_TAIL_HOURS])
	for recovery in recoveries:
		harness.check(recovery <= RECOVERY_CAP_HOURS, "failed-assault recovery is day-scale (%dh <= %dh; set-back, never death)" % [recovery, RECOVERY_CAP_HOURS])
	harness.check(warns >= 1, "the tension rhythm is live during the all-in phase: %d warns / %d telegraphs across the runs" % [warns, telegraphs])

	# --- Greed: the failure mode exists, on the greedy side of the line.
	var greed := _measure_greed(GREED_SEED, 400)
	harness.check(int(greed["crushes"]) > 0, "an all-in conspiracy that never lays low IS crushed (at ~%dh, after %d warns — crushes come from GREED, not from existing)" % [int(greed["crush_tick"]) / 60, int(greed["warns"])])
	harness.check(int(greed["warns"]) >= 1, "the greed death was telegraphed: %d warn zone entries before the crush" % greed["warns"])

	# --- Check-in value: the 3-5 minute ritual pays.
	var value := _measure_checkin_value(SEEDS[0], CADENCE_HOURS)
	harness.check(int(value["live_gross_per_5min"]) > 0, "a mid-run 5-min live window sees gross production move (~+%d resources)" % value["live_gross_per_5min"])
	harness.check(int(value["away_delta_per_window"]) > 0 and int(value["events_per_cycle"]) > 0, "one check-in cycle resolves %d events and banks ~+%d resources of away accrual (the ritual pays)" % [value["events_per_cycle"], value["away_delta_per_window"]])

	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	_print_digest(opening, wins, hours_total / maxi(1, wins), slowest, warns, telegraphs, greed, value, wall)
	harness.check(wall < BUDGET_SECONDS, "balance band suite in < %.0fs (took %.2fs)" % [BUDGET_SECONDS, wall])


# --- The player model (mirrors scripts/balance_sweep.gd exactly) ---------------


## The casual player's population line: the conspiracy grows with the camp
## (10 bodies + one per producer level) — a fixed cap would freeze the army
## the moment the workers fill it (workers cannot rebranch).
func _estate_cap(production: ProductionSystem) -> int:
	var levels := 0
	for id in MVP.producer_ids():
		levels += production.building_level(id)
	return 10 + levels


## Journey 1: attentive opening (a manage batch every 5 sim-min, everyone
## into the workforce). Sim-minutes from run start; the food trickle is the
## first minute whose food stock rises over the previous minute.
func _measure_opening(seed: int) -> Dictionary:
	var session: Variant = HOST.session(seed)
	var engine: SimEngine = session.engine
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var out := {"recruit": -1, "worker": -1, "food": -1, "arrivals_2h": 0}
	var food_prev := -1
	var seq := 0
	for i in range(240):
		if i % 5 == 0:
			HOST.manage(engine, 0, {})
		engine.fast_forward(1)
		while seq < engine.events.next_seq():
			var event := engine.events.get_event(seq)
			if event != null:
				if event.type == &"recruit_arrived":
					if i < 120:
						out["arrivals_2h"] += 1
					if out["recruit"] < 0:
						out["recruit"] = i + 1
				elif event.type == &"unit_promoted" and event.subject == &"worker" and out["worker"] < 0:
					out["worker"] = i + 1
			seq += 1
		var food_now := int(engine.get_resource(&"food"))
		if out["food"] < 0 and food_prev >= 0 and food_now > food_prev:
			out["food"] = i + 1
		food_prev = food_now
	return out


## The casual loop: manage once per check-in, a 3-minute live session, the
## away window through the REAL catch-up service (8h cap honored), commit at
## the sensible line, fold after a crush. Phase 1 measured (military 3),
## all-in once the floor is met (military 12).
func _measure_first_win(seed: int) -> Dictionary:
	var session: Variant = HOST.session(seed)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	var story := {
		"won": false, "win_tick": -1, "losses": 0, "first_loss_tick": -1,
		"warns": 0, "telegraphs": 0, "crushed": 0, "regime": run.regime_id(),
	}
	var epoch := 1_750_000_000
	var seq := 0
	while engine.tick_count < WIN_CAP_HOURS * 60:
		var laying_low := suspicion.suspicion_points() >= 70
		var military := 12 if resolver.floor_met(engine) else 3
		HOST.manage(engine, military, {&"laying_low": laying_low, &"population_cap": _estate_cap(production)})
		engine.fast_forward(LIVE_SESSION_TICKS)
		while seq < engine.events.next_seq():
			var event := engine.events.get_event(seq)
			if event != null:
				match event.type:
					&"suspicion_warn":
						story["warns"] += 1
					&"suspicion_telegraph":
						story["telegraphs"] += 1
			seq += 1
		if not run.is_running():
			story["crushed"] += 1
		elif resolver.floor_met(engine) and int(resolver.assault_odds(engine)["win_permille"]) >= COMMIT_PERMILLE:
			engine.submit_command(&"commit_assault", &"", 0)
			engine.fast_forward(1)
			if run.run_outcome() == RunLifecycleSystem.OUTCOME_VICTORY:
				story["won"] = true
				story["win_tick"] = engine.tick_count
				break
			story["losses"] += 1
			if story["first_loss_tick"] < 0:
				story["first_loss_tick"] = engine.tick_count
		epoch += LIVE_SESSION_TICKS * 60
		session.mark_seen(epoch)
		epoch += CADENCE_HOURS * 3600
		session.foreground(epoch)
		if not run.is_running() and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT:
			engine.submit_command(&"run_restart", &"", 0)
			engine.submit_command(&"grant_resources", &"", 0)
			engine.fast_forward(1)
	return story


## The greed probe: military 24, population 40, never lays low. Bounded by
## `hours`; stops at the first crush (the failure mode is proven).
func _measure_greed(seed: int, hours: int) -> Dictionary:
	var session: Variant = HOST.session(seed)
	var engine: SimEngine = session.engine
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var tally := {"crushes": 0, "warns": 0, "crush_tick": -1}
	var seq := 0
	for w in range(hours / 2):
		HOST.manage(engine, 24, {&"population_cap": 40})
		engine.fast_forward(120)
		while seq < engine.events.next_seq():
			var event := engine.events.get_event(seq)
			if event != null:
				match event.type:
					&"suspicion_warn":
						tally["warns"] += 1
					&"run_crushed":
						tally["crushes"] += 1
						tally["crush_tick"] = event.tick
			seq += 1
		if tally["crushes"] > 0:
			break
	return tally


## What one full check-in cycle resolves mid-run (live session + away
## window), gross of the session's own spends.
func _measure_checkin_value(seed: int, cadence_hours: int) -> Dictionary:
	var session: Variant = HOST.session(seed)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	var epoch := 1_750_000_000
	var out := {"live_gross_per_5min": 0, "away_delta_per_window": 0, "events_per_cycle": 0}
	var live_total := 0
	var away_total := 0
	var events_total := 0
	var measured := 0
	var batches := 0
	while batches * cadence_hours < 120 and measured < 2:
		var laying_low := suspicion.suspicion_points() >= 70
		var military := 12 if resolver.floor_met(engine) else 3
		var ledger: Dictionary = HOST.manage(engine, military, {&"laying_low": laying_low, &"population_cap": _estate_cap(production)})
		var seq_before := engine.events.next_seq()
		var stocks_before := {}
		for id in engine.resources.keys():
			stocks_before[id] = int(engine.resources[id])
		engine.fast_forward(LIVE_SESSION_TICKS)
		for id in stocks_before:
			live_total += int(engine.resources[id]) - int(stocks_before[id]) + int(ledger.get(id, 0))
		epoch += LIVE_SESSION_TICKS * 60
		session.mark_seen(epoch)
		var stocks_mid := {}
		for id in engine.resources.keys():
			stocks_mid[id] = int(engine.resources[id])
		epoch += cadence_hours * 3600
		session.foreground(epoch)
		for id in stocks_mid:
			away_total += int(engine.resources[id]) - int(stocks_mid[id])
		events_total += engine.events.next_seq() - seq_before
		batches += 1
		if batches > 12 and run.is_running():
			measured += 1
	out["live_gross_per_5min"] = live_total * 5 / maxi(1, LIVE_SESSION_TICKS * measured)
	out["away_delta_per_window"] = away_total / maxi(1, measured)
	out["events_per_cycle"] = events_total / maxi(1, measured)
	return out


# --- Reporting -----------------------------------------------------------------


func _print_digest(opening: Dictionary, wins: int, mean_hours: int, slowest: int, warns: int, telegraphs: int, greed: Dictionary, value: Dictionary, wall: float) -> void:
	print(
		"[economy_balance_band] opening: recruit %d min, worker %d min, food %d min, %d arrivals/2h | first win (6h cadence, commit %d): %d/%d regimes, mean %dh, slowest %dh, tension %d warns / %d telegraphs | greed crushed at ~%dh after %d warns | check-in: +%d per 5-min live window, %d events + ~+%d away per cycle; wall %.2fs"
		% [
			opening["recruit"], opening["worker"], opening["food"], opening["arrivals_2h"],
			COMMIT_PERMILLE, wins, SEEDS.size(), mean_hours, slowest, warns, telegraphs,
			int(greed["crush_tick"]) / 60, greed["warns"],
			value["live_gross_per_5min"], value["events_per_cycle"], value["away_delta_per_window"],
			wall,
		]
	)
