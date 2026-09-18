## Unit tests for the SHIPPED legacy unlock tree (L1-B/B2, the tree content
## — Mr Fantastic authoring + Prof X feel lane). Mirrors
## content/mvp/unlock_tree.tres + content/mvp/pack.tres (the wiring) +
## content/mvp/copy_table.tres + sim/copy_deck.gd (the voice seam) +
## content/mvp/art_manifest.tres (the branch crests) + the cost curve
## against docs/balance.md's measured earn rates (the L1 section). What is
## pinned:
##   - the pack loads with the tree attached and validates clean through
##     the loud gate (including the branch-crest manifest cross-check);
##   - SHAPE: 15 nodes across 4 branches (R5: 2-4 node families, one
##     effect per node — the RegimeModifier discipline; the arrival lever
##     is deliberately ABSENT, the measured dead/harmful kind; L1-B2's
##     Survivors branch carries the two pressure-model kinds);
##   - the COST CURVE: tier-1 nodes affordable from run 1's bank, the full
##     tree across ~8-12 measured runs, and cost strictly increasing along
##     every prerequisite edge (monotonic within branch tiers);
##   - FEEL BOUNDS: per-node effect values and the FULL-TREE compounds —
##     the training compound may not cross the measured-and-rejected 0.75
##     retune line (docs/balance.md 2026-09-17: 2h->1.5h drills pushed the
##     first-win tail to 169h), the economy multipliers keep the same
##     order of restraint, the stipend stays under x1.6, and the pressure
##     kinds are capped where the pressure model keeps its teeth (decay
##     compound under the greed line's net presence; veterans a nudge on
##     the odds, never a rewrite);
##   - the COPYDECK SEAM: every branch and node carries its
##     unlock_branch_*/unlock_flavor_* key through KEY_TOKENS + DEFAULTS +
##     CONSUMERS + the shipped table (one voice, no orphans, literal lines)
##     and every line fits its surface budget in the theme's real
##     ChronicleLine font metrics (the T-UI-06/09 pin pattern);
##   - the BRANCH CRESTS: declared for exactly the tree's branches and
##     resolving in the art manifest (pending art entries are legal — the
##     T-ARCH-04 hatch — but must be honest: licensed + flagged).
extends GdUnitTestSuite

const TREE_PATH := "res://content/mvp/unlock_tree.tres"
const COPY_PATH := "res://content/mvp/copy_table.tres"

## The T-UI-06/09 clip standard: every measured line clears its surface
## budget by 30px beyond fitting (a line that lands exactly at the budget
## clips first when anything drifts).
const CLIP_MARGIN := 30.0
## The branch plates print on the tree card's chronicle-label class (the
## choice card's 232px budget — the tightest single-line surface in the
## grammar; the L1-C tree UI inherits the guarantee, not the hope).
const BRANCH_PLATE_BUDGET := 232.0
## The node card's flavor row prints at the quote/row class (the 476px
## EventQuote label — the standard single-prose-line budget).
const FLAVOR_ROW_BUDGET := 476.0


func _pack() -> ContentPack:
	return Inks.pack()


func _tree() -> UnlockTreeDef:
	return load(TREE_PATH) as UnlockTreeDef


func _table() -> CopyTable:
	return load(COPY_PATH) as CopyTable


func _total_cost() -> int:
	var total := 0
	for node in _tree().nodes:
		total += node.cost
	return total


# --- the wiring + the loud gate -------------------------------------------------


func test_pack_loads_with_the_tree_attached_and_validates_clean() -> void:
	var pack := _pack()
	assert_that(pack).is_not_null()
	assert_that(pack.unlock_tree).is_not_null()
	assert_array(ContentValidator.validate_pack(pack)).is_empty()
	# Standalone scope agrees, including the manifest cross-check.
	assert_array(ContentValidator.validate_unlock_tree(pack.unlock_tree, pack.art)).is_empty()


func test_tree_shape_is_fifteen_nodes_across_four_branches() -> void:
	var tree := _tree()
	assert_int(tree.version).is_equal(1)
	assert_int(tree.nodes.size()).is_equal(15)
	var branches := {}
	for node in tree.nodes:
		branches[node.branch] = true
	assert_int(branches.size()).is_equal(4)
	for branch in [&"old_guard", &"workshop", &"yard", &"survivors"]:
		assert_bool(branches.has(branch)).is_true()
	# R5: 2-4 node families per layer — every branch carries 3-5 nodes
	# (the Old Guard's pantry ladder is 3; the Workshop's maker families 5;
	# the Survivors' pressure ladder 3).
	for branch in branches.keys():
		var count := 0
		for node in tree.nodes:
			if node.branch == branch:
				count += 1
		assert_int(count).is_greater_equal(3)
		assert_int(count).is_less_equal(5)
	# Every node carries exactly ONE known-kind effect (validator-pinned;
	# restated so a shape edit reads as a content failure here first).
	for node in tree.nodes:
		assert_that(node.effect).is_not_null()
		assert_bool(LegacyModifiers.EFFECT_KINDS.has(node.effect.kind)).is_true()


