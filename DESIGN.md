---
name: Castle Storm
description: "The Conspiracy's Spread — a cheap-print tarot table where the game itself is dealt as cards: ink on paper, states by line form, no popup chrome."
colors:
  cheap-paper: "#E7D9BD"
  recessed-paper: "#D5C5A5"
  pressed-paper: "#C4B598"
  faded-paper: "#CBBB9D"
  press-ink: "#1E1914"
  ink-running-low: "#544636"
  revolution-red: "#901E1E"
  candle-lit-red: "#E3785C"
  pressed-deep-red: "#6B1414"
  cold-ash: "#9EA8B8"
  table-ground-neutral: "#3C342B"
  table-ground-training: "#342C24"
  table-ground-ready: "#2C261F"
  table-ground-aftermath: "#868B94"
  gilded-crown-ground: "#3B2E1F"
  iron-rotunda-ground: "#262B30"
  paper-crown-ground: "#4C4533"
  velvet-fist-ground: "#3B1F2E"
  gilded-crown-gilt: "#CCA34C"
  iron-rotunda-steel: "#8F9CA8"
  paper-crown-ledger-blue: "#405278"
  velvet-fist-orchid: "#B86B99"
typography:
  display:
    fontFamily: "IM Fell English SC, Georgia, serif"
    fontSize: "42px"
    fontWeight: 400
  card-title:
    fontFamily: "IM Fell English SC, Georgia, serif"
    fontSize: "34px"
    fontWeight: 400
  body:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "22px"
    fontWeight: 400
  button:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "22px"
    fontWeight: 400
  chronicle-line:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "22px"
    fontWeight: 400
    fontStyle: italic
  numerals:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "26px"
    fontWeight: 700
  role-line:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "19px"
    fontWeight: 500
  pip-label:
    fontFamily: "Alegreya Sans, Verdana, sans-serif"
    fontSize: "15px"
    fontWeight: 500
rounded:
  chip: "4px"
  panel: "5px"
spacing:
  touch-grip-min: "48px"
  card-gap: "20px"
  table-edge-margin: "12px"
  rail-separation: "18px"
  chronicle-row-separation: "6px"
  frame-inset: "8px"
  frame-chamfer: "9px"
  edge-width: "4px"
  edge-dash: "10px"
  edge-dash-gap: "7px"
  strike-width: "5px"
components:
  card-frame:
    backgroundColor: "{colors.cheap-paper}"
    textColor: "{colors.press-ink}"
    size: "96px x 96px min"
  card-frame-focused:
    backgroundColor: "{colors.cheap-paper}"
    textColor: "{colors.press-ink}"
  button-chip:
    backgroundColor: "{colors.recessed-paper}"
    textColor: "{colors.press-ink}"
    typography: "{typography.button}"
    rounded: "{rounded.chip}"
    padding: "14px 9px"
  button-chip-hover:
    backgroundColor: "{colors.cheap-paper}"
    textColor: "{colors.press-ink}"
  button-chip-pressed:
    backgroundColor: "{colors.pressed-paper}"
    textColor: "{colors.press-ink}"
  button-chip-disabled:
    backgroundColor: "{colors.faded-paper}"
    textColor: "{colors.ink-running-low}"
  chronicle-line:
    textColor: "{colors.cheap-paper}"
    typography: "{typography.chronicle-line}"
    height: "48px"
  pip-mark:
    backgroundColor: "{colors.cheap-paper}"
    textColor: "{colors.press-ink}"
    typography: "{typography.numerals}"
    size: "72px x 48px"
  paper-panel:
    backgroundColor: "{colors.cheap-paper}"
    textColor: "{colors.press-ink}"
    rounded: "{rounded.panel}"
---

# Design System: Castle Storm

