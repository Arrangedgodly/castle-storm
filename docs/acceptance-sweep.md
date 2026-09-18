# Acceptance sweep — Castle Storm MVP (T-QA-05)

The final production gate: the town-hall acceptance criteria
(`docs/ultron/town-hall.md` §"Success measures and acceptance criteria" +
PRODUCT.md §"Accessibility & Inclusion") verified as a coherent whole.
Every row below names the evidence that stands behind it in `make test`.

**State: `make test` green — 742 gdUnit4 unit/property cases + 1,455
acceptance checks, ~44s wall (budget <60s). Rows below name the evidence
at the sweep that wrote them; Layer 1's rows are §11, Layer 2's are §12.**

## The matrix results, criterion by criterion

### 1. A complete run in CI in accelerated time — PASS

- `full_run_ci.gd` (T-QA-02): recruit → economy → FAILED first storm
  (set-back survived) → mid-run away window → rebuild → VICTORY → banking
  → restart → host re-init, bit-identical replay. 40 checks.
- `marathon_assault_storm.gd`: the lose-rebuild-win arc with odds-vs-verdict
  honesty and a save round-trip mid-recovery.
- `journeys_sweep.gd` J5 (NEW): the victory arc through the REAL SCREEN —
  storm by keyboard → outcome → win-restart reveal deals the next hand
  under the redrawn regime, the won hand sealed in the chronicle.

### 2. 1,000 simulated hours, no runaway/collapse — PASS

- `economy_stability_1000h.gd`, `marathon_sim_1000h.gd`,
  `marathon_production_1000h.gd`, `marathon_units_1000h.gd`,
  `marathon_suspicion_pressure.gd`, `economy_balance_band.gd` (the
  balance band itself: first-win ~2–4 wall days, 12/12 seeds —
  `docs/balance.md`). Unchanged this task; re-verified green.

### 3. Full loop operable three ways (touch ≥48dp / controller / kb+mouse) — PASS

- **The matrix**: `docs/input-parity.md` (the full surface × action ×
  mode table with owning tests). The consolidated driver is
  `input_parity_matrix.gd` (153 checks): action-model completeness
  (every verb prints as a chip; every disabled verb its reason), the fan
  / choice card / assault / chronicle / intro gestures all three ways,
  and a full touch-only storm beside the existing pad-only
  (`deck_nav_sweep.gd`) and keyboard (`journeys_sweep.gd` J5) storms.
- **Finds fixed this task**: (a) touch had no "fold without acting" —
  the bare-table tap now folds the fan/choice card; (b) a REOPENED
  assault odds table stranded focus (the deferred chip-grab landed on a
  `queue_free`d chip) — fixed detach-before-free in
  `assault_stage.set_chips`.
- **≥48dp targets**: pinned on every focusable (`test_responsive_layout`
  grip floor + the sweeps' mounted checks; `Inks.TOUCH_GRIP_MIN` mirrored
  in the theme, equality-tested).

### 4. Layouts usable at 1280×800 / 1920×1080 / phone portrait — PASS

