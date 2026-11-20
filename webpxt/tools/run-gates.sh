#!/usr/bin/env bash
# run-gates.sh - webpxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs. The three tests that
# need a compiler or an engine are not this list's: tests/smoke_test.c and
# tests/fuzz_test.c are the CMake build's (ctest), and
# tests/engine-selftest.lc is run by the native lane on a real engine over
# the library that build made. Any gate file added under tools/ or tests/
# MUST be named here: the suite's tools/check-member-standalone.py refuses a
# gate file this script never names.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. A fixture test runs before its gate.
#
# Runs from anywhere: every gate runs from the member root.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal).
echo "== webpxt: static gate =="
python3 tools/check-livecodescript.py

# The shim, its tests and its binding name the same functions: every export
# CALLED by the smoke test (a declaration is not a call) and bound once by
# the .lcb, no bind to a name the shim lacks, one ABI number in three places,
# and every public handler in the engine self-test's sweep. A mismatch here
# is not a compile error anywhere: it is a bind that fails on an engine.
echo "== webpxt: tools/test-shim-coverage.py =="
python3 tools/test-shim-coverage.py
echo "== webpxt: tools/check-shim-coverage.py =="
python3 tools/check-shim-coverage.py

# docs/api-reference.md is generated from the doc blocks; stale is a failure.
echo "== webpxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. Empty until the suite's
# release-binaries dispatch commits the first libraries.
echo "== webpxt: src/code/MANIFEST.sha256 =="
( cd src/code && if [ -s MANIFEST.sha256 ]; then sha256sum -c --quiet MANIFEST.sha256; else echo "no committed binaries yet"; fi )
