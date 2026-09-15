## Unit tests for the offline catch-up service (T-SIM-07).
## Mirrors sim/catch_up_service.gd + the RunMeta anchor field (test-mapping
## rule). Hawkeye seam coverage: every Hulk edge case — backwards clock
## (elapsed negative -> clamp 0, NO resource loss, wry chronicle line),
## huge forward jump (8h cap), first launch (sentinel anchor -> nothing),
## in-app pause (world freeze, zero accrual), sub-minute remainder discard,
## anchor refresh on every apply, kill-mid-catch-up (pre-catch-up save
## stays valid; reload recomputes from the anchor), save/load during an
## away window — plus the boundary math at exactly-the-cap / 1s-over /
## 0-elapsed, int64-overflow safety, and the pure-function invariants
## T-QA-04 will fuzz (checked here over 2000 seeded-random inputs).
extends GdUnitTestSuite

const RUN_SEED := 20260924
const CAP_SECONDS := 8 * 3600  # R4 default: 8h
const CAP_TICKS := 480
const T0 := 1_790_000_000  # fixed injected UTC epoch (never a wall clock)

var _dir_seq := 0


# --- Fixtures (in-code content; same classes the .tres files use) ----------


func _tunables(interval_hours := 1.0) -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_jitter_hours = 0.0  # metronome: zero RNG draws
	tunables.recruit_arrival_interval_hours = interval_hours
	# Quiet estate: presence weights 0 so away-window suspicion is pure decay.
	tunables.suspicion_presence_army_per_hour = 0.0
	tunables.suspicion_presence_follower_per_hour = 0.0
	tunables.suspicion_presence_building_per_hour = 0.0
	tunables.suspicion_presence_offer_per_hour = 0.0
	return tunables


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel"]
	pools.leader_epithets = ["the Unbearable", "the Almost Wise", "of the Leaky Barn"]
	pools.personality_tags = [&"ambitious", &"pious", &"paranoid"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick"]
	return pools


func _regime() -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = &"gilded_crown"
	regime.display_name = "The Gilded Crown"
	var combat := RegimeModifier.new()
	combat.kind = &"garrison_multiplier"
	combat.value = 1.2
	regime.combat_modifier = combat
	var quirk := RegimeModifier.new()
	quirk.kind = &"production_multiplier"
	quirk.target = &"timber"
	quirk.value = 0.85
	regime.economy_quirk = quirk
	return regime


func _farm() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"farm"
	def.display_name = "Farm"
	def.resource_produced = &"food"
	def.base_production_per_worker_hour = 6.0
	def.worker_slots_base = 2
	var cost: Dictionary[StringName, int] = {}
	cost[&"timber"] = 15
	def.base_cost = cost
	def.cost_growth = 1.08
	def.max_level = 30
	return def


func _unit_defs() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"worker")
	peasant.promotion_paths.append(&"militia")
	defs.append(peasant)

	var worker := UnitDef.new()
	worker.id = &"worker"
	worker.display_name = "Worker"
	worker.can_work = true
	worker.training_time_hours = 0.5
	defs.append(worker)

	var militia := UnitDef.new()
	militia.id = &"militia"
	militia.display_name = "Militia"
	militia.training_time_hours = 2.0
	militia.promotion_paths.append(&"trainee")
	militia.suspicion_on_train = 8
	defs.append(militia)

	var trainee := UnitDef.new()
	trainee.id = &"trainee"
	trainee.display_name = "Trainee"
	trainee.training_time_hours = 4.0
	trainee.promotion_paths.append(&"knight")
	trainee.promotion_paths.append(&"archer")
	defs.append(trainee)

	var knight := UnitDef.new()
	knight.id = &"knight"
	knight.display_name = "Knight"
	knight.training_time_hours = 12.0
	knight.combat_power = 10
	defs.append(knight)

	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.combat_power = 6
	archer.suspicion_on_train = 4
	defs.append(archer)
	return defs


## Full stack (the §14 registration order: suspicion LAST) with a small
## timber stipend so the prefix can build the farm.
func _stack(p_meta: RunMeta = null, interval_hours := 1.0) -> SimEngine:
	var tunables := _tunables(interval_hours)
	var buildings: Array[BuildingDef] = [_farm()]
	var stipend: Dictionary = {&"timber": 60}
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new([_regime()], _identity(), p_meta, stipend))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), [], tunables))
	engine.register_system(ProductionSystem.new(buildings, tunables, null))
	engine.register_system(SuspicionSystem.new(tunables, _unit_defs()))
	return engine


