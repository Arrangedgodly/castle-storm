# Castle Storm — developer wrapper.
#
# Uses the vendored engine binary tools/godot/godot (Godot 4.7.2-stable,
# standard/GDScript build, pinned per R1). Override with GODOT_BIN to use
# another 4.7.2 binary (CI does this later, per R2):
#
#     GODOT_BIN=/path/to/godot make check
#
# Test harness (T-QA-01, per R2): gdUnit4 v6.2.1 (vendored in addons/gdUnit4)
# runs unit + property suites; a custom SceneTree runner handles marathon
# acceptance suites. scripts/ci.sh orchestrates both and fails non-zero.
#
# Save debug (T-ARCH-03): a manual save/load probe — plays a full-stack
# session, saves both domains every 10h (ring rotates), and CONTINUES from
# disk when run again (cross-process persistence by hand; corruption probes
# in docs/save-format.md §9):
#     make save-debug
#     CS_SAVE_HOURS=500 make save-debug
#     CS_SAVE_ROOT=res://saves make save-debug
#
# Balance sweep (T-SIM-08): the tuning harness — sweeps EconomyTunables
# candidates against the canonical host and prints the measurement tables
# recorded in docs/balance.md (CS_SWEEP_SEEDS=n adjusts the seed count):
#     make balance-sweep
#
# Vendor asset pipeline (T-ARCH-04, per R6): stage declared art packs into
# assets/vendor/ (sha256-verified), pre-render every staged SVG to a sibling
# @2x PNG, and regenerate assets/vendor/ATTRIBUTIONS.md. Idempotent; offline
# (staged files are committed). To (re-)download packs first:
#     make vendor-assets FETCH=1
# Cache lives outside the repo (CS_VENDOR_CACHE, default ~/.cache/castle-storm/vendor).
vendor-assets:
	scripts/vendor_assets.sh $(if $(FETCH),--fetch,)

# Theme gallery (T-UI-01): windowed visual inspection of the component
# grammar — every component in every state at the 720x720 design base:
#     make run-gallery
run-gallery:
	$(GODOT_BIN) --path . res://ui/theme/theme_gallery.tscn

# Responsive lab (T-UI-02): windowed demo of the portrait/landscape
# topology swap — same component scenes in both slots, LayoutRouter
# hysteresis + focus restoration, debug panel to force orientation and
# cycle the common test sizes (720x1280 / 1280x800 / 1920x1080 /
# 800x1280). Screenshot hook: CS_RESPONSIVE_SHOT=/path.png writes
# one capture per test size (<path>.<WxH>.png) and quits:
#     make run-responsive
run-responsive:
	$(GODOT_BIN) --path . res://ui/layout/responsive_lab.tscn

# The Spread — THE GAME (T-UI-03): the home screen wired to a real
# engine host (canonical composition, seeded demo run, live pips/cards/
# chronicle/Watchful Eye). Debug accel: F (or pad R5, the
# debug_fast_forward action) cycles the time scale 1x -> 60x -> 600x; P
# freezes the world. Card interactions (T-UI-04): press a focused card
# (enter / pad A) or tap one to fan its contextual actions; esc / pad B
# folds the fan; the PROMOTE action's landing turns the trainee card
# over (the signature moment). CS_DEMO_RESET=0 continues the previous
# session (default: each run starts the same seeded fresh demo);
# CS_SEED=<int> overrides the seed. The demo debug chip (time scale /
# sim hours / paused) is OPT-IN dev chrome, off in normal runs and every
# capture so the table stays diegetic:
#   CS_DEBUG_CHROME=1 make run-game                        # show the debug chip
# Screenshot hooks (windowed):
#   CS_SPREAD_SHOT=/path.png make run-game                # quiet state
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_LOUD=1 make run-game  # pressured (telegraph)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_PROMOTE=1 make run-game  # promote, mid-flip
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_PROMOTE=2 make run-game  # promote, landed (flourish)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_FAN=1 make run-game      # an open action fan
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_ASSAULT=1 make run-game  # assault odds table (T-UI-07)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_ASSAULT=2 make run-game  # a beat mid-vignette (the storm)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_INTRO=1 make run-game    # the first-hand reveal (T-UI-05)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_INTRO=2 make run-game    # reveal + mid-unfold (.mid.png)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_RESTART=win make run-game   # full win-restart session captures
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_RESTART=loss make run-game  # the crush -> loss-restart captures
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_SUSPICION=1 make run-game  # the telegraph CHOICE CARD (T-UI-06)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_SUSPICION=2 make run-game  # the landed-crackdown BLOCKQUOTE
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_SUSPICION=3 make run-game  # the CRUSHED beat over the swept table
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_CHRONICLE=1 make run-game  # the ledger over three real hands (T-UI-08)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_CHRONICLE=2 make run-game  # 50-hand ring: newest + mid-ring tall page (.turn.png) + oldest (.old.png)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_CATCHUP=1 make run-game    # mid-session away window -> the print on the LIVE table (T-UI-09)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_CATCHUP=2 make run-game    # SEED: play 6h, background (anchor+save), quit (prints the =3 command)
#   CS_SPREAD_SHOT=/p.png CS_DEMO_RESET=0 CS_DEMO_NOW=<epoch> CS_SPREAD_CATCHUP=3 make run-game
#                                                               # RESUME: boots through the real save — the check-in
#                                                               # unfold + the while-you-were-away print + the
#                                                               # foreground->actionable wall measurement
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_CATCHUP=4 make run-game    # crackdown landing INSIDE the away window — the print's STRIKE
#                                                               # row + the signed seizure losses, from a real resolved window
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_FIRST=1 make run-game      # the first session, moment 1: the EMPTY SPREAD (staked plots)
#                                                               # + the first gate hint at the 7-minute arrival (T-UI-10)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_FIRST=2 make run-game      # moment 2: the assignment + build-order hints, focus on the plot
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_FIRST=3 make run-game      # moment 3: the arc to the TRICKLE print + the honest pacing
#                                                               # report (each beat's sim tick = wall minute at 1x)
run-game:
	$(GODOT_BIN) --path . res://ui/screens/spread/spread_screen.tscn

