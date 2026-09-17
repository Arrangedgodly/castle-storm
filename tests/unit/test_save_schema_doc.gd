## Doc-accuracy tests for docs/save-schema.md (T-DATA-03) — Mr. Fantastic lane.
##
## The schema doc's authority is only as good as its fidelity to the code, so
## the doc is MACHINE-CHECKED: every ```save-keys block (one key per line)
## and the ```save-version block are pinned against a save generated from a
## REAL 500h full-stack run — the same marathon script the acceptance suites
## use (the thin-loop fixture: recruits, both promotion branches, every gear
## tier, upgrades, a banked victory), written through SaveManager to a
## scratch root and parsed back from the bytes on disk. Drift in EITHER
## direction — a payload field the code grew but the doc misses, or a
## documented field the code no longer writes — fails with the exact diff.
## Also proves the §6 L2 reserve is honestly reserved: documented in the
## doc, absent from real saves.
extends GdUnitTestSuite

const THIN_LOOP := preload("res://tests/acceptance/suites/marathon_run_thin_loop.gd")

const DOC_PATH := "res://docs/save-schema.md"
const SCRATCH_ROOT := "user://cs_save_schema_doc_tests"
const RUN_HOURS := 500
const CHUNK_TICKS := 600  # one management batch per 10h

# The doc-accuracy contract (§9): every block id the doc may carry. A typo'd
# id in a new block (silently unchecked) or a removed block (test still
# expecting it) both fail here first.
const EXPECTED_BLOCK_IDS: Array[String] = [
	"run-envelope",
	"meta-envelope",
	"run-payload",
	"run-pending-command",
	"run-systems",
	"system-heartbeat",
	"system-run",
	"system-units",
	"system-units-entry",
	"system-production",
	"system-production-building",
	"system-production-quirks",
	"meta-payload",
	"meta-chronicle-entry",
	"meta-escalation-garrison",
	"meta-escalation-roster-entry",
]

var _doc_text := ""
var _doc_blocks: Dictionary = {}
var _run_envelope: Dictionary = {}
var _meta_envelope: Dictionary = {}


## gdUnit4 6.2.1 suite hooks are before()/after() (once per suite, shared
## instance) — before_all/after_all do NOT exist in this version and are
## silently never called.
func before() -> void:
	_doc_text = _read_text(DOC_PATH)
	_doc_blocks = _parse_marked_blocks(_doc_text, "save-keys")
	_generate_real_save()


func after() -> void:
	_erase_dir(SCRATCH_ROOT)


# --- The pinned contract ------------------------------------------------------


func test_doc_exists_and_carries_every_pinned_block() -> void:
	assert_bool(not _doc_text.is_empty()).is_true()
	var doc_ids := _sorted_keys(_doc_blocks)
	assert_str(",".join(doc_ids)).is_equal(",".join(_sorted(EXPECTED_BLOCK_IDS)))


func test_every_documented_key_set_matches_the_real_save() -> void:
	# Fixture sanity first — a degenerate run must fail loudly here, not pass
	# vacuously through empty key sets.
	var run_payload: Dictionary = _run_envelope["payload"]
	var systems: Dictionary = run_payload["systems"]
	var units: Array = systems["units"]["units"]
	var chronicle: Array = (_meta_envelope["payload"] as Dictionary)["chronicle"]
	assert_int(units.size()).is_greater(10)  # deep roster, gear, ranks
	assert_int(chronicle.size()).is_greater(0)  # a banked run (victory)
	assert_int((run_payload["pending_commands"] as Array).size()).is_greater(0)  # queued command

	var live := _live_key_sets()
	for block_id in EXPECTED_BLOCK_IDS:
		var documented: Array[String] = _sorted(_doc_blocks.get(block_id, []))
		var on_disk: Array[String] = _sorted(live.get(block_id, ["<NO LIVE SET FOR %s>" % block_id]))
		# Failure output shows both comma-joined lists: the exact diff.
		assert_str("%s -> %s" % [block_id, ",".join(documented)]).is_equal(
			"%s -> %s" % [block_id, ",".join(on_disk)]
		)


func test_version_axes_in_doc_match_the_code() -> void:
	var versions := _parse_marked_blocks(_doc_text, "save-version")
	assert_bool(versions.has("save-version")).is_true()
	var pinned: Dictionary = {}
	for line: String in versions.get("save-version", []):
		var parts := line.split(" ", false)
		assert_int(parts.size()).is_equal(2)
		if parts.size() == 2:
			pinned[parts[0]] = int(parts[1])
	assert_int(int(pinned.get("schema", -1))).is_equal(SaveManager.CURRENT_SCHEMA_VERSION)
	assert_int(int(pinned.get("engine-state", -1))).is_equal(SimEngine.STATE_FORMAT_VERSION)
	assert_int(int(pinned.get("meta-state", -1))).is_equal(RunMeta.META_FORMAT_VERSION)