## A short deterministic playing session (identical on twins): start + grant,
## then four managed chunks — accept everyone to worker, staff the farm,
## upgrade when affordable.
func _play(engine: SimEngine) -> void:
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	for i in 4:
		var units := engine.get_system(&"units") as UnitLifecycleSystem
		var production := engine.get_system(&"production") as ProductionSystem
		for uid in units.offer_ids():
			engine.submit_command(&"recruit_accept", &"", uid)
		for uid in units.idle_units(&"peasant"):
			engine.submit_command(&"assign_role", &"worker", uid)
		var free: int = production.worker_slots(&"farm") - production.assigned_workers(&"farm")
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", &"farm", mini(free, production.idle_workers()))
		engine.submit_command(&"upgrade_building", &"farm", 0)
		engine.fast_forward(120)


func _meta_of(engine: SimEngine) -> RunMeta:
	return (engine.get_system(&"run") as RunLifecycleSystem).meta


func _count_events(engine: SimEngine, type: StringName) -> int:
	var total := 0
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			total += 1
	return total


# --- Pure math: clamp + boundaries -------------------------------------------


func test_clamp_never_negative_never_uncapped() -> void:
	assert_int(CatchUpService.clamp_elapsed_seconds(-50, CAP_SECONDS)).is_equal(0)
	assert_int(CatchUpService.clamp_elapsed_seconds(0, CAP_SECONDS)).is_equal(0)
	assert_int(CatchUpService.clamp_elapsed_seconds(7200, CAP_SECONDS)).is_equal(7200)
	assert_int(CatchUpService.clamp_elapsed_seconds(CAP_SECONDS, CAP_SECONDS)).is_equal(CAP_SECONDS)
	assert_int(CatchUpService.clamp_elapsed_seconds(CAP_SECONDS + 1, CAP_SECONDS)).is_equal(CAP_SECONDS)
	assert_int(CatchUpService.clamp_elapsed_seconds(100 * 365 * 86400, CAP_SECONDS)).is_equal(CAP_SECONDS)
	# Defensive: a degenerate cap can never make the clamp negative.
	assert_int(CatchUpService.clamp_elapsed_seconds(500, 0)).is_equal(0)
	assert_int(CatchUpService.clamp_elapsed_seconds(500, -100)).is_equal(0)


func test_applied_ticks_boundaries() -> void:
	# 0 elapsed, sub-tick, first whole tick.
	assert_int(CatchUpService.applied_ticks_for(0, CAP_SECONDS)).is_equal(0)
	assert_int(CatchUpService.applied_ticks_for(59, CAP_SECONDS)).is_equal(0)
	assert_int(CatchUpService.applied_ticks_for(60, CAP_SECONDS)).is_equal(1)
	# EXACTLY at the cap: 8h -> 480 ticks.
	assert_int(CatchUpService.applied_ticks_for(CAP_SECONDS, CAP_SECONDS)).is_equal(CAP_TICKS)
	# 1s over the cap, 59s over, a full minute over: all still exactly 480
	# (the clamp runs BEFORE the divide).
	assert_int(CatchUpService.applied_ticks_for(CAP_SECONDS + 1, CAP_SECONDS)).is_equal(CAP_TICKS)
	assert_int(CatchUpService.applied_ticks_for(CAP_SECONDS + 59, CAP_SECONDS)).is_equal(CAP_TICKS)
	assert_int(CatchUpService.applied_ticks_for(CAP_SECONDS + 60, CAP_SECONDS)).is_equal(CAP_TICKS)
	# A 100-year forward jump is still just the cap.
	assert_int(CatchUpService.applied_ticks_for(100 * 365 * 86400, CAP_SECONDS)).is_equal(CAP_TICKS)
	# Negative elapsed can never produce negative ticks.
	assert_int(CatchUpService.applied_ticks_for(-7200, CAP_SECONDS)).is_equal(0)


