# Sim Engine — Castle Storm deterministic core (T-SIM-01)

The fixed-step deterministic economy engine: pure logic, no scene tree,
no timers, no wall clock. Everything the game *is* happens here; UI,
saving, and wall-clock drive are consumers.

- Code: `sim/sim_engine.gd` (core), `sim/sim_system.gd` (system base),
  `sim/sim_event_log.gd` + `sim/sim_event.gd` (event stream),
  `sim/sim_command.gd` (command), `sim/sim_fixed.gd` (fixed-point math),
  `sim/run_meta.gd` (T-SIM-04 meta bank, §12),
  `sim/legacy_modifiers.gd` + `sim/legacy_system.gd` (L1 unlock tree, §18),
  `sim/systems/heartbeat_system.gd` (placeholder system),
  `sim/systems/production_system.gd` (T-SIM-02 production, §10),
  `sim/systems/unit_lifecycle_system.gd` (T-SIM-03 units, §11),
  `sim/systems/run_lifecycle_system.gd` (T-SIM-04 run lifecycle, §12),
  `sim/systems/suspicion_system.gd` (T-SIM-05 suspicion, §14)
- Tests: `tests/unit/test_sim_engine.gd`, `tests/unit/test_sim_event_log.gd`,
  `tests/unit/test_sim_fixed.gd`, `tests/unit/test_production_system.gd`,
  `tests/unit/test_unit_lifecycle_system.gd`,
  `tests/unit/test_run_lifecycle_system.gd`,
  `tests/unit/test_suspicion_system.gd`,
  `tests/unit/test_legacy_system.gd` + `tests/unit/test_legacy_run_effects.gd`
  (L1, §18),
  acceptance marathons `tests/acceptance/suites/marathon_sim_1000h.gd`,
  `tests/acceptance/suites/marathon_production_1000h.gd`,
  `tests/acceptance/suites/marathon_units_1000h.gd`,
  `tests/acceptance/suites/marathon_run_thin_loop.gd`,
  `tests/acceptance/suites/marathon_suspicion_pressure.gd`
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
6. **Canonical TEXT order for id collections (T-QA-02 fix).** Wherever the
   hash (or an event stream) iterates ids in a "sorted" order, the sort is
   by STRING TEXT (`sort_custom(func(a, b): return String(a) < String(b))`),
   never plain `sort()` on StringNames: Variant ordering of StringNames is
   interning-order sensitive, so a plain sort made `state_hash()`'s
   resource-id loop depend on which names the PROCESS interned first —
   observed live when adding one acceptance suite shifted every sibling
   marathon digest without touching them (M1 finding F6's root cause: same
   state, different sort, different hash, per process). The oracle is a
   function of state alone. RunLifecycleSystem's grant loop and
   SuspicionSystem's seizure loop already used the text pattern; the engine
   core now matches them. Regression-pinned by
   `tests/unit/test_sim_engine.gd > test_state_hash_resource_order_is_text_canonical`
   (decoy-interned names + insertion-order-independent + full mix re-derived
   in text order). Hash VALUES of resource-bearing states migrated once by
   this fix (engine-only states never had resources in the pool and are
   unchanged — e.g. the engine-only marathon digest 3567881493 is stable
   across the fix); all reproducibility tests are twin-based, none pin
   absolute values.

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
| T-SIM-05 suspicion | `sim/systems/suspicion_system.gd` (§14) — the pressure curve: act bumps (`training_complete` subjects resolve `UnitDef.suspicion_on_train`; building level gains) + presence drip vs tiered decay, cancellable ≥4h telegraphs, crackdowns that seize floor-40% + scatter unassigned recruits, run death at 100 via `resolve_victory(engine, false)` (§12); joins the restart reset list |
| T-SIM-06 assault | `sim/systems/assault_resolver.gd` (§15) — a RESOLVER, not a ticker: `assault_odds` pure query (per-unit breakdown vs garrison), `commit_assault` command resolving at the drain into replayable `assault_beat` events + `resolve_victory` on win / set-back rules on loss |
| T-SIM-04 run lifecycle | `sim/systems/run_lifecycle_system.gd` (§12) — `run_seed` → `rng` for randomized leaders/regimes drawn at the run_start/restart drains; events for chronicle; meta bank in `sim/run_meta.gd` |
| T-SIM-07 catch-up | `sim/catch_up_service.gd` (§16, full contract in docs/catch-up.md) — the host service that turns two UTC timestamps into `fast_forward(≤480 ticks)`: anchor in RunMeta (meta domain), clamp/cap/backwards/freeze rules, one summary event + report; wall clock stays OUTSIDE sim (timestamps are injected) |
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
       worker  (0h; chores)  -> unit_promoted + add_worker into production's pool
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
`recruit_arrival_jitter_hours` (default 0.25, ±). Each NORMAL interval is
drawn from `engine.rng` INSIDE `on_tick` (the only sanctioned draw site) —
identical seeds produce identical arrival sequences (unit- and
marathon-tested); jitter 0 is a metronome that draws nothing (rng.state
frozen). The first tick schedules, so the first arrival lands at
~interval+1 tick. Per-regime cadence can arrive later as an additive
`RegimeModifier` kind (content-schema §4 registry is forward-compatible)
if design wants flavor-differentiated gates; the tunable keeps the
simulator in control at MVP.

