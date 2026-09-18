## SpreadCards — the conspirator-card factory (T-UI-03).
##
## One composed specimen shape for every card on the table (the
## theme-gallery/_demo_card pattern): CardFrame (state edge by line form,
## regime hairline, seeded misprint, focusable) + CardFace (art slot by
## manifest KEY — the T-UI-01 round-2 rule — name plate, role line).
## Cards are view-model driven: the presenter builds the data, this
## factory binds it; the frame carries the card id in a meta so the screen
## can diff without guessing.
class_name SpreadCards
extends RefCounted

const FRAME_SCENE := preload("res://ui/theme/card_frame.tscn")
const FACE_SCENE := preload("res://ui/theme/card_face.tscn")

## Portrait grid column ladder for the stacked spread (see
## adaptive_columns): more paper on the table -> more columns, so cards
## never shrink below the grip floor at roster scale.
const MAX_STACKED_COLUMNS := 5


## Build a card Control from one view-model card dict.
static func conspirator_card(card: Dictionary) -> Control:
	var frame := FRAME_SCENE.instantiate() as Control
	frame.set("edge_form", Inks.edge_form_for_state(card["edge_state"]))
	frame.set("regime_id", card["regime_id"])
	frame.set("misprint_seed", int(card["misprint_seed"]))
	frame.focus_mode = Control.FOCUS_ALL
	frame.set_meta(&"spread_card_id", String(card["id"]))
	# THE GATE PAPER MARK (the first-deal coverage fix): offers carry the
	# gate meta so CardSpread's gate_lane split lays them in the gate row,
	# never over the estate. Kind is immutable per card id (an offer_ uid
	# never rebinds into an estate card), so the meta is set once here.
	frame.set_meta(&"card_gate", StringName(card["kind"]) == &"offer")
	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.offset_left = 14.0
	inset.offset_top = 16.0
	inset.offset_right = -14.0
	inset.offset_bottom = -14.0
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := FACE_SCENE.instantiate() as BoxContainer
	face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	face.size_flags_vertical = Control.SIZE_EXPAND_FILL
	face.set("card_name", String(card["name"]))
	face.set("role_line", String(card["role"]))
	face.set("face_key", card["face_key"])
	inset.add_child(face)
	frame.add_child(inset)
	# THE PAPER HOLDS ITS PRINT (readability r3 — cards grow, the missing
	# height half): the frame is a plain Control whose own minimum is the
	# touch grip only, so when the face's honest minimum rose past the
	# granted cell (a wrapped title holding its r3 height at roster
	# density), the anchored inset simply OVERFLOWED the card paper — the
	# role caption printing past the bottom edge onto the dark ground
	# (the dense-estate find). The face's minimum now relays onto the
	# frame's custom minimum, inset margins included — THE CARD GROWS to
	# hold its print, and the grid's minimums relay the growth up through
	# the slot. Live, not one-way: a rebind that shrinks the honest
	# minimum lets the card settle back.
	#
	# THE HIDDEN PAPER IS PURE (r3, the layout-hash determinism pin): the
	# engine suppresses minimum updates inside HIDDEN subtrees, so a
	# hidden slot's relayed growth would latch whatever phase it was last
	# visible in — two mounts of one state then hash differently. When
	# the card leaves the rendered tree its paper RELAXES to the assigned
	# geometry; when it returns, the visibility-resumed minimum cascade
	# re-fires the relay and the card grows again. Same state -> same
	# rendered table, whichever path mounted it.
	var relay := func() -> void:
		frame.custom_minimum_size = face.get_combined_minimum_size() + Vector2(28.0, 30.0)
	face.minimum_size_changed.connect(relay)
	relay.call()
	frame.visibility_changed.connect(func() -> void:
		if not is_instance_valid(frame):
			return
		if frame.is_visible_in_tree():
			relay.call()
		elif is_instance_valid(frame.get_parent()):
			frame.custom_minimum_size = Vector2.ZERO
			(frame.get_parent() as Container).queue_sort())
	return frame


## Rebind an existing card in place (targeted refresh — the node stays,
## its plates re-print): returns true when anything changed.
static func rebind_card(frame: Control, card: Dictionary) -> bool:
	var changed := false
	if String(frame.get_meta(&"spread_card_id", "")) != String(card["id"]):
		return false
	var edge: int = Inks.edge_form_for_state(card["edge_state"])
	if int(frame.get("edge_form")) != edge:
		frame.set("edge_form", edge)
		changed = true
	for child in frame.get_children():
		if child is MarginContainer:
			for face in child.get_children():
				if face is BoxContainer:
					if String(face.get("card_name")) != String(card["name"]):
						face.set("card_name", String(card["name"]))
						changed = true
					if String(face.get("role_line")) != String(card["role"]):
						face.set("role_line", String(card["role"]))
						changed = true
					if StringName(String(face.get("face_key"))) != StringName(card["face_key"]):
						face.set("face_key", card["face_key"])
						changed = true
	return changed


## The stacked-spread column count for a roster at a given table size:
## THE READABILITY LADDER (r2 — cards grow, they do not shrink). The
## round-1 ladder picked the FEWEST columns that kept rows above a grip
## height — at a 10-card roster that dealt a 5-row grid whose aspect-tied
## cards were ~116px wide and fitted titles to 8px (the verifier's
## TINY find). The aspect ties a card's width to its row height, so the
## readable move is COLUMNS: among 2..MAX_STACKED_COLUMNS this ladder
## grants the WIDEST aspect-true card (the height the row count implies,
## capped at the card max; clamped by the cell width when
## `bounds_width` > 0), ties keeping the FEWER columns (the calmer
## table). Pure.
static func adaptive_columns(card_count: int, bounds_height: float,
		space: float = 20.0, bounds_width: float = 0.0) -> int:
	if card_count <= 0:
		return 2
	var best_cols := 2
	var best_w := -1.0
	for cols in range(2, MAX_STACKED_COLUMNS + 1):
		var rows: int = maxi(1, ceili(float(card_count) / float(cols)))
		var cell_w := INF if bounds_width <= 0.0 \
			else maxf(1.0, (bounds_width - float(cols - 1) * space) / float(cols))
		var cell_h := maxf(1.0, (bounds_height - float(rows - 1) * space) / float(rows))
		var card_w := minf(minf(cell_h, CardSpread.MAX_CARD_HEIGHT) * CardSpread.CARD_ASPECT, cell_w)
		if card_w > best_w + 0.5:
			best_w = card_w
			best_cols = cols
	return best_cols
