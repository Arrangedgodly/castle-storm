## Unit tests for the save architecture (T-ARCH-03) — Hawkeye + Hulk lanes.
##
## Mirrors sim/save_manager.gd (test-mapping rule, docs/gdscript-conventions.md).
## Hulk diligence: every failure path — process killed mid-write (both the
## truncated-temp and the killed-before-renamed variants), truncated file,
## empty file, corrupt JSON, tampered-but-parseable payload (checksum),
## wrong schema version (future + missing migration), slot ring wraparound,
## domain mismatch, meta corrupt while run intact and vice versa — with the
## invariant under test always: A FAILED OR CORRUPT SAVE NEVER DESTROYS THE
## PREVIOUS GOOD SLOT, and load falls back. Iron Man diligence: 64-bit-exact
## rng_state round-trips (the T-SIM-03 verifier note) and the migration
## registry contract, including the v1->v2 example stub.
extends GdUnitTestSuite


## Test-local system: draws from the engine RNG every tick so saved rng.state
## is nontrivial, and carries one field through to_dict/from_dict.
class ProbeSystem extends SimSystem:
	var draws := 0

	func system_name() -> StringName:
		return &"save_probe"

	func on_tick(engine: SimEngine) -> void:
		draws += 1
		engine.rng.randi()

	func state_hash() -> int:
		return draws

	func to_dict() -> Dictionary:
		return {"draws": draws}

	func from_dict(state: Dictionary) -> void:
		draws = int(state.get("draws", 0))


## Crash simulation 1: process killed MID temp write — a truncated .tmp is
## left behind, the final path never sees a byte.
class CrashMidWriteManager extends SaveManager:
	func _write_temp_file(tmp_path: String, text: String) -> bool:
		var file := FileAccess.open(tmp_path, FileAccess.WRITE)
		if file != null:
			file.store_string(text.substr(0, int(text.length() * 0.6)))
			file.flush()
			file.close()
		return false


## Crash simulation 2: temp file FULLY written, then the process dies before
## the rename — the worst an interrupted save can legitimately leave on disk.
class KilledBeforeRenameManager extends SaveManager:
	func _write_temp_file(tmp_path: String, text: String) -> bool:
		var _written: bool = super._write_temp_file(tmp_path, text)
		return false


var _dir_seq := 0


## gdUnit4 6.2.1 suite hooks are before()/after() — there is NO before_all/
## after_all (the T-DATA-03 note: this was an `after_all` that silently never
## ran, leaving every scratch root behind). `after()` fires once at suite end;
## each test also cleans its own dir up front.
func after() -> void:
	_erase_dir("user://cs_save_tests")


## Godot's DirAccess exposes no recursive remove — hand-rolled (files first,
## then subdirectories, then the emptied directory itself).
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


## A manager on a fresh, cleaned-up root (per-test isolation under user://).
func _new_manager(script: GDScript = null) -> SaveManager:
	_dir_seq += 1
	var root := "user://cs_save_tests/run-%02d" % _dir_seq
	_erase_dir(root)
	if script == null:
		return SaveManager.new(root)
	return script.new(root)


## A fresh instance pointed at the SAME root — the "next process" seam: all
## state flows through the disk, none through the instance.
func _reopen(manager: SaveManager, script: GDScript = null) -> SaveManager:
	if script == null:
		return SaveManager.new(manager.root_dir)
	return script.new(manager.root_dir)


func _erase_root(path: String) -> void:
	_erase_dir(path)


func _build_engine(run_seed: int) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(ProbeSystem.new())
	return engine


