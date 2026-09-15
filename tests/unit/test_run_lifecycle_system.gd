## Unit tests for the run lifecycle system (T-SIM-04).
## Mirrors sim/systems/run_lifecycle_system.gd + sim/run_meta.gd
## (test-mapping rule). Hawkeye seam coverage: identity/regime generation
## determinism (same seed -> same identity, rng stream consumed at the
## documented draw order), the 100-leader variety acceptance, victory +
## failure + abort banking (failure banks FULL progress), the restart reset
## contract (fresh identity, emptied run-scoped state, regime keep/redraw
## rule), the meta-domain separation (chronicle + bank survive restart via
## RunMeta, never via the engine save), and the to_dict/from_dict round-trip.
extends GdUnitTestSuite


const RUN_SEED := 20260915


# --- Fixtures (in-code content; same classes the .tres files use) ----------


func _tunables() -> EconomyTunables:
	# Metronome arrivals (jitter 0): the units system draws NOTHING from the
	# rng, so the run system's generation draws are the only stream consumers.
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_jitter_hours = 0.0
	return tunables


func _identity() -> IdentityPools:
	# The example-pack pools (8 x 8 x 6 x 12 — the validator's variety floors).
	var pools := IdentityPools.new()
	pools.leader_first_names = [
		"Bran", "Ottilie", "Wick", "Mabel", "Godfrey", "Petronella", "Aldous", "Sybil",
	]
	pools.leader_epithets = [
		"the Unbearable", "the Almost Wise", "of the Leaky Barn", "the Twice-Fooled",
		"the Modest Avalanche", "of Fine Debt", "the Whispering Shout", "the Patient Torch",
	]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous", &"paranoid", &"romantic", &"vengeful"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick", "Bess", "Gil", "Meg", "Ralph", "Joan", "Sim"]
	return pools


func _regime(
	id: StringName,
	combat_kind: StringName,
	combat_value: float,
	quirk_kind: StringName,
	quirk_target: StringName,
	quirk_value: float
) -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = id
	regime.display_name = "Regime %s" % id
	var combat := RegimeModifier.new()
	combat.kind = combat_kind
	combat.value = combat_value
	regime.combat_modifier = combat
	var quirk := RegimeModifier.new()
	quirk.kind = quirk_kind
	quirk.target = quirk_target
	quirk.value = quirk_value
	regime.economy_quirk = quirk
	return regime


func _regimes() -> Array[RegimeDef]:
	# The 4 MVP flavors: distinct combat modifiers + distinct economy quirks.
	var regimes: Array[RegimeDef] = [
		_regime(&"gilded_crown", &"garrison_multiplier", 1.2, &"production_multiplier", &"timber", 0.85),
		_regime(&"iron_rotunda", &"army_score_multiplier", 1.1, &"building_cost_multiplier", &"all", 1.2),
		_regime(&"velvet_fist", &"garrison_multiplier", 0.9, &"production_multiplier", &"all", 1.15),
		_regime(&"paper_crown", &"army_score_multiplier", 0.95, &"building_cost_multiplier", &"timber", 0.75),
	]
	return regimes


func _camp() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"camp"
	def.display_name = "Lumber Camp"
	def.resource_produced = &"timber"
	def.base_production_per_worker_hour = 6.0
	def.worker_slots_base = 2
	var cost: Dictionary[StringName, int] = {}
	cost[&"food"] = 10
	def.base_cost = cost
	def.cost_growth = 1.10
	var milestones: Array[int] = [10, 20]
	def.milestone_levels = milestones
	def.max_level = 30
	return def


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
	var milestones: Array[int] = [10, 20]
	def.milestone_levels = milestones
	def.max_level = 30
	return def


func _unit_defs() -> Array[UnitDef]:
	# The content-schema example chain (peasant -> worker|militia -> trainee
	# -> knight|archer) — the army_roster/army_power read seam for scoring.
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


func _gear_defs() -> Array[GearDef]:
	var defs: Array[GearDef] = []
	var weapon := GearDef.new()
	weapon.id = &"gear_weapon_t1"
	weapon.display_name = "Borrowed Sword"
	weapon.slot = &"weapon"
	weapon.tier = 1
	weapon.combat_power = 2
	weapon.recipe[&"iron"] = 10
	weapon.recipe[&"timber"] = 5
	defs.append(weapon)

	var armor := GearDef.new()
	armor.id = &"gear_armor_t1"
	armor.display_name = "Padded Jack"
	armor.slot = &"armor"
	armor.tier = 1
	armor.combat_power = 3
	armor.recipe[&"iron"] = 15
	defs.append(armor)
	return defs


