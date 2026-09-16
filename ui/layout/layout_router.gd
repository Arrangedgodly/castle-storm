## LayoutRouter — orientation detection + topology swap (T-UI-02, per R3).
##
## Watches the DESIGN aspect (the viewport's visible rect under
## canvas_items+expand is design units, not pixels) and swaps
## PortraitSlot/LandscapeSlot visibility when the aspect genuinely
## re-topologizes, with HYSTERESIS on two axes (the R3 prescription):
##   1. DEADBAND — aspect inside [band.x, band.y] (default 0.95..1.05)
##      NEVER swaps: square-ish resizes hold the current topology;
##   2. DWELL — an out-of-band aspect must PERSIST `dwell_seconds`
##      before the swap lands: flapping (window-drag chatter, sensor
##      jitter) resets the candidate and never swaps.
##
## Detection is belt-and-braces: the Viewport.size_changed signal arms the
## candidate instantly, and a cheap per-frame poll re-reads the aspect so
## the router still swaps if the signal under-fires under stretch (the
## R3-recorded reliability risk — probed in the T-UI-02 smoke suite,
## size_changed_count() is the evidence channel).
##
## FOCUS (Daredevil parity — "controller players must not lose their
## place"): every swap (a) records the focused control's focus_id meta,
## (b) hides the outgoing slot AND disables focus on its focusables (a
## hidden node loses focus, and Tab chains must not route through
## invisible layouts), (c) deferred-grab_focus() on the INCOMING slot's
## control with the SAME focus_id — find_focusable_element() is the
## equivalence query. No prior focus -> the first focusable is seeded
## (a screen must seed focus itself). Focus held OUTSIDE the slots (a
## debug panel) is left exactly where it is.
extends Node
class_name LayoutRouter

## Orientation vocabulary. PORTRAIT first: its aspect test is < band.x.
## Named ScreenOrientation: plain `Orientation` collides with a native
## global type in 4.7's analyzer (the inner enum then fails to unify
## with annotations).
enum ScreenOrientation { PORTRAIT, LANDSCAPE }

## Emitted after a swap applied (not on seed/force of the same value).
signal orientation_changed(new_orientation: ScreenOrientation)

## Sentinel: current focus lives outside both slots — do not touch it.
const FOCUS_OUTSIDE_SLOTS := "<<outside-slots>>"

## The two slots (OrientationSlot roots). Auto-discovered when unset:
## the parent's children named *Portrait*/*Landscape* win.
@export var portrait_slot: NodePath
@export var landscape_slot: NodePath

## Hysteresis deadband: aspect < band.x -> PORTRAIT candidate,
## aspect > band.y -> LANDSCAPE candidate, inside -> keep current.
@export var hysteresis_band: Vector2 = Vector2(0.95, 1.05)

## How long an out-of-band aspect must persist before the swap lands.
@export var dwell_seconds: float = 0.25

var _current: ScreenOrientation = ScreenOrientation.LANDSCAPE
var _candidate: int = -1
var _candidate_age := 0.0
var _forced: int = -1
var _size_changed_fired := 0

## Test seam: when set, aspect_probe.call() -> float replaces the
## viewport read (pure hysteresis tests without a live tree).
var aspect_probe: Callable

var _portrait: Control
var _landscape: Control


func _ready() -> void:
	_resolve_slots()
	if is_inside_tree():
		get_viewport().size_changed.connect(_on_size_changed)
	# Seed from the live aspect (no dwell on first appearance): square or
	# unknown defaults to LANDSCAPE — the desktop/Deck first target.
	_current = orientation_for_aspect(_current_aspect(), ScreenOrientation.LANDSCAPE, hysteresis_band) as ScreenOrientation
	_apply_orientation(_current, "")


## Late binding for code-built screens (ResponsiveScreen builds the slots
## after this node's _ready has run): applies the current orientation to
## the newly bound pair immediately, seeding focus on the visible one.
func bind_slots(portrait: Control, landscape: Control) -> void:
	_portrait = portrait
	_landscape = landscape
	_apply_orientation(_current, "")