**The opening rush (T-SIM-08, docs/balance.md)**: every run's FIRST
`recruit_arrival_early_count` arrivals (6) use a metronome ramp —
intervals `early_interval × early_step^i` capped at the base (tuned
6 → 12 → 24 → 48 → 96 → 120 min) — so journey 1's "first recruit within
10–15 min" holds (measured: first arrival at tick 7, zero variance; the
rush draws NO jitter). The rush index is the run's own arrival counter
(reset_run zeroes it): every restart re-opens eager.

**Gate capacity (T-SIM-08)**: while the gate holds
`recruit_gate_capacity` (6) concurrent offers the arrival countdown
PAUSES — a crowded gate draws no new peasants — and resumes the tick a
slot frees (accept / dismiss / scatter). One uniform rule, online or
offline: an away window stacks at most a gate's worth of recruits (the R4
`knight_assembly_offline` shape without forking the sim —
docs/catch-up.md §8). 0 = uncapped (the pre-T-SIM-08 behavior; arrivals
are suspicion presence and pile without bound — the T-QA-02 finding).
The UI reads the pause as `pending_offers() >= gate_capacity()` (no
extra state, no event spam). Recruit tolerance pressure (too many
recruits) is T-SIM-05's suspicion concern.

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
| `dismiss_offer` | — | offer uid | offer sent home (T-SIM-08: quiet, free, frees a gate slot; uid never reused) |
| `assign_role` | target def id | unit uid | peasant branch choice (worker/militia) |
| `start_training` | target def id | unit uid | any later hop (trainee, knight/archer) |
| `equip_gear` | gear id | unit uid | pay recipe, fill slot (tier-up replaces) |
| `promote` | — | unit uid | held trainee → knight/archer |

Events (subject = content id, value = unit uid unless noted):
`recruit_arrived` (value2 = pending offers), `recruit_accepted`
(value2 = base-def count), `recruit_dismissed` (value2 = remaining
offers), `training_started` (value2 = duration in
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

`pending_offers()`, `gate_capacity()` (T-SIM-08), `offer_ids()`,
`unit_ids()`, `unit_count(id)`, `total_units()`, `unit_def(uid)`,
`training_target(uid)`, `training_progress_milli(uid)`,
`training_duration_milli(id)`, `is_awaiting_promotion(uid)`,
`unit_gear(uid)`, `gear_tier(uid, slot)`, `missing_gear_slots(uid)`,
`idle_units(id)`, `awaiting_promotion_ids()`, `army_roster()`,
`army_power()`, `gear_ids_for_slot(slot)` (tier-sorted), `arrivals_total`.

Measured at 1000h: `marathon_units_1000h` — 60,000 ticks of the full
stack (heartbeat + units + production; 499 arrivals — 6 rush + the normal
cadence, 384 workers, 51 knights + 51 archers promoted with paid gear,
army power 2023, a 10h management cadence, and a 500h save round-trip)
in ~0.38s (~160,000 ticks/s; hash 75817539, reproduced identically
across processes; T-SIM-08's rush + gate changed the arrival stream and
with it the recorded hash — reproducibility here is twin-based, no test
pins absolute hashes). The engine-only marathon still holds ~1.67M ticks/s
and the production marathon ~143k ticks/s — both byte-identical to their
T-SIM-01/02 records: T-SIM-03 and T-SIM-08 added zero core drag.

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
| `grant_resources` | pay the run's starting stipend (boot-injected pack content, `ContentPack.starting_grants`) into the pool, ONCE per run — the F1 bootstrap verb; `resources_granted` per line (subject = resource, value = amount, value2 = new total; lines sorted by resource text). Denied 3 no running run / 4 pack has no stipend / 5 already paid this run; the PAID flag (`stipend_run`) is serialized + hashed so a restore cannot double-pay |
| `run_abort` | explicit surrender — the THIN failure path (the suspicion crush is T-SIM-05's failure, §14); banks + `run_aborted` |
| `run_restart` | fold a new identity, reset run-scoped state (below), `run_restarted` |
| `resolve_victory` | internal (queued by the entry point, below); subject `&"win"`/`&"loss"`, value = army power override |

`resolve_victory(engine, win, army_power = -1)` is the assault-outcome
entry point: T-SIM-06 (which owns the odds) calls it with its result; -1
reads the units system's live `army_power()` at drain. It is
tick-aligned like every write: it pre-checks (loud `false` when no run
is active) and queues the resolution command, which drains at the next
tick. Resolution banks the run into RunMeta and emits `run_won` /
`run_lost` (value = banked score, value2 = run index). The suspicion
crush (meter maxed, §14) resolves through this exact path with
`resolve_victory(engine, false)` — OUTCOME_DEFEAT, full banking.

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
legitimate); the suspicion system (§14) joined this list at T-SIM-05:
its meter, telegraph, relief/re-arm windows and audit baseline are all
run-scoped. The alternative (host-side engine re-init) remains available and
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
  T-SIM-06 will submit). No system write methods, no internals. The
  starting grant is a real command since T-DATA-02 (finding F1 resolved):
  `grant_resources` pays the pack's stipend — the amounts live in
  content (`ContentPack.starting_grants`), never in the command, so the
  verb cannot carry arbitrary amounts. The gate still proves the
  zero-grant bootstrap impossible (`upgrade_denied` reason 4 precedes
  the first `building_built`), then boots through the verb; restart
  zeroes the pool and the verb pays the new run's stipend.
  `engine.set_resource` is a documented TEST/construction seam only.
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

