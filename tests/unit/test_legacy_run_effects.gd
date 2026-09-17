## Unit tests for the ENGINE side of the L1 legacy unlock tree: purchased
## nodes' effects applied AT RUN START through the LegacyModifiers bundle,
## hash visibility, save round-trip lockstep, determinism, and the zero-
## impact proof (no unlocks -> byte-identical to the pre-L1 composition).
## Mirrors sim/systems/run_lifecycle_system.gd + production_system.gd +
## unit_lifecycle_system.gd (the set_legacy_modifiers seams),
## sim/legacy_modifiers.gd, sim/legacy_system.gd, ui/host/game_host.gd
## (test-mapping rule). The meta-domain rules (schema validation, purchase
## refusal grammar, RunMeta persistence) live in test_legacy_system.gd.
extends GdUnitTestSuite

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")
const FULL_STACK := preload("res://tests/acceptance/suites/_full_stack.gd")

const SEED := 20260917


# --- Fixtures ------------------------------------------------------------------


## A tree with one node per effect kind, all cheap — the full vocabulary in
## play. Values chosen for exact integer math (halves and 1.25).
func _effect_tree() -> UnlockTreeDef:
	var tree := UnlockTreeDef.new()
	var add := func(id: StringName, kind: StringName, value: float) -> void:
		var node := UnlockNodeDef.new()
		node.id = id
		node.display_name = "Node %s" % id
		node.branch = &"test"
		node.cost = 10
		var effect := UnlockEffect.new()
		effect.kind = kind
		effect.value = value
		node.effect = effect
		tree.nodes.append(node)
	add.call(&"stipend_25", &"stipend_bonus", 1.25)
	add.call(&"walls_90", &"building_cost_multiplier", 0.9)
	add.call(&"drills_50", &"training_time_multiplier", 0.5)
	add.call(&"road_50", &"recruit_arrival_interval_multiplier", 0.5)
	add.call(&"kit_50", &"gear_cost_multiplier", 0.5)
	return tree


func _legacy_all_purchased() -> LegacySystem:
	var meta := RunMeta.new()
	meta.legacy_points = 10_000
	var tree := _effect_tree()
	var legacy := LegacySystem.new(tree, meta)
	for node in tree.nodes:
		legacy.purchase(node.id)
	return legacy


## Metronome arrivals (no jitter, no opening rush): the arrival stream
## draws NOTHING, so cadence assertions are exact.
func _metronome() -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_jitter_hours = 0.0
	tunables.recruit_arrival_early_count = 0
	return tunables


## The engine composition under test (mirrors _mvp_pack.stack_with_regimes:
## heartbeat -> run -> units -> production), with the optional legacy
## provider wired exactly the way GameHost does.
func _stack(seed: int, meta: RunMeta, legacy: LegacySystem = null, tunables: EconomyTunables = null) -> SimEngine:
	var pack := MVP.load_mvp()
	var engine := SimEngine.new(seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, meta, pack.starting_grants, legacy))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, tunables if tunables != null else pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, tunables if tunables != null else pack.tunables, null))
	return engine


func _boot(engine: SimEngine, ticks: int = 1) -> void:
	engine.submit_command(&"run_start")
	engine.submit_command(&"grant_resources")
	engine.fast_forward(ticks)


