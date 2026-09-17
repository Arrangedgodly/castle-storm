## T-SIM-08 balance sweep — the tuning harness (NOT a test; a measurement
## tool whose recorded output lives in docs/balance.md).
##
##     make balance-sweep                     # full sweep (~1 min)
##     CS_SWEEP_SEEDS=24 make balance-sweep   # more seeds for the band rows
##
## Sweeps EconomyTunables candidates against the CANONICAL host composition
## (tests/acceptance/suites/_full_stack.gd — the reference host) and prints
## measurable outcomes per configuration:
##
##   OPENING    time to first recruit / first accepted worker / first food
##              trickle (sim-minutes == real minutes at 1 tick = 1 sim-min —
##              the journey-1 numbers town-hall pinned: first recruit <= 15
##              min of the first session). The modeled player watches the
##              gate for the first two hours (manage every 5 min, all
##              workers — journey 1 is the worker lesson).
##   FIRST WIN  time to first victory under a CASUAL check-in cadence (the
##              sensible player: manage() once per check-in, commit when the
##              displayed odds cross a sensible 450 permille; away windows
##              resolved through the REAL CatchUpService, 8h cap honored) —
##              the 2-4 day band at 3-5 min check-ins (4/day at 6h cadence
##              accrues ~24 sim-h per wall day; 2/day at 12h accrues ~16).
##   PRESSURE   1000h stability stream under the sensible-play policy
##              (military 4, population 24, lay low >= 70, fold after a
##              crush): crush/strike/cancel counts — the T-QA-02 finding's
##              before/after decomposition (crushes must come from GREED,
##              not from existing).
##   GREED      the failure-mode probe: an all-in conspiracy (military 24,
##              population 40, never lays low) MUST be crushable — the
##              failure exists by design, on the greedy side of the line.
##   CHECK-IN   gross resources per 5-minute live window mid-run (what a
##              check-in SEES happen) + what one full check-in cycle
##              resolves (events + away accrual + spends it decides).
##
## The chosen values are the pack's tunables defaults; the CI band suite
## (tests/acceptance/suites/economy_balance_band.gd) pins them. This script
## exists so the NEXT balance pass can re-sweep honestly.
extends SceneTree

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const BASE_SEED := 20261201
const FIRST_WIN_CAP_HOURS := 240
const LIVE_SESSION_TICKS := 3  # a 3-5 min check-in, minute-grained
const COMMIT_PERMILLE := 450  # the sensible player's line: near-even odds

## Candidate configurations: name -> {overrides, policy}. Policy keys map to
## manage() opts (the player model); "before" reproduces the pre-T-SIM-08
## player (no dismissal affordance in the policy) on the pre-T-SIM-08
## content values — the decomposition rows then add ONE intervention each.
const CONFIGS: Array[Dictionary] = [
	{"name": "before (R4 seeds, no dismiss)", "o": {
		"recruit_arrival_early_count": 0, "recruit_gate_capacity": 0,
		"suspicion_presence_army_per_hour": 0.5, "suspicion_presence_follower_per_hour": 0.1,
		"assault_garrison_base_power": 60,
	}, "p": {&"no_dismiss": true}},
	{"name": "+ dismissal affordance", "o": {
		"recruit_arrival_early_count": 0, "recruit_gate_capacity": 0,
		"suspicion_presence_army_per_hour": 0.5, "suspicion_presence_follower_per_hour": 0.1,
		"assault_garrison_base_power": 60,
	}},
	{"name": "+ presence weights 0.3/0.05", "o": {
		"recruit_arrival_early_count": 0, "recruit_gate_capacity": 0,
		"assault_garrison_base_power": 60,
	}},
	{"name": "+ gate capacity 6 (chosen)", "o": {
		"assault_garrison_base_power": 60,
	}},
	{"name": "chosen (all: rush + weights + gate + garrison 50)", "o": {}},
	{"name": "rush-uniform-8", "o": {
		"recruit_arrival_early_count": 8, "recruit_arrival_early_interval_hours": 0.1,
		"recruit_arrival_early_step": 1.0, "assault_garrison_base_power": 50,
	}},
	{"name": "rush-ramp-8-fast", "o": {
		"recruit_arrival_early_count": 8, "recruit_arrival_early_interval_hours": 0.08,
		"recruit_arrival_early_step": 1.7, "assault_garrison_base_power": 50,
	}},
	{"name": "gate-4", "o": {"recruit_gate_capacity": 4}},
	{"name": "gate-8", "o": {"recruit_gate_capacity": 8}},
	{"name": "weights-old (0.5/0.1)", "o": {
		"suspicion_presence_army_per_hour": 0.5, "suspicion_presence_follower_per_hour": 0.1,
	}},
	{"name": "weights-025-004", "o": {
		"suspicion_presence_army_per_hour": 0.25, "suspicion_presence_follower_per_hour": 0.04,
	}},
	{"name": "garrison-55", "o": {"assault_garrison_base_power": 55}},
	{"name": "garrison-60", "o": {"assault_garrison_base_power": 60}},
]


