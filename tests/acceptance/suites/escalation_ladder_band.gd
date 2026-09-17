## Acceptance suite (L2-B) — the escalation ladder band, pinned in CI.
##
## The tuned curve (docs/balance.md §7 — the chained-campaign sweep) must
## keep the loop the user designed, machine-checked on the CANONICAL host
## composition with the ESCALATION WIRED (the shipped game's wiring; a bare
## meta runs the static branch, so the campaign's own run 1 doubles as the
## no-snapshot zero-impact probe):
##
##   CYCLE 0      the first win against the STATIC wall (the shared meta
##                starts bare) — the ladder's reference run; its victory
##                captures the first garrison.
##   CYCLE 1      the first escalation ("your own veterans hold the wall"):
##                a ZERO-TREE rebuild wins it in a band similar to the
##                first win — the arc is a full campaign again (R5), never
##                a wall the player cannot face.
##   CYCLE 2      still climbable barefoot — the tree is a handrail, not a
##                key, until the curve compounds.
##   CYCLES 1-5   at FULL TREE every cycle wins and the time-to-win grows
##                gently (<= ~1.5x the previous cycle, no stalls) while
##                the wall itself RISES — the ladder is real.
##
## The player model matches scripts/balance_sweep.gd's escalation section
## exactly (chained campaigns on one shared meta — the host's
## one-meta-across-engines rule; fixed seeds, zero test-side RNG).
extends RefCounted

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

## Six fixed campaign seeds — the first half of the sweep's 12-seed ladder
## table's seed block (BASE_SEED + s*13), where full tree climbs 12/12
## through cycle 5; these six reproduce it (the growth pin reads their
## pooled means, which track the recorded 12-seed table).
const SEEDS: Array[int] = [20261201, 20261214, 20261227, 20261240, 20261253, 20261266]

const CADENCE_HOURS := 6
const LIVE_SESSION_TICKS := 3
const COMMIT_PERMILLE := 450
const CYCLE_CAP_HOURS := 360  # the sweep's honest per-cycle ceiling
const BUDGET_SECONDS := 18.0

## The modeled partial tree: the three tier-1 economy nodes (one win's
## bank) — the ladder's cycle-1 reading (the sweep's "partial tree" row).
const PARTIAL_TREE_NODES: Array[StringName] = [
	&"grandmas_recipes", &"unpaid_artisans", &"the_sergeants_primer",
]