func test_display_names_fit_the_card_plate_length_rule() -> void:
	# The epithet-pool plate rule (docs/voice-bible.md §5): plate-class
	# phrases stay whole on wrapping plates — the tree's node titles obey
	# the same length discipline the L1-C card inherits.
	for node in tree_nodes():
		assert_str(node.display_name).is_not_empty()
		assert_int(node.display_name.length()).is_less_equal(28)


func tree_nodes() -> Array[UnlockNodeDef]:
	return _tree().nodes


# --- the cost curve (docs/balance.md's L1 section is the rationale of record) ----


func test_tier_one_nodes_are_affordable_from_run_one() -> void:
	## Earn rates: ~150-260 lp per ended run (wins ~230-260 at the 79h
	## mean; losses/crushes ~150) — every ungated node must be buyable from
	## the FIRST bank, and there must be enough of them that run 1-2 show
	## tree growth (R5: breadth-first cheap nodes first).
	var tier_one: Array[StringName] = []
	for node in tree_nodes():
		if node.prerequisites.is_empty():
			tier_one.append(node.id)
			assert_int(node.cost).is_less_equal(120)
	assert_int(tier_one.size()).is_greater_equal(4)


func test_full_tree_costs_eight_to_twelve_measured_runs() -> void:
	## The curve of record: 2700 lp total vs the ~150-260 lp/run earn band
	## (mean ~205 baseline, wins trending richer as the Survivors branch
	## compresses runs) = the full tree lands across ~8-12 runs, inside the
	## L1-B2 contract; the bounds keep a future node-add from silently
	## halving or doubling the campaign length.
	var total := _total_cost()
	assert_int(total).is_greater_equal(2400)
	assert_int(total).is_less_equal(3000)
	assert_int(total).is_equal(2700)


func test_costs_strictly_increase_along_prerequisite_edges() -> void:
	## Monotonic within branch tiers, stated graph-natively: a gated node
	## always costs MORE than the node that gates it — the tree reads as
	## one rising curve per branch, never a cheap capstone behind an
	## expensive approach.
	var by_id := {}
	for node in tree_nodes():
		by_id[node.id] = node
	for node in tree_nodes():
		for prerequisite in node.prerequisites:
			var gate: UnlockNodeDef = by_id[prerequisite]
			assert_int(node.cost).is_greater(gate.cost)


# --- the feel bounds (Prof X lane: felt, never collapsing) ------------------------


func test_every_effect_value_is_felt_but_restrained() -> void:
	## Per-node bounds: every multiplier is a nudge a player can feel
	## (>= 5% per node) without any single node rewriting the economy or
	## the pressure model (<= 15% off a cost/time, <= +20% stipend; the
	## pressure kinds are capped where the L1-B2 probe measured their
	## failure lines — decay <= +20%/node with the compound under x1.25
	## (the greed crush erodes above it), veterans <= +10% (the
	## compression plateau's cliff sits at x1.15)).
	for node in tree_nodes():
		var value: float = node.effect.value
		match node.effect.kind:
			&"stipend_bonus":
				assert_float(value).is_greater_equal(1.05)
				assert_float(value).is_less_equal(1.20)
			&"suspicion_decay":
				assert_float(value).is_greater_equal(1.05)
				assert_float(value).is_less_equal(1.20)
			&"veterans":
				assert_float(value).is_greater_equal(1.03)
				assert_float(value).is_less_equal(1.10)
			_:
				assert_float(value).is_greater_equal(0.85)
				assert_float(value).is_less_equal(0.98)


