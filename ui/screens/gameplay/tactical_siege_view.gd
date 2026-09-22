## TacticalSiegeView — Interactive tactical combat viewport for siege operations (TS-03).
##
## Renders multi-stage fortification defense gauges, tactical stance cards,
## real-time round chronicles, and orderly retreat controls.
class_name TacticalSiegeView
extends Control

signal tactic_selected(tactic_id: StringName)
signal retreat_requested
signal siege_closed

# UI Component references
var header_title: Label
var phase_steps_container: HBoxContainer
var status_label: Label

var army_power_label: Label
var casualties_label: Label

var defender_name_label: Label
var defender_hp_bar: ProgressBar
var defender_hp_label: Label

var tactics_container: VBoxContainer
var chronicle_container: VBoxContainer
var retreat_button: Button
var close_button: Button


func _init() -> void:
	_build_ui()


func _build_ui() -> void:
	name = "TacticalSiegeView"
	anchor_right = 1.0
	anchor_bottom = 1.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Root panel background
	var root_panel := PanelContainer.new()
	root_panel.name = "RootPanel"
	root_panel.anchor_right = 1.0
	root_panel.anchor_bottom = 1.0
	add_child(root_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.add_theme_constant_override("separation", 12)
	root_panel.add_child(main_vbox)

	# --- 1. Header Bar ---
	var header_bar := HBoxContainer.new()
	header_bar.name = "HeaderBar"
	main_vbox.add_child(header_bar)

	header_title = Label.new()
	header_title.name = "HeaderTitle"
	header_title.text = "TACTICAL SIEGE: BREACHING THE CASTLE"
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(header_title)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Phase 1: Outer Gate"
	header_bar.add_child(status_label)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Dismiss View"
	close_button.pressed.connect(func(): siege_closed.emit())
	header_bar.add_child(close_button)

	# --- 2. Phase Steps Progress Stepper ---
	phase_steps_container = HBoxContainer.new()
	phase_steps_container.name = "PhaseStepsContainer"
	phase_steps_container.add_theme_constant_override("separation", 8)
	main_vbox.add_child(phase_steps_container)

	# --- 3. Battlefield Telemetry Status ---
	var telemetry_row := HBoxContainer.new()
	telemetry_row.name = "TelemetryRow"
	telemetry_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(telemetry_row)

	# Attacker Box
	var attacker_card := PanelContainer.new()
	attacker_card.name = "AttackerCard"
	attacker_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_row.add_child(attacker_card)

	var attacker_vbox := VBoxContainer.new()
	attacker_card.add_child(attacker_vbox)

	var attacker_title := Label.new()
	attacker_title.text = "REBEL VANGUARD"
	attacker_vbox.add_child(attacker_title)

	army_power_label = Label.new()
	army_power_label.name = "ArmyPowerLabel"
	army_power_label.text = "Active Army Power: 0"
	attacker_vbox.add_child(army_power_label)

	casualties_label = Label.new()
	casualties_label.name = "CasualtiesLabel"
	casualties_label.text = "Casualties Suffered: 0"
	attacker_vbox.add_child(casualties_label)

	# Defender Box
	var defender_card := PanelContainer.new()
	defender_card.name = "DefenderCard"
	defender_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_row.add_child(defender_card)

	var defender_vbox := VBoxContainer.new()
	defender_card.add_child(defender_vbox)

	defender_name_label = Label.new()
	defender_name_label.name = "DefenderNameLabel"
	defender_name_label.text = "CASTLE DEFENSES"
	defender_vbox.add_child(defender_name_label)

	defender_hp_bar = ProgressBar.new()
	defender_hp_bar.name = "DefenderHpBar"
	defender_hp_bar.max_value = 100.0
	defender_hp_bar.value = 100.0
	defender_hp_bar.custom_minimum_size = Vector2(0, 24)
	defender_hp_bar.show_percentage = false
	defender_vbox.add_child(defender_hp_bar)

	defender_hp_label = Label.new()
	defender_hp_label.name = "DefenderHpLabel"
	defender_hp_label.text = "Fortification HP: 0 / 0"
	defender_vbox.add_child(defender_hp_label)

	# --- 4. Tactical Orders Container ---
	var tactics_label := Label.new()
	tactics_label.text = "AVAILABLE TACTICAL ORDERS"
	main_vbox.add_child(tactics_label)

	tactics_container = VBoxContainer.new()
	tactics_container.name = "TacticsContainer"
	tactics_container.add_theme_constant_override("separation", 8)
	main_vbox.add_child(tactics_container)

	# --- 5. Combat Chronicle Log ---
	var log_header := Label.new()
	log_header.text = "SIEGE CHRONICLE & ENGAGEMENT LOG"
	main_vbox.add_child(log_header)

	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 100)
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(log_scroll)

	chronicle_container = VBoxContainer.new()
	chronicle_container.name = "ChronicleContainer"
	log_scroll.add_child(chronicle_container)

	# --- 6. Footer Actions (Retreat) ---
	var footer_hbox := HBoxContainer.new()
	footer_hbox.name = "FooterHBox"
	main_vbox.add_child(footer_hbox)

	retreat_button = Button.new()
	retreat_button.name = "RetreatButton"
	retreat_button.text = "SOUND RETREAT (Preserve Army)"
	retreat_button.pressed.connect(func(): retreat_requested.emit())
	footer_hbox.add_child(retreat_button)


