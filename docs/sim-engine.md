# Sim Engine — Castle Storm deterministic core (T-SIM-01)

The fixed-step deterministic economy engine: pure logic, no scene tree,
no timers, no wall clock. Everything the game *is* happens here; UI,
saving, and wall-clock drive are consumers.

- Code: `sim/sim_engine.gd` (core), `sim/sim_system.gd` (system base),
  `sim/sim_event_log.gd` + `sim/sim_event.gd` (event stream),
  `sim/sim_command.gd` (command), `sim/sim_fixed.gd` (fixed-point math),
  `sim/run_meta.gd` (T-SIM-04 meta bank, §12),
  `sim/systems/heartbeat_system.gd` (placeholder system),
  `sim/systems/production_system.gd` (T-SIM-02 production, §10),
  `sim/systems/unit_lifecycle_system.gd` (T-SIM-03 units, §11),
  `sim/systems/run_lifecycle_system.gd` (T-SIM-04 run lifecycle, §12)
- Tests: `tests/unit/test_sim_engine.gd`, `tests/unit/test_sim_event_log.gd`,
  `tests/unit/test_sim_fixed.gd`, `tests/unit/test_production_system.gd`,
  `tests/unit/test_unit_lifecycle_system.gd`,
  `tests/unit/test_run_lifecycle_system.gd`,
  acceptance marathons `tests/acceptance/suites/marathon_sim_1000h.gd`,
  `tests/acceptance/suites/marathon_production_1000h.gd`,
  `tests/acceptance/suites/marathon_units_1000h.gd`,
  `tests/acceptance/suites/marathon_run_thin_loop.gd`
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

## 7. Serialization hooks (persisted by T-ARCH-03)

`to_dict()` captures the whole engine — core scalars, RNG state, command
queue, resources, one sub-dict per system (keyed by `system_name`).
`apply_state_dict()` restores into an engine that has the same systems
registered; `STATE_FORMAT_VERSION` gates it loudly (refuse, never
half-apply). The event ring is not serialized (presentation). Proven by
the round-trip unit test: capture at t=130, restore, resume — lockstep
hashes from there on.

