## LegacySheet — the legacy DECK on the table (L1-C).
##
## THE FUTURE LEGACY TREE IS A GROWING DECK (design brief §3): this
## control is that deck, dealt as paper over the veiled table — the
## chronicle ledger's own composition rule, never modal chrome. The four
## branches print as FAMILIES (a branch crest plate + the CopyDeck
## branch name + a solid rule), each node one CARD in the world's
## grammar:
##
##   - the card's EDGE carries its state by LINE FORM (the raise, never
##     hue): owned SOLID + the ink-filled crest plate, affordable DASHED
##     (dashed-ready — the deck's in-hand form; the card is the enabled
##     verb and seeds focus), prereq-locked STRUCK + the "requires
##     <node>" note, unaffordable DASHED + the shortfall note;
##   - the card prints: name (display face), flavor line (the clerk's
##     italic, CopyDeck), the EFFECT in plain readable terms (derived
##     from the effect payload — "buildings cost 5% less"), and the cost
##     in legacy pips;
##   - the BANK band: the banked legacy pips + the total earned line +
##     the runs-recorded line;
##   - THE PRINT ROW: purchases and refusals print themselves here as
##     chronicle lines (double rule + "The Survivors remember <node>."
##     on a purchase; struck on a refusal) — states print themselves,
##     never popup chrome;
##   - THE MID-RUN NOTE: opened over a live hand, the deck prints the
##     honest mount rule — purchases take effect with the NEXT hand
##     (L1-A; the run system re-resolves the bundle at the next deal);
##   - THE EMPTY STATE: a fresh bank (first run unfinished) still sees
##     the whole deck — locked and dashed — under the CopyDeck "earn
##     your first legacy" line;
##   - the back verb (>= 48 grip, ActionFan's ActionChip unforked).
##
## NO-CLIP DISCIPLINE (the T-UI-06 lesson): the presenter shapes the
## flavor to the plate budget; these plates wrap at the same budget, the
## cards' minimums are deterministic from the model (never the live
## labels' asynchronous first pass), nothing clips.
##
## Determinism: bind(view) is a pure function of the presenter's view
## model; snapshot_hash() pins the render.
class_name LegacySheet
extends Control

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")
const FACE_SLOT_SCENE := preload("res://ui/theme/face_slot.tscn")
const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")

## Paper margins (design units; the chronicle sheet's own).
const MARGIN := 14.0
const PAD := 12.0
## The deck's readable column cap (the ledger rule: both topologies read
## the deck as a column, panoramic tables stay for cards).
const SHEET_MAX_WIDTH := 640.0
## Fixed region heights (design units; grown by the type factor where
## they carry text — the pure mapping's factor-scaled floor).
const TITLE_H := 54.0
const BANK_H := 26.0
const COUNT_H := 22.0
const PRINT_H := 50.0
const LIVE_H := 44.0
const CHIP_H := 48.0
const BACK_CHIP_COUNT := 1
## The branch families' inner separation.
const BRANCH_SEP := 16.0
const CREST_SIZE := 32.0

## LineClass -> RuleMark.RuleForm (the shared grammar; the print row's
## rule form IS the print's class — form, never hue).
const CLASS_TO_FORM: Dictionary = {
	Inks.LineClass.PLAIN: 0,
	Inks.LineClass.WARN: 1,
	Inks.LineClass.STRIKE: 2,
	Inks.LineClass.VICTORY: 3,
}

## A card was activated (the screen owns the purchase verb; refusals
## arrive here too — the card printed its own note, the print row says
## the rest).
signal card_pressed(id: StringName)

