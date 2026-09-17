## Economy tunables — the R4 research vocabulary as data, not code constants
## (docs/ultron/research/r4-idle-balance-references.md). Defaults started as
## R4 seed values and were TUNED by the T-SIM-08 balance pass in the
## simulator (docs/balance.md records every change + the reasoning table;
## comments at each field mark the tuned values and why). Consumed by:
## T-SIM-07 (offline block), T-SIM-02 (cost band), T-SIM-08 (all),
## T-SIM-05 (suspicion block), T-SIM-03 (recruit arrival cadence),
## T-SIM-06 (assault block), T-SEC-01 (cap/clamp policy).
class_name EconomyTunables
extends Resource

## --- Offline catch-up (R4 §A) ---

## Hours of real elapsed time that accrue while away (R4: 8, premium floor;
## tunable range 4-24 enforced by the validator).
@export var offline_cap_hours: float = 8.0

## Multiplier vs online production (R4: 1.0 — premium full-rate; sub-1.0 is
## an F2P lever and is rejected by the validator).
@export var offline_rate: float = 1.0

## --- Production & progression curves (R4 §B) ---

## Inclusive lower bound of the per-building cost_growth band (R4: 1.08).
@export var cost_growth_band_min: float = 1.08

## Inclusive upper bound of the per-building cost_growth band (R4: 1.12).
@export var cost_growth_band_max: float = 1.12

## Production multiplier fired at each building milestone level
## (R4: x2.0 at levels 10/20, then every +10).
@export var milestone_multiplier: float = 2.0

## Effective-cost compounding factor per additional knight
## (R4: ~1.6x; first knight lands end of day 1 casual).
@export var knight_cost_step: float = 1.6

## --- Recruit arrival cadence (T-SIM-03) ---

## Base interval between peasant arrivals at the gate, in sim-hours. The
## actual interval is jittered +/- recruit_arrival_jitter_hours using the
## engine's seeded RNG: identical run seeds produce identical arrival
## sequences (docs/sim-engine.md §11). Tunable choice recorded in
## docs/content-schema.md §4 — per-regime cadence can arrive later as an
## additive RegimeModifier kind if design wants flavor-differentiated gates.
@export var recruit_arrival_interval_hours: float = 2.0

## +/- jitter on each arrival interval, in sim-hours (0 = metronome cadence
## that draws no RNG at all). Must be < the base interval.
@export var recruit_arrival_jitter_hours: float = 0.25

## --- The opening rush (T-SIM-08; M1 finding F2) ---

## The FIRST N arrivals of every run come on a fast, METRONOME cadence (no
## jitter — the village is eager) that ramps up to the normal interval, so
## journey 1 ("first recruit within 10-15 min of the first session") holds
## without compressing the whole game's idle pace. 0 disables the rush (the
## pure R4 cadence). Per run: the early index is the run's own arrival
## counter (reset_run zeroes it), so every restart re-opens eager. Tuned in
## the simulator sweep — docs/balance.md.
@export var recruit_arrival_early_count: int = 6

## Interval of the FIRST early arrival, in sim-hours (0.1 = 6 sim-minutes —
## inside the 10-15 min journey-1 window with UI margin to spare). Must be
## > 0 and <= recruit_arrival_interval_hours.
@export var recruit_arrival_early_interval_hours: float = 0.1

## Multiplicative ramp per early arrival toward the base interval (>= 1.0;
## 1.0 = one uniform fast interval for the whole rush; the ramp caps at the
## base interval). Tuned 2.0 with count 6 / first interval 0.1h: the opening
## intervals run 6 -> 12 -> 24 -> 48 -> 96 -> 120 min, then the normal
## jittered 2h cadence takes over.
@export var recruit_arrival_early_step: float = 2.0

## The gate holds at most this many concurrent recruit offers (T-SIM-08; the
## T-QA-02 stability finding): while the gate is FULL the arrival countdown
## PAUSES (a crowded gate draws no new peasants) and resumes the tick a slot
## frees (accept / dismiss / scatter). One uniform rule, online or offline:
## an away window stacks at most a gate's worth of recruits — the R4
## `knight_assembly_offline` shape without forking the sim
## (docs/catch-up.md §8). 0 = uncapped, the pre-T-SIM-08 behavior
## (arrivals are presence and pile up without bound).
@export var recruit_gate_capacity: int = 6

