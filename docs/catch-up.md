# Offline Catch-Up — Castle Storm (T-SIM-07)

The authoritative contract for what happens to the simulation while the
player is not looking. Implementation: `sim/catch_up_service.gd`
(`CatchUpService`); the persisted anchor is `RunMeta.last_seen_epoch`
(save-schema §5). Engine-facing summary: sim-engine.md §16. R4 research
basis: `docs/ultron/research/r4-idle-balance-references.md` §A.

## 1. The rule

**8 hours of real elapsed time accrue at 100% (linear), then stop.**

```
elapsed        = now_epoch − last_seen_epoch          (UTC epoch seconds)
clamped        = clamp(elapsed, 0, cap_seconds)       (cap = 8h default)
applied_ticks  = clamped ÷ 60                         (floor; 1 tick = 1 sim-min)
```

- `cap` comes from `EconomyTunables.offline_cap_hours` (R4 seed 8, validator
  band 4–24; sub-8h is an F2P monetization device — rejected).
- 100% linear is the premium norm (Melvor, Tideward); `offline_rate` exists
  as a tunable but is pinned to 1.0 by the validator, so the math has no
  rate term on purpose. Diminishing offline curves pair with ad-watching,
  which this game will never have.
- The clamped gap is replayed through the REAL engine's `fast_forward`:
  arrivals, training, production, suspicion decay — everything advances by
  the actual deterministic rules. There is no parallel accrual formula to
  drift out of sync with the game. 8h = 480 ticks, resolved synchronously
  (measured 7ms full-stack in `marathon_catch_up_gap`; budget <100ms).
- Sub-tick remainders are discarded: a 59-second window applies 0 ticks and
  the anchor snaps to `now`, so the error is bounded by <1 sim-minute per
  away window and never accumulates across foregrounds.

## 2. Away-time semantics (precise)

**Away = the platform says the process is not being played.** Concretely,
per platform: the app is backgrounded/occluded (mobile OS background
notification; desktop window hidden/minimized per host policy), or the
player explicitly paused-away via a host "pause & exit" affordance. The
service itself consumes **platform-provided UTC epoch timestamps only** —
`apply(engine, meta, now)` takes `now` as a parameter, and `sim/` code
reads no clocks at all (gdscript-conventions: time arrives as tick counts
or injected timestamps).

- **Playing sessions never count as away time.** While foregrounded, the
  host refreshes the anchor (`mark_seen`) — on background notifications,
  on every save, and after every catch-up. The anchor is therefore "the
  last moment the host vouched for the player being present."
- **In-app pause is a world freeze, not away time.** A paused engine
  accrues NOTHING (`fast_forward` refuses while paused; the service
  reports `skipped_paused` instead of forcing it). Pausing and quitting
  keeps the freeze: the reload finds `paused` in the run save, skips
  catch-up, and the player unpauses into the world they left. Freeze is a
  deliberate single-player courtesy (a player who wants to stop the clock
  can; the cap already bounds what anyone gains either way).
- If the process is killed without a clean background (crash, force-quit),
  the anchor is stale by at most the host's save interval: the next launch
  treats the unsaved play window as away time. Bounded by the cap;
  acceptable by design (below).

**T-PERF-01 (landed 2026-09-15): the wiring.** `ui/host/app_lifecycle.gd`
(`AppLifecycle`) maps the engine's OS notifications onto the host seams,
with every timestamp injected by the game screen's `_notification` (the
one permitted clock read — the platform host):

| Notification (Node) | Platforms | Action |
|---|---|---|
| `NOTIFICATION_APPLICATION_PAUSED` | Android/iOS/web | `host.background(now)` — pacing gate closes, away anchor taken, both save domains flushed. The OS then suspends the whole process (main loop AND rendering stop engine-side by themselves — the notification exists so the game can flush first), so the flush is the entire job. |
| `NOTIFICATION_APPLICATION_RESUMED` | Android/iOS/web | `host.foreground(now)` — the away window resolves through the real engine (capped) and pacing resumes. |
| `NOTIFICATION_WM_CLOSE_REQUEST` | desktop | the same background flush before the process dies (mobile never sends it — a suspended process is killed without further notice; PAUSED is the mobile flush moment). |
| `NOTIFICATION_APPLICATION_FOCUS_OUT/_FOCUS_IN` | desktop + Android | **see the decision below.** |

