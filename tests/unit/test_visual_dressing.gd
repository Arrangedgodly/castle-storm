## Unit tests for GameplayStyle (T-07) — visual dressing, styling, and icon themes.
extends GdUnitTestSuite

const GameplayStyle := preload("res://ui/screens/gameplay/gameplay_style.gd")
const GameplayScreen := preload("res://ui/screens/gameplay/gameplay_screen.gd")


func test_create_panel_style_attributes() -> void:
	var style := GameplayStyle.create_panel_style(
		GameplayStyle.COLOR_PARCHMENT,
		GameplayStyle.COLOR_INK,
		3,
		6,
		10
	)
	assert_object(style).is_not_null()
	assert_float(style.bg_color.r).is_equal_approx(GameplayStyle.COLOR_PARCHMENT.r, 0.01)
	assert_int(style.border_width_left).is_equal(3)
	assert_int(style.corner_radius_top_left).is_equal(6)


func test_apply_button_style_overrides() -> void:
	var btn := Button.new()
	GameplayStyle.apply_button_style(btn)

	assert_object(btn.get_theme_stylebox("normal")).is_not_null()
	assert_object(btn.get_theme_stylebox("hover")).is_not_null()
	assert_object(btn.get_theme_stylebox("pressed")).is_not_null()
	assert_object(btn.get_theme_stylebox("disabled")).is_not_null()
	btn.free()


func test_apply_progress_bar_style_overrides() -> void:
	var bar := ProgressBar.new()
	GameplayStyle.apply_progress_bar_style(bar, GameplayStyle.COLOR_CRIMSON_BRIGHT)

	var fill_style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	assert_object(fill_style).is_not_null()
	assert_float(fill_style.bg_color.r).is_equal_approx(GameplayStyle.COLOR_CRIMSON_BRIGHT.r, 0.01)
	bar.free()


func test_dress_gameplay_screen_styles_children() -> void:
	var screen := GameplayScreen.new()
	GameplayStyle.dress_gameplay_screen(screen)

	# Verify HUD suspicion bar styled
	var susp_fill := screen.hud_bar.suspicion_meter.get_theme_stylebox("fill") as StyleBoxFlat
	assert_object(susp_fill).is_not_null()
	assert_float(susp_fill.bg_color.r).is_equal_approx(GameplayStyle.COLOR_CRIMSON_BRIGHT.r, 0.01)

	# Verify Siege odds meter styled
	var siege_fill := screen.siege_panel.odds_meter.get_theme_stylebox("fill") as StyleBoxFlat
	assert_object(siege_fill).is_not_null()
	assert_float(siege_fill.bg_color.g).is_equal_approx(GameplayStyle.COLOR_EMERALD.g, 0.01)

	# Verify Siege assault button styled
	var assault_normal := screen.siege_panel.assault_button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(assault_normal).is_not_null()
	assert_float(assault_normal.bg_color.r).is_equal_approx(GameplayStyle.COLOR_CRIMSON.r, 0.01)

	screen.free()
