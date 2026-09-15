## Unit tests for the resource production system (T-SIM-02).
## Mirrors sim/systems/production_system.gd (test-mapping rule). Hawkeye
## seam coverage: exact rate math (incl. the x0.85 regime-quirk remainder
## carry), upgrade cost curve across the milestone boundaries 1/9/10/11/
## 19/20/21, worker assignment/reassignment determinism, denial codes,
## events, and the to_dict/from_dict save round-trip (lockstep hash).
extends GdUnitTestSuite


# --- Fixtures (in-code content; same classes the .tres files use) ----------


func _tunables() -> EconomyTunables:
	# Bare defaults ARE the R4 seeds: band [1.08, 1.12], milestone x2.0.
	return EconomyTunables.new()


func _farm() -> BuildingDef:
	# The content-schema example farm: food 6/h/worker, timber 15, r=1.08,
	# milestones [10, 20], max 30, 2 slots at level 1.
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
	def.icon_id = &"icon_farm"
	return def


func _camp() -> BuildingDef:
	# Timber camp with the same 6/h shape (quirk tests) at r=1.10.
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
	def.icon_id = &"icon_camp"
	return def


func _mine() -> BuildingDef:
	# Multi-resource cost line (iron producer, dearest r=1.12).
	var def := BuildingDef.new()
	def.id = &"mine"
	def.display_name = "Iron Mine"
	def.resource_produced = &"iron"
	def.base_production_per_worker_hour = 3.0
	def.worker_slots_base = 3
	var cost: Dictionary[StringName, int] = {}
	cost[&"timber"] = 40
	cost[&"food"] = 20
	def.base_cost = cost
	def.cost_growth = 1.12
	var milestones: Array[int] = [10, 20]
	def.milestone_levels = milestones
	def.max_level = 30
	def.icon_id = &"icon_mine"
	return def


func _grounds() -> BuildingDef:
	# Non-producing building (training grounds shape): empty
	# resource_produced, 0 worker slots at every level.
	var def := BuildingDef.new()
	def.id = &"grounds"
	def.display_name = "Training Grounds"
	def.resource_produced = &""
	def.base_production_per_worker_hour = 0.0
	def.worker_slots_base = 0
	var cost: Dictionary[StringName, int] = {}
	cost[&"food"] = 25
	def.base_cost = cost
	def.cost_growth = 1.08
	var milestones: Array[int] = [10, 20]
	def.milestone_levels = milestones
	def.max_level = 30
	def.icon_id = &"icon_grounds"
	return def


func _regime(quirk_kind: StringName, target: StringName, value: float) -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = &"test_regime"
	regime.display_name = "Test Regime"
	var combat := RegimeModifier.new()
	combat.kind = &"garrison_multiplier"
	combat.value = 1.2
	regime.combat_modifier = combat
	var quirk := RegimeModifier.new()
	quirk.kind = quirk_kind
	quirk.target = target
	quirk.value = value
	regime.economy_quirk = quirk
	return regime


func _defs(buildings: Array) -> Array[BuildingDef]:
	var typed: Array[BuildingDef] = []
	for building in buildings:
		typed.append(building)
	return typed


func _engine(buildings: Array, regime: RegimeDef = null, run_seed := 7) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(ProductionSystem.new(_defs(buildings), _tunables(), regime))
	return engine


func _production(engine: SimEngine) -> ProductionSystem:
	return engine.get_system(&"production") as ProductionSystem


func _grant(engine: SimEngine, food: int, timber: int, iron: int) -> void:
	engine.set_resource(&"food", food)
	engine.set_resource(&"timber", timber)
	engine.set_resource(&"iron", iron)


## Builds the building (0 -> 1) with granted resources, at tick 1, then
## zeroes the pool so exact-total assertions start from a clean slate.
func _build(engine: SimEngine, id: StringName) -> void:
	_grant(engine, 1_000_000, 1_000_000, 1_000_000)
	engine.submit_command(&"upgrade_building", id, 1)
	engine.tick()
	_grant(engine, 0, 0, 0)


## Upgrades (grant + submit + tick) until the building reaches target
## level. Grants inside the loop so upgrades can never deny-stall.
func _reach_level(engine: SimEngine, id: StringName, target: int) -> void:
	var production := _production(engine)
	while production.building_level(id) < target:
		_grant(engine, 1_000_000, 1_000_000, 1_000_000)
		engine.submit_command(&"upgrade_building", id, 1)
		engine.tick()


