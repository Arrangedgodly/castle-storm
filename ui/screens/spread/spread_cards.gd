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


## The stacked-spread column count for a roster at a given table height:
## the FEWEST columns (from 2) that keep every row at or above a full
## card grip (2x touch grip), capped at MAX_STACKED_COLUMNS. Pure.
static func adaptive_columns(card_count: int, bounds_height: float, space: float = 20.0) -> int:
	if card_count <= 6:
		return 2
	# THE GRIP IS A WIDTH (the readability pass): the card's aspect ties
	# width to height, so a row budget built on the bare 96 height can
	# grant 90-wide cards whose plates step to 8px — the audit's densest
	# find. The rows budget uses the height the grip WIDTH implies
	# (96 / CARD_ASPECT), keeping every card at or above the grip on BOTH
	# axes; when even the cap cannot honor it, the cap stands and the
	# plates' full-fit is the density answer.
	var min_card := float(Inks.TOUCH_GRIP_MIN * 2) / CardSpread.CARD_ASPECT
	var max_rows := maxi(1, int(bounds_height / (min_card + space)))
	for cols in range(2, MAX_STACKED_COLUMNS + 1):
		var rows: int = ceil(float(card_count) / float(cols))
		if rows <= max_rows or cols == MAX_STACKED_COLUMNS:
			return cols
	return MAX_STACKED_COLUMNS
