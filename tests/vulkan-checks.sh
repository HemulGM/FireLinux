#!/bin/sh
# Run VulkanChecks in an existing Wayland session. Enable the installed Khronos
# validation layer with FMXWAYLAND_VULKAN_VALIDATION=1 (VK_LAYER_PATH if needed).
set -u
if [ "$#" -ne 1 ]; then
  echo "Usage: sh tests/vulkan-checks.sh /path/to/VulkanChecks" >&2
  exit 2
fi
log=$(mktemp)
trap 'rm -f "$log"' EXIT HUP INT TERM
timeout 30s "$1" >"$log" 2>&1
result=$?
cat "$log"
if [ "$result" -ne 0 ]; then exit "$result"; fi
if grep -Eq 'Validation Error|VUID-|UNASSIGNED-' "$log"; then
  echo 'Vulkan validation reported an error' >&2
  exit 1
fi
grep -q 'All Vulkan checks passed' "$log"
