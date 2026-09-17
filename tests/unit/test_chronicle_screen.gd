## Unit tests for the chronicle screen (T-UI-08) — Daredevil lane.
##
## Mirrors ui/screens/chronicle/ + the spread seams. What is pinned:
##   - THE PRESENTER: entry data maps RunMeta.chronicle EXACTLY (every
##     §5.1 field — real hands ended through the REAL verbs: win, loss,
##     abort; the record never reconstructed), outcome seals correct in
##     line form + print mark, duration/army prints, the empty state's
##     required line, the CURRENT-RUN EXCLUSION (the live hand is not
##     chronicle until it ends), pagination math over 50 entries
##     (newest-first, per-page slicing, end clamps), view-hash
##     determinism;
##   - THE SCREEN: the header chip affordance opens the ledger (focus
##     seeds the first entry, >= 48 grips, no popup chrome), back closes
##     and returns focus to the chip, page turns + refusals, input
##     parity x3 (chip tap / pad primary / Enter through the real
##     pipeline), FOCUS-BASED SCROLLING ACTUALLY SCROLLS (a focused
##     entry lands inside the scroll viewport), PAGE TURNS ON
##     BAND-EXCEEDING PAGES SETTLE AT THE TOP with the seeded focused
##     entry ON-SCREEN in both directions (the round-1 verifier FAIL,
##     pinned on the turn path), the longest
##     identity-pool names fit their labels in REAL font metrics (the
##     T-UI-06 lesson: shape content, never clip), the LIVE-HAND line
##     wraps INSIDE its band at the widest pool combination (finishing
##     refinement #6 — the covered-second-line caveat), both orientations
##     unclipped at the four common sizes;
##   - PERSISTENCE: a real save/load round-trip lands the same ring in
##     the screen (chronicle survives in the meta domain).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const ChronicleScreenScript := preload("res://ui/screens/chronicle/chronicle_screen.gd")
const ChronicleSheetScript := preload("res://ui/screens/chronicle/chronicle_sheet.gd")

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
	_erase_dir("user://cs_ui08_tests")


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


func _test_host(run_seed: int = 20261208) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_ui08_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


## End the running hand through the REAL verbs (win with an army-power
## override, loss, or abort), then deal the next hand exactly as the
## host does. Real chronicle entries land in the meta domain.
func _end_hand(host: GameHost, outcome: StringName, hours: int) -> void:
	host.fast_forward(hours * SimEngine.TICKS_PER_SIM_HOUR)
	match outcome:
		&"win":
			host.submit(&"resolve_victory", &"win", 30)
		&"loss":
			host.submit(&"resolve_victory", &"loss", 0)
		_:
			host.submit(&"run_abort")
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)


## Synthesize `count` entries straight into the META domain's own record
## (the fixture seam the screen still reads STRICTLY — like the suspicion
## meter seam): varied outcomes, regimes, durations, army rosters, and
## the identity pools' full breadth (including the LONGEST names — the
## label-budget rows).
func _synthetic_ring(host: GameHost, count: int) -> void:
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


func _mounted_screen(host: GameHost, intro_on := false) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## The seed settles on the page's REAL layout (the round-1 fix's
## contract): poll for the SEEDED STATE — the viewport's focus owner is
## one of the freshly-bound page's own focusables — instead of trusting
## a fixed frame count. `settle_seed` resets the scroll BEFORE the grab,
## so focus landing means the page has settled (post-sort rects, top).
func _await_seeded(chronicle: ChronicleScreenScript) -> void:
	for i in 60:
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner() as Control
		if focus == null:
			continue
		for card in chronicle.sheet().entries():
			if card == focus:
				return
		for chip in chronicle.sheet().chips():
			if chip == focus:
				return


# --- presenter: the record mapped exactly -----------------------------------------------


func test_entry_data_maps_chronicle_fields_exactly() -> void:
	var host := _test_host()
	var expected_leaders: Array[String] = [host.run().leader_name()]
	_end_hand(host, &"win", 10)
	expected_leaders.append(host.run().leader_name())
	_end_hand(host, &"loss", 6)
	expected_leaders.append(host.run().leader_name())
	_end_hand(host, &"abort", 3)
	assert_int(host.meta.chronicle.size()).is_equal(3)
	var view := ChroniclePresenter.view(host, 0, 5)
	var entries: Array = view["entries"]
	assert_int(entries.size()).is_equal(3)
	# Newest first: entry 0 is the LAST hand dealt (the abort), entry 2 the win.
	for i in entries.size():
		var record: Dictionary = host.meta.chronicle[2 - i]
		var entry: Dictionary = entries[i]
		assert_int(int(entry["run"])).is_equal(int(record["run"]))
		assert_str(String(entry["leader"])).is_equal(String(record["leader"]))
		assert_str(String(entry["outcome"])).is_equal(String(record["outcome"]))
		assert_str(String(entry["regime"]["id"])).is_equal(String(record["regime"]))
		assert_int(int(entry["duration_ticks"])).is_equal(int(record["duration_ticks"]))
		assert_int(int(entry["army_power"])).is_equal(int(record["army_power"]))
		assert_int(int(entry["score"])).is_equal(int(record["score"]))
		assert_dict(entry["army"]).is_equal(record["army"])
		# The leader's plate splits the record's own full name (first +
		# epithet), the role plate carries the record's tags + trait.
		assert_str(String(entry["leader_first"]) + " " + String(entry["epithet"])) \
			.is_equal(String(record["leader"]))
		for tag in (record["tags"] as Array):
			assert_bool(String(entry["role_line"]).contains(String(tag).replace("_", " "))).is_true()
		assert_bool(String(entry["role_line"]).contains(String(record["trait"]))).is_true()
		assert_str(String(expected_leaders[2 - i])).is_equal(String(record["leader"]))
	# The regime dressing resolves from the pack against the record's ids.
	for entry: Dictionary in entries:
		var regime_id := StringName(String(entry["regime"]["id"]))
		var regime_def: RegimeDef = null
		for regime: RegimeDef in Inks.pack().regimes:
			if regime.id == regime_id:
				regime_def = regime
				break
		assert_that(regime_def).is_not_null()
		assert_str(String(entry["regime"]["name"])).is_equal(regime_def.display_name)
		assert_str(StringName(String(entry["regime"]["crest_key"]))).is_equal(regime_def.crest_id)


