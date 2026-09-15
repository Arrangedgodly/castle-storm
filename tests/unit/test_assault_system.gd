## Unit tests for the assault resolver (T-SIM-06).
## Mirrors sim/systems/assault_resolver.gd + the sibling seams it consumes
## (UnitLifecycleSystem.army_contributions/apply_army_losses,
## SuspicionSystem.apply_external_bump; test-mapping rule). Hawkeye seam
## coverage: the odds formula's exactness at the knight floor (per-unit
## breakdown incl. gear tiers), regime combat modifiers applied to the
## correct side (all 4 MVP flavors), odds monotonicity in army power and
## gear quality, breakdown-sums-to-displayed-probability, the floor gate
## (commit refused below floor with reason; a floor, never a trigger),
## query purity (no RNG draws), resolution determinism (same seed -> same
## outcome + same beat sequence, live == fast-forward), the failed-assault
## set-back rules (ceil-fraction army losses newest-first, suspicion spike,
## re-attempt after rebuilding), victory wiring (same-tick run_won, banking,
## chronicle), relief damping of the spike, spike-at-the-edge crushing, and
## restart safety (stateless resolver: nothing survives a restart).
extends GdUnitTestSuite

const RUN_SEED := 20260916


# --- Fixtures (in-code content; same classes the .tres files use) ----------


## Metronome arrivals (jitter 0 — zero arrival draws), suspicion fully
## isolated (zero presence + zero decay — the meter moves ONLY through the
## assault spike in these tests), assault block parameterizable.
func _tunables(
	garrison_base := 60,
	floor := 23,
	loss_fraction := 0.5,
	failure_suspicion := 20,
	interval_hours := 0.05
) -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_interval_hours = interval_hours
	tunables.recruit_arrival_jitter_hours = 0.0
	tunables.suspicion_decay_per_hour = 0.0
	tunables.suspicion_decay_high_tier_per_hour = 0.0
	tunables.suspicion_presence_army_per_hour = 0.0
	tunables.suspicion_presence_follower_per_hour = 0.0
	tunables.suspicion_presence_building_per_hour = 0.0
	tunables.suspicion_presence_offer_per_hour = 0.0
	tunables.assault_garrison_base_power = garrison_base
	tunables.assault_knight_floor_power = floor
	tunables.assault_loss_fraction = loss_fraction
	tunables.assault_failure_suspicion = failure_suspicion
	return tunables


## Real-chain cadence: arrivals every 2h (the MVP metronome) so the long
## knight training does not pile hundreds of offers at the gate.
func _real_tunables(garrison_base := 60) -> EconomyTunables:
	return _tunables(garrison_base, 23, 0.5, 20, 2.0)


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel"]
	pools.leader_epithets = ["the Unbearable", "the Almost Wise", "of the Leaky Barn"]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous"]
	pools.recruit_names = ["Tom", "Hob", "Nell"]
	return pools


func _regime(id := &"gilded_crown", kind := &"garrison_multiplier", value := 1.0) -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = id
	regime.display_name = String(id)
	var combat := RegimeModifier.new()
	combat.kind = kind
	combat.value = value
	regime.combat_modifier = combat
	return regime


## The four MVP combat flavors (distinct kinds on both sides of the fight).
func _flavors() -> Array[RegimeDef]:
	return [
		_regime(&"gilded_crown", &"garrison_multiplier", 1.2),
		_regime(&"velvet_fist", &"garrison_multiplier", 0.9),
		_regime(&"iron_rotunda", &"army_score_multiplier", 1.1),
		_regime(&"paper_crown", &"army_score_multiplier", 0.95),
	]


## The MVP unit chain (1 knight t1 + 1 archer t1 = the power-23 floor line).
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


func _gear_defs() -> Array[GearDef]:
	var defs: Array[GearDef] = []
	for tier_data in [
		[&"gear_weapon_t1", 1, 2],
		[&"gear_armor_t1", 1, 3],
		[&"gear_weapon_t3", 3, 7],
		[&"gear_armor_t3", 3, 10],
	]:
		var gear := GearDef.new()
		gear.id = tier_data[0]
		gear.display_name = String(tier_data[0])
		gear.slot = &"armor" if String(tier_data[0]).contains("armor") else &"weapon"
		gear.tier = int(tier_data[1])
		gear.combat_power = int(tier_data[2])
		gear.recipe[&"iron"] = 1
		defs.append(gear)
	return defs


