## Security policy enforcement suite (T-SEC-01) — Captain America lane.
##
## Asserts the testable claims of docs/security-policy.md so the policy is
## CI-wired, not aspirational. Three groups:
##
##   1. BEHAVIOR — the clock-cheat envelope: the catch-up clamps hold under
##      adversarial elapsed values (int64 extremes composed through the real
##      pipeline), repeated manipulation cycles on a REAL engine are bounded
##      to one capped window per away-window (backwards cycles cost nothing,
##      hash-identical), and away-window suspicion movement is ENGINE-RULED
##      (exact pure decay; live-twin parity on a loud estate — the cheater's
##      estate gets louder, not richer).
##   2. STRUCTURAL SCANS (sim-time-only decay + write-only save stamp) — the
##      wall-clock surface inventory of security-policy.md §1.1, enforced as
##      a code scan: sim/ may read a wall clock ONLY on the single
##      documented write-only UTC `saved_at_unix` line in save_manager.gd;
##      the suspicion system must have zero clock paths.
##   3. NETWORK TRIPWIRE — zero network APIs / process escapes across the
##      game trees (sim, ui, content, scripts). Future creep — an
##      HTTPRequest, a socket, a "quick analytics call" — fails here.
##
## Scan scope notes: comment-stripped code is scanned (documentation
## comments stay free — these are tripwires for creep, not sandboxes; code
## review is the second layer). tools/ holds only the vendored engine
## binary (no scripts) and tests/ are the scanners themselves — neither is
## game code. Non-vacuity is asserted: the scan must see 20+ files
## including named anchor files, so a path typo cannot pass silently.
extends GdUnitTestSuite

const RUN_SEED := 20260925
const CAP_SECONDS := 8 * 3600  # R4 default cap
const CAP_TICKS := 480
const T0 := 1_790_000_000  # fixed injected UTC epoch (never a wall clock)

# Game-code trees the network tripwire walks (security-policy.md §2).
const SCAN_ROOTS: Array[String] = ["res://sim", "res://ui", "res://content", "res://scripts"]

# The scan must actually see the codebase — a broken path would otherwise
# pass every zero-hits assertion vacuously.
const ANCHOR_FILES: Array[String] = [
	"res://sim/sim_engine.gd",
	"res://sim/catch_up_service.gd",
	"res://sim/save_manager.gd",
	"res://sim/systems/suspicion_system.gd",
	"res://ui/main.gd",
	"res://content/schema/economy_tunables.gd",
	"res://scripts/save_debug.gd",
]

# Network / process-escape APIs (security-policy.md §2's inventory). Matched
# case-sensitively against comment-stripped code: class constructs and the
# method calls that would use them. Substring-class tokens ("StreamPeer",
# "PacketPeer", "MultiplayerPeer", "WebSocket") cover their subclasses.
const BANNED_NETWORK_TOKENS: Array[String] = [
	"HTTPClient",
	"HTTPRequest",
	"StreamPeer",
	"PacketPeer",
	"WebSocket",
	"MultiplayerPeer",
	"ENetConnection",
	"ENetMultiplayerPeer",
	"UDPServer",
	"TLSOptions",
	"JavaScriptBridge",
	"OS.shell_open",
	"OS.execute",
	"OS.create_process",
	"Engine.get_singleton",
	".create_client",
	".create_server",
	".connect_to_host",
	".open_url",
]

# Telemetry vocabulary, matched case-INSENSITIVELY: even a string literal
# naming a telemetry/analytics surface deserves a second look at review.
const BANNED_TELEMETRY_WORDS: Array[String] = [
	"telemetry",
	"analytics",
	"crashlytics",
	"gamecenter",
	"gameservices",
]

var _dir_seq := 0


## gdUnit4 6.2.1 suite hook (once per suite). Sweeps any scratch dirs a
## failed test left behind — policy tests must not litter user://.
func after() -> void:
	for seq in range(1, _dir_seq + 1):
		_erase_dir("user://cs_security_policy_%d" % seq)


# --- Fixtures (same in-code content shape as test_catch_up_service.gd) --------