Measured (seed 20260916, the T-DATA-02 MVP pack with its honest
`starting_grants` stipend of 80 timber + 50 food, paid through the
grant verb): thin knight floor (1 knight + 1 archer, army power 23) at
~27.0 sim-hours; run 2 produced +543 food / +80 timber / +17 iron in 18h
from a restarted economy; 324 events over 45 sim-hours (~7/h — a
UI-friendly chronicle volume); wall time 0.027s; replay hash 3372344018.
Full findings (pacing, gear cost vs production, UI coverage gaps,
watchlist for T-SIM-05..08): docs/ultron/m1-findings.md.

## 14. Suspicion system (T-SIM-05)

`sim/systems/suspicion_system.gd` (`SuspicionSystem`, system_name
`&"suspicion"`) — the pressure curve: revolutionary activity raises the
Crown's suspicion; a telegraphed crackdown at the tier-2 threshold
seizes resources and scatters unassigned recruits; a maxed meter crushes
the revolution and fails the run (failure banks full progress, §12).
Constructed from content and registered LAST (heartbeat, run, units,
production, **suspicion** — it watches its siblings' state at the tick
boundary, so it must tick after them; only ordering consistency is
contractual):

```gdscript
var suspicion := SuspicionSystem.new(pack.tunables, pack.units)
engine.register_system(suspicion)  # after units + production
```

The shared marathon fixture (`_mvp_pack.full_stack`) does NOT include
suspicion — sibling suites byte-identical to their T-SIM-02..04 records
by construction; the suspicion marathon registers it on top
(`tests/acceptance/suites/marathon_suspicion_pressure.gd`), and the
real-game host composes it the same way when it lands (T-UI-03+).

**Zero RNG draws** — the meter is exact integer arithmetic end to end
(act bumps are whole points; fractional presence/decay accrue through a
SimFixed milli-point-seconds accumulator, the production pattern). All
content floats cross `SimFixed.milli_from_float` ONCE, at construction.

### The heat profile (the auditable rise formula)

Per sim-hour, suspicion moves by **act bumps** (whole points, the tick
the act happens, each recorded as a `suspicion_rose` event) plus a
**presence drip** netted against **passive decay**:

```
presence = w_army    x army_units                       [milli-points/h]
         + w_follower x (total_units - army_units)
         + w_offer   x pending_gate_offers
         + w_building x SUM(building levels)            (default weight 0)
decay    = -2.5/h while the meter is >= 70 ("compromised", R4/Hitman),
           else -5/h;  0 while a decay pause runs
drift    = presence x relief_mult - decay   -> accumulates fractionally;
           whole points settle into the meter, clamped at [0, 100]
```

- **Act sources**: training completions bump `UnitDef.suspicion_on_train`
  per def (militia +8, knight +8, archer +4 in the MVP pack — completions
  are detected by set-diffing the units system's `training_uids()`
  between ticks: a uid that left the running-timer list completed its
  timer, whatever the promotion graph; held completions read the retained
  target, auto-completions the promoted def); every building level gained
  bumps `suspicion_rise_medium` (+4 — R4's "new building level" act, the
  reason the continuous building-presence weight defaults to 0); every
  gate arrival while offers exceed `suspicion_recruit_tolerance` (3)
  bumps `suspicion_rise_loud` (+8 — R4's "recruiting past tolerance";
  the gate itself stays uncapped, §11). Zero-hour trainings complete at
  the command drain, invisible to the tick-boundary scan — a def with 0h
  training AND suspicion_on_train warns at construction.
