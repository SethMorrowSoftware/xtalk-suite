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
# box2dxt joined this list 2026-08-17: it has carried a CMakeLists.txt and an
# `add_test(NAME smoke ...)` since the fold, but was walked only by the
# compiler-free gate loop below - so the one thing actually covering its 376
# raw b2* exports (tests/smoke_test.c, which three places in the tree cite as
# that layer's cover) had never run here. Its Box2D comes from FetchContent,
# so the lane costs a Box2D source build; unlike sodiumxt it copies nothing
# back into src/code/, so it adds no second case to the NOTE at the top.
CMAKE_MEMBERS=(sodiumxt torrentxt enetxt datachannelxt box2dxt)

# HOW MANY COMPILER PROCESSES, and why this is not left to CMake.
# `cmake --build --parallel` with NO NUMBER passes a BARE `-j` to GNU make,
# and a bare `-j` means UNLIMITED - make starts every target whose deps are
# ready, all at once. That is invisible on a small member and fatal on
# torrentxt, which builds libtorrent from source: on 2026-08-17 the suite's
# full-build CI lane was killed at 7 minutes with exit 143 ("the runner has
# received a shutdown signal") while ~60 g++ processes compiled libtorrent and
# a torrentxt test binary simultaneously. That is an OOM, not a test failure,
# and it would have hit anyone running this script on a laptop too.
# So: bound it, by MEMORY as well as by cores, since the constraint here is
# memory (heavy Boost/template translation units run to a gigabyte or more,
# while the core count says nothing about that). Override with BUILD_JOBS=N.
#
# THE PRECEDENT WAS ALREADY IN THE TREE, which is what makes this a fix rather
# than a guess: .github/workflows/native-torrentxt.yml has always built its
# libtorrent with `--parallel ${{ matrix.build_jobs || '4' }}`. The lane that
# builds this dependency every day had learned to cap it; the full walk was the
# one path that had not, and it is the only one that died. (One instance
# remains, knowingly: native-sodiumxt.yml passes a bare `-j`. It survives
# because libsodium is small - a handful of C files, not a Boost-heavy C++
# tree - so it is recorded here rather than changed inside a CI fix.)
if [ -z "${BUILD_JOBS:-}" ]; then
  _cpus="$(nproc 2>/dev/null || echo 2)"
  _memkb="$(awk '/MemTotal/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 4194304)"
  _memjobs="$(( _memkb / 2097152 ))"          # ~2 GiB per C++ translation unit
  [ "$_memjobs" -lt 1 ] && _memjobs=1
  if [ "$_memjobs" -lt "$_cpus" ]; then BUILD_JOBS="$_memjobs"; else BUILD_JOBS="$_cpus"; fi
fi

