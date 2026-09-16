## GameHost — the real-game engine host (T-UI-03).
##
## THE COMPOSITION MIRROR OF THE CANONICAL FIXTURE. tests/acceptance/
## suites/_full_stack.gd is where the "real game" composition is defined
## once (docs/sim-engine.md §17): heartbeat -> run -> units -> production
## -> assault -> suspicion-LAST, MVP pack through the loud gate, one RunMeta
## shared across engines, one CatchUpService from the pack tunables. Tests
## cannot ship, so this host composes THE SAME shape from THE SAME content
## — and `tests/unit/test_game_host.gd > composition parity` pins the two
## together (same system names, same order), so CI green means the
## composition the player runs is the composition CI asserts.
##
## WHAT IT OWNS (and nothing more — T-PERF-01 owns the platform boundary):
##   - the engine + all six systems, rebuilt wholesale on restart,
##   - ONE SaveManager (run ring + meta domain; scratch roots for tests),
##   - ONE RunMeta + ONE CatchUpService — the HostSession wiring,
##   - TICK PACING: `advance(delta_seconds)` converts injected real time to
##     sim ticks through `time_scale` (1 tick = 60 sim-seconds; the demo's
##     accel toggles the scale, never the engine). All time is INJECTED —
##     zero OS/Time reads live in this file (the security-policy inventory
##     stays true; the platform host injects timestamps at the seams below),
##   - EVENT DELIVERY, UNIFIED: every event is delivered to the UI EXACTLY
##     ONCE, in seq order, through `event_observed` — live ticks drain the
##     ring after each batch exactly like the post-fast-forward tail
##     (docs/sim-engine.md §3/§13: pooled events are copied to plain dicts;
##     a held SimEvent is invalid after its slot is reused),
##   - COMMANDS: `submit()` is the one write path down (the UI-seam
##     contract); reads flow up through the systems' query surfaces.
##
## T-PERF-01 SEAMS (WIRED via ui/host/app_lifecycle.gd — the platform
## boundary policy the game screen's `_notification` feeds): `background
## (now_epoch)` / `foreground(now_epoch)` / the `driving` flag. The host
## itself never polls focus and never reads a clock — timestamps arrive
## injected at these seams.
##
## Headless-testable by construction: RefCounted, no scene tree, injected
## time, injectable save root.
class_name GameHost
extends RefCounted

## One event copied out of the pooled ring: {seq, tick, type, subject,
## value, value2}. Delivered exactly once per event, seq order.
signal event_observed(event: Dictionary)

## Emitted once per advance()/foreground() batch that processed ticks
## (value = ticks run). Pips and countdowns refresh off this — NOT off
## per-frame state polling.
signal sim_advanced(ticks: int)

## Run liveness transitions (started/restarted, ended by any outcome).
signal run_state_changed(running: bool)

## A foreground catch-up window resolved (the report is T-UI-09's data).
signal catch_up_resolved(report: Dictionary)

## Run seed (identity source; same seed => same leader/regime draw order).
var run_seed: int

## The live engine (replaced wholesale by restart_run()/build_engine()).
var engine: SimEngine

## The meta save domain (chronicle + bank + catch-up anchor) — ONE per
## session, shared by every engine this host builds.
var meta: RunMeta

## The foreground-boundary service (timestamps injected by callers).
var catch_up: CatchUpService

## The save layer (run ring + meta). Tests inject scratch roots.
var save_manager: SaveManager

## Real-seconds -> sim-seconds multiplier (1.0 = wall-time play; the demo
## accelerates by scaling this, never by stepping the engine directly).
var time_scale: float = 1.0:
	set(value):
		time_scale = maxf(0.0, value)

## Autosave cadence in ticks (default: once per sim hour). 0 disables.
var autosave_interval_ticks: int = SimEngine.TICKS_PER_SIM_HOUR

## True while this host should drive the sim from injected time (the
## foreground seam — T-PERF-01 flips it on focus loss; advance() no-ops
## while false so a hidden app consumes nothing).
var driving: bool = true:
	set(value):
		driving = value

## True while event_observed is draining a FOREGROUND CATCH-UP window (the
## offline batch): T-UI-04's queued promotion-flip replay keys on it — an
## army promotion that lands inside an away window replays as a capped,
## staggered flip on the foreground boundary, never as a table of cards
## all turning at once. Read-only for consumers; only foreground()
## toggles it.
var delivering_catch_up := false

## The report of the MOST RECENTLY resolved away window ({} before the
## first foreground). The BOOT seam: a window resolved inside boot() fires
## catch_up_resolved before any screen has connected, so T-UI-09's check-in
## beat reads THIS instead — the summary is never lost to mount order.
var last_catch_up_report := {}

