## Unit tests for the L2-A escalation engine (post-MVP Layer 2, part A —
## docs/sim-engine.md §19, docs/save-schema.md §6). Mirrors sim/escalation.gd
## + the two sites that own the halves: RunLifecycleSystem's victory capture
## into RunMeta and the stateless AssaultResolver's garrison derivation.
## Covers, per the task contract: the snapshot shape == the reserved schema
## EXACTLY; victory-only capture (loss/abort leave the prior garrison — the
## regime that beat you stays until beaten; an empty-roster victory captures
## nothing); the derivation math exact at every hop; the zero-impact rule
## (no snapshot -> the static odds branch to the digit, exact key set); the
## save round-trip with a snapshot active (meta bytes + lockstep + the
## meta-domain-only rule); determinism (same seed + same meta -> same odds
## and same commit); cycle increments; and the curve/validator red paths.
extends GdUnitTestSuite

const RUN_SEED := 20260917
const SCRATCH_ROOT := "user://cs_escalation_garrison_tests"


# --- Fixtures (in-code content; same classes the .tres files use) ----------


## Metronome arrivals (jitter 0 — zero arrival draws), suspicion isolated,
## escalation step parameterizable; static garrison/floor at the tuned values.
func _tunables(escalation_step := 1.25, garrison_base := 50, floor := 23) -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_interval_hours = 0.05
	tunables.recruit_arrival_jitter_hours = 0.0
	tunables.suspicion_decay_per_hour = 0.0
	tunables.suspicion_decay_high_tier_per_hour = 0.0
	tunables.suspicion_presence_army_per_hour = 0.0
	tunables.suspicion_presence_follower_per_hour = 0.0
	tunables.suspicion_presence_building_per_hour = 0.0
	tunables.suspicion_presence_offer_per_hour = 0.0
	tunables.assault_garrison_base_power = garrison_base
	tunables.assault_knight_floor_power = floor
	tunables.escalation_garrison_cycle_step = escalation_step
	return tunables


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel"]
	pools.leader_epithets = ["the Unbearable", "the Almost Wise", "of the Leaky Barn"]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous"]
	pools.recruit_names = ["Tom", "Hob", "Nell"]
	return pools


func _regime(id := &"gilded_crown", kind := &"garrison_multiplier", value := 1.2) -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = id
	regime.display_name = String(id)
	var combat := RegimeModifier.new()
	combat.kind = kind
	combat.value = value
	regime.combat_modifier = combat
	regime.crest_id = StringName("crest_%s" % String(id))
	return regime


## The MVP unit chain (knight 10 / archer 6 — the pack's own values).
func _unit_defs() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"militia")
	defs.append(peasant)
	var militia := UnitDef.new()
	militia.id = &"militia"
	militia.display_name = "Militia"
	militia.training_time_hours = 2.0
	militia.promotion_paths.append(&"trainee")
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
	knight.required_gear_slots.append(&"weapon")
	knight.required_gear_slots.append(&"armor")
	knight.combat_power = 10
	defs.append(knight)
	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.required_gear_slots.append(&"weapon")
	archer.combat_power = 6
	defs.append(archer)
	return defs


## ALL SIX gear lines (combat values per tier: weapon 2/4/7, armor 3/6/10).
func _gear_defs() -> Array[GearDef]:
	var defs: Array[GearDef] = []
	for entry in [
		[&"gear_weapon_t1", &"weapon", 1, 2],
		[&"gear_weapon_t2", &"weapon", 2, 4],
		[&"gear_weapon_t3", &"weapon", 3, 7],
		[&"gear_armor_t1", &"armor", 1, 3],
		[&"gear_armor_t2", &"armor", 2, 6],
		[&"gear_armor_t3", &"armor", 3, 10],
	]:
		var gear := GearDef.new()
		gear.id = entry[0]
		gear.display_name = String(entry[0])
		gear.slot = entry[1]
		gear.tier = int(entry[2])
		gear.combat_power = int(entry[3])
		gear.recipe[&"iron"] = 1
		defs.append(gear)
	return defs


## The default flavor list: ONE gilded regime, so the run_start draw is
## forced and deterministic (garrison-side x1.2).
func _forced_flavors() -> Array[RegimeDef]:
	return [_regime()]


