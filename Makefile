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
# Boundary validation (T-ARCH-01 acceptance):
#     make version   # expect 4.7.2.stable.official.ed1daf0bf
#     make import    # godot --headless --path . --import
#     make check     # godot --headless --path . --quit  (project loads clean)
#     make test      # scripts/ci.sh (unit + property + acceptance)

GODOT_BIN ?= tools/godot/godot

.DEFAULT_GOAL := help
.PHONY: help version import check run test export

help:
	@echo "Targets: version | import | check | run | test | export  (GODOT_BIN defaults to tools/godot/godot)"

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

export:
	@echo "export: presets land in T-ARCH-02 (Windows x86_64 / macOS Universal / Linux-X11 x86_64)"
	@echo "usage: $(GODOT_BIN) --headless --path . --export-release \"<preset>\" exports/<output>"
