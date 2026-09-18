## Unit tests for the legacy deck screen (L1-C) — Daredevil lane.
##
## Mirrors ui/screens/legacy/ + the two entry seams (the spread header's
## verbs row, the boot title card's Legacy chip). What is pinned:
##   - THE PRESENTER: node cards map the tree EXACTLY (id, display
##     name, branch family, cost, flavor from the CopyDeck key, the
##     effect payload templated into plain readable terms per registered
##     kind), the bank arithmetic (bank + spent = total earned), the
##     runs-recorded line source, view-hash determinism;
##   - CARD STATES in line form: owned SOLID, affordable DASHED +
##     purchasable, locked STRUCK + the "requires <node>" note naming
##     the FIRST missing prerequisite, unaffordable DASHED + the
##     shortfall count — the decision order the LegacySystem owns;
##   - THE EMPTY STATE: a fresh bank (first run unfinished) still opens
##     the deck — all cards present, every one locked or short, the
##     CopyDeck "earn your first legacy" line exact;
##   - THE BUY PATH: one step (a shop, not a gamble) through the REAL
##     host command — the meta domain records the id, the bank
##     decrements by the node's cost, the confirmation line prints
##     ("The Survivors remember <node>."), the sheet rebinds LIVE (card
##     now owned, bank label updated, focus still on the card);
##     refusals print their reason and mutate NOTHING;
##   - THE MOUNT DISCIPLINE: a deck opened over a live hand prints the
##     honest "takes effect with the next hand" note; the ended-table
##     deck does not;
##   - THE ENTRIES: the header verb on BOTH slots (focus-equivalent id,
##     full grip), open seeds focus, back closes and returns focus to
##     the chip; the TITLE card prints its Legacy chip only
##     post-first-run (a real ended hand through a real save);
##   - INPUT PARITY x3 (card tap / pad primary / Enter through the real
##     pipeline), the four common sizes unclipped with focus never
##     stranded, the new copy lines' font-metric budget;
##   - PERSISTENCE: a purchase survives a fresh host booting the same
##     save root (the host persists the meta at once).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const LegacyScreenScript := preload("res://ui/screens/legacy/legacy_screen.gd")
const LegacySheetScript := preload("res://ui/screens/legacy/legacy_sheet.gd")
const MainShell := preload("res://ui/main.gd")

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]
const EXPECTED_PORTRAIT := [true, false, false, true]

var _dir_seq := 0


func after() -> void:
	get_window().size = Vector2i(720, 720)
	_erase_dir("user://cs_l1c_tests")


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
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


func _test_host(run_seed: int = 20260917) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_l1c_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


## End the running hand through the REAL verbs (abort banks fast and
## keeps this suite inside the harness budget; the win path is exercised
## by the chronicle suite), then deal the next hand exactly as the host
## does. The meta domain banks the score — the deck's whole economy.
func _end_hand(host: GameHost, hours: int) -> void:
	host.fast_forward(hours * SimEngine.TICKS_PER_SIM_HOUR)
	host.submit(&"run_abort")
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _enter_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	return key


