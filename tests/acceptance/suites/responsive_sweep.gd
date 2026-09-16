## Responsive layout sweep — T-QA-05 (Hawkeye lane, Daredevil consulted).
##
## THE consolidated four-size pass of the town-hall criterion "Layouts
## usable at 1280x800 (Deck), 1920x1080, and common phone portrait sizes
## (responsive, one codebase)": every screen surface MOUNTED at each of
## the four canonical test sizes, asserting
##
##   1. NO CLIPPING — every visible Control's global rect fits the
##      viewport's design rect (the test_responsive_layout standard,
##      swept over every paper layer: the quiet table, the armed
##      telegraph choice card, an open blockquote, the assault odds
##      table, the chronicle ledger, the leader intro);
##   2. FOCUS CHAINS HOLD — focus is seeded after every mount, swap, and
##      surface open/close; a full dpad BFS reaches every visible
##      focusable of the active slot at BOTH extremes (720x1280 phone
##      portrait and 1280x800 Deck landscape — the topology pair), and
##      no surface ever strands focus;
##   3. THE TYPE-SCALE SPOT — the same quiet table at 1.3x font scale
##      (the top of the supported range) still clips nothing at the Deck
##      window.
##
## One screen instance is RESIZED across the four sizes (the live swap is
## itself the criterion: the router swaps topology, surfaces re-place,
## focus restores). The piecemeal pins stay where they are (the lab scene
## in test_responsive_layout, the assault's own 4-size pin in
## test_assault_vignette); this suite is the whole-screen consolidation.
extends RefCounted

const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

const TEST_SIZES: Array[Vector2i] = [
	Vector2i(720, 1280),  # phone portrait
	Vector2i(1280, 800),  # Steam Deck (landscape)
	Vector2i(1920, 1080),  # desktop
	Vector2i(800, 1280),  # tablet portrait
]
const EXPECTED_PORTRAIT := [true, false, false, true]

const WATCH_SCALE := 20.0
const QUIET_SEED := 20261103
const T0 := 1_800_000_000

const DPAD: Array[int] = [13, 14, 11, 12]  # left, right, up, down

var _dir_seq := 0


func suite_name() -> String:
	return "responsive_sweep"


func run(harness) -> void:
	Engine.time_scale = WATCH_SCALE
	await _sweep_the_screen(harness)
	await _sweep_type_scale_spot(harness)
	(harness as Node).get_tree().root.size = Vector2i(720, 720)
	Engine.time_scale = 1.0
	_erase_dir("user://cs_responsive")


# --- the four-size consolidated sweep ------------------------------------------------------


