#!/bin/sh
# Download the pinned upstream Mainsail release, verify sha256, and extract into
# files/html/. Run this once after cloning, or whenever VERSION is bumped.
# Extracting wipes the tree, so scripts/patch-mainsail.sh runs afterwards and puts
# every Bespok3d modification back. It fails loudly on a chunk whose shape upstream
# changed, so a re-vendor never loses a patch quietly.
#
# Usage: ./scripts/fetch-mainsail.sh

set -eu

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$PLUGIN_DIR/VERSION"
TARGET_DIR="$PLUGIN_DIR/files/html"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: $VERSION_FILE not found" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$VERSION_FILE"

if [ -z "${MAINSAIL_VERSION:-}" ] || [ -z "${MAINSAIL_SHA256:-}" ]; then
  echo "ERROR: VERSION must set MAINSAIL_VERSION and MAINSAIL_SHA256" >&2
  exit 1
fi

URL="https://github.com/mainsail-crew/mainsail/releases/download/${MAINSAIL_VERSION}/mainsail.zip"
ZIP_PATH="$(mktemp -t mainsail-XXXXXX).zip"
trap 'rm -f "$ZIP_PATH"' EXIT

echo "Downloading Mainsail ${MAINSAIL_VERSION}..."
curl -fsSL -o "$ZIP_PATH" "$URL"

echo "Verifying sha256..."
actual=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
if [ "$actual" != "$MAINSAIL_SHA256" ]; then
  echo "ERROR: sha256 mismatch" >&2
  echo "  expected: $MAINSAIL_SHA256" >&2
  echo "  actual:   $actual" >&2
  exit 1
fi

echo "Extracting into $TARGET_DIR..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
unzip -q "$ZIP_PATH" -d "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/index.html" ]; then
  echo "ERROR: $TARGET_DIR/index.html missing after extract" >&2
  exit 1
fi

echo "Re-applying Bespok3d patches..."
"$PLUGIN_DIR/scripts/patch-mainsail.sh"

echo "Done. Mainsail ${MAINSAIL_VERSION} extracted to $TARGET_DIR"