func _build_meta() -> RunMeta:
	var meta := RunMeta.new()
	meta.legacy_points = 147
	meta.runs_recorded = 1
	meta.chronicle.append({
		"leader": "Bran the Unbearable",
		"regime": "gilded_crown",
		"outcome": "won",
		"duration_hours": 150,
		"army": {"knight": 50, "archer": 0},
		"score": 147,
	})
	return meta


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	return text


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _parse_file(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(_read_file(path)) != OK:
		return {}
	return parser.data


# --- Happy path: run domain -------------------------------------------------


func test_run_save_load_round_trip_hash_identical() -> void:
	var engine := _build_engine(20260915)
	engine.fast_forward(500)
	var saved_hash := engine.state_hash()
	var manager := _new_manager()
	assert_bool(manager.save_run(engine)).is_true()
	assert_str(manager.last_error).is_empty()

	var twin := _build_engine(1)  # different seed: load must fully overwrite it
	twin.fast_forward(3)  # and different history
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(saved_hash)
	assert_int(twin.rng.state).is_equal(engine.rng.state)
	assert_int(twin.tick_count).is_equal(engine.tick_count)


func test_run_save_writes_pretty_diffable_json() -> void:
	var engine := _build_engine(7)
	engine.fast_forward(10)
	var manager := _new_manager()
	assert_bool(manager.save_run(engine)).is_true()
	var text := _read_file(manager.run_slot_path(0))
	assert_that(text.contains("\n\t")).is_true()  # tab-indented, line-per-field
	assert_that(text.contains("\"domain\": \"run\"")).is_true()
	assert_that(text.contains("\"schema_version\": 1")).is_true()
	assert_that(text.contains("\"checksum\": \"")).is_true()
	assert_that(text.contains("\"payload\": {")).is_true()


func test_run_and_meta_are_separate_files() -> void:
	var manager := _new_manager()
	assert_bool(manager.save_run(_build_engine(7))).is_true()
	assert_bool(manager.save_meta(_build_meta())).is_true()
	assert_bool(FileAccess.file_exists(manager.run_slot_path(0))).is_true()
	assert_bool(FileAccess.file_exists(manager.meta_path())).is_true()
	assert_str(_parse_file(manager.run_slot_path(0))["domain"]).is_equal("run")
	assert_str(_parse_file(manager.meta_path())["domain"]).is_equal("meta")


func test_load_run_with_no_slots_fails_loudly() -> void:
	var manager := _new_manager()
	var engine := _build_engine(7)
	assert_bool(manager.load_run(engine)).is_false()
	assert_str(manager.last_error).is_not_empty()


func test_root_dir_created_on_first_save() -> void:
	_dir_seq += 1
	var base := "user://cs_save_tests/nested-%02d" % _dir_seq
	var manager := SaveManager.new(base + "/deeper")
	assert_bool(manager.save_run(_build_engine(7))).is_true()
	assert_bool(DirAccess.dir_exists_absolute(base + "/deeper")).is_true()


func test_save_seq_monotonic_across_manager_instances() -> void:
	var engine := _build_engine(7)
	var first := _new_manager()
	assert_bool(first.save_run(engine)).is_true()
	assert_int(first.peek_next_save_seq()).is_equal(1)
	var second := _reopen(first)  # fresh "process": rescans the ring header
	assert_int(second.peek_next_save_seq()).is_equal(1)
	engine.fast_forward(1)
	assert_bool(second.save_run(engine)).is_true()
	assert_int(_reopen(second).peek_next_save_seq()).is_equal(2)


# --- Happy path: meta domain --------------------------------------------------


func test_meta_save_load_round_trip() -> void:
	var manager := _new_manager()
	var meta := _build_meta()
	assert_bool(manager.save_meta(meta)).is_true()

	var loaded := _reopen(manager).load_meta()
	assert_int(loaded.legacy_points).is_equal(147)
	assert_int(loaded.runs_recorded).is_equal(1)
	assert_int(loaded.chronicle.size()).is_equal(1)
	# JSON parse erases int/float distinctions (50 -> 50.0), so compare
	# entries through the save format's canonical form.
	assert_str(SaveManager.canonical_form(loaded.chronicle[0])).is_equal(SaveManager.canonical_form(meta.chronicle[0]))
	assert_int(int(loaded.chronicle[0]["score"])).is_equal(147)
	assert_int(int(loaded.chronicle[0]["army"]["knight"])).is_equal(50)


func test_missing_meta_returns_fresh_run_meta() -> void:
	var manager := _new_manager()
	var loaded := manager.load_meta()
	assert_int(loaded.legacy_points).is_equal(0)
	assert_int(loaded.chronicle.size()).is_equal(0)
	assert_str(manager.last_error).is_empty()  # first boot is not an error


# --- 64-bit exactness (T-SIM-03 verifier note) --------------------------------


func test_rng_state_survives_exact_beyond_float_precision() -> void:
	var engine := _build_engine(20260915)
	engine.fast_forward(60)
	# 2^53 + 1: the first integer float64 CANNOT represent. If the save
	# pipeline carried this through a float anywhere, it would come back as
	# 9007199254740992 and the hash comparison below would fail.
	engine.rng.state = 9007199254740993
	var saved_hash := engine.state_hash()
	var manager := _new_manager()
	assert_bool(manager.save_run(engine)).is_true()
	assert_that(_read_file(manager.run_slot_path(0)).contains("__i64__")).is_true()

	var twin := _build_engine(1)
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	assert_int(twin.rng.state).is_equal(9007199254740993)
	assert_int(twin.state_hash()).is_equal(saved_hash)


func test_rng_state_max_int64_survives_exact() -> void:
	var engine := _build_engine(3)
	engine.rng.state = 9223372036854775807  # int64 max — full 63-bit spread
	var saved_hash := engine.state_hash()
	var manager := _new_manager()
	assert_bool(manager.save_run(engine)).is_true()
	var twin := _build_engine(1)
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	assert_int(twin.rng.state).is_equal(9223372036854775807)
	assert_int(twin.state_hash()).is_equal(saved_hash)


func test_negative_big_int_survives_exact() -> void:
	var engine := _build_engine(3)
	engine.rng.state = -9007199254740993
	var saved_hash := engine.state_hash()
	var manager := _new_manager()
	assert_bool(manager.save_run(engine)).is_true()
	var twin := _build_engine(1)
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	assert_int(twin.rng.state).is_equal(-9007199254740993)
	assert_int(twin.state_hash()).is_equal(saved_hash)


func test_small_ints_stay_untagged_plain_json() -> void:
	var engine := _build_engine(20260915)
	engine.rng.state = 42  # everything in range: nothing needs the tag
	var manager := _new_manager()  # zero ticks: no RNG draws, state stays 42
	assert_bool(manager.save_run(engine)).is_true()
	assert_that(_read_file(manager.run_slot_path(0)).contains("__i64__")).is_false()
	assert_that(_read_file(manager.run_slot_path(0)).contains("\"rng_state\": 42")).is_true()
	assert_that(_read_file(manager.run_slot_path(0)).contains("\"run_seed\": 20260915")).is_true()


func test_exact_int_codec_nested_round_trip() -> void:
	var payload := {
		"small": 123,
		"big": 9007199254740993,
		"negative_big": -4611686018427387905,
		"nested": [{"deep_big": 9223372036854775807, "text": "__i64__"}],
		"text": "not a number",
	}
	var decoded: Dictionary = SaveManager.decode_exact_ints(SaveManager.encode_exact_ints(payload))
	assert_int(int(decoded["small"])).is_equal(123)
	assert_int(int(decoded["big"])).is_equal(9007199254740993)
	assert_int(int(decoded["negative_big"])).is_equal(-4611686018427387905)
	assert_int(int(decoded["nested"][0]["deep_big"])).is_equal(9223372036854775807)
	assert_str(String(decoded["nested"][0]["text"])).is_equal("__i64__")
	assert_str(String(decoded["text"])).is_equal("not a number")


func test_codec_ignores_lookalike_dicts_with_extra_keys() -> void:
	# A dict that merely CONTAINS the tag key alongside others is ordinary
	# data (only the exact single-key form is a carrier) — it passes through.
	var lookalike := {"__i64__": "7", "extra": 1}
	var decoded: Dictionary = SaveManager.decode_exact_ints(lookalike)
	assert_int(decoded.size()).is_equal(2)
	assert_str(String(decoded["__i64__"])).is_equal("7")


func test_canonical_form_int_and_integral_float_agree() -> void:
	# JSON parse erases int/float; canonical must hash both identically or
	# every save would fail its own checksum on reload.
	assert_str(SaveManager.canonical_form(3)).is_equal(SaveManager.canonical_form(3.0))
	assert_str(SaveManager.canonical_form(0.5)).is_equal(SaveManager.canonical_form(0.5))
	# Distinct types stay distinct tokens (quoted string vs nil vs bool).
	assert_str(SaveManager.canonical_form("n")).is_not_equal(SaveManager.canonical_form(null))
	assert_str(SaveManager.canonical_form(true)).is_not_equal(SaveManager.canonical_form("b1"))
	# Key order is normalized away.
	assert_str(SaveManager.canonical_form({"b": 1, "a": 2})).is_equal(SaveManager.canonical_form({"a": 2, "b": 1}))


func test_disk_json_preserves_dictionary_insertion_order() -> void:
	# Godot's JSON.stringify SORTS dictionary keys, but engine state hashes
	# can legitimately depend on insertion order (unit gear slots mix into
	# state_hash in equip order). The save writer must not reorder, and a
	# parse of the written text must rebuild the same order — otherwise the
	# 500h marathon round-trip diverges (found by save_marathon_roundtrip).
	var ordered := {"zeta": 1, "alpha": 2, "nested": {"weapon": "w", "armor": "a"}}
	var text: String = SaveManager._stringify_ordered(ordered, "", true)
	assert_int(text.find("\"zeta\"")).is_less(text.find("\"alpha\""))  # NOT sorted
	var parser := JSON.new()
	assert_int(parser.parse(text)).is_equal(OK)
	var keys: Array = (parser.data as Dictionary).keys()
	assert_str(String(keys[0])).is_equal("zeta")
	assert_str(String(keys[1])).is_equal("alpha")
	var nested: Array = ((parser.data as Dictionary)["nested"] as Dictionary).keys()
	assert_str(String(nested[0])).is_equal("weapon")
	assert_str(String(nested[1])).is_equal("armor")


func test_checksum_stable_across_disk_round_trip() -> void:
	var engine := _build_engine(99)
	engine.fast_forward(100)
	var writer := _new_manager()
	assert_bool(writer.save_run(engine)).is_true()
	var first_checksum := String(_parse_file(writer.run_slot_path(0))["checksum"])

	# Same logical state, second save: envelope differs (saved_at), payload
	# checksum must not.
	var twin := _build_engine(1)
	assert_bool(_reopen(writer).load_run(twin)).is_true()
	var writer2 := _reopen(writer)
	assert_bool(writer2.save_run(twin)).is_true()
	assert_str(String(_parse_file(writer2.run_slot_path(1))["checksum"])).is_equal(first_checksum)


# --- Corruption: every Hulk path, fallback + quarantine -----------------------


## Saves an evolving engine three times; returns [hash1, hash2, hash3].
func _save_three_generations(manager: SaveManager) -> Array[int]:
	var engine := _build_engine(20260915)
	var hashes: Array[int] = []
	for generation: int in 3:
		engine.fast_forward(100 * (generation + 1))
		assert_bool(manager.save_run(engine)).is_true()
		hashes.append(engine.state_hash())
	return hashes


func _load_and_hash(manager: SaveManager) -> int:
	var twin := _build_engine(1)
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	return twin.state_hash()


func test_truncated_file_quarantined_and_falls_back() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	# Newest slot is 2 (seq 3). Truncate it mid-file — parse fails.
	var newest := manager.run_slot_path(2)
	var text := _read_file(newest)
	_write_file(newest, text.substr(0, int(text.length() * 0.55)))
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])  # fell back to seq 2
	assert_bool(FileAccess.file_exists(newest + ".corrupt")).is_true()


