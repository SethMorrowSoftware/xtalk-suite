#!/usr/bin/env bash
# run-gates.sh - riptide's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 is all it needs. check-demo-boot.py boots the whole
# shipped stack through an interpreter and takes minutes; the rest is fast.
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
# prints OK over a gate that has gone missing. The one glob is the golden
# suites, so a new golden is covered the day it lands.
#
# Runs from anywhere: every gate runs from the member root.
#
# CROSS-MEMBER GATES. Riptide is an APP over the suite, and most of what
# runs below reaches a sibling. tools/riptide_reference.py - the oracle
# behind check-selftest-vectors.py, check-script-vectors.py and
# export-protocol-vectors.py - exec-loads ../nostrxt/tools/nostr_reference.py
# at load time (the Nostr bridge's vectors are nostrxt's to pin; a copy
# would drift), and the interpreter every execution gate here runs on is
# ../nostrxt/tools/lcs-interp.py, loaded not copied. check-script-vectors.py's
# tier 2 additionally signs with the COMMITTED
# ../coinxt/src/code/x86_64-linux/coinxt.so; check-demo-boot.py imports
# check-script-vectors.py and test-demo-boot.py drives it, so the boot gates
# inherit the reach. Once each member is its own repository the sibling is
# not in this tree: each gate resolves it as ../<name> beside this checkout
# (its MEMBER name: nostrxt, coinxt), overridable with XTALK_SIBLINGS=<dir>
# (a directory holding the sibling checkouts) or XTALK_SIBLING_<NAME>=<path>
# (one sibling, e.g. XTALK_SIBLING_COINXT). The two absences differ, on
# purpose. An absent nostrxt FAILS every gate that loads the oracle or the
# interpreter - nothing runs without them - reported by the gate that needs
# it, naming the path, the repository to clone and the two variables, never
# a traceback. An absent coinxt SKIPS tier 2 loudly (it never passes
# silently; the boot's FULL profile names the same cause before its Nostr
# checks fail), and XTALK_REQUIRE_SIBLINGS=1 turns that skip into a failure
# - which is what CI wants, because a skip and a pass both exit 0. See the
# suite's docs/MEMBER-REPO-SPLIT.md.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript static gate. Every member carries a byte-identical copy
# (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy).
echo "== riptide: static gate =="
python3 tools/check-livecodescript.py

# The house-style docs gate.
echo "== riptide: docs-style gate =="
python3 tools/check-docs-style.py

# Every golden-vector suite this member ships (the protocol golden): the ONE
# glob in this file, so a member adding one is covered with no edit here.
# nullglob so an empty match runs nothing rather than handing python3 the
# literal pattern.
shopt -s nullglob
for rel in tests/*golden*.py; do
  echo "== riptide: $rel =="
  python3 "$rel"
done
shopt -u nullglob

# The OXT self-test's vectors are hand-copied literals in a .livecodescript,
# so they can drift from the oracle and from the published answers. A
# drifted expectation turns a real regression into a green run - so
# re-derive them on every push.
echo "== riptide: tools/check-selftest-vectors.py =="
python3 tools/check-selftest-vectors.py --check

# The pure-SCRIPT library, actually executed: OXT cannot run a
# .livecodescript headlessly, so the family's interpreter drives the shipped
# library against the oracle - and against the real committed coinxt in tier
# 2 (header). Riptide is the first member whose gate must REWRITE the source
# to do it (three spellings outside the modelled subset, each rewrite
# asserted to fire so it cannot go blind), and the gate found a
# negative-chunk-range bug in that shared interpreter on its first run.
echo "== riptide: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py --check

# The demo BOOT runner: executes the SHIPPED stack script's whole openStack
# chain - card builders, kit, self-check, navigation, a scripted identity
# session - through the family's interpreter over a modeled engine object
# world. Exists because on 2026-08-29 a card shipped through a fully green
# gate set and broke the whole app at openStack on a real engine, twice: no
# other gate here EXECUTES a stack script, so "all static gates passed"
# never meant "the window opens". The FIXTURES run first (the
# fixture-before-gate law): a boot runner that has gone blind reports OK,
# and the seeded defects - each drawn from the class that actually shipped
# that day - are what make the OK mean anything.
echo "== riptide: tools/test-demo-boot.py =="
python3 tools/test-demo-boot.py
echo "== riptide: tools/check-demo-boot.py =="
python3 tools/check-demo-boot.py --check

# The Riptide Protocol conformance bundle: the machine-readable golden +
# refusal vectors any-language implementations test against
# (docs/RIPTIDE-PROTOCOL.md is the prose half). --check regenerates the
# bundle from the oracle and requires the committed JSON to match
# byte-for-byte, and EXECUTES it first - every signed golden re-verifies,
# every target recomputes, every executed refusal vector refuses - so a
# bundle that stops proving what it claims fails before freshness is even
# compared.
echo "== riptide: tools/export-protocol-vectors.py --check =="
python3 tools/export-protocol-vectors.py --check