var _title_label: Label
var _bank_label: Label
var _count_label: Label
var _print_row: HBoxContainer
var _print_rule: Control
var _print_label: Label
var _live_row: HBoxContainer
var _live_rule: Control
var _live_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _cards: Array[LegacyCard] = []
var _chrome_rows: Array[Control] = []  # the empty state's two lines
var _back_chip: ActionFan.ActionChip
var _sheet_rect := Rect2()
## Bumped on every bind: a settle still awaiting a superseded layout
## aborts instead of grabbing focus for a deck that is gone.
var _bind_token := 0
## True until the first bind lands (the OPEN resets the scroll to the
## deck's head; a purchase's rebind deliberately does not — the reader's
## place holds, the settle contract re-seats focus on the bought card).
var _first_bind := true


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

	_bank_label = Label.new()
	_bank_label.theme_type_variation = &"RoleLine"
	_bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bank_label.clip_text = true
	_bank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bank_label)

	_count_label = Label.new()
	_count_label.theme_type_variation = &"PipLabel"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.clip_text = true
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)

	_live_row = HBoxContainer.new()
	_live_row.add_theme_constant_override("separation", 10)
	_live_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_rule = RULE_SCENE.instantiate()
	_live_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_live_rule.focus_mode = Control.FOCUS_NONE
	_live_rule.set("form", 1)  # RuleMark.RuleForm.DASHED — the mount rule is pending
	_live_rule.set("rule_ink", Inks.RED)
	_live_row.add_child(_live_rule)
	_live_label = Label.new()
	_live_label.theme_type_variation = &"ChronicleLine"
	_live_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_label.clip_text = true
	_live_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_row.add_child(_live_label)
	add_child(_live_row)

	_print_row = HBoxContainer.new()
	_print_row.add_theme_constant_override("separation", 10)
	_print_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_print_rule = RULE_SCENE.instantiate()
	_print_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_print_rule.focus_mode = Control.FOCUS_NONE
	_print_rule.set("rule_ink", Inks.INK)
	_print_row.add_child(_print_rule)
	_print_label = Label.new()
	_print_label.theme_type_variation = &"ChronicleLine"
	_print_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_print_label.clip_text = true
	_print_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_print_row.add_child(_print_label)
	add_child(_print_row)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(BRANCH_SEP))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)

	_back_chip = ActionFan.ActionChip.new()
	_back_chip.action = {
		"id": &"back", "label": "Back to the table", "command": &"", "subject": &"",
		"value": 0, "enabled": true, "reason": "", "signature": true,
	}
	_back_chip.custom_minimum_size = Vector2(196.0, CHIP_H)
	add_child(_back_chip)


# --- binding (pure in the view model) -----------------------------------------------------


## Bind the presenter's view. Same view => same render (snapshot_hash).
## The title's baked size re-applies on every bind — the press-room's
## live type-scale change re-flows a deck composed at another factor the
## next time it opens.
func bind(view: Dictionary) -> void:
	_bind_token += 1  # any settle still holding the previous deck aborts
	_title_label.add_theme_font_size_override("font_size", TypeScale.scaled(30))
	_title_label.text = String(view["title"])
	_title_label.add_theme_color_override("font_color", Inks.INK)
	_bank_label.text = "The bank holds %s legacy — %s earned in all." % [
		Inks.abbreviate_amount(int(view["bank"])),
		Inks.abbreviate_amount(int(view["total_earned"]))]
	_bank_label.add_theme_color_override("font_color", Inks.INK)
	_count_label.text = _count_line(view)
	_count_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	if bool(view["live_run"]):
		_live_row.visible = true
		_live_label.text = CopyDeck.line(Inks.pack().copy, &"legacy_midrun_note", 0)
		_live_label.add_theme_color_override("font_color", Inks.INK)
	else:
		_live_row.visible = false
		_live_label.text = ""
	_rebuild_deck(view)
	_wire_pad_column()
	_relaid()


func _count_line(view: Dictionary) -> String:
	var runs := int(view["runs_recorded"])
	var deck := "%d of %d cards kept" % [int(view["owned_count"]), int(view["node_count"])]
	match runs:
		0:
			return "no hands recorded · %s" % deck
		1:
			return "one hand recorded · %s" % deck
		_:
			return "%d hands recorded · %s" % [runs, deck]