- **R4 decay_reset_rule**: a loud act (training bump) above the warn
  threshold freezes decay for `suspicion_decay_pause_hours` (1h) —
  re-offending pauses the cooldown, softened to run scale.
- **Relief window** (24h after a crackdown): all rises — bumps AND
  presence — multiply by `post_crackdown_rise_multiplier` (x0.5).

### Thresholds, telegraph, crackdown, crush

| Threshold | Behavior |
|---|---|
| 35 warn | `suspicion_warn` on zone ENTRY (once per entry — leaving below re-primes it silently; hysteresis) |
| 70 crackdown | telegraph arms on the rising crossing: `suspicion_telegraph` (value = land tick, value2 = meter), countdown >= 4h (`crackdown_telegraph_hours`, validator-enforced). **Cancellable**: the tick the meter drops below 70 the riders stand down (`crackdown_cancelled`) — lay low and the warning was a warning. Re-arming needs a fresh crossing, gated by the re-arm timer |
| 100 crush | `run_crushed` (the story beat; subject = regime, value = max, value2 = run index) + `resolve_victory(engine, false)` queued — the run dies at the next drain (`run_lost`, OUTCOME_DEFEAT, banks full progress, §12). The meter freezes while no run is live |

When a telegraph lands: `crackdown_struck` (value = ordinal, value2 =
meter before), then per-resource `crackdown_seized` lines (sorted by
resource text; value = seized, value2 = remaining — **seize rounds DOWN**:
`floor(stock x 0.4)`, you lose at most the declared fraction of each
pile), then `crackdown_scattered` (value = scattered count, value2 =
gate offers left). Scatter takes **ceil(fraction)** of the unassigned
pool — gate offers first (arrival order), then idle peasants (roster
order) — and NEVER touches committed pipeline (militia/trainee/awaiting),
workers, trained army, or buildings: set-back, not death. The meter then
re-opens at `post_crackdown_suspicion` (45) under the relief window +
the **re-arm timer** (`crackdown_rearm_hours`, 4h — the fastest recur
cycle is telegraph 4h + re-arm 4h; crackdowns recur only if you climb
back to 70).

### Events, chronicle lines, read API

Events: `suspicion_rose` (subject = source id: unit def / `building` /
`gate`; value = points, value2 = meter after), `suspicion_warn`,
`suspicion_telegraph`, `crackdown_cancelled`, `crackdown_struck`,
`crackdown_seized`, `crackdown_scattered`, `run_crushed`. The stream
stays int-payload-only (pooled ring, §3); **human-readable chronicle
lines are a pure render query** — `chronicle_line(event)` maps each
beat to its satirical placeholder line (Professor X voice, T-COPY-01
deepens), the same identity-is-a-query pattern as M1 finding F5.

Read API: `suspicion_points()`, `max_points()`, `is_warned()`,
`crackdown_land_tick` (UI countdown = land − tick), `crackdowns_total`,
`relief_until_tick` / `rearm_until_tick` / `decay_paused_until_tick`
(public fields), `is_decay_paused(at)` / `is_in_relief(at)`.
`set_suspicion(points)` is a documented TEST/construction seam (mirrors
`SimEngine.set_resource`); the acceptance marathon drives the meter
honestly through real acts.

### Serialization + determinism

`to_dict()`/`from_dict()` fully overridden: meter, fractional carry,
warn flag, telegraph land tick, crackdown count, the three window ticks,
crush flag, and the **audit baseline** (last-seen units total/army/
offers/arrivals, per-building levels, the running-training uid set) —
without the baseline a restore would diff against zeroed counters and
spawn phantom rises on the first post-restore tick. `state_hash()` mixes
all of it (the countdown and windows are hashed state — an oracle blind
to them could call a lost telegraph "identical", the T-ARCH-03 lesson).
`reset_run(regime)` returns everything to constructed state at the
`run_restart` drain (§12 reset contract). The system consumes no
commands (`on_command` always false — a future lay-low verb would land
there); while no run is RUNNING it is dormant but keeps the audit
baseline current (arrivals do not stop for your defeat).

**Regime-neutral at MVP** (documented): RegimeDef carries exactly one
combat modifier + one economy quirk (validator-enforced, both claimed by
all four flavors); a suspicion-rate angle would need an additive third
modifier kind — deferred until a pack wants differentiated heat, per the
content-schema §4 registry's forward compatibility.

### Measured