func _tunables(interval_hours := 1.0, follower_weight := 0.0) -> EconomyTunables:
	var tunables := EconomyTunables.new()
	tunables.recruit_arrival_jitter_hours = 0.0  # metronome: zero RNG draws
	tunables.recruit_arrival_interval_hours = interval_hours
	# Quiet estate: presence weights 0 so away-window suspicion is pure decay.
	tunables.suspicion_presence_army_per_hour = 0.0
	tunables.suspicion_presence_follower_per_hour = follower_weight
	tunables.suspicion_presence_building_per_hour = 0.0
	tunables.suspicion_presence_offer_per_hour = 0.0
	return tunables


func _identity() -> IdentityPools:
	var pools := IdentityPools.new()
	pools.leader_first_names = ["Bran", "Ottilie", "Wick", "Mabel"]
	pools.leader_epithets = ["the Unbearable", "the Almost Wise", "of the Leaky Barn"]
	pools.personality_tags = [&"ambitious", &"pious", &"paranoid"]
	pools.recruit_names = ["Tom", "Hob", "Nell", "Kate", "Wat", "Dick"]
	return pools


func _regime() -> RegimeDef:
	var regime := RegimeDef.new()
	regime.id = &"gilded_crown"
	regime.display_name = "The Gilded Crown"
	var combat := RegimeModifier.new()
	combat.kind = &"garrison_multiplier"
	combat.value = 1.2
	regime.combat_modifier = combat
	var quirk := RegimeModifier.new()
	quirk.kind = &"production_multiplier"
	quirk.target = &"timber"
	quirk.value = 0.85
	regime.economy_quirk = quirk
	return regime


func _farm() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"farm"
	def.display_name = "Farm"
	def.resource_produced = &"food"
	def.base_production_per_worker_hour = 6.0
	def.worker_slots_base = 2
	var cost: Dictionary[StringName, int] = {}
	cost[&"timber"] = 15
	def.base_cost = cost
	def.cost_growth = 1.08
	def.max_level = 30
	return def


func _unit_defs() -> Array[UnitDef]:
	var defs: Array[UnitDef] = []
	var peasant := UnitDef.new()
	peasant.id = &"peasant"
	peasant.display_name = "Peasant"
	peasant.promotion_paths.append(&"worker")
	peasant.promotion_paths.append(&"militia")
	defs.append(peasant)

	var worker := UnitDef.new()
	worker.id = &"worker"
	worker.display_name = "Worker"
	worker.can_work = true
	worker.training_time_hours = 0.5
	defs.append(worker)

	var militia := UnitDef.new()
	militia.id = &"militia"
	militia.display_name = "Militia"
	militia.training_time_hours = 2.0
	militia.promotion_paths.append(&"trainee")
	militia.suspicion_on_train = 8
	defs.append(militia)

	var trainee := UnitDef.new()
	trainee.id = &"trainee"
	trainee.display_name = "Trainee"
	trainee.training_time_hours = 4.0
	trainee.promotion_paths.append(&"knight")
	trainee.promotion_paths.append(&"archer")
	defs.append(trainee)

	var knight := UnitDef.new()
	knight.id = &"knight"
	knight.display_name = "Knight"
	knight.training_time_hours = 12.0
	knight.combat_power = 10
	defs.append(knight)

	var archer := UnitDef.new()
	archer.id = &"archer"
	archer.display_name = "Archer"
	archer.training_time_hours = 6.0
	archer.combat_power = 6
	archer.suspicion_on_train = 4
	defs.append(archer)
	return defs


## Full stack (suspicion LAST per §14 registration order) with a timber
## stipend so the bootstrap can build the farm. `follower_weight` sets the
## estate's away-window loudness (0 = pure-decay quiet estate).
func _stack(interval_hours := 1.0, follower_weight := 0.0) -> SimEngine:
	var tunables := _tunables(interval_hours, follower_weight)
	var buildings: Array[BuildingDef] = [_farm()]
	var stipend: Dictionary = {&"timber": 60}
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new([_regime()], _identity(), null, stipend))
	engine.register_system(UnitLifecycleSystem.new(_unit_defs(), [], tunables))
	engine.register_system(ProductionSystem.new(buildings, tunables, null))
	engine.register_system(SuspicionSystem.new(tunables, _unit_defs()))
	return engine