## Rebuild the branch families to the view's deck. The OPEN lands at the
## deck's head (scroll to top); a PURCHASE's rebind keeps the scroll
## where the reader is — the cards' deterministic minimums keep the
## content height stable, and the settle contract re-seats focus on the
## bought card.
func _rebuild_deck(view: Dictionary) -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	for row in _chrome_rows:
		row.queue_free()
	_chrome_rows.clear()
	if _scroll != null and _first_bind:
		_scroll.scroll_vertical = 0
	_first_bind = false
	# The empty state's two lines head the deck (the deck still prints
	# beneath them — locked, dashed, all of it).
	if bool(view["empty"]):
		for line: Dictionary in view["empty_lines"]:
			var row: Control = CHRONICLE_SCENE.instantiate()
			row.set("line_class", int(line["class"]))
			row.set("text", String(line["text"]))
			row.set("ground", Inks.PAPER)
			_list.add_child(row)
			# The wrapped deck line has nothing to walk — chrome (the
			# chronicle's empty state does the same).
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.focus_mode = Control.FOCUS_NONE
			_chrome_rows.append(row)
	for branch: Dictionary in view["branches"]:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 8)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(block)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(head)
		var name_label := Label.new()
		name_label.theme_type_variation = &"CardTitle"
		name_label.add_theme_font_size_override("font_size", TypeScale.scaled(19))
		name_label.text = String(branch["name"])
		name_label.add_theme_color_override("font_color", Inks.INK)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(name_label)
		var rule := RULE_SCENE.instantiate()
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rule.focus_mode = Control.FOCUS_NONE
		rule.set("form", 0)  # SOLID — the family's settled crest rule
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(rule)
		var crest: Control = FACE_SLOT_SCENE.instantiate()
		crest.custom_minimum_size = Vector2(CREST_SIZE, CREST_SIZE)
		crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crest.focus_mode = Control.FOCUS_NONE
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crest.set("face_key", StringName(String(branch["crest_key"])))
		head.add_child(crest)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(grid)
		for node: Dictionary in branch["nodes"]:
			var card := LegacyCard.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.pressed.connect(func() -> void: card_pressed.emit(StringName(String(node["id"]))))
			grid.add_child(card)
			card.bind(node)
			card.focus_entered.connect(_ensure_card_visible.bind(card))
			_cards.append(card)


## THE PAD COLUMN: cards then the back verb as one cyclic vertical chain
## (the fan's own rule, vertical form — the chronicle sheet's
## discipline). Left/right stay free.
func _wire_pad_column() -> void:
	var column: Array[Control] = []
	column.append_array(_cards)
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


## THE FOCUS-SCROLL CONTRACT (Daredevil): a focused card is ALWAYS
## scrolled into view — pad/keyboard focus walks the deck, the paper
## follows. Deferred past the container's own child reposition; a card
## no longer in this bind never ensures.
func _ensure_card_visible(card: Control) -> void:
	if _scroll == null or card == null or not is_instance_valid(card):
		return
	if not _cards.has(card):
		return  # a newer bind superseded this card mid-settle
	_scroll.ensure_control_visible.call_deferred(card)


## THE OPEN SETTLE (the chronicle sheet's round-1 lesson): the deck
## opens at the TOP with the seeded focus ON-SCREEN, computed from the
## REAL post-sort layout — never from a fixed deferred frame.
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


## THE PURCHASE SETTLE: after a buy rebinds the deck, focus LANDS ON THE
## SAME CARD (now owned) without tearing the reader's place — the layout
## is awaited real, the card is ensured visible, then focus lands. Never
## a scroll-to-top on a mid-deck purchase.
func settle_card(card: Control) -> void:
	if card == null or _scroll == null:
		return
	var token := _bind_token
	await _await_real_layout(token)
	if token != _bind_token or not is_inside_tree() \
			or not is_instance_valid(card) or not card.is_visible_in_tree():
		return
	if not _cards.has(card):
		return
	_scroll.ensure_control_visible(card)
	card.grab_focus()


## Wait until the layout the scroll math consumes is REAL, not assumed:
## VALIDATED (the deck's first card sits at the top of the scroll's
## content) and stable across two consecutive frames. Bounded.
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


func _layout_is_real() -> bool:
	if _cards.is_empty():
		return true  # nothing to reposition (the empty chrome state)
	if _scroll == null or not is_inside_tree():
		return false
	var first := _cards[0] as Control
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
	if not _cards.is_empty() and is_instance_valid(_cards[0]):
		var first := _cards[0] as Control
		parts.append("%.2f %.2f" % [first.global_position.y, first.size.y])
	return " ".join(parts)


# --- the print row (states print themselves) -----------------------------------------------


## Print one line onto the deck's paper: the rule's FORM carries the
## class (double rule + ink for a purchase — the signature flourish;
## struck for a refusal), the clerk's italic carries the words.
func set_print(text: String, line_class: int) -> void:
	_print_rule.set("form", int(CLASS_TO_FORM.get(line_class, 0)))
	_print_rule.set("rule_ink", Inks.RED if line_class == Inks.LineClass.VICTORY else Inks.INK)
	_print_label.text = text
	_print_label.add_theme_color_override("font_color", Inks.INK)