func test_outcome_seals_correct_line_form_and_mark() -> void:
	# victory -> double rule (VICTORY class) + WON
	var seal := ChroniclePresenter.seal_view("victory")
	assert_int(int(seal["class"])).is_equal(Inks.LineClass.VICTORY)
	assert_str(String(seal["mark"])).is_equal("WON")
	assert_str(String(seal["word"])).is_equal("victory")
	# defeat -> struck + CRUSHED
	seal = ChroniclePresenter.seal_view("defeat")
	assert_int(int(seal["class"])).is_equal(Inks.LineClass.STRIKE)
	assert_str(String(seal["mark"])).is_equal("CRUSHED")
	# aborted -> dashed (a dream held, then dropped) + ABANDONED
	seal = ChroniclePresenter.seal_view("aborted")
	assert_int(int(seal["class"])).is_equal(Inks.LineClass.WARN)
	assert_str(String(seal["mark"])).is_equal("ABANDONED")
	# All three really occur through the real verbs, and the entry's seal
	# class matches the Inks chronicle grammar for its outcome word.
	var host := _test_host()
	_end_hand(host, &"win", 4)
	_end_hand(host, &"loss", 2)
	_end_hand(host, &"abort", 2)
	var entries: Array = ChroniclePresenter.view(host, 0, 5)["entries"]
	var classes := {}
	for entry: Dictionary in entries:
		classes[String(entry["outcome"])] = int(entry["seal"]["class"])
	assert_int(int(classes["victory"])).is_equal(Inks.LineClass.VICTORY)
	assert_int(int(classes["defeat"])).is_equal(Inks.LineClass.STRIKE)
	assert_int(int(classes["aborted"])).is_equal(Inks.LineClass.WARN)


func test_empty_state_is_the_blank_chronicle() -> void:
	var host := _test_host()
	assert_bool(host.meta.chronicle.is_empty()).is_true()
	var view := ChroniclePresenter.view(host, 0, 5)
	assert_bool(bool(view["empty"])).is_true()
	assert_int((view["entries"] as Array).size()).is_equal(0)
	assert_int(int(view["page_count"])).is_equal(1)
	assert_int(int(view["runs_recorded"])).is_equal(0)
	# The required first-run print, exact.
	var lines: Array = view["empty_lines"]
	assert_str(String(lines[0]["text"])).is_equal(
		"the chronicle is blank — no dream has yet dared")
	# The live hand strip still prints (the first hand IS on the table).
	assert_dict(view["current"]).is_not_empty()


func test_current_run_excluded_until_it_ends() -> void:
	var host := _test_host()
	var first_leader := host.run().leader_name()
	_end_hand(host, &"win", 8)
	var second_leader := host.run().leader_name()
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)  # the live hand, hours in
	# The LIVE leader is not among the sealed entries; the first leader is.
	var view := ChroniclePresenter.view(host, 0, 5)
	var leaders: Array[String] = []
	for entry: Dictionary in view["entries"]:
		leaders.append(String(entry["leader"]))
	assert_array(leaders).is_equal([first_leader])
	assert_bool(leaders.has(second_leader)).is_false()
	# The live strip reads the run lifecycle's own surfaces — run number,
	# leader, regime, the hours SO FAR (not the engine clock).
	var current: Dictionary = view["current"]
	assert_int(int(current["run_number"])).is_equal(2)
	assert_str(String(current["leader"])).is_equal(second_leader)
	assert_str(String(current["regime_id"])).is_equal(String(host.run().regime_id()))
	assert_int(int(current["hours"])).is_equal(3)
	# End the second hand: it IS chronicle now, and the strip moves on.
	_end_hand(host, &"loss", 2)
	view = ChroniclePresenter.view(host, 0, 5)
	leaders.clear()
	for entry: Dictionary in view["entries"]:
		leaders.append(String(entry["leader"]))
	assert_array(leaders).is_equal([second_leader, first_leader])
	assert_str(String(view["current"]["leader"])).is_not_equal(second_leader)


