## Acceptance marathon — offline catch-up across away windows (T-SIM-07;
## content: the T-DATA-02 MVP pack + suspicion registered LAST per §14).
##
## Marathon-style honesty: away windows are simulated purely through
## INJECTED UTC timestamps (never a wall clock — the service consumes
## platform-provided time by contract), and every resolved gap is proven
## against a TWIN ENGINE that ran the same ticks LIVE (tick() loop, not
## fast_forward): resources per type, state_hash, arrivals, suspicion —
## the whole deterministic state, not just the summary's own arithmetic.
##
##   PLAY: 24h honest prefix (builds the producers, staffs them) — twins
##   bit-identical before any away window.
##   WINDOW 1: 8h37m away -> capped at exactly 8h (480 ticks), twin parity.
##   WINDOW 2: 2h more play, then 2h17m away -> 137 ticks, twin parity.
##   KILL TEST: save at background time, "process dies" (the caught-up
##   engine is discarded unsaved), fresh engine + SaveManager reload from
##   disk, a LONGER gap resolves deterministically from the anchor — the
##   pre-catch-up save was the valid state all along (also covers
##   save/load DURING an away window: the save IS the window's opening).
##   FIRST LAUNCH: a fresh bank (sentinel anchor) accrues nothing.
##   BACKWARDS CLOCK: a rewound timestamp accrues nothing and changes
##   nothing (hash identical).
##
## Budget: Thor's compute bound — the capped 8h resolution must complete
## in < 100ms (480 ticks through the full stack).
extends RefCounted

const MVP := preload("res://tests/acceptance/suites/_mvp_pack.gd")

const RUN_SEED := 20260924
const T0 := 1_790_000_000  # injected UTC epoch; any value works — DST-safe by design
const SCRATCH_ROOT := "user://cs_catchup_marathon"
const COMPUTE_BUDGET_MSEC := 100
const TOTAL_BUDGET_SECONDS := 30.0


func suite_name() -> String:
	return "marathon_catch_up_gap"


