## Acceptance suite (T-QA-03) — the definitive zero-corruption proof, on the
## FULL canonical stack (`_full_stack.gd`: five gameplay systems + heartbeat,
## suspicion LAST, assault resolver stateless) with the catch-up anchor live.
## Three acts:
##
## ACT 1 — MILESTONE ROUND-TRIPS (save -> "process restart" -> lockstep).
## One deterministic honest session (pack stipend, zero test seams) crosses
## the disk boundary at SIX milestones — 10h, mid-training, mid-telegraph,
## post-crackdown, pre-assault, 250h — each through the full process shape
## (fresh SaveManager + fresh engine + loaded meta handed back to the run
## system, the documented host contract), asserting state_hash + 64-bit rng
## exactness, the milestone's SIGNATURE state (in-flight training countdown,
## armed telegraph land tick, live relief window, assault odds at the floor),
## and +N hours lockstep against the never-saved twin — including a lockstep
## that carries an armed telegraph THROUGH its landing tick and a pre-assault
## commit whose verdict lands identically on both timelines. The meta domain
## rides every restart: the chronicle GROWS across them, the catch-up anchor
## round-trips, and the final continuation is a REAL catch-up foreground
## window (CatchUpService on the restored engine) held to twin parity.
##
## ACT 2 — MIGRATION DRILL (a REAL simulated format bump on the deep 250h
## bytes). The on-disk envelope is surgically rewritten into an OLD shape —
## payload field renamed backward (`rng_state` -> `rng_stream`, run domain;
## `legacy_points` -> `points`, meta domain) with the checksum HONESTLY
## recomputed over the altered payload — then a schema-v2 manager with a
## registered v1->v2 rename migration loads it: the registry walks, the
## field lands where this build's reader expects it, and the restored hash
## equals the pre-migration save (hash equality is the proof the migration
## ran — the un-migrated old shape cannot restore this engine's rng stream).
## Plus the refusal paths: an unknown FUTURE schema version is quarantined
## loudly (lone slot => no false success; newest of a ring => fallback to the
## prior good generation, bytes preserved).
##
## ACT 3 — KILL-DURING-SAVE CHAOS (the crown jewel). A bounded interleaved
## loop on a second full-stack session: save every cycle while a rogue step
## corrupts the NEWEST file mid-sequence (truncation / garbage / empty /
## double truncation / future-version) and periodic crash-simulated saves die
## mid-temp-write. After EVERY rogue action the next "process" must load SOME
## good slot — the loaded hash always one of the recorded generations, every
## quarantine preserving the exact corrupted bytes, the ring NEVER advancing
## on a failed save, orphan temps always swept, the meta domain never touched.
extends RefCounted

const HOST := preload("res://tests/acceptance/suites/_full_stack.gd")
const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const BASE_SEED := 20261101
const CHAOS_SEED := 20261102

const ROOT := "user://cs_qa03_saves"
const MIGRATE_ROOT := "user://cs_qa03_migrate"
const REFUSE_ROOT := "user://cs_qa03_refuse"
const CHAOS_ROOT := "user://cs_qa03_chaos"

# Injected UTC epochs for the catch-up anchor (determinism: the engine never
# sees wall time; the host injects timestamps per docs/catch-up.md).
const EPOCH_A := 1_750_000_000
const EPOCH_C := EPOCH_A + 86_400
const CATCHUP_SECONDS := 5 * 3600  # the final continuation window: 5h

const BATCH_TICKS := 120  # one management batch per 2h sim time
const BUDGET_SECONDS := 60.0

# Loud-phase profiles for the suspicion milestones (military cap, population
# cap) — tried in order until one arms a telegraph that LANDS (not cancelled,
# not a pre-land crush). Deterministic per seed; the ladder just removes
# seed-luck from the narrative.
const LOUD_PROFILES: Array[Vector2i] = [
	Vector2i(6, 24),
	Vector2i(3, 16),
	Vector2i(2, 12),
	Vector2i(1, 8),
]

# Chaos loop shape: every cycle saves (every 5th dies mid-write), every cycle
# takes one rogue action (rotating variant), every cycle must still load.
const CHAOS_CYCLES := 120
const CHAOS_PRIME_HOURS := 39  # three priming generations, ~13h apart


func suite_name() -> String:
	return "save_integrity_full"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	for root in [ROOT, MIGRATE_ROOT, REFUSE_ROOT, CHAOS_ROOT]:
		_erase_dir(root)

	var report := {}
	_act1_milestones(harness, report)
	_act2_migration(harness, report)
	_act3_chaos(harness, report)

	for root in [ROOT, MIGRATE_ROOT, REFUSE_ROOT, CHAOS_ROOT]:
		_erase_dir(root)

	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	print(
		"[save_integrity_full] done: milestones %s; telegraph armed at %s; chronicle %s; migration %s; chaos %d cycles / %d good loads / %d quarantines; %.2fs"
		% [
			str(report.get("milestones", [])),
			str(report.get("armed_at", -1)),
			str(report.get("chronicle", [])),
			str(report.get("migration", "")),
			CHAOS_CYCLES, int(report.get("chaos_good_loads", 0)),
			int(report.get("chaos_quarantines", 0)), wall,
		]
	)
	harness.check(wall < BUDGET_SECONDS, "suite in < %.0fs (took %.2fs)" % [BUDGET_SECONDS, wall])


