## Unit tests for the L1 legacy unlock tree — schema validation + the
## LegacySystem purchase rules + persistence (RunMeta.unlocks) + the
## LegacyModifiers resolution. Mirrors content/schema/unlock_*.gd,
## content/content_validator.gd (validate_unlock_tree), sim/legacy_system.gd,
## sim/legacy_modifiers.gd, sim/run_meta.gd (test-mapping rule).
##
## Engine-side application (run_start modifiers, hash visibility, round-trip
## lockstep, determinism) lives in test_legacy_run_effects.gd; this suite
## owns the meta-domain contract.
extends GdUnitTestSuite

const EXAMPLE_TREE_PATH := "res://content/examples/unlock_tree.tres"
const EXAMPLE_PACK_PATH := "res://content/examples/pack_example.tres"


# --- Fixtures (in-code content; same classes the .tres files use) ----------


func _node(
	id: StringName,
	branch: StringName,
	cost: int,
	prerequisites: Array[StringName],
	kind: StringName,
	value: float
) -> UnlockNodeDef:
	var node := UnlockNodeDef.new()
	node.id = id
	node.display_name = "Node %s" % id
	node.branch = branch
	node.cost = cost
	node.prerequisites = prerequisites
	var effect := UnlockEffect.new()
	effect.kind = kind
	effect.value = value
	node.effect = effect
	return node


## A clean tree: two branches, four nodes, one gated edge, all five effect
## kinds in play across the suite (validated zero-error by the first test).
func _tree() -> UnlockTreeDef:
	var tree := UnlockTreeDef.new()
	tree.nodes = [
		_node(&"seed_capital", &"economy", 40, [], &"stipend_bonus", 1.25),
		_node(&"cheap_walls", &"economy", 60, [&"seed_capital"], &"building_cost_multiplier", 0.9),
		_node(&"busy_road", &"people", 50, [], &"recruit_arrival_interval_multiplier", 0.9),
		_node(&"quick_drills", &"people", 80, [&"busy_road"], &"training_time_multiplier", 0.9),
	]
	return tree


# --- Schema: green paths ------------------------------------------------------


func test_clean_tree_validates_with_zero_errors() -> void:
	assert_array(ContentValidator.validate_unlock_tree(_tree())).is_empty()


func test_example_tree_on_disk_validates_clean() -> void:
	var tree := ResourceLoader.load(EXAMPLE_TREE_PATH) as UnlockTreeDef
	assert_bool(tree != null).is_true()
	assert_array(ContentValidator.validate_unlock_tree(tree)).is_empty()


func test_example_pack_with_attached_tree_validates_clean() -> void:
	var pack := ContentValidator.load_pack(EXAMPLE_PACK_PATH)
	assert_bool(pack != null).is_true()
	if pack == null:
		return
	assert_array(ContentValidator.validate_pack(pack)).is_empty()
	assert_int(pack.unlock_tree.nodes.size()).is_equal(4)


func test_mvp_pack_without_tree_is_still_valid() -> void:
	## The additive-optional contract: the pre-L1-B MVP pack ships no tree
	## and must keep validating clean (absence is legal).
	var pack := ContentValidator.load_pack("res://content/mvp/pack.tres")
	assert_bool(pack != null).is_true()
	if pack == null:
		return
	assert_array(ContentValidator.validate_pack(pack)).is_empty()
	assert_bool(pack.unlock_tree == null).is_true()


func test_validator_registry_matches_the_resolution_engine() -> void:
	## One vocabulary: the validator's registry IS the resolution engine's
	## kind list (drift would make valid content unresolvable — or invalid
	## content loadable).
	assert_array(ContentValidator.LEGACY_EFFECT_KINDS).is_equal(LegacyModifiers.EFFECT_KINDS)


# --- Schema: red paths (message wording is API — asserted verbatim) ------------


func _errors_of(tree: UnlockTreeDef) -> Array[String]:
	return ContentValidator.validate_unlock_tree(tree)


func test_null_tree_is_an_error() -> void:
	assert_array(_errors_of(null)).is_equal(["unlock-tree: tree resource is null"])