func run(harness) -> void:
	var clock_start := Time.get_ticks_msec()
	var service := CatchUpService.new(MVP.load_mvp().tunables)
	harness.check(service.cap_ticks() == 480, "R4 default cap is 8h = 480 ticks (%d)" % service.cap_ticks())

	# --- Playing prefix, identical on both engines ---------------------------
	var engine := _build()
	var meta := _meta_of(engine)
	_play_prefix(engine)
	var twin := _build()
	_play_prefix(twin)
	harness.check(engine.state_hash() == twin.state_hash(), "prefix leaves the twins bit-identical (hash %d)" % engine.state_hash())

	# --- Window 1: 8h37m away, capped at 8h -----------------------------------
	var f1 := T0 + 8 * 3600 + 37 * 60  # the foreground timestamp (injected)
	service.mark_seen(meta, T0)
	var food_before := engine.get_resource(&"food")
	var twin_food_before := twin.get_resource(&"food")
	var twin_seq := twin.events.next_seq()
	var apply_start := Time.get_ticks_msec()
	var report := service.apply(engine, meta, f1)
	var apply_msec := Time.get_ticks_msec() - apply_start
	for i in int(report["applied_ticks"]):
		twin.tick()  # the same ticks, LIVE
	harness.check(bool(report["capped"]), "8h37m away is capped (raw %d s -> clamped %d s)" % [report["elapsed_seconds"], report["clamped_seconds"]])
	harness.check(int(report["applied_ticks"]) == 480, "capped window applies exactly 480 ticks (%d)" % report["applied_ticks"])
	harness.check(apply_msec < COMPUTE_BUDGET_MSEC, "capped 8h catch-up resolves in < %dms (took %dms)" % [COMPUTE_BUDGET_MSEC, apply_msec])
	harness.check(_resources_equal(engine, twin), "post-catch-up resource totals equal the live twin's, per type")
	harness.check(engine.state_hash() == twin.state_hash(), "post-catch-up state_hash equals the live twin's (%d)" % engine.state_hash())
	harness.check(engine.get_resource(&"food") > food_before, "the away window actually produced (food %d -> %d)" % [food_before, engine.get_resource(&"food")])
	harness.check(int(report["resource_delta"][&"food"]) == engine.get_resource(&"food") - food_before, "summary resource delta is honest (food +%d)" % int(report["resource_delta"][&"food"]))
	harness.check(engine.get_resource(&"food") - food_before == twin.get_resource(&"food") - twin_food_before, "twin's own window delta matches the summary's")
	var arrivals_twin := _count(twin, twin_seq, &"recruit_arrived")
	harness.check(int(report["arrivals"]) == arrivals_twin and arrivals_twin > 0, "summary arrivals match the twin's ring (%d arrivals while away)" % arrivals_twin)
	var heat := engine.get_system(&"suspicion") as SuspicionSystem
	var twin_heat := twin.get_system(&"suspicion") as SuspicionSystem
	harness.check(heat.suspicion == twin_heat.suspicion, "suspicion matches the live twin after away-window decay (%d)" % heat.suspicion)
	harness.check(_count(engine, engine.events.oldest_seq(), &"catch_up_applied") == 1, "exactly one catch_up_applied summary event in the ring (the raw tail keeps the detail)")

	# --- Window 2: 2h of play on both, then 2h17m away -------------------------
	_play_hours(engine, 2)
	_play_hours(twin, 2)
	var b2 := f1 + 2 * 3600  # background again
	var f2 := b2 + 2 * 3600 + 17 * 60  # away 2h17m, then foreground
	service.mark_seen(meta, b2)
	report = service.apply(engine, meta, f2)
	for i in int(report["applied_ticks"]):
		twin.tick()
	harness.check(int(report["applied_ticks"]) == 137, "2h17m away applies exactly 137 ticks (%d)" % report["applied_ticks"])
	harness.check(engine.state_hash() == twin.state_hash(), "second window keeps twin parity (hash %d)" % engine.state_hash())

	# --- Kill mid-catch-up: the save made at background time stays valid ------
	var manager := SaveManager.new(SCRATCH_ROOT)
	harness.check(bool(manager.save_run(engine)), "both domains save at the moment of backgrounding (run)")
	harness.check(bool(manager.save_meta(meta)), "both domains save at the moment of backgrounding (meta carries the anchor)")
	# The killed process: catch-up runs in memory, then the process dies
	# before ANY save — the disk still holds the pre-catch-up state.
	service.apply(engine, meta, f2 + 2 * 3600)
	# Fresh process, fresh everything; a LONGER gap resolves from the anchor.
	var revived := _build(manager.load_meta())
	harness.check(bool(manager.load_run(revived)), "fresh process loads the pre-catch-up save")
	report = service.apply(revived, _meta_of(revived), f2 + 7 * 3600)
	for i in int(report["applied_ticks"]):
		twin.tick()
	harness.check(int(report["applied_ticks"]) == 420, "the killed window's time re-resolves from the anchor (%d ticks — no partial state, no double-count)" % report["applied_ticks"])
	harness.check(revived.state_hash() == twin.state_hash(), "the revived engine lands bit-identical to the live twin (hash %d)" % revived.state_hash())

	# --- First launch on a fresh bank: nothing accrues -------------------------
	var fresh_meta := RunMeta.new()
	var fresh_report := service.apply(revived, fresh_meta, f2 + 365 * 86400)
	harness.check(bool(fresh_report["first_launch"]) and int(fresh_report["applied_ticks"]) == 0, "a first launch (sentinel anchor) accrues nothing even after a year")

	# --- Backwards clock: zero accrual, zero change ----------------------------
	var hash_before := revived.state_hash()
	var rewound := service.apply(revived, fresh_meta, f2 - 86400)
	harness.check(bool(rewound["rewound"]) and int(rewound["applied_ticks"]) == 0, "a rewound clock accrues nothing")
	harness.check(revived.state_hash() == hash_before, "a rewound clock changes NO state (hash identical)")
	harness.check(not str(CatchUpService.chronicle_line(rewound)).is_empty(), "the rewind gets its wry chronicle line")

	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var ticks_total: int = engine.tick_count + twin.tick_count
	print(
		"[marathon_catch_up_gap] window1 480 ticks capped in %dms; window2 137; revived 420; arrivals while away %d; food %d -> %d; suspicion %d; %d engine-ticks total in %.3fs; final hashes %d / %d"
		% [
			apply_msec, arrivals_twin, food_before, engine.get_resource(&"food"),
			heat.suspicion, ticks_total, wall, engine.state_hash(), twin.state_hash(),
		]
	)
	harness.check(wall < TOTAL_BUDGET_SECONDS, "whole suite in < %.0fs (took %.3fs)" % [TOTAL_BUDGET_SECONDS, wall])
	_erase_dir(SCRATCH_ROOT)


