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

## Width kept CLEAR of cards at the table's right edge (design units) —
## the armed Watchful Eye's strike lane (finishing refinement #3: the
## perch must not crowd the fan's end card when the telegraph arms, so the
## table itself makes way). 0.0 (the default and the resting state) lays
## out across the FULL width — every pre-existing rect is untouched by
## construction (the additive-param pattern the header insert follows).
@export var right_reserve: float = 0.0:
	set(value):
		if right_reserve != value:
			right_reserve = maxf(0.0, value)
			queue_sort()

## Card width / height. A card is a tall plate, not a square.
const CARD_ASPECT := 0.68

## Tallest a card may print even in a roomy layout (design units) — one
## lone card must not become the whole table.
const MAX_CARD_HEIGHT := 330.0

## The narrowest card the grid grants when the cell has width to spare
## (design units — readability r2): 132px of plate + the frame's insets,
## the width the longest authored role captions print whole at ≥18px
## ("drills in the yard" measures 123 at 18). Mid-density rosters widen
## to it; the densest cells (5 columns) stay cell-bound (density — the
## plates' 12px floor + wrap + grow carry those).
const MIN_READABLE_CARD_W := 164.0

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
## `right_reserve` (finishing refinement #3, additive; default 0.0) narrows
## the width the grid centers within — cards stay clear of the table's
## right lane. With 0.0 the rects are EXACTLY the pre-refinement values.
static func stacked_layout(count: int, bounds: Vector2, columns: int = 2,
		space: Vector2 = Vector2(20, 20), right_reserve: float = 0.0) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return rects
	var cols := maxi(1, columns)
	var rows := maxi(1, int(ceil(float(count) / float(cols))))
	var usable_w := maxf(1.0, bounds.x - right_reserve)
	var cell_w := maxf(1.0, (usable_w - float(cols - 1) * space.x) / float(cols))
	var cell_h := maxf(1.0, (bounds.y - float(rows - 1) * space.y) / float(rows))
	var card := _card_size_for_cell(cell_w, cell_h)
	var grid_w := float(cols) * card.x + float(cols - 1) * space.x
	var grid_h := float(rows) * card.y + float(rows - 1) * space.y
	var origin := Vector2((usable_w - grid_w) * 0.5, (bounds.y - grid_h) * 0.5)
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
## `right_reserve` (finishing refinement #3, additive; default 0.0) narrows
## the width the fan centers within — the end card never enters the table's
## right lane. With 0.0 the entries are EXACTLY the pre-refinement values.
static func panoramic_layout(count: int, bounds: Vector2, space: Vector2 = Vector2(20, 20),
		arc_depth: float = 24.0, fan_degrees: float = 10.0,
		right_reserve: float = 0.0) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return entries
	var usable_bounds := Vector2(maxf(1.0, bounds.x - right_reserve), bounds.y)
	var card_h := maxf(1.0, minf(MAX_CARD_HEIGHT, usable_bounds.y - arc_depth - 2.0 * space.y - ROTATION_SLACK))
	var card := Vector2(card_h * CARD_ASPECT, card_h)
	if count == 1:
		entries.append({
			"rect": Rect2(Vector2((usable_bounds.x - card.x) * 0.5, usable_bounds.y - space.y - card.y), card),
			"rotation": 0.0,
		})
		return entries
	var usable := usable_bounds.x - 2.0 * space.x
	var step: float = minf(card.x + space.x, (usable - card.x) / float(count - 1))
	var span := card.x + float(count - 1) * step
	var x0 := (usable_bounds.x - span) * 0.5
	var half := float(count - 1) * 0.5
	for i in count:
		var t := (float(i) - half) / half  # -1 .. 1 across the fan
		var lift := arc_depth * (1.0 - t * t)  # center cards highest
		entries.append({
			"rect": Rect2(
				Vector2(x0 + float(i) * step, usable_bounds.y - space.y - card.y - lift),
				card),
			"rotation": t * fan_degrees,
		})
	return entries


## Card size for a grid cell: height-honest (the cell's height, capped),
## width the aspect implies — clamped by the cell — then THE PLATES'
## FLOOR (readability r2): a mid-density cell's aspect-true width can
## starve the name/role plates into sub-floor steps ("drills in the
## yard" fitted to 12px at the audited 13-card roster), so when the cell
## has width to spare the card widens to the readable grant
## (MIN_READABLE_CARD_W) and the plates keep their air. Height never
## grows past the cell (the grid's honest rows contract).
static func _card_size_for_cell(cell_w: float, cell_h: float) -> Vector2:
	var card_h := minf(cell_h, MAX_CARD_HEIGHT)
	var card_w := card_h * CARD_ASPECT
	if card_w > cell_w:
		card_w = cell_w
		card_h = card_w / CARD_ASPECT
	var wanted := minf(cell_w, MIN_READABLE_CARD_W)
	if card_w < wanted and card_h >= float(Inks.TOUCH_GRIP_MIN * 2):
		card_w = wanted  # never widen a sliver cell — the grip owns those
	return Vector2(card_w, card_h)


# --- Container contract ------------------------------------------------------------


func _get_minimum_size() -> Vector2:
	## Honest floor: the grid of card minimums (STACKED) or the
	## fully-packed fan span (PANORAMIC — the layout overlap-packs to a
	## single card's width, so the floor is one grip card, not the loose
	## span: a 30-offer pile's 55%-advance span exceeded the window and
	## the root grew the whole screen past it, shearing the table off the
	## screen — the r2 audit's landscape find), plus the standing right
	## reserve — parents sizing below this would clip cards under the
	## touch grip.
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
		# THE GRID'S MINIMUM IS THE GRIP, NOT THE PLATES (readability r3):
		# a grown plate's honest minimum is honored by the GRID'S OWN
		# LAYOUT — the row gap absorbs a few px of growth — never by the
		# minimum chain, where it would inflate the slot's granted band,
		# re-pitch the column ladder (5 columns -> 4 -> more rows -> more
		# growth) and shear the last row off the design (the dense
		# estate's windowed runaway). Capped at the touch grip — the r2
		# floor of record — so parents never squeeze cards under the grip
		# and never grant the runaway either.
		var grip := float(Inks.TOUCH_GRIP_MIN * 2.0)
		return Vector2(
			float(cols) * minf(cell.x, grip) + float(cols - 1) * space.x + right_reserve,
			float(rows) * minf(cell.y, grip) + float(rows - 1) * space.y)
	return Vector2(cell.x + right_reserve,
		cell.y + arc_depth + ROTATION_SLACK)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_apply_layout(size)


func _apply_layout(bounds: Vector2) -> void:
	# T-UI-03 verifier nit (a), folded in at T-UI-04: a sort firing with
	# children present but degenerate bounds (observed in headless quit
	# teardown) printed out-of-bounds errors — a zero-size table simply
	# has no rects to hand out; the next real sort lays the cards.
	if bounds.x <= 0.5 or bounds.y <= 0.5:
		return
	var controls: Array[Control] = _card_children()
	if mode == Mode.STACKED:
		var rects := stacked_layout(controls.size(), bounds, columns, space, right_reserve)
		for i in controls.size():
			var card := controls[i]
			card.rotation = 0.0
			fit_child_in_rect(card, rects[i])
	else:
		var entries := panoramic_layout(controls.size(), bounds, space, arc_depth, fan_degrees, right_reserve)
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