var _accum_seconds := 0.0
var _consumed_seq := 0
var _ticks_since_autosave := 0


## `p_save_root` overrides the save root (tests use scratch dirs; the
## game uses SaveManager's own default, user://saves).
func _init(p_run_seed: int, p_save_root: String = "") -> void:
	run_seed = p_run_seed
	meta = RunMeta.new()
	catch_up = CatchUpService.new(Inks.pack().tunables)
	save_manager = SaveManager.new(p_save_root if not p_save_root.is_empty() else "user://saves")
	engine = build_engine()


# --- composition (THE mirror of _full_stack.game_stack) --------------------------


## Builds one canonical five-system engine + heartbeat around the shared
## meta. System order is contractual (docs/sim-engine.md §4/§14/§15):
## heartbeat -> run -> units -> production -> assault -> suspicion LAST.
func build_engine() -> SimEngine:
	var pack := Inks.pack()
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RunLifecycleSystem.new(pack.regimes, pack.identity, meta, pack.starting_grants))
	engine.register_system(UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables))
	engine.register_system(ProductionSystem.new(pack.buildings, pack.tunables, null))
	engine.register_system(AssaultResolver.new(pack.tunables))
	engine.register_system(SuspicionSystem.new(pack.tunables, pack.units, pack.copy))
	return engine


## System names in registration order — the parity probe the unit suite
## compares against the canonical fixture (derived from to_dict()'s
## systems map, which is insertion-ordered = registration order; the
## engine core stays untouched).
func system_order() -> Array[StringName]:
	var names: Array[StringName] = []
	for key in engine.to_dict()["systems"].keys():
		names.append(StringName(key))
	return names


# --- boot / session boundaries ----------------------------------------------------


## Boots the session. With a loadable save: restores run + meta domains
## into this host's engine and resolves the away window through the real
## catch-up service (`p_now_epoch` injected by the platform host; the
## first-launch sentinel 0 means "no anchor" and skips catch-up). Fresh:
## starts the first run through the run_start command and settles one tick
## so the booting screen binds a RUNNING run (identity drawn, stipend
## queued→paid) instead of a blank table. Returns true when a save loaded.
func boot(p_now_epoch: int = 0) -> bool:
	var loaded_meta := save_manager.load_meta()
	if loaded_meta != null:
		meta.apply_dict(loaded_meta.to_dict())
	var loaded: bool = has_saved_run() and save_manager.load_run(engine)
	_consumed_seq = engine.events.next_seq()
	_sync_run_state(false)
	if not loaded:
		# The canonical boot verbs (the M1 gate contract): start the run,
		# then pay the pack's stipend through the grant verb — amounts
		# live in content, never in the caller. Both drain at tick 1.
		engine.submit_command(&"run_start")
		engine.submit_command(&"grant_resources")
		advance_ticks(1)
		return false
	if p_now_epoch != 0:
		foreground(p_now_epoch)
	return true


## True when a run save exists on disk (first launch stays SILENT — the
## manager's load_run refusal is loud by design, for corruption; absence
## of any save is the normal fresh-boot path, not an error).
func has_saved_run() -> bool:
	if FileAccess.file_exists(save_manager.meta_path()):
		return true
	for slot in SaveManager.RUN_SLOT_COUNT:
		if FileAccess.file_exists(save_manager.run_slot_path(slot)):
			return true
	return false


## Foreground boundary (T-PERF-01's call): resolves one away window
## through the real engine, delivers the gap's events through the unified
## feed (flagged as the offline batch — see delivering_catch_up), and
## re-enables driving.
func foreground(p_now_epoch: int) -> Dictionary:
	driving = true
	delivering_catch_up = true
	var report := catch_up.apply(engine, meta, p_now_epoch)
	var applied := int(report.get("applied_ticks", 0))
	_drain_events()
	delivering_catch_up = false
	last_catch_up_report = report
	if applied > 0:
		_emit_advanced(applied)
		catch_up_resolved.emit(report)
		_autosave_if_due(applied)
	return report


## Background/save boundary (T-PERF-01's call): stops driving and refreshes
## the away-time anchor so the next foreground measures from here. ORDER:
## the anchor is taken BEFORE the world stops being driven — the away
## window opens at exactly this platform moment — and the whole boundary is
## synchronous, so no tick can land between the two. The save flush that
## follows is the window's opening bookend on disk (docs/catch-up.md §6).
func background(p_now_epoch: int) -> void:
	catch_up.mark_seen(meta, p_now_epoch)
	driving = false
	save_all()


# --- time (injected, scaled) -------------------------------------------------------


