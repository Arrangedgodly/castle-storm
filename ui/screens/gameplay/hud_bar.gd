## HUDBar — Top navigation and vital status bar for Castle Storm (T-02).
##
## Displays leader metadata, sim clock, resource stockpiles with hourly rates,
## and a real-time suspicion meter.
class_name HUDBar
extends PanelContainer

const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")

# Nodes
var leader_label: Label
var regime_label: Label
var time_label: Label
var food_label: Label
var timber_label: Label
var iron_label: Label
var suspicion_label: Label
var suspicion_meter: ProgressBar
var warn_badge: Label

# Cached resource label map
var resource_labels: Dictionary = {}


func _init() -> void:
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 52)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Frame style
	var style := StyleBoxFlat.new()
	style.bg_color = Inks.PAPER_DIM
	style.border_color = Inks.INK
	style.border_width_bottom = 2
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

	# --- Left: Leader & World info ---
	var leader_vbox := VBoxContainer.new()
	leader_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 8)
	leader_vbox.add_child(top_line)

	leader_label = Label.new()
	leader_label.text = "Conspirator Leader"
	leader_label.add_theme_color_override("font_color", Inks.INK)
	leader_label.add_theme_font_size_override("font_size", 14)
	top_line.add_child(leader_label)

	regime_label = Label.new()
	regime_label.text = "(Regime)"
	regime_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	regime_label.add_theme_font_size_override("font_size", 12)
	top_line.add_child(regime_label)

	time_label = Label.new()
	time_label.text = "Day 1, 00:00"
	time_label.add_theme_color_override("font_color", Inks.INK_SOFT)
	time_label.add_theme_font_size_override("font_size", 11)
	leader_vbox.add_child(time_label)

	hbox.add_child(leader_vbox)

	# --- Center: Resource counters ---
	var res_hbox := HBoxContainer.new()
	res_hbox.add_theme_constant_override("separation", 16)
	res_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	food_label = _create_resource_item(res_hbox, &"food", "Food")
	timber_label = _create_resource_item(res_hbox, &"timber", "Timber")
	iron_label = _create_resource_item(res_hbox, &"iron", "Iron")

	resource_labels[&"food"] = food_label
	resource_labels[&"timber"] = timber_label
	resource_labels[&"iron"] = iron_label

	hbox.add_child(res_hbox)

	# --- Right: Suspicion Meter & Warn Badge ---
	var susp_vbox := VBoxContainer.new()
	susp_vbox.custom_minimum_size = Vector2(180, 0)
	susp_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var susp_top := HBoxContainer.new()
	susp_top.add_theme_constant_override("separation", 6)

	var susp_title := Label.new()
	susp_title.text = "Suspicion:"
	susp_title.add_theme_color_override("font_color", Inks.INK)
	susp_title.add_theme_font_size_override("font_size", 12)
	susp_top.add_child(susp_title)

	suspicion_label = Label.new()
	suspicion_label.text = "0 / 100"
	suspicion_label.add_theme_color_override("font_color", Inks.INK)
	suspicion_label.add_theme_font_size_override("font_size", 12)
	susp_top.add_child(suspicion_label)

	warn_badge = Label.new()
	warn_badge.text = "[ ALERT ]"
	warn_badge.visible = false
	warn_badge.add_theme_color_override("font_color", Inks.RED)
	warn_badge.add_theme_font_size_override("font_size", 11)
	susp_top.add_child(warn_badge)

	susp_vbox.add_child(susp_top)

	suspicion_meter = ProgressBar.new()
	suspicion_meter.min_value = 0.0
	suspicion_meter.max_value = 100.0
	suspicion_meter.value = 0.0
	suspicion_meter.show_percentage = false
	suspicion_meter.custom_minimum_size = Vector2(160, 8)
	susp_vbox.add_child(suspicion_meter)

	hbox.add_child(susp_vbox)


func _create_resource_item(parent: Container, res_id: StringName, label_text: String) -> Label:
	var item_box := HBoxContainer.new()
	item_box.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = "%s:" % label_text
	name_lbl.add_theme_color_override("font_color", Inks.INK_SOFT)
	name_lbl.add_theme_font_size_override("font_size", 12)
	item_box.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "0 (+0/h)"
	val_lbl.add_theme_color_override("font_color", Inks.INK)
	val_lbl.add_theme_font_size_override("font_size", 12)
	item_box.add_child(val_lbl)

	parent.add_child(item_box)
	return val_lbl


## Updates the HUD bar directly from an active GameHost instance.
func update_from_host(host: GameHost) -> void:
	if host == null:
		return
	var data: Dictionary = GameplayPresenter.get_hud_data(host)
	bind_hud_data(data)


## Pure data-binding interface from the HUD data Dictionary.
func bind_hud_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Leader
	var leader_name: String = data.get("leader_name", "Unknown")
	var leader_epithet: String = data.get("leader_epithet", "")
	if leader_epithet.is_empty():
		leader_label.text = leader_name
	else:
		leader_label.text = "%s, %s" % [leader_name, leader_epithet]

	# Regime
	var regime_name: String = data.get("regime_name", "")
	var run_idx: int = int(data.get("run_index", 1))
	regime_label.text = "· %s (Run %d)" % [regime_name if not regime_name.is_empty() else "The Realm", run_idx]

	# Time
	var sim_hours: float = float(data.get("sim_hours", 0.0))
	var day: int = int(sim_hours / 24.0) + 1
	var hour_in_day: int = int(sim_hours) % 24
	var minute_fraction: int = int((sim_hours - floorf(sim_hours)) * 60.0)
	time_label.text = "Day %d · %02d:%02d" % [day, hour_in_day, minute_fraction]

	# Resources
	var res_map: Dictionary = data.get("resources", {})
	for res_id: StringName in res_map:
		var r_data: Dictionary = res_map[res_id]
		var amount: int = int(r_data.get("amount", 0))
		var rate: float = float(r_data.get("rate_per_hour", 0.0))
		var lbl: Label = resource_labels.get(res_id)
		if lbl != null:
			var sign_str := "+" if rate >= 0.0 else ""
			lbl.text = "%d (%s%.1f/h)" % [amount, sign_str, rate]

	# Suspicion
	var susp_cur: int = int(data.get("suspicion_points", 0))
	var susp_max: int = int(data.get("suspicion_max", 100))
	var is_warned: bool = bool(data.get("is_warned", false))

	suspicion_label.text = "%d / %d" % [susp_cur, susp_max]
	suspicion_meter.max_value = float(susp_max)
	suspicion_meter.value = float(susp_cur)
	warn_badge.visible = is_warned
