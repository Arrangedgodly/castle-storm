## SiegePanel — Castle siege forecasting and assault command panel (T-05).
##
## Displays target garrison intel, army power comparisons, calculated win odds,
## minimum assault floor status, and the assault trigger.
class_name SiegePanel
extends PanelContainer

signal assault_committed
signal tactical_siege_initiated

const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

var _host: GameHost

# Nodes
var title_label: Label
var garrison_label: Label
var army_label: Label
var floor_label: Label
var odds_meter: ProgressBar
var odds_label: Label
var assessment_label: Label
var assault_button: Button
var tactical_button: Button


func _init() -> void:
	_build_ui()


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Inks.PAPER
	style.border_color = Inks.INK
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 12)
	add_child(root_vbox)

	# --- Header ---
	title_label = Label.new()
	title_label.text = "Castle Siege & Threat"
	title_label.add_theme_color_override("font_color", Inks.INK)
	title_label.add_theme_font_size_override("font_size", 16)
	root_vbox.add_child(title_label)

	# --- Intel Section ---
	var intel_panel := PanelContainer.new()
	intel_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var intel_style := StyleBoxFlat.new()
	intel_style.bg_color = Inks.PAPER_DIM
	intel_style.border_color = Inks.INK_SOFT
	intel_style.border_width_left = 1
	intel_style.border_width_top = 1
	intel_style.border_width_right = 1
	intel_style.border_width_bottom = 1
	intel_style.set_content_margin_all(10)
	intel_panel.add_theme_stylebox_override("panel", intel_style)

	var intel_vbox := VBoxContainer.new()
	intel_vbox.add_theme_constant_override("separation", 6)
	intel_panel.add_child(intel_vbox)

	garrison_label = Label.new()
	garrison_label.text = "Castle Garrison: 0 Power"
	garrison_label.add_theme_color_override("font_color", Inks.INK)
	garrison_label.add_theme_font_size_override("font_size", 13)
	intel_vbox.add_child(garrison_label)

	army_label = Label.new()
	army_label.text = "Conspirator Army: 0 Power"
	army_label.add_theme_color_override("font_color", Inks.INK)
	army_label.add_theme_font_size_override("font_size", 13)
	intel_vbox.add_child(army_label)

	floor_label = Label.new()
	floor_label.text = "Minimum Assault Floor: 0 (Unmet)"
	floor_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	floor_label.add_theme_font_size_override("font_size", 11)
	intel_vbox.add_child(floor_label)

	root_vbox.add_child(intel_panel)

	# --- Forecast / Odds Section ---
	var odds_vbox := VBoxContainer.new()
	odds_vbox.add_theme_constant_override("separation", 6)

	var odds_header := HBoxContainer.new()
	odds_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	odds_label = Label.new()
	odds_label.text = "Calculated Win Odds: 0.0%"
	odds_label.add_theme_color_override("font_color", Inks.INK)
	odds_label.add_theme_font_size_override("font_size", 13)
	odds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds_header.add_child(odds_label)

	assessment_label = Label.new()
	assessment_label.text = "Unprepared"
	assessment_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	assessment_label.add_theme_font_size_override("font_size", 12)
	odds_header.add_child(assessment_label)

	odds_vbox.add_child(odds_header)

	odds_meter = ProgressBar.new()
	odds_meter.min_value = 0.0
	odds_meter.max_value = 100.0
	odds_meter.value = 0.0
	odds_meter.show_percentage = false
	odds_meter.custom_minimum_size = Vector2(0, 16)
	odds_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds_vbox.add_child(odds_meter)

	root_vbox.add_child(odds_vbox)

	# --- Assault Command Section ---
	var assault_box := VBoxContainer.new()
	assault_box.alignment = BoxContainer.ALIGNMENT_CENTER
	assault_box.add_theme_constant_override("separation", 8)

	tactical_button = Button.new()
	tactical_button.text = "COMMAND TACTICAL BREACH"
	tactical_button.custom_minimum_size = Vector2(0, 36)
	tactical_button.disabled = true
	tactical_button.pressed.connect(_on_tactical_pressed)
	assault_box.add_child(tactical_button)

	assault_button = Button.new()
	assault_button.text = "STORM THE CASTLE (Auto-Resolve)"
	assault_button.custom_minimum_size = Vector2(0, 32)
	assault_button.disabled = true
	assault_button.pressed.connect(_on_assault_pressed)
	assault_box.add_child(assault_button)

	root_vbox.add_child(assault_box)


## Updates panel state from live GameHost instance.
func update_from_host(host: GameHost) -> void:
	_host = host
	if host == null:
		return
	var data: Dictionary = GameplayPresenter.get_siege_data(host)
	bind_siege_data(data)


## Pure data-binding interface from siege data dictionary.
func bind_siege_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	var garrison_power: int = int(data.get("garrison_power", 0))
	var army_power: int = int(data.get("army_power", 0))
	var floor_power: int = int(data.get("floor_power", 0))
	var floor_met: bool = bool(data.get("floor_met", false))
	var win_odds: float = float(data.get("win_odds_percent", 0.0))
	var can_assault: bool = bool(data.get("can_assault", false))

	garrison_label.text = "Castle Garrison: %d Power" % garrison_power
	army_label.text = "Conspirator Army: %d Power" % army_power

	if floor_met:
		floor_label.text = "Minimum Floor: %d (Met - Ready to Assault)" % floor_power
		floor_label.add_theme_color_override("font_color", Inks.INK)
	else:
		floor_label.text = "Minimum Floor: %d (Unmet - Recruit More Knights/Soldiers)" % floor_power
		floor_label.add_theme_color_override("font_color", Inks.INK_SOFT)

	odds_meter.value = win_odds
	odds_label.text = "Calculated Win Odds: %.1f%%" % win_odds

	if win_odds >= 75.0:
		assessment_label.text = "Decisive Advantage"
	elif win_odds >= 50.0:
		assessment_label.text = "Favorable Position"
	elif win_odds >= 30.0:
		assessment_label.text = "Risky Engagement"
	else:
		assessment_label.text = "Severe Peril"

	assault_button.disabled = not can_assault
	tactical_button.disabled = not can_assault


func _on_assault_pressed() -> void:
	if _host == null:
		return
	GameplayPresenter.commit_assault(_host)
	assault_committed.emit()


func _on_tactical_pressed() -> void:
	tactical_siege_initiated.emit()