func _sweep_the_screen(harness) -> void:
	var host := _populated_host(QUIET_SEED, 8.0)
	var screen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	harness.mount(screen)
	await _frames(harness, 10)

	for i in TEST_SIZES.size():
		var size: Vector2i = TEST_SIZES[i]
		var want_portrait: bool = EXPECTED_PORTRAIT[i]
		await _settle(harness, screen, size, want_portrait)
		var tag := "%dx%d" % [size.x, size.y]

		# Orientation landed.
		harness.check(screen.get_router().is_portrait() == want_portrait,
			"responsive/%s: the router picked %s" % [tag, "portrait" if want_portrait else "landscape"])

		# 1. The QUIET TABLE — no clipping, focus seeded, grips hold.
		await _check_surface(harness, screen, "table", tag)

		# 2. The ARMED TELEGRAPH (choice card on the edge), placed by the
		# layer's own open seam at THIS geometry (the meter seam arms once;
		# this recomposes the same card per size, deterministically).
		var choice_model: Dictionary = SuspicionEvents.choice_card_for(host, {
			"seq": 1, "tick": 10, "type": &"suspicion_telegraph",
			"subject": 0, "value": 100, "value2": 0})
		screen._suspicion.open_choice(choice_model, screen._design_bounds().size)
		await _frames(harness, 4)
		await _check_surface(harness, screen, "choice", tag)
		screen._suspicion.fold_choice()
		screen._focus_first_card()  # the input path's restore, mirrored
		await _frames(harness, 3)

		# 3. An open BLOCKQUOTE (the while-you-were-away print shape).
		var rows: Array[Dictionary] = [
			{"class": Inks.LineClass.PLAIN, "text": "You were away 8h (the watch capped the rest)."},
			{"class": Inks.LineClass.PLAIN, "text": "+92 food, +44 timber, +31 iron."},
			{"class": Inks.LineClass.STRIKE, "text": "A strike landed: 2 recruits scattered."},
		]
		screen._suspicion.open_quote_rows(rows,
			screen._design_bounds().size, screen._quote_floor(), 0.0)
		await _frames(harness, 4)
		await _check_surface(harness, screen, "quote", tag)
		screen._suspicion.fold_quote()
		await _frames(harness, 3)

		# 4. The ASSAULT ODDS TABLE.
		if OS.get_environment("CS_RESP_TRACE") == "1":
			print("[trace] %s post-quote focus=%s choice_open=%s" % [tag, _focus(harness), screen._suspicion.choice_is_open()])
		screen.open_assault()
		await _frames(harness, 5)
		if OS.get_environment("CS_RESP_TRACE") == "1":
			print("[trace] %s pre-open focus=%s portrait=%s" % [tag, _focus(harness), screen.get_router().is_portrait()])
			for chip in screen._assault.stage().chips():
				print("[trace] %s chip %s fm=%s vis=%s rect=%s" % [tag, String(chip.action.get("id","?")), chip.focus_mode, chip.is_visible_in_tree(), chip.get_global_rect()])
			for j in 8:
				await _frame(harness)
				print("[trace] %s assault frame %d focus=%s open=%s state=%s" % [tag, j, _focus(harness), screen._assault.is_open(), screen._assault.state])
		await _check_surface(harness, screen, "assault", tag, screen._assault)
		screen._assault.close()
		await _frames(harness, 4)

		# 5. THE CHRONICLE LEDGER (a populated ring).
		screen.open_chronicle()
		await _frames(harness, 10)
		await _check_surface(harness, screen, "chronicle", tag, screen._chronicle)
		screen._chronicle.close()
		await _frames(harness, 4)

		host.driving = false

	# 6. The LEADER INTRO at the PORTRAIT topology (fresh deal: the reveal
	# is the first thing a player sees; the landscape reveal is walked by
	# the parity suite's intro legs, and both orientations' reveal math is
	# pinned in test_intro_reveal).
	for i in [0]:
		var size: Vector2i = TEST_SIZES[i]
		var tag := "%dx%d" % [size.x, size.y]
		var fresh := _test_host(QUIET_SEED + i)
		var intro_screen = SPREAD_SCENE.instantiate()
		intro_screen.host = fresh
		intro_screen.intro_enabled = true
		harness.mount(intro_screen)
		await _settle(harness, intro_screen, size, EXPECTED_PORTRAIT[i])
		fresh.driving = false
		var opened := false
		for j in 60:
			await _frame(harness)
			if intro_screen._intro.is_open():
				opened = true
				break
		if harness.check(opened, "responsive/intro-%s: the boot reveal opens" % tag):
			await _frames(harness, 4)
			await _check_surface(harness, intro_screen, "intro", tag, intro_screen._intro)
			harness.check(_focus(harness) != null,
				"responsive/intro-%s: the one-gesture chip holds focus" % tag)
		intro_screen.queue_free()
		await _frames(harness, 3)

	# 7. FOCUS-CHAIN BFS at the PHONE-PORTRAIT topology (re-mounted quiet
	# table): deck_nav_sweep.gd already BFS-walks the Deck landscape
	# window — this is the other half of the pair, the slot deck_nav never
	# walks. One BFS, both topologies covered between the two suites.
	for i in [0]:
		var size: Vector2i = TEST_SIZES[i]
		var tag := "%dx%d" % [size.x, size.y]
		var bfs_host := _populated_host(QUIET_SEED + 40 + i, 8.0)
		var bfs_screen = SPREAD_SCENE.instantiate()
		bfs_screen.host = bfs_host
		bfs_screen.intro_enabled = false
		harness.mount(bfs_screen)
		await _settle(harness, bfs_screen, size, EXPECTED_PORTRAIT[i])
		bfs_host.driving = false
		await _frames(harness, 4)
		var focusables := _slot_focusables(bfs_screen)
		harness.check(focusables.size() >= 4,
			"responsive/bfs-%s: the 8h table has >=4 focusables (got %d)" % [tag, focusables.size()])
		harness.check(_focus(harness) != null,
			"responsive/bfs-%s: focus is seeded after the resize" % tag)
		var walk: Array = await _walk_focus_graph(harness)
		harness.check(int(walk[1]) == 0,
			"responsive/bfs-%s: focus never lost across %d dpad presses" % [tag, walk[2]])
		var missing: Array[String] = []
		for node: Control in focusables:
			if not (walk[0] as Array).has(node.get_instance_id()):
				missing.append(_label_of(node))
		harness.check(missing.is_empty(),
			"responsive/bfs-%s: dpad BFS reached every visible focusable (unreached: %s)"
			% [tag, ", ".join(missing)])
		bfs_screen.queue_free()
		await _frames(harness, 3)

	screen.queue_free()
	await _frames(harness, 3)


# --- the type-scale spot ----------------------------------------------------------------------