func print_text() -> String:
	return _print_label.text


# --- accessors (tests + the screen) ---------------------------------------------------------


## The deck's cards in walk order (branch family order, tree order
## inside — the content author's deal).
func cards() -> Array[LegacyCard]:
	return _cards.duplicate()


## The card bound to one node id (null when the id left the deck).
func card_for(id: StringName) -> LegacyCard:
	for card in _cards:
		if StringName(String(card.model()["id"])) == id:
			return card
	return null


func back_chip() -> ActionFan.ActionChip:
	return _back_chip


func scroll() -> ScrollContainer:
	return _scroll


## The empty-state rows (the first-run print).
func chrome_rows() -> Array[Control]:
	return _chrome_rows.duplicate()


## All focusable controls in walk order — cards first (the deck), then
## the back verb at the foot.
func focusables() -> Array[Control]:
	var found: Array[Control] = []
	found.append_array(_cards)
	found.append(_back_chip)
	return found


## The fixed band heights at the current type factor (a text-carrying
## budget grows with the type — the blockquote principle). Pure GIVEN
## the factor.
static func fixed_band_h() -> float:
	return (TITLE_H + BANK_H + COUNT_H + PRINT_H + LIVE_H
		+ float(BACK_CHIP_COUNT) * CHIP_H) * TypeScale.factor()


# --- layout (pure statics) ----------------------------------------------------------------


func _relaid() -> void:
	if _title_label == null or size.x < 8.0 or size.y < 8.0:
		return
	var list_height := 0.0
	if _list != null:
		list_height = _list.get_combined_minimum_size().y
	var rects := sheet_rects(size, list_height, bool(_live_row.visible))
	_sheet_rect = rects["sheet"]
	var list_h: float = rects["list_h"]
	var inner := Rect2(_sheet_rect.position + Vector2(PAD, PAD),
		_sheet_rect.size - Vector2(2.0 * PAD, 2.0 * PAD))
	var top := 0.0
	_fit(_title_label, _row(inner, top, TITLE_H * TypeScale.factor()))
	top += TITLE_H * TypeScale.factor()
	_fit(_bank_label, _row(inner, top, BANK_H * TypeScale.factor()))
	top += BANK_H * TypeScale.factor()
	_fit(_count_label, _row(inner, top, COUNT_H * TypeScale.factor()))
	top += COUNT_H * TypeScale.factor()
	if _live_row.visible:
		_fit(_live_row, _row(inner, top, LIVE_H * TypeScale.factor()))
		top += LIVE_H * TypeScale.factor()
	_fit(_print_row, _row(inner, top, PRINT_H * TypeScale.factor()))
	top += PRINT_H * TypeScale.factor()
	_fit(_scroll, _row(inner, top, list_h))
	_fit(_back_chip, _row(inner, top + list_h, CHIP_H))
	queue_redraw()


func _row(inner: Rect2, offset: float, height: float) -> Rect2:
	return Rect2(inner.position + Vector2(0.0, offset), Vector2(inner.size.x, height))


## The sheet's layout rects. The paper column is capped at
## SHEET_MAX_WIDTH, centered; the deck band grows with the real content
## up to the height the bounds grant — a taller deck SCROLLS inside its
## band. Pure: same bounds + list height => same rects.
static func sheet_rects(bounds: Vector2, list_height: float, live_visible := true) -> Dictionary:
	var wide := minf(bounds.x - 2.0 * MARGIN, SHEET_MAX_WIDTH)
	var live_h := LIVE_H * TypeScale.factor() if live_visible else 0.0
	var fixed := (TITLE_H + BANK_H + COUNT_H + PRINT_H) * TypeScale.factor() + live_h \
		+ float(BACK_CHIP_COUNT) * CHIP_H + 2.0 * PAD
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


## The render oracle: every printed plate on the deck. Same view =>
## same hash (the deck is a function of the tree + meta, never of UI
## history).
func snapshot_hash() -> int:
	var h := 0x811C9DC5
	h = _mix(h, _title_label.text.hash())
	h = _mix(h, _bank_label.text.hash())
	h = _mix(h, _count_label.text.hash())
	h = _mix(h, _live_label.text.hash())
	h = _mix(h, int(_live_row.visible))
	h = _mix(h, _print_label.text.hash())
	for card in _cards:
		h = _mix(h, card.snapshot_hash())
	for row in _chrome_rows:
		h = _mix(h, String(row.get("text")).hash())
	h = _mix(h, String(_back_chip.action.get("label", "")).hash())
	return h