func test_empty_file_quarantined_and_falls_back() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	_write_file(manager.run_slot_path(2), "")
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(manager.run_slot_path(2) + ".corrupt")).is_true()


func test_corrupt_json_quarantined_and_falls_back() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	_write_file(manager.run_slot_path(2), "{ not json at all")
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(manager.run_slot_path(2) + ".corrupt")).is_true()


func test_tampered_but_parseable_payload_caught_by_checksum() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	# Rewrite one payload value so the file still parses — only the checksum
	# can catch this class of corruption.
	var newest := manager.run_slot_path(2)
	var envelope := _parse_file(newest)
	envelope["payload"]["tick_count"] = 999999
	_write_file(newest, JSON.stringify(envelope, "\t"))
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(newest + ".corrupt")).is_true()


func test_future_schema_version_quarantined() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	var newest := manager.run_slot_path(2)
	var envelope := _parse_file(newest)
	envelope["schema_version"] = 99  # from a newer game build
	_write_file(newest, JSON.stringify(envelope, "\t"))
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(newest + ".corrupt")).is_true()


func test_domain_mismatch_quarantined() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	assert_bool(manager.save_meta(_build_meta())).is_true()
	# Meta bytes planted in a run slot: valid envelope, WRONG domain.
	_write_file(manager.run_slot_path(2), _read_file(manager.meta_path()))
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(manager.run_slot_path(2) + ".corrupt")).is_true()
	# The real meta file was never touched.
	assert_str(_parse_file(manager.meta_path())["domain"]).is_equal("meta")


