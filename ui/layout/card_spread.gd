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

## Width kept CLEAR of cards at the table's LEFT edge (design units) —
## the guided objective note's pinned lane (the tutorial upgrade: the
## clerk's note sits at the table edge and the table makes way, exactly
## the armed Eye's grammar mirrored). 0.0 keeps every pre-existing rect
## byte-identical (the same additive-param pattern as right_reserve).
@export var left_reserve: float = 0.0:
	set(value):
		if left_reserve != value:
			left_reserve = maxf(0.0, value)
			queue_sort()

## THE GATE LANE (the first-deal coverage fix): while the gate holds
## recruit offers, the spread splits into TWO bands — a straight GATE ROW
## across the top of the table (the offers, laid whole and unoverlapped;
## they are the newest paper and the table presents them as such) and the
## estate band beneath it (the same topology as always — grid in STACKED,
## the held-fan arc in PANORAMIC). WHY: in the single-band fan the
## panoramic overlap buried every plot card's center under its neighbor
## (measured on the real first deal: 3 offers + 4 staked plots at the
## 720x720 design left each plot a ~45px clickable strip, its center
## unclickable) — "the offers cover the Farm". The gate row keeps EVERY
## plot's interactive area clear of every offer at deal time, in BOTH
## topologies. 0.0 (the default and the offer-free state) lays out across
## the FULL band exactly as before — every pre-existing rect is untouched
## by construction (the additive-param pattern). The screen sets this
## from the view (offers stand -> lane on); cards mark themselves as
## gate paper with the `card_gate` meta (SpreadCards).
@export var gate_lane: float = 0.0:
	set(value):
		var v := maxf(0.0, value)
		if gate_lane != v:
			gate_lane = v
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

## THE GATE SPLIT (gate_lane > 0.0): the gate row's share of the band
## height (the estate keeps the rest and the row gap), clamped so both
## bands stay honest — the gate row never starves the estate below the
## touch grip, and never grows past the card max.
const GATE_SHARE := 0.42
const GATE_ROW_MIN := 96.0

## THE SPLIT'S DENSITY CEILING: the gate lane is the FIRST DEAL's grammar
## (a handful of cards, every plot unambiguous). Past this many cards on
## the table the single-band fan resumes — the designed held-fan overlap
## (its steps clear card centers at real widths, the r4-audited state)
## and the documented density wall. The screen applies the threshold;
## this const is the shared rule of record.
const GATE_SPLIT_MAX_CARDS := 12

## The estate band's readable width floor (the stacked grid's
## MIN_READABLE_CARD_W rule, mirrored for the split's shorter fan):
## below this width the role captions shrink under the 16px print floor
## (the audit's TINY bar) — the band's cards widen to the grant, the
## held-fan advance absorbs the difference as overlap.
const GATE_ESTATE_MIN_W := 120.0


