## Acceptance suite (T-QA-02) — 1000h economy stability under sensible play.
##
## The town-hall criterion, machine-encoded: "1,000 simulated hours of
## fast-forwarded economy show no runaway explosion or progress collapse."
## The economy is THE canonical composition (`_full_stack.gd` — the reference
## host T-UI-03 consumes), driven by the scripted sensible-play policy
## (`_full_stack.manage`) in 2h management windows for 500 windows:
##
##   EXPLOSION   — every sampled stock is within the CONTENT bound: for each
##                 resource, starting grant + sum over producing buildings
##                 of (max per-worker rate x max level x milestone x worst
##                 production quirk x max worker slots) x 1000h. Any
##                 compounding-cost exploit, negative-cost loop or sign bug
##                 blows straight through it.
##   COLLAPSE    — production never stalls while staffed: each window, the
##                 measured production (stock delta + spent ledger + seized
##                 - granted, all accounted exactly) must be >= the exact
##                 SimFixed floor (per-worker rate x assigned x window). The
##                 only pool spends in the game are upgrade costs and gear
##                 recipes — both ledgered at submit time; seizures and
##                 grants are read off the event stream; a struck telegraph
##                 cannot stall a staffed producer.
##   HEALTH      — no negative/non-int stocks, suspicion always within
##                 [0, max], every run builds its estate, the bank grows.
##   SUSPICION   — asserted HONESTLY, whichever way the content rules take
##                 it. This pack's measured reality (recorded in the digest
##                 for T-SIM-08): arrivals never stop, pending gate offers
##                 are presence, and decay is capped — so a growing estate
##                 eventually loses a telegraph race and is CRUSHED AT
##                 EXACTLY 100. Sensible play folds a new run and continues.
##                 The suite asserts BOTH regimes per their rules: every
##                 strike lands at its telegraph's exact land tick (>=4h
##                 warning), every armed telegraph strikes / cancels / is
##                 orphaned by a crush, every crush fires at max with a
##                 same-tick run_lost and full banking, every restart resets
##                 the whole run-scoped estate, and the stream still ends
##                 with a LIVE run.
##   DETERMINISM — the whole script is a pure function of the seed: an
##                 in-process replay is bit-identical (hash + all counters),
##                 and the digest prints the hash so the double-ci.sh
##                 validation proves cross-process reproducibility.
##   ROUND-TRIP  — mid-stream at 500h the engine dict is captured; a twin
##                 restored from it replays the second half in lockstep
##                 (bit-identical hash), and the meta domain survives its
##                 own dict round-trip.
extends RefCounted

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const RUN_SEED := 20261001
const WINDOW_TICKS := 120  # one management batch per 2h sim time
const WINDOWS := 500  # 1000h total
const CAPTURE_AFTER_WINDOWS := 250  # mid-stream save/load round-trip at 500h
const BUDGET_SECONDS := 30.0


