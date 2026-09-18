## Unit tests for the catch-up resolution UX (T-UI-09) — Daredevil lane.
##
## Mirrors ui/screens/spread/catch_up_print.gd + the spread/intro seams.
## What is pinned:
##   - THE PRINT (pure): every row derives from the REAL report payload —
##     capped/uncapped/zero/rewound windows, per-type resource movement
##     (signed), arrivals/completions/promotions, the suspicion delta,
##     crackdowns-with-weight (STRIKE), run endings (STRIKE), the
##     FONT-METRIC no-clip line budget (every row variant measured in the
##     theme's real face against the live mounted quote label — the
##     round-1 re-dispatch fix; T-UI-06 standard), the single headline
##     voice shared by strip/blockquote/reveal;
##   - THE CHECK-IN (screen): a resumed boot opens the SHORT unfold over
##     the SAME hand (no re-deal), auto-opening with ZERO gestures
##     (reduced motion: synchronous), one gesture beating the auto from
##     all THREE input modes, the print landing after the fold (blockquote
##     + strip row; one quiet line for a nothing-happened window; the wry
##     line for a rewound clock), focus on the first actionable card, and
##     the dead-run chain (a run that ended inside the window prints,
##     then the loss-restart reveal deals the next hand);
##   - THE MID-SESSION foreground: the print lands on the LIVE table
##     (never popup chrome, focus untouched), a zero-tick foreground
##     prints nothing;
##   - THE SEAMS: GameHost.last_catch_up_report (the boot window is never
##     lost to mount order), the real report's crackdowns count (a
##     telegraph armed before the player left lands inside the window).
extends GdUnitTestSuite

const SPREAD_SCENE := "res://ui/screens/spread/spread_screen.tscn"
const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const IntroScreenScript := preload("res://ui/screens/intro/intro_screen.gd")

## Synthetic platform epochs (injected, never OS-read).
const T0 := 1_700_000_000
const CAP_SECONDS := 8 * 3600

var _dir_seq := 0


func after() -> void:
	MotionProfile.forced = -1
	Engine.time_scale = 1.0
	_erase_dir("user://cs_ui09_tests")
	get_window().size = Vector2i(720, 720)


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var dirs: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				dirs.append(entry)
			else:
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())


# --- report fixtures (the REAL payload shapes, docs/catch-up.md §7) ---------------


