## LegacyScreen — the legacy deck's state machine + input (L1-C).
##
## Composed by the Spread as a full-rect child (the chronicle's own
## composition: paper over the veiled table while open — never modal
## chrome), and by the boot title card (the Legacy chip on the front
## door — the bank is why a player returns between sessions). The deck
## reads STRICTLY through the host's legacy query surfaces and WRITES
## through the ONE real command, `GameHost.unlock_purchase` — the
## loud-gate verb that validates, mutates the meta domain and persists
## it at once.
##
##   open    — the sheet binds the whole deck (the bank band, the four
##             families, every card's state by line form) and focus
##             seeds the FIRST AFFORDABLE CARD (the shop's own
##             recommendation — where a thumb lands); a fully locked
##             deck seeds its first card; an empty pack seeds the back
##             chip;
##   buy     — IT'S A SHOP, NOT A GAMBLE: selecting an affordable card
##             IS the one-step buy (no two-step confirm — the
##             odds-COMMIT grammar stays on the assault, where the die
##             is cast). The buy prints itself as the deck's own
##             chronicle line ("The Survivors remember <node>." — the
##             clerk's voice, CopyDeck), the bank and the tree update
##             LIVE, and focus stays on the card, now owned;
##   refused — a locked, unaffordable or kept card activated (the fan's
##             kept-consistent rule: pad players can walk onto a struck
##             card and read why) prints the REASON on the same paper —
##             never a popup, never a silent dead press;
##   closed  — `closed()` hands the table back (the composer returns
##             focus to the chip that opened it).
##
## MOUNT DISCIPLINE (L1-A): a purchase applies at the NEXT run start —
## the run system re-resolves the modifier bundle at every deal — so a
## deck opened over a LIVE hand prints that honestly ("A hand is live —
## new cards join the next hand.") instead of implying a live effect.
##
## INPUT PARITY (Daredevil): touch (card presses, chip press,
## drag-scroll), keyboard (arrows walk cards — focus-driven scroll;
## Enter activates the focused card or chip; Esc closes), pad (d-pad
## walks, A activates, B closes). Back is accepted from anywhere on the
## deck. The pad's primary fallback accepts any BaseButton in the sheet
## (cards nest in branch grids — the check is ancestral, the fan's
## rule).
class_name LegacyScreen
extends Control

## The deck folded away (the composer owns the table again).
signal closed()

const SHEET_SCRIPT := preload("res://ui/screens/legacy/legacy_sheet.gd")

enum State { CLOSED, OPEN }

## The veil's opacity over the table beneath (every full-rect paper's
## candle-lit rule: paper over a dimmed table, never bare paper).
const VEIL_ALPHA := 0.90

var host: GameHost
var state: int = State.CLOSED

## Instrumentation (tests assert the open/buy/refuse contract).
var stats := {
	&"opens": 0,
	&"purchases": 0,
	&"refusals": 0,
}

var _veil: ColorRect
var _sheet: LegacySheet
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
	_sheet.name = "LegacySheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	_sheet.card_pressed.connect(purchase)
	_sheet.back_chip().pressed.connect(close)


# --- open / close -----------------------------------------------------------------------


## Open the deck. The veil carries the live regime's ground tone when a
## hand is running, the last chronicle hand's when the table is clear,
## the neutral ground at the very first door (the chronicle screen's
## own fallback chain).
func open(p_host: GameHost) -> void:
	host = p_host
	state = State.OPEN
	visible = true
	stats[&"opens"] += 1
	var regime_id := host.run().regime_id() if host.is_run_running() else &""
	if regime_id == &"" and not host.meta.chronicle.is_empty():
		regime_id = StringName(String(host.meta.chronicle[host.meta.chronicle.size() - 1].get("regime", "")))
	_veil.color = Color(Inks.ground_for(regime_id, Inks.Phase.RECRUITING), VEIL_ALPHA)
	_bind()
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
func sheet() -> LegacySheet:
	return _sheet


## Determinism oracle: same tree + meta => same deck render.
func snapshot_hash() -> int:
	return _sheet.snapshot_hash()