func _mounted_spread(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = false
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## Poll until the viewport's focus owner is one of the deck's own
## focusables (the settle contract landed on REAL layout).
func _await_seeded(legacy: LegacyScreenScript) -> void:
	for i in 60:
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null:
			continue
		for card in legacy.sheet().cards():
			if card == focus:
				return
		if legacy.sheet().back_chip() == focus:
			return


func _first_affordable(legacy: LegacyScreenScript) -> LegacySheetScript.LegacyCard:
	for card in legacy.sheet().cards():
		if bool(card.model()["purchasable"]):
			return card
	return null


# --- presenter: the tree mapped exactly ----------------------------------------------------


func test_node_cards_map_tree_fields_exactly() -> void:
	var host := _test_host()
	host.meta.legacy_points = 900
	var view := LegacyPresenter.view(host)
	var tree := Inks.pack().unlock_tree
	assert_int(int(view["node_count"])).is_equal(tree.nodes.size())
	# Branch families print in tree order, the nodes in tree order within.
	var expected_branch_order: Array[StringName] = []
	for def: UnlockNodeDef in tree.nodes:
		if not expected_branch_order.has(def.branch):
			expected_branch_order.append(def.branch)
	var branches: Array = view["branches"]
	assert_int(branches.size()).is_equal(expected_branch_order.size())
	var seen := 0
	for i in branches.size():
		var branch: Dictionary = branches[i]
		assert_str(String(branch["id"])).is_equal(String(expected_branch_order[i]))
		# The CopyDeck branch name resolves from the shipped key.
		assert_str(String(branch["name"])).is_equal(String(Inks.pack().copy
			.templates[StringName("unlock_branch_" + String(branch["id"]))][0]))
		# The crest key is the tree's own map entry.
		assert_str(String(branch["crest_key"])).is_equal(
			String(String(tree.branch_crests.get(StringName(String(branch["id"])), &""))))
		for node: Dictionary in branch["nodes"]:
			var def := host.unlock_node(StringName(String(node["id"])))
			assert_that(def).is_not_null()
			assert_str(String(node["name"])).is_equal(def.display_name)
			assert_int(int(node["cost"])).is_equal(def.cost)
			# The flavor is the CopyDeck key's own line (shaped ≤ 2 rows).
			assert_str(String(node["flavor_plain"])).is_equal(
				String(Inks.pack().copy.templates[StringName("unlock_flavor_" + String(def.id))][0]))
			assert_int(String(node["flavor"]).split("\n").size()).is_less_equal(2)
			seen += 1
	assert_int(seen).is_equal(tree.nodes.size())


func test_effect_lines_derive_from_the_payload_in_plain_terms() -> void:
	# Every registered kind, both directions, templated from the value.
	var cases := {
		[&"building_cost_multiplier", 0.95]: "buildings cost 5% less",
		[&"building_cost_multiplier", 1.25]: "buildings cost 25% more",
		[&"gear_cost_multiplier", 0.9]: "gear costs 10% less",
		[&"training_time_multiplier", 0.97]: "training runs 3% faster",
		[&"training_time_multiplier", 1.1]: "training runs 10% slower",
		[&"stipend_bonus", 1.1]: "the starting stipend pays 10% more",
		[&"stipend_bonus", 0.9]: "the starting stipend pays 10% less",
		[&"suspicion_decay", 1.05]: "suspicion cools 5% faster",
		[&"veterans", 1.08]: "the army fights 8% above its power",
		[&"recruit_arrival_interval_multiplier", 0.9]: "the road runs 10% busier",
		[&"made_up_kind", 1.5]: "an effect the press does not yet print (made_up_kind)",
	}
	for key in cases.keys():
		var effect := UnlockEffect.new()
		effect.kind = key[0]
		effect.value = key[1]
		assert_str(LegacyPresenter.effect_line(effect)).is_equal(String(cases[key]))
	# Null effect degrades honestly; identity value says so.
	assert_str(LegacyPresenter.effect_line(null)).is_equal("an effect the press has not set")
	var identity := UnlockEffect.new()
	identity.kind = &"stipend_bonus"
	identity.value = 1.0
	assert_str(LegacyPresenter.effect_line(identity)).is_equal(
		"an effect too fine for the press to print")


func test_bank_arithmetic_and_runs_line() -> void:
	var host := _test_host()
	var view := LegacyPresenter.view(host)
	assert_int(int(view["bank"])).is_equal(0)
	assert_int(int(view["total_earned"])).is_equal(0)
	assert_int(int(view["runs_recorded"])).is_equal(0)
	# Two real ended hands bank their scores; the total earned tracks.
	_end_hand(host, 4)
	_end_hand(host, 3)
	view = LegacyPresenter.view(host)
	assert_int(int(view["bank"])).is_equal(host.meta.legacy_points)
	assert_int(int(view["runs_recorded"])).is_equal(2)
	assert_int(int(view["total_earned"])).is_equal(int(view["bank"]))
	# A purchase spends the bank: total earned = bank + spent, always.
	host.meta.legacy_points = int(view["total_earned"]) + 200
	view = LegacyPresenter.view(host)
	var cost := host.unlock_node(&"grandmas_recipes").cost
	assert_bool(host.unlock_purchase(&"grandmas_recipes")).is_true()
	view = LegacyPresenter.view(host)
	assert_int(int(view["bank"])).is_equal(int(view["total_earned"]) - cost)
	assert_int(int(view["spent"])).is_equal(cost)
	assert_int(int(view["owned_count"])).is_equal(1)


# --- card states in line form ---------------------------------------------------------------


func test_card_states_line_form_and_notes() -> void:
	var host := _test_host()
	# Locked: bank covers the cost but the prerequisite is missing.
	var view := LegacyPresenter.view(host)
	var by_id := {}
	for branch: Dictionary in view["branches"]:
		for node: Dictionary in branch["nodes"]:
			by_id[String(node["id"])] = node
	# A root node with the bank still at zero: DASHED + shortfall.
	var root: Dictionary = by_id["grandmas_recipes"]
	assert_str(String(root["state"])).is_equal(LegacyPresenter.STATE_UNAFFORDABLE)
	assert_int(int(root["edge_form"])).is_equal(Inks.EdgeForm.DASHED)
	assert_int(int(root["shortfall"])).is_equal(int(root["cost"]))
	assert_str(String(root["note"])).is_equal("%d more legacy needed" % int(root["cost"]))
	# A gated node: STRUCK + the prerequisite named (bank irrelevant).
	var gated: Dictionary = by_id["the_seed_drawer"]
	assert_str(String(gated["state"])).is_equal(LegacyPresenter.STATE_LOCKED)
	assert_int(int(gated["edge_form"])).is_equal(Inks.EdgeForm.STRUCK)
	assert_str(String(gated["requires_name"])).is_equal("Grandma's Recipes")
	assert_str(String(gated["note"])).is_equal("requires Grandma's Recipes")
	# The dual-prereq node names the FIRST missing in tree order.
	var dual: Dictionary = by_id["the_salvage_charter"]
	assert_str(String(dual["note"])).is_equal("requires The Mason's Secret")
	# With the bank up (prereqs still missing): still locked, never a
	# misleading shortfall (the decision order is contract).
	host.meta.legacy_points = 5000
	view = LegacyPresenter.view(host)
	by_id.clear()
	for branch: Dictionary in view["branches"]:
		for node: Dictionary in branch["nodes"]:
			by_id[String(node["id"])] = node
	assert_str(String(by_id["the_seed_drawer"]["state"])).is_equal(LegacyPresenter.STATE_LOCKED)
	# Root nodes affordable: DASHED + purchasable + the ready note.
	var afford: Dictionary = by_id["grandmas_recipes"]
	assert_str(String(afford["state"])).is_equal(LegacyPresenter.STATE_AFFORDABLE)
	assert_int(int(afford["edge_form"])).is_equal(Inks.EdgeForm.DASHED)
	assert_bool(bool(afford["purchasable"])).is_true()
	assert_str(String(afford["note"])).is_equal("ready")
	# Owned: SOLID + kept.
	assert_bool(host.unlock_purchase(&"grandmas_recipes")).is_true()
	view = LegacyPresenter.view(host)
	for branch: Dictionary in view["branches"]:
		for node: Dictionary in branch["nodes"]:
			if String(node["id"]) == "grandmas_recipes":
				assert_str(String(node["state"])).is_equal(LegacyPresenter.STATE_OWNED)
				assert_int(int(node["edge_form"])).is_equal(Inks.EdgeForm.SOLID)
				assert_str(String(node["note"])).is_equal("kept in the deck")


func test_empty_state_opens_the_locked_deck() -> void:
	var host := _test_host()  # first run live, nothing earned
	var view := LegacyPresenter.view(host)
	assert_bool(bool(view["empty"])).is_true()
	assert_bool(bool(view["live_run"])).is_true()
	# The required first-run print, exact — and the deck still dealt.
	var lines: Array = view["empty_lines"]
	assert_str(String(lines[0]["text"])).is_equal(
		"the deck is still wrapped — no legacy earned yet")
	assert_str(String(lines[1]["text"])).is_equal(
		"Finish a hand, any hand. The bank keeps the points.")
	assert_int(int(view["node_count"])).is_equal(15)
	var states := {}
	for branch: Dictionary in view["branches"]:
		for node: Dictionary in branch["nodes"]:
			states[String(node["state"])] = true
	assert_bool(states.has(LegacyPresenter.STATE_AFFORDABLE)).is_false()
	assert_bool(states.has(LegacyPresenter.STATE_OWNED)).is_false()


# --- the buy path (a shop, not a gamble) ----------------------------------------------------


func test_purchase_through_the_real_host_command_updates_live() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	_end_hand(host, 4)  # banks a real score
	host.meta.legacy_points += 200  # fixture seam: reach the first card
	var screen: SpreadScreen = await _mounted_spread(host)
	var legacy := screen._legacy
	legacy.open(host)
	await _await_seeded(legacy)
	# One step: the focused affordable card IS the buy (no confirm).
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_bool(bool((focus as LegacySheetScript.LegacyCard).model()["purchasable"])).is_true()
	var id := StringName(String((focus as LegacySheetScript.LegacyCard).model()["id"]))
	var cost := host.unlock_node(id).cost
	var bank_before := host.unlock_bank()
	(focus as BaseButton).pressed.emit()
	for i in 6:
		await get_tree().process_frame
	# The REAL command went down: the meta domain records the id, the
	# bank decrements by exactly the node's cost.
	assert_bool(host.legacy.is_owned(id)).is_true()
	assert_int(host.unlock_bank()).is_equal(bank_before - cost)
	assert_int(int(legacy.stats[&"opens"])).is_equal(1)
	# The confirmation line printed (the clerk's voice).
	assert_str(legacy.sheet().print_text()).is_equal("The Survivors remember %s."
		% host.unlock_node(id).display_name)
	# The sheet rebound LIVE: the card reads owned, the bank label moved,
	# and focus never stranded — it sits on the SAME card, now owned.
	var card := legacy.sheet().card_for(id)
	assert_str(String(card.model()["state"])).is_equal(LegacyPresenter.STATE_OWNED)
	assert_str(legacy.sheet()._bank_label.text).contains(
		Inks.abbreviate_amount(host.unlock_bank()))
	# Focus never strands: the settle re-seats it on the SAME card (now
	# owned) — poll the settle's bounded real-layout wait out.
	for i in 60:
		await get_tree().process_frame
		if get_viewport().gui_get_focus_owner() == card:
			break
	assert_that(get_viewport().gui_get_focus_owner()).is_same(card as Object)
	# The buy persisted at once (the host's write-through).
	assert_bool(host.save_manager.load_meta() != null).is_true()
	screen.queue_free()


func test_refusals_print_reasons_and_mutate_nothing() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_spread(host)
	var legacy := screen._legacy
	legacy.open(host)
	await _await_seeded(legacy)
	var unlocked_before := host.meta.unlocks.duplicate(true)
	var bank_before := host.unlock_bank()
	# Unaffordable: the shortfall prints, the bank keeps everything.
	var root := legacy.sheet().card_for(&"grandmas_recipes")
	var cost := host.unlock_node(&"grandmas_recipes").cost
	(root as BaseButton).pressed.emit()
	await get_tree().process_frame
	assert_str(legacy.sheet().print_text()).is_equal(
		"The bank is short — %d more legacy." % cost)
	# Locked: the prerequisite's own name prints.
	var gated := legacy.sheet().card_for(&"the_seed_drawer")
	(gated as BaseButton).pressed.emit()
	await get_tree().process_frame
	assert_str(legacy.sheet().print_text()).is_equal(
		"The deck has an order — Grandma's Recipes first.")
	# Nothing mutated through either refusal.
	assert_int(int(legacy.stats[&"refusals"])).is_equal(2)
	assert_int(int(legacy.stats[&"purchases"])).is_equal(0)
	assert_dict(host.meta.unlocks).is_equal(unlocked_before)
	assert_int(host.unlock_bank()).is_equal(bank_before)
	# Owned: pressing a kept card says so (the fan's kept-consistent
	# rule — a pad player can walk onto it and read why).
	host.meta.legacy_points = 999
	assert_bool(host.unlock_purchase(&"grandmas_recipes")).is_true()
	legacy._bind()
	await get_tree().process_frame
	(legacy.sheet().card_for(&"grandmas_recipes") as BaseButton).pressed.emit()
	await get_tree().process_frame
	assert_str(legacy.sheet().print_text()).is_equal("Already pressed into the deck.")
	assert_int(int(legacy.stats[&"purchases"])).is_equal(0)
	screen.queue_free()


# --- the mount discipline -------------------------------------------------------------------


func test_midrun_deck_prints_the_next_hand_line() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_spread(host)
	var legacy := screen._legacy
	# A live hand under the paper: the honest note prints.
	legacy.open(host)
	await get_tree().process_frame
	assert_bool(bool(legacy.view()["live_run"])).is_true()
	assert_bool(legacy.sheet()._live_row.visible).is_true()
	assert_str(legacy.sheet()._live_label.text).is_equal(
		"A hand is live — new cards join the next hand.")
	legacy.close()
	# The ended table: no note (the next deal applies buys by rule).
	host.submit(&"run_abort")
	host.fast_forward(2)
	legacy.open(host)
	await get_tree().process_frame
	assert_bool(bool(legacy.view()["live_run"])).is_false()
	assert_bool(legacy.sheet()._live_row.visible).is_false()
	screen.queue_free()


# --- the entries ------------------------------------------------------------------------------


func test_header_verb_both_slots_open_back_focus() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	_end_hand(host, 3)
	host.meta.legacy_points += 200  # fixture seam: the seed is a BUYABLE card
	var screen: SpreadScreen = await _mounted_spread(host)
	# The affordance is on BOTH slots' header verbs rows, in world
	# grammar, with the router's focus-equivalence id and a full grip.
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		var chip := SpreadScreen.header_chip(slot, "legacy_chip")
		assert_that(chip).is_not_null()
		assert_str(String(chip.get_meta(&"focus_id", ""))).is_equal("legacy_chip")
		assert_float((chip as Control).get_combined_minimum_size().y) \
			.is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# The chip's press opens the deck (the one verb); focus seeds the
	# first AFFORDABLE card; no popup chrome anywhere.
	var chip := SpreadScreen.header_chip(screen.get_active_slot(), "legacy_chip")
	(chip as BaseButton).pressed.emit()
	await _await_seeded(screen._legacy)
	var legacy := screen._legacy
	assert_bool(legacy.is_open()).is_true()
	assert_int(int(screen.stats[&"legacies_opened"])).is_equal(1)
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_bool(focus is LegacySheetScript.LegacyCard).is_true()
	assert_bool(bool((focus as LegacySheetScript.LegacyCard).model()["purchasable"])).is_true()
	for node in legacy.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	# The papers are mutually exclusive: opening the chronicle folds it.
	screen.open_chronicle()
	await get_tree().process_frame
	assert_bool(legacy.is_open()).is_false()
	# BACK from the deck returns focus to the chip that opened it.
	screen.open_legacy()
	await _await_seeded(screen._legacy)
	legacy._unhandled_input(_action_event(&"back"))
	assert_bool(legacy.is_open()).is_false()
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(chip as Object)
	# Closed twice honestly: once folded by the chronicle's exclusivity,
	# once by BACK.
	assert_int(int(screen.stats[&"legacies_closed"])).is_equal(2)
	screen.queue_free()


func test_title_card_chip_post_first_run_through_a_real_save() -> void:
	# The visibility rule is pure and pinned.
	assert_bool(MainShell.show_legacy_chip_for(0)).is_false()
	assert_bool(MainShell.show_legacy_chip_for(1)).is_true()
	assert_bool(MainShell.show_legacy_chip_for(9)).is_true()
	# FRESH INSTALL: no chip on the card (nothing banked to spend).
	_dir_seq += 1
	var root := "user://cs_l1c_tests/title-%02d" % _dir_seq
	_erase_dir(root)
	var shell: MainShell = MainShell.new()
	shell.save_root = root
	shell.injected_now_epoch = 1800000000
	get_tree().root.add_child(shell)
	for i in 6:
		await get_tree().process_frame
	assert_that(shell._legacy_chip).is_null()
	assert_that(get_viewport().gui_get_focus_owner()).is_same(shell.primary_chip() as Object)
	# POST-FIRST-RUN (a real ended hand, saved through the real seam):
	# the same door now carries The Legacy chip, it opens the deck over
	# the title, and closing returns focus to the chip.
	shell._on_begin()
	for i in 6:
		await get_tree().process_frame
	var host := shell.host
	host.submit(&"run_abort")
	host.fast_forward(2)
	host.save_all()
	shell.queue_free()  # the whole first door folds (spread included)
	await get_tree().process_frame
	await get_tree().process_frame
	var reopened: MainShell = MainShell.new()
	reopened.save_root = root
	reopened.injected_now_epoch = 1800000000
	get_tree().root.add_child(reopened)
	for i in 6:
		await get_tree().process_frame
	assert_int(reopened.host.meta.runs_recorded).is_equal(1)
	assert_that(reopened._legacy_chip).is_not_null()
	var chip := reopened._legacy_chip
	(chip as BaseButton).pressed.emit()
	for i in 30:
		await get_tree().process_frame
		if reopened._legacy != null and reopened._legacy.is_open():
			break
	assert_bool(reopened._legacy.is_open()).is_true()
	assert_int(int(reopened._legacy.view()["runs_recorded"])).is_equal(1)
	# The deck buys through the real command even at the front door.
	reopened.host.meta.legacy_points += 200
	reopened._legacy._bind()
	await get_tree().process_frame
	var id := StringName(String(_first_affordable(reopened._legacy).model()["id"]))
	reopened._legacy.purchase(id)
	for i in 6:
		await get_tree().process_frame
	assert_bool(reopened.host.legacy.is_owned(id)).is_true()
	reopened._legacy._unhandled_input(_action_event(&"back"))
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(chip as Object)
	reopened.queue_free()


# --- input parity x3 ---------------------------------------------------------------------------


func test_deck_answers_from_all_three_input_modes() -> void:
	get_window().size = Vector2i(720, 1280)
	# (a) TOUCH: a card press is the gesture (the buy).
	var host_a := _test_host()
	_end_hand(host_a, 4)
	host_a.meta.legacy_points += 200
	var screen_a: SpreadScreen = await _mounted_spread(host_a)
	screen_a._legacy.open(host_a)
	await _await_seeded(screen_a._legacy)
	var card_a := _first_affordable(screen_a._legacy)
	var id_a := StringName(String(card_a.model()["id"]))
	(card_a as BaseButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(host_a.legacy.is_owned(id_a)).is_true()
	screen_a.queue_free()
	await get_tree().process_frame
	# (b) PAD: the non-positional primary activates the FOCUSED card
	# (the fallback the engine might not route as ui_accept).
	var host_b := _test_host()
	_end_hand(host_b, 4)
	host_b.meta.legacy_points += 200
	var screen_b: SpreadScreen = await _mounted_spread(host_b)
	screen_b._legacy.open(host_b)
	await _await_seeded(screen_b._legacy)
	assert_bool(screen_b._legacy.activate_focused()).is_true()
	await get_tree().process_frame
	assert_int(int(screen_b._legacy.stats[&"purchases"])).is_equal(1)
	# Pad B closes the deck (the back branch).
	screen_b._legacy._unhandled_input(_action_event(&"back"))
	assert_bool(screen_b._legacy.is_open()).is_false()
	screen_b.queue_free()
	await get_tree().process_frame
	# (c) KEYBOARD: Enter through the real input pipeline on the
	# focused card (the natively-routed form never reaches the fallback).
	var host_c := _test_host()
	_end_hand(host_c, 4)
	host_c.meta.legacy_points += 200
	var screen_c: SpreadScreen = await _mounted_spread(host_c)
	screen_c._legacy.open(host_c)
	await _await_seeded(screen_c._legacy)
	var focus_c := get_viewport().gui_get_focus_owner()
	var id_c := StringName(String((focus_c as LegacySheetScript.LegacyCard).model()["id"]))
	Input.parse_input_event(_enter_key())
	for i in 6:
		await get_tree().process_frame
	assert_bool(host_c.legacy.is_owned(id_c)).is_true()
	screen_c.queue_free()


# --- unclipped + determinism + persistence ------------------------------------------------------


func _clipped_controls(root: Control, design: Vector2) -> Array[String]:
	## Scrolled content is EXCLUDED (the deck scrolls inside its band by
	## design): the ScrollContainer's subtree is skipped, the container
	## itself (the viewport) is still audited.
	var offenders: Array[String] = []
	var queue: Array[Control] = [root]
	while not queue.is_empty():
		var node: Control = queue.pop_front()
		if not node.is_visible_in_tree():
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.size.x > 0.5 and rect.size.y > 0.5:
			if rect.position.x < -0.5 or rect.position.y < -0.5 \
					or rect.end.x > design.x + 0.5 or rect.end.y > design.y + 0.5:
				offenders.append("%s@%s" % [node.name, rect])
		if node is ScrollContainer:
			continue  # its children scroll by design
		for child in node.get_children():
			if child is Control:
				queue.append(child)
	return offenders


func test_unclipped_at_four_sizes_focus_never_stranded() -> void:
	var host := _test_host()
	_end_hand(host, 4)
	host.meta.legacy_points += 400
	var screen: SpreadScreen = await _mounted_spread(host)
	var legacy := screen._legacy
	var router: LayoutRouter = screen.get_router()
	Engine.time_scale = 60.0
	for i in TEST_SIZES.size():
		get_window().size = TEST_SIZES[i]
		for f in 240:
			await get_tree().process_frame
			if router.is_portrait() == EXPECTED_PORTRAIT[i] and router.design_size().x > 1.0:
				break
		Engine.time_scale = 1.0
		for f in 3:
			await get_tree().process_frame
		screen.open_legacy()
		await _await_seeded(legacy)
		assert_bool(legacy.is_open()).is_true()
		var design := router.design_size()
		# The whole deck renders (15 cards in 4 families) and nothing
		# clips the design bounds; focus is never stranded.
		assert_int(legacy.sheet().cards().size()).is_equal(15)
		for offender in _clipped_controls(legacy as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		# THE COLLAPSED-MINIMUM REGRESSION (the round-1 capture find,
		# probe-pinned): Button's native minimum shadows the
		# _get_minimum_size virtual in Godot 4.7, so the card's minimum
		# lands through custom_minimum_size at bind — every card keeps a
		# FULL GRIP and no two cards overlap (the 18px slivers the first
		# captures showed).
		var rects: Array[Rect2] = []
		for card in legacy.sheet().cards():
			var min_size: Vector2 = (card as Control).get_combined_minimum_size()
			assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN)) \
				.override_failure_message("card %s collapsed to %.0fx%.0f"
					% [card.model()["name"], min_size.x, min_size.y])
			assert_float((card as Control).size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
			rects.append((card as Control).get_global_rect())
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				var inter: Rect2 = rects[a].intersection(rects[b])
				assert_bool(inter.size.x > 1.0 and inter.size.y > 1.0).is_false() \
					.override_failure_message("cards %d and %d overlap at %s" % [a, b, inter])
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
		legacy.close()
		await get_tree().process_frame
		Engine.time_scale = 60.0
	Engine.time_scale = 1.0
	screen.queue_free()


func test_view_hash_deterministic_and_meta_sensitive() -> void:
	var host_a := _test_host()
	var host_b := _test_host()
	_end_hand(host_a, 4)
	_end_hand(host_b, 4)
	assert_int(LegacyPresenter.view_hash(LegacyPresenter.view(host_a))) \
		.is_equal(LegacyPresenter.view_hash(LegacyPresenter.view(host_b)))
	# A purchase moves it; a bank move moves it.
	host_a.meta.legacy_points += 300
	assert_int(LegacyPresenter.view_hash(LegacyPresenter.view(host_a))) \
		.is_not_equal(LegacyPresenter.view_hash(LegacyPresenter.view(host_b)))
	assert_bool(host_a.unlock_purchase(&"grandmas_recipes")).is_true()
	assert_int(LegacyPresenter.view_hash(LegacyPresenter.view(host_a))) \
		.is_not_equal(LegacyPresenter.view_hash(LegacyPresenter.view(host_b)))


func test_purchase_survives_a_fresh_host_boot() -> void:
	var host := _test_host()
	_end_hand(host, 5)
	host.meta.legacy_points += 300
	assert_bool(host.unlock_purchase(&"grandmas_recipes")).is_true()
	assert_bool(host.save_all()).is_true()
	# A fresh process's host boots from the same root: the owned set and
	# the spent bank both restore (the deck's whole point).
	var revived := GameHost.new(host.run_seed, host.save_manager.meta_path().get_base_dir())
	revived.autosave_interval_ticks = 0
	assert_bool(revived.boot(0)).is_true()
	assert_bool(revived.legacy.is_owned(&"grandmas_recipes")).is_true()
	var view := LegacyPresenter.view(revived)
	assert_int(int(view["owned_count"])).is_equal(1)
	assert_int(int(view["spent"])).is_equal(host.unlock_node(&"grandmas_recipes").cost)
	for branch: Dictionary in view["branches"]:
		for node: Dictionary in branch["nodes"]:
			if String(node["id"]) == "grandmas_recipes":
				assert_str(String(node["state"])).is_equal(LegacyPresenter.STATE_OWNED)


# --- the copy budget (the new lines, real font metrics) -------------------------------------------


func test_new_copy_lines_fit_the_print_row_budget() -> void:
	## The L1-C lines in the theme's real ChronicleLine face at the
	## CONSERVATIVE 24 over-measure, worst-case substituted (the tree's
	## longest node name, the widest shortfall), must clear the deck's
	## print-row label budget with >= 30px margin (test_copy_voice pins
	## the same lines at the family budgets; this pin is the SHEET's own
	## label width — the surface the sheet actually grants).
	const PRINT_ROW_BUDGET := 536.0
	const CLIP_MARGIN := 30.0
	var theme: Theme = load("res://ui/theme/spread_theme.tres") as Theme
	var font: Font = theme.get_font(&"font", &"ChronicleLine")
	var size := int(theme.get_font_size(&"font_size", &"ChronicleLine"))
	var node := ""
	for def: UnlockNodeDef in Inks.pack().unlock_tree.nodes:
		if def.display_name.length() > node.length():
			node = def.display_name
	var lines := [
		CopyDeck.line(Inks.pack().copy, &"legacy_empty_1", 0),
		CopyDeck.line(Inks.pack().copy, &"legacy_empty_2", 0),
		CopyDeck.line(Inks.pack().copy, &"legacy_midrun_note", 0),
		CopyDeck.line(Inks.pack().copy, &"legacy_purchase_line", 0, {"node": node}),
		CopyDeck.line(Inks.pack().copy, &"legacy_refusal_prereq", 0, {"node": node}),
		CopyDeck.line(Inks.pack().copy, &"legacy_refusal_short", 0, {"short": 9999}),
		CopyDeck.line(Inks.pack().copy, &"legacy_refusal_owned", 0),
	]
	for line in lines:
		# At the DECLARED render size (the readability pass re-seam: the
		# old +2 over-measure measured at 26 what renders at 24).
		var px: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		assert_float(px).is_less_equal(PRINT_ROW_BUDGET - CLIP_MARGIN) \
			.override_failure_message("'%s' -> %.0fpx over budget" % [line, px])