func test_full_tree_purchase_and_compound_bounds() -> void:
	## Tree order is a purchase order (every node listed after its
	## prerequisites): an exact bank of the tree total buys EVERYTHING and
	## lands at exactly zero — the cost curve's own closed-form check.
	var tree := _tree()
	var meta := RunMeta.new()
	meta.legacy_points = _total_cost()
	var legacy := LegacySystem.new(tree, meta)
	for id in legacy.node_ids():
		assert_bool(legacy.purchase(id)).is_true()
	assert_int(legacy.bank()).is_equal(0)
	assert_int(legacy.owned_count()).is_equal(15)
	# The resolved bundle — the full-tree modifiers the balance probe
	# drives, pinned EXACTLY (the balance doc's numbers live here) and
	# bounded. The training compound may not cross the measured-and-
	# rejected 0.75 retune line (docs/balance.md 2026-09-17: faster base
	# drills pushed the first-win tail to 169h past the 132h bound); the
	# economy fields keep the same order of restraint; the stipend is
	# capped; the decay compound stays under x1.25 (the L1-B2 probe
	# measured the greed crush ERODING seed-by-seed from ~x1.27 up — at
	# x1.4375 one probe seed survived 400h of never-lay-low; the shipped
	# x1.155 crushes all three probe seeds at 26h, the baseline hour) and
	# the veterans compound is a nudge (<= x1.10 — the compression
	# plateau's measured cliff: >= x1.15 starts losing seeds to early
	# commits), never an odds rewrite.
	var mods := legacy.modifiers()
	assert_bool(mods.is_identity()).is_false()
	assert_int(mods.recruit_arrival_interval_milli).is_equal(SimFixed.MILLI)
	assert_int(mods.building_cost_milli).is_equal(803)
	assert_int(mods.gear_cost_milli).is_equal(855)
	assert_int(mods.training_time_milli).is_equal(884)
	assert_int(mods.stipend_milli).is_equal(1306)
	assert_int(mods.suspicion_decay_milli).is_equal(1155)  # 1.05 x 1.10
	assert_int(mods.veterans_milli).is_equal(1080)
	assert_int(mods.recruit_arrival_interval_milli).is_greater_equal(800)
	assert_int(mods.building_cost_milli).is_greater_equal(700)
	assert_int(mods.gear_cost_milli).is_greater_equal(800)
	assert_int(mods.training_time_milli).is_greater_equal(750)
	assert_int(mods.stipend_milli).is_less_equal(1600)
	assert_int(mods.suspicion_decay_milli).is_less_equal(1250)
	assert_int(mods.veterans_milli).is_less_equal(1100)
	# Six of the seven effect kinds are in play; the ARRIVAL lever is
	# deliberately absent — the balance probe measured it dead above 1.0
	# (arrivals are acceptance-gated by the road's capacity pause, so a
	# quieter road changes nothing) and net-harmful below 1.0 (faster
	# arrivals multiply the gate-crowd suspicion acts). Re-adding an
	# arrival node is a balance decision against that recorded finding,
	# not a content edit.
	var kinds := {}
	for node in tree_nodes():
		kinds[node.effect.kind] = true
	assert_int(kinds.size()).is_equal(6)
	assert_bool(kinds.has(&"recruit_arrival_interval_multiplier")).is_false()
	for kind in [&"stipend_bonus", &"building_cost_multiplier", &"gear_cost_multiplier", &"training_time_multiplier", &"suspicion_decay", &"veterans"]:
		assert_bool(kinds.has(kind)).is_true()


# --- the CopyDeck voice seam (branch names + node flavors) ------------------------


func test_every_branch_and_node_is_voiced_through_the_full_seam() -> void:
	var table := _table()
	var branches := {}
	for node in tree_nodes():
		branches[node.branch] = true
	var expected: Array[StringName] = []
	for branch in branches.keys():
		expected.append(StringName("unlock_branch_%s" % branch))
	for node in tree_nodes():
		expected.append(StringName("unlock_flavor_%s" % node.id))
	for key in expected:
		# KEY_TOKENS (the validator's vocabulary — content cannot invent
		# keys, the tree cannot ship unvoiced)…
		assert_bool(CopyTable.KEY_TOKENS.has(key)).is_true()
		# …DEFAULTS (the code-side floor reads in voice)…
		assert_bool(CopyDeck.DEFAULTS.has(key)).is_true()
		# …CONSUMERS (the audit table: no orphan copy)…
		assert_bool(CopyDeck.CONSUMERS.has(key)).is_true()
		# …and the SHIPPED table carries the key with exactly the floor's
		# line (tree copy is static content: one variant, rotor 0, both
		# sources agree — one voice, two origins).
		assert_bool(table.templates.has(key)).is_true()
		var shipped: PackedStringArray = table.templates[key]
		assert_int(shipped.size()).is_equal(1)
		assert_str(String(shipped[0])).is_equal(String(CopyDeck.DEFAULTS[key][0]))
		assert_str(String(shipped[0])).is_not_empty()
	# No orphans the other way: every unlock key in the vocabulary belongs
	# to this tree's branches or nodes.
	for key in CopyTable.KEY_TOKENS.keys():
		if String(key).begins_with("unlock_"):
			assert_bool(expected.has(key)).is_true()


