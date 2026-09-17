# Voice Bible — Castle Storm (T-COPY-01, Professor X lane)

The satirical voice of the game: what it sounds like, why it sounds like
that, the rules every printed line obeys, and the machinery that keeps it
honest (validated content, budgeted lines, seeded rotation). Authority
chain: `PRODUCT.md` (the reset-is-the-story principle) → the town-hall
tone decision (satirical farce — silly names, pompous regimes, ironic
chronicles; **laughing at power while toppling it**) → this document.

The voice ships as DATA: `content/mvp/copy_table.tres` (the variant
table) + `content/mvp/identity_pools.tres` (the names), rendered by
`sim/copy_deck.gd` (`CopyDeck`) and pinned by
`tests/unit/test_copy_voice.gd`.

## 1. The register — three voices, one world

The world is a cheap-print conspiracy: a barn loft, a candle, a
hand-cranked press, cards dealt on a table. Every line is printed BY
SOMEONE in that world. There are exactly three someones:

### The regime voice — pompous-official
**Who speaks:** the Crown, its clerks, its edicts, its riders, everything
the castle does. **How it sounds:** self-important, bureaucratic,
self-congratulating. The regime never admits violence; it *files* it.
Its cruelty is paperwork. Its power is tone.

- "Taxes your timber, stations archers on every wall, and calls the
  arrangement prosperity." (The Gilded Crown's flavor card)
- "CRACKDOWN #7. The paperwork was flawless."
- "The Velvet Fist calls it peace. It is well paid."

The joke is ALWAYS the gap between the officialese and the mud. The
regime is petty, vain, and fatally pleased with itself — that is what
the player topples.

### The rebel voice — earthy-underdog
**Who speaks:** the conspiracy and its people — recruits, the leader's
own cards, the spread's strip lines. **How it sounds:** short, concrete,
unimpressed. Bread, carts, mud, barns, drills. The rebellion has no
rhetoric; it has chores.

- "Wat arrives at the gate, hat in hand."
- "The gate thins: 3 sent home, thanked, unpaid."
- "The army advances through the mud to the walls."