# --- ACT 1: milestone round-trips on the canonical host -----------------------
#
# The narrative: honest boot -> 10h estate -> first knight chain in flight ->
# loud phase arms a telegraph (saved mid-countdown, lockstep carries it
# THROUGH the landing) -> post-strike relief window -> rebuild to the knight
# floor (odds snapshotted, commit resolves identically on both timelines) ->
# honest run close + restart -> 250h total, final continuation via a REAL
# catch-up foreground window on the restored engine.


func _act1_milestones(harness, report: Dictionary) -> void:
	var session: Variant = HOST.session(BASE_SEED)
	var engine: SimEngine = session.engine
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	var tail := Tail.new()
	var hashes := {}  # milestone label -> state_hash at that save
	var chronicle_counts := {}  # milestone label -> meta chronicle size

	# Boot: run + honest pack stipend.
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)
	tail.drain(engine.events)

	# --- Milestone 1: 10h — the early estate (economy + arrivals warmed up).
	while engine.tick_count < 10 * SimEngine.TICKS_PER_SIM_HOUR:
		HOST.manage(engine, 4, {})
		engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		tail.drain(engine.events)
	session.mark_seen(EPOCH_A)
	var probe := _cross(harness, ROOT, engine, session.meta, BASE_SEED, "10h", report)
	hashes["10h"] = engine.state_hash()
	chronicle_counts["10h"] = (probe["meta"] as RunMeta).chronicle.size()
	harness.check((probe["meta"] as RunMeta).last_seen_epoch == EPOCH_A,
		"10h: catch-up anchor round-tripped through the meta domain (%d)" % EPOCH_A)
	harness.check((probe["engine"].get_system(&"run") as RunLifecycleSystem).leader_name() == run.leader_name(),
		"10h: leader identity restored (%s)" % run.leader_name())
	_lockstep(harness, engine, probe["engine"], 2 * SimEngine.TICKS_PER_SIM_HOUR, "10h: +2h")

	# --- Milestone 2: mid-training — a training timer captured mid-countdown.
	# Hunt deterministically: the pipeline moves in hours, so step until a
	# timer is actually in flight (trainings complete; new ones start).
	var trainee := _in_flight_training(units)
	var hunt := 0
	while trainee["uid"] == 0 and hunt < 24:
		HOST.manage(engine, 4, {})
		engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		tail.drain(engine.events)
		trainee = _in_flight_training(units)
		hunt += 1
	harness.check(trainee["uid"] > 0, "mid-training: found an in-flight timer (uid %d -> %s, %d/%d milli)"
		% [trainee["uid"], trainee["target"], trainee["progress"], trainee["duration"]])
	probe = _cross(harness, ROOT, engine, session.meta, BASE_SEED, "mid-training", report)
	hashes["mid-training"] = engine.state_hash()
	chronicle_counts["mid-training"] = (probe["meta"] as RunMeta).chronicle.size()
	var probe_units := (probe["engine"].get_system(&"units") as UnitLifecycleSystem)
	harness.check(probe_units.training_target(trainee["uid"]) == trainee["target"]
		and probe_units.training_progress_milli(trainee["uid"]) == trainee["progress"],
		"mid-training: the SAME timer restored mid-countdown (uid %d, %d milli elapsed)" % [trainee["uid"], trainee["progress"]])
	_lockstep(harness, engine, probe["engine"], SimEngine.TICKS_PER_SIM_HOUR, "mid-training: +1h (timer keeps counting identically)")

	# --- Milestone 3 + 4: mid-telegraph, then post-crackdown. Loud phase
	# drives the meter honestly; the save happens with the countdown ARMED and
	# the lockstep runs to land_tick + 30 so the strike (or its deterministic
	# alternative) happens INSIDE the continuation on both timelines.
	var struck := false
	for profile: Vector2i in LOUD_PROFILES:
		if not run.is_running():
			engine.submit_command(&"run_restart", &"", 0)
			engine.fast_forward(1)
			tail.drain(engine.events)
		if not _drive_to_telegraph(harness, engine, tail, profile.x, profile.y):
			continue  # run was crushed before arming: retry quieter
		var land_tick: int = heat.crackdown_land_tick
		var meter_at_save: int = heat.suspicion_points()
		harness.check(land_tick > engine.tick_count, "mid-telegraph: countdown in flight (lands %d, %d ticks out)" % [land_tick, land_tick - engine.tick_count])
		probe = _cross(harness, ROOT, engine, session.meta, BASE_SEED, "mid-telegraph", report)
		hashes["mid-telegraph"] = engine.state_hash()
		chronicle_counts["mid-telegraph"] = (probe["meta"] as RunMeta).chronicle.size()
		var probe_heat := (probe["engine"].get_system(&"suspicion") as SuspicionSystem)
		harness.check(probe_heat.crackdown_land_tick == land_tick and probe_heat.suspicion_points() == meter_at_save,
			"mid-telegraph: land tick + meter restored exactly (%d / %d)" % [probe_heat.crackdown_land_tick, probe_heat.suspicion_points()])
		# Lockstep THROUGH the landing tick: whatever the meter does next
		# happens identically on both timelines.
		_lockstep(harness, engine, probe["engine"], land_tick - engine.tick_count + 30,
			"mid-telegraph: lockstep through the landing tick")
		struck = heat.crackdowns_total > 0
		harness.check(probe_heat.crackdowns_total == heat.crackdowns_total,
			"mid-telegraph: the telegraph resolved IDENTICALLY on both timelines (strikes %d)" % heat.crackdowns_total)
		report["armed_at"] = meter_at_save
		break
	harness.check(struck, "loud phase landed a real crackdown (relief window live)")
	if not run.is_running():
		# every ladder attempt was crushed before arming: fold a fresh run so
		# the remaining milestones still exercise a live estate
		engine.submit_command(&"run_restart", &"", 0)
		engine.fast_forward(1)
		tail.drain(engine.events)

	if struck:
		# --- Milestone 4: post-crackdown — saved inside the relief window.
		harness.check(heat.relief_until_tick > engine.tick_count,
			"post-crackdown: relief window live at save (until tick %d, meter %d)" % [heat.relief_until_tick, heat.suspicion_points()])
		probe = _cross(harness, ROOT, engine, session.meta, BASE_SEED, "post-crackdown", report)
		hashes["post-crackdown"] = engine.state_hash()
		chronicle_counts["post-crackdown"] = (probe["meta"] as RunMeta).chronicle.size()
		var relief_probe := (probe["engine"].get_system(&"suspicion") as SuspicionSystem)
		harness.check(relief_probe.relief_until_tick == heat.relief_until_tick,
			"post-crackdown: relief window restored exactly (until %d)" % relief_probe.relief_until_tick)
		_lockstep(harness, engine, probe["engine"], 2 * SimEngine.TICKS_PER_SIM_HOUR, "post-crackdown: +2h")

	# --- Milestone 5: pre-assault — army at the floor, odds on screen, the
	# commit resolves identically through the disk boundary.
	var resolver := engine.get_system(&"assault") as AssaultResolver
	var batches := 0
	while not resolver.floor_met(engine) and batches < 360:
		HOST.manage(engine, 12, {&"population_cap": 30, &"laying_low": heat.suspicion_points() >= 70})
		engine.fast_forward(BATCH_TICKS)
		tail.drain(engine.events)
		batches += 1
	harness.check(resolver.floor_met(engine), "pre-assault: army reached the knight floor honestly (power %d)" % units.army_power())
	var odds_permille: int = int(resolver.assault_odds(engine)["win_permille"])
	probe = _cross(harness, ROOT, engine, session.meta, BASE_SEED, "pre-assault", report)
	hashes["pre-assault"] = engine.state_hash()
	chronicle_counts["pre-assault"] = (probe["meta"] as RunMeta).chronicle.size()
	var probe_resolver := (probe["engine"].get_system(&"assault") as AssaultResolver)
	harness.check(probe_resolver.floor_met(probe["engine"])
		and int(probe_resolver.assault_odds(probe["engine"])["win_permille"]) == odds_permille,
		"pre-assault: floor + odds restored identically (%d permille)" % odds_permille)
	# The commit: same rng state on both timelines => same verdict, same
	# aftermath, same banking.
	engine.submit_command(&"commit_assault", &"", 0)
	probe["engine"].submit_command(&"commit_assault", &"", 0)
	engine.fast_forward(1)
	probe["engine"].fast_forward(1)
	tail.drain(engine.events)
	var verdict: StringName = tail.last(&"assault_won").get("type", tail.last(&"assault_lost").get("type", &""))
	var probe_verdict: StringName = _last_event_of(probe["engine"].events, &"assault_won").get("t", _last_event_of(probe["engine"].events, &"assault_lost").get("t", &""))
	harness.check(String(probe_verdict) == String(verdict) and String(verdict) != "",
		"pre-assault: the commit produced the SAME verdict on both timelines (%s)" % String(verdict))
	harness.check((probe["engine"].get_system(&"run") as RunLifecycleSystem).is_running() == run.is_running(),
		"pre-assault: run liveness identical after the commit (running %s)" % str(run.is_running()))
	_lockstep(harness, engine, probe["engine"], 2 * SimEngine.TICKS_PER_SIM_HOUR, "pre-assault: +2h past the commit")

	# --- Honest run close (chronicle growth across restarts needs a recorded
	# ending): bounded re-commit attempts, then the documented defeat entry
	# point (used by the marathon suites) if the die rolls keep refusing.
	var attempts := 0
	while run.is_running() and attempts < 2:
		var rebuild := 0
		while run.is_running() and not resolver.floor_met(engine) and rebuild < 120:
			HOST.manage(engine, 12, {&"population_cap": 30, &"laying_low": heat.suspicion_points() >= 70})
			engine.fast_forward(BATCH_TICKS)
			tail.drain(engine.events)
			rebuild += 1
		if not run.is_running():
			break
		engine.submit_command(&"commit_assault", &"", 0)
		engine.fast_forward(1)
		tail.drain(engine.events)
		attempts += 1
	if run.is_running():
		run.resolve_victory(engine, false)  # honest defeat: banks full progress
		engine.fast_forward(1)
		tail.drain(engine.events)
	engine.submit_command(&"run_restart", &"", 0)
	engine.fast_forward(1)
	tail.drain(engine.events)

	# --- Milestone 6: 250h — deep history; continuation via a REAL catch-up
	# foreground window on the restored engine (twin parity through the
	# anchor, docs/catch-up.md).
	while engine.tick_count < 250 * SimEngine.TICKS_PER_SIM_HOUR:
		HOST.manage(engine, 6, {&"population_cap": 30})
		engine.fast_forward(BATCH_TICKS)
		tail.drain(engine.events)
	session.mark_seen(EPOCH_C)
	probe = _cross(harness, ROOT, engine, session.meta, BASE_SEED, "250h", report)
	hashes["250h"] = engine.state_hash()
	chronicle_counts["250h"] = (probe["meta"] as RunMeta).chronicle.size()
	harness.check(engine.tick_count >= 250 * SimEngine.TICKS_PER_SIM_HOUR, "250h milestone reached (%d ticks)" % engine.tick_count)
	harness.check((probe["meta"] as RunMeta).chronicle.size() > chronicle_counts["10h"],
		"meta: chronicle GREW across the restarts (%d -> %d entries)" % [chronicle_counts["10h"], (probe["meta"] as RunMeta).chronicle.size()])
	harness.check((probe["meta"] as RunMeta).last_seen_epoch == EPOCH_C,
		"250h: anchor refreshed by mark_seen round-tripped (%d)" % EPOCH_C)
	# The catch-up continuation: the restored engine resolves a 5h away window
	# through the REAL service; the never-saved twin just fast-forwards the
	# same 300 ticks — identical landings, identical hash.
	var catch_up := CatchUpService.new(MVP.load_mvp().tunables)
	var window := catch_up.apply(probe["engine"], probe["meta"], EPOCH_C + CATCHUP_SECONDS)
	engine.fast_forward(int(window["applied_ticks"]))
	harness.check(int(window["applied_ticks"]) == CATCHUP_SECONDS / SimEngine.TICK_SECONDS,
		"250h continuation: catch-up applied exactly %d ticks (5h, uncapped)" % int(window["applied_ticks"]))
	harness.check(probe["engine"].state_hash() == engine.state_hash(),
		"250h continuation: REAL catch-up window == twin fast-forward (hash %d)" % engine.state_hash())
	harness.check((probe["meta"] as RunMeta).last_seen_epoch == EPOCH_C + CATCHUP_SECONDS,
		"250h continuation: the anchor snapped to the foreground timestamp")

	report["milestones"] = hashes.keys()
	report["chronicle"] = [chronicle_counts["10h"], chronicle_counts["250h"]]
	report["hashes"] = hashes
	report["root"] = ROOT