func test_pagination_fifty_entries_newest_first() -> void:
	var host := _test_host()
	_synthetic_ring(host, 50)
	assert_int(host.meta.chronicle.size()).is_equal(50)
	# Page math: 50 entries / 5 per page = 10 pages; page 0 leads with the
	# newest hand (run 50), descending; the last page ends on run 1.
	var view := ChroniclePresenter.view(host, 0, 5)
	assert_int(int(view["page_count"])).is_equal(10)
	var entries: Array = view["entries"]
	assert_int(entries.size()).is_equal(5)
	assert_int(int(entries[0]["run"])).is_equal(50)
	assert_int(int(entries[4]["run"])).is_equal(46)
	# The last page carries the remainder (or the full page here: runs 5..1).
	view = ChroniclePresenter.view(host, 9, 5)
	entries = view["entries"]
	assert_int(int(view["page"])).is_equal(9)
	assert_int(entries.size()).is_equal(5)
	assert_int(int(entries[0]["run"])).is_equal(5)
	assert_int(int(entries[4]["run"])).is_equal(1)
	# Out-of-range pages clamp into the ring (never an empty view).
	view = ChroniclePresenter.view(host, 99, 5)
	assert_int(int(view["page"])).is_equal(9)
	assert_int((view["entries"] as Array).size()).is_equal(5)
	view = ChroniclePresenter.view(host, -7, 5)
	assert_int(int(view["page"])).is_equal(0)
	# A partial page prints its remainder honestly (52 = 10 full + 2).
	_synthetic_ring(host, 52)
	view = ChroniclePresenter.view(host, 10, 5)
	assert_int((view["entries"] as Array).size()).is_equal(2)


func test_duration_and_army_lines() -> void:
	# Hours under two days print as hours; above, days + hours.
	assert_str(ChroniclePresenter.duration_line(38 * 60)).is_equal("38h")
	assert_str(ChroniclePresenter.duration_line(3 * 24 * 60 + 14 * 60)).is_equal("3d 14h")
	assert_str(ChroniclePresenter.duration_line(0)).is_equal("0h")
	# The army at the end: per-def counts from the record's own roster
	# (pack display names, pluralized) + the power.
	var entry := {"army": {"knight": 3, "archer": 2}, "army_power": 41}
	assert_str(ChroniclePresenter.army_line(entry)).is_equal("3 knights, 2 archers · power 41")
	# Singular counts, an empty roster, and ids that left the pack (the
	# historical document keeps its own words).
	entry = {"army": {"knight": 1}, "army_power": 10}
	assert_str(ChroniclePresenter.army_line(entry)).is_equal("1 knight · power 10")
	entry = {"army": {}, "army_power": 7}
	assert_str(ChroniclePresenter.army_line(entry)).is_equal("no army stood · power 7")
	entry = {"army": {"halberdier": 2}, "army_power": 9}
	assert_str(ChroniclePresenter.army_line(entry)).is_equal("2 halberdiers · power 9")


func test_escalation_line_reads_the_entries_own_record() -> void:
	# L2-B: the victory that garrisoned the castle carries its escalation
	# cycle on the entry; the card prints the clerk's line from the entry's
	# OWN field (run-number rotor — same entry, same line; run 2 reads
	# variant 0, run 5 reads variant 1: repeats vary, the record does not).
	# Non-capturing entries carry an empty line and a zero cycle.
	var captured := {"run": 2, "leader": "Bran the Unbearable", "outcome": "victory",
		"regime": "gilded_crown", "escalation_cycle": 2}
	var view := ChroniclePresenter.entry_view(captured)
	assert_int(view["escalation_cycle"]).is_equal(2)
	assert_str(String(view["escalation_line"])).is_equal(
		"this army holds the castle — cycle 2 opens")
	# Same entry, same line (the rotor is the entry's own run number).
	var again := ChroniclePresenter.entry_view(captured.duplicate())
	assert_str(String(again["escalation_line"])).is_equal(String(view["escalation_line"]))
	# A different capturing run can read the other variant — still the
	# entry's own cycle, never another run's.
	var other := ChroniclePresenter.entry_view({"run": 5, "outcome": "victory",
		"regime": "velvet_fist", "escalation_cycle": 3})
	assert_str(String(other["escalation_line"])).contains("cycle 3")
	# Non-capturing entries: empty line, zero cycle, no invention.
	var quiet := ChroniclePresenter.entry_view({"run": 5, "outcome": "defeat",
		"regime": "paper_crown"})
	assert_int(quiet["escalation_cycle"]).is_equal(0)
	assert_str(String(quiet["escalation_line"])).is_equal("")


## L2-C: THE LEDGER RENDERS THE LINE — the entry card prints the clerk's
## italic row when (and only when) the entry carries the capture record;
## the card's row arithmetic and render oracle follow it; and the line
## fits its plate in the real italic face at the card's render size (the
## no-clip discipline, measured not assumed).
func test_entry_card_renders_the_escalation_line() -> void:
	var entry := {"run": 2, "leader": "Bran the Unbearable", "outcome": "victory",
		"regime": "gilded_crown", "escalation_cycle": 2,
		"duration_ticks": 38 * SimEngine.TICKS_PER_SIM_HOUR,
		"army": {"knight": 3}, "army_power": 34, "score": 88,
		"tags": [], "trait": ""}
	var card: ChronicleSheet.EntryCard = ChronicleSheet.EntryCard.new()
	add_child(card)
	await get_tree().process_frame
	card.bind(ChroniclePresenter.entry_view(entry))
	assert_str(card._escalation_label.text) \
		.is_equal("this army holds the castle — cycle 2 opens")
	var with_line := card.snapshot_hash()
	# The row arithmetic (the pure minimum override — deterministic in the
	# model alone; the live combined cache is the sheet's layout business).
	var height_with: Vector2 = card._get_minimum_size()
	# A non-capturing hand prints no row: empty plate, smaller minimum,
	# different render oracle.
	card.bind(ChroniclePresenter.entry_view({"run": 3, "leader": "Ida the Quiet",
		"outcome": "defeat", "regime": "paper_crown",
		"duration_ticks": 38 * SimEngine.TICKS_PER_SIM_HOUR,
		"army": {"knight": 3}, "army_power": 34, "score": 88,
		"tags": [], "trait": ""}))
	assert_str(card._escalation_label.text).is_empty()
	assert_int(card.snapshot_hash()).is_not_equal(with_line)
	assert_float(card._get_minimum_size().y).is_less(height_with.y)
	# The no-clip budget: every shipped escalation variant fits the card's
	# inner plate (CARD_MIN_WIDTH 380 - 2x pad 10 = 360) in the REAL italic
	# face at the card's render size, one row — measured headless-exact
	# against the plate budget, never a laid-out rect (the suite's node
	# carries no canvas layout).
	card.bind(ChroniclePresenter.entry_view(entry))
	await get_tree().process_frame
	var font: Font = card._escalation_label.get_theme_font(&"font")
	var font_size := card._escalation_label.get_theme_font_size(&"font_size")
	assert_int(font_size).is_equal(15)
	for variant in CopyDeck.variants(Inks.pack().copy, &"chronicle_escalation"):
		var text := String(variant).replace("{cycle}", "999")
		var measured := font.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		assert_float(measured).is_less(360.0)
	card.free()


