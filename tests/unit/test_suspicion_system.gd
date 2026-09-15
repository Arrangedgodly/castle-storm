## Unit tests for the suspicion system (T-SIM-05).
## Mirrors sim/systems/suspicion_system.gd + the sibling seams it consumes
## (UnitLifecycleSystem.training_uids/scatter_recruits/base_unit_id,
## ProductionSystem.building_ids; test-mapping rule). Hawkeye seam coverage:
## the heat-profile formula per source (presence weights exact in the
## fractional accumulator, act bumps exact per source), decay tiers + the
## never-below-zero floor, warn-zone hysteresis, telegraph arm/cancel at the
## crackdown threshold (>= 4h countdown, cancellable by dipping below),
## crackdown seize math (floor 40%, per-resource events), scatter rules
## (unassigned pool only: gate offers then idle peasants, ceil rounding),
## the post-crackdown relief window (rises halved) + re-arm timer, the
## crush-at-100 path (run_lost + OUTCOME_DEFEAT + meta banked), restart
## resetting every run-scoped field, determinism, and the save round-trip
## with an in-flight telegraph countdown.
extends GdUnitTestSuite

const RUN_SEED := 20260916


# --- Fixtures (in-code content; same classes the .tres files use) ----------


## Tunables dial: metronome arrivals (jitter 0 — zero RNG draws anywhere in
## the stack), selectable decay, selectable presence, selectable arrival
## interval (huge = "no arrivals inside this test's horizon").
func _tunables(
	decay := 5.0,
	high_decay := 2.5,
	presence := true,
	interval_hours := 2.0
) -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_jitter_hours = 0.0
	tunables.recruit_arrival_interval_hours = interval_hours
	tunables.suspicion_decay_per_hour = decay
	tunables.suspicion_decay_high_tier_per_hour = high_decay
	if not presence:
		tunables.suspicion_presence_army_per_hour = 0.0
		tunables.suspicion_presence_follower_per_hour = 0.0
		tunables.suspicion_presence_building_per_hour = 0.0
		tunables.suspicion_presence_offer_per_hour = 0.0
	else:
		# The building dial defaults to 0 in content (see economy_tunables.gd
		# for the un-cancellable-telegraph rationale); tests that want its
		# heat set it explicitly — this is the dial-under-test value.
		tunables.suspicion_presence_building_per_hour = 0.1
	return tunables


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel", "Godfrey", "Petronella", "Aldous", "Sybil"]
	pools.leader_epithets = [
		"the Unbearable", "the Almost Wise", "of the Leaky Barn", "the Twice-Fooled",
		"the Modest Avalanche", "of Fine Debt", "the Whispering Shout", "the Patient Torch",
	]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous", &"paranoid", &"romantic", &"vengeful"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick", "Bess", "Gil", "Meg", "Ralph", "Joan", "Sim"]
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
	var milestones: Array[int] = [10, 20]
	def.milestone_levels = milestones
	def.max_level = 30
	return def


func _unit_defs() -> Array[UnitDef]:
	# The MVP-pack suspicion shape: militia/knight +8, archer +4, the rest 0.
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
	knight.required_gear_slots.append(&"weapon")
	knight.required_gear_slots.append(&"armor")
	knight.combat_power = 10
	knight.suspicion_on_train = 8
	defs.append(knight)

	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.required_gear_slots.append(&"weapon")
	archer.combat_power = 6
	archer.suspicion_on_train = 4
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
	return defs


## Fast chain for the pure presence-rate probes: peasant -> guard in 6
## ticks (guard = terminal combat unit = army roster). Keeps MVP def VALUES
## out of the timing so the weight math is the only thing under test.
func _fast_unit_defs() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"guard")
	defs.append(peasant)
	var guard := UnitDef.new()
	guard.id = &"guard"
	guard.display_name = "Guard"
	guard.training_time_hours = 0.1  # exactly 6 ticks
	guard.combat_power = 10
	defs.append(guard)
	return defs


func _fast_engine(tunables: EconomyTunables) -> SimEngine:
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new([_regime()], _identity()))
	engine.register_system(UnitLifecycleSystem.new(_fast_unit_defs(), [], tunables))
	engine.register_system(SuspicionSystem.new(tunables, _fast_unit_defs()))
	return engine


