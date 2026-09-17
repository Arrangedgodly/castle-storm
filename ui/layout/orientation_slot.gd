## OrientationSlot — one orientation's topology (T-UI-02, per R3).
##
## A THIN container: it instances the SAME component scenes the other
## slot instances (TableGround, PipMark rail, CardSpread, ChronicleLine —
## the T-UI-01 theme grammar, no component is forked) and arranges them
## per the design brief §6 topology:
##   PORTRAIT  — pips as a TOP RAIL, stacked spread below it, chronicle
##               strip at the bottom;
##   LANDSCAPE — panoramic table filling the screen, chronicle strip
##               along the top (wide lines read wide), pips along the
##               BOTTOM EDGE.
## One script, two thin scenes (portrait_slot.tscn / landscape_slot.tscn);
## the LayoutRouter swaps their visibility. The slot is a dumb view —
## presenters bind state to whichever is visible.
##
## Layout is manual-rect on resize (the slot is a plain Control, so its
## children cannot use containers inside it): the math is the PURE static
## topology_rects(), test-pinned. Focus ids ("pip_i", "spread_card_i",
## "chronicle_i") are the router's equivalence keys across slots.
extends Control
class_name OrientationSlot

## Which topology this slot arranges. Set by the two thin scenes.
@export var portrait_topology: bool = true

## The run-header strip along the table's top edge (T-UI-03's run
## header: leader name + regime ink, then the ledger verbs row — the
## chronicle chip and the day-sheet chip, right-aligned). OFF by
## default — the T-UI-02 lab composition and its pinned topology tests
## are exactly unchanged (a zero-height header collapses topology_rects
## to the original rects). The Spread's thin slot scenes turn it on.
@export var show_header: bool = false

## Edge margin around the whole slot (design units; the ResponsiveScreen's
## safe-margin container adds the notch margins on top of this).
@export var edge_margin: float = 12.0

const GROUND_SCENE := preload("res://ui/theme/table_ground.tscn")
const PIP_SCENE := preload("res://ui/theme/pip_mark.tscn")
const CHRONICLE_SCENE := preload("res://ui/theme/chronicle_line.tscn")
const SPREAD_SCENE := preload("res://ui/layout/card_spread.tscn")

## Demonstration rail resources (the real Spread's presenter binds the
## live sim's resource read API to these pips in T-UI-03).
const RAIL_KINDS: Array[Inks.ResourceKind] = [
	Inks.ResourceKind.FOOD, Inks.ResourceKind.TIMBER, Inks.ResourceKind.IRON,
]

var _rail: HBoxContainer
var _spread: Control
var _chronicle: VBoxContainer
## The header COLUMN (the finishing refinement #2 restructure: the strip is
## a VBox — row 0 the letterhead (RunHeader), row 1 the ledger verbs
## (chronicle chip + day-sheet chip, right-aligned by the spread). The
## probe-measured letterhead row has no width to spare at the 720 portrait
## base (666 of 672 design units fixed); a second verb beside it would
## clip the leader's name to a stub. A column keeps every verb at a full
## grip AND widens the letterhead to the whole table.
var _header: VBoxContainer
var _ground: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ground := GROUND_SCENE.instantiate() as Control
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	_ground = ground

	if show_header:
		_header = VBoxContainer.new()
		_header.add_theme_constant_override("separation", 6)
		_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_header)

	_rail = HBoxContainer.new()
	_rail.add_theme_constant_override("separation", 18)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in RAIL_KINDS.size():
		var pip := PIP_SCENE.instantiate() as Control
		pip.set("kind", RAIL_KINDS[i])
		pip.set_meta(&"focus_id", "pip_%d" % i)
		_rail.add_child(pip)
	add_child(_rail)

	_spread = SPREAD_SCENE.instantiate() as Control
	_spread.set("mode", CardSpread.Mode.STACKED if portrait_topology else CardSpread.Mode.PANORAMIC)
	add_child(_spread)

	_chronicle = VBoxContainer.new()
	_chronicle.add_theme_constant_override("separation", 6)
	_chronicle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var line := CHRONICLE_SCENE.instantiate() as Control
		line.set_meta(&"focus_id", "chronicle_%d" % i)
		_chronicle.add_child(line)
	add_child(_chronicle)

	# Children's minimum sizes settle after one frame (PipMark/ChronicleLine
	# build their internals in _ready) — lay out then.
	layout_topology.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		layout_topology()