func test_view_hash_deterministic_and_meta_sensitive() -> void:
	var host_a := _test_host()
	var host_b := _test_host()
	_end_hand(host_a, &"win", 5)
	_end_hand(host_b, &"win", 5)
	assert_int(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_a, 0, 5))) \
		.is_equal(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_b, 0, 5)))
	# A different record (one more hand) and a different page both move it.
	_end_hand(host_a, &"loss", 3)
	assert_int(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_a, 0, 5))) \
		.is_not_equal(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_b, 0, 5)))
	_synthetic_ring(host_b, 12)
	assert_int(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_b, 0, 5))) \
		.is_not_equal(ChroniclePresenter.view_hash(ChroniclePresenter.view(host_b, 1, 5)))


# --- the screen: affordance, focus, paging, input -----------------------------------------------


func _header_chip(screen: SpreadScreen) -> BaseButton:
	# The verbs row nests the chips (finishing refinement #2's header
	# restructure) — the lookup is by focus id, not child index.
	return SpreadScreen.header_chip(screen.get_active_slot(), "chronicle_chip") as BaseButton


func test_header_chip_opens_the_ledger_and_back_returns_focus() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	_end_hand(host, &"win", 5)
	_end_hand(host, &"loss", 3)
	var screen: SpreadScreen = await _mounted_screen(host)
	# The affordance is on BOTH slots' header verbs rows, in world
	# grammar, with the router's focus-equivalence id and a full grip.
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		var chip := SpreadScreen.header_chip(slot, "chronicle_chip")
		assert_that(chip).is_not_null()
		assert_str(String(chip.get_meta(&"focus_id", ""))).is_equal("chronicle_chip")
		var min_size: Vector2 = chip.get_combined_minimum_size()
		assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# The chip's press opens the ledger (the one verb).
	var chip := _header_chip(screen)
	chip.pressed.emit()
	await _await_seeded(screen._chronicle)
	var chronicle := screen._chronicle
	assert_bool(chronicle.is_open()).is_true()
	assert_int(int(screen.stats[&"chronicles_opened"])).is_equal(1)
	# Focus seeds the FIRST ENTRY (the walkable ring), which carries the grip.
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	assert_bool(focus == (chronicle.sheet().entries()[0] as Control)).is_true()
	assert_float((focus as Control).get_combined_minimum_size().y) \
		.is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# The newest hand leads: entry 0 is the loss (hand 2).
	assert_int(int(chronicle.view()["entries"][0]["run"])).is_equal(2)
	# No popup chrome anywhere in the ledger.
	for node in chronicle.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	# BACK closes the ledger and returns focus to the chip that opened it.
	chronicle._unhandled_input(_action_event(&"back"))
	assert_bool(chronicle.is_open()).is_false()
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(_header_chip(screen) as Object)
	assert_int(int(screen.stats[&"chronicles_closed"])).is_equal(1)
	screen.queue_free()


func test_page_turns_and_refusals_through_the_chips() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	_synthetic_ring(host, 50)
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	chronicle.per_page = 5
	chronicle.open(host, screen.get_router())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int((chronicle.view()["entries"] as Array).size()).is_equal(5)
	# Page-end chips print their refusal state (focusable, struck) — the
	# newest page has no newer page, the first older turn works.
	var chips := chronicle.sheet().chips()
	assert_int(chips.size()).is_equal(3)
	assert_bool(bool(chips[0].action["enabled"])).is_false()  # newer at page 0
	assert_bool(bool(chips[1].action["enabled"])).is_true()
	var hashes := [chronicle.snapshot_hash()]
	for page in range(1, 10):
		# Chips are REBUILT on every bind (labels print per state) — re-read.
		chips = chronicle.sheet().chips()
		chips[1].pressed.emit()
		await get_tree().process_frame
		assert_int(int(chronicle.view()["page"])).is_equal(page)
		hashes.append(chronicle.snapshot_hash())
	# Every page renders differently (the ring is real data).
	for i in hashes.size():
		for j in range(i + 1, hashes.size()):
			assert_int(hashes[i]).is_not_equal(hashes[j])
	# The far end refuses loudly (the chip printed its strike; stats count it).
	var refused_before := int(chronicle.stats[&"refused_pages"])
	chips = chronicle.sheet().chips()
	chips[1].pressed.emit()
	await get_tree().process_frame
	assert_int(int(chronicle.stats[&"refused_pages"])).is_equal(refused_before + 1)
	assert_int(int(chronicle.view()["page"])).is_equal(9)
	# Newer walks back to the newest page.
	for page in range(8, -1, -1):
		chips = chronicle.sheet().chips()
		chips[0].pressed.emit()
		await get_tree().process_frame
	assert_int(int(chronicle.view()["page"])).is_equal(0)
	assert_int(int(chronicle.stats[&"page_turns"])).is_equal(18)
	screen.queue_free()