<!-- Full refresh written from the BUILT world (scan mode, ground truth over intention).
     Every token below is extracted from shipped code; the normative sources are
     ui/theme/inks.gd (tokens), ui/theme/spread_theme.tres (theme mirror, equality-tested
     against inks.gd in tests/unit/test_theme_grammar.gd), and content/mvp/regimes/*.tres
     (regime inks). Auto-mode proxy answers are recorded below as `simulated (auto mode)`. -->

**Auto-mode header note — qualitative choices and their sources** (this run had no live
user; document.md's Step-3 questions were answered from the approved direction contract):

| Question | Answer | Recorded as | Source |
|---|---|---|---|
| Creative North Star | "The Conspiracy's Spread" | simulated (auto mode) | docs/ultron/design-brief.md §3 — the user-chosen direction (2026-09-15, seed key `69dc9dac`) |
| Overview voice / mood | A hand-cranked revolutionary press run by satirical conspirators: flat, wobbly, deadpan | simulated (auto mode) | design-brief §3 visual authority + docs/voice-bible.md §1 (the three printed voices) |
| Color character names | Cheap Paper, Press Ink, Revolution Red, Candle-Lit Red, Cold Ash, … | simulated (auto mode) | ui/theme/inks.gd token doc-comments ("cheap paper — the card stock", "revolution red lifted for the dark table ground", "cold ash — the morning after") |
| Elevation philosophy | Flat print world: no shadows at all; depth is tonal layering + misregistration | simulated (auto mode) | ui/theme/card_frame.gd ("NO gold trim, NO gradients"), ui/theme/table_ground.gd ("flat print world"), design-brief §3 anti-goals |
| Component philosophy | Paper you can grip: print-block chips and cards that read as struck prints, never glassy controls | simulated (auto mode) | design-brief §3 implementation consequence + PRODUCT.md accessibility (≥48dp grips, form-not-hue) |

## Overview

**Creative North Star: "The Conspiracy's Spread"**

Castle Storm's UI is a cheap-print tarot and bestiary deck run off a revolutionary press,
dealt on a candle-lit table in a barn loft. Every surface is the conspirators' card
table: the home screen is a spread being laid out (each conspirator a face-up card in a
position), resources are pip marks along the table edge, suspicion is the Watchful Eye
card creeping in from the periphery, regimes are Major-Arcana-scale face cards, the
assault is cards played against the castle, and past runs live in the chronicle ledger.
Nothing is chrome. Events do not pop up — they print themselves onto the table as
chronicle lines.

The material is two-color ink on cheap paper: flat, bright paper cards carrying
near-black ink (and one red accent) over a dark table ground that deepens phase by
phase, like the candle burning down toward the assault. Everything is drawn with
CanvasItem vector primitives — `draw_polygon`, `draw_polyline`, `draw_dashed_line` —
texture-free and resolution-independent, with a seeded, deliberate misprint (max 0.9°
rotation, max 2 design units offset, FNV-1a-deterministic per card) that makes every
print look hand-cranked. Confirmed visual rejections, held since the direction was
chosen: never luxe gold-trim tarot, never dark-fantasy parchment, never pastel softness,
no gradients, no popup/modal chrome for in-world events.

The system is colorblind-safe and input-parity by construction: state is carried by
LINE FORM (solid ready / dashed in progress / struck lost), never by hue; resources are
encoded shape + glyph + label with color as a redundant tertiary channel; every
interactive target keeps a 48-design-unit grip and a focus treatment (a misregistered
second red pass) that reads without hover and without color.

**Key Characteristics:**

- The game IS the card table — screens are paper laid on the table, never modal chrome
- Two-ink cheap print: paper stock + near-black ink + revolution red; regime second inks recolor by data
- State by line form (solid / dashed / struck / double), never by hue
- States print themselves: events land as chronicle lines and blockquotes
- Phase-deepening ground: the table darkens recruiting → training → ready; aftermath washes cold and light
- Deliberate seeded misprint on every card (rotation ≤ 0.9°, offset ≤ 2 units)
- Flat vector print-block drawing; no textures, no gradients, no shadows
- 720×720 square design base; portrait stacked / landscape panoramic from one component set
- Fonts: IM Fell English SC (display) + Alegreya Sans (workhorse), both OFL, vendored

## Colors

A two-ink press palette: warm paper, warm near-black ink, one revolution red — plus a
data-driven pair of regime inks per flavor and a phase-deepening ground system underneath.

### Primary

- **Revolution Red** (#901E1E / `Inks.RED`): the accent ink ON PAPER — the corner seal
  on every card, focus ghost passes, pressed-button borders, countdown text when the
  telegraph arms. Passes 4.5:1 on Cheap Paper. The brief commits red to carrying
  30–60% of accents; it is the only accent that never changes with regime.
- **Candle-Lit Red** (#E3785C / `Inks.RED_CANDLE`): the same red lifted for the dark
  table ground — rules and marks only (the Watchful Eye's strike wash, focused
  chronicle baselines). Passes 3:1 on every phase-0..2 ground; never body text.
- **Pressed-Deep Red** (#6B1414 / `Inks.RED_DEEP`): the red pressed deep for LIGHT
  grounds — used on the pale aftermath wash where Candle-Lit Red would fail.

### Secondary

One regime secondary per flavor, printed as each card frame's inner hairline (1.5 units)
and the run header's signature rule. These are CONTENT (`RegimeDef.ink_secondary` in
`content/mvp/regimes/*.tres`), mirrored into theme entries
`regime_secondary_<id>` — a regime swap recolors the table by data, never by code:

- **Gilded Crown Gilt** (#CCA34C): the gaudy, grasping crown's gold ink.
- **Iron Rotunda Steel** (#8F9CA8): grim grey-blue iron; everything costs accordingly.
- **Paper Crown Ledger-Blue** (#405278): the frugal court's scrap-ledger blue.
- **Velvet Fist Orchid** (#B86B99): soft-spoken, generous plum.

### Neutral

- **Cheap Paper** (#E7D9BD / `Inks.PAPER`): the card stock and the world's light source
  — bright, flat, ungradiented. Also the text ink printed on dark grounds.
- **Recessed Paper** (#D5C5A5 / `Inks.PAPER_DIM`): plates and strips one shade down —
  button-chip rest state, disabled plate borders.
- **Pressed Paper** (#C4B598): the pressed-button fill (theme Button/pressed stylebox).
- **Faded Paper** (#CBBB9D): the disabled-button fill (theme Button/disabled stylebox).
- **Press Ink** (#1E1914 / `Inks.INK`): near-black ink, warmed to the paper's hue —
  never pure gray. Card edges, rules, glyphs, body text on paper, and the tone every
  dark phase pulls the ground toward.
- **Ink Running Low** (#544636 / `Inks.INK_SOFT`): secondary text tinted from the ink
  hue — role lines, pip labels, the placeholder face silhouette, disabled text.
- **Cold Ash** (#9EA8B8 / `Inks.ASH`): the aftermath wash's target tone — the cold
  morning-after light.

### The Table Grounds (the phase-deepening system)

`Inks.ground_for(regime, phase)` blends the regime's first ink
(`RegimeDef.ink_ground`, mirrored as `regime_ground_<id>`) with a per-phase depth:

- **Recruiting** = the regime ground itself (neutral default #3C342B; Gilded Crown
  #3B2E1F, Iron Rotunda #262B30, Paper Crown #4C4533, Velvet Fist #3B1F2E).
- **Training** lerps 28% toward ink (#342C24 neutral) — `PHASE_DEPTHS[0.0, 0.28, 0.52]`.
- **Ready-to-Storm** lerps 52% toward ink (#2C261F neutral) — the deepest hour.
- **Aftermath** washes 75% toward Cold Ash (#868B94 neutral) — light enough that
  Press Ink text passes 4.5:1 on it.

### Named Rules

**The Print Rule.** Text ink is chosen per stock, exactly as a press chooses ink:
`Inks.ground_text_ink(ground)` prints Cheap Paper on dark grounds and Press Ink on
light grounds (aftermath), split at relative luminance 0.19 (`GROUND_LIGHT_LUMA`).
Both channels pass 4.5:1 on their own side — tested. Accent red follows the same rule
(`ground_accent_ink`): Candle-Lit on dark, Pressed-Deep on light.

**The Line-Form Rule.** Hue never carries state. Card edges, rules, and chronicle
prefixes encode state by form — solid ready / dashed in progress / struck lost /
double victory — colorblind-safe by construction and pinned by
`tests/unit/test_colorblind_audit.gd`.

**The Data-Driven Regime Rule.** No regime color lives in UI code. The four ground and
four secondary inks ship as content resources; the theme mirrors them and
`test_theme_grammar.gd` proves the mirror equals the content — new flavors are a
`.tres` edit.

## Typography

**Display Font:** IM Fell English SC (with Georgia serif fallback) — a digitization of
the c.1667 Fell types that keeps their rough, unevenly-inked impressions; the
"deliberate misprint" baked into the letterforms, and small-caps titling that reads as
tarot caption plates.
**Body Font:** Alegreya Sans (with Verdana sans fallback) — a humanist sans from a
family designed for literature; its calligraphic skeleton keeps the print voice at
phone-scale sizes, with true weights and an italic for chronicle lines.
**Label/Mono Font:** none distinct — labels use Alegreya Sans Medium.

**Character:** A 17th-century press captioning a 21st-century idle game: wobbly
small-caps display over a crisp, slightly bookish workhorse. Neither face is an
AI-default sans; both are OFL-licensed and vendored through the asset pipeline
(`assets/vendor/fonts/`, license texts beside each family, pinned in ATTRIBUTIONS.md).

### Hierarchy (authored sizes at scale 1.0; `ui/theme/spread_theme.tres`)

- **Display / Heading** (IM Fell English SC, 42px): screen titles — the letterhead's
  leader name plate is tuned to 28px for table width.
- **Card Title** (IM Fell English SC, 34px): card name plates and the intro packet's
  title; regime Major-Arcana titles print one size down (the castle-title rule).
- **Body** (Alegreya Sans Regular, 22px): default reading size (theme default size 24
  covers untyped labels).
- **Chronicle Line** (Alegreya Sans Italic, 22px): every printed event row — the
  clerk's hand. On dark grounds prints Cheap Paper; on aftermath, Press Ink.
- **Numerals** (Alegreya Sans Bold, 26px): pip amounts and counted values, abbreviated
  idle-scale (`Inks.abbreviate_amount`: 1234 → "1.2K", 15400 → "15K", 1250000 → "1.3M").
- **Role Line** (Alegreya Sans Medium, 19px): card role captions, countdowns, fan hints.
- **Pip Label** (Alegreya Sans Medium, 15px): the textual resource channel ("FOOD",
  "TIMBER", "IRON") and the run clock plate.
- **Button** (Alegreya Sans Regular, 22px): chip labels.

### The font-scale seam

`ui/theme/type_scale.gd` multiplies the whole ladder by `castle_storm/type/scale`,
clamped to **1.0–1.3** (the cap is where fixed strip/rail plates would start clipping;
labels fail safe by clipping at the plate edge, never past the table). Text-bearing
panel budgets (the blockquote's 560px width, the choice card's width) grow by the same
factor so the no-clip surfaces stay no-clip at 1.3. Applied at boot; `CS_TYPE_SCALE`
overrides for capture; `TypeScale.scaled(base)` keeps local overrides on the ladder.

### Copy integration (the printed voice)

Every line is rendered by `sim/copy_deck.gd` (CopyDeck) from
`content/mvp/copy_table.tres` — 101 keys, 1–4 variants each, rotated by data already in
the view (event seq, run number, from_tick, beat hash — never RNG, never wall time).
Copy may embellish tone; it may never invent facts. The no-clip line budgets
(`docs/voice-bible.md` §4, font-metric-pinned in `tests/unit/test_copy_voice.gd`
against the real AlegreyaSans Italic face with ≥30px margin at worst-case
substitution):

- Blockquote / event-quote rows: **476px** label (560px panel − margins − rule).
- The choice card's rows: **232px** (312px card − pads − rule).
- The intro packet's lines band: **504px**.
- The rolling strip (wide/landscape): **610px**.

### Named Rules

**The Clerk's Hand Rule.** Events print in the italic workhorse; the display face is
for titling only (headings, card names, letterheads). No surface sets body copy in IM
Fell.

**The No-Clip Rule.** Every variant of every single-line template, substituted at
worst-case parameters, must fit its surface's label in the theme's real face with
≥30px margin. New copy that clips fails `test_copy_voice.gd`; names and counts are
substituted from sim data (`{first}`, `{points}`, `{regime}`), never authored.

## Layout

One square **720×720 design base** (`canvas_items` + `expand` stretch: the short edge
maps to 720 on every target — phone portrait, Deck 1280×800, 1920×1080), so one design
unit ≈ one dp and the 48-unit touch grip is the PRODUCT.md ≥48dp floor.

**Responsive topology (T-UI-02):** every screen extends `ResponsiveScreen`
(`ui/layout/responsive_screen.gd`) — SlotHost (12px design margin + clamped safe-area
insets) holding a PortraitSlot and a LandscapeSlot that instance the SAME component
scenes, swapped by `LayoutRouter` (`ui/layout/layout_router.gd`):

- **Portrait** — pip rail as a TOP rail, stacked spread below it, chronicle strip at
  the bottom.
- **Landscape** (Deck/desktop) — panoramic table filling the screen, chronicle strip
  along the top (wide lines read wide), pips along the BOTTOM edge.

Swaps are hysteretic: aspect deadband 0.95–1.05 never swaps, and an out-of-band aspect
must persist 0.25s (dwell) before the topology lands. Every swap restores focus by
`focus_id` equivalence (`pip_i`, `spread_card_i`, `chronicle_i`) so controller players
never lose their place; the incoming slot always ends focus-enabled.

**The spread itself** is `CardSpread` (`ui/layout/card_spread.gd`), a custom Container
with pure, test-pinned math: STACKED mode is a centered grid (2 columns default,
adaptive ladder to 5 — `SpreadCards.adaptive_columns` keeps every row at or above a
96-unit card grip); PANORAMIC mode is an arc along the table's width — cards
bottom-align with a parabolic lift (center highest, `arc_depth` 24), rotation swinging
±10° end-to-center, overlapping like a held fan (min advance 55% of a card width) when
the table is narrow. Cards keep aspect 0.68 (w/h), capped at 330 units tall; 36 units
of rotation slack reserve height for the rotated bounding boxes.

**Density rhythm:** 12-unit table edge margin, 18-unit pip-rail separation, 20-unit
card gaps, 6-unit chronicle-row separation, 16-unit header-strip separation. The run
header inserts at the very top and shifts everything below: a two-row COLUMN (probe-
measured — the letterhead row has no width to spare at the 720 portrait base) — the
letterhead (leader name, regime-ink rule, regime name, clock) at full table width
(the name wrapping to as many lines as the pools deal, the row growing with them),
then THE LEDGER VERBS row (The Chronicle chip + The Day-Sheet chip, right-aligned,
full grips).

**Key Characteristics:** hierarchy reads ground → cards → pips/numerals (edges first,
numbers second, faces last); roster runs 1–30 cards; the Watchful Eye perches on the
table's right edge, inset sliding toward the heart as suspicion rises — and when the
telegraph arms, the card field reserves the right lane (`CardSpread.right_reserve`) so
the Eye's full-size armed plate never crowds the fan's end card.

## Elevation & Depth

This system uses **no shadows at all** — none are defined anywhere in the theme or the
draw code. Depth is conveyed the way a print conveys it:

- **Tonal layering:** bright paper cards sit on a dark ground whose tone deepens by run
  phase; recessed paper (buttons at rest) sits one shade below card paper; aftermath
  washes the whole ground cold and light and inverts the print rule.
- **Misregistration:** the seeded misprint (rotation + offset), the focus mark (an
  offset second red pass that "missed registration"), and the flip landing's BACK-out
  overshoot all read as physical print depth, not glow.
- **Paper over table:** full-screen moments (intro reveal, chronicle ledger, assault
  vignette, blockquotes) are paper laid over a veiled table — a ground-toned ColorRect
  veil at 0.90–0.92 alpha — never opaque modal chrome; the table stays live beneath.

### Named Rules

**The Flat-Print Rule.** Surfaces are flat at rest. No gradients, no shadows, no glow;
emphasis is a second ink pass (the red ghost), an ink wash (the Eye's strike), or a
flash of the ground itself (the crackdown's 0.75s aftermath flash).

## Shapes

Cut paper, not molded plastic. The card is an **8-point chamfered quad** — a 9-unit
corner chamfer (`FRAME_CHAMFER`) described as cut paper; rounded-luxe corners are an
explicit rejection. Small controls get the press's slight rounding instead: 4px on
button chips, 5px on paper panels (theme styleboxes).

- **Card frame grammar** (`ui/theme/card_frame.gd`): paper quad inset 8 units from the
  control rect (`FRAME_INSET`), a 4-unit ink border carrying state by line form —
  SOLID (4-unit closed polyline), DASHED (10-unit dashes / 7-unit gaps on the long
  edges only; the chamfers stay solid — the paper is still cut, only the ink runs
  out), STRUCK (2-unit border plus a 5-unit diagonal strike corner-to-corner with
  misprint jitter). Inside: a 1.5-unit regime-secondary hairline; outside: an 8×8
  revolution-red corner seal 12 units in from the top-left (off for Crown paper — the
  seal is the revolution's stamp).
- **Rules** (`ui/theme/rule_mark.gd`): the line-form grammar at glyph scale — solid /
  dashed (6-on, 9-pitch) / struck (rule + its own strike-through) / double (the
  victory flourish, two 0.7-weight rules ±3 units).
- **Resource pip containers** (`ui/theme/pip_glyph.gd`): circle (food), square
  (timber), hexagon (iron) — paper fill, 3-unit ink outline, distinct by construction.
- **The paper grain:** a whisper of halftone dots on the table ground — 26-unit
  spacing, 1.15-unit radius, 0.055 alpha paper dots, baked once into a shared 26×26
  `ImageTexture` tile (T-PERF-02's Deck-profile fix: one tiled draw instead of ~1,250
  `draw_circle` calls per ground per frame) and placed with per-phase grid jitter.
- **The placeholder face** (`ui/theme/face_slot.gd`): an authored flat silhouette —
  circle head over a trapezoid shoulder block in Ink Running Low at 0.55 of the slot's
  short side — honestly generic until vendored art lands.

## Components

### The Card (the system's atom)

- **CardFrame** (`ui/theme/card_frame.gd/.tscn`): the print-block card described under
  Shapes. Focusable; a focused frame re-prints its border offset in Revolution Red —
  readable without hover and without color. Exports: `edge_form`, `regime_id`,
  `misprint_seed` (0 = clean print, used for chrome cards), `show_seal`.
  **The flip contract** — `flip_to()`/`set_face_up()`/`is_face_up()` +
  `flip_started`/`flip_completed`: the base grammar flips INSTANTLY (a print laid on
  the table does not animate); the authored promotion flip
  (`play_promotion_flip(swap)`) interposes on the seam (see Motion below). Minimum
  size: a 96×96 grip (2× touch grip).
- **CardFace** (`ui/theme/card_face.gd/.tscn`): the face plate — art slot + name plate
  (display face, clipped) + solid under-title rule (portrait cue) + role line (soft
  ink). Reflows portrait-stacked vs landscape-side-by-side on its own aspect
  hysteresis (flip above 1.15, back below 1.0).
- **FaceSlot + FaceArt + the print shader** (`ui/theme/face_slot.gd`, `face_art.gd`,
  `face_print.gdshader`): face art resolves through the content art manifest — one
  `atlas_region` cell of the vendored Kenney Toon Character pose sheets (uniform 9×5
  grid of 96×128px; cell (0,0) = neutral front pose) as an `AtlasTexture`, printed
  through the two-ink pass: source luminance → ink coverage (solid below luma 0.16,
  thin 0.14 wash above 0.78, `ink_color` = Press Ink), source alpha preserved so the
  paper stock shows through. One shared ShaderMaterial for the whole spread; pending
  or unknown keys print the authored placeholder — landing art is a content edit.

### Resource Pips (the table-edge notation)

- **PipMark** (`ui/theme/pip_mark.gd/.tscn`): glyph + abbreviated numeral (Numerals
  face) + optional name label (PipLabel) — the colorblind-safe triple channel, color
  on the glyph being redundant only. 72×48 minimum (a collectable grip). Rail order =
  pack resource order (FOOD / TIMBER / IRON).

### Chronicle Lines (states print themselves)

- **ChronicleLine** (`ui/theme/chronicle_line.gd/.tscn`): one printed event — a
  RuleMark prefix whose form is the event class (plain solid / warn dashed / strike
  struck / victory double, from `Inks.line_class_for_event`) + the italic clerk's hand,
  ink chosen by the print rule from the ground beneath. Focusable (the history walks
  by controller); a focused row re-prints its baseline offset in the ground's red.
  Grip-height rows (48 units); text clips at the strip edge, never past the table.
- **EventQuote / blockquotes** (`ui/screens/spread/suspicion_events.gd`,
  `catch_up_print.gd`): crackdowns, crushes, and while-you-were-away windows print as
  paper panels on the table (560px wide, scaling with the type factor) — rows of
  ChronicleLine grammar that dwell (2.6s base) and fold themselves. Never popup chrome.

### The Table Ground

- **TableGround** (`ui/theme/table_ground.gd/.tscn`): the phase-deepening ground +
  halftone grain (see Colors/Shapes). Also owns the 0.75s aftermath flash (a pure
  `flash_color` lerp toward ash) that pays across the table when a crackdown lands.

### Chrome

- **RunHeader** (`ui/screens/spread/run_header.gd`): the letterhead — leader name
  (display face, 28px), a solid rule in the regime's second ink, uppercase regime
  name in the secondary, clock/power plate in PipLabel; text ink by the print rule
  against the live ground. The letterhead's line budget (finishing refinement #6):
  the name WRAPS at word boundaries when the pools deal a long one (the epithet
  drops to its own line — never a mid-word clip at any type scale), the regime and
  clock plates fit their own measured text (a plate grows, its print stays whole),
  and the row's wrapped height is derived inside the slot's topology pass — a pure
  function of text + type factor + strip width, so the rendered layout stays a
  function of sim state alone. It tops a two-row header column whose second row is
  THE LEDGER VERBS (The Chronicle + The Day-Sheet ActionChips, right-aligned, full
  grips, focus-equivalent across orientation swaps).
- **ActionFan / ActionChip** (`ui/screens/spread/action_fan.gd`): the contextual
  affordance — a column of print-styled chips fanned at a card's edge (to its right,
  mirrored left when the table runs out, always inside the screen). Each chip: leading
  rule solid-enabled / struck-refused / double-the-signature-promote, label, refusal
  reason in soft ink. Buttons with the theme's chip styles (4px radius, 14/9 padding,
  PAPER_DIM rest / PAPER hover / PRESSED-PAPER pressed / FADED-PAPER disabled); focus
  is the red offset pass; the fan is a cyclic focus trap; the hint strip prints
  "choose — act — back". Disabled chips stay focusable so pad players can read why.
- **WatchfulEye** (`ui/screens/spread/watchful_eye.gd`): suspicion as a CARD — a
  seal-less frame creeping in from the right-edge perch (position), edge by line form
  (solid watching / dashed closing / struck telegraph-armed), a drawn almond eye whose
  iris dilates with dread, countdown plate, 0.55s strike bell (1.18× scale + a red wash
  that prints WIDER than the card onto the ground, 2.2× its rect) and 0.45s retreat
  flinch. THE ARMED PLATE (finishing refinement #3): an armed telegraph is a state, not
  a level — the Eye overrides the meter's creep (full inset, full scale, full dread),
  grows to a full card (144×202 design units), and prints the choice card's urgent
  vocabulary: a short DOUBLE red rule, the red countdown caption ("lands in"), and the
  landing hours as the plate's largest mark in INK (the numeral-plate grammar — size
  carries the escalation, never hue alone; red stays inside its 30–60% accent share).
  The table makes way: CardSpread's `right_reserve` keeps the card field (and the fan's
  rotated end-card corners) clear of the armed seat, so the perch never crowds the end
  card. The resting creep is untouched — unarmed binds are exactly the authored quiet
  forms — except the rest plate's share readout (finishing refinement #6): the share
  prints as a bare INK_SOFT numeral (the glyph carries the watching), its size
  COMPENSATING the card's meter scale so it reads at ~RoleLine size at every creep
  depth and never draws past the plate (the old caption both shrank to ~11px
  effective and spilled 60–155px onto the table). The armed countdown refreshes per
  sim batch so the numeral never goes stale.

### The Screens (paper over the table)

All screens compose the same grammar; none fork a component:

- **The Spread** (`ui/screens/spread/spread_screen.gd`): the home screen — live cards,
  pips, chronicle strip (2 rows, newest first), Eye, ground, header; event-driven
  targeted refresh (no whole-state polling); deterministic view/layout hashes.
- **IntroScreen / IntroPacket** (`ui/screens/intro/`): the leader intro / restart
  reveal — folded card backs, the leader card face-up, the regime face card at
  Major-Arcana scale (strictly larger, no seal), printed beat lines, and THE ONE
  GESTURE chip; the 1–3s unfold sweeps the packet open onto the live table beneath.
- **AssaultScreen / AssaultStage** (`ui/screens/assault/`): the odds table staged ON
  the table (army cards vs the castle card with regime ink), the vignette replayed
  from the captured event stream (march down the siege lane, cards struck
  newest-first, castle dashed at the gate, aftermath wash), skippable with one input.
  The odds table seeds focus on RETREAT (the free verb) and COMMIT is a two-step
  raise — the first press arms (the clerk's printed caution, the chip re-labeled),
  the second casts the die; one mispress never decides the run.
- **ChronicleScreen / ChronicleSheet** (`ui/screens/chronicle/`): the ledger of past
  spreads over a 0.90 veil in the live regime's ground tone; outcome seals by form
  (WON double / CRUSHED struck / ABANDONED dashed); the live run prints as its own
  dashed strip, never an entry — and that live line WRAPS for real pool names (every
  leader name exceeds the row's label budget), so its band holds the wrapped lines
  (finishing refinement #6: two lines at 1.0×, grown by the type factor — the same
  principle as every text-carrying budget; the pre-#6 one-line band covered the
  second line).
- **DaySheetScreen** (`ui/screens/spread/day_sheet_screen.gd`): the live run's own
  page — the retrieval surface for in-run history. Every line this hand printed
  accumulates on one scrolled column of ChronicleLine rows, NEWEST FIRST (the
  strip's reading order; the sought line is usually recent), with the blockquote-only
  payloads included (the scatter rows with names, the while-you-were-away detail
  rows). Data: the SpreadPresenter's run-scoped ledger (`push_row` is the one choke
  point), cleared when a new hand is dealt, NOT persisted — the durable record of a
  run is the chronicle entry it becomes; past the 600-row cap the oldest prints leave
  the page and the truncation prints honestly. Opened from the header's Day-Sheet
  verb; paper over a veiled table; the count rule prints dashed in red (the page
  itself is work in progress); an open page is live paper (new prints land on top);
  focus walks the rows with scroll-follow; back returns focus to the chip.

- **PressRoomScreen** (`ui/screens/spread/press_room_screen.gd`): the game's
  settings card — the
  accessibility surface, as paper rather than chrome. THE HAND (the letter
  size, four numeral steps 1.0×–1.3×, the audited range) and THE PRESSWORK
  (Full turn / Steady hand = reduced motion); the step in force carries the
  DOUBLE red rule (the ActionChip's signature mark — state by line form,
  never hue alone); the kept rule prints SOLID ink where the day-sheet's
  count rule prints dashed (settled fact vs work in hand). A step press
  applies LIVE (TypeScale rewrites the shared theme + the spread rebinds
  the whole view; MotionProfile answers immediately — no restart), writes
  `RunMeta.preferences` (additive-optional, META domain) and saves the meta
  file at once; the boot seam re-applies both before any chrome bakes
  sizes. Pressing the step already in force is a quiet no-op. Mutually
  exclusive with the chronicle and day-sheet (whichever paper opens folds
  the others); story paper (choice card, beat, reveal, vignette) folds it —
  the story never waits on the table's papers. No debug/show-fps here: dev
  chrome stays gated on `CS_DEBUG_CHROME`.

### Motion grammar

Three named transitions, paced in one place (`ui/theme/motion_profile.gd`), all
reduced-motion aware (`castle_storm/motion/reduced_motion`, or the
`MotionProfile.forced` hook; reduced = near-instant, same signals, same end state —
the reveal is content, not animation; entrance slides skip entirely):

- **Flip (promotion, the signature moment):** 0.65s scale-x squeeze about the center
  pivot — 42% away sweep (QUAD in), the silent content swap at the 90-degree crossing,
  return sweep (BACK out — one registration overshoot), then the landing stamps the
  flourish: a double Revolution-Red rule inside the hairline fading over 0.40s like a
  press impression lifting. One flip at a time per card; an in-flight flip
  snap-finishes in contract order.
- **Slide-and-settle (cards joining a live table):** 0.28s slide from the deck's
  seat at the table's head (offset 170, −110) with one BACK-out overshoot; a re-sort
  snaps any settling card onto its seat first. Offline promotions replay as a capped,
  staggered queue (latest 3).
- **Unfold (open / session start):** the packet sweeps open 1.7s (resumed check-in
  1.0s + 0.75s auto-open dwell — one gesture OR auto inside the 3-second promise);
  the veil lifts first, the leader card sweeps to the table's heart while the regime
  card withdraws, the print fades last.

### Component inventory (file map)

| Component | Path |
|---|---|
| Token source of truth | `ui/theme/inks.gd` |
| Theme mirror (styleboxes, type variations) | `ui/theme/spread_theme.tres` |
| CardFrame / CardFace / FaceSlot | `ui/theme/card_frame.gd` · `card_face.gd` · `face_slot.gd` |
| Face atlas resolver + print pass | `ui/theme/face_art.gd` · `ui/theme/face_print.gdshader` |
| PipMark / PipGlyph / RuleMark | `ui/theme/pip_mark.gd` · `pip_glyph.gd` · `rule_mark.gd` |
| ChronicleLine / TableGround | `ui/theme/chronicle_line.gd` · `table_ground.gd` |
| MotionProfile / TypeScale | `ui/theme/motion_profile.gd` · `type_scale.gd` |
| Component gallery (visual inspection) | `ui/theme/theme_gallery.tscn` (`make run-gallery`) |
| LayoutRouter / OrientationSlot / CardSpread / ResponsiveScreen | `ui/layout/layout_router.gd` · `orientation_slot.gd` · `card_spread.gd` · `responsive_screen.gd` |
| The Spread + card factory + fan + Eye + header + motion | `ui/screens/spread/` (spread_screen.gd, spread_cards.gd, card_actions.gd, action_fan.gd, card_motion.gd, watchful_eye.gd, run_header.gd, suspicion_events.gd, catch_up_print.gd, first_session.gd, day_sheet_screen.gd, press_room_screen.gd) |
| Intro / Assault / Chronicle screens | `ui/screens/intro/` · `ui/screens/assault/` · `ui/screens/chronicle/` |
| Regime inks (content) | `content/mvp/regimes/{gilded_crown,iron_rotunda,paper_crown,velvet_fist}.tres` |
| Copy system | `sim/copy_deck.gd` + `content/mvp/copy_table.tres` + `docs/voice-bible.md` |
| Pins | `tests/unit/test_theme_grammar.gd` · `test_type_scale.gd` · `test_colorblind_audit.gd` · `test_copy_voice.gd` |

## Do's and Don'ts

### Do:

- **Do** carry state by line form (solid ready / dashed in progress / struck lost /
  double victory) — reuse `Inks.EDGE_FORM_STATES` / `line_class_for_event`; unknown
  vocabulary fails loudly in review (push_error), never silently.
- **Do** choose text ink by the print rule (`Inks.ground_text_ink`) whenever anything
  prints on the ground — header, chronicle, quotes all do.
- **Do** keep every interactive target at or above the 48-unit grip (cards 96×96
  minimum; chronicle rows grip-height; chips grip-sized).
- **Do** let content recolor: regime grounds/secondaries, faces, and copy are data —
  UI code reads them through `Inks`/the manifest, never hardcodes.
- **Do** print events as chronicle lines/blockquotes on the table; dwell and
  self-fold paper rather than dismissing it for the player.
- **Do** keep in-run prints retrievable — the strip is a window, the day-sheet is
  the hand's page (every strip row + blockquote payload accumulates on it, newest
  first); teach the line-form grammar once per session at its first dashed edge,
  and let the background save flush print one quiet filing line (the periodic
  hourly autosave stays silent — routine status is not news).
- **Do** budget single-line copy against its surface (476px quote rows / 610px strip
  / 232px choice card / 504px packet band) in the real italic face with ≥30px margin.
- **Do** route every motion through `MotionProfile.duration()` and scale-bump local
  font sizes with `TypeScale.scaled()`.

### Don't:

- **Don't** add gold trim, gradients, rounded-luxe corners, shadows, glows, or pastel
  softness — the world refuses all of them (chamfer is cut paper; radius stops at 4–5px
  on small controls).
- **Don't** encode state, resource identity, or focus by hue alone — color is always
  the redundant tertiary channel.
- **Don't** open popup/modal chrome for in-world events (no Popup/Window nodes —
  pinned by test); paper goes on the table, over a veil at most.
- **Don't** put body copy in the display face, or print Ink-on-dark / Paper-on-light
  (follow the print rule; the dark phases and the aftermath wash never cross the
  0.19-luma band).
- **Don't** invent UI-side regime colors, face art, or copy variants — each has a
  content schema and a validator that refuses unknown keys.
- **Don't** exceed the misprint bounds (0.9° / 2 units) or the type-scale range
  (1.0–1.3); wobble is character, noise is a bug.
