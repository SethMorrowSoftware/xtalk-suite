#!/usr/bin/env bash
# run-gates.sh - box2dxt's OWN gate list: what CI and a contributor run.
# Compiler-free: python3 and sha256sum are all it needs (tests/smoke_test.c,
# the cover for the raw b2* exports, is the CMake build's, not this list's).
#
# ONE LIST. The suite's tools/build-all.sh delegates to this script rather
# than carrying a probe-by-filename copy of it, so a gate runs in the suite
# and standalone alike - or nowhere. Any gate file added under tools/ or
# tests/ MUST be named here: the suite's tools/check-member-standalone.py
# refuses a gate file this script never names. A tool nobody invokes is the
# rot this member has already paid for once (the Kit-freshness gate below);
# this list is where it is kept out.
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
# test-checker.py proves every rule fires in this copy).
echo "== box2dxt: static gate =="
python3 tools/check-livecodescript.py

# Embedded-Kit freshness: src/box2dxt-kit.livecodescript is the master, and
# each example stack carries a verbatim copy between sentinels so it stays
# paste-and-run. Its docstring has always said "--check exits non-zero ...
# so CI fails until sync-embedded-kit.py is re-run", and until 2026-08-17
# that was a claim with no caller behind it: the whole tree held five PROSE
# mentions of this tool and zero invocations. A drifted copy is one stale
# example running an old Kit and reporting a bug that was fixed in src/
# months ago.
echo "== box2dxt: tools/sync-embedded-kit.py --check =="
python3 tools/sync-embedded-kit.py --check

# The .lcb <-> C signature gate: every `binds to "c:box2dxt>SYM!cdecl"`
# declaration against its LC_API definition, comparing return type, arity
# and every parameter type. A mismatch here is not a compile error anywhere
# - it surfaces at RUN TIME on an engine, as a marshalling fault in a call
# that looks right in both files. Sub-second.
echo "== box2dxt: tools/check-lcb-signatures.py =="
python3 tools/check-lcb-signatures.py

# The platformer's level geometry. Read what this one IS before reading a
# green run as an endorsement: its own docstring calls the findings ADVISORY
# and "not a CI gate" - some beats deliberately sit a coin in an enemy's
# path - and main() prints the finding count without ever setting a non-zero
# exit. So what this holds is narrower than it looks: that the auditor can
# still PARSE the demo it audits. That is worth holding, because the parser
# reads the level builders by regex and a restructured pfL3Scene would leave
# the tool silently auditing nothing at all - the standard rot of a tool
# nobody runs. The findings print into the log for a human to read; nobody
# should treat "0 finding(s)" here as a layout gate.
echo "== box2dxt: tools/audit-platformer.py (advisory; gates only that it still parses) =="
python3 tools/audit-platformer.py

# Committed-extension COMPLETENESS: --check lists src/code/ and exits
# non-zero if any platform slot is empty. A different question from the
# MANIFEST below, which proves the blobs that ARE there are unchanged and
# says nothing about a missing one - and a missing slot is the failure a
# maintainer meets at run time on exactly the one platform they do not
# develop on, as "the extension will not load". (Six members ship a file
# with this name and only this member's takes --check.)
echo "== box2dxt: tools/package-extension.py --check =="
python3 tools/package-extension.py --check

# Committed-binary integrity manifest: a committed blob that is unlisted or
# does not match its recorded SHA256 fails the gate. It proves a blob is
# UNCHANGED, not that it still matches the source that produced it - that
# half (suite rule 5) is the suite's check-binary-freshness.py.
echo "== box2dxt: src/code/MANIFEST.sha256 =="
( cd src/code && sha256sum -c --quiet MANIFEST.sha256 )