func test_focus_based_scrolling_actually_scrolls() -> void:
	get_window().size = Vector2i(720, 720)  # a short band: the page must scroll
	var host := _test_host()
	_synthetic_ring(host, 50)
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	# Force a page TALLER than the band (the test seam): 6 wrapped cards.
	chronicle.per_page = 6
	chronicle.open(host, screen.get_router())
	await _await_seeded(chronicle)
	var sheet := chronicle.sheet()
	var scroll := sheet.scroll()
	var entries := sheet.entries()
	assert_int(entries.size()).is_equal(6)
	# The page really is taller than the viewport (the precondition —
	# otherwise the scroll contract is vacuous).
	var content := (scroll.get_child(0) as Control)
	assert_float(content.get_combined_minimum_size().y).is_greater(scroll.size.y + 1.0)
	assert_int(scroll.scroll_vertical).is_equal(0)
	# Focus the LAST entry: the paper follows (synchronously —
	# ensure_control_visible lands in the focus_entered handler).
	entries[5].grab_focus()
	await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_greater(0)
	# The focused entry's card is fully inside the scroll viewport.
	var viewport_rect := Rect2(scroll.global_position, scroll.size)
	var card_rect: Rect2 = (entries[5] as Control).get_global_rect()
	assert_bool(viewport_rect.encloses(card_rect.grow(-1.0))).is_true()
	# And back up: the first entry is scrolled into view again.
	entries[0].grab_focus()
	await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_equal(0)
	screen.queue_free()


## THE ROUND-1 VERIFIER FAIL, PINNED ON THE TURN PATH: on a page that
## EXCEEDS its band (the typical phone-portrait page — 6 real cards,
## content ~1250px over the ~934px band), EVERY page turn must land the
## ledger at the TOP with the seeded FOCUSED first entry ON-SCREEN, in
## BOTH directions. The old deferred ensure read the freshly-bound
## cards' PRE-SORT rects (still stacked under the dying previous page)
## and scrolled each fresh page to its MAXIMUM, stranding the focused
## card fully above the viewport (probe-measured: scroll 354/354, card0
## at global y −204).
func test_tall_page_turns_settle_at_top_with_focus_on_screen() -> void:
	get_window().size = Vector2i(720, 1280)  # phone portrait (per_page 6)
	var host := _test_host()
	_synthetic_ring(host, 26)  # 20+ real entries: 4 full pages + a 2-entry tail
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	chronicle.per_page = 6  # the derived portrait page size, pinned
	chronicle.open(host, screen.get_router())
	await _await_seeded(chronicle)
	var sheet := chronicle.sheet()
	var scroll := sheet.scroll()
	assert_int((chronicle.view()["entries"] as Array).size()).is_equal(6)
	# OPEN settles at the top with the seeded card on-screen.
	_assert_page_settled_at_top(sheet, scroll, true)
	# OLDER through every page of the ring (pages 1..3 full 6-card pages
	# that exceed the band; page 4 the 2-entry tail that fits it).
	for page in range(1, 5):
		chronicle.turn_page(1)
		await _await_seeded(chronicle)
		assert_int(int(chronicle.view()["page"])).is_equal(page)
		_assert_page_settled_at_top(sheet, scroll, page < 4)
	# NEWER back down through the SAME full pages — both directions, the
	# exact assertion shape of the focus-scroll contract, on every turn.
	for page in range(3, -1, -1):
		chronicle.turn_page(-1)
		await _await_seeded(chronicle)
		assert_int(int(chronicle.view()["page"])).is_equal(page)
		_assert_page_settled_at_top(sheet, scroll, true)
	assert_int(int(chronicle.stats[&"page_turns"])).is_equal(8)
	screen.queue_free()


## The per-turn settle contract: the scroll sits at the TOP, the seeded
## FOCUSED first entry is fully inside the scroll viewport, and — when
## `band_exceeding` — the page REALLY exceeds its band (otherwise the
## scroll assertions are vacuous).
func _assert_page_settled_at_top(sheet: ChronicleSheet, scroll: ScrollContainer,
		band_exceeding: bool) -> void:
	var entries := sheet.entries()
	assert_int(entries.size()).is_greater(0)
	if band_exceeding:
		var content := scroll.get_child(0) as Control
		assert_float(content.get_combined_minimum_size().y).is_greater(scroll.size.y + 1.0)
	assert_int(scroll.scroll_vertical).is_equal(0)
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_that(focus).is_not_null()
	assert_bool(focus == (entries[0] as Control)).is_true()
	var viewport_rect := Rect2(scroll.global_position, scroll.size)
	var card_rect: Rect2 = (entries[0] as Control).get_global_rect()
	assert_bool(viewport_rect.encloses(card_rect.grow(-1.0))).is_true()


## The small-page companions stay green: a ONE-page ring prints only the
## BACK chip, opens at the top, and its refused turn drifts nothing.
func test_one_page_ring_stays_at_top_and_prints_only_back() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	_synthetic_ring(host, 4)  # one page at 6 per page
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	chronicle.per_page = 6
	chronicle.open(host, screen.get_router())
	await _await_seeded(chronicle)
	assert_int(int(chronicle.view()["page_count"])).is_equal(1)
	assert_int(chronicle.sheet().chips().size()).is_equal(1)  # only BACK
	var scroll := chronicle.sheet().scroll()
	assert_int(scroll.scroll_vertical).is_equal(0)
	_assert_page_settled_at_top(chronicle.sheet(), scroll, false)
	# The out-of-range turn refuses (the chip printed its strike) and the
	# page stays settled at the top.
	chronicle.turn_page(1)
	await get_tree().process_frame
	assert_int(int(chronicle.stats[&"refused_pages"])).is_equal(1)
	assert_int(int(chronicle.view()["page"])).is_equal(0)
	assert_int(scroll.scroll_vertical).is_equal(0)
	screen.queue_free()


