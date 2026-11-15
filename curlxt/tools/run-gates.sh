#!/usr/bin/env bash
# run-gates.sh - curlxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs (the native smoke test
# is the CMake build's, not this list's). Any gate file added under tools/ or
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
echo "== curlxt: static gate =="
python3 tools/check-livecodescript.py

# Header <-> .lcb: every constant, every foreign bind, every name table.
echo "== curlxt: tools/test-abi-registry.py =="
python3 tools/test-abi-registry.py
echo "== curlxt: tools/check-abi-registry.py =="
python3 tools/check-abi-registry.py

# docs/api-reference.md is generated from the doc blocks; stale is a failure.
echo "== curlxt: tools/build-api-reference.py --check =="
python3 tools/build-api-reference.py --check

# The shipped helpers and tsNet layers RUN over the built native library and
# loopback HTTP and SMTP servers. Without a built library (no $CURLXT_LIB and
# no committed x86_64-linux binary) both SKIP and say so; the native lane sets
# CURLXT_REQUIRE_LIB=1, where a skip is a failure. Needs the riptide sibling
# (its headless runner).
echo "== curlxt: tools/test-script-vectors.py =="
python3 tools/test-script-vectors.py
echo "== curlxt: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate, and so does an empty
# manifest (the release dispatch of 2026-11-14 committed all six).
echo "== curlxt: src/code/MANIFEST.sha256 =="
( cd src/code && test -s MANIFEST.sha256 && sha256sum -c --quiet MANIFEST.sha256 )
