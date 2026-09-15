## Unit tests for the unit lifecycle system (T-SIM-03).
## Mirrors sim/systems/unit_lifecycle_system.gd (test-mapping rule).
## Hawkeye seam coverage: arrival-cadence reproducibility (seeded RNG,
## metronome no-draw mode), the full chains both branches (peasant→worker;
## peasant→militia→trainee→knight with gear; →archer), exact training
## timers per UnitDef, gear gating (promotion without gear refused
## loudly; unequipped trainee is a stable state), tier rules, denial
## codes, mid-run command determinism, and the to_dict/from_dict save
## round-trip with in-flight training timers and partial gear.
extends GdUnitTestSuite


# --- Fixtures (in-code content; same classes the .tres files use) ----------


func _metronome() -> EconomyTunables:
	# 1h interval, zero jitter: arrivals at exact ticks 61, 121, 181...
	# and NO rng draws anywhere (the deterministic backbone for tick math).
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_interval_hours = 1.0
	tunables.recruit_arrival_jitter_hours = 0.0
	return tunables


func _default_cadence() -> EconomyTunables:
	# R4 seed shape: 2h +/- 0.25h (the class defaults).
	return EconomyTunables.new()


func _def(id: StringName, training_hours: float, paths: Array) -> UnitDef:
	var def := UnitDef.new()
	def.id = id
	def.display_name = String(id).capitalize()
	def.training_time_hours = training_hours
	for path in paths:
		def.promotion_paths.append(path)
	def.face_id = StringName("face_%s" % id)
	return def


func _units() -> Array[UnitDef]:
	# The content-schema example chain: peasant → worker | militia →
	# trainee → knight | archer (0.5h / 2h / 4h / 12h / 6h).
	var defs: Array[UnitDef] = []
	var peasant := _def(&"peasant", 0.0, [&"worker", &"militia"])
	defs.append(peasant)
	var worker := _def(&"worker", 0.5, [])
	worker.can_work = true
	defs.append(worker)
	var militia := _def(&"militia", 2.0, [&"trainee"])
	militia.combat_power = 1
	militia.suspicion_on_train = 8
	defs.append(militia)
	var trainee := _def(&"trainee", 4.0, [&"knight", &"archer"])
	trainee.combat_power = 2
	defs.append(trainee)
	var knight := _def(&"knight", 12.0, [])
	knight.required_gear_slots.append(&"weapon")
	knight.required_gear_slots.append(&"armor")
	knight.combat_power = 10
	knight.suspicion_on_train = 8
	defs.append(knight)
	var archer := _def(&"archer", 6.0, [])
	archer.required_gear_slots.append(&"weapon")
	archer.combat_power = 6
	archer.suspicion_on_train = 4
	defs.append(archer)
	return defs


func _gear_def(id: StringName, slot: StringName, tier: int, combat: int, iron: int, timber: int) -> GearDef:
	var gear := GearDef.new()
	gear.id = id
	gear.display_name = String(id).capitalize()
	gear.slot = slot
	gear.tier = tier
	gear.combat_power = combat
	gear.recipe[&"iron"] = iron
	if timber > 0:
		gear.recipe[&"timber"] = timber
	gear.icon_id = StringName("icon_%s" % id)
	return gear


func _gear() -> Array[GearDef]:
	# Both slots x two tiers: t1 = the example pack recipes, t2 pricier
	# and stronger (tier data is recorded per unit for T-SIM-06 odds).
	var defs: Array[GearDef] = []
	defs.append(_gear_def(&"gear_weapon_t1", &"weapon", 1, 2, 10, 5))
	defs.append(_gear_def(&"gear_weapon_t2", &"weapon", 2, 4, 20, 10))
	defs.append(_gear_def(&"gear_armor_t1", &"armor", 1, 3, 15, 0))
	defs.append(_gear_def(&"gear_armor_t2", &"armor", 2, 6, 30, 0))
	return defs


func _engine(
	tunables: EconomyTunables = null,
	units: Array[UnitDef] = [],
	gear: Array[GearDef] = [],
	run_seed := 7,
	with_production := true
) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(UnitLifecycleSystem.new(
		units if not units.is_empty() else _units(),
		gear if not gear.is_empty() else _gear(),
		tunables if tunables != null else _metronome()
	))
	if with_production:
		var buildings: Array[BuildingDef] = []
		engine.register_system(ProductionSystem.new(buildings, EconomyTunables.new(), null))
	return engine


func _units_system(engine: SimEngine) -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


func _production(engine: SimEngine) -> ProductionSystem:
	return engine.get_system(&"production") as ProductionSystem


