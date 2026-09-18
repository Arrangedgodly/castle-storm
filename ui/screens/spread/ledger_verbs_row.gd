## LedgerVerbsRow — the header's second row: the four table-paper chips
## (Chronicle / Day-Sheet / Press-Room / Legacy), right-aligned.
##
## A FlowContainer so the verbs WRAP (paper flow) instead of clipping
## when the grown chips exceed the strip (the readability pass: the old
## fixed HBox clipped "The Press-Room" +38px at 1.3x portrait). A flow's
## own minimum height is width-dependent — measured at whatever width the
## last pass left — which made the header's height history-dependent and
## the layout-hash pin caught the drift. THE REFIT SEAM (the letterhead's
## pattern): the slot's topology calls refit(strip_w) BEFORE reading this
## row's minimum, so the row's height is a PURE function of the chips'
## minimums + the strip width: one row when they fit, two when they do
## not, never a clip and never a stale wrap.
class_name LedgerVerbsRow
extends FlowContainer


func _ready() -> void:
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 4)
	alignment = FlowContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, float(Inks.TOUCH_GRIP_MIN))


## The row's height for one strip width: the chips' combined minimum
## (each chip is already its own measured print — ActionChip grows to its
## label) laid in rows of at most strip_w. Pure: chips + width -> height.
func refit(strip_w: float) -> void:
	var row_w := 0.0
	var rows := 1
	var gap := get_theme_constant(&"h_separation")
	for chip in get_children():
		var chip_w: float = (chip as Control).get_combined_minimum_size().x
		if row_w > 0.0 and row_w + gap + chip_w > strip_w:
			rows += 1
			row_w = chip_w
		else:
			row_w = row_w + (gap if row_w > 0.0 else 0.0) + chip_w
	var v_gap := get_theme_constant(&"v_separation")
	custom_minimum_size.y = rows * float(Inks.TOUCH_GRIP_MIN) + float(rows - 1) * v_gap
