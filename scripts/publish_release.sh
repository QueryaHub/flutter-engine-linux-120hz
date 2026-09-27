#!/usr/bin/env bash
# Publish a built libflutter_linux_gtk.so as a GitHub release asset, tagged by
# the engine content_hash it was built for.
#
# Usage:
#   ./scripts/publish_release.sh <content_hash> [runtime_mode]
#
# Expects ./out/libflutter_linux_gtk.so to exist (from scripts/build.sh).
# Requires: gh CLI, authenticated with write access to this repo.
set -euo pipefail

CONTENT_HASH="${1:?usage: publish_release.sh <content_hash> [runtime_mode]}"
RUNTIME_MODE="${2:-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SO="$ROOT/out/libflutter_linux_gtk.so"
if [[ ! -f "$SO" ]]; then
  echo "error: $SO not found — run scripts/build.sh first" >&2
  exit 1
fi

TAG="engine-${CONTENT_HASH}"
ASSET_NAME="libflutter_linux_gtk-${RUNTIME_MODE}.so.gz"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
gzip -c "$SO" > "$WORKDIR/$ASSET_NAME"

REPO="QueryaHub/flutter-engine-linux-120hz"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$WORKDIR/$ASSET_NAME" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$WORKDIR/$ASSET_NAME" \
    --repo "$REPO" \
    --title "Engine $CONTENT_HASH ($RUNTIME_MODE)" \
    --notes "Patched libflutter_linux_gtk.so ($RUNTIME_MODE) for engine content_hash \`$CONTENT_HASH\`. See README.md for what's patched and why."
fi

echo "Published: https://github.com/$REPO/releases/tag/$TAG"
