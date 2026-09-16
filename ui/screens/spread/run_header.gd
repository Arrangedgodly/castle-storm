## RunHeader — the run's letterhead printed above the table (T-UI-03).
##
## Leader name (display face) + a rule in the regime's second ink + regime
## name + run clock: the identity strip of the current hand. Data-driven
## end to end — a restart rebinds it from the view model; a regime swap
## recolors the rule by content (Inks.regime_secondary), never by code.
## Chrome, not a control: nothing here is interactive, so it carries no
## focus (grips apply to interactive targets only).
extends HBoxContainer

const RULE_SCENE := preload("res://ui/theme/rule_mark.tscn")

var _name_label: Label
var _rule: Control
var _regime_label: Label
var _time_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.theme_type_variation = &"CardTitle"
	_name_label.add_theme_font_size_override("font_size", 28)  # the letterhead fits long names at table width
	_name_label.clip_text = true  # the strip's minimum never exceeds the table
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.custom_minimum_size = Vector2(160, 0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	_rule = RULE_SCENE.instantiate()
	_rule.set("form", 0)  # RuleMark.RuleForm.SOLID — the regime's signature
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_regime_label = Label.new()
	_regime_label.theme_type_variation = &"RoleLine"
	_regime_label.clip_text = true
	_regime_label.custom_minimum_size = Vector2(150, 0)
	_regime_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_regime_label)
	_time_label = Label.new()
	_time_label.theme_type_variation = &"PipLabel"
	_time_label.clip_text = true
	_time_label.custom_minimum_size = Vector2(96, 0)
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time_label)


func _get_minimum_size() -> Vector2:
	## A full grip-height row: the display-face name plate (~44 units at
	## size 28) must fit INSIDE the strip — an undersized minimum made the
	## labels overflow into the chronicle below (caught by screenshot
	## inspection, not by the rect tests — labels draw outside rects).
	return Vector2(Inks.TOUCH_GRIP_MIN * 4.0, Inks.TOUCH_GRIP_MIN)


## Bind from the view model's leader block + run clock + the ground the
## strip prints on. THE PRINT RULE (screenshot-inspection find): the
## header sits on the dark TABLE, so its text follows the same
## ink-per-stock rule as the chronicle — paper-bright on dark grounds,
## ink on the pale aftermath. Ink-on-dark was illegible.
func bind(leader: Dictionary, sim_hours: float, army_power: int, ground: Color) -> void:
	if _name_label == null:
		return
	var text_ink := Inks.ground_text_ink(ground)
	_name_label.text = str(leader["name"]) if not str(leader["name"]).is_empty() else "The Empty Chair"
	_name_label.add_theme_color_override("font_color", text_ink)
	_regime_label.text = str(leader["regime_name"]).to_upper()
	_regime_label.add_theme_color_override("font_color", Inks.regime_secondary(leader["regime_id"]))
	_rule.set("rule_ink", Inks.regime_secondary(leader["regime_id"]))
	_time_label.text = "%dh · power %d" % [int(sim_hours), army_power]
	_time_label.add_theme_color_override("font_color", text_ink)
