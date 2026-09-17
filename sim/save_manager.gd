## Save architecture (T-ARCH-03) — dual-domain, atomic, rotating, migratable.
##
## A plain RefCounted, deliberately NOT an autoload: headless tests construct
## isolated instances with their own root dirs (no global state, no scene
## tree, no autoload-ordering hazards — the same headless-first discipline as
## SimEngine/RunMeta), and the game host creates exactly ONE for a session
## and hands it the live engine + meta. The on-disk contract (envelope
## fields, canonical checksum, 64-bit int encoding, ring + quarantine
## semantics, migration registry) is documented in docs/save-format.md —
## that doc is the source of truth; this header is the map.
##
## Two domains, saved INDEPENDENTLY so one corrupting can never destroy the
## other (Hulk): run state (SimEngine.to_dict) goes to a rotating ring of
## RUN_SLOT_COUNT slot files; meta (RunMeta.to_dict: chronicle + legacy
## points) goes to a single meta file.
##
## Integrity model, every path tested (tests/unit/test_save_manager.gd):
##   - ATOMIC WRITES: payload text is written to <path>.tmp first, then
##     rename()d over the final path (POSIX rename(2) / MoveFileEx-with-
##     replace on Windows: the final path is never a partial file). A crash
##     mid-write can leave at most an orphan .tmp — swept by the next
##     process's first operation — while the previous good slot stays
##     untouched and loadable
##   - CHECKSUM: every file carries a SHA-256 over the canonical payload
##     form (docs/save-format.md §5), so truncation/tamper that still
##     parses as JSON is still detected
##   - QUARANTINE: an unloadable slot is renamed to *.corrupt[-n] (bytes
##     preserved for postmortem, never deleted, never able to take the
##     other slots or the other domain down); load falls back to the next
##     newest GOOD slot
##   - 64-BIT EXACTNESS (T-SIM-03 verifier note): JSON numbers are float64
##     and silently corrupt ints beyond ±2^53 — rng.state is the live
##     example and MUST survive byte-exact or determinism dies — so the
##     codec tags every out-of-range int as {"__i64__": "<decimal>"} on
##     write and restores it on read
##   - MIGRATIONS: files record their schema_version; a registry of
##     per-step callables walks old payloads forward. Missing step or
##     newer-than-current => refuse loudly, quarantine, fall back
class_name SaveManager
extends RefCounted

## Current on-disk save schema version (docs/save-format.md §7). Bump ONLY
## together with registering a migration for the previous version.
const CURRENT_SCHEMA_VERSION := 1

## Run-domain slot ring size. 3 = one corrupt newest slot still leaves two
## recovery points, and the ring never overwrites the newest good save (it
## always advances past it).
const RUN_SLOT_COUNT := 3

## Domain ids recorded in every envelope (docs/save-format.md §2).
const DOMAIN_RUN := "run"
const DOMAIN_META := "meta"

const META_FILENAME := "meta.json"
const TEMP_SUFFIX := ".tmp"
const QUARANTINE_SUFFIX := ".corrupt"

## Marker key for 64-bit-exact int carriers: {"__i64__": "18446744073709551615"}.
const U64_TAG := "__i64__"

## Last integer magnitude float64 represents exactly (2^53). Ints beyond
## ±this are tagged; ints at or inside it stay plain, diffable JSON numbers.
const JSON_SAFE_INT_LIMIT := 1 << 53

## Save root (user:// resolves per-platform; tests inject their own dirs).
var root_dir := "user://saves"

## On-disk schema version this manager READS and WRITES. Instance field (not
## a const binding) so migration tests can walk a future chain by setting
## schema_version + migrations locally — the shipped default is always
## CURRENT_SCHEMA_VERSION.
var schema_version := CURRENT_SCHEMA_VERSION

## Migration registry: int from_version -> Callable(Dictionary) -> Dictionary.
## Each entry upgrades a payload ONE step (from_version -> from_version + 1).
## Contract in docs/save-format.md §7. Ships empty at v1 (nothing to walk);
## example stub: [method example_migration_v1_to_v2].
var migrations: Dictionary = {}

## Last failure reason ("" when the previous operation succeeded). Human-
## readable, never used for control flow by the host.
var last_error := ""

var _scanned := false
var _next_save_seq := 0
var _next_run_slot := 0


func _init(p_root_dir: String = "user://saves") -> void:
	root_dir = p_root_dir


# --- Run domain (rotating ring) ---------------------------------------------


