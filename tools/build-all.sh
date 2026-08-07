#!/usr/bin/env bash
# build-all.sh - configure, build, and test every buildable suite member.
#
# The suite is a set of independent extensions, each with its own build system;
# this is a convenience walker, not a unified build. It is intentionally simple
# and fail-loud: the first member that fails stops the run with a non-zero
# exit, so CI and humans both see exactly what broke.
#
# Usage:
#   tools/build-all.sh              # Release build + native tests for every member
#   tools/build-all.sh --gates      # static gates only (fast; python3, plus a C
#                                   # compiler for coinxt's KAT harness)
#
# Build under gcc with sanitizers while iterating on a shim (see each member's
# CLAUDE.md / docs/building.md); this walker does a plain Release build.
#
# NOTE: a full build re-bundles sodiumxt's freshly built x86_64-linux binary
# into sodiumxt/src/code/ (its CMake does this on purpose), which will differ
# byte-for-byte from the committed one and fail the MANIFEST gate until you
# either `git checkout` it (nothing changed) or refresh binary + manifest
# together in the same change (suite rule 5, when the change is intentional).

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

GATES_ONLY=0
[ "${1:-}" = "--gates" ] && GATES_ONLY=1

# Members that carry a CMake build (a native shim to compile). Each gates its
# ctest registration behind <MEMBER>_BUILD_TESTS, so the walker turns that on.
CMAKE_MEMBERS=(sodiumxt torrentxt enetxt datachannelxt)
# CoinXT builds via coinxt/native/build.sh; OnionXT is pure script (nothing to
# compile).

run_gates() {
  local m="$1" rel
  # The LiveCodeScript/LCB static gate (every member carries it).
  if [ -f "$m/tools/check-livecodescript.py" ]; then
    echo "== $m: static gate =="
    ( cd "$m" && python3 tools/check-livecodescript.py )
  fi
  # The house-style docs gate, where a member ships one (onionxt, coinxt).
  if [ -f "$m/tools/check-docs-style.py" ]; then
    echo "== $m: docs-style gate =="
    ( cd "$m" && python3 tools/check-docs-style.py )
  fi
  # Every golden-vector suite the member ships (wire formats, BEP44, the file
  # server, ...) - glob, so a member adding one is covered with no edit here.
  for rel in "$m"/tests/*golden*.py; do
    if [ -f "$rel" ]; then
      echo "== $m: ${rel#"$m"/} =="
      ( cd "$m" && python3 "${rel#"$m"/}" )
    fi
  done
  # Record-registry sync (shim header <-> .lcb constants).
  if [ -f "$m/tools/check-record-registry.py" ]; then
    echo "== $m: tools/check-record-registry.py =="
    ( cd "$m" && python3 tools/check-record-registry.py )
  fi
  # Known-answer-vector harnesses: onionxt's is pure python; coinxt's builds
  # the shim from source in a temp dir and drives it via ctypes.
  if [ -f "$m/tools/onion-kat.py" ]; then
    echo "== $m: tools/onion-kat.py --check =="
    ( cd "$m" && python3 tools/onion-kat.py --check )
  fi
  if [ -f "$m/tools/coin-kat.py" ]; then
    echo "== $m: tools/coin-kat.py --check =="
    ( cd "$m" && python3 tools/coin-kat.py --check )
  fi
  # Generated-standalone freshness (onionxt): the committed standalones must
  # match what the generator would emit from the current sources.
  if [ -f "$m/tools/build-standalone.py" ]; then
    echo "== $m: tools/build-standalone.py --check =="
    ( cd "$m" && python3 tools/build-standalone.py --check )
  fi
  # Committed-binary / vendored-source integrity manifests: a committed blob
  # that is unlisted or does not match its recorded SHA256 fails the gate.
  if [ -f "$m/src/code/MANIFEST.sha256" ]; then
    echo "== $m: src/code/MANIFEST.sha256 =="
    ( cd "$m/src/code" && sha256sum -c --quiet MANIFEST.sha256 )
  fi
  if [ -f "$m/native/MANIFEST.sha256" ]; then
    echo "== $m: native/MANIFEST.sha256 =="
    ( cd "$m/native" && sha256sum -c --quiet MANIFEST.sha256 )
  fi
}

# --- static gates for every member (always run) ---
for m in sodiumxt torrentxt enetxt datachannelxt onionxt coinxt; do
  if [ -d "$m" ]; then run_gates "$m"; fi
done

# --- suite-level: every handler CALLED across members must actually EXIST ---
# The members call into each other by name across a boundary no compiler checks,
# and the only runtime that would catch a typo is a GUI engine we cannot run
# headless. This is the gate that would have caught the shipped example calling
# sxHashKey (a handler that never existed). It is repo-wide, so it runs once
# rather than per member.
if [ -f tools/check-handler-calls.py ]; then
  echo "== suite: tools/check-handler-calls.py =="
  python3 tools/check-handler-calls.py
fi

if [ "$GATES_ONLY" = 1 ]; then
  echo "All static gates passed."
  exit 0
fi

# --- native builds + tests ---
for m in "${CMAKE_MEMBERS[@]}"; do
  [ -d "$m" ] || continue
  # sodiumxt -> SODIUMXT_BUILD_TESTS etc.: without this flag no member
  # registers any ctest test, and ctest exits 0 on an empty test set, so the
  # old plain-Release walk "passed" while testing nothing. --no-tests=error
  # keeps that from ever happening silently again.
  tflag="$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')_BUILD_TESTS"
  echo "== $m: cmake configure + build + ctest =="
  cmake -S "$m" -B "$m/build" -DCMAKE_BUILD_TYPE=Release "-D${tflag}=ON"
  cmake --build "$m/build" --parallel
  ctest --test-dir "$m/build" --output-on-failure --no-tests=error || {
    echo "$m: ctest failed (or no tests were registered)"; exit 1;
  }
done

# CoinXT: the asan variant compiles the shim + vendored sources and runs the
# ASan/UBSan self-test, entirely in a temp dir (the plain `lib` variant would
# drop native/libcoinxt.so into the working tree, so the walker avoids it).
if [ -f coinxt/native/build.sh ]; then
  echo "== coinxt: native/build.sh asan (build + self-test) =="
  ( cd coinxt && sh native/build.sh asan )
else
  echo "coinxt/native/build.sh missing"; exit 1
fi

echo "build-all: every buildable member completed."
