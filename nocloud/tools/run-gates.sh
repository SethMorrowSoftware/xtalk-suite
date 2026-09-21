#!/usr/bin/env bash
# run-gates.sh - nocloud's OWN gate list: what CI and a contributor run.
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
# prints OK over a gate that has gone missing. The one glob is the golden
# suites, so a new golden is covered the day it lands.
#
# Runs from anywhere: every gate runs from the member root.
#
# CROSS-MEMBER GATE. tools/check-script-vectors.py executes the shipped
# stack's pure layer (the file server, against tests/fileserver_golden.py)
# by IMPORTING ../riptide/tools/check-demo-boot.py - the family's one boot
# runner, reused rather than copied - and that runner loads at import what
# riptide's own gates load: nostrxt's interpreter and, through riptide's
# oracle, ../nostrxt/tools/nostr_reference.py, plus the committed coinxt
# binary for its signing paths. So this gate's siblings are riptide, nostrxt
# and coinxt, and tools/test-script-vectors.py, which drives the same gate,
# inherits the reach. Once each member is its own repository the siblings
# are not in this tree: each is resolved as ../<name> beside this checkout
# (its MEMBER name), overridable with XTALK_SIBLINGS=<dir> (a directory
# holding the sibling checkouts) or XTALK_SIBLING_<NAME>=<path> (one
# sibling, e.g. XTALK_SIBLING_RIPTIDE). An absent sibling is a FAILURE here,
# not a skip - this gate runs no reduced tier without one - reported by the
# gate that needs it, naming the path, the repository to clone and the two
# variables, never a traceback (an absent riptide is exit 2: a setup
# problem, not a vector failure). XTALK_REQUIRE_SIBLINGS=1 is the CI knob
# that turns the skip-capable gates' skips (nostrxt's tier 2, riptide's
# native signing tier) into failures, because a skip and a pass both exit
# 0; the generated gates.yml sets it for every member so one rule holds.
# See the suite's docs/MEMBER-REPO-SPLIT.md.

set -euo pipefail
cd "$(dirname "$0")/.."

# The LiveCodeScript static gate. Every member carries a byte-identical copy
# (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy).
echo "== nocloud: static gate =="
python3 tools/check-livecodescript.py

# Every golden-vector suite this member ships (the file server): the ONE
# glob in this file, so a member adding one is covered with no edit here.
# nullglob so an empty match runs nothing rather than handing python3 the
# literal pattern.
shopt -s nullglob
for rel in tests/*golden*.py; do
  echo "== nocloud: $rel =="
  python3 "$rel"
done
shopt -u nullglob

# The execution gate is believed only once it has been shown to FAIL: the
# fixture driver edits one defect at a time into a copy of the shipped
# script, drives the REAL gate over it and requires a failure, then drives
# the untouched copy and requires OK (this member, 2026-09-11). It runs
# BEFORE the gate for the reason the suite's doc-status pair runs its
# fixtures first: a gate that has gone blind prints OK. Both reach riptide's
# runner (header).
echo "== nocloud: tools/test-script-vectors.py =="
python3 tools/test-script-vectors.py
echo "== nocloud: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py --check