func test_quarantine_preserves_bytes() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	var corrupt_bytes := "{ mangled beyond recognition"
	_write_file(manager.run_slot_path(2), corrupt_bytes)
	assert_int(_load_and_hash(manager)).is_equal(hashes[1])  # fallback worked
	assert_str(_read_file(manager.run_slot_path(2) + ".corrupt")).is_equal(corrupt_bytes)


func test_all_run_slots_corrupt_meta_intact() -> void:
	var manager := _new_manager()
	_save_three_generations(manager)
	assert_bool(manager.save_meta(_build_meta())).is_true()
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		_write_file(manager.run_slot_path(slot), "garbage %d" % slot)

	var loader := _reopen(manager)
	var engine := _build_engine(1)
	assert_bool(loader.load_run(engine)).is_false()
	assert_str(loader.last_error).is_not_empty()
	# The OTHER domain survived untouched — and every corrupt slot's bytes
	# are preserved in quarantine, not deleted.
	var meta := loader.load_meta()
	assert_int(meta.legacy_points).is_equal(147)
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		assert_bool(FileAccess.file_exists(manager.run_slot_path(slot) + ".corrupt")).is_true()


func test_meta_corrupt_run_intact() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	assert_bool(manager.save_meta(_build_meta())).is_true()
	_write_file(manager.meta_path(), "{\"legacy_points\": 99999")  # truncated

	var loader := _reopen(manager)
	var engine := _build_engine(1)
	assert_bool(loader.load_run(engine)).is_true()  # run slots unaffected
	assert_int(engine.state_hash()).is_equal(hashes[2])
	var meta := loader.load_meta()
	assert_int(meta.legacy_points).is_equal(0)  # fresh bank policy (docs §8)
	assert_int(meta.chronicle.size()).is_equal(0)
	assert_str(loader.last_error).is_not_empty()
	assert_bool(FileAccess.file_exists(manager.meta_path() + ".corrupt")).is_true()