func _report(overrides := {}) -> Dictionary:
	var base := {
		"first_launch": false, "rewound": false, "capped": false,
		"skipped_paused": false,
		"elapsed_seconds": 2 * 3600, "clamped_seconds": 2 * 3600,
		"applied_ticks": 120, "from_tick": 180, "to_tick": 300,
		"cap_seconds": CAP_SECONDS, "cap_ticks": 480,
		"events_in_window": 12, "arrivals": 0, "training_completions": 0,
		"promotions": 0, "run_endings": 0, "crackdowns": 0,
		"resources_before": {}, "resources_after": {},
		"resource_delta": {},
		"suspicion_present": true, "suspicion_before": 0,
		"suspicion_after": 0, "suspicion_delta": 0,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


# --- the print: pure rows from the real payload ------------------------------------


func test_duration_phrase_is_the_tables_own_clock() -> void:
	assert_str(CatchUpPrint.duration_phrase(30)).is_equal("<1m")
	assert_str(CatchUpPrint.duration_phrase(42 * 60)).is_equal("42m")
	assert_str(CatchUpPrint.duration_phrase(2 * 3600)).is_equal("2h 00m")
	assert_str(CatchUpPrint.duration_phrase(8 * 3600 + 37 * 60)).is_equal("8h 37m")


func test_rows_capped_window_prints_elapsed_cap_resources_people_suspicion() -> void:
	var rows := CatchUpPrint.rows(_report({
		"capped": true, "elapsed_seconds": 9 * 3600 + 37 * 60,
		"clamped_seconds": CAP_SECONDS, "applied_ticks": 480,
		"arrivals": 3, "training_completions": 2, "promotions": 1,
		"resource_delta": {&"food": 62, &"timber": 18, &"iron": 0},
		"suspicion_before": 30, "suspicion_after": 36, "suspicion_delta": 6,
	}))
	var joined := ""
	for row: Dictionary in rows:
		joined += String(row["text"]) + "\n"
	# In task order: elapsed (the clamped window that actually applied),
	# the capped clause, per-type resources, the people summary, suspicion.
	assert_bool(joined.contains("8h 00m passed at the table")).is_true()
	assert_bool(joined.contains("crown's clock stops at 8 hours")).is_true()
	assert_bool(joined.contains("+62 food")).is_true()
	assert_bool(joined.contains("+18 timber")).is_true()
	assert_bool(joined.contains("+0 iron")).is_false()  # silent types stay silent
	assert_bool(joined.contains("3 came to the gate")).is_true()
	assert_bool(joined.contains("2 finished drills")).is_true()
	assert_bool(joined.contains("1 was promoted")).is_true()
	assert_bool(joined.contains("The Crown's eye: 30 to 36")).is_true()
	# Nothing moved with weight in this window: no STRIKE rows.
	for row: Dictionary in rows:
		assert_int(int(row["class"])).is_equal(Inks.LineClass.PLAIN)


func test_rows_uncapped_window_has_no_crown_clock_clause() -> void:
	var rows := CatchUpPrint.rows(_report())
	var joined := ""
	for row: Dictionary in rows:
		joined += String(row["text"])
	assert_bool(joined.contains("crown's clock")).is_false()
	assert_bool(joined.contains("2h 00m passed at the table")).is_true()


func test_rows_nothing_moved_stay_two_rows() -> void:
	var rows := CatchUpPrint.rows(_report())
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[1]["text"])).is_equal("The stores kept their count.")


func test_rows_rewound_leads_with_the_wry_line_and_stops() -> void:
	var rows := CatchUpPrint.rows(_report({
		"rewound": true, "elapsed_seconds": -3600, "clamped_seconds": 0,
		"applied_ticks": 0,
	}))
	assert_int(rows.size()).is_equal(1)
	assert_bool(String(rows[0]["text"]).contains("wound backwards")).is_true()
	assert_bool(String(rows[0]["text"]).contains("Nothing was lost")).is_true()


func test_rows_crackdown_and_run_ending_print_with_weight() -> void:
	var rows := CatchUpPrint.rows(_report({
		"crackdowns": 1, "run_endings": 1,
	}))
	var strike := 0
	var joined := ""
	for row: Dictionary in rows:
		joined += String(row["text"]) + "\n"
		if int(row["class"]) == Inks.LineClass.STRIKE:
			strike += 1
	assert_int(strike).is_equal(2)
	assert_bool(joined.contains("A crackdown landed while you were away")).is_true()
	assert_bool(joined.contains("The hand itself ended while you were away")).is_true()


func test_rows_negative_resource_movement_prints_signed() -> void:
	var rows := CatchUpPrint.rows(_report({
		"resource_delta": {&"food": -24, &"timber": 9},
	}))
	var joined := ""
	for row: Dictionary in rows:
		joined += String(row["text"])
	assert_bool(joined.contains("-24 food")).is_true()
	assert_bool(joined.contains("+9 timber")).is_true()


## The clip margin every row must clear BEYOND fitting: headroom for
## glyph and wide-digit drift (the round-1 FAIL's caution — a row that
## fits at EXACTLY the label width clips first when anything drifts).
const CLIP_MARGIN := 30.0


