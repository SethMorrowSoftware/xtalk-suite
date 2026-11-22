#!/usr/bin/env bash
# run-gates.sh - artnetxt's OWN gate list: what CI and a contributor run.
# Compiler-free and engine-free: python3 is all it needs. The layers that
# need an engine are not this list's: tools/run-lcb-tests.py (lc-compile +
# lc-run) and tools/run-lcs-tests.py (the standalone engine) are run by the
# native lane, which has an OXT engine. artnetxt has no native code, so there
# is no ctest and no committed library either. Any gate file added under
# tools/ or tests/ MUST be named here: the suite's
# tools/check-member-standalone.py refuses a gate file this script never names.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. A fixture test runs before its gate.
#
# Runs from anywhere: every gate runs from the member root.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal).
echo "== artnetxt: static gate =="
python3 tools/check-livecodescript.py

# tests/vectors/artnet.json is the one source of the wire format: it must
# project cleanly into the LCB vectors module, and a clean-room Python codec
# written from the Art-Net 4 specification must agree with every vector.
echo "== artnetxt: tools/gen_vectors.py --check =="
python3 tools/gen_vectors.py --check
echo "== artnetxt: tests/vectors_reference_test.py =="
python3 tests/vectors_reference_test.py

# A third encoder, sharing no code with the codec or the binding, holds
# hand-checked golden packets with each byte-order trap called out alone.
echo "== artnetxt: tests/artnet_golden_test.py =="
python3 tests/artnet_golden_test.py

# The virtual Art-Net node the engine interop suite trusts, proven over real
# UDP on 127.0.0.1 against the vectors before any engine test leans on it.
echo "== artnetxt: tests/simulators_test.py =="
python3 tests/simulators_test.py

# docs/api-reference.md is generated from the binding's doc blocks (the
# blocks the IDE dictionary reads): it must match them.
echo "== artnetxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check
