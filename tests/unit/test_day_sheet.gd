## Unit tests for the day-sheet (finishing refinement #2) — Daredevil lane.
##
## Mirrors ui/screens/spread/day_sheet_screen.gd + the SpreadPresenter's
## run-scoped ledger + the spread seams (the header verbs row, the primer,
## the autosave line). What is pinned:
##   - THE LEDGER (presenter): push_row accumulates strip rows onto the
##     page, push_rows records blockquote-only payloads WITHOUT the strip
##     buffer, the newest-first view, the cap's honest truncation, the
##     page turn at run boundaries (cleared BEFORE the new hand's own
##     announcement prints);
##   - THE HEADER VERBS ROW: both slots carry the chronicle chip AND the
##     day-sheet chip (focus-equivalent ids, full grips);
##   - THE SCREEN: the Day-Sheet chip opens the page (focus seeds the
##     newest row, no popup chrome), back closes and returns focus to the
##     chip, the page shows what the strip printed (newest first, real
##     event classes), the catch-up print's DETAIL rows reach the page
##     while the headline prints exactly once, an OPEN page is live
##     paper, focus-walked rows scroll into view, unclipped at the four
##     common sizes;
##   - THE PRIMER (P2): one teaching line at the session's first dashed
##     edge, once only;
##   - THE AUTOSAVE LINE (P3): the background flush prints one quiet row;
##     the periodic hourly autosave stays silent.
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const DaySheetScreenScript := preload("res://ui/screens/spread/day_sheet_screen.gd")

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
	_erase_dir("user://cs_daysheet_tests")


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


func _test_host(run_seed: int = 20270115) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_daysheet_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _mounted_screen(host: GameHost) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = false  # these suites pin THE TABLE + the page
	get_tree().root.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## The seed settles on the page's REAL layout (the chronicle suite's
## pattern): poll for the SEEDED STATE — the viewport's focus owner is
## one of the freshly-bound page's own walkables (a row, or the back
## chip on the blank page) — instead of trusting a fixed frame count.
## The spread's cards hold focus until settle_seed grabs the row, so a
## plain non-null poll would race the settle.
func _await_seeded(day_sheet: DaySheetScreenScript) -> void:
	for i in 60:
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner() as Control
		if focus == null:
			continue
		for row in day_sheet.sheet().rows():
			if row == focus:
				return
		if focus == day_sheet.sheet().back_chip():
			return


# --- the ledger (presenter) ---------------------------------------------------------------


func test_push_row_accumulates_strip_rows_newest_first() -> void:
	var presenter := SpreadPresenter.new()
	for i in 3:
		presenter.push_row({"class": Inks.LineClass.PLAIN, "text": "line %d" % i})
	assert_int(presenter.day_sheet.size()).is_equal(3)
	# The rolling strip buffer still keeps only its 12.
	var newest: Array[Dictionary] = presenter.day_sheet_newest_first()
	assert_int(newest.size()).is_equal(3)
	assert_str(String(newest[0]["text"])).is_equal("line 2")
	assert_str(String(newest[2]["text"])).is_equal("line 0")


func test_push_rows_records_blockquote_payloads_without_the_strip() -> void:
	var presenter := SpreadPresenter.new()
	presenter.push_rows([
		{"class": Inks.LineClass.STRIKE, "text": "Swept: Aldous, Bertrand and 2 more board carts."},
		{"class": Inks.LineClass.STRIKE, "text": "…1 loitering peasants follow them."},
	])
	# The page carries the named blockquote rows...
	assert_int(presenter.day_sheet.size()).is_equal(2)
	# ...the strip's rolling buffer does NOT (they never printed there).
	assert_int(presenter.chronicle.size()).is_equal(0)