## --- Suspicion / pressure curve (R4 §C) ---

## Meter maximum; reaching it ends the run and banks meta (R4: 100).
@export var suspicion_max: int = 100

## Tier-1 warning threshold (R4: 35; crossing telegraphs a chronicle line).
@export var suspicion_warn_threshold: int = 35

## Tier-2 crackdown threshold (R4: 70; seizes resources, scatters recruits).
@export var suspicion_crackdown_threshold: int = 70

## Passive decay per sim-hour below tier 2 when quiet (R4: -5/h).
@export var suspicion_decay_per_hour: float = 5.0

## Passive decay per sim-hour at tier 2+ — the "compromised" state
## (R4: -2.5/h; must not exceed the low-tier decay).
@export var suspicion_decay_high_tier_per_hour: float = 2.5

## Suspicion rise per loud act — militia/knight training, crafting past
## tolerance, recruiting past tolerance (R4: +8).
@export var suspicion_rise_loud: int = 8

## Suspicion rise per medium act — new building level, stockpiling past cap
## (R4: +4).
@export var suspicion_rise_medium: int = 4

## Fraction of stockpiled resources a crackdown seizes (R4: 40%).
@export var crackdown_seize_fraction: float = 0.4

## Minimum sim-hours between the telegraph warning and enforcement
## (R4 commitment: >= 4h — the strongest telegraph in the source research).
@export var crackdown_telegraph_hours: float = 4.0

## Meter level immediately after a crackdown re-opens playable space
## (R4: drops to 45).
@export var post_crackdown_suspicion: int = 45

## Rise multiplier during the post-crackdown relief window (R4: x0.5).
@export var post_crackdown_rise_multiplier: float = 0.5

## Sim-hours the relief window lasts (R4: 24h).
@export var post_crackdown_relief_hours: float = 24.0

## --- Suspicion heat profile (T-SIM-05; presence weights — additive schema
## extension, documented deviation from R4's per-act-only rise: the task
## contract requires presence that "scales with visible revolution size".
## Hour-scale weights are derived, not cited — same derivation status as R4's
## own hour-scale numbers; T-SIM-08 tunes them in the simulator) ---

## Suspicion points per sim-hour per ARMY unit on the roster (knights,
## archers — armor and weapons are maximally visible). R4 seed 0.5, tuned to
## 0.3 in the T-SIM-08 sweep: at 0.5 the sensible steady estate (army 4 +
## 20 followers) alone out-shouts the tier-2 decay (2.5/h) — an un-cancellable
## telegraph, which R4's tension mechanic forbids; at 0.3 laying low works
## and GREED (army ~8+) still ratchets. docs/balance.md.
@export var suspicion_presence_army_per_hour: float = 0.3

## Suspicion points per sim-hour per NON-army tracked unit (workers,
## peasants, militia, trainees — every body in the conspiracy's camp is a
## co-conspirator to the Crown's eyes, but quietly). R4-derived seed 0.1,
## tuned to 0.05 in the T-SIM-08 sweep (same reasoning as the army weight:
## 20 followers at 0.1 = 2.0/h alone approached the tier-2 decay line).
@export var suspicion_presence_follower_per_hour: float = 0.05

## Suspicion points per sim-hour per TOTAL building level. DEFAULT 0.0 — a
## design decision, not an omission: buildings are loud when they GROW (the
## +suspicion_rise_medium act per level gained, R4's "new building level"),
## and continuous estate presence would make the tier-2 decay dip (−2.5/h)
## mathematically unreachable once levels stack — an un-cancellable
## telegraph, which the R4 tension mechanic forbids. The dial stays for
## T-SIM-08 if the balance pass wants always-on estate visibility.
@export var suspicion_presence_building_per_hour: float = 0.0

## Suspicion points per sim-hour per recruit OFFER waiting at the gate (a
## crowd loitering at the gate is louder than a farmer; default 0.25).
@export var suspicion_presence_offer_per_hour: float = 0.25

