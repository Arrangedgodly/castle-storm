# Economy Balance Pass — Castle Storm (T-SIM-08)

Date: 2026-09-15. Worker: Iron Man lane, Hawkeye consulted. Harness:
`scripts/balance_sweep.gd` (`make balance-sweep`) — sweeps `EconomyTunables`
candidates against the CANONICAL host composition (`_full_stack.gd`) and
prints the measurement tables recorded below. The chosen values are the
class defaults in `content/schema/economy_tunables.gd` (the pack `.tres`
sets nothing; defaults flow through — pinned by
`test_mvp_pack.test_tunables_equal_the_tuned_class_defaults`). The CI
acceptance suite `tests/acceptance/suites/economy_balance_band.gd` pins the
band on fixed seeds (one per regime). Re-sweep before any future retune.

## 1. The targets (town-hall / R4 → task contract)

| Target | Source | Measured (chosen) |
|---|---|---|
| First recruit ≤ 15 real min of the first session | journey 1 (M1 finding F2: was ~118 min, 8–12× late) | **7 min** (metronome — zero variance) |
| "I get it" session 10–15 min: assignment + first trickle visible fast | journey 1 | first worker **45 min** (rush + 30-min training, M1 F2 called that fine), first food trickle **58 min** |
| First win in the 2–4 day band at sensible pace (3–5 min check-ins) | town-hall | **mean 79 sim-h ≈ 3.3 wall days** at 4 check-ins/day (12/12 seeds won, slowest 127 h) |
| 1000h stability: ≤ 1 crush under sensible play; crushes from GREED not existing | task contract (T-QA-02 finding) | **0 crushes**, suspicion peak 24 (< warn 35); the greed probe crushes at ~28 h |
| Failed-assault recovery ~day-scale | task contract | **mean 29 h** loss→win (6 multi-loss runs) |
| Check-in value (resources gained per 5-min window mid-run) | task contract | **~+20–60 gross resources** per 5-min live window; one full cycle resolves ~18–36 events, banks ~+1400–4500 away accrual, decides ~150 resources of spends |

Cadence model: one `manage()` batch per check-in (the shared sensible-play
policy), a 3-minute live session, the away gap through the REAL
`CatchUpService` (8 h cap honored). 4 check-ins/day (6 h apart) accrue ~24
sim-h per wall day; 3/day (8 h) also ~24 (the cap clamps the gap); 2/day
(12 h) accrues ~16 — a 2/day player wins in ~5–7 wall days (the band assumes
the town-hall "several short check-ins" rhythm; recorded, not hidden).

## 2. The chosen values (and what changed from the R4 seeds)