## Saves both domains, then loads them through a FRESH manager + FRESH engine
## + loaded meta re-pointed into the run system — the process-restart shape.
## Asserts the core identity (hash, rng, meta canonical) and returns the probe
## {"engine", "manager", "run", "meta", "ok"}.
func _cross(harness, root: String, engine: SimEngine, meta: RunMeta, seed: int, label: String, report: Dictionary) -> Dictionary:
	var hash_at_save := engine.state_hash()
	var rng_at_save := engine.rng.state
	var saver := SaveManager.new(root)
	var saved_run := saver.save_run(engine)
	var saved_meta := saver.save_meta(meta)
	var manager := SaveManager.new(root)
	var probe_engine := HOST.game_stack(seed, RunMeta.new(), {})
	var loaded_run := manager.load_run(probe_engine)
	var loaded_meta := manager.load_meta()
	(probe_engine.get_system(&"run") as RunLifecycleSystem).meta = loaded_meta
	harness.check(saved_run and loaded_run, "%s: save_run -> fresh process load_run" % label)
	harness.check(saved_meta, "%s: save_meta (bank %d lp, chronicle %d)" % [label, meta.legacy_points, meta.chronicle.size()])
	harness.check(probe_engine.state_hash() == hash_at_save, "%s: state_hash identical across the boundary (%d)" % [label, hash_at_save])
	harness.check(probe_engine.rng.state == rng_at_save, "%s: 64-bit rng bit-exact (%d)" % [label, rng_at_save])
	harness.check(SaveManager.canonical_form(loaded_meta.to_dict()) == SaveManager.canonical_form(meta.to_dict()),
		"%s: meta domain round-tripped (chronicle %d, anchor %d)" % [label, loaded_meta.chronicle.size(), loaded_meta.last_seen_epoch])
	return {"engine": probe_engine, "manager": manager, "run": probe_engine.get_system(&"run"), "meta": loaded_meta, "ok": loaded_run}


