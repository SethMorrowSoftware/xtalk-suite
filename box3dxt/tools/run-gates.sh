#!/usr/bin/env bash
# run-gates.sh - box3dxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs. The tests that need a
# compiler or an engine are not this list's: tests/smoke_test.c and
# tests/fuzz_test.c are the CMake build's (ctest), and tests/engine-selftest.lc,
# tests/engine-kit.lc and tests/engine-demo.lc (the game Kit and its example
# game) are run by the native lane on a real engine over the library that
# build made. Any gate file added under tools/ or tests/
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
echo "== box3dxt: static gate =="
python3 tools/check-livecodescript.py

# The shim against its two native tests: every LC_API export declared in
# tests/smoke_test.c as the shim defines it and CALLED there (a declaration
# is not a call), and every export in tests/fuzz_test.c's generated table.
echo "== box3dxt: tools/test-smoke-coverage.py =="
python3 tools/test-smoke-coverage.py
# The model the smoke test loads is carried as a generated header; this holds
# it to tests/models/teapot.obj.
echo "== box3dxt: tools/build-test-model.py --check =="
python3 tools/build-test-model.py --check

echo "== box3dxt: tools/check-smoke-coverage.py =="
python3 tools/check-smoke-coverage.py

# The .lcb against the shim: every foreign bind (name, return, each
# parameter), the mechanical names both ways, each public wrapper's shape,
# every doc block, the ABI number on both sides, and the engine self-test's
# generated sweep of every public handler. A mismatch here is not a compile
# error anywhere: it is a marshalling fault at run time, on an engine.
echo "== box3dxt: tools/test-lcb-signatures.py =="
python3 tools/test-lcb-signatures.py
echo "== box3dxt: tools/check-lcb-signatures.py =="
python3 tools/check-lcb-signatures.py

# docs/api-reference.md is generated from the doc blocks; stale is a failure.
echo "== box3dxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# The game Kit: its one source in src/, the copy the example game carries
# between its markers, and docs/kit-reference.md built from its doc blocks,
# whose --check also holds the Kit's header cheat sheet to its handlers and
# every b3k name in the hand-written pages to the real ones.
echo "== box3dxt: tools/sync-embedded-kit.py --check =="
python3 tools/sync-embedded-kit.py --check

# Orb Island carries Kenney's models (examples/models/) as text between its
# GAME MODELS markers: the carried text is what the source models make
echo "== box3dxt: tools/build-game-models.py --check =="
python3 tools/build-game-models.py --check
echo "== box3dxt: tools/test-kit-reference.py =="
python3 tools/test-kit-reference.py
echo "== box3dxt: tools/build-kit-reference.py --check =="
python3 tools/build-kit-reference.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. Empty until the suite's
# release-binaries dispatch commits the first libraries.
echo "== box3dxt: src/code/MANIFEST.sha256 =="
( cd src/code && if [ -s MANIFEST.sha256 ]; then sha256sum -c --quiet MANIFEST.sha256; else echo "no committed binaries yet"; fi )