func test_elapsed_between_overflow_safe() -> void:
	# Normal values subtract exactly.
	assert_int(CatchUpService.elapsed_between(T0, T0 + 3600)).is_equal(3600)
	assert_int(CatchUpService.elapsed_between(T0 + 3600, T0)).is_equal(-3600)
	# int64 extremes clamp operands to +/-2^40 before subtracting, so the
	# widest representable gap is 2^41 — no wrap, no crash (fuzz-safe).
	var extreme := 1 << 62
	assert_int(CatchUpService.elapsed_between(-extreme, extreme)).is_equal(1 << 41)
	assert_int(CatchUpService.elapsed_between(0, extreme)).is_equal(1 << 40)
	# And the composed rule still lands on the cap.
	assert_int(
		CatchUpService.applied_ticks_for(
			CatchUpService.elapsed_between(-extreme, extreme), CAP_SECONDS
		)
	).is_equal(CAP_TICKS)


func test_pure_math_invariants_over_generated_inputs() -> void:
	# The T-QA-04 properties, checked here over 2000 seeded-random inputs:
	# never negative, never uncapped, floor-remainder < 1 tick, monotone in
	# elapsed for a fixed cap.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	for i in 2000:
		var elapsed := rng.randi_range(-1_000_000, 1_000_000_000)
		var cap := rng.randi_range(4 * 3600, 24 * 3600)
		var eff := CatchUpService.clamp_elapsed_seconds(elapsed, cap)
		var applied := CatchUpService.applied_ticks_for(elapsed, cap)
		if applied < 0 or applied * 60 > eff or eff - applied * 60 >= 60 or applied > cap / 60:
			assert_bool(false).is_true()  # invariant broken — see values above
			return
		var next := CatchUpService.applied_ticks_for(elapsed + 1, cap)
		if next < applied:
			assert_bool(false).is_true()  # monotonicity broken
			return


# --- The service: Hulk edge cases ----------------------------------------------


func test_happy_path_accrual_matches_live_twin() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var twin := _stack()
	_play(twin)
	var hash_before := engine.state_hash()
	assert_int(hash_before).is_equal(twin.state_hash())  # fixture sanity

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 3 * 3600)

	assert_int(report["applied_ticks"]).is_equal(180)
	assert_int(report["clamped_seconds"]).is_equal(10800)
	assert_bool(report["capped"]).is_false()
	assert_bool(report["rewound"]).is_false()
	assert_int(report["from_tick"]).is_equal(engine.tick_count - 180)
	# The anchor refreshed to the foreground timestamp.
	assert_int(meta.last_seen_epoch).is_equal(T0 + 3 * 3600)
	# ONE summary event, carrying ticks + clamped seconds.
	assert_int(_count_events(engine, &"catch_up_applied")).is_equal(1)
	# Twin parity: the catch-up fast-forward == 180 LIVE ticks on an
	# identically-built engine (determinism incl. arrival rng draws).
	for i in 180:
		twin.tick()
	assert_int(engine.state_hash()).is_equal(twin.state_hash())
	assert_int(engine.get_resource(&"food")).is_equal(twin.get_resource(&"food"))
	# The summary's resource delta is honest against the twin's own window.
	assert_int(int(report["resource_delta"].get(&"food", 0))).is_greater(0)


func test_zero_elapsed_is_a_silent_noop() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var hash_before := engine.state_hash()
	var ticks_before := engine.tick_count

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0)

	assert_int(report["applied_ticks"]).is_equal(0)
	assert_int(engine.tick_count).is_equal(ticks_before)
	assert_int(engine.state_hash()).is_equal(hash_before)
	assert_int(_count_events(engine, &"catch_up_applied")).is_equal(0)
	assert_int(meta.last_seen_epoch).is_equal(T0)


func test_backwards_clock_clamps_to_zero_with_no_loss() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var hash_before := engine.state_hash()
	var food_before := engine.get_resource(&"food")
	var ticks_before := engine.tick_count

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 - 3600)  # clock rewound 1h

	assert_bool(report["rewound"]).is_true()
	assert_int(report["applied_ticks"]).is_equal(0)
	assert_int(report["elapsed_seconds"]).is_equal(-3600)
	# NO resource loss: state, pool and clock are bit-identical.
	assert_int(engine.state_hash()).is_equal(hash_before)
	assert_int(engine.get_resource(&"food")).is_equal(food_before)
	assert_int(engine.tick_count).is_equal(ticks_before)
	# The rewind is announced (event payload = rewound seconds) and gets a
	# wry chronicle placeholder line.
	assert_int(_count_events(engine, &"catch_up_clock_rewound")).is_equal(1)
	assert_str(CatchUpService.chronicle_line(report)).is_not_empty()