## Arrange the three regions per topology. Safe to call any time after the
## children exist; earlier calls are no-ops. (Safe-area insets arrive via
## the SlotHost's inset rect — the slot's own size already excludes them.)
func layout_topology() -> void:
	if _rail == null or _spread == null or _chronicle == null:
		return
	var header_size := Vector2.ZERO
	if _header != null:
		# FINISHING #6: the letterhead's name wraps, and its wrapped height
		# must be derived HERE — at the width THIS pass is about to fit —
		# never left over from an earlier layout at another width (the
		# spread's layout-hash determinism pin). The row owns the refit;
		# the slot owns the width.
		var before: Vector2 = _header.get_combined_minimum_size()
		if _header.get_child_count() > 0 and _header.get_child(0).has_method(&"refit"):
			_header.get_child(0).refit(maxf(0.0, size.x - 2.0 * edge_margin))
		header_size = _header.get_combined_minimum_size()
		# A refit that CHANGED the row's minimum must reach the host: the
		# sort that resized this slot read the stale minimum, and a HIDDEN
		# slot never gets a corrective pass of its own (hidden children
		# don't drive container minimums) — one deferred re-sort re-fits
		# both slots at the fresh budget. Converges: the next pass refits
		# to the same minimum and queues nothing.
		if not before.is_equal_approx(header_size) and get_parent() is Container:
			(get_parent() as Container).queue_sort()
	var rects := topology_rects(portrait_topology, size,
		_rail.get_combined_minimum_size(), _chronicle.get_combined_minimum_size(), edge_margin, header_size)
	_fit(_rail, rects["rail"])
	_fit(_spread, rects["spread"])
	_fit(_chronicle, rects["chronicle"])
	if _header != null:
		_fit(_header, rects["header"])