func suite_name() -> String:
	return "escalation_ladder_band"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var tunables := MVP.load_mvp().tunables

	# --- Full tree: the climbability gate (cycles 0-5, all seeds — the
	# tree owned from run 1, exactly the sweep's full-tree probe).
	var full_campaigns: Array = []
	for seed in SEEDS:
		full_campaigns.append(_measure_campaign(tunables, seed, 5,
			func(_cycle: int, meta: RunMeta, purchased: Dictionary) -> LegacySystem:
				if not bool(purchased.get("done", false)):
					purchased["done"] = true
					return _full_tree_provider(meta)
				return LegacySystem.new(MVP.load_mvp().unlock_tree, meta)))
	var cycle0_hours: Array[int] = []
	for stories in full_campaigns:
		harness.check(bool(stories[0]["won"]), "full-tree campaign seed %d: run 1 (the static wall) wins within %dh (took %dh)" % [stories[0]["seed"], CYCLE_CAP_HOURS, stories[0]["win_tick"] / 60])
		cycle0_hours.append(int(stories[0]["win_tick"]) / 60)
	var cycle0_mean := (cycle0_hours[0] + cycle0_hours[1]) / 2
	harness.check(cycle0_mean >= 48 and cycle0_mean <= 130,
		"the ladder's reference run sits in the first-win band (mean %dh over %d campaigns — the static baseline is untouched by escalation wiring, the zero-impact rule)" % [cycle0_mean, SEEDS.size()])

	var all_climb := true
	var prev_mean := -1
	var walls_first := 0
	var walls_last := 0
	for cycle in range(1, 6):
		var won := 0
		var hours_total := 0
		var walls := 0
		for stories in full_campaigns:
			if cycle >= stories.size() or not bool(stories[cycle]["won"]):
				continue
			won += 1
			hours_total += int(stories[cycle]["win_tick"]) / 60
			walls += int(stories[cycle]["wall_strength"])
			harness.check(int(stories[cycle]["win_tick"]) / 60 <= 300,
				"full tree cycle %d wins inside the growth band (seed %s: %dh)" % [cycle, stories[0]["seed"], int(stories[cycle]["win_tick"]) / 60])
		harness.check(won == SEEDS.size(), "full tree climbs cycle %d: %d/%d campaigns won" % [cycle, won, SEEDS.size()])
		if won == SEEDS.size():
			var mean := hours_total / SEEDS.size()
			if prev_mean > 0:
				harness.check(mean <= prev_mean * 1.5,
					"cycle %d grows gently over cycle %d's band (%dh <= 1.5 x %dh — never a stall)" % [cycle, cycle - 1, mean, prev_mean])
			prev_mean = mean
			if cycle == 1:
				walls_first = walls / SEEDS.size()
			if cycle == 5:
				walls_last = walls / SEEDS.size()
		else:
			all_climb = false
	harness.check(all_climb and walls_last > walls_first,
		"the ladder is real: the wall RISES across the climb (cycle 1 mean %d -> cycle 5 mean %d power)" % [walls_first, walls_last])

	# --- Zero tree: cycle 1 is a full new campaign, climbable barefoot;
	# cycle 2 still stands without a single purchase (two seeds — the
	# sweep's 12-seed table carries the full reading).
	for seed in [SEEDS[0], SEEDS[1]]:
		var stories := _measure_campaign(tunables, seed, 2,
			func(_cycle: int, _meta: RunMeta, _p: Dictionary) -> LegacySystem: return null)
		harness.check(bool(stories[0]["won"]) and int(stories[0]["wall_cycle"]) == 0,
			"zero-tree seed %d: run 1 faces the STATIC wall (wall cycle %d — no snapshot, no escalation keys)" % [seed, int(stories[0]["wall_cycle"])])
		harness.check(bool(stories[1]["won"]) and int(stories[1]["win_tick"]) / 60 <= 300 and int(stories[1]["wall_cycle"]) == 1,
			"zero-tree seed %d: cycle 1 (your own veterans) is beatable in the similar band — %dh, wall cycle %d, strength %d" % [seed, int(stories[1]["win_tick"]) / 60, int(stories[1]["wall_cycle"]), int(stories[1]["wall_strength"])])
		if stories.size() > 2:
			harness.check(bool(stories[2]["won"]),
				"zero-tree seed %d: cycle 2 still climbable without a single purchase (%dh — the tree is a handrail, not a key, until the curve compounds)" % [seed, int(stories[2]["win_tick"]) / 60])

	# --- Partial tree (the modeled early campaign: run 1's bank buys the
	# three tier-1 economy nodes, no veterans yet): cycles 1-2 stay in band.
	var partial := _measure_campaign(tunables, SEEDS[0], 2,
		func(cycle: int, meta: RunMeta, purchased: Dictionary) -> LegacySystem:
			if cycle == 0:
				return null  # run 1 barefoot; its bank buys the nodes after
			var legacy := LegacySystem.new(MVP.load_mvp().unlock_tree, meta)
			if not bool(purchased.get("done", false)):
				purchased["done"] = true
				for id in PARTIAL_TREE_NODES:
					if legacy.purchase_result(id) == LegacySystem.PURCHASE_OK:
						legacy.purchase(id)
			return legacy)
	var partial_hours := [-1, -1]
	if partial.size() == 3 and bool(partial[1]["won"]) and bool(partial[2]["won"]):
		partial_hours = [int(partial[1]["win_tick"]) / 60, int(partial[2]["win_tick"]) / 60]
	harness.check(partial_hours[0] > 0 and partial_hours[1] > 0,
		"partial tree (the 3 tier-1 economy nodes, no veterans): cycles 1-2 both won (%dh / %dh) — the first escalation asks for a rebuild, not a meta wall" % [partial_hours[0], partial_hours[1]])

	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	print("[escalation_ladder_band] reference run mean %dh; full tree climbs cycles 1-5 (walls %d -> %d); zero tree takes cycle 1-2 barefoot; wall %.2fs" % [cycle0_mean, walls_first, walls_last, wall])
	harness.check(wall < BUDGET_SECONDS, "escalation ladder suite in < %.0fs (took %.2fs)" % [BUDGET_SECONDS, wall])