**Desktop focus decision of record:** losing window focus on desktop does
NOT background the host. This is an idle game — the player expects the
conspiracy to keep working while they tab away; the session never stopped,
so no window is owed on return. The pacing accumulator consumes wall-clock
deltas at 1× whatever the frame rate (a suspended-then-restored desktop
process replays its gap as one live batch: measured 59.9 ms for a 3-day
delta, `scripts/perf_probe.gd`), and the hourly autosave keeps the anchor
fresh. The engine does keep submitting frames while the window is
unfocused — accepted: the game layer costs +0.31 ms/frame idle (measured,
T-PERF-01's probe; the compositor skips presenting an occluded window),
and `low_processor_usage_mode` was rejected because it caps the whole
game at ~20fps (T-PERF-02's 60fps target). Hosts that want focus-loss to
count (kiosk/battery-strict builds) set
`AppLifecycle.desktop_backgrounds_on_focus_loss = true`. Both edges are
idempotent: a second PAUSED cannot stretch the window (the anchor never
moves twice), a second RESUMED cannot resolve twice (no double
fast-forward, no duplicate reports).

## 3. The anchor

- Stored as `RunMeta.last_seen_epoch` — UTC epoch **seconds**, an int, in
  the META save domain (away time crosses run boundaries, so the anchor
  must outlive any single engine). Additive-optional key with a tolerant
  reader (absent = 0); no migration (save-schema §5, the
  `regime_quirks`/`stipend_run` precedent).
- **0 is the first-launch sentinel**: never marked → no anchor → no
  catch-up ever fires off it, whatever `now` claims. A brand-new install
  — and a pre-T-SIM-07 save upgraded in place — both land here, which is
  exactly right.
- `apply()` sets `last_seen_epoch = now` on EVERY call, rewind included.
  The service consumes timestamps; it never extrapolates them.

## 4. Clock policy (T-SEC-01's substrate; Captain America's lane)

**Stance: single-player game, no DRM, no server, no telemetry. Saves are
local files. We do not detect or punish clock manipulation — we bound it.**

| Clock event | Behavior |
|---|---|
| Set BACKWARDS (`now < anchor`) | elapsed is negative → clamped to **0**. No accrual, **no resource loss**, no state change (`state_hash` bit-identical — unit + marathon tested). The rewind is announced as a `catch_up_clock_rewound` event and a wry chronicle line ("The castle clock was found wound backwards..."). The anchor follows `now` anyway. |
| Set forwards (huge jump) | Capped at 8h. A 100-year jump awards exactly what 8h awards. |
| Rewind then forward again | The anchor followed the rewound time, so the "elapsed" when the clock normalizes includes the rewind span — **still capped at 8h**. |

What a player "gains" by cheating the clock: at most one capped window
(8h of linear accrual) per manipulation cycle, the same award as leaving
the game closed overnight — twice. That is a nuisance ceiling, not an
economy break: every accruable quantity (resources, arrivals, training,
suspicion) is bounded per-window by the engine's own curves, and
suspicion pressure accrues TOO (a cheater's estate gets louder, not
richer). We spend zero code on detection and keep zero secrets: the clamp
rules ARE the policy, and they are property-tested (T-QA-04's fuzz target
is the pure function; the invariants — never negative, never uncapped,
monotone — are already pinned over generated inputs in
`tests/unit/test_catch_up_service.gd`).

## 5. DST, timezones, and why they cannot matter

**UTC epoch seconds everywhere, internally and on disk. Local time is
never stored, never computed on, never displayed as an input.** Unix
epoch time is DST-invariant by definition (a "spring forward" gap is a
labeling change, not an elapsed-time change): `elapsed` is always a plain
subtraction of two UTC readings, so a DST transition inside an away window
is indistinguishable from any other second. Traveling timezones changes
only how the OS renders `now` — the epoch it hands the host is the same
instant. There is nothing to test beyond the arithmetic, and the
arithmetic is fuzzed.

## 6. Crash safety / no partial state

`apply()` is synchronous and completes before gameplay resumes. A process
kill during the fast-forward leaves the on-disk save untouched (it still
holds the pre-catch-up state — the anchor and engine state that WOULD have
produced the same catch-up); the next launch simply recomputes the gap
from the anchor, deterministically (same seed, same commands, same
result — `marathon_catch_up_gap`'s kill test proves the revived engine
lands bit-identical to a live twin). Saves made DURING an away window are
the normal case, not an edge: the background-time save IS the window's
opening bookend.

## 7. The summary (T-UI-09's data)

One `catch_up_applied` ring event (value = applied ticks, value2 = clamped
seconds) — the ring tail keeps the raw per-tick events for detail; we do
not replay thousands of events at the player. The returned report
Dictionary carries: flags (`first_launch`, `rewound`, `capped`,
`skipped_paused`), the raw/clamped/applied numbers, per-type resource
deltas, arrivals, training completions, promotions, run endings,
crackdowns that landed inside the window, and the suspicion delta.
`CatchUpService.chronicle_line(report)` renders the Prof X placeholder
lines (rewind / freeze / capped / plain; empty for a nothing-happened
foreground).

**T-UI-09 (the consumer, landed 2026-09-15):** the resumed session opens
with the intro's SHORT unfold variant (`VARIANT_RESUMED`, 1.0s sweep +
0.75s dwell, auto or one gesture), then the window prints as a
while-you-were-away chronicle BLOCKQUOTE on the table
(`ui/screens/spread/catch_up_print.gd` — elapsed/capped clause, per-type
resources, arrivals/completions/promotions, suspicion delta,
crackdowns-with-weight; one quiet strip line for a nothing-happened
window; the wry line leads a rewound one). Every row is shaped to the
panel's label budget in the REAL theme face with margin (the T-UI-06
no-clip standard; font-metric pinned per variant in the test map below —
the ≤-character count is only a secondary guard, wide glyphs made it
leaky). A window resolved inside
`boot()` fires its signal before any screen connects, so `GameHost.
last_catch_up_report` is the boot seam the check-in reads. Never a
"welcome back" modal — the quote dwells and folds itself, the table is
live beneath it.

