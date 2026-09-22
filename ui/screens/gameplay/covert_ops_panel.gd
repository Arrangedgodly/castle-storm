## CovertOpsPanel — Interactive espionage and infiltration operations interface (CO-03).
##
## Displays espionage network status, covert operation cards with costs and risks,
## launch triggers, and operative debrief history.
class_name CovertOpsPanel
extends PanelContainer

signal operation_requested(op_id: StringName)
signal operation_executed(result: Dictionary)

const CovertOpsPresenter := preload("res://ui/screens/gameplay/covert_ops_presenter.gd")
const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")

var _covert_system: CovertOpsSystem
var _engine: SimEngine
var _host: GameHost

# Nodes
var title_label: Label
var network_status_label: Label
var operations_container: VBoxContainer
var history_container: VBoxContainer
var history_scroll: ScrollContainer

# Map of op_id -> Dictionary of controls
var operation_cards: Dictionary = {}


func _init() -> void:
	_build_ui()


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Inks.PAPER
	panel_style.border_color = Inks.INK
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", panel_style)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 10)
	add_child(root_vbox)

	# --- Header ---
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	title_label = Label.new()
	title_label.text = "Clandestine Operations & Espionage"
	title_label.add_theme_color_override("font_color", Inks.INK)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_label)

	network_status_label = Label.new()
	network_status_label.text = "Network: Inactive"
	network_status_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	network_status_label.add_theme_font_size_override("font_size", 12)
	header_hbox.add_child(network_status_label)

	root_vbox.add_child(header_hbox)

	# --- Main Content Split (Operations Cards + Debrief Log) ---
	var content_split := HBoxContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_split.add_theme_constant_override("separation", 12)
	root_vbox.add_child(content_split)

	# Left: Operation Cards
	var ops_scroll := ScrollContainer.new()
	ops_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ops_scroll.size_flags_stretch_ratio = 1.6
	ops_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	operations_container = VBoxContainer.new()
	operations_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operations_container.add_theme_constant_override("separation", 8)
	ops_scroll.add_child(operations_container)
	content_split.add_child(ops_scroll)

	# Right: Intelligence Debrief Chronicle
	var intel_panel := PanelContainer.new()
	intel_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intel_panel.size_flags_stretch_ratio = 1.0
	intel_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var intel_style := StyleBoxFlat.new()
	intel_style.bg_color = Inks.PAPER_DIM
	intel_style.border_color = Inks.INK_SOFT
	intel_style.border_width_left = 1
	intel_style.border_width_top = 1
	intel_style.border_width_right = 1
	intel_style.border_width_bottom = 1
	intel_style.set_content_margin_all(8)
	intel_panel.add_theme_stylebox_override("panel", intel_style)

	var intel_vbox := VBoxContainer.new()
	intel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intel_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intel_vbox.add_theme_constant_override("separation", 6)
	intel_panel.add_child(intel_vbox)

	var debrief_header := Label.new()
	debrief_header.text = "Operative Chronicle"
	debrief_header.add_theme_color_override("font_color", Inks.INK)
	debrief_header.add_theme_font_size_override("font_size", 13)
	intel_vbox.add_child(debrief_header)

	history_scroll = ScrollContainer.new()
	history_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	history_container = VBoxContainer.new()
	history_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_container.add_theme_constant_override("separation", 4)
	history_scroll.add_child(history_container)
	intel_vbox.add_child(history_scroll)

	content_split.add_child(intel_panel)


## Sets up connection with live game host and covert operations system.
func setup_host(host: GameHost, covert_sys: CovertOpsSystem) -> void:
	_host = host
	_covert_system = covert_sys
	if host != null:
		_engine = host.engine
	refresh()


## Refreshes the panel UI using current state.
func refresh() -> void:
	if _covert_system == null or _engine == null:
		return
	var vm: Dictionary = CovertOpsPresenter.format_operations_view(_covert_system, _engine)
	bind_operations_data(vm)


