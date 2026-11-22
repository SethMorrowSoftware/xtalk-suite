#!/usr/bin/env bash
# run-gates.sh - oscxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs. The layers that need
# a compiler or an engine are not this list's: tests/osc_smoke_test.c,
# tests/osc_vectors_test.c and tests/fuzz/osc_fuzz.c are the CMake build's
# (ctest), and tools/run-lcb-tests.py (lc-compile + lc-run) and
# tools/run-lcs-tests.py (the standalone engine) are run by the native lane
# over the library that build made. Any gate file added under tools/ or
# tests/ MUST be named here: the suite's tools/check-member-standalone.py
# refuses a gate file this script never names.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. A fixture test runs before its gate.
#
# Runs from anywhere: every gate runs from the member root.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal).
echo "== oscxt: static gate =="
python3 tools/check-livecodescript.py

# tests/vectors/osc.json is the one source of the wire format: the C header
# generated from it must be fresh, and a clean-room Python codec written from
# the OSC 1.0 specification must agree with every vector (python-osc too,
# when it is installed; the native lane sets OSCXT_REQUIRE_PYTHONOSC=1).
echo "== oscxt: tools/gen_vectors.py --check =="
python3 tools/gen_vectors.py --check
echo "== oscxt: tests/vectors_reference_test.py =="
python3 tests/vectors_reference_test.py

# The virtual OSC peer the engine interop suite trusts, proven over real UDP
# on 127.0.0.1 against the vectors before any engine test leans on it.
echo "== oscxt: tests/simulators_test.py =="
python3 tests/simulators_test.py

# docs/api-reference.md is generated from the binding's doc blocks (the
# blocks the IDE dictionary reads): it must match them.
echo "== oscxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. Empty until the suite's
# release-binaries dispatch commits the first libraries.
echo "== oscxt: src/code/MANIFEST.sha256 =="
( cd src/code && if [ -s MANIFEST.sha256 ]; then sha256sum -c --quiet MANIFEST.sha256; else echo "no committed binaries yet"; fi )
