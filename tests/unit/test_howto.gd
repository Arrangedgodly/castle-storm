## Unit tests for the how-to pamphlet (the tutorial's pamphlet half) —
## Daredevil + Prof X lane.
##
## Pins: the pamphlet renders ALL its sections as content (the goal
## sentence, the table, the EDGE LEGEND with three LIVE mini card-frames
## in the solid/dashed/struck states, the stores, the Watchful Eye with
## the real thresholds, legacy + escalation); the entries are wired (the
## title card's chip, the spread header's How-to-Play chip, and the
## FIRST-FRESH-BOOT OFFER — offered once, declinable ("I know this
## table"), persisted); input parity x3 (chip press / focused primary /
## back) and the papers' mutual exclusion.
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const HowToScreenScript := preload("res://ui/screens/howto/howto_screen.gd")

var _dir_seq := 0


func after() -> void:
	MotionProfile.forced = -1
	_erase_dir("user://cs_howto_tests")
	get_window().size = Vector2i(720, 720)


# --- the pamphlet's content -----------------------------------------------------------------


## The view model carries every section, all lines from the copy deck:
## the goal sentence first, the table, the THREE edge rows in the three
## line forms with their captions, the stores, the Eye (the real
## thresholds — 35 warn / 70 crackdown / 100 crush), the long game.
func test_the_view_carries_every_section_in_voice() -> void:
	var view := HowToScreenScript.view_for()
	# THE GOAL, one sentence, ending in the storm.
	assert_bool(String(view["goal_line"]).begins_with("Grow the conspiracy")).is_true()
	assert_bool(String(view["goal_line"]).contains("storm the castle")).is_true()
	# THE TABLE: cards are people/buildings; the player's three verbs.
	var table: Array = view["table_lines"]
	assert_int(table.size()).is_equal(2)
	assert_bool(String(table[0]).contains("card")).is_true()
	assert_bool(String(table[1]).to_lower().contains("recruits")).is_true()
	# THE EDGES: three live examples, one per line form, captions keyed.
	var edges: Array = view["edge_rows"]
	assert_int(edges.size()).is_equal(3)
	assert_int(int(edges[0]["form"])).is_equal(Inks.EdgeForm.SOLID)
	assert_int(int(edges[1]["form"])).is_equal(Inks.EdgeForm.DASHED)
	assert_int(int(edges[2]["form"])).is_equal(Inks.EdgeForm.STRUCK)
	assert_bool(String(edges[0]["caption"]).begins_with("Solid")).is_true()
	assert_bool(String(edges[1]["caption"]).begins_with("Dashed")).is_true()
	assert_bool(String(edges[2]["caption"]).begins_with("Struck")).is_true()
	# THE WATCHFUL EYE: the sim's own thresholds, never invented ones.
	var eye := String(view["eye_line"])
	assert_bool(eye.contains("35")).is_true()
	assert_bool(eye.contains("70")).is_true()
	assert_bool(eye.contains("100")).is_true()
	assert_bool(eye.contains("legacy")).is_true()
	# THE LONG GAME: legacy + escalation, one line each.
	var long_lines: Array = view["long_lines"]
	assert_int(long_lines.size()).is_equal(2)
	assert_bool(String(long_lines[0]).contains("Legacy")).is_true()
	assert_bool(String(long_lines[1]).contains("veterans")).is_true()
	# The offer's line exists (the first-boot paper's own voice).
	assert_bool(String(view["offer_line"]).length() > 0).is_true()


## The mounted sheet renders the whole pamphlet: three REAL card frames
## in the three edge states (the line-form primer taught with pictures),
## six walkable section headings, the goal under the signature's double
## rule, and a deterministic render (same view => same hash).
func test_the_sheet_renders_sections_and_three_live_edge_frames() -> void:
	var screen: HowToScreenScript = HowToScreenScript.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	screen.open(null)  # no host: the neutral ground (the front door's case)
	await get_tree().process_frame
	var sheet := screen.sheet()
	assert_bool(String(sheet._title_label.text) == "HOW TO PLAY").is_true()
	# THE WALK: six section headings (goal / table / edges / stores /
	# eye / long game), all bound, then the back verb.
	var headings := sheet.headings()
	assert_int(headings.size()).is_equal(6)
	assert_bool(String(headings[0].text) == "THE GOAL").is_true()
	assert_bool(String(headings[2].text) == "THE EDGES").is_true()
	assert_bool(String(headings[5].text) == "THE LONG GAME").is_true()
	# THE LIVE EXAMPLES: three card frames, edge forms SOLID/DASHED/
	# STRUCK, each beside its caption — the primer for line-form states.
	var rows := sheet.legend_rows()
	assert_int(rows.size()).is_equal(3)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var frame: Control = row["frame"]
		assert_bool(frame is Control).is_true()
		assert_int(int(frame.get("edge_form"))).is_equal(int(Inks.EdgeForm.SOLID) \
			if i == 0 else (int(Inks.EdgeForm.DASHED) if i == 1 else int(Inks.EdgeForm.STRUCK)))
		assert_bool((row["caption"] as Label).text.length() > 0).is_true()
	# The goal body carries the goal sentence; the scroll holds it.
	var goal_body: Label = (sheet._sections[0]["bodies"] as Array)[0]
	assert_bool(goal_body.text.begins_with("Grow the conspiracy")).is_true()
	# Deterministic render: same view => same hash.
	var first_hash := sheet.snapshot_hash()
	sheet.bind(HowToScreenScript.view_for())
	assert_int(sheet.snapshot_hash()).is_equal(first_hash)
	# The back verb closes (the sheet's own signal).
	var closed := [false]
	screen.closed.connect(func() -> void: closed[0] = true)
	sheet._back_chip.pressed.emit()
	assert_bool(closed[0]).is_true()
	await _free(screen)