## Full-stack engine (heartbeat, run, units, production) — the registration
## order mirrors causality: the run frame exists before recruits/economy,
## and run commands dispatch before the systems they orchestrate.
func _engine(p_run_seed: int = RUN_SEED, p_meta: RunMeta = null) -> SimEngine:
	return _engine_with(_regimes(), _identity(), p_run_seed, p_meta)


func _engine_with(
	p_regimes: Array[RegimeDef],
	p_identity: IdentityPools,
	p_run_seed: int,
	p_meta: RunMeta = null
) -> SimEngine:
	var engine := SimEngine.new(p_run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(p_regimes, p_identity, p_meta))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), _tunables()))
	engine.register_system(ProductionSystem.new([_farm(), _camp()], _tunables(), null))
	return engine


func _run(engine: SimEngine) -> RunLifecycleSystem:
	return engine.get_system(&"run") as RunLifecycleSystem


func _units_system(engine: SimEngine) -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


func _production(engine: SimEngine) -> ProductionSystem:
	return engine.get_system(&"production") as ProductionSystem


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


## Starts a run and advances one tick so the command drains.
func _start(engine: SimEngine) -> RunLifecycleSystem:
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	return _run(engine)


## The full generated identity tuple (for equality/diversity assertions).
func _identity_tuple(run: RunLifecycleSystem) -> Dictionary:
	return {
		"first": run.leader_first_name(),
		"epithet": run.leader_epithet(),
		"tags": run.leader_tags(),
		"trait": run.leader_trait_stub(),
		"regime": run.regime_id(),
	}


# --- Generation: identity + regime --------------------------------------------


func test_run_start_generates_identity_and_regime() -> void:
	var engine := _engine()
	var run := _start(engine)
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_RUNNING)
	assert_bool(run.is_running()).is_true()
	assert_int(run.current_run_index()).is_equal(1)
	assert_int(run.run_start_tick()).is_equal(1)  # drained at the first tick
	# Name: a pool first name + a pool epithet, joined.
	var pools := _identity()
	assert_that(pools.leader_first_names.has(run.leader_first_name())).is_true()
	assert_that(pools.leader_epithets.has(run.leader_epithet())).is_true()
	assert_str(run.leader_name()).is_equal("%s %s" % [run.leader_first_name(), run.leader_epithet()])
	# Tags: two DISTINCT personality tags from the pool.
	var tags := run.leader_tags()
	assert_int(tags.size()).is_equal(2)
	assert_str(String(tags[0])).is_not_equal(String(tags[1]))
	assert_that(pools.personality_tags.has(tags[0])).is_true()
	assert_that(pools.personality_tags.has(tags[1])).is_true()
	# Trait stub: index in range, label renders.
	assert_that(run.leader_trait_stub() >= 0 and run.leader_trait_stub() < RunLifecycleSystem.TRAIT_STUB_LABELS.size()).is_true()
	assert_str(run.leader_trait_label()).is_equal(RunLifecycleSystem.TRAIT_STUB_LABELS[run.leader_trait_stub()])
	# Regime: one of the 4 flavors, exposed for later systems to read.
	assert_that(run.current_regime() != null).is_true()
	var ids: Array[StringName] = []
	for regime in _regimes():
		ids.append(regime.id)
	assert_that(ids.has(run.regime_id())).is_true()
	assert_str(String(run.current_regime().display_name)).is_not_empty()
	# Event: run_started carries the regime id + run index.
	var started := _events_of_type(engine, &"run_started")
	assert_int(started.size()).is_equal(1)
	assert_str(String(started[0]["subject"])).is_equal(String(run.regime_id()))
	assert_int(int(started[0]["value"])).is_equal(1)


func test_generation_is_deterministic_from_seed() -> void:
	# Same seed + same command timing -> identical identity AND identical
	# rng stream (the draws are the only consumers under metronome arrivals).
	var first := _start(_engine(RUN_SEED))
	var second := _start(_engine(RUN_SEED))
	assert_dict(_identity_tuple(first)).is_equal(_identity_tuple(second))
	assert_int(first.meta.runs_recorded).is_equal(0)  # starting banks nothing
	var a := _engine(RUN_SEED)
	var b := _engine(RUN_SEED)
	_start(a)
	_start(b)
	assert_int(a.rng.state).is_equal(b.rng.state)
	# A different seed (almost surely) rolls a different identity.
	var other := _start(_engine(RUN_SEED + 1))
	assert_bool(_identity_tuple(first) == _identity_tuple(other)).is_false()