## The gate split's pure geometry: {gate: Rect2, estate: Rect2} — the gate
## row across the band's top, the estate in the remainder, one row gap
## between. Deliberately reads ONLY the band bounds (never the children's
## minimums, never the factor): any layout-output fed back into the band
## heights turns every sort into a new minimum cascade — the layout never
## settles (the message-queue storm this fix's first draft died of). At
## 1.3x the short bands can under-grant the scaled plates; the r3 rule
## (the card grows to hold its print) absorbs that growth into the bands'
## lower padding. Pure: same band => same rects (test-pinned).
static func gate_split(bounds: Vector2, space: Vector2 = Vector2(20, 20)) -> Dictionary:
	var estate_floor := float(Inks.TOUCH_GRIP_MIN * 2.0)
	var gate_h := clampf((bounds.y - space.y) * GATE_SHARE,
		GATE_ROW_MIN, maxf(GATE_ROW_MIN, bounds.y - space.y - estate_floor))
	var estate_h := maxf(1.0, bounds.y - gate_h - space.y)
	return {
		"gate": Rect2(Vector2.ZERO, Vector2(bounds.x, gate_h)),
		"estate": Rect2(Vector2(0.0, gate_h + space.y), Vector2(bounds.x, estate_h)),
	}


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
## `right_reserve` / `left_reserve` (additive; default 0.0) narrow the
## width the grid centers within — cards stay clear of the reserved table
## lanes. With 0.0 the rects are EXACTLY the pre-refinement values.
static func stacked_layout(count: int, bounds: Vector2, columns: int = 2,
		space: Vector2 = Vector2(20, 20), right_reserve: float = 0.0,
		left_reserve: float = 0.0) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return rects
	var cols := maxi(1, columns)
	var rows := maxi(1, int(ceil(float(count) / float(cols))))
	var usable_w := maxf(1.0, bounds.x - right_reserve - left_reserve)
	var cell_w := maxf(1.0, (usable_w - float(cols - 1) * space.x) / float(cols))
	var cell_h := maxf(1.0, (bounds.y - float(rows - 1) * space.y) / float(rows))
	var card := _card_size_for_cell(cell_w, cell_h)
	var grid_w := float(cols) * card.x + float(cols - 1) * space.x
	var grid_h := float(rows) * card.y + float(rows - 1) * space.y
	var origin := Vector2(left_reserve + (usable_w - grid_w) * 0.5,
		(bounds.y - grid_h) * 0.5)
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
## `right_reserve` / `left_reserve` (additive; default 0.0) narrow the
## width the fan centers within — the end card never enters a reserved
## lane. With the defaults the entries are EXACTLY the pre-refinement
## values. `rotation_slack` (additive; default the authored const) is the
## height reserve for the rotated bounding box — the gate split's estate
## band passes a tightened share so a shorter band keeps honest cards
## (the arc scales with the band it lives in).
static func panoramic_layout(count: int, bounds: Vector2, space: Vector2 = Vector2(20, 20),
		arc_depth: float = 24.0, fan_degrees: float = 10.0,
		right_reserve: float = 0.0, left_reserve: float = 0.0,
		rotation_slack: float = ROTATION_SLACK, min_card_w: float = 0.0) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if count <= 0 or bounds.x <= 0.0 or bounds.y <= 0.0:
		return entries
	var usable_bounds := Vector2(
		maxf(1.0, bounds.x - right_reserve - left_reserve), bounds.y)
	var card_h := maxf(1.0, minf(MAX_CARD_HEIGHT,
		usable_bounds.y - arc_depth - 2.0 * space.y - rotation_slack))
	var card := Vector2(card_h * CARD_ASPECT, card_h)
	# THE READABLE GRANT (the stacked grid's r2 rule mirrored): a short
	# band's aspect-true card starves the role captions under the print
	# floor — widen to the grant when the band has width to spare (the
	# fan's advance absorbs it as overlap).
	if min_card_w > 0.0 and card.x < min_card_w:
		card.x = minf(min_card_w, usable_bounds.x)
	if count == 1:
		entries.append({
			"rect": Rect2(Vector2(left_reserve + (usable_bounds.x - card.x) * 0.5,
				usable_bounds.y - space.y - card.y), card),
			"rotation": 0.0,
		})
		return entries
	var usable := usable_bounds.x - 2.0 * space.x
	var step: float = minf(card.x + space.x, (usable - card.x) / float(count - 1))
	var span := card.x + float(count - 1) * step
	var x0 := left_reserve + (usable_bounds.x - span) * 0.5
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
	## touch grip. With the gate lane standing, the floor carries BOTH
	## bands (the gate row's grip row + the estate band's own floor).
	var controls: Array[Control] = _card_children()
	if controls.is_empty():
		return Vector2.ZERO
	var cell := Vector2.ZERO
	var gate_count := 0
	for card in controls:
		var ms: Vector2 = card.get_combined_minimum_size()
		cell = Vector2(maxf(cell.x, ms.x), maxf(cell.y, ms.y))
		if bool(card.get_meta(&"card_gate", false)):
			gate_count += 1
	var grip := float(Inks.TOUCH_GRIP_MIN * 2.0)
	# The gate row's floor is the grip row + the gap (the STACKED grid's
	# own grip rule); the estate band keeps its topology's usual floor.
	# Deliberately MINIMUM-BLIND (see gate_split): the floor must never
	# feed the children's minimums back into the band heights.
	var gate_floor: float = (grip + space.y) \
		if (gate_lane > 0.0 and gate_count > 0) else 0.0
	if mode == Mode.STACKED:
		var cols := maxi(1, columns)
		var estate_count := maxi(0, controls.size() - gate_count)
		var rows := maxi(1, int(ceil(float(estate_count) / float(cols))))
		# THE GRID'S MINIMUM IS THE GRIP, NOT THE PLATES (readability r3):
		# a grown plate's honest minimum is honored by the GRID'S OWN
		# LAYOUT — the row gap absorbs a few px of growth — never by the
		# minimum chain, where it would inflate the slot's granted band,
		# re-pitch the column ladder (5 columns -> 4 -> more rows -> more
		# growth) and shear the last row off the design (the dense
		# estate's windowed runaway). Capped at the touch grip — the r2
		# floor of record — so parents never squeeze cards under the grip
		# and never grant the runaway either. The gate row keeps the same
		# grip-based rule (its own layout caps its row honestly).
		gate_floor = (grip + space.y) if (gate_lane > 0.0 and gate_count > 0) else 0.0
		return Vector2(
			float(cols) * minf(cell.x, grip) + float(cols - 1) * space.x
				+ right_reserve + left_reserve,
			float(rows) * minf(cell.y, grip) + float(rows - 1) * space.y
				+ gate_floor)
	return Vector2(cell.x + right_reserve + left_reserve,
		cell.y + arc_depth + ROTATION_SLACK + gate_floor)


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
	if gate_lane > 0.0:
		_apply_gate_split(controls, bounds)
		wire_focus_neighbors()
		return
	if mode == Mode.STACKED:
		var rects := stacked_layout(controls.size(), bounds, columns, space, right_reserve, left_reserve)
		for i in controls.size():
			var card := controls[i]
			card.rotation = 0.0
			fit_child_in_rect(card, rects[i])
	else:
		var entries := panoramic_layout(controls.size(), bounds, space, arc_depth, fan_degrees, right_reserve, left_reserve)
		for i in controls.size():
			var card := controls[i]
			var entry: Dictionary = entries[i]
			fit_child_in_rect(card, entry["rect"])
			card.pivot_offset = card.size * 0.5
			card.rotation_degrees = float(entry["rotation"])
	wire_focus_neighbors()


