## Heartbeat — the placeholder system proving the registration seam (T-SIM-01).
##
## Deliberately trivial but not dead: it exercises every path later
## systems (T-SIM-02..08) will use, so the core contract is tested
## end-to-end from day one:
##   - on_tick: counts ticks, strikes `hour_struck` into the event ring
##     on every sim-hour boundary (tick % 60 == 0)
##   - on_command: consumes `ping` commands (`value` accumulates into
##     `pings`) — the full command -> state -> event -> hash path
##   - state_hash/to_dict/from_dict: the determinism-oracle and save hooks
##
## T-SIM-02+ replace nothing here — they register additional systems
## alongside it. Delete this system only when a real system has taken
## over its test role.
class_name HeartbeatSystem
extends SimSystem

const HOUR_TICKS: int = SimEngine.TICKS_PER_SIM_HOUR

var ticks: int = 0
var pings: int = 0


func system_name() -> StringName:
	return &"heartbeat"


func on_tick(engine: SimEngine) -> void:
	ticks += 1
	if ticks % HOUR_TICKS == 0:
		engine.events.record(
			engine.tick_count, &"hour_struck", &"sim", ticks / HOUR_TICKS
		)


func on_command(engine: SimEngine, command: SimCommand) -> bool:
	if command.kind == &"ping":
		pings += command.value
		engine.events.record(engine.tick_count, &"ping_counted", &"heartbeat", pings)
		return true
	return false


func state_hash() -> int:
	return ticks * 31 + pings


func to_dict() -> Dictionary:
	return {"ticks": ticks, "pings": pings}


func from_dict(state: Dictionary) -> void:
	ticks = int(state.get("ticks", 0))
	pings = int(state.get("pings", 0))