## Full engine around a SHARED meta. One forced regime by default (the draw
## is deterministic), L2-wired resolver by default (`p_escalation = false`
## reproduces the pre-L2 construction).
func _engine(
	meta: RunMeta,
	tunables: EconomyTunables,
	p_escalation := true,
	p_regimes: Array[RegimeDef] = [],
	p_run_seed: int = RUN_SEED
) -> SimEngine:
	var regimes := p_regimes if not p_regimes.is_empty() else _forced_flavors()
	var engine := SimEngine.new(p_run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(regimes, _identity(), meta))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), tunables))
	if p_escalation:
		engine.register_system(AssaultResolver.new(tunables, _unit_defs(), _gear_defs(), regimes))
	else:
		engine.register_system(AssaultResolver.new(tunables))
	return engine


func _start(engine: SimEngine) -> RunLifecycleSystem:
	engine.submit_command(&"run_start", &"", 0)
	engine.fast_forward(1)
	return engine.get_system(&"run") as RunLifecycleSystem


func _run(engine: SimEngine) -> RunLifecycleSystem:
	return engine.get_system(&"run") as RunLifecycleSystem


func _resolver(engine: SimEngine) -> AssaultResolver:
	return engine.get_system(&"assault") as AssaultResolver


func _units(engine: SimEngine) -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


## Marches one unit through the REAL chain to the target rank with the
## requested gear tiers (t1 recipes are cheap; resources seeded through the
## documented test seam).
func _field_rank(engine: SimEngine, target: StringName, tiers: Dictionary = {&"weapon": 1, &"armor": 1}) -> void:
	var units := _units(engine)
	while units.pending_offers() == 0:
		engine.fast_forward(3)
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	engine.fast_forward(1)
	var peasant := units.idle_units(&"peasant")[0]
	engine.submit_command(&"assign_role", &"militia", peasant)
	engine.fast_forward(121)
	engine.submit_command(&"start_training", &"trainee", peasant)
	engine.fast_forward(241)
	engine.submit_command(&"start_training", target, peasant)
	engine.fast_forward(12 * 60 + 1)
	engine.set_resource(&"iron", 1000)
	engine.set_resource(&"timber", 1000)
	for slot in units.missing_gear_slots(peasant):
		var tier := int(tiers.get(slot, 1))
		var gear_id := StringName("gear_%s_t%d" % [String(slot), tier])
		engine.submit_command(&"equip_gear", gear_id, peasant)
	engine.fast_forward(1)
	engine.submit_command(&"promote", &"", peasant)
	engine.fast_forward(1)


## The M1 floor line: 1 knight t1 + 1 archer t1 = army power 23.
func _field_floor(engine: SimEngine) -> void:
	_field_rank(engine, &"knight")
	_field_rank(engine, &"archer")


func _win(engine: SimEngine) -> void:
	var run := _run(engine)
	assert_bool(run.resolve_victory(engine, true)).is_true()
	engine.fast_forward(1)


func _sorted_keys_text(value: Dictionary) -> String:
	var keys: Array[String] = []
	for key in value.keys():
		keys.append(String(key))
	keys.sort()
	return ",".join(keys)


# --- Capture: shape + victory-only + cycles -----------------------------------


func test_victory_captures_the_reserved_shape_exactly() -> void:
	var meta := RunMeta.new()
	var engine := _engine(meta, _tunables())
	_start(engine)
	_field_rank(engine, &"knight", {&"weapon": 1, &"armor": 1})
	_field_rank(engine, &"archer", {&"weapon": 2})
	var run := _run(engine)
	_win(engine)
	# Shape == the reserve (save-schema §6) to the key set: top level, roster
	# line, and the tier maps keyed by STRING tiers summing to the counts.
	assert_str(_sorted_keys_text(meta.escalation_garrison)).is_equal(
		"captured_at_run,crest_id,cycle,leader,regime_id,roster"
	)
	var roster: Dictionary = meta.escalation_garrison["roster"]
	assert_str(_sorted_keys_text(roster)).is_equal("archer,knight")
	assert_str(_sorted_keys_text(roster["knight"])).is_equal("count,gear_tiers")
	assert_int(int(roster["knight"]["count"])).is_equal(1)
	assert_int(int(roster["archer"]["count"])).is_equal(1)
	assert_that(roster["knight"]["gear_tiers"]).is_equal({
		"weapon": {"1": 1},
		"armor": {"1": 1},
	})
	assert_that(roster["archer"]["gear_tiers"]).is_equal({"weapon": {"2": 1}})
	# The flavor + provenance fields (L2-C's data).
	assert_str(String(meta.escalation_garrison["regime_id"])).is_equal("gilded_crown")
	assert_str(String(meta.escalation_garrison["crest_id"])).is_equal("crest_gilded_crown")
	assert_str(String(meta.escalation_garrison["leader"])).is_equal(_run(engine).leader_name())
	assert_int(int(meta.escalation_garrison["captured_at_run"])).is_equal(1)
	assert_int(int(meta.escalation_garrison["cycle"])).is_equal(1)
	assert_int(meta.escalation_cycle).is_equal(1)
	assert_bool(not meta.escalation_garrison.is_empty()).is_true()