## A short deterministic playing session (identical on twins): start + grant,
## then four managed chunks — accept everyone to worker, staff the farm,
## upgrade when affordable.
func _play(engine: SimEngine) -> void:
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	for i in 4:
		var units := engine.get_system(&"units") as UnitLifecycleSystem
		var production := engine.get_system(&"production") as ProductionSystem
		for uid in units.offer_ids():
			engine.submit_command(&"recruit_accept", &"", uid)
		for uid in units.idle_units(&"peasant"):
			engine.submit_command(&"assign_role", &"worker", uid)
		var free: int = production.worker_slots(&"farm") - production.assigned_workers(&"farm")
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", &"farm", mini(free, production.idle_workers()))
		engine.submit_command(&"upgrade_building", &"farm", 0)
		engine.fast_forward(120)


func _meta_of(engine: SimEngine) -> RunMeta:
	return (engine.get_system(&"run") as RunLifecycleSystem).meta


# --- 1. Behavior: the clock-cheat envelope -------------------------------------


func test_clamp_envelope_holds_under_adversarial_elapsed() -> void:
	# The envelope claim (security-policy.md §1.2): for EVERY representable
	# elapsed — including int64 extremes and the widest overflow-safe gap —
	# applied ticks are in [0, cap/60]. Nothing a clock can say yields more
	# than one capped window.
	var cap := CAP_SECONDS
	var adversarial: Array[int] = [
		0,
		-1,
		59,
		60,
		cap - 1,
		cap,
		cap + 1,
		cap + 3600,
		100 * 365 * 86400,  # 100 years forward
		-(100 * 365 * 86400),  # 100 years backward
		1 << 40,
		1 << 41,
		1 << 62,
		9223372036854775807,  # int64 max
		-9223372036854775807 - 1,  # int64 min
		-(1 << 62),
	]
	for elapsed in adversarial:
		var ticks := CatchUpService.applied_ticks_for(elapsed, cap)
		if ticks < 0 or ticks > cap / SimEngine.TICK_SECONDS:
			assert_bool(false).is_true()  # envelope broken at elapsed=%d (see values)
			return
		assert_int(ticks).is_less_equal(CAP_TICKS)
	# Degenerate caps are defensively empty windows, never negative ones.
	assert_int(CatchUpService.applied_ticks_for((1 << 62), 0)).is_equal(0)
	assert_int(CatchUpService.applied_ticks_for((1 << 62), -100)).is_equal(0)
	# The widest composed gap int64 operands can produce (±2^40 clamped) is
	# exactly 2^41 — and the composed rule still lands on the cap, never
	# wraps, never exceeds it.
	var extreme := 1 << 62
	assert_int(CatchUpService.elapsed_between(-extreme, extreme)).is_equal(1 << 41)
	assert_int(
		CatchUpService.applied_ticks_for(
			CatchUpService.elapsed_between(-extreme, extreme), cap
		)
	).is_equal(CAP_TICKS)
	assert_int(
		CatchUpService.applied_ticks_for(
			CatchUpService.elapsed_between(extreme, -extreme), cap
		)
	).is_equal(0)