## Fast chain for volume probes: peasant -> soldier in 6 ticks, power 10,
## no gear — keeps MVP def VALUES out of the odds-monotonicity sweep.
func _fast_defs() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"soldier")
	defs.append(peasant)
	var soldier := UnitDef.new()
	soldier.id = &"soldier"
	soldier.display_name = "Soldier"
	soldier.training_time_hours = 0.1  # exactly 6 ticks
	soldier.combat_power = 10
	defs.append(soldier)
	return defs


func _engine(
	tunables: EconomyTunables,
	regimes: Array[RegimeDef],
	fast := true,
	with_suspicion := false,
	p_run_seed: int = RUN_SEED
) -> SimEngine:
	var engine := SimEngine.new(p_run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(regimes, _identity()))
	if fast:
		engine.register_system(UnitLifecycleSystem.new(_fast_defs(), [], tunables))
	else:
		engine.register_system(UnitLifecycleSystem.new(_unit_defs(), _gear_defs(), tunables))
	engine.register_system(AssaultResolver.new(tunables))
	if with_suspicion:
		var defs := _fast_defs() if fast else _unit_defs()
		engine.register_system(SuspicionSystem.new(tunables, defs))
	return engine


func _start(engine: SimEngine) -> RunLifecycleSystem:
	engine.submit_command(&"run_start", &"", 0)
	engine.tick()
	return engine.get_system(&"run") as RunLifecycleSystem


func _resolver(engine: SimEngine) -> AssaultResolver:
	return engine.get_system(&"assault") as AssaultResolver


func _units_system(engine: SimEngine) -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


func _suspicion(engine: SimEngine) -> SuspicionSystem:
	return engine.get_system(&"suspicion") as SuspicionSystem


## Accepts the next gate offer and marches it into the fast army (peasant ->
## soldier in 6 ticks). Returns when the soldier count grew by EXACTLY one:
## the gate is drained every pass (offers never pile up mid-march) and only
## ONE idle peasant is assigned per call.
func _field_soldier(engine: SimEngine) -> void:
	var units := _units_system(engine)
	var before := units.unit_count(&"soldier")
	while units.unit_count(&"soldier") <= before:
		for uid in units.offer_ids():
			engine.submit_command(&"recruit_accept", &"", uid)
		engine.fast_forward(1)
		var idle := units.idle_units(&"peasant")
		if not idle.is_empty():
			engine.submit_command(&"assign_role", &"soldier", idle[0])
			engine.fast_forward(7)  # drain + the 6-tick training
		else:
			engine.fast_forward(3)  # wait for the next arrival


func _field_soldiers(engine: SimEngine, count: int) -> void:
	for _i in count:
		_field_soldier(engine)


## Marches one unit through the REAL chain to the target rank (militia ->
## trainee -> knight|archer, t1 gear funded through the documented test seam).
func _field_rank(engine: SimEngine, target: StringName) -> void:
	var units := _units_system(engine)
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
	# Knight 12h / archer 6h — wait out the longest timer, then gear + promote.
	engine.fast_forward(12 * 60 + 1)
	engine.set_resource(&"iron", 100)
	engine.set_resource(&"timber", 100)
	for slot in units.missing_gear_slots(peasant):
		var gear_id := &"gear_%s_t1" % String(slot)
		engine.submit_command(&"equip_gear", gear_id, peasant)
	engine.fast_forward(1)
	engine.submit_command(&"promote", &"", peasant)
	engine.fast_forward(1)


## The M1 floor line through real content: 1 knight t1 + 1 archer t1 = 23.
func _field_floor(engine: SimEngine) -> void:
	_field_rank(engine, &"knight")
	_field_rank(engine, &"archer")


func _events_of_type(engine: SimEngine, type: StringName) -> Array[Dictionary]:
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


func _beats(engine: SimEngine) -> Array[Dictionary]:
	return _events_of_type(engine, &"assault_beat")


# --- Odds formula: exactness at the floor + the data contract -----------------


