#!/usr/bin/env bash
# run-gates.sh - midixt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs. The layers that need
# a compiler or an engine are not this list's: tests/midi_smoke_test.c and
# tests/midi_mock_smoke_test.c are the CMake build's (ctest), and
# tools/run-lcb-tests.py (lc-compile + lc-run) and tools/run-lcs-tests.py (the
# standalone engine) are run by the native lane over the libraries that build
# made. Any gate file added under tools/ or tests/ MUST be named here: the
# suite's tools/check-member-standalone.py refuses a gate file this script
# never names.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. A fixture test runs before its gate.
#
# Runs from anywhere: every gate runs from the member root.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal).
echo "== midixt: static gate =="
python3 tools/check-livecodescript.py

# tests/vectors/midi.json is the one source of the senders' and the decoder's
# expected bytes: the LCB vectors module generated from it must project
# cleanly, and a clean-room Python codec written from the MIDI 1.0
# specification must agree with every vector.
echo "== midixt: tools/gen_vectors.py --check =="
python3 tools/gen_vectors.py --check
echo "== midixt: tests/vectors_reference_test.py =="
python3 tests/vectors_reference_test.py

# The packager must never ship the mock library (it exports midimock_* under
# the same bare name): proven on a stand-in file, so it needs no build.
echo "== midixt: tests/package_extension_test.py =="
python3 tests/package_extension_test.py

# docs/api-reference.md is generated from the binding's doc blocks (the
# blocks the IDE dictionary reads): it must match them.
echo "== midixt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. Empty until the suite's
# release-binaries dispatch commits the first libraries.
echo "== midixt: src/code/MANIFEST.sha256 =="
( cd src/code && if [ -s MANIFEST.sha256 ]; then sha256sum -c --quiet MANIFEST.sha256; else echo "no committed binaries yet"; fi )