func suite_name() -> String:
	return "economy_stability_1000h"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()

	# --- The stream (main line, with the mid-stream capture + twin).
	var session: Variant = HOST.session(RUN_SEED)
	var stream := _stream(session.engine, session.meta, true)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	_print_digest(stream, wall)

	# --- Explosion / collapse / health (the town-hall criterion).
	var bounds := _content_bounds()
	harness.check(bool(stream["in_bounds"]), "no runaway explosion: every sampled stock within the content-derived bound %s (peaks %s)" % [str(bounds), str(stream["peaks"])])
	harness.check(int(stream["floor_failures"]) == 0, "no progress collapse: every staffed window produced at least its exact content floor (%d violations over %d windows)" % [stream["floor_failures"], WINDOWS])
	harness.check(bool(stream["non_negative"]), "resources never negative (integer pool, sampled every window)")
	harness.check(int(stream["gross_produced"][&"food"]) > 0 and int(stream["gross_produced"][&"timber"]) > 0 and int(stream["gross_produced"][&"iron"]) > 0, "the economy produced all three resources over 1000h (gross food %d, timber %d, iron %d)" % [stream["gross_produced"][&"food"], stream["gross_produced"][&"timber"], stream["gross_produced"][&"iron"]])
	harness.check(bool(stream["suspicion_in_range"]), "suspicion always within [0, %d]" % MVP.load_mvp().tunables.suspicion_max)
	harness.check(int(stream["builds"]) >= (int(stream["restarts"]) + 1) * MVP.building_ids().size(), "every run built its full estate (%d building_built events across %d runs)" % [stream["builds"], int(stream["restarts"]) + 1])

	# --- Suspicion verdict, per the rules (whichever regime the content
	# chose — the digest records which; this seed exercises BOTH).
	var strikes: int = stream["strikes"]
	var crushes: int = stream["crushes"]
	harness.check(strikes > 0, "the tension rhythm is live in CI: %d crackdown strikes over 1000h" % strikes)
	harness.check(bool(stream["strikes_landed_at_telegraph"]), "every strike landed at its telegraph's exact land tick (the >=4h warning held)")
	harness.check(int(stream["telegraphs"]) == strikes + int(stream["cancels"]) + int(stream["orphaned_telegraphs"]) + int(stream["pending_telegraphs"]), "every armed telegraph struck, was cancelled, was orphaned by a crush, or is still pending (%d armed = %d struck + %d cancelled + %d orphaned + %d pending)" % [stream["telegraphs"], strikes, stream["cancels"], stream["orphaned_telegraphs"], stream["pending_telegraphs"]])
	harness.check(crushes > 0, "the content's long-horizon reality is encoded, not hidden: %d crush(es), each per the rules (balance note for T-SIM-08 in the digest)" % crushes)
	harness.check(bool(stream["crushes_at_max"]), "every crush fired at exactly max suspicion with same-tick run_lost + full banking")
	harness.check(crushes == int(stream["restarts"]), "sensible play folded a fresh run after every crush (%d restarts)" % stream["restarts"])
	harness.check(bool(stream["restart_reset"]), "each restart emptied roster/estate/pool and reset the meter to 0")
	harness.check(bool(stream["alive_at_end"]), "the stream ends with a LIVE run (the loop is playable indefinitely)")

	# --- Determinism: bit-identical replay (fresh session, same script).
	var replay_session: Variant = HOST.session(RUN_SEED)
	var replay := _stream(replay_session.engine, replay_session.meta, false)
	harness.check(int(replay["hash"]) == int(stream["hash"]), "replay: identical final hash (%d)" % stream["hash"])
	harness.check(int(replay["strikes"]) == strikes and int(replay["crushes"]) == crushes and int(replay["restarts"]) == int(stream["restarts"]), "replay: identical tension counters (strikes %d, crushes %d, restarts %d)" % [strikes, crushes, stream["restarts"]])
	harness.check(int(replay["bank"]) == int(stream["bank"]) and int(replay["hash_500h"]) == int(stream["hash_500h"]), "replay: identical bank (%d lp) + identical 500h checkpoint hash" % stream["bank"])

	# --- Mid-stream save/load round-trip: the restored twin replayed the
	# second half in lockstep, and the meta domain round-tripped.
	harness.check(bool(stream["twin_lockstep"]), "mid-stream round-trip at 500h: restored twin replayed 500h to a bit-identical hash (%d)" % stream["twin_hash"])
	harness.check(bool(stream["meta_roundtrip"]), "meta bank + chronicle survived their own dict round-trip mid-stream")

	harness.check(wall < BUDGET_SECONDS, "1000h stability stream in < %.0fs (took %.2fs; replay runs separately)" % [BUDGET_SECONDS, wall])
	harness.check(session.engine.pending_command_count() == 0, "every gameplay write went through submit_command (queue drained)")