func test_l2_escalation_snapshot_is_live_and_shape_pinned() -> void:
	# §6 since L2-A: the reserve is LIVE — the real save (which banks a
	# victory) carries the snapshot with exactly the documented keys, and the
	# RUN payload never carries an escalation key (the meta-domain-only rule:
	# a run-save restore must not be able to fork the garrison).
	assert_bool(_doc_text.contains("escalation_garrison")).is_true()
	assert_bool(_doc_text.contains("L2 ESCALATION SNAPSHOT")).is_true()
	var meta_payload: Dictionary = _meta_envelope["payload"]
	assert_bool(meta_payload.has("escalation_garrison")).is_true()
	assert_bool(meta_payload.has("escalation_cycle")).is_true()
	assert_int(int(meta_payload["escalation_cycle"])).is_equal(1)
	var run_payload: Dictionary = _run_envelope["payload"]
	for system_key: String in (run_payload["systems"] as Dictionary).keys():
		assert_str(system_key).is_not_equal("escalation")  # never a system key either
		var system: Dictionary = (run_payload["systems"] as Dictionary)[system_key]
		assert_bool(not system.has("escalation_garrison")).is_true()
	assert_bool(not run_payload.has("escalation_garrison")).is_true()


# --- The real save (built once; every test reads the parsed bytes) -------------


## Plays the marathon script (start -> 500h managed -> banked victory), queues
## one command so `pending_commands` is non-empty at the save boundary, then
## writes BOTH domains through SaveManager and parses the bytes back — the
## doc describes the on-disk form, so the on-disk form is what is checked.
func _generate_real_save() -> void:
	_erase_dir(SCRATCH_ROOT)
	var fixture := THIN_LOOP.new()
	var engine: SimEngine = fixture._build()
	engine.submit_command(&"run_start", &"", 0)
	fixture._seed_run(engine)
	var ran := 0
	var total := RUN_HOURS * SimEngine.TICKS_PER_SIM_HOUR
	while ran < total:
		if ran > 0:
			fixture._manage(engine)
		ran += engine.fast_forward(mini(CHUNK_TICKS, total - ran))
	var run := engine.get_system(&"run") as RunLifecycleSystem
	run.resolve_victory(engine, true)
	engine.fast_forward(1)  # resolve_victory is tick-aligned: drain it
	engine.submit_command(&"ping", &"probe", 1)  # a queued command must survive the boundary

	var manager := SaveManager.new(SCRATCH_ROOT)
	assert_bool(manager.save_run(engine)).is_true()
	assert_bool(manager.save_meta(run.meta)).is_true()
	_run_envelope = _parse_json_file(manager.run_slot_path(0))
	_meta_envelope = _parse_json_file(manager.meta_path())
	assert_bool(not _run_envelope.is_empty())
	assert_bool(not _meta_envelope.is_empty())


## Block id -> the live key set it describes, extracted from the parsed files.
func _live_key_sets() -> Dictionary:
	var run_payload: Dictionary = _run_envelope["payload"]
	var meta_payload: Dictionary = _meta_envelope["payload"]
	var systems: Dictionary = run_payload["systems"]
	var sets := {}
	sets["run-envelope"] = _keys_of(_run_envelope)
	sets["meta-envelope"] = _keys_of(_meta_envelope)
	sets["run-payload"] = _keys_of(run_payload)
	sets["run-pending-command"] = _keys_of((run_payload["pending_commands"] as Array)[0])
	sets["run-systems"] = _keys_of(systems)
	sets["system-heartbeat"] = _keys_of(systems["heartbeat"])
	sets["system-run"] = _keys_of(systems["run"])
	sets["system-units"] = _keys_of(systems["units"])
	sets["system-units-entry"] = _keys_of((systems["units"]["units"] as Array)[0])
	sets["system-production"] = _keys_of(systems["production"])
	sets["system-production-building"] = _keys_of((systems["production"]["buildings"] as Array)[0])
	sets["system-production-quirks"] = _keys_of(systems["production"]["regime_quirks"])
	sets["meta-payload"] = _keys_of(meta_payload)
	sets["meta-chronicle-entry"] = _keys_of((meta_payload["chronicle"] as Array)[0])
	# The L2 escalation snapshot (§6): the pinned save banks a victory, so
	# the snapshot + its first roster line are on disk and shape-checked
	# like every other nested entry.
	var garrison: Dictionary = meta_payload["escalation_garrison"]
	sets["meta-escalation-garrison"] = _keys_of(garrison)
	sets["meta-escalation-roster-entry"] = _keys_of((garrison["roster"] as Dictionary).values()[0])
	return sets


# --- Doc parsing ---------------------------------------------------------------


## Extracts fenced blocks tagged ```<marker> (id) — one token per line,
## lines preserved, blank lines dropped. Untagged fences (json/gdscript/
## plain) are ignored entirely; a fence only opens on the marker.
func _parse_marked_blocks(text: String, marker: String) -> Dictionary:
	var blocks := {}
	var current_id := ""
	var current: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		var opens := "```%s" % marker
		if trimmed.begins_with(opens + " ") or trimmed == opens:
			current_id = trimmed.substr(opens.length()).strip_edges()
			if current_id.is_empty():
				current_id = marker
			current = []
		elif trimmed == "```" and not current_id.is_empty():
			blocks[current_id] = current.duplicate()
			current_id = ""
		elif not current_id.is_empty() and not trimmed.is_empty():
			current.append(trimmed)
	return blocks


# --- Helpers --------------------------------------------------------------------


func _keys_of(value: Variant) -> Array[String]:
	var keys: Array[String] = []
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			keys.append(String(key))
	keys.sort()
	return keys


func _sorted(values: Array) -> Array[String]:
	var strings: Array[String] = []
	for value in values:
		strings.append(String(value))
	strings.sort()
	return strings


func _sorted_keys(dict: Dictionary) -> Array[String]:
	return _sorted(dict.keys())


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	return text


func _parse_json_file(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(_read_text(path)) != OK:
		return {}
	return parser.data


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
	for file_name in files:
		dir.remove(file_name)
	for sub in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