func _lockstep(harness, engine: SimEngine, probe_engine: SimEngine, ticks: int, label: String) -> void:
	engine.fast_forward(ticks)
	probe_engine.fast_forward(ticks)
	harness.check(probe_engine.state_hash() == engine.state_hash() and probe_engine.tick_count == engine.tick_count,
		"%s: lockstep vs never-saved twin (hash %d)" % [label, engine.state_hash()])


## Loud phase: acts + presence push the meter; 1-tick stepping near the
## threshold so the arm event can never be stepped over. Returns true when a
## telegraph is armed with its countdown in flight. False => the run was
## crushed before arming (caller restarts + retries quieter).
func _drive_to_telegraph(harness, engine: SimEngine, tail: Tail, military_cap: int, population_cap: int) -> bool:
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	var run := engine.get_system(&"run") as RunLifecycleSystem
	var steps := 0
	while steps < 4320:  # bounded: <= 72h of loud play
		if heat.crackdown_land_tick > engine.tick_count:
			return true
		if not run.is_running():
			return false  # crushed before arming
		if heat.suspicion_points() >= 65:
			engine.fast_forward(1)  # cannot step over the arm event
		else:
			HOST.manage(engine, military_cap, {&"population_cap": population_cap})
			engine.fast_forward(30)
		tail.drain(engine.events)
		steps += 1
	return false