func _grant(engine: SimEngine, food: int, timber: int, iron: int) -> void:
	engine.set_resource(&"food", food)
	engine.set_resource(&"timber", timber)
	engine.set_resource(&"iron", iron)


func _events_of_type(engine: SimEngine, type: StringName) -> Array[Dictionary]:
	# Copy fields out of the pooled ring (references are slot-reuse-unsafe).
	var found: Array[Dictionary] = []
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			found.append({
				"tick": event.tick,
				"subject": event.subject,
				"value": event.value,
				"value2": event.value2,
			})
	return found


## Accepts the first pending offer and returns its uid (queued; applies on
## the next tick).
func _accept_first(engine: SimEngine) -> int:
	var offers := _units_system(engine).offer_ids()
	engine.submit_command(&"recruit_accept", &"", offers[0])
	return offers[0]


## Drives one recruit to a resting trainee under metronome timing and
## returns the uid. (accept+militia drain @62; 2h -> militia @181; trainee
## starts @182, 4h -> trainee @421. The tick-421 offer stays pending.)
func _trainee(engine: SimEngine) -> int:
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"militia", uid)
	engine.fast_forward(120)  # ticks 62..181
	engine.submit_command(&"start_training", &"trainee", uid)
	engine.fast_forward(240)  # ticks 182..421
	return uid


# --- Arrival cadence: seeded RNG, reproducibility, metronome ----------------


func test_arrival_sequence_reproducible_from_seed() -> void:
	# Identical seed -> identical (tick, uid) arrival sequence; a different
	# seed jitters to a different sequence. 48h at 2h +/- 0.25h.
	var collect := func(run_seed: int) -> Array:
		var engine := _engine(_default_cadence(), [], [], run_seed)
		engine.fast_forward(48 * SimEngine.TICKS_PER_SIM_HOUR)
		var sequence: Array = []
		for event in _events_of_type(engine, &"recruit_arrived"):
			sequence.append([event["tick"], event["value"]])
		return sequence

	var first: Array = collect.call(20260915)
	var second: Array = collect.call(20260915)
	assert_array(first).is_equal(second)
	assert_int(first.size()).is_greater(18)  # ~24 arrivals in 48h at ~2h
	assert_bool(first == collect.call(20260916)).is_false()


func test_zero_jitter_is_metronome_and_draws_nothing() -> void:
	# 1h interval, jitter 0: arrivals at exact ticks 61/121/181 (the first
	# tick schedules, then 60 decrements), and the engine RNG is never
	# drawn — rng.state is frozen (production draws nothing either).
	var engine := _engine(_metronome())
	var rng_state_before := engine.rng.state
	engine.fast_forward(190)
	var arrivals := _events_of_type(engine, &"recruit_arrived")
	assert_int(arrivals.size()).is_equal(3)
	assert_int(int(arrivals[0]["tick"])).is_equal(61)
	assert_int(int(arrivals[1]["tick"])).is_equal(121)
	assert_int(int(arrivals[2]["tick"])).is_equal(181)
	assert_int(engine.rng.state).is_equal(rng_state_before)


