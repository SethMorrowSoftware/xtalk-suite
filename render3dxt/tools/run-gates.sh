#!/usr/bin/env bash
# run-gates.sh - render3dxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs. The tests that
# need a compiler or an engine are not this list's: tests/smoke_test.c and
# tests/fuzz_test.c are the CMake build's (ctest), and
# tests/engine-selftest.lc, tests/engine-interop.lc and tests/engine-demo.lc
# are run by the native lane on a real engine over the library that build
# made. Any gate file added under tools/ or tests/
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
echo "== render3dxt: static gate =="
python3 tools/check-livecodescript.py

# The model and picture files the two native tests carry inside them
# (tests/test_assets.h) are the files of tests/assets/, byte for byte.
echo "== render3dxt: tools/build-test-assets.py --check =="
python3 tools/build-test-assets.py --check

# The shim against its two native tests: every LC_API export declared in
# tests/smoke_test.c as the shim defines it and CALLED there (a declaration
# is not a call), and every export in tests/fuzz_test.c's generated table.
echo "== render3dxt: tools/test-smoke-coverage.py =="
python3 tools/test-smoke-coverage.py
echo "== render3dxt: tools/check-smoke-coverage.py =="
python3 tools/check-smoke-coverage.py

# The .lcb against the shim: every foreign bind (name, return, each
# parameter), the mechanical names both ways, each public wrapper's whole
# body, every doc block, the ABI number on both sides, and the engine
# self-test's generated sweep of every public handler. A mismatch here is not
# a compile error anywhere: it is a marshalling fault at run time, on an
# engine.
echo "== render3dxt: tools/test-lcb-signatures.py =="
python3 tools/test-lcb-signatures.py
echo "== render3dxt: tools/check-lcb-signatures.py =="
python3 tools/check-lcb-signatures.py

# docs/api-reference.md is generated from the doc blocks; stale is a failure.
echo "== render3dxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. Empty until the suite's
# release-binaries dispatch commits the first libraries.
echo "== render3dxt: src/code/MANIFEST.sha256 =="
( cd src/code && if [ -s MANIFEST.sha256 ]; then sha256sum -c --quiet MANIFEST.sha256; else echo "no committed binaries yet"; fi )