## Runs the whole 1000h stream. Pure function of (engine construction, seed):
## all decisions read live state; all writes are engine commands. Returns the
## report. When `with_twin`, the 500h capture + lockstep twin runs too.
func _stream(engine: SimEngine, meta: RunMeta, with_twin: bool) -> Dictionary:
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var production := engine.get_system(&"production") as ProductionSystem
	var suspicion := engine.get_system(&"suspicion") as SuspicionSystem
	var suspicion_max: int = MVP.load_mvp().tunables.suspicion_max
	var report := {
		"floor_failures": 0,
		"in_bounds": true,
		"non_negative": true,
		"suspicion_in_range": true,
		"strikes_landed_at_telegraph": true,
		"crushes_at_max": true,
		"restart_reset": true,
		"peaks": {},
		"gross_produced": {},
	}
	var bounds := _content_bounds()
	var prev_stock := {}
	var ring_seq := 0
	var telegraph_land_ticks: Array[int] = []  # armed, unresolved (FIFO)
	var crushed_ticks: Array[int] = []  # global: crush resolution is NEXT-tick aligned
	var lost_ticks: Array[int] = []
	var restart_windows := {}
	var crushed_last_window := false
	var tally := {
		"warns": 0, "telegraphs": 0, "strikes": 0, "cancels": 0,
		"crushes": 0, "restarts": 0, "seized": 0, "builds": 0,
		"orphaned": 0,
	}
	var hash_500h := 0
	var twin_engine: SimEngine = null
	var twin_meta := RunMeta.new()

	# Boot: the honest stipend through the grant verb (no set_resource).
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	var bank_before := meta.legacy_points

	for w in range(WINDOWS):
		# Sensible play: lay low in the crackdown zone; keep a measured
		# estate (army 4, population 24); fold a fresh run after a crush.
		var laying_low := suspicion.suspicion_points() >= 70
		var ledger: Dictionary = HOST.manage(engine, 4, {&"laying_low": laying_low, &"population_cap": 24})
		if crushed_last_window:
			engine.submit_command(&"run_restart", &"", 0)
			engine.submit_command(&"grant_resources", &"", 0)
		engine.fast_forward(WINDOW_TICKS)

		# --- Window accounting (events first: they carry the corrections).
		var seized := {}
		var granted := {}
		var struck_ticks: Array[int] = []
		while ring_seq < engine.events.next_seq():
			var event := engine.events.get_event(ring_seq)
			if event == null:
				ring_seq += 1
				continue
			match event.type:
				&"suspicion_warn":
					tally["warns"] += 1
				&"suspicion_telegraph":
					tally["telegraphs"] += 1
					telegraph_land_ticks.append(event.value)
				&"crackdown_cancelled":
					tally["cancels"] += 1
					if not telegraph_land_ticks.is_empty():
						telegraph_land_ticks.remove_at(0)
				&"crackdown_struck":
					tally["strikes"] += 1
					struck_ticks.append(event.tick)
				&"crackdown_seized":
					seized[event.subject] = int(seized.get(event.subject, 0)) + event.value
					tally["seized"] += event.value
				&"run_crushed":
					tally["crushes"] += 1
					crushed_ticks.append(event.tick)
					# The crush orphans its own armed telegraph, if any.
					if not telegraph_land_ticks.is_empty():
						telegraph_land_ticks.remove_at(0)
						tally["orphaned"] += 1
					if event.value != suspicion_max:
						report["crushes_at_max"] = false
				&"run_lost":
					lost_ticks.append(event.tick)
					if meta.legacy_points <= bank_before:
						report["crushes_at_max"] = false  # defeat must bank full progress
					bank_before = meta.legacy_points
				&"run_restarted":
					tally["restarts"] += 1
					restart_windows[w] = true
				&"building_built":
					tally["builds"] += 1
				&"resources_granted":
					granted[event.subject] = int(granted.get(event.subject, 0)) + event.value
			ring_seq += 1
		for tick in struck_ticks:
			if telegraph_land_ticks.is_empty() or int(telegraph_land_ticks[0]) != tick:
				report["strikes_landed_at_telegraph"] = false
			else:
				telegraph_land_ticks.remove_at(0)

		# --- Stock health + explosion bound (every window, every resource).
		for id in engine.resources.keys():
			var value: int = int(engine.resources[id])
			if value < 0:
				report["non_negative"] = false
			if value > int((report["peaks"] as Dictionary).get(id, 0)):
				report["peaks"][id] = value
			if value > int(bounds.get(id, 0)):
				report["in_bounds"] = false
		if suspicion.suspicion_points() < 0 or suspicion.suspicion_points() > suspicion_max:
			report["suspicion_in_range"] = false

		# --- Collapse floor + gross production: measured production >= the
		# exact content floor in every staffed window. Restarts deliberately
		# zero the estate mid-window (and re-grant), so restart windows are
		# excluded from BOTH the floor assertion and the gross tally.
		if not restart_windows.has(w):
			var staffed := false
			var floor := 0
			for id in MVP.producer_ids():
				var assigned: int = production.assigned_workers(id)
				if assigned > 0:
					staffed = true
					floor += production.production_rate_milli_per_worker(id) * assigned * (WINDOW_TICKS / SimEngine.TICKS_PER_SIM_HOUR) / SimFixed.MILLI
			var corrections := 0
			var produced := 0
			for id in engine.resources.keys():
				var delta: int = int(engine.resources[id]) - int(prev_stock.get(id, 0))
				prev_stock[id] = int(engine.resources[id])
				var correction: int = int(ledger.get(id, 0)) + int(seized.get(id, 0)) - int(granted.get(id, 0))
				produced += delta
				corrections += correction
				report["gross_produced"][id] = int((report["gross_produced"] as Dictionary).get(id, 0)) + delta + correction
			if staffed and w > 0 and produced + corrections < floor:
				report["floor_failures"] += 1
		else:
			for id in engine.resources.keys():
				prev_stock[id] = int(engine.resources[id])

		# --- Crush bookkeeping + the restart-reset assertion (state sampled
		# at the window's end, after the restart's synchronous reset drain).
		crushed_last_window = not run.is_running() \
			and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT
		if restart_windows.has(w):
			crushed_last_window = false
			# The reset contract, sampled after the window that drained the
			# restart (arrivals may legitimately resume inside the window —
			# the cadence restarts with the run; the ROSTER must be empty).
			var resources_match_grant := true
			for id in engine.resources.keys():
				if int(engine.resources[id]) != int(granted.get(id, 0)):
					resources_match_grant = false
			if units.total_units() != 0 \
					or production.building_level(&"farm") != 0 \
					or production.idle_workers() != 0 \
					or suspicion.suspicion_points() != 0 \
					or not resources_match_grant:
				report["restart_reset"] = false

		# --- Mid-stream capture at 500h: fork a twin from the engine dict.
		if w == CAPTURE_AFTER_WINDOWS - 1:
			hash_500h = engine.state_hash()
			if with_twin:
				var captured := engine.to_dict()
				var meta_captured := meta.to_dict()
				twin_engine = HOST.game_stack(RUN_SEED, twin_meta)
				twin_engine.apply_state_dict(captured)
				twin_meta.apply_dict(meta_captured)
				report["meta_roundtrip"] = twin_meta.legacy_points == meta.legacy_points \
					and twin_meta.runs_recorded == meta.runs_recorded \
					and twin_meta.chronicle.size() == meta.chronicle.size()

	# Twin: replay the second half from the captured state, in lockstep.
	if with_twin and twin_engine != null:
		_twin_second_half(twin_engine)
		report["twin_lockstep"] = twin_engine.state_hash() == engine.state_hash()
		report["twin_hash"] = twin_engine.state_hash()

	# Crush resolution is tick-aligned (the crush submits resolve_victory;
	# run_lost drains the NEXT tick — possibly the next window): each crush
	# must be followed by its defeat exactly one tick later.
	for tick in crushed_ticks:
		if not lost_ticks.has(tick + 1):
			report["crushes_at_max"] = false

	report["hash"] = engine.state_hash()
	report["hash_500h"] = hash_500h
	report["warns"] = tally["warns"]
	report["telegraphs"] = tally["telegraphs"]
	report["strikes"] = tally["strikes"]
	report["cancels"] = tally["cancels"]
	report["crushes"] = tally["crushes"]
	report["restarts"] = tally["restarts"]
	report["seized"] = tally["seized"]
	report["builds"] = tally["builds"]
	report["orphaned_telegraphs"] = tally["orphaned"]
	report["pending_telegraphs"] = telegraph_land_ticks.size()
	report["bank"] = meta.legacy_points
	report["chronicle"] = meta.runs_recorded
	report["alive_at_end"] = run.is_running()
	var estate := {}
	for id in production.building_ids():
		estate[id] = production.building_level(id)
	report["estate"] = str(estate)
	report["arrivals"] = units.arrivals_total
	report["army_power"] = units.army_power()
	return report


