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

# Boundary validation (T-ARCH-01 acceptance):
#     make version   # expect 4.7.2.stable.official.ed1daf0bf
#     make import    # godot --headless --path . --import
#     make check     # godot --headless --path . --quit  (project loads clean)
#     make test      # scripts/ci.sh (unit + property + acceptance)

GODOT_BIN ?= tools/godot/godot

.DEFAULT_GOAL := help
.PHONY: help version import check run test save-debug balance-sweep vendor-assets export

help:
	@echo "Targets: version | import | check | run | test | save-debug | balance-sweep | vendor-assets | export  (GODOT_BIN defaults to tools/godot/godot)"

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