func test_victory_only_capture_loss_and_abort_leave_the_prior_snapshot() -> void:
	var meta := RunMeta.new()
	var engine := _engine(meta, _tunables())
	_start(engine)
	_field_floor(engine)
	_win(engine)
	var captured := meta.escalation_garrison.duplicate(true)
	# Defeat (the crush funnels here too — §14 resolves the crush through
	# OUTCOME_DEFEAT): the regime that beat you STAYS.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	_field_floor(engine)
	assert_bool(_run(engine).resolve_victory(engine, false)).is_true()
	engine.fast_forward(1)
	assert_that(meta.escalation_garrison).is_equal(captured)
	assert_int(meta.escalation_cycle).is_equal(1)
	# Abort: same rule.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	engine.submit_command(&"run_abort", &"", 0)
	engine.fast_forward(1)
	assert_that(meta.escalation_garrison).is_equal(captured)
	assert_int(meta.escalation_cycle).is_equal(1)


func test_empty_roster_victory_captures_nothing_and_keeps_the_prior_garrison() -> void:
	# Fresh install: a victory with NO standing army captures nothing (an
	# empty castle garrisons nobody) and the meta emits no escalation key —
	# a pre-victory meta stays byte-identical to the pre-L2 build.
	var meta := RunMeta.new()
	var engine := _engine(meta, _tunables())
	_start(engine)
	_win(engine)
	assert_bool(meta.escalation_garrison.is_empty()).is_true()
	assert_int(meta.escalation_cycle).is_equal(0)
	assert_bool(not meta.to_dict().has("escalation_garrison")).is_true()
	assert_bool(not meta.to_dict().has("escalation_cycle")).is_true()
	# A standing garrison is never displaced by an empty-roster victory:
	# the reset contract clears the roster at restart, the next run wins
	# empty, the PRIOR victor's army stays on the wall.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	_field_floor(engine)
	_win(engine)
	assert_int(meta.escalation_cycle).is_equal(1)
	var captured := meta.escalation_garrison.duplicate(true)
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	_win(engine)
	assert_that(meta.escalation_garrison).is_equal(captured)
	assert_int(meta.escalation_cycle).is_equal(1)


func test_cycle_increments_per_capturing_victory_and_latest_victor_wins() -> void:
	var meta := RunMeta.new()
	var engine := _engine(meta, _tunables(1.25))
	_start(engine)
	_field_rank(engine, &"knight", {&"weapon": 3, &"armor": 3})
	_win(engine)
	assert_int(meta.escalation_cycle).is_equal(1)
	assert_int(int(meta.escalation_garrison["captured_at_run"])).is_equal(1)
	# Second victory: cycle 2, the LATEST victor's army stands (one t1 knight
	# here), captured at run 2.
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	_field_rank(engine, &"knight", {&"weapon": 1, &"armor": 1})
	_win(engine)
	assert_int(meta.escalation_cycle).is_equal(2)
	assert_int(int(meta.escalation_garrison["captured_at_run"])).is_equal(2)
	assert_int(int(meta.escalation_garrison["cycle"])).is_equal(2)
	var roster: Dictionary = meta.escalation_garrison["roster"]
	assert_int(int(roster["knight"]["count"])).is_equal(1)
	assert_that(roster["knight"]["gear_tiers"]).is_equal({"weapon": {"1": 1}, "armor": {"1": 1}})


func test_run_system_read_accessors_return_copies() -> void:
	var meta := RunMeta.new()
	meta.escalation_garrison = {"regime_id": "gilded_crown", "roster": {"knight": {"count": 1}}}
	meta.escalation_cycle = 3
	var engine := _engine(meta, _tunables())
	_start(engine)
	var run := _run(engine)
	assert_int(run.escalation_cycle()).is_equal(3)
	var read := run.escalation_garrison()
	read["regime_id"] = "tampered"
	read["roster"]["knight"]["count"] = 99
	assert_str(String(run.escalation_garrison()["regime_id"])).is_equal("gilded_crown")
	assert_int(int(run.escalation_garrison()["roster"]["knight"]["count"])).is_equal(1)


