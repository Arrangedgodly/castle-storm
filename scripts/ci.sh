#!/usr/bin/env bash
# Castle Storm local CI — per R2 (docs/ultron/research/r2-test-framework.md).
#
# Stages:
#   unit      gdUnit4 unit tests         (res://tests/unit)
#   property  gdUnit4 property/fuzz      (res://tests/property)
#   accept    SceneTree marathon runner  (res://tests/acceptance)
#   all       unit + property in one gdUnit4 process, then accept (default)
#
# Exit codes (CI-readable): 0 green; non-zero red. gdUnit4 exits 100 on test
# failures and 101 on warnings/orphans — BOTH are treated as failures here
# (orphan nodes in a deterministic sim are bugs, per R2). The acceptance
# runner exits 1 on any failed check.
#
# GODOT_BIN selects the engine binary (Godot 4.7.2-stable per R1). It falls
# back to the vendored tools/godot/godot when present, so `make test` works
# out of the box; export GODOT_BIN on CI machines.

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
	if [[ -x "tools/godot/godot" ]]; then
		GODOT_BIN="tools/godot/godot"
	else
		echo "ci.sh: no engine binary. Set GODOT_BIN=/path/to/godot or vendor tools/godot/godot" >&2
		exit 2
	fi
fi

start=$SECONDS

# T-QA-01 harness budget (L1-C re-dispatch, 2026-09-17): both stages run under
# `--fixed-fps 144`. Probed on the vendored 4.7.2 headless: every
# `await process_frame` floors at ~6.90ms of wall regardless of load,
# Engine.max_fps or Engine.time_scale — that floor is the engine's REAL-TIME
# frame synchronization, not compute (the FAIL round's 63s `make test` was
# ~39% CPU; the acceptance stage alone idled ~16s across its frame-stepped
# polls). `--fixed-fps` "disables real-time synchronization" (engine docs):
# frames advance at compute speed while the per-frame delta is PINNED at
# 1/144s = 6.94ms — within 1% of the floor the suites' green baseline already
# runs at, so every per-frame premise keeps its exact dynamics (paced paper,
# LayoutRouter dwell aging, the suspicion suite's mid-beat windows, the
# flapping pins at the true clock; deltas become CONSTANT, removing the
# slow-host variance real deltas carried). Chosen over per-suite micro-trims
# because it reclaims the idle under EVERY frame-stepped poll in both stages
# with zero test-file edits — coverage provably byte-identical.
FIXED_FPS_ARGS=(--fixed-fps 144)

# Runs gdUnit4 suites headless. Arguments: one or more res:// suite dirs.
run_gdunit() {
	local dirs=("$@")
	local args=()
	local dir
	for dir in "${dirs[@]}"; do
		args+=( -a "$dir" )
	done
	echo "==> gdUnit4 (unit/property): ${dirs[*]}"
	local rc=0
	# --remote-debug tcp://127.0.0.1:0 (port never bound) stops Godot dropping
	# into its interactive 'debug>' CLI on script parse errors — pattern from
	# gdUnit4's own runtest.sh. --ignoreHeadlessMode switches off gdUnit4's
	# headless refusal (our suites are pure logic, no InputEvents needed).
	# -c continues past the first failure so CI reports everything.
	"$GODOT_BIN" --headless --path . "${FIXED_FPS_ARGS[@]}" \
		-s -d --remote-debug tcp://127.0.0.1:0 \
		res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -c -rd res://reports "${args[@]}" || rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "==> gdUnit4 stage FAILED (exit $rc: 100=failures, 101=warnings/orphans, 105=script parse errors; all are red here)" >&2
		exit "$rc"
	fi
	echo "==> gdUnit4 stage green"
}

run_acceptance() {
	echo "==> acceptance (SceneTree marathon runner)"
	local rc=0
	"$GODOT_BIN" --headless --path . "${FIXED_FPS_ARGS[@]}" -s res://tests/acceptance/run_headless.gd || rc=$?
	if [[ $rc -ne 0 ]]; then
		echo "==> acceptance stage FAILED (exit $rc)" >&2
		exit "$rc"
	fi
	echo "==> acceptance stage green"
}

stage="${1:-all}"
case "$stage" in
	unit)
		run_gdunit res://tests/unit
		;;
	property)
		run_gdunit res://tests/property
		;;
	accept)
		run_acceptance
		;;
	all)
		run_gdunit res://tests/unit res://tests/property
		run_acceptance
		;;
	*)
		echo "usage: scripts/ci.sh [all|unit|property|accept]" >&2
		exit 2
		;;
esac

echo "==> ci.sh: all requested stages green in $((SECONDS - start))s"
