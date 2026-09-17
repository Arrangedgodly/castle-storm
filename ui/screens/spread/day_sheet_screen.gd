## DaySheetScreen — the live run's own page (finishing refinement #2).
##
## THE DAY-SHEET (in-world: the clerk's page for the hand in play). The
## closing critique's P1: in-run history was unretrievable — the strip
## keeps 2 rows, the blockquotes self-fold, and the chronicle screen
## records only ENDED runs, so a missed crackdown line (seized what?
## scattered who?) was permanently lost exactly when re-planning
## mattered. This surface closes that: EVERY line that printed this run —
## every strip row (events, hints, refusals) PLUS the blockquote-only
## payloads (the scatter rows with the swept gate crowd's names, the
## while-you-were-away print's detail rows) — accumulates on one page,
## the chronicle screen's little sibling:
##
##   - paper over a veiled table (the same composition rule as the
##     chronicle ledger / intro packet — never modal chrome);
##   - NEWEST FIRST (documented choice): the strip reads newest-first,
##     the chronicle ring pages newest-first, and the line being sought
##     is almost always a recent one — reading order matches arrival
##     order on every print surface in this world;
##   - a single SCROLLED column of ChronicleLine rows (grip-height,
##     focusable — the history walks by pad/keyboard, the paper follows);
##     the ring PAGES because its entries are tall cards; rows are one
##     grip each, so the page scrolls;
##   - the count rule prints DASHED in red — the page itself is work in
##     progress (the edge-form grammar), the same distinction the
##     chronicle's live-hand strip carries;
##   - LIVE: prints that land while the sheet is open appear at the top
##     (the page is the table's own paper, not a snapshot).
##
## DATA + PERSISTENCE (documented choices): the ledger lives in the
## SpreadPresenter (run-scoped presentation state — the same category as
## the rolling chronicle buffer, deliberately OUTSIDE the sim and the
## save domains). It is NOT persisted across sessions: the durable record
## of a run is the chronicle entry it becomes, and a resumed session's
## away window prints its own catch-up summary onto the fresh page. A new
## hand turns the page (cleared at the run_started/run_restarted
## boundary). Rows past the presenter's cap leave the page and the sheet
## reports the truncation honestly.
##
## INPUT PARITY (Daredevil): touch (chip presses, drag-scroll), keyboard
## (arrows walk rows — focus-driven scroll; Enter activates the focused
## chip; Esc closes), pad (d-pad walks, A activates, B closes). Back is
## accepted from anywhere on the page. Reached from the spread header's
## verbs row (the Day-Sheet chip), one per slot, focus-equivalent across
## orientation swaps.
class_name DaySheetScreen
extends Control

## The page folded away (the spread owns the table again).
signal closed()

## The veil's opacity over the table beneath (the chronicle ledger's own
## candle-lit rule: paper over a dimmed table, never bare paper over a
## live one).
const VEIL_ALPHA := 0.90

## The page's letterpress (code-side, like the chronicle's own title).
const TITLE := "THE DAY-SHEET"

enum State { CLOSED, OPEN }

var host: GameHost
var state: int = State.CLOSED

## Instrumentation (tests assert the open/close contract).
var stats := {
	&"opens": 0,
	&"live_appends": 0,
}