func _initialize() -> void:
	var seed_count := 12 if OS.get_environment("CS_SWEEP_SEEDS") == "" else OS.get_environment("CS_SWEEP_SEEDS").to_int()
	var clock := Time.get_ticks_msec()
	print("[balance-sweep] canonical host, MVP pack; %d seeds from %d; commit line %d permille" % [seed_count, BASE_SEED, COMMIT_PERMILLE])
	print()
	_sweep_opening(seed_count)
	_sweep_pressure()
	_sweep_first_win(seed_count)
	_sweep_legacy_tree(seed_count)
	_sweep_final_detail()
	print()
	print("[balance-sweep] done in %.1fs — record into docs/balance.md" % [float(Time.get_ticks_msec() - clock) / 1000.0])
	quit(0)


func _tunables(overrides: Dictionary) -> EconomyTunables:
	var t := MVP.load_mvp().tunables.duplicate() as EconomyTunables
	for key in overrides:
		t.set(key, overrides[key])
	return t


## The casual player's population line: the conspiracy grows with the camp
## (10 bodies + one per producer level). Keeps the estate staffable while
## leaving room for the army to keep growing — see measure_first_win.
func _estate_cap(production: ProductionSystem) -> int:
	var levels := 0
	for id in MVP.producer_ids():
		levels += production.building_level(id)
	return 10 + levels


func _policy(config: Dictionary) -> Dictionary:
	return (config.get("p", {}) as Dictionary).duplicate()


# --- Opening (journey 1): first recruit / worker / trickle --------------------


## The journey-1 player: attentive for the first four hours (a manage batch
## every 5 sim-min, everyone into the workforce — the worker lesson), so the
## first acceptance, worker promotion and food trickle are PLAYER-paced, not
## gate-starved. Sim-minutes from run start. The food trickle is the first
## minute whose food stock RISES over the previous minute (gross — upgrade
## spends can hold the net stock below the stipend baseline for hours).
func measure_opening(tunables: EconomyTunables, seed: int, policy: Dictionary) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables)
	var engine: SimEngine = session.engine
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var out := {"recruit": -1, "worker": -1, "food": -1, "arrivals_2h": 0}
	var food_prev := -1
	var seq := 0
	for i in range(240):
		if i % 5 == 0:
			HOST.manage(engine, 0, policy)
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


# --- First win at a casual cadence ---------------------------------------------


