#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT_DIR/assets/app-icon"
SVG_FILE="$ICON_DIR/AppIcon.svg"
ICONSET_DIR="$ICON_DIR/WritingAssistant.iconset"
ICNS_FILE="$ICON_DIR/WritingAssistant.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required. Install it with: brew install librsvg" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to create the .icns file." >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR"

rsvg-convert -w 16 -h 16 "$SVG_FILE" -o "$ICONSET_DIR/icon_16x16.png"
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICONSET_DIR/icon_16x16@2x.png"
rsvg-convert -w 32 -h 32 "$SVG_FILE" -o "$ICONSET_DIR/icon_32x32.png"
rsvg-convert -w 64 -h 64 "$SVG_FILE" -o "$ICONSET_DIR/icon_32x32@2x.png"
rsvg-convert -w 128 -h 128 "$SVG_FILE" -o "$ICONSET_DIR/icon_128x128.png"
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICONSET_DIR/icon_128x128@2x.png"
rsvg-convert -w 256 -h 256 "$SVG_FILE" -o "$ICONSET_DIR/icon_256x256.png"
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICONSET_DIR/icon_256x256@2x.png"
rsvg-convert -w 512 -h 512 "$SVG_FILE" -o "$ICONSET_DIR/icon_512x512.png"
rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$ICONSET_DIR/icon_512x512@2x.png"

python3 "$ROOT_DIR/scripts/make_icns.py" "$ICONSET_DIR" "$ICNS_FILE"

echo "Generated $ICNS_FILE"
