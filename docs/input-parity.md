# Input parity matrix — Castle Storm (T-QA-05)

The town-hall criterion: **"Full loop operable three ways: touch (≥48dp
targets), controller (Deck focus navigation), keyboard/mouse."** This is
the complete surface × action × mode matrix, with the test that proves
each row. The consolidated driver is
`tests/acceptance/suites/input_parity_matrix.gd` (in `make test`, 153
checks); per-moment pins stay in their owning unit suites; the Deck-window
pad BFS walk lives in `tests/acceptance/suites/deck_nav_sweep.gd`.

## The three input pipelines (how "touch/pad/kb" is enforced)

| Mode | Injection | Notes |
|---|---|---|
| Touch | `InputEventMouseButton` LEFT at the target's center via `Viewport.push_input(ev, true)` | The gui dispatch a finger rides. `Input.parse_input_event` is NOT usable for positional events headless — the platform display server rescales positions (probe-measured `(200,140) → (2250,1575)`); `push_input`'s local-coords form is exact. |
| Pad | `InputEventJoypadButton` via `Input.parse_input_event` (device 0) | dpad 11–14 → the engine's `ui_*` focus moves; A(0) = `primary`; B(1) = `back`. Godot 4.7's `ui_accept` carries NO joypad binding — every screen's "activate focused chip" pad fallback exists for exactly this (T-PERF-02's finds). |
| Keyboard | `InputEventKey` via `Input.parse_input_event` | Arrows = focus moves; Enter = `primary` (routed `ui_accept` on the focused control); Esc = `back`. |

Touch targets on cards need the **topmost-point solver** (the suite's
`_tappable_action_card`): the panoramic arc ROTATES cards, so an
axis-aligned rect test lies about what a tap hits — every later sibling
is tested through its inverse transform, exactly how the engine picks.

## A. Action-model completeness (every verb prints as a chip)

Every card verb is a uniform `ActionChip` button — one input target shape
for the whole estate. The suite drives 12 sim-hours of sensible play and
collects every verb the model prints (`CardActions.actions_for` over each
view snapshot); every core verb family must appear, and every
disabled-but-visible verb must carry its printed reason.

| Verb family | Card | Sim command |
|---|---|---|
| `accept` / `dismiss` | gate offer | `recruit_accept` / `dismiss_offer` |
| `assign_worker` / `assign_militia` | idle peasant | `assign_role` |
| `train` | idle militia | `start_training trainee` |
| `train_knight` / `train_archer` | idle trainee (the branch choice) | `start_training` |
| `equip_<slot>_t<n>` | trainee awaiting gear | `equip_gear` |
| `promote` (signature) | fully-geared trainee | `promote` |
| `storm` (signature) | sworn army unit | opens the odds table (the Spread intercepts; the sim verb is `commit_assault` on COMMIT) |
| `build` | staked plot (level 0) | `upgrade_building 0→1` |
| `upgrade` / `assign_hand` / `stand_down` | building | `upgrade_building` / `assign_worker` / `unassign_worker` |

Owning tests: `input_parity_matrix.gd` §A (model sweep + reasons);
`test_card_interactions.gd` (exact per-card action sets); `test_theme_grammar.gd` §7 + `test_colorblind_audit.gd` §7 (refusals print).

## B. The matrix (surface × action × mode)

"✓ = the suite drives the action through that pipeline's real events."
Where a row is owned by a different suite, it is named.

### The spread table and the action fan

| Action | Touch | Pad | Keyboard | Owning test |
|---|---|---|---|---|
| Focus / move between cards | tap = direct select + fan | dpad BFS (never lost) | arrows (focus chain) | `deck_nav_sweep.gd` §1; `input_parity_matrix.gd` §B |
| Open a card's action fan | tap card (topmost-point) | A on focused card | Enter on focused card | §B all three |
| Cycle fan chips | tap = direct | dpad (focus trap holds) | arrows | §B kb+pad driven; trap pinned `test_card_interactions.gd` |
| Submit a chip | tap chip (exactly once) | A on focused chip | Enter on focused chip | §B all three |
| Refuse a disabled (struck) chip — prints the clerk's hint, submits nothing | tap struck chip | A on focused struck chip | Enter | §B (pad leg asserts the refusal count; the reason contract in §A) |
| Fold the fan WITHOUT acting | tap the bare table | B | Esc | §B all three — **the touch column forced the bare-table fold into existence this task** (`spread_screen._unhandled_input` positional branch) |

