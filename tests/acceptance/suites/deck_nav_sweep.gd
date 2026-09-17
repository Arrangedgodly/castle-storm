## Deck controller navigation sweep — T-PERF-02 (Thor lane).
##
## A SCRIPTED pad-event walk of every interactive surface at the Deck's
## window (1280x800 landscape — the T-ARCH-02 target profile). The events
## are REAL InputEventJoypadButtons fed through Input.parse_input_event
## (device 0; the project's Deck baseline binds everything Any-Device, so
## device 0 matches) — the same dispatch pipeline a physical pad press
## rides:
##   dpad 11/12/13/14 -> ui_up/ui_down/ui_left/ui_right (focus movement,
##                        Godot's built-in joypad bindings)
##   A  (button 0)    -> the project's `primary` — NOT ui_accept (4.7's
##                        default ui_accept carries no joypad event, the
##                        engine fact every screen's pad fallback exists
##                        for; this sweep is what proves those fallbacks)
##   B  (button 1)    -> the project's `back`
##
## The contract swept, one section per surface:
##   1. THE SPREAD TABLE: from seeded focus, a BFS over the four dpad
##      directions reaches EVERY visible focusable of the active slot and
##      focus is never lost mid-walk (no dead ends);
##   2. THE ACTION FAN: pad A opens it off a focused card, dpad cycles
##      every chip (the focus trap holds), pad A submits the focused
##      chip, pad B folds — focus returns to the card each way;
##   3. THE ASSAULT: odds (focus seeds on RETREAT; dpad between the
##      chips; A on a below-floor COMMIT prints the refusal and stays
##      open; A on RETREAT closes — the pad fallback this sweep forced
##      into existence; on a floor-met table the first A ARMS the die
##      and the second casts it — the two-step raise), the vignette
##      (A skips), the outcome (A closes) — a full pad-only storm;
##   4. THE CHRONICLE LEDGER over a 50-hand ring: A on the header chip
##      opens it (the second pad fallback this sweep forced), dpad walks
##      the entries, A on a paging chip turns the page, B closes;
##   5. THE LEADER INTRO: A unfolds the one gesture, focus lands on the
##      table beneath;
##   6. THE SUSPICION CHOICE CARD: dpad walks its chips, B folds;
##   7. THE WHILE-YOU-WERE-AWAY PRINT: passive paper — the table keeps
##      focus through the whole print (nothing to navigate, nothing
##      stolen).
##
## No wall waits: paced paper runs under Engine.time_scale (the T-UI-05
## round-2 injected-time strategy), restored at the end.
extends RefCounted

const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

const DECK_WINDOW := Vector2i(1280, 800)
## Injected-time scale for the paced paths (the storm's vignette beats,
## the intro unfold, the choice card's slide). Every paced wait in this
## sweep is a forward state poll (nothing asserts mid-motion against
## frame counts), so the scale rides the same premise at 60 as it did at
## 20 — raised in the finishing #5 re-dispatch's harness-budget trim.
const WATCH_SCALE := 60.0
const QUIET_SEED := 20261103
## Probed in test_assault_vignette.gd: 2 t1 knights (power 30 > floor 23),
## iron_rotunda's army-side modifier — a deterministic pad-driven WIN.
const WIN_SEED := 20261207

const BTN_A := 0
const BTN_B := 1
const DPAD_UP := 11
const DPAD_DOWN := 12
const DPAD_LEFT := 13
const DPAD_RIGHT := 14
const DIRECTIONS: Array[int] = [DPAD_LEFT, DPAD_RIGHT, DPAD_UP, DPAD_DOWN]

## Synthetic platform epoch for the catch-up boundary (injected).
const T0 := 1_800_000_000

var _dir_seq := 0


func suite_name() -> String:
	return "deck_nav_sweep"


func run(harness) -> void:
	Engine.time_scale = WATCH_SCALE
	var window := (harness as Node).get_tree().root
	window.size = DECK_WINDOW

	await _sweep_spread_table(harness)
	await _sweep_action_fan(harness)
	await _sweep_assault(harness)
	await _sweep_chronicle(harness)
	await _sweep_intro(harness)
	await _sweep_suspicion_choice(harness)
	await _sweep_catch_up_print(harness)

	window.size = Vector2i(720, 720)
	Engine.time_scale = 1.0
	_erase_dir("user://cs_deck_nav")


