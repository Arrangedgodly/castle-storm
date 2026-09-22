## RosterPanel — Recruitment, population allocation, and military armory panel (T-04).
##
## Manages gate arrivals (offers), peasant role assignments, training progress,
## and military forces.
class_name RosterPanel
extends PanelContainer

signal offer_accepted(offer_id: int)
signal offer_dismissed(offer_id: int)
signal peasant_promoted_to_worker(unit_id: int)
signal peasant_promoted_to_militia(unit_id: int)

const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

var _host: GameHost

# Nodes
var title_label: Label
var gate_header_label: Label
var offers_container: VBoxContainer
var peasant_summary_label: Label
var assign_worker_btn: Button
var assign_militia_btn: Button
var army_summary_label: Label
var training_container: VBoxContainer
var soldiers_container: VBoxContainer

# Cache
var offer_rows: Dictionary = {}
var first_peasant_id: int = -1


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

	# --- Title ---
	title_label = Label.new()
	title_label.text = "Roster & Military Armory"
	title_label.add_theme_color_override("font_color", Inks.INK)
	title_label.add_theme_font_size_override("font_size", 16)
	root_vbox.add_child(title_label)

	# --- Scrollable Body ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(content_vbox)

	# === SECTION 1: Gate Arrivals ===
	var gate_section := VBoxContainer.new()
	gate_section.add_theme_constant_override("separation", 6)

	gate_header_label = Label.new()
	gate_header_label.text = "Gate Arrivals (0 Available)"
	gate_header_label.add_theme_color_override("font_color", Inks.INK)
	gate_header_label.add_theme_font_size_override("font_size", 14)
	gate_section.add_child(gate_header_label)

	offers_container = VBoxContainer.new()
	offers_container.add_theme_constant_override("separation", 4)
	gate_section.add_child(offers_container)

	content_vbox.add_child(gate_section)

	# === SECTION 2: Peasant Assignment ===
	var peasant_section := VBoxContainer.new()
	peasant_section.add_theme_constant_override("separation", 6)

	var peasant_header := Label.new()
	peasant_header.text = "Peasant Allocation"
	peasant_header.add_theme_color_override("font_color", Inks.INK)
	peasant_header.add_theme_font_size_override("font_size", 14)
	peasant_section.add_child(peasant_header)

	peasant_summary_label = Label.new()
	peasant_summary_label.text = "Idle Peasants: 0"
	peasant_summary_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	peasant_summary_label.add_theme_font_size_override("font_size", 12)
	peasant_section.add_child(peasant_summary_label)

	var peasant_btns := HBoxContainer.new()
	peasant_btns.add_theme_constant_override("separation", 8)

	assign_worker_btn = Button.new()
	assign_worker_btn.text = "Assign to Workforce"
	assign_worker_btn.disabled = true
	assign_worker_btn.pressed.connect(_on_assign_peasant_to_worker)
	peasant_btns.add_child(assign_worker_btn)

	assign_militia_btn = Button.new()
	assign_militia_btn.text = "Mobilize into Militia"
	assign_militia_btn.disabled = true
	assign_militia_btn.pressed.connect(_on_assign_peasant_to_militia)
	peasant_btns.add_child(assign_militia_btn)

	peasant_section.add_child(peasant_btns)
	content_vbox.add_child(peasant_section)

	# === SECTION 3: Training & Military Forces ===
	var army_section := VBoxContainer.new()
	army_section.add_theme_constant_override("separation", 6)

	var army_header := Label.new()
	army_header.text = "Forces & Training"
	army_header.add_theme_color_override("font_color", Inks.INK)
	army_header.add_theme_font_size_override("font_size", 14)
	army_section.add_child(army_header)

	army_summary_label = Label.new()
	army_summary_label.text = "Army Combat Power: 0 · Militia: 0 · Soldiers: 0"
	army_summary_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	army_summary_label.add_theme_font_size_override("font_size", 12)
	army_section.add_child(army_summary_label)

	training_container = VBoxContainer.new()
	training_container.add_theme_constant_override("separation", 4)
	army_section.add_child(training_container)

	soldiers_container = VBoxContainer.new()
	soldiers_container.add_theme_constant_override("separation", 4)
	army_section.add_child(soldiers_container)

	content_vbox.add_child(army_section)


## Updates panel state from live GameHost instance.
func update_from_host(host: GameHost) -> void:
	_host = host
	if host == null:
		return
	var data: Dictionary = GameplayPresenter.get_roster_data(host)
	bind_roster_data(data)


