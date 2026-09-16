## ChronicleScreen — the chronicle's state machine + input (T-UI-08).
##
## Composed by the Spread as a full-rect child (like the IntroScreen and
## the AssaultScreen: paper over the table while open — never modal
## chrome). Opened from the Spread's header affordance (the chronicle
## chip on the run's letterhead strip); the ledger reads STRICTLY from
## the meta domain (RunMeta.chronicle — the append-only record, never
## reconstructed here), so it is exactly as durable as the save: a
## save/load round-trip lands the same ring in the same order.
##
##   open    — the sheet binds page 0 (the newest hand leads) and focus
##             seeds the first ENTRY (the ring is the walkable thing;
##             the empty chronicle seeds the back chip — there is no
##             ring yet);
##   paging  — NEWER / OLDER chips turn pages (50 hands = 10 pages at
##             per-page 5); the focus re-seeds on the first entry of the
##             new page; within a page the scroll follows focus (the
##             sheet's contract);
##   closed  — `closed()` hands the table back (the Spread returns focus
##             to the chronicle chip that opened it).
##
## INPUT PARITY (Daredevil): touch (chip presses, drag-scroll), keyboard
## (arrows walk entries — focus-driven scroll; Enter activates the
## focused chip; Esc closes), pad (d-pad walks, A activates, B closes).
## Back is accepted from anywhere in the ledger.
##
## The live run is NEVER an entry (it is not chronicle until it ends) —
## the sheet prints it as its own dashed "live hand" strip instead.
extends Control

## The ledger folded away (the spread owns the table again).
signal closed()

const SHEET_SCRIPT := preload("res://ui/screens/chronicle/chronicle_sheet.gd")

enum State { CLOSED, OPEN }

## The veil's opacity over the table beneath (the intro packet's own
## candle-lit rule: paper over a dimmed table, never bare paper over a
## live one — the capture find: the rolling strip beneath printed
## through the ledger's margins and read as clutter).
const VEIL_ALPHA := 0.90

var host: GameHost
var state: int = State.CLOSED
## The current page (0 = newest; presenter re-clamps on bind).
var page := 0
## Entries per page. 0 = derive from the live design height at open (the
## sheet's pure mapping); tests pin it explicitly BEFORE open (the same
## seam discipline as the suspicion meter).
var per_page := 0

## Instrumentation (tests assert the paging + focus contract).
var stats := {
	&"opens": 0,
	&"page_turns": 0,
	&"refused_pages": 0,
}

var _veil: ColorRect
var _sheet: ChronicleSheet
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
	_sheet = SHEET_SCRIPT.new()
	_sheet.name = "ChronicleSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	_sheet.chip_pressed.connect(_on_chip)


# --- open / close -----------------------------------------------------------------------


## Open the ledger at the newest page. `p_router` is the spread's router
## (orientation seam: the sheet relays on swaps via NOTIFICATION_RESIZED
## of the full-rect control — the window drives both).
func open(p_host: GameHost, p_router: LayoutRouter) -> void:
	host = p_host
	_router = p_router
	state = State.OPEN
	page = 0
	visible = true
	stats[&"opens"] += 1
	# The veil carries the live regime's ground tone (candle-lit paper
	# over the table — the intro packet's composition rule).
	var regime_id := host.run().regime_id() if host.is_run_running() else &""
	if regime_id == &"" and not host.meta.chronicle.is_empty():
		regime_id = StringName(String(host.meta.chronicle[host.meta.chronicle.size() - 1].get("regime", "")))
	_veil.color = Color(Inks.ground_for(regime_id, Inks.Phase.RECRUITING), VEIL_ALPHA)
	# The page size derives from the live design height (the sheet's pure
	# mapping): more ledger per page on tall phones, fewer on the Deck's
	# 800 — never below the walkable floor of 3. An explicit per_page set
	# before open (the test seam) stands.
	if per_page <= 0:
		var design := size
		if _router != null and _router.design_size().x > 1.0:
			design = _router.design_size()
		per_page = ChronicleSheet.per_page_for_height(design.y)
	_bind()
	_seed_focus()


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	visible = false
	page = 0
	per_page = 0
	closed.emit()


func is_open() -> bool:
	return state != State.CLOSED


## The bound view model (tests read the mapped data).
func view() -> Dictionary:
	return _view


## The composed sheet (tests + the capture hook).
func sheet() -> ChronicleSheet:
	return _sheet


## Determinism oracle: same meta => same ledger render.
func snapshot_hash() -> int:
	return _sheet.snapshot_hash()


# --- paging -----------------------------------------------------------------------------


func _bind() -> void:
	_view = ChroniclePresenter.view(host, page, per_page)
	page = int(_view["page"])  # the presenter's clamp is the truth
	_sheet.bind(_view)


func turn_page(direction: int) -> void:
	## direction −1 = newer (toward page 0), +1 = older (down the ring).
	if state != State.OPEN:
		return
	var target := page + direction
	if target < 0 or target >= int(_view["page_count"]):
		stats[&"refused_pages"] += 1
		return  # the chip already printed its refusal
	page = target
	stats[&"page_turns"] += 1
	_bind()
	_seed_focus()


func _on_chip(id: StringName) -> void:
	match id:
		&"newer":
			turn_page(-1)
		&"older":
			turn_page(1)
		&"back":
			close()


## Focus seeds the walk: the first ENTRY of the page (the ring is the
## readable thing); the empty chronicle seeds the back chip — a screen
## must seed itself, the router's rule.
func _seed_focus() -> void:
	var focusables := _sheet.focusables()
	if not focusables.is_empty():
		focusables[0].grab_focus.call_deferred()


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return
	if event.is_action_pressed(&"back"):
		close()
		get_viewport().set_input_as_handled()
		return
	# PAD PARITY: a non-positional primary the engine did not route to the
	# focused chip as ui_accept activates it here (the ActionFan fallback
	# mirrored — acting on the ledger is reachable identically from touch,
	# keyboard, and pad, exactly once each).
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