func test_jittered_cadence_moves_rng_deterministically() -> void:
	# Jitter consumes the stream (scheduling + one roll per arrival) and
	# stays reproducible: twin engines share rng.state after 10h.
	var engine := _engine(_default_cadence())
	var rng_state_before := engine.rng.state
	engine.fast_forward(10 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.rng.state).is_not_equal(rng_state_before)
	var twin := _engine(_default_cadence(), [], [], 7)
	twin.fast_forward(10 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(twin.rng.state).is_equal(engine.rng.state)


func test_offers_accumulate_as_a_stable_state() -> void:
	# A full gate is stable: nothing forces acceptance, no unit exists yet.
	var engine := _engine(_default_cadence())
	engine.fast_forward(10 * SimEngine.TICKS_PER_SIM_HOUR)
	var units := _units_system(engine)
	assert_int(units.total_units()).is_equal(0)
	assert_int(units.pending_offers()).is_greater_equal(4)  # 10h / 2.25h max interval
	assert_int(units.arrivals_total).is_equal(units.pending_offers())


# --- Recruit acceptance -------------------------------------------------------


func test_recruit_accept_creates_peasant_and_denies_unknown_offer() -> void:
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var units := _units_system(engine)
	var uid := _accept_first(engine)
	engine.submit_command(&"recruit_accept", &"", uid)  # stale: same uid queued twice
	engine.submit_command(&"recruit_accept", &"", 999)  # never existed
	engine.tick()
	assert_int(units.unit_count(&"peasant")).is_equal(1)
	assert_int(units.pending_offers()).is_equal(0)
	var accepted := _events_of_type(engine, &"recruit_accepted")
	assert_int(accepted.size()).is_equal(1)
	assert_int(int(accepted[0]["value"])).is_equal(uid)
	assert_int(int(accepted[0]["value2"])).is_equal(1)  # peasant count after
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(2)  # double-accept + unknown id
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_RECRUIT)
	assert_int(int(denied[1]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_RECRUIT)


# --- Worker branch: peasant → worker → production pool -----------------------


func test_worker_branch_full_chain_hands_off_to_production_pool() -> void:
	# Metronome math: accept + assign drain at tick 62; worker training is
	# 0.5h = 30 ticks -> completes AT tick 91; the add_worker handoff
	# command drains at tick 92 (commands are tick-aligned, never same-tick
	# from on_tick).
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"worker", uid)
	engine.tick()  # tick 62: accepted + training_started
	var units := _units_system(engine)
	assert_int(units.unit_count(&"peasant")).is_equal(1)
	assert_str(String(units.training_target(uid))).is_equal("worker")
	var started := _events_of_type(engine, &"training_started")
	assert_int(started.size()).is_equal(1)
	assert_int(int(started[0]["value2"])).is_equal(30_000)  # 30 ticks in milli-ticks
	engine.fast_forward(29)  # ticks 63..91
	assert_int(units.unit_count(&"worker")).is_equal(1)  # promoted at tick 91
	assert_str(String(units.training_target(uid))).is_equal("")
	var complete := _events_of_type(engine, &"training_complete")
	assert_int(complete.size()).is_equal(1)
	assert_int(int(complete[0]["tick"])).is_equal(91)
	assert_int(int(complete[0]["value2"])).is_equal(0)  # gear-free rank: auto-promoted
	assert_int(_events_of_type(engine, &"unit_promoted").size()).is_equal(1)
	# The handoff: identity stays HERE, the count lands in production one
	# tick later via the command queue.
	assert_int(_production(engine).idle_workers()).is_equal(0)
	engine.tick()  # tick 92: add_worker drains
	assert_int(_production(engine).idle_workers()).is_equal(1)
	assert_int(units.total_units()).is_equal(1)  # worker unit stays tracked


# --- Military branch: militia → trainee → knight / archer --------------------


func test_military_chain_to_knight_with_full_gear() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	assert_str(String(units.unit_def(uid))).is_equal("trainee")
	# Choose the branch, then gear up (gear binds to the current def or
	# the training target — same-tick FIFO order works).
	engine.submit_command(&"start_training", &"knight", uid)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.submit_command(&"equip_gear", &"gear_armor_t1", uid)
	engine.tick()  # started + equip x2 drain together
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(1)
	assert_int(units.gear_tier(uid, &"armor")).is_equal(1)
	engine.fast_forward(719)  # 12h = 720 ticks; started at 422 -> completes at 1141
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	assert_int(units.unit_count(&"knight")).is_equal(0)  # held: gear ranks need promote
	var completes := _events_of_type(engine, &"training_complete")
	var knight_completes := completes.filter(func(event): return event["subject"] == StringName(&"knight"))
	assert_int(knight_completes.size()).is_equal(1)  # militia/trainee completions came before
	assert_int(int(knight_completes[0]["value2"])).is_equal(1)  # held flag
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"knight")).is_equal(1)
	assert_str(String(units.unit_def(uid))).is_equal("knight")
	var promotions := _events_of_type(engine, &"unit_promoted")
	var knight_promotions := promotions.filter(func(event): return event["subject"] == StringName(&"knight"))
	assert_int(knight_promotions.size()).is_equal(1)
	# Army roster + power: knight 10 + weapon t1 (2) + armor t1 (3) = 15.
	assert_int(units.army_roster().size()).is_equal(1)
	assert_int(int(units.army_roster()[&"knight"])).is_equal(1)
	assert_int(units.army_power()).is_equal(15)
	# The worker seam is untouched by the military path.
	assert_int(_production(engine).idle_workers()).is_equal(0)


func test_military_chain_to_archer_weapon_only() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"archer", uid)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.fast_forward(6 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"archer")).is_equal(1)
	# Archer 6 + weapon t1 (2) = 8; armor was never required.
	assert_int(units.army_power()).is_equal(8)
	assert_int(units.gear_tier(uid, &"armor")).is_equal(0)
	assert_int(units.missing_gear_slots(uid).size()).is_equal(0)


