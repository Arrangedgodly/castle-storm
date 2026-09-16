## Content schema validation tests (T-DATA-01).
##
## Mirrors content/content_validator.gd + content/schema/*. Two jobs:
## 1. GREEN — the worked examples in content/examples/ validate clean (they
##    are the seeds for the T-DATA-02 MVP pack).
## 2. RED — invalid content fails loudly with precise, asserted messages
##    (town-hall q#4 acceptance: invalid content never silently defaults).
##
## Error message wording is API (documented in docs/content-schema.md §5);
## changing a message requires changing it here in the same commit.
extends GdUnitTestSuite

const EXAMPLE_PACK := "res://content/examples/pack_example.tres"
const INVALID_PACK := "res://tests/unit/fixtures/pack_invalid.tres"


# --- GREEN: worked examples validate clean ---------------------------------


func test_example_pack_validates_clean() -> void:
	var pack := load(EXAMPLE_PACK) as ContentPack
	assert_that(pack).is_not_null()
	var errors := ContentValidator.validate_pack(pack)
	assert_int(errors.size()).is_equal(0)


func test_load_pack_returns_validated_example_pack() -> void:
	var pack := ContentValidator.load_pack(EXAMPLE_PACK)
	assert_that(pack).is_not_null()
	assert_int(ContentValidator.validate_pack(pack).size()).is_equal(0)


func test_example_pack_shape() -> void:
	var pack := load(EXAMPLE_PACK) as ContentPack
	assert_int(pack.format_version).is_equal(1)
	assert_str(String(pack.pack_id)).is_equal("example")
	assert_array(pack.resources).is_equal([&"food", &"timber", &"iron"] as Array[StringName])
	assert_array(pack.gear_slots).is_equal([&"weapon", &"armor"] as Array[StringName])
	assert_int(pack.units.size()).is_equal(6)
	assert_int(pack.buildings.size()).is_equal(1)
	assert_int(pack.gear.size()).is_equal(2)
	assert_int(pack.regimes.size()).is_equal(1)
	assert_array(pack.units.map(func(u: UnitDef) -> StringName: return u.id)).is_equal(
		[&"peasant", &"worker", &"militia", &"trainee", &"knight", &"archer"] as Array[StringName])


func test_example_pack_carry_both_promotion_branches() -> void:
	var pack := load(EXAMPLE_PACK) as ContentPack
	var by_id := {}
	for unit: UnitDef in pack.units:
		by_id[unit.id] = unit
	var peasant := by_id[&"peasant"] as UnitDef
	var trainee := by_id[&"trainee"] as UnitDef
	var knight := by_id[&"knight"] as UnitDef
	var archer := by_id[&"archer"] as UnitDef
	assert_array(peasant.promotion_paths).is_equal([&"worker", &"militia"] as Array[StringName])
	assert_array(trainee.promotion_paths).is_equal([&"knight", &"archer"] as Array[StringName])
	assert_array(knight.required_gear_slots).is_equal([&"weapon", &"armor"] as Array[StringName])
	assert_int(knight.combat_power).is_greater(archer.combat_power)
	assert_bool(knight.training_time_hours > archer.training_time_hours).is_true()


func test_r4_seed_tunables_are_data_not_code_constants() -> void:
	var pack := load(EXAMPLE_PACK) as ContentPack
	var t := pack.tunables
	assert_float(t.offline_cap_hours).is_equal(8.0)
	assert_float(t.offline_rate).is_equal(1.0)
	assert_float(t.cost_growth_band_min).is_equal_approx(1.08, 0.0001)
	assert_float(t.cost_growth_band_max).is_equal_approx(1.12, 0.0001)
	assert_float(t.milestone_multiplier).is_equal(2.0)
	assert_float(t.knight_cost_step).is_equal_approx(1.6, 0.0001)
	assert_int(t.suspicion_max).is_equal(100)
	assert_int(t.suspicion_warn_threshold).is_equal(35)
	assert_int(t.suspicion_crackdown_threshold).is_equal(70)
	assert_float(t.suspicion_decay_per_hour).is_equal(5.0)
	assert_float(t.suspicion_decay_high_tier_per_hour).is_equal(2.5)
	assert_int(t.suspicion_rise_loud).is_equal(8)
	assert_int(t.suspicion_rise_medium).is_equal(4)
	assert_float(t.crackdown_seize_fraction).is_equal_approx(0.4, 0.0001)
	assert_float(t.crackdown_telegraph_hours).is_equal(4.0)
	assert_int(t.post_crackdown_suspicion).is_equal(45)
	assert_float(t.post_crackdown_rise_multiplier).is_equal_approx(0.5, 0.0001)
	assert_float(t.post_crackdown_relief_hours).is_equal(24.0)


func test_default_tunables_match_r4_research() -> void:
	# The class defaults ARE the R4 seed values: a bare EconomyTunables.new()
	# must validate clean so tunables never block a fresh pack draft.
	assert_int(ContentValidator.validate_tunables(EconomyTunables.new()).size()).is_equal(0)


# --- RED: invalid content fails loudly, with precise messages --------------