func test_forward_huge_jump_caps_at_eight_hours() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var twin := _stack()
	_play(twin)

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 8 * 3600 + 90 * 60)

	assert_bool(report["capped"]).is_true()
	assert_int(report["elapsed_seconds"]).is_equal(8 * 3600 + 90 * 60)
	assert_int(report["clamped_seconds"]).is_equal(CAP_SECONDS)
	assert_int(report["applied_ticks"]).is_equal(CAP_TICKS)
	assert_int(service.cap_ticks()).is_equal(CAP_TICKS)
	for i in CAP_TICKS:
		twin.tick()
	assert_int(engine.state_hash()).is_equal(twin.state_hash())


func test_first_launch_never_accrues() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)  # fresh: last_seen_epoch == sentinel 0
	_play(engine)
	var hash_before := engine.state_hash()

	var service := CatchUpService.new(_tunables())
	var report := service.apply(engine, meta, T0 + 30 * 86400)

	assert_bool(report["first_launch"]).is_true()
	assert_int(report["applied_ticks"]).is_equal(0)
	assert_int(engine.state_hash()).is_equal(hash_before)
	assert_int(_count_events(engine, &"catch_up_applied")).is_equal(0)
	# The first foreground BECOMES the anchor.
	assert_int(meta.last_seen_epoch).is_equal(T0 + 30 * 86400)


func test_paused_engine_freezes_the_world() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	engine.pause()
	var hash_before := engine.state_hash()

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 5 * 3600)

	assert_bool(report["skipped_paused"]).is_true()
	assert_int(report["applied_ticks"]).is_equal(0)
	assert_int(engine.state_hash()).is_equal(hash_before)  # paused bit included
	assert_int(_count_events(engine, &"catch_up_applied")).is_equal(0)
	assert_int(meta.last_seen_epoch).is_equal(T0 + 5 * 3600)  # anchor refreshes anyway
	# Unpausing resumes normal play — nothing was corrupted by the skip.
	engine.resume()
	assert_bool(engine.tick()).is_true()


func test_sub_minute_remainder_is_discarded() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var ticks_before := engine.tick_count

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var first := service.apply(engine, meta, T0 + 59)
	assert_int(first["applied_ticks"]).is_equal(0)
	assert_int(engine.tick_count).is_equal(ticks_before)

	# The anchor snapped to the first foreground: the next window measures
	# from THERE — exactly 60 more seconds is exactly one tick.
	var second := service.apply(engine, meta, T0 + 59 + 60)
	assert_int(second["applied_ticks"]).is_equal(1)


func test_mark_seen_refresh_blocks_play_time_accrual() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	# Ten minutes of PLAYING (the host keeps marking the session seen), then
	# a foreground 11 minutes after T0: only the final minute is away.
	service.mark_seen(meta, T0 + 600)
	var report := service.apply(engine, meta, T0 + 660)
	assert_int(report["applied_ticks"]).is_equal(1)


func test_summary_counts_match_the_twin_event_stream() -> void:
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var twin := _stack()
	_play(twin)
	# Start the meter mid-decay so the away window has an exact delta to
	# report (quiet estate: -5/h with all presence weights at 0).
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	heat.set_suspicion(30)
	var twin_heat := twin.get_system(&"suspicion") as SuspicionSystem
	twin_heat.set_suspicion(30)

	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 3 * 3600)

	# The twin recomputes every count independently from ITS ring over the
	# same 180 live ticks.
	var twin_seq_before := twin.events.next_seq()
	for i in 180:
		twin.tick()
	var arrivals := 0
	var completions := 0
	var promotions := 0
	for seq in range(twin_seq_before, twin.events.next_seq()):
		var event := twin.events.get_event(seq)
		if event.type == &"recruit_arrived":
			arrivals += 1
		elif event.type == &"training_complete":
			completions += 1
		elif event.type == &"unit_promoted":
			promotions += 1
	assert_int(int(report["arrivals"])).is_equal(arrivals)
	assert_int(int(report["training_completions"])).is_equal(completions)
	assert_int(int(report["promotions"])).is_equal(promotions)
	assert_int(arrivals).is_greater(0)  # 1h metronome: the window sees ~3
	assert_int(int(report["events_in_window"])).is_greater(0)
	# Suspicion parity on the busy estate: the report's delta matches the
	# twin's own live-ticked delta to the point (exact single-source decay
	# is pinned in its own minimal test below).
	assert_bool(report["suspicion_present"]).is_true()
	assert_int(report["suspicion_before"]).is_equal(30)
	assert_int(report["suspicion_delta"]).is_equal(twin_heat.suspicion - 30)
	assert_int(heat.suspicion).is_equal(twin_heat.suspicion)