func test_run_start_denied_once_started_or_ended() -> void:
	var engine := _engine()
	var run := _start(engine)
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	var denied := _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(RunLifecycleSystem.REASON_ALREADY_STARTED)
	assert_int(run.current_run_index()).is_equal(1)
	# After an ended run, run_start is STILL refused — run_restart is the fold.
	run.resolve_victory(engine, true, 0)
	engine.tick()
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	denied = _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(2)
	assert_int(int(denied[1]["value"])).is_equal(RunLifecycleSystem.REASON_ALREADY_STARTED)


func test_run_start_refused_without_content() -> void:
	var engine := _engine_with([], _identity(), RUN_SEED)
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	var denied := _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(RunLifecycleSystem.REASON_NO_CONTENT)
	assert_int(_run(engine).run_status()).is_equal(RunLifecycleSystem.STATUS_UNSTARTED)
	# Missing identity pools are refused identically (fresh engine: no pools).
	var no_pools := _engine_with(_regimes(), null, RUN_SEED)
	no_pools.submit_command(&"run_start", &"", 0)
	no_pools.tick()
	assert_int(_events_of_type(no_pools, &"run_denied").size()).is_equal(1)


func test_generated_regime_applies_to_production_quirk() -> void:
	# T-SIM-02's handoff seam: production is constructed BEFORE the regime
	# exists; run_start applies the drawn economy quirk at the same drain.
	# Single-flavor pack pins the draw to the timber x0.85 quirk.
	var regime := _regimes()[0]
	var pinned: Array[RegimeDef] = [regime]
	var engine := _engine_with(pinned, _identity(), RUN_SEED)
	engine.set_resource(&"food", 100)
	engine.submit_command(&"upgrade_building", &"camp", 0)
	engine.tick()  # camp built; no run yet -> no quirk
	assert_int(_production(engine).production_rate_milli_per_worker(&"camp")).is_equal(6000)
	var run := _start(engine)  # run_start drains; quirk applied synchronously
	assert_str(String(run.regime_id())).is_equal("gilded_crown")
	# 6/h x 0.85 = 5.1/h exactly in milli (single SimFixed boundary).
	assert_int(_production(engine).production_rate_milli_per_worker(&"camp")).is_equal(5100)


func test_resolve_victory_win_banks_chronicle_and_event() -> void:
	var engine := _engine()
	var run := _start(engine)  # start_tick == 1
	engine.fast_forward(599)  # tick_count == 600
	assert_bool(run.resolve_victory(engine, true, 42)).is_true()
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_RUNNING)  # tick-aligned: not yet
	engine.tick()  # drains at tick 601: duration 600 = 10h
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_VICTORY)
	# Thin score stub: 10h + army 42 + win bonus 100 = 152.
	assert_int(run.last_run_score()).is_equal(152)
	assert_int(run.meta.legacy_points).is_equal(152)
	assert_int(run.meta.runs_recorded).is_equal(1)
	assert_int(run.meta.chronicle.size()).is_equal(1)
	var entry: Dictionary = run.meta.chronicle[0]
	assert_int(int(entry["run"])).is_equal(1)
	assert_str(String(entry["leader"])).is_equal(run.leader_name())
	assert_str(String(entry["regime"])).is_equal(String(run.regime_id()))
	assert_str(String(entry["outcome"])).is_equal("victory")
	assert_int(int(entry["duration_ticks"])).is_equal(600)
	assert_int(int(entry["army_power"])).is_equal(42)
	assert_int(int(entry["score"])).is_equal(152)
	# Event: run_won carries the banked score + run index.
	var won := _events_of_type(engine, &"run_won")
	assert_int(won.size()).is_equal(1)
	assert_int(int(won[0]["value"])).is_equal(152)
	assert_int(int(won[0]["value2"])).is_equal(1)