func test_training_progress_events_fire_at_quarters() -> void:
	# Militia 2h: quarter thresholds at 30/60/90 ticks of training -> three
	# progress events (250/500/750 permille) strictly before completion.
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"militia", uid)
	engine.fast_forward(120)
	var progress := _events_of_type(engine, &"training_progress")
	assert_int(progress.size()).is_equal(3)
	assert_int(int(progress[0]["value2"])).is_equal(250)
	assert_int(int(progress[1]["value2"])).is_equal(500)
	assert_int(int(progress[2]["value2"])).is_equal(750)
	for event in progress:
		assert_int(int(event["tick"])).is_less(181)  # strictly before completion
	# Short trainings emit them too: worker 0.5h still crosses 25/50/75%.
	var worker_engine := _engine(_metronome())
	worker_engine.fast_forward(61)
	var worker_uid := _accept_first(worker_engine)
	worker_engine.submit_command(&"assign_role", &"worker", worker_uid)
	worker_engine.fast_forward(30)
	assert_int(_events_of_type(worker_engine, &"training_progress").size()).is_equal(3)


func test_zero_hour_training_promotes_within_the_same_drain() -> void:
	# A 0h target (content edge) completes immediately at command drain:
	# started + complete + promoted all in one tick.
	var units: Array[UnitDef] = [
		_def(&"peasant", 0.0, [&"instant"]),
		_def(&"instant", 0.0, []),
	]
	var engine := _engine(_metronome(), units, _gear())
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"instant", uid)
	engine.tick()
	assert_int(_units_system(engine).unit_count(&"instant")).is_equal(1)
	assert_int(_events_of_type(engine, &"training_started").size()).is_equal(1)
	assert_int(_events_of_type(engine, &"training_complete").size()).is_equal(1)
	assert_int(_events_of_type(engine, &"unit_promoted").size()).is_equal(1)


# --- Gear gating: loud refusal, stable waiting, tier rules -------------------


func test_promote_without_gear_refused_loudly() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.fast_forward(12 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	# No gear at all: refused, state intact.
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_GEAR_INCOMPLETE)
	assert_int(int(denied[0]["value2"])).is_equal(uid)
	assert_int(units.unit_count(&"knight")).is_equal(0)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	# Partial gear (weapon only): still refused.
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(_events_of_type(engine, &"lifecycle_denied").size()).is_equal(2)
	assert_int(units.unit_count(&"knight")).is_equal(0)
	# Armor completes the requirement: promote succeeds.
	engine.submit_command(&"equip_gear", &"gear_armor_t1", uid)
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"knight")).is_equal(1)


func test_promote_with_incomplete_training_refused() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.submit_command(&"equip_gear", &"gear_armor_t1", uid)
	engine.tick()
	engine.fast_forward(11 * SimEngine.TICKS_PER_SIM_HOUR)  # 11 of 12h
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_TRAINING_INCOMPLETE)
	assert_int(units.unit_count(&"knight")).is_equal(0)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # the last hour
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"knight")).is_equal(1)


func test_unequipped_trainee_waiting_for_gear_is_stable() -> void:
	# The held state is a resting state, not an error: 500 ticks of waiting
	# changes nothing about the unit, emits no spurious lifecycle events
	# for it, and the promote path still works afterwards.
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"archer", uid)
	engine.fast_forward(6 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	engine.fast_forward(500)
	assert_str(String(units.unit_def(uid))).is_equal("trainee")
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	assert_int(units.training_progress_milli(uid)).is_equal(units.training_duration_milli(&"archer"))
	# Exactly one archer-target completion, zero archer promotions (the
	# militia/trainee auto-promotions earlier in the chain don't count).
	var completes := _events_of_type(engine, &"training_complete")
	var archer_completes := completes.filter(func(event): return event["subject"] == StringName(&"archer"))
	assert_int(archer_completes.size()).is_equal(1)
	var promotions := _events_of_type(engine, &"unit_promoted")
	var archer_promotions := promotions.filter(func(event): return event["subject"] == StringName(&"archer"))
	assert_int(archer_promotions.size()).is_equal(0)
	assert_int(_events_of_type(engine, &"lifecycle_denied").size()).is_equal(0)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"archer")).is_equal(1)


func test_equip_gear_pays_recipe_all_or_nothing() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.tick()
	# weapon t1 costs 10 iron + 5 timber: one iron short -> nothing deducted.
	_grant(engine, 100, 5, 9)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.tick()
	assert_int(engine.get_resource(&"iron")).is_equal(9)
	assert_int(engine.get_resource(&"timber")).is_equal(5)
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(0)
	assert_int(_events_of_type(engine, &"lifecycle_denied").size()).is_equal(1)
	# Exact funds: pays to zero, equips, event carries the tier.
	_grant(engine, 100, 5, 10)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.tick()
	assert_int(engine.get_resource(&"iron")).is_equal(0)
	assert_int(engine.get_resource(&"timber")).is_equal(0)
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(1)
	var equipped := _events_of_type(engine, &"gear_equipped")
	assert_int(equipped.size()).is_equal(1)
	assert_int(int(equipped[0]["value2"])).is_equal(1)


