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
# CS_SEED=<int> overrides the seed. Screenshot hooks (windowed):
#   CS_SPREAD_SHOT=/path.png make run-game                # quiet state
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_LOUD=1 make run-game  # pressured (telegraph)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_PROMOTE=1 make run-game  # promote, mid-flip
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_PROMOTE=2 make run-game  # promote, landed (flourish)
#   CS_SPREAD_SHOT=/p.png CS_SPREAD_FAN=1 make run-game      # an open action fan
run-game:
	$(GODOT_BIN) --path . res://ui/screens/spread/spread_screen.tscn

# Boundary validation (T-ARCH-01 acceptance):
#     make version   # expect 4.7.2.stable.official.ed1daf0bf
#     make import    # godot --headless --path . --import
#     make check     # godot --headless --path . --quit  (project loads clean)
#     make test      # scripts/ci.sh (unit + property + acceptance)

GODOT_BIN ?= tools/godot/godot

.DEFAULT_GOAL := help
.PHONY: help version import check run test save-debug balance-sweep vendor-assets run-gallery run-responsive run-game export

help:
	@echo "Targets: version | import | check | run | run-game | run-gallery | run-responsive | test | save-debug | balance-sweep | vendor-assets | export  (GODOT_BIN defaults to tools/godot/godot)"

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

balance-sweep:
	$(GODOT_BIN) --headless --path . -s res://scripts/balance_sweep.gd

export:
	@echo "export: presets land in T-ARCH-02 (Windows x86_64 / macOS Universal / Linux-X11 x86_64)"
	@echo "usage: $(GODOT_BIN) --headless --path . --export-release \"<preset>\" exports/<output>"