## The twin's second half: same policy, same windows, from the captured
## state (divergence is caught by the final hash comparison).
func _twin_second_half(twin: SimEngine) -> void:
	var suspicion := twin.get_system(&"suspicion") as SuspicionSystem
	var run := twin.get_system(&"run") as RunLifecycleSystem
	var crushed_last := false
	for _w in range(CAPTURE_AFTER_WINDOWS, WINDOWS):
		var laying_low := suspicion.suspicion_points() >= 70
		HOST.manage(twin, 4, {&"laying_low": laying_low, &"population_cap": 24})
		if crushed_last:
			twin.submit_command(&"run_restart", &"", 0)
			twin.submit_command(&"grant_resources", &"", 0)
		twin.fast_forward(WINDOW_TICKS)
		crushed_last = not run.is_running() \
			and run.run_outcome() == RunLifecycleSystem.OUTCOME_DEFEAT


## Content-derived explosion bound per resource: starting grant + every
## producing building's MAXIMUM conceivable output over 1000h — per-worker
## rate x max level x milestone compounding x the WORST production quirk any
## regime applies to that resource x the max worker slots. All from pack
## data (no suite-side economy numbers).
func _content_bounds() -> Dictionary:
	var pack := MVP.load_mvp()
	var hours := WINDOWS * WINDOW_TICKS / SimEngine.TICKS_PER_SIM_HOUR
	var milestone_milli := SimFixed.milli_from_float(pack.tunables.milestone_multiplier)
	var bounds := {}
	for id in pack.starting_grants.keys():
		bounds[id] = int(pack.starting_grants[id])
	for building: BuildingDef in pack.buildings:
		if building.resource_produced == &"":
			continue
		var rate_milli := SimFixed.milli_from_float(building.base_production_per_worker_hour) * building.max_level
		for milestone in building.milestone_levels:
			if milestone <= building.max_level:
				rate_milli = rate_milli * milestone_milli / SimFixed.MILLI
		rate_milli = rate_milli * _worst_production_quirk_milli(pack, building.resource_produced) / SimFixed.MILLI
		var slots: int = building.worker_slots_base + building.max_level - 1
		var total := rate_milli * slots * hours / SimFixed.MILLI
		bounds[building.resource_produced] = int(bounds.get(building.resource_produced, 0)) + total
	return bounds