func _sweep_type_scale_spot(harness) -> void:
	## The top of the supported font range at the Deck window: the table
	## and its paper re-print larger and nothing escapes the viewport (the
	## no-clip property; the audited text budgets are pinned in
	## test_type_scale.gd at real font metrics).
	TypeScale.apply_factor(1.3)
	var host := _populated_host(QUIET_SEED, 8.0)  # the same deterministic 8h shape
	var screen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	harness.mount(screen)
	await _settle(harness, screen, Vector2i(1280, 800), false)
	host.driving = false
	await _frames(harness, 4)
	await _check_surface(harness, screen, "table", "1280x800@1.3x")
	var rows: Array[Dictionary] = [
		{"class": Inks.LineClass.PLAIN, "text": "You were away 8h (the watch capped the rest)."},
		{"class": Inks.LineClass.STRIKE, "text": "A strike landed: 2 recruits scattered."},
	]
	screen._suspicion.open_quote_rows(rows,
		screen._design_bounds().size, screen._quote_floor(), 0.0)
	await _frames(harness, 4)
	await _check_surface(harness, screen, "quote", "1280x800@1.3x")
	screen.queue_free()
	await _frames(harness, 3)
	TypeScale.reset()


# --- helpers ------------------------------------------------------------------------------------


func _check_surface(harness, screen, surface: String, tag: String, scope: Control = null) -> void:
	## No visible control escapes the design rect + focus is never stranded.
	await _frames(harness, 3)
	var design: Vector2 = screen._design_bounds().size
	var root: Control = scope if scope != null else screen
	var offenders := _clipped_controls(root, design)
	harness.check(offenders.is_empty(),
		"responsive/%s-%s: no control escapes the viewport (offenders: %s)"
		% [surface, tag, "; ".join(offenders.slice(0, 4))])
	if scope == null or scope.is_visible_in_tree():
		# Focus seeding is deferred on several surfaces (the assault's
		# chip grab, the sheet's settle): poll briefly, then hold to account.
		var held := false
		for i in 20:
			if _focus(harness) != null:
				held = true
				break
			await _frame(harness)
		harness.check(held,
			"responsive/%s-%s: focus is held (never stranded)" % [surface, tag])


func _settle(harness, screen, size: Vector2i, want_portrait: bool) -> void:
	# The settle frames don't need the world ticking (the pacing gate's
	# per-frame advance is the sweep's own biggest cost — freeze at mount;
	# the surfaces that need ticks call fast_forward directly).
	(harness as Node).get_tree().root.size = size
	for i in 240:
		await _frame(harness)
		if screen.get_router().is_portrait() == want_portrait \
				and screen.get_router().design_size().x > 1.0:
			break
	await _frames(harness, 5)


func _await_open(harness, condition: bool, max_frames: int) -> void:
	for i in max_frames:
		if condition:
			return
		await _frame(harness)


func _frame(harness) -> void:
	await (harness as Node).get_tree().process_frame


func _frames(harness, count: int) -> void:
	for _i in count:
		await _frame(harness)


func _focus(harness) -> Control:
	return (harness as Node).get_viewport().gui_get_focus_owner()


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_responsive/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _populated_host(run_seed: int, hours := 8.0) -> GameHost:
	var host := _test_host(run_seed)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(hours * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	return host


func _slot_focusables(screen) -> Array[Control]:
	var found: Array[Control] = []
	var slot: Control = screen.get_active_slot()
	_collect_focusables(slot, found)
	return found


func _collect_focusables(node: Node, into: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree():
			into.append(control)
	for child in node.get_children():
		_collect_focusables(child, into)


func _label_of(node: Control) -> String:
	var id := String(node.get_meta(&"spread_card_id", ""))
	if not id.is_empty():
		return id
	if node.has_meta(&"focus_id"):
		return String(node.get_meta(&"focus_id"))
	return String(node.name)


## BFS the dpad focus graph from seeded focus (the deck_nav_sweep walker).
func _walk_focus_graph(harness, max_steps := 240) -> Array:
	var tree: SceneTree = (harness as Node).get_tree()
	var reached: Array[int] = []
	var queue: Array[Control] = []
	var start := _focus(harness)
	if start == null:
		return [[], 1, 0]
	reached.append(start.get_instance_id())
	queue.append(start)
	var lost := 0
	var steps := 0
	while not queue.is_empty() and steps < max_steps:
		var node := queue.pop_front() as Control
		for direction in DPAD:
			node.grab_focus()
			await tree.process_frame
			var press := InputEventJoypadButton.new()
			press.device = 0
			press.button_index = direction as JoyButton
			press.pressed = true
			Input.parse_input_event(press)
			await tree.process_frame
			var release := InputEventJoypadButton.new()
			release.device = 0
			release.button_index = direction as JoyButton
			release.pressed = false
			Input.parse_input_event(release)
			await tree.process_frame
			steps += 1
			var focus := _focus(harness)
			if focus == null:
				lost += 1
				node.grab_focus()
				await tree.process_frame
				continue
			if not reached.has(focus.get_instance_id()):
				reached.append(focus.get_instance_id())
				queue.append(focus)
	return [reached, lost, steps]


## Visible Controls whose global rect escapes the design rect (the
## test_responsive_layout standard).
func _clipped_controls(root: Control, design: Vector2) -> Array[String]:
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
		for child in node.get_children():
			if child is Control:
				queue.append(child)
	return offenders


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
