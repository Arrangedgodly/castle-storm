## GameplayScreen — Unified playable strategy viewport for Castle Storm (T-06).
##
## Integrates HUD, Village & Production, Roster & Armory, Castle Siege,
## Tactical Siege combat view, and Clandestine Espionage into a unified interface.
class_name GameplayScreen
extends Control

const HUDBar := preload("res://ui/screens/gameplay/hud_bar.gd")
const VillagePanel := preload("res://ui/screens/gameplay/village_panel.gd")
const RosterPanel := preload("res://ui/screens/gameplay/roster_panel.gd")
const SiegePanel := preload("res://ui/screens/gameplay/siege_panel.gd")
const GameplayPresenter := preload("res://ui/screens/gameplay/gameplay_presenter.gd")
const GameplayStyle := preload("res://ui/screens/gameplay/gameplay_style.gd")
const TacticalSiegeView := preload("res://ui/screens/gameplay/tactical_siege_view.gd")
const TacticalSiegePresenter := preload("res://ui/screens/gameplay/tactical_siege_presenter.gd")
const TacticalSiegeResolver := preload("res://sim/systems/tactical_siege_resolver.gd")
const CovertOpsPanel := preload("res://ui/screens/gameplay/covert_ops_panel.gd")
const CovertOpsSystem := preload("res://sim/systems/covert_ops_system.gd")

var host: GameHost:
	set(value):
		host = value
		if is_inside_tree() and host != null:
			_bind_host()

# Subcomponents
var hud_bar: HUDBar
var village_panel: VillagePanel
var roster_panel: RosterPanel
var siege_panel: SiegePanel
var tab_container: TabContainer

# Tactical Siege & Espionage Subcomponents
var tactical_view: TacticalSiegeView
var tactical_siege: TacticalSiegeResolver
var covert_panel: CovertOpsPanel
var covert_system: CovertOpsSystem

# Dedicated tabs
var dashboard_hbox: HBoxContainer
var tab_village_wrapper: MarginContainer
var tab_roster_wrapper: MarginContainer
var tab_siege_wrapper: MarginContainer
var tab_tactical_wrapper: MarginContainer
var tab_covert_wrapper: MarginContainer

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
	siege_panel.tactical_siege_initiated.connect(_on_tactical_siege_initiated)
	dashboard_hbox.add_child(siege_panel)

	tab_container.add_child(dash_margin)

	# Tab 1: Tactical Siege View
	tab_tactical_wrapper = MarginContainer.new()
	tab_tactical_wrapper.name = "🏹 Tactical Siege"
	tab_tactical_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_tactical_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_tactical_wrapper.add_theme_constant_override("margin_left", 8)
	tab_tactical_wrapper.add_theme_constant_override("margin_top", 8)
	tab_tactical_wrapper.add_theme_constant_override("margin_right", 8)
	tab_tactical_wrapper.add_theme_constant_override("margin_bottom", 8)

	tactical_view = TacticalSiegeView.new()
	tactical_view.tactic_selected.connect(_on_tactical_tactic_selected)
	tactical_view.retreat_requested.connect(_on_tactical_retreat_requested)
	tactical_view.siege_closed.connect(_on_tactical_siege_closed)
	tab_tactical_wrapper.add_child(tactical_view)
	tab_container.add_child(tab_tactical_wrapper)

	# Tab 2: Espionage & Infiltration
	tab_covert_wrapper = MarginContainer.new()
	tab_covert_wrapper.name = "🕵️ Espionage"
	tab_covert_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_covert_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_covert_wrapper.add_theme_constant_override("margin_left", 8)
	tab_covert_wrapper.add_theme_constant_override("margin_top", 8)
	tab_covert_wrapper.add_theme_constant_override("margin_right", 8)
	tab_covert_wrapper.add_theme_constant_override("margin_bottom", 8)

	covert_system = CovertOpsSystem.new()
	covert_panel = CovertOpsPanel.new()
	covert_panel.operation_executed.connect(_on_covert_operation_executed)
	tab_covert_wrapper.add_child(covert_panel)
	tab_container.add_child(tab_covert_wrapper)

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


## Binds an active GameHost instance to all screens and views.
func setup_host(game_host: GameHost) -> void:
	self.host = game_host
	if host != null:
		_bind_host()


func _bind_host() -> void:
	if host == null:
		return

	if not host.sim_advanced.is_connected(refresh):
		host.sim_advanced.connect(refresh)

	if covert_panel != null:
		covert_panel.setup_host(host, covert_system)

	refresh()


## Refreshes all active subcomponents from the GameHost.
func refresh() -> void:
	if host == null:
		return

	hud_bar.update_from_host(host)
	village_panel.update_from_host(host)
	roster_panel.update_from_host(host)
	siege_panel.update_from_host(host)
	if covert_panel != null:
		covert_panel.refresh()
	_refresh_tactical_view()


func _on_tactical_siege_initiated() -> void:
	if host == null or host.engine == null:
		return
	tactical_siege = TacticalSiegeResolver.new(host.engine)
	var start_event := tactical_siege.start_siege(host.engine, covert_system)
	event_ticker_label.text = "Chronicle: " + str(start_event.get("text", "The siege begins!"))
	_refresh_tactical_view()
	# Switch to tactical siege tab
	tab_container.current_tab = 1


func _on_tactical_tactic_selected(tactic_id: StringName) -> void:
	if tactical_siege == null:
		return
	var res := TacticalSiegePresenter.execute_tactic(tactical_siege, tactic_id)
	event_ticker_label.text = "Chronicle: " + str(res.get("text", "Tactical order executed."))
	_refresh_tactical_view()
	refresh()


func _on_tactical_retreat_requested() -> void:
	if tactical_siege == null:
		return
	var res := TacticalSiegePresenter.order_retreat(tactical_siege)
	event_ticker_label.text = "Chronicle: " + str(res.get("text", "Retreat sounded!"))
	_refresh_tactical_view()
	refresh()


func _on_tactical_siege_closed() -> void:
	tab_container.current_tab = 0


func _on_covert_operation_executed(result: Dictionary) -> void:
	if result.has("text"):
		event_ticker_label.text = "Chronicle: " + str(result["text"])
	refresh()


func _refresh_tactical_view() -> void:
	if tactical_view == null:
		return
	var view_data := TacticalSiegePresenter.format_siege_view(tactical_siege)
	tactical_view.bind_view(view_data)


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
