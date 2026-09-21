#!/usr/bin/env bash
# run-gates.sh - holde-em's OWN gate list: what CI and a contributor run.
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
# CROSS-MEMBER GATE. tools/check-script-vectors.py executes the shipped
# stack through ../riptide/tools/check-demo-boot.py (the family's one boot
# runner, imported rather than copied) and checks it against
# ../riptide/tools/riptide_reference.py, the oracle - and those two load at
# import what riptide's own gates load: nostrxt's interpreter,
# ../nostrxt/tools/nostr_reference.py, and the committed coinxt binary for
# the signing paths. So this gate's siblings are riptide, nostrxt and
# coinxt, and tools/test-script-vectors.py, which drives the same gate,
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
# test-checker.py proves every rule fires in this copy). This member's extra
# idiom checker (the hold-em lineage) was RETIRED 2026-08-15: its checks
# live in this unified copy (docstring 13-21).
echo "== holde-em: static gate =="
python3 tools/check-livecodescript.py

# holde-em's pure-logic gates, in order: the docs smart-quote scan, the
# table-layout arithmetic, seven KAT mirrors of the game's pure handlers
# (evaluator, betting/settlement, shuffle, crypto protocol, transcript fold,
# card atlas, sounds), and the independent-reference fuzz (a SECOND
# evaluator/settlement implementation plus whole-game invariants - the
# backing for the member's "verified sound" claim).
echo "== holde-em: tools/check-docs.py =="
python3 tools/check-docs.py

# The game table's CONTROL geometry, re-derived from the stack source: every
# rect the builders set, bounds-checked against kHeStackRect and proved
# pairwise disjoint outside a written exemption list. The suite's
# check-stack-size.py reads one number per stack (the stack's own rect) and
# never looks at a control, so without this a seat-spot or board-Y tweak
# could push chrome below the fold with every gate green - which is exactly
# what the 720p re-layout's once-run, never-committed scratchpad script left
# unrepeatable (added 2026-08-16).
echo "== holde-em: tools/check-table-layout.py =="
python3 tools/check-table-layout.py

# The seven KAT mirrors and the fuzz, named one by one rather than globbed:
# the suite walk probed these by exact name because a *-kat.py glob would
# collide with the different --check calling convention of the siblings'
# onion-kat.py / coin-kat.py / nostr-kat.py, and a list that reads in order
# is the list a maintainer can audit.
for rel in evaluator-kat.py betting-kat.py shuffle-kat.py protocol-kat.py \
           fold-kat.py atlas-kat.py sounds-kat.py logic-fuzz.py; do
  echo "== holde-em: tools/$rel =="
  python3 "tools/$rel"
done

# The execution gate is believed only once it has been shown to FAIL: the
# fixture driver edits one defect at a time into a copy of the shipped
# script, drives the REAL gate over it and requires a failure, then drives
# the untouched copy and requires OK. It runs BEFORE the gate for the reason
# the suite's doc-status pair runs its fixtures first: a gate that has gone
# blind prints OK. Both reach riptide's runner and oracle (header).
echo "== holde-em: tools/test-script-vectors.py =="
python3 tools/test-script-vectors.py
echo "== holde-em: tools/check-script-vectors.py =="
python3 tools/check-script-vectors.py --check
