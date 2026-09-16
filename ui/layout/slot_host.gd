## SlotHost — the container that holds a screen's two orientation slots
## (T-UI-02, per R3).
##
## A custom Container using the documented recipe (NOTIFICATION_SORT_CHILDREN
## + fit_child_in_rect) because the stock alternatives all fought the
## ALTERNATE-slot shape while building this (measured on 4.7.2): a
## MarginContainer refuses to shrink below a stale minimum across
## orientation swaps and overflows the design rect, and manually-placed
## slot children get re-centered to old minimums by the preset/offset
## bookkeeping on rapid resizes. Containers OWN their children — this one
## force-fits BOTH slots into the same margin-inset rect, every sort.
##
## Minimum size is deliberately ZERO: the slots are alternates (only one
## is ever visible), the window/design rect is the layout authority, and
## per-component touch grips are enforced by the test suites — a min-size
## here would re-create the shrink-refusal overflow.
extends Container
class_name SlotHost

## Design margin inside the screen (safe-area insets add on top; the
## ResponsiveScreen plumbs the clamped insets in).
@export var margin: float = 12.0

## Clamped safe-area insets (R3 §4), set by the ResponsiveScreen.
var safe_insets: Vector2 = Vector2.ZERO

## Largest fraction of an axis safe-area insets may claim (the clamp).
const SAFE_INSET_MAX_FRACTION := 0.25

## Absolute notch-scale cap on either axis (a real cutout is notch-sized,
## not quarter-screen-sized).
const NOTCH_MAX_INSET := 120.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var inset := Vector2.ONE * margin + safe_insets
		var rect := Rect2(inset, size - inset * 2.0)
		for child in get_children():
			if child is Control:
				fit_child_in_rect(child, rect)


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO


## Refresh the safe insets and re-sort. POLICY (the R3 §4 groundwork,
## hardened while building this): insets are derived from the CUTOUT LIST
## — DisplayServer.get_display_cutouts() — and only when cutouts exist
## does the safe-area rect refine them (mobile). Desktop/Deck/headless
## report no cutouts -> insets are exactly zero. Measured reason: on
## desktop the safe-area rect can differ from the window frame for
## reasons that are not notches (menu-bar/discrepancy class,
## godotengine/godot#105462), and "clamping" such insets to a fraction
## of the axis still ate a quarter of the table. Clamps: a quarter of
## each axis AND a notch-scale absolute cap.
func update_safe_insets() -> void:
	if not is_inside_tree():
		safe_insets = Vector2.ZERO
		return
	var window := get_window()
	var cutouts := DisplayServer.get_display_cutouts()
	if cutouts.is_empty():
		safe_insets = Vector2.ZERO
		queue_sort()
		return
	var safe := DisplayServer.get_display_safe_area()
	var window_rect := Rect2(window.position, window.size)
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	for cutout in cutouts:
		if not window_rect.intersects(cutout):
			continue
		left = maxf(left, float(window_rect.position.x - cutout.position.x))
		right = maxf(right, float(cutout.end.x - window_rect.end.x))
		top = maxf(top, float(window_rect.position.y - cutout.position.y))
		bottom = maxf(bottom, float(cutout.end.y - window_rect.end.y))
	# Refine with the safe-area rect when it is the tighter statement.
	left = maxf(left, float(safe.position.x - window_rect.position.x))
	right = maxf(right, float(window_rect.end.x - safe.end.x))
	top = maxf(top, float(safe.position.y - window_rect.position.y))
	bottom = maxf(bottom, float(window_rect.end.y - safe.end.y))
	var clamp_x: float = minf(float(window.size.x) * SAFE_INSET_MAX_FRACTION, NOTCH_MAX_INSET)
	var clamp_y: float = minf(float(window.size.y) * SAFE_INSET_MAX_FRACTION, NOTCH_MAX_INSET)
	safe_insets = Vector2(
		clampf(maxf(left, right), 0.0, clamp_x),
		clampf(maxf(top, bottom), 0.0, clamp_y))
	queue_sort()
