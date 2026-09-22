## GameplayScreen — Unified Playable Game Viewport for Castle Storm (T-06).
##
## Composes the HUDBar, VillagePanel, RosterPanel, and SiegePanel into an
## intuitive, accessible, multi-view medieval strategy dashboard.
class_name GameplayScreen
extends Control

const HUDBar := preload("res://ui/screens/gameplay/hud_bar.gd")
const VillagePanel := preload("res://ui/screens/gameplay/village_panel.gd")
const RosterPanel := preload("res://ui/screens/gameplay/roster_panel.gd")
const SiegePanel := preload("res://ui/screens/gameplay/siege_panel.gd")
const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")
const GameplayStyle := preload("res://ui/screens/gameplay/gameplay_style.gd")

var host: GameHost:
	set(value):
		host = value
		if is_inside_tree() and host != null:
			_bind_host()

# Sub-components
var hud_bar: HUDBar
var village_panel: VillagePanel
var roster_panel: RosterPanel
var siege_panel: SiegePanel
var tab_container: TabContainer

# Dedicated tabs
var dashboard_hbox: HBoxContainer
var tab_village_wrapper: MarginContainer
var tab_roster_wrapper: MarginContainer
var tab_siege_wrapper: MarginContainer

# Status & Event ticker
var event_ticker_label: Label


func _init() -> void:
	_build_ui()


func _ready() -> void:
	if host != null:
		_bind_host()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Root background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Inks.NEUTRAL_GROUND
	add_child(bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	# --- 1. Top HUD Bar ---
	hud_bar = HUDBar.new()
	root_vbox.add_child(hud_bar)

	# --- 2. Main Content Area with Tab Container ---
	tab_container = TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_theme_font_size_override("font_size", 14)
	root_vbox.add_child(tab_container)

	# Tab 0: Overview Dashboard (3-column layout)
	var dash_margin := MarginContainer.new()
	dash_margin.name = "🏰 Dashboard"
	dash_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dash_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dash_margin.add_theme_constant_override("margin_left", 8)
	dash_margin.add_theme_constant_override("margin_top", 8)
	dash_margin.add_theme_constant_override("margin_right", 8)
	dash_margin.add_theme_constant_override("margin_bottom", 8)

	dashboard_hbox = HBoxContainer.new()
	dashboard_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dashboard_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dashboard_hbox.add_theme_constant_override("separation", 8)
	dash_margin.add_child(dashboard_hbox)

	village_panel = VillagePanel.new()
	village_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	village_panel.size_flags_stretch_ratio = 1.0
	dashboard_hbox.add_child(village_panel)

	roster_panel = RosterPanel.new()
	roster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_panel.size_flags_stretch_ratio = 1.0
	dashboard_hbox.add_child(roster_panel)

	siege_panel = SiegePanel.new()
	siege_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	siege_panel.size_flags_stretch_ratio = 0.9
	dashboard_hbox.add_child(siege_panel)

	tab_container.add_child(dash_margin)

	# --- 3. Bottom Ticker & Controls ---
	var bottom_bar := PanelContainer.new()
	bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Inks.PAPER_DIM
	b_style.border_color = Inks.INK
	b_style.border_width_top = 1
	b_style.set_content_margin_all(6)
	bottom_bar.add_theme_stylebox_override("panel", b_style)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_theme_constant_override("separation", 12)
	bottom_bar.add_child(bottom_hbox)

	event_ticker_label = Label.new()
	event_ticker_label.text = "Chronicle: The realm whispers in the dark. Plan your revolt."
	event_ticker_label.add_theme_color_override("font_color", Inks.INK)
	event_ticker_label.add_theme_font_size_override("font_size", 12)
	event_ticker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(event_ticker_label)

	var pass_hour_btn := Button.new()
	pass_hour_btn.text = "Advance 1h"
	pass_hour_btn.pressed.connect(_on_advance_1h)
	bottom_hbox.add_child(pass_hour_btn)

	var pass_day_btn := Button.new()
	pass_day_btn.text = "Advance 24h"
	pass_day_btn.pressed.connect(_on_advance_24h)
	bottom_hbox.add_child(pass_day_btn)

	root_vbox.add_child(bottom_bar)

	# Apply theme styling
	GameplayStyle.dress_gameplay_screen(self)


func _bind_host() -> void:
	if host == null:
		return

	if not host.sim_advanced.is_connected(refresh):
		host.sim_advanced.connect(refresh)

	refresh()


## Refreshes all active subcomponents from the GameHost.
func refresh() -> void:
	if host == null:
		return

	hud_bar.update_from_host(host)
	village_panel.update_from_host(host)
	roster_panel.update_from_host(host)
	siege_panel.update_from_host(host)


func _on_advance_1h() -> void:
	if host == null:
		return
	# 60 fixed ticks per hour
	host.advance_ticks(60)
	refresh()


func _on_advance_24h() -> void:
	if host == null:
		return
	# 24 * 60 ticks
	host.advance_ticks(1440)
	refresh()
