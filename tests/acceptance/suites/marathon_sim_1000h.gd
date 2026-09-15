## Acceptance marathon — 1000 sim-hours fast-forward (T-SIM-01).
##
## The economy-engine smoke at scale: from a seeded minimal state, run
## 1000 sim-hours (60,000 one-minute ticks) through fast_forward and
## assert the determinism oracle; record the measured ticks/sec rate
## into the run report (target: 1000h in well under 60s of pure logic —
## this suite exists precisely because gdUnit4 would timeout-own it).
##
## Full economy marathons (production, victory arcs) extend this pattern
## in T-QA-02; this suite pins the ENGINE contract those runs rely on.
extends RefCounted

const SIM_HOURS := 1000
const RUN_SEED := 20260915
const BUDGET_SECONDS := 60.0


## Deterministic RNG consumer: proves rng draw order + state survive the
## full marathon inside the state hash (same idea as the unit suite's
## RngProbeSystem, kept local so the marathon is self-contained).
class ProbeSystem extends SimSystem:
	var draws: int = 0
	var checksum: int = 1

	func system_name() -> StringName:
		return &"probe"

	func on_tick(engine: SimEngine) -> void:
		draws += 1
		checksum = (checksum * 31 + engine.rng.randi_range(-1_000_000, 1_000_000)) % 1_000_000_007

	func state_hash() -> int:
		return draws * 1_000_003 + checksum


func suite_name() -> String:
	return "marathon_sim_1000h"


func run(harness) -> void:
	var total_ticks := SIM_HOURS * SimEngine.TICKS_PER_SIM_HOUR

	# --- Run 1: timed fast-forward with mid-run command injections.
	var first := _build(RUN_SEED)
	first.submit_command(&"ping", &"", 7)
	var clock_start := Time.get_ticks_msec()
	var ran := first.fast_forward(total_ticks / 2)
	first.submit_command(&"ping", &"", 5)
	ran += first.fast_forward(total_ticks - ran)
	var wall := float(Time.get_ticks_msec() - clock_start) / 1000.0
	var rate := float(total_ticks) / wall

	# Rate evidence line (lands in the CI log / report).
	print(
		"[marathon_sim_1000h] %d ticks (%d sim-hours) in %.3fs — %.0f ticks/s, %.1f sim-hours/s; state_hash=%d"
		% [total_ticks, SIM_HOURS, wall, rate, float(SIM_HOURS) / wall, first.state_hash()]
	)

	harness.check(ran == total_ticks, "fast_forward ran all %d ticks" % total_ticks)
	harness.check(first.tick_count == total_ticks, "tick_count == %d" % total_ticks)
	harness.check(first.sim_minutes() == total_ticks, "sim_minutes == %d" % total_ticks)
	harness.check(wall < BUDGET_SECONDS, "1000h in < %.0fs (took %.3fs)" % [BUDGET_SECONDS, wall])

	# --- Run 2: same construction, same seed, same commands at the same
	# boundaries — must reproduce the identical state hash.
	var second := _build(RUN_SEED)
	second.submit_command(&"ping", &"", 7)
	second.fast_forward(total_ticks / 2)
	second.submit_command(&"ping", &"", 5)
	second.fast_forward(total_ticks / 2)
	harness.check(first.state_hash() == second.state_hash(), "same seed + commands -> same 1000h state hash")
	harness.check(first.rng.state == second.rng.state, "rng state identical after 60k draws")

	# --- Run 3: one seed step away — must diverge.
	var third := _build(RUN_SEED + 1)
	third.submit_command(&"ping", &"", 7)
	third.fast_forward(total_ticks)
	harness.check(first.state_hash() != third.state_hash(), "different seed -> different hash")

	# --- State actually advanced and systems ran to the end.
	harness.check(first.state_hash() != _build(RUN_SEED).state_hash(), "1000h hash differs from t=0")
	var probe := first.get_system(&"probe") as ProbeSystem
	harness.check(probe != null and probe.draws == total_ticks, "probe system drew exactly once per tick")
	var heartbeat := first.get_system(&"heartbeat") as HeartbeatSystem
	harness.check(heartbeat.pings == 12, "both injected pings applied (7 + 5)")
	harness.check(first.sim_hours() == float(SIM_HOURS), "sim_hours() == 1000.0")
	var last_event := first.events.get_event(first.events.next_seq() - 1)
	harness.check(last_event != null and last_event.type == &"hour_struck" and last_event.value == SIM_HOURS, "final ring event is hour_struck #1000")


func _build(run_seed: int) -> SimEngine:
	var engine := SimEngine.new(run_seed)
	engine.register_system(HeartbeatSystem.new())
	engine.register_system(ProbeSystem.new())
	return engine
