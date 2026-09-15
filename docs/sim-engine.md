# Sim Engine — Castle Storm deterministic core (T-SIM-01)

The fixed-step deterministic economy engine: pure logic, no scene tree,
no timers, no wall clock. Everything the game *is* happens here; UI,
saving, and wall-clock drive are consumers.

- Code: `sim/sim_engine.gd` (core), `sim/sim_system.gd` (system base),
  `sim/sim_event_log.gd` + `sim/sim_event.gd` (event stream),
  `sim/sim_command.gd` (command), `sim/sim_fixed.gd` (fixed-point math),
  `sim/systems/heartbeat_system.gd` (placeholder system)
- Tests: `tests/unit/test_sim_engine.gd`, `tests/unit/test_sim_event_log.gd`,
  `tests/unit/test_sim_fixed.gd`, acceptance marathon
  `tests/acceptance/suites/marathon_sim_1000h.gd`
- Conventions: `docs/gdscript-conventions.md` (sim/ determinism rules)

## 1. Tick size: 1 tick = 1 sim-minute

`SimEngine.TICK_SECONDS = 60`; `TICKS_PER_SIM_HOUR = 60`. One tick is one
atomic engine transition — there is no sub-tick state.

Why a minute, not a second:

| Concern | 1-second tick | 1-minute tick (chosen) |
|---|---|---|
| 1000h fast-forward | 3.6M ticks × future systems (T-SIM-02..05: production, training, suspicion per tick) — GDScript cost stacks toward the CI 60s budget on slow runners | 60k ticks; measured **1.7M ticks/s** with two systems + per-tick RNG draws → 1000h in ~0.035s, ~1700x headroom before T-SIM-02+ add weight |
| Mechanic resolution | Finest tuned mechanic is suspicion decay 5/h (visible each 12 min); training 6–12h; telegraph ≥4h; catch-up cap 8h — everything is hour-scale | 1-minute is 60x finer than the finest mechanic |
| Offline catch-up (T-SIM-07) | 8h cap = 28,800 ticks to replay on foreground | 8h cap = 480 ticks (or linear accrual, even cheaper) |

All economy math stays in these units: rates are per-hour values converted
once to integer milli-units/hour (§2), and accrual happens per tick. A
finer tick can be layered later *without format breakage* by re-deriving
rates — the contract is the tick count, not the wall second.

## 2. Determinism contract

**Oracle:** identical construction (same systems, same registration order)
+ same run seed + same commands between the same ticks + same tick count
⟹ identical `state_hash()`. Tested at 1000h scale in the marathon suite.

Rules the contract rests on:

1. **Integer core.** Resources, timers, suspicion are integers. Content
   floats (rates per hour, multipliers) cross ONE boundary:
   `SimFixed.milli_from_float()` (IEEE `x*1000` + `round`, platform-stable —
   0.85 → 850 everywhere). After that, accrual is exact integer math in
   milli-units×seconds (`SimFixed.accrue`): 6/hour is exactly 6 units after
   60 ticks with zero remainder — no truncation drift, no float ordering
   assumptions. Locked by `tests/unit/test_sim_fixed.gd` (incl. the ×0.85
   regime-quirk case: remainders carry, never lost).
2. **Single seeded RNG per engine.** `SimEngine.rng`, seeded from
   `run_seed` at construction. Systems may draw ONLY inside `on_tick` /
   `on_command` (never `on_register` — registration sites may vary). Draw
   order is fixed by system registration order, so the stream — and
   `rng.state`, which is hashed — is reproducible.
3. **Fixed system order.** Systems tick in registration order; commands
   dispatch in registration order, first `true` wins. Two engines must
   register the same systems in the same order (asserted by tests, enforced
   by construction sites).
4. **Commands are tick-aligned.** `submit_command()` queues FIFO; the queue
   drains at the START of the next processed tick. Same commands between
   the same ticks ⟹ same application points, on every machine.
5. **Hash algorithm.** `state_hash()` mixes ONLY integers + Godot's stable
   `String.hash()` for ids, through an FNV-flavored multiply/xor kept
   inside 32 bits per step (`SimEngine._mix`) — both halves of every 64-bit
   value folded in, no signed-overflow anywhere, no float formatting. The
   event ring is deliberately NOT hashed: it is presentation history, not
   simulation state (live-ticking and fast-forwarding produce identical
   hashes — proven by the ffwd-equivalence test).

## 3. Event stream (change log)

`SimEngine.events` — a `SimEventLog`: fixed-capacity ring (default 4096) of
POOLED `SimEvent` objects allocated once per engine. Recording mutates a
slot in place: steady-state allocation is zero, so streaming through
millions of ticks costs nothing and the log stays bounded.

