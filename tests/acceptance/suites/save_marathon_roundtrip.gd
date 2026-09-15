## Acceptance marathon — save/load across "process restarts" at marathon
## scale (T-ARCH-03 acceptance; pre-stages T-QA-03).
##
## Builds the FULL system stack (heartbeat + run + units + production — the
## same fixture as marathon_run_thin_loop, reused by preload), plays ~500
## sim-hours of the real management script, then proves the disk boundary:
##
##   1. save_run + save_meta to a scratch dir under user://
##   2. a NEW SaveManager + NEW engine (the headless stand-in for a process
##      restart: nothing is shared except the bytes on disk) loads BOTH
##      domains and reproduces state_hash() EXACTLY — including the 64-bit
##      rng_state (the T-SIM-03 verifier note: JSON float64 would corrupt
##      it; SaveManager's tagged encoding must carry it bit-perfect)
##   3. both engines then fast-forward the SAME 50h and stay hash-identical
##      (continuation determinism across the restart, not just a snapshot)
##   4. a second save rotates the ring; the newest slot is then deliberately
##      corrupted on disk (truncation) and the next "process" falls back to
##      the older good slot — the marathon-scale corruption recovery path
##   5. REGIME SWEEP (the T-ARCH-03 verifier re-dispatch): every pack regime
##      flavor — production-target, production-all, cost-all AND cost-target
##      quirks — drives its own save -> "process restart" -> restore, with
##      the restored economy's rates AND costs asserted equal to the pre-save
##      quirked values and a +10h continuation (upgrade command included)
##      locked against the never-saved twin. Parameterized over regimes, NOT
##      seed-dependent: the first verifier FAIL was masked because the seed
##      happened to draw the one identity-production regime — a sweep over
##      forced single-regime draws cannot luck out.
##
## The 500h state is the "all systems, deep history" case: full roster with
## in-flight training timers, built-up buildings, remainder-carrying
## accumulators, and a drawn rng stream — everything to_dict composes. All
## observables are snapshotted at the moment they occur (later acts mutate
## the engine); the checks at the end read snapshots only.
extends RefCounted

const THIN_LOOP := preload("res://tests/acceptance/suites/marathon_run_thin_loop.gd")

const SCRATCH_ROOT := "user://cs_acceptance_saves"
const RUN_HOURS := 500
const CONTINUE_HOURS := 50
const BUDGET_SECONDS := 60.0
const CHUNK_TICKS := 600  # one management batch per 10h
const SWEEP_CONTINUE_HOURS := 10


func suite_name() -> String:
	return "save_marathon_roundtrip"


