## ChronicleSheet — the chronicle's ledger ON THE TABLE (T-UI-08).
##
## The chronicle is PAST SPREADS (design brief §3): this control is the
## pressed ledger of every ended hand — one small spread card per
## chronicle entry, dealt newest-first down a paper column. Anti-goal
## popup chrome (brief §4): this is paper laid over the table, the same
## composition rule as the intro packet and the assault stage.
##
## Composition (all T-UI-01 grammar, nothing forked):
##   - the SHEET: a paper quad (drawn cheap-print border, chamfered by
##     hand — the choice-card stock) capped at a readable column width,
##     centered, inside the design bounds in BOTH topologies;
##   - the letterpress title + the run-count line;
##   - THE LIVE HAND strip — the current run's own distinction: the hand
##     on the table right now prints DASHED (in progress, the edge-form
##     grammar) ABOVE the sealed records, so the ledger reads
##     live-hand-first and the live run is never mistaken for history;
##   - THE RING OF PAST SPREADS: a ScrollContainer of entry cards (the
##     EntryCard below), one page at a time — the roster grows unbounded
##     across runs, so the sheet PAGES it (chips below) and scrolls
##     within a page (focus-driven: a focused entry is ALWAYS scrolled
##     into view — pad focus walks the list, the paper follows);
##   - the footer: the bank line (the number every past hand added to);
##   - the chips: NEWER / OLDER page turns + BACK TO THE TABLE (>= 48
##     grips, ActionFan's ActionChip unforked; a page-end chip stays
##     focusable and prints its refusal — the fan's kept-consistent rule);
##   - the EMPTY state: the first run prints "the chronicle is blank —
##     no dream has yet dared" on the empty ledger.
##
## NO-CLIP DISCIPLINE (the T-UI-06 lesson: shape content, never clip
## mid-sentence): the presenter shapes lines to label budgets and these
## plates autowrap at the same budgets — long pool names and army rosters
## wrap onto bounded rows, nothing clips. sheet_rects() is pure and
## test-pinned.
##
## Determinism: bind(view) is a pure function of the presenter's view
## model; snapshot_hash() pins the render.
class_name ChronicleSheet
extends Control

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")
const FACE_SLOT_SCENE := preload("res://ui/theme/face_slot.tscn")
const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")

## Ledger margins (design units; grip = 48).
const MARGIN := 14.0
const PAD := 12.0
## The column's readable width cap (a ledger of full-wide lines is a
## wall — the brief's landscape topology keeps panoramic tables for
## cards; the ledger reads as a column in both topologies).
const SHEET_MAX_WIDTH := 640.0
## Entry rows per page when the screen does not derive one from bounds.
const DEFAULT_PER_PAGE := 5
## Region heights for the pure layout (labels wrap inside their rows).
const TITLE_H := 54.0
const COUNT_H := 24.0
const LIVE_H := 46.0
const FOOTER_H := 26.0
const CHIP_H := 48.0
## Fixed chip count (page turns + back).
const CHIP_COUNT := 3
## The crest plate's size inside an entry card.
const CREST_SIZE := 56.0

## A chip was activated (the screen owns what the verbs do; refused page
## ends arrive here too — the chip printed its own refusal).
signal chip_pressed(id: StringName)

var _title_label: Label
var _count_label: Label
var _live_row: HBoxContainer
var _live_rule: Control
var _live_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array[Control] = []
var _empty_rows: Array[Control] = []
var _footer_label: Label
var _chips: Array[ActionFan.ActionChip] = []
var _sheet_rect := Rect2()
## Bumped on every bind: a settle still awaiting a superseded page's
## layout aborts instead of grabbing focus for a page that is gone (the
## rapid-turn guard).
var _bind_token := 0


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

	_count_label = Label.new()
	_count_label.theme_type_variation = &"PipLabel"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_live_row = HBoxContainer.new()
	_live_row.add_theme_constant_override("separation", 10)
	_live_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_rule = RULE_SCENE.instantiate()
	_live_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_live_rule.focus_mode = Control.FOCUS_NONE
	_live_row.add_child(_live_rule)
	_live_label = Label.new()
	_live_label.theme_type_variation = &"ChronicleLine"
	_live_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrap-width floor (the probe's 2181px-row find): the live strip's text
	# is long, and an un-floored autowrap minimum evaluates its first pass
	# at ~0 width — a thousands-px poisoned minimum the row then carries.
	_live_label.custom_minimum_size = Vector2(400.0, 0.0)
	_live_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_row.add_child(_live_label)
	add_child(_live_row)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)

	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"RoleLine"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer_label)