The underdog never wails. Losses are stated flatly ("Nell is sent home
with kind words and no bread") — the deadpan IS the comedy and the
dignity.

### The chronicle voice — the ironic clerk-narrator
**Who speaks:** the printed record itself — the rolling strip, the
chronicle screen, the catch-up print, the reveal's lines. **How it
sounds:** a minor clerk with a dry streak, recording everything,
impressed by nothing. The narrator is ON the player's side the way an
honest witness is: it reports the truth that embarrasses power.

- "Somewhere in the capital, a clerk underlines your name. Twice."
- "…4 recruits discover relatives in other counties."
- "The clock was wound backwards. Nothing was lost."

The clerk's irony targets the regime first, the player's disasters
second, and always gently: the player is mocked for theatre ("The hand
collapses"), never for trying.

### The four regimes, in one line each (established personalities)

| Regime | Personality | The line |
|---|---|---|
| The Gilded Crown | Gaudy, grasping, calls greed prosperity | "Taxes your timber, stations archers on every wall, and calls the arrangement prosperity." |
| The Iron Rotunda | Grim, rigid, prices everything in iron | "Everything here is iron, including the decrees. Everything costs accordingly." |
| The Velvet Fist | Soft-spoken, generous, naps its garrison | "Governed with kindness, generously applied. The fields flourish; the walls doze." |
| The Paper Crown | Penurious, procedural, cheap glory | "A frugal court of scrap and ledger. Timber is cheap here, and so is glory." |

When copy addresses "the Crown" generically (the strip's suspicion
lines), it means whichever crest rules — regime-specific suspicion copy
is a future additive key, not MVP scope.

## 2. The rules

1. **No modern anachronisms.** The world is pre-industrial farce. No
   technology, no casual slang, no meta/game vocabulary (§3). Period
   officialese is allowed and encouraged: warrants, seals, ledgers,
   stipends, requisitions, edicts, heraldry, tithes.
2. **Humor from pomposity and bureaucratic absurdity, never cruelty.**
   The comedy is the regime's self-importance and the world's
   matter-of-fact resilience. Never mock the poor for being poor, never
   punch down at the recruits, no graphic violence (farce arson — "the
   barns burn" — is the ceiling), no modern political references.
3. **Failure stings via the regime's smugness; hope banks via the
   concrete number.** The crush beat's grammar: the regime closes its
   hand (smug, official) → the chronicle remembers (record outlives the
   crest) → **the bank keeps what fire cannot: N points** (the real
   number, the player's to keep). The sting is being *filed*; the hook
   is *what you still hold*.
4. **Revenge is one reveal away.** The loss-restart reveal's first line
   names the SAME crest that crushed the dream, dealing your very next
   hand — "The Gilded Crown crushed Bartholomew's dream." / "Same crest,
   same walls." — the reset is the story, not a punishment.
5. **One voice per fact.** A fact prints in ONE canonical place and
   every surface that repeats it reads the same source (the catch-up
   headline: strip row == blockquote lead == reveal away line, all
   `CatchUpPrint`; the suspicion beats all read `SuspicionSystem`'s
   render query).
6. **The reveal cannot lie.** Every name, count, hour, crest and banked
   number in every line is the sim's own data substituted into a
   template — `{first}`, `{points}`, `{regime}`. Copy may embellish
   tone; it may never invent facts.
7. **Marker phrases are API.** Where a test or surface recognizes a
   line by a phrase ("gate thins", "cards close", "regime remembers",
   "tree line", "CRACKDOWN"), EVERY variant of that key carries the
   phrase — variety changes the tail, never the marker.

## 3. The banned list

Breaking-register words refused at load (`CopyTable.BANNED_FRAGMENTS`,
word-boundary, case-insensitive — the validator scans shipped copy,
`test_copy_voice.gd` scans the code-side floor and every identity pool):
modern anachronisms (okay, cool, awesome, email, internet, phone, wifi,
battery, caffeine, pizza, taxi…), casual slang (dude, hey, hello, congrats,
sorry, lol, omg, yeet…), and meta/game vocabulary (level up, xp, loot,
quest, boss, respawn, grind, buff, nerf, noob, tutorial, speedrun, git,
merge, startup, marketing…).

Hand-checked beyond the automated list (review rule, not grep): no named
real historical figures after ~1500, no real-world religions' rites as
punchlines, no fourth-wall breaks (the press is IN the world; it never
mentions players, games, or screens), no modern politics by analogy. If
a joke needs the player to know the present, it is the wrong joke.

## 4. The line budget (the no-clip standard)

Chronicle rows are SINGLE-LINE clip (`clip_text` — the row grammar). The
standard, from T-UI-06's clip find and T-UI-09's font-metric pin: **every
variant of every single-line template, substituted at WORST-CASE
parameters, fits its surface's label in the theme's real AlegreyaSans
italic face (declared 22px, measured at the conservative 24 fallback)
with ≥ 30px of margin.** Pinned by
`test_every_template_variant_fits_its_surface_in_real_font_metrics`
against the LIVE pack — pool growth cannot silently outrun the budget
(the worst case is recomputed from the pools every run).

| Surface | Label budget | Margin floor | Keys |
|---|---|---|---|
| Blockquote / EventQuote rows | 476px (min(560, bounds−12) − 84) | ≥30px | crackdown_*, scatter_*, crush_*, catchup_* rows, beat_*, chronicle_empty_* |
| The choice card's rows | 232px (312 − pads − rule) | ≥30px | card_warn_line, card_telegraph_line, warn_context, telegraph_context |
| The intro packet's lines band | 504px | ≥30px | intro_* |
| The rolling strip (wide) | 610px | ≥30px | everything that prints in the strip |

Worst-case substitution values (all derived live): longest regime name
("The Gilded Crown"), longest leader first (≤ 12 chars by pool rule),
longest recruit name (≤ 8), longest gear ("Grandfather's Plate"),
longest building ("Training Grounds"), 3-digit counts, 4-digit points,
3-digit hours, the widest stores line ("+9999 food, +9999 timber,
+9999 iron"), two longest recruit names joined for `{who}`.
Practical ceiling at the 24 over-measure: ~48 chars for quote-class
prose, ~24 for card phrases, ~52 for packet lines, ~62 for the strip.
The assault outcome block is exempt (its label AUTOWRAPS — two
sentences are the design); chip labels are grip-sized buttons, not
chronicle rows.

Two adjacent budgets are WRAP-shaped, not clip-shaped, and owned by
their surfaces: the intro/chronicle name plates wrap word-smart at
measured sizes (T-UI-05), and the chronicle sheet's role plate wraps at
the " · " separator so a trait never splits mid-phrase (T-COPY-01 fix).

## 5. The naming pools

Shape rules, then the numbers (`content/mvp/identity_pools.tres`):

- **Leader first names** — period farce, plausible-but-ridiculous
  (Ottilie, Bartholomew, Kunegunda, Hamo). **≤ 12 chars**: first names
  print inside single-line strip copy (`run_started` etc.).
- **Leader epithets** — the pomposity engine, two patterns: "the
  Adverbially Adjective" ("the Marginally Brave", "the Mildly
  Terrible") and "of the Comic Noun-Phrase" ("of the Miscounted Army",
  "of the Thumb-Marked Ledger"). The epithet is the joke; the farce is
  that someone embroidered it. ≤ 28 chars (plates wrap, never strip).
- **Personality tags** — one lowercase word each, drawn TWO distinct per
  leader ("vengeful and pious"). 20 shipped: the sharpened set adds the
  farce-workhorses (spendthrift, superstitious, practical, stubborn,
  cowardly, magnanimous).
- **Recruit names** — monosyllabic comic texture (Wat, Hob, Broom,
  Scrag, Gobbet, Thistle). **≤ 8 chars**: recruit names print in strip
  rows, scatter rows and casualty lines. Real medieval bynames, not
  jokes about the person (Broom sweeps; nobody is mocked).
- **Leader traits** — what the PRESS calls them (T-COPY-01's new
  additive pool; the run lifecycle draws from content, one draw either
  way): "Born Unlucky", "Sneezes at Kings", "Ledger-Devout",
  "Mildly Doomed". ≤ 16 chars — the role plate's wrap keeps each whole.

**Permutation space: 46 firsts × 52 epithets = 2,392 full names**
(thousands, pinned at ≥ 2,000 by test), 20 tags (190 ordered pairs ×
2-slot draws), 72 recruits, 10 traits.

## 6. The template table (keys, tokens, variants, consumers)

The complete vocabulary is `CopyTable.KEY_TOKENS` (128 keys; content
cannot invent keys the code never reads). The shipped variant counts and
the surface consuming each key print into the test log as the COPY
COVERAGE REPORT (`CopyDeck.coverage_report`) — the machine-checked
answer to "which screens got which templates". Shape of the table:

- **Suspicion beats** (`suspicion_warn/telegraph/rose`,
  `crackdown_cancelled/struck/seized/scattered`, `run_crushed`) — the
  strip + blockquote vocabulary; the sim's own render query, rotated by
  event seq.
- **The spread's strip** (`recruit_*`, `training_*`, `unit_promoted`,
  `gear_equipped`, `building_*`, `run_*`, `assault_*`, `clerk_denied`,
  `gate_thinned`, `cards_kept_close`…) — rotated by event seq.
- **The choice cards** (`card_*`, `warn/telegraph_context`, `chip_*`) —
  the card-budget short forms; the full beat line stays in the strip.
- **The crush beat** (`crush_regime`, `crush_chronicle`, `crush_bank`)
  + **the reveals** (`intro_*`) — rotated by the RUN number (the next
  deal reads differently).
- **The catch-up print** (`catchup_*`) — rotated by the window's
  `from_tick` (the headline itself is rotor-0-only: one voice).
- **The assault vignette** (`beat_*`, `assault_win/loss_*`) — rotated
  by the battle's own visual-sequence hash.
- **The chronicle's empty page** (`chronicle_empty_*`) — rotor 0
  always (an empty chronicle means run 0).
- **The first session's printed cues** (`first_gate`, `first_assign`,
  `first_build`, `first_trickle`, `first_train`) — once-only teaching
  lines in the strip (T-UI-10), rotor = the beat's own tick (the line
  a player reads is fixed by when the world brought the moment).
- **The legacy tree's voice** (`unlock_branch_<branch>`,
  `unlock_flavor_<node_id>` — L1-B): one branch-name key per branch
  plate and one flavor key per node card, literal lines (no tokens,
  rotor 0 — the tree is static content), 1 variant each, table == floor
  (one voice, two origins); consumed by the L1-C tree UI, budget-pinned
  at the card/quote classes by `tests/unit/test_mvp_unlock_tree.gd`.