## Binds formatted view-model dictionary from TacticalSiegePresenter.
func bind_view(view: Dictionary) -> void:
	if view.is_empty():
		return

	status_label.text = String(view.get("status_label", ""))
	army_power_label.text = "Active Army Power: %d" % int(view.get("army_power", 0))
	casualties_label.text = "Casualties Suffered: %d" % int(view.get("casualties_suffered", 0))

	var def_hp: int = int(view.get("defender_hp", 0))
	var def_max: int = int(view.get("defender_max_hp", 0))
	defender_hp_bar.max_value = float(maxi(1, def_max))
	defender_hp_bar.value = float(def_hp)
	defender_hp_label.text = "Fortification HP: %d / %d" % [def_hp, def_max]

	defender_name_label.text = "DEFENSES: %s" % String(view.get("phase_name", "Garrison")).to_upper()

	retreat_button.disabled = not bool(view.get("can_retreat", false))

	_render_phase_steps(view.get("phase_steps", []))
	_render_tactics(view.get("available_tactics", []), bool(view.get("is_active", false)))
	_render_chronicle(view.get("combat_log", []))


func _render_phase_steps(steps: Array) -> void:
	for child in phase_steps_container.get_children():
		child.queue_free()

	for step_variant in steps:
		var step: Dictionary = step_variant
		var btn := Button.new()
		btn.text = String(step.get("label", ""))
		btn.disabled = true
		match String(step.get("state", "")):
			"completed":
				btn.text = "[DONE] " + btn.text
			"active":
				btn.text = ">>> " + btn.text + " <<<"
			_:
				btn.text = "[ ] " + btn.text
		phase_steps_container.add_child(btn)


func _render_tactics(tactics: Array, is_active: bool) -> void:
	for child in tactics_container.get_children():
		child.queue_free()

	if not is_active or tactics.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No tactical orders available."
		tactics_container.add_child(empty_lbl)
		return

	for tactic_variant in tactics:
		var tactic: Dictionary = tactic_variant
		var tactic_id: StringName = tactic.get("id", &"")

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 48)
		tactics_container.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		card.add_child(hbox)

		var title_vbox := VBoxContainer.new()
		title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(title_vbox)

		var name_lbl := Label.new()
		name_lbl.text = "%s [%s | %s]" % [
			String(tactic.get("title", "")),
			String(tactic.get("perk", "")),
			String(tactic.get("risk", ""))
		]
		title_vbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = String(tactic.get("desc", ""))
		title_vbox.add_child(desc_lbl)

		var exec_btn := Button.new()
		exec_btn.text = "EXECUTE ORDER"
		exec_btn.pressed.connect(func(): tactic_selected.emit(tactic_id))
		hbox.add_child(exec_btn)


func _render_chronicle(log_entries: Array) -> void:
	for child in chronicle_container.get_children():
		child.queue_free()

	if log_entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No siege actions logged yet."
		chronicle_container.add_child(empty_lbl)
		return

	# Show latest entries
	for entry_variant in log_entries:
		var entry: Dictionary = entry_variant
		var lbl := Label.new()
		lbl.text = "• " + String(entry.get("text", ""))
		chronicle_container.add_child(lbl)