## THE GATE SPLIT (gate_lane > 0.0): partition the children into gate
## paper (the `card_gate` meta — SpreadCards sets it from the view's
## offer kind) and the estate, lay the gate row STRAIGHT across the top
## band (the stacked single-row math: no arc, no rotation — the offers
## present themselves whole; the estate's fan never reaches them), and
## lay the estate in the lower band with this spread's own topology
## (grid in STACKED; the held-fan arc in PANORAMIC, its arc/slack
## tightened to the band it now lives in). With no gate children the
## estate takes the FULL band (a transient lane-before-cards sort never
## parks an empty row on the table).
func _apply_gate_split(controls: Array[Control], bounds: Vector2) -> void:
	var gate: Array[Control] = []
	var estate: Array[Control] = []
	for card in controls:
		if bool(card.get_meta(&"card_gate", false)):
			gate.append(card)
		else:
			estate.append(card)
	var bands := gate_split(bounds, space)
	var estate_band: Rect2 = bands["estate"]
	if gate.is_empty():
		estate_band = Rect2(Vector2.ZERO, bounds)
	else:
		var gate_band: Rect2 = bands["gate"]
		# The straight gate row: one row, every offer whole and separate.
		var gate_rects := stacked_layout(gate.size(), gate_band.size, gate.size(),
			space, right_reserve, left_reserve)
		for i in gate.size():
			var offer := gate[i]
			offer.rotation = 0.0
			var rect: Rect2 = gate_rects[i]
			rect.position += gate_band.position
			fit_child_in_rect(offer, rect)
	if estate.is_empty():
		return
	match mode:
		Mode.STACKED:
			var rects := stacked_layout(estate.size(), estate_band.size, columns,
				space, right_reserve, left_reserve)
			for i in estate.size():
				var card := estate[i]
				card.rotation = 0.0
				var rect: Rect2 = rects[i]
				rect.position += estate_band.position
				fit_child_in_rect(card, rect)
		Mode.PANORAMIC:
			# The estate fan, tightened to its band: a whisper of the arc,
			# a thin rotation slack and a thin vertical pad (the tall
			# single-band overheads would eat a short band's whole height
			# and push the cards' honest minimums past the band's bottom,
			# into the rail chrome), plus the readable width grant (the
			# captions' print floor at short-band widths).
			var entries := panoramic_layout(estate.size(), estate_band.size,
				Vector2(space.x, minf(space.y, 8.0)), minf(arc_depth, 8.0),
				fan_degrees, right_reserve, left_reserve,
				minf(ROTATION_SLACK, 12.0), GATE_ESTATE_MIN_W)
			for i in estate.size():
				var card := estate[i]
				var entry: Dictionary = entries[i]
				var rect: Rect2 = entry["rect"]
				rect.position += estate_band.position
				fit_child_in_rect(card, rect)
				card.pivot_offset = card.size * 0.5
				card.rotation_degrees = float(entry["rotation"])


func _card_children() -> Array[Control]:
	var controls: Array[Control] = []
	for child in get_children():
		if child is Control:
			controls.append(child)
	return controls
