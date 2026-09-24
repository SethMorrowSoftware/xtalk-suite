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
#   tools/build-all.sh --gates --installing
#                                   # the same set, forwarding --installing to
#                                   # check-binary-freshness.py. ONLY
#                                   # release-binaries.yml passes this, straight
#                                   # after tools/install-release-binaries.py has
#                                   # written new libraries into the tree: it
#                                   # lets a platform appear one run ahead of the
#                                   # `ships` row that declares it. Every other
#                                   # caller wants the strict gate.
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
# Forwarded verbatim to check-binary-freshness.py; empty for every caller that
# does not pass --installing, which is every caller but the release job.
FRESHNESS_ARGS=""
for _arg in "$@"; do
  case "$_arg" in
    --gates)      GATES_ONLY=1 ;;
    --installing) FRESHNESS_ARGS="--installing" ;;
    *) echo "build-all.sh: unknown argument '$_arg'" >&2; exit 2 ;;
  esac
done

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
#
# AND THE PER-MEMBER GATE WALK IS SCOPED BY THE SAME KNOB (2026-09-10). When
# the knob landed it scoped only the native builds, and the walk below still
# ran every member's gates first - which was invisible while those took
# minutes. coinxt's wallet gates now take hours (check-wallet-vectors ~45 min,
# then test-wallet-boot.py boots the whole wallet once per fixture, up to ~40
# min each - they run at once since 2026-09-11, see the walk below), so the
# cross-member lane spent its entire 120-minute budget inside
# coinxt's gates and was CANCELLED before its first native build began, on
# main and on every PR that touched the scope list - a lane that could not
# pass, and a gate that could not fail, since 2026-09-09. The fast --gates
# job owns every member's gates and runs them on the same push; a scoped lane
# runs the listed members' own gates (their MANIFEST, record and golden
# checks are what its build must agree with) and nothing else. The suite-level
# blocks are not scoped: they are seconds, and the harness/embeds they check
# are what the two libraries are loaded FOR.
SUITE_ONLY_MEMBERS="${SUITE_ONLY_MEMBERS:-}"
# CoinXT builds via coinxt/native/build.sh; OnionXT is pure script (nothing to
# compile).