## Pure data-binding interface from view-model dictionary.
func bind_operations_data(data: Dictionary) -> void:
	var net_active: bool = bool(data.get("network_active", false))
	var perks_count: int = int(data.get("active_perks_count", 0))

	if net_active:
		network_status_label.text = "Network: Active (%d Infiltrations Established)" % perks_count
		network_status_label.add_theme_color_override("font_color", Inks.INK)
	else:
		network_status_label.text = "Network: Inactive (0 Infiltrations)"
		network_status_label.add_theme_color_override("font_color", Inks.INK_SOFT)

	var ops: Array = data.get("operations", [])
	_sync_operation_cards(ops)

	var history: Array = data.get("history", [])
	_sync_history_log(history)


func _sync_operation_cards(operations: Array) -> void:
	# Clean up any cards that no longer exist
	for child in operations_container.get_children():
		child.queue_free()
	operation_cards.clear()

	for op in operations:
		var op_id: StringName = op.get("id", &"")
		var is_active: bool = bool(op.get("is_active", false))
		var can_launch: bool = bool(op.get("can_launch", false))

		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Inks.PAPER_DIM if not is_active else Inks.PAPER
		card_style.border_color = Inks.INK if is_active else Inks.INK_SOFT
		card_style.border_width_left = 1
		card_style.border_width_top = 1
		card_style.border_width_right = 1
		card_style.border_width_bottom = 1
		card_style.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 4)
		card.add_child(card_vbox)

		# Row 1: Title and Status Tag
		var top_row := HBoxContainer.new()
		top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var op_title := Label.new()
		op_title.text = String(op.get("title", ""))
		op_title.add_theme_color_override("font_color", Inks.INK)
		op_title.add_theme_font_size_override("font_size", 13)
		op_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(op_title)

		var status_badge := Label.new()
		status_badge.text = String(op.get("status_label", ""))
		status_badge.add_theme_font_size_override("font_size", 10)
		status_badge.add_theme_color_override("font_color", Inks.INK if is_active else Inks.INK_SOFT)
		top_row.add_child(status_badge)
		card_vbox.add_child(top_row)

		# Row 2: Description
		var desc_lbl := Label.new()
		desc_lbl.text = String(op.get("desc", ""))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
		desc_lbl.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(desc_lbl)

		# Row 3: Perk
		var perk_lbl := Label.new()
		perk_lbl.text = "Benefit: " + String(op.get("perk", ""))
		perk_lbl.add_theme_color_override("font_color", Inks.INK)
		perk_lbl.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(perk_lbl)

		# Row 4: Telemetry & Launch Action
		var bot_row := HBoxContainer.new()
		bot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var cost_lbl := Label.new()
		cost_lbl.text = "Cost: %s | %s" % [String(op.get("cost_text", "")), String(op.get("chance_text", ""))]
		cost_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bot_row.add_child(cost_lbl)

		var launch_btn := Button.new()
		launch_btn.text = "ESTABLISHED" if is_active else "LAUNCH OPERATION"
		launch_btn.disabled = not can_launch
		launch_btn.custom_minimum_size = Vector2(130, 26)
		launch_btn.pressed.connect(_on_launch_pressed.bind(op_id))
		bot_row.add_child(launch_btn)

		card_vbox.add_child(bot_row)

		operations_container.add_child(card)
		operation_cards[op_id] = {
			"card": card,
			"button": launch_btn,
			"status": status_badge
		}


func _sync_history_log(history: Array) -> void:
	for child in history_container.get_children():
		child.queue_free()

	if history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No operations executed yet."
		empty_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		history_container.add_child(empty_lbl)
		return

	for entry in history:
		var entry_lbl := Label.new()
		entry_lbl.text = "• " + String(entry.get("text", ""))
		entry_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry_lbl.add_theme_font_size_override("font_size", 10)
		if bool(entry.get("success", false)):
			entry_lbl.add_theme_color_override("font_color", Inks.INK)
		else:
			entry_lbl.add_theme_color_override("font_color", Inks.RED)
		history_container.add_child(entry_lbl)


func _on_launch_pressed(op_id: StringName) -> void:
	operation_requested.emit(op_id)

	if _covert_system != null and _engine != null:
		var res: Dictionary = CovertOpsPresenter.launch_operation(_covert_system, _engine, op_id)
		operation_executed.emit(res)
		refresh()
