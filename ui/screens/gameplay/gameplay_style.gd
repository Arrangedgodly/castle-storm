## GameplayStyle — Visual styling, themes, and icon dressing for Castle Storm (T-07).
##
## Provides cohesive medieval parchment styling, custom button themes,
## and color-coded progress indicators across all gameplay viewport panels.
class_name GameplayStyle
extends RefCounted

# Color Tokens
const COLOR_GOLD := Color(0.82, 0.65, 0.22)
const COLOR_GOLD_LIGHT := Color(0.95, 0.82, 0.45)
const COLOR_CRIMSON := Color(0.65, 0.12, 0.12)
const COLOR_CRIMSON_BRIGHT := Color(0.85, 0.20, 0.20)
const COLOR_EMERALD := Color(0.18, 0.55, 0.28)
const COLOR_SLATE := Color(0.22, 0.25, 0.29)
const COLOR_PARCHMENT := Color(0.92, 0.87, 0.77)
const COLOR_PARCHMENT_LIGHT := Color(0.96, 0.93, 0.85)
const COLOR_PARCHMENT_DARK := Color(0.83, 0.77, 0.66)
const COLOR_INK := Color(0.12, 0.10, 0.08)
const COLOR_INK_MUTED := Color(0.38, 0.32, 0.26)

# Resource Icon Badges
const ICONS := {
	&"food": "🌾",
	&"timber": "🪵",
	&"iron": "⛏️",
	&"suspicion": "👁️",
	&"combat": "⚔️",
	&"militia": "🛡️",
	&"castle": "🏰",
	&"crown": "👑",
}


## Creates a customized parchment or slate panel StyleBoxFlat.
static func create_panel_style(
	bg: Color = COLOR_PARCHMENT,
	border: Color = COLOR_INK,
	border_width: int = 2,
	corner_radius: int = 4,
	margin: int = 8
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.set_content_margin_all(margin)
	return style


## Creates styled button states (normal, hover, pressed, disabled).
static func apply_button_style(
	btn: Button,
	bg: Color = COLOR_PARCHMENT_LIGHT,
	border: Color = COLOR_INK,
	font_color: Color = COLOR_INK
) -> void:
	if btn == null:
		return

	# Normal
	var normal := create_panel_style(bg, border, 1, 3, 6)
	btn.add_theme_stylebox_override("normal", normal)

	# Hover
	var hover := create_panel_style(bg.lightened(0.1), border.lightened(0.2), 2, 3, 6)
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed
	var pressed := create_panel_style(bg.darkened(0.1), border, 2, 3, 6)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Disabled
	var disabled := create_panel_style(COLOR_PARCHMENT_DARK.darkened(0.1), COLOR_INK_MUTED, 1, 3, 6)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_disabled_color", COLOR_INK_MUTED)


## Styles progress bars with custom background and fill styling.
static func apply_progress_bar_style(
	bar: ProgressBar,
	fill_color: Color,
	bg_color: Color = COLOR_PARCHMENT_DARK
) -> void:
	if bar == null:
		return

	var bg_box := StyleBoxFlat.new()
	bg_box.bg_color = bg_color
	bg_box.border_color = COLOR_INK_MUTED
	bg_box.border_width_left = 1
	bg_box.border_width_top = 1
	bg_box.border_width_right = 1
	bg_box.border_width_bottom = 1
	bg_box.corner_radius_top_left = 3
	bg_box.corner_radius_top_right = 3
	bg_box.corner_radius_bottom_left = 3
	bg_box.corner_radius_bottom_right = 3

	var fill_box := StyleBoxFlat.new()
	fill_box.bg_color = fill_color
	fill_box.corner_radius_top_left = 2
	fill_box.corner_radius_top_right = 2
	fill_box.corner_radius_bottom_left = 2
	fill_box.corner_radius_bottom_right = 2

	bar.add_theme_stylebox_override("background", bg_box)
	bar.add_theme_stylebox_override("fill", fill_box)


## Applies complete visual theme dressing across the GameplayScreen.
static func dress_gameplay_screen(screen: Control) -> void:
	if screen == null:
		return

	# Style HUD progress bar (crimson suspicion meter)
	var hud = screen.get("hud_bar")
	if hud != null and hud.get("suspicion_meter") != null:
		apply_progress_bar_style(hud.suspicion_meter, COLOR_CRIMSON_BRIGHT)

	# Style Siege progress bar (emerald win odds meter) and assault button
	var siege = screen.get("siege_panel")
	if siege != null:
		if siege.get("odds_meter") != null:
			apply_progress_bar_style(siege.odds_meter, COLOR_EMERALD)
		if siege.get("assault_button") != null:
			apply_button_style(
				siege.assault_button,
				COLOR_CRIMSON,
				COLOR_GOLD,
				COLOR_PARCHMENT_LIGHT
			)

	# Style Roster buttons
	var roster = screen.get("roster_panel")
	if roster != null:
		if roster.get("assign_worker_btn") != null:
			apply_button_style(roster.assign_worker_btn)
		if roster.get("assign_militia_btn") != null:
			apply_button_style(roster.assign_militia_btn)
