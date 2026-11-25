#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=$1
for mode in csd ssd refuse force-client old; do
  runtime=$(mktemp -d)
  chmod 700 "$runtime"
  python3 "$repo/tests/window-server.py" "$runtime" "$mode" &
  fixture=$!
  trap 'kill "$fixture" 2>/dev/null || true; rm -f "$runtime/ready" "$runtime/wayland-windows"; rmdir "$runtime"' EXIT INT TERM
  attempt=0
  while [ ! -f "$runtime/ready" ]; do
    kill -0 "$fixture"
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ]; sleep 0.05
  done
  FMX_TEST_WM_MODE="$mode" XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-windows timeout 30 "$binary"
  wait "$fixture"
  rm -f "$runtime/ready" "$runtime/wayland-windows"
  rmdir "$runtime"
  trap - EXIT INT TERM
done