func test_odds_breakdown_exact_at_floor() -> void:
	# The odds screen's whole data contract at the M1 floor line: knight t1
	# (10+2+3) + archer t1 (6+2) = 23 vs neutral garrison 60 -> 277 permille.
	var engine := _engine(_real_tunables(), [_regime()], false)
	_start(engine)
	_field_floor(engine)
	var resolver := _resolver(engine)
	assert_int(resolver.knight_floor_power()).is_equal(23)
	assert_int(resolver.garrison_base_power()).is_equal(60)
	var odds := resolver.assault_odds(engine)
	assert_int(int(odds["floor_power"])).is_equal(23)
	assert_bool(bool(odds["floor_met"])).is_true()
	var army: Dictionary = odds["army"]
	assert_int(int(army["power"])).is_equal(23)
	assert_int(int(army["units"])).is_equal(2)
	assert_int(int(army["def_power_sum"])).is_equal(16)
	assert_int(int(army["gear_power_sum"])).is_equal(7)
	assert_int(int(army["regime_multiplier_milli"])).is_equal(1000)
	assert_int(int(army["score_milli"])).is_equal(23000)
	var garrison: Dictionary = odds["garrison"]
	assert_int(int(garrison["base_power"])).is_equal(60)
	assert_int(int(garrison["strength_milli"])).is_equal(60000)
	assert_int(int(odds["win_permille"])).is_equal(277)
	# Per-unit contributions, roster order: knight first (fielded first).
	var per_unit: Array = army["per_unit"]
	assert_int(per_unit.size()).is_equal(2)
	assert_int(int(per_unit[0]["def_power"])).is_equal(10)
	assert_int(int(per_unit[0]["gear_power"])).is_equal(5)
	assert_int(int(per_unit[0]["total"])).is_equal(15)
	assert_int(int(per_unit[1]["def_power"])).is_equal(6)
	assert_int(int(per_unit[1]["gear_power"])).is_equal(2)
	assert_int(int(per_unit[1]["total"])).is_equal(8)


func test_regime_combat_modifiers_apply_to_the_correct_side() -> void:
	# One combat modifier per flavor, applied to exactly one side: the two
	# garrison kinds scale the castle (army score untouched), the two army
	# kinds scale the army (garrison untouched). Exact permilles at power 23.
	var expected := {
		"gilded_crown": {"kind": "garrison_multiplier", "win": 242, "army_m": 1000, "garrison_m": 1200},
		"velvet_fist": {"kind": "garrison_multiplier", "win": 298, "army_m": 1000, "garrison_m": 900},
		"iron_rotunda": {"kind": "army_score_multiplier", "win": 296, "army_m": 1100, "garrison_m": 1000},
		"paper_crown": {"kind": "army_score_multiplier", "win": 266, "army_m": 950, "garrison_m": 1000},
	}
	for regime in _flavors():
		var engine := _engine(_real_tunables(), [regime], false)
		_start(engine)
		_field_floor(engine)
		var odds := _resolver(engine).assault_odds(engine)
		var want: Dictionary = expected[String(regime.id)]
		var army: Dictionary = odds["army"]
		var garrison: Dictionary = odds["garrison"]
		assert_int(int(odds["win_permille"])).is_equal(int(want["win"]))
		assert_str(String(garrison["modifier_kind"])).is_equal(String(want["kind"]))
		assert_int(int(army["regime_multiplier_milli"])).is_equal(int(want["army_m"]))
		assert_int(int(garrison["regime_multiplier_milli"])).is_equal(int(want["garrison_m"]))
		# The modifier's side is the ONLY thing that moved vs neutral (23/60).
		if String(want["kind"]) == "garrison_multiplier":
			assert_int(int(army["score_milli"])).is_equal(23000)
		else:
			assert_int(int(garrison["strength_milli"])).is_equal(60000)


# --- Monotonicity: surplus and quality raise the visible odds ------------------


func test_odds_monotone_in_army_power_all_flavors() -> void:
	# More power NEVER lowers the odds — the monotonicity seam, swept across
	# the growth curve (1..7 soldiers, power 10..70) and every flavor.
	for regime in _flavors():
		var engine := _engine(_tunables(), [regime])
		_start(engine)
		var previous := -1
		var at_floor := -1
		var at_seven := -1
		for count in range(1, 8):
			_field_soldiers(engine, 1)
			var odds := _resolver(engine).assault_odds(engine)
			var permille := int(odds["win_permille"])
			assert_int(permille).is_greater_equal(previous)
			if count == 2:
				assert_bool(bool(odds["floor_met"])).is_false()  # power 20 < 23
			if count == 3:  # power 30 — the first step over the floor
				at_floor = permille
				assert_bool(bool(odds["floor_met"])).is_true()
			if count == 7:
				at_seven = permille
			previous = permille
		assert_int(at_seven).is_greater(at_floor)  # surplus visibly raises odds