func run(harness) -> void:
	_erase_dir(SCRATCH_ROOT)
	var fixture := THIN_LOOP.new()
	var clock_start := Time.get_ticks_msec()

	# --- Act 1: 500h of the real managed loop, then bank a victory (so the
	# META domain round-trips real weight) and save both domains.
	var engine := _play_script(fixture)
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var hash_at_save := engine.state_hash()
	var rng_at_save := engine.rng.state
	var points_at_save := run.meta.legacy_points
	var roster_at_save := units.total_units()
	var leader_at_save := run.leader_name()

	var saver := SaveManager.new(SCRATCH_ROOT)
	var saved_run := saver.save_run(engine)
	var saved_meta := saver.save_meta(run.meta)
	var slot0_size := _file_size(saver.run_slot_path(0))
	var meta_size := _file_size(saver.meta_path())
	var slot0_text := _read_text(saver.run_slot_path(0))

	# --- Act 2: "process restart" — fresh manager, fresh engine, disk only.
	# Meta wiring is the documented host contract (sim/run_meta.gd): the
	# loaded bank instance is handed to the engine the host continues with.
	var restarted: SimEngine = fixture._build()
	var restarter := SaveManager.new(SCRATCH_ROOT)
	var loaded_run := restarter.load_run(restarted)
	var loaded_meta := restarter.load_meta()
	var restarted_run := restarted.get_system(&"run") as RunLifecycleSystem
	restarted_run.meta = loaded_meta
	var restarted_hash_at_load := restarted.state_hash()
	var restarted_rng_at_load := restarted.rng.state

	# --- Act 3: continuation determinism — both timelines run the same 50h.
	var continue_ticks := CONTINUE_HOURS * SimEngine.TICKS_PER_SIM_HOUR
	restarted.fast_forward(continue_ticks)
	engine.fast_forward(continue_ticks)
	var hash_after_continuation := engine.state_hash()
	var ticks_after_continuation := engine.tick_count

	# --- Act 4: rotate the ring with a second save, then corrupt the newest
	# slot on disk (truncation — the parse-failure corruption class) and
	# prove the NEXT "process" falls back to the older good slot.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	var saver2 := SaveManager.new(SCRATCH_ROOT)
	var saved_again := saver2.save_run(engine)
	var hash_at_second_save := engine.state_hash()
	var newest_slot := -1
	var newest_seq := -1
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		if FileAccess.file_exists(saver2.run_slot_path(slot)):
			var envelope := _parse_file(saver2.run_slot_path(slot))
			if int(envelope.get("save_seq", -1)) > newest_seq:
				newest_seq = int(envelope["save_seq"])
				newest_slot = slot
	var newest_path := saver2.run_slot_path(newest_slot)
	_truncate_file(newest_path, 0.5)
	var rescued: SimEngine = fixture._build()
	var rescue_manager := SaveManager.new(SCRATCH_ROOT)
	var rescued_ok := rescue_manager.load_run(rescued)
	var rescued_hash := rescued.state_hash()
	var meta_size_after := _file_size(rescue_manager.meta_path())

	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	print(
		"[save_marathon_roundtrip] %dh state (%d ticks, %d units, %d lp banked) -> disk (%d B run slot + %d B meta) -> restart (hash %d, rng %d) -> +%dh lockstep (hash %d); ring seq %d corrupted -> fallback hash %d; %.3fs"
		% [
			RUN_HOURS, engine.tick_count, roster_at_save, points_at_save, slot0_size, meta_size,
			hash_at_save, rng_at_save, CONTINUE_HOURS, hash_after_continuation,
			newest_seq, rescued_hash, wall,
		]
	)

	# --- Checks: happy path at marathon scale.
	harness.check(saved_run, "save_run succeeded at 500h full stack")
	harness.check(saved_meta, "save_meta succeeded (chronicle + %d lp)" % points_at_save)
	harness.check(loaded_run, "restart: run domain loaded from disk")
	harness.check(roster_at_save > 50, "500h state is deep (roster %d units — timers, gear, ranks)" % roster_at_save)
	harness.check(restarted_hash_at_load == hash_at_save, "restart: state_hash identical across the disk boundary (%d)" % hash_at_save)
	harness.check(restarted_rng_at_load == rng_at_save, "restart: 64-bit rng_state bit-exact (was %d)" % rng_at_save)
	harness.check(loaded_meta.legacy_points == points_at_save and points_at_save > 0, "restart: meta bank loaded identically (%d lp, chronicle %d)" % [points_at_save, loaded_meta.chronicle.size()])
	harness.check(restarted_run.leader_name() == leader_at_save, "restart: leader identity restored (%s)" % leader_at_save)
	harness.check(restarted.state_hash() == hash_after_continuation, "continuation: +%dh lockstep after restart (hash %d)" % [CONTINUE_HOURS, hash_after_continuation])
	harness.check(restarted.tick_count == ticks_after_continuation, "continuation: tick counts equal (%d)" % ticks_after_continuation)

	# 64-bit exactness, observed at marathon scale: whenever the drawn state
	# is outside the float64-exact range, the tag must be on disk (the exact
	# value is already asserted above either way).
	if absi(rng_at_save) > SaveManager.JSON_SAFE_INT_LIMIT:
		harness.check(slot0_text.contains("__i64__"), "marathon rng_state %d carried via the 64-bit tag" % rng_at_save)

	# --- Checks: rotation + corruption recovery at marathon scale.
	harness.check(saved_again, "second save rotated the ring")
	harness.check(newest_seq >= 1, "ring holds two generations (newest seq %d)" % newest_seq)
	harness.check(rescued_ok, "corruption: load fell back to the older good slot")
	harness.check(rescued_hash == hash_at_second_save or rescued_hash == hash_at_save,
		"corruption: fallback hash is a real prior generation (%d)" % rescued_hash)
	harness.check(FileAccess.file_exists(newest_path + ".corrupt"), "corruption: newest slot quarantined, bytes preserved")
	harness.check(meta_size_after == meta_size, "corruption: meta domain untouched by run-slot corruption (%d B)" % meta_size)
	harness.check(wall < BUDGET_SECONDS, "suite in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Replay: acts 1-3 (the deterministic script, save points included)
	# are a pure function of the seed — the disk boundary included.
	var replay := _replay(fixture)
	harness.check(replay == hash_after_continuation, "replay: hash identical through save/load/restart (hash %d)" % hash_after_continuation)

	# --- Act 5: the regime sweep (verifier re-dispatch) — every flavor.
	var sweep_root := SCRATCH_ROOT + "_regimes"
	_erase_dir(sweep_root)
	for regime: RegimeDef in fixture._regimes():
		_regime_round_trip(harness, fixture, sweep_root, regime)
	# De-mask guards: the sweep must have actually run NON-identity production
	# AND cost multipliers (the original suite passed because its seed drew
	# the identity-production regime — distinct-value checks make that class
	# of luck impossible to repeat silently).
	var distinct_rates := {}
	for rate in _sweep_camp_rates:
		distinct_rates[rate] = true
	var distinct_costs := {}
	for cost in _sweep_farm_costs:
		distinct_costs[cost] = true
	harness.check(distinct_rates.size() >= 2,
		"sweep covered non-identity production quirks (distinct camp rates %s)" % str(_sweep_camp_rates))
	harness.check(distinct_costs.size() >= 2,
		"sweep covered non-identity cost quirks (distinct farm costs %s)" % str(_sweep_farm_costs))
	_erase_dir(sweep_root)

	_erase_dir(SCRATCH_ROOT)


## The deterministic script both the main run and the replay execute: build,
## run 500h managed, bank a victory. Pure function of the fixture + seed.
func _play_script(fixture) -> SimEngine:
	var engine: SimEngine = fixture._build()
	engine.submit_command(&"run_start", &"", 0)
	fixture._seed_run(engine)
	var ran := 0
	while ran < RUN_HOURS * SimEngine.TICKS_PER_SIM_HOUR:
		if ran > 0:
			fixture._manage(engine)
		ran += engine.fast_forward(mini(CHUNK_TICKS, RUN_HOURS * SimEngine.TICKS_PER_SIM_HOUR - ran))
	(engine.get_system(&"run") as RunLifecycleSystem).resolve_victory(engine, true)
	engine.fast_forward(1)  # resolve_victory is tick-aligned: drain it
	return engine


## Re-runs acts 1-3 (the deterministic part) and returns the post-continuation
## hash, or -1 when the replay's own lockstep comparison already failed.
func _replay(fixture) -> int:
	var engine := _play_script(fixture)
	var replay_root := SCRATCH_ROOT + "_replay"
	_erase_dir(replay_root)
	var saver := SaveManager.new(replay_root)
	saver.save_run(engine)
	saver.save_meta((engine.get_system(&"run") as RunLifecycleSystem).meta)
	var restarted: SimEngine = fixture._build()
	SaveManager.new(replay_root).load_run(restarted)
	restarted.fast_forward(CONTINUE_HOURS * SimEngine.TICKS_PER_SIM_HOUR)
	engine.fast_forward(CONTINUE_HOURS * SimEngine.TICKS_PER_SIM_HOUR)
	_erase_dir(replay_root)
	return restarted.state_hash() if restarted.state_hash() == engine.state_hash() else -1


# --- Act 5: the regime sweep (T-ARCH-03 verifier re-dispatch) ---------------
#
# One forced single-regime flavor per iteration: run_start draws uniformly
# over a ONE-regime pack, so the quirk lands through the REAL set_regime
# handoff with zero seed luck. Covers every pack flavor: production-target
# (gilded_crown), cost-all (iron_rotunda), production-all (velvet_fist),
# cost-target (paper_crown). Per flavor: develop a real economy, snapshot the
# QUIRKED rate + cost + hash, cross the disk boundary through SaveManager,
# and demand the restored economy reproduce them exactly, then +10h
# continuation lockstep (an upgrade command included — the cost quirk's only
# query path) against the never-saved twin.

var _sweep_camp_rates: Array[int] = []
var _sweep_farm_costs: Array[int] = []


func _regime_round_trip(harness, fixture, root: String, regime: RegimeDef) -> void:
	var label := String(regime.id)
	var engine := _build_under(fixture, regime)
	engine.submit_command(&"run_start", &"", 0)  # forced draw: the quirk applies at the drain
	fixture._seed_run(engine)
	engine.submit_command(&"assign_worker", &"farm", 2)
	engine.submit_command(&"assign_worker", &"lumber_camp", 2)
	engine.fast_forward(CHUNK_TICKS)  # 10h of real production under the quirk

	var production := engine.get_system(&"production") as ProductionSystem
	var rate_farm: int = production.production_rate_milli_per_worker(&"farm")
	var rate_camp: int = production.production_rate_milli_per_worker(&"lumber_camp")
	var cost_timber: int = production.upgrade_cost(&"farm")[&"timber"]
	var hash_at_save: int = engine.state_hash()
	_sweep_camp_rates.append(rate_camp)
	_sweep_farm_costs.append(cost_timber)

	# Disk boundary: save, then a fresh engine + fresh manager ("process").
	var saver := SaveManager.new(root)
	var saved: bool = saver.save_run(engine)
	var restarted := _build_under(fixture, regime)
	var loaded: bool = SaveManager.new(root).load_run(restarted)
	var restarted_production := restarted.get_system(&"production") as ProductionSystem
	var restored_rate_farm: int = restarted_production.production_rate_milli_per_worker(&"farm")
	var restored_rate_camp: int = restarted_production.production_rate_milli_per_worker(&"lumber_camp")
	var restored_cost_timber: int = restarted_production.upgrade_cost(&"farm")[&"timber"]
	var hash_at_load: int = restarted.state_hash()

	# +10h continuation with an upgrade in flight on BOTH timelines.
	var continue_ticks := SWEEP_CONTINUE_HOURS * SimEngine.TICKS_PER_SIM_HOUR
	for e: SimEngine in [engine, restarted]:
		e.submit_command(&"upgrade_building", &"farm", 1)
	engine.fast_forward(continue_ticks)
	restarted.fast_forward(continue_ticks)
	var hash_twin: int = engine.state_hash()
	var hash_restored: int = restarted.state_hash()

	print(
		"[save_marathon_roundtrip] regime sweep %s: rates %d/%d milli/h, cost %d timber -> restart %d/%d, %d -> lockstep %d"
		% [label, rate_farm, rate_camp, cost_timber, restored_rate_farm,
			restored_rate_camp, restored_cost_timber, hash_restored]
	)
	harness.check(saved and loaded, "%s: save -> \"process restart\" -> load" % label)
	harness.check(restored_rate_farm == rate_farm and restored_rate_camp == rate_camp,
		"%s: restored production rates match pre-save under quirk (farm %d, camp %d)" % [label, restored_rate_farm, restored_rate_camp])
	harness.check(restored_cost_timber == cost_timber,
		"%s: restored upgrade cost matches pre-save under quirk (%d timber)" % [label, restored_cost_timber])
	harness.check(hash_at_load == hash_at_save, "%s: state_hash identical at restore (%d)" % [label, hash_at_save])
	harness.check(hash_restored == hash_twin,
		"%s: +%dh continuation lockstep incl. an upgrade (%d)" % [label, SWEEP_CONTINUE_HOURS, hash_twin])


## The fixture's stack with ONE regime in the pack: run_start's uniform draw
## is forced, so each sweep iteration deterministically exercises its flavor
## (the pack's 4 flavors cover every quirk shape: production-target
## gilded_crown, cost-all iron_rotunda, production-all velvet_fist,
## cost-target paper_crown). Marathon funds through the grant verb (F1).
func _build_under(fixture, regime: RegimeDef) -> SimEngine:
	var single: Array[RegimeDef] = [regime]
	var mvp = load("res://tests/acceptance/suites/_mvp_pack.gd")
	return mvp.stack_with_regimes(
		20260915, single, fixture._unit_defs(), fixture._building_defs(),
		mvp.MARATHON_STIPEND
	)


# --- File helpers (the suite runs under user:// and cleans up after itself)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	return text


func _parse_file(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(_read_text(path)) != OK:
		return {}
	return parser.data


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return int(length)


func _truncate_file(path: String, fraction: float) -> void:
	var text := _read_text(path)
	var truncated := text.substr(0, int(text.length() * fraction))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(truncated)
	file.close()


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var dirs: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				dirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
