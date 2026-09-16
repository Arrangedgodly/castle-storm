# Acceptance sweep — Castle Storm MVP (T-QA-05)

The final production gate: the town-hall acceptance criteria
(`docs/ultron/town-hall.md` §"Success measures and acceptance criteria" +
PRODUCT.md §"Accessibility & Inclusion") verified as a coherent whole.
Every row below names the evidence that stands behind it in `make test`.

**State: `make test` green — 569 gdUnit4 unit/property cases + 1,274
acceptance checks, ~55s wall (budget <60s).**

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
- **Documented deviation**: the scale applies at BOOT (main scene, the
  spread screen, the test runners). A live settings toggle needs a
  whole-view rebind and ships with the (post-MVP) settings screen; at
  MVP it is a project setting, like `motion/reduced_motion`.

### 10. The journeys 1–5 — PASS

`journeys_sweep.gd` (NEW, 33 checks) ties the arcs together at the
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

## Accepted deviations (with rationale)

| Deviation | Rationale |
|---|---|
| **Deck hardware validation deferred** | No Deck hardware in this environment. `docs/deck-validation.md` carries the concrete hardware checklist (SteamOS run, 60Hz lock, battery, Steam Input, suspend/resume, first-boot). The M-series windowed pass (T-PERF-02) is necessary-not-sufficient with 3–5× budget margins. |
| **Font scale applies at boot** | A live toggle needs a whole-view rebind + settings screen (post-MVP). Project setting at MVP, like reduced motion. |
| **Journey-1 literal payoff timing** (~min 49 trickle / ~min 141 trainee at 1×) | Accepted at T-UI-10 (the "I get it" arc lands at minute 8); content-side levers routed to the T-SIM-08 follow-up. |
| **Header long-name truncation at 1.0×** | Pre-existing (visible in both 1.0× and 1.3× captures); a name/copy budget decision, T-COPY-01 territory. |
| **The vsync-cadence max gate flakes on this macOS host** | T-PERF-02's recorded non-blocking caveat (~24ms OS compositor hitch, not game cost); belongs on the hardware checklist. NOT in `make test`. |

## The suites added by this task

| Suite | Checks | What it owns |
|---|---|---|
| `tests/acceptance/suites/input_parity_matrix.gd` | 153 | the three-mode matrix (§3 above) |
| `tests/acceptance/suites/responsive_sweep.gd` | 56 | the four-size whole-screen sweep (§4) + the 1.3× spot |
| `tests/acceptance/suites/journeys_sweep.gd` | 33 | the five journeys at the screen (§10) |
| `tests/unit/test_type_scale.gd` | 8 | the font-scale mechanism (§9) |
| `tests/unit/test_colorblind_audit.gd` | 6 | the consolidated colorblind audit (§8) |

Game-code changes this task: `ui/theme/type_scale.gd` (new seam, wired
into `ui/main.gd`, `spread_screen.gd`, the acceptance runner, and
`project.godot`); 13 local font-size overrides + the quote/choice/header
plate budgets made scale-aware; the touch bare-table fold
(`spread_screen._unhandled_input`); the assault odds re-open focus fix
(`assault_stage.set_chips`).