func test_cheating_envelope_bounded_per_away_window() -> void:
	# Six full manipulation cycles on a REAL engine (quiet estate): each
	# forward jump of 100 years awards EXACTLY one capped window (480 ticks);
	# each rewind of 1 year awards nothing, changes nothing (hash-identical),
	# and the anchor follows the injected timestamp everywhere. Total accrual
	# is exactly cycles x cap — linear in effort, no carry, no compounding.
	var engine := _stack()
	var meta := _meta_of(engine)
	_play(engine)
	var service := CatchUpService.new(_tunables())
	var ticks_before := engine.tick_count

	var now := T0
	for cycle in 6:
		service.mark_seen(meta, now)
		# Forward cheat: a century of "away" is one capped window.
		now += 100 * 365 * 86400
		var cheat := service.apply(engine, meta, now)
		if int(cheat["applied_ticks"]) != CAP_TICKS or not bool(cheat["capped"]):
			assert_bool(false).is_true()  # forward cycle not exactly one capped window
			return
		# Rewind cheat: nothing accrues, nothing is lost, anchor follows.
		var hash_after_window := engine.state_hash()
		var food_after_window := engine.get_resource(&"food")
		now -= 365 * 86400
		var rewind := service.apply(engine, meta, now)
		if int(rewind["applied_ticks"]) != 0 or not bool(rewind["rewound"]):
			assert_bool(false).is_true()  # rewind cycle accrued or went unflagged
			return
		if engine.state_hash() != hash_after_window or engine.get_resource(&"food") != food_after_window:
			assert_bool(false).is_true()  # rewind changed state — no-loss policy broken
			return
		if meta.last_seen_epoch != now:
			assert_bool(false).is_true()  # anchor did not follow the injected timestamp
			return

	# Exactly six capped windows' worth of ticks exist; nothing compounding.
	assert_int(engine.tick_count - ticks_before).is_equal(6 * CAP_TICKS)


func test_away_window_suspicion_is_engine_ruled_exact() -> void:
	# Quiet estate: the capped away window's ONLY meter movement is passive
	# decay at the sim rate (-5/h), exactly — away time cannot skip, freeze,
	# or inflate the suspicion curve. (Sim-time decay, security-policy.md
	# §1.1 row 4, proven behaviorally here.)
	var engine := _stack(100000.0)  # no arrivals inside any horizon
	var meta := _meta_of(engine)
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	heat.set_suspicion(50)

	var service := CatchUpService.new(_tunables(100000.0))
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 30 * 86400)  # a month "away"

	assert_bool(report["capped"]).is_true()
	assert_int(report["applied_ticks"]).is_equal(CAP_TICKS)
	assert_int(report["suspicion_before"]).is_equal(50)
	assert_int(report["suspicion_delta"]).is_equal(-40)  # -5/h x 8h, exactly
	assert_int(heat.suspicion).is_equal(10)


func test_repeated_capped_windows_raise_suspicion_loud_estate() -> void:
	# The "louder, not richer" claim (§1.2): on an estate whose followers
	# outweigh decay, repeated capped cheat windows push the meter UP by the
	# SAME rules live play uses — twin parity against a live-ticked engine.
	var engine := _stack(1.0, 1.0)
	var meta := _meta_of(engine)
	_play(engine)
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	heat.set_suspicion(30)  # below warn; the window's rise is presence-driven

	# The live twin: same construction, same session, 480 LIVE ticks.
	var twin := _stack(1.0, 1.0)
	_play(twin)
	var twin_heat := twin.get_system(&"suspicion") as SuspicionSystem
	twin_heat.set_suspicion(30)
	for i in CAP_TICKS:
		twin.tick()

	var service := CatchUpService.new(_tunables(1.0, 1.0))
	service.mark_seen(meta, T0)
	var report := service.apply(engine, meta, T0 + 100 * 365 * 86400)

	assert_int(report["applied_ticks"]).is_equal(CAP_TICKS)
	assert_int(report["suspicion_delta"]).is_greater(0)  # the estate got LOUDER
	assert_int(heat.suspicion).is_equal(twin_heat.suspicion)  # engine-ruled: == live


# --- 2. Structural scan: the wall-clock inventory (§1.1) -----------------------


func test_suspicion_system_reads_no_wall_clock() -> void:
	# Suspicion decay is SIM-TIME ONLY (§1.1 row 4): the system measures
	# everything in ticks via engine.tick_count — a wall-clock read anywhere
	# in the file would make the meter platform-clock-dependent and break the
	# determinism rules. Comment-stripped: doc comments stay free.
	var pred := func(line: String, _path: String) -> bool:
		return (
			line.contains("Time.")
			or line.contains("OS.get_system_time")
			or line.contains("OS.get_ticks")
		)
	var hits := _scan_lines("res://sim/systems/suspicion_system.gd", pred)
	assert_str(",".join(hits)).is_equal("")  # expected zero clock reads; got: (list)