func _events_of_type(engine: SimEngine, type: StringName) -> Array[Dictionary]:
	# Copy fields out of the pooled ring (references are slot-reuse-unsafe).
	var found: Array[Dictionary] = []
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			found.append({
				"subject": event.subject, "value": event.value, "value2": event.value2,
			})
	return found


# --- Rate math: production matches declared data exactly -------------------


func test_level_one_rate_matches_declared_data_exactly() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	engine.submit_command(&"add_worker", &"production", 1)
	engine.submit_command(&"assign_worker", &"farm", 1)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	# Farm declares 6 food per worker-hour: exactly 6 after one sim-hour.
	assert_int(engine.get_resource(&"food")).is_equal(6)
	assert_int(_production(engine).accumulated_milli_unit_seconds(&"farm")).is_equal(0)  # zero drift, exact


func test_production_scales_linearly_with_workers_and_level() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	engine.submit_command(&"add_worker", &"production", 2)
	engine.submit_command(&"assign_worker", &"farm", 2)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.get_resource(&"food")).is_equal(12)  # 2 workers x 6
	_reach_level(engine, &"farm", 2)
	engine.set_resource(&"food", 0)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.get_resource(&"food")).is_equal(24)  # x2 level, 2 workers


func test_milestone_doubles_rate_at_levels_10_and_20() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	var production := _production(engine)
	# 9 -> 10: 54/h jumps to 120/h (x2 milestone on top of linear level).
	_reach_level(engine, &"farm", 9)
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(54_000)
	_reach_level(engine, &"farm", 10)
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(120_000)
	_reach_level(engine, &"farm", 20)
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(480_000)
	_reach_level(engine, &"farm", 21)
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(504_000)


func test_rate_is_zero_when_unbuilt_unassigned_or_non_producing() -> void:
	var engine := _engine([_farm(), _grounds()])
	var production := _production(engine)
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(0)
	assert_int(production.production_rate_milli(&"farm")).is_equal(0)
	_build(engine, &"farm")
	assert_int(production.production_rate_milli(&"farm")).is_equal(0)  # no workers
	_build(engine, &"grounds")
	assert_int(production.production_rate_milli_per_worker(&"grounds")).is_equal(0)


func test_non_producing_building_has_no_slots() -> void:
	var engine := _engine([_grounds()])
	_build(engine, &"grounds")
	engine.submit_command(&"add_worker", &"production", 3)
	engine.submit_command(&"assign_worker", &"grounds", 1)
	engine.tick()
	assert_int(_production(engine).assigned_workers(&"grounds")).is_equal(0)
	var denied := _events_of_type(engine, &"assignment_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(ProductionSystem.REASON_NO_FREE_SLOTS)
	_reach_level(engine, &"grounds", 5)
	assert_int(_production(engine).worker_slots(&"grounds")).is_equal(0)


# --- The x0.85 regime quirk: remainder carry, never lost -------------------


func test_quirk_085_remainder_carries_exactly() -> void:
	# Regime timber tax x0.85 on a 6/h camp => 5.1/h: 5 whole units after one
	# hour, the 0.1 remainder carried in the accumulator; 51 exact after 10h.
	var engine := _engine([_camp()], _regime(&"production_multiplier", &"timber", 0.85))
	_build(engine, &"camp")
	engine.submit_command(&"add_worker", &"production", 1)
	engine.submit_command(&"assign_worker", &"camp", 1)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.get_resource(&"timber")).is_equal(5)
	var production := _production(engine)
	assert_int(production.accumulated_milli_unit_seconds(&"camp")).is_equal(360_000)  # exactly 0.1 unit carried
	engine.fast_forward(9 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.get_resource(&"timber")).is_equal(51)  # 5.1 x 10, exact
	assert_int(production.accumulated_milli_unit_seconds(&"camp")).is_equal(0)


func test_quirk_targets_only_its_resource() -> void:
	var engine := _engine([_farm(), _camp()], _regime(&"production_multiplier", &"timber", 0.85))
	var production := _production(engine)
	_build(engine, &"farm")
	_build(engine, &"camp")
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(6_000)
	assert_int(production.production_rate_milli_per_worker(&"camp")).is_equal(5_100)


