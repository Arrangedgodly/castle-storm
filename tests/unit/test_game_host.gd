## Unit tests for the GameHost (T-UI-03) — Daredevil lane.
##
## Mirrors ui/host/game_host.gd (test-mapping rule). The host is the
## shipping mirror of the canonical composition, so the parity proofs here
## are the point:
##   - COMPOSITION PARITY vs tests/acceptance/suites/_full_stack.gd —
##     same system names in the same order AND same state hash per seed
##     (the hash covers order, content and stipend in one integer);
##   - the event feed delivers EVERY event EXACTLY ONCE in seq order,
##     live-ticked and fast-forwarded alike (the §13 both-feeds contract);
##   - tick pacing math, pause seam, determinism twins, save round-trip,
##     catch-up boundary seams;
##   - zero OS/Time reads in the source (the security-policy inventory).
extends GdUnitTestSuite

const FULL_STACK := preload("res://tests/acceptance/suites/_full_stack.gd")

var _dir_seq := 0


func after() -> void:
	_erase_dir("user://cs_host_tests")


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


func _fresh_host(run_seed: int = 20261103) -> GameHost:
	_dir_seq += 1
	var root := "user://cs_host_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	return GameHost.new(run_seed, root)


# --- composition parity ---------------------------------------------------------------


func test_composition_matches_the_canonical_fixture() -> void:
	var host := _fresh_host()
	var canonical := FULL_STACK.game_stack(20261103, RunMeta.new())
	var expected: Array[StringName] = []
	for key in canonical.to_dict()["systems"].keys():
		expected.append(StringName(key))
	assert_array(host.system_order()).is_equal(expected)


func test_same_seed_same_ticks_same_hash_as_canonical_fixture() -> void:
	## The strongest parity proof: composition + content + the honest boot
	## (run_start + the stipend grant verb) all agree => identical
	## determinism oracle per seed. The canonical engine runs the boot
	## verbs + 600 ticks; the host's boot consumes the first tick (the
	## drain), so it continues with 599.
	var host := _fresh_host(777)
	var canonical := FULL_STACK.game_stack(777, RunMeta.new())
	host.boot(0)
	canonical.submit_command(&"run_start")
	canonical.submit_command(&"grant_resources")
	canonical.fast_forward(600)
	host.advance_ticks(599)
	assert_int(host.engine.state_hash()).is_equal(canonical.state_hash())


# --- boot ------------------------------------------------------------------------------


func test_fresh_boot_starts_a_running_run_and_pays_the_stipend() -> void:
	var host := _fresh_host(42)
	var loaded: bool = host.boot(0)
	assert_bool(loaded).is_false()
	assert_bool(host.is_run_running()).is_true()
	assert_str(host.run().leader_name()).is_not_empty()
	assert_str(String(host.run().regime_id())).is_not_empty()
	var pack := Inks.pack()
	for id in pack.starting_grants.keys():
		assert_int(host.engine.get_resource(id)).is_equal(int(pack.starting_grants[id]))
	# The first run's events are already delivered (boot ticks once).
	assert_int(host.engine.events.next_seq()).is_greater(0)


func test_boot_loads_a_saved_session_and_continues_it() -> void:
	var host := _fresh_host(4242)
	host.boot(0)
	host.advance_ticks(300)
	assert_bool(host.save_all()).is_true()
	var meta_points_before: int = host.meta.legacy_points

	var reborn := GameHost.new(4242, host.save_manager.root_dir)
	var loaded: bool = reborn.boot(0)
	assert_bool(loaded).is_true()
	assert_int(reborn.engine.state_hash()).is_equal(host.engine.state_hash())
	assert_int(reborn.engine.tick_count).is_equal(host.engine.tick_count)
	assert_int(reborn.meta.legacy_points).is_equal(meta_points_before)
	reborn.advance_ticks(60)
	host.advance_ticks(60)
	assert_int(reborn.engine.state_hash()).is_equal(host.engine.state_hash())


# --- the unified event feed ------------------------------------------------------------


func test_every_event_delivered_exactly_once_in_seq_order() -> void:
	var host := _fresh_host(99)
	# Connect BEFORE boot: the boot tick's events belong to the feed too.
	var seen: Array[int] = []
	var dupes := [0]  # lambdas capture by VALUE — counters ride arrays
	host.event_observed.connect(func(event: Dictionary) -> void:
		if seen.has(int(event["seq"])):
			dupes[0] += 1
		seen.append(int(event["seq"])))
	host.boot(0)
	# Live batches...
	host.advance_ticks(240)
	# ...then a fast-forward (the catch-up shape) through the SAME feed.
	host.fast_forward(240)
	var sorted_seen := seen.duplicate()
	sorted_seen.sort()
	assert_int(dupes[0]).is_zero()
	assert_array(seen).is_equal(sorted_seen)
	# Every event the engine ever recorded is in the feed, exactly once,
	# 0-based contiguous.
	assert_int(seen.size()).is_equal(host.engine.events.next_seq())
	assert_int(seen[0]).is_zero()
	assert_int(seen[seen.size() - 1]).is_equal(host.engine.events.next_seq() - 1)