func test_resolve_victory_loss_banks_full_progress() -> void:
	# Failure banks FULL progress (town-hall decision): no win bonus, but
	# duration + army still accrue. Explicit surrender/abort is the other
	# thin failure path; the assault LOSS lands here too (T-SIM-06's call).
	var engine := _engine()
	var run := _start(engine)
	engine.fast_forward(120)  # tick 121
	assert_bool(run.resolve_victory(engine, false, 8)).is_true()
	engine.tick()  # drains at tick 122: duration 121 = 2h
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_DEFEAT)
	assert_int(run.last_run_score()).is_equal(10)  # 2h + 8 power, no bonus
	assert_int(run.meta.legacy_points).is_equal(10)
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("defeat")
	assert_int(_events_of_type(engine, &"run_lost").size()).is_equal(1)
	assert_int(_events_of_type(engine, &"run_won").size()).is_equal(0)


func test_resolve_victory_reads_army_power_when_not_overridden() -> void:
	# -1 (default) reads the units system's live army_power at drain.
	var engine := _engine()
	var run := _start(engine)
	engine.fast_forward(60)
	var units := _units_system(engine)
	assert_int(units.army_power()).is_equal(0)  # no army yet — power 0 path
	run.resolve_victory(engine, true)
	engine.tick()
	assert_int(run.last_run_score()).is_equal(1 + RunLifecycleSystem.WIN_BONUS)  # 1h + 0 + bonus


func test_resolve_victory_refused_when_no_run_active() -> void:
	var engine := _engine()
	var run := _run(engine)
	assert_bool(run.resolve_victory(engine, true, 0)).is_false()  # unstarted
	engine.submit_command(&"resolve_victory", &"win", 0)
	engine.tick()
	assert_int(_events_of_type(engine, &"run_won").size()).is_equal(0)
	var denied := _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(RunLifecycleSystem.REASON_NOT_RUNNING)
	# After an ended run, a second resolution is refused (no double banking).
	_start(engine)
	run.resolve_victory(engine, true, 0)
	engine.tick()
	assert_bool(run.resolve_victory(engine, true, 0)).is_false()
	assert_int(run.meta.chronicle.size()).is_equal(1)


func test_run_abort_is_the_thin_failure_path() -> void:
	var engine := _engine()
	var run := _start(engine)
	engine.fast_forward(180)  # tick 181
	engine.submit_command(&"run_abort", &"", 0)
	engine.tick()  # drains at tick 182: 3h run
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_ABORTED)
	assert_int(run.last_run_score()).is_equal(3)
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("aborted")
	var aborted := _events_of_type(engine, &"run_aborted")
	assert_int(aborted.size()).is_equal(1)
	assert_int(int(aborted[0]["value"])).is_equal(3)
	assert_int(int(aborted[0]["value2"])).is_equal(1)
	# Abort when not running is denied loudly.
	engine.submit_command(&"run_abort", &"", 0)
	engine.tick()
	var denied := _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(RunLifecycleSystem.REASON_NOT_RUNNING)


func test_chronicle_entry_carries_army_stats() -> void:
	# With a units system present, the entry snapshots the terminal roster
	# (empty here — no training happened; the marathon proves it populated).
	var engine := _engine()
	var run := _start(engine)
	run.resolve_victory(engine, true, 7)
	engine.tick()
	var entry: Dictionary = run.meta.chronicle[0]
	var army: Dictionary = entry["army"]
	assert_int(army.size()).is_equal(0)
	assert_int(int(entry["army_power"])).is_equal(7)
	# Tags + trait ride along for the chronicle screen (T-UI-08).
	var tags: Array = entry["tags"]
	assert_int(tags.size()).is_equal(2)
	assert_str(String(entry["trait"])).is_equal(run.leader_trait_label())


# --- Restart: fresh identity, emptied state, regime rule -----------------------