func _events_of_type(engine: SimEngine, type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for seq in range(engine.events.oldest_seq(), engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			found.append({"tick": event.tick, "subject": event.subject, "value": event.value, "value2": event.value2})
	return found


## Fast-forward until `cond` (a Callable -> bool) holds; false on timeout.
func _ff_until(engine: SimEngine, cond: Callable, max_ticks: int) -> bool:
	var ran := 0
	while ran < max_ticks:
		if cond.call():
			return true
		var step := engine.fast_forward(1)
		if step == 0:
			return false
		ran += 1
	return cond.call()


# --- The boot stipend -------------------------------------------------------------


func test_stipend_bonus_applies_to_the_boot_grant_at_run_start() -> void:
	var pack := MVP.load_mvp()
	var legacy := _legacy_all_purchased()
	var plain := _stack(SEED, RunMeta.new(), null)
	var boosted := _stack(SEED, RunMeta.new(), legacy)
	_boot(plain)
	_boot(boosted)
	for id in pack.starting_grants.keys():
		var base := int(pack.starting_grants[id])
		# Single floored division: 50 food x 1.25 = 62, 80 timber x 1.25 = 100.
		var expected := maxi(1, base * 1250 / 1000)
		assert_int(boosted.get_resource(id)).is_equal(expected)
		assert_int(plain.get_resource(id)).is_equal(base)
	# The grant events carry the paid amounts (visible, not silent).
	var boosted_grants := _events_of_type(boosted, &"resources_granted")
	assert_int(boosted_grants.size()).is_equal(pack.starting_grants.size())


func test_stipend_multiplier_is_serialized_and_restored_verbatim() -> void:
	var legacy := _legacy_all_purchased()
	var meta := legacy.meta
	var engine := _stack(SEED, meta, legacy)
	_boot(engine, 5)
	var state: Dictionary = engine.to_dict()["systems"]["run"]
	assert_int(int(state["legacy_stipend_milli"])).is_equal(1250)
	# A no-unlocks engine OMITS the key entirely (byte-identical saves).
	var plain := _stack(SEED, RunMeta.new(), null)
	_boot(plain, 5)
	assert_bool((plain.to_dict()["systems"]["run"] as Dictionary).has("legacy_stipend_milli")).is_false()


# --- Building costs ------------------------------------------------------------------


func test_building_cost_multiplier_scales_upgrade_cost_and_composes_with_regime() -> void:
	var pack := MVP.load_mvp()
	var production := ProductionSystem.new(pack.buildings, pack.tunables, null)
	# Identity: the farm's construction line is exactly the content base
	# (timber 15) — the pre-L1 cost, unchanged.
	var identity := production.upgrade_cost(&"farm")
	assert_int(int(identity.get(&"timber", 0))).is_equal(15)
	# x0.9 walls: 15 x 900 / 1000 = 13 (single floored division).
	var mods := LegacyModifiers.identity()
	mods.building_cost_milli = 900
	production.set_legacy_modifiers(mods)
	assert_int(int(production.upgrade_cost(&"farm").get(&"timber", 0))).is_equal(13)
	# Composition with a regime quirk at the SAME drain: iron_rotunda taxes
	# ALL costs x1.2; 15 x 1.2 x 0.9 = 16.2 -> 16 (one division at the end).
	production.set_regime(_regime_by_id(&"iron_rotunda"))
	assert_int(int(production.upgrade_cost(&"farm").get(&"timber", 0))).is_equal(16)
	# The applied multiplier is serialized + hash-visible when non-identity,
	# absent when identity.
	assert_int(int(production.to_dict()["legacy_cost_milli"])).is_equal(900)
	production.set_legacy_modifiers(LegacyModifiers.identity())
	assert_bool(production.to_dict().has("legacy_cost_milli")).is_false()
	var restored := ProductionSystem.new(pack.buildings, pack.tunables, null)
	restored.from_dict({"workers_idle": 0, "buildings": production.to_dict()["buildings"], "legacy_cost_milli": 900})
	assert_int(int(restored.upgrade_cost(&"farm").get(&"timber", 0))).is_equal(13)


func _regime_by_id(id: StringName) -> RegimeDef:
	for regime in MVP.load_mvp().regimes:
		if regime.id == id:
			return regime
	return null


# --- Training + arrivals + gear ----------------------------------------------------


func test_training_multiplier_scales_durations_and_keeps_zero_hour() -> void:
	var pack := MVP.load_mvp()
	var units := UnitLifecycleSystem.new(pack.units, pack.gear, _metronome())
	var base_militia := units.training_duration_milli(&"militia")
	assert_int(base_militia).is_equal(2 * 60 * SimFixed.MILLI)  # 2h drills = 120_000 milli-ticks
	var mods := LegacyModifiers.identity()
	mods.training_time_milli = 500
	units.set_legacy_modifiers(mods)
	assert_int(units.training_duration_milli(&"militia")).is_equal(base_militia / 2)
	# Zero-hour chores stay exactly zero under any multiplier.
	assert_int(units.training_duration_milli(&"worker")).is_zero()
	# Serialized only when non-identity; restored verbatim.
	var state := units.to_dict()
	assert_int(int((state["legacy_modifiers"] as Dictionary)["training_milli"])).is_equal(500)
	units.set_legacy_modifiers(LegacyModifiers.identity())
	assert_bool(units.to_dict().has("legacy_modifiers")).is_false()


func test_training_multiplier_speeds_completions_by_the_same_factor() -> void:
	## Same seed, same driver, one engine at identity and one at x0.5: the
	## 2h militia drills span 120 ticks to the tick, and the drills at x0.5
	## span exactly half of that. (119/59 ticks elapse BETWEEN the
	## training_started event and the promotion event — the first
	## milli-tick is credited on the drain tick itself.)
	assert_int(_militia_training_span(null)).is_equal(119)
	assert_int(_militia_training_span(_legacy_all_purchased())).is_equal(59)


## Drives one recruit into militia drills under the given modifiers and
## returns promoted_tick - training_started_tick (the pure training span).
func _militia_training_span(legacy: LegacySystem) -> int:
	var engine := SimEngine.new(SEED)
	var pack := MVP.load_mvp()
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, _metronome()))
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	if legacy != null:
		units.set_legacy_modifiers(legacy.modifiers())
	assert_bool(_ff_until(engine, func() -> bool: return units.pending_offers() > 0, 400)).is_true()
	var uid := units.offer_ids()[0]
	engine.submit_command(&"recruit_accept", &"", uid)
	engine.submit_command(&"assign_role", &"militia", uid)
	assert_bool(_ff_until(
		engine,
		func() -> bool: return units.unit_count(&"militia") > 0,
		400
	)).is_true()
	var started := _events_of_type(engine, &"training_started").filter(
		func(event: Dictionary) -> bool: return event["subject"] == StringName(&"militia")
	)
	var promoted := _events_of_type(engine, &"unit_promoted").filter(
		func(event: Dictionary) -> bool: return event["subject"] == StringName(&"militia")
	)
	assert_int(started.size()).is_equal(1)
	assert_int(promoted.size()).is_equal(1)
	return int(promoted[0]["tick"]) - int(started[0]["tick"])