## THE FONT-METRIC NO-CLIP PIN (the round-1 verifier FAIL — the T-UI-06
## standard for this exact panel): EVERY row variant the print can
## compose is set through the REAL seam (`_deliver_catch_up`'s
## `open_quote_rows`) onto a LIVE mounted EventQuote, and each printed
## row's text is measured in the theme's own ChronicleLine face against
## the label it must fit: assert <= live label width - CLIP_MARGIN. The
## old <=66-character proxy PASSED while the crackdown STRIKE row
## measured 505px on the 476px label and clipped mid-word — wide glyphs
## make the char proxy leaky, so the metric is the pin and the character
## count stays only as a secondary guard.
func test_every_print_row_fits_the_label_in_real_font_metrics() -> void:
	MotionProfile.forced = 1
	var host := _host(20261122)
	var screen: SpreadScreen = await _mounted(host, false)
	# Every variant, at the widest shapes each template can carry: the
	# maximal window (every field hot, 4-digit signed deltas, the
	# steepest suspicion climb, BOTH strike rows), the plain uncapped
	# window, the nothing-moved window, the sub-minute headline, the
	# rewound wry line, the zero-tick quiet strip row.
	var variants: Array[Array] = [
		CatchUpPrint.rows(_report({
			"capped": true, "clamped_seconds": CAP_SECONDS,
			"arrivals": 5, "training_completions": 4, "promotions": 3,
			"resource_delta": {&"food": -2345, &"timber": 1999, &"iron": 1777},
			"suspicion_before": 5, "suspicion_after": 95, "suspicion_delta": 90,
			"crackdowns": 2, "run_endings": 1,
		})),
		CatchUpPrint.rows(_report({
			"arrivals": 1, "training_completions": 1, "promotions": 1,
			"resource_delta": {&"food": -24, &"timber": 9},
			"suspicion_before": 30, "suspicion_after": 36, "suspicion_delta": 6,
		})),
		CatchUpPrint.rows(_report()),
		CatchUpPrint.rows(_report({"clamped_seconds": 30, "elapsed_seconds": 30,
			"applied_ticks": 0})),
		CatchUpPrint.rows(_report({"rewound": true, "elapsed_seconds": -3600,
			"clamped_seconds": 0, "applied_ticks": 0})),
		[CatchUpPrint.quiet_row()],
	]
	var bounds := screen._design_bounds().size
	## The label budget itself, pinned against geometry drift: panel
	## min(560, bounds.x - 12), less 2*14 panel margins, 2*8 row insets,
	## the 30 rule and its 10 separation (the verifier's 476px at 720).
	var want_label := minf(560.0, bounds.x - 12.0) - 84.0
	## THE RENDER SIZE (the readability pass re-seam): the label's own
	## resolved "font_size" item — the declared ChronicleLine 24 since the
	## ladder raise — is the truth, and the pin asserts the render never
	## resolves UNDER it. (The old seam asked for the nonexistent "font"
	## item and measured at the theme default as an over-measure; with the
	## raised ladder that fallback would over-measure honest rows.)
	var declared := (load("res://ui/theme/spread_theme.tres") as Theme) \
		.get_font_size(&"font_size", &"ChronicleLine")
	assert_int(declared).is_equal(24)
	var texts: Array[String] = []
	for rows: Array in variants:
		var typed_rows: Array[Dictionary] = []
		typed_rows.assign(rows)
		screen._suspicion.open_quote_rows(typed_rows,
			bounds, screen._quote_floor(), 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var quote_lines: Array = screen._suspicion._quote._lines
		assert_int(quote_lines.size()).is_equal(rows.size())
		for i in quote_lines.size():
			var label := _chronicle_label_of(quote_lines[i])
			assert_that(label).is_not_null()
			if label == null:
				continue
			# The budget the rows are shaped against is the LIVE label.
			assert_float(label.size.x).is_equal_approx(want_label, 0.5)
			assert_int(label.get_theme_font_size(&"font_size")) \
				.is_greater_equal(declared)  # never under-render
			var width := label.get_theme_font("font").get_string_size(
				String(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size(&"font_size")).x
			assert_float(width).is_less_equal(label.size.x - CLIP_MARGIN)
			if not texts.has(String(label.text)):
				texts.append(String(label.text))
	# Every distinct row text was measured (the audit: maximal + plain +
	# nothing-moved + sub-minute + rewound + quiet, strikes included).
	assert_int(texts.size()).is_greater_equal(11)
	# Secondary guard (leaky alone, kept cheap): the character count.
	for text in texts:
		assert_int(text.length()).is_less_equal(CatchUpPrint.ROW_CHAR_BUDGET)
	screen.queue_free()


## The away line prints on the reveal PACKET (its own surface — the
## 560-wide lines band, WIDER than the quote label): every variant
## measured on a live mounted packet bound through the real presenter.
func test_every_away_line_fits_the_reveal_packet_in_real_font_metrics() -> void:
	var host := _host(20261123)
	var packet := IntroPacket.new()
	get_tree().root.add_child(packet)
	packet.size = Vector2(720, 720)
	await get_tree().process_frame
	for report in [{}, _report({"rewound": true}), _report(),
			_report({"capped": true, "clamped_seconds": CAP_SECONDS}),
			_report({"clamped_seconds": 30})]:
		packet.bind(IntroPresenter.reveal_view(host, true, report))
		await get_tree().process_frame
		await get_tree().process_frame
		for line: Control in packet._lines:
			var label := _chronicle_label_of(line)
			if label == null or String(label.text).is_empty():
				continue
			var width := label.get_theme_font("font").get_string_size(
				String(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size(&"font_size")).x
			assert_float(width).is_less_equal(label.size.x - CLIP_MARGIN)
	packet.queue_free()


## The printed row's Label (ChronicleLine -> HBox -> [rule, label]) —
## the T-UI-06 helper shape.
func _chronicle_label_of(row: Control) -> Label:
	for child in row.get_children():
		if child is HBoxContainer:
			for leaf in child.get_children():
				if leaf is Label:
					return leaf
	return null


func test_one_headline_voice_strip_quote_and_reveal_agree() -> void:
	var report := _report({"clamped_seconds": 2 * 3600 + 45 * 60})
	var headline := CatchUpPrint.headline_text(2 * 3600 + 45 * 60)
	assert_str(String(CatchUpPrint.headline_row(report)["text"])).is_equal(headline)
	var rows := CatchUpPrint.rows(report)
	assert_str(String(rows[0]["text"])).is_equal(headline)
	assert_bool(CatchUpPrint.away_line(report).contains("2h 45m")).is_true()


func test_quiet_row_is_one_plain_line() -> void:
	var row := CatchUpPrint.quiet_row()
	assert_int(int(row["class"])).is_equal(Inks.LineClass.PLAIN)
	assert_bool(String(row["text"]).contains("table kept still")).is_true()


# --- the check-in reveal (presenter + pacing) ---------------------------------------


func test_resumed_variant_is_forced_by_the_session_boundary() -> void:
	var host := _host(20261110)
	var view := IntroPresenter.reveal_view(host, true, {})
	assert_str(String(view["variant"])).is_equal(String(IntroPresenter.VARIANT_RESUMED))
	# Without the force, the chronicle still derives its own truth.
	assert_str(String(IntroPresenter.variant_for(host))).is_equal(
		String(IntroPresenter.VARIANT_FIRST_RUN))


func test_resumed_lines_read_the_leader_and_the_real_report() -> void:
	var host := _host(20261110)
	var view := IntroPresenter.reveal_view(host, true,
		_report({"clamped_seconds": 5 * 3600, "arrivals": 2}))
	var lines: Array = view["lines"]
	assert_int(lines.size()).is_equal(3)
	assert_bool(String(lines[0]["text"]).contains(host.run().leader_name().split(" ")[0])).is_true()
	assert_bool(String(lines[0]["text"]).contains("hour %d" % int(host.engine.sim_hours()))).is_true()
	assert_bool(String(lines[1]["text"]).contains("5h 00m")).is_true()
	assert_bool(String(lines[2]["text"]).contains("spread waits beneath")).is_true()


func test_resumed_unfold_is_faster_than_the_deal_inside_the_band() -> void:
	MotionProfile.forced = -1
	var resumed := IntroPresenter.unfold_seconds(IntroPresenter.VARIANT_RESUMED)
	var deal := IntroPresenter.unfold_seconds(IntroPresenter.VARIANT_FIRST_RUN)
	assert_float(resumed).is_less(deal)
	assert_float(resumed).is_greater_equal(0.5)
	assert_float(resumed).is_less_equal(1.5)
	MotionProfile.forced = 1
	assert_float(IntroPresenter.unfold_seconds(IntroPresenter.VARIANT_RESUMED)).is_less_equal(0.15)


# --- the host seams ------------------------------------------------------------------


func _host(run_seed: int, p_root := "") -> GameHost:
	var root := p_root
	if root.is_empty():
		_dir_seq += 1
		root = "user://cs_ui09_tests/h-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func test_last_catch_up_report_is_the_boot_seam() -> void:
	var host := _host(20261111)
	assert_bool(host.last_catch_up_report.is_empty()).is_true()  # fresh boot(0)
	host.fast_forward(60)
	host.background(T0)
	var report := host.foreground(T0 + 2 * 3600)
	assert_int(int(host.last_catch_up_report["applied_ticks"])).is_equal(120)
	assert_int(int(report["applied_ticks"])).is_equal(120)


func test_armed_telegraph_lands_inside_the_window_and_counts() -> void:
	## The rare-but-possible case: the player leaves with the telegraph
	## armed; the crackdown lands WHILE AWAY. Constructed through the
	## documented meter seam at 78 (the capture hook's discipline): at 1h
	## the early-rush gate is full (arrivals pause, no act bumps) and the
	## window's net movement is a slow presence rise (measured ~+2/h), so
	## the meter stays armed across the 4h land tick without nearing the
	## crush at 100.
	var host := _host(20261112)
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)  # a real running world
	host.suspicion().set_suspicion(78)
	host.fast_forward(2)
	assert_bool(host.suspicion().crackdown_land_tick != -1)  # armed
	host.background(T0)
	var report := host.foreground(T0 + 5 * 3600)  # the 4h land tick is inside
	assert_int(int(report["crackdowns"])).is_greater_equal(1)
	var rows := CatchUpPrint.rows(report)
	var strike_lines := 0
	for row: Dictionary in rows:
		if int(row["class"]) == Inks.LineClass.STRIKE:
			strike_lines += 1
	assert_int(strike_lines).is_greater_equal(1)  # printed with weight


# --- the resumed boot (screen) ----------------------------------------------------------


## One REAL away window across a process boundary: session 1 plays 3h and
## backgrounds (anchor + save on disk); session 2 boots the same root at
## T0+gap — the window resolves inside boot(), exactly the mount-order the
## last_catch_up_report seam exists for.
func _resumed_session(gap_seconds: int, p_seed := 20261113,
		prefix := "") -> Dictionary:
	_dir_seq += 1
	var root := "user://cs_ui09_tests/%sresume-%02d" % [prefix, _dir_seq]
	_erase_dir(root)
	var first := GameHost.new(p_seed, root)
	first.autosave_interval_ticks = 0
	first.boot(0)
	first.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
	first.background(T0)
	var resumed := GameHost.new(p_seed, root)
	resumed.autosave_interval_ticks = 0
	resumed.boot(T0 + gap_seconds)
	return {"first": first, "resumed": resumed}


func _mounted(host: GameHost, intro_on := true) -> SpreadScreen:
	var scene := load(SPREAD_SCENE) as PackedScene
	var screen: SpreadScreen = scene.instantiate()
	screen.host = host
	screen.intro_enabled = intro_on
	get_tree().root.add_child(screen)
	for i in 4:
		await get_tree().process_frame
	return screen


func test_resumed_boot_short_unfold_prints_and_lands_focus_synchronously() -> void:
	## Reduced motion: the whole check-in lands inside the mount's frames
	##  — reveal, auto-unfold (ZERO gestures), print, first-card focus.
	MotionProfile.forced = 1
	var session := _resumed_session(2 * 3600)
	var screen: SpreadScreen = await _mounted(session["resumed"])
	assert_int(screen.stats[&"intros_opened"]).is_equal(1)
	assert_int(screen.stats[&"intros_unfolded"]).is_equal(1)
	assert_int(screen._intro.interactions).is_equal(0)  # AUTO, not a gesture
	assert_bool(screen._intro.is_open()).is_false()
	# The print: the 2h window's blockquote + the strip's headline row.
	assert_int(screen.stats[&"catch_up_prints"]).is_equal(1)
	assert_bool(screen._suspicion.quote_is_open()).is_true()
	var rows := screen._suspicion.quote_rows()
	assert_bool(String(rows[0]["text"]).contains("2h 00m")).is_true()
	var strip := ""
	for row: Dictionary in screen.presenter.chronicle:
		strip += String(row["text"]) + "\n"
	assert_bool(strip.contains("2h 00m passed at the table")).is_true()
	# Focus landed on the table's first actionable card (a screen must
	# seed itself; the quote never owns focus).
	var focus := get_viewport().gui_get_focus_owner()
	assert_that(focus).is_not_null()
	if focus != null:
		assert_bool(focus.has_meta(&"spread_card_id")).is_true()
	# Never popup chrome.
	for node in screen.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	screen.queue_free()


func test_resumed_boot_zero_tick_window_prints_one_quiet_line() -> void:
	MotionProfile.forced = 1
	var session := _resumed_session(30)  # < 60s away: 0 ticks, nothing moved
	var screen: SpreadScreen = await _mounted(session["resumed"])
	assert_int(screen.stats[&"catch_up_prints"]).is_equal(0)
	assert_int(screen.stats[&"quiet_lines"]).is_equal(1)
	assert_bool(screen._suspicion.quote_is_open()).is_false()
	var strip := ""
	for row: Dictionary in screen.presenter.chronicle:
		strip += String(row["text"]) + "\n"
	assert_bool(strip.contains("table kept still")).is_true()
	screen.queue_free()


func test_resumed_boot_rewound_clock_prints_the_wry_line() -> void:
	MotionProfile.forced = 1
	var session := _resumed_session(-3600)  # the clock went BACKWARDS
	var screen: SpreadScreen = await _mounted(session["resumed"])
	assert_int(screen.stats[&"catch_up_prints"]).is_equal(1)
	var rows := screen._suspicion.quote_rows()
	assert_int(rows.size()).is_equal(1)
	assert_bool(String(rows[0]["text"]).contains("wound backwards")).is_true()
	# No accrual, no state change — the first session's world stands.
	assert_int(session["resumed"].engine.tick_count).is_greater_equal(
		session["first"].engine.tick_count)
	screen.queue_free()


func test_resumed_boot_auto_opens_itself_full_motion_no_gesture() -> void:
	## Full motion: the reveal dwells, then opens ITSELF (scaled clock —
	##  the T-UI-05 injected-time strategy; no wall waits).
	MotionProfile.forced = 0
	Engine.time_scale = 12.0
	var session := _resumed_session(2 * 3600)
	var screen: SpreadScreen = await _mounted(session["resumed"])
	assert_int(screen.stats[&"intros_opened"]).is_equal(1)
	assert_str(String(screen._intro.variant)).is_equal(
		String(IntroPresenter.VARIANT_RESUMED))
	for i in 240:
		await get_tree().process_frame
		if not screen._intro.is_open() and int(screen.stats[&"catch_up_prints"]) > 0:
			break
	assert_bool(screen._intro.is_open()).is_false()
	assert_int(screen._intro.interactions).is_zero()  # the AUTO half of the contract
	assert_int(screen.stats[&"intros_unfolded"]).is_equal(1)
	assert_int(screen.stats[&"catch_up_prints"]).is_equal(1)
	Engine.time_scale = 1.0
	screen.queue_free()


func test_one_gesture_beats_the_auto_all_three_modes() -> void:
	## Full motion, real clock speed: the gesture lands inside the dwell
	## from touch, pad and keyboard-equivalent (back) — each unfolds with
	## the SHORT variant's sweep and counts exactly one interaction.
	MotionProfile.forced = 0
	var seeds := [20261114, 20261115, 20261116]
	var modes := ["touch", "primary", "back"]
	for i in modes.size():
		var session := _resumed_session(2 * 3600, seeds[i], "gesture%d-" % i)
		var screen: SpreadScreen = await _mounted(session["resumed"])
		var intro := screen._intro
		assert_bool(intro.is_open()).is_true()
		match modes[i]:
			"touch":
				var touch := InputEventScreenTouch.new()
				touch.pressed = true
				touch.position = Vector2(360, 360)
				intro._gui_input(touch)
			"primary":
				var primary := InputEventAction.new()
				primary.action = &"primary"
				primary.pressed = true
				intro._unhandled_input(primary)
			"back":
				var back := InputEventAction.new()
				back.action = &"back"
				back.pressed = true
				intro._unhandled_input(back)
		assert_int(intro.state).is_equal(IntroScreenScript.State.UNFOLDING)
		assert_int(intro.interactions).is_equal(1)
		assert_float(intro.last_unfold_seconds) \
			.is_equal(IntroPresenter.unfold_seconds(IntroPresenter.VARIANT_RESUMED))
		# Finish the sweep on injected strides (never the wall clock).
		var strides := 0
		while intro.is_open() and strides < 32:
			intro._packet._process(intro.last_unfold_seconds / 8.0)
			strides += 1
		assert_bool(intro.is_open()).is_false()
		assert_int(screen.stats[&"catch_up_prints"]).is_equal(1)
		screen.queue_free()
		await get_tree().process_frame


func test_resumed_boot_dead_run_prints_then_deals_the_next_hand() -> void:
	## The hand ENDED inside the away window (a queued resolution verb
	##  draining on the window's first tick — real sim behavior, no test
	##  seams): the check-in prints the death with weight, then the
	##  loss-restart reveal deals the next hand after the quote's read.
	MotionProfile.forced = 1
	Engine.time_scale = 12.0
	_dir_seq += 1
	var root := "user://cs_ui09_tests/dead-%02d" % _dir_seq
	_erase_dir(root)
	var first := GameHost.new(20261117, root)
	first.autosave_interval_ticks = 0
	first.boot(0)
	first.fast_forward(2 * SimEngine.TICKS_PER_SIM_HOUR)
	first.submit(&"resolve_victory", &"loss", -1)  # queued — drains IN the window
	first.background(T0)
	var resumed := GameHost.new(20261117, root)
	resumed.autosave_interval_ticks = 0
	resumed.boot(T0 + 3600)
	assert_int(int(resumed.last_catch_up_report.get("run_endings", 0))).is_equal(1)
	var screen: SpreadScreen = await _mounted(resumed)
	assert_bool(screen._suspicion.quote_is_open()).is_true()
	var joined := ""
	for row: Dictionary in screen._suspicion.quote_rows():
		joined += String(row["text"]) + "\n"
	assert_bool(joined.contains("The hand itself ended while you were away")).is_true()
	# After the quote's dwell (scaled), the loss-restart reveal deals the
	# next hand through the real restart verbs.
	var dealt := false
	for i in 400:
		await get_tree().process_frame
		if screen._intro.is_open():
			dealt = true
			break
	assert_bool(dealt).is_true()
	assert_str(String(screen._intro.view()["variant"])) \
		.is_equal(String(IntroPresenter.VARIANT_LOSS_RESTART))
	assert_int(resumed.run().run_index).is_equal(2)
	assert_bool(resumed.is_run_running()).is_true()
	Engine.time_scale = 1.0
	screen.queue_free()


func test_resumed_print_places_the_quote_inside_the_design_both_orientations() -> void:
	MotionProfile.forced = 1
	for size in [Vector2i(720, 1280), Vector2i(1280, 800)]:
		get_window().size = size
		var session := _resumed_session(9 * 3600, 20261118, "orient-%dx%d-" % [size.x, size.y])
		var screen: SpreadScreen = await _mounted(session["resumed"])
		for i in 60:
			await get_tree().process_frame
			if screen._suspicion.quote_is_open() and screen.get_router().design_size().x > 1.0:
				break
		assert_bool(screen._suspicion.quote_is_open()).is_true()
		var quote: Control = screen._suspicion._quote
		var rect := quote.get_global_rect()
		var window_rect := Rect2(Vector2.ZERO, Vector2(size))
		assert_bool(window_rect.grow(1.0).encloses(rect)) \
			.is_true()  # inside the window in this orientation
		var joined := ""
		for row: Dictionary in screen._suspicion.quote_rows():
			joined += String(row["text"]) + "\n"
		assert_bool(joined.contains("crown's clock stops at 8 hours")).is_true()
		screen.queue_free()
		await get_tree().process_frame
	get_window().size = Vector2i(720, 720)


# --- the mid-session foreground (the live table) ------------------------------------


func test_mid_session_foreground_prints_on_the_live_table() -> void:
	MotionProfile.forced = 1
	var host := _host(20261119)
	var screen: SpreadScreen = await _mounted(host, false)  # the bare table
	host.fast_forward(2 * SimEngine.TICKS_PER_SIM_HOUR)
	# The player was holding a card when the app hid.
	var active := screen.get_active_slot() as OrientationSlot
	for child in active.get_spread().get_children():
		if child is Control and child.has_meta(&"spread_card_id"):
			child.grab_focus()
			break
	var held := get_viewport().gui_get_focus_owner()
	host.background(T0)
	var report := host.foreground(T0 + 9 * 3600 + 37 * 60)  # 9h37m -> capped
	assert_int(int(report["applied_ticks"])).is_equal(480)
	assert_bool(report["capped"]).is_true()
	assert_int(screen.stats[&"catch_up_prints"]).is_equal(1)
	assert_bool(screen._suspicion.quote_is_open()).is_true()
	var joined := ""
	for row: Dictionary in screen._suspicion.quote_rows():
		joined += String(row["text"]) + "\n"
	assert_bool(joined.contains("8h 00m passed at the table")).is_true()
	assert_bool(joined.contains("crown's clock stops at 8 hours")).is_true()
	# The strip's headline came through the unified drain — SAME voice.
	var strip := ""
	for row: Dictionary in screen.presenter.chronicle:
		strip += String(row["text"]) + "\n"
	assert_bool(strip.contains(CatchUpPrint.headline_text(CAP_SECONDS))).is_true()
	# The print never blocks: the held card still owns focus.
	assert_that(get_viewport().gui_get_focus_owner()).is_same(held)
	# Never popup chrome.
	for node in screen.get_children():
		assert_bool(node is Popup or node is Window or node is AcceptDialog).is_false()
	screen.queue_free()


func test_mid_session_zero_tick_foreground_prints_nothing() -> void:
	MotionProfile.forced = 1
	var host := _host(20261120)
	var screen: SpreadScreen = await _mounted(host, false)
	host.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
	host.background(T0)
	host.foreground(T0 + 30)  # half a minute: 0 ticks, not even a quiet line
	assert_int(screen.stats[&"catch_up_prints"]).is_zero()
	assert_int(screen.stats[&"quiet_lines"]).is_zero()
	assert_bool(screen._suspicion.quote_is_open()).is_false()
	screen.queue_free()


func test_fresh_boot_is_still_the_first_hand_deal() -> void:
	## Regression guard: the check-in beat never hijacks T-UI-05's entry.
	MotionProfile.forced = 1
	var host := _host(20261121)
	var screen: SpreadScreen = await _mounted(host)
	assert_bool(screen._intro.is_open()).is_true()
	assert_str(String(screen._intro.view()["variant"])) \
		.is_equal(String(IntroPresenter.VARIANT_FIRST_RUN))
	assert_int(screen.stats[&"catch_up_prints"]).is_zero()
	screen.queue_free()