T-ARCH-03 composes these hooks into the on-disk save format:
`sim/save_manager.gd` (SaveManager) wraps the dict in a versioned,
checksummed envelope, writes atomically (temp + rename), rotates 3 run
slots, and keeps the meta domain (RunMeta) in its own file. The full
contract — 64-bit-exact RNG encoding, canonical checksum, quarantine and
migration registry — is documented in `docs/save-format.md`; the 500h
disk round-trip (including `rng_state` bit-exactness and continuation
lockstep across the restart seam) is proven by
`tests/acceptance/suites/save_marathon_roundtrip.gd`.

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
| T-SIM-03 units | `sim/systems/unit_lifecycle_system.gd` (§11) — arrivals draw `rng` in `on_tick`, worker handoff rides the command queue, training/gear state in the save hooks |
| T-SIM-05 suspicion / T-SIM-06 assault | systems + commands + events + per-tick timers in tick units; suspicion keys off `training_complete` subjects (UnitDef.suspicion_on_train) and `building_upgraded`; assault reads `army_power()`/`gear_tier()` and resolves through `RunLifecycleSystem.resolve_victory` (§12) |
| T-SIM-04 run lifecycle | `sim/systems/run_lifecycle_system.gd` (§12) — `run_seed` → `rng` for randomized leaders/regimes drawn at the run_start/restart drains; events for chronicle; meta bank in `sim/run_meta.gd` |
| T-SIM-07 catch-up | `fast_forward` (480 ticks = 8h cap) or linear accrual at the boundary; wall clock stays OUTSIDE sim |
| T-ARCH-03 save | `to_dict()/apply_state_dict()` + system save hooks |
| T-UI-03/06 The Spread | `event_logged` (live), `events` ring (post-ffwd tail), `pause_changed` |
| T-SCOPE-01 gate / any UI-CLI host | the command queue as the ONE write entry point + read APIs + both event feeds — the full contract is proven by `tests/acceptance/suites/gate_m1_thin_loop.gd` (§13) |
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
integer math (§2). The defs are NOT serialized — same pack at boot
reproduces them, saves carry ids only. The APPLIED quirk multipliers ARE
serialized + hashed state (T-ARCH-03 verifier fix): `from_dict` runs with no
`run_start` drain to re-apply a regime, so a save made under a quirked regime
must carry the quirk itself or the restored economy silently resumes under
identity multipliers and diverges on the first tick.

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
`workers_idle` + one `{id, level, assigned, accum}` entry per building + the
applied `regime_quirks` multipliers (`prod_all_milli`, per-resource
`prod_milli`, `cost_all_milli`, per-resource `cost_milli` — the effective
economy config, restored verbatim by `from_dict`; a dict WITHOUT the key is
a pre-fix save and keeps the constructed regime). Round-trip is
lockstep-hash-equal including carried remainders (unit-tested for all four
quirk flavors with an upgrade issued during continuation; the save marathon
re-proves it across the disk boundary per regime). `state_hash()` mixes only
ints — workers, buildings, AND the applied quirk multipliers: an oracle
blind to the economy config called a quirk-losing restore "identical" (the
T-ARCH-03 verifier FAIL), so the multipliers are hashed state now. Upgrades
apply instantly at command drain (no build timer at this stage — a timer
would be a future system's per-tick countdown, not a core change).

### Read API (for the UI; pure queries)

`idle_workers()`, `building_level(id)`, `assigned_workers(id)`,
`worker_slots(id)`, `production_rate_milli_per_worker(id)`,
`production_rate_milli(id)`, `accumulated_milli_unit_seconds(id)`
(progress-to-next-pip), `upgrade_cost(id)` (next level; empty at max).

Measured at 1000h: `marathon_production_1000h` — 60,000 ticks with 3
producing buildings + a 10h upgrade cadence in ~0.42s
(~144,000 ticks/s; the engine-only marathon holds ~1.67M ticks/s) —
~143× headroom under the 60s budget for the remaining T-SIM-03..08 weight.

## 11. Unit lifecycle system (T-SIM-03)

`sim/systems/unit_lifecycle_system.gd` (`UnitLifecycleSystem`, system_name
`&"units"`) — recruit arrival, role assignment, training timers, gear
requirements and promotion to the knight/archer branches, all data-driven
from `UnitDef`/`GearDef`/`EconomyTunables`. Constructed from content at
boot and registered alongside production (order: heartbeat, units,
production — mirrors causality; only the ordering *consistency* is
contractual):

```gdscript
var units := UnitLifecycleSystem.new(pack.units, pack.gear, pack.tunables)
engine.register_system(units)
```

### Lifecycle

```
recruit_arrived (RNG cadence)      stable: offers wait at the gate, never expire
  -> recruit_accept                peasant joins (the base unit)
  -> assign_role worker|militia    starts that def's training timer
       worker  (0.5h ex.)  -> unit_promoted + add_worker into production's pool
       militia (2h)        -> unit_promoted (resting militia)
  -> start_training trainee        militia -> trainee (4h)
  -> start_training knight|archer  trainee -> branch (12h / 6h)
       training_complete (held)    STABLE: trainee awaiting gear + promote
  -> equip_gear (per required slot, any tier; pays the GearDef recipe)
  -> promote                       knight / archer — counts on the army roster
```

- **Every hop is explicit** — no auto-advance: the player issues
  `assign_role` for the peasant's branch, `start_training` for each later
  hop (one command kind per semantic step; both funnel into the same
  promotion-start path). Zero-hour targets complete within the same
  command drain.
- **Gear gating**: promotion into a def with `required_gear_slots`
  (knight: weapon+armor; archer: weapon) REQUIRES training complete +
  every required slot equipped, any tier (top tier NOT required — tiers
  are recorded per unit as slot→gear-id and feed T-SIM-06 odds). An
  unequipped trainee awaiting gear is a stable state, not an error;
  `promote` without gear is refused LOUDLY (`lifecycle_denied`,
  `REASON_GEAR_INCOMPLETE`). Gear-free ranks (worker, militia, trainee)
  promote automatically when the timer runs out.
- **Gear rules**: `equip_gear` pays the recipe from `resources`
  (all-or-nothing); a slot may be filled only where the unit's current
  def or training target requires it (choose the branch, then gear up);
  re-equipping requires a strictly higher tier (tier refits). Craft
  timers (GearDef.craft_time_hours) are a future smithy system's per-tick
  countdown, not a core change — equip is instant at command drain.
- **Army roster**: terminal combat units (combat_power > 0 and no
  promotion_paths — knight/archer; militia/trainee excluded).
  `army_power()` = Σ (def.combat_power + equipped gear combat_power).
- **Worker handoff**: worker promotion submits `add_worker` to
  production through the same command queue the UI uses — drained at the
  next tick's start, one tick after the promotion. Identity mapping
  lives here (worker units stay tracked); counts live in production.

### Arrival cadence (interpretation choice, documented)

Arrivals are a **tunable, not per-regime data**:
`EconomyTunables.recruit_arrival_interval_hours` (default 2.0) +
`recruit_arrival_jitter_hours` (default 0.25, ±). Each interval is drawn
from `engine.rng` INSIDE `on_tick` (the only sanctioned draw site) —
identical seeds produce identical arrival sequences (unit- and
marathon-tested); jitter 0 is a metronome that draws nothing (rng.state
frozen). The first tick schedules, so the first arrival lands at
~interval+1 tick. Per-regime cadence can arrive later as an additive
`RegimeModifier` kind (content-schema §4 registry is forward-compatible)
if design wants flavor-differentiated gates; the tunable keeps T-SIM-08's
simulator in control at MVP. Recruit tolerance pressure (too many
recruits) is T-SIM-05's suspicion concern — the gate itself is uncapped.

### Timers (integer, milli-ticks)

`training_time_hours` crosses `SimFixed.milli_from_float` ONCE at
construction, × 60 → duration in **milli-ticks**; each tick adds
`SimFixed.MILLI` (1000) to the trainee's progress; completion when
progress ≥ duration. 0.5h/2h/4h/6h/12h are exactly 30/120/240/360/720
ticks — no truncation at the schema's hour granularity. Progress is
visible two ways: the read API (`training_progress_milli` /
`training_duration_milli` — exact, for meters) and
`training_progress` events at each quarter crossing (250/500/750
permille) — bounded per training, never per-tick spam.

### Commands and events

| Command | Subject | Value | Effect |
|---|---|---|---|
| `recruit_accept` | — | offer uid | offer → peasant |
| `assign_role` | target def id | unit uid | peasant branch choice (worker/militia) |
| `start_training` | target def id | unit uid | any later hop (trainee, knight/archer) |
| `equip_gear` | gear id | unit uid | pay recipe, fill slot (tier-up replaces) |
| `promote` | — | unit uid | held trainee → knight/archer |

Events (subject = content id, value = unit uid unless noted):
`recruit_arrived` (value2 = pending offers), `recruit_accepted`
(value2 = base-def count), `training_started` (value2 = duration in
milli-ticks), `training_progress` (value2 = permille), `training_complete`
(value2 = 1 held-for-gear / 0 auto-promoted; subject resolves
`UnitDef.suspicion_on_train` for T-SIM-05), `gear_equipped`
(subject = gear id, value2 = tier), `unit_promoted` (value2 = new-def
count), and `lifecycle_denied` (value = reason code 1–13, value2 = uid;
constants on UnitLifecycleSystem — unknown unit/recruit/gear/target,
invalid target, already training, awaiting promotion, slot not needed,
slot occupied, unaffordable, not awaiting promotion, training
incomplete, gear incomplete).

### Serialization + determinism

`to_dict()`/`from_dict()` fully overridden: uid counter, arrival
countdown + arrivals_total, pending offers, one entry per unit
(`{uid, def, target, progress, awaiting, gear}` — ids only, gear as
slot→gear-id). Round-trip is lockstep-hash-equal with in-flight training
timers and partial gear (unit-tested; the marathon re-proves at 500h
scale). Unknown defs skip the unit loudly; an unknown training target
drops the training (unit survives, resting); unknown gear ids are
dropped — same pack at boot reproduces defs, exactly like production.
`state_hash()` mixes the ints + `String.hash()` of def/gear ids. The
engine serializes `rng.state`, so the jittered arrival stream continues
identically after restore.

### Read API (for the UI; pure queries)

`pending_offers()`, `offer_ids()`, `unit_ids()`, `unit_count(id)`,
`total_units()`, `unit_def(uid)`, `training_target(uid)`,
`training_progress_milli(uid)`, `training_duration_milli(id)`,
`is_awaiting_promotion(uid)`, `unit_gear(uid)`, `gear_tier(uid, slot)`,
`missing_gear_slots(uid)`, `idle_units(id)`,
`awaiting_promotion_ids()`, `army_roster()`, `army_power()`,
`gear_ids_for_slot(slot)` (tier-sorted), `arrivals_total`.

Measured at 1000h: `marathon_units_1000h` — 60,000 ticks of the full
stack (heartbeat + units + production; 498 arrivals, 385 workers, 50
knights + 50 archers promoted with paid gear, army power 1150, a 10h
management cadence, and a 500h save round-trip) in ~0.31s
(~190,000 ticks/s; hash 191601477, reproduced identically across
processes). The engine-only marathon still holds ~1.67M ticks/s
(hash 3567881493) and the production marathon ~143k ticks/s
(hash 2971927959) — both byte-identical to their T-SIM-01/02 records:
T-SIM-03 added zero core drag.

## 12. Run lifecycle system (T-SIM-04)

`sim/systems/run_lifecycle_system.gd` (`RunLifecycleSystem`, system_name
`&"run"`) — randomized leader/regime generation at run start,
victory/failure resolution, restart with a new identity, chronicle
entries and the meta bank reserve. Constructed from content at boot and
registered with the stack (order used by the marathons: heartbeat, run,
units, production — the run frame exists before the recruits/economy it
governs; only ordering consistency is contractual):

```gdscript
var meta := RunMeta.new()                  # or one restored from the meta save
var run := RunLifecycleSystem.new(pack.regimes, pack.identity, meta)
engine.register_system(run)
```

### Generation (engine RNG, drawn at the command drains)

`run_start` draws, in this fixed order, from `engine.rng` inside
on_command (the only sanctioned draw site): leader first name
(IdentityPools), epithet, personality tag, a second DISTINCT tag (draw
over the n−1 others — uniform, no redraw loop, constant draw count),
a trait-stub index (4 code-side placeholder labels pending T-COPY-01),
and finally the regime (uniform over the pack's flavors). Identical seed
+ identical command timing ⟹ identical identities and identical
`rng.state` (unit-tested at 100-leader scale and in the thin-loop
replay). The regime is exposed whole (`current_regime()`) for later
systems — T-SIM-06 reads its `combat_modifier`; production's economy
quirk is applied at the SAME drain through `set_regime` (the T-SIM-02
handoff: production is constructed before the regime exists, so the
quirk lands the moment the draw does — 6/h × 0.85 becomes exactly
5,100 milli/h at the drain tick).

### Run frame, victory and failure

| Command | Effect |
|---|---|
| `run_start` | draw identity + regime, UNSTARTED → RUNNING, `run_started` (subject = regime id, value = run index) |
| `run_abort` | explicit surrender — the THIN failure path (suspicion failure is T-SIM-05); banks + `run_aborted` |
| `run_restart` | fold a new identity, reset run-scoped state (below), `run_restarted` |
| `resolve_victory` | internal (queued by the entry point, below); subject `&"win"`/`&"loss"`, value = army power override |

`resolve_victory(engine, win, army_power = -1)` is the assault-outcome
entry point: T-SIM-06 (which owns the odds) calls it with its result; -1
reads the units system's live `army_power()` at drain. It is
tick-aligned like every write: it pre-checks (loud `false` when no run
is active) and queues the resolution command, which drains at the next
tick. Resolution banks the run into RunMeta and emits `run_won` /
`run_lost` (value = banked score, value2 = run index).

**Failure banks FULL progress** (town-hall decision): every ended run
accrues — victory, assault loss, abort, and a still-running run that
gets restarted (auto-resolved as abandoned). Thin score stub, T-SIM-08
owns the real curve: `score = duration_hours + army_power + 100
(victory only)`.

### The reset contract (documented choice)

Restart is **in-engine, command-driven, orchestrated by the run system**
— not an engine re-init. At the `run_restart` drain it: (1) auto-banks a
running run as abandoned; (2) zeroes the engine resource pool
(run-scoped); (3) resets sibling systems SYNCHRONOUSLY via the
`reset_run(regime)` seam — systems that own run-scoped state implement
it (production: buildings unbuilt, no workers, no remainders, new
regime quirk applied; units: roster/gate/counters cleared, next tick
re-schedules the first arrival like boot). Direct synchronous calls, no
queued reset commands, because a restart must be atomic within one tick
(no half-reset overlap) — the same reasoning as T-SIM-03's queue
handoff, which HAD to queue because it fires mid-tick. Absent siblings
are skipped (`has_method` guard — an engine without production is
legitimate); T-SIM-05's suspicion system joins the reset list when it
lands. The alternative (host-side engine re-init) remains available and
is the same contract one level up: build a fresh engine and hand it the
SAME RunMeta instance — the unit tests prove both forms.

### Regime rule across restarts (town-hall journeys 4/5)

Defeat/abort restarts under the SAME regime (the regime survived you);
victory redraws it (you became the new regime — flavor-only at MVP, the
L2 escalation snapshot is the post-MVP deepening). The identity is
always freshly drawn; the regime draw happens only on start and
victory-restarts, so the RNG stream shape is fixed per transition.

### Meta domain separation (RunMeta)

`sim/run_meta.gd` (`RunMeta`) holds `legacy_points`, `runs_recorded`
(the chronicle's monotonic run number — engine-local run indexes reset
with a re-init) and the append-only `chronicle` (one JSON-safe entry
per ended run: `{run, leader, tags, trait, regime, outcome,
duration_ticks, army_power, army, score}`). It lives in the META save
domain: the run system's engine-side `to_dict()`/`state_hash()`
deliberately EXCLUDE it — a run-save restore can neither fork nor
rewind the bank, and two engines with the same seed hash identically
regardless of carried-over meta (unit-tested both ways). RunMeta has its
own `to_dict()/apply_dict()` with a version refusal mirroring the
engine's; T-ARCH-03 persists it in the separate meta slot and hands the
same instance to every engine. No spending exists yet — the L1 unlock
tree is post-MVP by the layer gate.

### Events and read API

Events: `run_started`, `run_restarted` (value2 = previous outcome),
`run_won`, `run_lost`, `run_aborted` (value = banked score, value2 =
run index), `run_denied` (reasons 1 already started, 2 not started,
3 not running, 4 no content). Read API: `is_running()`, `run_status()`,
`current_run_index()`, `run_outcome()`, `last_run_score()`,
`run_start_tick()`, `run_end_tick()`, `leader_name()`,
`leader_first_name()`, `leader_epithet()`, `leader_tags()`,
`leader_trait_stub()`, `leader_trait_label()`, `current_regime()`,
`regime_id()`, `meta`. Serialization: ids + ints only (leader strings,
trait index, regime id resolved from the pack at boot — unknown id
warns and runs regime-less); round-trip is lockstep-hash-equal mid-run
and across a restart (unit- and marathon-tested).

Measured: `marathon_run_thin_loop` — three full runs in 16,204 ticks
(270h) in ~0.06s (~250–280k ticks/s across runs; hash 1951872722).
Run 1 recruits/produces/trains/gears/promotes to the 100-power line in
exactly 9,000 ticks (150h), wins, and banks 365 lp (150h + 115 power +
100 bonus; chronicle snapshots 5 knights + 5 archers); run 2 restarts
under a fresh identity (the redrawn regime slot happened to hold the
same flavor) with emptied state, rebuilds, produces +1,200 food over
100h under the restarted economy, loses, banks 100 lp; run 3 folds a
third identity and save-round-trips both domains mid-run (engine
lockstep hash + meta dict). The replay is deterministic — identical
identities, bank, and hash. This pre-stages the T-SCOPE-01 thin-loop
gate. The engine/production/units marathons all held their
T-SIM-01/02/03 hashes byte-identically — the run frame adds no per-tick
cost (on_tick is empty; all work is at command drains).

## 13. M1 thin-loop gate (T-SCOPE-01) — the UI-seam contract

`tests/acceptance/suites/gate_m1_thin_loop.gd` formalizes the M1
milestone gate: the whole loop (recruit → assign → train/gear →
assault → restart, twice — victory then defeat) driven exactly the way
a future UI/CLI host must drive it. The contract it proves, and that
T-UI-03..10 and any future CLI should treat as binding:

- **Writes**: ONE entry point — `engine.submit_command(kind, subject,
  value)`. The assault is the raw `resolve_victory` command (what
  T-SIM-06 will submit). No system write methods, no internals.
  Exception (finding F1, docs/ultron/m1-findings.md): the STARTING
  GRANT must currently use `engine.set_resource` at boot — the command
  vocabulary has no grant verb and a zero-grant bootstrap is impossible
  (cheapest producer costs timber+food while no resource flows until a
  producer is built AND staffed; every restart zeroes the pool). The
  gate proves the refusal (`upgrade_denied` reason 4) before granting,
  and counts its grants (2 resources × 2 runs). A data-driven grant
  should replace this (T-DATA-02).
- **Reads**: the systems' documented UI-query surfaces only
  (`offer_ids`, `idle_units`, `missing_gear_slots`, `upgrade_cost`,
  `army_power`, `leader_name`, ...). A host-side affordability mirror
  (recipes + idle/assigned counts) keeps doomed commands out of the
  queue — denial events stay for genuinely contested states.
- **Events, both feeds**: live play drives `tick()` and subscribes to
  `event_logged` (copy at receipt — pooled events must never be
  cached); after `fast_forward` (catch-up/offline) the host polls the
  ring tail via `next_seq()`/`get_event(seq)` — there is no other way
  to receive fast-forwarded events. The gate runs run 1 on the signal
  feed and run 2 on the ring feed and merges both into one session
  log with strictly +1 seq continuity.
- **Determinism**: the identical script re-run fast-forward-only
  (no signals) reproduces the same `state_hash()`, identities, bank
  and event count — the live drive and the catch-up drive see the
  same world.

Measured (seed 20260916, honest 60t+40f grants, example-pack
content): thin knight floor (1 knight + 1 archer, power 23) at ~26.1
sim-hours; run 2 produced +584 food / +114 timber / +17 iron in 18h
from a restarted economy; 319 events over 45 sim-hours (~7/h — a
UI-friendly chronicle volume); wall 0.018s; replay hash 1285341300.
Full findings (pacing, gear cost vs production, UI coverage gaps,
watchlist for T-SIM-05..08): docs/ultron/m1-findings.md.
