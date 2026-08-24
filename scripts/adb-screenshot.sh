#!/usr/bin/env bash
# Reliable adb screenshot on Windows Git Bash.
# MSYS_NO_PATHCONV=1 stops Git Bash mangling the on-device /sdcard path
# (otherwise it becomes C:/Program Files/Git/sdcard and screencap fails).
# Usage: ./adb-screenshot.sh <local_out.png> [serial]
set -euo pipefail
OUT="${1:-shot.png}"; SERIAL="${2:-}"
ADB="${ADB:-adb}"; SEL=""; [ -n "$SERIAL" ] && SEL="-s $SERIAL"
export MSYS_NO_PATHCONV=1
$ADB $SEL shell screencap -p /sdcard/_shot.png
$ADB $SEL pull /sdcard/_shot.png "$OUT"
$ADB $SEL shell rm -f /sdcard/_shot.png
echo "saved $OUT"