func test_copy_lines_fit_their_surface_budgets_in_real_font_metrics() -> void:
	## The T-UI-06/09 pin pattern applied to the tree's voice: branch
	## plates and node flavor rows, measured in the theme's real
	## ChronicleLine face at its RESOLVED render size (the declared 24
	## since the readability pass), clear their budget classes by
	## CLIP_MARGIN. The L1-C tree UI inherits the
	## guarantee whatever plate widths it lands on inside these classes.
	var line: Control = preload("res://ui/theme/chronicle_line.tscn").instantiate()
	get_tree().root.add_child(line)
	await get_tree().process_frame
	var label := _label_of(line)
	assert_that(label).is_not_null()
	var declared: int = (load("res://ui/theme/spread_theme.tres") as Theme) \
		.get_font_size(&"font_size", &"ChronicleLine")
	assert_int(declared).is_equal(24)
	var face := label.get_theme_font("font")
	var size := label.get_theme_font_size(&"font_size")
	assert_int(size).is_greater_equal(declared)
	var table := _table()
	var worst := -1000000.0
	var worst_key := &""
	var measured := 0
	for entry in _voiced_keys_with_budgets():
		var key: StringName = entry["key"]
		var budget: float = entry["budget"]
		var text := String(CopyDeck.variants(table, key)[0])
		assert_bool(text.contains("{")).is_false()  # literal lines only
		var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		measured += 1
		if width - (budget - CLIP_MARGIN) > worst:
			worst = width - (budget - CLIP_MARGIN)
			worst_key = key
	assert_float(worst).is_less_equal(0.0)
	assert_int(measured).is_equal(19)
	print("[unlock-copy] tightest line: %s at %.0fpx inside its budget-margin" % [String(worst_key), -worst])
	line.queue_free()


func _voiced_keys_with_budgets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var branches := {}
	for node in tree_nodes():
		branches[node.branch] = true
	for branch in branches.keys():
		out.append({"key": StringName("unlock_branch_%s" % branch), "budget": BRANCH_PLATE_BUDGET})
	for node in tree_nodes():
		out.append({"key": StringName("unlock_flavor_%s" % node.id), "budget": FLAVOR_ROW_BUDGET})
	return out


func _label_of(line: Control) -> Label:
	for child in line.get_children():
		var row := child as HBoxContainer
		if row == null:
			continue
		for item in row.get_children():
			if item is Label:
				return item
	return null


# --- the branch crests (art-manifested; pending art is honest) -------------------


func test_branch_crests_cover_exactly_the_tree_branches_and_resolve() -> void:
	var tree := _tree()
	var manifest := _pack().art
	var branches := {}
	for node in tree_nodes():
		branches[node.branch] = true
	# Declared for exactly the tree's branches — no crestless branch, no
	# dead entries (the validator's own rule, pinned on the shipped tree).
	assert_int(tree.branch_crests.size()).is_equal(branches.size())
	for branch in branches.keys():
		assert_bool(tree.branch_crests.has(branch)).is_true()
	# Every crest resolves to a manifest asset.
	for branch in tree.branch_crests.keys():
		var crest: StringName = tree.branch_crests[branch]
		var found := false
		for asset in manifest.assets:
			if asset.id == crest:
				found = true
				# Pending art is legal (the T-ARCH-04 hatch — the Armorial
				# pack needs its one human purchase), but the entry must be
				# honest: licensed and flagged for the ship flip.
				assert_str(asset.license).is_not_empty()
				assert_bool(asset.pending).is_true()
		assert_bool(found).is_true()


# --- the red paths of the crest cross-check (message wording is API) -------------


func test_missing_branch_crest_is_refused() -> void:
	var tree: UnlockTreeDef = _tree().duplicate(true)
	tree.branch_crests.erase(&"yard")
	var errors := ContentValidator.validate_unlock_tree(tree, _pack().art)
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "unlock-tree: branch 'yard' has no crest in branch_crests (declare it or clear the dictionary)")).is_true()


func test_unresolved_branch_crest_is_refused() -> void:
	var tree: UnlockTreeDef = _tree().duplicate(true)
	tree.branch_crests[&"yard"] = &"crest_no_such_thing"
	var errors := ContentValidator.validate_unlock_tree(tree, _pack().art)
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "unlock-tree 'yard': crest 'crest_no_such_thing' missing from art manifest")).is_true()
	# Standalone scope (no manifest) checks only the shape — the tree
	# order/branches still validate clean beside the map itself.
	assert_bool(ContentValidator.validate_unlock_tree(tree).is_empty()).is_true()


func test_crest_for_a_branchless_tree_entry_is_refused() -> void:
	var tree: UnlockTreeDef = _tree().duplicate(true)
	tree.branch_crests[&"ghost_branch"] = &"crest_yard"
	var errors := ContentValidator.validate_unlock_tree(tree)
	assert_bool(errors.any(func(e: String) -> bool:
		return e == "unlock-tree: branch_crests carries branch 'ghost_branch' with no nodes in tree")).is_true()