func test_sim_tree_wall_clock_reads_are_the_documented_set() -> void:
	# The complete wall-clock surface of sim/ is EXACTLY one line: the
	# write-only UTC `saved_at_unix` stamp in save_manager.gd (§1.1 row 5,
	# the gdscript-conventions determinism rule). Any other Time./OS.-clock
	# read in sim/ fails here with the file:line.
	var pred := func(line: String, path: String) -> bool:
		var is_clock: bool = (
			line.contains("Time.")
			or line.contains("OS.get_system_time")
			or line.contains("OS.get_ticks")
		)
		if not is_clock:
			return false
		# The single allowlisted read: the UTC debug stamp write.
		return not (
			path == "res://sim/save_manager.gd"
			and line.contains("saved_at_unix")
			and line.contains("get_unix_time_from_system")
		)
	var hits := _scan_tree("res://sim", pred)
	assert_str(",".join(hits)).is_equal("")  # undocumented wall-clock read(s): (list)


func test_save_stamp_is_write_only() -> void:
	# `saved_at_unix` is never READ BACK (§1.1 row 5): the token may appear
	# in exactly ONE comment-stripped line of game code — the envelope write
	# in save_manager.gd. A second occurrence anywhere is a read (or a second
	# stamp), and fails with the file:line.
	var outside_write := func(_line: String, path: String) -> bool:
		return path != "res://sim/save_manager.gd" and _line.contains("saved_at_unix")
	var hits := _scan_trees(SCAN_ROOTS, outside_write)
	assert_str(",".join(hits)).is_equal("")  # save stamp read outside its write: (list)
	var at_write := func(line: String, path: String) -> bool:
		return path == "res://sim/save_manager.gd" and line.contains("saved_at_unix")
	var writes := _scan_tree("res://sim", at_write)
	assert_str(",".join(writes)).contains("get_unix_time_from_system")  # the one use is the UTC write


# --- 3. Network tripwire (§2) ----------------------------------------------------


func test_zero_network_apis_in_game_code() -> void:
	# No network APIs, no process escapes, no telemetry vocabulary anywhere
	# in the game trees (§2: "no network calls of any kind"). This is the
	# CI-wired form of the privacy claim — future creep fails HERE first,
	# with the offending file:line, before it ships.
	var pred := func(line: String, _path: String) -> bool:
		for token in BANNED_NETWORK_TOKENS:
			if line.contains(token):
				return true
		var lower := line.to_lower()
		for word in BANNED_TELEMETRY_WORDS:
			if lower.contains(word):
				return true
		return false
	var banned := _scan_trees(SCAN_ROOTS, pred)
	assert_str(",".join(banned)).is_equal("")  # network/telemetry creep: (list)

	# Non-vacuity: the scan must have seen the real codebase. A path typo or
	# a renamed directory would otherwise pass every zero-hits assertion
	# above without looking at a single file.
	var files := _collect_gd_files(SCAN_ROOTS)
	assert_int(files.size()).is_greater_equal(20)
	var present := {}
	for path in files:
		present[path] = true
	var missing: Array[String] = []
	for anchor in ANCHOR_FILES:
		if not present.has(anchor):
			missing.append(anchor)
	assert_str(",".join(missing)).is_equal("")  # scan scope broken: (missing anchors)


# --- Tampering stance (§3) -------------------------------------------------------