func test_gear_quality_raises_odds() -> void:
	# Quality surplus: refitting the knight t1 -> t3 (+5 weapon, +7 armor)
	# raises the odds at the SAME unit count. 23 -> 35 power: 277 -> 368.
	var engine := _engine(_real_tunables(), [_regime()], false)
	_start(engine)
	_field_floor(engine)
	var units := _units_system(engine)
	var before := int(_resolver(engine).assault_odds(engine)["win_permille"])
	var knight_uid := 0
	for entry in units.army_contributions():
		if entry["def"] == &"knight":
			knight_uid = int(entry["uid"])
	assert_int(knight_uid).is_not_equal(0)
	engine.set_resource(&"iron", 1000)
	engine.set_resource(&"timber", 1000)
	engine.submit_command(&"equip_gear", &"gear_weapon_t3", knight_uid)
	engine.submit_command(&"equip_gear", &"gear_armor_t3", knight_uid)
	engine.fast_forward(1)
	var after: Dictionary = _resolver(engine).assault_odds(engine)
	assert_int(int(after["army"]["power"])).is_equal(35)
	assert_int(int(after["win_permille"])).is_equal(368)
	assert_int(int(after["win_permille"])).is_greater(before)


func test_breakdown_sums_to_displayed_probability() -> void:
	# The odds screen cannot lie: the displayed permille is EXACTLY the
	# arithmetic of its own breakdown parts, at every army size and flavor.
	for regime in _flavors():
		var engine := _engine(_tunables(), [regime])
		_start(engine)
		for _count in range(1, 6):
			_field_soldiers(engine, 1)
			var odds := _resolver(engine).assault_odds(engine)
			var army: Dictionary = odds["army"]
			var garrison: Dictionary = odds["garrison"]
			var total_power := 0
			for entry in army["per_unit"]:
				total_power += int(entry["total"])
			# per-unit totals sum to the army power; power x multiplier is the
			# score; the two sides reproduce the displayed permille exactly.
			assert_int(total_power).is_equal(int(army["power"]))
			assert_int(int(army["power"]) * int(army["regime_multiplier_milli"])).is_equal(int(army["score_milli"]))
			var recomputed := int(army["score_milli"]) * 1000 / (int(army["score_milli"]) + int(garrison["strength_milli"]))
			assert_int(recomputed).is_equal(int(odds["win_permille"]))


# --- The floor gate: a floor, never a trigger -----------------------------------


func test_commit_refused_below_floor_with_reason() -> void:
	var engine := _engine(_tunables(), [_regime()])
	_start(engine)
	_field_soldiers(engine, 2)  # power 20 < 23
	var resolver := _resolver(engine)
	assert_bool(resolver.floor_met(engine)).is_false()
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	var denials := _events_of_type(engine, &"assault_denied")
	assert_int(denials.size()).is_equal(1)
	assert_int(int(denials[0]["value"])).is_equal(AssaultResolver.REASON_BELOW_FLOOR)
	assert_int(int(denials[0]["value2"])).is_equal(20)
	assert_int(_beats(engine).size()).is_equal(0)
	assert_int(_events_of_type(engine, &"assault_won").size()).is_equal(0)
	assert_int(_events_of_type(engine, &"assault_lost").size()).is_equal(0)
	assert_int(_units_system(engine).army_power()).is_equal(20)  # nothing died
	# The refusal is a denial, not a resolution: the run is still live.
	assert_bool((engine.get_system(&"run") as RunLifecycleSystem).is_running()).is_true()


func test_commit_refused_without_running_run() -> void:
	var engine := _engine(_tunables(), [_regime()])
	_field_soldiers(engine, 3)  # no run_start: power is fine, the run is not
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	var denials := _events_of_type(engine, &"assault_denied")
	assert_int(denials.size()).is_equal(1)
	assert_int(int(denials[0]["value"])).is_equal(AssaultResolver.REASON_NOT_RUNNING)