func test_ledger_answers_from_all_three_input_modes() -> void:
	get_window().size = Vector2i(720, 1280)
	# (a) TOUCH: a chip press is the gesture (page turn).
	var host_a := _test_host()
	_synthetic_ring(host_a, 12)
	var screen_a: SpreadScreen = await _mounted_screen(host_a)
	screen_a._chronicle.per_page = 5
	screen_a._chronicle.open(host_a, screen_a.get_router())
	await get_tree().process_frame
	(screen_a._chronicle.sheet().chips()[1] as BaseButton).pressed.emit()
	await get_tree().process_frame
	assert_int(int(screen_a._chronicle.view()["page"])).is_equal(1)
	screen_a.queue_free()
	await get_tree().process_frame
	# (b) PAD: non-positional primary activates the FOCUSED chip (the
	# fallback the engine might not route as ui_accept).
	var host_b := _test_host()
	_synthetic_ring(host_b, 12)
	var screen_b: SpreadScreen = await _mounted_screen(host_b)
	screen_b._chronicle.per_page = 5
	screen_b._chronicle.open(host_b, screen_b.get_router())
	await _await_seeded(screen_b._chronicle)
	# Walk focus down the ring onto the OLDER chip, then A.
	var focus := get_viewport().gui_get_focus_owner()
	for i in 6:
		focus = focus.find_next_valid_focus()
	(focus as Control).grab_focus()
	assert_bool(screen_b._chronicle.activate_focused()).is_true()
	await get_tree().process_frame
	assert_int(int(screen_b._chronicle.view()["page"])).is_equal(1)
	# Pad B closes the ledger (the back branch).
	screen_b._chronicle._unhandled_input(_action_event(&"back"))
	assert_bool(screen_b._chronicle.is_open()).is_false()
	screen_b.queue_free()
	await get_tree().process_frame
	# (c) KEYBOARD: Enter through the real input pipeline on the focused
	# chip (the natively-routed form never reaches the fallback).
	var host_c := _test_host()
	_synthetic_ring(host_c, 12)
	var screen_c: SpreadScreen = await _mounted_screen(host_c)
	screen_c._chronicle.per_page = 5
	screen_c._chronicle.open(host_c, screen_c.get_router())
	await _await_seeded(screen_c._chronicle)
	var focus_c := get_viewport().gui_get_focus_owner()
	for i in 6:
		focus_c = focus_c.find_next_valid_focus()
	(focus_c as Control).grab_focus()
	await get_tree().process_frame
	Input.parse_input_event(_enter_key())
	for i in 6:
		await get_tree().process_frame
	assert_int(int(screen_c._chronicle.view()["page"])).is_equal(1)
	screen_c.queue_free()


