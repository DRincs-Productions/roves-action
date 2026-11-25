#!/usr/bin/env bash
# Usage: icns.sh <square.png> <out.icns>
#
# The macOS player's application icon (README "Application icon"): converts a square PNG
# (the game's project icon, or the repository's Roves icon.png as the fallback) into an .icns
# with the system's own tools, sips (resampling) and iconutil (iconset -> icns). Sizes above
# the source edge are left out instead of upscaled; iconutil accepts a partial iconset.
# cef's macOS bundler (`bundle --resources <dir>`) copies <dir>/mac/<executable>.icns into
# Contents/Resources and sets CFBundleIconFile; packaging replaces that file in place.
set -euo pipefail
png="$1"
out="$2"
edge="$(sips -g pixelWidth "$png" | awk '/pixelWidth/ { print $2 }')"
height="$(sips -g pixelHeight "$png" | awk '/pixelHeight/ { print $2 }')"
if [ -z "$edge" ] || [ "$edge" != "$height" ] || [ "$edge" -lt 16 ]; then
  echo "icns.sh: $png is ${edge:-?}x${height:-?}, expected a square of at least 16 px" >&2
  exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
set="$work/icon.iconset"
mkdir "$set"
for size in 16 32 128 256 512; do
  if [ "$size" -le "$edge" ]; then
    sips -s format png -z "$size" "$size" "$png" --out "$set/icon_${size}x${size}.png" > /dev/null
  fi
  if [ "$((size * 2))" -le "$edge" ]; then
    sips -s format png -z "$((size * 2))" "$((size * 2))" "$png" --out "$set/icon_${size}x${size}@2x.png" > /dev/null
  fi
done
mkdir -p "$(dirname "$out")"
iconutil -c icns "$set" -o "$out"
echo "icns.sh: $out from $png (${edge}x${edge}, $(ls "$set" | wc -l | tr -d ' ') sizes)"