## Saves the engine's full state to the next ring slot. The ring always
## writes the slot AFTER the newest good one, i.e. it overwrites the oldest
## position. Returns false (last_error set, ring + sequence NOT advanced,
## previous good slot untouched) if the atomic write fails at any point.
func save_run(engine: SimEngine) -> bool:
	_ensure_ready()
	var slot := _next_run_slot
	var payload: Variant = encode_exact_ints(engine.to_dict())
	var text := _build_envelope_text(DOMAIN_RUN, payload, _next_save_seq)
	if not _write_atomic(run_slot_path(slot), text):
		return false
	_next_save_seq += 1
	_next_run_slot = (slot + 1) % RUN_SLOT_COUNT
	return true


## Loads the newest GOOD run slot into `engine` (registered systems must
## match what was saved; the engine's own apply_state_dict refusal rules
## apply). Corrupt/unloadable slots are quarantined and older good slots
## tried in descending save order. Returns false when nothing loadable
## remains (all slots then sit in quarantine, bytes preserved).
func load_run(engine: SimEngine) -> bool:
	_ensure_ready()
	var candidates: Array[Dictionary] = []
	for slot: int in RUN_SLOT_COUNT:
		var path := run_slot_path(slot)
		if not FileAccess.file_exists(path):
			continue
		var envelope := _read_envelope(path, DOMAIN_RUN)
		if envelope.is_empty():
			continue  # already quarantined inside; try the other slots
		candidates.append({
			"slot": slot,
			"seq": int(envelope["save_seq"]),
			"file_version": int(envelope["file_version"]),
			"payload": envelope["payload"],
		})
	if candidates.is_empty():
		last_error = "no loadable run slot in '%s' (last: %s)" % [root_dir, last_error]
		push_error("save: %s" % last_error)
		return false
	candidates.sort_custom(func(a, b) -> bool: return int(a["seq"]) > int(b["seq"]))
	for candidate: Dictionary in candidates:
		var migrated: Variant = _migrate(int(candidate["file_version"]), candidate["payload"])
		if typeof(migrated) == TYPE_DICTIONARY and engine.apply_state_dict(decode_exact_ints(migrated)):
			return true
		# Checksum + version were fine, so the slot is not corrupt — this is
		# an apply refusal (e.g. engine STATE_FORMAT_VERSION skew or host
		# misconstruction). The bytes stay in place (NOT quarantined); try
		# the next candidate so an older slot can still rescue the session.
		last_error = "run slot %d refused by the engine (migration/apply): %s" % [int(candidate["slot"]), last_error]
		push_warning("save: %s" % last_error)
	push_error("save: %s" % last_error)
	return false


## Absolute (resolved) path of run ring slot `slot`.
func run_slot_path(slot: int) -> String:
	return root_dir.path_join("run_slot_%d.json" % slot)


## Next save sequence number the ring would write (monotonic across
## processes: rescanned from the newest existing slot header).
func peek_next_save_seq() -> int:
	_ensure_ready()
	return _next_save_seq


# --- Meta domain (single file) ----------------------------------------------


## Saves the meta bank (chronicle + legacy points) atomically to its single
## file. Overwrites the previous file only after the temp write fully
## succeeded.
func save_meta(meta: RunMeta) -> bool:
	_ensure_ready()
	var payload: Variant = encode_exact_ints(meta.to_dict())
	var text := _build_envelope_text(DOMAIN_META, payload, 0)
	return _write_atomic(meta_path(), text)


## Loads the meta bank. A missing file returns a FRESH RunMeta (first boot,
## not an error). A corrupt/unloadable file is quarantined and a fresh RunMeta
## returns with last_error set — the documented single-meta-file policy
## (docs/save-format.md §8): the run slots are never touched by it.
func load_meta() -> RunMeta:
	_ensure_ready()
	var meta := RunMeta.new()
	var path := meta_path()
	if not FileAccess.file_exists(path):
		return meta
	var envelope := _read_envelope(path, DOMAIN_META)
	if envelope.is_empty():
		push_error("save: meta lost to corruption — starting a fresh bank (bytes quarantined): %s" % last_error)
		return meta
	var migrated: Variant = _migrate(int(envelope["file_version"]), envelope["payload"])
	if typeof(migrated) == TYPE_DICTIONARY and meta.apply_dict(decode_exact_ints(migrated)):
		return meta
	push_error("save: meta payload refused (migration/apply): %s" % last_error)
	return meta


## Path of the single meta-domain file.
func meta_path() -> String:
	return root_dir.path_join(META_FILENAME)