static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF


# --- the card ---------------------------------------------------------------------------------


## LegacyCard — one node of the growing deck (L1-C): cut-stock paper,
## the EDGE carrying the card's state by LINE FORM (solid owned /
## dashed in-hand / struck locked), the ink-filled crest plate on an
## owned card, the name plate, the flavor line, the effect in plain
## terms, the cost in legacy pips and the state note. Focusable (the
## deck is walkable): focus re-prints the baseline in red — the same
## misregistration grammar as every card. Activating a non-affordable
## card still speaks (the sheet's card_pressed reaches the screen, which
## prints the refusal — the fan's kept-consistent rule: a pad player
## can walk onto a struck card and READ why).
class LegacyCard:
	extends Button

	const PAD := 10.0
	## Fixed minimum width — the deterministic-minimum rule (an autowrap
	## label's first-pass minimum can collapse or poison; the card's
	## minimum is arithmetic from the model, never the live labels').
	const CARD_MIN_WIDTH := 258.0
	## The crest plate's size (the owned mark — ink-filled when kept).
	const CREST_PLATE := 16.0

	var _model := {}
	var _name_label: Label
	var _flavor_label: Label
	var _effect_label: Label
	var _cost_label: Label
	var _note_label: Label

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		custom_minimum_size = Vector2(CARD_MIN_WIDTH, float(Inks.TOUCH_GRIP_MIN))

	func _ready() -> void:
		var column := VBoxContainer.new()
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		column.offset_left = PAD
		column.offset_right = -PAD
		column.offset_top = PAD - 2.0
		column.offset_bottom = -PAD + 2.0
		column.add_theme_constant_override("separation", 3)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(column)

		_name_label = Label.new()
		_name_label.theme_type_variation = &"CardTitle"
		_name_label.add_theme_font_size_override("font_size", TypeScale.scaled(17))
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_name_label)

		_flavor_label = Label.new()
		_flavor_label.theme_type_variation = &"ChronicleLine"
		_flavor_label.add_theme_font_size_override("font_size", TypeScale.scaled(13))
		_flavor_label.add_theme_color_override("font_color", Inks.INK_SOFT)
		_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Wrap-width floor (the autowrap minimum-poison find): the wrap
		# always evaluates at a sane plate width.
		_flavor_label.custom_minimum_size = Vector2(190.0, 0.0)
		_flavor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_flavor_label)

		_effect_label = Label.new()
		_effect_label.theme_type_variation = &"RoleLine"
		_effect_label.add_theme_font_size_override("font_size", TypeScale.scaled(15))
		_effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_effect_label)

		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 8)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(footer)
		_cost_label = Label.new()
		_cost_label.theme_type_variation = &"RoleLine"
		_cost_label.add_theme_font_size_override("font_size", TypeScale.scaled(15))
		_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(_cost_label)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(spacer)
		_note_label = Label.new()
		_note_label.theme_type_variation = &"RoleLine"
		_note_label.add_theme_font_size_override("font_size", TypeScale.scaled(13))
		_note_label.clip_text = true
		_note_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(_note_label)

	## The card's minimum, DETERMINISTIC from the model (the EntryCard
	## rule — never the live labels' asynchronous first pass): Button's
	## native minimum wins over the _get_minimum_size virtual in Godot
	## 4.7 (probe-pinned: Control honors it, Button does not), so the
	## arithmetic lands through custom_minimum_size at bind instead —
	## same numbers, same determinism, one seam earlier. The flavor's
	## shaped rows drive the height the presenter shaped the text to.
	func _card_minimum() -> Vector2:
		if _model.is_empty():
			return Vector2(CARD_MIN_WIDTH, float(Inks.TOUCH_GRIP_MIN))
		var flavor_rows := String(_model["flavor"]).split("\n").size()
		var factor := TypeScale.factor()
		var height := 2.0 * PAD + 24.0 * factor + flavor_rows * 17.0 * factor \
			+ 19.0 * factor + 18.0 * factor + 8.0
		return Vector2(CARD_MIN_WIDTH, maxf(float(Inks.TOUCH_GRIP_MIN), height))

	func _draw() -> void:
		## Cut-stock paper + the edge whose FORM carries the card's state
		## (never hue), the crest plate (ink-filled when kept), and focus
		## as the red misregistered baseline.
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect.grow(-1.5), Inks.PAPER_DIM)
		var form := int(_model.get("edge_form", Inks.EdgeForm.SOLID))
		var border := rect.grow(-1.5)
		match form:
			Inks.EdgeForm.DASHED:
				# Dashed-ready / dashed-short: the ink runs out on the
				# long edges (the frame grammar's own cut).
				var dash := 8.0
				var gap := 5.0
				draw_dashed_line(border.position, Vector2(border.end.x, border.position.y), Inks.INK, 2.0, dash, gap)
				draw_dashed_line(Vector2(border.end.x, border.position.y), Vector2(border.end.x, border.end.y), Inks.INK, 2.0, dash, gap)
				draw_dashed_line(Vector2(border.end.x, border.end.y), Vector2(border.position.x, border.end.y), Inks.INK, 2.0, dash, gap)
				draw_dashed_line(Vector2(border.position.x, border.end.y), border.position, Inks.INK, 2.0, dash, gap)
			Inks.EdgeForm.STRUCK:
				# Locked: a thinned border plus the strike diagonal —
				# barred by the deck's own order.
				draw_rect(border, Inks.INK_SOFT, false, 1.5)
				draw_line(Vector2(8.0, size.y - 8.0), Vector2(size.x - 8.0, 8.0), Inks.INK_SOFT, 2.5, true)
			_:
				# Owned: SOLID — pressed into the deck, settled.
				draw_rect(border, Inks.INK, false, 2.0)
		# THE CREST PLATE (top-right): ink-filled when the card is kept,
		# an outlined plate while it is still paper.
		var owned := String(_model.get("state", "")) == LegacyPresenter.STATE_OWNED
		var plate := Rect2(Vector2(size.x - 8.0 - CREST_PLATE, 8.0), Vector2(CREST_PLATE, CREST_PLATE))
		if owned:
			draw_rect(plate, Inks.INK)
		else:
			draw_rect(plate, Inks.PAPER)
			draw_rect(plate.grow(-0.75), Inks.INK_SOFT, false, 1.5)
		# Focus ghost: the registration-miss mark (form, not hue).
		if has_focus():
			draw_line(Vector2(12.0, size.y - 8.0), Vector2(size.x - 12.0, size.y - 8.0), Inks.RED, 3.0, true)
			draw_line(Vector2(15.0, size.y - 6.0), Vector2(size.x - 9.0, size.y - 6.0), Inks.RED, 3.0, true)
		# The pressed card re-inks its edge (the press's impression).
		if pressed:
			draw_rect(border, Inks.INK, false, 2.0)

	func bind(model: Dictionary) -> void:
		_model = model.duplicate(true)
		custom_minimum_size = _card_minimum()
		if _name_label == null:
			return  # bind before _ready (composition order safety)
		_name_label.text = String(model["name"])
		_name_label.add_theme_color_override("font_color", Inks.INK)
		_flavor_label.text = String(model["flavor"])
		_effect_label.text = String(model["effect_line"])
		_effect_label.add_theme_color_override("font_color", Inks.INK)
		_cost_label.text = String(model["cost_line"])
		_cost_label.add_theme_color_override("font_color", Inks.INK)
		_note_label.text = String(model["note"])
		_note_label.add_theme_color_override("font_color",
			Inks.INK if String(model["state"]) == LegacyPresenter.STATE_AFFORDABLE else Inks.INK_SOFT)
		queue_redraw()

	func model() -> Dictionary:
		return _model

	func snapshot_hash() -> int:
		var h := 0x811C9DC5
		h = _mix(h, _name_label.text.hash())
		h = _mix(h, _flavor_label.text.hash())
		h = _mix(h, _effect_label.text.hash())
		h = _mix(h, _cost_label.text.hash())
		h = _mix(h, _note_label.text.hash())
		h = _mix(h, String(_model.get("state", "")).hash())
		return h

	static func _mix(hash_value: int, value: int) -> int:
		var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
		x = (x * 16777619) & 0xFFFFFFFF
		x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return (x * 16777619) & 0xFFFFFFFF
