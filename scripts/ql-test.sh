#!/usr/bin/env bash
# Opens a file in Quick Look via qlmanage for a few seconds and prints the extension's log messages.
# Usage: scripts/ql-test.sh file.ifc [seconds]
set -uo pipefail
FILE="$1"; SECS="${2:-10}"
LOG="$(mktemp -t qltest)"
/usr/bin/log stream --level info --style compact --predicate 'subsystem == "com.ibaranov.IFCQuickLook"' > "$LOG" 2>&1 &
LP=$!
sleep 1
qlmanage -p "$FILE" > /dev/null 2>&1 &
QP=$!
sleep "$SECS"
kill $QP 2>/dev/null; sleep 0.5; kill $LP 2>/dev/null
grep -v '^Filtering\|^Timestamp' "$LOG" | sed -E 's/^[0-9-]+ ([0-9:.]+) +[A-Za-z]+ +IFCPreview\[[0-9:a-f]+\] \[com\.ibaranov\.IFCQuickLook:([a-z]+)\]/\1 [\2]/'
rm -f "$LOG"