`marathon_suspicion_pressure` — run A (forced loud: every recruit
militarized, every gear tier promoted, one upgrade per chunk) crosses
warn, arms two telegraphs, eats one crackdown (every `crackdown_seized`
event re-derives its own floor-40% math from its payload), and is
**crushed at 66h** with 146 lp banked; the restart resets every field
and the follow-up run stays quiet. Run B (careful-loud, then lay low)
arms the telegraph at exactly 70 and **cancels it** by dipping below 70 —
no crackdown ever fires, the meter keeps falling. The whole script
replays bit-for-bit. ~59k ticks/s full-stack. All sibling marathons held
their recorded hashes byte-identically (engine 3567881493, production
3517250863, units 4081412319, run_thin 2708794948, gate 3372344018) —
suspicion is strictly opt-in per engine until the game host composes the
full stack.

## 15. Assault resolver (T-SIM-06)

`sim/systems/assault_resolver.gd` (`AssaultResolver`, system_name
`&"assault"`) — army score vs castle garrison: the odds query, the
player-chosen commit, the deterministic resolution, and the replayable beat
stream the assault vignette (T-UI-07) renders from events alone.

**A RESOLVER, not a system that ticks.** `on_tick` is a hard no-op (the
RunLifecycleSystem precedent, §12) and the resolver holds ZERO state between
commands — every persistent effect lives in the siblings it hands its result
to (units roster, suspicion meter, run frame). It sits on the SimSystem seam
anyway because the commit must be a COMMAND (the tick-aligned write
contract, §5): `commit_assault` queues exactly like every other player verb
and resolves at the next tick's drain, inside the engine's determinism
rules. Consequences of statelessness, all deliberate: `to_dict()` is `{}`
and `state_hash()` constant (nothing to save — nothing survives a restart
by construction; the units system's roster reset IS the whole assault
reset), and no `reset_run` (the §12 `has_method` guard skips it). Placement
justification: a per-tick system would carry armed-assault state between
ticks (a new save/restore/fork surface for zero gameplay value); the
resolver pattern keeps the whole battle inside ONE command drain — the
same-tick property the vignette replay relies on.

```gdscript
var assault := AssaultResolver.new(pack.tunables)
engine.register_system(assault)  # anywhere after run; suites: 5th, before suspicion
```

Opt-in per engine like suspicion (§14): the shared `_mvp_pack.full_stack`
fixture does NOT register it, so every sibling suite's recorded hash stays
byte-identical; the assault marathon registers it on top
(`tests/acceptance/suites/marathon_assault_storm.gd`).

### The odds (pure query — the odds screen's data contract)

`assault_odds(engine)` — no RNG draws, no writes, callable every frame:

```
army_score   = army_power() (def + gear tiers, incl. archer support values)
               x army_score_multiplier    [regime combat kind -> army side]
garrison     = assault_garrison_base_power
               x garrison_multiplier      [regime combat kind -> castle side]
win_permille = army_milli * 1000 / (army_milli + garrison_milli)
```

The regime's ONE combat modifier lands on exactly one side (the schema
allots one per flavor: gilded_crown garrison x1.2, velvet_fist x0.9,
iron_rotunda army x1.1, paper_crown x0.95); a regime-less run (restore
edge, §12 warns loudly) is neutral x1.000 both sides. Monotone by
construction — more power NEVER lowers the odds (unit-tested across the
growth curve and all four flavors); at parity 500; the floor assault
(power 23 vs garrison 50, the T-SIM-08 tuned base) opens at **277–338
by flavor** (neutral 315), 2x floor ≈ 44–49%, the M1
100-power line ≈ 63–69%. The breakdown dict carries per-unit contributions
(`{uid, def, def_power, gear_power, total}` in roster order), the army
sums + multiplier, the garrison composition (base, modifier kind,
multiplier, strength), `floor_power`, `floor_met`, and `win_permille` —
and the parts SUM to the displayed probability exactly (unit-tested:
per-unit totals = army power; power x multiplier = score_milli; the two
sides reproduce the permille to the digit).

### The knight floor: a floor, never a trigger

