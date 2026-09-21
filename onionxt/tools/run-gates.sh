#!/usr/bin/env bash
# run-gates.sh - onionxt's OWN gate list: what CI and a contributor run.
# Compiler-free and daemon-free: python3 is all it needs (OnionXT is pure
# script over a local Tor daemon, and nothing here talks to one - the
# live-Tor legs are the engine pass's, per the honesty convention).
#
# ONE LIST. The suite's tools/build-all.sh delegates to this script rather
# than carrying a probe-by-filename copy of it, so a gate runs in the suite
# and standalone alike - or nowhere. Any gate file added under tools/ or
# tests/ MUST be named here: the suite's tools/check-member-standalone.py
# refuses a gate file this script never names. A tool nobody invokes is the
# rot the suite root records more than once; this list is where that is kept
# out of this member.
#
# Fail-loud, in order: set -e stops at the first gate that fails, so the last
# banner printed is the one that broke. The banners match build-all.sh's, so
# a log reads the same whichever ran the walk. Nothing is probed with
# `[ -f ]` - the member knows what it ships, and a probe that finds nothing
# prints OK over a gate that has gone missing.
#
# Runs from anywhere: every gate runs from the member root.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript static gate. Every member carries a byte-identical copy
# (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy).
echo "== onionxt: static gate =="
python3 tools/check-livecodescript.py

# The house-style docs gate.
echo "== onionxt: docs-style gate =="
python3 tools/check-docs-style.py

# Known-answer-vector harness, pure python: OnionXT adds no cryptography of
# its own, so this is a reference cross-check of the "seed -> .onion"
# determinism claim (the script base32, the address<->key mapping, the
# seed->ed25519 steps) against fixed vectors - not a second implementation
# that ships. --check runs the self-test and exits non-zero on any failure.
echo "== onionxt: tools/onion-kat.py --check =="
python3 tools/onion-kat.py --check

# The OXT self-test's vectors are hand-copied literals in a .livecodescript,
# so they can drift from the published answers. A drifted expectation turns a
# real regression into a green run - so re-derive them on every push.
echo "== onionxt: tools/check-selftest-vectors.py =="
python3 tools/check-selftest-vectors.py --check