func test_cap_presses_oldest_off_and_reports_honestly() -> void:
	var presenter := SpreadPresenter.new()
	presenter.day_sheet_cap = 4
	for i in 6:
		presenter.push_row({"class": Inks.LineClass.PLAIN, "text": "line %d" % i})
	assert_int(presenter.day_sheet.size()).is_equal(4)
	assert_int(presenter.day_sheet_dropped).is_equal(2)
	# The SURVIVORS are the newest.
	assert_str(String(presenter.day_sheet[0]["text"])).is_equal("line 2")
	assert_str(String(presenter.day_sheet_newest_first()[0]["text"])).is_equal("line 5")


func test_page_turn_clears_and_the_new_hand_opens_its_own_page() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	await get_tree().process_frame
	assert_int(screen.presenter.day_sheet.size()).is_greater(1)
	# End the hand and deal the next (the real verbs, the real drain).
	var old_lines := {}
	for row: Dictionary in screen.presenter.day_sheet:
		old_lines[row["text"]] = true
	host.submit(&"resolve_victory", &"loss", 0)
	host.fast_forward(2)
	host.restart_run()
	host.advance_ticks(1)
	await get_tree().process_frame
	# The page TURNED: not one of the old hand's lines remains, and the
	# new page opens with its own announcement (the run_restarted line
	# prints AFTER the clear — the oldest row on the fresh page).
	var page: Array[Dictionary] = screen.presenter.day_sheet
	assert_int(page.size()).is_greater_equal(1)
	assert_int(page.size()).is_less(4)
	for row: Dictionary in page:
		assert_bool(old_lines.has(row["text"])).is_false()
	screen.queue_free()


# --- the header verbs row -------------------------------------------------------------------


func test_header_carries_both_ledger_verbs() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	for slot: OrientationSlot in [screen.get_portrait_slot(), screen.get_landscape_slot()]:
		for focus_id in ["chronicle_chip", "day_sheet_chip"]:
			var chip := SpreadScreen.header_chip(slot, focus_id)
			assert_that(chip).is_not_null()
			assert_str(String(chip.get_meta(&"focus_id", ""))).is_equal(focus_id)
			var min_size: Vector2 = chip.get_combined_minimum_size()
			assert_float(min_size.y).is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# The letterhead keeps the strip's first row (child 0), the verbs row
	# nests beneath it — the RunHeader API still binds.
	var header := (screen.get_portrait_slot() as OrientationSlot).get_header().get_child(0)
	assert_str(String(header._name_label.text)).is_not_empty()
	screen.queue_free()


func test_day_chip_opens_the_page_and_back_returns_focus() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# A printed history first (the primer + one real arrival).
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	await get_tree().process_frame
	var chip := SpreadScreen.header_chip(screen.get_active_slot() as OrientationSlot, "day_sheet_chip")
	chip.pressed.emit()
	var day_sheet: DaySheetScreenScript = screen._day_sheet
	await _await_seeded(day_sheet)
	assert_bool(day_sheet.is_open()).is_true()
	assert_int(int(screen.stats[&"day_sheets_opened"])).is_equal(1)
	# Focus seeds the NEWEST row (the walkable page), grip-height.
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_that(focus).is_not_null()
	assert_bool(focus == (day_sheet.sheet().rows()[0] as Control)).is_true()
	assert_float(focus.get_combined_minimum_size().y) \
		.is_greater_equal(float(Inks.TOUCH_GRIP_MIN))
	# No popup chrome anywhere on the page.
	var stack: Array[Node] = [day_sheet]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
		for child in node.get_children():
			stack.append(child)
	# BACK closes the page and returns focus to the chip that opened it.
	day_sheet._unhandled_input(_action_event(&"back"))
	assert_bool(day_sheet.is_open()).is_false()
	await get_tree().process_frame
	assert_that(get_viewport().gui_get_focus_owner()).is_same(chip as Object)
	assert_int(int(screen.stats[&"day_sheets_closed"])).is_equal(1)
	screen.queue_free()


# --- the page: what it shows, how it behaves ------------------------------------------------