# --- 64-bit-exact int codec (docs/save-format.md §4) -------------------------


## Recursively tags every int outside the float64-exact range (|v| > 2^53)
## as {"__i64__": "<decimal>"} so JSON round-trips it exactly. Everything
## else passes through untouched (small ints stay plain, diffable numbers).
static func encode_exact_ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			if int(value) > JSON_SAFE_INT_LIMIT or int(value) < -JSON_SAFE_INT_LIMIT:
				return {U64_TAG: str(int(value))}
			return value
		TYPE_DICTIONARY:
			var encoded := {}
			for key: Variant in value:
				encoded[key] = encode_exact_ints(value[key])
			return encoded
		TYPE_ARRAY:
			var entries := []
			for entry: Variant in value:
				entries.append(encode_exact_ints(entry))
			return entries
		_:
			return value


## Inverse of [method encode_exact_ints]: any single-key {"__i64__": "..."}
## dict becomes its exact int again. Requires BOTH the exact single key and
## a String value, so ordinary payloads can never be misread as carriers.
static func decode_exact_ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			if dict.size() == 1 and dict.has(U64_TAG) and typeof(dict[U64_TAG]) == TYPE_STRING:
				return int(String(dict[U64_TAG]))
			var decoded := {}
			for key: Variant in dict:
				decoded[key] = decode_exact_ints(dict[key])
			return decoded
		TYPE_ARRAY:
			var entries := []
			for entry: Variant in value:
				entries.append(decode_exact_ints(entry))
			return entries
		_:
			return value


# --- Canonical form + checksum (docs/save-format.md §5) ----------------------


## Deterministic, formatter-independent textual form of a JSON-safe value:
## dictionary keys are sorted; ints and integral floats share one token
## (JSON parse erases the int/float distinction, so both sides of a
## round-trip must canonicalize identically); non-integral floats use
## str()'s shortest round-trip form; strings are JSON-quoted. This is
## what the envelope checksum hashes.
static func canonical_form(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "n"
		TYPE_BOOL:
			return "b1" if bool(value) else "b0"
		TYPE_INT:
			return "i%d" % int(value)
		TYPE_FLOAT:
			var floating := float(value)
			if is_finite(floating) and floating == floor(floating) and absf(floating) < float(JSON_SAFE_INT_LIMIT):
				return "i%d" % int(floating)
			# Godot's `%` operator carries no %g specifier (a runtime
			# formatting error — surfaced when finishing refinement #5's
			# type-scale preferences put 1.1 into the meta payload, the
			# first non-integral float any domain ever saved), so the
			# canonical token is str()'s shortest round-trip form: same
			# double => same token, distinct doubles => distinct tokens,
			# and stable across the JSON round-trip (the parser restores
			# the exact double).
			return "f" + str(floating)
		TYPE_STRING:
			return JSON.stringify(String(value))
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			var keys: Array = dict.keys()
			keys.sort()
			var parts: Array[String] = ["{"]
			for key: Variant in keys:
				parts.append(JSON.stringify(String(key)) + ":" + canonical_form(dict[key]))
			parts.append("}")
			return ",".join(parts)
		TYPE_ARRAY:
			var parts: Array[String] = ["["]
			for entry: Variant in value:
				parts.append(canonical_form(entry))
			parts.append("]")
			return ",".join(parts)
	push_warning("save: value of type %d has no canonical form — checksum may be unstable" % typeof(value))
	return "?"


## SHA-256 hex digest of the canonical payload form.
static func payload_checksum(payload: Variant) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical_form(payload).to_utf8_buffer())
	return ctx.finish().hex_encode()


# --- Migration registry (docs/save-format.md §7) -----------------------------


## Walks a payload from `file_version` up to this manager's schema_version,
## one registered callable per step. Returns the upgraded Dictionary, or
## null (last_error set) when a step is missing or a callable misbehaves.
## A file_version NEWER than schema_version is refused before any step runs.
func _migrate(file_version: int, payload: Dictionary) -> Variant:
	if file_version > schema_version:
		last_error = "payload schema %d is newer than this build's %d — refusing" % [file_version, schema_version]
		return null
	var current: Dictionary = payload
	var step := file_version
	while step < schema_version:
		if not migrations.has(step):
			last_error = "no migration registered for step v%d -> v%d" % [step, step + 1]
			return null
		var upgraded: Variant = migrations[step].call(current)
		if typeof(upgraded) != TYPE_DICTIONARY:
			last_error = "migration v%d -> v%d returned %s, not a Dictionary" % [step, step + 1, type_string(typeof(upgraded))]
			return null
		current = upgraded
		step += 1
	return current