run_gates() {
  # THE MEMBER OWNS ITS GATE LIST (2026-09-21). Until this date this function
  # was ~300 lines of `if [ -f "$m/tools/<gate>" ]` probes - the one place
  # that knew which gates each member had, and it lived in the SUITE. Every
  # member is on its way to being its own repository
  # (docs/MEMBER-REPO-SPLIT.md), and a gate list that exists only in the
  # walker of a repository the member is leaving is a gate list the member's
  # repository does not have: archivext left on this date with no runner at
  # all. So each member now carries tools/run-gates.sh - its own gates, in
  # the order this function ran them, with the why-comments this function
  # used to carry moved in beside the gate they explain (coinxt's script
  # keeps the three wallet gates running at once, for the reason recorded
  # there) - and this walker DELEGATES rather than duplicating, so the suite
  # and the standalone repository run the same list by construction. Its
  # generated .github/workflows/gates.yml runs the same script.
  #
  # Two things hold the shape. tools/check-member-standalone.py (the suite
  # block below) refuses a gate file under a member's tools/ or tests/ that
  # its run-gates.sh never names, because a gate nobody runs is this file's
  # own recorded failure mode; and a member without the script fails the
  # walk here rather than being silently walked as "no gates".
  local m="$1"
  if [ ! -f "$m/tools/run-gates.sh" ]; then
    echo "build-all: $m has no tools/run-gates.sh - every member owns its" \
         "gate list (docs/MEMBER-REPO-SPLIT.md); add one before it is walked" >&2
    exit 1
  fi
  echo "== $m: tools/run-gates.sh =="
  ( cd "$m" && bash tools/run-gates.sh )
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
# Fixtures FIRST (D-23, 2026-09-24): the suite core is a kit adopter, and the
# generated paste is skipped by EXACT PATH through GENERATED_CARRIERS - so the
# fixture proves the skip is load-bearing and path-exact (a byte copy of the
# paste anywhere else in tests/ is still flagged) before the gate is trusted.
# It mutates the core in place and plants a file in tests/: never run it
# beside another gate that reads those files.
if [ -f tools/test-ui-kit-drift.py ]; then
  echo "== suite: tools/test-ui-kit-drift.py =="
  python3 tools/test-ui-kit-drift.py
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
if [ -f tools/test-harness-scaffold-drift.py ]; then
  echo "== suite: tools/test-harness-scaffold-drift.py =="
  python3 tools/test-harness-scaffold-drift.py
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
# One name, one LIBRARY, suite-wide: the per-file gate above cannot see two
# libraries claiming the same name, and the embed tools compare only the
# combinations actually registered. This one holds the whole library corpus
# disjoint (handlers, script-level names, the engine socket messages' pass
# discipline, and the public-prefix ratchet), so ANY pair stays co-loadable
# and co-embeddable - the interoperability the suite advertises. The fixture
# test mutates real corpus files in place and restores them, proving each
# check fires the way this build runs it.
if [ -f tools/test-cross-library-names.py ]; then
  echo "== suite: tools/test-cross-library-names.py =="
  python3 tools/test-cross-library-names.py
fi
if [ -f tools/check-cross-library-names.py ]; then
  echo "== suite: tools/check-cross-library-names.py =="
  python3 tools/check-cross-library-names.py
fi
# The three C++ shims carry ONE handle table in three files, and this is the
# first gate in the suite that compares one member's NATIVE code to another's.
# The existing native gates are all vertical and single-member; the horizontal
# "are the N copies still one thing?" question had gates only on the script
# side. Suite rule 4 - a stale handle is a harmless no-op - IS this header,
# three times, so a fix landing in one copy leaves the other two members'
# stale-handle rule quietly weaker, and the symptom arrives on an engine as a
# touch of a recycled slot. Scoped to the handle table ALONE: the record codecs
# genuinely diverge per library. docs/OPEN-DECISIONS.md D-14 RETIRED the wider
# oxtkit/ extraction on 2026-08-27, because this gate already holds the one
# property it would have bought; nothing else in the shims is compared.
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
  # Unquoted on purpose: empty must expand to NO argument, not to "".
  # shellcheck disable=SC2086
  python3 tools/check-binary-freshness.py $FRESHNESS_ARGS
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

# check-doc-status-consistency.py holds the OTHER half of doc truth: an anchor
# gate proves a citation still points at something, this one proves a document
# has not been left asserting a world an engine pass already ended. The fixture
# suite runs FIRST and for the reason this file's siblings do it - a gate that
# has gone blind reports OK, so the discriminating test is what makes the OK
# mean anything. Both regressions it pins were introduced while fixing the
# other, which is why they are pinned together rather than trusted to a docstring.
if [ -f tools/test-doc-status-consistency.py ]; then
  echo "== suite: tools/test-doc-status-consistency.py =="
  python3 tools/test-doc-status-consistency.py
fi
if [ -f tools/check-doc-status-consistency.py ]; then
  echo "== suite: tools/check-doc-status-consistency.py =="
  python3 tools/check-doc-status-consistency.py
fi

# --- suite-level: every member is ready to be its own repository ------------
# Each member directory is on its way to a repository of its own
# (docs/MEMBER-REPO-SPLIT.md), and "ready" is held as a property of the tree
# rather than of one cleanup pass, the way the ui-kit gate holds "every demo
# is a kit adopter". Three generated-copy sets ride the same shape as the
# demo embeds above - a generator writes the tree, --check refuses drift:
#   sync-member-workflows.py  each member's own .github/workflows/, DERIVED
#                             from the root native-<member>.yml lanes and the
#                             member registry (the pre-suite copies had rotted
#                             216-445 diff lines behind the lanes that run);
#   sync-member-readmes.py    the "Relationship to the xTalk suite" section
#                             of every README, derived from the registry and
#                             the carried-copy registries so it cannot
#                             disagree with them;
#   check-member-standalone.py the readiness gate itself: the files a
#                             standalone repository needs, no markdown link
#                             that climbs out of the member, no tool that
#                             climbs to the suite root except through the
#                             declared sibling helper, and every gate file in
#                             tools/ or tests/ named by the member's own
#                             tools/run-gates.sh - because a gate nobody runs
#                             is this file's recorded failure shape.
# The fixture test runs first, for the reason every pair here does.
if [ -f tools/sync-member-workflows.py ]; then
  echo "== suite: tools/sync-member-workflows.py --check =="
  python3 tools/sync-member-workflows.py --check
fi
if [ -f tools/sync-member-readmes.py ]; then
  echo "== suite: tools/sync-member-readmes.py --check =="
  python3 tools/sync-member-readmes.py --check
fi
if [ -f tools/test-member-standalone.py ]; then
  echo "== suite: tools/test-member-standalone.py =="
  python3 tools/test-member-standalone.py
fi
if [ -f tools/check-member-standalone.py ]; then
  echo "== suite: tools/check-member-standalone.py =="
  python3 tools/check-member-standalone.py
fi
# The publisher itself (tools/publish-members.py) writes to eleven
# repositories that are not this one, from .github/workflows/
# publish-members.yml, so this is where its promises are held: it replays
# exactly the suite's trees, never writes a repository it was not told to
# adopt, never force-pushes (a git shim injects the mid-publish race that is
# the only place a force-push would bite), and refuses a member repository
# with commits the suite never wrote or ported. It drives the tool's real
# command line over throwaway file:// repositories - no network, a few
# seconds - and each refusal is required to leave its repository untouched.
if [ -f tools/test-publish-members.py ]; then
  echo "== suite: tools/test-publish-members.py =="
  python3 tools/test-publish-members.py
fi

# --- static gates for every member (always run) ---
# riptide, nocloud, and holde-em are not extensions but carry the same gate
# shape (script checker, golden glob, vector gate, docs style), so they ride
# the same loop.
for m in sodiumxt torrentxt enetxt datachannelxt onionxt coinxt riptide nocloud box2dxt holde-em nostrxt; do
  [ -d "$m" ] || continue
  # the same skip the native loop applies - see SUITE_ONLY_MEMBERS above for
  # why the gate walk has to honour it too
  if [ -n "$SUITE_ONLY_MEMBERS" ]; then
    case " $SUITE_ONLY_MEMBERS " in
      *" $m "*) ;;
      *) echo "== $m: gates SKIPPED (SUITE_ONLY_MEMBERS=$SUITE_ONLY_MEMBERS) =="; continue ;;
    esac
  fi
  run_gates "$m"
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

