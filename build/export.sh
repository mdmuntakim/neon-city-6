#!/usr/bin/env bash
# ============================================================================
# One-command reproducible build of NEON CITY 6 for Android.
#
#   bash build/export.sh                 # signed arm64-v8a release APK
#   ABI=both bash build/export.sh        # + x86_64 debug smoke APK
#   ABI=x86_64 bash build/export.sh      # x86_64 debug smoke APK only
#
# Pinned: Godot 4.5.2-stable editor and matching export templates.
# Output: build/neoncity6-arm64.apk (signed, arm64-v8a only) and optionally
# build/neoncity6-x86_64-debug.apk (smoke tests, never released).
# No Android SDK or gradle is required: Godot's prebuilt APK template is used.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_VERSION="4.5.2-stable"
GODOT_TEMPLATE_DIR="4.5.2.stable"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
TEMPLATES_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
TOOLS="${NEONCITY_TOOLS:-$HOME/.cache/neoncity-tools}"
ABI="${ABI:-arm64}"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR"

log() { printf '==> %s\n' "$*"; }

mkdir -p "$TOOLS" build
START_EPOCH=$(date +%s)

# --- engine ----------------------------------------------------------------
if [ ! -x "$TOOLS/godot" ]; then
  log "downloading Godot $GODOT_VERSION editor"
  [ -f "$TOOLS/godot.zip" ] || curl -fsSL -o "$TOOLS/godot.zip" "$GODOT_URL"
  unzip -o -q "$TOOLS/godot.zip" -d "$TOOLS"
  mv "$TOOLS/Godot_v${GODOT_VERSION}_linux.x86_64" "$TOOLS/godot"
  chmod +x "$TOOLS/godot"
fi
GODOT="$TOOLS/godot"

if [ ! -f "$TEMPLATES_DIR/android_release.apk" ]; then
  log "downloading Godot $GODOT_VERSION export templates (~1.3 GB)"
  [ -f "$TOOLS/templates.tpz" ] || curl -fsSL -o "$TOOLS/templates.tpz" "$TEMPLATES_URL"
  mkdir -p "$TEMPLATES_DIR"
  rm -rf "$TOOLS/tpz"
  unzip -o -q "$TOOLS/templates.tpz" -d "$TOOLS/tpz"
  mv "$TOOLS/tpz/templates/"* "$TEMPLATES_DIR/"
fi

# --- signing key -----------------------------------------------------------
# The project's public, debug-grade signing key. Documented in signing/README.md.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/signing/debug.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

# --- generated assets ------------------------------------------------------
if [ ! -f assets/textures/facade_0.png ] || [ ! -f assets/audio/radio_synth.wav ]; then
  log "generating original textures and audio"
  command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
  python3 tools/gen_assets.py
fi

# --- converter tests -------------------------------------------------------
log "running converter tests"
python3 -m unittest discover -s tests -p 'test_*.py' -v 2>&1 | tail -12

# --- import + engine tests -------------------------------------------------
log "importing assets"
"$GODOT" --headless --import >"$TOOLS/import.log" 2>&1 || {
  tail -60 "$TOOLS/import.log"; exit 1; }

log "running engine tests"
"$GODOT" --headless -s tests/run_tests.gd 2>&1 | tee "$TOOLS/tests.log" | tail -5
grep -q "ALL TESTS PASSED" "$TOOLS/tests.log" || {
  echo "engine tests failed"; tail -40 "$TOOLS/tests.log"; exit 1; }

# --- export ----------------------------------------------------------------
PRESET="Android arm64"
export_arm64() {
  log "exporting signed Android arm64 release APK"
  "$GODOT" --headless --export-release "$PRESET" build/neoncity6-arm64.apk 2>&1 | tail -4
  log "arm64 APK: $(wc -c <build/neoncity6-arm64.apk) bytes"
  unzip -l build/neoncity6-arm64.apk | grep 'lib/' | awk '{print $4}' | sort -u
  sha256sum build/neoncity6-arm64.apk
}

export_x86_64() {
  cp export_presets.cfg "$TOOLS/export_presets.cfg.bak"
  sed -i 's|architectures/arm64-v8a=true|architectures/arm64-v8a=false|; s|architectures/x86_64=false|architectures/x86_64=true|' export_presets.cfg
  log "exporting x86_64 debug APK (smoke test only, never released)"
  "$GODOT" --headless --export-debug "$PRESET" build/neoncity6-x86_64-debug.apk 2>&1 | tail -4
  cp "$TOOLS/export_presets.cfg.bak" export_presets.cfg
  log "x86_64 APK: $(wc -c <build/neoncity6-x86_64-debug.apk) bytes"
  unzip -l build/neoncity6-x86_64-debug.apk | grep 'lib/' | awk '{print $4}' | sort -u
}

case "$ABI" in
  arm64)  export_arm64 ;;
  x86_64) export_x86_64 ;;
  both)   export_arm64; export_x86_64 ;;
  *) echo "ABI must be arm64, x86_64 or both" >&2; exit 2 ;;
esac

END_EPOCH=$(date +%s)
log "build time: $((END_EPOCH - START_EPOCH)) s"
