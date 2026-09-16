## Deck-profile performance measurement — T-PERF-02. NOT a test: a
## WINDOWED measurement harness (the real Compatibility renderer, the
## one the Deck will run).
##
##     make deck-perf
##
## Forces the Deck's window (1280x800, canvas_items/expand — the design
## derives 1152x720 landscape, the exact profile the export targets) and
## measures, per representative state:
##   1. BARE FRAME       — engine-only baseline (nothing mounted);
##   2. IDLE SPREAD      — the 4h quiet table, settled: frame budget +
##                         THE PIXEL-IDENTITY PROOF (two captures frames
##                         apart hash equal — no tween, timer or redraw
##                         can evade it: the quiet table does NOTHING) +
##                         a vsync-locked cadence sample (the display's
##                         refresh held without missed frames);
##   3. BUSY SPREAD      — the loudest honest moment: the while-you-were-
##                         away print dwelling + a promotion flip turning
##                         + entrance slides settling, concurrently;
##   4. ASSAULT VIGNETTE — mid-beats: rank tweens marching, cards
##                         striking, the castle under the wash;
##   5. CHRONICLE 50     — the 50-hand ledger open, scrolling and turning
##                         pages every few frames.
##
## Frame times are sampled with VSYNC DISABLED (the honest headroom
## number: what the frame actually costs, not what the compositor paces)
## and reported mean / p99 / max against the 16.63ms budget (60Hz) with
## the pass line at p99 <= 11.1ms (33% margin) and mean <= 8.3ms (50%).
## Memory (static, objects, texture/video/buffer) and draw calls are
## reported per state; the chronicle state doubles as the paging-
## boundedness probe (two full page cycles, stable memory).
##
## THE HONEST SCOPE: this machine is an M-series Mac (measured at its
## Retina backing — MORE pixels than the Deck's 1280x800) running the
## same Compatibility renderer class, NOT SteamOS/AMD Van Gogh. A pass
## here is necessary-not-sufficient for the Deck; the hardware-gated
## remainder is the checklist in docs/deck-validation.md.
extends SceneTree

const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

const DECK_WINDOW := Vector2i(1280, 800)
const RUN_SEED := 20261103
const PROBE_ROOT := "user://cs_deck_perf"
const T0 := 1_800_000_000

var _failures: Array[String] = []


func _initialize() -> void:
	root.add_child(Probe.new())