func test_empty_nodes_is_an_error() -> void:
	var tree := UnlockTreeDef.new()
	assert_array(_errors_of(tree)).is_equal([
		"unlock-tree: nodes must not be empty (a tree with no nodes is content churn, not content)",
	])


func test_version_must_be_positive() -> void:
	var tree := _tree()
	tree.version = 0
	assert_array(_errors_of(tree)).is_equal(["unlock-tree: version must be >= 1 (got 0)"])


func test_empty_id_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].id = &""
	var errors := _errors_of(tree)
	assert_bool(errors.has("unlock '': id must not be empty")).is_true()


func test_duplicate_id_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[1].id = tree.nodes[0].id
	var errors := _errors_of(tree)
	assert_bool(errors.has("unlock-tree: duplicate node id '%s'" % tree.nodes[0].id)).is_true()


func test_empty_display_name_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].display_name = ""
	assert_array(_errors_of(tree)).is_equal(["unlock '%s': display_name must not be empty" % tree.nodes[0].id])


func test_empty_branch_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].branch = &""
	assert_array(_errors_of(tree)).is_equal(["unlock '%s': branch must not be empty (the tree UI's grouping label)" % tree.nodes[0].id])


func test_zero_cost_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].cost = 0
	assert_array(_errors_of(tree)).is_equal(["unlock '%s': cost must be > 0 legacy points (got 0)" % tree.nodes[0].id])


func test_unknown_prerequisite_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].prerequisites = [&"ghost"]
	assert_array(_errors_of(tree)).is_equal([
		"unlock '%s': prerequisite 'ghost' does not match any node in tree" % tree.nodes[0].id,
	])


func test_empty_prerequisite_id_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].prerequisites = [&""]
	assert_array(_errors_of(tree)).is_equal([
		"unlock '%s': prerequisite id must not be empty" % tree.nodes[0].id,
	])


func test_self_referential_prerequisite_is_a_cycle() -> void:
	var tree := _tree()
	tree.nodes[0].prerequisites = [tree.nodes[0].id]
	assert_array(_errors_of(tree)).is_equal([
		"unlock '%s': prerequisite cycle detected: %s -> %s" % [tree.nodes[0].id, tree.nodes[0].id, tree.nodes[0].id],
	])


func test_two_node_prerequisite_cycle_is_detected() -> void:
	var tree := UnlockTreeDef.new()
	tree.nodes = [
		_node(&"a", &"x", 10, [&"b"], &"stipend_bonus", 1.1),
		_node(&"b", &"x", 10, [&"a"], &"stipend_bonus", 1.1),
	]
	assert_array(_errors_of(tree)).is_equal(["unlock 'a': prerequisite cycle detected: a -> b -> a"])


func test_missing_effect_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].effect = null
	assert_array(_errors_of(tree)).is_equal(["unlock '%s': effect must be set (exactly one per node)" % tree.nodes[0].id])


func test_null_node_entry_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[1] = null
	var errors := _errors_of(tree)
	assert_bool(errors.has("unlock <null>: node entry must not be null")).is_true()


func test_unknown_effect_kind_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].effect.kind = &"smell_bonus"
	var expected := "unlock '%s': effect kind 'smell_bonus' not recognized (expected one of: %s)" % [
		tree.nodes[0].id,
		", ".join(PackedStringArray(LegacyModifiers.EFFECT_KINDS.map(func(k: StringName) -> String: return String(k)))),
	]
	assert_array(_errors_of(tree)).is_equal([expected])


func test_nonpositive_effect_value_is_an_error() -> void:
	var tree := _tree()
	tree.nodes[0].effect.value = 0.0
	assert_array(_errors_of(tree)).is_equal(["unlock '%s': effect value must be > 0 (got %s)" % [tree.nodes[0].id, tree.nodes[0].effect.value]])


# --- LegacyModifiers resolution ---------------------------------------------------


func test_identity_bundle_is_all_1000s() -> void:
	var mods := LegacyModifiers.identity()
	assert_bool(mods.is_identity()).is_true()
	assert_int(mods.recruit_arrival_interval_milli).is_equal(1000)
	assert_int(mods.building_cost_milli).is_equal(1000)
	assert_int(mods.training_time_milli).is_equal(1000)
	assert_int(mods.gear_cost_milli).is_equal(1000)
	assert_int(mods.stipend_milli).is_equal(1000)