## The largest production multiplier any regime flavor applies to `resource`
## (per-resource quirks and all-resource quirks both considered; identity
## floor 1.0 — a quirk can only loosen the bound, never invert it).
func _worst_production_quirk_milli(pack: ContentPack, resource: StringName) -> int:
	var worst := SimFixed.MILLI
	for regime: RegimeDef in pack.regimes:
		var quirk := regime.economy_quirk
		if quirk == null or quirk.kind != &"production_multiplier":
			continue
		if quirk.target == &"all" or quirk.target == resource:
			worst = maxi(worst, SimFixed.milli_from_float(quirk.value))
	return worst


func _print_digest(report: Dictionary, wall: float) -> void:
	print(
		"[economy_stability_1000h] seed %d: 1000h (%d ticks) in %.2fs — peaks %s; gross %d food / %d timber / %d iron; suspicion %d warns / %d telegraphs / %d strikes / %d cancels / %d crushes / %d restarts, %d seized, %d builds; bank %d lp over %d chronicle runs; alive at end %s; 500h hash %d; final hash %d"
		% [
			RUN_SEED, WINDOWS * WINDOW_TICKS, wall,
			str(report["peaks"]), report["gross_produced"][&"food"],
			report["gross_produced"][&"timber"], report["gross_produced"][&"iron"],
			report["warns"], report["telegraphs"], report["strikes"],
			report["cancels"], report["crushes"], report["restarts"],
			report["seized"], report["builds"], report["bank"],
			report["chronicle"], report["alive_at_end"],
			report["hash_500h"], report["hash"],
		]
	)
	print("[economy_stability_1000h] balance note for T-SIM-08: arrivals never stop, gate offers are presence, decay is capped — long runs ratchet to crush; measured here, not tuned here")
