## CardSpread — the responsive card arrangement (T-UI-02, per R3).
##
## The custom Container R3 prescribes for "a fan/arc cannot be expressed by
## stock containers": one scripted spread that re-topologizes between the
## design brief's two layouts —
##   STACKED   (portrait): cards in a centered grid of `columns` columns,
##              each card sized to its cell preserving the card aspect;
##   PANORAMIC (landscape): a panoramic arc along the table's width —
##              cards advance by a full gap when there is room and overlap
##              like a held fan when there is not, with a gentle lift and
##              rotation per card (the table's fan, not a grid on its side).
##
## The layout math is PURE and static (stacked_layout / panoramic_layout)
## so tests pin the arrangement for N cards in both topologies without a
## live tree; _sort_children applies the rects via fit_child_in_rect, the
## documented custom-container recipe. Minimum size reports the honest
## floor (grid of card minimums / overlap-packed span) so parents can
## never squeeze cards under the touch grip.
##
## Focus (Daredevil parity): geometric auto-neighbors track the reflowed
## positions by construction, but the spread ALSO wires explicit
## left/right/next neighbors by card index after every sort — a spatial
## layout where left-pad means left-card, never an engine guess (the
## gui_navigation docs' warned-against path).
extends Container
class_name CardSpread

## Which topology the spread arranges in.
enum Mode {
	STACKED,    ## Portrait: centered grid, `columns` wide.
	PANORAMIC,  ## Landscape: panoramic arc / row with overlap.
}

## Topology selector. Set by the OrientationSlot / LayoutRouter.
@export var mode: Mode = Mode.STACKED:
	set(value):
		if mode != value:
			mode = value
			queue_sort()

## Grid column count for STACKED mode (clamped >= 1 when read).
@export var columns: int = 2:
	set(value):
		if columns != value:
			columns = value
			queue_sort()

## Card separation: grid gaps in STACKED, gap+side margins in PANORAMIC
## (design units — the square 720 base maps 1:1 to dp).
@export var space: Vector2 = Vector2(20, 20):
	set(value):
		if space != value:
			space = value
			queue_sort()

## Card width / height. A card is a tall plate, not a square.
const CARD_ASPECT := 0.68

## Tallest a card may print even in a roomy layout (design units) — one
## lone card must not become the whole table.
const MAX_CARD_HEIGHT := 330.0

## Panoramic arc: lift of the center cards above the end cards, and the
## total rotation swing from end to center (degrees, per card at the ends).
@export var arc_depth: float = 24.0:
	set(value):
		if arc_depth != value:
			arc_depth = value
			queue_sort()

@export var fan_degrees: float = 10.0:
	set(value):
		if fan_degrees != value:
			fan_degrees = value
			queue_sort()

## Height reserve for the rotated bounding box in PANORAMIC (a rotated
## card's corners extend past its rect; the reserve keeps the fan inside
## the table at the default swing).
const ROTATION_SLACK := 36.0

## PANORAMIC minimum-size overlap: how far cards may pack when the table
## is too narrow for gaps (fraction of one card's width per advance).
const PANORAMA_MIN_ADVANCE := 0.55


## Convenience for the router/slots: STACKED == portrait.
func set_portrait(portrait: bool) -> void:
	mode = Mode.STACKED if portrait else Mode.PANORAMIC


func is_portrait() -> bool:
	return mode == Mode.STACKED


## Card at index (the i-th Control child), or null.
func card_at(index: int) -> Control:
	var controls: Array[Control] = _card_children()
	return controls[index] if index >= 0 and index < controls.size() else null


## Wire explicit focus neighbors by index (left/right in reading order;
## focus_next/previous the same chain). Top/bottom stay on geometric
## auto-neighbors — in a grid that vertical axis is genuinely spatial.
## Called after every sort; neighbors are NodePaths between siblings, so
## they survive re-sorts without re-wiring.
func wire_focus_neighbors() -> void:
	var controls: Array[Control] = _card_children()
	for i in controls.size():
		var card := controls[i]
		var prev: Control = controls[i - 1] if i > 0 else null
		var next: Control = controls[i + 1] if i + 1 < controls.size() else null
		if prev != null:
			card.focus_neighbor_left = card.get_path_to(prev)
			card.focus_previous = card.get_path_to(prev)
		if next != null:
			card.focus_neighbor_right = card.get_path_to(next)
			card.focus_next = card.get_path_to(next)


# --- the pure arrangement math (test-pinned for N cards, both topologies) --------