# --- Derivation: exact math + transparency + fallbacks -------------------------


## A handcrafted snapshot exercising every arithmetic term: 2 knights (one
## t1/t2 mix, one t3/t3) + 1 archer (t2 weapon) = 45 + 10 = 55 power.
func _snapshot(cycle := 1, regime_id := "gilded_crown") -> Dictionary:
	return {
		"regime_id": regime_id,
		"captured_at_run": 7,
		"cycle": cycle,
		"leader": "Bran the Unbearable",
		"crest_id": "crest_gilded_crown",
		"roster": {
			"knight": {
				"count": 2,
				"gear_tiers": {"weapon": {"1": 1, "3": 1}, "armor": {"2": 1, "3": 1}},
			},
			"archer": {"count": 1, "gear_tiers": {"weapon": {"2": 1}}},
		},
	}


func test_garrison_derivation_math_is_exact() -> void:
	# snapshot_power = 2x10 + (2+7) + (6+10) + 6 + 4 = 55; cycle 1 curve x1.000
	# (the snapshot itself is the first escalation); gilded garrison x1.2.
	# base 55, strength 55 x 1200 = 66000; army 23 (neutral army side) ->
	# permille = 23000 x 1000 / 89000 = 258.
	var meta := RunMeta.new()
	meta.escalation_garrison = _snapshot()
	meta.escalation_cycle = 1
	var engine := _engine(meta, _tunables(1.25))
	_start(engine)
	_field_floor(engine)
	assert_int(_units(engine).army_power()).is_equal(23)
	var odds := _resolver(engine).assault_odds(engine)
	var garrison: Dictionary = odds["garrison"]
	assert_str(_sorted_keys_text(garrison)).is_equal(
		"base_power,captured_at_run,curve_multiplier_milli,escalation_cycle,leader,modifier_kind,regime_id,regime_multiplier_milli,roster,snapshot_power,source,strength_milli"
	)
	assert_str(String(garrison["source"])).is_equal("escalation")
	assert_int(int(garrison["snapshot_power"])).is_equal(55)
	assert_int(int(garrison["curve_multiplier_milli"])).is_equal(1000)
	assert_int(int(garrison["base_power"])).is_equal(55)
	assert_str(String(garrison["modifier_kind"])).is_equal("garrison_multiplier")
	assert_int(int(garrison["regime_multiplier_milli"])).is_equal(1200)
	assert_int(int(garrison["strength_milli"])).is_equal(66000)
	assert_int(int(garrison["escalation_cycle"])).is_equal(1)
	assert_str(String(garrison["regime_id"])).is_equal("gilded_crown")
	assert_str(String(garrison["leader"])).is_equal("Bran the Unbearable")
	assert_int(int(garrison["captured_at_run"])).is_equal(7)
	assert_that(garrison["roster"]).is_equal(_snapshot()["roster"])
	assert_int(int(odds["win_permille"])).is_equal(258)
	# The parts-sum invariant survives the escalation branch: strength ==
	# base x mult and the two sides reproduce the permille to the digit.
	assert_int(int(garrison["base_power"]) * int(garrison["regime_multiplier_milli"])).is_equal(
		int(garrison["strength_milli"])
	)


func test_curve_compounds_per_cycle_with_floored_exact_int_hops() -> void:
	# cycle 3, step x1.25: 1000 -> 1250 -> 1562 (1562500 / 1000 floored);
	# base = 55 x 1562 / 1000 = 85 (floored); strength 85 x 1200 = 102000;
	# permille = 23000 x 1000 / 125000 = 184.
	var meta := RunMeta.new()
	meta.escalation_garrison = _snapshot(3)
	meta.escalation_cycle = 3
	var engine := _engine(meta, _tunables(1.25))
	_start(engine)
	_field_floor(engine)
	var odds := _resolver(engine).assault_odds(engine)
	var garrison: Dictionary = odds["garrison"]
	assert_int(int(garrison["curve_multiplier_milli"])).is_equal(1562)
	assert_int(int(garrison["base_power"])).is_equal(85)
	assert_int(int(garrison["strength_milli"])).is_equal(102000)
	assert_int(int(odds["win_permille"])).is_equal(184)
	# Doubling the step doubles every hop: cycle 3, step x2.0 -> 4000 ->
	# base 220, strength 264000, permille 80.
	meta.escalation_cycle = 3
	var fast := _engine(meta, _tunables(2.0))
	_start(fast)
	_field_floor(fast)
	var fast_odds := _resolver(fast).assault_odds(fast)
	assert_int(int((fast_odds["garrison"] as Dictionary)["curve_multiplier_milli"])).is_equal(4000)
	assert_int(int((fast_odds["garrison"] as Dictionary)["base_power"])).is_equal(220)
	assert_int(int((fast_odds["garrison"] as Dictionary)["strength_milli"])).is_equal(264000)
	assert_int(int(fast_odds["win_permille"])).is_equal(80)


