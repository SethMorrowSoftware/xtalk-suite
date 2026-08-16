#!/usr/bin/env bash
# build-all.sh - configure, build, and test every buildable suite member.
#
# The suite is a set of independent extensions, each with its own build system;
# this is a convenience walker, not a unified build. It is intentionally simple
# and fail-loud: the first member that fails stops the run with a non-zero
# exit, so CI and humans both see exactly what broke.
#
# Usage:
#   tools/build-all.sh              # Release build + native tests for every member
#   tools/build-all.sh --gates      # static gates only (fast; python3, plus a C
#                                   # compiler for coinxt's KAT harness)
#
# Build under gcc with sanitizers while iterating on a shim (see each member's
# CLAUDE.md / docs/building.md); this walker does a plain Release build.
#
# NOTE: a full build re-bundles sodiumxt's freshly built x86_64-linux binary
# into sodiumxt/src/code/ (its CMake does this on purpose), which will differ
# byte-for-byte from the committed one and fail the MANIFEST gate until you
# either `git checkout` it (nothing changed) or refresh binary + manifest
# together in the same change (suite rule 5, when the change is intentional).

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

GATES_ONLY=0
[ "${1:-}" = "--gates" ] && GATES_ONLY=1

# Members that carry a CMake build (a native shim to compile). Each gates its
# ctest registration behind <MEMBER>_BUILD_TESTS, so the walker turns that on.
CMAKE_MEMBERS=(sodiumxt torrentxt enetxt datachannelxt)
# CoinXT builds via coinxt/native/build.sh; OnionXT is pure script (nothing to
# compile).