func _rebuild_chips(view: Dictionary) -> void:
	for chip in _chips:
		chip.queue_free()
	_chips.clear()
	var page := int(view["page"])
	var page_count := int(view["page_count"])
	var actions: Array[Dictionary] = []
	# A one-page ring has nothing to page (two struck no-op chips read as
	# broken chrome, not honest state) — only the back verb prints.
	if page_count > 1:
		actions.append({
			"id": &"newer", "label": "Newer hands", "command": &"", "subject": &"",
			"value": 0, "enabled": page > 0, "reason": "the newest hand leads",
			"signature": false,
		})
		actions.append({
			"id": &"older", "label": "Older hands", "command": &"", "subject": &"",
			"value": 0, "enabled": page < page_count - 1, "reason": "the ledger begins here",
			"signature": false,
		})
	actions.append({
		"id": &"back", "label": "Back to the table", "command": &"", "subject": &"",
		"value": 0, "enabled": true, "reason": "", "signature": true,
	})
	for action in actions:
		var chip := ActionFan.ActionChip.new()
		chip.action = action
		chip.custom_minimum_size = Vector2(196.0, CHIP_H)
		chip.pressed.connect(func() -> void: chip_pressed.emit(action["id"]))
		add_child(chip)
		_chips.append(chip)


# --- binding (pure in the view model) -----------------------------------------------------


## Bind the presenter's view. Same view => same render (snapshot_hash).
func bind(view: Dictionary) -> void:
	_bind_token += 1  # any settle still holding the previous page aborts
	# The title's baked size re-applies on every bind — the press-room's
	# live type-scale change (finishing refinement #5) re-flows a ledger
	# composed at another factor the next time it opens.
	_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
	_title_label.text = String(view["title"])
	_title_label.add_theme_color_override("font_color", Inks.INK)
	_count_label.text = _count_line(view)
	_count_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	var current: Dictionary = view["current"]
	if current.is_empty():
		_live_row.visible = false
	else:
		_live_row.visible = true
		_live_rule.set("form", 1)  # RuleForm.DASHED — the hand is still in progress
		_live_rule.set("rule_ink", Inks.RED)
		_live_label.text = "THE LIVE HAND — %s serves %s, %dh in: not yet chronicle." % [
			String(current["leader"]), _regime_with_article(String(current["regime_name"])),
			int(current["hours"])]
		_live_label.add_theme_color_override("font_color", Inks.INK)
	_rebuild_entries(view)
	_rebuild_chips(view)
	if bool(view["empty"]):
		_footer_label.text = ""
	else:
		_footer_label.text = "the bank holds %s legacy points" % Inks.abbreviate_amount(int(view["bank"]))
		_footer_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	_wire_pad_column()
	_relaid()


## THE PAD COLUMN (T-PERF-02's Deck sweep find): entries then chips as one
## cyclic vertical chain (the fan's own rule, vertical form). The engine's
## geometric neighbor resolution races the chips' row against a tall
## page's last entries — on the Deck profile the dpad skipped from the
## second entry straight to the NEWER chip, leaving the third entry
## unreachable by pad. Wired, every entry and chip walks by dpad
## regardless of the page's geometry; left/right stay free.
func _wire_pad_column() -> void:
	var column: Array[Control] = []
	column.append_array(_entries)
	for chip in _chips:
		column.append(chip)
	var count := column.size()
	if count == 0:
		return
	for i in count:
		var node := column[i]
		var prev: Control = column[wrapi(i - 1, 0, count)]
		var next: Control = column[wrapi(i + 1, 0, count)]
		node.focus_neighbor_top = node.get_path_to(prev)
		node.focus_neighbor_bottom = node.get_path_to(next)