func _in_flight_training(units: UnitLifecycleSystem) -> Dictionary:
	for uid in units.unit_ids():
		var target := units.training_target(uid)
		if target != &"" and units.training_progress_milli(uid) < units.training_duration_milli(target):
			return {
				"uid": uid,
				"target": target,
				"progress": units.training_progress_milli(uid),
				"duration": units.training_duration_milli(target),
			}
	return {"uid": 0, "target": &"", "progress": 0, "duration": 0}


# --- ACT 2: migration drill + future-version refusal ----------------------------


func _act2_migration(harness, report: Dictionary) -> void:
	var hashes: Dictionary = report["hashes"]
	var root: String = report["root"]

	# The deep bytes: the newest milestone slot (250h) + the meta file.
	var newest := _newest_slot(root)
	harness.check(newest["slot"] >= 0, "migration: found the newest slot (slot %d, seq %d)" % [newest["slot"], newest["seq"]])
	var run_text: String = newest["text"]
	var meta_text := _read_text(root.path_join(SaveManager.META_FILENAME))

	# (1) RUN domain — simulate the OLD format: rename the payload field
	# backward, recompute the checksum honestly, then load through a v2
	# manager whose registered v1->v2 migration renames it forward again.
	var old_run := _rename_payload_field(run_text, "rng_state", "rng_stream")
	old_run = _rechecksum(harness, old_run, "migration(run)")
	DirAccess.make_dir_recursive_absolute(MIGRATE_ROOT)
	_write_text(MIGRATE_ROOT.path_join("run_slot_0.json"), old_run)
	var v2_run := SaveManager.new(MIGRATE_ROOT)
	v2_run.schema_version = 2
	v2_run.migrations = {1: _migrate_rng_stream_to_state}
	var v2_engine := HOST.game_stack(BASE_SEED, RunMeta.new(), {})
	var migrated := v2_run.load_run(v2_engine)
	harness.check(migrated, "migration(run): v1 old-shape file loaded by the v2 build")
	harness.check(v2_engine.state_hash() == hashes["250h"],
		"migration(run): the walk restored the EXACT pre-migration state (hash %d — the rename landed where this build reads it)" % hashes["250h"])

	# (2) META domain — same drill on the bank file.
	var old_meta := _rename_payload_field(meta_text, "legacy_points", "points")
	old_meta = _rechecksum(harness, old_meta, "migration(meta)")
	_write_text(MIGRATE_ROOT.path_join(SaveManager.META_FILENAME), old_meta)
	var v2_meta := SaveManager.new(MIGRATE_ROOT)
	v2_meta.schema_version = 2
	v2_meta.migrations = {1: _migrate_points_to_legacy}
	var migrated_meta := v2_meta.load_meta()
	var source_meta := _parse_text(meta_text)
	harness.check(migrated_meta.legacy_points == int(source_meta["payload"]["legacy_points"]),
		"migration(meta): the bank field landed where this build reads it (%d lp)" % migrated_meta.legacy_points)
	harness.check(migrated_meta.chronicle.size() == (source_meta["payload"]["chronicle"] as Array).size(),
		"migration(meta): chronicle intact through the walk (%d entries)" % migrated_meta.chronicle.size())

	# (3) Unknown FUTURE version — lone slot: loud refusal, no false success.
	DirAccess.make_dir_recursive_absolute(REFUSE_ROOT)
	var future := run_text.replace("\"schema_version\": 1", "\"schema_version\": 99")
	harness.check(run_text.count("\"schema_version\": 1") == 1, "migration: future-version surgery touched exactly one envelope field")
	_write_text(REFUSE_ROOT.path_join("run_slot_0.json"), future)
	var refusing := SaveManager.new(REFUSE_ROOT)
	var refused_engine := HOST.game_stack(BASE_SEED, RunMeta.new(), {})
	harness.check(not refusing.load_run(refused_engine), "future schema 99: load REFUSED (no false success)")
	harness.check(refusing.last_error.contains("newer"), "future schema 99: refusal names the reason (%s)" % refusing.last_error)
	harness.check(_read_text(REFUSE_ROOT.path_join("run_slot_0.json") + SaveManager.QUARANTINE_SUFFIX) == future,
		"future schema 99: bytes quarantined, preserved")

	# (4) Future version as the NEWEST of a ring: quarantine + fallback to the
	# prior good generation (mid-telegraph/post-crackdown-era bytes are still
	# in the ring from the milestone saves).
	var future_ring := int(newest["slot"])
	_write_text(root.path_join("run_slot_%d.json" % future_ring), future)
	var fallback_manager := SaveManager.new(root)
	var fallback_engine := HOST.game_stack(BASE_SEED, RunMeta.new(), {})
	var fell_back := fallback_manager.load_run(fallback_engine)
	var known := {}
	for label in hashes:
		known[hashes[label]] = label
	harness.check(fell_back, "future newest: load fell back to a prior good slot")
	harness.check(known.has(fallback_engine.state_hash()),
		"future newest: fallback hash is a REAL prior generation (%s)" % str(known.get(fallback_engine.state_hash(), "?")))
	harness.check(FileAccess.file_exists(root.path_join("run_slot_%d.json" % future_ring) + SaveManager.QUARANTINE_SUFFIX),
		"future newest: quarantined with bytes preserved")
	report["migration"] = "v1->v2 walk + future refusal OK"