## EXAMPLE ONLY (registered when the schema actually reaches v2 — see
## docs/save-format.md §7): demonstrates the migration callable contract —
## pure Dictionary -> Dictionary, additive, never destructive — by stamping
## a v2 marker. Unit-tested via a local manager with schema_version = 2.
static func example_migration_v1_to_v2(payload: Dictionary) -> Dictionary:
	var upgraded: Dictionary = payload.duplicate(true)
	upgraded["schema_migration_note"] = "upgraded v1 -> v2 by example_migration_v1_to_v2"
	return upgraded


# --- Envelope ----------------------------------------------------------------


## Serializes one file body: pretty-printed (tab-indented, diff-friendly)
## JSON with the documented envelope fields. `save_seq` participates in run
## files only (0 for meta). Written by [method _stringify_ordered], NOT
## JSON.stringify: Godot's stringify SORTS dictionary keys, and parts of the
## engine state legitimately depend on insertion order (unit gear slots feed
## state_hash in equip order — docs/save-format.md §3), so the on-disk form
## must record dictionaries exactly as the engine holds them. Godot's
## JSON.parse preserves document order, so a load rebuilds the same order.
func _build_envelope_text(domain: String, payload: Variant, save_seq: int) -> String:
	var envelope := {
		"domain": domain,
		"schema_version": schema_version,
		"save_seq": save_seq,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"checksum": payload_checksum(payload),
		"payload": payload,
	}
	if domain == DOMAIN_META:
		envelope.erase("save_seq")
	return _stringify_ordered(envelope, "", true)


## JSON writer that preserves Dictionary INSERTION order (Godot's
## JSON.stringify sorts keys, which is fine for the checksum's canonical
## form but lossy for order-sensitive engine state — see above). Scalars are
## delegated to JSON.stringify so escaping/number formatting match the
## engine's own JSON exactly.
static func _stringify_ordered(value: Variant, indent: String, pretty: bool) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			if (value as Dictionary).is_empty():
				return "{}"
			var inner := ""
			var first := true
			for key: Variant in value:
				inner += ("" if first else ",") + ("" if not pretty else "\n" + indent + "\t")
				inner += JSON.stringify(String(key)) + (":" if not pretty else ": ")
				inner += _stringify_ordered(value[key], indent + "\t" if pretty else "", pretty)
				first = false
			return "{" + inner + ("" if not pretty else "\n" + indent) + "}"
		TYPE_ARRAY:
			if (value as Array).is_empty():
				return "[]"
			var inner := ""
			var first := true
			for entry: Variant in value:
				inner += ("" if first else ",") + ("" if not pretty else "\n" + indent + "\t")
				inner += _stringify_ordered(entry, indent + "\t" if pretty else "", pretty)
				first = false
			return "[" + inner + ("" if not pretty else "\n" + indent) + "]"
		TYPE_INT:
			return str(int(value))  # int64 printed exactly (never float64)
		_:
			return JSON.stringify(value)


## Reads + fully validates one envelope (parse, domain, version bounds,
## checksum over the canonical payload). On ANY failure the file is
## quarantined (renamed, bytes preserved), last_error is set, and {} is
## returned — the caller falls back. Returns
## {"payload": ..., "file_version": int, "save_seq": int} on success.
func _read_envelope(path: String, expected_domain: String) -> Dictionary:
	var fail := func(reason: String) -> Dictionary:
		last_error = "%s: %s" % [path.get_file(), reason]
		var quarantined := _quarantine(path)
		push_warning("save: quarantined '%s' (%s -> %s)" % [path, reason, quarantined if quarantined != "" else "rename failed"])
		return {}
	var text := _read_text(path)
	if text.is_empty():
		return fail.call("empty or unreadable file")
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return fail.call("JSON parse error (line %d): %s" % [parser.get_error_line(), parser.get_error_message()])
	if typeof(parser.data) != TYPE_DICTIONARY:
		return fail.call("top-level value is %s, not an object" % type_string(typeof(parser.data)))
	var envelope: Dictionary = parser.data
	if String(envelope.get("domain", "")) != expected_domain:
		return fail.call("domain '%s' does not match expected '%s'" % [envelope.get("domain", ""), expected_domain])
	var file_version := int(envelope.get("schema_version", -1))
	if file_version < 1:
		return fail.call("schema_version %d is invalid" % file_version)
	if file_version > schema_version:
		return fail.call("schema_version %d is newer than this build's %d" % [file_version, schema_version])
	if typeof(envelope.get("payload")) != TYPE_DICTIONARY:
		return fail.call("payload missing or not an object")
	var actual := payload_checksum(envelope["payload"])
	if actual != String(envelope.get("checksum", "")):
		return fail.call("checksum mismatch (truncated or tampered)")
	return {
		"payload": envelope["payload"],
		"file_version": file_version,
		"save_seq": int(envelope.get("save_seq", 0)),
	}