- **The escalation presence** (`garrison_escalation`,
  `escalation_captured`, `chronicle_escalation` — L2-B): the odds castle
  card's line when a CAPTURED garrison stands ("garrison 46 · Ottilie's
  veterans — cycle 2" — rotor 0, a static composition surface; the
  leader prints by FIRST name, the single-line pool rule), the strip's
  victory beat when the win garrisons the castle ("Ottilie's veterans
  take the wall — cycle 2." — seq-rotated, 2 variants, rides the
  `escalation_captured` event before `run_won`), and the victory
  chronicle entry's line ("this army holds the castle — cycle 2 opens" —
  run-number-rotated, reads the entry's `escalation_cycle` field). The
  clerk's register throughout: the army that won becomes the wall, the
  record says so flat — the joke is the castle now files YOUR paperwork.
  A non-capturing victory prints nothing (the pre-L2-B stream).

Every key that the sim REPEATS (`CopyTable.ROTATING_KEYS` — arrivals,
trainings, promotions, suspicion beats, headlines, card phrases) ships
≥ 2 variants; no key ships more than 4 (`MAX_VARIANTS` — variety, not
sprawl; the renderer is O(1)).

## 7. The rotation contract (seeded, deterministic, pure)

Variants are chosen by a ROTOR derived from data already in the view —
never RNG, never wall time: event `seq` (strip + suspicion), run number
(reveals + crush beat), `from_tick` (catch-up), the beat script's hash
(vignette), `choices_made` (chip acknowledgment rows). Consequences,
pinned by test:

- **Same state → same lines** (replay-identical; the view-hash oracles
  keep their guarantee — copy is a pure function).
- **Different events → different variants** (the third crackdown of a
  run does not read like the first; a returning player's fifth deal
  does not read like their first).
- **Rendering never touches the engine's RNG stream** (the sim's
  determinism oracles are untouched by copy).

## 8. Failure copy that stings without souring (the recipe)

The crushed beat and the loss reveal, in order (Prof X's T-UI-06
contract, now shipped):

1. **The sting is the regime's smugness** — "The Gilded Crown closes
   its hand. The barns burn." / "…files the dream as 'resolved'." The
   player is beaten by POMPOSITY, which is toppable. Never by despair.
2. **The record survives** — "The revolution is crushed. The chronicle
   remembers." (All `run_crushed` variants keep the word "crushed":
   the record states it plainly.)
3. **The hope is a number you keep** — "The bank keeps what fire
   cannot: 231 points." The REAL bank from the meta domain. Losing
   banks full progress (town-hall) and the copy says so concretely.
4. **Revenge under the same crest** — the reveal's first line, STRIKE
   weight: "The Gilded Crown crushed Bartholomew's dream." The next
   hand is dealt under the very crest that did it; the standard is
   already raised.
5. **Skippable the moment it reads as pressure** (T-UI-06's beat, not
   copy) — the copy never begs for its read.

The catch-up wry lines follow the same clerk: "The clock was wound
backwards. Nothing was lost." (clock-cheat policy: announced, never
punished — the copy IS the policy's tone).

## 9. Where the voice lives (the file map)

| Artifact | Role |
|---|---|
| `content/schema/copy_table.gd` | The key/token vocabulary, variant caps, rotating keys, banned list (validated) |
| `content/mvp/copy_table.tres` | THE shipped voice — 128 keys, 1–4 variants each |
| `ui/screens/spread/first_session.gd` | The first session's five printed cues (T-UI-10) |
| `content/schema/identity_pools.gd` + `content/mvp/identity_pools.tres` | The names (firsts, epithets, tags, recruits, traits) |
| `sim/copy_deck.gd` | The renderer: variant selection, substitution, fallback floor, coverage report |
| `sim/systems/suspicion_system.gd` | The suspicion beats' render query (seq-rotated) |
| `ui/screens/spread/spread_presenter.gd` | The strip's event lines |
| `ui/screens/spread/suspicion_events.gd` | Choice cards, scatter rows, the crush beat |
| `ui/screens/spread/catch_up_print.gd` | The while-you-were-away print |
| `ui/screens/intro/intro_presenter.gd` | The reveals (first run / win / loss / check-in) |
| `ui/screens/assault/assault_presenter.gd` | Beat summaries + the outcome block |
| `ui/screens/chronicle/chronicle_presenter.gd` | The empty page + the record's dressing |
| `tests/unit/test_copy_voice.gd` | The pins: budgets, rotation, gate reds, banned scan, coverage, failure-feel |

Adding copy: new keys start in `CopyTable.KEY_TOKENS` (+ `DEFAULTS` +
`CONSUMERS`), the surface passes its actual data, the table carries the
variants — the validator refuses unknown keys, bad tokens, single-variant
repeated beats and banned words at load; the budget pin refuses lines
that would clip.