## One casual player: check-ins every `cadence_hours`, a 3-minute live
## session each (manage + a few live ticks), away windows through the REAL
## catch-up service (8h cap honored). Phase 1 builds measured (military 3);
## once the floor is met the conspiracy goes all-in (military 12) and the
## player commits when displayed odds cross `commit_permille`; after a loss
## the run KEEPS RUNNING (set-back) and re-commits at the same line. The
## population cap GROWS WITH THE ESTATE (10 + producer levels): a real
## player's conspiracy scales with the camp that feeds it — a fixed cap
## would freeze the army the moment the workers fill it (workers cannot
## rebranch; army growth needs fresh recruits). `legacy` (L1 probe) wires
## the unlock-tree provider into the session exactly the way GameHost does.
func measure_first_win(tunables: EconomyTunables, seed: int, cadence_hours: int, commit_permille: int, legacy: LegacySystem = null) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables, legacy)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	var story := {
		"won": false, "win_tick": -1, "losses": 0, "first_loss_tick": -1,
		"suspicion_max": 0, "warns": 0, "telegraphs": 0, "cancels": 0,
		"crushed": false, "batches": 0, "regime": run.regime_id(),
		"odds_cross_tick": -1, "power_at_win": 0,
	}
	var epoch := 1_750_000_000
	var seq := 0
	var batches := 0
	while engine.tick_count < FIRST_WIN_CAP_HOURS * 60:
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
					&"crackdown_cancelled":
						story["cancels"] += 1
			seq += 1
		if not run.is_running():
			story["crushed"] = true
		elif resolver.floor_met(engine) and int(resolver.assault_odds(engine)["win_permille"]) >= commit_permille:
			if story["odds_cross_tick"] < 0:
				story["odds_cross_tick"] = engine.tick_count
			story["power_at_win"] = units.army_power()
			engine.submit_command(&"commit_assault", &"", 0)
			engine.fast_forward(1)
			if run.run_outcome() == RunLifecycleSystem.OUTCOME_VICTORY:
				story["won"] = true
				story["win_tick"] = engine.tick_count
				break
			story["losses"] += 1
			if story["first_loss_tick"] < 0:
				story["first_loss_tick"] = engine.tick_count
		# Away window through the real service (timestamps injected).
		epoch += LIVE_SESSION_TICKS * 60
		session.mark_seen(epoch)
		epoch += cadence_hours * 3600
		session.foreground(epoch)
		story["suspicion_max"] = maxi(story["suspicion_max"], suspicion.suspicion_points())
		batches += 1
		story["batches"] = batches
		if not run.is_running() and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT:
			engine.submit_command(&"run_restart", &"", 0)
			engine.submit_command(&"grant_resources", &"", 0)
			engine.fast_forward(1)
	return story


# --- Pressure: the 1000h sensible-play stability stream ------------------------


func measure_stability(tunables: EconomyTunables, seed: int, policy: Dictionary, legacy: LegacySystem = null) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables, legacy)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var opts: Dictionary = {&"laying_low": false, &"population_cap": 24}
	opts.merge(policy, true)
	var tally := {"crushes": 0, "strikes": 0, "cancels": 0, "warns": 0, "restarts": 0, "telegraphs": 0}
	var crushed_last := false
	var seq := 0
	var suspicion_peak := 0
	for w in range(500):
		opts[&"laying_low"] = suspicion.suspicion_points() >= 70
		HOST.manage(engine, 4, opts)
		if crushed_last:
			engine.submit_command(&"run_restart", &"", 0)
			engine.submit_command(&"grant_resources", &"", 0)
		engine.fast_forward(120)
		while seq < engine.events.next_seq():
			var event := engine.events.get_event(seq)
			if event != null:
				match event.type:
					&"suspicion_warn":
						tally["warns"] += 1
					&"suspicion_telegraph":
						tally["telegraphs"] += 1
					&"crackdown_cancelled":
						tally["cancels"] += 1
					&"crackdown_struck":
						tally["strikes"] += 1
					&"run_crushed":
						tally["crushes"] += 1
					&"run_restarted":
						tally["restarts"] += 1
			seq += 1
		suspicion_peak = maxi(suspicion_peak, suspicion.suspicion_points())
		crushed_last = not run.is_running() and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT
	tally["suspicion_peak"] = suspicion_peak
	tally["alive_at_end"] = run.is_running()
	return tally


# --- Greed: the failure-mode probe ----------------------------------------------


## The greedy player: accepts everyone (population 40), builds the biggest
## army the policy allows (military 24), and NEVER lays low — no dismissal,
## no standing down. The crush MUST be reachable on this side of the line.
func measure_greed(tunables: EconomyTunables, seed: int, hours: int) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var tally := {"crushes": 0, "strikes": 0, "warns": 0, "crush_tick": -1, "suspicion_peak": 0}
	var seq := 0
	var windows := hours / 2
	for w in range(windows):
		HOST.manage(engine, 24, {&"population_cap": 40})
		engine.fast_forward(120)
		while seq < engine.events.next_seq():
			var event := engine.events.get_event(seq)
			if event != null:
				match event.type:
					&"suspicion_warn":
						tally["warns"] += 1
					&"crackdown_struck":
						tally["strikes"] += 1
					&"run_crushed":
						tally["crushes"] += 1
						tally["crush_tick"] = event.tick
			seq += 1
		tally["suspicion_peak"] = maxi(tally["suspicion_peak"], suspicion.suspicion_points())
		if tally["crushes"] > 0:
			break  # the failure mode is proven; no need to farm restarts
	return tally


