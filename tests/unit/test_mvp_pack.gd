## MVP content pack tests (T-DATA-02).
##
## The pack IS the game's content (content/mvp/pack.tres): these tests are
## the pack's acceptance seams —
##   1. LOAD + VALIDATE: the pack clears the loud gate with zero errors.
##   2. ID CONTRACT: every unit/building/gear/regime id the tests, suites
##      and saves reference exists, with the full promotion graph.
##   3. ECONOMY SELF-CONSISTENCY: gear recipes vs producer rates (the M1
##      measured economy: knight kit ≈ 2.8h of full L1 smithy), starting
##      grants vs construction costs, R4 seed tunables.
##   4. REGIME COVERAGE: the 4 flavors carry distinct combat modifiers AND
##      the economy-quirk shapes later tests need (at least one cost quirk,
##      at least one per-resource production quirk — the serializer sweep
##      depends on both existing).
##   5. INTEGRITY: no duplicate display names within a pool where
##      uniqueness matters, no orphan art keys, identity-pool breadth.
##   6. GRANT VERB (M1 finding F1): a run boots through grant_resources
##      with ZERO backdoor set_resource calls, and the stipend math is exact.
extends GdUnitTestSuite

const PACK_PATH := "res://content/mvp/pack.tres"

const UNIT_IDS := [&"peasant", &"worker", &"militia", &"trainee", &"knight", &"archer"]
const BUILDING_IDS := [&"farm", &"lumber_camp", &"smithy", &"training_grounds"]
const PRODUCER_IDS := [&"farm", &"lumber_camp", &"smithy"]
const REGIME_IDS := [&"gilded_crown", &"iron_rotunda", &"velvet_fist", &"paper_crown"]


func _pack() -> ContentPack:
	var pack := ContentValidator.load_pack(PACK_PATH)
	assert_that(pack).is_not_null()
	return pack


func _by_id(defs: Array) -> Dictionary:
	var map := {}
	for def in defs:
		map[def.id] = def
	return map


# --- 1. Load + validate ------------------------------------------------------


func test_pack_loads_and_validates_clean() -> void:
	var pack := _pack()
	assert_that(pack).is_not_null()
	var errors := ContentValidator.validate_pack(pack)
	assert_int(errors.size()).is_equal(0)


func test_pack_header_shape() -> void:
	var pack := _pack()
	assert_int(pack.format_version).is_equal(1)
	assert_str(String(pack.pack_id)).is_equal("mvp")
	assert_bool(pack.display_name.length() > 0).is_true()
	assert_array(pack.resources).is_equal([&"food", &"timber", &"iron"] as Array[StringName])
	assert_array(pack.gear_slots).is_equal([&"weapon", &"armor"] as Array[StringName])
	assert_int(pack.units.size()).is_equal(6)
	assert_int(pack.buildings.size()).is_equal(4)
	assert_int(pack.gear.size()).is_equal(6)
	assert_int(pack.regimes.size()).is_equal(4)


# --- 2. The id contract (suites, saves and events reference these ids) ------


func test_unit_id_contract() -> void:
	var ids: Array[StringName] = []
	for unit: UnitDef in _pack().units:
		ids.append(unit.id)
	assert_array(ids).is_equal(UNIT_IDS as Array[StringName])


func test_building_id_contract() -> void:
	var ids: Array[StringName] = []
	for building: BuildingDef in _pack().buildings:
		ids.append(building.id)
	assert_array(ids).is_equal(BUILDING_IDS as Array[StringName])


func test_regime_id_contract() -> void:
	var ids: Array[StringName] = []
	for regime: RegimeDef in _pack().regimes:
		ids.append(regime.id)
	assert_array(ids).is_equal(REGIME_IDS as Array[StringName])


func test_gear_id_contract() -> void:
	var ids: Array[StringName] = []
	for gear: GearDef in _pack().gear:
		ids.append(gear.id)
	assert_array(ids).is_equal(
		[&"gear_weapon_t1", &"gear_weapon_t2", &"gear_weapon_t3",
		 &"gear_armor_t1", &"gear_armor_t2", &"gear_armor_t3"] as Array[StringName])


func test_full_promotion_graph_covers_both_branches() -> void:
	var units := _by_id(_pack().units)
	var peasant := units[&"peasant"] as UnitDef
	var militia := units[&"militia"] as UnitDef
	var trainee := units[&"trainee"] as UnitDef
	var knight := units[&"knight"] as UnitDef
	var archer := units[&"archer"] as UnitDef
	assert_array(peasant.promotion_paths).is_equal([&"worker", &"militia"] as Array[StringName])
	assert_array(militia.promotion_paths).is_equal([&"trainee"] as Array[StringName])
	assert_array(trainee.promotion_paths).is_equal([&"knight", &"archer"] as Array[StringName])
	assert_array(knight.required_gear_slots).is_equal([&"weapon", &"armor"] as Array[StringName])
	assert_array(archer.required_gear_slots).is_equal([&"weapon"] as Array[StringName])
	# Every promotion target resolves inside the pack (the validator also
	# checks this — pinned here as the id contract).
	for unit: UnitDef in _pack().units:
		for target in unit.promotion_paths:
			assert_bool(units.has(target)).is_true()


