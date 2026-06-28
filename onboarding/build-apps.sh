#!/usr/bin/env bash
#
# build-apps.sh — wrap generated <seat>.command launchers into double-clickable .app bundles.
#
# A .app can't host an interactive TTY, so each bundle just `open`s its .command (which opens
# Terminal running seat-launch.sh -> claude). The .command stays the single source of truth, so
# the app inherits every loop/prompt change for free. Hand-built bundles — no Platypus/Homebrew.
# Drop icons/<key>.icns next to the commands to brand a seat, then re-run.
#
# Usage:  build-apps.sh --dir ~/Code/agents/sammy                 # wrap every *.command in DIR
#         build-apps.sh --command ~/Code/agents/sammy/dex.command --name Dex
#
set -euo pipefail

DIR="" ; ONE="" ; ONENAME=""
while [ $# -gt 0 ]; do case "$1" in
  --dir)     DIR="$2"; shift 2 ;;
  --command) ONE="$2"; shift 2 ;;
  --name)    ONENAME="$2"; shift 2 ;;
  *) echo "build-apps: unknown arg: $1" >&2; exit 1 ;;
esac; done

titlecase() { printf '%s' "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }

build_one() {
  local cmd="$1" name="$2"
  local dir; dir="$(cd "$(dirname "$cmd")" && pwd)"
  local key; key="$(basename "$cmd" .command)"
  local app="$dir/${name}.app"
  local macos="$app/Contents/MacOS" res="$app/Contents/Resources"
  rm -rf "$app"; mkdir -p "$macos" "$res"

  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>${name}</string>
  <key>CFBundleDisplayName</key><string>${name}</string>
  <key>CFBundleIdentifier</key><string>dev.agentic-sdlc.seat.${key}</string>
  <key>CFBundleExecutable</key><string>run</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>10.13</string>
</dict></plist>
PLIST

  cat > "$macos/run" <<RUN
#!/bin/bash
# ${name} seat launcher — open Terminal on the seat command (which execs claude).
open "${cmd}"
RUN
  chmod +x "$macos/run"

  [ -f "$dir/icons/${key}.icns" ] && cp "$dir/icons/${key}.icns" "$res/icon.icns"
  echo "app: $app  →  open $cmd"
}

if [ -n "$ONE" ]; then
  [ -f "$ONE" ] || { echo "build-apps: no such command: $ONE" >&2; exit 1; }
  build_one "$ONE" "${ONENAME:-$(titlecase "$(basename "$ONE" .command)")}"
elif [ -n "$DIR" ]; then
  shopt -s nullglob
  found=0
  for cmd in "$DIR"/*.command; do build_one "$cmd" "$(titlecase "$(basename "$cmd" .command)")"; found=1; done
  [ "$found" -eq 1 ] || echo "build-apps: no *.command files in $DIR"
else
  echo "usage: build-apps.sh --dir <dir-of-.commands> | --command <file> [--name N]" >&2; exit 1
fi