# --- The player model (mirrors scripts/balance_sweep.gd exactly) ----------------


## A LegacySystem around the campaign's shared meta with the whole tree
## bought (the climbability probe's wallet — the L1-B 1M-bank pattern).
func _full_tree_provider(meta: RunMeta) -> LegacySystem:
	var legacy := LegacySystem.new(MVP.load_mvp().unlock_tree, meta)
	var bank := meta.legacy_points
	meta.legacy_points += 1_000_000
	for id in legacy.node_ids():
		if not legacy.purchase(id):
			push_error("[escalation_ladder_band] full-tree purchase of '%s' refused" % id)
	meta.legacy_points = bank
	return legacy


## One chained campaign: cycle 0 = the static first win (the shared meta
## starts bare); every later run faces the captured garrison of the run
## before it. Stops at the first unwon cycle.
func _measure_campaign(
		tunables: EconomyTunables, seed: int, cycles: int, p_provider: Callable
) -> Array[Dictionary]:
	var meta := RunMeta.new()
	var purchased := {}
	var stories: Array[Dictionary] = []
	for cycle in range(cycles + 1):
		var legacy: LegacySystem = p_provider.call(cycle, meta, purchased)
		var story := _measure_first_win(tunables, seed + cycle * 101, legacy, meta)
		story["cycle"] = cycle
		story["seed"] = seed
		stories.append(story)
		if not story["won"]:
			break
	return stories


## The casual loop (the balance band suite's model, parameterized for the
## chained campaign): manage once per check-in, away windows through the
## REAL catch-up service, commit at the sensible line, fold after a crush.
func _measure_first_win(
		tunables: EconomyTunables, seed: int, legacy: LegacySystem, meta: RunMeta
) -> Dictionary:
	var session: Variant = HOST.session(seed, {}, tunables, legacy, true, meta)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	var wall: Dictionary = resolver.assault_odds(engine)["garrison"]
	var story := {
		"won": false, "win_tick": -1, "losses": 0,
		"wall_strength": int(wall["strength_milli"]) / SimFixed.MILLI,
		"wall_cycle": int(wall.get("escalation_cycle", 0)),
	}
	var epoch := 1_750_000_000
	while engine.tick_count < CYCLE_CAP_HOURS * 60:
		var laying_low := suspicion.suspicion_points() >= 70
		var military := 12 if resolver.floor_met(engine) else 3
		HOST.manage(engine, military, {&"laying_low": laying_low, &"population_cap": _estate_cap(production)})
		engine.fast_forward(LIVE_SESSION_TICKS)
		if not run.is_running():
			story["crushed"] = true
		elif resolver.floor_met(engine) and int(resolver.assault_odds(engine)["win_permille"]) >= COMMIT_PERMILLE:
			engine.submit_command(&"commit_assault", &"", 0)
			engine.fast_forward(1)
			if run.run_outcome() == RunLifecycleSystem.OUTCOME_VICTORY:
				story["won"] = true
				story["win_tick"] = engine.tick_count
				break
			story["losses"] += 1
		epoch += LIVE_SESSION_TICKS * 60
		session.mark_seen(epoch)
		epoch += CADENCE_HOURS * 3600
		session.foreground(epoch)
		if not run.is_running() and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT:
			engine.submit_command(&"run_restart", &"", 0)
			engine.submit_command(&"grant_resources", &"", 0)
			engine.fast_forward(1)
	return story


## The casual player's population line: the conspiracy grows with the camp.
func _estate_cap(production: ProductionSystem) -> int:
	var levels := 0
	for id in MVP.producer_ids():
		levels += production.building_level(id)
	return 10 + levels