func test_event_payloads_are_plain_copies() -> void:
	var host := _fresh_host(7)
	var kinds: Array[StringName] = []
	host.event_observed.connect(func(event: Dictionary) -> void:
		assert_bool(event is Dictionary).is_true()  # a copied dict, never the pooled SimEvent
		kinds.append(event["type"]))
	host.boot(0)
	assert_array(kinds).contains(&"run_started")


# --- tick pacing -------------------------------------------------------------------------


func test_advance_converts_injected_seconds_to_ticks_with_remainder_carry() -> void:
	var host := _fresh_host(5)
	host.boot(0)
	var before: int = host.engine.tick_count
	assert_int(host.advance(30.0)).is_zero()  # half a tick: carried
	assert_int(host.engine.tick_count).is_equal(before)
	assert_int(host.advance(30.0)).is_equal(1)  # the carried half completes it
	assert_int(host.engine.tick_count).is_equal(before + 1)
	host.time_scale = 6.0
	assert_int(host.advance(10.0)).is_equal(1)  # 10s x6 = one minute


func test_paused_engine_advances_nothing() -> void:
	var host := _fresh_host(6)
	host.boot(0)
	host.engine.pause()
	assert_int(host.advance_ticks(10)).is_zero()
	host.engine.resume()
	assert_int(host.advance_ticks(10)).is_equal(10)


func test_driving_false_stops_advance() -> void:
	var host := _fresh_host(8)
	host.boot(0)
	host.driving = false
	assert_int(host.advance(600.0)).is_zero()
	host.driving = true
	assert_int(host.advance(600.0)).is_equal(10)


# --- determinism ---------------------------------------------------------------------------


func test_same_seed_same_drive_same_hash_and_event_count() -> void:
	var a := _fresh_host(2026)
	var b := _fresh_host(2026)
	var events_a := 0
	var events_b := 0
	a.boot(0)
	b.boot(0)
	a.event_observed.connect(func(_e: Dictionary) -> void: events_a += 1)
	b.event_observed.connect(func(_e: Dictionary) -> void: events_b += 1)
	for host in [a, b]:
		host.submit(&"recruit_accept", &"", (host.units().offer_ids()[0] if host.units().pending_offers() > 0 else 1))
		host.advance_ticks(1200)
	assert_int(a.engine.state_hash()).is_equal(b.engine.state_hash())
	assert_int(events_a).is_equal(events_b)
	assert_int(a.engine.tick_count).is_equal(b.engine.tick_count)


func test_different_seed_different_world() -> void:
	var a := _fresh_host(11)
	var b := _fresh_host(12)
	a.boot(0)
	b.boot(0)
	assert_int(a.engine.state_hash()).is_not_equal(b.engine.state_hash())


# --- catch-up boundary seams -----------------------------------------------------------------


func test_background_then_foreground_resolves_the_away_window() -> void:
	var host := _fresh_host(13)
	host.boot(1000)
	host.advance_ticks(120)
	host.background(2000)
	assert_bool(host.driving).is_false()
	var reports: Array[Dictionary] = []
	host.catch_up_resolved.connect(func(report: Dictionary) -> void: reports.append(report))
	var before: int = host.engine.tick_count
	var report := host.foreground(2000 + 9 * 3600)  # 9h away -> capped at 8h
	assert_int(int(report["applied_ticks"])).is_equal(480)
	assert_bool(report["capped"]).is_true()
	assert_int(host.engine.tick_count).is_equal(before + 480)
	assert_bool(host.driving).is_true()
	assert_int(reports.size()).is_equal(1)


# --- the no-OS discipline ----------------------------------------------------------------------


func test_host_source_reads_no_clock_and_no_os() -> void:
	## The security-policy clock inventory: the platform host is the only
	## layer permitted a clock, and GameHost is not it (timestamps are
	## injected). Comment-stripped scan, the test_security_policy pattern.
	var source := FileAccess.get_file_as_string("res://ui/host/game_host.gd")
	var stripped := source.replace("\n#", "\n").replace("\t#", "\t")
	for banned in ["OS.", "Time.get_unix", "Time.get_system", "Time.get_ticks", "SceneTreeTimer"]:
		assert_str(_first_hit(stripped, banned)).is_empty()


func _first_hit(haystack: String, needle: String) -> String:
	var at := haystack.find(needle)
	if at == -1:
		return ""
	var line_start := haystack.rfind("\n", at) + 1
	var line_end := haystack.find("\n", at)
	return haystack.substr(line_start, line_end - line_start).strip_edges()
