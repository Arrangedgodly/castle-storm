# Deck Validation — T-PERF-02

Status: **validated on the development host (necessary-not-sufficient); hardware-gated remainder tracked below.**
The Deck target: Steam Deck LCD, Linux x86_64, 1280x800 @60Hz window, Compatibility renderer (project pin R1), pad input through Steam Input presenting as a standard SDL controller.

## What was validated HERE (no Deck hardware in this environment)

### 1. Frame budget at the Deck profile — `make deck-perf` (windowed, real renderer)

`scripts/deck_perf_suite.gd` forces the Deck window (1280x800, design 1152x720 landscape — the same canvas_items/expand profile the export ships) and measures whole-frame cost (game layer + render submit) with **vsync disabled** so the number is cost, not compositor pacing. Pass lines: mean <= 8.3ms (50% of the 16.63ms 60Hz budget), p95 <= 11.1ms (67%), max <= 16.63ms (no missed 60Hz frame). Host: Apple M2, Godot 4.7.2 Compatibility (OpenGL-on-Metal), March 2026 build.

| state | mean | p95 | p99 | max | draw calls | verdict |
|---|---|---|---|---|---|---|
| bare frame (engine only) | 2.32 ms | 6.16 | 7.03 | 7.03 | 0 | PASS |
| idle spread (quiet, settled) | 3.54 ms | 8.95 | 12.89 | 15.50 | 154 | PASS |
| busy spread (away print + promotion flip concurrent) | 4.71 ms | 8.95 | 11.97 | 12.11 | 181 | PASS |
| assault vignette (mid-beats) | 5.36 ms | 9.37 | 15.05 | 15.70 | 209 | PASS |
| chronicle 50 (scrolled) | 4.83 ms | 9.21 | 10.28 | 11.06 | 193 | PASS |

Companion evidence in the same run:

- **Idle pixel-identity**: two viewport captures 8 frames apart are BYTE-IDENTICAL (4,096,000 bytes each) — the quiet table animates nothing at all. This is the catch-all the headless battery counter cannot express (Godot 4.7 has no per-item redraw query).
- **Vsync-locked cadence**: max 12.91ms under vsync — inside the 16.63ms 60Hz budget with a full period of slack (this display paces ~120Hz in practice despite reporting 60; the budget line is the honest check, not the period).
- **Chronicle page-turn transitions**: worst 13.21ms, median 9.77ms — a turn is an event (it rebuilds the page), reported, not gated; under budget anyway.
- **The measurement find, fixed**: `TableGround._draw` (and the assault stage's copy) drew the halftone paper grain as ~1,250 `draw_circle` commands per ground per frame — measured **1487 draw calls / 8.81ms mean** on the idle table before the fix (the vignette: 1624 calls / 18.42ms mean, over budget). The grain now bakes once into a shared 26x26 `ImageTexture` tile and covers the ground in ONE tiled draw (placement carries the phase jitter — same dots, same grammar): idle **154 calls / 3.54ms**, vignette **209 calls / 5.36ms**.

### 2. Texture / video memory per state — same run

Per-state engine memory (the whole run never frees earlier state's caches by design; per-state deltas are the honest reading):

| state | static | objects | resources | texture mem | video mem | buffer mem |
|---|---|---|---|---|---|---|
| bare | 42.2 MB | 1634 | 100 | 8.0 MB | 14.3 MB | 6.3 MB |
| idle spread | 53.9 MB | 6461 | 159 | 20.5 MB | 26.8 MB | 6.3 MB |
| busy spread | 76.8 MB | 10703 | 160 | 23.5 MB | 29.8 MB | 6.3 MB |
| assault vignette | 82.7 MB | 14829 | 160 | 24.0 MB | 30.3 MB | 6.3 MB |
| chronicle 50 | 89.5 MB | 19009 | 160 | 24.6 MB | 30.9 MB | 6.3 MB |

Boundedness, pinned in `make test` (`tests/acceptance/suites/deck_battery_memory.gd`) and re-measured windowed:

- **chronicle pages**: two full 10-page cycles of the 50-hand ring hold static memory and object counts steady (headless: 84.1 -> 84.2 MB static, 16276 -> 16276 objects; windowed run: stable to within noise; the sheet holds exactly one page of entry cards at a time) — dying pages free;
- **card-art cache** (`FaceArt`): bounded by the art manifest (7 cached <= 13 non-pending entries), unchanged across three whole-view rebinds;
- **rebind churn**: five full `refresh_from_state()` passes hold object count exactly flat;
- **away print**: structurally bounded — worst honest window prints 7 rows (the quote panel's own cap); a rewound clock prints 1.

Total footprint is far under the Deck's ~4GB usable (worst state ~90MB static + ~31MB video).

### 3. Controller navigation sweep — `make test` (`tests/acceptance/suites/deck_nav_sweep.gd`, 40 checks)

Scripted pad events through the REAL dispatch pipeline (`Input.parse_input_event` of `InputEventJoypadButton`, device 0 — the project's Any-Device bindings accept it; dpad 11-14 ride Godot's built-in `ui_*` bindings, A/B ride the project's `primary`/`back`), at the Deck window, across every screen:

- **the spread table**: dpad BFS from seeded focus reaches ALL 12 visible focusables (cards, both chronicle strip lines, the header ledger chip), focus never lost across 48 presses;
- **the action fan**: pad A opens it off a focused card, the trap cycles every chip (nothing escapes), A submits exactly once, B folds — focus returns to the card both ways;
- **the assault**: a FULL pad-only storm — A on a below-floor COMMIT prints the refusal and stays open (focusable-but-struck is honest), A on RETREAT retreats at no cost, A on COMMIT commits, A skips the vignette, A closes the outcome (verified win handoff);
- **the chronicle ledger**: A on the header chip opens it, dpad walks every entry and chip on the page, A on OLDER turns the page, B closes — focus returns to the chip;
- **the leader intro**: focus lands on the one-gesture chip, A unfolds, focus lands on the table;
- **the suspicion choice card**: dpad reaches every chip (the wired pad column), B folds;
- **the while-you-were-away print**: passive paper — the table keeps focus through it.

**Four genuine pad gaps the sweep found, all fixed in this task:**

1. `ui_accept` carries NO joypad binding in Godot 4.7 — the pad's A button only reaches screens that implement a `primary` fallback. The assault odds/outcome had none: **COMMIT was unreachable by pad** (a Deck player could open the storm table and never raise the standard). Fixed: `AssaultScreen.activate_focused()` (the ActionFan/Chronicle pattern).
2. The spread's own primary handler activated fans, choice cards and cards — but not a focused BUTTON on the table itself: **the chronicle header chip could not be opened by pad**. Fixed: the generic focused-`BaseButton` fallback in `SpreadScreen._unhandled_input`.
3. The chronicle sheet's page relied on geometric focus resolution — the chips row races a tall page's last entries and the dpad **skipped an entry outright**. Fixed: `ChronicleSheet._wire_pad_column()` — entries + chips as one cyclic vertical chain (the fan's own rule; left/right stay free).
4. The suspicion choice card had the same disease worse: only 1 of 4 chips was pad-reachable (the table beneath won the geometric race). Fixed: `ChoiceCard._wire_pad_column()` — the paper's column wired cyclically, leaving the card is still free (its documented non-trap design).

Also hardened (the sweep's own infrastructure): the acceptance runner's `_process` re-entry could interleave suites and quit under a live coroutine once async suites existed (all originals are synchronous) — guarded by an in-flight latch.

### 4. Battery-shape discipline — `make test` (same suite, 3 checks) + the windowed pixel proof

- **Idle activity counter** (headless, 30 quiet frames): zero processing nodes outside the two documented seams (the spread's pacing `_process` and the LayoutRouter's aspect poll — the counter is non-vacuous: it observes exactly those two), zero physics-processing nodes. The intro packet's `_process` is a gated no-op at rest.
- **The counter's own find, fixed**: `AssaultScreen._process` polled every frame even when CLOSED (a whole-session per-frame no-op for a screen that opens rarely). Now gated to the RESOLVING drain only.
- **Idle pixel-identity** (windowed, the catch-all): byte-identical captures — see above.
- **Passive paper settles**: after the while-you-were-away print self-folds, the activity counter reads zero again.
- **Posture for the Deck** (documented decisions of record): vsync ON at 60Hz (the window paces to the display; `low_processor_usage_mode` stays REJECTED per T-PERF-01 — it caps ~20fps against the 60fps target); focus-loss does NOT pause the sim (desktop decision of record, T-PERF-01 — measured negligible cost while the window keeps submitting); the OS suspend path (`NOTIFICATION_APPLICATION_PAUSED`) is the mobile boundary, not the Deck's.

### 5. Why this is necessary-not-sufficient for the Deck

Measured on an M-series Mac through Godot's OpenGL-on-Metal translation at the Deck's exact window size. The Deck is a slower APU (Van Gogh, ~1/2-1/3 the GPU) on a different stack (Mesa GL / Gamescope or KWin). The margins here (mean 21-32% of budget, p95 54-81% of the M2's headroom-heavy numbers, worst state 5.4ms mean) are large enough that a 2-3x slowdown still holds 60fps, but only the hardware run proves it. The p99/max tails on this host include macOS compositor hitches (~7ms spikes measured on a BARE frame) — a different tail shape than Gamescope.

## The hardware-gated remainder (the Deck checklist)

Run on ACTUAL Steam Deck hardware, SteamOS, the exported `exports/linux/castle-storm.x86_64` (embedded PCK, `make export-linux`):

- [ ] **60Hz lock**: run the five `deck-perf` states (the same script runs on the Deck — `godot` binary or the export with `--script` removed; measure with the engine's own monitors or `mangohud`). Pass = mean <= 8.3ms, p95 <= 11.1ms, max <= 16.63ms per state at 1280x800, vsync on (60/60 held over a 5-min idle session).
- [ ] **Battery drain target**: idle spread at 60Hz with vsync on — expect roughly 6-9W whole-system (Deck LCD idles ~4-6W; the game layer measures ~0.3ms CPU + one 154-draw frame). Record actual W and est. runtime; target >= 5h on the 40Wh LCD battery for the quiet-table loop (the game's dominant state). Use `powerdeck`/`steamui` battery readout.
- [ ] **Steam Input mapping live-test**: Desktop mode → Game Mode; confirm the pad presents as the standard SDL mapping the `InputMap` baseline pins (A=0 primary, B=1 back, X=2 secondary, R1=5 debug fast-forward, L3=6 pause; test_input_map.gd pins the Any-Device bindings). Play one full loop by pad only: intro unfold -> table walk -> fan act -> chronicle -> storm -> outcome -> next hand (the deck_nav_sweep's manual mirror).
- [ ] **SteamOS suspend/resume**: sleep the Deck mid-run, wake, and confirm the catch-up window resolves through the real save (the T-PERF-01 seam) and the while-you-were-away print lands inside 3s.
- [ ] **First-boot smoke**: the Linux export boots to the intro on the Deck's 1280x800 with no CLI flags (the export embeds the PCK; if SteamOS's runtime needs `--rendering-driver opengl3` explicitly, record it in the launch config).

## Reproducing

```
make deck-perf    # windowed measurement at the Deck profile (opens a window)
make test         # deck_nav_sweep (40 checks) + deck_battery_memory (15 checks) + everything else
```

Evidence recorded in `docs/ultron/production-log.md` (T-PERF-02 entry): the full deck-perf table above, the pre-fix draw-call numbers, and the four pad-gap fixes.