func test_arrival_multiplier_speeds_the_whole_cadence_including_the_rush() -> void:
	## MVP tunables: the opening rush's first entry is 6 sim-min, so the
	## first arrival lands at tick 7 (docs/balance.md's measured zero-variance
	## opening); at x0.5 the whole cadence halves and it lands at tick 4.
	assert_int(_first_arrival_tick(null)).is_equal(7)
	assert_int(_first_arrival_tick(_legacy_all_purchased())).is_equal(4)


func _first_arrival_tick(legacy: LegacySystem) -> int:
	var engine := SimEngine.new(SEED)
	var pack := MVP.load_mvp()
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	if legacy != null:
		(engine.get_system(&"units") as UnitLifecycleSystem).set_legacy_modifiers(legacy.modifiers())
	engine.fast_forward(10)
	var arrivals := _events_of_type(engine, &"recruit_arrived")
	assert_int(arrivals.size()).is_greater(0)
	return int(arrivals[0]["tick"])


func test_gear_cost_multiplier_scales_recipe_payment() -> void:
	## The t1 sword's recipe is 10 iron + 5 timber; at x0.5 the forge charges
	## 5 + 2 (floored) — an exact pool pays to exactly zero either way.
	# Identity charges 10 iron + 5 timber from an exact pool.
	assert_int(_drive_and_equip(null, 10, 5)).is_equal(0)
	# x0.5 charges 5 + 2 from an exact pool (floored lines, never free).
	assert_int(_drive_and_equip(_legacy_all_purchased(), 5, 2)).is_equal(0)