func test_odds_query_is_pure() -> void:
	# The query draws no RNG and writes no state — the odds screen can call
	# it every frame for free.
	var engine := _engine(_tunables(), [_regime()])
	_start(engine)
	_field_soldiers(engine, 3)
	var rng_before := engine.rng.state
	var hash_before := engine.state_hash()
	_resolver(engine).assault_odds(engine)
	_resolver(engine).assault_odds(engine)
	assert_int(engine.rng.state).is_equal(rng_before)
	assert_int(engine.state_hash()).is_equal(hash_before)


# --- Determinism: same seed -> same outcome + same beat sequence ----------------


func test_resolution_determinism_twin_engines() -> void:
	# Twin engines, same seed, same script; one driven live (tick), one via
	# fast_forward: identical outcome, identical beat sequence, identical
	# rng stream + final hash (live == catch-up, the gate's determinism
	# statement applied to the assault).
	var tunables := _tunables()
	var live := _engine(tunables, [_regime()])
	_start(live)
	_field_soldiers(live, 4)
	live.submit_command(&"commit_assault", &"", 0)
	for _i in 3:
		live.tick()

	var twin := _engine(tunables, [_regime()])
	_start(twin)
	_field_soldiers(twin, 4)
	twin.submit_command(&"commit_assault", &"", 0)
	twin.fast_forward(3)

	var live_won := _events_of_type(live, &"assault_won").size()
	var live_lost := _events_of_type(live, &"assault_lost").size()
	assert_int(live_won + live_lost).is_equal(1)  # exactly one verdict
	assert_int(_events_of_type(twin, &"assault_won").size()).is_equal(live_won)
	assert_int(_events_of_type(twin, &"assault_lost").size()).is_equal(live_lost)
	var live_beats := _beats(live)
	var twin_beats := _beats(twin)
	assert_int(live_beats.size()).is_equal(4)
	assert_int(twin_beats.size()).is_equal(4)
	for i in 4:
		assert_str(String(live_beats[i]["subject"])).is_equal(String(twin_beats[i]["subject"]))
		assert_int(int(live_beats[i]["value"])).is_equal(int(twin_beats[i]["value"]))
		assert_int(int(live_beats[i]["value2"])).is_equal(int(twin_beats[i]["value2"]))
	assert_int(live.rng.state).is_equal(twin.rng.state)
	assert_int(live.state_hash()).is_equal(twin.state_hash())


# --- The failed assault: set-back rules, exactly ---------------------------------


func _forced_loss_engine(p_run_seed: int = RUN_SEED) -> SimEngine:
	# Garrison 10,000,000: win_permille floors to 0 — every roll loses.
	return _engine(_tunables(10_000_000), [_regime()], true, true, p_run_seed)


func test_failed_assault_is_a_setback_not_death() -> void:
	var engine := _forced_loss_engine()
	_start(engine)
	_field_soldiers(engine, 4)  # power 40
	var units := _units_system(engine)
	var uids_before: Array[int] = []
	for entry in units.army_contributions():
		uids_before.append(int(entry["uid"]))
	var shown := int(_resolver(engine).assault_odds(engine)["win_permille"])
	assert_int(shown).is_equal(0)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)

	# Beats: 4 phases, army remaining monotone non-increasing, ending at the
	# TRUE survivors (2 soldiers = 20000 milli).
	var beats := _beats(engine)
	assert_int(beats.size()).is_equal(4)
	assert_str(String(beats[0]["subject"])).is_equal("advance")
	assert_str(String(beats[1]["subject"])).is_equal("skirmish")
	assert_str(String(beats[2]["subject"])).is_equal("gate")
	assert_str(String(beats[3]["subject"])).is_equal("rout")
	for i in range(1, beats.size()):
		assert_bool(int(beats[i]["value"]) <= int(beats[i - 1]["value"])).is_true()
	assert_int(int(beats[3]["value"])).is_equal(20000)

	# Casualties: ceil(0.5 x 4) = 2, NEWEST first (the vanguard holds).
	var casualties := _events_of_type(engine, &"assault_casualties")
	assert_int(casualties.size()).is_equal(1)
	assert_int(int(casualties[0]["value"])).is_equal(2)
	assert_int(int(casualties[0]["value2"])).is_equal(20)
	var survivors: Array[int] = []
	for entry in units.army_contributions():
		survivors.append(int(entry["uid"]))
	assert_array(survivors).is_equal([uids_before[0], uids_before[1]] as Array[int])
	assert_int(units.army_power()).is_equal(20)

	# The spike: exactly +20 through the suspicion seam, source "assault".
	assert_int(_suspicion(engine).suspicion).is_equal(20)
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(1)
	assert_str(String(rose[0]["subject"])).is_equal("assault")
	assert_int(int(rose[0]["value"])).is_equal(20)

	# The verdict: the run KEEPS RUNNING; the odds that were shown rode on
	# the event for the vignette.
	var lost := _events_of_type(engine, &"assault_lost")
	assert_int(lost.size()).is_equal(1)
	assert_int(int(lost[0]["value"])).is_equal(shown)
	assert_int(int(lost[0]["value2"])).is_equal(40)
	assert_bool((engine.get_system(&"run") as RunLifecycleSystem).is_running()).is_true()