func _regime_with_article(regime_name: String) -> String:
	## Regime display names carry their own article ("The Paper Crown").
	if regime_name.is_empty():
		return "the Crown"
	if regime_name.begins_with("The "):
		return regime_name
	return "the " + regime_name


func _count_line(view: Dictionary) -> String:
	var runs := int(view["runs_recorded"])
	if runs <= 0:
		return "no hands recorded"
	if runs == 1:
		return "one hand recorded"
	return "%d hands recorded" % runs


## Rebuild the entry cards to the page's entries + the empty state.
## A FRESH PAGE STARTS AT THE TOP: the immediate reset here is provisional
## — the definitive one lands in `settle_seed` once the page's layout is
## REAL (post-sort rects), because the focus-ensure that follows the seed
## must never consume the freshly-added children's stale geometry (the
## verifier's round-1 FAIL: the ensure scrolled fresh pages to their
## bottom and stranded the seeded card above the viewport).
func _rebuild_entries(view: Dictionary) -> void:
	for entry in _entries:
		entry.queue_free()
	_entries.clear()
	for row in _empty_rows:
		row.queue_free()
	_empty_rows.clear()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	if bool(view["empty"]):
		var lines: Array = view["empty_lines"]
		for i in lines.size():
			var line: Control = CHRONICLE_SCENE.instantiate()
			line.set("line_class", int(lines[i]["class"]))
			line.set("text", String(lines[i]["text"]))
			line.set("ground", Inks.PAPER)
			_list.add_child(line)
			# After add_child: the row's own _ready sets FOCUS_ALL (its
			# walking role on the table); the empty ledger has no ring to
			# walk, so the rows retire to chrome.
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.focus_mode = Control.FOCUS_NONE
			_empty_rows.append(line)
		return
	var entries: Array = view["entries"]
	for i in entries.size():
		var card := EntryCard.new()
		_list.add_child(card)
		card.bind(entries[i])
		card.focus_entered.connect(_ensure_entry_visible.bind(card))
		_entries.append(card)


## THE FOCUS-SCROLL CONTRACT (Daredevil): a focused entry is ALWAYS
## scrolled into view — pad/keyboard focus walks the ring, the paper
## follows. ScrollContainer does not do this by itself. The ensure is
## DEFERRED past the container's own child reposition — on a SETTLED page
## (a focus walk) one deferral is enough. A card no longer on this page
## (a newer bind superseded it mid-settle) never ensures.
func _ensure_entry_visible(card: Control) -> void:
	if _scroll == null or card == null or not is_instance_valid(card):
		return
	if not _entries.has(card):
		return  # the page turned again under the walk — stale card
	_scroll.ensure_control_visible.call_deferred(card)


## THE FRESH-PAGE SETTLE (the verifier's round-1 FAIL, fixed at the
## root): a fresh page lands with the scroll at the TOP and its seeded
## focus ON-SCREEN, computed from the page's REAL layout — never from a
## fixed deferred frame. On a page turn the dying previous page's cards
## and the container's QUEUED re-sort out-last a single deferral: the
## seeded first card still holds its PRE-SORT rect (down where the
## container stacked it under the dying page), so an ensure reading that
## rect scrolls the ledger to its maximum and the re-sort then strands
## the focused card fully above the viewport (probe-measured: scroll
## 354/354 at a 934px band, card0 at global y −204). This awaits the
## layout the scroll math actually consumes, re-asserts the top, and only
## then grabs focus — the focus-ensure that follows reads REAL rects.
func settle_seed(seed: Control) -> void:
	if seed == null or _scroll == null:
		return
	var token := _bind_token
	await _await_real_layout(token)
	if token != _bind_token or not is_inside_tree() \
			or not is_instance_valid(seed) or not seed.is_visible_in_tree():
		return  # a newer bind (or a close) superseded this settle
	_scroll.scroll_vertical = 0
	seed.grab_focus()