## Registered v1->v2 migration (run domain): renames the old payload field
## forward to where this build's engine reads it. The payload's own
## `format_version` is deliberately UNtouched — the engine state shape is
## unchanged in this drill; only the envelope-era field name moved (the
## stamp-the-payload-version rule applies when the ENGINE shape changes).
func _migrate_rng_stream_to_state(payload: Dictionary) -> Dictionary:
	var upgraded: Dictionary = payload.duplicate(true)
	if upgraded.has("rng_stream"):
		upgraded["rng_state"] = upgraded["rng_stream"]
		upgraded.erase("rng_stream")
	return upgraded


## Registered v1->v2 migration (meta domain): same rename discipline.
func _migrate_points_to_legacy(payload: Dictionary) -> Dictionary:
	var upgraded: Dictionary = payload.duplicate(true)
	if upgraded.has("points"):
		upgraded["legacy_points"] = upgraded["points"]
		upgraded.erase("points")
	return upgraded


## Surgical payload-field rename on the PRETTY envelope text (order-preserving:
## never re-serializes the payload, so insertion-ordered engine state — unit
## gear slots — keeps its order bit-for-bit).
func _rename_payload_field(text: String, from_key: String, to_key: String) -> String:
	var needle := "\"%s\": " % from_key
	return text.replace(needle, "\"%s\": " % to_key)


## Recomputes the envelope checksum over the altered payload and patches it
## into the text (the drill stays honest: a stale checksum would quarantine).
func _rechecksum(harness, text: String, label: String) -> String:
	var envelope := _parse_text(text)
	var stale := String(envelope["checksum"])
	var fresh := SaveManager.payload_checksum(envelope["payload"])
	harness.check(text.count(stale) == 1, "%s: checksum patch touched exactly one field" % label)
	return text.replace(stale, fresh)


# --- ACT 3: kill-during-save chaos ------------------------------------------------
#
# Prime the ring with three good generations, then interleave: every cycle
# advances the world 2h and saves; every 5th save DIES mid-temp-write (the
# killed-process simulation); every cycle a rogue step corrupts the newest
# file (rotating: truncate / garbage / empty / double-truncate / orphan tmp /
# future version — never more slots than present-1). After EVERY rogue action
# the next "process" must load SOME good slot. The zero-corruption invariant,
# machine-checked N times.


## Crash simulation: process killed MID temp write — a truncated .tmp is left
## behind, the final slot path never sees a byte, save_run reports false.
class CrashMidWriteManager extends SaveManager:
	func _write_temp_file(tmp_path: String, text: String) -> bool:
		var file := FileAccess.open(tmp_path, FileAccess.WRITE)
		if file != null:
			file.store_string(text.substr(0, int(text.length() * 0.6)))
			file.flush()
			file.close()
		return false