# Build a SUBSET of the native members. A lane that exists to settle one
# question should build what that question needs and nothing else: the
# cross-member invariants load exactly sodiumxt/build/sodiumxt.so and
# torrentxt/build/torrentxt.so, so building enetxt, datachannelxt, box2dxt and
# coinxt for them is runner time spent proving nothing. Empty = build them all,
# which is what a local full walk and the release lane both want.
SUITE_ONLY_MEMBERS="${SUITE_ONLY_MEMBERS:-}"
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
  if [ -f "$m/tools/nostr-kat.py" ]; then
    echo "== $m: tools/nostr-kat.py --check =="
    ( cd "$m" && python3 tools/nostr-kat.py --check )
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
  # Embedded-Kit freshness (box2dxt): the same shape as
  # tools/sync-demo-embeds.py below - src/box2dxt-kit.livecodescript is the
  # master, and each of the six example stacks carries a verbatim copy between
  # sentinels so it stays paste-and-run. Its docstring has always said "--check exits non-zero ... so
  # CI fails until sync-embedded-kit.py is re-run", and until 2026-08-17 that
  # was a claim with no caller behind it: the whole tree held five PROSE
  # mentions of this tool and zero invocations. A drifted copy is the demo-kit
  # failure with the blast radius the other way round - one stale example runs
  # an old Kit and reports a bug that was fixed in src/ months ago.
  if [ -f "$m/tools/sync-embedded-kit.py" ]; then
    echo "== $m: tools/sync-embedded-kit.py --check =="
    ( cd "$m" && python3 tools/sync-embedded-kit.py --check )
  fi
  # The platformer's level geometry (box2dxt). Read what this one IS before
  # reading a green run as an endorsement: its own docstring calls the findings
  # ADVISORY and "not a CI gate" - some beats deliberately sit a coin in an
  # enemy's path - and main() prints the finding count without ever setting a
  # non-zero exit. So what this probe actually holds is narrower than it looks:
  # that the auditor can still PARSE the demo it audits. That is worth holding,
  # because the parser reads the level builders by regex and a restructured
  # pfL3Scene would leave the tool silently auditing nothing at all - the
  # standard rot of a tool nobody runs. The findings themselves print into the
  # build log for a human to read; nobody should treat "0 finding(s)" here as a
  # layout gate.
  # The .lcb <-> C signature gate: 370 `binds to "c:box2dxt>SYM!cdecl"`
  # declarations against 370 LC_API definitions, comparing return type, arity
  # and every parameter type. A mismatch here is not a compile error anywhere -
  # it surfaces at RUN TIME on an engine, as a marshalling fault in a call that
  # looks right in both files. Sub-second, and green today.
  # Do the docs and the shipped handler set still agree? A `cx*` name in the
  # docs that no handler defines costs a reader a `handler not found`, and every
  # other gate stays green about it: SPEC.md named `cxSeckeyValidate` where the
  # shipped handler is `cxSeckeyIsValid`, in the one document that member calls
  # its source of truth. Holds BOTH directions - a documented name nothing
  # defines, and a shipped public handler the api-reference never names - with
  # the stale-excuse ratchet from tools/check-suite-coverage.py, so a rename
  # cannot leave a permanent exemption behind it.
  if [ -f "$m/tools/check-doc-handlers.py" ]; then
    echo "== $m: tools/check-doc-handlers.py =="
    ( cd "$m" && python3 tools/check-doc-handlers.py --check )
  fi
  if [ -f "$m/tools/check-lcb-signatures.py" ]; then
    echo "== $m: tools/check-lcb-signatures.py =="
    ( cd "$m" && python3 tools/check-lcb-signatures.py )
  fi
  if [ -f "$m/tools/audit-platformer.py" ]; then
    echo "== $m: tools/audit-platformer.py (advisory; gates only that it still parses) =="
    ( cd "$m" && python3 tools/audit-platformer.py )
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
  # Committed-extension COMPLETENESS (box2dxt): --check lists src/code/ and
  # exits non-zero if any of the five platform slots is empty. That is a
  # different question from the MANIFEST below, which proves the blobs that ARE
  # there are unchanged and says nothing about a missing one - and a missing
  # slot is the failure a maintainer meets at run time on exactly the one
  # platform they do not develop on, as "the extension will not load". Probed by
  # CAPABILITY rather than by name, which is the one place the *-kat.py block's
  # probe-by-exact-name trick does not work: six members ship a file with this
  # exact name and only box2dxt's takes --check (enetxt's takes
  # --platform-id/--build-dir and would fail on the flag). Probing the flag
  # keeps the file's preference for lists that cover a new member with no edit
  # here - a sibling that grows a --check is covered the day it does.
  if [ -f "$m/tools/package-extension.py" ] && \
     grep -q '"--check"' "$m/tools/package-extension.py"; then
    echo "== $m: tools/package-extension.py --check =="
    ( cd "$m" && python3 tools/package-extension.py --check )
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
# Fixtures beside the gate: this one reported a confident 43/27 for months while
# measuring nothing at all in nocloud, so its three legs are proven before it
# is trusted.
if [ -f tools/test-stack-size.py ]; then
  echo "== suite: tools/test-stack-size.py =="
  python3 tools/test-stack-size.py
fi
if [ -f tools/check-stack-size.py ]; then
  echo "== suite: tools/check-stack-size.py =="
  python3 tools/check-stack-size.py
fi
if [ -f tools/check-harness-scaffold-drift.py ]; then
  echo "== suite: tools/check-harness-scaffold-drift.py =="
  python3 tools/check-harness-scaffold-drift.py