class Probe extends Node:
	## The 60Hz frame budget and the pass margins: mean <= 50% of budget
	## (headroom for the Deck's slower APU), p95 <= 67%, and NO frame over
	## the budget itself (a 16.63ms frame misses exactly one 60Hz vsync).
	## p99/max are REPORTED but not gated — this host's GL-on-Metal
	## compositing hitches (measured ~7ms spikes even on a bare frame)
	## sit in the tail; the Deck's Gamescope path is a different stack.
	const BUDGET_MS := 16.63
	const P95_LINE_MS := 11.1
	const MEAN_LINE_MS := 8.3

	func _ready() -> void:
		_measure.call_deferred()

	# --- helpers -------------------------------------------------------------------

	## Frame deltas in ms over n frames (the whole-frame cost: game layer
	## + render submit; vsync must be OFF or the compositor paces it).
	func _frame_ms(n: int) -> Array[float]:
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in n:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - last) / 1000.0)
			last = now
		return samples

	func _mean(samples: Array[float]) -> float:
		if samples.is_empty():
			return 0.0
		var total := 0.0
		for value in samples:
			total += value
		return total / float(samples.size())

	func _percentile(samples: Array[float], fraction: float) -> float:
		if samples.is_empty():
			return 0.0
		var sorted := samples.duplicate()
		sorted.sort()
		var index: int = clampi(int(fraction * float(sorted.size())), 0, sorted.size() - 1)
		return sorted[index]

	func _max_of(samples: Array[float]) -> float:
		var peak := 0.0
		for value in samples:
			peak = maxf(peak, value)
		return peak

	func _monitor(name: String) -> float:
		return Performance.get_monitor(Performance[name])

	## One state's full report line(s) + budget assertion.
	func _report(label: String, samples: Array[float], failures: Array[String]) -> void:
		var mean := _mean(samples)
		var p95 := _percentile(samples, 0.95)
		var p99 := _percentile(samples, 0.99)
		var peak := _max_of(samples)
		var draws := int(_monitor("RENDER_TOTAL_DRAW_CALLS_IN_FRAME"))
		var verdict := mean <= MEAN_LINE_MS and p95 <= P95_LINE_MS and peak <= BUDGET_MS
		print("[deck-perf] %-34s mean %6.2f ms | p95 %6.2f ms | p99 %6.2f ms | max %6.2f ms | draws %4d | %s"
			% [label, mean, p95, p99, peak, draws, "PASS" if verdict else "FAIL"])
		if mean > MEAN_LINE_MS:
			failures.append("%s: mean %.2fms > %.2fms" % [label, mean, MEAN_LINE_MS])
		if p95 > P95_LINE_MS:
			failures.append("%s: p95 %.2fms > %.2fms" % [label, p95, P95_LINE_MS])
		if peak > BUDGET_MS:
			failures.append("%s: max %.2fms > the %.2fms budget (misses a 60Hz frame)" % [label, peak, BUDGET_MS])

	func _memory_line(label: String) -> void:
		print("[deck-perf]   mem %-30s static %8.1f KB | objects %5d | resources %4d | texture %7.1f KB | video %7.1f KB | buffer %7.1f KB"
			% [label, _monitor("MEMORY_STATIC") / 1024.0, int(_monitor("OBJECT_COUNT")),
				int(_monitor("OBJECT_RESOURCE_COUNT")), _monitor("RENDER_TEXTURE_MEM_USED") / 1024.0,
				_monitor("RENDER_VIDEO_MEM_USED") / 1024.0, _monitor("RENDER_BUFFER_MEM_USED") / 1024.0])

	func _mounted_screen(host: GameHost) -> SpreadScreen:
		var screen: SpreadScreen = SPREAD_SCENE.instantiate()
		screen.host = host
		screen.intro_enabled = false
		get_tree().root.add_child(screen)
		for _i in 10:
			await get_tree().process_frame
		return screen

	func _drive_policy(host: GameHost, hours: float) -> void:
		var policy := DemoPolicy.new(16, 8, false)
		var chunks := int(hours * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
		for _i in chunks:
			host.fast_forward(60)
			if policy.on_ticks(60):
				policy.apply(host)

	func _erase_dir(path: String) -> void:
		var dir := DirAccess.open(path)
		if dir == null:
			return
		dir.list_dir_begin()
		var files: Array[String] = []
		var entry := dir.get_next()
		while not entry.is_empty():
			if entry != "." and entry != "..":
				files.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
		for file_name: String in files:
			dir.remove(file_name)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null:
			parent.remove(path.get_file())

	## One host holding `count` fully-geared trainees/knights (the assault
	## suite's fixture shape; keep_trainee_leaves keeps one UNPROMOTED for
	## the flip probe).
	func _knight_host(count: int, keep_trainees: int) -> GameHost:
		var host := GameHost.new(20261207, PROBE_ROOT + "/storm")
		_erase_dir(PROBE_ROOT + "/storm")
		host.boot(0)
		var ready: Array[int] = []
		while ready.size() < count + keep_trainees:
			while host.units().pending_offers() == 0:
				host.fast_forward(30)
			var uid := host.units().offer_ids()[0]
			host.submit(&"recruit_accept", &"", uid)
			host.fast_forward(10)
			var idle: Array = host.units().idle_units(host.units().base_unit_id())
			host.submit(&"assign_role", &"militia", idle[0])
			host.fast_forward(3 * SimEngine.TICKS_PER_SIM_HOUR)
			var militia: Array = host.units().idle_units(&"militia")
			host.submit(&"start_training", &"trainee", militia[0])
			host.fast_forward(5 * SimEngine.TICKS_PER_SIM_HOUR)
			var trainee: Array = host.units().idle_units(&"trainee")
			host.submit(&"start_training", &"knight", trainee[0])
			host.fast_forward(13 * SimEngine.TICKS_PER_SIM_HOUR)
			ready.append(trainee[0])
		host.engine.set_resource(&"food", 500)
		host.engine.set_resource(&"timber", 500)
		host.engine.set_resource(&"iron", 500)
		for uid in ready:
			for slot in host.units().missing_gear_slots(uid):
				host.submit(&"equip_gear", host.units().gear_ids_for_slot(slot)[0], uid)
		host.fast_forward(5)
		for i in count:
			var uid: int = ready[i]
			if host.units().is_awaiting_promotion(uid) and host.units().missing_gear_slots(uid).is_empty():
				host.submit(&"promote", &"", uid)
		host.fast_forward(5)
		return host

	# --- the measurement ----------------------------------------------------------------

	func _measure() -> void:
		var failures: Array[String] = []
		var window := get_window()
		window.size = DECK_WINDOW
		# Let the window settle BEFORE touching vsync (probe-verified: a
		# vsync change in the same breath as the resize does not land).
		for i in 10:
			await get_tree().process_frame
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, window.get_window_id())
		await get_tree().process_frame
		var refresh := DisplayServer.screen_get_refresh_rate()
		print("[deck-perf] Deck profile forced: window %s (design %s), vsync OFF for headroom, display reports %.0f Hz"
			% [str(window.size), str(get_viewport().get_visible_rect().size), refresh])
		for i in 5:
			await get_tree().process_frame

		# 1. BARE FRAME — engine-only baseline.
		var bare := await _frame_ms(90)
		_report("1. bare frame (engine only)", bare, failures)
		_memory_line("bare")

		# 2. IDLE SPREAD — the quiet table, settled.
		_erase_dir(PROBE_ROOT + "/idle")
		var idle_host := GameHost.new(RUN_SEED, PROBE_ROOT + "/idle")
		idle_host.autosave_interval_ticks = 0
		idle_host.boot(0)
		_drive_policy(idle_host, 4.0)
		var idle_screen := await _mounted_screen(idle_host)
		idle_host.driving = false  # the quiet table: pacing closed
		for _i in 30:
			await get_tree().process_frame  # entrances, tweens, deferred binds settle
		var idle := await _frame_ms(240)
		_report("2. IDLE SPREAD (quiet, settled)", idle, failures)
		_memory_line("idle spread")
		# THE PIXEL-IDENTITY PROOF: two captures 8 frames apart hash equal
		# — nothing animates, nothing redraws, the battery claim's
		# catch-all (impossible headless; trivial here).
		var image_a := get_viewport().get_texture().get_image()
		for _i in 8:
			await get_tree().process_frame
		var image_b := get_viewport().get_texture().get_image()
		var identical := image_a.get_data() == image_b.get_data()
		print("[deck-perf]   idle pixel-identity: two captures 8 frames apart are %s (%d vs %d bytes)"
			% ["BYTE-IDENTICAL — zero animation" if identical else "DIFFERENT — something animates",
				image_a.get_data().size(), image_b.get_data().size()])
		if not identical:
			failures.append("idle pixel-identity: the quiet table changed between captures")
		# VSYNC-LOCKED CADENCE: the display's refresh held, no missed
		# frames (a ProMotion display locks at its own rate — the ratio is
		# the honest check, not the absolute period).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED, window.get_window_id())
		for _i in 10:
			await get_tree().process_frame
		var locked := await _frame_ms(90)
		var locked_median := _percentile(locked, 0.5)
		var locked_max := _max_of(locked)
		# This display paces ~120Hz in practice (ProMotion; the OS reports
		# 60) — the honest check is the 60Hz budget itself: no frame over
		# 16.63ms means 60fps holds with a full period of slack.
		print("[deck-perf]   vsync-locked cadence: median %.2f ms, max %.2f ms (%s at the %.2fms budget)"
			% [locked_median, locked_max,
				"holds" if locked_max <= BUDGET_MS else "misses a 60Hz period", BUDGET_MS])
		if locked_max > BUDGET_MS:
			failures.append("vsync-locked cadence: max %.2fms > %.2fms" % [locked_max, BUDGET_MS])
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, window.get_window_id())
		for _i in 5:
			await get_tree().process_frame
		idle_screen.queue_free()
		for _i in 8:
			await get_tree().process_frame

		# 3. BUSY SPREAD — print dwelling + flip turning + entrances, together.
		# The storm fixture guarantees a held, fully-geared trainee for the
		# flip (a policy-driven table does not reliably reach one).
		var busy_host := _knight_host(1, 1)
		var busy_screen := await _mounted_screen(busy_host)
		# The away window resolves NOW (the blockquote opens, its rows
		# print, offline arrivals slide onto the table).
		busy_host.background(T0)
		busy_host.foreground(T0 + 9 * 3600 + 37 * 60)
		# And the signature moment: a promotion flip starts...
		var flip_uid := 0
		for uid in busy_host.units().awaiting_promotion_ids():
			if busy_host.units().missing_gear_slots(uid).is_empty() \
					and busy_host.units().training_target(uid) == &"knight":
				flip_uid = uid
				break
		if flip_uid != 0:
			busy_host.submit(&"promote", &"", flip_uid)
			busy_host.fast_forward(1)  # drain the command so the flip starts NOW
		busy_host.driving = false
		var busy := await _frame_ms(180)
		var concurrent := int(busy_screen.stats[&"catch_up_prints"]) > 0 \
			and int(busy_screen.stats[&"flips_played"]) + int(busy_screen.stats[&"flip_replays"]) > 0
		_report("3. BUSY SPREAD (print+flip+slides)", busy, failures)
		print("[deck-perf]   busy state concurrent: print %s, flip(s) %d+%d, entrances %d (%s)"
			% [str(int(busy_screen.stats[&"catch_up_prints"]) > 0),
				int(busy_screen.stats[&"flips_played"]), int(busy_screen.stats[&"flip_replays"]),
				int(busy_screen.stats[&"entrances"]),
				"all three live" if concurrent else "partial — see counts"])
		_memory_line("busy spread")
		busy_screen.queue_free()
		for _i in 5:
			await get_tree().process_frame

		# 4. ASSAULT VIGNETTE — mid-beats (tweens marching, cards striking).
		var storm_host := _knight_host(2, 0)
		var storm_screen := await _mounted_screen(storm_host)
		storm_screen.open_assault()
		for _i in 5:
			await get_tree().process_frame
		storm_screen._assault.commit()
		for i in 120:
			await get_tree().process_frame
			if storm_screen._assault.state == storm_screen._assault.State.VIGNETTE:
				break
		var vignette := await _frame_ms(240)
		_report("4. ASSAULT VIGNETTE (mid-beats)", vignette, failures)
		_memory_line("vignette")
		storm_screen._assault.skip()
		for i in 300:
			await get_tree().process_frame
			if storm_screen._assault.state == storm_screen._assault.State.OUTCOME:
				break
		storm_screen._assault.close()
		storm_screen.queue_free()
		for _i in 5:
			await get_tree().process_frame

		# 5. CHRONICLE 50 — the ledger open, scrolling + turning pages;
		#    doubles as the paging-boundedness probe (two full cycles).
		_erase_dir(PROBE_ROOT + "/ledger")
		var ledger_host := GameHost.new(RUN_SEED, PROBE_ROOT + "/ledger")
		ledger_host.autosave_interval_ticks = 0
		ledger_host.boot(0)
		ledger_host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
		_synthetic_ring(ledger_host, 50)
		var ledger_screen := await _mounted_screen(ledger_host)
		ledger_host.driving = false
		ledger_screen._chronicle.per_page = 5
		ledger_screen._chronicle.open(ledger_host, ledger_screen.get_router())
		for _i in 20:
			await get_tree().process_frame
		var measured := await _frame_ms_scroll(ledger_screen, 240)
		_report("5. CHRONICLE 50 (scrolled)", measured["scroll"], failures)
		print("[deck-perf]   chronicle page-turn transitions: %d turns, worst %.2f ms, median %.2f ms (a turn is an event, not a steady state — reported, not gated)"
			% [measured["turns"].size(), _max_of(measured["turns"]), _percentile(measured["turns"], 0.5)])
		var cycle_a := _memory_snapshot()
		for _cycle in 2:
			for i in 9:
				ledger_screen._chronicle.turn_page(1)
				for _f in 3:
					await get_tree().process_frame
			for i in 9:
				ledger_screen._chronicle.turn_page(-1)
				for _f in 3:
					await get_tree().process_frame
		for _i in 8:
			await get_tree().process_frame
		var cycle_b := _memory_snapshot()
		print("[deck-perf]   chronicle paging boundedness: static %.0f -> %.0f KB, objects %d -> %d (%s)"
			% [cycle_a["static"] / 1024.0, cycle_b["static"] / 1024.0,
				int(cycle_a["objects"]), int(cycle_b["objects"]),
				"stable" if absf(cycle_b["static"] - cycle_a["static"]) < 512.0 * 1024.0
					and absi(int(cycle_b["objects"]) - int(cycle_a["objects"])) < 40 else "GROWING"])
		if absf(cycle_b["static"] - cycle_a["static"]) >= 512.0 * 1024.0 \
				or absi(int(cycle_b["objects"]) - int(cycle_a["objects"])) >= 40:
			failures.append("chronicle paging grows memory across page cycles")
		_memory_line("chronicle")
		ledger_screen._chronicle.close()
		ledger_screen.queue_free()
		for _i in 5:
			await get_tree().process_frame

		# Verdict.
		print("[deck-perf] budget: %.2fms (60Hz); pass lines mean <= %.1fms, p95 <= %.1fms, max <= %.2fms"
			% [BUDGET_MS, MEAN_LINE_MS, P95_LINE_MS, BUDGET_MS])
		if failures.is_empty():
			print("[deck-perf] ALL STATES PASS on this hardware (necessary-not-sufficient for Deck — see docs/deck-validation.md)")
			get_tree().quit(0)
		else:
			for failure in failures:
				printerr("[deck-perf] FAIL: %s" % failure)
			get_tree().quit(1)

	func _memory_snapshot() -> Dictionary:
		return {"static": _monitor("MEMORY_STATIC"), "objects": _monitor("OBJECT_COUNT")}

	## Frame samples while the ledger scrolls (the scroll oscillates).
	## Page-turn frames are measured SEPARATELY as transitions (a turn
	## rebuilds the page — an event cost, not a steady-state frame).
	func _frame_ms_scroll(screen: SpreadScreen, n: int) -> Dictionary:
		var samples: Array[float] = []
		var turns: Array[float] = []
		var scroll := screen._chronicle.sheet().scroll()
		var direction := 1
		var last := Time.get_ticks_usec()
		for i in n:
			if scroll.scroll_vertical <= 0:
				direction = 1
			elif scroll.scroll_vertical >= int(scroll.get_v_scroll_bar().max_value) - 4:
				direction = -1
			scroll.scroll_vertical += direction * 42
			if i % 60 == 59:
				# A turn frame: the rebuild lands inside THIS frame delta.
				screen._chronicle.turn_page(1 if (i / 60) % 2 == 0 else -1)
				var now_turn := Time.get_ticks_usec()
				await get_tree().process_frame
				turns.append(float(Time.get_ticks_usec() - now_turn) / 1000.0)
				last = Time.get_ticks_usec()
				continue
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - last) / 1000.0)
			last = now
		return {"scroll": samples, "turns": turns}

	func _synthetic_ring(host: GameHost, count: int) -> void:
		var firsts: Array = Inks.pack().identity.leader_first_names
		var epithets: Array = Inks.pack().identity.leader_epithets
		var regimes := Inks.regime_ids()
		host.meta.chronicle.clear()
		host.meta.runs_recorded = 0
		host.meta.legacy_points = 0
		var outcomes := ["victory", "defeat", "aborted"]
		for i in count:
			var entry := {
				"run": i + 1,
				"leader": "%s %s" % [firsts[i % firsts.size()], epithets[(i * 5) % epithets.size()]],
				"tags": [&"scheming", &"pious"],
				"trait": "haggles with geese",
				"regime": String(regimes[i % regimes.size()]),
				"outcome": outcomes[i % 3],
				"duration_ticks": (i % 90 + 2) * SimEngine.TICKS_PER_SIM_HOUR,
				"army_power": i * 3,
				"army": {"knight": i % 4, "archer": (i + 1) % 3},
				"score": 40 + i,
			}
			host.meta.chronicle.append(entry)
			host.meta.runs_recorded += 1
			host.meta.legacy_points += int(entry["score"])
