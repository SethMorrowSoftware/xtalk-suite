#!/usr/bin/env python3
"""check-shim-scaffold-drift.py - the three C++ shims' HANDLE TABLE is ONE
implementation living in three files, and this gate proves it still is.

SCOPE FIRST, BECAUSE THE SCOPE IS THE POINT. This compares exactly one block:
`<pfx>_handle_table.h` in torrentxt, enetxt and datachannelxt. It says nothing
about the record codecs, the exception-firewall macros, the out-buffer helpers
or the poll-drain queues, and it must not be read as saying anything about
them. `docs/OPEN-DECISIONS.md` D-14 is an OPEN OWNER DECISION over that wider
scaffolding, with three live options - execute the `oxtkit/` extraction, retire
the plan item, or add a read-only cross-member report - and this file is
carefully none of them:

  * it moves no code, so "execute now" is exactly as available as it was;
  * it declares nothing un-unifiable and nothing worth unifying, so "retire"
    stays open, now with one measured fact on the record instead of an
    estimate;
  * it IS a gate rather than a report, but over the ONE block that was already
    measured identical - a strict subset of the middle path's
    "genuinely-identical blocks", with no opinion on any block it does not
    name.

D-14's reasoning says verbatim that the shim scaffolding "must NOT be
byte-identical ... so byte-unification is not even the right goal". Re-measured
2026-08-17, that is TRUE of the record codecs - `btx_record.h` / `enx_record.h`
/ `dcx_record.h` normalise to 275 / 198 / 202 code lines over three different
field registries, and every one of those divergences is a real per-library
design - and FALSE of the handle table, which normalises to 89 code lines in
all three members and to ONE digest. Both halves were measured before this file
was written; the gate covers only the half that is one implementation.

WHY THIS BLOCK IS THE ONE WORTH GATING. Suite rule 4 - "generation-tagged
integer handles, validated before use - a stale handle is a harmless no-op" -
is not a convention here, it is literally this file, three times. The rule
lives in `slot_of`'s `handle <= 0` and `idx >= slots_.size()` guards, in the
`gen == 0 -> 1` invariant that keeps generation 0 from ever naming a live slot,
in `free()`'s `GEN_MAX` wrap (which is what makes a freed handle stale rather
than merely unlucky) and in `free()`'s idempotence. A fix to any of those that
lands in ONE copy leaves the other two members' stale-handle rule quietly
weaker, and the symptom arrives where this suite's expensive bugs always
arrive: on an engine, on a user's machine, as a touch of a RECYCLED slot -
which is precisely the outcome rule 4 exists to make impossible.

WHAT CLASS THIS RETIRES - stated narrowly, because the wide version is false.
It is NOT true that no gate in this suite reads native code: three members'
`tools/check-record-registry.py` parse their own `<pfx>_record.h` enums against
their `.lcb` constants, `box2dxt/tools/check-lcb-signatures.py` parses
`src/box2d_lc.c` against 370 `foreign handler` declarations, and
`tools/check-binary-freshness.py` parses every member's shim for its source
oracle. What is true is that every one of those is VERTICAL and single-member:
header against `.lcb`, source against committed binary. Nothing in the suite
has ever compared one member's native code to another member's. The three
gates that do ask that HORIZONTAL question - `check-checker-drift.py`,
`check-ui-kit-drift.py`, `check-harness-scaffold-drift.py` - are all script and
docs. This closes the native corner of that hole for one block.

The failure class is the one the suite already paid for: on 2026-08-12 the
per-member copies of `check-livecodescript.py` had diverged, sodiumxt's could
not parse `switch`, and nobody found out until the fold put enetxt's dispatcher
in front of the one copy that could not read it. A fix applied to one copy and
not the others is invisible from inside that copy - every member's own tests
pass, because each tests its own copy - and stays invisible until another
member's code meets the un-fixed one. That is exactly the shape a shared header
carried three ways has, minus the fold that surfaced it.

WHAT IS COMPARED, AND WHAT IS NORMALISED AWAY. Code only:

  1. Comments are stripped (`//` and block, string- and char-literal aware).
     This is deliberate and is the second half of the scoping: the three
     headers' comments legitimately DIVERGE and should - btx's names libtorrent
     and the torrent enumeration, enx's says ENet is threadless, dcx's says
     libdatachannel fires callbacks from its own threads and that the shim
     guards every access with its state mutex. Those paragraphs are the
     per-library knowledge D-14 is protecting. A gate that demanded them
     identical would be demanding the wrong thing, so this one does not read
     them at all.
  2. Blank lines are dropped, leading/trailing whitespace stripped, internal
     whitespace runs collapsed - so a reindent is not reported as drift.
  3. Each file's OWN prefix is normalised: `btx` -> `PFX`, `BTX_` -> `PFXU_`
     in torrentxt's copy, and so on. ONLY its own, never all three: a copy that
     picked up a SIBLING's prefix by a bad paste (`#include "btx_abi.h"` inside
     `enx_handle_table.h`) survives normalisation and shows up as a diff, which
     is the whole reason not to write the lazier three-way substitution.

The normalised bodies must then be byte-identical, all three.

ANTI-VACUITY, BECAUSE A GATE THAT CANNOT FAIL IS WORSE THAN NO GATE (this
repo's own lesson, from coinxt's constant gate reporting the constants it had
PARSED as the ones it had CHECKED). Three empty strings are byte-identical, so
before comparing anything this gate asserts each normalised body still is a
handle table: at least MIN_CODE_LINES lines, and every token in ANCHORS
present - including `namespace PFX {`, which fails if prefix normalisation
silently stopped running. It FAILS on a body that does not look like one
rather than falling back, the same rule `check-suite-coverage.py` applies to a
harness with no spans to cut. And it refuses an UNREGISTERED carrier: a fourth
`*_handle_table.h` appearing under any member's `src/` fails the build until it
is either added to CARRIERS or given a written reason in NOT_COMPARED, so a new
C++ wrap cannot copy this header and start drifting on day one.

    python3 tools/check-shim-scaffold-drift.py           # the gate
    python3 tools/check-shim-scaffold-drift.py --show    # dump normalised form

Exit 0 = one implementation, three files. Exit 1 = drift, or a carrier that no
longer looks like a handle table, or an unregistered one.
"""
import difflib
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (member, path relative to the member, the member's native prefix). The
# prefix is lowercase; its uppercase form is derived, so the two spellings
# cannot drift apart in this registry either.
CARRIERS = [
    ("torrentxt",     "src/btx_handle_table.h", "btx"),
    ("enetxt",        "src/enx_handle_table.h", "enx"),
    ("datachannelxt", "src/dcx_handle_table.h", "dcx"),
]

# Native scaffolding this gate deliberately does NOT compare, with the reason
# for each. This list is documentation with a job: it is what keeps a reader
# (or a later agent) from mistaking a green line here for a claim about the
# whole shim layer, and it is where the D-14 options stay open. Nothing here is
# checked - measurements are dated because they will age.
NOT_COMPARED = {
    "the record codecs (btx_record.h / enx_record.h / dcx_record.h)":
        "three different field registries - 275 / 198 / 202 normalised code "
        "lines measured 2026-08-17. Genuinely divergent per library, and each "
        "already has a vertical gate of its own "
        "(<member>/tools/check-record-registry.py holds its enums to the "
        ".lcb's constants). D-14 open.",
    "sodiumxt's stream handle table (src/sodium_shim.c)":
        "a different implementation, not a copy: C rather than a C++ "
        "template, a fixed slot array rather than a vector, a 14-bit "
        "generation over a 1-BASED slot index rather than 15 bits over a "
        "0-based one. Comparing it would mean unifying it first, which is "
        "D-14's 'execute' option and not this gate's call.",
    "box2dxt's DEFINE_PTR_TABLE (src/box2d_lc.c)":
        "the ancestor of the three C++ tables and also not a copy: a C macro "
        "over realloc'd parallel arrays. Same reason as sodiumxt's.",
    "the exception firewall, out-buffer helpers and poll-drain queues":
        "not measured. D-14 names them as extraction candidates and its "
        "'execute / retire / report' options all remain open over them; this "
        "gate takes no position it has not measured.",
}

# A normalised body must still LOOK like the handle table, or three identical
# nothings would pass. Every token below is load-bearing: the class itself, the
# four public operations, both halves of the bit layout, the validation helper
# that implements the stale-handle rule, and the namespace line - which is the
# one that fails if prefix normalisation quietly stopped running.
ANCHORS = (
    "namespace PFX {",
    "class HandleTable",
    "int alloc(T obj)",
    "bool free(int handle)",
    "void collect_live(",
    "size_t live_count()",
    "slot_of(int handle)",
    "SLOT_MASK",
    "GEN_MAX",
    "encode(uint32_t gen, uint32_t idx)",
    "decode_gen(int h)",
    "decode_idx(int h)",
)
MIN_CODE_LINES = 60   # measured 89 in all three on 2026-08-17


def strip_comments(text):
    """Remove C and C++ comments, leaving line structure intact.

    Literal-aware, so a `/` inside a string is not a comment and a quote inside
    a comment does not open one. Newlines inside a block comment are KEPT so a
    reported line number still means something. The one shape this misreads is
    a C++14 digit separator (`1'000`), which would read as an unterminated char
    literal - it is not in these headers, and the failure mode if it ever is
    would be a loud diff, not a silent pass.
    """
    out = []
    i, n = 0, len(text)
    state = None   # None | "line" | "block" | "str" | "char"
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state is None:
            if c == "/" and nxt == "/":
                state = "line"
                i += 2
                continue
            if c == "/" and nxt == "*":
                state = "block"
                out.append(" ")     # a comment separates tokens
                i += 2
                continue
            if c == '"':
                state = "str"
            elif c == "'":
                state = "char"
            out.append(c)
            i += 1
            continue
        if state == "line":
            if c == "\n":
                state = None
                out.append(c)
            i += 1
            continue
        if state == "block":
            if c == "*" and nxt == "/":
                state = None
                i += 2
                continue
            if c == "\n":
                out.append(c)
            i += 1
            continue
        # inside a literal: copy verbatim, honouring escapes so that `"\\"`
        # and `'\''` do not read as terminators.
        if c == "\\" and i + 1 < n:
            out.append(c)
            out.append(text[i + 1])
            i += 2
            continue
        out.append(c)
        if (state == "str" and c == '"') or (state == "char" and c == "'"):
            state = None
        i += 1
    return "".join(out)


def normalise(text, prefix):
    """Comment-free, whitespace-normalised, own-prefix-normalised code lines."""
    body = strip_comments(text)
    # ONLY this file's own prefix (see the module docstring): a stray sibling
    # prefix must survive normalisation so that it shows up as drift.
    body = re.sub(r"\b%s_" % prefix.upper(), "PFXU_", body)
    body = re.sub(r"\b%s_" % prefix, "PFX_", body)
    body = re.sub(r"\b%s\b" % prefix, "PFX", body)
    lines = []
    for raw in body.splitlines():
        line = " ".join(raw.split())     # collapse + strip in one move
        if line:
            lines.append(line)
    return "\n".join(lines) + "\n"


def discover_unregistered(registered):
    """Any other `*_handle_table.h` under a member's src/ is a new carrier.

    An exemption list goes stale; a discovery rule does not. A fourth C++ wrap
    that copies this header gets exactly one build failure telling it to
    register, rather than a year of silent drift.
    """
    found = []
    for member in sorted(os.listdir(ROOT)):
        src = os.path.join(ROOT, member, "src")
        if not os.path.isdir(src):
            continue
        for name in sorted(os.listdir(src)):
            if not name.endswith("_handle_table.h"):
                continue
            rel = "%s/src/%s" % (member, name)
            if rel not in registered:
                found.append(rel)
    return found


def main(argv):
    show = "--show" in argv[1:]
    failures = []
    bodies = {}          # member -> normalised text
    stats = {}           # member -> (total lines, code lines)

    registered = set()
    for member, rel, prefix in CARRIERS:
        registered.add("%s/%s" % (member, rel))
        path = os.path.join(ROOT, member, rel)
        if not os.path.exists(path):
            failures.append("%s/%s: MISSING - it is in CARRIERS, so either the "
                            "file moved or the member stopped carrying a "
                            "handle table; update the registry in the same "
                            "change" % (member, rel))
            continue
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()
        body = normalise(raw, prefix)
        bodies[member] = body
        stats[member] = (len(raw.splitlines()), len(body.splitlines()))

        # Anti-vacuity: prove this still IS a handle table before believing any
        # comparison over it. Fail, do not fall back.
        n_code = len(body.splitlines())
        if n_code < MIN_CODE_LINES:
            failures.append(
                "%s/%s: normalises to %d code lines, below the %d floor - the "
                "comparison below would be over something that is no longer a "
                "handle table" % (member, rel, n_code, MIN_CODE_LINES))
        missing = [a for a in ANCHORS if a not in body]
        if missing:
            failures.append(
                "%s/%s: normalised body is missing %d anchor(s): %s - either "
                "the table was rewritten (update ANCHORS in the same change) "
                "or the normaliser stopped working, and in both cases an "
                "'identical' verdict here would be worthless"
                % (member, rel, len(missing), ", ".join(repr(m)
                                                        for m in missing)))

    for rel in discover_unregistered(registered):
        failures.append(
            "%s: an UNREGISTERED handle table - add it to CARRIERS (if it is "
            "a copy of the shared one) or to NOT_COMPARED with a written "
            "reason (if it is genuinely its own implementation, as sodiumxt's "
            "and box2dxt's are)" % rel)

    # --show dumps the normalised form for a maintainer diagnosing a failure.
    # It does NOT return early: a debug flag that exits 0 before the checks run
    # is a way for a green line to mean nothing, which is the one thing this
    # file is built not to allow.
    if show:
        for member in sorted(bodies):
            print("----- %s (normalised) -----" % member)
            sys.stdout.write(bodies[member])
            print("")

    groups = {}
    for member, body in bodies.items():
        groups.setdefault(hashlib.sha256(body.encode()).hexdigest(),
                          []).append(member)
    if len(groups) > 1:
        shape = ", ".join("{%s}" % ", ".join(sorted(ms))
                          for _, ms in sorted(groups.items()))
        failures.append(
            "the handle table has DRIFTED into %d variants: %s - it is ONE "
            "implementation carried three ways (suite rule 4 lives in it), so "
            "fix one copy and carry the fix to the others in the SAME change"
            % (len(groups), shape))
        # A diff, not just the grouping: normalisation means the raw files were
        # never expected to match, so "they differ" is not by itself actionable.
        base_member = sorted(groups[sorted(groups)[0]])[0]
        for digest in sorted(groups)[1:]:
            other = sorted(groups[digest])[0]
            diff = list(difflib.unified_diff(
                bodies[base_member].splitlines(True),
                bodies[other].splitlines(True),
                fromfile="%s (normalised)" % base_member,
                tofile="%s (normalised)" % other, n=2))
            failures.append("".join(diff[:80]).rstrip("\n") or
                            "(no textual diff - check for a trailing newline)")

    if failures:
        print("check-shim-scaffold-drift: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  " + f.replace("\n", "\n  "))
        return 1

    digest = sorted(groups)[0] if groups else "-"
    print("check-shim-scaffold-drift: OK (%d copies of the handle table, one "
          "normalised digest %s)" % (len(bodies), digest[:16]))
    for member, rel, _ in CARRIERS:
        total, code = stats[member]
        print("    %-14s %-26s %3d lines, %d code (%d comment/blank, NOT "
              "compared)" % (member, rel.split("/")[-1], total, code,
                             total - code))
    print("    scope: the handle table ONLY. %d other native block(s) are "
          "deliberately not compared (see NOT_COMPARED); docs/OPEN-DECISIONS.md"
          " D-14 stays open over all of them." % len(NOT_COMPARED))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
