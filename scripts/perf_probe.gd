## T-PERF-01 frame-cost micro-benchmark — NOT a test; a measurement probe.
##
##     make perf-probe
##
## Measures the idle-loop costs the background/foreground lifecycle stands
## on (headless, so the numbers are the GAME LAYER's CPU cost — the
## Compatibility renderer's GPU/present work is engine-side and excluded
## by construction; stated honestly in production-log.md):
##   1. bare-frame baseline   — engine iteration with nothing mounted;
##   2. IDLE SPREAD FRAME     — the real game screen (a 4h seeded session,
##                              quiet table, nothing animating, no intro)
##                              mounted and framed; delta vs baseline =
##                              the game layer's per-frame cost. THIS is
##                              the desktop-focus decision's evidence: an
##                              unfocused window keeps rendering, and the
##                              game layer contributes ~nothing per frame;
##   3. BACKGROUND FRAME      — the same screen with the host backgrounded
##                              through the REAL policy surface (pacing
##                              gate closed): the per-frame work that
##                              remains while hidden;
##   4. advance() pacing math — the accumulator call per frame,
##                              foreground (sub-tick delta, 0 ticks) vs
##                              backgrounded (the driving gate);
##   5. foreground() catch-up — the 8h capped window (480 ticks) resolved
##                              on the LIVE table (engine + event drain +
##                              targeted rebinds): the resume-side budget;
##   6. suspended-resume      — one advance() carrying a 3-day delta
##                              (4320 live ticks in a single frame): the
##                              desktop worst case for a kept-running
##                              process whose window the OS had suspended —
##                              the decision of record's honest ceiling.
extends SceneTree

const RUN_SEED := 20261103
const PROBE_ROOT := "user://cs_perf_probe"
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")

## Synthetic platform epoch for the lifecycle boundaries (injected, like
## every platform timestamp).
const T0 := 1_800_000_000


func _initialize() -> void:
	_probe()


func _probe() -> void:
	_erase_dir(PROBE_ROOT)
	var host := GameHost.new(RUN_SEED, PROBE_ROOT)
	host.boot(0)
	host.fast_forward(240)  # 4h in: a populated, quiet table

	# 1. Bare-frame baseline (before the screen exists).
	var bare := await _frame_samples(60)

	# 2. The real screen, idle (the sibling-suite mount pattern: host
	# pre-attached, intro off — the bare table).
	var screen: Control = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	root.add_child(screen)
	await _frame_samples(30)  # mount + deferred first bind settle
	var idle := await _frame_samples(240)

	# 3. The same screen with the host BACKGROUND through the real policy.
	var policy := AppLifecycle.new()
	policy.host = host
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, T0)
	await _frame_samples(30)  # the boundary flush (anchor + save) settles
	var hidden := await _frame_samples(240)
	# Resume THROUGH THE POLICY (a direct host.foreground would leave the
	# idempotency latch closed — the exact double-resolution guard the
	# probe would otherwise trip on below).
	policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, T0 + 8 * 3600)
	var report := host.last_catch_up_report
	await _frame_samples(5)

	# 4. The pacing math per call (the _process payload).
	var ticks_before: int = host.engine.tick_count
	var fg_advance := _loop_usec(3000, func() -> void: host.advance(1.0 / 60.0))
	var sub_tick_ticks: int = host.engine.tick_count - ticks_before
	host.driving = false
	var bg_advance := _loop_usec(3000, func() -> void: host.advance(1.0 / 60.0))
	host.driving = true

	# 5. The 8h capped window resolved on the LIVE table, 5 windows, min.
	# Each window opens PAST the previous one (the anchor follows every
	# apply) — a fresh capped 8h each time, never a rewound no-op.
	var best_resolve_usec := -1
	var window_base := T0
	for i in 5:
		policy.handle_notification(Node.NOTIFICATION_APPLICATION_PAUSED, window_base)
		var started := Time.get_ticks_usec()
		policy.handle_notification(Node.NOTIFICATION_APPLICATION_RESUMED, window_base + 8 * 3600)
		var took := Time.get_ticks_usec() - started
		if int(host.last_catch_up_report["applied_ticks"]) != 480:
			push_error("perf-probe: window %d applied %d ticks — not a real capped window"
				% [i, int(host.last_catch_up_report["applied_ticks"])])
		if best_resolve_usec == -1 or took < best_resolve_usec:
			best_resolve_usec = took
		window_base += 9 * 3600

	# 6. The kept-running desktop worst case: one frame carries 3 days.
	var batch_start := Time.get_ticks_usec()
	var batch_ticks := host.advance(3.0 * 86400.0)
	var batch_usec := Time.get_ticks_usec() - batch_start

	print("[perf-probe] bare frame baseline          : mean %8.1f usec/frame (max %6d, n=%d)"
		% [bare["mean"], bare["max"], bare["n"]])
	print("[perf-probe] IDLE SPREAD frame            : mean %8.1f usec/frame (max %6d, n=%d) -> game layer +%.1f usec/frame"
		% [idle["mean"], idle["max"], idle["n"], idle["mean"] - bare["mean"]])
	print("[perf-probe] BACKGROUND frame (gate shut) : mean %8.1f usec/frame (max %6d, n=%d) -> game layer +%.1f usec/frame"
		% [hidden["mean"], hidden["max"], hidden["n"], hidden["mean"] - bare["mean"]])
	print("[perf-probe] advance() foreground no-op   : %8.3f usec/call (3000 calls, %d ticks — sub-tick accumulator only)"
		% [fg_advance, sub_tick_ticks])
	print("[perf-probe] advance() backgrounded gate  : %8.3f usec/call (3000 calls)"
		% bg_advance)
	print("[perf-probe] foreground() 8h capped window: %8.1f ms resolve (min of 5; 480 ticks, live-table drain; probe resume applied %d)"
		% [best_resolve_usec / 1000.0, int(report["applied_ticks"])])
	print("[perf-probe] suspended-resume 3-day batch : %8.1f ms for %d live ticks in ONE advance() (the kept-running desktop ceiling)"
		% [batch_usec / 1000.0, batch_ticks])
	quit(0)


## Mean/max wall usec per engine frame over n frames (awaited — the tree
## iterates between resumptions; this is the honest whole-frame cost the
## headless loop spends, not a synthetic micro-call).
func _frame_samples(n: int) -> Dictionary:
	var last := Time.get_ticks_usec()
	var total := 0
	var peak := 0
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		var took := now - last
		last = now
		total += took
		peak = maxi(peak, took)
	return {"mean": float(total) / float(n), "max": peak, "n": n}


func _loop_usec(calls: int, fn: Callable) -> float:
	var started := Time.get_ticks_usec()
	for i in calls:
		fn.call()
	return float(Time.get_ticks_usec() - started) / float(calls)


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