## Feeds real elapsed seconds into the pacer. Returns ticks processed.
## Fractional remainders carry in the accumulator (never lost, never
## double-counted); the engine itself only ever sees whole ticks.
func advance(delta_seconds: float) -> int:
	if not driving or delta_seconds <= 0.0:
		return 0
	_accum_seconds += delta_seconds * time_scale
	var ticks := int(_accum_seconds / float(SimEngine.TICK_SECONDS))
	if ticks <= 0:
		return 0
	_accum_seconds -= float(ticks) * float(SimEngine.TICK_SECONDS)
	return advance_ticks(ticks)


## Processes exactly n ticks (live semantics: tick(), pause-aware) and
## delivers the batch. The deterministic-drive path tests and the demo
## policy scheduler use; behaviorally identical to advance() pacing.
func advance_ticks(ticks: int) -> int:
	if ticks <= 0 or not driving:
		return 0
	var was_running := run().is_running()
	var ran := 0
	for i in ticks:
		if not engine.tick():
			break  # paused: the world is frozen
		ran += 1
	if ran > 0:
		_drain_events()
		_emit_advanced(ran)
		_autosave_if_due(ran)
		_sync_run_state(was_running)
	return ran


## Convenience: fast-forward through the SAME drain path (used by the
## screenshot harness; events still delivered exactly once).
func fast_forward(ticks: int) -> int:
	var was_running := is_run_running()
	var ran := engine.fast_forward(ticks)
	if ran > 0:
		_drain_events()
		_emit_advanced(ran)
		_autosave_if_due(ran)
		_sync_run_state(was_running)
	return ran


# --- writes / reads -----------------------------------------------------------------


## THE write path down (UI-seam contract): queues a command; it drains at
## the next processed tick's start.
func submit(kind: StringName, subject: StringName = &"", value: int = 0) -> void:
	engine.submit_command(kind, subject, value)


## In-engine restart (the run_restart command — equivalent to build_engine
## by docs/sim-engine.md §12; a fresh identity is drawn at the drain, the
## pool zeroes, and the new run's stipend is paid through the grant verb
## in the same drain).
func restart_run() -> void:
	submit(&"run_restart")
	submit(&"grant_resources")


## Saves both domains atomically. Returns true when both wrote.
func save_all() -> bool:
	var run_ok := save_manager.save_run(engine)
	var meta_ok := save_manager.save_meta(meta)
	return run_ok and meta_ok


# --- typed read accessors (the systems' documented query surfaces) -----------------


func run() -> RunLifecycleSystem:
	return engine.get_system(&"run") as RunLifecycleSystem


func units() -> UnitLifecycleSystem:
	return engine.get_system(&"units") as UnitLifecycleSystem


func production() -> ProductionSystem:
	return engine.get_system(&"production") as ProductionSystem


func suspicion() -> SuspicionSystem:
	return engine.get_system(&"suspicion") as SuspicionSystem


func assault() -> AssaultResolver:
	return engine.get_system(&"assault") as AssaultResolver


func is_run_running() -> bool:
	var run_system := run()
	return run_system != null and run_system.is_running()


# --- internals -----------------------------------------------------------------------


## Delivers every not-yet-delivered ring event as a copied dict, in seq
## order. Handles eviction loudly (a 4096 ring with small UI batches
## should never evict undelivered events; if one does, say so and resume
## from the frontier rather than replaying garbage).
func _drain_events() -> void:
	var next := engine.events.next_seq()
	var oldest := engine.events.oldest_seq()
	if _consumed_seq < oldest:
		push_warning("game-host: %d event(s) evicted before delivery (seq %d..%d) — resuming at the frontier"
			% [oldest - _consumed_seq, _consumed_seq, oldest - 1])
		_consumed_seq = oldest
	while _consumed_seq < next:
		var event := engine.events.get_event(_consumed_seq)
		if event == null:
			push_warning("game-host: event %d vanished from the ring — stopping this drain" % _consumed_seq)
			return
		event_observed.emit({
			"seq": event.seq,
			"tick": event.tick,
			"type": event.type,
			"subject": event.subject,
			"value": event.value,
			"value2": event.value2,
		})
		_consumed_seq += 1
	next = engine.events.next_seq()  # events recorded during emission (none today)


func _emit_advanced(ticks: int) -> void:
	sim_advanced.emit(ticks)


func _autosave_if_due(ticks: int) -> void:
	if autosave_interval_ticks <= 0:
		return
	_ticks_since_autosave += ticks
	if _ticks_since_autosave >= autosave_interval_ticks:
		_ticks_since_autosave = 0
		save_all()


func _sync_run_state(_was_running: bool) -> void:
	var running := is_run_running()
	if running != _was_running:
		run_state_changed.emit(running)