# --- shared helpers ------------------------------------------------------------------------


func _tap(harness, button: int):
	## One pad press: down, a frame, up, a frame (the frame lets deferred
	## focus grabs and the engine's action dispatch land before we read).
	var tree: SceneTree = (harness as Node).get_tree()
	var press := InputEventJoypadButton.new()
	press.device = 0
	press.button_index = button as JoyButton
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	var release := InputEventJoypadButton.new()
	release.device = 0
	release.button_index = button as JoyButton
	release.pressed = false
	Input.parse_input_event(release)
	await tree.process_frame


func _focus_owner(harness) -> Control:
	return (harness as Node).get_viewport().gui_get_focus_owner()


func _frames(harness, count: int):
	var tree: SceneTree = (harness as Node).get_tree()
	for _i in count:
		await tree.process_frame


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_deck_nav/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _mounted_screen(harness, host: GameHost, intro_on := false) -> SpreadScreen:
	var screen: SpreadScreen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	harness.mount(screen)
	# Settle longer than the sibling suites' 2-3 frames: the sweep reads
	# SETTLED card geometry (the dpad's geometric neighbor resolution runs
	# against real rects — half-laid cards strand nodes unreachable).
	await _frames(harness, 10)
	return screen


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


## The visible focusables of the active slot (the pad can only walk what
## participates in focus on the visible topology).
func _slot_focusables(screen: SpreadScreen) -> Array[Control]:
	return _visible_focusables_under(screen.get_active_slot())