func test_tampering_stance_checksig_refuses_recompute_loads_future_refuses() -> void:
	# The §3 distinction, executed: (A) an edit WITHOUT recomputing the
	# checksum is treated as corruption — refused loudly, quarantined;
	# (B) an edit WITH a consistent envelope loads and plays — editing your
	# own single-player save is your prerogative, not our battle; (C) a
	# future schema version is refused loudly (protects the player's data
	# from our code, never silently mis-parsed).
	_dir_seq += 1
	var scratch := "user://cs_security_policy_%d" % _dir_seq
	var manager := SaveManager.new(scratch)
	var engine := _stack()
	_play(engine)
	engine.set_resource(&"food", 123)
	assert_bool(manager.save_run(engine)).is_true()
	var path := manager.run_slot_path(0)
	var envelope: Dictionary = _parse_json(path)

	# (A) accidental corruption / lazy edit: checksum mismatch -> refuse.
	envelope["payload"]["resources"]["food"] = 999999
	assert_bool(_write_json(path, envelope)).is_true()
	var tampered_engine := _stack()
	var strict := SaveManager.new(scratch)
	assert_bool(strict.load_run(tampered_engine)).is_false()
	assert_str(strict.last_error).contains("checksum")
	assert_int(tampered_engine.get_resource(&"food")).is_equal(0)  # nothing half-applied

	# (B) deliberate edit with a consistent envelope: loads. Player's game.
	_dir_seq += 1
	var scratch_b := "user://cs_security_policy_%d" % _dir_seq
	var manager_b := SaveManager.new(scratch_b)
	assert_bool(manager_b.save_run(engine)).is_true()
	var path_b := manager_b.run_slot_path(0)
	var envelope_b: Dictionary = _parse_json(path_b)
	envelope_b["payload"]["resources"]["food"] = 999999
	envelope_b["checksum"] = SaveManager.payload_checksum(envelope_b["payload"])
	assert_bool(_write_json(path_b, envelope_b)).is_true()
	var consenting := _stack()
	assert_bool(manager_b.load_run(consenting)).is_true()
	assert_int(consenting.get_resource(&"food")).is_equal(999999)  # stance, not oversight

	# (C) future version: refused loudly, never silently mis-parsed.
	_dir_seq += 1
	var scratch_c := "user://cs_security_policy_%d" % _dir_seq
	var manager_c := SaveManager.new(scratch_c)
	assert_bool(manager_c.save_run(engine)).is_true()
	var path_c := manager_c.run_slot_path(0)
	var envelope_c: Dictionary = _parse_json(path_c)
	envelope_c["schema_version"] = 99  # from a newer game build
	assert_bool(_write_json(path_c, envelope_c)).is_true()
	var from_future := _stack()
	assert_bool(manager_c.load_run(from_future)).is_false()
	assert_str(manager_c.last_error).contains("newer")

	_erase_dir(scratch)
	_erase_dir(scratch_b)
	_erase_dir(scratch_c)


# --- Scan helpers -----------------------------------------------------------------
#
# All matching runs against COMMENT-STRIPPED code (everything after the
# first '#' on a line) so documentation comments never trip the wires —
# these are creep tripwires, not sandboxes.


func _strip_comment(line: String) -> String:
	var cut := line.find("#")
	return line if cut < 0 else line.substr(0, cut)


## Collects every .gd file under `roots` (recursive; hidden dirs skipped).
func _collect_gd_files(roots: Array[String]) -> Array[String]:
	var files: Array[String] = []
	for root in roots:
		_walk(root, files)
	files.sort()
	return files


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := dir_path + "/" + entry
		if entry.begins_with("."):
			pass  # hidden/engine-internal dirs (.godot) are not game code
		elif dir.current_is_dir():
			_walk(child, out)
		elif entry.get_extension() == "gd":
			out.append(child)
		entry = dir.get_next()
	dir.list_dir_end()


## Runs `predicate(stripped_line, path)` over one file; returns offending
## "path:line-no: stripped line" strings.
func _scan_lines(path: String, predicate: Callable) -> Array[String]:
	var hits: Array[String] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["%s:<unreadable>" % path]
	var line_no := 0
	while not file.eof_reached():
		var raw := file.get_line()
		line_no += 1
		var stripped := _strip_comment(raw)
		if bool(predicate.call(stripped, path)):
			hits.append("%s:%d: %s" % [path, line_no, stripped.strip_edges()])
	file.close()
	return hits


func _scan_tree(root: String, predicate: Callable) -> Array[String]:
	var roots: Array[String] = [root]
	return _scan_trees(roots, predicate)


func _scan_trees(roots: Array[String], predicate: Callable) -> Array[String]:
	var hits: Array[String] = []
	for path in _collect_gd_files(roots):
		hits.append_array(_scan_lines(path, predicate))
	return hits


# --- Disk helpers -----------------------------------------------------------------


func _parse_json(path: String) -> Dictionary:
	var text := FileAccess.open(path, FileAccess.READ).get_as_text()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	return true


func _erase_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not dir.current_is_dir():
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for file_name in files:
		dir.remove(file_name)
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