## Wait until the layout the scroll math consumes is REAL, not assumed:
## VALIDATED, never a fixed frame count. The post-sort invariant: the
## page's first entry sits AT THE TOP of the scroll's content (pre-sort
## it holds a position below the dying page's cards), and the geometry
## stamp holds still across two consecutive frames (a re-sort still in
## flight moves it). Bounded — a degenerate layout degrades to the old
## fixed-defer behavior rather than blocking the seed forever.
func _await_real_layout(token: int) -> void:
	var prev := ""
	for i in 12:
		await get_tree().process_frame
		if token != _bind_token or not is_inside_tree():
			return
		var stamp := _geometry_stamp()
		if _layout_is_real() and stamp == prev:
			return
		prev = stamp


## The first entry sits at the very top of the scroll's content: true
## only once the container's re-sort has repositioned the freshly-bound
## cards (the stale geometry the round-1 ensure consumed fails this —
## the first card reads hundreds of px down the content).
func _layout_is_real() -> bool:
	if _entries.is_empty():
		return true  # nothing to reposition (the empty state / chips page)
	if _scroll == null or not is_inside_tree():
		return false
	var first := _entries[0] as Control
	if not is_instance_valid(first) or first.size.y < 1.0:
		return false
	var content_y := first.global_position.y - _scroll.global_position.y \
		+ float(_scroll.scroll_vertical)
	return absf(content_y) <= 0.5


## The geometry the scroll math consumes, as a comparable stamp: the
## scroll offset, the content's combined minimum, the viewport, and the
## first card's laid rect.
func _geometry_stamp() -> String:
	if _scroll == null or _list == null:
		return "null"
	var parts: Array[String] = [
		"%d" % _scroll.scroll_vertical,
		"%.2f" % _list.get_combined_minimum_size().y,
		"%.2f" % _scroll.size.y,
	]
	if not _entries.is_empty() and is_instance_valid(_entries[0]):
		var first := _entries[0] as Control
		parts.append("%.2f %.2f" % [first.global_position.y, first.size.y])
	return " ".join(parts)


## The entry cards in ledger order (tests + focus seeding).
func entries() -> Array[Control]:
	return _entries.duplicate()


func chips() -> Array[ActionFan.ActionChip]:
	return _chips.duplicate()


func scroll() -> ScrollContainer:
	return _scroll


## The empty-state rows (the first-run print).
func empty_rows() -> Array[Control]:
	return _empty_rows.duplicate()


## All focusable rows in ledger order — entries first (the walkable
## ring), then the chips (the verbs at the foot).
func focusables() -> Array[Control]:
	var found: Array[Control] = []
	for card in _entries:
		found.append(card)
	for chip in _chips:
		found.append(chip)
	return found


## Entries per page for one design height (pure; the screen derives its
## page size at open, tests pin the mapping): enough wrapped entry cards
## to fill the band the fixed regions leave, clamped to a sane floor
## (never fewer than 3 — a one-entry page is a tease) and ceiling.
static func per_page_for_height(bounds_y: float) -> int:
	var fixed := TITLE_H + COUNT_H + LIVE_H + FOOTER_H + float(CHIP_COUNT) * CHIP_H \
		+ 2.0 * PAD + 2.0 * MARGIN
	return clampi(int((bounds_y - fixed) / 150.0), 3, 6)


# --- layout (pure statics) ----------------------------------------------------------------