func test_equip_tier_upgrade_replaces_and_rejects_lower_or_equal() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.tick()
	# Same tier again: refused (not an upgrade).
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_SLOT_OCCUPIED)
	# Strictly higher tier: replaces (full recipe paid again), tier recorded.
	engine.submit_command(&"equip_gear", &"gear_weapon_t2", uid)
	engine.tick()
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(2)
	assert_int(engine.get_resource(&"iron")).is_equal(100 - 10 - 20)
	# Downgrade after upgrade: refused.
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.tick()
	assert_int(_events_of_type(engine, &"lifecycle_denied").size()).is_equal(2)
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(2)


func test_equip_slot_rules_and_denial_codes() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.tick()  # peasant exists, no training target
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)  # peasant needs no weapon
	engine.submit_command(&"equip_gear", &"gear_ghost", uid)  # unknown gear
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", 999)  # unknown unit
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(3)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_SLOT_NOT_NEEDED)
	assert_int(int(denied[1]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_GEAR)
	assert_int(int(denied[2]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_UNIT)
	# Archer-target trainee: armor is not in the archer's requirements.
	var archer_engine := _engine(_metronome())
	_grant(archer_engine, 100, 100, 100)
	var archer_uid := _trainee(archer_engine)
	archer_engine.submit_command(&"start_training", &"archer", archer_uid)
	archer_engine.submit_command(&"equip_gear", &"gear_armor_t1", archer_uid)
	archer_engine.tick()
	var archer_denied := _events_of_type(archer_engine, &"lifecycle_denied")
	assert_int(archer_denied.size()).is_equal(1)
	assert_int(int(archer_denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_SLOT_NOT_NEEDED)


func test_equipping_during_training_is_allowed() -> void:
	# Gear may land before, during or after training — only the promote
	# gate is strict. Fully-geared + complete promotes right after the
	# held transition.
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.tick()
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.submit_command(&"equip_gear", &"gear_armor_t1", uid)
	engine.fast_forward(12 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()
	engine.submit_command(&"promote", &"", uid)
	engine.tick()
	assert_int(units.unit_count(&"knight")).is_equal(1)


# --- Command surface hygiene ---------------------------------------------------


func test_assign_and_start_denial_codes() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.tick()
	engine.submit_command(&"assign_role", &"knight", uid)  # not in peasant's paths
	engine.submit_command(&"assign_role", &"ghost", uid)  # unknown def
	engine.submit_command(&"assign_role", &"militia", 999)  # unknown unit
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(3)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_INVALID_TARGET)
	assert_int(int(denied[1]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_TARGET)
	assert_int(int(denied[2]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_UNIT)
	# Busy units: already training / promote before completion.
	engine.submit_command(&"assign_role", &"militia", uid)
	engine.tick()
	engine.submit_command(&"assign_role", &"worker", uid)  # mid-training reassign
	engine.submit_command(&"promote", &"", uid)  # and promote before completion
	engine.tick()
	denied = _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(5)
	assert_int(int(denied[3]["value"])).is_equal(UnitLifecycleSystem.REASON_ALREADY_TRAINING)
	assert_int(int(denied[4]["value"])).is_equal(UnitLifecycleSystem.REASON_TRAINING_INCOMPLETE)


func test_promote_denies_resting_and_unknown_units() -> void:
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.tick()
	engine.submit_command(&"promote", &"", uid)  # resting peasant: nothing to promote
	engine.submit_command(&"promote", &"", 999)  # unknown unit
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(2)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_NOT_AWAITING_PROMOTION)
	assert_int(int(denied[1]["value"])).is_equal(UnitLifecycleSystem.REASON_UNKNOWN_UNIT)


func test_awaiting_unit_cannot_start_new_training() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 100, 100, 100)
	var uid := _trainee(engine)
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"knight", uid)
	engine.fast_forward(12 * SimEngine.TICKS_PER_SIM_HOUR)
	engine.submit_command(&"start_training", &"archer", uid)  # committed to knight
	engine.tick()
	var denied := _events_of_type(engine, &"lifecycle_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(UnitLifecycleSystem.REASON_AWAITING_PROMOTION)
	assert_bool(units.is_awaiting_promotion(uid)).is_true()


func test_commands_queue_until_tick_start() -> void:
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var units := _units_system(engine)
	_accept_first(engine)
	assert_int(units.total_units()).is_equal(0)  # queued, not applied
	engine.tick()
	assert_int(units.unit_count(&"peasant")).is_equal(1)


func test_pause_freezes_training_and_arrivals() -> void:
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"militia", uid)
	engine.tick()
	engine.fast_forward(30)  # ticks 63..92: 31 ticks of the 2h militia training
	var units := _units_system(engine)
	var progress := units.training_progress_milli(uid)
	assert_int(progress).is_equal(31_000)  # tick 62 (start) + 30 more
	engine.pause()
	assert_bool(engine.tick()).is_false()
	assert_int(engine.fast_forward(600)).is_equal(0)
	assert_int(units.training_progress_milli(uid)).is_equal(progress)
	assert_int(units.pending_offers()).is_equal(0)  # gate frozen too
	engine.resume()
	engine.fast_forward(90)  # remaining training + buffer
	assert_str(String(units.unit_def(uid))).is_equal("militia")


# --- Determinism: mid-run command scripts, hash sensitivity -------------------


func test_midrun_script_determinism_checkpoints() -> void:
	# Identical seed + identical command script at identical tick
	# boundaries -> identical hash at every checkpoint (the T-SIM-01
	# oracle extended through the whole lifecycle, jittered cadence
	# included — the RNG stream itself is part of the state).
	var script := func(engine: SimEngine) -> Array:
		var checkpoints: Array = []
		_grant(engine, 100, 100, 100)
		engine.fast_forward(200)
		var units := _units_system(engine)
		for offer in units.offer_ids():
			engine.submit_command(&"recruit_accept", &"", offer)
		engine.fast_forward(2)
		var militia_uid: int = units.idle_units(&"peasant")[0]
		engine.submit_command(&"assign_role", &"militia", militia_uid)
		engine.fast_forward(150)
		checkpoints.append(engine.state_hash())
		engine.submit_command(&"start_training", &"trainee", militia_uid)
		engine.fast_forward(300)
		engine.submit_command(&"equip_gear", &"gear_weapon_t1", militia_uid)
		engine.submit_command(&"start_training", &"archer", militia_uid)
		engine.fast_forward(60)
		checkpoints.append(engine.state_hash())
		# Deterministic denials on the same path: armor not needed for the
		# archer target; promote while training is still incomplete.
		engine.submit_command(&"equip_gear", &"gear_armor_t1", militia_uid)
		engine.submit_command(&"promote", &"", militia_uid)
		engine.fast_forward(400)
		checkpoints.append(engine.state_hash())
		return checkpoints

	var first: Array = script.call(_engine(_default_cadence(), [], [], 20260915))
	var second: Array = script.call(_engine(_default_cadence(), [], [], 20260915))
	assert_array(first).is_equal(second)
	assert_int(int(first[0])).is_not_equal(int(first[2]))  # the script moved the state


func test_state_hash_separates_training_gear_and_awaiting() -> void:
	var make := func(equip: bool, promote_now: bool) -> int:
		var engine := _engine(_metronome())
		_grant(engine, 100, 100, 100)
		var uid := _trainee(engine)
		engine.submit_command(&"start_training", &"archer", uid)
		if equip:
			engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
		engine.fast_forward(6 * SimEngine.TICKS_PER_SIM_HOUR)
		if promote_now and equip:
			engine.submit_command(&"promote", &"", uid)
			engine.tick()
		return _units_system(engine).state_hash()

	var bare: int = make.call(false, false)  # held, no gear
	var armed: int = make.call(true, false)  # held, weapon on
	var promoted: int = make.call(true, true)  # promoted archer
	assert_int(bare).is_not_equal(armed)
	assert_int(armed).is_not_equal(promoted)


# --- Save round-trip: in-flight timers, partial gear, arrival stream ---------


func test_save_round_trip_with_inflight_training_and_partial_gear() -> void:
	var original := _engine(_metronome())
	_grant(original, 100, 100, 100)
	var uid := _trainee(original)
	original.submit_command(&"start_training", &"knight", uid)
	original.tick()  # drain: training_started at tick 422
	original.submit_command(&"equip_gear", &"gear_weapon_t1", uid)  # partial gear
	original.tick()  # equipped at 423
	original.fast_forward(298)  # tick 721: exactly 300 ticks of training elapsed
	var units := _units_system(original)
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(1)
	assert_int(units.training_progress_milli(uid)).is_equal(300_000)

	var captured := original.to_dict()
	var system_state: Dictionary = captured["systems"]["units"]
	assert_int((system_state["units"] as Array).size()).is_equal(1)
	var saved_unit: Dictionary = system_state["units"][0]
	assert_int(int(saved_unit["progress"])).is_equal(300_000)
	assert_int((saved_unit["gear"] as Dictionary).size()).is_equal(1)

	var restored := _engine(_metronome())
	assert_bool(restored.apply_state_dict(captured)).is_true()
	assert_int(restored.state_hash()).is_equal(original.state_hash())
	var restored_units := _units_system(restored)
	assert_int(restored_units.gear_tier(uid, &"weapon")).is_equal(1)
	assert_int(restored_units.training_progress_milli(uid)).is_equal(300_000)
	# Lockstep: the timer completes on the SAME tick on both engines, the
	# promote works after restore, and hashes stay equal throughout.
	var remaining: int = 12 * SimEngine.TICKS_PER_SIM_HOUR - 300 + 1
	original.fast_forward(remaining)
	restored.fast_forward(remaining)
	assert_int(restored.state_hash()).is_equal(original.state_hash())
	var engines: Array[SimEngine] = [original, restored]
	for engine in engines:
		engine.submit_command(&"equip_gear", &"gear_armor_t1", uid)
		engine.submit_command(&"promote", &"", uid)
		engine.tick()
	assert_int(_units_system(original).unit_count(&"knight")).is_equal(1)
	assert_int(_units_system(restored).unit_count(&"knight")).is_equal(1)
	assert_int(restored.state_hash()).is_equal(original.state_hash())


func test_round_trip_preserves_arrival_stream() -> void:
	# The countdown + rng.state cross the save boundary: post-restore
	# arrivals land on identical ticks (jittered cadence included).
	var original := _engine(_default_cadence())
	original.fast_forward(137)  # mid-countdown or just after the first arrival
	var captured := original.to_dict()
	var restored := _engine(_default_cadence())
	assert_bool(restored.apply_state_dict(captured)).is_true()
	original.fast_forward(500)
	restored.fast_forward(500)
	assert_int(original.state_hash()).is_equal(restored.state_hash())
	assert_int(_units_system(restored).arrivals_total).is_equal(_units_system(original).arrivals_total)


func test_from_dict_handles_missing_defs_and_gear_loudly() -> void:
	var original := _engine(_metronome())
	_grant(original, 100, 100, 100)
	var knight_uid := _trainee(original)  # tick 421; arrivals 121..421 stay pending
	original.submit_command(&"start_training", &"knight", knight_uid)
	original.submit_command(&"equip_gear", &"gear_weapon_t1", knight_uid)
	original.submit_command(&"equip_gear", &"gear_armor_t1", knight_uid)
	original.fast_forward(30)  # ticks 422..451, training in flight
	var captured := original.to_dict()

	# Reduced pack: no knight def, no armor gear. The trainee def is known,
	# so the unit survives — but its knight training target and its armor
	# are dropped loudly, and the engine keeps ticking.
	var reduced_units: Array[UnitDef] = []
	for def in _units():
		if def.id != &"knight":
			def.promotion_paths = def.promotion_paths.filter(func(path): return path != &"knight")
			reduced_units.append(def)
	var reduced_gear: Array[GearDef] = []
	for gear in _gear():
		if gear.slot != &"armor":
			reduced_gear.append(gear)
	var restored := _engine(_metronome(), reduced_units, reduced_gear)
	assert_bool(restored.apply_state_dict(captured)).is_true()
	var restored_units := _units_system(restored)
	assert_int(restored_units.total_units()).is_equal(1)
	assert_str(String(restored_units.unit_def(knight_uid))).is_equal("trainee")
	assert_str(String(restored_units.training_target(knight_uid))).is_equal("")
	assert_int(restored_units.gear_tier(knight_uid, &"weapon")).is_equal(1)  # known gear kept
	assert_int(restored_units.gear_tier(knight_uid, &"armor")).is_equal(0)  # unknown gear dropped
	assert_int(restored_units.pending_offers()).is_equal(6)  # offers carry no defs
	restored.fast_forward(120)  # no crash on the dropped training
	assert_str(String(restored_units.unit_def(knight_uid))).is_equal("trainee")

	# A pack missing the unit's own def skips it wholesale (loudly).
	var no_trainee: Array[UnitDef] = []
	for def in _units():
		if def.id != &"trainee" and def.id != &"knight":
			def.promotion_paths = def.promotion_paths.filter(func(path): return path != &"trainee")
			no_trainee.append(def)
	var stranger := _engine(_metronome(), no_trainee, reduced_gear)
	assert_bool(stranger.apply_state_dict(captured)).is_true()
	assert_int(_units_system(stranger).total_units()).is_equal(0)
	assert_int(_units_system(stranger).pending_offers()).is_equal(6)


# --- Queries: counts, roster, power, base-unit detection ----------------------


func test_counts_roster_and_power_queries() -> void:
	var engine := _engine(_metronome())
	_grant(engine, 1000, 1000, 1000)
	# Three recruits on the military path: one STAYS militia, one branches
	# archer (t1 weapon), one branches knight (t2 gear).
	engine.fast_forward(61)
	var first := _accept_first(engine)
	engine.fast_forward(60)
	var second := _accept_first(engine)
	engine.fast_forward(60)
	var third := _accept_first(engine)
	engine.submit_command(&"assign_role", &"militia", first)  # stays militia
	engine.submit_command(&"assign_role", &"militia", second)
	engine.submit_command(&"assign_role", &"militia", third)
	engine.tick()  # tick 182: third accept + all three militia assignments
	engine.fast_forward(120)  # militia promoted at 301
	var units := _units_system(engine)
	engine.submit_command(&"start_training", &"trainee", second)
	engine.submit_command(&"start_training", &"trainee", third)
	engine.fast_forward(240)  # trainees at 542
	engine.submit_command(&"start_training", &"archer", second)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", second)
	engine.submit_command(&"start_training", &"knight", third)
	engine.submit_command(&"equip_gear", &"gear_weapon_t2", third)
	engine.submit_command(&"equip_gear", &"gear_armor_t2", third)
	engine.fast_forward(12 * SimEngine.TICKS_PER_SIM_HOUR)
	engine.submit_command(&"promote", &"", second)
	engine.submit_command(&"promote", &"", third)
	engine.tick()
	assert_int(units.unit_count(&"militia")).is_equal(1)
	assert_int(units.unit_count(&"archer")).is_equal(1)
	assert_int(units.unit_count(&"knight")).is_equal(1)
	assert_int(units.total_units()).is_equal(3)
	# Roster: terminal combat units only — militia/trainee excluded.
	assert_int(units.army_roster().size()).is_equal(2)
	assert_int(int(units.army_roster()[&"archer"])).is_equal(1)
	assert_int(int(units.army_roster()[&"knight"])).is_equal(1)
	# Archer 6 + weapon t1 (2); knight 10 + weapon t2 (4) + armor t2 (6).
	assert_int(units.army_power()).is_equal(8 + 20)
	var weapon_options := units.gear_ids_for_slot(&"weapon")
	assert_int(weapon_options.size()).is_equal(2)
	assert_str(String(weapon_options[0])).is_equal("gear_weapon_t1")  # lowest tier first
	assert_str(String(weapon_options[1])).is_equal("gear_weapon_t2")


func test_base_unit_autodetected_and_overridable() -> void:
	# Default: peasant is the unique root (no other def promotes into it).
	var engine := _engine(_metronome())
	engine.fast_forward(61)
	_accept_first(engine)
	engine.tick()
	assert_int(_units_system(engine).unit_count(&"peasant")).is_equal(1)

	# Two roots: the explicit constructor param wins over the ambiguity.
	var roots: Array[UnitDef] = [
		_def(&"peasant_a", 0.0, [&"worker"]),
		_def(&"peasant_b", 0.0, [&"worker"]),
		_def(&"worker", 0.5, []),
	]
	roots[2].can_work = true
	var override := SimEngine.new(7)
	override.register_system(HeartbeatSystem.new())
	override.register_system(UnitLifecycleSystem.new(roots, _gear(), _metronome(), &"peasant_b"))
	override.fast_forward(61)
	var offers := _units_system(override).offer_ids()
	override.submit_command(&"recruit_accept", &"", offers[0])
	override.tick()
	assert_int(_units_system(override).unit_count(&"peasant_b")).is_equal(1)
	assert_int(_units_system(override).unit_count(&"peasant_a")).is_equal(0)


func test_worker_handoff_without_production_is_loud_not_fatal() -> void:
	# The handoff command simply has no handler without production: it is
	# recorded as command_rejected (loud, deterministic) — never a crash.
	var engine := _engine(_metronome(), _units(), _gear(), 7, false)
	engine.fast_forward(61)
	var uid := _accept_first(engine)
	engine.submit_command(&"assign_role", &"worker", uid)
	engine.fast_forward(32)
	assert_int(_units_system(engine).unit_count(&"worker")).is_equal(1)
	assert_int(_events_of_type(engine, &"command_rejected").size()).is_equal(1)
