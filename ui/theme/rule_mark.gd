## RuleMark — a printed rule in the line-form grammar (T-UI-01).
##
## The smallest state carrier after the card edge: a short rule that
## prints solid / dashed / struck / double, reusing the same
## form-carries-state vocabulary (Inks.EdgeForm). The ChronicleLine
## prefixes its text with one; anything else that needs a printed
## state mark (suspicion meter ticks, building plates) reuses it.
extends Control

## Double rule = the chronicle's VICTORY flourish (a printed double
## rule, distinct form from SOLID/DASHED/STRUCK).
enum RuleForm { SOLID, DASHED, STRUCK, DOUBLE }

@export var form: RuleForm = RuleForm.SOLID:
	set(value):
		if form != value:
			form = value
			queue_redraw()

## Rule ink (the row sets it from its ground — dark grounds print
## paper-bright, light grounds print ink).
@export var rule_ink: Color = Inks.PAPER:
	set(value):
		if rule_ink != value:
			rule_ink = value
			queue_redraw()

@export var rule_width := 3.0:
	set(value):
		if rule_width != value:
			rule_width = value
			queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(30.0, 22.0)


func _draw() -> void:
	var center := size * 0.5
	var half_w := size.x * 0.5
	var a := Vector2(center.x - half_w, center.y)
	var b := Vector2(center.x + half_w, center.y)
	match form:
		RuleForm.SOLID:
			draw_line(a, b, rule_ink, rule_width, true)
		RuleForm.DASHED:
			var dir := (b - a) / size.x
			var t := 0.0
			while t < size.x:
				var dash_end := minf(t + 6.0, size.x)
				draw_line(a + dir * t, a + dir * dash_end, rule_ink, rule_width, true)
				t += 9.0
		RuleForm.STRUCK:
			## A struck rule: the rule plus its own strike-through — the
			## same form language as a struck card edge, at glyph scale.
			draw_line(a, b, rule_ink, rule_width * 0.6, true)
			draw_line(Vector2(center.x - 7.0, center.y + 7.0), Vector2(center.x + 7.0, center.y - 7.0), rule_ink, rule_width, true)
		RuleForm.DOUBLE:
			draw_line(a + Vector2(0, -3.0), b + Vector2(0, -3.0), rule_ink, rule_width * 0.7, true)
			draw_line(a + Vector2(0, 3.0), b + Vector2(0, 3.0), rule_ink, rule_width * 0.7, true)
