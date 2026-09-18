## HowToScreen — "How to Play", the printed primer (the tutorial's
## pamphlet half; Daredevil + Prof X lane).
##
## THE GOAL comes first ("Grow the conspiracy until your knights are
## many and armed — then storm the castle."), then the table: what the
## cards are, what the player does, THE EDGES — the line-form legend
## taught with LIVE EXAMPLES (three real card frames: solid ready /
## dashed work-in-hand / struck lost), the stores, the Watchful Eye,
## and the long game (legacy + escalation), one line each. All the
## world's grammar, all the sim's own facts — the pamphlet cannot lie
## about the game it teaches.
##
## Composed like the chronicle's siblings: PAPER over a veiled table
## (never modal chrome) — by the Spread's header verb, by the title
## card's chip, and ONCE on the first fresh boot as the OFFER (a small
## paper with two verbs: read the pamphlet, or "I know this table").
## The offer is answered exactly once; both answers persist through the
## META domain (the spread owns the flag; the screen emits and moves).
##
## INPUT PARITY (Daredevil): touch (chip presses, drag-scroll),
## keyboard (arrows walk the section headings — focus-driven scroll;
## Enter activates the focused chip; Esc closes), pad (d-pad walks, A
## activates, B closes). Back is accepted from anywhere on the paper.
extends Control

## The paper folded away / the offer answered (the composer owns the
## table again, and the once-only flag).
signal closed()
## The offer's verb landed: p_read true = open the pamphlet, false =
## "I know this table" (the composer marks the answered flag either way).
signal offer_answered(p_read: bool)

const SHEET_SCRIPT := preload("res://ui/screens/howto/howto_sheet.gd")

enum State { CLOSED, OFFER, OPEN }

## The veil's opacity over the table beneath (every full-rect paper's
## candle-lit rule).
const VEIL_ALPHA := 0.90

var host: GameHost
var state: int = State.CLOSED

## Instrumentation (tests assert the open/offer contract).
var stats := {
	&"opens": 0,
	&"offers": 0,
	&"answered": 0,
}

