## Deterministic fixed-step economy engine core (T-SIM-01).
##
## Pure logic: RefCounted, no scene tree, no timers, no wall clock —
## time arrives only as tick counts (the drive shell is T-SIM-07's job).
## The full contract is documented in docs/sim-engine.md; the invariants:
##
##   - FIXED STEP: 1 tick = 1 sim-minute (TICK_SECONDS = 60); 1000
##     sim-hours = 60,000 ticks
##   - DETERMINISM: identical run seed + identical tick count + identical
##     injected commands (in the same order between the same ticks)
##     => identical `state_hash()`. Single seeded RNG per engine, drawn
##     only inside system on_tick/on_command, in fixed registration order
##   - FAST-FORWARD: `fast_forward(n)` runs n ticks with zero per-tick
##     signal emission (events still land in the bounded ring) — the
##     1000h marathon is pure loop
##   - COMMANDS: FIFO queue drained at the START of each processed tick;
##     dispatched to systems in registration order, first `true` wins
##   - PAUSE: frozen tick advancement; commands still queue and apply on
##     the first resumed tick
##   - STATE ACCESS: everything a save needs flows through
##     `to_dict()/apply_state_dict()` (T-ARCH-03 composes them)
class_name SimEngine
extends RefCounted

## Seconds of game time advanced per tick (docs/sim-engine.md §1: the
## 1-minute tick choice and its justification).
const TICK_SECONDS: int = 60

## Ticks per whole sim-hour (3600 / TICK_SECONDS).
const TICKS_PER_SIM_HOUR: int = 3600 / TICK_SECONDS

## Ticks per whole sim-day.
const TICKS_PER_SIM_DAY: int = 24 * TICKS_PER_SIM_HOUR

## Version of the engine's core state dict (T-ARCH-03 bumps on change).
const STATE_FORMAT_VERSION: int = 1

## Live-tick event signal (NOT emitted during fast_forward).
signal event_logged(event: SimEvent)

## Emitted once per successful fast_forward call (cheap: n ticks, 1 signal).
signal fast_forwarded(from_tick: int, to_tick: int)

## Emitted on pause()/resume() transitions (idempotent calls stay silent).
signal pause_changed(is_paused: bool)

## The run seed this engine was constructed with (hashed + serialized).
var run_seed: int

## The engine's single RNG. Systems draw from it ONLY inside on_tick /
## on_command — call order is deterministic, so the stream is
## reproducible. Its full state is part of state_hash().
var rng := RandomNumberGenerator.new()

## The change/event stream (bounded ring, pooled events; §3).
var events: SimEventLog

## True while advancement is frozen (pause()); commands still queue.
var paused := false

## Number of processed ticks (tick N is the Nth transition; first tick
## moves it to 1). The engine's clock — nothing else advances it.
var tick_count: int = 0

## Whole-unit resource pool, keyed by resource id (T-SIM-02's systems
## settle integer units into it from their SimFixed accumulators).
var resources: Dictionary[StringName, int] = {}

var _systems: Array[SimSystem] = []
var _systems_by_name: Dictionary = {}
var _pending: Array[SimCommand] = []


func _init(p_run_seed: int = 0, p_event_capacity: int = SimEventLog.DEFAULT_CAPACITY) -> void:
	run_seed = p_run_seed
	rng.seed = p_run_seed
	events = SimEventLog.new(p_event_capacity)


# --- Systems -------------------------------------------------------------
#
# Systems run in registration order; that order is part of the
# determinism contract (two engines must register the same systems in
# the same order to produce identical hashes).

## Registers a system. Returns false (and refuses) on duplicate name.
func register_system(system: SimSystem) -> bool:
	assert(system != null, "SimEngine.register_system: system must not be null")
	var id := system.system_name()
	if _systems_by_name.has(id):
		push_warning("sim: system '%s' already registered — refusing duplicate" % id)
		return false
	_systems.append(system)
	_systems_by_name[id] = system
	system.on_register(self)
	return true


func get_system(id: StringName) -> SimSystem:
	return _systems_by_name.get(id)


func system_count() -> int:
	return _systems.size()


# --- Advancement ---------------------------------------------------------

## Advances exactly one tick, emitting event_logged for every event
## recorded during it (live mode — this is what the game loop calls).
## Returns false (and does nothing) while paused.
func tick() -> bool:
	if paused:
		return false
	_step(true)
	return true


## Runs n ticks back-to-back with NO per-tick signals (events still land
## in the bounded ring). Returns ticks actually run: 0 while paused,
## otherwise n. This is the catch-up / marathon / offline path.
func fast_forward(n_ticks: int) -> int:
	assert(n_ticks >= 0, "SimEngine.fast_forward: n_ticks must be >= 0")
	if paused or n_ticks == 0:
		return 0
	var from := tick_count
	for i in n_ticks:
		_step(false)
	fast_forwarded.emit(from, tick_count)
	return tick_count - from


func pause() -> void:
	if not paused:
		paused = true
		pause_changed.emit(true)


func resume() -> void:
	if paused:
		paused = false
		pause_changed.emit(false)


# --- Commands ------------------------------------------------------------

## Queues a command. It is dispatched to systems (in registration order,
## first handler wins) at the START of the next processed tick — never
## immediately, so command application is tick-aligned and identical
## across engines that receive the same commands between the same ticks.
func submit_command(kind: StringName, subject: StringName = &"", value: int = 0) -> void:
	_pending.append(SimCommand.new(kind, subject, value))


func pending_command_count() -> int:
	return _pending.size()


# --- Resources (whole-unit int pool; T-SIM-02 owns production) ----------

func get_resource(id: StringName) -> int:
	return int(resources.get(id, 0))