func _relaid() -> void:
	if _title_label == null or size.x < 8.0 or size.y < 8.0:
		return
	# The page's real settled height (wrapped plates included): the list
	# band grows to its content up to the cap the rect math enforces.
	var list_height := 0.0
	if _list != null:
		list_height = _list.get_combined_minimum_size().y
	var rects := sheet_rects(size, list_height, maxi(1, _chips.size()))
	_sheet_rect = rects["sheet"]
	var list_h: float = rects["list_h"]
	var inner := Rect2(_sheet_rect.position + Vector2(PAD, PAD),
		_sheet_rect.size - Vector2(2.0 * PAD, 2.0 * PAD))
	_fit(_title_label, _row(inner, 0.0, TITLE_H))
	_fit(_count_label, _row(inner, TITLE_H, COUNT_H))
	var live_h := LIVE_H if _live_row.visible else 0.0
	if _live_row.visible:
		_fit(_live_row, _row(inner, TITLE_H + COUNT_H, live_h))
	_fit(_scroll, _row(inner, TITLE_H + COUNT_H + live_h, list_h))
	var list_top := TITLE_H + COUNT_H + live_h
	_fit(_footer_label, _row(inner, list_top + list_h, FOOTER_H))
	var chip_top := list_top + list_h + FOOTER_H
	for i in _chips.size():
		_fit(_chips[i], _row(inner, chip_top + float(i) * CHIP_H, CHIP_H))
	queue_redraw()


func _row(inner: Rect2, offset: float, height: float) -> Rect2:
	return Rect2(inner.position + Vector2(0.0, offset), Vector2(inner.size.x, height))


## The sheet's layout rects. The paper column is capped at
## SHEET_MAX_WIDTH, centered; the list band grows with the page's real
## content up to the height the bounds grant — a too-tall page SCROLLS
## inside its band (the caps keep every other region on the sheet).
## `chip_count` is the live verb count (a one-page ring prints only the
## back chip). Pure: same bounds + list height => same rects.
static func sheet_rects(bounds: Vector2, list_height: float, chip_count: int = CHIP_COUNT) -> Dictionary:
	var wide := minf(bounds.x - 2.0 * MARGIN, SHEET_MAX_WIDTH)
	var fixed := TITLE_H + COUNT_H + LIVE_H + FOOTER_H + float(maxi(1, chip_count)) * CHIP_H + 2.0 * PAD
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


## The render oracle: every printed plate on the sheet. Same view => same
## hash (the ledger is a function of the record, never of UI history).
func snapshot_hash() -> int:
	var h := 0x811C9DC5
	h = _mix(h, _title_label.text.hash())
	h = _mix(h, _count_label.text.hash())
	h = _mix(h, _live_label.text.hash())
	h = _mix(h, int(_live_row.visible))
	h = _mix(h, _footer_label.text.hash())
	for card in _entries:
		h = _mix(h, (card as EntryCard).snapshot_hash())
	for row in _empty_rows:
		h = _mix(h, String(row.get("text")).hash())
	for chip in _chips:
		h = _mix(h, String(chip.action.get("label", "")).hash())
		h = _mix(h, int(chip.action.get("enabled", false)))
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- the entry card --------------------------------------------------------------------------