func test_failed_assault_can_be_reattempted_after_rebuilding() -> void:
	var engine := _forced_loss_engine()
	_start(engine)
	_field_soldiers(engine, 4)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	assert_int(_units_system(engine).army_power()).is_equal(20)  # 2 fell

	# Below the floor again: re-commit refused with the floor reason.
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	var denials := _events_of_type(engine, &"assault_denied")
	assert_int(denials.size()).is_equal(1)
	assert_int(int(denials[0]["value"])).is_equal(AssaultResolver.REASON_BELOW_FLOOR)

	# Rebuild past the floor: the commit is unlocked again (and resolves —
	# the loss fixture loses, but the DENIAL list must not grow).
	_field_soldier(engine)
	assert_int(_units_system(engine).army_power()).is_equal(30)
	assert_bool(_resolver(engine).floor_met(engine)).is_true()
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	assert_int(_events_of_type(engine, &"assault_denied").size()).is_equal(1)
	assert_int(_events_of_type(engine, &"assault_lost").size()).is_equal(2)


func test_failed_assault_spike_damped_by_relief_window() -> void:
	# The spike rides the SAME damped path as every other rise: inside a
	# post-crackdown relief window it halves (20 -> 10).
	var engine := _forced_loss_engine()
	_start(engine)
	_field_soldiers(engine, 3)
	var heat := _suspicion(engine)
	heat.relief_until_tick = engine.tick_count + 240  # oracle probe (public field)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	var rose := _events_of_type(engine, &"suspicion_rose")
	assert_int(rose.size()).is_equal(1)
	assert_int(int(rose[0]["value"])).is_equal(10)
	assert_int(heat.suspicion).is_equal(10)


func test_failed_assault_at_the_meters_edge_crushes() -> void:
	# The one place the set-back rule bends: a failed assault with the meter
	# at 90 spikes to 100 and the crush path ends the run (defeat, banked).
	var engine := _forced_loss_engine()
	_start(engine)
	_field_soldiers(engine, 3)
	_suspicion(engine).set_suspicion(90)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(2)  # spike+crush at T, resolve_victory drains at T+1
	assert_int(_events_of_type(engine, &"run_crushed").size()).is_equal(1)
	var run := engine.get_system(&"run") as RunLifecycleSystem
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_DEFEAT)
	assert_int(_events_of_type(engine, &"run_lost").size()).is_equal(1)
	assert_int(run.meta.legacy_points).is_greater(0)


# --- Victory wiring ---------------------------------------------------------------