## Every visible focus-mode control under `root` (the generic collector —
## the slot offers its own; the paper layers are walked the same way).
func _visible_focusables_under(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	_collect_focusables(root, found)
	return found


func _collect_focusables(node: Node, into: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree():
			into.append(control)
	for child in node.get_children():
		_collect_focusables(child, into)


## BFS the dpad focus graph from wherever focus sits. Returns
## [reached_ids: Array[int], lost_focus_steps: int, steps: int].
func _walk_focus_graph(harness, max_steps := 240) -> Array:
	var tree: SceneTree = (harness as Node).get_tree()
	var reached: Array[int] = []
	var queue: Array[Control] = []
	var start := _focus_owner(harness)
	if start == null:
		return [[], 1, 0]
	reached.append(start.get_instance_id())
	queue.append(start)
	var lost := 0
	var steps := 0
	while not queue.is_empty() and steps < max_steps:
		var node := queue.pop_front() as Control
		for direction in DIRECTIONS:
			# Stand ON the node before every probe: each tap leaves focus on
			# its target, so without the re-grab the next direction would
			# fire from wherever the last one landed (a walk by chaos, not a
			# per-node sweep).
			node.grab_focus()
			await tree.process_frame
			await _tap(harness, direction)
			steps += 1
			var focus := _focus_owner(harness)
			if focus == null:
				lost += 1
				node.grab_focus()
				await tree.process_frame
				continue
			if not reached.has(focus.get_instance_id()):
				reached.append(focus.get_instance_id())
				queue.append(focus)
	return [reached, lost, steps]


func _ids_of(nodes: Array) -> Array[int]:
	var ids: Array[int] = []
	for node in nodes:
		ids.append((node as Control).get_instance_id())
	return ids


## Human label for a focusable (diagnostics in failure messages).
func _focus_label(node: Control) -> String:
	var id := String(node.get_meta(&"spread_card_id", ""))
	if not id.is_empty():
		return id
	if node.has_meta(&"focus_id"):
		return String(node.get_meta(&"focus_id"))
	if node is Button and (node as Button).action is Dictionary:
		return String((node as Button).action.get("id", ""))
	return String(node.name)


# --- 1. the spread table --------------------------------------------------------------------


func _sweep_spread_table(harness) -> void:
	var host := _test_host(QUIET_SEED)
	# A populated, quiet table: the sensible policy drives ~4h (offers,
	# workers, a building or two) — enough cards to make the walk honest.
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(4.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # freeze the table: no card churn mid-sweep
	var focusables := _slot_focusables(screen)
	harness.check(focusables.size() >= 4,
		"nav/table: the 4h Deck table has >=4 focusables (got %d)" % focusables.size())
	var seed_focus := _focus_owner(harness)
	harness.check(seed_focus != null,
		"nav/table: focus is seeded after mount (a screen must seed itself)")
	var walk: Array = await _walk_focus_graph(harness)
	var reached: Array[int] = walk[0]
	var lost: int = walk[1]
	harness.check(lost == 0,
		"nav/table: focus never lost across %d dpad presses (lost %d)" % [walk[2], lost])
	var missing := 0
	var missed: Array[String] = []
	for node in focusables:
		if not reached.has(node.get_instance_id()):
			missing += 1
			missed.append(_focus_label(node))
	harness.check(missing == 0,
		"nav/table: dpad BFS reached every visible focusable of the active slot (%d of %d reached; unreached: %s)"
		% [focusables.size() - missing, focusables.size(), ", ".join(missed)])
	screen.queue_free()
	await _frames(harness, 3)


# --- 2. the action fan ------------------------------------------------------------------------


## A card whose fan actions keep the card on the table (unit/building
## cards persist through their verbs; an accepted offer does not).
func _persistent_fan_card(screen: SpreadScreen) -> Control:
	var active := screen.get_active_slot() as OrientationSlot
	var fallback: Control = null
	for child in active.get_spread().get_children():
		if not (child is Control):
			continue
		var id := String((child as Control).get_meta(&"spread_card_id", ""))
		if not id.begins_with("unit_") and not id.begins_with("bld_"):
			continue
		for card: Dictionary in screen._view["cards"]:
			if String(card["id"]) == id and not CardActions.actions_for(screen.host, card).is_empty():
				return child
		if fallback == null:
			fallback = child
	return fallback


func _sweep_action_fan(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(4.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # freeze the table: no card churn mid-sweep
	var card := _persistent_fan_card(screen)
	if not harness.check(card != null, "nav/fan: a card with fan actions is on the 4h table"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	card.grab_focus()
	await _frames(harness, 2)
	# A opens the fan off the focused card (the pad primary path).
	var chosen: Array = []
	screen._fan.action_chosen.connect(func(action: Dictionary) -> void: chosen.append(String(action["id"])))
	await _tap(harness, BTN_A)
	await _frames(harness, 2)
	if not harness.check(screen._fan.is_open(), "nav/fan: pad A on a focused card opens the fan"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	var chips := screen._fan.chips()
	harness.check(_focus_owner(harness) is Button, "nav/fan: focus lands on a fan chip after open")
	# The trap: dpad cycles every chip without ever leaving the fan.
	var walk: Array = await _walk_focus_graph(harness)
	var reached: Array[int] = walk[0]
	var missing_chips := 0
	for chip in chips:
		if not reached.has((chip as Control).get_instance_id()):
			missing_chips += 1
	var escaped := 0
	for id in reached:
		var node: Control = instance_from_id(id) as Control
		if node == null or not screen._fan.is_ancestor_of(node):
			escaped += 1
	harness.check(missing_chips == 0 and escaped == 0,
		"nav/fan: the focus trap cycles all %d chips and never leaves the fan (%d unreached, %d escaped)"
		% [chips.size(), missing_chips, escaped])
	# A submits the focused chip (the pad fallback), the fan folds, focus
	# returns to the card.
	var chip_focus := _focus_owner(harness)
	if chip_focus != null:
		chip_focus.grab_focus()
		await _frames(harness, 2)
	await _tap(harness, BTN_A)
	await _frames(harness, 2)
	harness.check(chosen.size() == 1,
		"nav/fan: pad A submits the focused chip exactly once (got %d)" % chosen.size())
	harness.check(not screen._fan.is_open(), "nav/fan: the fan folds after the pad submit")
	harness.check(_focus_owner(harness) == card,
		"nav/fan: focus returns to the card that opened the fan")
	# B folds it too.
	card.grab_focus()
	await _frames(harness, 2)
	await _tap(harness, BTN_A)
	await _frames(harness, 2)
	if screen._fan.is_open():
		await _tap(harness, BTN_B)
		await _frames(harness, 2)
		harness.check(not screen._fan.is_open(), "nav/fan: pad B folds the open fan")
		harness.check(_focus_owner(harness) == card,
			"nav/fan: pad B returns focus to the card")
	screen.queue_free()
	await _frames(harness, 3)


# --- 3. the assault (odds, vignette, outcome) -------------------------------------------------


## One host holding `count` fully-geared PROMOTED t1 knights — the
## deterministic floor-state army (the test_assault_vignette fixture
## shape, assert-free for the acceptance harness).
func _knight_host(run_seed: int, count: int) -> GameHost:
	var host := _test_host(run_seed)
	var knights: Array[int] = []
	while knights.size() < count:
		while host.units().pending_offers() == 0:
			host.fast_forward(30)
		var uid := host.units().offer_ids()[0]
		host.submit(&"recruit_accept", &"", uid)
		host.fast_forward(10)
		var idle: Array = host.units().idle_units(host.units().base_unit_id())
		host.submit(&"assign_role", &"militia", idle[0])
		host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
		var militia: Array = host.units().idle_units(&"militia")
		host.submit(&"start_training", &"trainee", militia[0])
		host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
		var trainee: Array = host.units().idle_units(&"trainee")
		host.submit(&"start_training", &"knight", trainee[0])
		host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
		knights.append(trainee[0])
	host.engine.set_resource(&"food", 500)
	host.engine.set_resource(&"timber", 500)
	host.engine.set_resource(&"iron", 500)
	for uid in knights:
		for slot in host.units().missing_gear_slots(uid):
			host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
	host.fast_forward(5)
	for uid in knights:
		if host.units().is_awaiting_promotion(uid) and host.units().missing_gear_slots(uid).is_empty():
			host.submit(&"promote", &"", uid)
	host.fast_forward(5)
	return host


func _sweep_assault(harness) -> void:
	# 3a. The odds table BELOW the floor (the honest early-Deck state):
	# COMMIT is focusable-but-struck, RETREAT free.
	var host := _test_host(QUIET_SEED)
	host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # freeze the table: the odds walk races nothing
	var first_card := _focus_owner(harness)
	if first_card == null:
		var active := screen.get_active_slot() as OrientationSlot
		for focusable in active.focusables():
			first_card = focusable
			break
	first_card.grab_focus()
	await _frames(harness, 2)
	screen.open_assault()
	await _frames(harness, 3)
	if not harness.check(screen._assault.is_open(), "nav/assault: the odds table opens from the table"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	var commit: Control = null
	for chip in screen._assault.stage().chips():
		if chip is Button and String((chip as Button).action.get("id", "")) == "commit":
			commit = chip
			break
	var seeded := _focus_owner(harness)
	harness.check(seeded is Button and String((seeded as Button).action.get("id", "")) == "retreat",
		"nav/assault: focus seeds on RETREAT when the odds open (the safe verb)")
	# dpad onto the struck COMMIT through the cyclic trap; pad A: the
	# printed refusal, screen stays open (a refused petition never arms).
	for direction in DIRECTIONS:
		if _focus_owner(harness) == commit:
			break
		await _tap(harness, direction)
	harness.check(_focus_owner(harness) == commit, "nav/assault: dpad reaches the struck COMMIT")
	await _tap(harness, BTN_A)
	await _frames(harness, 3)
	harness.check(screen._assault.is_open() and screen._assault.state == screen._assault.State.ODDS,
		"nav/assault: pad A on a below-floor COMMIT prints the refusal and stays on odds")
	# dpad to RETREAT; pad A retreats (the pad fallback). (The finished
	# collector is an ARRAY — GDScript lambdas capture locals by value.)
	var retreated: Array = []
	screen._assault.finished.connect(func(_outcome: StringName, _script: Dictionary) -> void:
		retreated.append(String(_outcome)))
	for direction in DIRECTIONS:
		await _tap(harness, direction)
		var focus := _focus_owner(harness)
		if focus is Button and String((focus as Button).action.get("id", "")) == "retreat":
			break
	await _tap(harness, BTN_A)
	await _frames(harness, 3)
	harness.check(retreated.size() == 1 and not screen._assault.is_open(),
		"nav/assault: pad A on the focused RETREAT chip retreats at no cost (%s)" % str(retreated))
	harness.check(_focus_owner(harness) != null,
		"nav/assault: focus survives the retreat (returned to the opener)")
	screen.queue_free()
	await _frames(harness, 3)

	# 3b. The full pad storm on a floor-met army: A arms, A casts, A skips
	# the vignette, A closes the outcome — no keyboard, no touch, no seams.
	var storm_host := _knight_host(WIN_SEED, 2)
	var storm_screen := await _mounted_screen(harness, storm_host)
	# NOT frozen: the commit's one-tick drain runs through advance_ticks,
	# which respects the pacing gate (a frozen host never resolves).
	var outcomes: Array = []
	storm_screen._assault.finished.connect(func(outcome: StringName, _script: Dictionary) -> void:
		outcomes.append(String(outcome)))
	storm_screen.open_assault()
	await _frames(harness, 3)
	var storm_seeded := _focus_owner(harness)
	harness.check(storm_seeded is Button and String((storm_seeded as Button).action.get("id", "")) == "retreat",
		"nav/assault: the floor-met odds table seeds focus on RETREAT too")
	# dpad onto COMMIT; the first A ARMS (the die is not yet cast), the
	# second CASTS — the two-step raise by pad alone.
	var on_commit := false
	for direction in DIRECTIONS:
		var focus := _focus_owner(harness)
		if focus is Button and String((focus as Button).action.get("id", "")) == "commit":
			on_commit = true
			break
		await _tap(harness, direction)
	harness.check(on_commit, "nav/assault: dpad reaches COMMIT on the floor-met table")
	await _tap(harness, BTN_A)  # ARM — the pad path
	await _frames(harness, 3)
	var armed_focus := _focus_owner(harness)
	harness.check(storm_screen._assault.state == storm_screen._assault.State.ODDS
			and armed_focus is Button and String((armed_focus as Button).action.get("id", "")) == "commit",
		"nav/assault: the first pad A arms the die — still odds, focus on the armed verb")
	await _tap(harness, BTN_A)  # CAST — the second pad press
	for i in 60:
		await _frames(harness, 1)
		if storm_screen._assault.state != storm_screen._assault.State.ODDS:
			break
	harness.check(storm_screen._assault.state == storm_screen._assault.State.VIGNETTE,
		"nav/assault: the second pad A casts the die (state %d)" % storm_screen._assault.state)
	await _tap(harness, BTN_A)  # one input skips the vignette
	for i in 200:
		await _frames(harness, 1)
		if storm_screen._assault.state == storm_screen._assault.State.OUTCOME:
			break
	harness.check(storm_screen._assault.state == storm_screen._assault.State.OUTCOME,
		"nav/assault: pad A skips the vignette to the outcome")
	for i in 30:
		await _frames(harness, 1)
		var focus := _focus_owner(harness)
		if focus is Button and (focus as Button).action.get("id", "") == "close":
			break
	await _tap(harness, BTN_A)  # the close chip
	await _frames(harness, 3)
	harness.check(outcomes.size() == 1 and outcomes[0] == "win",
		"nav/assault: pad A closes the outcome — a full pad-only storm won and handed off (%s)"
		% str(outcomes))
	storm_screen.queue_free()
	await _frames(harness, 3)


# --- 4. the chronicle ledger -------------------------------------------------------------------


func _synthetic_ring(host: GameHost, count: int) -> void:
	## The test_chronicle_screen fixture shape: a varied 50-hand ring in
	## the META domain's own record.
	var firsts: Array = Inks.pack().identity.leader_first_names
	var epithets: Array = Inks.pack().identity.leader_epithets
	var regimes := Inks.regime_ids()
	host.meta.chronicle.clear()
	host.meta.runs_recorded = 0
	host.meta.legacy_points = 0
	var outcomes := ["victory", "defeat", "aborted"]
	for i in count:
		var entry := {
			"run": i + 1,
			"leader": "%s %s" % [firsts[i % firsts.size()], epithets[(i * 5) % epithets.size()]],
			"tags": [&"scheming", &"pious"],
			"trait": "haggles with geese",
			"regime": String(regimes[i % regimes.size()]),
			"outcome": outcomes[i % 3],
			"duration_ticks": (i % 90 + 2) * SimEngine.TICKS_PER_SIM_HOUR,
			"army_power": i * 3,
			"army": {"knight": i % 4, "archer": (i + 1) % 3},
			"score": 40 + i,
		}
		host.meta.chronicle.append(entry)
		host.meta.runs_recorded += 1
		host.meta.legacy_points += int(entry["score"])


func _sweep_chronicle(harness) -> void:
	var host := _test_host(QUIET_SEED)
	host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
	_synthetic_ring(host, 50)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # freeze the table: the ledger walk races nothing
	# The header chip (focus seeded directly here; section 1's BFS already
	# proved the dpad reaches it from the cards). The verbs row nests the
	# chips (finishing refinement #2) — the lookup is by focus id.
	var chip: Control = SpreadScreen.header_chip(
		screen.get_active_slot() as OrientationSlot, "chronicle_chip")
	if not harness.check(chip != null, "nav/chronicle: the header chronicle chip exists"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	chip.grab_focus()
	await _frames(harness, 2)
	await _tap(harness, BTN_A)  # pad A opens the ledger (the spread's BaseButton fallback)
	await _frames(harness, 6)
	if not harness.check(screen._chronicle.is_open(), "nav/chronicle: pad A on the header chip opens the ledger"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	# Focus seeds the first entry (the sheet's settle awaits real layout).
	var seeded := false
	for i in 60:
		await _frames(harness, 1)
		var focus := _focus_owner(harness)
		if focus != null and screen._chronicle.sheet().is_ancestor_of(focus):
			seeded = true
			break
	harness.check(seeded, "nav/chronicle: focus seeds inside the ledger after open")
	# dpad walks the page's entries + chips; every sheet focusable reached.
	if OS.get_environment("CS_NAV_TRACE") == "1":
		for node in screen._chronicle.sheet().focusables():
			if (node as Control).is_visible_in_tree():
				print("[trace] sheet focusable %s rc=%s L=%s R=%s T=%s B=%s"
					% [_focus_label(node), str((node as Control).get_global_rect().position.round()),
					str((node as Control).focus_neighbor_left), str((node as Control).focus_neighbor_right),
					str((node as Control).focus_neighbor_top), str((node as Control).focus_neighbor_bottom)])
	var walk: Array = await _walk_focus_graph(harness)
	var reached: Array[int] = walk[0]
	var sheet_focusables: Array[Control] = []
	for node in screen._chronicle.sheet().focusables():
		if node.is_visible_in_tree():
			sheet_focusables.append(node)
	var missing := 0
	var missed: Array[String] = []
	for node in sheet_focusables:
		if not reached.has(node.get_instance_id()):
			missing += 1
			missed.append(_focus_label(node))
	harness.check(missing == 0,
		"nav/chronicle: dpad reaches every focusable on the newest page (%d of %d; unreached: %s)"
		% [sheet_focusables.size() - missing, sheet_focusables.size(), ", ".join(missed)])
	# A on the OLDER chip turns the page (the chronicle's own pad fallback).
	var older: Control = null
	for focusable in sheet_focusables:
		if focusable is Button and String((focusable as Button).action.get("id", "")) == "older":
			older = focusable
			break
	if older != null:
		older.grab_focus()
		await _frames(harness, 2)
		await _tap(harness, BTN_A)
		await _frames(harness, 8)
		harness.check(screen._chronicle.page == 1 and int(screen._chronicle.stats[&"page_turns"]) == 1,
			"nav/chronicle: pad A on the OLDER chip turns to page 2 of the 50-hand ring")
	# B closes from anywhere; focus returns to the chip that opened it.
	await _tap(harness, BTN_B)
	await _frames(harness, 3)
	harness.check(not screen._chronicle.is_open(), "nav/chronicle: pad B closes the ledger")
	harness.check(_focus_owner(harness) == chip,
		"nav/chronicle: focus returns to the header chip after the close")
	screen.queue_free()
	await _frames(harness, 3)


# --- 5. the leader intro ------------------------------------------------------------------------


func _sweep_intro(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var screen := await _mounted_screen(harness, host, true)
	host.driving = false  # freeze: the reveal owns the entry, nothing ticks
	var opened := false
	for i in 60:
		await _frames(harness, 1)
		if screen._intro.is_open():
			opened = true
			break
	if not harness.check(opened, "nav/intro: the boot reveal opens on the fresh first deal"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	var chip_focus := false
	for i in 30:
		await _frames(harness, 1)
		if _focus_owner(harness) != null and screen._intro.is_ancestor_of(_focus_owner(harness)):
			chip_focus = true
			break
	harness.check(chip_focus, "nav/intro: focus lands on the one-gesture chip")
	await _tap(harness, BTN_A)  # the one gesture, by pad
	for i in 200:
		await _frames(harness, 1)
		if not screen._intro.is_open():
			break
	harness.check(not screen._intro.is_open(), "nav/intro: pad A unfolds the reveal")
	harness.check(_focus_owner(harness) != null,
		"nav/intro: the table takes focus back after the unfold (no stranded focus)")
	screen.queue_free()
	await _frames(harness, 3)


# --- 6. the suspicion choice card -----------------------------------------------------------------


func _sweep_suspicion_choice(harness) -> void:
	var host := _test_host(QUIET_SEED)
	host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # frozen: the seam + fast_forward arm everything
	# The documented meter seam arms the telegraph (the capture-drive
	# pattern): the choice card slides onto the edge, live. The world
	# FREEZES once the card is up (the pacing gate) — the sweep walks the
	# paper, it does not race the 4h countdown.
	host.suspicion().set_suspicion(78)
	host.fast_forward(2)
	var opened := false
	for i in 30:
		await _frames(harness, 1)
		if screen._suspicion.choice_is_open():
			opened = true
			break
	if not harness.check(opened, "nav/suspicion: the telegraph choice card opens live"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	await _frames(harness, 3)
	# Focus seeds on the choice card's chips; dpad walks them all.
	var walk: Array = await _walk_focus_graph(harness)
	var reached: Array[int] = walk[0]
	var choice_focusables := _visible_focusables_under(screen._suspicion)
	var missing := 0
	var missed: Array[String] = []
	for node in choice_focusables:
		if not reached.has(node.get_instance_id()):
			missing += 1
			missed.append(_focus_label(node))
	harness.check(missing == 0,
		"nav/suspicion: dpad reaches every choice-card chip (%d of %d; unreached: %s)"
		% [choice_focusables.size() - missing, choice_focusables.size(), ", ".join(missed)])
	# B folds the card; focus returns to the table's first card.
	await _tap(harness, BTN_B)
	await _frames(harness, 3)
	host.driving = true
	harness.check(not screen._suspicion.choice_is_open(),
		"nav/suspicion: pad B folds the choice card")
	harness.check(_focus_owner(harness) != null,
		"nav/suspicion: focus survives the fold (back on the table)")
	screen.queue_free()
	await _frames(harness, 3)


# --- 7. the while-you-were-away print --------------------------------------------------------------


func _sweep_catch_up_print(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(5.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # the boundary drives everything; wall pacing stays out
	var active := screen.get_active_slot() as OrientationSlot
	var a_card: Control = null
	for child in active.get_spread().get_children():
		if child is Control and child.has_meta(&"spread_card_id"):
			a_card = child
			break
	a_card.grab_focus()
	await _frames(harness, 2)
	# The mid-session boundary: 9h37m away -> the capped window resolves
	# on the LIVE table and the print lands as passive paper.
	host.background(T0)
	host.foreground(T0 + 9 * 3600 + 37 * 60)
	var printed := false
	for i in 60:
		await _frames(harness, 1)
		if int(screen.stats[&"catch_up_prints"]) > 0:
			printed = true
			break
	harness.check(printed, "nav/catch-up: the while-you-were-away print lands on the live table")
	harness.check(_focus_owner(harness) == a_card,
		"nav/catch-up: the print is passive paper — the table keeps focus through it")
	harness.check(screen._suspicion.quote_rows().size() >= 1,
		"nav/catch-up: the print carries its rows")
	screen.queue_free()
	await _frames(harness, 3)