# --- Atomic write ------------------------------------------------------------


## Write-temp-rename. The temp file lives in the SAME directory (rename is
## only atomic within one filesystem). Any pre-existing temp at the path is
## removed first (single-writer assumption, docs/save-format.md §3). The
## write itself goes through [method _write_temp_file] — the seam crash
## simulations subclass.
func _write_atomic(path: String, text: String) -> bool:
	last_error = ""
	var tmp := path + TEMP_SUFFIX
	_remove_file(tmp)
	if not _write_temp_file(tmp, text):
		return false
	var dir := DirAccess.open(root_dir)
	if dir == null:
		last_error = "cannot open save root '%s' for rename" % root_dir
		return false
	if dir.rename(tmp.get_file(), path.get_file()) != OK:
		last_error = "rename '%s' -> '%s' failed" % [tmp, path]
		return false
	return true


## Writes the full text to `tmp_path`. Returns false on any open/write
## failure (the final path then still holds the previous good save). NOTE:
## Godot's FileAccess exposes flush() (fflush) but no fsync(); the
## never-a-partial-final-file guarantee is carried by the atomic rename,
## which is exactly what the kill-during-save tests prove (docs §3).
func _write_temp_file(tmp_path: String, text: String) -> bool:
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_error = "cannot open '%s' for write (err %d)" % [tmp_path, FileAccess.get_open_error()]
		return false
	file.store_string(text)
	file.flush()
	var write_ok := file.get_error() == OK
	file.close()
	if not write_ok:
		last_error = "write failed on '%s'" % tmp_path
	return write_ok


# --- Ring scan / housekeeping -------------------------------------------------


## One-time per instance: create the root, sweep orphan temp files left by
## a killed process, and rescan the ring so save_seq stays monotonic and the
## next write lands AFTER the newest existing slot.
func _ensure_ready() -> void:
	if _scanned:
		return
	DirAccess.make_dir_recursive_absolute(root_dir)
	_sweep_temp_files()
	var best_seq := -1
	var best_slot := -1
	for slot: int in RUN_SLOT_COUNT:
		var path := run_slot_path(slot)
		if not FileAccess.file_exists(path):
			continue
		var seq := _peek_save_seq(path)
		if seq > best_seq:
			best_seq = seq
			best_slot = slot
	if best_slot >= 0:
		_next_save_seq = best_seq + 1
		_next_run_slot = (best_slot + 1) % RUN_SLOT_COUNT
	_scanned = true


## Reads just the save_seq header field; -1 when unreadable (the load path
## will quarantine such a slot properly — the scan only needs the newest).
func _peek_save_seq(path: String) -> int:
	var parser := JSON.new()
	if parser.parse(_read_text(path)) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return -1
	return int((parser.data as Dictionary).get("save_seq", -1))


## Removes every *.tmp in the save root — any temp present when a NEW
## process starts is by definition abandoned (writes are synchronous and
## single-writer; docs/save-format.md §3).
func _sweep_temp_files() -> void:
	var dir := DirAccess.open(root_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var names: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(TEMP_SUFFIX):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name: String in names:
		dir.remove(name)


## Renames an unloadable file to <name>.corrupt[-n], preserving its bytes
## for postmortem. Returns the quarantine path, or "" if the rename failed.
func _quarantine(path: String) -> String:
	var base := path + QUARANTINE_SUFFIX
	var target := base
	var n := 1
	while FileAccess.file_exists(target):
		n += 1
		target = "%s-%d" % [base, n]
	var dir := DirAccess.open(root_dir)
	if dir == null or dir.rename(path.get_file(), target.get_file()) != OK:
		push_warning("save: could not quarantine '%s'" % path)
		return ""
	return target


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	var read_ok := file.get_error() == OK
	file.close()
	if not read_ok:
		return ""
	return text


func _remove_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir := DirAccess.open(root_dir)
	if dir != null:
		dir.remove(path.get_file())