func test_run_restart_denied_before_any_run() -> void:
	var engine := _engine()
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	var denied := _events_of_type(engine, &"run_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(RunLifecycleSystem.REASON_NOT_STARTED)


func test_run_restart_folds_fresh_identity_and_empties_state() -> void:
	var engine := _engine()
	var run := _start(engine)
	# Populate run-scoped state: bootstrap workers, a built + staffed camp,
	# resources, and a couple of recruit arrivals (1 accepted).
	engine.set_resource(&"food", 500)
	engine.set_resource(&"timber", 500)
	engine.submit_command(&"add_worker", &"production", 3)
	engine.submit_command(&"upgrade_building", &"camp", 0)
	engine.submit_command(&"assign_worker", &"camp", 2)
	engine.fast_forward(240)  # metronome: offers fire at ticks 121 + 241
	var units := _units_system(engine)
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()
	assert_int(units.pending_offers()).is_equal(1)
	assert_int(units.total_units()).is_equal(1)
	var first_identity := _identity_tuple(run)
	# Restart (running -> auto-abandoned, banks, folds, resets).
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	assert_int(run.current_run_index()).is_equal(2)
	assert_bool(run.is_running()).is_true()
	assert_int(run.run_start_tick()).is_equal(engine.tick_count)
	# Fresh identity: the full tuple moved on (pinned by the seed).
	assert_bool(_identity_tuple(run) == first_identity).is_false()
	# Run-scoped state emptied: resources, production, units.
	assert_int(engine.get_resource(&"food")).is_equal(0)
	assert_int(engine.get_resource(&"timber")).is_equal(0)
	var production := _production(engine)
	assert_int(production.idle_workers()).is_equal(0)
	assert_int(production.building_level(&"camp")).is_equal(0)
	assert_int(production.assigned_workers(&"camp")).is_equal(0)
	assert_int(units.total_units()).is_equal(0)
	assert_int(units.pending_offers()).is_equal(0)
	assert_int(units.arrivals_total).is_equal(0)
	assert_int(units.unit_ids().size()).is_equal(0)
	# The auto-abandonment banked (failure banks full progress).
	assert_int(run.meta.chronicle.size()).is_equal(1)
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("aborted")
	# Event: run_restarted carries the NEW regime id + run index.
	var restarted := _events_of_type(engine, &"run_restarted")
	assert_int(restarted.size()).is_equal(1)
	assert_str(String(restarted[0]["subject"])).is_equal(String(run.regime_id()))
	assert_int(int(restarted[0]["value"])).is_equal(2)
	assert_int(int(restarted[0]["value2"])).is_equal(RunLifecycleSystem.OUTCOME_ABORTED)


func test_restart_after_defeat_keeps_the_regime() -> void:
	# Town-hall journey 4: failure restarts under the SAME regime.
	var engine := _engine()
	var run := _start(engine)
	var regime_before := run.regime_id()
	run.resolve_victory(engine, false, 0)
	engine.tick()
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	assert_str(String(run.regime_id())).is_equal(String(regime_before))
	assert_int(run.current_run_index()).is_equal(2)


func test_restart_after_victory_redraws_the_regime() -> void:
	# Town-hall journey 5: victory swaps the regime. Over 10 pinned seeds the
	# redraw changes it for the majority (frozen counts — deterministic).
	var changed := 0
	for i in range(10):
		var engine := _engine(RUN_SEED + 100 + i)
		var run := _start(engine)
		var before := run.regime_id()
		run.resolve_victory(engine, true, 0)
		engine.tick()
		engine.submit_command(&"run_restart", &"", 0)
		engine.tick()
		if run.regime_id() != before:
			changed += 1
	assert_int(changed).is_greater_equal(5)


func test_restart_while_running_banks_the_abandonment() -> void:
	var engine := _engine()
	var run := _start(engine)
	engine.fast_forward(240)
	var points_before := run.meta.legacy_points
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	assert_int(run.meta.chronicle.size()).is_equal(1)
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("aborted")
	assert_int(run.meta.legacy_points).is_greater(points_before)
	assert_int(run.last_run_score()).is_equal(0)  # folded: new run, no score yet


# --- Meta domain separation -----------------------------------------------------


func test_meta_is_excluded_from_run_save_and_hash() -> void:
	# Two engines, same seed, same script — one carries a rich meta history.
	# Their run hashes are IDENTICAL: the bank/chronicle live in the meta
	# save domain and can neither fork nor perturb run determinism.
	var preloaded := RunMeta.new()
	preloaded.legacy_points = 12345
	preloaded.runs_recorded = 67
	preloaded.chronicle.append({"run": 67, "leader": "Ancient One", "outcome": "victory"})
	var bare := _engine(RUN_SEED)
	var rich := _engine_with(_regimes(), _identity(), RUN_SEED, preloaded)
	_start(bare)
	_start(rich)
	assert_int(bare.state_hash()).is_equal(rich.state_hash())
	# The run system's engine-side dict carries ids/scalars ONLY.
	var state := _run(bare).to_dict()
	assert_that(state.has("chronicle")).is_false()
	assert_that(state.has("legacy_points")).is_false()
	assert_that(state.has("meta")).is_false()
	assert_int(_run(rich).meta.legacy_points).is_equal(12345)  # untouched by the run


func test_meta_survives_restarts_and_round_trips() -> void:
	# The chronicle grows across restarts and crosses a meta dict round-trip;
	# handing the SAME meta to a re-inited engine continues the numbering.
	var engine := _engine()
	var run := _start(engine)
	run.resolve_victory(engine, true, 10)
	engine.tick()
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()
	run.resolve_victory(engine, false, 5)
	engine.tick()
	assert_int(run.meta.chronicle.size()).is_equal(2)
	assert_int(run.meta.runs_recorded).is_equal(2)
	assert_int(run.meta.legacy_points).is_greater(0)
	# Meta round-trip (the T-ARCH-03 meta save shape).
	var carried := RunMeta.new()
	assert_bool(carried.apply_dict(run.meta.to_dict())).is_true()
	assert_int(carried.legacy_points).is_equal(run.meta.legacy_points)
	assert_int(carried.chronicle.size()).is_equal(2)
	assert_str(String(carried.chronicle[1]["leader"])).is_equal(String(run.meta.chronicle[1]["leader"]))
	# A fresh engine (re-init form of restart) continues from the carried meta.
	var next_engine := _engine_with(_regimes(), _identity(), RUN_SEED + 9, carried)
	var next_run := _start(next_engine)
	next_run.resolve_victory(next_engine, true, 0)
	next_engine.tick()
	assert_int(next_run.meta.chronicle.size()).is_equal(3)
	assert_int(int(next_run.meta.chronicle[2]["run"])).is_equal(3)  # monotonic meta numbering


func test_run_meta_refuses_unknown_format_version() -> void:
	var meta := RunMeta.new()
	meta.legacy_points = 50
	assert_bool(meta.apply_dict({"format_version": 99, "legacy_points": 1})).is_false()
	assert_int(meta.legacy_points).is_equal(50)  # refused -> untouched


# --- Save round-trip --------------------------------------------------------------


func test_save_round_trip_mid_run_lockstep() -> void:
	var engine := _engine()
	var run := _start(engine)
	engine.fast_forward(200)
	var captured := engine.to_dict()
	var twin := _engine()
	assert_bool(twin.apply_state_dict(captured)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	var twin_run := _run(twin)
	assert_str(twin_run.leader_name()).is_equal(run.leader_name())
	assert_str(String(twin_run.regime_id())).is_equal(String(run.regime_id()))
	assert_int(twin_run.current_run_index()).is_equal(run.current_run_index())
	assert_int(twin_run.run_start_tick()).is_equal(run.run_start_tick())
	assert_bool(twin_run.is_running()).is_true()
	# Lockstep: identical futures under identical commands.
	engine.submit_command(&"run_abort", &"", 0)
	twin.submit_command(&"run_abort", &"", 0)
	engine.fast_forward(60)
	twin.fast_forward(60)
	assert_int(engine.state_hash()).is_equal(twin.state_hash())
	assert_int(_run(twin).last_run_score()).is_equal(run.last_run_score())


func test_from_dict_unknown_regime_runs_regime_less() -> void:
	var engine := _engine()
	var run := _start(engine)
	var state := run.to_dict()
	state["regime_id"] = "vanished_regime"
	var twin := _engine()
	_run(twin).from_dict(state)
	assert_that(_run(twin).current_regime() == null).is_true()
	assert_str(_run(twin).leader_name()).is_equal(run.leader_name())  # identity survives
	assert_bool(_run(twin).is_running()).is_true()  # the run keeps ticking
	# Resolution still works (regime is not needed for scoring).
	_run(twin).resolve_victory(twin, true, 0)
	twin.tick()
	assert_str(String(_run(twin).meta.chronicle[0]["regime"])).is_equal("")


# --- Variety acceptance: 100 generated leaders --------------------------------


func test_100_generated_leaders_have_varied_identities() -> void:
	var firsts := {}
	var names := {}
	var tags_seen := {}
	var regimes_seen := {}
	var traits_seen := {}
	var identities: Array[Dictionary] = []
	var pools := _identity()
	for i in range(100):
		var run := _start(_engine(RUN_SEED + 1000 + i))
		# Well-formed: pool first + pool epithet, joined.
		assert_that(pools.leader_first_names.has(run.leader_first_name())).is_true()
		assert_that(pools.leader_epithets.has(run.leader_epithet())).is_true()
		names[run.leader_name()] = true
		firsts[run.leader_first_name()] = true
		for tag in run.leader_tags():
			tags_seen[tag] = true
		regimes_seen[run.regime_id()] = true
		traits_seen[run.leader_trait_stub()] = true
		identities.append(_identity_tuple(run))
	# 100 draws over 8x8=64 name combos -> ~51 distinct expected; floor 40.
	assert_int(names.size()).is_greater_equal(40)
	assert_int(firsts.size()).is_greater_equal(6)
	# All 4 regime flavors appear; 5+ of 6 tags; 3+ of 4 trait stubs.
	assert_int(regimes_seen.size()).is_equal(4)
	assert_int(tags_seen.size()).is_greater_equal(5)
	assert_int(traits_seen.size()).is_greater_equal(3)
	# No immediate full-identity repeats (name + tags + trait + regime).
	var immediate := 0
	for i in range(1, identities.size()):
		if identities[i] == identities[i - 1]:
			immediate += 1
	assert_int(immediate).is_equal(0)


func test_100_restarts_stream_varied_identities() -> void:
	# One engine, 100 consecutive runs via restart (all defeats/aborts, so
	# the regime persists by rule — and the PEOPLE still churn).
	var engine := _engine(RUN_SEED + 77)
	var run := _start(engine)
	var names: Array[String] = []
	var regimes: Array[StringName] = []
	var identities: Array[Dictionary] = []
	for i in range(99):
		names.append(run.leader_name())
		regimes.append(run.regime_id())
		identities.append(_identity_tuple(run))
		engine.submit_command(&"run_restart", &"", 0)
		engine.tick()
	names.append(run.leader_name())
	regimes.append(run.regime_id())
	identities.append(_identity_tuple(run))
	# Stream variety: distinct names >= 35 of 100; same-name immediate pairs
	# within statistical expectation (~100/64 ~= 1.6 expected; floor 10).
	var distinct := {}
	for name in names:
		distinct[name] = true
	assert_int(distinct.size()).is_greater_equal(35)
	var name_repeats := 0
	var identity_repeats := 0
	for i in range(1, names.size()):
		if names[i] == names[i - 1]:
			name_repeats += 1
		if identities[i] == identities[i - 1]:
			identity_repeats += 1
	assert_int(name_repeats).is_less_equal(10)
	assert_int(identity_repeats).is_equal(0)
	# Regime keep-rule under non-victory restarts: same flavor throughout.
	for regime_id in regimes:
		assert_str(String(regime_id)).is_equal(String(regimes[0]))
	# The chronicle recorded every COMPLETED run: 99 abandoned runs banked;
	# run 100 is still running (folded identities, not yet resolved).
	assert_int(run.meta.runs_recorded).is_equal(99)
	assert_int(run.meta.chronicle.size()).is_equal(99)
	assert_int(run.current_run_index()).is_equal(100)


func test_full_run_script_is_deterministic() -> void:
	# The whole thin loop (start -> produce -> resolve -> restart -> resolve)
	# twins exactly: same seed + same script -> same hash + same identities.
	var script := func(engine: SimEngine) -> Array[Dictionary]:
		var run := _start(engine)
		var identities: Array[Dictionary] = [_identity_tuple(run)]
		engine.set_resource(&"food", 100)
		engine.submit_command(&"upgrade_building", &"camp", 0)
		engine.fast_forward(300)
		run.resolve_victory(engine, true, 33)
		engine.tick()
		engine.submit_command(&"run_restart", &"", 0)
		engine.tick()
		identities.append(_identity_tuple(run))
		engine.fast_forward(120)
		run.resolve_victory(engine, false, 0)
		engine.tick()
		identities.append({"hash": engine.state_hash(), "points": run.meta.legacy_points})
		return identities

	var first: Array[Dictionary] = script.call(_engine(RUN_SEED + 5))
	var second: Array[Dictionary] = script.call(_engine(RUN_SEED + 5))
	assert_dict(first[0]).is_equal(second[0])
	assert_dict(first[1]).is_equal(second[1])
	assert_int(int(first[2]["hash"])).is_equal(int(second[2]["hash"]))
	assert_int(int(first[2]["points"])).is_equal(int(second[2]["points"]))