func test_unknown_ids_skip_and_unknown_regime_is_neutral() -> void:
	# A def that left the pack: the body + its kit skip loudly (warned once),
	# the rest derive; a regime that left the pack resolves neutral.
	var meta := RunMeta.new()
	meta.escalation_garrison = {
		"regime_id": "ghost_regime",
		"captured_at_run": 1,
		"cycle": 1,
		"leader": "Wick of the Leaky Barn",
		"crest_id": "crest_ghost",
		"roster": {
			"pikeman": {"count": 5, "gear_tiers": {"weapon": {"9": 5}}},  # all-unknown
			"knight": {"count": 1, "gear_tiers": {"weapon": {"1": 1}}},
		},
	}
	meta.escalation_cycle = 1
	var engine := _engine(meta, _tunables(1.25))
	_start(engine)
	var garrison: Dictionary = _resolver(engine).assault_odds(engine)["garrison"]
	assert_int(int(garrison["snapshot_power"])).is_equal(12)  # knight 10 + t1 weapon 2
	assert_str(String(garrison["modifier_kind"])).is_equal("")
	assert_int(int(garrison["regime_multiplier_milli"])).is_equal(1000)
	assert_int(int(garrison["strength_milli"])).is_equal(12000)


func test_all_unknown_snapshot_falls_back_to_the_static_garrison() -> void:
	# A snapshot whose EVERY id left the pack derives 0 power — a zero
	# castle would auto-win every assault, so the static branch rules.
	var meta := RunMeta.new()
	meta.escalation_garrison = {
		"regime_id": "gilded_crown",
		"captured_at_run": 1,
		"cycle": 1,
		"leader": "X",
		"crest_id": "c",
		"roster": {"pikeman": {"count": 5, "gear_tiers": {}}},
	}
	meta.escalation_cycle = 1
	var engine := _engine(meta, _tunables(1.25))
	_start(engine)
	var odds := _resolver(engine).assault_odds(engine)
	assert_str(_sorted_keys_text(odds["garrison"])).is_equal(
		"base_power,modifier_kind,regime_multiplier_milli,strength_milli"
	)
	assert_int(int((odds["garrison"] as Dictionary)["base_power"])).is_equal(50)


# --- Zero-impact: no snapshot = the pre-L2 odds to the digit -------------------


func test_no_snapshot_odds_are_byte_identical_regardless_of_wiring() -> void:
	# Static branch under the FORCED gilded regime: base 50 x 1200 = 60000;
	# army 23 -> permille 23000 x 1000 / 83000 = 277; exactly the four
	# static keys — whether or not the resolver is L2-wired.
	for wired in [true, false]:
		var meta := RunMeta.new()
		var engine := _engine(meta, _tunables(), wired)
		_start(engine)
		_field_floor(engine)
		var odds := _resolver(engine).assault_odds(engine)
		var expected := {
			"base_power": 50,
			"modifier_kind": &"garrison_multiplier",
			"regime_multiplier_milli": 1200,
			"strength_milli": 60000,
		}
		assert_that(odds["garrison"]).is_equal(expected)
		assert_int(int(odds["win_permille"])).is_equal(277)


func test_unwired_resolver_with_snapshot_falls_back_to_static() -> void:
	# The pre-L2 construction (no content passed): a snapshot may stand in
	# the meta, the resolver cannot resolve it — static odds, byte-identical
	# (the shared marathon fixtures' recorded digests rest on this).
	var meta := RunMeta.new()
	meta.escalation_garrison = _snapshot()
	meta.escalation_cycle = 1
	var engine := _engine(meta, _tunables(), false)
	_start(engine)
	_field_floor(engine)
	var odds := _resolver(engine).assault_odds(engine)
	assert_int(int((odds["garrison"] as Dictionary)["base_power"])).is_equal(50)
	assert_int(int((odds["garrison"] as Dictionary)["strength_milli"])).is_equal(60000)
	assert_int(int(odds["win_permille"])).is_equal(277)
	assert_bool(not (odds["garrison"] as Dictionary).has("source")).is_true()


