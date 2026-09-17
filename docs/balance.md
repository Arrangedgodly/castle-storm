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

**FOLLOW-UP RETUNE (2026-09-17, the deferred backlog sweep — journey-1
trickle timing):** content-DATA only, no tunable or logic change —
`worker.training_time_hours` 0.5 → **0.0** (chores are zero-hour: the hoe
is picked up on the way to the field) and `farm.base_production_per_worker_hour`
6 → **24** (the first whole food lands ~2.5 min after staffing). The first
visible food trickle moved **minute 58 → 22** on this harness's 5-minute
manage cadence — **minute 12** on the player-paced reading
(`test_first_session`'s documented sensible path) — inside the town-hall
10–15 min first session. First worker: 45 → 16 min. The first-win band is
UNMOVED (re-swept below: 12/12 seeds, mean 79 h, slowest 127 h — sensible
play was never food-gated; the retune widens the opening only). The
first-trainee half of the follow-up was measured and REJECTED: cutting the
2 h militia drills to 1.0 h or 1.5 h pushed the first-win tail to 169 h
(past the 132 h bound) and +3 assault losses (faster militia completions
churn the suspicion acts), so `militia.training_time_hours` stands at 2.0
and the trainee hop keeps its ~141-min idle cadence. Sections 1/3 below
carry the re-measured rows; the 2026-09-15 pass's reasoning tables stand
otherwise.

## 1. The targets (town-hall / R4 → task contract)

| Target | Source | Measured (chosen) |
|---|---|---|
| First recruit ≤ 15 real min of the first session | journey 1 (M1 finding F2: was ~118 min, 8–12× late) | **7 min** (metronome — zero variance) |
| "I get it" session 10–15 min: assignment + first trickle visible fast | journey 1 | first worker **16 min** (rush + zero-hour chores; was 45), first food trickle **22 min** on the 5-min manage cadence / **minute 12** player-paced (was 58) — the 2026-09-17 follow-up |
| First win in the 2–4 day band at sensible pace (3–5 min check-ins) | town-hall | **mean 79 sim-h ≈ 3.3 wall days** at 4 check-ins/day (12/12 seeds, slowest 127 h) — unchanged by the follow-up |
| 1000h stability: ≤ 1 crush under sensible play; crushes from GREED not existing | task contract (T-QA-02 finding) | **0 crushes**, suspicion peak 24 (< warn 35); the greed probe crushes at ~28 h |
| Failed-assault recovery ~day-scale | task contract | **mean 29 h** loss→win (6 multi-loss runs) |
| Check-in value (resources gained per 5-min window mid-run) | task contract | **~+46 gross resources** per 5-min live window (the faster farm); one full cycle resolves ~36 events, banks ~+3369 away accrual, decides ~150 resources of spends |

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

## 3. The recorded sweep (2026-09-15, seeds 20261201+, commit line 450‰;
## re-run 2026-09-17 on the follow-up retune's content)

Opening (sim-minutes from run start, mean of measured seeds; 2026-09-17
re-run — the "before" decomposition rows now ride the retuned worker/farm
content on their pre-T-SIM-08 TUNABLE overrides, so their opening numbers
moved too; their job is the rush/gate decomposition, which stands):

| config | first recruit | first worker | first food trickle | arrivals in 2h |
|---|---|---|---|---|
| before (R4 seeds, no dismiss) | 118 | 126 | 132 | 0 |
| + dismissal affordance | 118 | 126 | 132 | 0 |
| + presence weights 0.3/0.05 | 118 | 126 | 132 | 0 |
| + gate capacity 6 | 7 | 16 | 22 | 4 |
| **chosen (rush + weights + gate + garrison 50)** | **7** | **16** | **22** | **4** |
| rush-uniform-8 | 7 | 16 | 22 | 8 |
| rush-ramp-8-fast | 6 | 16 | 22 | 5 |

(2026-09-15's recorded opening on the pre-retune content — worker 45 min,
trickle 58 min — is superseded by the rows above; the harness's manage
cadence is 5 sim-min, so the player-paced trickle lands earlier than the
table's 22: minute 12 on test_first_session's documented sensible path.)

Pressure — 1000h sensible-play stream, seed 20261001 (the T-QA-02 seed;
recorded pre-pass history: **7 crushes**, 25 strikes; 2026-09-17 re-run —
unchanged by the retune):

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
configuration is crushed — chosen at ~28 h after 3 warns (2026-09-17
re-run). The failure mode lives on the greedy side of the line (the crush
comes from presence + ignored telegraphs out-pacing the 4 h countdown, not
from a mechanic the player cannot see coming).

First win (player model above; commit at 450‰; 2026-09-17 re-run — the
band is unmoved by the opening retune):

| cadence | sim-h/wall-day | won | mean | slowest | losses | recovery mean |
|---|---|---|---|---|---|---|
| 6 h (4/day) | ~24 | 12/12 | **79 h** | 127 h | 11 | 29 h |
| 8 h (3/day) | ~24 | 12/12 | 117 h | 217 h | 12 | 62 h |
| 12 h (2/day) | ~16 | 12/12 | 117 h | 217 h | 12 | 62 h |

(8 h and 12 h rows are the same sim script: the catch-up cap clamps both to
8 h of accrual per cycle; only the wall-clock differs.) Garrison axis at
6 h cadence (2026-09-17 re-run): **50 → 79 h mean / 12 won**, 55 → 90 h /
12, 60 → 95 h / 12 (slowest 145 h).

Check-in value (mid-run, cadence 6 h; 2026-09-17 re-run): a 5-min live
window sees ~+46 gross resources (the faster farm); one full cycle resolves
~36 events, banks ~+3369 resources of away accrual, and decides ~150
resources of spends (timber 86 / food 28 / iron 35).

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
  bounds (recruit ≤ 15 min, worker ≤ 30, trickle ≤ 30 — tightened with the
  2026-09-17 follow-up retune; measured 7 / 16 / 22), 4 fixed regime seeds
  each winning ≤ 240 h with mean in [48, 96] h and tail ≤ 132 h, recovery
  ≤ 72 h, tension ≥ 1 warn, the greed crush, and check-in value > 0.
- `tests/acceptance/suites/escalation_ladder_band.gd` (55 checks, L2-B):
  the chained-campaign ladder on 6 fixed seeds — the reference (static)
  run in band, cycle 1 beatable barefoot in the similar band, cycle 2
  barefoot, partial tree (the 3 tier-1 economy nodes) cycles 1-2, full
  tree cycles 1-5 all won with growth ≤ 1.5× and rising walls (§7).
- `economy_stability_1000h` now asserts the tuned reality honestly:
  crushes ≤ 1, suspicion peak < warn under sensible play, structural
  telegraph/strike/crush/restart rules unchanged.
- `test_mvp_pack` pins the retuned content data (farm 24 food/h; the
  M1-measured camp/smithy rates stand); `test_first_session` pins the
  player-paced opening (gate 7, choice arc < 15, trickle ≤ 16, trainee
  ≤ 170 — the retune's goal and its honestly-rejected half).
- To re-tune: edit the defaults in `content/schema/economy_tunables.gd`
  (or the content data the opening rides on — units/buildings `.tres`),
  `make balance-sweep`, update this doc's tables, then the band bounds.
  The sweep's decomposition rows ("before" = R4 seeds + no dismissal) exist
  so the next pass always has its before/after on one harness.

## 6. L1 — the legacy unlock tree (L1-B, 2026-09-17): cost curve + the full-tree probe

Worker: Mr Fantastic + Prof X lane. Harness: `make balance-sweep`'s
"L1 full-tree probe" section (the first-win player model above, cadence 6h,
commit 450 permille, the shipped tree purchased whole through the REAL
LegacySystem -> run-start modifier path — `_full_stack.session` gained the
optional legacy provider exactly as GameHost wires it).

**The shipped tree** (`content/mvp/unlock_tree.tres`, attached to the MVP
pack; CopyDeck-voiced per docs/voice-bible.md): 15 nodes, 4 branches —
the L1-B comfort tree plus L1-B2's pressure-model branch:

| branch | nodes (costs) | effects (compound) |
|---|---|---|
| The Old Guard — the pantry ladder | Grandma's Recipes 60 -> The Seed Drawer 140 -> The Emergency Cheese 260 | stipend x1.10 / x1.10 / x1.08 = **x1.306** |
| The Workshop — the makers | The Union of Unpaid Artisans 80 -> The Mason's Secret 180 -> The Salvage Charter 310 (the charter also gated by The Smith's Signature 220 <- A Cousin in Ironmongery 120) | building x0.95 / x0.93 / x0.91 = **x0.803**; gear x0.95 / x0.90 = **x0.855** |
| The Yard — the drills | The Sergeant's Primer 100 -> The Drill-Song Book 140 + The Sand Yard 170 -> War Games on Sundays 230 | training x0.98 / x0.97 / x0.97 / x0.96 = **x0.884** |
| The Survivors — the ones who came back (L1-B2) | Quiet Boots 110 -> Scarred Banners 250 -> The Night Watch 330 | suspicion decay x1.05 / x1.10 = **x1.155**; veterans x1.08 |

The **arrival lever is deliberately absent** (the one L1-A effect kind the
tree does not use — measured dead above x1.0 and harmful below; evidence
below). Exact compounds are pinned in `tests/unit/test_mvp_unlock_tree.gd`
(milli: 1306 / 803 / 855 / 884 / 1155 / 1080 / identity).

**The cost curve, against the measured earn rates.** Score = duration +
army power + 100 win bonus -> the recorded ~150-260 lp/run band: a 79 h
first win banks ~230-260; an early loss/crush ~150. The curve:

| tier | nodes | costs | buyable from |
|---|---|---|---|
| 1 (ungated) | 5 | 60 / 80 / 100 / 110 / 120 | run 1's bank (even a losing run) |
| 2 (one gate) | 6 | 140 / 140 / 170 / 180 / 220 / 250 | runs 2-4 |
| 3 (capstones) | 4 | 230 / 260 / 310 / 330 | runs 5-10 |

- **Total 2700 lp = ~8-12 runs** at the measured band (the full-tree
  player trends toward the rich end: compressed ~70 h wins bank ~200-240,
  losses ~150) — the L1-B2 contract band; pinned [2400, 3000] so a
  node-add cannot silently halve or double the campaign.
- Rationale: tier-1 is cheap and plural (R5's Rogue-Legacy finding:
  breadth-first economy nodes first, something visible per early run);
  costs strictly increase along every prerequisite edge (one rising curve
  per branch, never a cheap capstone behind an expensive approach — the
  monotonic pin); each branch rises ~2.3-4x gate -> capstone.

**The full-tree probe** (12 seeds, 20261201+; the L1-B rows recorded
2026-09-15, re-run 2026-09-17; the L1-B2 rows recorded 2026-09-17 on the
15-node tree; re-verified at the L1-D close 2026-09-17 — baseline and
full-tree rows reproduce exactly, bundle / pressure / greed lines
unchanged):

| config | won | win mean | slowest | losses | crushed |
|---|---|---|---|---|---|
| baseline (zero purchases) | 12/12 | **79 h** | 127 h | 11 | 0 |
| L1-B tree (the 12 economy nodes) | 12/12 | **83 h** | 175 h | 13 | 0 |
| **full tree (all 15 nodes, L1-B2)** | 12/12 | **70 h** | 115 h | 9 | 0 |

(L1-B's 24-seed confirmation: baseline 85 h / 24/24, full tree 87 h — the
+2-4 h delta was inside the band's seed noise; every run still winning
either way. Pressure at full tree — the 1000 h sensible stream, T-QA-02
seed: **0 crushes / 0 strikes / 0 warns, suspicion peak 22** (< warn 35):
the suspicion model is intact under the whole tree.)

**The honest finding: the first-win band is act-rate-limited, not
resource-limited — no L1-A effect composition compresses it.** The L1-B
brief hoped for ~20-35% faster at full tree. Measured (branch-isolation +
raw-bundle probes, 12-24 seeds each):

| probe | win mean | reading |
|---|---|---|
| gear x0.75 alone | 79 h — **identical to baseline to the digit** | gear is never the binding cost under sensible play (away accrual ~3369/window dwarfs the recipes) |
| arrivals x1.10-1.20 | identical to baseline | arrivals are ACCEPTANCE-gated (a full gate pauses the road); a quieter road changes nothing |
| arrivals x0.955 (+ stipend x1.45) — v1's Old Guard | 103 h | faster arrivals multiply the gate-crowd acts (+8 each past tolerance 3): pure heat |
| training x0.77 — v1's Yard | 85 h | compressed completions ratchet the meter (loud acts above warn freeze decay — the SAME mechanism the 2026-09-17 retune rejection measured at baseline) |
| **v1 full tree** (arr x0.855, bld x0.726, trn x0.770, gear x0.855, stp x1.454) | **96 h (12 seeds) / 97 h (24), losses 11 -> 18-33, 11/12 won** | **REJECTED** — meta progression that makes every run slower |
| chosen v2 (the shipped compounds) | 83 h / 87 h | band-neutral within noise |

Why: crossing the commit line is paced by the training pipeline x the
check-in cadence, with resources over-accumulated. Every accelerator in
the vocabulary concentrates the FIXED act count (training completions +8
militia/knight, building levels +4, gate crowds +8) into fewer hours;
decay (5/h minus presence drift) cannot clear it between batches, the
meter rides higher, and warns/telegraphs stall the military pipeline.
Cost cuts only shift building acts slightly earlier; the one strictly-safe
kind (gear cost — equips are not acts) is inert in this policy. This is
the L1-side twin of the retune's rejected trainee half.

**What the tree therefore sells** (all real, all felt, none band-breaking):
+31% stipend (a visibly richer opening — 50 -> 65 food, 80 -> 104 timber),
-20% walls / -15% gear recipes (every check-in's spends go further;
post-loss re-equips hurt less), -12% drills (the pipeline breathes faster
without ratcheting the meter). The BASELINE band is untouched (the CI band
suite runs zero purchases and passes unchanged); the full tree stays
inside the band's noise with every run still winning.

### 6b. L1-B2 — the pressure-model extension (2026-09-17): suspicion_decay + veterans

Worker: Iron Man lane (effects + tree), Hawkeye lane (the balance truth).
The L1-B finding above asked for an L1-A vocabulary extension into the
pressure model or the odds curve. L1-B2 shipped exactly two kinds —
`suspicion_decay` (a multiplier on the passive −5/h decay, both tiers
proportionally, applied at the run-start fold through the same
legacy-modifier seam) and `veterans` (a multiplier on the army side of
the assault odds math only — `raw_power x regime x veterans`; the commit
floor and score banking read the RAW power) — plus the tree's 4th branch,
**The Survivors** (Quiet Boots / Scarred Banners / The Night Watch).

**The honest measurement (12-seed isolation probes, one lever at a time
on the 15-node tree):**

| probe | win mean | reading |
|---|---|---|
| L1-B 12-node tree (control) | 83 h | the act-rate-limited baseline of §6 |
| **veterans x1.08 alone** | **70 h** (12/12, losses 13 -> 9) | **the compression lever**: the 450-permille commit line is crossed one pipeline batch earlier — the odds hop, not the meter |
| veterans x1.10 / x1.12 | 70 h — identical to the digit | the plateau is QUANTIZED by the check-in cadence: no batch to skip, no gain |
| veterans x1.15 / x1.20 | 71 h, **11/12 won**, losses 15 | the cliff: committing at thinner rosters trades wins for speed — rejected |
| suspicion decay x1.4375 alone | 82 h | decay is COMPRESSION-INERT in this policy (the modeled player's meter rides below warn either way) — and at the task's example magnitude it still buys 0 h of win time while breaking the greed line (below) |
| decay x1.155 … x1.4375 ON TOP of veterans x1.08 | 70 h — identical to veterans alone at every magnitude probed | the meter was never the stall in this policy; the odds line was |

**The plateau is structural, not tunable**: at the sensible cadence the
commit line lands at check-in granularity, so 79 h -> 70 h (~11%, the
12-seed mean) is everything the two kinds can buy without starting to
lose runs. The 12-seed full-tree target band "~62-70 h" is met at its
edge (70 h, 12/12 won, slowest 115 h vs baseline 127 h, losses 11 -> 9);
the ~12-22% hope above ~12% needs a cadence/commit-line change (the
player model), not more multiplier.

**The pressure retune (Hawkeye's line): the decay node magnitudes were
cut from the task's examples (x1.15/x1.25) to x1.05/x1.10 — the greed
crush demanded it.** At compound x1.4375 the failure-mode probe ERODED
seed by seed: seed 20261201 survived 400 h of military-24 /
never-lay-low (11 warns, 6 strikes, no crush; baseline crushes it at
~28 h). At x1.265 a different seed survived. The shipped x1.155 keeps
the teeth: the harness's greed probe crushes at **27 h on both recorded
seeds** (baseline 28 h), and the 1000 h sensible stream stays quiet
(peak 22 < warn 35). Greed's net presence is ~+0.8/h over even a x1.4
decay — the failure mode survives on margins that thin, which is exactly
why the compound is pinned under x1.25 in test_mvp_unlock_tree.

**What The Survivors therefore sells**: the commit line arrives one
batch earlier (veterans x1.08 — felt every run), and the meter cools
~15% faster (decay x1.155 — felt in the telegraph-cancel window, the
lay-low recovery and the post-crackdown dip; deliberately small so the
Crown keeps its bite). Baseline digests: byte-identical (every existing
marathon suite green, unchanged); the zero-impact proof extends to both
new seams (serialized + hashed only when non-identity).

## 7. L2 — the escalation ladder (L2-B, 2026-09-17: the tuned curve + the climbability pass)

Worker: Hawkeye + Prof X lane. Harness: `make balance-sweep`'s "L2
escalation ladder" section (`CS_SWEEP_ONLY=escalation` re-runs it) —
CHAINED CAMPAIGNS on the canonical host with escalation wired (the
shipped game's wiring): run 1 is the static first win (the shared meta
starts bare — the zero-impact rule, so the campaign's own run 1 doubles
as the no-snapshot probe), its victory CAPTURES the winning army, and
every later run is a fresh engine around the SAME meta (`_full_stack`
gained the additive `p_meta` injection — the host's one-shared-meta
rule). Cadence 6h, commit 450 permille, cap 360h/cycle, 12 seeds.
CI pin: `tests/acceptance/suites/escalation_ladder_band.gd`.

**The L2-A anchor was wrong, and the sweep corrects it:** §7's
placeholder note estimated "a typical winning army ~100-115 power already
doubles the static 50 wall". Measured: the sensible player's winning army
is **~43-55 power** (the commit line crosses at `0.818 x wall` — the
clump of trainings that lands the batch the odds cross 450 permille), so
**cycle 1's wall (the snapshot itself, ×1.000) opens at the static 50
wall's own scale** — a like-for-like rebuild opens cycle 1 at ~500
permille, exactly the "first L2 cycle is a full new campaign" arc (R5):
the arc is a full estate+army rebuild, not a doubled wall.

**The chosen curve: step ×1.10** (was the ×1.25 placeholder), compounded
(cycle−1) — the engine's shipped shape, only the number moved. The
mechanism that makes a SMALL step right: **the snapshot self-damps** —
a 450-permille commit captures only ~0.82× the wall's power, so in
steady state the wall grows `~0.82 x step x regime-mult ≈ ×1.0` per
cycle; the step's exponent only surfaces from cycle 3. The step
candidates (full tree, cycles 1-5, 12 seeds each):

| step | full-tree per cycle: won / mean h (mean wall) | verdict |
|---|---|---|
| ×1.00 | 12/12 75h (44) · 12/12 79h (40) · 12/12 75h (39) · 12/12 72h (39) · 12/12 67h (39) | climbs, but the ladder DECAYS (walls sink under the static 50) — no escalation at all |
| **×1.10** | **12/12 75h (44) · 12/12 79h (43) · 12/12 82h (46) · 12/12 73h (55) · 12/12 102h (71)** | **climbs — the ladder holds** |
| ×1.15 | 12/12 75h (44) · 12/12 75h (45) · 12/12 86h (55) · 12/12 90h (68) · 11/12 110h (109) | bites one cycle early |
| ×1.20 | … 11/12 112h (85) · 8/11 165h (160) | ceiling bites at 4-5 |
| ×1.25 (placeholder) | … 11/12 123h (109) · **4/11** 151h (212) | rejected — 7 of 11 stall |

**The ladder table** (shipped step ×1.10; the modeled campaign shapes:
**no tree** = zero purchases; **partial** = the 3 tier-1 economy nodes
(240 lp ≈ run 1's bank — Grandma's Recipes, The Union of Unpaid
Artisans, The Sergeant's Primer; NO veterans branch: Scarred Banners +
prerequisite = 360 lp ≈ two wins); **full tree** = all 15 nodes from run
1, the climbability ceiling probe):

| cycle | garrison wall (mean) | no tree | partial tree | full tree |
|---|---|---|---|---|
| 0 (static) | 50 | 82h mean (the first-win band, unmoved) | — | 75h mean |
| 1 | 44 | 12/12, 82h mean, 205h slow | 12/12, 82h | 12/12, 75h, 175h slow |
| 2 | 43 | 12/12, 78h | 12/12, 77h | 12/12, 79h |
| 3 | 46 | 12/12, 93h | 12/12, 93h | 12/12, 82h |
| 4 | 55 | 12/12, 106h | 12/12, 106h | 12/12, 73h, 115h slow |
| 5 | 71 | 11/12, 119h, 278h slow | 11/12, 108h | 12/12, 102h, 175h slow |

**How the contract reads against it:**

- **Cycle 1 is beatable by a partial-tree (and even a zero-tree) player
  in the similar band** — 82h vs the 79h first win: the wall is your own
  last army at ~44-54 power, the arc is the full rebuild. The ladder's
  first rung is a campaign, not a spike.
- **Cycles 2-3 consume the headroom progressively**: barefoot times
  inflate 78 → 93h while full tree holds 79 → 82h — the same wall costs
  the un-tree'd player more each cycle. The hard fork lands at 4-5, where
  the step's exponent surfaces: no tree 106 → 119h (one seed of twelve
  stalls at cycle 5), full tree 73 → 102h. The tree is the ladder's
  handrail — the odds-hop veterans node (Scarred Banners, 360 lp ≈ two
  wins) is the purchase that holds the band.
- **Full tree climbs 12/12 through cycle 5** with per-cycle growth ≤1.4×
  (73 → 102h) and the wall rising 44 → 71: the ladder is real, never a
  stall. (The full-tree row's honest asterisk: a real campaign reaches
  the full tree around runs 8-12 at the measured earn rates — the row is
  the climbability ceiling, the partial row is the early campaign.)
- **Why not steeper**: ×1.15 already drops one full-tree seed at cycle 5
  and the placeholder ×1.25 stalls 7 of 11 there — the snapshot
  self-damping means the felt escalation per cycle is `0.82 × step`, so
  the intuitive "×1.25 per victory" is really "×1.02 net early, then
  superexponential" — the ceiling (the sensible policy's ~138-power
  12-unit army) arrives two cycles later but arrives HARD.

**Zero-impact, re-proven:** the static first-win band, the pressure and
greed rows, and every §3/§6 table are byte-unmoved (the sweep's own
no-snapshot sections re-ran unchanged; `economy_balance_band` pins the
static ladder on the unwired fixtures and passes untouched). The CI
ladder suite pins the chained campaigns on 6 fixed seeds (55 checks:
reference run in band, barefoot cycles 1-2, partial cycles 1-2, full
tree cycles 1-5 all won, growth ≤1.5×, walls rising).

**The flavor (L2-B's CopyDeck presence, budget-pinned per voice-bible
§4):** `garrison_escalation` (the odds castle card when a captured
garrison stands: "garrison 46 · Ottilie's veterans — cycle 2" — the
leader prints by first name, the single-line pool rule), 
`escalation_captured` (the strip's victory beat: "Ottilie's veterans take
the wall — cycle 2." — seq-rotated, 2 variants), and
`chronicle_escalation` (the victory chronicle entry's line: "this army
holds the castle — cycle 2 opens" — the entry's `escalation_cycle` field
rendered, run-number-rotated). The capture beat rides a NEW engine event
(`escalation_captured`, same tick, before `run_won`, value = the cycle,
value2 = the wall-taking power) and the chronicle field is
emit-when-set (save-schema §5.1) — a non-capturing victory prints and
records nothing, byte-identical to pre-L2-B.