# Boundary validation (T-ARCH-01 acceptance):
#     make version   # expect 4.7.2.stable.official.ed1daf0bf
#     make import    # godot --headless --path . --import
#     make check     # godot --headless --path . --quit  (project loads clean)
#     make test      # scripts/ci.sh (unit + property + acceptance)

GODOT_BIN ?= tools/godot/godot

.DEFAULT_GOAL := help
.PHONY: help version import check run test save-debug perf-probe deck-perf balance-sweep vendor-assets run-gallery run-responsive run-game export export-windows export-macos export-linux

help:
	@echo "Targets: version | import | check | run | run-game | run-gallery | run-responsive | test | save-debug | perf-probe | deck-perf | balance-sweep | vendor-assets | export | export-windows | export-macos | export-linux  (GODOT_BIN defaults to tools/godot/godot; exports need scripts/fetch_templates.sh once)"

version:
	@$(GODOT_BIN) --version

import:
	$(GODOT_BIN) --headless --path . --import

check: import
	$(GODOT_BIN) --headless --path . --quit

run:
	$(GODOT_BIN) --path .

test:
	GODOT_BIN="$(GODOT_BIN)" scripts/ci.sh

save-debug:
	$(GODOT_BIN) --headless --path . -s res://scripts/save_debug.gd

# Frame-cost micro-benchmark (T-PERF-01): the idle-loop evidence —
# bare-frame baseline vs the real spread screen idle vs backgrounded
# (pacing gate shut), the advance() pacing math, the 8h capped
# foreground resolve on the live table, and the kept-running desktop
# worst case (a 3-day delta in one advance). Numbers recorded in
# docs/ultron/production-log.md (T-PERF-01 entry).
perf-probe:
	$(GODOT_BIN) --headless --path . -s res://scripts/perf_probe.gd

# Deck-profile performance measurement (T-PERF-02): WINDOWED (the real
# Compatibility renderer) at the forced Deck window 1280x800 — frame
# budget per representative state (idle / busy / assault vignette /
# chronicle 50 scrolled) with vsync off for honest headroom, the idle
# pixel-identity proof (zero animation on the quiet table), a vsync-
# locked cadence sample, and per-state memory/draw-call reports.
# NOT part of make test (it opens a real window and measures hardware).
# The hardware-gated Deck remainder: docs/deck-validation.md.
deck-perf:
	$(GODOT_BIN) --path . -s res://scripts/deck_perf_suite.gd

balance-sweep:
	$(GODOT_BIN) --headless --path . -s res://scripts/balance_sweep.gd

# Export pipeline (T-ARCH-02, per R1): one-command headless CLI exports of the
# three desktop presets in export_presets.cfg (committed per R1 E7):
#     make export          # all three -> exports/ (gitignored)
#     make export-windows  # exports/windows/castle-storm.exe   (x86_64, embedded PCK)
#     make export-macos    # exports/macos/castle-storm.dmg     (Universal, ad-hoc signed)
#     make export-linux    # exports/linux/castle-storm.x86_64 (Steam Deck target, embedded PCK)
# Prerequisite (once per machine): the 4.7.2 export templates —
#     scripts/fetch_templates.sh
# downloads the official TPZ (R1 E1 URL) into an out-of-repo cache and installs
# the three desktop release templates where the engine expects them (see
# docs/DEV_SETUP.md). macOS exports run ON a Mac (R1 E9: DMG + ad-hoc signing).
export: export-windows export-macos export-linux
	@ls -lh exports/windows/castle-storm.exe exports/macos/castle-storm.dmg exports/linux/castle-storm.x86_64

export-windows:
	mkdir -p exports/windows
	$(GODOT_BIN) --headless --path . --export-release "Windows Desktop" exports/windows/castle-storm.exe

export-macos:
	mkdir -p exports/macos
	$(GODOT_BIN) --headless --path . --export-release "macOS" exports/macos/castle-storm.dmg

export-linux:
	mkdir -p exports/linux
	$(GODOT_BIN) --headless --path . --export-release "Linux" exports/linux/castle-storm.x86_64