func set_resource(id: StringName, amount: int) -> void:
	assert(amount >= 0, "SimEngine.set_resource: amount must be >= 0 (id '%s')" % id)
	resources[id] = amount


func add_resource(id: StringName, delta: int) -> void:
	set_resource(id, get_resource(id) + delta)


# --- Time (derived, read-only) -------------------------------------------

func sim_minutes() -> int:
	return tick_count


func sim_seconds() -> int:
	return tick_count * TICK_SECONDS


## Float sim-hours for DISPLAY/reporting only — never hashed, never the
## input to economy math (integers + SimFixed are).
func sim_hours() -> float:
	return float(tick_count) / float(TICKS_PER_SIM_HOUR)


# --- State hash (the determinism oracle) ---------------------------------

## Deterministic 64-bit-int hash over ALL simulation state (never the
## event ring — that is presentation history). Same construction + same
## seed + same commands between the same ticks => same value, on every
## machine: it mixes only integers (FNV-1a-style multiply/xor kept
## inside 32 bits per step, so no signed-overflow anywhere) plus
## Godot's stable String.hash() for identifiers.
func state_hash() -> int:
	var h := 0x811C9DC5  # FNV-1a 32-bit offset basis
	h = _mix(h, STATE_FORMAT_VERSION)
	h = _mix(h, run_seed)
	h = _mix(h, tick_count)
	h = _mix(h, rng.state)
	h = _mix(h, 1 if paused else 0)
	h = _mix(h, _pending.size())
	for command in _pending:
		h = _mix(h, String(command.kind).hash())
		h = _mix(h, String(command.subject).hash())
		h = _mix(h, command.value)
	var resource_ids: Array = resources.keys()
	resource_ids.sort()
	for id in resource_ids:
		h = _mix(h, String(id).hash())
		h = _mix(h, int(resources[id]))
	for system in _systems:
		h = _mix(h, String(system.system_name()).hash())
		h = _mix(h, system.state_hash())
	return h


# --- Serialization hooks (full save compose lands in T-ARCH-03) ----------

## Whole engine state as a JSON-safe Dictionary: core scalars + command
## queue + one sub-dict per registered system (keyed by system_name).
## The event ring is presentation history and is NOT serialized.
func to_dict() -> Dictionary:
	var pending: Array[Dictionary] = []
	for command in _pending:
		pending.append({
			"kind": String(command.kind),
			"subject": String(command.subject),
			"value": command.value,
		})
	var resource_state := {}
	for id in resources.keys():
		resource_state[String(id)] = int(resources[id])
	var system_states := {}
	for system in _systems:
		system_states[String(system.system_name())] = system.to_dict()
	return {
		"format_version": STATE_FORMAT_VERSION,
		"run_seed": run_seed,
		"tick_count": tick_count,
		"paused": paused,
		"rng_state": rng.state,
		"resources": resource_state,
		"pending_commands": pending,
		"systems": system_states,
	}


## Restores core + per-system state captured by to_dict() into THIS
## engine. Register the same systems first (same order); each system's
## from_dict() is fed its sub-dict by name. Returns false (refuses,
## state untouched) on a format_version mismatch — loud, never
## half-applied.
func apply_state_dict(state: Dictionary) -> bool:
	var version := int(state.get("format_version", -1))
	if version != STATE_FORMAT_VERSION:
		push_error(
			"sim: engine state format %d is not supported (expected %d) — refusing"
			% [version, STATE_FORMAT_VERSION]
		)
		return false
	run_seed = int(state["run_seed"])
	rng.seed = run_seed
	rng.state = int(state["rng_state"])
	tick_count = int(state["tick_count"])
	paused = bool(state["paused"])
	_pending.clear()
	for entry in state.get("pending_commands", []):
		_pending.append(SimCommand.new(StringName(entry["kind"]), StringName(entry["subject"]), int(entry["value"])))
	resources.clear()
	var resource_state: Dictionary = state.get("resources", {})
	for id in resource_state.keys():
		resources[StringName(id)] = int(resource_state[id])
	var system_states: Dictionary = state.get("systems", {})
	for system in _systems:
		var id := String(system.system_name())
		if system_states.has(id):
			system.from_dict(system_states[id])
		else:
			push_warning("sim: state dict has no entry for system '%s'" % id)
	return true


# --- Internals ------------------------------------------------------------

## One fixed-step transition: commands first, then systems in
## registration order. `live` only controls signal emission — the
## state transition is IDENTICAL either way (test: ffwd(100) ==
## 100 x tick()).
func _step(live: bool) -> void:
	tick_count += 1
	var first_seq := events.next_seq()
	if not _pending.is_empty():
		_drain_commands()
	for system in _systems:
		system.on_tick(self)
	if live:
		var seq := first_seq
		while seq < events.next_seq():
			event_logged.emit(events.get_event(seq))
			seq += 1


func _drain_commands() -> void:
	while not _pending.is_empty():
		var command: SimCommand = _pending.pop_front()
		var handled := false
		for system in _systems:
			if system.on_command(self, command):
				handled = true
				break
		if not handled:
			push_warning("sim: command '%s' had no handler — recorded as rejected" % command.kind)
			events.record(tick_count, &"command_rejected", command.kind, command.value)


## FNV-flavored integer mix: both halves of the 64-bit value are folded
## in; every intermediate stays inside 32 bits, so the result depends on
## no platform-sensitive behavior (docs/sim-engine.md §2).
static func _mix(hash_value: int, value: int) -> int:
	var x := (hash_value ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	x = (x * 16777619) & 0xFFFFFFFF
	x = (x ^ ((value >> 32) & 0xFFFFFFFF)) & 0xFFFFFFFF
	return (x * 16777619) & 0xFFFFFFFF