func test_page_shows_what_the_strip_printed_newest_first() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# One line the strip has already FORGOTTEN (a synthetic older print —
	# the strip keeps 2, the page keeps the hand).
	screen.presenter.push_row({"class": Inks.LineClass.PLAIN, "text": "an older print"})
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	await get_tree().process_frame
	var day_sheet: DaySheetScreenScript = screen._day_sheet
	day_sheet.open(host, screen.get_router(), screen.presenter)
	await get_tree().process_frame
	await get_tree().process_frame
	# The page's newest row IS the strip's newest print (one choke point:
	# strip and page can never disagree).
	var strip_rows: Array[Dictionary] = screen.presenter.chronicle_strip()
	var page_rows: Array = day_sheet.view()["rows"]
	assert_int(page_rows.size()).is_greater_equal(strip_rows.size())
	assert_str(String(page_rows[0]["text"])).is_equal(String(strip_rows[0]["text"]))
	assert_int(int(page_rows[0]["class"])).is_equal(int(strip_rows[0]["class"]))
	# A retrieval surface, not a summary: the OLDER prints are all still
	# on the page even though the strip forgot them.
	var strip_texts := {}
	for row: Dictionary in strip_rows:
		strip_texts[row["text"]] = true
	var older_on_page := 0
	for row: Dictionary in page_rows:
		if not strip_texts.has(row["text"]):
			older_on_page += 1
	assert_int(older_on_page).is_greater(0)
	day_sheet.close()
	screen.queue_free()


func test_catch_up_detail_rows_reach_the_page_headline_once() -> void:
	get_window().size = Vector2i(720, 720)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	const T0 := 1_800_000_000
	host.background(T0)
	host.foreground(T0 + 6 * 3600)  # a 6h away window resolves on the live table
	await get_tree().process_frame
	var page: Array[Dictionary] = screen.presenter.day_sheet
	# The headline printed through the event drain — EXACTLY ONCE (the
	# mid-session path does not re-push it)...
	var headlines := 0
	var detail := 0
	for row: Dictionary in page:
		var text := String(row["text"])
		if text.contains("While you were away"):
			headlines += 1
		if text.contains("stores") or text.contains("The Crown's eye"):
			detail += 1
	assert_int(headlines).is_equal(1)
	# ...and the blockquote's DETAIL (stores / the Crown's eye — rows the
	# self-folding quote would have taken with it) stays on the page.
	assert_int(detail).is_greater(0)
	screen.queue_free()


func test_open_page_is_live_paper() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var day_sheet: DaySheetScreenScript = screen._day_sheet
	day_sheet.open(host, screen.get_router(), screen.presenter)
	await get_tree().process_frame
	var bound: int = day_sheet.view()["rows"].size()
	# The world prints while the page is open — the new line lands ON TOP.
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	await get_tree().process_frame
	assert_int(int(day_sheet.stats[&"live_appends"])).is_greater(0)
	var fresh_rows: Array = day_sheet.view()["rows"]
	assert_int(fresh_rows.size()).is_greater(bound)
	assert_str(String(fresh_rows[0]["text"])).contains("gate")
	day_sheet.close()
	screen.queue_free()


func test_focus_walked_rows_scroll_into_view() -> void:
	get_window().size = Vector2i(720, 720)  # a short band: the page must scroll
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	for i in 30:
		screen.presenter.push_row({"class": Inks.LineClass.PLAIN, "text": "line %d" % i})
	var day_sheet: DaySheetScreenScript = screen._day_sheet
	day_sheet.open(host, screen.get_router(), screen.presenter)
	await _await_seeded(day_sheet)
	var sheet := day_sheet.sheet()
	var scroll := sheet.scroll()
	var rows := sheet.rows()
	assert_int(rows.size()).is_greater_equal(30)
	# The page really is taller than the viewport (the precondition).
	var content := scroll.get_child(0) as Control
	assert_float(content.get_combined_minimum_size().y).is_greater(scroll.size.y + 1.0)
	assert_int(scroll.scroll_vertical).is_equal(0)
	# Focus the OLDEST row (the page's foot): the paper follows (the
	# deferred ensure lands, then the scroll re-positions its content —
	# measure after the re-layout settles, like the paper does).
	rows[rows.size() - 1].grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_greater(0)
	var viewport_rect := Rect2(scroll.global_position, scroll.size)
	var row_rect: Rect2 = (rows[rows.size() - 1] as Control).get_global_rect()
	assert_bool(viewport_rect.encloses(row_rect.grow(-1.0))).is_true()
	day_sheet.close()
	screen.queue_free()