# --- Builders -----------------------------------------------------------------


## Full MVP stack + suspicion (§14 order): the away window advances the real
## economy AND the real pressure curve. `p_meta` injects a shared/loaded bank.
func _build(p_meta: RunMeta = null) -> SimEngine:
	var pack := MVP.load_mvp()
	var engine := SimEngine.new(RUN_SEED)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, p_meta, pack.starting_grants))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))
	engine.register_system(SuspicionSystem.new(pack.tunables, pack.units))
	return engine


func _meta_of(engine: SimEngine) -> RunMeta:
	return (engine.get_system(&"run") as RunLifecycleSystem).meta


## 40h of honest play: start + grant, build every producer (0 -> 1), then
## four managed 10h chunks (the command queue is tick-aligned, so each hop
## needs its own batch: accept -> train -> staff; identical on twins by
## construction). By the end the farm is STAFFED — the away window must
## have real production to accrue.
func _play_prefix(engine: SimEngine) -> void:
	engine.submit_command(&"run_start", &"", 0)
	engine.submit_command(&"grant_resources", &"", 0)
	engine.tick()
	for id in MVP.producer_ids():
		engine.submit_command(&"upgrade_building", id, 0)  # construct at base cost
	for i in 4:
		_quiet_manage(engine)
		engine.fast_forward(10 * SimEngine.TICKS_PER_SIM_HOUR)


## A short managed play stretch (whole hours), twin-symmetric.
func _play_hours(engine: SimEngine, hours: int) -> void:
	for i in hours:
		_quiet_manage(engine)
		engine.fast_forward(SimEngine.TICKS_PER_SIM_HOUR)


func _quiet_manage(engine: SimEngine) -> void:
	var units := engine.get_system(&"units") as UnitLifecycleSystem
	for uid in units.offer_ids():
		engine.submit_command(&"recruit_accept", &"", uid)
	for uid in units.idle_units(&"peasant"):
		engine.submit_command(&"assign_role", &"worker", uid)
	var production := engine.get_system(&"production") as ProductionSystem
	for id in MVP.producer_ids():
		var free: int = production.worker_slots(id) - production.assigned_workers(id)
		if free > 0 and production.idle_workers() > 0:
			engine.submit_command(&"assign_worker", id, mini(free, production.idle_workers()))


# --- Helpers --------------------------------------------------------------------


func _resources_equal(a: SimEngine, b: SimEngine) -> bool:
	var ids: Array = a.resources.keys()
	for id in b.resources.keys():
		if not ids.has(id):
			ids.append(id)
	for id in ids:
		if a.get_resource(id) != b.get_resource(id):
			return false
	return true


func _count(engine: SimEngine, from_seq: int, type: StringName) -> int:
	var total := 0
	for seq in range(from_seq, engine.events.next_seq()):
		var event := engine.events.get_event(seq)
		if event != null and event.type == type:
			total += 1
	return total


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