func test_scratch_pack_fixture_is_valid() -> void:
	# Self-check: the red-path fixture starts valid, so each red test's single
	# mutation is provably the cause of its error.
	assert_int(ContentValidator.validate_pack(_scratch_pack()).size()).is_equal(0)


func test_empty_unit_id_fails_loudly() -> void:
	var pack := _scratch_pack()
	(pack.units[0] as UnitDef).id = &""
	var errors := ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "id must not be empty")).is_greater_equal(1)
	assert_str(_first(errors, "unit '': id must not be empty")).is_equal("unit '': id must not be empty")


func test_unknown_promotion_target_fails() -> void:
	var pack := _scratch_pack()
	(pack.units[0] as UnitDef).promotion_paths = [&"ninja"]
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "promotion target")).is_equal(
		"unit 'peasant': promotion target 'ninja' does not match any unit in pack")


func test_promotion_cycle_fails() -> void:
	var pack := _scratch_pack()
	(pack.units[0] as UnitDef).promotion_paths = [&"knight"]
	(pack.units[1] as UnitDef).promotion_paths = [&"peasant"]
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "promotion cycle")).is_equal(
		"unit 'peasant': promotion cycle detected: peasant -> knight -> peasant")


func test_duplicate_unit_id_fails() -> void:
	var pack := _scratch_pack()
	var extra := (pack.units[1] as UnitDef).duplicate(true) as UnitDef
	pack.units.append(extra)
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "duplicate unit id")).is_equal("pack: duplicate unit id 'knight'")


func test_building_cost_growth_outside_r4_band_fails() -> void:
	var pack := _scratch_pack()
	(pack.buildings[0] as BuildingDef).cost_growth = 1.25
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "cost_growth")).is_equal(
		"building 'farm': cost_growth 1.25 outside tunables band [1.08, 1.12] (R4: 1.08-1.12)")


func test_suspicion_threshold_order_fails() -> void:
	var pack := _scratch_pack()
	pack.tunables.suspicion_warn_threshold = 80
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "suspicion thresholds")).is_equal(
		"tunables: suspicion thresholds must satisfy 0 < warn < crackdown < max (got warn=80 crackdown=70 max=100)")


func test_telegraph_below_r4_floor_fails() -> void:
	var pack := _scratch_pack()
	pack.tunables.crackdown_telegraph_hours = 3.0
	var errors := ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "crackdown_telegraph_hours must be >= 4.0")).is_equal(1)


func test_assault_loss_fraction_one_plus_fails() -> void:
	# A failed assault is a set-back, NEVER annihilation (T-SIM-06 rule the
	# validator pins): fraction must stay within (0, 1].
	var pack := _scratch_pack()
	pack.tunables.assault_loss_fraction = 1.5
	var errors := ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "assault_loss_fraction must be within (0, 1]")).is_equal(1)


func test_assault_tunables_bounds_fail() -> void:
	# Floor and garrison must be positive; the failure spike cannot exceed
	# the meter max (a failed assault bends the set-back rule only at the
	# edge, never past it).
	var pack := _scratch_pack()
	pack.tunables.assault_knight_floor_power = 0
	pack.tunables.assault_garrison_base_power = 0
	pack.tunables.assault_failure_suspicion = 101
	var errors := ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "assault_knight_floor_power must be > 0")).is_equal(1)
	assert_int(_count(errors, "assault_garrison_base_power must be > 0")).is_equal(1)
	assert_int(_count(errors, "assault_failure_suspicion must be within")).is_equal(1)


func test_missing_art_key_fails() -> void:
	var pack := _scratch_pack()
	(pack.units[1] as UnitDef).face_id = &"face_ghost"
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "missing from art manifest")).is_equal(
		"unit 'knight': face_id 'face_ghost' missing from art manifest")


func test_ccby_art_requires_attribution() -> void:
	var pack := _scratch_pack()
	var asset := ArtAssetDef.new()
	asset.id = &"icon_extra"
	asset.source_path = "res://assets/vendor/game-icons/lorc/extra.svg"
	asset.license = "CC-BY-3.0"
	pack.art.assets.append(asset)
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "requires attribution")).is_equal(
		"art-asset 'icon_extra': license 'CC-BY-3.0' requires attribution (CC-BY family)")


func test_undeclared_gear_slot_fails() -> void:
	var pack := _scratch_pack()
	(pack.gear[0] as GearDef).slot = &"hat"
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "not a declared gear slot")).is_equal(
		"gear 'sword': slot 'hat' is not a declared gear slot")


func test_required_slot_without_gear_fails() -> void:
	var pack := _scratch_pack()
	pack.gear_slots = [&"weapon", &"armor"]
	(pack.units[1] as UnitDef).required_gear_slots = [&"weapon", &"armor"]
	var errors := ContentValidator.validate_pack(pack)
	assert_str(_first(errors, "has no gear in pack")).is_equal(
		"unit 'knight': required gear slot 'armor' has no gear in pack")