func test_unclipped_at_four_sizes_focus_never_stranded() -> void:
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	while host.units().pending_offers() == 0:
		host.fast_forward(30)
	var day_sheet: DaySheetScreenScript = screen._day_sheet
	var router: LayoutRouter = screen.get_router()
	for i in TEST_SIZES.size():
		get_window().size = TEST_SIZES[i]
		for f in 240:
			await get_tree().process_frame
			if router.is_portrait() == EXPECTED_PORTRAIT[i] and router.design_size().x > 1.0:
				break
		for f in 3:
			await get_tree().process_frame
		day_sheet.open(host, router, screen.presenter)
		await _await_seeded(day_sheet)
		assert_bool(day_sheet.is_open()).is_true()
		var design := router.design_size()
		for offender in _clipped_controls(day_sheet as Control, design):
			assert_str(offender).is_equal("<no clipping expected>")
		assert_that(get_viewport().gui_get_focus_owner()).is_not_null()
		day_sheet.close()
		await get_tree().process_frame
	screen.queue_free()


func _clipped_controls(root: Control, design: Vector2) -> Array[String]:
	## Scrolled content is EXCLUDED (the page scrolls inside its band by
	## design — out-of-viewport rows are the scroll working, not clipping):
	## the ScrollContainer's subtree is skipped, the container itself (the
	## viewport) is still audited.
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


# --- the line-form primer (P2) ----------------------------------------------------------------


func test_primer_prints_once_at_the_first_dashed_edge() -> void:
	get_window().size = Vector2i(720, 1280)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	# The fresh table's staked plots print dashed (queued paper) from the
	# FIRST bind — the primer prints there, once.
	assert_int(int(screen.stats[&"primer_lines"])).is_equal(1)
	var page: Array[Dictionary] = screen.presenter.day_sheet
	var primer_rows := 0
	for row: Dictionary in page:
		if String(row["text"]).to_lower().contains("dashed"):
			primer_rows += 1
	assert_int(primer_rows).is_equal(1)
	# Once-only: later binds (and real events) never re-print it.
	host.fast_forward(30)
	screen.refresh_from_state()
	await get_tree().process_frame
	assert_int(int(screen.stats[&"primer_lines"])).is_equal(1)
	screen.queue_free()


# --- the autosave line (P3) --------------------------------------------------------------------


func test_background_flush_prints_one_quiet_line_periodic_stays_silent() -> void:
	get_window().size = Vector2i(720, 720)
	var host := _test_host()
	var screen: SpreadScreen = await _mounted_screen(host)
	var before := screen.presenter.day_sheet.size()
	# The background boundary: the flush prints ONE quiet row (the clerk
	# files the hour — visible on return, retrievable on the page).
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_int(int(screen.stats[&"autosave_lines"])).is_equal(1)
	var page: Array[Dictionary] = screen.presenter.day_sheet
	assert_int(page.size()).is_equal(before + 1)
	assert_int(int(page[page.size() - 1]["class"])).is_equal(Inks.LineClass.PLAIN)
	# Both variants speak the hour being filed/blotted — the row is the
	# flush's own voice, whichever variant the rotor draws.
	assert_str(String(page[page.size() - 1]["text"])).contains("hour")
	# The foreground returns with (near-)zero window — no more print.
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_int(int(screen.stats[&"autosave_lines"])).is_equal(1)
	# The PERIODIC autosave (once per sim hour here) stays silent by
	# choice — a line per hour is spam, not status.
	host.autosave_interval_ticks = 60
	host.fast_forward(120)
	await get_tree().process_frame
	assert_int(int(screen.stats[&"autosave_lines"])).is_equal(1)
	screen.queue_free()
