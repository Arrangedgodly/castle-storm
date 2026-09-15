## Economy tunables — the R4 research vocabulary as data, not code constants
## (docs/ultron/research/r4-idle-balance-references.md; every default below is
## an R4 seed value; T-SIM-08 tunes them in the simulator). Consumed by:
## T-SIM-07 (offline block), T-SIM-02 (cost band), T-SIM-08 (all),
## T-SIM-05 (suspicion block), T-SIM-03 (recruit arrival cadence),
## T-SEC-01 (cap/clamp policy).
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