func _process(delta: float) -> void:
	poll(delta)


## One detection step. Reads the aspect, applies deadband + dwell, lands
## the swap when the candidate has aged past dwell_seconds. Exposed so
## tests can step time deterministically.
func poll(delta: float = 0.0) -> void:
	if _forced != -1:
		return
	var desired := orientation_for_aspect(_current_aspect(), _current, hysteresis_band) as ScreenOrientation
	if desired == _current:
		_candidate = -1
		_candidate_age = 0.0
		return
	if desired != _candidate:
		_candidate = desired
		_candidate_age = 0.0
		return
	_candidate_age += delta
	if _candidate_age >= dwell_seconds:
		var target := desired
		var focus_id := _focus_id_of_current_focus()
		_candidate = -1
		_candidate_age = 0.0
		_apply_orientation(target, focus_id)


## Pure decision: which orientation does this aspect want, given the
## current one? Inside the band the answer is "keep current" — the
## deadband half of the hysteresis. NOTE: int at this static seam — a
## static function resolving this class's own enum qualifies it
## (LayoutRouter.Orientation) and 4.7's analyzer then fails to unify
## that with the plain enum type; int is the same wire format.
static func orientation_for_aspect(aspect: float, current: int,
		band: Vector2 = Vector2(0.95, 1.05)) -> int:
	if aspect < band.x:
		return ScreenOrientation.PORTRAIT
	if aspect > band.y:
		return ScreenOrientation.LANDSCAPE
	return current


## Force a topology (debug panel / tests): applies immediately, ignoring
## aspect changes until clear_forced(). Passing -1 is a no-op.
func force_orientation(forced: int) -> void:
	if forced < 0:
		return
	_forced = forced
	_candidate = -1
	_candidate_age = 0.0
	_apply_orientation(forced as ScreenOrientation, _focus_id_of_current_focus())


## Return to automatic detection (the next out-of-band aspect swaps
## after the normal dwell).
func clear_forced() -> void:
	_forced = -1
	_candidate = -1
	_candidate_age = 0.0


## Current query API.
func current_orientation() -> ScreenOrientation:
	return _current


func is_portrait() -> bool:
	return _current == ScreenOrientation.PORTRAIT


func is_forced() -> bool:
	return _forced != -1


## The live design rectangle (design units under canvas_items+expand).
func design_size() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
	var size := get_viewport().get_visible_rect().size
	return size


## How many times the Viewport's size_changed fired since _ready — the
## smoke-test evidence channel for the R3 signal-reliability risk.
func size_changed_count() -> int:
	return _size_changed_fired


## Equivalence query: the focusable Control in `slot`'s subtree carrying
## focus_id == focus_id. Empty focus_id -> the FIRST focusable in tree
## order (the seed rule). Not found -> null. Deliberately does NOT filter
## by visibility, and treats a focus-disabled control (this router sets
## FOCUS_NONE on the inactive slot, remembering the original mode) by its
## REMEMBERED mode — the equivalent control lives in the slot that is
## hidden by definition at mapping time.
func find_focusable_element(slot: Control, focus_id: String) -> Control:
	var first: Control = null
	var queue: Array[Node] = [slot]
	while not queue.is_empty():
		var node := queue.pop_front() as Control
		if node == null:
			continue
		if _participates_in_focus(node):
			if first == null:
				first = node
			if not focus_id.is_empty() and String(node.get_meta(&"focus_id", "")) == focus_id:
				return node
		for child in node.get_children():
			queue.append(child)
	return first if focus_id.is_empty() else null


## Focus participation, robust to this router's own disabling: a control
## the router disabled keeps its original mode in a meta.
func _participates_in_focus(node: Control) -> bool:
	if node.focus_mode != Control.FOCUS_NONE:
		return true
	return node.has_meta(&"layout_router_original_focus_mode") \
		and int(node.get_meta(&"layout_router_original_focus_mode")) != Control.FOCUS_NONE