fi
# The fourth carried block: the demos' boot self-check. Registered here in the
# same change that created it, because a drift gate nobody runs is the shape
# this file's own history keeps warning about.
# Fixtures FIRST: the drift gate shipped with a dead fourth check (a substring
# test against the whole file, defeated by the block that defines the very name
# it looked for), so a gate here does not run unproven.
if [ -f tools/test-demo-selfcheck-drift.py ]; then
  echo "== suite: tools/test-demo-selfcheck-drift.py =="
  python3 tools/test-demo-selfcheck-drift.py
fi
if [ -f tools/check-demo-selfcheck-drift.py ]; then
  echo "== suite: tools/check-demo-selfcheck-drift.py =="
  python3 tools/check-demo-selfcheck-drift.py
fi
# Each demo's control list is DERIVED, not maintained: a phantom name makes the
# demo print a red FAIL on every open, which trains the operator to ignore the
# block. Four of eleven shipped with one.
if [ -f tools/check-demo-control-lists.py ]; then
  echo "== suite: tools/check-demo-control-lists.py =="
  python3 tools/check-demo-control-lists.py
fi
# One script is one compile unit, so a name declared twice does not warn - it
# takes the whole file down, at PASTE time, on an engine. Four carried blocks
# are pasted into a dozen-odd files each and only ONE of them (the embedded
# libraries) was collision-checked against its host. Fixtures first, so a
# scanner that cannot discriminate cannot pass as a clean one.
if [ -f tools/test-duplicate-declarations.py ]; then
  echo "== suite: tools/test-duplicate-declarations.py --mutate =="
  python3 tools/test-duplicate-declarations.py --mutate
fi
if [ -f tools/check-duplicate-declarations.py ]; then
  echo "== suite: tools/check-duplicate-declarations.py =="
  python3 tools/check-duplicate-declarations.py
fi
# The three C++ shims carry ONE handle table in three files, and this is the
# first gate in the suite that compares one member's NATIVE code to another's.
# The existing native gates are all vertical and single-member; the horizontal
# "are the N copies still one thing?" question had gates only on the script
# side. Suite rule 4 - a stale handle is a harmless no-op - IS this header,
# three times, so a fix landing in one copy leaves the other two members'
# stale-handle rule quietly weaker, and the symptom arrives on an engine as a
# touch of a recycled slot. Scoped to the handle table ALONE: the record codecs
# genuinely diverge per library, and docs/OPEN-DECISIONS.md D-14 stays open over
# every block this does not name.
if [ -f tools/check-shim-scaffold-drift.py ]; then
  echo "== suite: tools/check-shim-scaffold-drift.py =="
  python3 tools/check-shim-scaffold-drift.py
fi
# The committed binaries still match the source that produced them.
# MANIFEST.sha256, checked per member below, proves a blob is UNCHANGED; it
# cannot prove the blob is what the current source would BUILD - so an export
# lost in a MinGW cross-build, or an ABI bump the binary never got, passes it
# and reaches a user as a bind failure at LOAD time. No compiler and no
# binutils: stdlib struct walks over ELF and PE.
if [ -f tools/check-binary-freshness.py ]; then
  echo "== suite: tools/check-binary-freshness.py =="
  python3 tools/check-binary-freshness.py
fi
if [ -f tools/test-launcher-registry.py ]; then
  echo "== suite: tools/test-launcher-registry.py =="
  python3 tools/test-launcher-registry.py
fi
if [ -f tools/check-launcher-registry.py ]; then
  echo "== suite: tools/check-launcher-registry.py =="
  python3 tools/check-launcher-registry.py
