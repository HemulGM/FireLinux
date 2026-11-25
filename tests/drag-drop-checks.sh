#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=$1
mode=${2:-text}
runtime=$(mktemp -d)
chmod 700 "$runtime"
python3 "$repo/tests/drag-drop-server.py" "$runtime" "$mode" &
fixture=$!
trap 'kill "$fixture" 2>/dev/null || true; rm -f "$runtime/ready" "$runtime/wayland-drag"; rmdir "$runtime"' EXIT INT TERM
attempt=0
while [ ! -f "$runtime/ready" ]; do
  kill -0 "$fixture"
  attempt=$((attempt + 1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
FMX_TEST_DRAG_MODE="$mode" XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-drag timeout 15 "$binary" ${FMX_TEST_DRAG_ARGS:-}
wait "$fixture"