func test_longest_names_fit_their_labels_in_real_font_metrics() -> void:
	get_window().size = Vector2i(720, 1280)
	# The pools' LONGEST first + epithet, on every outcome — the T-UI-06
	# lesson as a test: shape content to the label budget, never clip.
	var host := _test_host()
	var firsts: Array = Inks.pack().identity.leader_first_names
	var epithets: Array = Inks.pack().identity.leader_epithets
	var longest := ""
	for a in firsts.size():
		for b in epithets.size():
			var candidate := "%s %s" % [firsts[a], epithets[b]]
			if candidate.length() > longest.length():
				longest = candidate
	host.meta.chronicle.clear()
	host.meta.runs_recorded = 0
	host.meta.legacy_points = 0
	for i in 3:
		host.meta.chronicle.append({
			"run": i + 1, "leader": longest, "tags": [&"gregarious", &"melancholy"],
			"trait": "counts everything twice", "regime": String(Inks.regime_ids()[i % 4]),
			"outcome": ["victory", "defeat", "aborted"][i],
			"duration_ticks": 86 * 60, "army_power": 120 + i,
			"army": {"knight": 12, "archer": 9}, "score": 306 + i,
		})
		host.meta.runs_recorded += 1
		host.meta.legacy_points += 306 + i
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	chronicle.per_page = 3
	chronicle.open(host, screen.get_router())
	await get_tree().process_frame
	await get_tree().process_frame
	# Settle poll: measure only against the LAID-OUT page (the first card
	# at full ledger width), never a mid-layout frame.
	for i in 30:
		if (chronicle.sheet().entries()[0] as Control).size.x > 400.0:
			break
		await get_tree().process_frame
	for card in chronicle.sheet().entries():
		var labels := _labels_of(card as Control)
		assert_bool(labels.is_empty()).is_false()
		for label in labels:
			var font := (label as Label).get_theme_font("font")
			# The theme item for a Label's size is "font_size" ("font"
			# returns the base default, ~24 — the probe find: measured
			# widths ran ~60% long off the wrong size).
			var size := (label as Label).get_theme_font_size("font_size")
			var width := (label as Control).size.x
			assert_float(width).is_greater(0.0)
			if (label as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				# Wrapped plate: the text fits its width AT THE WRAP, and
				# its wrapped height fits the plate (nothing hides).
				var wrapped := font.get_multiline_string_size(
					(label as Label).text, HORIZONTAL_ALIGNMENT_LEFT,
					width, size)
				assert_float(wrapped.y).is_less_equal((label as Control).size.y + 1.0)
				for word in (label as Label).text.split(" "):
					var word_width := font.get_string_size(String(word),
						HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
					assert_float(word_width).is_less_equal(width + 0.5)
			else:
				# Single-line plate: the whole line fits (clip_text is the
				# last resort, not the design).
				var line_width := font.get_string_size((label as Label).text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				assert_float(line_width).is_less_equal(width + 0.5)
	screen.queue_free()


func test_live_hand_line_wraps_inside_its_band() -> void:
	## FINISHING #6 (the T-UI-08 caveat, pinned): the live-hand line wraps
	## for EVERY real pool leader (the label budget at the sheet's 640
	## column is ~576px; even the SHORTEST name's line measures ~697px),
	## and the band holds BOTH wrapped lines — the second line never hides
	## under the entries band again. Pinned at the widest pool name +
	## widest regime + a 3-digit clock, the worst real combination.
	get_window().size = Vector2i(720, 1280)
	var theme: Theme = load("res://ui/theme/spread_theme.tres") as Theme
	var font: Font = theme.get_font(&"font", &"ChronicleLine")
	var size := int(theme.get_font_size(&"font_size", &"ChronicleLine"))
	# The widest leader + widest regime from the LIVE pools, measured.
	var firsts: Array = Inks.pack().identity.leader_first_names
	var epithets: Array = Inks.pack().identity.leader_epithets
	var widest_name := ""
	var widest_px := -1.0
	for a in firsts.size():
		for b in epithets.size():
			var candidate := "%s %s" % [firsts[a], epithets[b]]
			var px: float = font.get_string_size(candidate,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
			if px > widest_px:
				widest_px = px
				widest_name = candidate
	var widest_regime := ""
	var regime_px := -1.0
	for id in Inks.regime_ids():
		var name := String(Inks.regime_name(id))
		var px: float = font.get_string_size(name,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		if px > regime_px:
			regime_px = px
			widest_regime = name
	var sheet: ChronicleSheetScript = ChronicleSheetScript.new()
	sheet.size = Vector2(720.0, 1280.0)
	get_tree().root.add_child(sheet)
	await get_tree().process_frame
	await get_tree().process_frame
	sheet.bind({
		"title": "THE CHRONICLE", "runs_recorded": 3, "page": 0, "page_count": 2,
		"empty": false, "bank": 4688, "entries": [], "empty_lines": [],
		"current": {"leader": widest_name, "regime_name": widest_regime, "hours": 999},
	})
	await get_tree().process_frame
	await get_tree().process_frame
	# The precondition is real: the full line exceeds the label's width
	# (the wrap this test pins is the design, not an accident).
	var label: Label = sheet._live_label
	var full_px: float = font.get_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	assert_float(full_px).is_greater(label.size.x + 1.0) \
		.override_failure_message("the longest live line must genuinely wrap")
	# The wrap's two lines fit INSIDE the band (the covered-second-line
	# defect this round closes — LIVE_H is the 2-line band, font-metric
	# derived and grown by the type factor).
	var wrapped := font.get_multiline_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
	assert_float(wrapped.y).is_less_equal(sheet._live_row.size.y + 1.0) \
		.override_failure_message("the live band must hold every wrapped line")
	assert_float(sheet._live_row.size.y) \
		.is_greater_equal(ChronicleSheetScript.live_band_h() - 0.5)
	# The pure mapping re-baseline (LIVE_H grew 10px: same pages at every
	# common height — bigger band, same honest ring).
	for pair in [[1280.0, 6], [1080.0, 4], [800.0, 3], [720.0, 3]]:
		assert_int(ChronicleSheetScript.per_page_for_height(pair[0])).is_equal(pair[1])
	sheet.queue_free()


## THE 1.3x THIRD WRAP (the backlog sweep pin): at max type scale the
## widest pool names wrap the live-hand line to a THIRD line — the band is
## now ADAPTIVE (its height measured from the bound text's real wrap in
## the live font), so every wrapped line renders; the documented
## strip-plate fail-safe no longer covers a line.
func test_live_hand_band_holds_every_wrapped_line_at_1_3x() -> void:
	TypeScale.apply_factor(1.3)
	get_window().size = Vector2i(720, 1280)
	var theme: Theme = load("res://ui/theme/spread_theme.tres") as Theme
	var font: Font = theme.get_font(&"font", &"ChronicleLine")
	var size := int(theme.get_font_size(&"font_size", &"ChronicleLine"))
	# The widest leader + widest regime from the LIVE pools (the worst
	# corner the fail-safe documented), measured in the scaled face.
	var firsts: Array = Inks.pack().identity.leader_first_names
	var epithets: Array = Inks.pack().identity.leader_epithets
	var widest_name := ""
	var widest_px := -1.0
	for a in firsts.size():
		for b in epithets.size():
			var candidate := "%s %s" % [firsts[a], epithets[b]]
			var px: float = font.get_string_size(candidate,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
			if px > widest_px:
				widest_px = px
				widest_name = candidate
	var widest_regime := ""
	var regime_px := -1.0
	for id in Inks.regime_ids():
		var name := String(Inks.regime_name(id))
		var px: float = font.get_string_size(name,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		if px > regime_px:
			regime_px = px
			widest_regime = name
	var sheet: ChronicleSheetScript = ChronicleSheetScript.new()
	sheet.size = Vector2(720.0, 1280.0)
	get_tree().root.add_child(sheet)
	await get_tree().process_frame
	await get_tree().process_frame
	sheet.bind({
		"title": "THE CHRONICLE", "runs_recorded": 3, "page": 0, "page_count": 2,
		"empty": false, "bank": 4688, "entries": [], "empty_lines": [],
		"current": {"leader": widest_name, "regime_name": widest_regime, "hours": 999},
	})
	await get_tree().process_frame
	await get_tree().process_frame
	var label: Label = sheet._live_label
	# The precondition is real at 1.3x: the worst-corner text wraps PAST
	# two lines (the third line the fail-safe used to cover).
	var wrapped_two := font.get_multiline_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size, 2)
	var wrapped := font.get_multiline_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, label.size.x, size)
	assert_float(wrapped.y).is_greater(wrapped_two.y + 1.0) \
		.override_failure_message("the 1.3x worst corner must genuinely wrap a third line")
	# The adaptive band holds EVERY wrapped line (no covered third line).
	assert_float(wrapped.y).is_less_equal(sheet._live_row.size.y + 1.0) \
		.override_failure_message("the adaptive live band must hold every wrapped line at 1.3x")
	assert_float(sheet._live_row.size.y) \
		.is_greater_equal(ChronicleSheetScript.live_band_h() - 0.5)
	sheet.queue_free()
	await get_tree().process_frame
	TypeScale.reset()


func _labels_of(root: Control) -> Array[Label]:
	var found: Array[Label] = []
	var queue: Array[Control] = [root]
	while not queue.is_empty():
		var node: Control = queue.pop_front()
		if node is Label:
			found.append(node)
		for child in node.get_children():
			if child is Control:
				queue.append(child)
	return found


func _clipped_controls(root: Control, design: Vector2) -> Array[String]:
	## Scrolled content is EXCLUDED (the ledger's ring scrolls inside its
	## band by design — out-of-viewport rows are the scroll working, not
	## clipping): the ScrollContainer's subtree is skipped, the container
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
	_synthetic_ring(host, 9)
	var screen: SpreadScreen = await _mounted_screen(host)
	var chronicle := screen._chronicle
	var router: LayoutRouter = screen.get_router()
	# Harness-budget trim (finishing #5 re-dispatch): the router's 0.25s
	# dwell is the only wall-paced thing under these polls — age it under
	# the injected clock; the audits read SETTLED state at the true clock
	# (the dwell's flapping premise stays pinned at 1.0x in
	# test_responsive_layout's flapping test).
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
		chronicle.open(host, router)
		await _await_seeded(chronicle)
		assert_bool(chronicle.is_open()).is_true()
		# The page size derives from the live height — every entry of the
		# page renders, the sheet fits the design, nothing clips.
		var design := router.design_size()
		assert_int((chronicle.view()["entries"] as Array).size()) \
			.is_equal(ChronicleSheet.per_page_for_height(design.y))
		for offender in _clipped_controls(chronicle as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
		chronicle.close()
		await get_tree().process_frame
		Engine.time_scale = 60.0
	Engine.time_scale = 1.0
	screen.queue_free()


# --- persistence: the ring survives save/load ---------------------------------------------------


func test_save_load_persistence_into_the_screen() -> void:
	get_window().size = Vector2i(720, 720)
	var host := _test_host()
	_end_hand(host, &"win", 9)
	_end_hand(host, &"loss", 5)
	_end_hand(host, &"abort", 4)
	host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	assert_bool(host.save_all()).is_true()
	# A fresh process's host boots from the same root: the meta domain
	# (chronicle + bank) loads, run + meta both restored.
	var revived := GameHost.new(host.run_seed, host.save_manager.meta_path().get_base_dir())
	revived.autosave_interval_ticks = 0
	assert_bool(revived.boot(0)).is_true()
	assert_int(revived.meta.chronicle.size()).is_equal(3)
	assert_int(revived.meta.runs_recorded).is_equal(host.meta.runs_recorded)
	assert_int(revived.meta.legacy_points).is_equal(host.meta.legacy_points)
	# The SCREEN renders the same ring (same page 0 content + same
	# snapshot hash at the same size/per-page).
	var screen_a: SpreadScreen = await _mounted_screen(host)
	screen_a._chronicle.per_page = 5
	screen_a._chronicle.open(host, screen_a.get_router())
	await get_tree().process_frame
	var screen_b: SpreadScreen = await _mounted_screen(revived)
	screen_b._chronicle.per_page = 5
	screen_b._chronicle.open(revived, screen_b.get_router())
	await get_tree().process_frame
	assert_int(screen_b._chronicle.snapshot_hash()).is_equal(screen_a._chronicle.snapshot_hash())
	var entries_a: Array = screen_a._chronicle.view()["entries"]
	var entries_b: Array = screen_b._chronicle.view()["entries"]
	assert_int(entries_b.size()).is_equal(entries_a.size())
	for i in entries_a.size():
		assert_str(String(entries_b[i]["leader"])).is_equal(String(entries_a[i]["leader"]))
		assert_int(int(entries_b[i]["run"])).is_equal(int(entries_a[i]["run"]))
		assert_int(int(entries_b[i]["score"])).is_equal(int(entries_a[i]["score"]))
		assert_str(String(entries_b[i]["seal"]["mark"])).is_equal(String(entries_a[i]["seal"]["mark"]))
	# The revived LIVE hand is still not chronicle (the strip prints it).
	assert_str(String(screen_b._chronicle.view()["current"]["leader"])) \
		.is_equal(String(revived.run().leader_name()))
	screen_a.queue_free()
	screen_b.queue_free()