- **Pull (authoritative):** UI polls `events.next_seq()` /
  `get_event(seq)`; evicted events return null (`oldest_seq()` marks the
  frontier). A UI that fast-forwarded behind reads just the tail it missed.
- **Push (live only):** `SimEngine.event_logged(event)` fires per event
  during `tick()`, NEVER during `fast_forward()` — a 60k-tick catch-up
  emits one `fast_forwarded(from, to)` signal instead of a signal storm.
- **Pooled-object caveat:** a held `SimEvent` reference is valid only until
  its slot is overwritten — read and copy, never cache.
- Unhandled commands are recorded as `command_rejected` events (and
  push_warning'd) — loud, inspectable, deterministic.

## 4. Systems (the seam T-SIM-02..08 build on)

A system is any `SimSystem` subclass registered via
`engine.register_system()`; the core never changes to add one. The
contract: `system_name()` (unique, stable — it is the serialization key),
`on_tick(engine)` (advance; the only RNG draw site), `on_command(engine,
command) -> bool` (consume or pass), `state_hash()` (int over
gameplay-visible state), `to_dict()/from_dict()` (save hooks).

`sim/systems/heartbeat_system.gd` is the placeholder proving every path
end-to-end: hour-boundary `hour_struck` events from `on_tick`, `ping`
command consumption, hash + save hooks. T-SIM-02 (production) registers
its system alongside; when a real system covers the same test role,
heartbeat retires.

Typical system pattern (T-SIM-02 shape):

```gdscript
var _accum := 0  # SimFixed milli-units x seconds

func on_tick(engine: SimEngine) -> void:
    _accum = SimFixed.accrue(_accum, _rate_milli_per_hour)  # int, exact
    var units := SimFixed.whole_units(_accum)
    if units > 0:
        _accum -= units * SimFixed.UNIT_ACCUM
        engine.add_resource(&"food", units)
```

## 5. Commands

`submit_command(kind, subject, value)` — the ONLY external write path into
the simulation (UI sends commands down; state flows up via events —
`docs/gdscript-conventions.md`). Queued FIFO, drained at tick start,
dispatched to systems in registration order. While paused, commands queue
and apply on the first resumed tick.

## 6. Pause / resume

`pause()` freezes advancement: `tick()` returns false, `fast_forward()`
returns 0, `tick_count` — and therefore the state hash modulo the paused
bit — stands still. `resume()` restores advancement. Both idempotent;
`pause_changed` fires only on transitions.

## 7. Serialization hooks (reserved for T-ARCH-03)

`to_dict()` captures the whole engine — core scalars, RNG state, command
queue, resources, one sub-dict per system (keyed by `system_name`).
`apply_state_dict()` restores into an engine that has the same systems
registered; `STATE_FORMAT_VERSION` gates it loudly (refuse, never
half-apply). The event ring is not serialized (presentation). Proven by
the round-trip unit test: capture at t=130, restore, resume — lockstep
hashes from there on.

## 8. Fast-forward + measured performance

`fast_forward(n)` runs n ticks back-to-back with zero per-tick signals
(events still land in the bounded ring). Equivalence with the live loop is
a unit-test invariant (`ffwd(100) == 100 × tick()`, including chunked
variants and mid-run command injection).

Measured (vendored 4.7.2 binary, Apple silicon, this repo's CI command):

- `tests/acceptance/suites/marathon_sim_1000h.gd`: 60,000 ticks
  (1000 sim-hours) with 2 systems + per-tick RNG draws + mid-run commands
  → **0.035s wall, ~1,714,000 ticks/s (~28,600 sim-hours/s)** — vs the
  60s budget: ~1700x headroom for T-SIM-02..08 system weight and slow CI
  runners. The suite asserts the budget, the determinism oracle (same
  seed twice → same hash; different seed → different), and prints the
  rate + hash into the CI report.

## 9. Consumer map

| Consumer | What it uses |
|---|---|
| T-SIM-02 production | systems + `SimFixed` + `resources` pool + `EconomyTunables` band |
| T-SIM-03 training / T-SIM-05 suspicion / T-SIM-06 assault | systems + commands + events + per-tick timers in tick units |
| T-SIM-04 run lifecycle | `run_seed` → `rng` for randomized leaders/regimes; events for chronicle |
| T-SIM-07 catch-up | `fast_forward` (480 ticks = 8h cap) or linear accrual at the boundary; wall clock stays OUTSIDE sim |
| T-ARCH-03 save | `to_dict()/apply_state_dict()` + system save hooks |
| T-UI-03/06 The Spread | `event_logged` (live), `events` ring (post-ffwd tail), `pause_changed` |
| T-QA-02 economy CI | marathon pattern; asserts via `state_hash()` |
