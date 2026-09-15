# Sim Engine — Castle Storm deterministic core (T-SIM-01)

The fixed-step deterministic economy engine: pure logic, no scene tree,
no timers, no wall clock. Everything the game *is* happens here; UI,
saving, and wall-clock drive are consumers.

- Code: `sim/sim_engine.gd` (core), `sim/sim_system.gd` (system base),
  `sim/sim_event_log.gd` + `sim/sim_event.gd` (event stream),
  `sim/sim_command.gd` (command), `sim/sim_fixed.gd` (fixed-point math),
  `sim/systems/heartbeat_system.gd` (placeholder system),
  `sim/systems/production_system.gd` (T-SIM-02 production, §10)
- Tests: `tests/unit/test_sim_engine.gd`, `tests/unit/test_sim_event_log.gd`,
  `tests/unit/test_sim_fixed.gd`, `tests/unit/test_production_system.gd`,
  acceptance marathons `tests/acceptance/suites/marathon_sim_1000h.gd`,
  `tests/acceptance/suites/marathon_production_1000h.gd`
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
command consumption, hash + save hooks. T-SIM-02's production system
(§10) registers alongside it as the first real system; heartbeat retires
when a real system covers its test role.

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
| T-SIM-02 production | `sim/systems/production_system.gd` (§10) — the seam + `SimFixed` + `resources` pool + `EconomyTunables` band, live since T-SIM-02 |
| T-SIM-03 training / T-SIM-05 suspicion / T-SIM-06 assault | systems + commands + events + per-tick timers in tick units |
| T-SIM-04 run lifecycle | `run_seed` → `rng` for randomized leaders/regimes; events for chronicle |
| T-SIM-07 catch-up | `fast_forward` (480 ticks = 8h cap) or linear accrual at the boundary; wall clock stays OUTSIDE sim |
| T-ARCH-03 save | `to_dict()/apply_state_dict()` + system save hooks |
| T-UI-03/06 The Spread | `event_logged` (live), `events` ring (post-ffwd tail), `pause_changed` |
| T-QA-02 economy CI | marathon pattern; asserts via `state_hash()` |

## 10. Production system (T-SIM-02)

`sim/systems/production_system.gd` (`ProductionSystem`, system_name
`&"production"`) — worker assignment → building rates → upgrade
multipliers for food/timber/iron. Constructed from content at boot:

```gdscript
var production := ProductionSystem.new(pack.buildings, pack.tunables, regime)
engine.register_system(production)  # registration order is part of the contract
```

`regime` is the run's RegimeDef (null = no quirk); only its
`economy_quirk` is read (`production_multiplier`, `building_cost_multiplier`
— target resource or `all`, e.g. timber ×0.85). All content floats cross
`SimFixed.milli_from_float` ONCE, in the constructor; everything after is
integer math (§2). The regime and defs are NOT serialized — same pack +
same regime at boot reproduces them; saves carry ids only.

### State model

- Buildings start at **level 0 = not yet built** (0 slots, 0 production).
  Upgrading 0→1 CONSTRUCTS the building for exactly `base_cost` and emits
  `building_built` — construction is the first upgrade.
- Per building: `level`, `assigned` (worker count), `accum` (SimFixed
  milli-unit-seconds remainder). Plus one global `workers_idle` pool.
- Workers are COUNT-level by design: T-SIM-03 feeds the pool with
  `add_worker`/`remove_worker` as recruits promote or scatter.

### Curves (all integer, in milli-space)

- **Upgrade cost** to reach level L (per resource line, ≥ 1, single
  floored division):
  `base_cost[res] × growth_milli[L] × milestone_milli[L] × cost_quirk / 10⁹`
  where `growth_milli` compounds `cost_growth` r per level (rescaled to
  milli each step — exact ints, never a float `pow`), and
  `milestone_milli` compounds `tunables.milestone_multiplier` once per
  milestone level ≤ L. The ×2 R4 milestone boosts therefore land AT
  levels 10/20 and stay compounded beyond (10 ≤ L < 20 pays ×2, L ≥ 20
  pays ×4) — per the T-SIM-02 contract and plan T-SIM-08's cost wording.
  Worked example (farm: timber 15, r=1.08, milestones [10, 20] ×2),
  locked verbatim by `test_upgrade_cost_curve_across_milestone_boundaries`:

  | to-level | 1 | 9 | 10 | 11 | 19 | 20 | 21 |
  |---|---|---|---|---|---|---|---|
  | timber | 15 | 27 | 59 | 64 | 119 | 257 | 278 |

- **Production** per worker per sim-hour at level L:
  `base_rate_milli × L × milestone_milli[L] × production_quirk / 10⁶`
  — linear in level and in workers (R4 §B production_shape), ×2 spike at
  each milestone (6/h at L1, 54/h at L9, **120/h at L10**, 480/h at L20).
  Per tick each producing building adds `rate × assigned × TICK_SECONDS`
  to its accumulator; whole units settle into `engine.resources`,
  remainders carry (never lost — the ×0.85 quirk at 5.1/h yields exactly
  5 units + 0.1 carried per hour, 51 exact after 10h).
- **Worker slots** at level L: `worker_slots_base + L − 1` for producing
  buildings (the T-SIM-02 slot curve; an additive schema field can make
  it data-driven later per content-schema §6). Non-producing buildings
  and level 0 have 0 slots.

### Commands (the only external writes; UI issues the same ones)

| Kind | Subject | Value | Effect |
|---|---|---|---|
| `add_worker` | `&"production"` | count | idle pool += count |
| `remove_worker` | `&"production"` | count | idle pool −= count (idle only) |
| `assign_worker` | building id | count | pool → building (all-or-nothing) |
| `unassign_worker` | building id | count | building → pool |
| `upgrade_building` | building id | — | pay next-level cost, level += 1 |

### Events (the UI's subscription surface)

`building_built`, `building_upgraded`, `building_milestone` (value=level,
value2=multiplier in milli), `worker_added`/`worker_removed` (value=new
idle), `worker_assigned`/`worker_unassigned` (value=new assigned,
value2=idle after), and denials `upgrade_denied`/`assignment_denied`/
`worker_pool_denied` with reason codes 1 unknown building, 2 not built,
3 max level, 4 unaffordable, 5 no idle workers, 6 no free slots,
7 not enough assigned, 8 invalid count (constants on ProductionSystem).

### Serialization + determinism

`to_dict()`/`from_dict()` are fully overridden (never the `{}` default):
`workers_idle` + one `{id, level, assigned, accum}` entry per building.
Round-trip is lockstep-hash-equal including carried remainders
(unit-tested; marathon re-proves at 1000h). `state_hash()` mixes only
the ints. Upgrades apply instantly at command drain (no build timer at
this stage — a timer would be a future system's per-tick countdown, not
a core change).

### Read API (for the UI; pure queries)

`idle_workers()`, `building_level(id)`, `assigned_workers(id)`,
`worker_slots(id)`, `production_rate_milli_per_worker(id)`,
`production_rate_milli(id)`, `accumulated_milli_unit_seconds(id)`
(progress-to-next-pip), `upgrade_cost(id)` (next level; empty at max).

Measured at 1000h: `marathon_production_1000h` — 60,000 ticks with 3
producing buildings + a 10h upgrade cadence in ~0.42s
(~144,000 ticks/s; the engine-only marathon holds ~1.67M ticks/s) —
~143× headroom under the 60s budget for the remaining T-SIM-03..08 weight.
