## Deck battery-shape + memory-boundedness suite — T-PERF-02 (Thor lane).
##
## THE BATTERY CLAIM: when the table is quiet, the game does NOTHING per
## frame — no animation, no polling beyond the two documented seams (the
## spread's pacing `_process` that advances the host, and the
## LayoutRouter's cheap aspect poll; the intro packet's `_process` is a
## gated no-op at rest). Proven headless by an ACTIVITY COUNTER that
## walks the screen's whole subtree every frame for a settle window:
##   - zero processing nodes outside the documented allowlist,
##   - zero physics-processing nodes,
##   - and the allowlist itself IS observed processing (the counter is
##     non-vacuous — it sees the two seams and nothing else).
## Godot 4.7 exposes no per-item redraw query (`is_queued_redraw` died
## with 3.x; only `queue_redraw()` remains), so the full "zero animating
## nodes" catch-all — two pixel-identical captures of the quiet table,
## which no tween/timer/redraw can evade — lives in the WINDOWED harness
## (scripts/deck_perf_suite.gd, `make deck-perf`), where the renderer is
## real.
##
## MEMORY BOUNDEDNESS (the Deck has ~1GB free for the game):
##   - the face-art cache is bounded by the art manifest (never grows
##     with rebinds — cached per face key, the manifest is finite);
##   - the 50-hand chronicle ledger pages without growth: two full page
##     cycles through all 10 pages land the same static-memory and object
##     counts (the sheet rebuilds each page; dying pages must not leak);
##   - whole-view rebind churn (5 full refreshes) is object-count stable;
##   - the while-you-were-away print is structurally bounded (rows() and
##     the quote's own MAX_ROWS cap).
extends RefCounted

const SpreadScreen := preload("res://ui/screens/spread/spread_screen.gd")
const SPREAD_SCENE := preload("res://ui/screens/spread/spread_screen.tscn")
const QUIET_SEED := 20261103
const DECK_WINDOW := Vector2i(1280, 800)
## Injected-time scale for the passive paper's dwell + the mount/entrance
## tweens (restored at exit). Every paced wait is a forward state poll,
## so the scale rides the same premise at 60 as it did at 20 — raised in
## the finishing #5 re-dispatch's harness-budget trim.
const WATCH_SCALE := 60.0
const T0 := 1_800_000_000

## The documented per-frame seams (script file names): the pacing process
## + the aspect poll + the unfold gate. Anything else processing while
## the table is quiet is a battery drain.
const PROCESS_ALLOWLIST: Array[String] = [
	"spread_screen.gd", "layout_router.gd", "intro_packet.gd",
]

var _dir_seq := 0


func suite_name() -> String:
	return "deck_battery_memory"


func run(harness) -> void:
	Engine.time_scale = WATCH_SCALE
	var window := (harness as Node).get_tree().root
	window.size = DECK_WINDOW

	await _probe_idle_activity(harness)
	await _probe_print_settles(harness)
	await _probe_face_art_cache_bound(harness)
	await _probe_chronicle_paging_bounded(harness)
	await _probe_rebind_churn_bounded(harness)
	await _probe_catch_up_print_rows_bounded(harness)

	window.size = Vector2i(720, 720)
	Engine.time_scale = 1.0
	_erase_dir("user://cs_deck_batt")


# --- shared -----------------------------------------------------------------------------


func _frames(harness, count: int):
	var tree: SceneTree = (harness as Node).get_tree()
	for _i in count:
		await tree.process_frame


func _test_host(run_seed: int) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_deck_batt/run-%02d" % _dir_seq
	_erase_dir(root)
	var host := GameHost.new(run_seed, root)
	host.autosave_interval_ticks = 0
	host.boot(0)
	return host


func _mounted_screen(harness, host: GameHost) -> SpreadScreen:
	var screen: SpreadScreen = SPREAD_SCENE.instantiate()
	screen.host = host
	screen.intro_enabled = false
	harness.mount(screen)
	await _frames(harness, 8)
	return screen


## One activity sample over the screen's subtree:
##   {strays, physics, seams} — processing nodes outside the allowlist,
##   physics processors, and the allowlisted seams actually observed
##   (the non-vacuous guard: the counter must SEE the two documented
##   seams while flagging nothing else).
func _activity_sample(screen: SpreadScreen) -> Dictionary:
	var strays: Array[String] = []
	var physics := 0
	var seams: Array[String] = []
	var queue: Array[Node] = [screen]
	while not queue.is_empty():
		var node := queue.pop_front() as Node
		if node.is_processing():
			if _is_allowlisted(node):
				seams.append(String(node.get_script().resource_path.get_file()))
			else:
				var script: Script = node.get_script()
				strays.append("%s(%s)" % [String(node.name),
					String(script.resource_path.get_file()) if script != null else "<native>"])
		if node.is_physics_processing():
			physics += 1
		for child in node.get_children():
			queue.append(child)
	return {"strays": strays, "physics": physics, "seams": seams}