## STACKED: centered grid rects. Each card is sized to its cell preserving
## CARD_ASPECT, capped at MAX_CARD_HEIGHT; the grid centers in bounds.
static func stacked_layout(count: int, bounds: Vector2, columns: int = 2,
		space: Vector2 = Vector2(20, 20)) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return rects
	var cols := maxi(1, columns)
	var rows := maxi(1, int(ceil(float(count) / float(cols))))
	var cell_w := maxf(1.0, (bounds.x - float(cols - 1) * space.x) / float(cols))
	var cell_h := maxf(1.0, (bounds.y - float(rows - 1) * space.y) / float(rows))
	var card := _card_size_for_cell(cell_w, cell_h)
	var grid_w := float(cols) * card.x + float(cols - 1) * space.x
	var grid_h := float(rows) * card.y + float(rows - 1) * space.y
	var origin := Vector2((bounds.x - grid_w) * 0.5, (bounds.y - grid_h) * 0.5)
	for i in count:
		var col := i % cols
		var row := i / cols
		rects.append(Rect2(
			origin + Vector2(float(col) * (card.x + space.x), float(row) * (card.y + space.y)),
			card))
	return rects


## PANORAMIC: arc entries {"rect": Rect2, "rotation": float(deg)}.
## Cards bottom-align with a parabolic lift (center highest), advance by a
## full gap when the table has room and overlap when it does not; rotation
## swings +-fan_degrees across the fan. The span is centered in bounds.
static func panoramic_layout(count: int, bounds: Vector2, space: Vector2 = Vector2(20, 20),
		arc_depth: float = 24.0, fan_degrees: float = 10.0) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return entries
	var card_h := maxf(1.0, minf(MAX_CARD_HEIGHT, bounds.y - arc_depth - 2.0 * space.y - ROTATION_SLACK))
	var card := Vector2(card_h * CARD_ASPECT, card_h)
	if count == 1:
		entries.append({
			"rect": Rect2(Vector2((bounds.x - card.x) * 0.5, bounds.y - space.y - card.y), card),
			"rotation": 0.0,
		})
		return entries
	var usable := bounds.x - 2.0 * space.x
	var step: float = minf(card.x + space.x, (usable - card.x) / float(count - 1))
	var span := card.x + float(count - 1) * step
	var x0 := (bounds.x - span) * 0.5
	var half := float(count - 1) * 0.5
	for i in count:
		var t := (float(i) - half) / half  # -1 .. 1 across the fan
		var lift := arc_depth * (1.0 - t * t)  # center cards highest
		entries.append({
			"rect": Rect2(
				Vector2(x0 + float(i) * step, bounds.y - space.y - card.y - lift),
				card),
			"rotation": t * fan_degrees,
		})
	return entries


## Card size for a grid cell: aspect-true, height-capped, cell-clamped.
static func _card_size_for_cell(cell_w: float, cell_h: float) -> Vector2:
	var card_h := minf(cell_h, MAX_CARD_HEIGHT)
	var card_w := card_h * CARD_ASPECT
	if card_w > cell_w:
		card_w = cell_w
		card_h = card_w / CARD_ASPECT
	return Vector2(card_w, card_h)


# --- Container contract ------------------------------------------------------------


func _get_minimum_size() -> Vector2:
	## Honest floor: the grid of card minimums (STACKED) or the
	## overlap-packed span (PANORAMIC) — parents sizing below this would
	## clip cards under the touch grip.
	var controls: Array[Control] = _card_children()
	if controls.is_empty():
		return Vector2.ZERO
	var cell := Vector2.ZERO
	for card in controls:
		var ms: Vector2 = card.get_combined_minimum_size()
		cell = Vector2(maxf(cell.x, ms.x), maxf(cell.y, ms.y))
	if mode == Mode.STACKED:
		var cols := maxi(1, columns)
		var rows := maxi(1, int(ceil(float(controls.size()) / float(cols))))
		return Vector2(
			float(cols) * cell.x + float(cols - 1) * space.x,
			float(rows) * cell.y + float(rows - 1) * space.y)
	return Vector2(
		cell.x + float(controls.size() - 1) * cell.x * PANORAMA_MIN_ADVANCE,
		cell.y + arc_depth + ROTATION_SLACK)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_apply_layout(size)


func _apply_layout(bounds: Vector2) -> void:
	var controls: Array[Control] = _card_children()
	if mode == Mode.STACKED:
		var rects := stacked_layout(controls.size(), bounds, columns, space)
		for i in controls.size():
			var card := controls[i]
			card.rotation = 0.0
			fit_child_in_rect(card, rects[i])
	else:
		var entries := panoramic_layout(controls.size(), bounds, space, arc_depth, fan_degrees)
		for i in controls.size():
			var card := controls[i]
			var entry: Dictionary = entries[i]
			fit_child_in_rect(card, entry["rect"])
			card.pivot_offset = card.size * 0.5
			card.rotation_degrees = float(entry["rotation"])
	wire_focus_neighbors()


func _card_children() -> Array[Control]:
	var controls: Array[Control] = []
	for child in get_children():
		if child is Control:
			controls.append(child)
	return controls
