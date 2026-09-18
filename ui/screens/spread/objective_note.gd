## ObjectiveNote — the guided objective arc's PINNED clerk's note (the
## T-UI-10 upgrade). A small paper plate pinned at the table's LEFT edge
## (the Watchful Eye's own perch grammar, mirrored; the table makes way
## through CardSpread.left_reserve while the note stands) showing the
## CURRENT objective in plain language, plus the one verb that skips it:
##
##   THE WORK  |  2 of 7
##   Idle hands, honest work — touch Wat's card: chores or drills.
##   [ I know this ]
##
## PAPER, NEVER CHROME: the note blocks nothing, steals no input (the
## skip chip is its only interactive ink), and folds the moment the arc
## graduates — never to return. Same session in both slots (the Eye's
## rule); the screen places it and owns the skip verb.
##
## Line form: the heading's rule is DASHED in red — the work is in hand,
## the day-sheet's own grammar. State by line form, never hue.
##
## No-clip discipline: every dimension scales with the type factor (the
## text-bearing budget rule), and the objective band holds the WIDEST
## arc line wrapped at the worst factor (the readability audit's
## WRAP-CLIP check is the pin).
class_name ObjectiveNote
extends Control

## The note answered its skip verb (the spread owns what skipping does).
signal skip_pressed()

## Paper margins (design units at 1.0x; the papers' own).
const PAD := 10.0
## The note's plate width at 1.0x — the reserved lane's basis (the
## spread sets CardSpread.left_reserve from note_lane()).
const NOTE_WIDTH := 238.0
const HEADING_H := 24.0
## The objective band: the widest arc line wraps to four lines at the
## 218px inner width in the real italic face — 4 x ~30px, held with air.
const LINE_H := 124.0
const CHIP_H := 48.0

var _heading_label: Label
var _count_label: Label
var _rule: Control
var _objective_label: Label
var _skip_chip: ActionFan.ActionChip
var _note_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_compose()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relaid()


func _draw() -> void:
	## The paper quad + its ink border (the choice card's cut stock).
	if _note_rect.size.x < 4.0:
		return
	var rect := _note_rect.grow(-2.0)
	draw_rect(rect, Inks.PAPER)
	draw_rect(rect.grow(-1.5), Inks.INK, false, 2.0)
	var c := 9.0
	draw_line(Vector2(rect.position.x, rect.position.y + c), Vector2(rect.position.x + c, rect.position.y), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.end.x - c, rect.position.y), Vector2(rect.end.x, rect.position.y + c), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x + c, rect.end.y), Inks.PAPER, 5.0, true)
	draw_line(Vector2(rect.end.x - c, rect.end.y), Vector2(rect.end.x, rect.end.y - c), Inks.PAPER, 5.0, true)


func _compose() -> void:
	_heading_label = Label.new()
	_heading_label.theme_type_variation = &"PipLabel"
	_heading_label.text = "THE WORK"
	_heading_label.add_theme_color_override("font_color", Inks.INK)
	_heading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading_label.size = Vector2(NOTE_WIDTH - 66.0, HEADING_H)
	add_child(_heading_label)

	_rule = preload("res://ui/theme/rule_mark.tscn").instantiate()
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.focus_mode = Control.FOCUS_NONE
	# The work is IN HAND: DASHED, in red — the live page's grammar.
	_rule.set("form", 1)  # RuleMark.RuleForm.DASHED
	_rule.set("rule_ink", Inks.RED)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)

	_objective_label = Label.new()
	_objective_label.theme_type_variation = &"ChronicleLine"
	_objective_label.add_theme_color_override("font_color", Inks.INK)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.size = Vector2(NOTE_WIDTH - 20.0, LINE_H)
	_objective_label.custom_minimum_size = _objective_label.size
	add_child(_objective_label)

	_skip_chip = ActionFan.ActionChip.new()
	_skip_chip.action = {
		"id": &"skip", "label": "I know this", "command": &"",
		"subject": &"", "value": 0, "enabled": true, "reason": "",
		"signature": false,
	}
	_skip_chip.custom_minimum_size = Vector2(148.0, CHIP_H)
	_skip_chip.pressed.connect(func() -> void: skip_pressed.emit())
	add_child(_skip_chip)


## Bind one objective (FirstSession.current_objective's view): {} folds
## the note. Same objective => same render.
func bind(objective: Dictionary) -> void:
	visible = not objective.is_empty()
	if objective.is_empty():
		return
	_objective_label.text = String(objective["text"])
	_relaid()


## The heading row (tests read the plate's parts).
func heading_label() -> Label:
	return _heading_label


func objective_label() -> Label:
	return _objective_label


func heading_rule() -> Control:
	return _rule


func skip_chip() -> ActionFan.ActionChip:
	return _skip_chip


## The lane the table must keep clear (the spread reads this for
## CardSpread.left_reserve): the note's width plus its stand-off.
static func note_lane() -> float:
	return note_rect(Rect2(Vector2.ZERO, Vector2(4096.0, 4096.0))).size.x + 24.0


## The note's plate rect anchored inside the given spread-band rect (the
## screen places the note from the live geometry, the Eye's pattern).
## All dimensions ride the type factor (the text-bearing budget rule).
## Pure: same band + factor => same rect.
static func note_rect(spread_rect: Rect2) -> Rect2:
	var f := TypeScale.factor()
	var width := NOTE_WIDTH * f
	var height := (HEADING_H + LINE_H + CHIP_H + 3.0 * PAD) * f
	var x := spread_rect.position.x + 12.0
	var y := spread_rect.get_center().y - height * 0.5
	return Rect2(Vector2(x, y), Vector2(width, height))


func _relaid() -> void:
	if _heading_label == null or size.x < 8.0 or size.y < 8.0:
		return
	var f := TypeScale.factor()
	_note_rect = Rect2(Vector2.ZERO, size)
	var inner := _note_rect.grow(-PAD * f)
	var heading_h := HEADING_H * f
	var line_h := LINE_H * f
	var chip_h := CHIP_H * f
	_heading_label.position = inner.position
	_heading_label.size = Vector2(inner.size.x, heading_h)
	_rule.position = Vector2(inner.position.x + 110.0 * f, inner.position.y + heading_h * 0.5 - 3.0)
	_rule.size = Vector2(24.0, 6.0)
	_objective_label.position = Vector2(inner.position.x, inner.position.y + heading_h + 4.0 * f)
	_objective_label.size = Vector2(inner.size.x, line_h)
	_objective_label.custom_minimum_size = _objective_label.size
	_heading_label.custom_minimum_size = _heading_label.size
	_skip_chip.position = Vector2(inner.position.x, inner.end.y - chip_h)
	_skip_chip.size = Vector2(148.0 * f, chip_h)
	queue_redraw()