func test_load_pack_refuses_invalid_file() -> void:
	# Loud refusal at load: the fixture on disk is invalid (unit with no id,
	# among other faults) — load_pack must return null, never a half-pack.
	var pack := ContentValidator.load_pack(INVALID_PACK)
	assert_that(pack).is_null()


# --- helpers ----------------------------------------------------------------


## Minimal valid pack built in code (never touches the cached example
## resources, so mutations cannot leak between tests).
func _scratch_pack() -> ContentPack:
	var pack := ContentPack.new()
	pack.format_version = 1
	pack.pack_id = &"scratch"
	pack.display_name = "Scratch pack"
	pack.resources = [&"food", &"timber"]

	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths = [&"knight"]
	peasant.face_id = &"face_peasant"

	var knight := UnitDef.new()
	knight.id = &"knight"
	knight.display_name = "Knight"
	knight.training_time_hours = 12.0
	knight.combat_power = 10
	knight.required_gear_slots = [&"weapon"]
	knight.face_id = &"face_knight"

	var farm := BuildingDef.new()
	farm.id = &"farm"
	farm.display_name = "Farm"
	farm.resource_produced = &"food"
	farm.base_production_per_worker_hour = 6.0
	farm.worker_slots_base = 2
	farm.base_cost = {&"timber": 15}
	farm.cost_growth = 1.08
	farm.milestone_levels = [10, 20]
	farm.max_level = 30
	farm.icon_id = &"icon_farm"

	var sword := GearDef.new()
	sword.id = &"sword"
	sword.display_name = "Borrowed Sword"
	sword.slot = &"weapon"
	sword.tier = 1
	sword.recipe = {&"timber": 5}
	sword.combat_power = 2
	sword.craft_time_hours = 1.0
	sword.icon_id = &"icon_sword"

	var combat := RegimeModifier.new()
	combat.kind = &"garrison_multiplier"
	combat.value = 1.2
	var quirk := RegimeModifier.new()
	quirk.kind = &"production_multiplier"
	quirk.target = &"food"
	quirk.value = 0.9
	var crown := RegimeDef.new()
	crown.id = &"crown"
	crown.display_name = "The Gilded Crown"
	crown.combat_modifier = combat
	crown.economy_quirk = quirk
	crown.crest_id = &"crest_crown"
	crown.ink_ground = Color(0.2, 0.2, 0.2)
	crown.ink_secondary = Color(0.8, 0.6, 0.3)

	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel", "Godfrey", "Petronella"]
	pools.leader_epithets = ["the Unbearable", "the Almost Wise", "of the Leaky Barn", "the Twice-Fooled", "the Modest Avalanche", "of Fine Debt"]
	pools.personality_tags = [&"ambitious", &"pious", &"gluttonous", &"paranoid"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick", "Bess", "Gil"]

	var manifest := ArtManifest.new()
	manifest.assets = [
		_art(&"face_peasant"), _art(&"face_knight"), _art(&"icon_farm"),
		_art(&"icon_sword"), _art(&"crest_crown"),
	]

	pack.gear_slots = [&"weapon"]
	pack.units = [peasant, knight]
	pack.buildings = [farm]
	pack.gear = [sword]
	pack.regimes = [crown]
	pack.identity = pools
	pack.tunables = EconomyTunables.new()
	pack.art = manifest
	return pack


func _art(id: StringName) -> ArtAssetDef:
	var asset := ArtAssetDef.new()
	asset.id = id
	asset.source_path = "res://assets/vendor/kenney/board-game-icons/vector/%s.svg" % id
	asset.license = "CC0"
	return asset


func _count(errors: Array[String], fragment: String) -> int:
	return errors.filter(func(e: String) -> bool: return e.contains(fragment)).size()


func _first(errors: Array[String], fragment: String) -> String:
	for e in errors:
		if e.contains(fragment):
			return e
	return "<no error containing '%s'; errors were: %s>" % [fragment, "\n".join(errors)]


func test_opening_rush_tunables_bounds_fail() -> void:
	# T-SIM-08: the rush's first interval must be a real interval inside
	# (0, base], the ramp must grow toward the base (step >= 1.0), the count
	# cannot be negative, and the gate capacity cannot be negative (0 =
	# uncapped, the pre-T-SIM-08 shape).
	var pack := _scratch_pack()
	pack.tunables.recruit_arrival_early_count = -1
	var errors := ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "recruit_arrival_early_count must be >= 0")).is_equal(1)

	pack = _scratch_pack()
	pack.tunables.recruit_arrival_early_count = 4
	pack.tunables.recruit_arrival_early_interval_hours = 2.5  # > the 2h base
	pack.tunables.recruit_arrival_early_step = 0.5
	errors = ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "recruit_arrival_early_interval_hours must be within (0, recruit_arrival_interval_hours]")).is_equal(1)
	assert_int(_count(errors, "recruit_arrival_early_step must be >= 1.0")).is_equal(1)

	pack = _scratch_pack()
	pack.tunables.recruit_gate_capacity = -2
	errors = ContentValidator.validate_pack(pack)
	assert_int(_count(errors, "recruit_gate_capacity must be >= 0")).is_equal(1)