## 8. Deviation of record: R4's `knight_assembly_offline` row

R4 sketched "new recruit arrivals + assault only when app open" as a
starting point for which verbs progress offline. NOT implemented as a
gate: the whole engine fast-forwards (Thor's directive — the REAL engine,
one code path, determinism preserved; a verb-gated catch-up would fork the
simulation into offline/live variants that can drift, for a balance nicety).
Consequences while away: arrivals stack up as gate offers (and their gate
presence accrues suspicion pressure honestly), training timers run out,
assaults are impossible (a commit is a player command — commands only
exist while playing).

**RESOLVED 2026-09-15, T-SIM-08 (recorded decision): implemented in
SPIRIT as the gate capacity, not as a gate.**
`EconomyTunables.recruit_gate_capacity` (tuned 6) makes the units system
PAUSE the arrival countdown while the gate holds a full capacity of
concurrent offers — one uniform rule that cannot tell offline from online
ticks, so there is no sim fork: an away window of any length stacks AT
MOST a gate's worth of recruits (an 8h capped window stacks ≤5 at the 2h
cadence — the gate does not even fill; a longer-future cadence or slower
check-ins self-limit at exactly 6). You still cannot amass an army
offline — accepting is a player command — which is the R4 row's actual
concern, and the `dismiss_offer` command (T-SIM-08's refusal affordance)
plus this bound keep gate-offer pressure manageable forever
(docs/balance.md §2/§3 — the T-QA-02 crush-ratchet finding this closes).

## 9. Test map

| Case | Where |
|---|---|
| clamp/boundaries (0, 59s, 60s, exactly-cap, +1s, +59s, +60s, 100y) | `tests/unit/test_catch_up_service.gd` `test_clamp...`, `test_applied_ticks_boundaries` |
| never negative / never uncapped / monotone over generated inputs | same file, `test_pure_math_invariants_over_generated_inputs` (2000 seeded pairs — the T-QA-04 surface) |
| int64-extreme timestamps (overflow-safe subtraction) | same file, `test_elapsed_between_overflow_safe` |
| backwards clock (no loss + wry line) | same file + `marathon_catch_up_gap` |
| first launch | same file + `marathon_catch_up_gap` |
| paused freeze | same file, `test_paused_engine_freezes_the_world` |
| kill mid-catch-up / save-during-away | same file `test_kill_mid_catch_up...` + `marathon_catch_up_gap` |
| twin parity (fast-forward == live ticks) | same file + `marathon_catch_up_gap` (resources per type, hash, arrivals, suspicion) |
| compute budget (<100ms for capped 8h) | `marathon_catch_up_gap` (measured 7ms) |
| the while-you-were-away print (capped/uncapped/zero/rewound/crackdown-while-away), the check-in unfold + focus landing, input parity ×3, reduced motion | `tests/unit/test_catch_up_ux.gd` (T-UI-09) |
| notification surfaces → host seams (PAUSED/RESUMED/CLOSE/focus, notification simulation with injected epochs), pacing gate, anchor ordering, window exactness across cycles, idempotent double cycles, desktop focus decision, frozen-engine boundary, lifecycle clock discipline | `tests/unit/test_app_lifecycle.gd` (T-PERF-01) |
| every print row variant no-clip in REAL font metrics (live mounted quote label − 30px margin; the away lines on the live reveal packet — the round-1 re-dispatch pin) | `tests/unit/test_catch_up_ux.gd` `test_every_print_row_fits_the_label_in_real_font_metrics`, `test_every_away_line_fits_the_reveal_packet_in_real_font_metrics` |
