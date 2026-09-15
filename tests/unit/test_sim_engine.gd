## Unit tests for the deterministic engine core (T-SIM-01).
## Mirrors sim/sim_engine.gd (test-mapping rule, docs/gdscript-conventions.md).
## Hawkeye lane seam coverage: determinism, tick boundaries, pause/resume,
## fast-forward equivalence, event stream semantics, serialization hooks.
extends GdUnitTestSuite


## Test-local system: consumes the engine RNG every tick and accumulates a
## bounded deterministic checksum — proves rng draw order + state are part
## of the determinism contract without shipping a fake economy system.
class RngProbeSystem extends SimSystem:
	var draws: int = 0
	var checksum: int = 1

	func system_name() -> StringName:
		return &"rng_probe"

	func on_tick(engine: SimEngine) -> void:
		draws += 1
		checksum = (checksum * 31 + engine.rng.randi_range(-1_000_000, 1_000_000)) % 1_000_000_007

	func state_hash() -> int:
		return draws * 1_000_003 + checksum

	func to_dict() -> Dictionary:
		return {"draws": draws, "checksum": checksum}

	func from_dict(state: Dictionary) -> void:
		draws = int(state.get("draws", 0))
		checksum = int(state.get("checksum", 1))


## Builds the standard two-system engine used by most tests here
## (registration order matters — always heartbeat, then probe).
func _build_engine(run_seed: int) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(RngProbeSystem.new())
	return engine


# --- Determinism ----------------------------------------------------------


func test_same_seed_same_commands_same_hash() -> void:
	var first := _build_engine(20260915)
	var second := _build_engine(20260915)
	# Identical command streams at identical tick boundaries.
	first.submit_command(&"ping", &"", 3)
	second.submit_command(&"ping", &"", 3)
	first.fast_forward(70)
	second.fast_forward(70)
	first.submit_command(&"ping", &"", 5)
	second.submit_command(&"ping", &"", 5)
	first.tick()
	second.tick()
	assert_int(first.state_hash()).is_equal(second.state_hash())
	assert_int(first.tick_count).is_equal(second.tick_count)
	# RNG streams identical too — same draws, same internal state.
	assert_int(first.rng.state).is_equal(second.rng.state)
	var probe_a := first.get_system(&"rng_probe") as RngProbeSystem
	var probe_b := second.get_system(&"rng_probe") as RngProbeSystem
	assert_int(probe_a.checksum).is_equal(probe_b.checksum)
	assert_int(probe_a.draws).is_equal(71)


func test_different_seed_different_hash() -> void:
	var first := _build_engine(20260915)
	var second := _build_engine(20260916)
	first.fast_forward(120)
	second.fast_forward(120)
	assert_int(first.rng.state).is_not_equal(second.rng.state)
	assert_int(first.state_hash()).is_not_equal(second.state_hash())


func test_hash_advances_with_state() -> void:
	var engine := _build_engine(7)
	var initial := engine.state_hash()
	engine.fast_forward(1)
	assert_int(engine.state_hash()).is_not_equal(initial)


# --- Tick boundary + command semantics ------------------------------------


func test_command_waits_for_next_tick_boundary() -> void:
	var engine := _build_engine(1)
	var heartbeat := engine.get_system(&"heartbeat") as HeartbeatSystem
	engine.submit_command(&"ping", &"", 3)
	# Queued but NOT applied before a tick runs.
	assert_int(heartbeat.pings).is_equal(0)
	assert_int(engine.pending_command_count()).is_equal(1)
	assert_int(engine.tick_count).is_equal(0)
	# Applied at the START of the next tick — visible to that tick's systems.
	engine.tick()
	assert_int(heartbeat.pings).is_equal(3)
	assert_int(engine.tick_count).is_equal(1)
	assert_int(engine.pending_command_count()).is_equal(0)
	engine.tick()
	assert_int(heartbeat.pings).is_equal(3) # no replay


func test_duplicate_system_registration_refused() -> void:
	var engine := SimEngine.new(1)
	assert_bool(engine.register_system(HeartbeatSystem.new())).is_true()
	assert_bool(engine.register_system(HeartbeatSystem.new())).is_false()
	assert_int(engine.system_count()).is_equal(1)


