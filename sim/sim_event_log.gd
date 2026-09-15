## Allocation-light ring-buffer event stream for the engine (T-SIM-01).
##
## This is the change stream the future UI subscribes to (T-UI-03, T-UI-06).
## Design for 1000h scale (docs/sim-engine.md §3):
##   - a fixed-capacity ring of pooled SimEvent objects, allocated once;
##     recording MUTATES the oldest slot in place — zero steady-state
##   - readers address events by absolute `seq` and poll
##     (`next_seq()` / `get_event(seq)`), so a UI that fast-forwarded
##     behind can pull just the tail it missed
##   - the engine additionally emits `SimEngine.event_logged` per event
##     during LIVE ticks only (never during fast-forward) so a mounted UI
##     can react without polling; the ring is authoritative either way
##   - state_hash() deliberately ignores the log: it is presentation
##     history, not simulation state
class_name SimEventLog
extends RefCounted

const DEFAULT_CAPACITY: int = 4096

var _capacity: int
var _ring: Array[SimEvent] = []
var _next: int = 0  # events ever recorded == next seq


func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	assert(capacity >= 1, "SimEventLog capacity must be >= 1")
	_capacity = capacity
	_ring.resize(capacity)
	for i in capacity:
		_ring[i] = SimEvent.new()


## Records one event by mutating the pooled slot at `_next % capacity`.
## Overwrites (evicts) the oldest event once the ring is full.
func record(tick: int, type: StringName, subject: StringName = &"", value: int = 0, value2: int = 0) -> SimEvent:
	var event := _ring[_next % _capacity]
	event.seq = _next
	event.tick = tick
	event.type = type
	event.subject = subject
	event.value = value
	event.value2 = value2
	_next += 1
	return event


## Event by absolute seq, or null if not yet written or already evicted.
func get_event(seq: int) -> SimEvent:
	if seq < 0 or seq >= _next:
		return null
	if seq < oldest_seq():
		return null
	return _ring[seq % _capacity]


## Total events recorded so far (the seq the next record() will take).
func next_seq() -> int:
	return _next


## Seq of the oldest event still readable (events before it were evicted).
func oldest_seq() -> int:
	return maxi(0, _next - _capacity)


func capacity() -> int:
	return _capacity
