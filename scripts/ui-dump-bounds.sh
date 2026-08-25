#!/usr/bin/env bash
# Dump the on-screen accessibility tree and print every clickable node's real
# center + bounds. Tap by these centers instead of guessing pixels from a
# screenshot. Zero bounds ([0,0][0,0]) reveal NON-tappable elements (e.g. a
# tab bar pushed under the system nav bar on edge-to-edge) — a real defect that
# blind coordinate taps only look like a "miss".
# Usage: ADB=/path/adb PY=/path/python ./ui-dump-bounds.sh [serial]
set -euo pipefail
ADB="${ADB:-adb}"; PY="${PY:-python}"; SERIAL="${1:-}"; SEL=""; [ -n "$SERIAL" ] && SEL="-s $SERIAL"
export MSYS_NO_PATHCONV=1
$ADB $SEL shell uiautomator dump /sdcard/_ui.xml >/dev/null
$ADB $SEL pull /sdcard/_ui.xml ./_ui.xml >/dev/null
# NOTE: pass the script via stdin — do NOT write to /tmp while MSYS_NO_PATHCONV=1
# is set (python would look for C:\tmp on Windows Git Bash).
"$PY" - <<'PYEOF'
import re,xml.etree.ElementTree as ET
r=ET.parse("./_ui.xml").getroot()
for n in r.iter('node'):
    if n.get('clickable')!='true': continue
    b=n.get('bounds'); m=re.findall(r'\[(\d+),(\d+)\]',b);(x1,y1),(x2,y2)=[(int(a),int(c)) for a,c in m]
    lab=(n.get('text') or n.get('content-desc') or n.get('resource-id') or '')[:40]
    flag=' <-- ZERO/NON-TAPPABLE' if (x2-x1==0 or y2-y1==0) else ''
    print(f"center={(x1+x2)//2},{(y1+y2)//2}\tbounds={b}\t'{lab}'{flag}")
PYEOF