func test_hour_boundary_event_fires_exactly_on_the_hour() -> void:
	var engine := SimEngine.new(1)
	engine.register_system(HeartbeatSystem.new())
	engine.fast_forward(61)
	# Two hour boundaries struck (tick 60 and 120? no: 61 ticks -> one at 60).
	assert_int(engine.events.next_seq()).is_equal(1)
	var hour := engine.events.get_event(0)
	assert_that(hour).is_not_null()
	assert_int(hour.tick).is_equal(60)
	assert_str(String(hour.type)).is_equal("hour_struck")
	assert_int(hour.value).is_equal(1)


# --- Pause / resume --------------------------------------------------------


func test_pause_freezes_tick_and_fast_forward() -> void:
	var engine := _build_engine(5)
	engine.fast_forward(10)
	engine.pause()
	engine.pause() # idempotent
	var frozen := engine.state_hash()
	assert_bool(engine.tick()).is_false()
	assert_int(engine.fast_forward(100)).is_equal(0)
	assert_int(engine.tick_count).is_equal(10)
	assert_int(engine.state_hash()).is_equal(frozen)
	engine.resume()
	assert_bool(engine.tick()).is_true()
	assert_int(engine.tick_count).is_equal(11)


func test_command_submitted_during_pause_applies_on_first_resumed_tick() -> void:
	var engine := _build_engine(5)
	engine.pause()
	engine.submit_command(&"ping", &"", 2)
	engine.tick() # refused — command still queued
	var heartbeat := engine.get_system(&"heartbeat") as HeartbeatSystem
	assert_int(heartbeat.pings).is_equal(0)
	assert_int(engine.pending_command_count()).is_equal(1)
	engine.resume()
	engine.tick()
	assert_int(heartbeat.pings).is_equal(2)


func test_pause_changed_signal_only_on_transitions() -> void:
	var engine := SimEngine.new(1)
	var fired: Array[bool] = []
	engine.pause_changed.connect(func(is_paused: bool) -> void: fired.append(is_paused))
	engine.pause()
	engine.pause()
	engine.resume()
	engine.resume()
	assert_array(fired).is_equal([true, false])


# --- Fast-forward equivalence ----------------------------------------------


func test_fast_forward_equals_tick_loop() -> void:
	# A: one fast_forward(100) with a command injected at the halfway boundary.
	var looped := _build_engine(99)
	looped.submit_command(&"ping", &"", 4)
	for i in 50:
		looped.tick()
	looped.submit_command(&"ping", &"", 6)
	for i in 50:
		looped.tick()
	# B: the same 100 ticks in one fast_forward, same command boundaries.
	var skipped := _build_engine(99)
	skipped.submit_command(&"ping", &"", 4)
	skipped.fast_forward(50)
	skipped.submit_command(&"ping", &"", 6)
	skipped.fast_forward(50)
	assert_int(skipped.tick_count).is_equal(100)
	assert_int(looped.tick_count).is_equal(100)
	assert_int(skipped.state_hash()).is_equal(looped.state_hash())
	# Chunked fast-forward (25+25+50) is identical too.
	var chunked := _build_engine(99)
	chunked.submit_command(&"ping", &"", 4)
	chunked.fast_forward(25)
	chunked.fast_forward(25)
	chunked.submit_command(&"ping", &"", 6)
	chunked.fast_forward(50)
	assert_int(chunked.state_hash()).is_equal(looped.state_hash())


func test_fast_forward_zero_is_noop() -> void:
	var engine := _build_engine(3)
	var before := engine.state_hash()
	assert_int(engine.fast_forward(0)).is_equal(0)
	assert_int(engine.tick_count).is_equal(0)
	assert_int(engine.state_hash()).is_equal(before)


func test_fast_forwarded_signal_emits_once_per_call() -> void:
	var engine := SimEngine.new(1)
	var seen: Array[int] = []
	engine.fast_forwarded.connect(func(from_tick: int, to_tick: int) -> void:
		seen.append_array([from_tick, to_tick]))
	engine.fast_forward(10)
	engine.fast_forward(5)
	assert_array(seen).is_equal([0, 10, 10, 15])


# --- Event stream: live signal vs ring --------------------------------------