- `responsive_sweep.gd` (56 checks, NEW): every screen surface mounted at
  each of the four canonical sizes (720×1280, 1280×800, 1920×1080,
  800×1280) — the quiet table, the armed choice card, an open
  blockquote, the assault odds, the chronicle ledger, the leader intro —
  asserting NO control escapes the viewport's design rect and focus is
  never stranded, through LIVE resizes (one screen resized across all
  four). A dpad BFS reaches every focusable at the phone-portrait
  topology (the Deck-landscape BFS is `deck_nav_sweep.gd`'s).
- Piecemeal pins consolidated, not replaced: `test_responsive_layout.gd`
  (the lab scene, router hysteresis, topology math, focus equivalence),
  `test_assault_vignette.gd` (the vignette's own 4-size unclipped pin).

### 5. Offline catch-up: never negative, never over cap, kill-proof saves — PASS

- `catch_up_property_windows.gd`, `test_catch_up_properties.gd` (never
  negative / never over cap / DST / rewound clocks),
  `save_integrity_full.gd` (120/120 chaos loads, quarantines preserved),
  `save_marathon_roundtrip.gd`, `test_app_lifecycle.gd` (the bg/fg
  boundary seams). Unchanged; re-verified green. The check-in UX:
  `journeys_sweep.gd` J2 (print lands ≤1 per window, passive, choice
  answered, focus held) + T-UI-09's measured 1.6s
  foreground→actionable.

### 6. Randomized identity: visibly varied leaders/regimes — PASS

- `test_intro_reveal.gd` (leader/regime equality with the sim's read
  APIs, pools in the thousands), `test_mvp_pack.gd` (content schema),
  `journeys_sweep.gd` J4/J5 (the loss and win restarts deal NEW leaders,
  regimes re-drawn).

### 7. First-win ~2–4 days of casual play (balancing target) — PASS (target, not commitment)

- `economy_balance_band.gd` + `docs/balance.md` (T-SIM-08). The known
  deviation of record: journey-1's literal 10–15-minute trickle/trainee
  payoff runs ~49/~141 min at 1× (the choice arc lands at minute 8) —
  accepted at T-UI-10, routed to the T-SIM-08 follow-up
  (`docs/ultron/state.md` §Follow-ups).

### 8. Colorblind-safe: state by line-form/shape/label, never hue alone — PASS

- `test_colorblind_audit.gd` (NEW, consolidated mechanical audit):
  (1) every LIVE card state keys a line form in `Inks.EDGE_FORM_STATES`;
  (2) the four chronicle classes inject onto four distinct rule forms;
  (3) outcome seals doubly encoded (WON/CRUSHED/ABANDONED marks AND
  distinct line forms); (4) the live rail's three pips each carry their
  name label (the text channel of the shape+glyph+label triple);
  (5) the Watchful Eye's armed/watching states differ in TEXT;
  (6) urgent vs calm choice cards differ in rule form AND title;
  (7) every disabled action carries a printed reason;
  (8) the odds print as numerals + confidence words (meter blocks are
  the redundant channel).
- Owning pins kept: `test_theme_grammar.gd` §3/§7 (edge-form vocabulary,
  pip triple encoding, container shapes), the seals in
  `test_chronicle_screen.gd`, the odds in `test_assault_vignette.gd`.
- No hue-only dependency found; none fixed (the grammar was built
  form-first — T-UI-01's "state is carried by line form, never by hue").

### 9. Font scaling — PASS (supported range 1.0–1.3, applied at boot)

- The mechanism: `ui/theme/type_scale.gd` (`castle_storm/type/scale`
  project setting, 1.0 default; `CS_TYPE_SCALE=<f>` windowed override)
  rescales the shared theme's whole font ladder from the authored base
  (never compounds), the 13 local `add_theme_font_size_override` sites,
  and the text panel budgets that grow with text (the blockquote's 560px
  panel, the choice card's 312px).
- `test_type_scale.gd` (NEW): range clamp, exact ladder math,
  idempotence + authored-restore, label minimums grow, budgets grow and
  clamp inside narrow windows, the widest catch-up rows measured in the
  theme's real face still fit the LIVE quote label at 1.3 with ≥30px
  margin, local overrides scale.
- `responsive_sweep.gd`: the quiet table + an open blockquote at 1.3× at
  the Deck window escape nothing.
- Windowed spot-check (eyes): at 1.3× the regime plate and the status
  chip clipped mid-word — both plate budgets now grow with the scale
  (`run_header.gd`, the debug chip); re-captured and inspected clean.
  The header leader-name truncation on long names is pre-existing at
  1.0× (a copy/name-budget matter, T-COPY-01 territory, recorded).
- **Documented deviation (RESOLVED by finishing refinement #5)**: the
  scale originally applied at BOOT only (main scene, the spread screen,
  the test runners) — a live toggle was deferred to a settings screen.
  The press-room card now IS that surface: the 1.0–1.3 steps apply LIVE
  (the theme rewrite + the whole-view rebind) and persist in the META
  domain (`RunMeta.preferences`, additive-optional), re-applied at boot
  before any chrome bakes sizes. The project setting remains the
  pre-feature default for a player who never touched the card;
  `motion/reduced_motion` gained the same live + persisted surface.

### 10. The journeys 1–5 — PASS

`journeys_sweep.gd` (33 checks at the MVP sweep) ties the arcs together at the
screen: J1 first session (reveal → recruit → worker → farm → trickle →
trainee — table carries the session's cards); J2 daily check-in (capped
9h37m window → one print, passive → one choice answered → focus held);
J3 long session (floor met, odds consulted); J4 failure (greed crushed →
beat → one-input skip → loss-restart reveal, SAME regime, new leader,
run 2 live); J5 victory (storm → win handoff → win-restart reveal → new
regime, chronicle sealed). The sim-level arcs remain in
`full_run_ci.gd`/`marathon_*`; per-moment pins in the unit suites. No
journey gap found — the sweep consolidated what was piecemeal and added
the missing J1/J2/J3 screen-level arcs.

### 11. Layer 1 — the always-on legacy loop (L1-D, 2026-09-17) — PASS

The Layer-1 loop as one continuous acceptance arc, `journeys_sweep.gd`
**J6** (+31 checks, 65 total), through the REAL front door
(`ui/main.tscn`):

- **The multi-run arc (3 accelerated runs)**: a fresh install → the
  knight-fixture army → the storm committed by KEYBOARD → the WIN banks
  run 1 (bank == the won hand's chronicle score, exactly) → quit at the
  reveal through the platform boundary (`background` flush) → the
  returning boot finds the live hand (CONTINUE) and the title carries
  **The Legacy chip** → the deck opens through the chip (keyboard): the
  bank band reads the real banked score over the live hand (the honest
  mount rule) → focus seeds the FIRST AFFORDABLE card → one Enter buys
  **Grandma's Recipes** down the real `unlock_purchase` command (bank
  pays exactly the card's price, the purchase prints on the deck's
  paper) → back folds the deck, focus returns to the chip → the two-step
  NEW RUN ends run 2 honestly (abandoned, banked) → the loss-restart
  reveal deals run 3 — **whose opening stipend pays each content line ×
  the card's milli exactly (food 55, timber 88 at ×1.1), the veterans
  read stays identity, and the applied multiplier rides the run save** →
  chronicle, run counter, bank + spent, and the deck's own arithmetic
  all agree. The stipend exactness is proven load-bearing (A/B:
  asserting identity milli fails both lines).
- **The first-session interaction check**: the FRESH title carries NO
  Legacy chip (`show_legacy_chip_for(0)` false — nothing earned, no deck
  to read; the fresh flow stays single-BEGIN with seeded focus), and the
  RETURNING title's chip never steals the seeded CONTINUE focus. The
  deck's earn-first line itself (fresh bank, everything locked) is
  L1-C's pinned unit territory (`test_legacy_screen.gd`), reached
  mid-run through the header verb.
- Supporting pins: the L1-C/L1-B2 unit suites (the deck's mapping,
  states, buy/refuse contract, parity, budgets, persistence; the tree's
  content + compound millis) and the balance evidence in
  `docs/balance.md` §6/6b (re-verified at L1-D close: baseline band
  79 h / 12/12 unchanged, full-tree 70 h / 12/12, greed crushes at 27 h
  on both seeds).

### 12. Layer 2 — the escalation cycle (L2-D, 2026-09-17) — PASS

The Layer-2 ladder as one continuous acceptance arc through the REAL
FRONT DOOR, `journeys_sweep.gd` **J7** (+38 checks, 103 total), one save
root, booting twice — the META thread (snapshot, cycle, bank) and the
FELT thread (reveal line, odds garrison line, header mark) asserted at
every step:

- **The fresh gate**: a fresh install carries NO snapshot (cycle 0) and
  the first deal's reveal carries no escalation presence — the
  zero-impact rule read at the door itself.
- **Cycle 1**: the knight-fixture army takes the STATIC wall by the
  two-step keyboard COMMIT; the outcome prints the CAPTURE BEAT beside
  the seal; the meta captures the first garrison EXACTLY (cycle 1,
  captured at run 1, the old leader's name + regime + crest, and the
  snapshot's roster power == the army that took the wall, 30 power);
  the chronicle entry records the cycle it opened and the bank holds
  the score.
- **The handoff felt**: run 2's win-restart reveal names the OLD
  LEADER's veterans at cycle 1 (escalation block + the re-faced regime
  card's crest/line + the third print in the escalation voice), and
  the letterhead carries the CYCLE MARK (1) — the only spread chrome.
- **The odds against your own army**: run 2's consult derives the
  castle side from the SNAPSHOT (source `escalation`, power 30, cycle 1
  identity curve); the castle card's line names whose veterans hold
  the wall and the strip prints the composition + the snapshot's
  tier-mix detail row. Retreat is free — the consult never commits.
- **The layers compose**: a legacy card bought BETWEEN the cycles
  through the table's own header verb (Grandma's Recipes, one Enter,
  bank pays exactly the price mid-run, the deck folds on back).
- **Cycle 2**: run 2's own veterans take the wall back (deterministic
  on the seeded die — try 1 at 60 power vs the 30-veteran wall); the
  SECOND capture is the LATEST victor's army (cycle 2, captured at run
  2); the chronicle records both captures; run 3's reveal names run
  2's veterans, the letterhead's mark reads 2, and run 3's odds show
  the ×1.10 rung EXACTLY (snapshot 60 ×1.10 = 66 garrison).
- **The records agree + the boundary**: bank + spent == the two banked
  scores (358 + 60 == 418), the deck's own arithmetic reads the same;
  and after the platform boundary (background flush + a fresh boot),
  the returning door CONTINUEs run 3 with the garrison STILL in the
  meta save — the check-in reveal reads cycle 2 and the resumed table
  carries the cycle-2 mark.
- Supporting pins: the L2-A/B/C unit suites (the engine's
  capture/derivation/round-trip math; the reveal, odds, header and
  chronicle presence), the `escalation_ladder_band` chained-campaign
  suite (55 checks), and the balance evidence in `docs/balance.md` §7
  (re-verified at L2-D close: baseline band 79 h / 12/12 unchanged,
  the ×1.10 row and the ladder table reproduce exactly, full-tree
  70 h / 12/12, greed 27 h both seeds).

## Accepted deviations (with rationale)

| Deviation | Rationale |
|---|---|
| **Deck hardware validation deferred** | No Deck hardware in this environment. `docs/deck-validation.md` carries the concrete hardware checklist (SteamOS run, 60Hz lock, battery, Steam Input, suspend/resume, first-boot). The M-series windowed pass (T-PERF-02) is necessary-not-sufficient with 3–5× budget margins. |
| **Font scale applies at boot** | Originally: a live toggle needs a whole-view rebind + settings screen (post-MVP). RESOLVED by finishing refinement #5 — the press-room card applies the 1.0–1.3 steps live and persists them in the meta domain (see §9 above); the recorded evidence of this sweep predates that surface. |
| **Journey-1 literal payoff timing** (was ~min 49 trickle / ~min 141 trainee at 1×) | TRICKLE RESOLVED by the 2026-09-17 backlog sweep's content retune (zero-hour chores + farm 24 food/h — the first visible food lands at minute 12 player-paced, 22 on the 5-min manage cadence; docs/balance.md carries the re-swept tables, first-win band unmoved). The TRAINEE (~min 141) stands: measured — shortening the 2h militia drills to 1.0h/1.5h pushed the first-win tail to 169h past the 132h bound, so the drills keep the band's pacing. |
| **Card-title clip below the plate-fit floor** | RESOLVED twice. The 2026-09-17 readability pass removed the 55%/70% floors, but its shrink-to-full-fit (absolute 8px) converted CLIP into TINY — the verifier's re-audit found 40 sub-floor texts (plot titles at 8–10px at 1.0x). RE-DISPATCHED same day (readability r2, grow-don't-shrink): `CardFace.fit_label_to_width` now steps down only to the READABILITY FLOOR (12 design units; titles 18), wraps multi-word prints below the small-print line when the card has the height, and GROWS the plate to the floor-size print when it cannot wrap; the fit measures the widest line and keeps air (no edge-to-edge glyphs). The ladder grants the widest aspect-true card; the odds castle grew to 244 (the garrison share line prints whole at its authored size — the round-1 "whole at ~16px on its fixed seat" keep was FALSE as rendered and is fixed, not kept). Bar of record: `scripts/readability_audit.gd` — 0 CLIP / 0 OVERFLOW / 0 WRAP-CLIP / 0 OCCLUSION / 0 SUB-FLOOR at 1.0x both orientations, TINY 1 (<= the 10 baseline); 1.3x floor-check clean. Pinned by `test_face_plates_step_down_to_fit_before_clipping` (floors hold, the plate grows, the clip never engages). |
| **Header long-name truncation at 1.0×** | Pre-existing (visible in both 1.0× and 1.3× captures); a name/copy budget decision, T-COPY-01 territory. (Refinement #6 since made the letterhead wrap; the row records the sweep's state at its time.) |
| **The vsync-cadence max gate flakes on this macOS host** | T-PERF-02's recorded non-blocking caveat (~24ms OS compositor hitch, not game cost); belongs on the hardware checklist. NOT in `make test`. |

## The suites added by this task

| Suite | Checks | What it owns |
|---|---|---|
| `tests/acceptance/suites/input_parity_matrix.gd` | 153 | the three-mode matrix (§3 above) |
| `tests/acceptance/suites/responsive_sweep.gd` | 56 | the four-size whole-screen sweep (§4) + the 1.3× spot |
| `tests/acceptance/suites/journeys_sweep.gd` | 33 → **103** | the five journeys at the screen (§10) + J6 the Layer-1 loop (§11, L1-D) + J7 the escalation cycle (§12, L2-D) |
| `tests/acceptance/suites/escalation_ladder_band.gd` | 55 | the chained-campaign ladder band (§12, L2-B; docs/balance.md §7) |
| `tests/unit/test_type_scale.gd` | 8 | the font-scale mechanism (§9) |
| `tests/unit/test_colorblind_audit.gd` | 6 | the consolidated colorblind audit (§8) |

Game-code changes this task: `ui/theme/type_scale.gd` (new seam, wired
into `ui/main.gd`, `spread_screen.gd`, the acceptance runner, and
`project.godot`); 13 local font-size overrides + the quote/choice/header
plate budgets made scale-aware; the touch bare-table fold
(`spread_screen._unhandled_input`); the assault odds re-open focus fix
(`assault_stage.set_chips`).