func test_win_resolves_victory_in_the_same_tick() -> void:
	# Garrison 1: permille 967 at power 30 — find the first seed that wins
	# (deterministic search; 25 candidates at ~97% each is beyond doubt).
	var winning_seed := 0
	for candidate in range(RUN_SEED, RUN_SEED + 25):
		var probe := _engine(_tunables(1), [_regime()], true, false, candidate)
		_start(probe)
		_field_soldiers(probe, 3)
		probe.submit_command(&"commit_assault", &"", 0)
		probe.fast_forward(1)
		if _events_of_type(probe, &"assault_won").size() == 1:
			winning_seed = candidate
			break
	assert_int(winning_seed).is_not_equal(0)

	var engine := _engine(_tunables(1), [_regime()], true, false, winning_seed)
	var run := _start(engine)
	var start_tick := engine.tick_count
	_field_soldiers(engine, 3)
	var odds := _resolver(engine).assault_odds(engine)
	assert_int(int(odds["win_permille"])).is_equal(967)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)

	# The full victory wiring: beats end on the throne, the verdict carries
	# the odds that were shown, run_won lands in the SAME tick, the bank and
	# the chronicle snapshot the army that fought.
	var beats := _beats(engine)
	assert_int(beats.size()).is_equal(4)
	assert_str(String(beats[3]["subject"])).is_equal("throne")
	assert_int(int(beats[3]["value2"])).is_equal(0)  # the garrison is broken
	var won := _events_of_type(engine, &"assault_won")
	assert_int(won.size()).is_equal(1)
	assert_int(int(won[0]["value"])).is_equal(967)
	assert_int(int(won[0]["value2"])).is_equal(30)
	var run_won := _events_of_type(engine, &"run_won")
	assert_int(run_won.size()).is_equal(1)
	assert_int(int(run_won[0]["tick"])).is_equal(int(won[0]["tick"]))
	assert_int(run.run_status()).is_equal(RunLifecycleSystem.STATUS_ENDED)
	assert_int(run.run_outcome()).is_equal(RunLifecycleSystem.OUTCOME_VICTORY)
	var duration_h := (engine.tick_count - start_tick) / SimEngine.TICKS_PER_SIM_HOUR
	assert_int(run.last_run_score()).is_equal(duration_h + 30 + RunLifecycleSystem.WIN_BONUS)
	assert_int(run.meta.runs_recorded).is_equal(1)
	assert_int(int(run.meta.chronicle[0]["army_power"])).is_equal(30)
	assert_str(String(run.meta.chronicle[0]["outcome"])).is_equal("victory")


# --- Stateless resolver: restart safety -------------------------------------------


func test_stateless_save_roundtrip_and_restart_safety() -> void:
	var engine := _forced_loss_engine()
	_start(engine)
	_field_soldiers(engine, 4)
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)

	# The resolver serializes NOTHING and contributes a constant to the hash.
	var resolver := _resolver(engine)
	assert_bool(resolver.to_dict().is_empty()).is_true()
	assert_int(resolver.state_hash()).is_equal(0)

	# Round-trip with the resolver registered: lockstep hash, and the commit
	# still resolves on the restored engine (nothing needed restoring).
	var state := engine.to_dict()
	var restored := _forced_loss_engine()
	restored.apply_state_dict(state)
	assert_int(restored.state_hash()).is_equal(engine.state_hash())
	_field_soldiers(restored, 1)  # rebuild over the floor (30 again)
	restored.submit_command(&"commit_assault", &"", 0)
	restored.fast_forward(1)
	assert_int(_events_of_type(restored, &"assault_lost").size()).is_equal(1)

	# Restart: no assault state existed to survive — the roster the units
	# system cleared is the whole story (army 0, floor unmet, commit denied).
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	assert_int(_units_system(engine).army_power()).is_equal(0)
	assert_bool(_resolver(engine).floor_met(engine)).is_false()
	engine.submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	var denials := _events_of_type(engine, &"assault_denied")
	assert_int(denials.size()).is_equal(1)
	assert_int(int(denials[0]["value"])).is_equal(AssaultResolver.REASON_BELOW_FLOOR)
	assert_int(int(denials[0]["value2"])).is_equal(0)


# --- The units-system army-loss seam, directly ------------------------------------


func test_apply_army_losses_direct_seam() -> void:
	var engine := _engine(_tunables(), [_regime()])
	_start(engine)
	_field_soldiers(engine, 3)
	var units := _units_system(engine)
	var uids: Array[int] = []
	for entry in units.army_contributions():
		uids.append(int(entry["uid"]))
	var removed := units.apply_army_losses(2)
	# Newest first; gear would go with them (fast defs carry none); survivors
	# keep their places; non-army units are never eligible.
	assert_array(removed).is_equal([uids[2], uids[1]] as Array[int])
	assert_int(units.army_power()).is_equal(10)
	var over := units.apply_army_losses(99)
	assert_array(over).is_equal([uids[0]] as Array[int])
	assert_int(units.army_power()).is_equal(0)
	assert_int(units.apply_army_losses(5).size()).is_equal(0)