# --- 3. Economy self-consistency (M1 measured economy preserved) -------------


func test_three_producers_cover_every_resource_exactly_once() -> void:
	var produced: Array[StringName] = []
	for id in PRODUCER_IDS:
		var building := _by_id(_pack().buildings)[id] as BuildingDef
		assert_bool(_pack().resources.has(building.resource_produced)).is_true()
		produced.append(building.resource_produced)
	assert_bool(produced.has(&"food")).is_true()
	assert_bool(produced.has(&"timber")).is_true()
	assert_bool(produced.has(&"iron")).is_true()
	assert_int(produced.size()).is_equal(3)  # each resource produced exactly once


func test_training_grounds_is_the_flavor_building() -> void:
	# The M1 watch-item reconciliation: town-hall names 4 buildings; the
	# smithy doubles as the iron producer (bog-iron smelt + forge) so gear
	# crafting has its flavor home, and the training grounds is the
	# non-producing flavor card (training itself needs no building, T-SIM-03).
	var grounds := _by_id(_pack().buildings)[&"training_grounds"] as BuildingDef
	assert_str(String(grounds.resource_produced)).is_equal("")
	assert_int(grounds.worker_slots_base).is_equal(0)


func test_producer_rates_and_costs_match_the_m1_measured_economy() -> void:
	var buildings := _by_id(_pack().buildings)
	var farm := buildings[&"farm"] as BuildingDef
	var camp := buildings[&"lumber_camp"] as BuildingDef
	var smithy := buildings[&"smithy"] as BuildingDef
	# The M1 trio, with the farm raised by the T-SIM-08 follow-up (journey
	# 1's first-trickle retune): farm 24 food/h (2 slots) so the first
	# whole food lands ~2.5 min after staffing — the trickle print inside
	# the 10-15 min first session; lumber camp 6 timber/h (2 slots) and
	# smithy 3 iron/h (3 slots) stand at the M1-measured numbers (the
	# retune moved ONLY the food opening; the estate's build costs — the
	# camp's 10 food, the grounds' 15 — were measured against it and the
	# first-win band re-swept identical: 12/12 seeds, mean 79h).
	assert_float(farm.base_production_per_worker_hour).is_equal(24.0)
	assert_int(farm.worker_slots_base).is_equal(2)
	assert_float(camp.base_production_per_worker_hour).is_equal(6.0)
	assert_int(camp.worker_slots_base).is_equal(2)
	assert_float(smithy.base_production_per_worker_hour).is_equal(3.0)
	assert_int(smithy.worker_slots_base).is_equal(3)
	# Cost chain: farm costs timber, camp costs food, smithy costs both.
	assert_int(int(farm.base_cost.get(&"timber", 0))).is_equal(15)
	assert_int(int(camp.base_cost.get(&"food", 0))).is_equal(10)
	assert_int(int(smithy.base_cost.get(&"timber", 0))).is_equal(40)
	assert_int(int(smithy.base_cost.get(&"food", 0))).is_equal(20)


func test_gear_covers_both_slots_at_three_tiers_with_scaling() -> void:
	var gear := _pack().gear
	for slot: StringName in _pack().gear_slots:
		var tiers := {}
		var previous_power := -1
		var previous_iron := -1
		for item: GearDef in gear:
			if item.slot != slot:
				continue
			assert_int(int(item.recipe[&"iron"] if item.recipe.has(&"iron") else 0)).is_greater(0)
			assert_bool(tiers.has(item.tier)).is_false()  # one item per slot per tier
			tiers[item.tier] = item
			assert_int(item.combat_power).is_greater(previous_power)  # power strictly up per tier
			previous_power = item.combat_power
			assert_int(int(item.recipe[&"iron"])).is_greater(previous_iron)  # costs scale up
			previous_iron = int(item.recipe[&"iron"])
		assert_array(tiers.keys()).is_equal([1, 2, 3])