func test_odds_query_draws_no_rng() -> void:
	var meta := RunMeta.new()
	meta.escalation_garrison = _snapshot()
	meta.escalation_cycle = 1
	var engine := _engine(meta, _tunables())
	_start(engine)
	_field_floor(engine)
	var before := engine.rng.state
	_resolver(engine).assault_odds(engine)
	assert_int(engine.rng.state).is_equal(before)


# --- Round-trip: bytes + lockstep + the meta-domain-only rule ------------------


func test_save_round_trip_with_snapshot_active() -> void:
	_erase_dir(SCRATCH_ROOT)
	var meta := RunMeta.new()
	var engine := _engine(meta, _tunables())
	_start(engine)
	_field_rank(engine, &"knight", {&"weapon": 3, &"armor": 2})
	_win(engine)
	engine.submit_command(&"ping", &"probe", 1)  # a queued command survives the boundary
	var manager := SaveManager.new(SCRATCH_ROOT)
	assert_bool(manager.save_run(engine)).is_true()
	assert_bool(manager.save_meta(meta)).is_true()
	# Hash-visible: the snapshot rides INSIDE the checksummed meta payload —
	# the bytes on disk carry it, and the envelope re-loads.
	var meta_text := _read_text(manager.meta_path())
	assert_bool(meta_text.contains("escalation_garrison")).is_true()
	assert_bool(meta_text.contains("escalation_cycle")).is_true()
	var loaded_meta := manager.load_meta()
	assert_bool(loaded_meta != null).is_true()
	# JSON parses every number as float — compare through the manager's
	# canonical form (whole floats normalize to ints; the save-integrity
	# suite's own pattern).
	assert_str(SaveManager.canonical_form(loaded_meta.escalation_garrison)).is_equal(
		SaveManager.canonical_form(meta.escalation_garrison)
	)
	assert_int(loaded_meta.escalation_cycle).is_equal(1)
	# A fresh meta re-emits the same payload (twin round trip through the
	# reader, the apply_dict discipline).
	var twin_meta := RunMeta.new()
	assert_bool(twin_meta.apply_dict(loaded_meta.to_dict())).is_true()
	assert_str(SaveManager.canonical_form(twin_meta.to_dict())).is_equal(
		SaveManager.canonical_form(loaded_meta.to_dict())
	)
	# Pre-L2 tolerant read: a meta WITHOUT the keys reads as no-snapshot.
	var pre_l2 := RunMeta.new()
	assert_bool(pre_l2.apply_dict({"format_version": 1, "legacy_points": 5, "runs_recorded": 1, "chronicle": []})).is_true()
	assert_bool(pre_l2.escalation_garrison.is_empty()).is_true()
	assert_int(pre_l2.escalation_cycle).is_equal(0)
	# Engine lockstep across the restore seam: a fresh engine (same seed,
	# same systems) loaded from the run save continues identically — and its
	# OWN meta stays snapshot-free (the run payload cannot fork the garrison).
	var fresh_meta := RunMeta.new()
	var restored := _engine(fresh_meta, _tunables())
	assert_bool(manager.load_run(restored)).is_true()
	assert_bool(fresh_meta.escalation_garrison.is_empty()).is_true()
	for target in [engine, restored]:
		target.submit_command(&"run_restart", &"", 0)
		target.fast_forward(120)
	# Lockstep across the restore seam: identical clock + identical world.
	# (The event RING is presentation history, deliberately not serialized —
	# §3 — so ring depth is not a restore invariant; the commit-stream
	# determinism test below pins identical event flow on equal worlds.)
	assert_int(restored.tick_count).is_equal(engine.tick_count)
	assert_int(restored.state_hash()).is_equal(engine.state_hash())
	# The restored engine's derived odds reproduce the escalation through
	# the LOADED meta (the host hands the same meta instance back): the
	# captured army was 1 knight (t3 weapon + t2 armor) = power 23.
	fresh_meta.apply_dict(loaded_meta.to_dict())
	_field_floor(restored)
	var live_garrison: Dictionary = _resolver(restored).assault_odds(restored)["garrison"]
	assert_str(String(live_garrison["source"])).is_equal("escalation")
	assert_int(int(live_garrison["snapshot_power"])).is_equal(23)