## Input parity x3 on the offer: touch (chip press), keyboard/pad (the
## focused primary — the spread fallback shape), and back (Esc = decline
## on the offer). The offer seeds the READ verb.
func test_the_offer_answers_three_ways_and_once() -> void:
	var root := _root()
	var host := GameHost.new(20261021, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	var screen: SpreadScreen = await _mounted(host, true)
	# The boot reveal opens; its fold offers the pamphlet (once).
	for i in 240:
		await get_tree().process_frame
		if screen._intro.is_open():
			break
	assert_bool(screen._intro.is_open()).is_true()
	screen._intro.unfold()
	for i in 300:
		await get_tree().process_frame
		if not screen._intro.is_open():
			break
	for i in 60:
		await get_tree().process_frame
		if screen._howto.is_open():
			break
	assert_bool(screen._howto.is_open()).is_true()
	assert_int(int(screen._howto.state)).is_equal(int(HowToScreenScript.State.OFFER))
	assert_int(int(screen.stats[&"howto_offers"])).is_equal(1)
	# Decline through the real verb: the paper folds, the flag persists.
	var declined := [false]
	screen._howto.offer_answered.connect(func(p_read: bool) -> void:
		if not p_read:
			declined[0] = true)
	screen._howto.offer_panel().decline_chip().pressed.emit()
	await get_tree().process_frame
	assert_bool(declined[0]).is_true()
	assert_bool(screen._howto.is_open()).is_false()
	assert_bool(host.meta.first_session_flag(&"howto")).is_true()
	var disk := _read_meta_json(host)
	assert_bool(bool((((disk.get("payload", {}) as Dictionary)
		.get("first_session", {}) as Dictionary)
		.get("howto", false)))).is_true()
	await _free_screen(screen)
	# A SECOND fresh boot on the same install: the reveal folds, and the
	# offer never comes back (answered once, persisted).
	var returning := GameHost.new(20261022, root)
	returning.autosave_interval_ticks = 0
	assert_bool(returning.boot(0)).is_true()
	var screen2: SpreadScreen = await _mounted(returning, true)
	for i in 240:
		await get_tree().process_frame
		if screen2._intro.is_open():
			break
	if screen2._intro.is_open():
		screen2._intro.unfold()
		for i in 300:
			await get_tree().process_frame
			if not screen2._intro.is_open():
				break
	for i in 60:
		await get_tree().process_frame
	assert_bool(screen2._howto.is_open()).is_false()
	assert_int(int(screen2.stats[&"howto_offers"])).is_equal(0)
	await _free_screen(screen2)


# --- the entries -----------------------------------------------------------------------------


## The header verbs row carries the How-to-Play chip on BOTH slots; the
## verb opens the pamphlet over the veiled table; closing returns focus
## to the chip (the affordance that opened it); the table papers are
## mutually exclusive (opening the chronicle folds the pamphlet).
func test_the_header_chip_opens_the_pamphlet_and_papers_stay_exclusive() -> void:
	var host := _host(20261023)
	var screen: SpreadScreen = await _mounted(host, true)
	var active := screen.get_active_slot() as OrientationSlot
	var chip := screen.header_chip(active, "howto_chip")
	assert_that(chip).is_not_null()
	var other := screen.header_chip(
		screen.get_portrait_slot() if active == screen.get_landscape_slot()
		else screen.get_landscape_slot(), "howto_chip")
	assert_that(other).is_not_null()
	# Open through the verb: the pamphlet, over the table, focus on the
	# sheet's walk (the seeded heading).
	chip.pressed.emit()
	await get_tree().process_frame
	assert_int(int(screen.stats[&"howtos_opened"])).is_equal(1)
	assert_bool(screen._howto.is_open()).is_true()
	assert_int(int(screen._howto.state)).is_equal(int(HowToScreenScript.State.OPEN))
	# The chip answered the first-boot offer's receipt too (a read is an
	# answer) — but the OFFER itself never fired here (the intro is up;
	# answering by chip is the same once-only flag).
	assert_bool(host.meta.first_session_flag(&"howto")).is_true()
	# Papers never stack: the chronicle verb folds the pamphlet.
	screen.open_chronicle()
	await get_tree().process_frame
	assert_bool(screen._howto.is_open()).is_false()
	assert_bool(screen._chronicle.is_open()).is_true()
	screen._chronicle.close()
	await get_tree().process_frame
	# Opening the pamphlet folds the ledger back (one paper at a time).
	screen.open_howto()
	await get_tree().process_frame
	assert_bool(screen._howto.is_open()).is_true()
	# Back (the keyboard/pad verb) closes; focus returns to the chip.
	screen._howto.close()
	await get_tree().process_frame
	assert_bool(screen.get_viewport().gui_get_focus_owner() == chip).is_true()
	await _free_screen(screen)


# --- helpers ---------------------------------------------------------------------------------


func _host(run_seed: int) -> GameHost:
	var root := _root()
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _root() -> String:
	_dir_seq += 1
	var root := "user://cs_howto_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	return root


func _mounted(host: GameHost, intro_on := true) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	for i in 4:
		await get_tree().process_frame
	return screen


func _free_screen(screen: SpreadScreen) -> void:
	screen.queue_free()
	await get_tree().process_frame


func _free(screen: Control) -> void:
	screen.queue_free()
	await get_tree().process_frame


func _read_meta_json(host: GameHost) -> Dictionary:
	var path := host.save_manager.meta_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var text := file.get_as_text()
	file.close()
	if parser.parse(text) != OK:
		return {}
	return parser.data


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