func test_no_nodes_resolve_to_identity() -> void:
	assert_bool(LegacyModifiers.from_nodes([]).is_identity()).is_true()


func test_each_kind_lands_in_its_own_field() -> void:
	var tree := UnlockTreeDef.new()
	tree.nodes = [
		_node(&"a", &"x", 1, [], &"recruit_arrival_interval_multiplier", 0.9),
		_node(&"b", &"x", 1, [], &"building_cost_multiplier", 0.8),
		_node(&"c", &"x", 1, [], &"training_time_multiplier", 0.7),
		_node(&"d", &"x", 1, [], &"gear_cost_multiplier", 0.6),
		_node(&"e", &"x", 1, [], &"stipend_bonus", 1.25),
	]
	var mods := LegacyModifiers.from_nodes(tree.nodes)
	assert_int(mods.recruit_arrival_interval_milli).is_equal(900)
	assert_int(mods.building_cost_milli).is_equal(800)
	assert_int(mods.training_time_milli).is_equal(700)
	assert_int(mods.gear_cost_milli).is_equal(600)
	assert_int(mods.stipend_milli).is_equal(1250)
	assert_bool(mods.is_identity()).is_false()


func test_same_kind_compounds_and_order_does_not_matter() -> void:
	## Exact integer milli chains: 900 x 900 / 1000 = 810 both ways — the
	## bundle is a function of the owned SET, not the purchase order.
	var forward := UnlockTreeDef.new()
	forward.nodes = [
		_node(&"a", &"x", 1, [], &"building_cost_multiplier", 0.9),
		_node(&"b", &"x", 1, [], &"building_cost_multiplier", 0.9),
	]
	var backward := UnlockTreeDef.new()
	backward.nodes = [forward.nodes[1], forward.nodes[0]]
	assert_int(LegacyModifiers.from_nodes(forward.nodes).building_cost_milli).is_equal(810)
	assert_int(LegacyModifiers.from_nodes(backward.nodes).building_cost_milli).is_equal(810)


func test_unknown_kind_and_null_effect_are_skipped_by_resolution() -> void:
	## The runtime defense: a future-vocabulary node resolves nowhere
	## instead of crashing (validated attached packs never hit this).
	var weird := _node(&"a", &"x", 1, [], &"hypothetical_future_kind", 0.5)
	assert_bool(LegacyModifiers.from_nodes([weird]).is_identity()).is_true()
	var bare := _node(&"b", &"x", 1, [], &"stipend_bonus", 1.5)
	bare.effect = null
	assert_bool(LegacyModifiers.from_nodes([bare]).is_identity()).is_true()
	assert_bool(LegacyModifiers.from_nodes([null]).is_identity()).is_true()


func test_modifier_bundle_round_trips_through_dict() -> void:
	var mods := LegacyModifiers.from_nodes(_tree().nodes)
	var restored := LegacyModifiers.from_dict(mods.to_dict())
	assert_int(restored.stipend_milli).is_equal(1250)
	assert_int(restored.building_cost_milli).is_equal(900)
	assert_bool(LegacyModifiers.from_dict({}).is_identity()).is_true()


# --- LegacySystem: purchase rules ---------------------------------------------------


func _system(points: int) -> LegacySystem:
	var meta := RunMeta.new()
	meta.legacy_points = points
	return LegacySystem.new(_tree(), meta)


func test_purchase_success_decrements_bank_and_records_order() -> void:
	var legacy := _system(200)
	assert_bool(legacy.purchase(&"seed_capital")).is_true()
	assert_bool(legacy.purchase(&"busy_road")).is_true()
	assert_int(legacy.bank()).is_equal(200 - 40 - 50)
	assert_array(legacy.owned_ids()).is_equal([&"seed_capital", &"busy_road"])
	assert_int(legacy.owned_count()).is_equal(2)


func test_unknown_node_refuses_loudly_and_mutates_nothing() -> void:
	var legacy := _system(500)
	assert_bool(legacy.purchase(&"nope")).is_false()
	assert_int(legacy.bank()).is_equal(500)
	assert_int(legacy.owned_count()).is_zero()
	assert_bool(legacy.can_purchase(&"nope")).is_false()
	assert_int(legacy.purchase_result(&"nope")).is_equal(LegacySystem.PURCHASE_UNKNOWN_NODE)


