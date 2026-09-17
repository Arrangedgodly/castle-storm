# Dev Setup — Castle Storm

## Engine pin (R1, committed)

- **Godot 4.7.2-stable** — standard (GDScript) build, **not** .NET.
- **Compatibility renderer** (`gl_compatibility`, desktop + mobile) — set in `project.godot` under `[rendering]`.
- Export targets (T-ARCH-02): Windows Desktop x86_64, macOS Universal (ad-hoc), Linux x86_64 (Steam Deck target) — see "Export pipeline" below.

## Vendored binary

`tools/godot/godot` is the command-line engine binary, vendored for reproducibility (gitignored, ~164 MB).

Re-vendor it with:

```sh
curl -L -o /tmp/godot.zip \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip
ditto -x -k /tmp/godot.zip /tmp/godot-extracted
mkdir -p tools/godot
cp /tmp/godot-extracted/Godot.app/Contents/MacOS/Godot tools/godot/godot
chmod +x tools/godot/godot
codesign --force --sign - tools/godot/godot   # re-sign ad-hoc for standalone CLI use (macOS)
tools/godot/godot --version                   # expect: 4.7.2.stable.official.ed1daf0bf
```

Notes:

- Downloaded from the official GitHub release asset
  `Godot_v4.7.2-stable_macos.universal.zip` (universal: x86_64 + arm64). This
  machine is arm64.
- macOS: the executable inside the notarized `.app` bundle fails its Designated
  Requirement when run standalone (killed with exit 137), so the vendored copy
  is re-signed ad-hoc. This is a local dev binary; it never ships.
- The ad-hoc re-sign means the binary itself is not notarized. It runs fine via
  CLI (no Gatekeeper prompt because `curl` does not set the quarantine xattr).

## Day-to-day commands

All wrapper targets go through `make` (see `Makefile`); every target honors a
`GODOT_BIN` override:

```sh
make version   # tools/godot/godot --version -> 4.7.2.stable.official.ed1daf0bf
make import    # --headless --path . --import   (run once after clone / adding assets)
make check     # import + --headless --path . --quit  (project loads clean, exit 0)
make run       # open the game
make test      # scripts/ci.sh: gdUnit4 unit+property, then acceptance (R2)
make export    # all three desktop presets -> exports/ (see "Export pipeline" below)
```

## Test harness (T-QA-01, per R2)

- **gdUnit4 v6.2.1 is vendored** at `addons/gdUnit4/` (committed, 272 files)
  from the exact upstream tag `v6.2.1` — repo `godot-gdunit-labs/gdUnit4`,
  commit `08ffc7c65b61b1b2edd545616061a99973c13ce1` — so CI is reproducible
  with no asset-library download. Re-vendor only deliberately (majors churn;
  v5→v6 happened inside a year).
- Lanes (per R2): `tests/unit/` and `tests/property/` run under gdUnit4;
  `tests/acceptance/` runs the custom SceneTree marathon runner
  (`tests/acceptance/run_headless.gd`), which has no framework timeout for
  1000h fast-forward (T-QA-02) and save round-trip (T-QA-03) suites.
- `scripts/ci.sh [all|unit|property|accept]` orchestrates everything through
  `GODOT_BIN` (defaults to the vendored binary) and fails non-zero:
  gdUnit4 exit codes 100 (failures), 101 (warnings/orphans — orphans in a
  deterministic sim are bugs), 105 (script parse errors) are all red; the
  acceptance runner exits 1 on any failed check.
- gdUnit4 headless quirks handled in `ci.sh`: `--ignoreHeadlessMode` is
  REQUIRED (v6.2.1 refuses `--headless` otherwise), and
  `-d --remote-debug tcp://127.0.0.1:0` (port 0 never binds, per gdUnit4's
  own `runtest.sh`) stops Godot dropping into an interactive `debug>` prompt
  on script parse errors. The two `ERROR: ... remote port ...` lines this
  prints are expected noise.
- Reports (JUnit XML + HTML) land in `reports/` (gitignored).
- Acceptance suites may set `CS_ACCEPTANCE_SEED=<int>` to seed the global
  RNG; suite contract is documented in the `run_headless.gd` header.


## Export pipeline (T-ARCH-02, per R1)

One-command headless CLI exports of the three desktop presets (R1: Windows
Desktop x86_64, macOS Universal ad-hoc, Linux x86_64 as the Steam Deck
target). Presets live in the committed `export_presets.cfg` (safe to commit
per R1 E7; secrets would go in `.godot/export_credentials.cfg`, never
committed — none used).

**Prerequisite, once per machine** — install the 4.7.2 export templates:

```sh
scripts/fetch_templates.sh   # downloads the official TPZ (R1 E1 URL) into an
                             # out-of-repo cache (~/.cache/castle-storm/templates),
                             # installs the 3 desktop release templates into
                             # ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
                             # Idempotent; ALL=1 unpacks everything, FORCE=1 reinstalls.
```

Then:

```sh
make export          # all three -> exports/ (gitignored)
make export-windows  # exports/windows/castle-storm.exe
make export-macos    # exports/macos/castle-storm.dmg
make export-linux    # exports/linux/castle-storm.x86_64
```