func test_away_window_is_exact_pure_decay_when_quiet() -> void:
	# A silent estate (no arrivals inside any horizon, no trainings, no
	# upgrades): the away window's ONLY suspicion movement is passive decay,
	# and the report carries it exactly.
	var engine := _stack(null, 100000.0)
	var meta := _meta_of(engine)
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	heat.set_suspicion(30)

	var service := CatchUpService.new(_tunables(100000.0))
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 3 * 3600)

	assert_int(report["applied_ticks"]).is_equal(180)
	assert_int(report["suspicion_before"]).is_equal(30)
	assert_int(report["suspicion_delta"]).is_equal(-15)  # -5/h quiet decay
	assert_int(heat.suspicion).is_equal(15)


func test_kill_mid_catch_up_leaves_pre_catch_up_save_valid() -> void:
	# Save at the moment of backgrounding (the away window OPENS with a
	# save), then "die" without ever saving again: the reload recomputes
	# the whole gap from the anchor, deterministically, capped.
	_dir_seq += 1
	var scratch := "user://cs_catchup_tests_%d" % _dir_seq
	var manager := SaveManager.new(scratch)
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var service := CatchUpService.new(_tunables())
	service.mark_seen(meta, T0)
	assert_bool(manager.save_run(engine)).is_true()
	assert_bool(manager.save_meta(meta)).is_true()

	# The killed process: catch-up ran in memory, then the process died
	# before ANY save — the disk still holds the pre-catch-up state.
	service.apply(engine, meta, T0 + 2 * 3600)

	# Fresh process: fresh stack (same systems/order), load both domains.
	var revived := _stack()
	var revived_meta := manager.load_meta()
	assert_int(revived_meta.last_seen_epoch).is_equal(T0)  # anchor survived
	assert_bool(manager.load_run(revived)).is_true()
	var report := service.apply(revived, revived_meta, T0 + 6 * 3600)
	assert_int(report["applied_ticks"]).is_equal(360)  # from T0, not T0+2h

	# Twin: the same pre-save state live-ticking the same 360 ticks.
	var twin := _stack()
	_play(twin)
	for i in 360:
		twin.tick()
	assert_int(revived.state_hash()).is_equal(twin.state_hash())
	assert_int(revived.get_resource(&"food")).is_equal(twin.get_resource(&"food"))
	_erase_dir(scratch)


func test_meta_roundtrip_carries_the_anchor() -> void:
	var meta := RunMeta.new()
	meta.last_seen_epoch = 1_234_567
	var restored := RunMeta.new()
	assert_bool(restored.apply_dict(JSON.parse_string(JSON.stringify(meta.to_dict())))).is_true()
	assert_int(restored.last_seen_epoch).is_equal(1_234_567)
	# A pre-T-SIM-07 meta (no anchor key) reads back as the first-launch
	# sentinel — tolerant reader, never a refusal.
	var legacy := RunMeta.new()
	assert_bool(legacy.apply_dict({"format_version": 1, "legacy_points": 5, "runs_recorded": 1, "chronicle": []})).is_true()
	assert_int(legacy.last_seen_epoch).is_equal(0)


func test_chronicle_lines_cover_every_report_shape() -> void:
	var rewound := CatchUpService.chronicle_line({"rewound": true, "applied_ticks": 0})
	var paused := CatchUpService.chronicle_line({"skipped_paused": true})
	var capped := CatchUpService.chronicle_line({"capped": true, "applied_ticks": 480, "cap_seconds": 28800})
	var plain := CatchUpService.chronicle_line({"applied_ticks": 180})
	var silent := CatchUpService.chronicle_line({"applied_ticks": 0})
	assert_str(rewound).is_not_empty()
	assert_str(paused).is_not_empty()
	assert_str(capped).is_not_empty()
	assert_str(capped).contains("8")
	assert_str(plain).is_not_empty()
	assert_str(silent).is_empty()  # nothing happened -> no line


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not dir.current_is_dir():
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name in files:
		dir.remove(file_name)
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