## Pure data-binding interface from roster data dictionary.
func bind_roster_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	# 1. Offers
	var offers: Array = data.get("offers", [])
	gate_header_label.text = "Gate Arrivals (%d Available)" % offers.size()
	_update_offers(offers)

	# 2. Peasants
	var idle_peasants: Array = data.get("idle_peasants", [])
	peasant_summary_label.text = "Idle Peasants: %d" % idle_peasants.size()
	first_peasant_id = idle_peasants[0] if not idle_peasants.is_empty() else -1
	assign_worker_btn.disabled = (first_peasant_id == -1)
	assign_militia_btn.disabled = (first_peasant_id == -1)

	# 3. Military
	var total_power: int = int(data.get("total_combat_power", 0))
	var militia_count: int = int(data.get("militia_count", 0))
	var soldiers: Array = data.get("soldiers", [])
	army_summary_label.text = "Army Combat Power: %d · Militia: %d · Trained Soldiers: %d" % [
		total_power, militia_count, soldiers.size()
	]

	# 4. Training
	var training_units: Array = data.get("training_units", [])
	_update_training(training_units)

	# 5. Soldiers
	_update_soldiers(soldiers)


func _update_offers(offers: Array) -> void:
	for child: Node in offers_container.get_children():
		offers_container.remove_child(child)
		child.free()
	offer_rows.clear()

	for offer_info: Dictionary in offers:
		var o_id: int = int(offer_info.get("id", -1))
		var disp_name: String = offer_info.get("display_name", "Recruit")

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var lbl := Label.new()
		lbl.text = "• %s" % disp_name
		lbl.add_theme_color_override("font_color", Inks.INK)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.pressed.connect(func() -> void: _on_accept_offer(o_id))
		row.add_child(accept_btn)

		var dismiss_btn := Button.new()
		dismiss_btn.text = "Dismiss"
		dismiss_btn.pressed.connect(func() -> void: _on_dismiss_offer(o_id))
		row.add_child(dismiss_btn)

		offers_container.add_child(row)
		offer_rows[o_id] = {
			"row": row,
			"label": lbl,
			"accept_btn": accept_btn,
			"dismiss_btn": dismiss_btn,
		}


func _update_training(training_units: Array) -> void:
	for child: Node in training_container.get_children():
		training_container.remove_child(child)
		child.free()

	if training_units.is_empty():
		return

	var title := Label.new()
	title.text = "Undergoing Training:"
	title.add_theme_color_override("font_color", Inks.INK_SOFT)
	title.add_theme_font_size_override("font_size", 12)
	training_container.add_child(title)

	for t_info: Dictionary in training_units:
		var target: String = String(t_info.get("training_target", "Soldier")).capitalize()
		var pct: float = float(t_info.get("progress_percent", 0.0))

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var lbl := Label.new()
		lbl.text = "%s (%0.0f%%)" % [target, pct]
		lbl.add_theme_color_override("font_color", Inks.INK)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.custom_minimum_size = Vector2(100, 0)
		row.add_child(lbl)

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = pct
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(80, 8)
		row.add_child(bar)

		training_container.add_child(row)


func _update_soldiers(soldiers: Array) -> void:
	for child: Node in soldiers_container.get_children():
		soldiers_container.remove_child(child)
		child.free()

	if soldiers.is_empty():
		return

	for s_info: Dictionary in soldiers:
		var disp: String = s_info.get("display_name", "Soldier")
		var pwr: int = int(s_info.get("combat_power", 0))

		var lbl := Label.new()
		lbl.text = "⚔️ %s (Power: %d)" % [disp, pwr]
		lbl.add_theme_color_override("font_color", Inks.INK)
		lbl.add_theme_font_size_override("font_size", 12)
		soldiers_container.add_child(lbl)


func _on_accept_offer(offer_id: int) -> void:
	offer_accepted.emit(offer_id)
	if _host != null:
		GameplayPresenter.accept_offer(_host, offer_id)
		update_from_host(_host)


func _on_dismiss_offer(offer_id: int) -> void:
	offer_dismissed.emit(offer_id)
	if _host != null:
		GameplayPresenter.dismiss_offer(_host, offer_id)
		update_from_host(_host)


func _on_assign_peasant_to_worker() -> void:
	if first_peasant_id == -1:
		return
	peasant_promoted_to_worker.emit(first_peasant_id)
	if _host != null:
		GameplayPresenter.assign_peasant_to_worker(_host, first_peasant_id)
		update_from_host(_host)


func _on_assign_peasant_to_militia() -> void:
	if first_peasant_id == -1:
		return
	peasant_promoted_to_militia.emit(first_peasant_id)
	if _host != null:
		GameplayPresenter.assign_peasant_to_militia(_host, first_peasant_id)
		update_from_host(_host)