func _bind() -> void:
	_view = LegacyPresenter.view(host)
	_sheet.bind(_view)


# --- the purchase verb (one step — it's a shop, not a gamble) --------------------------


## THE BUY PATH: an affordable card's press goes straight down the REAL
## host command (validate, mutate, persist at once); anything else
## prints its reason on the deck's own paper and mutates nothing. The
## refusal reasons follow the LegacySystem's decision order (owned,
## prerequisite, bank) so the paper never blames the bank for a
## prerequisite's refusal.
func purchase(id: StringName) -> void:
	if state != State.OPEN or host == null:
		return
	var node := host.unlock_node(id)
	if node == null:
		return  # the id left the tree mid-session — nothing to say
	var table: CopyTable = Inks.pack().copy
	if host.legacy.is_owned(id):
		stats[&"refusals"] += 1
		_sheet.set_print(CopyDeck.line(table, &"legacy_refusal_owned",
			host.meta.runs_recorded), Inks.LineClass.STRIKE)
		return
	for prerequisite in node.prerequisites:
		if not host.legacy.is_owned(prerequisite):
			stats[&"refusals"] += 1
			_sheet.set_print(CopyDeck.line(table, &"legacy_refusal_prereq",
				host.legacy.owned_count(), {
					"node": LegacyPresenter.node_display_name(host, prerequisite),
				}), Inks.LineClass.STRIKE)
			return
	if node.cost > host.unlock_bank():
		stats[&"refusals"] += 1
		_sheet.set_print(CopyDeck.line(table, &"legacy_refusal_short",
			node.cost, {"short": node.cost - host.unlock_bank()}),
			Inks.LineClass.STRIKE)
		return
	# One step: the real command, the real persistence.
	if host.unlock_purchase(id):
		stats[&"purchases"] += 1
		_sheet.set_print(CopyDeck.line(table, &"legacy_purchase_line",
			host.legacy.owned_count(), {"node": node.display_name}),
			Inks.LineClass.VICTORY)
		_bind()
		_sheet.settle_card(_sheet.card_for(id))
	else:
		# The loud gate refused underneath us (a state the reads above
		# already excluded — a raced bank, a churned tree): print the
		# shortfall shape honestly and rebind the deck to the truth.
		stats[&"refusals"] += 1
		_sheet.set_print(CopyDeck.line(table, &"legacy_refusal_short",
			node.cost, {"short": maxi(0, node.cost - host.unlock_bank())}),
			Inks.LineClass.STRIKE)
		_bind()


# --- focus -------------------------------------------------------------------------------


## Focus seeds the walk: the FIRST AFFORDABLE CARD (the shop's own
## recommendation), else the deck's first card, else the back chip (an
## empty pack) — a screen must seed itself, the router's rule. The seed
## SETTLES on the deck's REAL post-sort layout (the chronicle's round-1
## lesson).
func _seed_focus() -> void:
	var focusables := _sheet.focusables()
	if focusables.is_empty():
		return
	for card in _sheet.cards():
		if bool(card.model()["purchasable"]):
			_sheet.settle_seed(card)
			return
	_sheet.settle_seed(focusables[0])


# --- input ------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if state != State.OPEN:
		return
	if event.is_action_pressed(&"back"):
		close()
		get_viewport().set_input_as_handled()
		return
	# PAD PARITY: a non-positional primary the engine did not route to
	# the focused control as ui_accept activates it here (the ActionFan
	# fallback mirrored — buying is reachable identically from touch,
	# keyboard, and pad, exactly once each).
	if event.is_action_pressed(&"primary") and not (event is InputEventMouseButton) \
			and not (event is InputEventScreenTouch):
		if activate_focused():
			get_viewport().set_input_as_handled()


## Activate the sheet control that holds focus, if any (the pad
## fallback — a card OR the back chip). Cards nest inside branch grids,
## so the check is ANCESTRAL (the fan's rule, widened to the sheet's
## subtree). Returns true when something was activated.
func activate_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is BaseButton and _sheet.is_ancestor_of(focus):
		(focus as BaseButton).pressed.emit()
		return true
	return false
