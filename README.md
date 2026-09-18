# Castle Storm

**A satirical idle-roguelite about starting a revolution from one peasant — and living with who wins it.**

Castle Storm is an idle army-builder fused with a roguelite restart loop. You begin as a single peasant under a regime you never chose: recruit followers, assign workers, craft gear, and train knights in real time — then storm the castle when the odds look right. Win or lose, the run ends and you restart as a new randomized peasant living under whatever regime now rules; the reset is the story, not the punishment, and losing never costs your banked progress.

The whole game plays out as **"The Conspiracy's Spread"**: a cheap-print tarot table in a barn loft, where every unit, event, and regime is dealt as an ink-on-paper card. Nothing pops up — events print themselves onto the table as chronicle lines.

## Status

Playable MVP plus Layers 1–2 (the persistent legacy tree; enemy escalation), production-complete and verified in CI. The full loop — recruit, economy, suspicion, storm, win/loss, restart — runs headlessly in accelerated time as an acceptance suite, alongside 1,000-hour stability runs, chaos-tested saves, and an input-parity matrix across touch, gamepad, and keyboard. What's in the loop:

- 3 resources (food, timber, iron), 4 upgradeable buildings, worker and militia-to-knight training plus an archer branch
- 2 gear slots across 3 tiers; 4 regime flavors, each with a combat modifier and an economy quirk
- The Watchful Eye: suspicion that ratchets as you grow, telegraphs, and lands crackdowns that seize resources — or a crush that ends the run
- Player-initiated auto-resolved assault with visible win odds and a played-out vignette
- Randomized leader identities and regimes on every restart; a persistent chronicle of past runs
- Offline progress resolved on return (capped at 8h) and printed as a while-you-were-away report
- **The Legacy (Layer 1, shipped)**: every ended run — win, loss, or abandon — banks legacy points. Between runs, the growing deck on the title screen (or the header's The-Legacy verb) spends them on 15 cards across 4 families: a richer stipend, cheaper walls and gear, faster drills, a cooler Watchful Eye, veterans that fight above their power. A card bought is kept forever and takes effect with the next hand — losing never costs the bank.
- **The ladder (Layer 2, shipped)**: every victory garrisons the castle with your own veterans — the next run's walls are held by your last winning army, at the exact power and gear tiers it took them with, and each cycle taken compounds the garrison ×1.10. The next hand's reveal says whose veterans hold the walls, the odds table prints the tier mix you armed them with, and the letterhead counts cycles taken. Your veterans are beatable (a full rebuild, not a wall) — until the compounding asks for the Legacy tree's help.

Balance is measured, not guessed: first recruit at ~7 minutes, first food trickle at minute 12, first win in the 2–4 wall-day band at a 4-check-ins-a-day rhythm ([docs/balance.md](docs/balance.md)).

## Requirements

- Desktop: macOS, Windows, or Linux (the Steam Deck is a first-class target at 1280x800)
- **Godot 4.7.2-stable** (standard/GDScript build, Compatibility renderer) — no separate install required if you vendor the pinned binary (below); the exact build is recorded in [docs/DEV_SETUP.md](docs/DEV_SETUP.md)
- ~164 MB for the vendored engine binary (export templates install outside the repo, only needed to build releases)

## Getting started

Everything goes through `make`. The Makefile defaults to a vendored engine binary at `tools/godot/godot` (gitignored, ~164 MB) so the whole repo runs against one pinned build.

```sh
git clone <repo-url> castle-storm
cd castle-storm
```

One-time setup, either option:

```sh
# Option A: vendor the pinned binary (macOS; other platforms see docs/DEV_SETUP.md)
mkdir -p tools/godot
curl -L -o /tmp/godot.zip \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip
ditto -x -k /tmp/godot.zip /tmp/godot-extracted
cp /tmp/godot-extracted/Godot.app/Contents/MacOS/Godot tools/godot/godot
chmod +x tools/godot/godot
codesign --force --sign - tools/godot/godot

# Option B: point at your own Godot 4.7.2 standard build
export GODOT_BIN=/path/to/godot
```

Then:

```sh
make version    # expect: 4.7.2.stable.official.ed1daf0bf
make import     # one-time asset import (also after adding assets)
make run-game   # play: the front door (title / continue / new run) — exactly what F5 runs
make check      # headless load check, exit 0 = project imports clean
make test       # full CI battery (see Testing below)
```

> [!NOTE]
> `make run-game` (and `make run`, and pressing F5 in the editor) boots the real game: a fresh install opens the CASTLE STORM title card, a saved run offers CONTINUE (offline time resolves at the press) or NEW RUN (a two-step confirm — abandoning banks the hand and the chronicle records it). `make run-demo` is the developer's seeded Spread demo drive (sensible-play autopilot, `CS_SEED=<int>` picks the seed, `CS_DEMO_RESET=0` continues the session); its debug accel — `F` cycling the time scale (1x / 60x / 600x) and `P` freezing the world — is gated behind `CS_DEBUG_CHROME=1`.

### Exporting desktop builds

```sh
scripts/fetch_templates.sh   # once per machine: installs the 4.7.2 export templates
make export                  # Windows .exe, macOS .dmg, Linux x86_64 -> exports/
```

Artifacts: `castle-storm.exe` (~110 MB, embedded PCK), `castle-storm.dmg` (~70 MB, Universal, ad-hoc signed), and `castle-storm.x86_64` (~76 MB, the Steam Deck build). macOS DMGs must be produced on a Mac.

## Playing

Start with one peasant and a stipend. Assign recruits as workers to produce food, timber, and iron; raise and upgrade four buildings; train militia into knights along the melee path or the archer branch; craft gear into two slots across three tiers. Growth draws the Watchful Eye — suspicion climbs as your camp grows, arms a telegraph, and lands crackdowns that seize resources and scatter followers unless you lay low or act. When the odds meter looks right, commit the storm: an auto-resolved assault with visible confidence bands and a card-played vignette. Win, and the castle is garrisoned by your own veterans — the next run's reveal says so, its odds table prints the exact army you left on the wall, and beating your old army opens the next cycle of a ladder that compounds ×1.10 per victory taken. Lose, and you bank the run's chronicle and deal the next hand the same way. Every ended hand also banks legacy points — the growing deck (The Legacy, on the title card or the table's header verbs) spends them between runs on permanent cards that join your next hand. Time away resolves when you return and prints on the table.

Every verb works three ways, at parity:

| Action | Keyboard | Gamepad (Deck) | Touch |
| --- | --- | --- | --- |
| Confirm / press focused card | Enter, Space, Left click | A | Tap |
| Back / fold | Esc | B | Tap the table |
| Secondary | E | X | — |
| Pause (dev, `CS_DEBUG_CHROME=1`) | P | L3 | — |
| Fast-forward (dev, `CS_DEBUG_CHROME=1`) | F | R1 | — |

D-pad and sticks drive focus navigation. Touch targets are at least 48dp, state is carried by line form (solid / dashed / struck) rather than color, and a type-scale setting (1.0–1.3x) lives in the in-game press-room.

## Project layout

| Path | Purpose |
| --- | --- |
| `ui/` | Screens and components: the Spread home table, assault, chronicle, leader intro, plus the print theme |
| `sim/` | Deterministic economy engine — headless-first, no UI imports |
| `content/` | Declarative content packs: units, buildings, gear, regimes, economy tunables |
| `saves/` | Versioned, atomic save architecture (run and meta domains) |
| `tests/` | `unit/`, `property/` (gdUnit4) and `acceptance/` (custom marathon runner) |
| `addons/gdUnit4/` | Vendored gdUnit4 v6.2.1 test framework |
| `scripts/` | `ci.sh`, export-template installer, art pipeline, balance and perf harnesses |
| `assets/vendor/` | Third-party art and fonts with generated attributions |
| `docs/` | Developer and design documentation |
| `tools/godot/` | Vendored engine binary (gitignored) |

## Testing

```sh
make test    # ~44s: 742 gdUnit4 unit/property cases + 1,455 acceptance checks
```

`make test` runs `scripts/ci.sh`: the gdUnit4 suites, then a SceneTree-based acceptance runner built for marathon suites with no framework timeout. What the suites pin:

- **Full runs in CI** — recruit through economy, a failed first storm, rebuild, victory, banking, restart, and bit-identical replay
- **Stability** — 1,000 simulated hours with no runaway or collapse; the balance band (first win 2–4 wall days, 12/12 seeds)
- **The escalation ladder** — chained campaigns on one shared meta: cycles 1–5 climbable (full tree 12/12 every cycle, walls rising 44 → 71), cycle 1 beatable barefoot; and the two-cycle journey through the real front door — capture, the veterans' reveal, the odds against your own army, the ×1.10 rung — in the journeys sweep
- **Saves** — chaos and corruption probes across rotating slots and both save domains (the captured-garrison snapshot rides the meta save)
- **Input parity** — 153-check matrix: every verb through touch, pad, and keyboard, including full pad-only and touch-only storms
- **Responsive and Deck posture** — every surface at four canonical sizes, pad navigation across every screen, idle battery discipline (zero processing, zero animation at rest), and memory boundedness

Extra harnesses: `make balance-sweep` (economy tuning tables), `make save-debug` (cross-process save/load probe), `make perf-probe` and `make deck-perf` (frame-cost and windowed Deck-profile measurements). See [docs/acceptance-sweep.md](docs/acceptance-sweep.md) for the criterion-by-criterion evidence.

## Third-party assets

Art and fonts are vendored and attributed in [assets/vendor/ATTRIBUTIONS.md](assets/vendor/ATTRIBUTIONS.md): Kenney packs (CC0), icons by Lorc and Delapouite at game-icons.net (CC BY 3.0, attribution required), and the IM Fell English SC and Alegreya Sans typefaces (SIL OFL 1.1). All in-game visuals are otherwise drawn as flat vector prints in code.

## Roadmap

The honest one, in order:

1. **L1 — persistent legacy unlock tree: SHIPPED.** Every ended run banks legacy points (win, loss, or abandon — the bank survives everything). Between runs, the Legacy deck — reachable from the title card once a hand has ended, or the header's The-Legacy verb mid-session — spends them on permanent cards across four families (The Old Guard's stipend ladder, The Workshop's cheaper walls and gear, The Yard's faster drills, The Survivors' cooler suspicion and veteran fighters). Buying is one step, the bank and the deck update live, and the card joins the NEXT hand: the loop is always on. The whole arc — bank, buy, next run's opening pays the effect exactly, chronicle consistent — runs in CI as the journeys sweep's sixth journey.
2. **L2 — enemy escalation: SHIPPED.** Every victory garrisons the castle with your own veterans. The next run's walls are held by your last winning army — same units, same gear tiers, the old leader's crest on the regime card — and each cycle taken compounds the garrison ×1.10 (docs/balance.md §7: cycles 1–5 climbable, the tree is the handrail when the exponent surfaces). The whole arc — capture, the veterans' reveal, the odds against the snapshot, a legacy buy between cycles, the second capture, and the rung the third run faces — runs in CI as the journeys sweep's seventh journey.
3. **Steam Deck hardware validation**: the checklist in [docs/deck-validation.md](docs/deck-validation.md) — 60Hz lock, battery target, live Steam Input loop, suspend/resume on real hardware
4. **Android** (mobile is in the design foundation; iOS is post-MVP)

## Known limitations

- Deck performance is validated on an M-series Mac at the Deck's exact window profile — the hardware run hasn't happened yet
- At 1x the first trainee hop lands ~2h20m in (the 2h militia drills set the army's pace; shortening them broke the first-win band when measured)
- Card titles step their font down to fit their plate; at the narrowest five-column roster the longest names still clip at the plate edge (fails safe, never past the card)
- Two art packs are pending vendoring (one CC0 pack, one paid heraldry pack awaiting purchase)
- No audio yet (event hooks exist as signals; no assets shipped)
- English only; no mobile builds yet

## License

The project's own code and content are MIT-licensed — see [LICENSE](LICENSE). Third-party assets under `assets/vendor/` (Kenney CC0 packs, game-icons.net CC-BY icons, OFL fonts) remain under their respective licenses; see [assets/vendor/ATTRIBUTIONS.md](assets/vendor/ATTRIBUTIONS.md) for the shipped per-file attribution.

## Further reading

[PRODUCT.md](PRODUCT.md) - the product brief · [DESIGN.md](DESIGN.md) - the visual world · [docs/DEV_SETUP.md](docs/DEV_SETUP.md) - engine pin and export detail · [docs/balance.md](docs/balance.md) - economy tuning · [docs/input-parity.md](docs/input-parity.md) - the parity matrix · [docs/save-format.md](docs/save-format.md) - save architecture
