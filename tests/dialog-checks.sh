#!/bin/sh
# Run under dbus-run-session; Python dbus/gi are fixture dependencies only.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=${1:-"$repo/out/dialogs/bin/Linux64/Release/DialogChecks"}
if [ "$#" -gt 0 ]; then shift; fi
ready=$(mktemp)
rm -f "$ready"
python3 "$repo/tests/portal-mock.py" "$ready" &
fixture=$!
trap 'kill "$fixture" 2>/dev/null || true; rm -f "$ready" "$ready.closed"' EXIT INT TERM
attempt=0
while [ ! -f "$ready" ]; do
  kill -0 "$fixture"
  attempt=$((attempt + 1))
  [ "$attempt" -lt 100 ]
  sleep 0.05
done
timeout 30 "$binary" "$@"
if [ "${binary##*/}" = DialogChecks ]; then [ -f "$ready.closed" ]; fi