What each export is (verified 2026-09-16, sizes from the landed build):

| Preset | Artifact | Shape |
|---|---|---|
| `Windows Desktop` x86_64 | `castle-storm.exe` (~110 MB) | **embedded PCK** (GDPC trailer, single file), project icon in the PE resources (16→256 px, auto-converted from `icon.svg`) |
| `macOS` Universal | `castle-storm.dmg` (~70 MB) | `.app` with both x86_64 + arm64 slices, **ad-hoc signed** (`codesign/codesign=1` built-in, no Apple account), notarization disabled; the PCK ships *inside the bundle* at `Contents/Resources/Castle Storm.pck` — the macOS exporter does not embed into the universal binary, and the DMG is the single distributable artifact. Bundle id `com.castlestorm.game` (placeholder, revisit before distribution). |
| `Linux` x86_64 | `castle-storm.x86_64` (~76 MB) | **embedded PCK** (GDPC trailer; verified = template + 6,292,052 B PCK + 12 B trailer, exactly), the Steam Deck build (1280×800 16:10 design target) |

Notes:

- `project.godot` sets `rendering/textures/vram_compression/import_etc2_astc=true`
  — required or the macOS Universal export refuses (Apple GPUs have no S3TC);
  textures re-import on the next `make import` after flipping it.
- Icons: both Windows and macOS presets leave `application/icon` empty — the
  exporter auto-converts the project icon (`res://icon.svg`). Verified in the
  landed artifacts by pixel-comparing the embedded 128 px icon against an
  engine rasterization of `icon.svg` (99.2% identical; the rest is the
  generator's resampling).
- The embedded-PCK check: last 12 bytes of the binary are the 8-byte PCK size
  + `GDPC` magic, and the PCK header magic sits exactly at
  `len(file) − 12 − pck_size`.
- macOS exports must be produced on a Mac (R1 E9: DMG + correct +x). Running
  the exported app locally for smoke: `hdiutil attach` the DMG, then
  `HOME=<scratch> "<app>/Contents/MacOS/Castle Storm" --headless --quit`.

## Steam Deck controller mapping (T-ARCH-02, per R1 E13/E14)

Godot 4.5+ reads controllers through SDL3 (R1 E13): the Deck's physical pad
surfaces as a standard Xbox-style gamepad, so InputMap actions bound to SDL
joypad indices work on the Deck unchanged; Steam Input handles everything
else (R1 E15). The one documented R1 gotcha (E14): joypad events must be
bound to **Any Device (`device = -1`)** or Linux builds can lose controller
input on the Deck. All five actions comply (pinned by
`tests/unit/test_input_map.gd`).

| Steam Deck button | SDL / Godot `button_index` | Action | Also on |
|---|---|---|---|
| **A** (bottom face) | 0 | `primary` — confirm / press focused card | Enter, Space, left click |
| **B** (right face) | 1 | `back` — back / fold / cancel | Esc |
| **X** (left face) | 2 | `secondary` | E |
| **R1** (right shoulder) | 5 | `debug_fast_forward` — time-scale ladder (dev; acts only under `CS_DEBUG_CHROME=1`) | F |
| **L3** (left stick click) | 6 | `pause` — freeze the world (dev; acts only under `CS_DEBUG_CHROME=1`) | P |

Deliberately unbound: Menu (9) — the conventional future "settings/pause"
home; D-pad/sticks drive focus navigation via the engine's `ui_*` actions on
the focused Control chain (gameplay code never reads `ui_*` directly, R3).
Changing any binding is a product decision: update this table and
`tests/unit/test_input_map.gd` together.

## Repository layout

| Path | Purpose |
|---|---|
| `project.godot` | Engine pin, renderer, R3 root content-scale settings, InputMap action stubs |
| `ui/` | Screens and components (main scene: `ui/main.tscn` — the boot shell that Play/F5 and `make run-game` run) |
| `sim/` | Deterministic economy engine — headless-first, no UI imports |
| `content/` | Declarative content packs: schema classes in `content/schema/`, load-time validator `content/content_validator.gd`, worked examples `content/examples/` (schema: T-DATA-01, see `docs/content-schema.md`) |
| `saves/` | Save architecture: versioned, atomic writes (T-ARCH-03) |
| `tests/` | `unit/`, `property/` (gdUnit4), `acceptance/` (SceneTree runner) per R2 |
| `addons/gdUnit4/` | Vendored gdUnit4 v6.2.1 test framework (committed) |
| `scripts/` | `ci.sh` — local CI entry point; `fetch_templates.sh` — export-template installer; `vendor_assets.sh` — art pipeline |
| `reports/` | gdUnit4 JUnit XML + HTML reports (gitignored) |
| `tools/godot/` | Vendored engine binary (gitignored) |
| `docs/` | `DEV_SETUP.md`, `gdscript-conventions.md`, `content-schema.md` |

Input actions (bound to **Any Device** so Linux/Deck exports keep controller
input, per R1/E14): `primary`, `secondary`, `back`, `pause`, `debug_fast_forward`.
Gameplay code must not use `ui_*` actions (R3 focus-navigation rule). The
Deck button table lives in "Steam Deck controller mapping" above.
