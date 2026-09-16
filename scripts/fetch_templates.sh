#!/usr/bin/env bash
# fetch_templates.sh — install the pinned Godot 4.7.2-stable export templates
# for headless CLI export (T-ARCH-02, per R1 / docs/DEV_SETUP.md).
#
# The vendored engine binary (tools/godot/godot) is the editor build; exporting
# also needs the MATCHING export templates installed where the engine looks
# for them:
#
#   macOS:   ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
#   Linux:   ~/.local/share/godot/export_templates/4.7.2.stable/
#   Windows: %APPDATA%/Godot/export_templates/4.7.2.stable/
#
# By default this installs ONLY the three desktop release templates the export
# presets use (~230 MB unpacked instead of ~1.2 GB for every platform):
#   windows_release_x86_64.exe, macos.zip, linux_release.x86_64
# Set ALL=1 to unpack the whole TPZ (adds debug templates, Android, Web, ...).
#
# Idempotent: the TPZ is downloaded ONCE into an out-of-repo cache
# (CS_TEMPLATES_CACHE, default ~/.cache/castle-storm/templates — same cache
# root as the vendor asset pipeline) and skipped when already present at the
# expected size; an existing template install is left alone unless FORCE=1.
#
# Usage:
#   scripts/fetch_templates.sh            # download if needed + install 3 desktop templates
#   ALL=1 scripts/fetch_templates.sh      # install every template in the TPZ
#   FORCE=1 scripts/fetch_templates.sh    # re-install even if already present
#
# The download URL is the official release asset recorded in R1 evidence E1
# and docs/DEV_SETUP.md (godotengine/godot tag 4.7.2-stable).

set -euo pipefail

GODOT_VERSION="4.7.2.stable"
TPZ_URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
TPZ_NAME="Godot_v4.7.2-stable_export_templates.tpz"

# Desktop release templates the export_presets.cfg presets build with.
DESKTOP_TEMPLATES=(
  "windows_release_x86_64.exe"
  "macos.zip"
  "linux_release.x86_64"
)

cache="${CS_TEMPLATES_CACHE:-$HOME/.cache/castle-storm/templates}"
mkdir -p "$cache"
tpz="$cache/$TPZ_NAME"

case "$(uname -s)" in
  Darwin) godot_config="$HOME/Library/Application Support/Godot" ;;
  Linux)  godot_config="$HOME/.local/share/godot" ;;
  *)      godot_config="${APPDATA:-$HOME/AppData/Roaming}/Godot" ;;
esac
install_dir="$godot_config/export_templates/$GODOT_VERSION"

installed() {
  [[ -f "$install_dir/version.txt" ]] || return 1
  local f
  for f in "${DESKTOP_TEMPLATES[@]}"; do
    [[ -s "$install_dir/$f" ]] || return 1
  done
  return 0
}

if installed && [[ "${FORCE:-0}" != "1" ]]; then
  echo "fetch_templates: $GODOT_VERSION desktop templates already installed:"
  ls -lh "$install_dir" | tail -n +2 | awk '{print "  ", $NF, "("$5")"}'
  echo "fetch_templates: nothing to do (FORCE=1 to reinstall)"
  exit 0
fi

# --- download (once) ------------------------------------------------------
if [[ -s "$tpz" ]]; then
  echo "fetch_templates: using cached $tpz"
else
  echo "fetch_templates: downloading $TPZ_URL"
  echo "fetch_templates: (~1.3 GB; cached at $cache, never inside the repo)"
  curl -fL --retry 3 -o "$tpz.part" "$TPZ_URL"
  mv "$tpz.part" "$tpz"
fi
# Provenance record next to the cached archive.
printf '%s\n%s\n' "$TPZ_URL" "$GODOT_VERSION" > "$cache/source.txt"

# --- unpack + install ------------------------------------------------------
work="$(mktemp -d "${TMPDIR:-/tmp}/cs-templates.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ "${ALL:-0}" = "1" ]]; then
  echo "fetch_templates: unpacking the full TPZ (ALL=1)"
  unzip -q -o "$tpz" 'templates/*' -d "$work"
else
  echo "fetch_templates: unpacking the ${#DESKTOP_TEMPLATES[@]} desktop release templates"
  unzip -q -o "$tpz" "${DESKTOP_TEMPLATES[@]/#/templates/}" -d "$work"
fi

mkdir -p "$install_dir"
if [[ "${ALL:-0}" = "1" ]]; then
  cp -R "$work/templates/." "$install_dir/"
else
  local_files=()
  for f in "${DESKTOP_TEMPLATES[@]}"; do local_files+=("$work/templates/$f"); done
  cp "${local_files[@]}" "$install_dir/"
fi
printf '%s\n' "$GODOT_VERSION" > "$install_dir/version.txt"

echo "fetch_templates: installed into $install_dir:"
ls -lh "$install_dir" | tail -n +2 | awk '{print "  ", $NF, "("$5")"}'
echo "fetch_templates: done — 'make export' can now run headless"
