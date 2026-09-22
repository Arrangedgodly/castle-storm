## VillagePanel — Village production and worker assignment panel for Castle Storm (T-03).
##
## Displays production buildings, worker allocations, and building upgrades.
class_name VillagePanel
extends PanelContainer

signal assign_worker_clicked(building_id: StringName)
signal unassign_worker_clicked(building_id: StringName)
signal upgrade_building_clicked(building_id: StringName)

const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

var _host: GameHost

# Nodes
var title_label: Label
var idle_workers_label: Label
var buildings_container: VBoxContainer

# Map of building_id (StringName) -> Dictionary of row controls
var building_rows: Dictionary = {}


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
	root_vbox.add_theme_constant_override("separation", 10)
	add_child(root_vbox)

	# --- Header ---
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	title_label = Label.new()
	title_label.text = "Village & Production"
	title_label.add_theme_color_override("font_color", Inks.INK)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_label)

	idle_workers_label = Label.new()
	idle_workers_label.text = "Idle Workers: 0"
	idle_workers_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	idle_workers_label.add_theme_font_size_override("font_size", 13)
	header_hbox.add_child(idle_workers_label)

	root_vbox.add_child(header_hbox)

	# --- Scrollable building list ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	buildings_container = VBoxContainer.new()
	buildings_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildings_container.add_theme_constant_override("separation", 8)
	scroll.add_child(buildings_container)

	root_vbox.add_child(scroll)


## Sets or updates the panel using an active GameHost.
func update_from_host(host: GameHost) -> void:
	_host = host
	if host == null:
		return
	var data: Dictionary = GameplayPresenter.get_village_data(host)
	bind_village_data(data)


## Pure data-binding interface from the village data Dictionary.
func bind_village_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	var idle_workers: int = int(data.get("idle_workers", 0))
	idle_workers_label.text = "Idle Workers: %d" % idle_workers

	var buildings: Array = data.get("buildings", [])

	# Ensure rows exist for all buildings
	for b_info: Dictionary in buildings:
		var b_id: StringName = b_info.get("id", &"")
		if not building_rows.has(b_id):
			_create_building_row(b_id)
		_update_building_row(b_id, b_info, idle_workers)


func _create_building_row(b_id: StringName) -> void:
	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Inks.PAPER_DIM
	row_style.border_color = Inks.INK_SOFT
	row_style.border_width_left = 1
	row_style.border_width_top = 1
	row_style.border_width_right = 1
	row_style.border_width_bottom = 1
	row_style.set_content_margin_all(8)
	row_panel.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	row_panel.add_child(hbox)

	# Info column
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = String(b_id)
	name_lbl.add_theme_color_override("font_color", Inks.INK)
	name_lbl.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_lbl)

	var rate_lbl := Label.new()
	rate_lbl.text = "Produces: - · Rate: 0/h"
	rate_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
	rate_lbl.add_theme_font_size_override("font_size", 11)
	info_vbox.add_child(rate_lbl)

	hbox.add_child(info_vbox)

	# Worker assignment column
	var worker_vbox := VBoxContainer.new()
	worker_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var worker_lbl := Label.new()
	worker_lbl.text = "Workers: 0 / 0"
	worker_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	worker_lbl.add_theme_color_override("font_color", Inks.INK)
	worker_lbl.add_theme_font_size_override("font_size", 12)
	worker_vbox.add_child(worker_lbl)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 4)

	var unassign_btn := Button.new()
	unassign_btn.text = " - "
	unassign_btn.custom_minimum_size = Vector2(28, 28)
	unassign_btn.pressed.connect(func() -> void: _on_unassign_pressed(b_id))
	btn_hbox.add_child(unassign_btn)

	var assign_btn := Button.new()
	assign_btn.text = " + "
	assign_btn.custom_minimum_size = Vector2(28, 28)
	assign_btn.pressed.connect(func() -> void: _on_assign_pressed(b_id))
	btn_hbox.add_child(assign_btn)

	worker_vbox.add_child(btn_hbox)
	hbox.add_child(worker_vbox)

	# Upgrade column
	var upgrade_vbox := VBoxContainer.new()
	upgrade_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var upgrade_btn := Button.new()
	upgrade_btn.text = "Upgrade"
	upgrade_btn.custom_minimum_size = Vector2(100, 32)
	upgrade_btn.pressed.connect(func() -> void: _on_upgrade_pressed(b_id))
	upgrade_vbox.add_child(upgrade_btn)

	var cost_lbl := Label.new()
	cost_lbl.text = ""
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
	cost_lbl.add_theme_font_size_override("font_size", 10)
	upgrade_vbox.add_child(cost_lbl)

	hbox.add_child(upgrade_vbox)

	buildings_container.add_child(row_panel)

	# Cache control references
	building_rows[b_id] = {
		"panel": row_panel,
		"name_label": name_lbl,
		"rate_label": rate_lbl,
		"worker_label": worker_lbl,
		"assign_btn": assign_btn,
		"unassign_btn": unassign_btn,
		"upgrade_btn": upgrade_btn,
		"cost_label": cost_lbl,
	}