func _act3_chaos(harness, report: Dictionary) -> void:
	var session: Variant = HOST.session(CHAOS_SEED, MVP.MARATHON_STIPEND)
	var engine: SimEngine = session.engine
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.fast_forward(1)

	# Prime: three good generations 13h apart (the ring needs depth before
	# the rogue starts — one corruption per cycle must never exhaust it).
	# 1h steps so the 13h marks land exactly.
	var known := {}
	var hour := 0
	while hour < CHAOS_PRIME_HOURS:
		HOST.manage(engine, 8, {&"population_cap": 40})
		engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)
		hour += 1
		if hour % 13 == 0:
			var primed: bool = SaveManager.new(CHAOS_ROOT).save_run(engine)
			harness.check(primed, "chaos prime: generation at %dh saved" % hour)
			known[engine.state_hash()] = true
	harness.check(known.size() == 3, "chaos prime: ring holds three good generations")
	var meta_saved: bool = SaveManager.new(CHAOS_ROOT).save_meta(session.meta)
	harness.check(meta_saved, "chaos prime: meta domain saved (bank %d lp)" % session.meta.legacy_points)

	var tally := {"saves": 0, "crash_saves": 0, "truncate": 0, "garbage": 0, "empty": 0,
		"double": 0, "tmp": 0, "future": 0}
	var good_loads := 0
	var quarantines := 0
	var bytes_verified := 0
	for cycle: int in CHAOS_CYCLES:
		# Advance + save (or die mid-write on every 5th cycle).
		HOST.manage(engine, 8, {&"population_cap": 40})
		engine.fast_forward(BATCH_TICKS)
		if cycle % 5 == 4:
			var seq_before := SaveManager.new(CHAOS_ROOT).peek_next_save_seq()
			var crasher := CrashMidWriteManager.new(CHAOS_ROOT)
			var crashed: bool = crasher.save_run(engine)
			tally["crash_saves"] += 1
			if harness.check(not crashed, "chaos %d: killed mid-write save reported failure" % cycle):
				harness.check(SaveManager.new(CHAOS_ROOT).peek_next_save_seq() == seq_before,
					"chaos %d: the ring did NOT advance on the failed save" % cycle)
		else:
			var saver := SaveManager.new(CHAOS_ROOT)
			if harness.check(saver.save_run(engine), "chaos %d: save succeeded" % cycle):
				known[engine.state_hash()] = true
				tally["saves"] += 1

		# The rogue step. Variant rotation, EXCEPT on crash cycles (the cycle
		# saved nothing): there the rogue may not touch slot bytes at all —
		# killing the last good slot on a cycle with no fresh save could wipe
		# the ring, which no real interleaving produces (a save must die AND
		# two prior generations must already be gone). Its action is the
		# orphan-temp probe instead. On save cycles the ring holds >= 2 good
		# slots here, so corrupting <= present-1 always leaves a loadable one.
		var variant := cycle % 6
		if cycle % 5 == 4:
			variant = 4
		var rogue_bytes := ""
		var expect_quarantine := false
		var present := _present_slots(CHAOS_ROOT)
		var newest := _max_seq_slot(present)
		match variant:
			0:
				rogue_bytes = _truncate_slot(CHAOS_ROOT, newest, 0.55)
				tally["truncate"] += 1
				expect_quarantine = true
			1:
				rogue_bytes = "{ torn mid-write by a rogue sector "
				_write_text(CHAOS_ROOT.path_join("run_slot_%d.json" % newest), rogue_bytes)
				tally["garbage"] += 1
				expect_quarantine = true
			2:
				_write_text(CHAOS_ROOT.path_join("run_slot_%d.json" % newest), "")
				tally["empty"] += 1
				expect_quarantine = true
			3:
				rogue_bytes = _truncate_slot(CHAOS_ROOT, newest, 0.4)
				tally["double"] += 1
				expect_quarantine = true
				if present.size() >= 3:
					var oldest := 0
					var first := true
					for slot: int in present:
						if first or int(present[slot]) < int(present[oldest]):
							oldest = slot
							first = false
					_truncate_slot(CHAOS_ROOT, oldest, 0.7)
			4:
				var orphan := CHAOS_ROOT.path_join("run_slot_%d.json" % ((newest + 1) % SaveManager.RUN_SLOT_COUNT)) + SaveManager.TEMP_SUFFIX
				_write_text(orphan, "orphaned partial bytes from a killed process")
				tally["tmp"] += 1
			5:
				var path := CHAOS_ROOT.path_join("run_slot_%d.json" % newest)
				rogue_bytes = _read_text(path).replace("\"schema_version\": 1", "\"schema_version\": 99")
				_write_text(path, rogue_bytes)
				tally["future"] += 1
				expect_quarantine = true

		# The next "process" MUST load some good slot.
		var manager := SaveManager.new(CHAOS_ROOT)
		var next_engine := HOST.game_stack(CHAOS_SEED, RunMeta.new(), MVP.MARATHON_STIPEND)
		var loaded: bool = manager.load_run(next_engine)
		var good_hash := loaded and known.has(next_engine.state_hash())
		if harness.check(good_hash, "chaos %d: next process loaded a GOOD slot (hash %d)" % [cycle, next_engine.state_hash()]):
			good_loads += 1
		if variant == 4:
			var orphan := CHAOS_ROOT.path_join("run_slot_%d.json" % ((newest + 1) % SaveManager.RUN_SLOT_COUNT)) + SaveManager.TEMP_SUFFIX
			harness.check(not FileAccess.file_exists(orphan), "chaos %d: the orphan temp was swept by the next process" % cycle)
		if expect_quarantine:
			if _quarantine_holds(CHAOS_ROOT, "run_slot_%d.json" % newest, rogue_bytes):
				bytes_verified += 1
				quarantines += 1
			else:
				harness.check(false, "chaos %d: corrupted bytes preserved in quarantine" % cycle)

	# The meta domain was never touched by the rogue.
	var meta_files := _list_files(CHAOS_ROOT)
	var meta_quarantined := false
	for name in meta_files:
		if String(name).begins_with(SaveManager.META_FILENAME + SaveManager.QUARANTINE_SUFFIX):
			meta_quarantined = true
	var final_meta: RunMeta = SaveManager.new(CHAOS_ROOT).load_meta()
	harness.check(not meta_quarantined, "chaos: the meta domain was never quarantined (rogue only hit run slots)")
	harness.check(final_meta.chronicle.size() == session.meta.chronicle.size()
		and final_meta.legacy_points == session.meta.legacy_points,
		"chaos: meta intact after %d cycles (bank %d lp, chronicle %d)" % [CHAOS_CYCLES, final_meta.legacy_points, final_meta.chronicle.size()])
	harness.check(good_loads == CHAOS_CYCLES, "chaos: EVERY cycle ended loadable (%d/%d good loads)" % [good_loads, CHAOS_CYCLES])
	harness.check(quarantines > 0 and bytes_verified == quarantines,
		"chaos: %d quarantines, every one byte-preserving" % quarantines)
	harness.check(int(tally["crash_saves"]) > 0 and int(tally["saves"]) > 0,
		"chaos interleaved both save kinds (%d good saves, %d killed mid-write)" % [tally["saves"], tally["crash_saves"]])
	print(
		"[save_integrity_full] chaos: %d cycles — %d saves + %d kill-mid-write; rogue %s; %d/%d good loads; %d quarantines preserved; meta never touched"
		% [CHAOS_CYCLES, tally["saves"], tally["crash_saves"], str(tally), good_loads, CHAOS_CYCLES, quarantines]
	)
	report["chaos_good_loads"] = good_loads
	report["chaos_quarantines"] = quarantines


