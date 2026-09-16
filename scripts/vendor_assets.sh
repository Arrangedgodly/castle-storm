#!/usr/bin/env bash
# Vendor asset pipeline (T-ARCH-04, per R6) — fetch + orchestrate wrapper.
#
#   scripts/vendor_assets.sh            # stage + verify + @2x render + attributions
#   scripts/vendor_assets.sh --fetch    # download declared packs into the cache first,
#                                       # then stage (curl + jq needed for this mode only)
#
# Staging/verification/rendering itself lives in scripts/vendor_assets.gd and
# runs on the pinned engine binary (see manifest.json "render" note for the
# renderer decision: Godot/ThorVG, no Inkscape on target machines). This
# wrapper only downloads — game code stays network-free per
# docs/security-policy.md §2.
#
# Cache: CS_VENDOR_CACHE (default ~/.cache/castle-storm/vendor). Downloads are
# NEVER committed; only the staged subset under assets/vendor/ enters git
# (small: the manifest declares exactly the files the art manifest references).
#
# Idempotent: staged files with matching sha256 are skipped; re-rendering the
# same SVG on the same engine version produces identical bytes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
	if [[ -x "tools/godot/godot" ]]; then
		GODOT_BIN="tools/godot/godot"
	else
		echo "vendor_assets.sh: no engine binary. Set GODOT_BIN=/path/to/godot or vendor tools/godot/godot" >&2
		exit 2
	fi
fi

MANIFEST="assets/vendor/manifest.json"
CACHE="${CS_VENDOR_CACHE:-$HOME/.cache/castle-storm/vendor}"

fetch() {
	command -v curl >/dev/null || { echo "vendor_assets.sh: --fetch needs curl" >&2; exit 2; }
	command -v jq >/dev/null || { echo "vendor_assets.sh: --fetch needs jq" >&2; exit 2; }

	# Pack-level archives (zips): one download per pack.
	while IFS=$'\t' read -r pack_id url; do
		[[ -n "$pack_id" ]] || continue
		dest="$CACHE/$pack_id/${url##*/}"
		mkdir -p "$(dirname "$dest")"
		if [[ -s "$dest" ]]; then
			echo "[fetch] cached $dest"
		else
			echo "[fetch] $url -> $dest"
			curl -sfL --retry 2 -o "$dest" "$url"
		fi
	done < <(jq -r '.packs[] | select(.download.url) | [.id, .download.url] | @tsv' "$MANIFEST")

	# Per-file URLs: cache path mirrors the staging dest under the pack dir.
	while IFS=$'\t' read -r pack_id dest url; do
		[[ -n "$pack_id" ]] || continue
		cache_dest="$CACHE/$pack_id/$dest"
		mkdir -p "$(dirname "$cache_dest")"
		if [[ -s "$cache_dest" ]]; then
			echo "[fetch] cached $cache_dest"
		else
			echo "[fetch] $url -> $cache_dest"
			curl -sfL --retry 2 -o "$cache_dest" "$url"
		fi
	done < <(jq -r '.packs[] | select(.status != "pending") | .id as $p | .files[] | select(.url) | [$p, .dest, .url] | @tsv' "$MANIFEST")

	# Checksums are verified by the Godot stage below (single verification
	# authority) — a bad download fails there with the exact hash mismatch.
}

[[ "${1:-}" == "--fetch" ]] && fetch

exec "$GODOT_BIN" --headless --path . -s res://scripts/vendor_assets.gd