fi
# The anchored citations in docs/ still resolve. This gate's own docstring
# records the failure it was built for: docs/OPEN-DECISIONS.md opened by
# attesting that every one of its `file:line` citations had been "re-verified
# against the tree on the compile date". That was true on the compile date and
# false a day later - a line number is a fact about a file's CURRENT shape, and
# this tree reshapes faster than its documents are re-read - so six of them had
# drifted into unrelated prose while the attestation still read as fresh. It
# re-resolves the citations that carry an ANCHOR PHRASE (text that moves WITH
# the thing it names) and deliberately only COUNTS the bare ones, because
# guessing at those produced 93 false alarms in its first draft. Run with -v:
# the brief that cites this tool claims two things of it, that it fails on an
# anchor that no longer appears AND that it prints where the anchor now lives,
# and only -v prints the second - the failure path has no line to print, since
# an anchor that has vanished has no location. -v does not change the exit code.
# Wired 2026-08-19, and until then this gate was itself the thing it exists to
# stop: a claim with no caller behind it - the same failure the
# sync-embedded-kit.py block above records for box2dxt's Kit - and the one tool
# in tools/ that no script and no workflow invoked.
if [ -f tools/check-doc-anchors.py ]; then
  echo "== suite: tools/check-doc-anchors.py -v =="
  python3 tools/check-doc-anchors.py -v
fi

# --- static gates for every member (always run) ---
# riptide, nocloud, and holde-em are not extensions but carry the same gate
# shape (script checker, golden glob, vector gate, docs style), so they ride
# the same loop.
for m in sodiumxt torrentxt enetxt datachannelxt onionxt coinxt riptide nocloud box2dxt holde-em nostrxt; do
  if [ -d "$m" ]; then run_gates "$m"; fi
done