## Drives one recruit to a trainee targeting knight, then equips the t1
## sword from an EXACT pool; returns iron + 1000 x timber left (0 = the
## pool paid to zero, i.e. the charged price was exactly the pool).
func _drive_and_equip(legacy: LegacySystem, iron: int, timber: int) -> int:
	var engine := SimEngine.new(SEED)
	var pack := MVP.load_mvp()
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, _metronome()))
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	if legacy != null:
		units.set_legacy_modifiers(legacy.modifiers())
	assert_bool(_ff_until(engine, func() -> bool: return units.pending_offers() > 0, 400)).is_true()
	var uid := units.offer_ids()[0]
	engine.submit_command(&"recruit_accept", &"", uid)
	engine.submit_command(&"assign_role", &"militia", uid)
	assert_bool(_ff_until(engine, func() -> bool: return units.idle_units(&"militia").size() > 0, 400)).is_true()
	uid = units.idle_units(&"militia")[0]
	engine.submit_command(&"start_training", &"trainee", uid)
	assert_bool(_ff_until(engine, func() -> bool: return units.idle_units(&"trainee").size() > 0, 400)).is_true()
	uid = units.idle_units(&"trainee")[0]
	engine.submit_command(&"start_training", &"knight", uid)
	engine.fast_forward(1)  # drain: the knight target makes the weapon slot legal
	engine.set_resource(&"iron", iron)
	engine.set_resource(&"timber", timber)
	engine.submit_command(&"equip_gear", &"gear_weapon_t1", uid)
	engine.fast_forward(1)
	assert_int(units.gear_tier(uid, &"weapon")).is_equal(1)
	return engine.get_resource(&"iron") + 1000 * engine.get_resource(&"timber")


# --- Hash visibility + serialization ----------------------------------------------


func test_unlocks_are_hash_visible_before_any_economy_moves() -> void:
	## Two engines, same seed, run_start only (no grant yet): the baked
	## modifier bundle alone separates the hashes — the T-ARCH-03 oracle can
	## see a lost multiplier even before it diverges a tick.
	var legacy := _legacy_all_purchased()
	var with_unlocks := _stack(SEED, legacy.meta, legacy)
	var without := _stack(SEED, RunMeta.new(), null)
	with_unlocks.submit_command(&"run_start")
	without.submit_command(&"run_start")
	with_unlocks.fast_forward(1)
	without.fast_forward(1)
	assert_int(with_unlocks.state_hash()).is_not_equal(without.state_hash())


func test_no_unlocks_engine_is_byte_identical_to_a_pre_legacy_engine() -> void:
	## THE zero-impact proof: a legacy provider with an empty owned set
	## serializes nothing, hashes nothing, changes nothing — the exact
	## composition the existing suites drive (which is why their recorded
	## digests survive this change unperturbed).
	var empty_legacy := LegacySystem.new(_effect_tree(), RunMeta.new())
	var with_provider := _stack(SEED, empty_legacy.meta, empty_legacy)
	var without := _stack(SEED, RunMeta.new(), null)
	_boot(with_provider, 600)
	_boot(without, 600)
	assert_int(with_provider.state_hash()).is_equal(without.state_hash())
	assert_bool(with_provider.to_dict() == without.to_dict()).is_true()


