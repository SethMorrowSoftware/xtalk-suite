#!/usr/bin/env bash
# run-gates.sh - nostrxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 is all it needs.
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
#
# CROSS-MEMBER GATES. tools/check-script-vectors.py has two tiers, and tier
# 2 (the COMPOSED vectors: event ids, signatures, NIP-44 payloads) feeds the
# script's cx*/sx* calls from the COMMITTED sibling libraries - coinxt's and
# sodiumxt's x86_64-linux binaries - because NostrXT adds no cryptography of
# its own and a tier that stubbed those calls would prove nothing about the
# composition. tools/test-script-vectors.py drives that same gate, so it
# inherits the reach. Once each member is its own repository the sibling is
# not in this tree: the gate resolves it as ../<name> beside this checkout,
# overridable with XTALK_SIBLINGS=<dir> (a directory holding the sibling
# checkouts) or XTALK_SIBLING_<NAME>=<path> (one sibling, e.g.
# XTALK_SIBLING_COINXT). A sibling that is absent SKIPS tier 2 loudly - it
# never passes silently - and XTALK_REQUIRE_SIBLINGS=1 turns that skip into
# a failure, which is what CI wants, because a skip and a pass both exit 0.
# See the suite's docs/MEMBER-REPO-SPLIT.md.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript static gate. Every member carries a byte-identical copy
# (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy).
echo "== nostrxt: static gate =="
python3 tools/check-livecodescript.py

# The house-style docs gate.
echo "== nostrxt: docs-style gate =="
python3 tools/check-docs-style.py

# Known-answer-vector harness, pure python: sweeps the FULL published vector
# sets (NIP-01 canonical JSON, NIP-19 bech32/TLV, the NIP-44 key schedule
# and padding, RFC 6455 client framing) through tools/nostr_reference.py,
# the independent oracle, and prints the constants the member harness pins.
# --check sweeps everything and exits non-zero on failure.
echo "== nostrxt: tools/nostr-kat.py --check =="
python3 tools/nostr-kat.py --check

# The OXT self-test's vectors are hand-copied literals in a .livecodescript,
# so they can drift from the oracle and from the published answers. A
# drifted expectation turns a real regression into a green run - so
# re-derive them on every push.
echo "== nostrxt: tools/check-selftest-vectors.py =="
python3 tools/check-selftest-vectors.py --check

# The pure-SCRIPT layer, actually executed: OXT cannot run a .livecodescript
# headlessly, so the family's interpreter (tools/lcs-interp.py) drives the
# real shipped file against the published vectors - tier 1 alone, tier 2
# with the sibling libraries (header). A gate is believed only once it has
# been shown to FAIL, so the fixture driver runs FIRST: it edits one defect
# at a time into a copy of the shipped script, drives the REAL gate over it
# and requires a failure, then drives the untouched copy and requires OK. A
# gate that has gone blind prints OK.
echo "== nostrxt: tools/test-script-vectors.py =="
python3 tools/test-script-vectors.py
echo "== nostrxt: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py --check

# Do the docs and the shipped handler set still agree? A documented name no
# handler defines costs a reader a `handler not found` while every other
# gate stays green about it. Holds BOTH directions - a documented name
# nothing defines, and a shipped public handler the api-reference never
# names - with a stale-excuse ratchet, so a rename cannot leave a permanent
# exemption behind it.
echo "== nostrxt: tools/check-doc-handlers.py =="
python3 tools/check-doc-handlers.py --check