# --- Chaos helpers ---------------------------------------------------------------


## {slot path index -> save_seq} for every slot file currently on disk.
func _present_slots(root: String) -> Dictionary:
	var present := {}
	for slot: int in SaveManager.RUN_SLOT_COUNT:
		var path := root.path_join("run_slot_%d.json" % slot)
		if not FileAccess.file_exists(path):
			continue
		var envelope := _parse_text(_read_text(path))
		if not envelope.is_empty():
			present[slot] = int(envelope.get("save_seq", -1))
	return present


func _max_seq_slot(present: Dictionary) -> int:
	var best := -1
	var best_slot := 0
	for slot: int in present:
		if int(present[slot]) > best:
			best = int(present[slot])
			best_slot = slot
	return best_slot


## Truncates one slot to `fraction` of its bytes; returns the bytes it now
## holds (the exact content a quarantine must preserve).
func _truncate_slot(root: String, slot: int, fraction: float) -> String:
	var path := root.path_join("run_slot_%d.json" % slot)
	var truncated := _read_text(path).substr(0, int(_read_text(path).length() * fraction))
	_write_text(path, truncated)
	return truncated


## True when some <name>.corrupt[-n] file holds exactly `bytes`. Scans the
## directory (the -n suffix counter grows without bound across cycles).
func _quarantine_holds(root: String, file_name: String, bytes: String) -> bool:
	var prefix := file_name + SaveManager.QUARANTINE_SUFFIX
	for name: String in _list_files(root):
		if name.begins_with(prefix) and _read_text(root.path_join(name)) == bytes:
			return true
	return false


func _newest_slot(root: String) -> Dictionary:
	var present := _present_slots(root)
	if present.is_empty():
		return {"slot": -1, "seq": -1, "text": ""}
	var slot := _max_seq_slot(present)
	var path := root.path_join("run_slot_%d.json" % slot)
	return {"slot": slot, "seq": int(present[slot]), "text": _read_text(path)}


func _list_files(root: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return names


# --- Event tail (copy at drain; pooled events must never be cached) -------------


class Tail:
	extends RefCounted

	var entries: Array[Dictionary] = []
	var _seq := 0

	func drain(log: SimEventLog) -> void:
		while _seq < log.next_seq():
			var event := log.get_event(_seq)
			if event != null:
				entries.append({"tick": event.tick, "type": event.type, "subject": event.subject, "value": event.value})
			_seq += 1

	func of_type(type: StringName) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for entry in entries:
			if entry["type"] == type:
				found.append(entry)
		return found

	func last(type: StringName) -> Dictionary:
		for index in range(entries.size() - 1, -1, -1):
			if entries[index]["type"] == type:
				return entries[index]
		return {}


## Most recent event of `type` in an engine's ring (probe engines: read back
## a bounded window from the head — their continuations are short).
func _last_event_of(log: SimEventLog, type: StringName) -> Dictionary:
	var hi := log.next_seq()
	var lo := maxi(0, hi - 40)
	for seq in range(hi - 1, lo - 1, -1):
		var event := log.get_event(seq)
		if event != null and event.type == type:
			return {"t": event.type}
	return {}


# --- File helpers (the suite runs under user:// and cleans up after itself) ------


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _parse_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
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
	for file_name: String in files:
		dir.remove(file_name)
	for sub: String in dirs:
		_erase_dir(path.path_join(sub))
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null:
		parent.remove(path.get_file())
