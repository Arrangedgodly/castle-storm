## One injected player/UI command for the deterministic engine (T-SIM-01).
##
## Commands are the only way state outside the tick loop reaches the
## simulation. They queue FIFO on the engine (`SimEngine.submit_command`)
## and are drained in order at the START of the next processed tick, then
## dispatched to systems in registration order — so "identical seed +
## identical tick count + identical injected commands" is a total order
## and yields identical state (docs/sim-engine.md §2).
##
## Allocation note: one small object per command is fine — commands are
## human-rate input, unlike the per-tick event stream, which is pooled
## (SimEventLog).
class_name SimCommand
extends RefCounted

## Command kind identifier (e.g. `&"assign_worker"`, `&"ping"`). Kinds are
## owned by the systems that handle them; T-SIM-02+ define their own.
var kind: StringName

## What the command applies to (unit id, building id, ...). Free-form.
var subject: StringName

## Integer payload (slot index, amount, choice index, ...). Systems that
## need fractional amounts convert at their boundary via SimFixed.
var value: int


func _init(p_kind: StringName = &"", p_subject: StringName = &"", p_value: int = 0) -> void:
	kind = p_kind
	subject = p_subject
	value = p_value