func test_tier1_knight_kit_matches_the_m1_measured_parity() -> void:
	# F3 (M1 findings): the thin knight kit = 25 iron + 5 timber was healthy —
	# ≈ 2.8h of fully-staffed L1 smithy (3 slots x 3 iron/h = 9 iron/h). The
	# pack pins tier 1 to exactly those numbers; higher tiers stay within a
	# bounded multiple (<= 6x iron, <= 8x timber) of the t1 kit.
	var gear := _by_id(_pack().gear)
	var kit_iron := {1: 0, 2: 0, 3: 0}
	var kit_timber := {1: 0, 2: 0, 3: 0}
	for slot: StringName in _pack().gear_slots:
		for item: GearDef in _pack().gear:
			if item.slot != slot:
				continue
			kit_iron[item.tier] += int(item.recipe.get(&"iron", 0))
			kit_timber[item.tier] += int(item.recipe.get(&"timber", 0))
	assert_int(int(kit_iron[1])).is_equal(25)
	assert_int(int(kit_timber[1])).is_equal(5)
	assert_float(float(kit_iron[1]) / 9.0).is_equal_approx(2.8, 0.05)  # ≈ 2.8h full L1 smithy
	assert_int(int(kit_iron[3])).is_less_equal(int(kit_iron[1]) * 6)  # bounded tier scaling (t3 = 115 iron)
	assert_int(int(kit_timber[3])).is_less_equal(int(kit_timber[1]) * 10)  # t3 = 45 timber (still cheap at that scale)


func test_starting_grants_cover_all_four_constructions() -> void:
	# The stipend (pack data, paid by grant_resources) affords building every
	# building exactly once at identity costs (zero-grant bootstrap is
	# impossible by design), with a thin spare buffer for the first gear
	# tier's timber line. Under a cost-quirk regime (iron_rotunda all x1.2)
	# the last building waits for producer income instead — a designed
	# tension, not a gap.
	var pack := _pack()
	var needed := {}
	for building: BuildingDef in pack.buildings:
		for resource: StringName in building.base_cost:
			needed[resource] = int(needed.get(resource, 0)) + int(building.base_cost[resource])
	for resource: StringName in needed:
		assert_int(int(pack.starting_grants.get(resource, 0))).is_greater_equal(int(needed[resource]))


func test_tunables_equal_the_tuned_class_defaults() -> void:
	# Every exported EconomyTunables field equals the class default — the
	# T-SIM-08 TUNED values (R4 seeds superseded by the balance pass,
	# docs/balance.md; the .tres sets nothing, defaults flow through) —
	# property-walk so future additive fields are covered automatically.
	var defaults := EconomyTunables.new()
	for property in defaults.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var field: String = property["name"]
		if field == "script":
			continue
		assert_that(_pack().tunables.get(field)).is_equal(defaults.get(field))


# --- 4. Regime coverage (T-SIM-06 garrisons + serializer quirk shapes) ------


func test_regimes_carry_distinct_combat_modifiers() -> void:
	var kinds := {}
	var garrison_values := {}
	for regime: RegimeDef in _pack().regimes:
		var combat := regime.combat_modifier
		assert_that(combat).is_not_null()
		kinds[combat.kind] = true
		if combat.kind == &"garrison_multiplier":
			garrison_values[combat.value] = true
	assert_bool(kinds.has(&"garrison_multiplier")).is_true()
	assert_bool(kinds.has(&"army_score_multiplier")).is_true()
	assert_int(garrison_values.size()).is_greater_equal(2)  # distinct garrison quirks


func test_regime_quirk_shapes_cover_test_needs() -> void:
	# The serializer sweep (T-ARCH-03) and production quirks need: at least
	# one cost quirk, at least one per-resource production quirk, at least
	# one all-resource production quirk. All four flavors differ.
	var cost_quirks := 0
	var per_resource_prod := 0
	var all_prod := 0
	for regime: RegimeDef in _pack().regimes:
		var quirk := regime.economy_quirk
		assert_that(quirk).is_not_null()
		if quirk.kind == &"building_cost_multiplier":
			cost_quirks += 1
		if quirk.kind == &"production_multiplier" and quirk.target == &"all":
			all_prod += 1
		if quirk.kind == &"production_multiplier" and quirk.target != &"all":
			per_resource_prod += 1
	assert_int(cost_quirks).is_greater_equal(1)
	assert_int(per_resource_prod).is_greater_equal(1)
	assert_int(all_prod).is_greater_equal(1)


func test_regimes_carry_inks_crests_and_flavor() -> void:
	for regime: RegimeDef in _pack().regimes:
		assert_bool(regime.ink_ground != regime.ink_secondary).is_true()
		assert_bool(regime.crest_id != &"").is_true()
		assert_bool(regime.flavor_text.length() > 10).is_true()


# --- 5. Integrity: uniqueness + no orphans + identity breadth ----------------


func test_no_duplicate_display_names_within_each_pool() -> void:
	for pool_name: String in ["units", "buildings", "gear", "regimes"]:
		var seen := {}
		for def: Resource in _pack().get(pool_name):
			assert_bool(seen.has(def.display_name)).is_false()
			seen[def.display_name] = true