var _veil: ColorRect
var _sheet: DaySheetSheet
var _router: LayoutRouter
var _view := {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_sheet = DaySheetSheet.new()
	_sheet.name = "DaySheetSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	_sheet.chip_pressed.connect(_on_chip)


# --- open / close -----------------------------------------------------------------------


## Open the run's page. `p_router` is the spread's router (orientation
## seam — the sheet relays on window resizes through NOTIFICATION_RESIZED
## of this full-rect control, the chronicle screen's pattern).
func open(p_host: GameHost, p_router: LayoutRouter, p_presenter: SpreadPresenter) -> void:
	host = p_host
	_router = p_router
	state = State.OPEN
	visible = true
	stats[&"opens"] += 1
	# The veil carries the live regime's ground tone (candle-lit paper
	# over the table — the composition rule every full-rect paper keeps).
	var regime_id := p_host.run().regime_id() if p_host.is_run_running() else &""
	_veil.color = Color(Inks.ground_for(regime_id, Inks.Phase.RECRUITING), VEIL_ALPHA)
	_view = view_for(p_host, p_presenter)
	_sheet.bind(_view)
	_seed_focus()


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	visible = false
	closed.emit()


func is_open() -> bool:
	return state != State.CLOSED


## The bound view model (tests read the mapped data).
func view() -> Dictionary:
	return _view


## The composed sheet (tests + the capture hook).
func sheet() -> DaySheetSheet:
	return _sheet


## Determinism oracle: same ledger => same page render.
func snapshot_hash() -> int:
	return _sheet.snapshot_hash()


## LIVE PAPER: new prints arrived while the page is open (the spread calls
## this from its strip bind). The delta lands at the TOP of the column —
## the page is the table's own paper, not a snapshot; a page that TURNED
## under the open sheet (a new hand was dealt) rebinds wholesale.
func sync_rows(p_host: GameHost, p_presenter: SpreadPresenter) -> void:
	if state != State.OPEN or _sheet == null:
		return
	var fresh := view_for(p_host, p_presenter)
	if _sheet.sync_rows(fresh):
		stats[&"live_appends"] += 1
	_view = fresh


func _on_chip(id: StringName) -> void:
	if id == &"back":
		close()


## Focus seeds the walk: the NEWEST row (the page leads with it); the
## empty page seeds the back chip — a screen must seed itself, the
## router's rule. The seed SETTLES on the real post-sort layout (the
## sheet's settle contract, the chronicle's round-1 lesson).
func _seed_focus() -> void:
	var focusables := _sheet.focusables()
	if not focusables.is_empty():
		_sheet.settle_seed(focusables[0])


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return
	if event.is_action_pressed(&"back"):
		close()
		get_viewport().set_input_as_handled()
		return
	# PAD PARITY: a non-positional primary the engine did not route to the
	# focused chip as ui_accept activates it here (the chronicle screen's
	# fallback mirrored — acting on the page is reachable identically from
	# touch, keyboard, and pad, exactly once each).
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		if activate_focused():
			get_viewport().set_input_as_handled()


## Activate the sheet chip that holds focus, if any (the pad fallback).
## Returns true when a chip was activated.
func activate_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and focus.get_parent() == _sheet:
		(focus as BaseButton).pressed.emit()
		return true
	return false


# --- the pure view ------------------------------------------------------------------------


## The whole page as data. Pure: reads only the presenter's run-scoped
## ledger + the run lifecycle's live query surfaces (the hand's number,
## the hours so far). Same ledger (+ live run) => same view.
static func view_for(p_host: GameHost, p_presenter: SpreadPresenter) -> Dictionary:
	var rows := p_presenter.day_sheet_newest_first()
	var count_line := ""
	if not p_host.is_run_running():
		count_line = "%d lines — the hand has ended" % rows.size()
	else:
		var run := p_host.run()
		var hours := (p_host.engine.tick_count - run.run_start_tick()) \
			/ SimEngine.TICKS_PER_SIM_HOUR
		count_line = "hand %d · %dh in · %d lines printed" % [
			p_host.meta.runs_recorded + 1, hours, rows.size()]
	return {
		"title": TITLE,
		"empty": rows.is_empty(),
		"empty_lines": [
			{"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"daysheet_empty_1", 0)},
			{"class": Inks.LineClass.PLAIN,
				"text": CopyDeck.line(Inks.pack().copy, &"daysheet_empty_2", 0)},
		],
		"rows": rows,
		"dropped": p_presenter.day_sheet_dropped,
		"count_line": count_line,
	}


# --- the sheet (the paper itself) -----------------------------------------------------------

## DaySheetSheet — the page ON THE TABLE: a paper quad (the choice card's
## cut stock), the letterpress title, the dashed count rule, the scrolled
## column of ChronicleLine rows, and the back verb. All T-UI-01 grammar,
## nothing forked; the no-clip discipline rides the row component itself
## (grip-height rows, text clips at the sheet edge, never past the
## paper).
class DaySheetSheet:
	extends Control

	const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")
	const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

	## Paper margins (design units; the chronicle sheet's own).
	const MARGIN := 14.0
	const PAD := 12.0
	## The column's readable width cap (a page of full-wide lines is a
	## wall — the ledger rule; both topologies read the page as a column).
	const SHEET_MAX_WIDTH := 640.0
	const TITLE_H := 54.0
	const COUNT_H := 26.0
	const CHIP_H := 48.0
	const BACK_CHIP_COUNT := 1

	## A chip was activated (the screen owns what the verbs do).
	signal chip_pressed(id: StringName)

	var _title_label: Label
	var _count_row: HBoxContainer
	var _count_rule: Control
	var _count_label: Label
	var _scroll: ScrollContainer
	var _list: VBoxContainer
	var _rows: Array[Control] = []
	var _chrome_rows: Array[Control] = []  # empty-state + truncation prints
	var _back_chip: ActionFan.ActionChip
	var _sheet_rect := Rect2()
	## Ledger length at the last bind (the live-append seam's delta).
	var _bound_total := -1


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compose()
		_relaid()


	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_relaid()


	func _draw() -> void:
		## The paper quad + its ink border (the choice card's stock: cheap
		## print, chamfered by hand — cut paper, never rounded luxe).
		if _sheet_rect.size.x < 4.0:
			return
		var rect := _sheet_rect.grow(-2.0)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
		var c := 9.0
		draw_line(Vector2(c, rect.position.y), Vector2(rect.position.x, rect.position.y + c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.position.y), Vector2(rect.end.x, rect.position.y + c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(c, rect.end.y), Vector2(rect.position.x, rect.end.y - c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 5.0, true)


# --- composition (T-UI-01 components; nothing forked) ------------------------------------


	func _compose() -> void:
		_title_label = Label.new()
		_title_label.theme_type_variation = &"CardTitle"
		_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_title_label)

		_count_row = HBoxContainer.new()
		_count_row.add_theme_constant_override("separation", 10)
		_count_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_count_rule = RULE_SCENE.instantiate()
		_count_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_count_rule.focus_mode = Control.FOCUS_NONE
		# The page itself is work in progress: DASHED, in red — the live
		# hand's own grammar (the chronicle's live strip prints the same).
		_count_rule.set("form", 1)  # RuleMark.RuleForm.DASHED
		_count_rule.set("rule_ink", Inks.RED)
		_count_row.add_child(_count_rule)
		_count_label = Label.new()
		_count_label.theme_type_variation = &"PipLabel"
		_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_count_label.clip_text = true
		_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_count_row.add_child(_count_label)
		add_child(_count_row)

		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(_scroll)
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 6)
		_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll.add_child(_list)

		_back_chip = ActionFan.ActionChip.new()
		_back_chip.action = {
			"id": &"back", "label": "Back to the table", "command": &"", "subject": &"",
			"value": 0, "enabled": true, "reason": "", "signature": true,
		}
		_back_chip.custom_minimum_size = Vector2(196.0, CHIP_H)
		_back_chip.pressed.connect(func() -> void: chip_pressed.emit(&"back"))
		add_child(_back_chip)


	## Bind the view: same view => same render (snapshot_hash pins it).
	## The title's baked size re-applies on every bind — the press-room's
	## live type-scale change (finishing refinement #5) re-flows a page
	## that was composed at another factor the next time it opens.
	func bind(view: Dictionary) -> void:
		_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
		_title_label.text = String(view["title"])
		_title_label.add_theme_color_override("font_color", Inks.INK)
		_count_label.text = String(view["count_line"])
		_count_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		_bind_rows(view)
		_wire_pad_column()
		_relaid()


	func _bind_rows(view: Dictionary) -> void:
		for row in _rows:
			row.queue_free()
		_rows.clear()
		for row in _chrome_rows:
			row.queue_free()
		_chrome_rows.clear()
		if _scroll != null:
			_scroll.scroll_vertical = 0
		var lines: Array = view["empty_lines"] if bool(view["empty"]) else view["rows"]
		for i in lines.size():
			var line: Control = CHRONICLE_SCENE.instantiate()
			line.set("line_class", int(lines[i]["class"]))
			line.set("text", String(lines[i]["text"]))
			# The page prints on PAPER stock — the print rule picks ink.
			line.set("ground", Inks.PAPER)
			_list.add_child(line)
			if bool(view["empty"]):
				# The blank page has nothing to walk — the rows retire to
				# chrome (the chronicle's empty state does the same).
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				line.focus_mode = Control.FOCUS_NONE
				_chrome_rows.append(line)
			else:
				line.focus_entered.connect(_ensure_row_visible.bind(line))
				_rows.append(line)
		if not bool(view["empty"]) and int(view["dropped"]) > 0:
			# The cap's honest report, at the foot of the page (the oldest
			# prints pressed off the sheet — bookkeeping, not walkable).
			var truncation: Control = CHRONICLE_SCENE.instantiate()
			truncation.set("line_class", Inks.LineClass.PLAIN)
			truncation.set("text", "…%d older line(s) pressed off this page." % int(view["dropped"]))
			truncation.set("ground", Inks.PAPER)
			_list.add_child(truncation)
			truncation.mouse_filter = Control.MOUSE_FILTER_IGNORE
			truncation.focus_mode = Control.FOCUS_NONE
			_chrome_rows.append(truncation)
		_bound_total = (view["rows"] as Array).size()


	## THE LIVE PAGE: append prints that arrived since the last bind. The
	## delta lands at the TOP (newest first) without disturbing the row the
	## player is reading (nodes are appended, never rebuilt). Returns true
	## when rows landed. A page that TURNED under the sheet (the ledger
	## shrank — a new hand) rebinds wholesale instead.
	func sync_rows(view: Dictionary) -> bool:
		var rows: Array = view["rows"]
		var total := rows.size()
		if total < _bound_total:
			bind(view)
			return false
		_count_label.text = String(view["count_line"])
		if total == _bound_total:
			return false
		var delta := total - _bound_total
		# Oldest of the delta seats first, each newer one above it: the
		# final order is [newest … oldest-of-delta, previous page].
		for i in range(delta - 1, -1, -1):
			var row: Dictionary = rows[i]
			var line: Control = CHRONICLE_SCENE.instantiate()
			line.set("line_class", int(row["class"]))
			line.set("text", String(row["text"]))
			line.set("ground", Inks.PAPER)
			_list.add_child(line)
			_list.move_child(line, 0)
			line.focus_entered.connect(_ensure_row_visible.bind(line))
			_rows.insert(0, line)
		_bound_total = total
		_wire_pad_column()
		_relaid()
		return true


	## THE PAD COLUMN: rows then the back verb as one cyclic vertical
	## chain (the fan's own rule, vertical form — the chronicle sheet's
	## discipline). Left/right stay free.
	func _wire_pad_column() -> void:
		var column: Array[Control] = []
		column.append_array(_rows)
		column.append(_back_chip)
		var count := column.size()
		if count == 0:
			return
		for i in count:
			var node := column[i]
			var prev: Control = column[wrapi(i - 1, 0, count)]
			var next: Control = column[wrapi(i + 1, 0, count)]
			node.focus_neighbor_top = node.get_path_to(prev)
			node.focus_neighbor_bottom = node.get_path_to(next)


	## THE FOCUS-SCROLL CONTRACT (Daredevil): a focused row is ALWAYS
	## scrolled into view — pad/keyboard focus walks the page, the paper
	## follows (the chronicle sheet's contract, mirrored).
	func _ensure_row_visible(row: Control) -> void:
		if _scroll == null or row == null or not is_instance_valid(row):
			return
		if not _rows.has(row):
			return  # a newer bind superseded this row mid-settle
		_scroll.ensure_control_visible.call_deferred(row)


	## THE OPEN SETTLE (the chronicle sheet's round-1 lesson): the page
	## opens at the TOP (the newest line) with the seeded focus ON-SCREEN,
	## computed from the REAL post-sort layout — never from a fixed
	## deferred frame.
	func settle_seed(seed: Control) -> void:
		if seed == null or _scroll == null:
			return
		await _await_real_layout()
		if not is_inside_tree() or not is_instance_valid(seed) or not seed.is_visible_in_tree():
			return
		_scroll.scroll_vertical = 0
		seed.grab_focus()


	## Wait until the layout the scroll math consumes is REAL: validated
	## (the first row sits at the top of the scroll's content) and stable
	## across two consecutive frames. Bounded — a degenerate layout
	## degrades to the fixed-defer behavior rather than blocking.
	func _await_real_layout() -> void:
		if _rows.is_empty():
			await get_tree().process_frame
			return
		var prev := ""
		for i in 12:
			await get_tree().process_frame
			if not is_inside_tree():
				return
			var stamp := _geometry_stamp()
			if _layout_is_real() and stamp == prev:
				return
			prev = stamp


	func _layout_is_real() -> bool:
		if _rows.is_empty() or _scroll == null or not is_inside_tree():
			return true
		var first := _rows[0] as Control
		if not is_instance_valid(first) or first.size.y < 1.0:
			return false
		var content_y := first.global_position.y - _scroll.global_position.y \
			+ float(_scroll.scroll_vertical)
		return absf(content_y) <= 0.5


	func _geometry_stamp() -> String:
		if _scroll == null or _list == null:
			return "null"
		var parts: Array[String] = [
			"%d" % _scroll.scroll_vertical,
			"%.2f" % _list.get_combined_minimum_size().y,
			"%.2f" % _scroll.size.y,
		]
		if not _rows.is_empty() and is_instance_valid(_rows[0]):
			var first := _rows[0] as Control
			parts.append("%.2f %.2f" % [first.global_position.y, first.size.y])
		return " ".join(parts)


	## The printed rows in page order (tests + focus seeding).
	func rows() -> Array[Control]:
		return _rows.duplicate()


	## The empty-state + truncation prints (tests).
	func chrome_rows() -> Array[Control]:
		return _chrome_rows.duplicate()


	func back_chip() -> ActionFan.ActionChip:
		return _back_chip


	func scroll() -> ScrollContainer:
		return _scroll


	## All focusable controls in page order — rows first (the walkable
	## page), then the back verb at the foot.
	func focusables() -> Array[Control]:
		var found: Array[Control] = []
		if not _rows.is_empty():
			found.append_array(_rows)
		else:
			found.append(_back_chip)
		return found


# --- layout (pure statics) ----------------------------------------------------------------


	func _relaid() -> void:
		if _title_label == null or size.x < 8.0 or size.y < 8.0:
			return
		var list_height := 0.0
		if _list != null:
			list_height = _list.get_combined_minimum_size().y
		var rects := sheet_rects(size, list_height)
		_sheet_rect = rects["sheet"]
		var list_h: float = rects["list_h"]
		var inner := Rect2(_sheet_rect.position + Vector2(PAD, PAD),
			_sheet_rect.size - Vector2(2.0 * PAD, 2.0 * PAD))
		_fit(_title_label, _row(inner, 0.0, TITLE_H))
		_fit(_count_row, _row(inner, TITLE_H, COUNT_H))
		_fit(_scroll, _row(inner, TITLE_H + COUNT_H, list_h))
		_fit(_back_chip, _row(inner, TITLE_H + COUNT_H + list_h, CHIP_H))
		queue_redraw()


	func _row(inner: Rect2, offset: float, height: float) -> Rect2:
		return Rect2(inner.position + Vector2(0.0, offset), Vector2(inner.size.x, height))


	## The sheet's layout rects. The paper column is capped at
	## SHEET_MAX_WIDTH, centered; the rows band grows with the page's real
	## content up to the height the bounds grant — a taller page SCROLLS
	## inside its band. Pure: same bounds + list height => same rects.
	static func sheet_rects(bounds: Vector2, list_height: float) -> Dictionary:
		var wide := minf(bounds.x - 2.0 * MARGIN, SHEET_MAX_WIDTH)
		var fixed := TITLE_H + COUNT_H + float(BACK_CHIP_COUNT) * CHIP_H + 2.0 * PAD
		var list_h := clampf(list_height, float(Inks.TOUCH_GRIP_MIN),
			maxf(float(Inks.TOUCH_GRIP_MIN), bounds.y - 2.0 * MARGIN - fixed))
		var sheet_h := fixed + list_h
		var sheet := Rect2(Vector2((bounds.x - wide) * 0.5, (bounds.y - sheet_h) * 0.5),
			Vector2(wide, sheet_h))
		return {"sheet": sheet, "list_h": list_h}


	func _fit(control: Control, rect: Rect2) -> void:
		control.position = rect.position
		control.size = rect.size


# --- render oracle --------------------------------------------------------------------------


	## The render oracle: every printed plate on the page. Same view =>
	## same hash (the page is a function of the ledger, never of UI
	## history).
	func snapshot_hash() -> int:
		var h := 0x811C9DC5
		h = _mix(h, _title_label.text.hash())
		h = _mix(h, _count_label.text.hash())
		for row in _rows:
			h = _mix(h, String(row.get("text")).hash())
			h = _mix(h, int(row.get("line_class")))
		for row in _chrome_rows:
			h = _mix(h, String(row.get("text")).hash())
		h = _mix(h, String(_back_chip.action.get("label", "")).hash())
		return h


	static func _mix(hash_value: int, value: int) -> int:
		var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
		x = (x * 16777619) & 0xFFFFFFFF
		x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return (x * 16777619) & 0xFFFFFFFF