# --- Kill-during-save (atomicity on every path) --------------------------------


func test_failed_save_leaves_previous_good_slot_loadable() -> void:
	var manager := _new_manager()
	var engine := _build_engine(20260915)
	engine.fast_forward(100)
	assert_bool(manager.save_run(engine)).is_true()
	var good_hash := engine.state_hash()

	# "Process killed" mid-write: save reports failure, leaves a truncated
	# temp behind, and the final slot never sees a byte of it.
	engine.fast_forward(100)
	var crashed := _reopen(manager, CrashMidWriteManager)
	assert_bool(crashed.save_run(engine)).is_false()

	# Atomicity: the previous good slot is still there, still loadable, and
	# a fresh process sweeps the orphan temp on its first operation.
	var twin := _build_engine(1)
	var loader := _reopen(manager)
	assert_bool(loader.load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(good_hash)
	assert_bool(not FileAccess.file_exists(manager.run_slot_path(1) + SaveManager.TEMP_SUFFIX)).is_true()


func test_killed_before_rename_recovers_identically() -> void:
	var manager := _new_manager()
	var engine := _build_engine(20260915)
	engine.fast_forward(100)
	assert_bool(manager.save_run(engine)).is_true()
	var good_hash := engine.state_hash()

	engine.fast_forward(100)
	var killed := _reopen(manager, KilledBeforeRenameManager)
	assert_bool(killed.save_run(engine)).is_false()
	# The worst legitimate crash leftover: a COMPLETE temp next to the slot.
	assert_bool(FileAccess.file_exists(manager.run_slot_path(1) + SaveManager.TEMP_SUFFIX)).is_true()
	# Slot 1 itself was never touched (no partial final file, ever).
	assert_bool(not FileAccess.file_exists(manager.run_slot_path(1))).is_true()

	var twin := _build_engine(1)
	var loader := _reopen(manager)
	assert_bool(loader.load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(good_hash)
	# And the next process swept the orphan.
	assert_bool(not FileAccess.file_exists(manager.run_slot_path(1) + SaveManager.TEMP_SUFFIX)).is_true()


func test_stale_temp_from_killed_process_is_swept() -> void:
	var manager := _new_manager()
	var engine := _build_engine(7)
	engine.fast_forward(10)
	assert_bool(manager.save_run(engine)).is_true()
	_write_file(manager.run_slot_path(1) + SaveManager.TEMP_SUFFIX, "orphaned partial bytes")

	var next_process := _reopen(manager)
	next_process.peek_next_save_seq()  # forces the scan + sweep
	assert_bool(not FileAccess.file_exists(manager.run_slot_path(1) + SaveManager.TEMP_SUFFIX)).is_true()
	var twin := _build_engine(1)
	assert_bool(next_process.load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())


# --- Ring rotation ---------------------------------------------------------------


func test_slot_ring_wraps_after_three_saves() -> void:
	var manager := _new_manager()
	var engine := _build_engine(20260915)
	for generation: int in 5:
		engine.fast_forward(50)
		assert_bool(manager.save_run(engine)).is_true()
	# Ring order: saves 1..5 (seqs 0..4) landed in slots 0,1,2,0,1.
	var seqs: Array[int] = []
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		seqs.append(int(_parse_file(manager.run_slot_path(slot))["save_seq"]))
	assert_int(seqs[0]).is_equal(3)
	assert_int(seqs[1]).is_equal(4)
	assert_int(seqs[2]).is_equal(2)
	# Latest good is the 5th save.
	var twin := _build_engine(1)
	assert_bool(_reopen(manager).load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	# The sequence is monotonic; the next save rotates past the newest.
	assert_int(manager.peek_next_save_seq()).is_equal(5)


# --- Version skew + migrations ----------------------------------------------------


func test_engine_format_skew_falls_back_without_destroying() -> void:
	var manager := _new_manager()
	var hashes := _save_three_generations(manager)
	# A slot saved by an engine with a NEWER internal state format parses,
	# checksums and migrates fine — but this build's engine refuses it
	# (apply_state_dict version rule). It must fall back, NOT quarantine:
	# the bytes are future-good, not corrupt. (The envelope checksum is
	# recomputed: format_version lives INSIDE the payload.)
	var newest := manager.run_slot_path(2)
	var envelope := _parse_file(newest)
	envelope["payload"]["format_version"] = 99
	envelope["checksum"] = SaveManager.payload_checksum(envelope["payload"])
	_write_file(newest, JSON.stringify(envelope, "\t"))

	var twin := _build_engine(1)
	var loader := _reopen(manager)
	assert_bool(loader.load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(hashes[1])
	assert_bool(FileAccess.file_exists(newest)).is_true()  # left in place
	assert_bool(not FileAccess.file_exists(newest + ".corrupt")).is_true()


func test_missing_migration_step_refuses() -> void:
	var engine := _build_engine(7)
	engine.fast_forward(10)
	var writer := _new_manager()
	assert_bool(writer.save_run(engine)).is_true()

	# A future build (schema 2) with NO registered 1->2 migration: the
	# honest refusal — never a guessed upgrade.
	var future := _reopen(writer)
	future.schema_version = 2
	var twin := _build_engine(1)
	assert_bool(future.load_run(twin)).is_false()
	assert_str(future.last_error).is_not_empty()


func test_migration_chain_walks_registered_steps() -> void:
	var engine := _build_engine(7)
	engine.fast_forward(10)
	var writer := _new_manager()
	assert_bool(writer.save_run(engine)).is_true()

	var migrated_to_v3 := func(payload: Dictionary) -> Dictionary:
		var upgraded: Dictionary = payload.duplicate(true)
		upgraded["third_epoch_note"] = "v3"
		return upgraded

	var future := _reopen(writer)
	future.schema_version = 3
	future.migrations = {
		1: Callable(SaveManager, "example_migration_v1_to_v2"),
		2: migrated_to_v3,
	}
	var twin := _build_engine(1)
	assert_bool(future.load_run(twin)).is_true()
	assert_int(twin.state_hash()).is_equal(engine.state_hash())
	# The chain ran BOTH steps in order, on the payload itself.
	var walked: Variant = future._migrate(1, _parse_file(writer.run_slot_path(0))["payload"])
	assert_that(typeof(walked) == TYPE_DICTIONARY).is_true()
	assert_str(String((walked as Dictionary).get("schema_migration_note", ""))).is_not_empty()
	assert_str(String((walked as Dictionary).get("third_epoch_note", ""))).is_equal("v3")


func test_example_migration_stub_is_additive() -> void:
	var payload := {"format_version": 1, "run_seed": 5, "systems": {}}
	var upgraded: Dictionary = SaveManager.example_migration_v1_to_v2(payload)
	assert_int(upgraded.size()).is_equal(payload.size() + 1)  # additive only
	assert_str(String(upgraded.get("schema_migration_note", ""))).is_not_empty()
	assert_int(int(upgraded["run_seed"])).is_equal(5)  # nothing destroyed
	assert_int(payload.size()).is_equal(3)  # input untouched (pure function)
