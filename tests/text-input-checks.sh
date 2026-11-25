#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=$1
mode=${2:-core}
runtime=$(mktemp -d)
chmod 700 "$runtime"
python3 "$repo/tests/text-input-server.py" "$runtime" "$mode" &
fixture=$!
trap 'kill "$fixture" 2>/dev/null || true; rm -f "$runtime/ready" "$runtime/wayland-ime"; rmdir "$runtime"' EXIT INT TERM
attempt=0
while [ ! -f "$runtime/ready" ]; do
  kill -0 "$fixture"
  attempt=$((attempt + 1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
FMX_TEST_IME_MODE="$mode" XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-ime timeout 15 "$binary"
wait "$fixture"