`assault_knight_floor_power` (23 = the M1-measured 1K+1A t1 line, m1-findings)
gates the COMMIT only: below it `commit_assault` is refused loudly
(`assault_denied` reason 3, value2 = live army power for the "you need X
more" line); meeting it merely UNLOCKS the commit button. The odds query
itself always answers — the screen shows the odds you are climbing toward
while locked. Surplus power and gear quality (t1 → t3 refits) keep raising
the displayed odds; nothing auto-triggers.

### The commit (`commit_assault`, resolved AT the drain)

Guards → `assault_denied` (1 no running run, 2 no units system, 3 below
floor). Then **one decisive draw**: `rng.randi_range(0, 999) <
win_permille` wins — the odds shown before the commit are exactly the
odds rolled. Then the beat stream, then the outcome:

- **Win**: `assault_won` (value = the win_permille that was shown, value2 =
  army power at commit) and `run.resolve_victory(engine, true, power)` —
  queued from INSIDE this drain, so `run_won` lands in the SAME tick
  (the queue drains until empty; unit- and marathon-tested). Victory
  applies no roster losses: the roster is terminal at victory (restart
  clears it; the future L2 snapshot reads whatever stands). The beats
  still narrate attrition for the vignette.
- **Loss — set-back, NEVER instant run death** (R4 philosophy): (a)
  `ceil(assault_loss_fraction x army units)` ARMY units fall — newest
  first (reverse roster order: the vanguard holds), gear and all — via
  the units system's `apply_army_losses` seam, `assault_casualties`
  (value = count, value2 = surviving power); (b) `+
  assault_failure_suspicion` (20) through the suspicion system's
  `apply_external_bump` seam — the same damped/clamped path as every
  rise (relief x0.5 inside the window), loud (pauses decay above warn),
  `suspicion_rose` with subject `assault`. The run KEEPS RUNNING; the
  floor re-arms below 23 and the assault can be re-attempted after
  rebuilding. The ONE bend in the rule: a spike that reaches the meter
  max (100) crushes at that tick's suspicion on_tick (§14) — an assault
  thrown away with the meter already at the edge is fatal, mirroring the
  crackdown design.

### The beat stream (the T-UI-07 vignette contract)

Four `assault_beat` events per resolved commit — replayable from events
alone, data-light, int payloads only: `subject` = phase, `value` = army
score remaining (milli), `value2` = garrison strength remaining (milli).

| Path | Phases in order |
|---|---|
| win | `advance` → `skirmish` → `gate` → `throne` (garrison ends at 0) |
| loss | `advance` → `skirmish` → `gate` → `rout` (army ends at the TRUE survivors) |

Army remaining is non-increasing across every chain and ends at the true
post-battle state: on the loss path the TOTAL applied loss is split
across skirmish/gate by one drawn share so the gate beat lands exactly on
the survivors the roster holds. Event order per commit — win: 4 beats,
`assault_won`, `run_won` (same tick); loss: 4 beats, `assault_casualties`,
`suspicion_rose`, `assault_lost`.

**RNG draw count per commit** (documented for stream reasoning): 1 roll +
4 attrition draws on the win path, 1 + 3 on the loss path. Content floats
cross the single `SimFixed.milli_from_float` boundary (regime modifier
values at use; the loss fraction once at construction); after that
everything is integer milli.

### Events, read API, serialization

Events: `assault_denied`, `assault_beat`, `assault_won`, `assault_lost`,
`assault_casualties` (+ the sibling `suspicion_rose` on loss). Read API:
`assault_odds(engine)` (the full breakdown), `floor_met(engine)`,
`knight_floor_power()`, `garrison_base_power()`. Serialization: the
resolver is stateless — `to_dict()` `{}`, constant `state_hash()`, no
`reset_run` (§12's guard skips it); a save carries `"assault": {}`
(additive-optional, the §save-schema 4.2 policy) and a restored engine
commits identically. Sibling seams added for T-SIM-06:
`UnitLifecycleSystem.army_contributions()` (per-unit def/gear power,
roster order — also the odds screen's panel) and `apply_army_losses(count)`
(newest-first army-only removal, gear included), and
`SuspicionSystem.apply_external_bump(engine, source, points, loud)` (the
shared damped/clamped act-bump path — internal act bumps and external
spikes ride the same rules).

### Measured

`marathon_assault_storm` — the full arc on the MVP pack (seed searched
deterministically for loss-then-win): floor assault at power 23 (2 units)
under paper_crown → 266 permille → **lost**: 1 casualty (ceil(0.5 x 2)),
suspicion +20 exactly, army 15, run still RUNNING, re-commit refused
below the floor; rebuilt 28h to power 77 → 549 permille → **won**:
`run_won` in the same tick as `assault_won`, 233 lp banked, exactly one
chronicle entry. A mid-recovery fork (engine state saved, twin restored,
phase 2 replayed) reproduces the final hash bit-identically; the full
fast-forward replay reproduces hash + event count (578 events). Wall
0.98s including the seed search. All sibling marathons held their
recorded hashes byte-identically (engine 3567881493, production
3517250863, units 4081412319, run_thin 2708794948) — the resolver adds
zero per-tick cost (it does not tick).

## 16. Catch-up service (T-SIM-07)

`sim/catch_up_service.gd` (`CatchUpService`) — offline catch-up: timestamp
math at the foreground boundary plus one bounded replay through the REAL
engine. Full contract (away-time semantics, clock policy, DST, crash
safety): **docs/catch-up.md** — that doc is the source of truth; this
section is the engine-facing map.

**A HOST SERVICE, not a SimSystem** (the SaveManager discipline): plain
RefCounted, no scene tree, no autoload, and NO CLOCK READS — every
timestamp is injected by the platform host (`apply(engine, meta, now)`),
which is what keeps the wall clock outside sim (§1's boundary rule,
gdscript-conventions). It never registers on the seam, never ticks, holds
no engine state; sibling marathons are byte-identical by construction.

```gdscript
var service := CatchUpService.new(pack.tunables)   # cap from offline_cap_hours
service.mark_seen(run.meta, now_epoch)             # host: backgrounding/saving
var report := service.apply(engine, run.meta, now_epoch)  # host: foreground/load
```

- **Anchor**: `RunMeta.last_seen_epoch` (UTC epoch seconds, META domain,
  additive-optional key; 0 = first-launch sentinel — no anchor, no
  catch-up). Every `apply()` refreshes it to `now`.
- **Math (pure, the T-QA-04 fuzz surface)**: `clamp_elapsed_seconds`,
  `applied_ticks_for(elapsed, cap)` (= clamp then floor-divide by
  `TICK_SECONDS`), `elapsed_between` (operands clamped to ±2^40 first, so
  int64 extremes cannot overflow). Never negative, never uncapped,
  monotone — pinned over 2000 generated inputs in the unit suite.
- **Replay**: `engine.fast_forward(applied)` — arrivals, training,
  production and suspicion all advance by the real deterministic rules
  (twin-proven: catch-up == the same ticks live, hash-identical, in the
  unit suite AND `marathon_catch_up_gap`). A paused engine accrues
  nothing (`skipped_paused` — pause is a world freeze).
- **Events**: one `catch_up_applied` (value = ticks, value2 = clamped
  seconds) recorded AFTER the window so the ring tail keeps the raw
  detail; `catch_up_clock_rewound` (value = rewound seconds) on a
  backwards clock — zero state change, never punishment. The returned
  report Dictionary (resource deltas per type, arrivals, completions,
  promotions, run endings, crackdowns that landed in-window, suspicion
  delta) is T-UI-09's data (the consumer landed:
  `ui/screens/spread/catch_up_print.gd` + the check-in unfold — see
  docs/catch-up.md §7); `chronicle_line(report)` renders the placeholder
  voice.
- **Measured** (`marathon_catch_up_gap`, full MVP stack + suspicion):
  capped 8h = 480 ticks resolves in ~7ms (budget 100ms); two away
  windows + a kill-mid-catch-up revival + first-launch + rewind all
  twin-verified in ~0.1s total.

## 17. The reference host composition (T-QA-02)

`tests/acceptance/suites/_full_stack.gd` is the canonical "real game host"
composition, defined ONCE so CI and the UI cannot drift apart:

- `game_stack(seed, meta, stipend)` — one engine + ALL five gameplay
  systems + the heartbeat placeholder, in the ONE contractual order:
  heartbeat → run → units → production → assault → suspicion (suspicion
  LAST: it audits siblings at the tick boundary, §14; the resolver is
  stateless, §15). Content is the MVP pack through the loud gate; the
  stipend defaults to the pack's own starting grants (the honest boot).
- `HostSession` — the host wiring beyond the engine: ONE `RunMeta` (meta
  save domain) shared by every engine the session builds, ONE
  `CatchUpService` from the pack tunables, `build_engine()` (the
  host-side restart: fresh engine around the same meta — equivalent to
  in-engine `run_restart` by §12's both-forms rule), `mark_seen(now)` /
  `foreground(now)` (the docs/catch-up.md boundary; timestamps always
  injected by the platform host). T-UI-03 builds its live engine from
  this shape; T-PERF-01 owns the platform boundary around it.
- `manage(engine, military_cap, opts)` — the scripted sensible-play policy
  shared by the T-QA-02 suites (build order, staffing, training queues,
  gear crafting; reads → commands only, zero test-side RNG). `opts`:
  `laying_low` (the R4 tension response — no new trainings/upgrades in the
  crackdown zone) and `population_cap` (measured growth).
- The opt-in rule stands: the older `full_stack` in `_mvp_pack.gd` stays
  suspicion/assault-free so pre-T-SIM-05/06 marathon constructions are
  untouched; `_full_stack.gd` is where the complete five-system stack
  lives and what the two T-QA-02 suites drive
  (`economy_stability_1000h`, `full_run_ci`).

Sibling digest note: pre-T-QA-02 the resource-bearing marathon digests
were quietly process-order sensitive (§2 rule 6) — the recorded values
were never truly stable across machines. After the fix they are
bit-reproducible across processes (proven by back-to-back `ci.sh accept`
runs) and were re-recorded once: engine-only 3567881493 (unchanged),
production 306376767, units 2731020335, run_thin 659828436,
gate_m1 145325186, assault_storm 1090049983,
economy_stability 500h 3692574814 / final 460399411.

## 18. The legacy unlock tree (L1)

The post-MVP Layer 1 — the persistent meta-progression tree (R5: the
Rogue Legacy manor pattern — always-on, fed by EVERY run win or lose;
docs/ultron/research/r5-revolution-idol-cadence.md). Three pieces:

1. **Content** (content-schema §4 UnlockNodeDef/UnlockEffect/UnlockTreeDef,
   `ContentValidator.validate_unlock_tree` — the loud gate: unique ids,
   positive costs, resolving prerequisites, an ACYCLIC graph, one
   known-kind positive effect per node). The tree attaches to the pack
   additively-optional (`ContentPack.unlock_tree`); the MVP pack pre-L1-B
   ships none and the whole layer runs empty.
2. **The service** (`sim/legacy_system.gd`, `LegacySystem`) — NOT a
   per-tick SimSystem: meta-progression is meta-domain, like RunMeta and
   CatchUpService. A plain RefCounted host service owning the purchase
   rules over one tree + one RunMeta. The persistence is
   `RunMeta.unlocks` (node id -> true, purchase order; meta save domain,
   additive-optional with a tolerant reader — pre-L1 metas read as owning
   nothing) and `RunMeta.legacy_points` (the bank; `purchase` decrements
   it, the only spending writer). Purchases validate affordability +
   prerequisites + not-already-owned and refuse LOUDLY (push_error +
   false, zero mutation); `GameHost.unlock_purchase(node_id)` is the host
   command and persists the meta domain the moment a purchase lands.
   Unlocks survive every restart by design — the reset contract (§12) has
   no legacy member, and a run-save restore can never fork them.
3. **The resolution** (`sim/legacy_modifiers.gd`, `LegacyModifiers`) —
   what the owned set MEANS to a run: one pure bundle of int-milli
   multipliers, compounded per node through exact integer chains (order-
   independent), over the L1 effect vocabulary:
   `recruit_arrival_interval_multiplier` (the whole arrival cadence —
   normal interval, jitter AND the opening-rush ramp — scales together),
   `building_cost_multiplier` (a fourth milli factor in the §10 upgrade
   curve), `training_time_multiplier` (§11 durations; zero-hour stays
   zero-hour), `gear_cost_multiplier` (§11 recipe lines, floored, min 1),
   `stipend_bonus` (the `grant_resources` verb, floored, min 1).

### Application — the regime-quirk pattern, one drain later

`RunLifecycleSystem` (constructed with the optional `p_legacy` provider —
`GameHost` and any host wires it) resolves ONE bundle at EVERY
`run_start`/`run_restart` drain and applies it synchronously, exactly the
way the regime economy quirk lands (`set_regime`): production and units
take `set_legacy_modifiers(bundle)` at the same drain, and the run system
applies the stipend field inside `grant_resources`. Consequences, all
deliberate:

- **Purchases land at the NEXT run start, never mid-run** — the tree is a
  between-runs verb; the reset contract's clean-tick property is intact.
- **Hash-visible, round-trip exact** (the T-ARCH-03 lesson): each
  consumer carries its APPLIED multipliers as serialized + hashed state —
  `run.legacy_stipend_milli`, `production.legacy_cost_milli`,
  `units.legacy_modifiers` — emitted ONLY when non-identity (the
  escalation_garrison emit-when-non-null discipline). An engine with NO
  unlocks serializes nothing and hashes byte-identically to the pre-L1
  build (unit-proven: same seed, provider vs no provider -> identical
  `to_dict()` and `state_hash()`), which is why every existing suite's
  recorded digest survives this layer unperturbed. A save made under
  active modifiers restores them verbatim and continues in lockstep.
- **Determinism**: the modifiers are a pure function of (tree, owned
  set) resolved at the drain and then baked — same seed + same unlocks ->
  identical world; same seed + different unlocks -> different world (the
  oracle sees the bundle even before a tick diverges). This deliberately
  narrows §12's "engines with the same seed hash identically regardless
  of carried-over meta": the BANK still cannot perturb a run, but unlock
  EFFECTS can — they are engine-visible economy config, like regime
  quirks, not bank values.
- **Identity is bit-exact**: every seam scales by exact integer milli
  math where 1000 = identity reproduces the content value to the digit
  (cost curves, timers, cadence, recipes, stipend) — the zero-impact
  proof above is mathematical, not incidental.

Measured: the two L1 suites (~60 cases) add ~0.4s to `make test`; every
sibling marathon digest unchanged.