func test_quirk_all_targets_every_resource() -> void:
	var engine := _engine([_farm(), _camp()], _regime(&"production_multiplier", &"all", 0.5))
	var production := _production(engine)
	_build(engine, &"farm")
	_build(engine, &"camp")
	assert_int(production.production_rate_milli_per_worker(&"farm")).is_equal(3_000)
	assert_int(production.production_rate_milli_per_worker(&"camp")).is_equal(3_000)


# --- Upgrade cost curve: r-band growth + x2 milestone boosts ---------------


func test_upgrade_cost_curve_across_milestone_boundaries() -> void:
	# Farm: timber 15, r=1.08, milestones [10, 20] x2. Integer milli-space
	# curve (single floored division): the x2 boosts land AT 10 and 20 and
	# compound for every level beyond (10 <= L < 20 pays x2, L >= 20 pays x4).
	var engine := _engine([_farm()])
	var production := _production(engine)
	_grant(engine, 0, 100_000_000, 0)
	var expected := {1: 15, 9: 27, 10: 59, 11: 64, 19: 119, 20: 257, 21: 278}
	for target in [1, 9, 10, 11, 19, 20, 21]:
		_reach_level(engine, &"farm", target - 1)
		var cost := production.upgrade_cost(&"farm")
		assert_int(cost.size()).is_equal(1)
		assert_int(cost[&"timber"]).is_equal(int(expected[target]))


func test_cost_curve_is_strictly_increasing_across_milestones() -> void:
	var engine := _engine([_farm()])
	var production := _production(engine)
	_grant(engine, 0, 1_000_000_000, 0)
	var previous := 0
	for level in range(1, 31):
		_reach_level(engine, &"farm", level - 1)
		var cost := production.upgrade_cost(&"farm")
		assert_int(cost[&"timber"]).is_greater(previous)
		previous = cost[&"timber"]


func test_cost_quirk_multiplies_upgrade_costs() -> void:
	# building_cost_multiplier x1.2 on everything: cost(1) = 15 x 1.2 = 18
	# exactly (read at level 0, where the next level is the construction).
	var engine := _engine([_farm()], _regime(&"building_cost_multiplier", &"all", 1.2))
	var cost := _production(engine).upgrade_cost(&"farm")
	assert_int(cost[&"timber"]).is_equal(18)
	# Targeted cost quirk: x1.5 on timber only -> 15 x 1.5 = 22.5 -> 22 (floor).
	var targeted := _engine([_farm()], _regime(&"building_cost_multiplier", &"timber", 1.5))
	var targeted_cost := _production(targeted).upgrade_cost(&"farm")
	assert_int(targeted_cost[&"timber"]).is_equal(22)


func test_multi_resource_cost_lines_are_exact() -> void:
	var engine := _engine([_mine()])
	var production := _production(engine)
	# Level 0 -> 1 costs exactly base_cost (construction).
	var cost := production.upgrade_cost(&"mine")
	assert_int(cost.size()).is_equal(2)
	assert_int(cost[&"timber"]).is_equal(40)
	assert_int(cost[&"food"]).is_equal(20)


# --- Building / upgrading: payments, events, denials -----------------------


func test_build_from_zero_costs_base_and_emits_built_event() -> void:
	var engine := _engine([_farm()])
	_grant(engine, 0, 15, 0)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.tick()
	assert_int(_production(engine).building_level(&"farm")).is_equal(1)
	assert_int(engine.get_resource(&"timber")).is_equal(0)
	var built := _events_of_type(engine, &"building_built")
	assert_int(built.size()).is_equal(1)
	assert_str(String(built[0]["subject"])).is_equal("farm")
	assert_int(int(built[0]["value"])).is_equal(1)
	# Building again is an upgrade now, not a second build (cost(2)=16).
	_grant(engine, 0, 16, 0)
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.tick()
	assert_int(_production(engine).building_level(&"farm")).is_equal(2)
	assert_int(engine.get_resource(&"timber")).is_equal(0)
	var upgraded := _events_of_type(engine, &"building_upgraded")
	assert_int(upgraded.size()).is_equal(1)
	assert_int(int(upgraded[0]["value"])).is_equal(2)