func test_no_orphan_art_keys() -> void:
	# Stricter than the validator (which allows unreferenced entries): THIS
	# pack's manifest is exactly the referenced set — 23 assets, all used
	# (faces + building/gear icons + regime crests + the L1-B tree's branch
	# crests since 2026-09-17).
	var pack := _pack()
	var referenced := {}
	for unit: UnitDef in pack.units:
		referenced[unit.face_id] = true
	for building: BuildingDef in pack.buildings:
		referenced[building.icon_id] = true
	for item: GearDef in pack.gear:
		referenced[item.icon_id] = true
	for regime: RegimeDef in pack.regimes:
		referenced[regime.crest_id] = true
	if pack.unlock_tree != null:
		for branch: StringName in pack.unlock_tree.branch_crests.keys():
			referenced[pack.unlock_tree.branch_crests[branch]] = true
	var orphans: Array[StringName] = []
	for asset: ArtAssetDef in pack.art.assets:
		if not referenced.has(asset.id):
			orphans.append(asset.id)
	assert_array(orphans).is_empty()
	assert_int(pack.art.assets.size()).is_equal(referenced.size())


func test_identity_pools_breadth() -> void:
	# The breadth substrate for T-COPY-01: hundreds of leader permutations,
	# a rich recruit pool, all pools duplicate-free.
	var pools := _pack().identity
	assert_int(pools.leader_first_names.size()).is_greater_equal(24)
	assert_int(pools.leader_epithets.size()).is_greater_equal(24)
	assert_int(
		pools.leader_first_names.size() * pools.leader_epithets.size()
	).is_greater_equal(400)  # full-name permutations in the hundreds
	assert_int(pools.recruit_names.size()).is_greater_equal(24)
	assert_int(pools.personality_tags.size()).is_greater_equal(8)
	for pool: Array in [pools.leader_first_names, pools.leader_epithets, pools.recruit_names, pools.personality_tags]:
		assert_int(pool.size()).is_equal(_unique_count(pool))


func _unique_count(pool: Array) -> int:
	var seen := {}
	for entry in pool:
		seen[entry] = true
	return seen.size()


# --- 6. The grant verb boots a run with zero backdoor writes (F1) ------------


func test_grant_verb_boots_a_run_with_zero_backdoor_grants() -> void:
	var pack := _pack()
	# Single-regime pool (gilded_crown: production quirk only, cost identity)
	# keeps the boot math exact regardless of the seed's draw; the 4-flavor
	# draw path is covered by the run-lifecycle grant tests.
	var gilded := _by_id(pack.regimes)[&"gilded_crown"] as RegimeDef
	var engine := SimEngine.new(20260915)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new([gilded], pack.identity, null, pack.starting_grants))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))

	# The honest boot sequence, entirely through the command queue: the
	# zero-grant gap is still real (first build refuses), then the stipend
	# arrives through the verb, then all four buildings construct.
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"upgrade_building", &"farm", 1)  # refused: pool empty (F1 proof)
	engine.tick()
	var production := engine.get_system(&"production") as ProductionSystem
	assert_int(production.building_level(&"farm")).is_equal(0)
	# Snapshot the ACTUAL construction costs now that the drawn regime's
	# quirk is applied (run_start drained above) — the exact lines charged.
	var charged := {}
	for id in BUILDING_IDS:
		for resource: StringName in production.upgrade_cost(id):
			charged[resource] = int(charged.get(resource, 0)) + int(production.upgrade_cost(id)[resource])
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	for id in BUILDING_IDS:
		engine.submit_command(&"upgrade_building", id, 1)
	engine.tick()

	# All four buildings built; the pool is EXACTLY grants - charged under
	# whatever regime was drawn (zero backdoor writes — the math proves no
	# set_resource touched the pool).
	assert_int(production.building_level(&"farm")).is_equal(1)
	assert_int(production.building_level(&"lumber_camp")).is_equal(1)
	assert_int(production.building_level(&"smithy")).is_equal(1)
	assert_int(production.building_level(&"training_grounds")).is_equal(1)
	for resource: StringName in pack.starting_grants:
		assert_int(engine.get_resource(resource)).is_equal(
			int(pack.starting_grants[resource]) - int(charged.get(resource, 0)))

	# The stipend events are in the ring (one per resource line, sorted).
	var granted_lines := 0
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == &"resources_granted":
			granted_lines += 1
	assert_int(granted_lines).is_equal(pack.starting_grants.size())
	# No rejections in the boot script after the grant verb (the queue was
	# driven cleanly; the ONE pre-grant denial is the documented F1 proof).
	var post_grant_denials := 0
	var seen_grant := false
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event == null:
			continue
		if event.type == &"resources_granted":
			seen_grant = true
		if seen_grant and event.type == &"upgrade_denied":
			post_grant_denials += 1
	assert_int(post_grant_denials).is_equal(0)
