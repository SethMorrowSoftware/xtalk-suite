#!/usr/bin/env bash
# run-gates.sh - sodiumxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs.
#
# ONE LIST. The suite's tools/build-all.sh delegates to this script rather
# than carrying a probe-by-filename copy of it, so a gate runs in the suite
# and standalone alike - or nowhere. Any gate file added under tools/ or
# tests/ MUST be named here: the suite's tools/check-member-standalone.py
# refuses a gate file this script never names. A tool nobody invokes is the
# rot the suite root records more than once (a Kit-freshness gate that spent
# months as prose mentions and zero callers); this list is where that is kept
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

# The LiveCodeScript/LCB static gate. Every member carries a byte-identical
# copy (the suite's check-checker-drift.py holds them equal and its
# test-checker.py proves every rule fires in this copy), so a fix landing in
# one copy and not the others is a state the tree cannot quietly be in.
echo "== sodiumxt: static gate =="
python3 tools/check-livecodescript.py

# The house-style docs gate.
echo "== sodiumxt: docs-style gate =="
python3 tools/check-docs-style.py

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. It proves a blob is
# UNCHANGED, not that it still matches the source that produced it - that
# half (suite rule 5) is the suite's check-binary-freshness.py. NOTE: a full
# CMake build re-bundles the freshly built x86_64-linux binary into src/code/
# (on purpose), which differs byte-for-byte from the committed one and fails
# this gate until you `git checkout` it (nothing changed) or refresh binary +
# manifest together in the same change (the change was intentional).
echo "== sodiumxt: src/code/MANIFEST.sha256 =="
( cd src/code && sha256sum -c --quiet MANIFEST.sha256 )