func test_upgrade_denied_unaffordable_leaves_state_intact() -> void:
	var engine := _engine([_farm()])
	_grant(engine, 0, 14, 0)  # one short of the 15 base cost
	engine.submit_command(&"upgrade_building", &"farm", 1)
	engine.tick()
	assert_int(_production(engine).building_level(&"farm")).is_equal(0)
	assert_int(engine.get_resource(&"timber")).is_equal(14)
	var denied := _events_of_type(engine, &"upgrade_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(ProductionSystem.REASON_UNAFFORDABLE)


func test_multi_resource_upgrade_denied_keeps_all_resources() -> void:
	# All-or-nothing: rich in timber, one food short -> nothing deducted.
	var engine := _engine([_mine()])
	_grant(engine, 19, 1_000_000, 0)
	engine.submit_command(&"upgrade_building", &"mine", 1)
	engine.tick()
	assert_int(_production(engine).building_level(&"mine")).is_equal(0)
	assert_int(engine.get_resource(&"timber")).is_equal(1_000_000)
	assert_int(engine.get_resource(&"food")).is_equal(19)
	assert_int(_events_of_type(engine, &"upgrade_denied").size()).is_equal(1)


func test_upgrade_denied_at_max_level() -> void:
	var capped := BuildingDef.new()
	capped.id = &"shed"
	capped.display_name = "Shed"
	capped.resource_produced = &"food"
	capped.base_production_per_worker_hour = 1.0
	capped.worker_slots_base = 1
	var cost: Dictionary[StringName, int] = {}
	cost[&"timber"] = 5
	capped.base_cost = cost
	capped.cost_growth = 1.08
	var milestones: Array[int] = [2]
	capped.milestone_levels = milestones
	capped.max_level = 2
	var engine := _engine([capped])
	_reach_level(engine, &"shed", 2)
	engine.submit_command(&"upgrade_building", &"shed", 1)
	engine.tick()
	assert_int(_production(engine).building_level(&"shed")).is_equal(2)
	assert_int(_production(engine).upgrade_cost(&"shed").size()).is_equal(0)
	var denied := _events_of_type(engine, &"upgrade_denied")
	assert_int(denied.size()).is_equal(1)
	assert_int(int(denied[0]["value"])).is_equal(ProductionSystem.REASON_MAX_LEVEL)


func test_milestone_events_carry_level_and_multiplier() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	_reach_level(engine, &"farm", 10)
	_reach_level(engine, &"farm", 20)
	var milestones := _events_of_type(engine, &"building_milestone")
	assert_int(milestones.size()).is_equal(2)
	assert_int(int(milestones[0]["value"])).is_equal(10)
	assert_int(int(milestones[0]["value2"])).is_equal(2_000)  # x2.0 in milli
	assert_int(int(milestones[1]["value"])).is_equal(20)
	assert_int(int(milestones[1]["value2"])).is_equal(4_000)  # x4.0 in milli


# --- Workers: pool, slots, assignment denials ------------------------------


func test_worker_pool_add_remove_semantics() -> void:
	var engine := _engine([_farm()])
	engine.submit_command(&"remove_worker", &"production", 1)  # empty pool
	engine.submit_command(&"add_worker", &"production", 0)  # invalid count
	engine.tick()
	assert_int(_production(engine).idle_workers()).is_equal(0)
	var denied := _events_of_type(engine, &"worker_pool_denied")
	assert_int(denied.size()).is_equal(2)
	assert_int(int(denied[0]["value"])).is_equal(ProductionSystem.REASON_NO_IDLE_WORKERS)
	assert_int(int(denied[1]["value"])).is_equal(ProductionSystem.REASON_INVALID_COUNT)
	engine.submit_command(&"add_worker", &"production", 2)
	engine.tick()
	assert_int(_production(engine).idle_workers()).is_equal(2)
	engine.submit_command(&"remove_worker", &"production", 1)
	engine.tick()
	assert_int(_production(engine).idle_workers()).is_equal(1)
	assert_int(_events_of_type(engine, &"worker_added").size()).is_equal(1)
	assert_int(_events_of_type(engine, &"worker_removed").size()).is_equal(1)


func test_assignment_denial_codes() -> void:
	var engine := _engine([_farm(), _camp()])
	_build(engine, &"farm")
	engine.submit_command(&"assign_worker", &"ghost", 1)  # unknown building
	engine.submit_command(&"assign_worker", &"camp", 1)  # camp never built
	engine.submit_command(&"add_worker", &"production", 2)
	engine.submit_command(&"assign_worker", &"farm", 3)  # only 2 idle
	engine.tick()
	engine.submit_command(&"add_worker", &"production", 2)
	engine.submit_command(&"assign_worker", &"farm", 2)  # fills both slots
	engine.submit_command(&"assign_worker", &"farm", 1)  # no free slots
	engine.tick()
	var production := _production(engine)
	assert_int(production.assigned_workers(&"farm")).is_equal(2)
	assert_int(production.idle_workers()).is_equal(2)
	var denied := _events_of_type(engine, &"assignment_denied")
	assert_int(denied.size()).is_equal(4)
	assert_int(int(denied[0]["value"])).is_equal(ProductionSystem.REASON_UNKNOWN_BUILDING)
	assert_int(int(denied[1]["value"])).is_equal(ProductionSystem.REASON_NOT_BUILT)
	assert_int(int(denied[2]["value"])).is_equal(ProductionSystem.REASON_NO_IDLE_WORKERS)
	assert_int(int(denied[3]["value"])).is_equal(ProductionSystem.REASON_NO_FREE_SLOTS)
	var assigned := _events_of_type(engine, &"worker_assigned")
	assert_int(assigned.size()).is_equal(1)
	assert_int(int(assigned[0]["value"])).is_equal(2)
	assert_int(int(assigned[0]["value2"])).is_equal(2)


func test_unassignment_denial_and_pool_return() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	engine.submit_command(&"add_worker", &"production", 1)
	engine.submit_command(&"assign_worker", &"farm", 1)
	engine.submit_command(&"unassign_worker", &"farm", 2)  # only 1 assigned
	engine.tick()
	assert_int(_events_of_type(engine, &"assignment_denied").size()).is_equal(1)
	engine.submit_command(&"unassign_worker", &"farm", 1)
	engine.tick()
	var production := _production(engine)
	assert_int(production.assigned_workers(&"farm")).is_equal(0)
	assert_int(production.idle_workers()).is_equal(1)
	var unassigned := _events_of_type(engine, &"worker_unassigned")
	assert_int(unassigned.size()).is_equal(1)
	assert_int(int(unassigned[0]["value2"])).is_equal(1)


func test_worker_slots_grow_one_per_level() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	var production := _production(engine)
	assert_int(production.worker_slots(&"farm")).is_equal(2)
	_reach_level(engine, &"farm", 2)
	assert_int(production.worker_slots(&"farm")).is_equal(3)
	_reach_level(engine, &"farm", 5)
	assert_int(production.worker_slots(&"farm")).is_equal(6)
	assert_int(production.worker_slots(&"ghost")).is_equal(0)


# --- Determinism: reassignment mid-run, hash sensitivity -------------------


func test_reassignment_mid_run_is_deterministic_and_redirects_flow() -> void:
	# Identical seed + identical command script at identical tick
	# boundaries => identical hash at every checkpoint (the T-SIM-01 oracle
	# extended through the production system).
	var script := func(engine: SimEngine) -> Array:
		var checkpoints: Array = []
		# Exactly the build costs: farm 15 timber, camp 10 food.
		_grant(engine, 10, 15, 0)
		engine.submit_command(&"add_worker", &"production", 2)
		engine.submit_command(&"upgrade_building", &"farm", 1)
		engine.submit_command(&"upgrade_building", &"camp", 1)
		engine.submit_command(&"assign_worker", &"farm", 2)
		engine.fast_forward(30)
		checkpoints.append(engine.state_hash())
		engine.submit_command(&"unassign_worker", &"farm", 2)
		engine.submit_command(&"assign_worker", &"camp", 2)
		engine.fast_forward(30)
		checkpoints.append(engine.state_hash())
		return checkpoints

	var first: Array = script.call(_engine([_farm(), _camp()], null, 20260915))
	var second: Array = script.call(_engine([_farm(), _camp()], null, 20260915))
	assert_array(first).is_equal(second)
	# The reassignment redirected the flow mid-run: 6 food from the first
	# half hour (2 workers x 6/h x 0.5h), then 6 timber from the second.
	var redirected := _engine([_farm(), _camp()], null, 20260915)
	script.call(redirected)
	assert_int(redirected.get_resource(&"food")).is_equal(6)
	assert_int(redirected.get_resource(&"timber")).is_equal(6)


func test_state_hash_separates_assignments() -> void:
	var make := func(assign_to_farm: int) -> int:
		var engine := _engine([_farm()])
		_build(engine, &"farm")
		engine.submit_command(&"add_worker", &"production", 2)
		engine.submit_command(&"assign_worker", &"farm", assign_to_farm)
		engine.tick()
		return _production(engine).state_hash()

	assert_int(make.call(1)).is_not_equal(make.call(2))


# --- Save round-trip: to_dict / from_dict lockstep --------------------------


func test_save_round_trip_resumes_in_lockstep_with_remainder() -> void:
	var original := _engine([_farm(), _camp()], null, 20260915)
	_build(original, &"farm")
	original.submit_command(&"add_worker", &"production", 1)
	original.submit_command(&"assign_worker", &"farm", 1)
	original.fast_forward(45)  # 6/h x 45 min = 4.5 units -> 4 banked + remainder
	assert_int(original.get_resource(&"food")).is_equal(4)
	assert_int(_production(original).accumulated_milli_unit_seconds(&"farm")).is_equal(1_800_000)  # half a unit carried

	var captured := original.to_dict()
	var system_state: Dictionary = captured["systems"]["production"]
	assert_int(int(system_state["workers_idle"])).is_equal(0)
	assert_int(system_state["buildings"].size()).is_equal(2)

	var restored := _engine([_farm(), _camp()], null, 20260915)
	assert_bool(restored.apply_state_dict(captured)).is_true()
	assert_int(restored.state_hash()).is_equal(original.state_hash())
	assert_int(restored.get_resource(&"food")).is_equal(4)
	# The carried remainder crosses the save boundary: 15 more minutes
	# complete the hour — exactly 6 on BOTH engines, remainder drained.
	original.fast_forward(15)
	restored.fast_forward(15)
	assert_int(original.get_resource(&"food")).is_equal(6)
	assert_int(restored.get_resource(&"food")).is_equal(6)
	assert_int(_production(original).accumulated_milli_unit_seconds(&"farm")).is_equal(0)
	assert_int(restored.state_hash()).is_equal(original.state_hash())


func test_from_dict_skips_unknown_buildings_loudly() -> void:
	var original := _engine([_farm()])
	_build(original, &"farm")
	original.submit_command(&"add_worker", &"production", 1)
	original.tick()
	var captured := original.to_dict()
	var restored := _engine([_camp()])  # different pack: farm is unknown here
	assert_bool(restored.apply_state_dict(captured)).is_true()
	assert_int(_production(restored).building_level(&"camp")).is_equal(0)
	assert_int(_production(restored).idle_workers()).is_equal(1)


# --- Engine integration ------------------------------------------------------


func test_commands_apply_at_tick_start_not_immediately() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	engine.submit_command(&"add_worker", &"production", 1)
	engine.submit_command(&"assign_worker", &"farm", 1)
	# Queued, not yet applied: no production this instant.
	assert_int(_production(engine).idle_workers()).is_equal(0)
	engine.tick()  # commands drain first, then the system ticks
	assert_int(_production(engine).assigned_workers(&"farm")).is_equal(1)
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR - 1)
	assert_int(engine.get_resource(&"food")).is_equal(6)  # full hour produced


func test_paused_engine_produces_nothing() -> void:
	var engine := _engine([_farm()])
	_build(engine, &"farm")
	engine.submit_command(&"add_worker", &"production", 1)
	engine.submit_command(&"assign_worker", &"farm", 1)
	engine.tick()
	engine.pause()
	engine.tick()
	engine.fast_forward(600)
	assert_int(engine.get_resource(&"food")).is_equal(0)
	var frozen := engine.state_hash()
	engine.resume()
	engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	assert_int(engine.get_resource(&"food")).is_equal(6)
	assert_int(engine.state_hash()).is_not_equal(frozen)