# --- suite-level: the scripts that live at the ROOT, not inside a member ---
# tests/suite-selftest.livecodescript drives all the members from one stack, so
# it belongs to no member and no member's run_gates would ever see it. One
# member's checker covers it: the copies are byte-identical and the drift gate
# above already failed the build if they were not (this block used to run all
# seven copies in turn, back when the lineages disagreed about `switch`).
#
# WIDENED 2026-08-17, and the hole it closed was the worst-placed one in the
# tree. The member loop walks only member directories and this list read
# `tests/*` only, so the three suite-level scripts - start-here.livecodescript,
# tools/ui-kit.livecodescript and tools/harness-scaffold.livecodescript - were
# read by NO static gate at all. Rule 5 says the gate is law for script, and
# two of those three are CARRIED MASTERS, which is where a defect is worst: the
# kit is copied verbatim into 15 demos and the scaffold into 5 harnesses, so one
# bad line in a master is one bad line in fifteen pasteable files - and the
# drift gates, doing exactly their job, would hold every copy faithfully
# identical to it.
shopt -s nullglob
ROOT_SCRIPTS=(start-here.livecodescript
              tests/*.livecodescript tests/*.lcb
              tools/*.livecodescript tools/*.lcb)
shopt -u nullglob

# ONE documented exemption, and it is checked rather than assumed.
# tools/harness-scaffold.livecodescript is a TEMPLATE WITH HOLES, not a
# runnable stack: its window half reads kStWidth/kStHeight/kStTitle, which the
# block's own header instructs each ADOPTER to declare ABOVE the carried region
# (OXT resolves constants by lexical position, so they cannot live in the
# master). Run through the checker it reports three undeclared constants -
# correctly, for a file nobody pastes on its own, and unfixably, because the
# fix is to declare them in the master and the master is carried byte-identical
# into five harnesses that already declare them. tools/check-stack-size.py's
# SKIP set reached the identical conclusion about the identical three names and
# took the identical route, so this is the tree's existing answer to this
# question and not a new one. The real constants ARE gated: every adopter
# declares them and every adopter goes through its own member's checker.
#
# The exemption asserts its input still exists, the way box2dxt's fold
# mechanisms do: a renamed or deleted master must fail the build rather than
# leave a stale excuse behind that quietly exempts nothing.
SCRIPT_GATE_EXEMPT=(tools/harness-scaffold.livecodescript)
for x in "${SCRIPT_GATE_EXEMPT[@]}"; do
  if [ ! -f "$x" ]; then
    echo "build-all: static-gate exemption names $x, which does not exist -" \
         "remove the exemption or restore the file"; exit 1
  fi
done
GATED_SCRIPTS=()
# ${arr[@]+"${arr[@]}"}: the set -u-safe expansion. Plain "${arr[@]}" on an
# empty array is an unbound-variable error under `set -u`, and the "${arr[@]:-}"
# spelling quietly yields one EMPTY element - which the checker would then
# accept and silently drop, reporting OK over a shorter list than intended.
for s in ${ROOT_SCRIPTS[@]+"${ROOT_SCRIPTS[@]}"}; do
  skip=0
  for x in "${SCRIPT_GATE_EXEMPT[@]}"; do [ "$s" = "$x" ] && skip=1; done
  [ "$skip" = 1 ] || GATED_SCRIPTS+=("$s")
done

if [ ${#GATED_SCRIPTS[@]} -gt 0 ]; then
  echo "== suite: root + tests/ + tools/ under the unified static gate (sodiumxt's copy) =="
  python3 sodiumxt/tools/check-livecodescript.py "${GATED_SCRIPTS[@]}"
fi

# --- suite-level: every handler CALLED across members must actually EXIST ---
# The members call into each other by name across a boundary no compiler checks,
# and the only runtime that would catch a typo is a GUI engine we cannot run
# headless. This is the gate that would have caught the shipped example calling
# sxHashKey (a handler that never existed). It is repo-wide, so it runs once
# rather than per member.
if [ -f tools/test-handler-calls.py ]; then
  echo "== suite: tools/test-handler-calls.py =="
  python3 tools/test-handler-calls.py
fi
if [ -f tools/check-handler-calls.py ]; then
  echo "== suite: tools/check-handler-calls.py =="
  python3 tools/check-handler-calls.py
fi

# --- suite-level: the script -> .lcb boundary, argument by argument ----------
# check-handler-calls proves a called NAME exists; check-lcb-signatures proves
# the .lcb agrees with the C. Between them sat the direction that actually
# failed on an engine: a script handing a typed .lcb parameter a value it
# cannot convert. Every public .lcb parameter is typed and NONE is optional, so
# an empty value into an Integer is a hard runtime error, not a no-op - which
# is how enet-lan-chat's unguarded enHostDestroy killed its poll chain.
# Check 4 is the same boundary from the other side: a dispatched event name
# resolves through that one namespace too, so an event named identically to a
# public handler reaches the library handler instead of the app's - which is
# exactly what dcLocalDescription did.
if [ -f tools/test-lcb-call-types.py ]; then
  echo "== suite: tools/test-lcb-call-types.py --mutate =="
  python3 tools/test-lcb-call-types.py --mutate
fi
if [ -f tools/check-lcb-call-types.py ]; then
  echo "== suite: tools/check-lcb-call-types.py =="
  python3 tools/check-lcb-call-types.py
fi

# --- suite-level: a delayed message must know which stack it is on ----------
# An unqualified `field "x"` resolves against the DEFAULTSTACK, not the stack
# whose script is running. Inside openStack those are the same, which is why
# every demo's startup status line always worked; a handler arriving from
# `send ... in` has no such guarantee. enet-lan-chat's dashboard threw
# "Chunk: error in object expression" once a second, and dht-chat hid the same
# fault behind an existence guard - its status line just stopped updating.
# --- suite-level: every foreign bind against its C definition ----------------
# check-binary-freshness resolves all 636 binds against an exported SYMBOL;
# this checks the SHAPE - arity, return type, parameter types. Only box2dxt had
# such a gate before 2026-08-19, and its own (which also checks the name
# bijection) still runs in its member gates; this covers the other five.
if [ -f tools/check-lcb-signatures.py ]; then
  echo "== suite: tools/check-lcb-signatures.py =="
  python3 tools/check-lcb-signatures.py
fi

if [ -f tools/check-timer-stack-pin.py ]; then
  echo "== suite: tools/check-timer-stack-pin.py =="
  python3 tools/check-timer-stack-pin.py
fi

# --- suite-level: the unified self-test harness is BUILT, so it can go stale ---
# tests/suite-selftest.livecodescript is assembled from every member's own
# harness. If a member's tests change and nobody rebuilds, the file a maintainer
# pastes into an engine is no longer the one the sources describe - and it will
# still run, and still go green, about code that moved. Same failure and same
# gate shape as tools/sync-demo-embeds.py.
if [ -f tools/build-suite-selftest.py ]; then
  echo "== suite: tools/build-suite-selftest.py --check =="
  python3 tools/build-suite-selftest.py --check
fi

# --- suite-level: and the merge itself is structurally sound -----------------
# No compiler can see this file headlessly, so these are the checks a compiler
# would have made: no duplicate handlers, no undeclared constant (which
# LiveCodeScript turns into the literal text of its own name rather than an
# error), the core's entry points present, and the async cuts still cut.
# tests/preflight.livecodescript is the one-paste "can this machine run the
# pass at all?" stack, and its six expected-ABI numbers are READ from the C
# shims - so it goes stale at the next ABI bump exactly as the suite harness
# goes stale on a test change. --check re-derives them and re-proves the three
# invariants the generated stack depends on.
# Every demo carries the script libraries it needs, so a reader can paste one
# file and have it run - no `start using` wiring. The sources under <member>/src
# stay the single source of truth; this proves the copies inside the demos have
# not drifted from them.
# Its collision detector shipped blind once - it required the remainder of a
# declaration line to be a bare identifier, so every commented `local` was
# invisible and a duplicate `sPolling` reached an engine as a hard compile
# error. The fixtures run FIRST, and --mutate proves they still discriminate
# against the pre-fix implementation, so "the checker is clean" means the
# checker can see.
if [ -f tools/test-demo-embeds.py ]; then
  echo "== suite: tools/test-demo-embeds.py --mutate =="
  python3 tools/test-demo-embeds.py --mutate
fi
if [ -f tools/sync-demo-embeds.py ]; then
  echo "== suite: tools/sync-demo-embeds.py --check =="
  python3 tools/sync-demo-embeds.py --check
fi
if [ -f tools/build-preflight.py ]; then
  echo "== suite: tools/build-preflight.py --check =="
  python3 tools/build-preflight.py --check
fi
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
# tools/install-release-binaries.py is the one piece of code standing between a
# freshly built artifact and a committed binary, and until now NOTHING ran it
# except release-binaries.yml - the gates were silent about the tool whose whole
# job is refusing bad libraries. --selftest drives main() over throwaway bundles
# and asserts each leg: member routing, filename, architecture, the thin-Mach-O
# refusal, and both manifest legs against a temporary ROOT. Nothing in the tree
# is written.
if [ -f tools/install-release-binaries.py ]; then
  echo "== suite: tools/install-release-binaries.py --selftest =="
  python3 tools/install-release-binaries.py --selftest
fi

if [ "$GATES_ONLY" = 1 ]; then
  echo "All static gates passed."
  exit 0
fi

# --- native builds + tests ---
for m in "${CMAKE_MEMBERS[@]}"; do
  [ -d "$m" ] || continue
  if [ -n "$SUITE_ONLY_MEMBERS" ]; then
    case " $SUITE_ONLY_MEMBERS " in
      *" $m "*) ;;
      *) echo "== $m: SKIPPED (SUITE_ONLY_MEMBERS=$SUITE_ONLY_MEMBERS) =="; continue ;;
    esac
  fi
  # sodiumxt -> SODIUMXT_BUILD_TESTS etc.: without this flag no member
  # registers any ctest test, and ctest exits 0 on an empty test set, so the
  # old plain-Release walk "passed" while testing nothing. --no-tests=error
  # keeps that from ever happening silently again.
  tflag="$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')_BUILD_TESTS"
  echo "== $m: cmake configure + build + ctest ($BUILD_JOBS job(s)) =="
  cmake -S "$m" -B "$m/build" -DCMAKE_BUILD_TYPE=Release "-D${tflag}=ON"
  cmake --build "$m/build" --parallel "$BUILD_JOBS"
  ctest --test-dir "$m/build" --output-on-failure --no-tests=error || {
    echo "$m: ctest failed (or no tests were registered)"; exit 1;
  }
done

# CoinXT: the asan variant compiles the shim + vendored sources and runs the
# ASan/UBSan self-test, entirely in a temp dir (the plain `lib` variant would
# drop native/libcoinxt.so into the working tree, so the walker avoids it).
if [ -n "$SUITE_ONLY_MEMBERS" ] && case " $SUITE_ONLY_MEMBERS " in *" coinxt "*) false;; *) true;; esac; then
  echo "== coinxt: SKIPPED (SUITE_ONLY_MEMBERS=$SUITE_ONLY_MEMBERS) =="
elif [ -f coinxt/native/build.sh ]; then
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