# --- Determinism ----------------------------------------------------------------


func test_same_seed_same_meta_same_odds_and_commit() -> void:
	var meta := RunMeta.new()
	meta.escalation_garrison = _snapshot()
	meta.escalation_cycle = 1
	var odds_values: Array[int] = []
	var hashes: Array[int] = []
	var won: Array[bool] = []
	for _i in 2:
		var engine := _engine(meta, _tunables())
		_start(engine)
		_field_floor(engine)
		odds_values.append(int(_resolver(engine).assault_odds(engine)["win_permille"]))
		engine.submit_command(&"commit_assault", &"", 0)
		engine.fast_forward(1)
		hashes.append(engine.state_hash())
		won.append(_run(engine).run_outcome() == RunLifecycleSystem.OUTCOME_VICTORY)
	assert_int(odds_values[0]).is_equal(odds_values[1])
	assert_int(hashes[0]).is_equal(hashes[1])
	assert_bool(won[0]).is_equal(won[1])


func test_bigger_garrison_lowers_the_odds_monotone() -> void:
	# A fatter snapshot (12 fully t3 knights + the same archer: power 325
	# vs 55) must never RAISE the player's odds.
	var small := RunMeta.new()
	small.escalation_garrison = _snapshot(1)
	small.escalation_cycle = 1
	var big := RunMeta.new()
	big.escalation_garrison = _snapshot(1)
	(big.escalation_garrison as Dictionary)["roster"] = {
		"knight": {"count": 12, "gear_tiers": {"weapon": {"3": 12}, "armor": {"3": 12}}},
		"archer": {"count": 1, "gear_tiers": {"weapon": {"2": 1}}},
	}
	big.escalation_cycle = 1
	var small_odds := 0
	var big_odds := 0
	for pair in [[small, 0], [big, 1]]:
		var engine := _engine(pair[0], _tunables())
		_start(engine)
		_field_floor(engine)
		if int(pair[1]) == 0:
			small_odds = int(_resolver(engine).assault_odds(engine)["win_permille"])
		else:
			big_odds = int(_resolver(engine).assault_odds(engine)["win_permille"])
	assert_int(big_odds).is_less(small_odds)


# --- The curve helper + the validator band ---------------------------------------


func test_curve_multiplier_helper_is_exact_and_capped() -> void:
	assert_int(Escalation.curve_multiplier_milli(1250, 0)).is_equal(1000)
	assert_int(Escalation.curve_multiplier_milli(1250, 1)).is_equal(1000)
	assert_int(Escalation.curve_multiplier_milli(1250, 2)).is_equal(1250)
	assert_int(Escalation.curve_multiplier_milli(1250, 3)).is_equal(1562)
	assert_int(Escalation.curve_multiplier_milli(2000, 3)).is_equal(4000)
	# Hops cap at MAX_CURVE_HOPS: deeper cycles clamp, never overflow.
	assert_int(Escalation.curve_multiplier_milli(1250, 1 + Escalation.MAX_CURVE_HOPS)).is_equal(
		Escalation.curve_multiplier_milli(1250, 500)
	)


func test_validator_pins_the_escalation_step_band() -> void:
	# Validate against near-default tunables (the engine fixtures' 0.05 h
	# arrival interval violates the unrelated early-interval band; the
	# validator probe uses clean content).
	var ok := EconomyTunables.new()
	ok.escalation_garrison_cycle_step = 1.0
	assert_int(ContentValidator.validate_tunables(ok).size()).is_equal(0)
	var shrinking := EconomyTunables.new()
	shrinking.escalation_garrison_cycle_step = 0.9
	assert_bool(ContentValidator.validate_tunables(shrinking).any(
		func(error: String) -> bool: return error.contains("escalation_garrison_cycle_step")
	)).is_true()
	var runaway := EconomyTunables.new()
	runaway.escalation_garrison_cycle_step = 4.0
	assert_bool(ContentValidator.validate_tunables(runaway).any(
		func(error: String) -> bool: return error.contains("escalation_garrison_cycle_step")
	)).is_true()


# --- Helpers ------------------------------------------------------------------------


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	return text


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
	for file_name in files:
		dir.remove(file_name)
	for sub in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
