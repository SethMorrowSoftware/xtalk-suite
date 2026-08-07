#!/usr/bin/env bash
# build-all.sh - configure, build, and test every buildable suite member.
#
# The suite is a set of independent extensions, each with its own build system;
# this is a convenience walker, not a unified build. It is intentionally simple
# and fail-loud: the first member that fails to build stops the run with a
# non-zero exit, so CI and humans both see exactly what broke.
#
# Usage:
#   tools/build-all.sh              # Release build + tests for every member
#   tools/build-all.sh --gates      # static gates only (fast; no compiler needed)
#
# Build under gcc with sanitizers while iterating on a shim (see each member's
# CLAUDE.md / docs/building.md); this walker does a plain Release build.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

GATES_ONLY=0
[ "${1:-}" = "--gates" ] && GATES_ONLY=1

# Members that carry a CMake build (a native shim to compile).
CMAKE_MEMBERS=(sodiumxt torrentxt enetxt datachannelxt)
# CoinXT builds via its own script; OnionXT is pure script (nothing to compile).

run_gates() {
  local m="$1" rel
  if [ -f "$m/tools/check-livecodescript.py" ]; then
    echo "== $m: static gate =="
    ( cd "$m" && python3 tools/check-livecodescript.py )
  fi
  # Record-schema golden / registry checks, where a member ships them. Use
  # explicit if/then (not `test && cmd`): under `set -e` a false `test &&` would
  # abort the whole run when a member simply lacks that optional gate.
  for rel in tests/record_golden_test.py tools/check-record-registry.py; do
    if [ -f "$m/$rel" ]; then
      echo "== $m: $rel =="
      ( cd "$m" && python3 "$rel" )
    fi
  done
}

# --- static gates for every member (always run; the only gate for onionxt) ---
for m in sodiumxt torrentxt enetxt datachannelxt onionxt coinxt; do
  if [ -d "$m" ]; then run_gates "$m"; fi
done

if [ "$GATES_ONLY" = 1 ]; then
  echo "All static gates passed."
  exit 0
fi

# --- native builds + tests ---
for m in "${CMAKE_MEMBERS[@]}"; do
  [ -d "$m" ] || continue
  echo "== $m: cmake configure + build + ctest =="
  cmake -S "$m" -B "$m/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$m/build" --parallel
  ctest --test-dir "$m/build" --output-on-failure || {
    echo "$m: ctest reported failures (or no tests registered)"; exit 1;
  }
done

if [ -x coinxt/build.sh ]; then
  echo "== coinxt: build.sh =="
  ( cd coinxt && ./build.sh )
fi

echo "build-all: every buildable member completed."