# --- internals ----------------------------------------------------------------------


func _resolve_slots() -> void:
	if portrait_slot != null and not portrait_slot.is_empty():
		_portrait = get_node(portrait_slot) as Control
	if landscape_slot != null and not landscape_slot.is_empty():
		_landscape = get_node(landscape_slot) as Control
	if (_portrait == null or _landscape == null) and get_parent() != null:
		for child in get_parent().get_children():
			if child is Control:
				if _portrait == null and String(child.name).to_lower().contains("portrait"):
					_portrait = child
				elif _landscape == null and String(child.name).to_lower().contains("landscape"):
					_landscape = child


func _current_aspect() -> float:
	if aspect_probe.is_valid():
		return float(aspect_probe.call())
	if is_inside_tree():
		var size := get_viewport().get_visible_rect().size
		return size.x / maxf(size.y, 1.0)
	return 1.0


func _on_size_changed() -> void:
	_size_changed_fired += 1
	poll(0.0)


func _slot_for(orientation: ScreenOrientation) -> Control:
	return _portrait if orientation == ScreenOrientation.PORTRAIT else _landscape


func _apply_orientation(new_orientation: ScreenOrientation, focus_id: String) -> void:
	var changed := new_orientation != _current
	_current = new_orientation
	if _portrait == null or _landscape == null:
		if changed:
			orientation_changed.emit(_current)
		return
	var incoming := _slot_for(new_orientation)
	var outgoing := _slot_for(ScreenOrientation.LANDSCAPE if new_orientation == ScreenOrientation.PORTRAIT else ScreenOrientation.PORTRAIT)
	outgoing.visible = false
	_set_slot_focus_enabled(outgoing, false)
	incoming.visible = true
	_set_slot_focus_enabled(incoming, true)
	if changed:
		orientation_changed.emit(_current)
	_restore_focus.call_deferred(incoming, focus_id)


## Disable/enable focus on a slot's focusables. Original modes are kept in
## a meta so repeated swaps are exact, and the incoming slot always ends
## with focus ENABLED (never a dead screen). Note the two branches: a
## focus-enabled node is REMEMBERED-then-cleared when disabling; a
## focus-disabled node is restored from its memory when enabling (its
## current FOCUS_NONE is this router's own doing, not the control's).
func _set_slot_focus_enabled(slot: Control, enabled: bool) -> void:
	var queue: Array[Node] = [slot]
	while not queue.is_empty():
		var node := queue.pop_front() as Control
		if node != null and node != slot:
			if node.focus_mode != Control.FOCUS_NONE:
				if not node.has_meta(&"layout_router_original_focus_mode"):
					node.set_meta(&"layout_router_original_focus_mode", node.focus_mode)
				if not enabled:
					node.focus_mode = Control.FOCUS_NONE
			elif enabled and node.has_meta(&"layout_router_original_focus_mode"):
				node.focus_mode = int(node.get_meta(&"layout_router_original_focus_mode"))
		for child in node.get_children():
			queue.append(child)


func _focus_id_of_current_focus() -> String:
	if not is_inside_tree():
		return ""
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return ""
	if _portrait != null and not _portrait.is_ancestor_of(focused) \
			and _landscape != null and not _landscape.is_ancestor_of(focused):
		return FOCUS_OUTSIDE_SLOTS
	return String(focused.get_meta(&"focus_id", ""))


func _restore_focus(slot: Control, focus_id: String) -> void:
	if slot == null or not is_inside_tree() or focus_id == FOCUS_OUTSIDE_SLOTS:
		return
	var target := find_focusable_element(slot, focus_id)
	if target == null:
		# No equivalent (e.g. fewer cards in the incoming slot): seed the
		# first focusable — a swap must never strand the player focusless.
		target = find_focusable_element(slot, "")
	if target != null:
		target.grab_focus()