func test_live_tick_emits_event_signals_fast_forward_does_not() -> void:
	var engine := SimEngine.new(1)
	engine.register_system(HeartbeatSystem.new())
	var live_events: Array[int] = []
	engine.event_logged.connect(func(event: SimEvent) -> void: live_events.append(event.seq))
	for i in 60:
		engine.tick() # crosses one hour boundary -> one event, emitted live
	assert_array(live_events).is_equal([0])
	engine.fast_forward(600) # 10 more hour events into the ring, no signals
	assert_array(live_events).is_equal([0])
	assert_int(engine.events.next_seq()).is_equal(11)
	var last := engine.events.get_event(10)
	assert_that(last).is_not_null()
	assert_str(String(last.type)).is_equal("hour_struck")
	assert_int(last.value).is_equal(11)


func test_unhandled_command_recorded_as_rejected() -> void:
	var engine := SimEngine.new(1)
	engine.register_system(HeartbeatSystem.new())
	engine.submit_command(&"no_such_command", &"ghost", 1)
	engine.tick()
	assert_int(engine.events.next_seq()).is_equal(1)
	var rejected := engine.events.get_event(0)
	assert_str(String(rejected.type)).is_equal("command_rejected")
	assert_str(String(rejected.subject)).is_equal("no_such_command")
	assert_int(rejected.value).is_equal(1)


# --- Resources (int pool seam for T-SIM-02) ---------------------------------


func test_resource_pool_is_integer() -> void:
	var engine := SimEngine.new(1)
	assert_int(engine.get_resource(&"food")).is_equal(0)
	engine.add_resource(&"food", 6)
	engine.add_resource(&"food", 6)
	assert_int(engine.get_resource(&"food")).is_equal(12)
	engine.set_resource(&"timber", 3)
	assert_int(engine.get_resource(&"timber")).is_equal(3)
	# Resource contents and order-independence of hashing.
	var other := SimEngine.new(1)
	other.set_resource(&"timber", 3)
	other.set_resource(&"food", 12)
	assert_int(other.state_hash()).is_equal(engine.state_hash())


# --- Serialization hooks (save seam reserved for T-ARCH-03) ------------------


func test_state_round_trip_resumes_identically() -> void:
	var original := _build_engine(20260915)
	original.submit_command(&"ping", &"", 7)
	original.fast_forward(130)
	var captured := original.to_dict()
	assert_int(int(captured["format_version"])).is_equal(SimEngine.STATE_FORMAT_VERSION)

	var restored := _build_engine(20260915) # same systems, same order
	assert_bool(restored.apply_state_dict(captured)).is_true()
	assert_int(restored.tick_count).is_equal(130)
	assert_int(restored.rng.state).is_equal(original.rng.state)
	assert_int(restored.state_hash()).is_equal(original.state_hash())
	# Resume both: still lockstep.
	original.submit_command(&"ping", &"", 1)
	restored.submit_command(&"ping", &"", 1)
	original.fast_forward(25)
	restored.fast_forward(25)
	assert_int(restored.state_hash()).is_equal(original.state_hash())


func test_state_dict_pending_commands_survive_round_trip() -> void:
	var original := SimEngine.new(4)
	original.register_system(HeartbeatSystem.new())
	original.submit_command(&"ping", &"heartbeat", 9)
	var captured := original.to_dict()
	var restored := SimEngine.new(4)
	restored.register_system(HeartbeatSystem.new())
	restored.apply_state_dict(captured)
	assert_int(restored.pending_command_count()).is_equal(1)
	restored.tick()
	var heartbeat := restored.get_system(&"heartbeat") as HeartbeatSystem
	assert_int(heartbeat.pings).is_equal(9)


func test_apply_state_dict_refuses_wrong_format_loudly() -> void:
	var engine := SimEngine.new(4)
	engine.fast_forward(5)
	var before := engine.state_hash()
	var bad := {"format_version": SimEngine.STATE_FORMAT_VERSION + 99}
	assert_bool(engine.apply_state_dict(bad)).is_false()
	assert_int(engine.state_hash()).is_equal(before) # untouched


# --- Clock units -------------------------------------------------------------


func test_tick_units_are_sim_minutes() -> void:
	assert_int(SimEngine.TICK_SECONDS).is_equal(60)
	assert_int(SimEngine.TICKS_PER_SIM_HOUR).is_equal(60)
	var engine := SimEngine.new(1)
	engine.fast_forward(90)
	assert_int(engine.sim_minutes()).is_equal(90)
	assert_int(engine.sim_seconds()).is_equal(5400)
	assert_float(engine.sim_hours()).is_equal_approx(1.5, 0.0001)