## The pure topology: rail/spread/chronicle rects for one orientation.
##   portrait  — rail top, spread middle, chronicle bottom;
##   landscape — chronicle top, spread middle, rail bottom (brief §6).
## `header_size` (T-UI-03, additive; default zero) inserts an optional
## header strip at the very top and shifts everything below it down — with
## a zero-height header the rects are EXACTLY the pre-T-UI-03 values (the
## T-UI-02 lab + its pinned tests are untouched by construction).
## The spread keeps a non-negative height at degenerate sizes (a clamp,
## not a clip: parents that respect the slot's minimum size never hit it).
static func topology_rects(portrait: bool, bounds: Vector2, rail_size: Vector2,
		chronicle_size: Vector2, margin: float, header_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var wide: float = maxf(0.0, bounds.x - 2.0 * margin)
	var header := Rect2(Vector2(margin, margin), Vector2(wide, header_size.y))
	# A zero-height header must shift NOTHING (backward-exact topology).
	var header_shift: float = 0.0 if header_size.y <= 0.0 else header_size.y + margin
	var rail := Rect2(Vector2(margin, margin + header_shift), Vector2(wide, rail_size.y))
	var chronicle := Rect2(
		Vector2(margin, bounds.y - margin - chronicle_size.y),
		Vector2(wide, chronicle_size.y))
	if portrait:
		var top: float = rail.position.y + rail.size.y + margin
		var bottom: float = chronicle.position.y - margin
		return {
			"header": header,
			"rail": rail,
			"spread": Rect2(Vector2(margin, top), Vector2(wide, maxf(0.0, bottom - top))),
			"chronicle": chronicle,
		}
	var flipped_chronicle := Rect2(Vector2(margin, margin + header_shift), Vector2(wide, chronicle_size.y))
	var flipped_rail := Rect2(
		Vector2(margin, bounds.y - margin - rail_size.y), Vector2(wide, rail_size.y))
	var top_l: float = flipped_chronicle.position.y + flipped_chronicle.size.y + margin
	var bottom_l: float = flipped_rail.position.y - margin
	return {
		"header": header,
		"rail": flipped_rail,
		"spread": Rect2(Vector2(margin, top_l), Vector2(wide, maxf(0.0, bottom_l - top_l))),
		"chronicle": flipped_chronicle,
	}


## The slot's own honest minimum: rail + spread floor + chronicle stacked
## (portrait) — the height every parent must grant for an unclipped table.
## An enabled header adds its FLOOR (finishing #6): the letterhead's name
## wraps, so its live height varies with the dealt name and the type
## factor — a live height here made the slot's minimum history-dependent,
## and a HIDDEN slot sized at a stale moment never got a corrective pass
## of its own (the layout-hash determinism pin caught exactly that). The
## layout still shifts everything by the header's REAL height
## (layout_topology reads the live combined minimum); this floor is the
## grant a parent must provide for the one-row letterhead's table.
func _get_minimum_size() -> Vector2:
	if _rail == null or _spread == null or _chronicle == null:
		return Vector2.ONE * Inks.TOUCH_GRIP_MIN
	var rail_s: Vector2 = _rail.get_combined_minimum_size()
	var chronicle_s: Vector2 = _chronicle.get_combined_minimum_size()
	var spread_s: Vector2 = _spread.get_combined_minimum_size()
	var header_h := 0.0
	if _header != null:
		header_h = float(Inks.TOUCH_GRIP_MIN) + 2.0 * edge_margin
	return Vector2(
		maxf(maxf(rail_s.x, spread_s.x), chronicle_s.x) + 2.0 * edge_margin,
		rail_s.y + spread_s.y + chronicle_s.y + header_h + 4.0 * edge_margin)


# --- presenter seams ----------------------------------------------------------------


## The table ground (T-UI-03 binds regime + phase here). Null before _ready.
func get_ground() -> Control:
	return _ground


## The run-header column (T-UI-03's letterhead row + the finishing
## refinement's ledger-verbs row), when this slot was built with
## `show_header`; null otherwise (the presenter falls back gracefully).
func get_header() -> VBoxContainer:
	return _header


## Add a card (any Control — a composed CardFrame in practice) to this
## slot's spread, with the router's focus-equivalence id.
func add_card(card: Control) -> void:
	card.set_meta(&"focus_id", "spread_card_%d" % card_count())
	_spread.add_child(card)
	_spread.queue_sort()


## Card count in this slot's spread.
func card_count() -> int:
	return _spread.get_child_count() if _spread != null else 0


## Card by index (equivalent index in the OTHER slot's spread is the
## equivalent card — the router's mapping).
func card_at(index: int) -> Control:
	return _spread.get_child(index) if _spread != null and index < _spread.get_child_count() else null


## The slot's spread (presenters rebind / retotal through this).
func get_spread() -> Control:
	return _spread


## The rail's pip by rail index.
func get_pip(index: int) -> Control:
	return _rail.get_child(index) if _rail != null and index < _rail.get_child_count() else null


## The chronicle row by index.
func get_chronicle_line(index: int) -> Control:
	return _chronicle.get_child(index) if _chronicle != null and index < _chronicle.get_child_count() else null


## All focusable descendants (focus_mode != NONE), tree order.
func focusables() -> Array[Control]:
	var found: Array[Control] = []
	_collect_focusables(self, found)
	return found


func _collect_focusables(node: Node, into: Array[Control]) -> void:
	if node is Control and (node as Control).focus_mode != Control.FOCUS_NONE:
		into.append(node)
	for child in node.get_children():
		_collect_focusables(child, into)


func _fit(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