run_gates() {
  local m="$1" rel
  # The LiveCodeScript/LCB static gate (every member carries it).
  if [ -f "$m/tools/check-livecodescript.py" ]; then
    echo "== $m: static gate =="
    ( cd "$m" && python3 tools/check-livecodescript.py )
  fi
  # The house-style docs gate, where a member ships one (onionxt, coinxt).
  if [ -f "$m/tools/check-docs-style.py" ]; then
    echo "== $m: docs-style gate =="
    ( cd "$m" && python3 tools/check-docs-style.py )
  fi
  # Every golden-vector suite the member ships (wire formats, BEP44, the file
  # server, ...) - glob, so a member adding one is covered with no edit here.
  for rel in "$m"/tests/*golden*.py; do
    if [ -f "$rel" ]; then
      echo "== $m: ${rel#"$m"/} =="
      ( cd "$m" && python3 "${rel#"$m"/}" )
    fi
  done
  # Record-registry sync (shim header <-> .lcb constants).
  if [ -f "$m/tools/check-record-registry.py" ]; then
    echo "== $m: tools/check-record-registry.py =="
    ( cd "$m" && python3 tools/check-record-registry.py )
  fi
  # Known-answer-vector harnesses: onionxt's is pure python; coinxt's builds
  # the shim from source in a temp dir and drives it via ctypes.
  if [ -f "$m/tools/onion-kat.py" ]; then
    echo "== $m: tools/onion-kat.py --check =="
    ( cd "$m" && python3 tools/onion-kat.py --check )
  fi
  if [ -f "$m/tools/coin-kat.py" ]; then
    echo "== $m: tools/coin-kat.py --check =="
    ( cd "$m" && python3 tools/coin-kat.py --check )
  fi
  # holde-em's pure-logic gates: the docs smart-quote scan, the table-layout
  # arithmetic, seven KAT mirrors of the game's pure handlers (evaluator,
  # betting/settlement, shuffle, crypto protocol, transcript fold, card
  # atlas, sounds), and the independent-reference fuzz (a SECOND
  # evaluator/settlement implementation plus whole-game invariants - the
  # backing for the member's "verified sound" claim). The member's extra
  # idiom checker (the hold-em lineage) was RETIRED 2026-08-15: its checks
  # live in the unified check-livecodescript.py (docstring 13-21), which
  # already ran above.
  # Probed by exact name, not a glob: the *-kat.py names would otherwise
  # collide with the different --check calling convention of
  # onion-kat.py/coin-kat.py above.
  if [ -f "$m/tools/check-docs.py" ]; then
    echo "== $m: tools/check-docs.py =="
    ( cd "$m" && python3 tools/check-docs.py )
  fi
  # The game table's CONTROL geometry, re-derived from the stack source:
  # every rect the builders set, bounds-checked against kHeStackRect and
  # proved pairwise disjoint outside a written exemption list. The suite's
  # check-stack-size.py reads one number per stack (the stack's own rect)
  # and never looks at a control, so without this a seat-spot or board-Y
  # tweak could push chrome below the fold with every gate green - which is
  # exactly what the 720p re-layout's once-run, never-committed scratchpad
  # script left unrepeatable (added 2026-08-16).
  if [ -f "$m/tools/check-table-layout.py" ]; then
    echo "== $m: tools/check-table-layout.py =="
    ( cd "$m" && python3 tools/check-table-layout.py )
  fi
  for rel in evaluator-kat.py betting-kat.py shuffle-kat.py protocol-kat.py \
             fold-kat.py atlas-kat.py sounds-kat.py logic-fuzz.py; do
    if [ -f "$m/tools/$rel" ]; then
      echo "== $m: tools/$rel =="
      ( cd "$m" && python3 "tools/$rel" )
    fi
  done
  # The OXT self-test's vectors are hand-copied literals in a .livecodescript,
  # so they can drift from the shim and from the published answers. A drifted
  # expectation turns a real regression into a green run, which in a money
  # library is the worst possible failure mode - so re-derive them on every
  # push. Needs no compiler, unlike coin-kat.py above.
  if [ -f "$m/tools/check-selftest-vectors.py" ]; then
    echo "== $m: tools/check-selftest-vectors.py =="
    ( cd "$m" && python3 tools/check-selftest-vectors.py --check )
  fi

  # The pure-SCRIPT encoding layer, actually executed. OXT cannot run a
  # .livecodescript headlessly, so coinxt carries a small interpreter for the
  # subset its encoders are written in and drives the real file against the
  # published BIP-173 / BIP-350 / EIP-55 / RLP vectors. It is an approximation
  # of the engine and does not replace the on-engine pass; what it catches is a
  # wrong alphabet or an inverted checksum, which on this surface would produce
  # a valid-looking WRONG address. Slow by nature (every bit of the bech32
  # checksum is interpreted arithmetic), so it runs after the fast gates.
  if [ -f "$m/tools/check-script-vectors.py" ]; then
    echo "== $m: tools/check-script-vectors.py =="
    ( cd "$m" && python3 tools/check-script-vectors.py --check )
  fi
  # Generated-standalone freshness (onionxt): the committed standalones must
  # match what the generator would emit from the current sources.
  if [ -f "$m/tools/build-standalone.py" ]; then
    echo "== $m: tools/build-standalone.py --check =="
    ( cd "$m" && python3 tools/build-standalone.py --check )
  fi
  # Committed-binary FRESHNESS (distinct from the manifests below, which prove a
  # committed blob is unchanged but say nothing about whether it still matches
  # the source). This is the automated half of suite rule 5: a shim that gained,
  # lost, or renamed an export, or bumped its ABI, without its committed library
  # being rebuilt in the same change.
  if [ -f "$m/tools/check-binary-freshness.py" ]; then
    echo "== $m: tools/check-binary-freshness.py =="
    ( cd "$m" && python3 tools/check-binary-freshness.py )
  fi
  # Committed-binary / vendored-source integrity manifests: a committed blob
  # that is unlisted or does not match its recorded SHA256 fails the gate.
  if [ -f "$m/src/code/MANIFEST.sha256" ]; then
    echo "== $m: src/code/MANIFEST.sha256 =="
    ( cd "$m/src/code" && sha256sum -c --quiet MANIFEST.sha256 )
  fi
  if [ -f "$m/native/MANIFEST.sha256" ]; then
    echo "== $m: native/MANIFEST.sha256 =="
    ( cd "$m/native" && sha256sum -c --quiet MANIFEST.sha256 )
  fi
}

# --- suite-level: the copied tools have not drifted, and the checker works ---
# Each member carries its own copy of check-livecodescript.py (and, where it
# has docs gates, check-docs-style.py) so it stays self-contained standalone.
# The copies are UNIFIED and byte-identical; the drift gate fails the build the
# moment a fix lands in one copy and not the others (the exact failure that
# once left sodiumxt's copy unable to parse `switch` while its siblings could).
# The fixture tests then prove every rule in every member's copy actually
# fires - and does NOT fire on the neighbouring legal form - so "the checker
# refuses X" stays a tested claim rather than an attested one. Both run BEFORE
# the member loop: a drifted or broken checker makes every downstream green
# meaningless.
if [ -f tools/check-checker-drift.py ]; then
  echo "== suite: tools/check-checker-drift.py =="
  python3 tools/check-checker-drift.py
fi
if [ -f tools/test-checker.py ]; then
  echo "== suite: tools/test-checker.py =="
  python3 tools/test-checker.py
fi
if [ -f tools/check-ui-kit-drift.py ]; then
  echo "== suite: tools/check-ui-kit-drift.py =="
  python3 tools/check-ui-kit-drift.py
fi
if [ -f tools/check-stack-size.py ]; then
  echo "== suite: tools/check-stack-size.py =="
  python3 tools/check-stack-size.py
fi
if [ -f tools/check-harness-scaffold-drift.py ]; then
  echo "== suite: tools/check-harness-scaffold-drift.py =="
  python3 tools/check-harness-scaffold-drift.py
fi
if [ -f tools/check-launcher-registry.py ]; then
  echo "== suite: tools/check-launcher-registry.py =="
  python3 tools/check-launcher-registry.py
fi

# --- static gates for every member (always run) ---
# riptide, nocloud, and holde-em are not extensions but carry the same gate
# shape (script checker, golden glob, vector gate, docs style), so they ride
# the same loop.
for m in sodiumxt torrentxt enetxt datachannelxt onionxt coinxt riptide nocloud box2dxt holde-em; do
  if [ -d "$m" ]; then run_gates "$m"; fi
done

# --- suite-level: the scripts that live at the ROOT, not inside a member ---
# tests/suite-selftest.livecodescript drives all the members from one stack, so
# it belongs to no member and no member's run_gates would ever see it. One
# member's checker covers it: the copies are byte-identical and the drift gate
# above already failed the build if they were not (this block used to run all
# seven copies in turn, back when the lineages disagreed about `switch`).
shopt -s nullglob
ROOT_SCRIPTS=(tests/*.livecodescript tests/*.lcb)
shopt -u nullglob
if [ ${#ROOT_SCRIPTS[@]} -gt 0 ]; then
  echo "== suite: tests/ under the unified static gate (sodiumxt's copy) =="
  python3 sodiumxt/tools/check-livecodescript.py "${ROOT_SCRIPTS[@]}"
fi

# --- suite-level: every handler CALLED across members must actually EXIST ---
# The members call into each other by name across a boundary no compiler checks,
# and the only runtime that would catch a typo is a GUI engine we cannot run
# headless. This is the gate that would have caught the shipped example calling
# sxHashKey (a handler that never existed). It is repo-wide, so it runs once
# rather than per member.
if [ -f tools/check-handler-calls.py ]; then
  echo "== suite: tools/check-handler-calls.py =="
  python3 tools/check-handler-calls.py
fi

# --- suite-level: the unified self-test harness is BUILT, so it can go stale ---
# tests/suite-selftest.livecodescript is assembled from every member's own
# harness. If a member's tests change and nobody rebuilds, the file a maintainer
# pastes into an engine is no longer the one the sources describe - and it will
# still run, and still go green, about code that moved. Same failure and same
# gate shape as onionxt's build-standalone.py.
if [ -f tools/build-suite-selftest.py ]; then
  echo "== suite: tools/build-suite-selftest.py --check =="
  python3 tools/build-suite-selftest.py --check
fi

# --- suite-level: and the merge itself is structurally sound -----------------
# No compiler can see this file headlessly, so these are the checks a compiler
# would have made: no duplicate handlers, no undeclared constant (which
# LiveCodeScript turns into the literal text of its own name rather than an
# error), the core's entry points present, and the async cuts still cut.
if [ -f tools/check-suite-selftest.py ]; then
  echo "== suite: tools/check-suite-selftest.py =="
  python3 tools/check-suite-selftest.py
fi

# --- suite-level: and it actually reaches the suite --------------------------
# The two gates above prove the pasteable harness is CURRENT and STRUCTURALLY
# SOUND. Neither one looks at whether it covers anything: a member could ship a
# new public handler, never test it, and both would stay green about a harness
# that does not touch the new code. This is the gate that asks.
if [ -f tools/check-suite-coverage.py ]; then
  echo "== suite: tools/check-suite-coverage.py =="
  python3 tools/check-suite-coverage.py --check
fi

if [ "$GATES_ONLY" = 1 ]; then
  echo "All static gates passed."
  exit 0
fi

# --- native builds + tests ---
for m in "${CMAKE_MEMBERS[@]}"; do
  [ -d "$m" ] || continue
  # sodiumxt -> SODIUMXT_BUILD_TESTS etc.: without this flag no member
  # registers any ctest test, and ctest exits 0 on an empty test set, so the
  # old plain-Release walk "passed" while testing nothing. --no-tests=error
  # keeps that from ever happening silently again.
  tflag="$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')_BUILD_TESTS"
  echo "== $m: cmake configure + build + ctest =="
  cmake -S "$m" -B "$m/build" -DCMAKE_BUILD_TYPE=Release "-D${tflag}=ON"
  cmake --build "$m/build" --parallel
  ctest --test-dir "$m/build" --output-on-failure --no-tests=error || {
    echo "$m: ctest failed (or no tests were registered)"; exit 1;
  }
done

# CoinXT: the asan variant compiles the shim + vendored sources and runs the
# ASan/UBSan self-test, entirely in a temp dir (the plain `lib` variant would
# drop native/libcoinxt.so into the working tree, so the walker avoids it).
if [ -f coinxt/native/build.sh ]; then
  echo "== coinxt: native/build.sh asan (build + self-test) =="
  ( cd coinxt && sh native/build.sh asan )
else
  echo "coinxt/native/build.sh missing"; exit 1
fi

# --- suite-level: the invariants that span two members --------------------
# Runs HERE, not in run_gates, because it drives the shims the loop above just
# built. These are the claims tests/suite-selftest.livecodescript makes from
# script and cannot settle without an engine - but most of them are questions
# about two C libraries, and two C libraries are exactly what we have.
if [ -f tests/cross-member-test.py ]; then
  echo "== suite: tests/cross-member-test.py =="
  python3 tests/cross-member-test.py
fi

echo "build-all: every buildable member completed."