## Gate tolerance: pending offers at or below this count are a normal-looking
## queue; each ARRIVAL while the gate holds MORE than this many is a loud act
## (+suspicion_rise_loud) — R4 "recruiting past tolerance". The gate itself
## stays uncapped (docs/sim-engine.md §11); the crowd is what gets noticed.
@export var suspicion_recruit_tolerance: int = 3

## Sim-hours a LOUD act (training completion with suspicion_on_train > 0)
## freezes passive decay while suspicion is above the warn threshold (R4
## decay_reset_rule, GTA's re-offense-resets-cooldown softened to run scale).
@export var suspicion_decay_pause_hours: float = 1.0

## Fraction of the unassigned-recruit pool (gate offers + idle peasants) a
## crackdown scatters. Rounds UP (the Crown is thorough). Never touches
## trained army, workers, or buildings.
@export var crackdown_scatter_fraction: float = 0.5

## Sim-hours after a crackdown before the NEXT telegraph may arm (the re-arm
## timer: crackdowns recur only if you stay >= 70, and never faster than
## this). Default 4.0 — the fastest possible recur cycle is telegraph (4h) +
## re-arm (4h).
@export var crackdown_rearm_hours: float = 4.0

## --- Assault resolution (T-SIM-06; derived defaults, same derivation status
## as R4's own hour-scale numbers — T-SIM-08 tunes them in the simulator) ---

## Minimum ARMY POWER to commit an assault — the knight FLOOR (a floor, not a
## trigger: meeting it only unlocks the commit; surplus power and gear quality
## keep raising the displayed odds). Default 23 = the M1-measured thin line of
## one knight (10 + t1 weapon 2 + t1 armor 3) + one archer (6 + t1 weapon 2),
## docs/ultron/m1-findings.md.
@export var assault_knight_floor_power: int = 23

## Base castle garrison strength before the regime combat modifier (a
## garrison_multiplier regime scales it; an army_score_multiplier regime
## scales the army instead). R4-derived seed 60, tuned to 50 in the T-SIM-08
## sweep: at 60 the sensible commit line (~450 permille) arrives ~72h in and
## the multi-loss tail pushes first wins past the 2-4 day band; at 50 the
## same line arrives ~15h earlier and every flavor still spans a real odds
## curve (floor ~277-338 permille, 2x floor ~44-49, 100 power ~63-69).
## docs/balance.md.
@export var assault_garrison_base_power: int = 50

## Fraction of ARMY UNITS (knights/archers, gear and all) that fall when an
## assault FAILS. Rounds UP (the rout is thorough). Survivors keep their
## places; the run continues — set-back, not death (R4 philosophy). Only the
## trained army is touched: workers, pipeline, offers, buildings never are.
@export var assault_loss_fraction: float = 0.5

## Suspicion added when an assault FAILS — the Crown watched your whole army
## march, break, and run home (louder than any single training act). Applied
## through the suspicion system's external-bump seam: relief-damped, clamped
## at the meter max, and CAN crush the run if the meter was already at the
## edge. Default 20 = just above half a warn threshold.
@export var assault_failure_suspicion: int = 20

## --- Enemy escalation (L2 — docs/sim-engine.md §19; the curve placeholder
## shipped by L2-A, TUNED BY THE L2-B BALANCE PASS) ---

## Per-cycle compounding step of the escalation curve: when a garrison
## snapshot stands in the meta, the castle's strength is the SNAPSHOT's
## army-power-equivalent x step^(cycle-1) — cycle 1 (the first captured
## victory) is x1.000 because the snapshot ITSELF is the first escalation
## (a typical winning army ~100 power already doubles the static 50 wall,
## re-establishing R5's "first L2 cycle is a full new campaign" arc);
## every later captured cycle compounds this step (R5: the ladder the
## player climbs, compressing ~2-5x per arc as legacy power compounds).
## Exact integer milli math (SimFixed.milli_from_float ONCE at the
## resolver's construction; one floored int division per hop, hops capped
## at Escalation.MAX_CURVE_HOPS). Validator band [1.0, 4.0): the ladder
## never shrinks. Default 1.25 is the L2-A PLACEHOLDER — L2-B owns the
## tuned value (docs/balance.md §7).
@export var escalation_garrison_cycle_step: float = 1.25
