## One entry in the engine's change/event stream (T-SIM-01).
##
## Events are POOLED by SimEventLog: a fixed ring of these objects is
## allocated once per engine and reused in place, so streaming events for
## 3.6M ticks of fast-forward allocates nothing (docs/sim-engine.md §3).
## Consequence: a held SimEvent reference is only valid until its ring
## slot is overwritten (capacity more events) — UI code reads and copies,
## never caches.
class_name SimEvent
extends RefCounted

## Absolute sequence number since engine construction (monotonic; the
## engine resumes from this after fast-forward gaps).
var seq: int

## Tick the event was recorded during (1-based: the tick being processed).
var tick: int

## Event type identifier (e.g. `&"hour_struck"`, `&"command_rejected"`).
var type: StringName

## What the event is about (system/content id) or `&""`.
var subject: StringName

## Integer payload (primary).
var value: int

## Integer payload (secondary).
var value2: int


func _to_string() -> String:
	return "SimEvent#%d(tick=%d %s %s %d %d)" % [seq, tick, type, subject, value, value2]