## EntryCard — one past hand as a small spread card (T-UI-08): cut-stock
## paper, the leader's plate (name + epithet, wrapped at the presenter's
## budget), the regime rule in the regime's OWN second ink + crest slot,
## the outcome seal (RuleMark in the seal's line form + print mark +
## duration), the army at the end, and the legacy that hand banked.
## Focusable (the ring is walkable): focus re-prints the baseline in red
## — the same misregistration focus grammar as every card.
class EntryCard:
	extends Control

	const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")
	const FACE_SLOT_SCENE := preload("res://ui/theme/face_slot.tscn")
	const PAD := 10.0
	## The crest plate's size (the outer class's CREST_SIZE, repeated: an
	## inner class does not see the outer scope's consts).
	const CREST_SIZE := 56.0
	## Fixed minimum width — wide enough that every plate (regime row,
	## seal row, wrapped name) lays out at a sane width from the FIRST
	## pass (the deterministic-minimum rule above).
	const CARD_MIN_WIDTH := 380.0

	## LineClass -> RuleMark.RuleForm (the shared grammar; the seal's line
	## form IS the outcome's state carrier — form, never hue).
	const CLASS_TO_FORM: Dictionary = {
		Inks.LineClass.PLAIN: 0,
		Inks.LineClass.WARN: 1,
		Inks.LineClass.STRIKE: 2,
		Inks.LineClass.VICTORY: 3,
	}

	var _model := {}
	var _name_label: Label
	var _role_label: Label
	var _crest: TextureRect
	var _regime_row: HBoxContainer
	var _regime_rule: Control
	var _regime_label: Label
	var _seal_row: HBoxContainer
	var _seal_rule: Control
	var _seal_label: Label
	var _seal_line: Label
	var _army_label: Label
	var _bank_label: Label

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var column := VBoxContainer.new()
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		column.offset_left = PAD
		column.offset_right = -PAD
		column.offset_top = PAD - 2.0
		column.offset_bottom = -PAD + 2.0
		column.add_theme_constant_override("separation", 3)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(column)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(head)
		var head_column := VBoxContainer.new()
		head_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_column.add_theme_constant_override("separation", 1)
		head_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(head_column)
		_name_label = Label.new()
		_name_label.theme_type_variation = &"CardTitle"
		_name_label.add_theme_font_size_override("font_size", TypeScale.scaled(21))
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# MIN-WIDTH FLOOR (probe-measured): an autowrap label's first-pass
		# minimum can collapse toward zero, and a wrap evaluated at ~1px
		# width reports a thousands-px MINIMUM HEIGHT that poisons the
		# card's minimum. The floor makes the wrap always evaluate at a
		# sane plate width (the presenter shapes the text to match).
		_name_label.custom_minimum_size = Vector2(160.0, 0.0)
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head_column.add_child(_name_label)
		_role_label = Label.new()
		_role_label.theme_type_variation = &"RoleLine"
		_role_label.add_theme_font_size_override("font_size", TypeScale.scaled(15))
		_role_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_role_label.custom_minimum_size = Vector2(160.0, 0.0)
		_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head_column.add_child(_role_label)
		_crest = FACE_SLOT_SCENE.instantiate()
		_crest.custom_minimum_size = Vector2(CREST_SIZE, CREST_SIZE)
		_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_crest.focus_mode = Control.FOCUS_NONE
		_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_crest)

		_regime_row = HBoxContainer.new()
		_regime_row.add_theme_constant_override("separation", 8)
		_regime_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_regime_row)
		_regime_rule = RULE_SCENE.instantiate()
		_regime_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_regime_rule.focus_mode = Control.FOCUS_NONE
		_regime_row.add_child(_regime_rule)
		_regime_label = Label.new()
		_regime_label.theme_type_variation = &"PipLabel"
		# EXPAND_FILL, like the seal line: a clip_text label's MINIMUM
		# width excludes its text (probe-measured: without the expand it
		# collapses to ~1px next to the rule and clips everything).
		_regime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_regime_label.clip_text = true
		_regime_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_regime_row.add_child(_regime_label)

		_seal_row = HBoxContainer.new()
		_seal_row.add_theme_constant_override("separation", 8)
		_seal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_seal_row)
		_seal_rule = RULE_SCENE.instantiate()
		_seal_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_seal_rule.focus_mode = Control.FOCUS_NONE
		_seal_row.add_child(_seal_rule)
		_seal_label = Label.new()
		_seal_label.theme_type_variation = &"PipLabel"
		_seal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_seal_row.add_child(_seal_label)
		_seal_line = Label.new()
		_seal_line.theme_type_variation = &"RoleLine"
		_seal_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_seal_line.clip_text = true
		_seal_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_seal_row.add_child(_seal_line)

		_army_label = Label.new()
		_army_label.theme_type_variation = &"RoleLine"
		_army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_army_label.custom_minimum_size = Vector2(200.0, 0.0)
		_army_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_army_label)

		_bank_label = Label.new()
		_bank_label.theme_type_variation = &"RoleLine"
		_bank_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		_bank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_bank_label)

	func _get_minimum_size() -> Vector2:
		## DETERMINISTIC from the model, NEVER delegated to the live label
		## minimums (probe-measured: an autowrap label's first-pass minimum
		## height evaluates its wrap at the pre-layout width and reports a
		## thousands-px height that poisons the card — the card then never
		## re-shrinks without a re-sort). The row arithmetic below follows
		## the same budgets the presenter shaped the text to; the fixed
		## width floor guarantees every plate lays out at a sane width, so
		## the inner VBoxes never see a degenerate wrap either.
		if _model.is_empty():
			return Vector2(CARD_MIN_WIDTH, float(Inks.TOUCH_GRIP_MIN))
		var name_rows: int = (_model["name_lines"] as Array).size()
		var role_rows := String(_model["role_line"]).split("\n").size()
		var army_rows := String(_model.get("army_wrapped", "")).split("\n").size()
		var head := maxf(CREST_SIZE + 8.0, name_rows * 30.0 + role_rows * 21.0)
		var height := head + 24.0 + 24.0 + army_rows * 21.0 + 19.0 + 15.0 + 2.0 * PAD + 8.0
		return Vector2(CARD_MIN_WIDTH, maxf(float(Inks.TOUCH_GRIP_MIN), height))

	func _draw() -> void:
		## Cut-stock paper + ink border (the ledger's card grammar), and
		## focus as the red misregistered baseline (form, not hue).
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Inks.PAPER_DIM)
		draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
		if has_focus():
			draw_line(Vector2(12.0, size.y - 8.0), Vector2(size.x - 12.0, size.y - 8.0), Inks.RED, 3.0, true)
			draw_line(Vector2(15.0, size.y - 6.0), Vector2(size.x - 9.0, size.y - 6.0), Inks.RED, 3.0, true)

	func bind(model: Dictionary) -> void:
		_model = model.duplicate(true)
		var regime: Dictionary = model["regime"]
		var seal: Dictionary = model["seal"]
		var victory := int(seal["class"]) == Inks.LineClass.VICTORY
		var seal_ink := Inks.INK if victory else Inks.RED
		_model["army_wrapped"] = ChroniclePresenter.wrap_army_line(String(model["army_line"]))
		_name_label.text = " · ".join(model["name_lines"])
		_name_label.add_theme_color_override("font_color", Inks.INK)
		_role_label.text = String(model["role_line"])
		_crest.set("face_key", regime["crest_key"])
		_regime_rule.set("rule_ink", regime["ink"])
		var regime_name := String(regime["name"])
		if regime_name.is_empty():
			regime_name = String(regime["id"])
		_regime_label.text = "under %s · hand %d" % [regime_name, int(model["run"])]
		_regime_label.add_theme_color_override("font_color", regime["ink"])
		_seal_rule.set("form", int(CLASS_TO_FORM[int(seal["class"])]))
		_seal_rule.set("rule_ink", seal_ink)
		_seal_label.text = String(seal["mark"])
		_seal_label.add_theme_color_override("font_color", seal_ink)
		_seal_line.text = "%s after %s" % [String(seal["word"]), String(model["duration_line"])]
		_seal_line.add_theme_color_override("font_color", Inks.INK)
		_army_label.text = String(_model["army_wrapped"])
		_bank_label.text = "%s legacy banked by this hand" % Inks.abbreviate_amount(int(model["score"]))
		queue_redraw()

	func model() -> Dictionary:
		return _model

	func snapshot_hash() -> int:
		var h := 0x811C9DC5
		h = _mix(h, _name_label.text.hash())
		h = _mix(h, _role_label.text.hash())
		h = _mix(h, _regime_label.text.hash())
		h = _mix(h, String(StringName(String(_crest.get("face_key")))).hash())
		h = _mix(h, _seal_label.text.hash())
		h = _mix(h, _seal_line.text.hash())
		h = _mix(h, _army_label.text.hash())
		h = _mix(h, _bank_label.text.hash())
		return h

	static func _mix(hash_value: int, value: int) -> int:
		var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
		x = (x * 16777619) & 0xFFFFFFFF
		x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return (x * 16777619) & 0xFFFFFFFF