func _update_building_row(b_id: StringName, b_info: Dictionary, idle_workers: int) -> void:
	var row: Dictionary = building_rows.get(b_id, {})
	if row.is_empty():
		return

	var display_name: String = b_info.get("display_name", String(b_id))
	var level: int = int(b_info.get("level", 1))
	var max_level: int = int(b_info.get("max_level", 1))
	var assigned: int = int(b_info.get("assigned_workers", 0))
	var slots: int = int(b_info.get("worker_slots", 0))
	var rate: float = float(b_info.get("production_rate_per_hour", 0.0))
	var res_kind: String = b_info.get("resource_produced", "")
	var can_upgrade: bool = bool(b_info.get("can_afford_upgrade", false))
	var upgrade_cost: Dictionary = b_info.get("upgrade_cost", {})

	# Labels
	row["name_label"].text = "%s (Lv %d/%d)" % [display_name, level, max_level]
	row["rate_label"].text = "Produces: %s · Rate: %.1f/h" % [res_kind.capitalize(), rate]
	row["worker_label"].text = "Workers: %d / %d" % [assigned, slots]

	# Worker assignment buttons
	row["assign_btn"].disabled = (idle_workers <= 0 or assigned >= slots)
	row["unassign_btn"].disabled = (assigned <= 0)

	# Upgrade button & cost text
	if level >= max_level:
		row["upgrade_btn"].disabled = true
		row["upgrade_btn"].text = "MAX LEVEL"
		row["cost_label"].text = "Fully Upgraded"
	else:
		row["upgrade_btn"].disabled = not can_upgrade
		row["upgrade_btn"].text = "Upgrade Lv %d" % (level + 1)
		var cost_parts: Array[String] = []
		for res_name: StringName in upgrade_cost:
			cost_parts.append("%d %s" % [upgrade_cost[res_name], String(res_name).capitalize()])
		row["cost_label"].text = ", ".join(cost_parts) if not cost_parts.is_empty() else "Free"


func _on_assign_pressed(building_id: StringName) -> void:
	assign_worker_clicked.emit(building_id)
	if _host != null:
		GameplayPresenter.assign_worker_to_building(_host, building_id)
		update_from_host(_host)


func _on_unassign_pressed(building_id: StringName) -> void:
	unassign_worker_clicked.emit(building_id)
	if _host != null:
		GameplayPresenter.unassign_worker_from_building(_host, building_id)
		update_from_host(_host)


func _on_upgrade_pressed(building_id: StringName) -> void:
	upgrade_building_clicked.emit(building_id)
	if _host != null:
		GameplayPresenter.upgrade_building(_host, building_id)
		update_from_host(_host)