| Tunable | R4 seed | Chosen | Why |
|---|---|---|---|
| `recruit_arrival_early_count` | — (new) | **6** | The opening rush (M1 F2): first recruit 7 min instead of ~118. 6 arrivals cover journey 1 + the first evening; the ramp then hands over to the idle cadence. |
| `recruit_arrival_early_interval_hours` | — (new) | **0.1** (6 min) | Inside the 10–15 min window with UI margin; metronome (no jitter) so the first-recruit time is exact. |
| `recruit_arrival_early_step` | — (new) | **2.0** | Intervals 6→12→24→48→96→120 min: "fast cadence decaying to normal" without dumping 8 bodies on a learning player (uniform-8 measured identical journey-1 numbers; ramp chosen for pace). |
| `recruit_gate_capacity` | — (new) | **6** | The T-QA-02 finding's structural fix: a full gate PAUSES arrivals, so offers (presence, 0.25/h each) are bounded at 1.5/h forever — offline included (the R4 `knight_assembly_offline` shape, one uniform rule, no offline/live sim fork; docs/catch-up.md §8). 4/6/8 measured identical in every table (an 8 h away window stacks ≤5); 6 = 2× tolerance, roomy. |
| `suspicion_presence_army_per_hour` | 0.5 | **0.3** | The sustainability inequality: a measured estate (army 4 + 20 followers) must sit BELOW the tier-2 decay (2.5/h) or laying low can never cancel a telegraph (an un-cancellable telegraph is the one thing R4's tension mechanic forbids). 0.5 gave 4.0/h presence → the telegraph could never be heeded. At 0.3: 2.2/h — cancel works; greed (army ≥ ~8 with followers) still ratchets. |
| `suspicion_presence_follower_per_hour` | 0.1 | **0.05** | Same inequality (20 followers at 0.1 = 2.0/h alone). Halved, not zeroed: followers still count — a big camp is warm. |
| `suspicion_presence_building_per_hour` | 0.0 | **0.0 (kept)** | T-SIM-05's recorded rationale re-affirmed as a CONSCIOUS choice: buildings are loud when they GROW (+4/level medium act); always-on estate heat at any meaningful weight makes the tier-2 decay dip unreachable at high levels (w=0.02 × ~120 late-game levels = 2.4/h ≈ the whole decay budget). |
| `assault_garrison_base_power` | 60 (derived) | **50** | The first-win band lever. At 60 the sensible commit line (~450‰) arrives ~72 h in and the multi-loss tail pushed mean wins to ~113 h (11/12 seeds, slowest 205 h). At 50: mean 79 h, 12/12, slowest 127 h. The odds curve stays real: floor ~27.7→31.5%, 2× floor ~43→48%, 100 power ~62→67% (neutral). |
| Everything else (decay 5/2.5, warn 35, crackdown 70, telegraph 4 h, seize 40 %, scatter 50 %, relief ×0.5/24 h, re-arm 4 h, floor 23, loss 0.5, failure spike 20, cost band 1.08–1.12, milestones ×2, catch-up 8 h @100 %) | R4 | **unchanged** | The R4 shape held; the failures were in arrival/offer pressure and the commit-line timing, not the thresholds. Catch-up stays 8 h (premium floor, validator band 4–24; R4 committed). `knight_cost_step` 1.6 stays a declared-but-unconsumed hook (M1 F4 note): no system models per-copy knight cost scaling — gear recipes + training time ARE the knight cost curve at MVP; wiring the step in is a content-curve change, not a tunable flip (recorded, not silently dropped). |

**Additive mechanics (no scope growth, both tunable-backed):** the
`dismiss_offer` command (send a gate loiterer home — quiet, free, frees a
gate slot; event `recruit_dismissed`; UI-free API) and the gate-capacity
arrival pause (above). The sensible-play policy (`_full_stack.manage`) now
uses dismissal: at the population cap the remaining offers are sent home
(accept-what-fits, dismiss-the-rest, with locally counted room — the old
loop read stale state and overshot the cap by up to the offer count).

## 3. The recorded sweep (2026-09-15, seeds 20261201+, commit line 450‰)

Opening (sim-minutes from run start, mean of measured seeds):

| config | first recruit | first worker | first food trickle | arrivals in 2h |
|---|---|---|---|---|
| before (R4 seeds, no dismiss) | 118 | 155 | 168 | 0 |
| + dismissal affordance | 118 | 155 | 168 | 0 |
| + presence weights 0.3/0.05 | 118 | 155 | 168 | 0 |
| + gate capacity 6 | 7 | 45 | 58 | 4 |
| **chosen (rush + weights + gate + garrison 50)** | **7** | **45** | **58** | **4** |
| rush-uniform-8 | 7 | 45 | 58 | 8 |
| rush-ramp-8-fast | 6 | 45 | 58 | 5 |

Pressure — 1000h sensible-play stream, seed 20261001 (the T-QA-02 seed;
recorded pre-pass history: **7 crushes**, 25 strikes):

| config | crushes | strikes | cancels | warns | peak | alive |
|---|---|---|---|---|---|---|
| before (R4 seeds, no dismiss) | **6** | 26 | 0 | 10 | 100 | yes |
| + dismissal affordance | 0 | 2 | 0 | 3 | 77 | yes |
| + presence weights 0.3/0.05 | 0 | 0 | 0 | 0 | 14 | yes |
| + gate capacity 6 | 0 | 0 | 0 | 0 | 24 | yes |
| **chosen** | **0** | 0 | 0 | 0 | **24** | yes |
| weights-old (0.5/0.1) | 0 | 2 | 0 | 4 | 76 | yes |

The "before" decomposition row reproduces the recorded finding (6 vs 7
crushes: the policy's accept-room fix removed a one-unit cap overshoot the
old stream had — the overshoot made the estate slightly louder; the ratchet
is the same). Dismissal ALONE removes the crushes (offers no longer pile);
the weights then pull the measured estate below warn entirely; the gate
capacity bounds the away-window stack structurally.

Greed probe (military 24, population 40, never lays low, ≤400 h): every
configuration is crushed — chosen at ~28 h after 3 warns. The failure mode
lives on the greedy side of the line (the crush comes from presence +
ignored telegraphs out-pacing the 4 h countdown, not from a mechanic the
player cannot see coming).

First win (player model above; commit at 450‰):

| cadence | sim-h/wall-day | won | mean | slowest | losses | recovery mean |
|---|---|---|---|---|---|---|
| 6 h (4/day) | ~24 | 12/12 | **79 h** | 127 h | 11 | 29 h |
| 8 h (3/day) | ~24 | 12/12 | 117 h | 217 h | 12 | 62 h |
| 12 h (2/day) | ~16 | 12/12 | 117 h | 217 h | 12 | 62 h |

(8 h and 12 h rows are the same sim script: the catch-up cap clamps both to
8 h of accrual per cycle; only the wall-clock differs.) Garrison axis at
6 h cadence: **50 → 79 h mean / 12 won**, 55 → 90 h / 12, 60 → 95 h / 11.

Check-in value (mid-run, cadence 6 h): a 5-min live window sees ~+20 gross
resources; one full cycle resolves ~36 events, banks ~+1425 resources of
away accrual, and decides ~150 resources of spends (upgrade + gear).

## 4. Where the tension lives now (and where the failure lives)

- A measured estate (army 4, pop 24) is indefinitely quiet: presence 2.2/h
  vs decay 5/h, and below-warn forever in the 1000 h stream. That is the
  point: **existing is not a death sentence**.
- The tension lives in the ARMY BUILD (the fantasy): the all-in phase
  (military 12) warns and can arm telegraphs during the climb to the
  assault (6 warns / 3 telegraphs per 12 first-win runs); crackdown strikes
  land as set-backs (seize 40 %, scatter the gate) on the way.
- The crush lives at GREED: military 24 + never laying low is crushed in
  ~28 h (three ignored warnings). Between the two, weights-old rows show
  the dial still bites if a future pass wants a louder middle game.

## 5. CI pinning and how to re-tune

- `tests/acceptance/suites/economy_balance_band.gd` (16 checks): opening
  bounds (recruit ≤ 15 min, worker ≤ 60, trickle ≤ 75), 4 fixed regime seeds
  each winning ≤ 240 h with mean in [48, 96] h and tail ≤ 132 h, recovery
  ≤ 72 h, tension ≥ 1 warn, the greed crush, and check-in value > 0.
- `economy_stability_1000h` now asserts the tuned reality honestly:
  crushes ≤ 1, suspicion peak < warn under sensible play, structural
  telegraph/strike/crush/restart rules unchanged.
- To re-tune: edit the defaults in `content/schema/economy_tunables.gd`,
  `make balance-sweep`, update this doc's tables, then the band bounds.
  The sweep's decomposition rows ("before" = R4 seeds + no dismissal) exist
  so the next pass always has its before/after on one harness.
