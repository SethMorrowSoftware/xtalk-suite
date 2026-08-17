#!/usr/bin/env python3
"""check-doc-handlers.py - do the docs and the shipped handler set agree?

WHY THIS EXISTS. SPEC.md section 4 said, for about a year, that `cxSeckeyValidate`
checks a private key's range. No such handler has ever existed: the shipped one
is `cxSeckeyIsValid`. Sections 5.1 and 8 spelled it correctly, so the wrong name
sat in exactly one paragraph, in the document this member calls its source of
truth, and every gate in the tree stayed green about it. A reader who copied it
out got `handler not found` - the same symptom the api-reference already warns
about for `cxSha3_512`, arriving from a typo rather than from a decision.

That is a documentation defect with a code-shaped cost, and it is exactly the
class a static check can hold. Nothing here reads prose or judges whether a
handler is described WELL; it holds two mechanical properties that were both
true when this gate landed, and refuses to let either one quietly stop being
true.

WHAT IT CHECKS.

  1. DOCUMENTED -> SHIPPED. Every `cx*` token in the scanned docs is either a
     public handler, a private handler, or listed in NOT_A_HANDLER below with a
     written reason. Private counts because CLAUDE.md is an internals record and
     legitimately names internals (`cxToLower`, `cxCheckPubkey` and seven more);
     they are real names in the tree, so a rename still breaks the reference and
     is still caught.

  2. SHIPPED -> DOCUMENTED. Every public handler is named in
     docs/api-reference.md, which is the page a caller is sent to. This was
     90/90 with zero exemptions when the gate landed, so it starts as a ratchet
     rather than as a backlog: the next public handler that ships undocumented
     fails the build on the day it ships.

THE STALE-EXCUSE RATCHET, which is the half that makes an allowlist safe to
have. `tools/check-suite-coverage.py` at the suite root established the pattern
and the reason: a stale excuse is worse than none, because it reads as a
considered decision about a name that no longer means what it meant, and it
hides the next real one. Three ways an entry here goes stale, all fatal:

  - the name IS a handler now. The exemption says "documented but not shipped";
    if it ships, the exemption is a lie and the docs may now be right.
  - the name appears in no scanned doc. The prose it excused is gone, so the
    entry is inert text that will outlive everyone's memory of why it is here.
  - its `replaced_by` is no longer a public handler. A `superseded-design` entry
    justifies itself by naming what was built INSTEAD; if that name is renamed
    or deleted the justification has rotted, even though the excused name is
    untouched. This is the direction a rename actually travels, and it is why
    the field is required for that category rather than optional.

THE CATEGORIES ARE A FIXED SET, for the same reason check-suite-coverage.py's
two are: an open-ended "reason" field becomes "hard to fix" within a year.

  convention          the token is a NAMING CONVENTION example, not a call.
                      SPEC.md's house-style line, "Public API `cxPascalCase`;
                      C ABI `cnx_snake_case`", is the only one.
  deferred            specced, deliberately not built, decision recorded in the
                      docs with its cost and the condition for revisiting.
  superseded-design   a design that was NOT taken, named in a sentence whose
                      own content is that it was not taken. These live in dated
                      records (IMPLEMENTATION-PLAN.md's phase notes, SPEC.md's
                      AS BUILT marks), which the suite convention deliberately
                      keeps in their original spelling. Requires replaced_by.
  corrected           a WRONG name, quoted by the note that corrects it. This
                      category exists because the first thing this gate ever
                      caught was its own author: fixing SPEC.md's
                      `cxSeckeyValidate` to `cxSeckeyIsValid` left the dead
                      name in the AS BUILT paragraph explaining the fix, and
                      the scan does not read English. Deleting the quote would
                      make the correction unsearchable by the name people
                      actually typed, so the quote stays and carries an entry.
                      Requires replaced_by - which is the RIGHT name, so a
                      later rename of that handler fails this gate instead of
                      leaving a correction pointing at a second dead name.

WHAT IT DELIBERATELY DOES NOT CHECK. That a handler is NAMED in the
api-reference is not that it is documented well - a name inside a sentence
saying the handler does not exist would satisfy check 2, and that is not
hypothetical: it is how `cxSha3_512` reads there today (which is harmless only
because it is not shipped). Check 2 is a floor, the same shape and the same
honest limit as the suite coverage gate's: it exists so a handler cannot be
missed ENTIRELY. Depth is a human's job, and a stricter rule was measured and
rejected - requiring a `###` heading would fail 43 of the 90 handlers that are
correctly documented in tables and prose, which is a gate nobody would keep.

Usage:
  python3 tools/check-doc-handlers.py          # per-file detail
  python3 tools/check-doc-handlers.py --check  # terse: one OK line or exit 1
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

LCB = os.path.join(ROOT, "src", "coinxt.lcb")
SCRIPT = os.path.join(ROOT, "src", "coinxt.livecodescript")
API_REFERENCE = os.path.join(ROOT, "docs", "api-reference.md")

# Every doc in this member that can name a handler. Listed explicitly rather
# than globbed from the root, so ADDING a document is a deliberate act that
# shows up in a diff: a glob would silently start enforcing a new file, and
# (worse) a RENAMED file would silently stop being scanned. docs/*.md is
# globbed because that directory is by definition the member's doc set and a
# new page there must be covered from the day it lands.
DOC_FILES = [
    "README.md",
    "SPEC.md",
    "IMPLEMENTATION-PLAN.md",
    "MIGRATION.md",
    "CLAUDE.md",
    os.path.join("templates", "CLAUDE.md"),
]

# A `cx` token. The trailing class includes `_` because cxSha3_256 has one, and
# a bare `cx*` glob in prose ("the `cx*` handlers") does not match, which is
# what we want - it names no handler in particular.
CX_TOKEN = re.compile(r"\bcx[A-Za-z0-9_]+")

# name -> (category, replaced_by or None, reason)
#
# Every entry is a name that appears in this member's docs and is NOT a handler.
# Keep the reason specific enough that the next reader can decide whether it is
# still true without re-deriving it.
NOT_A_HANDLER = {
    "cxSeckeyValidate": (
        "corrected", "cxSeckeyIsValid",
        "A name SPEC.md section 4 carried for about a year and that has never "
        "existed anywhere in the tree; sections 5.1 and 8 always spelled the "
        "shipped handler correctly. Corrected 2026-08-17, and the AS BUILT "
        "paragraph that records the fix quotes the dead name on purpose, so "
        "somebody who hit `handler not found` after copying it can still find "
        "the correction by searching for what they typed. This is the defect "
        "that caused this gate to be written."),

    "cxPascalCase": (
        "convention", None,
        "SPEC.md's house-style line, 'Public API cxPascalCase; C ABI "
        "cnx_snake_case'. It is the NAMING RULE spelled in its own style, not "
        "a handler, and the whole point of writing it that way is that it "
        "reads as one. Nothing to ship, nothing to strike."),

    "cxSha3_512": (
        "deferred", None,
        "Specced since phase 1, never built, and DEFERRED by a decision "
        "recorded 2026-08-17 in SPEC.md section 1 (with README.md and "
        "docs/api-reference.md agreeing): the vendored sha3.c implements it, "
        "but exporting it costs a cnx_ export, an .lcb wrapper, an ABI bump "
        "and a four-platform binary refresh under suite rule 5, and neither "
        "chain, no caller and no suite member needs SHA3-512. The docs name it "
        "in sentences whose content is that it is a `handler not found`. When "
        "a real caller appears, ship it in a native release pass - and this "
        "entry goes stale the moment it does, which is the point."),

    # The BIP-32 accessor sketch. SPEC.md section 5.1 and IMPLEMENTATION-PLAN.md
    # phase 4 both name these three in the SAME sentence as the thing that
    # replaced them, so the prose is not wrong; it is a record of a design
    # decision. replaced_by pins that record to the tree: rename cxHdFromSeed
    # and this justification stops being checkable, so the gate says so.
    "cxHdSeckey": (
        "superseded-design", "cxHdFromSeed",
        "A BIP-32 accessor sketched in the spec and NOT built. The node is an "
        "ARRAY read by name (seckey / pubkey / chaincode / depth / index / "
        "parentfp) in exactly the order BIP-32 serializes, which is what makes "
        "cxXprv a concatenation rather than a translation. Both documents say "
        "so where they name it."),
    "cxHdPubkey": (
        "superseded-design", "cxHdFromSeed",
        "The public half of the same sketched accessor set. See cxHdSeckey."),
    "cxHdChainCode": (
        "superseded-design", "cxHdFromSeed",
        "The chaincode half of the same sketched accessor set. See cxHdSeckey."),

    # IMPLEMENTATION-PLAN.md is a DATED record, and the suite convention keeps
    # dated records in their original spelling rather than rewriting history.
    # Both of these are named in phase text that itself says the names settled
    # differently, so an exemption is the honest treatment and a doc edit would
    # not be.
    "cxBech32Encode": (
        "superseded-design", "cxBech32EncodeValues",
        "IMPLEMENTATION-PLAN.md phase 3 writes the pair as "
        "'cxBech32Encode/Decode'. The shipped names carry a Values suffix, "
        "because the handlers move 5-bit DATA VALUES as a comma list rather "
        "than bytes, and the plan is a dated record."),
    "cxRlpEncode": (
        "superseded-design", "cxRlpEncodeBytes",
        "IMPLEMENTATION-PLAN.md phase 3 writes 'cxRlpEncode/Decode'. RLP "
        "shipped as two encoders, cxRlpEncodeBytes and cxRlpEncodeList, "
        "because a string and a list are different RLP prefixes and one "
        "handler could not tell an empty list from an empty string. Dated "
        "record; cxRlpDecode did keep its planned name."),
}

CATEGORIES = ("convention", "deferred", "superseded-design", "corrected")

# The categories whose whole justification is "something else was built under a
# different name", so the name of that something else is what the ratchet hangs
# on. See the module docstring.
NEEDS_REPLACEMENT = ("superseded-design", "corrected")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def public_handlers():
    """The shipped public surface: .lcb `public handler` plus every top-level
    handler in the script layer (which has no `public` keyword - a script
    handler is public unless it says `private`)."""
    lcb = set(re.findall(r"^public handler (cx\w+)", read(LCB), re.M))
    script = set(re.findall(r"^(?:function|command) (cx\w+)", read(SCRIPT), re.M))
    return lcb | script


def private_handlers():
    lcb = set(re.findall(r"^private handler (cx\w+)", read(LCB), re.M))
    script = set(re.findall(r"^private (?:function|command) (cx\w+)",
                            read(SCRIPT), re.M))
    return lcb | script


def doc_paths():
    paths = [os.path.join(ROOT, rel) for rel in DOC_FILES]
    paths += sorted(glob.glob(os.path.join(ROOT, "docs", "*.md")))
    return paths


def main(argv):
    terse = "--check" in argv[1:]
    problems = []

    public = public_handlers()
    private = private_handlers()
    # The check-suite-coverage.py guard, for the same reason it has one: if the
    # source layout moves under this gate, every doc name becomes "unknown" and
    # the failure would read as 100 doc defects instead of as one broken
    # parser. Refuse loudly and name the cause.
    if not public:
        print("check-doc-handlers: FAILED - parsed NO public handlers from "
              "src/, so the source layout changed and this gate is checking "
              "nothing")
        return 1
    known = public | private

    # ---- pass 1: every cx* token in the docs is a real name or excused -------
    mentions = {}   # name -> [doc labels]
    rows = []
    for path in doc_paths():
        if not os.path.exists(path):
            # A doc that MOVED must fail rather than shrink the scan silently.
            problems.append("%s is listed in DOC_FILES but does not exist - "
                            "renamed or deleted? Update the list in this file."
                            % os.path.relpath(path, ROOT))
            continue
        label = os.path.relpath(path, ROOT)
        names = set(CX_TOKEN.findall(read(path)))
        for name in names:
            mentions.setdefault(name, []).append(label)
        unknown = sorted(n for n in names
                         if n not in known and n not in NOT_A_HANDLER)
        rows.append((label, len(names), unknown))
        if unknown:
            problems.append(
                "%s names %d cx* handler(s) that no handler defines:\n      %s"
                "\n      Fix the name, or - if the docs are deliberately "
                "naming something that is not shipped - add it to "
                "NOT_A_HANDLER in tools/check-doc-handlers.py with a category "
                "and a reason."
                % (label, len(unknown), "\n      ".join(unknown)))

    # ---- pass 2: every public handler reaches the api-reference --------------
    api = set(CX_TOKEN.findall(read(API_REFERENCE)))
    undocumented = sorted(public - api)
    if undocumented:
        problems.append(
            "%d public handler(s) are never named in docs/api-reference.md:"
            "\n      %s\n      A shipped handler a caller cannot look up is "
            "not shipped as far as they are concerned."
            % (len(undocumented), "\n      ".join(undocumented)))

    # ---- the ratchet: no exemption may outlive its reason --------------------
    for name in sorted(NOT_A_HANDLER):
        category, replaced_by, reason = NOT_A_HANDLER[name]
        if category not in CATEGORIES:
            problems.append("%s is listed with category %r, which is not one "
                            "of %s. An open-ended reason field becomes 'hard "
                            "to fix' within a year."
                            % (name, category, ", ".join(CATEGORIES)))
        if not reason.strip():
            problems.append("%s is listed with an empty reason" % name)
        if name in known:
            problems.append(
                "%s is listed in NOT_A_HANDLER but IS a handler now - the "
                "exemption says the docs name something that does not exist, "
                "and it does. Delete the entry (and check whether the doc "
                "sentence around it is now wrong too)." % name)
        if name not in mentions:
            problems.append(
                "%s is listed in NOT_A_HANDLER but appears in no scanned doc - "
                "the prose it excused is gone. Delete the entry." % name)
        if category in NEEDS_REPLACEMENT:
            if not replaced_by:
                problems.append(
                    "%s is %s but names no replacement. That field is what "
                    "ties the excuse to the tree; without it the entry cannot "
                    "go stale." % (name, category))
            elif replaced_by not in public:
                problems.append(
                    "%s is excused because %s is the real name, but %s is not "
                    "a public handler any more - the justification has rotted "
                    "even though the excused name has not. Re-point it at "
                    "whatever ships today."
                    % (name, replaced_by, replaced_by))
        elif replaced_by is not None:
            problems.append("%s is %s, which takes no replaced_by (%s)"
                            % (name, category, replaced_by))

    if not terse:
        print("shipped: %d public, %d private" % (len(public), len(private)))
        print()
        print("%-28s %8s  %s" % ("doc", "cx names", "unknown"))
        for label, count, unknown in rows:
            flag = "" if not unknown else "   <-- %d UNKNOWN" % len(unknown)
            print("%-28s %8d%s" % (label, count, flag))
            for name in unknown:
                print("%30s%s" % ("", name))
        print()
        print("api-reference covers %d of %d public handlers"
              % (len(public) - len(undocumented), len(public)))
        print("%d documented name(s) are excused as not-a-handler:"
              % len(NOT_A_HANDLER))
        for name in sorted(NOT_A_HANDLER):
            category, replaced_by, _ = NOT_A_HANDLER[name]
            extra = "" if not replaced_by else " -> %s" % replaced_by
            print("   %-18s %s%s   [%s]"
                  % (name, category, extra, ", ".join(mentions.get(name, []))))

    if problems:
        print("check-doc-handlers: FAILED")
        for problem in problems:
            print("  - %s" % problem)
        return 1
    print("check-doc-handlers: OK (%d public handlers, %d/%d named in "
          "docs/api-reference.md, %d doc(s) scanned, %d excused name(s))"
          % (len(public), len(public) - len(undocumented), len(public),
             len(rows), len(NOT_A_HANDLER)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
