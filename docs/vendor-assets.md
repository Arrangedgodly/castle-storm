# Vendor asset pipeline (T-ARCH-04, per R6)

How third-party art gets into `assets/vendor/`, how licenses are tracked, and
how SVGs become @2x PNGs. The game-facing half is the art manifest
(`content/mvp/art_manifest.tres`, asset keys only — content never hardcodes
paths); this doc is the pipeline half.

## One command

```
make vendor-assets          # stage + verify + @2x render + ATTRIBUTIONS.md (offline, idempotent)
make vendor-assets FETCH=1  # download declared packs into the cache first (curl + jq)
```

- **manifest**: `assets/vendor/manifest.json` — every pack with its source
  URL, license, artist, the exact files we keep, and the sha256 each staged
  file must hash to. Downloads live in `~/.cache/castle-storm/vendor`
  (`CS_VENDOR_CACHE`), never in the repo; only the staged subset is
  committed (≈2.5 MB today).
- **scripts**: `scripts/vendor_assets.sh` (fetch + orchestrate; the only
  networked step, deliberately OUTSIDE game code per
  docs/security-policy.md §2) and `scripts/vendor_assets.gd` (stage via
  ZIPReader/copy, sha256-verify via HashingContext, render, generate
  ATTRIBUTIONS.md — runs on the pinned engine binary).

## Invariants

1. **Vendored bytes are immutable.** A staged file that hashes differently
   than the manifest is a hard pipeline failure (edit manifests, never
   staged files). Re-running is byte-identical (deterministic renderer +
   sorted, timestamp-free ATTRIBUTIONS.md).
2. **Every SVG ships with a render.** `<name>.svg` gets a sibling
   `<name>@2x.png`. Never rely on runtime SVG scaling (R6: ThorVG rasterizes
   at fixed import scale; `DPITexture` is experimental).
3. **Attribution is data.** `assets/vendor/ATTRIBUTIONS.md` is generated from
   the manifest: CC-BY entries (artist + license + link, per file — the exact
   strings the art manifest carries) MUST survive into shipped credits;
   CC0 packs are listed for provenance; pending packs are visible, not
   silently absent. Per-pack `LICENSE.txt` files are vendored beside the art
   they license.
4. **The content validator closes the loop.** Every non-pending art-manifest
   entry's `source_path` must exist at validation time (R6 license hygiene +
   no phantom content). `pending = true` is the explicit hatch for packs not
   yet vendored so T-UI-01 can land art incrementally without red CI;
   every entry flips to a real staged file before ship.

## Renderer decision of record

R6 planned Inkscape CLI for the @2x pre-render. **This machine (and the CI
shape it implies) has no Inkscape, no rsvg-convert, no ImageMagick, and its
ffmpeg is built without an SVG decoder** (all probed 2026-09-15; ffmpeg
fails with "no decoder found for: svg"). The options were:

| Option | Verdict |
|---|---|
| Install Inkscape | New heavyweight dependency outside the repo's pinned toolchain; renderer varies by install |
| ffmpeg | No SVG decoder on this machine (probed) |
| Godot editor import at `svg/scale=2` | Zero new deps, but bakes the render into `.godot` cache — no committed PNG artifact, "pre-render" becomes "import" |
| **`Image.load_svg_from_buffer(bytes, scale)` on the vendored 4.7.2-stable binary** | **Chosen** — zero new dependencies, exact-version reproducible, writes real PNGs |

So "pre-render to @2x PNG" is done by the pinned engine itself (ThorVG).
Limitations, honestly:

- **ThorVG is not Inkscape.** Godot's SVG feature support is limited (R6
  records this); complex vectors — gradients, filters, `<text>` — may render
  imperfectly. The pipeline fails loudly on decode errors and zero-sized
  renders, and renders are visually spot-checked; the Kenney + game-icons
  sets staged so far (flat paths, no text) render clean. If the Armorial
  heraldry SVGs misrender, install Inkscape and add an inkscape renderer
  path to `scripts/vendor_assets.gd` before re-rendering.
- **"@2x" means 2x display-ready, not always 2x-of-natural.** Global
  `render.scale` is 2.0; a pack may override `render_scale` (the Kenney
  character SVGs are naturally 864x640 — already >2x any card-figure display
  size in the 720x720 design base — so their natural size IS the 2x render;
  2x-of-natural would commit ~6 MB of pixels no target screen can use).
  The exact scale applied is recorded per pack in the manifest and
  re-derived by the tests, so a render can never silently drift from its
  declared scale.

## Fonts (T-UI-01, 2026-09-15)

The theme's typography rides the same pipeline: two OFL-1.1 families are
vendored under `assets/vendor/fonts/` as plain per-file URL packs
(game-icons pattern — no zip, sha256 per file, OFL.txt vendored beside
each family):

- **IM Fell English SC** (Igino Marini) — the display face: a digitization
  of the c.1667 Fell types that keeps their rough, unevenly-inked
  impressions; the "deliberate misprint" character lives in the
  letterforms themselves. Small-caps titling for card name plates.
- **Alegreya Sans** (Juan Pablo del Peral) — the workhorse: humanist sans
  with a calligraphic skeleton from the Alegreya literature superfamily;
  readable at phone-scale sizes, true weight range + italic for chronicle
  lines. Weights kept: Regular, Medium, Bold, Italic.

Fonts skip the @2x render step (not SVG) but stage and checksum exactly
like art. ATTRIBUTIONS.md gains an OFL section with family + artist +
specimen link per family (the `family` manifest field is the
human-spelled name tests and credits key on). Pairing rationale lives in
`ui/theme/inks.gd`'s header and the T-UI-01 production-log entry.

## Pending packs (as of 2026-09-15)

- **tzunghaor Cartoon Vector Characters** (CC0, OpenGameArt) — opengameart.org
  was unreachable from the build machine and the pack ships as .7z (no
  extractor present). The three `face_*` keys referencing it are `pending`.
- **Armorial – Procedural Heraldry** (commercial, $12, itch.io) — requires a
  human purchase. The four `crest_*` keys referencing it are `pending`.
  After purchase: stage crests under `assets/vendor/armorial/`, add the
  pack's LICENSE.txt + manifest entries with checksums, flip `pending`.

Landing either pack: add files to its manifest entry (sha256s via
`shasum -a 256`), run `make vendor-assets FETCH=1`, flip the art-manifest
entries' `pending`, run `make test`.