## Full stack with suspicion LAST (the documented registration order: it
## watches units/production at the tick boundary; only consistency is
## contractual).
func _engine(tunables: EconomyTunables, p_run_seed: int = RUN_SEED) -> SimEngine:
	var engine := SimEngine.new(p_run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new([_regime()], _identity()))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), tunables))
	engine.register_system(ProductionSystem.new([_farm()], tunables, null))
	engine.register_system(SuspicionSystem.new(tunables, _unit_defs()))
	return engine


func _start(engine: SimEngine) -> RunLifecycleSystem:
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	return engine.get_system(&"run") as RunLifecycleSystem


func _suspicion(engine: SimEngine) -> SuspicionSystem:
	return engine.get_system(&"suspicion") as SuspicionSystem


func _units_system(engine: SimEngine) -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


func _events_of_type(engine: SimEngine, type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			found.append({
				"tick": event.tick,
				"subject": String(event.subject),
				"value": event.value,
				"value2": event.value2,
			})
	return found


## Builds the farm at the next drain (funded via the documented test seam).
func _build_farm(engine: SimEngine) -> void:
	engine.set_resource(&"timber", 1000)
	engine.submit_command(&"upgrade_building", &"farm", 0)
	engine.tick()


# --- Heat profile: presence weights (exact fractional accumulator) ----------


func test_presence_building_weight_is_exact() -> void:
	# 0.1 points/h per building level: 1 whole point per 600 ticks (10h).
	# Decay 0 isolates presence; interval 1000h keeps arrivals out.
	var engine := _engine(_tunables(0.0, 0.0, true, 1000.0))
	_start(engine)
	_build_farm(engine)  # +4 medium bump (construction = first level gain)
	var heat := _suspicion(engine)
	assert_int(heat.suspicion).is_equal(4)
	assert_int(heat.accum).is_equal(6000)  # presence already ran at the bump tick
	engine.fast_forward(597)  # t599: under one settled point
	assert_int(heat.suspicion).is_equal(4)
	assert_int(heat.accum).is_equal(6000 + 597 * 6000)
	engine.fast_forward(2)  # t601: 600 presence ticks total -> exactly 1 point
	assert_int(heat.suspicion).is_equal(5)
	assert_int(heat.accum).is_equal(0)


func test_presence_offer_weight_is_exact() -> void:
	# 0.25 points/h per gate offer: one offer from t121 -> accum 1.8M at t240;
	# the second offer at t241 doubles the rate for the next 120 ticks.
	var engine := _engine(_tunables(0.0, 0.0, true, 2.0))
	_start(engine)
	engine.fast_forward(239)  # t240: offers fired at t121 only so far
	var units := _units_system(engine)
	assert_int(units.pending_offers()).is_equal(1)
	var heat := _suspicion(engine)
	assert_int(heat.suspicion).is_equal(0)  # 1 offer x 120 ticks = 1.8M, no point
	assert_int(heat.accum).is_equal(120 * 15000)
	engine.fast_forward(120)  # t241..t360: 2 offers (250 + 250 milli/h)
	assert_int(units.pending_offers()).is_equal(2)
	assert_int(heat.suspicion).is_equal(1)  # +1.8M carried + 3.6M = 1 point
	assert_int(heat.accum).is_equal(1800000)


func test_presence_follower_and_army_weights_are_exact() -> void:
	# Fast chain (peasant -> guard in 6 ticks): follower 0.1/h for the 6
	# waiting ticks + army 0.5/h after promotion, both EXACT in the carry.
	var engine := _fast_engine(_tunables(0.0, 0.0, true, 2.0))
	_start(engine)
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var heat := _suspicion(engine)
	engine.fast_forward(120)  # t121: first offer fires this tick
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()  # t122: accepted (follower from the next scan)
	engine.submit_command(&"assign_role", &"guard", units.unit_ids()[0])
	engine.fast_forward(6)  # assign drains t123; guard completes t128
	assert_int(units.army_roster().size()).is_equal(1)
	# Carry at t128: the offer's presence tick at t121 (15000) + follower
	# 6 ticks x 6000 (t122..t127) + 1 army tick x 30000.
	assert_int(heat.accum).is_equal(81000)
	# Army rate: zero the carry, then 120 ticks at 0.5/h = exactly +1 point
	# (the t241 offer's presence rides along in the carry - deterministic).
	heat.accum = 0
	var before := heat.suspicion
	engine.fast_forward(120)  # t248
	assert_int(heat.suspicion).is_equal(before + 1)
	assert_int(heat.accum).is_equal(8 * 15000)  # second offer: t241..t248


func test_held_archer_completion_bumps_content_points() -> void:
	# The HELD completion path (knight/archer: training complete, awaiting
	# gear + promote) bumps via the retained target def - a different
	# detection branch than the auto-promotion militia test below.
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	_start(engine)
	var units := _units_system(engine)
	engine.set_resource(&"iron", 100)
	engine.set_resource(&"timber", 100)
	engine.fast_forward(121)
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()  # accepted at t123
	engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
	engine.fast_forward(125)  # militia auto-completes: +8
	engine.submit_command(&"start_training", &"trainee", units.unit_ids()[0])
	engine.fast_forward(250)  # trainee auto-completes: 0 (no content points)
	# Clear the gate (3 offers at t241/361/481, still tolerance-quiet) so the
	# later arrivals cannot add gate noise to the assertion.
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	engine.tick()
	engine.submit_command(&"start_training", &"archer", units.unit_ids()[0])
	engine.fast_forward(370)  # archer completes HELD: +4
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(2)
	assert_str(rose[0]["subject"]).is_equal("militia")
	assert_int(int(rose[0]["value"])).is_equal(8)
	assert_str(rose[1]["subject"]).is_equal("archer")
	assert_int(int(rose[1]["value"])).is_equal(4)
	assert_int(_suspicion(engine).suspicion).is_equal(12)


func test_training_completion_bumps_content_points() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	_start(engine)
	var units := _units_system(engine)
	engine.fast_forward(121)
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()
	engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
	engine.tick()
	assert_int(_suspicion(engine).suspicion).is_equal(0)  # starting the timer is quiet
	engine.fast_forward(125)  # 2h militia training completes
	var heat := _suspicion(engine)
	assert_int(heat.suspicion).is_equal(8)
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(1)
	assert_str(rose[0]["subject"]).is_equal("militia")
	assert_int(int(rose[0]["value"])).is_equal(8)
	assert_int(int(rose[0]["value2"])).is_equal(8)  # meter after the bump


func test_building_level_gains_bump_medium() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	_build_farm(engine)  # 0 -> 1 construction = first level gain
	assert_int(_suspicion(engine).suspicion).is_equal(4)
	engine.submit_command(&"upgrade_building", &"farm", 0)
	engine.tick()  # 1 -> 2
	assert_int(_suspicion(engine).suspicion).is_equal(8)
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(2)
	for entry in rose:
		assert_str(entry["subject"]).is_equal("building")
		assert_int(int(entry["value"])).is_equal(4)


func test_gate_arrivals_past_tolerance_bump_loud() -> void:
	# Tolerance 3: arrivals while offers <= 3 are quiet; the 4th pending
	# offer makes the NEXT arrival loud (+8 per arrival).
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	_start(engine)
	engine.fast_forward(361)  # offers at t121/241/361 -> 3 pending, quiet
	assert_int(_units_system(engine).pending_offers()).is_equal(3)
	assert_int(_suspicion(engine).suspicion).is_equal(0)
	engine.fast_forward(120)  # t481: 4th arrival, offers 4 > 3 -> +8
	assert_int(_suspicion(engine).suspicion).is_equal(8)
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(1)
	assert_str(rose[0]["subject"]).is_equal("gate")
	assert_int(int(rose[0]["value"])).is_equal(8)


# --- Decay: tiers, floor, pause ----------------------------------------------


func test_decay_below_tier_floors_at_zero() -> void:
	var engine := _engine(_tunables(5.0, 2.5, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(50)
	engine.fast_forward(60)  # 1h at -5/h
	assert_int(heat.suspicion).is_equal(45)
	heat.set_suspicion(2)
	engine.fast_forward(60)
	assert_int(heat.suspicion).is_equal(0)  # never below 0
	engine.fast_forward(600)
	assert_int(heat.suspicion).is_equal(0)
	assert_int(heat.accum).is_equal(0)  # no decay debt accrues at the floor


func test_decay_at_tier_2_is_slower() -> void:
	# The "compromised" tier: >= 70 decays at 2.5/h, not 5/h.
	var engine := _engine(_tunables(5.0, 2.5, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(75)
	engine.fast_forward(60)  # 1h at -2.5/h -> 72.5: settles -2, carries -1.8M
	assert_int(heat.suspicion).is_equal(73)
	assert_int(heat.accum).is_equal(-1800000)
	heat.set_suspicion(65)
	engine.fast_forward(60)  # below tier: -5/h exactly
	assert_int(heat.suspicion).is_equal(60)


func test_decay_pauses_after_a_loud_act_above_warn() -> void:
	# R4 decay_reset_rule: a loud act above the warn threshold freezes decay
	# for 1h. Exactness: re-anchor the meter just before the completion (the
	# test seam exists for exactly this), then the pause window holds the
	# meter EXACTLY still, and decay resumes after it.
	var engine := _engine(_tunables(5.0, 2.5, false, 2.0))
	_start(engine)
	var units := _units_system(engine)
	var heat := _suspicion(engine)
	engine.fast_forward(121)
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()  # accepted at t123
	engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
	engine.tick()  # training starts t124 -> completes t243
	engine.fast_forward(113)  # t237: just before the completion
	heat.set_suspicion(40)  # above warn (35), below crackdown
	engine.fast_forward(6)  # t243: militia completes -> +8, decay pauses 1h
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(1)
	var completion_tick := int(rose[0]["tick"])
	assert_int(heat.decay_paused_until_tick).is_equal(completion_tick + 60)
	assert_int(heat.suspicion).is_equal(48)  # 40 + 8; decay ran only 6 ticks (no whole point)
	engine.fast_forward(60)  # the pause window: no decay, no presence (off)
	assert_int(heat.suspicion).is_equal(48)
	engine.fast_forward(60)  # pause expired: -5/h exactly
	assert_int(heat.suspicion).is_equal(43)


# --- Thresholds: warn hysteresis, telegraph arm/cancel ------------------------


func test_warn_zone_entry_fires_once_per_entry() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(34)
	engine.tick()
	assert_int(_events_of_type(engine, &"suspicion_warn").size()).is_equal(0)
	heat.set_suspicion(36)
	engine.tick()  # enters the warn zone
	var warned := _events_of_type(engine, &"suspicion_warn")
	assert_int(warned.size()).is_equal(1)
	assert_int(int(warned[0]["value"])).is_equal(36)
	assert_int(int(warned[0]["value2"])).is_equal(35)  # threshold
	assert_bool(heat.warned).is_true()
	engine.fast_forward(10)  # hovering inside: no repeat
	assert_int(_events_of_type(engine, &"suspicion_warn").size()).is_equal(1)
	heat.set_suspicion(30)
	engine.tick()  # silent exit
	assert_bool(heat.warned).is_false()
	assert_int(_events_of_type(engine, &"suspicion_warn").size()).is_equal(1)
	heat.set_suspicion(36)
	engine.tick()  # re-entry fires again
	assert_int(_events_of_type(engine, &"suspicion_warn").size()).is_equal(2)


func test_telegraph_arms_at_70_with_minimum_countdown() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(69)
	engine.tick()
	assert_int(heat.crackdown_land_tick).is_equal(-1)
	heat.set_suspicion(70)
	engine.tick()
	var telegraph := _events_of_type(engine, &"suspicion_telegraph")
	assert_int(telegraph.size()).is_equal(1)
	assert_int(heat.crackdown_land_tick).is_equal(engine.tick_count + 240)  # >= 4h


func test_telegraph_cancels_when_suspicion_dips_below_70() -> void:
	# The R4 tension mechanic: lay low during the countdown and the riders
	# stand down — the telegraph is a warning you can still heed.
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()
	var land := heat.crackdown_land_tick
	assert_int(land).is_greater(0)
	heat.set_suspicion(65)
	engine.tick()
	assert_int(heat.crackdown_land_tick).is_equal(-1)
	var cancelled := _events_of_type(engine, &"crackdown_cancelled")
	assert_int(cancelled.size()).is_equal(1)
	assert_int(int(cancelled[0]["value"])).is_equal(65)
	engine.fast_forward(land - engine.tick_count + 60)  # well past the old landing
	assert_int(_events_of_type(engine, &"crackdown_struck").size()).is_equal(0)
	assert_int(heat.crackdowns_total).is_equal(0)


# --- Crackdown: seize + scatter + setback -------------------------------------


func test_crackdown_seize_math_is_exact() -> void:
	# Seize floor(40%) of every stock: 100/50/3 -> 40/20/1 seized, 60/30/2
	# left; events sorted by resource TEXT (food, iron, timber).
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	engine.set_resource(&"food", 100)
	engine.set_resource(&"timber", 50)
	engine.set_resource(&"iron", 3)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()
	var land := heat.crackdown_land_tick
	engine.fast_forward(land - engine.tick_count)
	var struck := _events_of_type(engine, &"crackdown_struck")
	assert_int(struck.size()).is_equal(1)
	assert_int(int(struck[0]["value"])).is_equal(1)  # ordinal 1
	assert_int(int(struck[0]["value2"])).is_equal(70)  # meter before the drop
	var seized := _events_of_type(engine, &"crackdown_seized")
	assert_int(seized.size()).is_equal(3)
	assert_str(seized[0]["subject"]).is_equal("food")
	assert_int(int(seized[0]["value"])).is_equal(40)
	assert_int(int(seized[0]["value2"])).is_equal(60)
	assert_str(seized[1]["subject"]).is_equal("iron")
	assert_int(int(seized[1]["value"])).is_equal(1)  # floor(3 x 0.4) = 1
	assert_int(int(seized[1]["value2"])).is_equal(2)
	assert_str(seized[2]["subject"]).is_equal("timber")
	assert_int(int(seized[2]["value"])).is_equal(20)
	assert_int(int(seized[2]["value2"])).is_equal(30)
	# The setback: meter re-opens at 45 (below the 70 threshold), relief +
	# re-arm windows set, no scatter (empty pool fires no event).
	assert_int(heat.suspicion).is_equal(45)
	assert_int(heat.relief_until_tick).is_equal(engine.tick_count + 24 * 60)
	assert_int(heat.rearm_until_tick).is_equal(engine.tick_count + 4 * 60)
	assert_int(_events_of_type(engine, &"crackdown_scattered").size()).is_equal(0)


func test_crackdown_scatters_unassigned_pool_only() -> void:
	# Timeline (metronome 2h): 2 offers by t241; peasant 1 -> militia
	# pipeline (completes t362, +8), peasant 2 idle; telegraph armed t245
	# lands t485; arrivals at t361/t481 refill the gate to 2 offers (<=
	# tolerance, quiet). Pool at landing = 2 offers + 1 idle peasant = 3 ->
	# ceil(3 x 0.5) = 2, taken OFFERS FIRST; the committed militia and the
	# idle peasant survive untouched.
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	_start(engine)
	var units := _units_system(engine)
	engine.fast_forward(240)  # t241: offers at t121 + t241
	assert_int(units.pending_offers()).is_equal(2)
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()  # t242: peasant 1
	engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
	engine.tick()  # t243: training starts -> completes t362
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()  # t244: peasant 2, idle + unassigned
	assert_int(units.pending_offers()).is_equal(0)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()  # t245: telegraph arms, lands t485
	var land := heat.crackdown_land_tick
	engine.fast_forward(land - engine.tick_count)
	# The militia training completed mid-countdown (+8): meter 78 at landing.
	var struck := _events_of_type(engine, &"crackdown_struck")
	assert_int(struck.size()).is_equal(1)
	assert_int(int(struck[0]["value2"])).is_equal(78)
	assert_int(heat.suspicion).is_equal(45)  # post-crackdown drop already applied
	var scattered := _events_of_type(engine, &"crackdown_scattered")
	assert_int(scattered.size()).is_equal(1)
	assert_int(int(scattered[0]["value"])).is_equal(2)  # ceil(3 x 0.5)
	assert_int(int(scattered[0]["value2"])).is_equal(0)  # offers drained
	# Roster after: militia survived, the idle peasant survived, offers gone.
	assert_int(units.unit_count(&"militia")).is_equal(1)
	assert_int(units.unit_count(&"peasant")).is_equal(1)
	assert_int(units.pending_offers()).is_equal(0)
	assert_int(units.total_units()).is_equal(2)


func test_scatter_recruits_direct_pool_rules() -> void:
	# Direct seam test: offers first (arrival order), then idle base units;
	# committed pipeline (training militia) and everything else untouchable.
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	_start(engine)
	var units := _units_system(engine)
	engine.fast_forward(601)  # offers at t121..t601 -> 5 pending
	assert_int(units.pending_offers()).is_equal(5)
	# peasant 1 -> militia pipeline (in training = committed).
	engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
	engine.tick()
	engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
	engine.tick()
	# peasants 2..4 -> accepted, idle + unassigned.
	for i in range(3):
		engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
		engine.tick()
	assert_int(units.pending_offers()).is_equal(1)
	assert_int(units.unit_count(&"peasant")).is_equal(4)
	var scattered := units.scatter_recruits(3)
	assert_int(scattered).is_equal(3)
	assert_int(units.pending_offers()).is_equal(0)  # the last offer went first
	assert_int(units.unit_count(&"peasant")).is_equal(2)  # training unit (def stays peasant) + 1 idle
	assert_int(units.total_units()).is_equal(2)  # the committed trainee + 1 idle peasant
	assert_str(String(units.training_target(units.unit_ids()[0]))).is_equal("militia")  # untouched
	assert_int(units.training_progress_milli(units.unit_ids()[0])).is_greater(0)
	scattered = units.scatter_recruits(99)  # drains the rest of the pool
	assert_int(scattered).is_equal(1)
	assert_int(units.total_units()).is_equal(1)  # only the committed trainee survives
	assert_str(String(units.unit_def(units.unit_ids()[0]))).is_equal("peasant")
	assert_int(units.scatter_recruits(5)).is_equal(0)  # empty pool: no-op


func test_relief_window_halves_rises() -> void:
	var engine := _engine(_tunables(0.0, 0.0, true, 1000.0))
	_start(engine)
	_build_farm(engine)  # +4 (construction)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()
	var land := heat.crackdown_land_tick
	engine.fast_forward(land - engine.tick_count)  # crackdown lands; meter 45
	assert_int(heat.suspicion).is_equal(45)
	# Act bump during relief: +4 medium x 0.5 = +2 exactly.
	engine.submit_command(&"upgrade_building", &"farm", 0)
	engine.tick()
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(2)  # construction + this upgrade
	assert_int(int(rose[1]["value"])).is_equal(2)
	assert_int(heat.suspicion).is_equal(47)
	# Presence during relief: farm L2 at 0.2/h x 0.5 = 100 milli/h -> 6000
	# per tick (t244, the bump tick, already banked its 6000).
	assert_int(heat.accum).is_equal(6000)
	engine.fast_forward(59)  # t303: 60 relief-presence ticks total
	assert_int(heat.accum).is_equal(60 * 6000)
	assert_int(heat.suspicion).is_equal(47)


func test_rearm_timer_gates_the_next_telegraph() -> void:
	# After a crackdown, a fresh >= 70 crossing does NOT re-arm the telegraph
	# until the re-arm window expires — then it arms on the tick it may.
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()
	var land := heat.crackdown_land_tick
	engine.fast_forward(land - engine.tick_count)  # crackdown #1
	var rearm := heat.rearm_until_tick
	assert_int(engine.tick_count).is_equal(rearm - 240)
	heat.set_suspicion(75)  # loud again, instantly
	engine.fast_forward(239)  # inside the re-arm window: no telegraph
	assert_int(heat.crackdown_land_tick).is_equal(-1)
	assert_int(_events_of_type(engine, &"suspicion_telegraph").size()).is_equal(1)
	engine.tick()  # the re-arm tick itself
	assert_int(engine.tick_count).is_equal(rearm)
	assert_int(heat.crackdown_land_tick).is_equal(rearm + 240)
	assert_int(_events_of_type(engine, &"suspicion_telegraph").size()).is_equal(2)


# --- Crush at 100: run fails, banks meta, resets on restart -------------------


func test_crush_at_max_fails_run_and_banks_meta() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	var run := _start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(99)
	engine.fast_forward(65)  # ~1h of duration for a meaningful bank
	heat.set_suspicion(100)
	engine.tick()  # the crush fires (meter maxed while the run is live)
	var crushed := _events_of_type(engine, &"run_crushed")
	assert_int(crushed.size()).is_equal(1)
	assert_int(int(crushed[0]["value"])).is_equal(100)
	assert_int(int(crushed[0]["value2"])).is_equal(1)  # run index
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_RUNNING)  # tick-aligned
	engine.tick()  # resolve_victory drains: run_lost
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_DEFEAT)
	assert_int(_events_of_type(engine, &"run_lost").size()).is_equal(1)
	assert_int(run.meta.runs_recorded).is_equal(1)
	assert_int(run.meta.legacy_points).is_equal(run.last_run_score())
	assert_int(run.last_run_score()).is_greater(0)  # duration banked on failure
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("defeat")
	# Dormant after the end: the meter freezes, nothing further accrues.
	engine.fast_forward(300)
	assert_int(heat.suspicion).is_equal(100)
	assert_int(_events_of_type(engine, &"suspicion_rose").size()).is_equal(0)


func test_run_restart_resets_every_suspicion_field() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 2.0))
	var run := _start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(80)  # hot, telegraph armed, warn zone
	engine.tick()
	assert_int(heat.crackdown_land_tick).is_greater(0)
	assert_bool(heat.warned).is_true()
	engine.submit_command(&"run_restart", &"", 0)
	engine.tick()  # reset contract: sibling reset at the drain
	assert_int(run.current_run_index()).is_equal(2)
	assert_bool(run.is_running()).is_true()
	assert_int(heat.suspicion).is_equal(0)
	assert_int(heat.accum).is_equal(0)
	assert_bool(heat.warned).is_false()
	assert_int(heat.crackdown_land_tick).is_equal(-1)
	assert_int(heat.crackdowns_total).is_equal(0)
	assert_int(heat.relief_until_tick).is_equal(0)
	assert_int(heat.rearm_until_tick).is_equal(0)
	assert_int(heat.decay_paused_until_tick).is_equal(0)
	# The new run's meter is LIVE again: an upgrade bumps it.
	_build_farm(engine)
	assert_int(heat.suspicion).is_equal(4)
	assert_int(run.meta.chronicle.size()).is_equal(1)  # the restart banked run 1


# --- Determinism + save round-trip ---------------------------------------------


func test_full_script_is_deterministic() -> void:
	var script := func(engine: SimEngine) -> Dictionary:
		_start(engine)
		engine.set_resource(&"timber", 1000)
		engine.set_resource(&"iron", 100)
		var units := engine.get_system(&"units") as UnitLifecycleSystem
		var heat := engine.get_system(&"suspicion") as SuspicionSystem
		engine.submit_command(&"upgrade_building", &"farm", 0)
		engine.fast_forward(121)
		engine.submit_command(&"recruit_accept", &"", units.offer_ids()[0])
		engine.tick()
		engine.submit_command(&"assign_role", &"militia", units.unit_ids()[0])
		engine.fast_forward(125)
		heat.set_suspicion(70)  # forced threshold state (test seam)
		engine.tick()
		engine.fast_forward(240)  # telegraph lands
		engine.fast_forward(120)
		return {
			"hash": engine.state_hash(),
			"rng": engine.rng.state,
			"crackdowns": heat.crackdowns_total,
			"food": engine.get_resource(&"food"),
		}

	var first: Dictionary = script.call(_engine(_tunables(0.0, 0.0, true, 2.0)))
	var second: Dictionary = script.call(_engine(_tunables(0.0, 0.0, true, 2.0)))
	assert_int(int(first["hash"])).is_equal(int(second["hash"]))
	assert_int(int(first["rng"])).is_equal(int(second["rng"]))
	assert_int(int(first["crackdowns"])).is_equal(int(second["crackdowns"]))
	assert_int(int(first["crackdowns"])).is_greater_equal(1)
	assert_int(int(first["food"])).is_equal(int(second["food"]))


func test_save_round_trip_with_in_flight_telegraph() -> void:
	var engine := _engine(_tunables(0.0, 0.0, true, 2.0))
	_start(engine)
	engine.set_resource(&"timber", 1000)
	engine.submit_command(&"upgrade_building", &"farm", 0)
	engine.fast_forward(150)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()  # telegraph armed
	assert_int(heat.crackdown_land_tick).is_greater(0)
	var captured := engine.to_dict()
	var twin := _engine(_tunables(0.0, 0.0, true, 2.0))
	assert_bool(twin.apply_state_dict(captured)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	assert_int((_suspicion(twin)).crackdown_land_tick).is_equal(heat.crackdown_land_tick)
	# Lockstep THROUGH the landing: identical futures under identical drives.
	engine.fast_forward(300)
	twin.fast_forward(300)
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	var twin_heat := _suspicion(twin)
	assert_int(twin_heat.crackdowns_total).is_equal(heat.crackdowns_total)
	assert_int(twin_heat.crackdowns_total).is_greater_equal(1)  # it really landed
	assert_int(twin_heat.suspicion).is_equal(heat.suspicion)
	assert_int(twin.get_resource(&"food")).is_equal(engine.get_resource(&"food"))


func test_state_hash_sees_telegraph_and_windows() -> void:
	# Oracle probes via public-field pokes: identical engines differing only
	# in the countdown (or a window) must hash differently — a blind oracle
	# here would call a lost telegraph "identical" (the T-ARCH-03 lesson).
	var a := _engine(_tunables(0.0, 0.0, false, 1000.0))
	var b := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(a)
	_start(b)
	var heat_a := _suspicion(a)
	var heat_b := _suspicion(b)
	heat_a.set_suspicion(70)
	heat_b.set_suspicion(70)
	a.tick()
	b.tick()
	assert_int(a.state_hash()).is_equal(b.state_hash())
	heat_b.crackdown_land_tick = -1  # same meter, telegraph dropped
	assert_int(a.state_hash()).is_not_equal(b.state_hash())
	heat_b.crackdown_land_tick = heat_a.crackdown_land_tick
	heat_b.relief_until_tick = 99999  # same meter + telegraph, window moved
	assert_int(a.state_hash()).is_not_equal(b.state_hash())


# --- Professor X: chronicle lines ----------------------------------------------


func test_chronicle_lines_render_for_every_beat() -> void:
	var engine := _engine(_tunables(0.0, 0.0, false, 1000.0))
	_start(engine)
	var heat := _suspicion(engine)
	heat.set_suspicion(70)
	engine.tick()  # telegraph arms
	heat.set_suspicion(65)
	engine.tick()  # cancelled
	heat.set_suspicion(100)
	engine.tick()  # crushed
	var telegraph := _events_of_type(engine, &"suspicion_telegraph")[0]
	var cancelled := _events_of_type(engine, &"crackdown_cancelled")[0]
	var crushed := _events_of_type(engine, &"run_crushed")[0]
	# The renderers are pure functions of the event payloads: rebuild copies
	# (pooled ring slots are reuse-unsafe) and assert the human beats.
	var event := SimEvent.new()
	event.tick = int(telegraph["tick"])
	event.type = &"suspicion_telegraph"
	event.value = int(telegraph["value"])
	assert_str(heat.chronicle_line(event)).is_equal(
		"The Watchful Eye turns: riders in livery count your barns. The crackdown lands in 4 hours."
	)
	event = SimEvent.new()
	event.type = &"crackdown_cancelled"
	assert_that(heat.chronicle_line(event).length()).is_greater(10)
	event = SimEvent.new()
	event.type = &"run_crushed"
	assert_str(heat.chronicle_line(event)).contains("crushed")
	event = SimEvent.new()
	event.type = &"training_complete"  # not a suspicion beat
	assert_str(heat.chronicle_line(event)).is_empty()