# --- Check-in value (mid-run) ---------------------------------------------------


## What one 5-minute LIVE window sees mid-run (gross production — spends are
## added back, the stability suite's accounting), and what one full check-in
## cycle (live session + away window) resolves.
func measure_checkin_value(tunables: EconomyTunables, seed: int, cadence_hours: int) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	var epoch := 1_750_000_000
	var warmup := 12
	var totals := {"live_gross": 0, "away_delta": 0, "events": 0, "spends": {}}
	var measured := 0
	var batches := 0
	while batches * cadence_hours < FIRST_WIN_CAP_HOURS and measured < 2:
		var laying_low := suspicion.suspicion_points() >= 70
		var military := 12 if resolver.floor_met(engine) else 3
		var ledger: Dictionary = HOST.manage(engine, military, {&"laying_low": laying_low, &"population_cap": _estate_cap(production)})
		var seq_before := engine.events.next_seq()
		var stocks_before := {}
		for id in engine.resources.keys():
			stocks_before[id] = int(engine.resources[id])
		engine.fast_forward(LIVE_SESSION_TICKS)
		var live_gross := 0
		for id in stocks_before:
			# Gross: the spends the session decided (ledger) are production
			# the window paid for, not production that did not happen.
			live_gross += int(engine.resources[id]) - int(stocks_before[id]) + int(ledger.get(id, 0))
		epoch += LIVE_SESSION_TICKS * 60
		session.mark_seen(epoch)
		var stocks_mid := {}
		for id in engine.resources.keys():
			stocks_mid[id] = int(engine.resources[id])
		epoch += cadence_hours * 3600
		session.foreground(epoch)
		var away_delta := 0
		for id in stocks_mid:
			away_delta += int(engine.resources[id]) - int(stocks_mid[id])
		batches += 1
		if batches > warmup and run.is_running():
			totals["live_gross"] += live_gross
			totals["away_delta"] += away_delta
			totals["events"] += engine.events.next_seq() - seq_before
			for id in ledger:
				totals["spends"][id] = int(totals["spends"].get(id, 0)) + int(ledger[id])
			measured += 1
	totals["live_gross_per_5min"] = totals["live_gross"] * 5 / maxi(1, LIVE_SESSION_TICKS * measured)
	totals["away_delta_per_window"] = totals["away_delta"] / maxi(1, measured)
	totals["events_per_cycle"] = totals["events"] / maxi(1, measured)
	return totals


# --- The sweep drivers -----------------------------------------------------------


func _sweep_opening(seed_count: int) -> void:
	print("== opening (sim-minutes from run start, mean of measured seeds; journey-1 target: first recruit <= 15 min) ==")
	print("| config | first recruit | first worker | first food trickle | arrivals in 2h |")
	print("|---|---|---|---|---|")
	for config in CONFIGS:
		var tunables := _tunables(config["o"])
		var policy := _policy(config)
		var recruit := 0
		var recruit_n := 0
		var worker := 0
		var worker_n := 0
		var food := 0
		var food_n := 0
		var arrivals := 0
		var n := mini(seed_count, 6)
		for s in range(n):
			var opening := measure_opening(tunables, BASE_SEED + s, policy)
			if opening["recruit"] > 0:
				recruit += opening["recruit"]
				recruit_n += 1
			if opening["worker"] > 0:
				worker += opening["worker"]
				worker_n += 1
			if opening["food"] > 0:
				food += opening["food"]
				food_n += 1
			arrivals += opening["arrivals_2h"]
		print("| %s | %s | %s | %s | %d |" % [
			config["name"],
			"%d (%d/%d)" % [recruit / maxi(1, recruit_n), recruit_n, n] if recruit_n > 0 else ">240",
			"%d (%d/%d)" % [worker / maxi(1, worker_n), worker_n, n] if worker_n > 0 else ">240",
			"%d (%d/%d)" % [food / maxi(1, food_n), food_n, n] if food_n > 0 else ">240",
			arrivals / n,
		])
	print()