### The suspicion choice card (T-UI-06)

| Action | Touch | Pad | Keyboard | Owning test |
|---|---|---|---|---|
| Submit a choice chip | tap chip | A on focused chip | Enter | §C all three |
| Fold without choosing | tap the bare table | B | Esc | §C all three |
| Chips all reachable (the wired pad column) | tap = direct | dpad | arrows | `deck_nav_sweep.gd` §6 |

### The assault (T-UI-07)

| Action | Touch | Pad | Keyboard | Owning test |
|---|---|---|---|---|
| Open the odds table (via the STORM chip on an army card) | tap chip | A on focused chip | Enter | §D all three |
| COMMIT below the floor — the printed refusal, table stays | tap COMMIT | A on COMMIT | Enter | §D all three |
| RETREAT (free) | tap RETREAT | A on RETREAT / B | Enter on RETREAT / Esc | §D all three |
| Skip the vignette (one input) | any tap | A / B | Enter / Esc | §D touch storm; `deck_nav_sweep.gd` §3 pad storm; `journeys_sweep.gd` J5 keyboard storm |
| Close the outcome | tap close chip | A / B | Enter | same three suites |
| Full storm end-to-end in ONE mode | touch-only storm (§D) | pad-only storm (`deck_nav_sweep.gd` §3) | keyboard storm (`journeys_sweep.gd` J5) | all three |

### The chronicle ledger (T-UI-08)

| Action | Touch | Pad | Keyboard | Owning test |
|---|---|---|---|---|
| Open from the header chip | tap chip | A on focused chip | Enter | §E all three |
| Walk entries | tap = direct | dpad (all focusables reached) | arrows | §E + `deck_nav_sweep.gd` §4 |
| Turn pages (NEWER/OLDER) | tap chip | A on focused chip | Enter | §E all three |
| Close (BACK TO THE TABLE) | tap BACK chip | B | Esc | §E all three |

### The leader intro / restart reveal (T-UI-05)

| Action | Touch | Pad | Keyboard | Owning test |
|---|---|---|---|---|
| The one gesture (unfold) | tap anywhere on the packet | A | Enter | §F all three |
| Focus lands and returns | n/a (auto path exists) | focus seeds on the chip, table takes it back | same | §F; `test_intro_reveal.gd` |

### Passive paper (no verbs by design — nothing to reach, nothing stolen)

- The while-you-were-away print (T-UI-09): passive; the table keeps focus
  through the whole print — `deck_nav_sweep.gd` §7, `journeys_sweep.gd` J2.
- The first-session cues (T-UI-10): printed nudges, never modal —
  `test_first_session.gd`, `journeys_sweep.gd` J1.
- The crush beat: ANY input skips (one branch for every mode — positional
  included); the touch skip is driven in `journeys_sweep.gd` J4, the
  branch structure in `suspicion_events.gd`/`spread_screen._unhandled_input`.

### Out of the player matrix by design

- The debug time-scale chip / `debug_fast_forward` / `pause` — dev chrome
  (documented in `spread_screen.gd`; still three-way bound in the InputMap,
  pinned by `test_input_map.gd`).
- `secondary` (Deck X) — bound in the InputMap (pinned by
  `test_input_map.gd`), not yet claimed by any player surface.

## Bugs this matrix found and fixed (this task)

1. **Touch had no "fold without acting"** for the fan and choice card —
   a tap on the bare table now folds the open paper
   (`spread_screen._unhandled_input` positional branch).
2. **Reopened assault odds stranded focus** (controller/keyboard): a
   re-open's chip-grab deferred onto a `queue_free`d chip. Fixed in
   `assault_stage.set_chips` (detach-before-free, the `EventQuote`
   precedent); regression-pinned by `responsive_sweep.gd`'s per-size
   focus checks (the odds table is opened at all four sizes).
3. Historical (found by the T-PERF-02 pad sweep, kept green here): pad-A
   COMMIT, pad-openable chronicle, the wired pad columns — see
   `docs/ultron/production-log.md` T-PERF-02.

## The InputMap baseline (what binds what)

Pinned by `tests/unit/test_input_map.gd` (4 cases): every project action
has an Any-Device (device −1) joypad button — A(0) primary, B(1) back,
X(2) secondary, R1(5) debug_fast_forward, L3(6) pause — exact indices per
the `docs/DEV_SETUP.md` table, keyboard parity intact, `primary` also
mouse-bound. Changing a binding is a product decision: update the table
and the test together.