func test_round_trip_lockstep_with_unlocks_active() -> void:
	## The T-ARCH-03 discipline for the legacy seams: a mid-run save under
	## active modifiers restores verbatim and continues in lockstep — the
	## serialized keys are load-bearing (a gap here is exactly the class of
	## bug the quirks-hash fix closed).
	var legacy := _legacy_all_purchased()
	var engine := _stack(SEED, legacy.meta, legacy, _metronome())
	_boot(engine, 200)
	# The payload carries every applied multiplier.
	var state := engine.to_dict()
	var run_state: Dictionary = state["systems"]["run"]
	var production_state: Dictionary = state["systems"]["production"]
	var units_state: Dictionary = state["systems"]["units"]
	assert_int(int(run_state["legacy_stipend_milli"])).is_equal(1250)
	assert_int(int(production_state["legacy_cost_milli"])).is_equal(900)
	var units_mods: Dictionary = units_state["legacy_modifiers"]
	assert_int(int(units_mods["training_milli"])).is_equal(500)
	assert_int(int(units_mods["arrival_milli"])).is_equal(500)
	assert_int(int(units_mods["gear_cost_milli"])).is_equal(500)
	# The twin: same construction, same unlock set (its own meta copy), the
	# captured state applied — then lockstep through managed continuation.
	var twin_meta := RunMeta.new()
	twin_meta.apply_dict(legacy.meta.to_dict())
	var twin_legacy := LegacySystem.new(_effect_tree(), twin_meta)
	var twin := _stack(SEED, twin_meta, twin_legacy, _metronome())
	assert_bool(twin.apply_state_dict(state)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	for target in [engine, twin]:
		target.submit_command(&"upgrade_building", &"farm", 1)  # pays the DISCOUNTED price
	engine.fast_forward(300)
	twin.fast_forward(300)
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	assert_int((twin.get_system(&"production") as ProductionSystem).building_level(&"farm")).is_equal(1)


func test_same_seed_same_unlocks_replay_identically() -> void:
	var a := _legacy_all_purchased()
	var b := _legacy_all_purchased()
	var engine_a := _stack(SEED, a.meta, a)
	var engine_b := _stack(SEED, b.meta, b)
	_boot(engine_a, 400)
	_boot(engine_b, 400)
	assert_int(engine_a.state_hash()).is_equal(engine_b.state_hash())


func test_purchase_between_runs_lands_at_the_next_run_start() -> void:
	## The between-runs verb: a purchase made after a run ends changes the
	## NEXT run's boot, never the running one. Run 1 pays the honest stipend;
	## after aborting and buying the stipend node, the restart's grant pays
	## the bonus.
	var legacy := _legacy_all_purchased()
	legacy.meta.unlocks.clear()  # start owning nothing but the full bank
	var engine := _stack(SEED, legacy.meta, legacy)
	_boot(engine, 3)
	assert_int(engine.get_resource(&"food")).is_equal(50)  # the pack's honest stipend
	engine.submit_command(&"run_abort")
	engine.fast_forward(1)
	assert_bool(legacy.purchase(&"stipend_25")).is_true()
	engine.submit_command(&"run_restart")
	engine.submit_command(&"grant_resources")
	engine.fast_forward(2)
	assert_int(engine.get_resource(&"food")).is_equal(62)  # 50 x 1.25 floored


# --- GameHost wiring -----------------------------------------------------------------


func after() -> void:
	# Restore the process pack cache (the host tests inject a tree-bearing
	# copy); null forces the honest reload for every other suite.
	Inks._pack_cache = null
	_erase_dir("user://cs_legacy_host_tests")


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
	for file_name in files:
		dir.remove(file_name)
	for sub in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


## A host whose pack carries the effect tree, with the process pack cache
## injected. `fresh` wipes the scratch root first (unlock_purchase persists
## the meta domain, so roots must not leak state across suite runs); pass
## false when intentionally RELOADING a root a previous host wrote.
func _host_with_tree(seed: int, root: String, fresh := true) -> GameHost:
	if fresh:
		_erase_dir(root)
	var pack := Inks.pack().duplicate() as ContentPack
	pack.unlock_tree = _effect_tree()
	Inks._pack_cache = pack
	return GameHost.new(seed, root)


func test_host_exposes_legacy_reads_and_the_purchase_command() -> void:
	var host := _host_with_tree(SEED, "user://cs_legacy_host_tests/a")
	assert_array(host.unlock_tree_nodes()).is_equal([
		&"stipend_25", &"walls_90", &"drills_50", &"road_50", &"kit_50",
	])
	assert_int(host.unlock_bank()).is_zero()
	assert_array(host.unlock_owned()).is_empty()
	assert_array(host.unlock_affordable()).is_empty()  # empty bank: nothing affordable
	assert_bool(host.unlock_node(&"stipend_25") != null).is_true()
	# Seed the bank (the meta instance the host shares with every engine)
	# and buy: the command validates, mutates, and PERSISTS the meta domain.
	host.meta.legacy_points = 25
	# Every node costs 10 and none is gated: all five are affordable.
	assert_array(host.unlock_affordable()).is_equal([
		&"stipend_25", &"walls_90", &"drills_50", &"road_50", &"kit_50",
	])
	assert_bool(host.unlock_purchase(&"stipend_25")).is_true()
	assert_int(host.unlock_bank()).is_equal(15)
	assert_array(host.unlock_owned()).is_equal([&"stipend_25"])
	# Persist both domains, then boot a second host on the same root: the
	# purchase loads back — owned survives, bank stays decremented
	# (process-restart persistence).
	host.advance_ticks(5)
	assert_bool(host.save_all()).is_true()
	var reborn := _host_with_tree(SEED, "user://cs_legacy_host_tests/a", false)
	assert_bool(reborn.boot(0)).is_true()  # loads the saved run + meta
	assert_array(reborn.unlock_owned()).is_equal([&"stipend_25"])
	assert_int(reborn.unlock_bank()).is_equal(15)


func test_host_refuses_purchases_when_the_pack_has_no_tree() -> void:
	## The additive-optional contract still holds post-L1-B: a pack WITHOUT
	## a tree (a stripped duplicate — the shipped pack carries the L1-B
	## tree now, pinned by test_mvp_unlock_tree) runs an empty legacy
	## surface, and the purchase command refuses loudly (unknown node) —
	## never a crash.
	var stripped: ContentPack = Inks.pack().duplicate(true)
	stripped.unlock_tree = null
	Inks._pack_cache = stripped
	var host := GameHost.new(SEED, "user://cs_legacy_host_tests/b")
	host.boot(0)
	assert_array(host.unlock_tree_nodes()).is_empty()
	assert_bool(host.unlock_purchase(&"grandmas_recipes")).is_false()
	assert_int(host.unlock_bank()).is_zero()


func test_host_purchase_applies_at_the_next_run_start() -> void:
	var host := _host_with_tree(SEED, "user://cs_legacy_host_tests/c")
	host.boot(0)
	assert_int(host.engine.get_resource(&"food")).is_equal(50)
	host.meta.legacy_points = 25
	assert_bool(host.unlock_purchase(&"stipend_25")).is_true()
	host.restart_run()
	host.advance_ticks(3)  # restart drain + new stipend + one quiet tick
	assert_int(host.engine.get_resource(&"food")).is_equal(62)


func test_host_with_empty_unlocks_hashes_like_the_canonical_fixture() -> void:
	## The composition-parity rule holds through the legacy seam: a host
	## whose (tree-bearing) pack has ZERO purchases runs the same world as
	## the canonical fixture on the same seed.
	var host := _host_with_tree(777, "user://cs_legacy_host_tests/d")
	host.boot(0)
	var canonical := FULL_STACK.game_stack(777, RunMeta.new())
	canonical.submit_command(&"run_start")
	canonical.submit_command(&"grant_resources")
	canonical.fast_forward(600)
	host.advance_ticks(599)
	assert_int(host.engine.state_hash()).is_equal(canonical.state_hash())
