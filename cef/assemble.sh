#!/usr/bin/env bash
# Usage: assemble.sh <macos|linux> <base-dir> <content-dir> <out-dir> <steam: true|false> <icon-dir>
#
# macOS/Linux counterpart of assemble.ps1 (../README.md, "Desktop: the CEF player"): turns an
# extracted roves_shell_<macos|linux>[_steam].zip release asset into the developer's package.
#
#   1. Locate the player in <base-dir> (macOS: the only .app; Linux: the only folder with
#      libcef.so) and check the files the engine documents (support/cef-macos-gate/README.md,
#      support/cef-linux-gate/README.md), with the Steam redistributable exactly when <steam>.
#   2. Copy it to <out-dir> unchanged, keeping modes and symlinks (ditto / cp -a).
#   3. Replace game/ with <content-dir>.
#   4. Project icon (<icon-dir>, written by project_icon.py): the base's icon.png is dropped; a
#      resolved icon.png becomes the window icon and, on macOS, the bundle icon (icns.sh, an
#      identical copy of the engine's packaging/icns.sh, replaces the file CFBundleIconFile
#      names). Without a project icon the player keeps the Roves icons.
set -euo pipefail
platform="$1" base="$2" content="$3" out="$4" steam="$5" icons="$6"
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "::error::$*" >&2; exit 1; }

[ -f "$content/index.html" ] || fail "$content has no index.html at its root"
[ ! -e "$out" ] || fail "$out already exists"

# 1. Locate and check. No mapfile or empty arrays: macOS runners may use the system bash 3.2.
case "$platform" in
  macos) player="$(find "$base" -maxdepth 2 -type d -name '*.app')" ;;
  linux) player="$(find "$base" -maxdepth 2 -type f -name libcef.so -exec dirname {} \;)" ;;
  *) fail "unknown platform $platform" ;;
esac
if [ -z "$player" ] || [ "$(printf '%s\n' "$player" | wc -l | tr -d ' ')" != 1 ]; then
  fail "the $platform release asset does not contain exactly one CEF player: $(find "$base" -maxdepth 2 | head -20 | tr '\n' ' ')"
fi
if [ "$platform" = macos ]; then
  plist="$player/Contents/Info.plist"
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" || fail "$plist has no CFBundleExecutable"
  icns="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" || fail "$plist has no CFBundleIconFile"
  icns="Contents/Resources/${icns%.icns}.icns"
  required=("Contents/MacOS/$exe" "Contents/Frameworks/Chromium Embedded Framework.framework" "$icns" Contents/Resources/game/index.html)
  steam_lib=Contents/MacOS/libsteam_api.dylib game=Contents/Resources/game window_icon=Contents/Resources/icon.png
  root="$out/$(basename "$player")"
else
  required=(libcef.so chrome-sandbox icudtl.dat resources.pak game/index.html)
  steam_lib=libsteam_api.so game=game window_icon=icon.png
  root="$out"
  [ -x "$player/chrome-sandbox" ] || fail "chrome-sandbox lost its execute bit: the release asset was not extracted with its modes"
fi
for rel in "${required[@]}"; do
  [ -e "$player/$rel" ] || fail "the CEF base package lacks $rel"
done
if [ "$steam" = true ] && [ ! -f "$player/$steam_lib" ]; then fail "the Steam asset lacks $steam_lib"; fi
if [ "$steam" != true ] && [ -e "$player/$steam_lib" ]; then fail "the standard asset unexpectedly contains $steam_lib"; fi
echo "::notice::CEF $platform base package checked (${#required[@]} required entries, Steam $steam)"

# 2. Copy.
mkdir -p "$out"
if [ "$platform" = macos ]; then ditto "$player" "$root"; else cp -a "$player/." "$root/"; fi

# 3. Game.
rm -rf "${root:?}/$game"
mkdir -p "$root/$game"
cp -R "$content/." "$root/$game/"

# 4. Project icon.
rm -f "$root/$window_icon"
if [ -f "$icons/icon.png" ]; then
  cp "$icons/icon.png" "$root/$window_icon"
  if [ "$platform" = macos ]; then bash "$here/icns.sh" "$icons/icon.png" "$root/$icns"; fi
fi
echo "::notice::CEF $platform package assembled at $root"