func _is_allowlisted(node: Node) -> bool:
	var script: Script = node.get_script()
	if script == null:
		return false  # native nodes (Containers, Labels) never process by themselves
	return PROCESS_ALLOWLIST.has(String(script.resource_path.get_file()))


func _monitor(name: String) -> float:
	return Performance.get_monitor(Performance[name])


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


# --- 1. idle activity counter ---------------------------------------------------------------


func _probe_idle_activity(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(4.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false  # the quiet table: pacing closed, nothing animating
	await _frames(harness, 30)  # entrances, tweens and deferred binds settle
	var frames_checked := 0
	var worst_strays: Array[String] = []
	var worst_physics := 0
	var seams_seen := false
	for i in 30:
		await _frames(harness, 1)
		var sample := _activity_sample(screen)
		frames_checked += 1
		if (sample["strays"] as Array[String]).size() > worst_strays.size():
			worst_strays = sample["strays"]
		worst_physics = maxi(worst_physics, int(sample["physics"]))
		if (sample["seams"] as Array[String]).has("spread_screen.gd") \
				and (sample["seams"] as Array[String]).has("layout_router.gd"):
			seams_seen = true
	harness.check(worst_strays.is_empty(),
		"battery/idle: zero processing outside the documented seams over %d quiet frames (strays: %s)"
		% [frames_checked, ", ".join(worst_strays)])
	harness.check(worst_physics == 0,
		"battery/idle: zero physics-processing nodes (worst %d)" % worst_physics)
	harness.check(seams_seen,
		"battery/idle: the counter is non-vacuous — it observes the two documented seams (pacing + aspect poll)")
	screen.queue_free()
	await _frames(harness, 3)


# --- 2. passive paper settles back to zero -----------------------------------------------------


func _probe_print_settles(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(5.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	# The mid-session away window resolves; the print dwells, then folds.
	host.background(T0)
	host.foreground(T0 + 9 * 3600 + 37 * 60)
	var printed := false
	for i in 90:
		await _frames(harness, 1)
		if int(screen.stats[&"catch_up_prints"]) > 0:
			printed = true
			break
	if not harness.check(printed, "battery/print: the while-you-were-away print lands"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	host.driving = false
	# The dwell (QUOTE_DWELL * 2 at the injected-time scale) folds the
	# quote; then the quiet-table counter must read ZERO again.
	for i in 400:
		await _frames(harness, 1)
		if not screen._suspicion.quote_is_open():
			break
	await _frames(harness, 10)
	var sample := _activity_sample(screen)
	harness.check((sample["strays"] as Array[String]).is_empty() and int(sample["physics"]) == 0,
		"battery/print: the passive print self-folds and the table settles back to zero activity (strays: %s)"
		% ", ".join(sample["strays"]))
	screen.queue_free()
	await _frames(harness, 3)


# --- 3. the face-art cache is manifest-bounded -------------------------------------------------


func _probe_face_art_cache_bound(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(6.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false
	var manifest_bound := 0
	for entry: ArtAssetDef in Inks.pack().art.assets:
		if entry != null and not entry.pending:
			manifest_bound += 1
	var cache_size := FaceArt._texture_cache.size()
	harness.check(cache_size <= manifest_bound,
		"memory/faces: the face-art cache never exceeds the manifest (%d cached <= %d non-pending)"
		% [cache_size, manifest_bound])
	# Full rebinds must not grow it: the cache is keyed by face key.
	for i in 3:
		screen.refresh_from_state()
		await _frames(harness, 2)
	var after := FaceArt._texture_cache.size()
	harness.check(after == cache_size,
		"memory/faces: three whole-view rebinds leave the cache unchanged (%d -> %d)"
		% [cache_size, after])
	screen.queue_free()
	await _frames(harness, 3)


# --- 4. chronicle paging is bounded ------------------------------------------------------------


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


func _probe_chronicle_paging_bounded(harness) -> void:
	var host := _test_host(QUIET_SEED)
	host.fast_forward(4 * SimEngine.TICKS_PER_SIM_HOUR)
	_synthetic_ring(host, 50)
	var screen := await _mounted_screen(harness, host)
	host.driving = false
	screen._chronicle.per_page = 5
	screen._chronicle.open(host, screen.get_router())
	await _frames(harness, 20)
	if not harness.check(screen._chronicle.is_open(), "memory/chronicle: the 50-hand ledger opens"):
		screen.queue_free()
		await _frames(harness, 3)
		return
	var page_count := int(screen._chronicle.view()["page_count"])
	harness.check(page_count == 10,
		"memory/chronicle: 50 hands at per-page 5 = 10 pages (got %d)" % page_count)
	var cycle_stats: Array[Dictionary] = []
	for cycle in 2:
		# Walk EVERY page (a frame between turns so dying pages flush),
		# newest to oldest and back.
		for i in page_count - 1:
			screen._chronicle.turn_page(1)
			await _frames(harness, 2)
		for i in page_count - 1:
			screen._chronicle.turn_page(-1)
			await _frames(harness, 2)
		await _frames(harness, 5)  # let the last page's deferred frees land
		cycle_stats.append({
			"static": int(_monitor("MEMORY_STATIC")),
			"objects": int(_monitor("OBJECT_COUNT")),
			"resources": int(_monitor("OBJECT_RESOURCE_COUNT")),
		})
	var first_cycle: Dictionary = cycle_stats[0]
	var second_cycle: Dictionary = cycle_stats[1]
	harness.check(absi(int(second_cycle["static"]) - int(first_cycle["static"])) < 512 * 1024,
		"memory/chronicle: two full 10-page cycles hold static memory steady (%d B -> %d B)"
		% [int(first_cycle["static"]), int(second_cycle["static"])])
	harness.check(absi(int(second_cycle["objects"]) - int(first_cycle["objects"])) < 40,
		"memory/chronicle: two full 10-page cycles hold the object count steady (%d -> %d)"
		% [int(first_cycle["objects"]), int(second_cycle["objects"])])
	var sheet_children := screen._chronicle.sheet().entries().size()
	harness.check(sheet_children == 5,
		"memory/chronicle: the sheet holds one page of entries at a time (got %d)" % sheet_children)
	screen._chronicle.close()
	await _frames(harness, 3)
	screen.queue_free()
	await _frames(harness, 3)


# --- 5. whole-view rebind churn is bounded ------------------------------------------------------


func _probe_rebind_churn_bounded(harness) -> void:
	var host := _test_host(QUIET_SEED)
	var policy := DemoPolicy.new(16, 8, false)
	var chunks := int(6.0 * float(SimEngine.TICKS_PER_SIM_HOUR) / 60.0)
	for _i in chunks:
		host.fast_forward(60)
		if policy.on_ticks(60):
			policy.apply(host)
	var screen := await _mounted_screen(harness, host)
	host.driving = false
	await _frames(harness, 5)  # deferred frees from the mount settle
	var before := int(_monitor("OBJECT_COUNT"))
	for i in 5:
		screen.refresh_from_state()
		await _frames(harness, 2)
	var after := int(_monitor("OBJECT_COUNT"))
	harness.check(after - before < 40,
		"memory/rebinds: five whole-view rebuilds hold the object count steady (%d -> %d)"
		% [before, after])
	screen.queue_free()
	await _frames(harness, 3)


# --- 6. the away print is structurally bounded ---------------------------------------------------


func _probe_catch_up_print_rows_bounded(harness) -> void:
	## The WORST honest report: capped, every resource moved, people,
	## suspicion both ways, crackdowns AND a run ending inside the window.
	## rows() must stay within the quote panel's own MAX_ROWS budget (the
	## EventQuote caps its printed rows; the print composes within it).
	var worst := {
		"applied_ticks": 480, "clamped_seconds": 8 * 3600 + 37 * 60, "cap_seconds": 8 * 3600,
		"capped": true, "rewound": false, "from_tick": 1234,
		"resource_delta": {&"food": 960, &"timber": 311, &"iron": -42},
		"arrivals": 4, "training_completions": 7, "promotions": 2,
		"suspicion_present": true, "suspicion_delta": 12, "suspicion_before": 30,
		"suspicion_after": 42, "crackdowns": 1, "run_endings": 1,
	}
	var rows := CatchUpPrint.rows(worst)
	harness.check(rows.size() >= 5 and rows.size() <= 7,
		"memory/away-print: the worst window prints a bounded blockquote (%d rows, panel cap 7)" % rows.size())
	var rewound := worst.duplicate(true)
	rewound["rewound"] = true
	harness.check(CatchUpPrint.rows(rewound).size() == 1,
		"memory/away-print: the rewound window prints exactly its one wry line")