func _sweep_pressure() -> void:
	print("== pressure: 1000h sensible-play stream (seed 20261001, the T-QA-02 seed; recorded pre-T-SIM-08: 7 crushes) ==")
	print("| config | crushes | strikes | telegraph cancels | warns | suspicion peak | alive at end |")
	print("|---|---|---|---|---|---|---|")
	for config in CONFIGS:
		var tunables := _tunables(config["o"])
		var tally := measure_stability(tunables, 20261001, _policy(config))
		print("| %s | %d | %d | %d | %d | %d | %s |" % [
			config["name"], tally["crushes"], tally["strikes"], tally["cancels"],
			tally["warns"], tally["suspicion_peak"], tally["alive_at_end"],
		])
	print()
	print("== greed: the failure-mode probe (military 24, population 40, never lay low, <= 400h) ==")
	print("| config | crushed | at hour | strikes first | warns |")
	print("|---|---|---|---|---|")
	for config in CONFIGS:
		if config["name"].begins_with("rush-") or config["name"].begins_with("gate-"):
			continue  # orthogonal to greed; keep the table tight
		var tunables := _tunables(config["o"])
		var tally := measure_greed(tunables, 20261201, 400)
		print("| %s | %s | %.0f | %d | %d |" % [
			config["name"], "YES" if tally["crushes"] > 0 else "no",
			tally["crush_tick"] / 60.0, tally["strikes"], tally["warns"],
		])
	print()


func _sweep_first_win(seed_count: int) -> void:
	for cadence in [6, 8, 12]:
		var tunables := _tunables({})  # the chosen defaults
		var wins := 0
		var hours_total := 0
		var losses_total := 0
		var recovery_hours := 0
		var recovery_runs := 0
		var crushed := 0
		var slowest := 0
		var cross_total := 0
		var regimes := {}
		var warns := 0
		var telegraphs := 0
		var cancels := 0
		for s in range(seed_count):
			var story := measure_first_win(tunables, BASE_SEED + s, cadence, COMMIT_PERMILLE)
			regimes[String(story["regime"])] = true
			warns += story["warns"]
			telegraphs += story["telegraphs"]
			cancels += story["cancels"]
			if story["crushed"]:
				crushed += 1
			if story["won"]:
				wins += 1
				var hours := int(story["win_tick"]) / 60
				hours_total += hours
				slowest = maxi(slowest, hours)
				cross_total += int(story["odds_cross_tick"]) / 60
				if story["losses"] > 0:
					recovery_hours += (int(story["win_tick"]) - int(story["first_loss_tick"])) / 60
					recovery_runs += 1
			losses_total += story["losses"]
		print("[first-win] cadence %2dh (sim-h/wall-day ~%d): %2d/%d won, odds-line cross mean %dh, win mean %dh, slowest %dh; losses %d, recovery-after-loss mean %dh over %d runs; tension %d warns / %d telegraphs / %d cancels; %d crushed; regimes %s" % [
			cadence, 24 if cadence <= 8 else 16, wins, seed_count,
			cross_total / maxi(1, wins), hours_total / maxi(1, wins), slowest,
			losses_total, recovery_hours / maxi(1, recovery_runs), recovery_runs,
			warns, telegraphs, cancels, crushed, str(regimes.keys()),
		])
	print()
	print("== garrison axis (cadence 6h, commit %d permille) ==" % COMMIT_PERMILLE)
	for garrison in [50, 55, 60]:
		var tunables := _tunables({"assault_garrison_base_power": garrison})
		var wins := 0
		var hours_total := 0
		var slowest := 0
		var losses_total := 0
		for s in range(12):
			var story := measure_first_win(tunables, BASE_SEED + s, 6, COMMIT_PERMILLE)
			if story["won"]:
				wins += 1
				hours_total += int(story["win_tick"]) / 60
				slowest = maxi(slowest, int(story["win_tick"]) / 60)
			losses_total += story["losses"]
		print("[garrison %d] %2d/12 won, win mean %dh, slowest %dh, losses %d (floor odds ~%.1f%% neutral)" % [
			garrison, wins, hours_total / maxi(1, wins), slowest, losses_total,
			23000.0 / (23000.0 + float(garrison) * 1000.0) * 100.0,
		])
	print()