var _veil: ColorRect
var _sheet: SHEET_SCRIPT
var _offer: OfferPanel
var _view := {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_sheet = SHEET_SCRIPT.new()
	_sheet.name = "HowToSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	_sheet.back_pressed.connect(close)
	_offer = OfferPanel.new()
	_offer.name = "HowToOffer"
	_offer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_offer.visible = false
	add_child(_offer)
	_offer.read_pressed.connect(_on_read)
	_offer.decline_pressed.connect(_on_decline)


# --- open / close / offer ----------------------------------------------------------------


## Open the pamphlet (the title chip, the header verb).
func open(p_host: GameHost) -> void:
	host = p_host
	state = State.OPEN
	visible = true
	stats[&"opens"] += 1
	_veil.color = Color(Inks.ground_for(_regime_id(), Inks.Phase.RECRUITING), VEIL_ALPHA)
	_sheet.visible = true
	_offer.visible = false
	_sheet.bind(view_for())
	_sheet.seed_focus()


## The FIRST-FRESH-BOOT offer: a small paper, two verbs, once.
func offer(p_host: GameHost) -> void:
	host = p_host
	state = State.OFFER
	visible = true
	stats[&"offers"] += 1
	_veil.color = Color(Inks.ground_for(_regime_id(), Inks.Phase.RECRUITING), VEIL_ALPHA)
	_sheet.visible = false
	_offer.visible = true
	_offer.bind(view_for())
	_offer.seed_focus()


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	visible = false
	_sheet.visible = false
	_offer.visible = false
	closed.emit()


func is_open() -> bool:
	return state != State.CLOSED


## The bound view model (tests read the mapped data).
func view() -> Dictionary:
	return _view


## The composed pamphlet sheet (tests + the capture hook).
func sheet() -> SHEET_SCRIPT:
	return _sheet


func offer_panel() -> OfferPanel:
	return _offer


func _regime_id() -> StringName:
	if host == null:
		return &""
	if host.is_run_running():
		return host.run().regime_id()
	if not host.meta.chronicle.is_empty():
		return StringName(String(host.meta.chronicle[host.meta.chronicle.size() - 1].get("regime", "")))
	return &""


func _on_read() -> void:
	stats[&"answered"] += 1
	offer_answered.emit(true)
	open(host)


func _on_decline() -> void:
	stats[&"answered"] += 1
	offer_answered.emit(false)
	close()


# --- the pure view ------------------------------------------------------------------------


## The whole pamphlet as data. Pure: the copy deck's own lines (rotor 0
## — static content, the legacy-tree precedent). Same table => same view.
static func view_for() -> Dictionary:
	var copy: CopyTable = Inks.pack().copy
	return {
		"title": "HOW TO PLAY",
		"goal_line": CopyDeck.line(copy, &"howto_goal", 0),
		"table_lines": [
			CopyDeck.line(copy, &"howto_table_1", 0),
			CopyDeck.line(copy, &"howto_table_2", 0),
		],
		"edge_rows": [
			{"form": Inks.EdgeForm.SOLID,
				"caption": CopyDeck.line(copy, &"howto_edges_solid", 0)},
			{"form": Inks.EdgeForm.DASHED,
				"caption": CopyDeck.line(copy, &"howto_edges_dashed", 0)},
			{"form": Inks.EdgeForm.STRUCK,
				"caption": CopyDeck.line(copy, &"howto_edges_struck", 0)},
		],
		"stores_line": CopyDeck.line(copy, &"howto_stores", 0),
		"eye_line": CopyDeck.line(copy, &"howto_eye", 0),
		"long_lines": [
			CopyDeck.line(copy, &"howto_legacy", 0),
			CopyDeck.line(copy, &"howto_escalation", 0),
		],
		"offer_line": CopyDeck.line(copy, &"howto_offer", 0),
	}


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state == State.CLOSED:
		return
	if event.is_action_pressed(&"back"):
		if state == State.OFFER:
			_on_decline()  # back on the offer IS "I know this table"
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	# PAD PARITY: a non-positional primary the engine did not route to
	# the focused chip as ui_accept activates it here (the papers' shared
	# fallback — acting on the paper is reachable identically from touch,
	# keyboard, and pad, exactly once each).
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		if activate_focused():
			get_viewport().set_input_as_handled()


## Activate the chip that holds focus, if any (the pad fallback).
func activate_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and _sheet != null and _sheet.is_ancestor_of(focus):
		(focus as BaseButton).pressed.emit()
		return true
	if focus is BaseButton and _offer != null and _offer.is_ancestor_of(focus):
		(focus as BaseButton).pressed.emit()
		return true
	return false


# --- the offer panel ------------------------------------------------------------------------


## OfferPanel — the first-fresh-boot offer: one clerk's line on a small
## paper, two verbs. The choice-card's stock, parked center (the
## blockquote's grammar — it never touches the table's edges).
class OfferPanel:
	extends Control

	signal read_pressed()
	signal decline_pressed()

	const PANEL_WIDTH := 480.0
	const PAD := 14.0
	const LINE_H := 64.0
	const CHIP_H := 48.0

	var _line_label: Label
	var _read_chip: ActionFan.ActionChip
	var _decline_chip: ActionFan.ActionChip
	var _panel_rect := Rect2()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_line_label = Label.new()
		_line_label.theme_type_variation = &"ChronicleLine"
		_line_label.add_theme_color_override("font_color", Inks.INK)
		_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_line_label)
		_read_chip = ActionFan.ActionChip.new()
		_read_chip.action = {
			"id": &"read", "label": "Read the pamphlet", "command": &"",
			"subject": &"", "value": 0, "enabled": true, "reason": "",
			"signature": true,
		}
		_read_chip.custom_minimum_size = Vector2(216.0, CHIP_H)
		_read_chip.pressed.connect(func() -> void: read_pressed.emit())
		add_child(_read_chip)
		_decline_chip = ActionFan.ActionChip.new()
		_decline_chip.action = {
			"id": &"decline", "label": "I know this table", "command": &"",
			"subject": &"", "value": 0, "enabled": true, "reason": "",
			"signature": false,
		}
		_decline_chip.custom_minimum_size = Vector2(216.0, CHIP_H)
		_decline_chip.pressed.connect(func() -> void: decline_pressed.emit())
		add_child(_decline_chip)

	func bind(view: Dictionary) -> void:
		_line_label.text = String(view["offer_line"])
		_relaid()

	func line_label() -> Label:
		return _line_label

	func read_chip() -> ActionFan.ActionChip:
		return _read_chip

	func decline_chip() -> ActionFan.ActionChip:
		return _decline_chip

	## Seed focus on the READ verb (the offer's generous default —
	## declining stays one press away, the two-step rule inverted: the
	## default act opens the help, never ends it).
	func seed_focus() -> void:
		_read_chip.grab_focus.call_deferred()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_relaid()

	func _draw() -> void:
		if _panel_rect.size.x < 4.0:
			return
		var rect := _panel_rect.grow(-2.0)
		draw_rect(rect, Inks.PAPER)
		draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
		var c := 9.0
		draw_line(Vector2(rect.position.x, rect.position.y + c), Vector2(rect.position.x + c, rect.position.y), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.position.y), Vector2(rect.end.x, rect.position.y + c), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x + c, rect.end.y), Inks.PAPER, 5.0, true)
		draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 5.0, true)

	func _relaid() -> void:
		if _line_label == null or size.x < 8.0 or size.y < 8.0:
			return
		var f := TypeScale.factor()
		var wide := minf(PANEL_WIDTH * f, size.x - 24.0)
		var height := (LINE_H + CHIP_H + 3.0 * PAD) * f
		_panel_rect = Rect2(Vector2((size.x - wide) * 0.5, (size.y - height) * 0.5),
			Vector2(wide, height))
		var inner := _panel_rect.grow(-PAD * f)
		_line_label.position = inner.position
		_line_label.size = Vector2(inner.size.x, LINE_H * f)
		_read_chip.position = Vector2(inner.position.x, inner.end.y - CHIP_H * f)
		_read_chip.size = Vector2(216.0 * f, CHIP_H * f)
		_decline_chip.position = Vector2(inner.end.x - 216.0 * f, inner.end.y - CHIP_H * f)
		_decline_chip.size = Vector2(216.0 * f, CHIP_H * f)
		queue_redraw()
