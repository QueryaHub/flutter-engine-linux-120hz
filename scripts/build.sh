#!/usr/bin/env bash
# Build the vsync-patched libflutter_linux_gtk.so for a given Flutter engine
# monorepo commit.
#
# Usage:
#   ./scripts/build.sh <flutter-framework-commit> [runtime_mode]
#
#   flutter-framework-commit  The "Framework • revision" from `flutter --version`
#                             on the exact Flutter version/channel you're matching.
#                             flutter/flutter is a monorepo: the engine sources
#                             (engine/src/flutter/...) live at this same commit.
#   runtime_mode              release (default) | profile | debug
#
# Produces ./out/libflutter_linux_gtk.so and prints its content_hash (the value
# to tag the GitHub release with: engine-<content_hash>).
#
# Requires: git, python3, and enough disk (~15-20 GB for the gclient sync plus
# build output) and time (~30-90 min depending on CPU). See README.md caveats.
set -euo pipefail

COMMIT="${1:?usage: build.sh <flutter-framework-commit> [runtime_mode]}"
RUNTIME_MODE="${2:-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$ROOT/.build}"
mkdir -p "$WORK"

if [[ ! -d "$WORK/depot_tools" ]]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$WORK/depot_tools"
fi
export PATH="$WORK/depot_tools:$PATH"

# flutter/flutter is a monorepo: this single clone already contains
# engine/src/flutter/shell/platform/linux/... at the framework commit.
# gclient then only fetches the engine's third-party DEPS (skia, dart,
# boringssl, sysroots, ...) alongside it.
if [[ ! -d "$WORK/flutter/.git" ]]; then
  git clone https://github.com/flutter/flutter.git "$WORK/flutter"
fi
cd "$WORK/flutter"
git fetch origin "$COMMIT"
git checkout "$COMMIT"

cat > .gclient <<'EOF'
solutions = [
  {
    "custom_deps": {},
    "deps_file": "DEPS",
    "managed": False,
    "custom_vars": {
      "download_android_deps": False,
      "download_jdk": False,
      "download_fuchsia_deps": False,
      "download_esbuild": False,
    },
    "name": ".",
    "safesync_url": "",
    "url": "https://github.com/flutter/flutter.git",
  },
]
EOF
gclient sync -D --no-history

echo "Applying vsync patch..."
git apply "$ROOT/patches/vsync-fl_engine-fl_display_monitor.patch"

cd engine/src

python3 flutter/tools/gn --runtime-mode "$RUNTIME_MODE" --no-goma
ninja -C "out/host_$RUNTIME_MODE" flutter/shell/platform/linux:flutter_linux_gtk

OUT_SO="out/host_$RUNTIME_MODE/libflutter_linux_gtk.so"
CONTENT_HASH="$(grep '^content_hash' "out/host_$RUNTIME_MODE/args.gn" | sed 's/.*"\(.*\)"/\1/')"

mkdir -p "$ROOT/out"
cp "$OUT_SO" "$ROOT/out/libflutter_linux_gtk.so"

echo "Built: $ROOT/out/libflutter_linux_gtk.so"
echo "content_hash=$CONTENT_HASH"
echo "Publish with: ./scripts/publish_release.sh $CONTENT_HASH $RUNTIME_MODE"
