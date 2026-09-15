# Dev Setup — Castle Storm

## Engine pin (R1, committed)

- **Godot 4.7.2-stable** — standard (GDScript) build, **not** .NET.
- **Compatibility renderer** (`gl_compatibility`, desktop + mobile) — set in `project.godot` under `[rendering]`.
- Export targets (T-ARCH-02): Windows Desktop x86_64, macOS Universal (ad-hoc), Linux/X11 x86_64 (Steam Deck target).

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
make export    # placeholder until T-ARCH-02 adds export presets
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


## Export templates (needed from T-ARCH-02 onward)

Headless CLI export requires the **4.7.2.stable** export templates installed
for this binary. Either run the editor once (`tools/godot/godot -e`) and use
*Editor > Manage Export Templates > Download*, or fetch the TPZ directly:

- `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
- Unzip into `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` (macOS).

## Repository layout

| Path | Purpose |
|---|---|
| `project.godot` | Engine pin, renderer, R3 root content-scale settings, InputMap action stubs |
| `ui/` | Screens and components (main scene: `ui/main.tscn`) |
| `sim/` | Deterministic economy engine — headless-first, no UI imports |
| `content/` | Declarative content packs (schema: T-DATA-01) |
| `saves/` | Save architecture: versioned, atomic writes (T-ARCH-03) |
| `tests/` | `unit/`, `property/` (gdUnit4), `acceptance/` (SceneTree runner) per R2 |
| `addons/gdUnit4/` | Vendored gdUnit4 v6.2.1 test framework (committed) |
| `scripts/` | `ci.sh` — local CI entry point (stages: unit/property/accept) |
| `reports/` | gdUnit4 JUnit XML + HTML reports (gitignored) |
| `tools/godot/` | Vendored engine binary (gitignored) |
| `docs/` | `DEV_SETUP.md`, `gdscript-conventions.md` |

Input actions (bound to **Any Device** so Linux/Deck exports keep controller
input, per R1/E14): `primary`, `secondary`, `back`, `pause`, `debug_fast_forward`.
Gameplay code must not use `ui_*` actions (R3 focus-navigation rule).