func test_double_purchase_refuses() -> void:
	var legacy := _system(500)
	assert_bool(legacy.purchase(&"seed_capital")).is_true()
	var bank_after: int = legacy.bank()
	assert_bool(legacy.purchase(&"seed_capital")).is_false()
	assert_int(legacy.bank()).is_equal(bank_after)
	assert_int(legacy.purchase_result(&"seed_capital")).is_equal(LegacySystem.PURCHASE_ALREADY_OWNED)


func test_prerequisite_not_owned_refuses() -> void:
	var legacy := _system(10_000)
	assert_int(legacy.purchase_result(&"cheap_walls")).is_equal(LegacySystem.PURCHASE_PREREQUISITE_MISSING)
	assert_bool(legacy.purchase(&"cheap_walls")).is_false()
	assert_bool(legacy.purchase(&"seed_capital")).is_true()
	assert_int(legacy.purchase_result(&"cheap_walls")).is_equal(LegacySystem.PURCHASE_OK)


func test_insufficient_points_refuses() -> void:
	var legacy := _system(39)
	assert_int(legacy.purchase_result(&"seed_capital")).is_equal(LegacySystem.PURCHASE_INSUFFICIENT_POINTS)
	assert_bool(legacy.purchase(&"seed_capital")).is_false()
	assert_int(legacy.bank()).is_equal(39)
	assert_array(legacy.owned_ids()).is_empty()


func test_exact_bank_purchase_succeeds_to_zero() -> void:
	var legacy := _system(40)
	assert_bool(legacy.purchase(&"seed_capital")).is_true()
	assert_int(legacy.bank()).is_zero()


func test_affordable_lists_only_purchasable_nodes_in_tree_order() -> void:
	var legacy := _system(150)
	# seed_capital (40) + busy_road (50) fit; cheap_walls fits the bank but
	# its prerequisite is unowned; quick_drills is prereq-gated AND
	# unaffordable either way.
	assert_array(legacy.affordable_ids()).is_equal([&"seed_capital", &"busy_road"])
	assert_bool(legacy.purchase(&"seed_capital")).is_true()
	# Bank 110, prereq owned: cheap_walls (60) and busy_road (50) now both
	# purchasable (tree order); quick_drills still gated (busy_road unowned).
	assert_array(legacy.affordable_ids()).is_equal([&"cheap_walls", &"busy_road"])
	assert_bool(legacy.purchase(&"busy_road")).is_true()
	# Bank 60: cheap_walls fits exactly; quick_drills (80) does not.
	assert_array(legacy.affordable_ids()).is_equal([&"cheap_walls"])


func test_tree_reads_expose_the_ui_surface() -> void:
	var legacy := _system(0)
	assert_array(legacy.node_ids()).is_equal([&"seed_capital", &"cheap_walls", &"busy_road", &"quick_drills"])
	assert_int(legacy.tree_version()).is_equal(1)
	assert_int(legacy.cost(&"cheap_walls")).is_equal(60)
	var node := legacy.node(&"busy_road")
	assert_bool(node != null).is_true()
	if node != null:
		assert_bool(node.effect.value > 0.0).is_true()
	assert_bool(legacy.node(&"nope") == null).is_true()


func test_modifiers_compose_the_owned_set_across_branches() -> void:
	var legacy := _system(10_000)
	legacy.purchase(&"seed_capital")
	legacy.purchase(&"cheap_walls")
	legacy.purchase(&"busy_road")
	var mods := legacy.modifiers()
	assert_int(mods.stipend_milli).is_equal(1250)
	assert_int(mods.building_cost_milli).is_equal(900)
	assert_int(mods.recruit_arrival_interval_milli).is_equal(900)
	# quick_drills is NOT owned: training stays identity.
	assert_int(mods.training_time_milli).is_equal(1000)