# --- L1: the legacy-tree probe (docs/balance.md's L1 section) --------------------


## A LegacySystem owning EVERY node of the shipped tree (tree order is a
## valid purchase order — the shipped .tres lists every node after its
## prerequisites), with a bank big enough to buy it all.
func _legacy_full_tree() -> LegacySystem:
	var tree := MVP.load_mvp().unlock_tree
	if tree == null:
		return null
	var meta := RunMeta.new()
	meta.legacy_points = 1_000_000
	var legacy := LegacySystem.new(tree, meta)
	for id in legacy.node_ids():
		if not legacy.purchase(id):
			push_error("[balance-sweep] full-tree purchase of '%s' refused — tree order is not a purchase order" % id)
			return null
	return legacy


func _sweep_legacy_tree(seed_count: int) -> void:
	var tree := MVP.load_mvp().unlock_tree
	if tree == null:
		print("[legacy] the pack ships no unlock tree — probe skipped")
		return
	var total := 0
	for node in tree.nodes:
		total += node.cost
	var mods := _legacy_full_tree().modifiers()
	print("== L1 full-tree probe (the shipped tree: %d nodes, %d lp total; earn rates ~150-260 lp/run) ==" % [
		tree.nodes.size(), total])
	print("[legacy] resolved full-tree bundle: arrivals x%.3f · building x%.3f · training x%.3f · gear x%.3f · stipend x%.3f" % [
		mods.recruit_arrival_interval_milli / 1000.0, mods.building_cost_milli / 1000.0,
		mods.training_time_milli / 1000.0, mods.gear_cost_milli / 1000.0,
		mods.stipend_milli / 1000.0])
	print("| config | won | win mean | slowest | losses | crushed |")
	print("|---|---|---|---|---|---|")
	for config in [
		{"name": "baseline (zero purchases)", "legacy": null},
		{"name": "full tree (all nodes)", "legacy": _legacy_full_tree()},
	]:
		var wins := 0
		var hours_total := 0
		var slowest := 0
		var losses_total := 0
		var crushed := 0
		for s in range(seed_count):
			var story := measure_first_win(_tunables({}), BASE_SEED + s, 6, COMMIT_PERMILLE, config["legacy"])
			if story["crushed"]:
				crushed += 1
			if story["won"]:
				wins += 1
				var hours := int(story["win_tick"]) / 60
				hours_total += hours
				slowest = maxi(slowest, hours)
			losses_total += story["losses"]
		print("| %s | %d/%d | %dh | %dh | %d | %d |" % [
			config["name"], wins, seed_count, hours_total / maxi(1, wins), slowest, losses_total, crushed])
	print()
	# The suspicion-pressure question at full tree: the 1000h sensible-play
	# stream (the T-QA-02 seed) must stay quiet — meta progression must not
	# break the pressure model's "existing is not a death sentence" line.
	var pressure := measure_stability(_tunables({}), 20261001, {}, _legacy_full_tree())
	print("[legacy pressure] 1000h sensible-play at full tree: crushes %d, strikes %d, telegraphs %d, cancels %d, warns %d, suspicion peak %d, alive %s" % [
		pressure["crushes"], pressure["strikes"], pressure["telegraphs"], pressure["cancels"],
		pressure["warns"], pressure["suspicion_peak"], pressure["alive_at_end"]])
	print()


func _sweep_final_detail() -> void:
	var tunables := _tunables({})
	var value := measure_checkin_value(tunables, BASE_SEED, 6)
	print("[check-in value] mid-run, cadence 6h: a 5-min live window SEES ~+%d gross resources; one full check-in cycle resolves %d events, banks +%d resources of away accrual, and decides spends %s" % [
		value["live_gross_per_5min"], value["events_per_cycle"],
		value["away_delta_per_window"], str(value["spends"]),
	])