# The fixture test runs FIRST: the gate has been widened twice, each time
# because it asked the question that described the bug already found, and a
# gate that has narrowed again still prints OK. The fixtures drive the real
# main() over a tree shaped like all three delivery classes, the wall, and the
# kit, and refuse a scan that finds nothing.
if [ -f tools/test-timer-stack-pin.py ]; then
  echo "== suite: tools/test-timer-stack-pin.py =="
  python3 tools/test-timer-stack-pin.py
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
# The generator's own refusals first (D-23): a hand-written late declaration,
# a continued one, a drifted rewrite needle and an unexcused registry member
# must each stop the build, and the declaration hoist must move exactly the
# carried blocks' declarations and nothing else.
if [ -f tools/test-build-suite-selftest.py ]; then
  echo "== suite: tools/test-build-suite-selftest.py =="
  python3 tools/test-build-suite-selftest.py
fi
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
# Every check the gate makes, proven to fire on a seeded defect (one mutation
# per case, the needle present exactly once) and to stay quiet on the negative
# controls, before the gate is trusted on the committed paste.
if [ -f tools/test-suite-selftest.py ]; then
  echo "== suite: tools/test-suite-selftest.py =="
  python3 tools/test-suite-selftest.py
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

# --- suite-level: and the board RUNS -----------------------------------------
# The three gates above prove the paste is current, structurally sound and
# reaches the suite; none executes a line of it. The board (D-23) is booted
# headlessly through riptide's stack runner in an all-absent profile and
# driven through its real routes (a row's Run, Show, the filters, Copy, a
# close mid-run, the boot self-check). It settles LOGIC only - no rendering,
# parsing or message delivery - so it upgrades no honesty label. The fixture
# runs FIRST: each case seeds one defect into a scratch copy of the paste and
# requires the gate to fail on the check that names it.
if [ -f tools/test-suite-ui-boot.py ]; then
  echo "== suite: tools/test-suite-ui-boot.py =="
  python3 tools/test-suite-ui-boot.py
fi
if [ -f tools/check-suite-ui-boot.py ]; then
  echo "== suite: tools/check-suite-ui-boot.py =="
  python3 tools/check-suite-ui-boot.py
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