func test_owned_id_missing_from_tree_is_kept_but_contributes_nothing() -> void:
	## Content churn: a purchased node that later left the tree stays in the
	## historical record (purchase order) while resolving to nothing.
	var meta := RunMeta.new()
	meta.legacy_points = 100
	meta.unlocks = {"retired_node": true}
	var legacy := LegacySystem.new(_tree(), meta)
	assert_array(legacy.owned_ids()).is_equal([&"retired_node"])
	assert_bool(legacy.modifiers().is_identity()).is_true()


func test_no_tree_means_nothing_purchasable_and_identity_modifiers() -> void:
	## The pre-L1-B MVP pack shape: an empty service that still resolves.
	var meta := RunMeta.new()
	meta.legacy_points = 999
	var legacy := LegacySystem.new(null, meta)
	assert_array(legacy.node_ids()).is_empty()
	assert_int(legacy.tree_version()).is_zero()
	assert_bool(legacy.purchase(&"seed_capital")).is_false()
	assert_bool(legacy.modifiers().is_identity()).is_true()
	assert_array(legacy.affordable_ids()).is_empty()


# --- Persistence (RunMeta.unlocks — the meta save domain) ---------------------------


func test_meta_round_trip_preserves_unlocks_and_bank() -> void:
	var legacy := _system(200)
	legacy.purchase(&"seed_capital")
	legacy.purchase(&"busy_road")
	var restored := RunMeta.new()
	assert_bool(restored.apply_dict(legacy.meta.to_dict())).is_true()
	assert_int(restored.legacy_points).is_equal(110)
	var keys: Array = restored.unlocks.keys()
	assert_int(keys.size()).is_equal(2)
	assert_bool(restored.unlocks.has("seed_capital")).is_true()
	assert_bool(restored.unlocks.has("busy_road")).is_true()
	# The restored meta feeds a fresh service: the owned set survives the
	# process restart, and the remaining purchase still works.
	var reborn := LegacySystem.new(_tree(), restored)
	assert_array(reborn.owned_ids()).is_equal([&"seed_capital", &"busy_road"])
	assert_bool(reborn.purchase(&"cheap_walls")).is_true()  # prereq owned, 60 <= 110


func test_pre_l1_meta_without_the_key_reads_empty() -> void:
	## The tolerant reader: a pre-L1 meta payload has no `unlocks` — that
	## reads as "owns nothing", never a refusal.
	var meta := RunMeta.new()
	assert_bool(meta.apply_dict({
		"format_version": RunMeta.META_FORMAT_VERSION,
		"legacy_points": 300,
		"runs_recorded": 4,
		"chronicle": [],
		"last_seen_epoch": 0,
		"first_session": {},
		"preferences": {},
	})).is_true()
	assert_bool(meta.unlocks.is_empty()).is_true()
	assert_int(meta.legacy_points).is_equal(300)


func test_falsy_unlock_values_are_filtered_on_read() -> void:
	## A hand-edited meta degrades to the legal purchase set, never a crash.
	var meta := RunMeta.new()
	meta.apply_dict({
		"format_version": RunMeta.META_FORMAT_VERSION,
		"unlocks": {"real": true, "tampered": false},
	})
	assert_bool(meta.unlocks.has("real")).is_true()
	assert_bool(meta.unlocks.has("tampered")).is_false()


func test_meta_payload_always_carries_the_unlocks_key() -> void:
	## Always emitted (like first_session/preferences), so the doc's
	## machine-checked meta-payload block stays unconditional.
	assert_bool(RunMeta.new().to_dict().has("unlocks")).is_true()


func test_unlocks_survive_run_restarts_by_design() -> void:
	## Meta-domain rule: nothing in the run lifecycle ever touches the
	## owned set — restarts, engine re-inits and process restarts all keep
	## it (the reset contract has no legacy member).
	var legacy := _system(200)
	legacy.purchase(&"seed_capital")
	var fresh_engine_meta := legacy.meta  # the SAME instance an engine re-init reuses
	assert_int(fresh_engine_meta.unlocks.size()).is_equal(1)
	var second_engine_meta := RunMeta.new()
	second_engine_meta.apply_dict(fresh_engine_meta.to_dict())
	assert_int(second_engine_meta.unlocks.size()).is_equal(1)
	assert_int(second_engine_meta.legacy_points).is_equal(160)
