#!/usr/bin/env python3
"""check-doc-handlers.py - do the docs and the shipped handler set agree?

The coinxt gate established the class and the reason (a handler name that
exists only in prose is a documentation defect with a code-shaped cost: a
reader who copies it out gets `handler not found`, and every other gate stays
green about it). nostrxt ships the same two mechanical properties from day
one, adapted to its two prefixes:

  1. DOCUMENTED -> SHIPPED. Every `nx*` / `nxr*` token in the scanned docs is
     a public handler, a private handler (CLAUDE.md and the numbered docs are
     internals records and legitimately name internals - a rename still
     breaks the reference and is still caught), or listed in NOT_A_HANDLER
     below with a category and a written reason.
  2. SHIPPED -> DOCUMENTED. Every public handler of BOTH source files is
     named in docs/06-api-reference.md. This was complete with zero
     exemptions when the gate landed, so it is a ratchet, not a backlog.

The stale-excuse ratchet is carried whole: an entry whose name IS a handler
now, or that appears in no scanned doc, or whose replaced_by is no longer a
public handler, fails the build. The categories are the fixed coinxt set
(convention / deferred / superseded-design / corrected).

USAGE
    python3 nostrxt/tools/check-doc-handlers.py [--check]
    Exit 0 when both directions hold, 1 otherwise.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)

SOURCES = [
    os.path.join(MEMBER, "src", "nostrxt.livecodescript"),
    os.path.join(MEMBER, "src", "nostr-relay.livecodescript"),
]
# The harness defines real names the docs may cite (nxSelfTest above all),
# but its surface is documented in README/the plan, not the api-reference,
# so it feeds the KNOWN set only - never the must-be-documented set.
EXTRA_KNOWN_SOURCES = [
    os.path.join(MEMBER, "examples", "nostrxt-tests.livecodescript"),
]
API_REFERENCE = os.path.join(MEMBER, "docs", "06-api-reference.md")
DOC_FILES = [
    os.path.join(MEMBER, "README.md"),
    os.path.join(MEMBER, "CLAUDE.md"),
    os.path.join(MEMBER, "IMPLEMENTATION-PLAN.md"),
] + sorted(
    os.path.join(MEMBER, "docs", f)
    for f in os.listdir(os.path.join(MEMBER, "docs")) if f.endswith(".md"))

# name -> (category, replaced_by, reason). Categories are the coinxt gate's
# fixed set; replaced_by is required for superseded-design and corrected.
NOT_A_HANDLER = {
    "nxPascalCase": (
        "convention", None,
        "the house-style line ('public API nxPascalCase') in CLAUDE.md and "
        "the docs; a naming convention example, not a call."),
    "nxrPascalCase": (
        "convention", None,
        "the relay half of the same house-style line; a naming convention "
        "example, not a call."),
    "nxNip44": (
        "convention", None,
        "the prefix of the seam's own error string ('nxNip44 needs SodiumXT "
        "sxChaCha20IetfXor ...'), quoted VERBATIM by docs 04/06/07/09; a "
        "message fragment, not a call."),
    "nxWs": (
        "convention", None,
        "the family-stem glob nxWs* the docs use for the websocket helper "
        "group; a group name, not a call."),
}

DEF_RE = re.compile(
    r"^\s*(private\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)", re.M)
TOKEN_RE = re.compile(r"\b(nxr?[A-Z]\w*)\b")


def harvest():
    public, private, extra = set(), set(), set()
    for path in SOURCES:
        text = open(path, encoding="utf-8").read()
        # strip comments so prose mentions in source do not count as defs
        code = "\n".join(ln.split("--", 1)[0] for ln in text.split("\n"))
        for is_private, name in DEF_RE.findall(code):
            (private if is_private else public).add(name)
    for path in EXTRA_KNOWN_SOURCES:
        text = open(path, encoding="utf-8").read()
        code = "\n".join(ln.split("--", 1)[0] for ln in text.split("\n"))
        for _is_private, name in DEF_RE.findall(code):
            extra.add(name)
    return public, private, extra


def main(argv):
    problems, seen_in_docs = [], set()
    public, private, extra = harvest()
    known = public | private | extra

    for path in DOC_FILES:
        rel = os.path.relpath(path, MEMBER)
        text = open(path, encoding="utf-8").read()
        for name in set(TOKEN_RE.findall(text)):
            seen_in_docs.add(name)
            if name not in known and name not in NOT_A_HANDLER:
                problems.append(
                    f"{rel}: `{name}` is not a handler in either source file "
                    "- fix the name, or list it in NOT_A_HANDLER with a "
                    "category and a written reason")

    # Word-boundary search rather than the nx-token harvest: the relay layer
    # legitimately defines the ENGINE's unprefixed socket messages, and the
    # reference documents them in its engine-called section.
    api_text = open(API_REFERENCE, encoding="utf-8").read()
    for name in sorted(public):
        if not re.search(r"\b" + re.escape(name) + r"\b", api_text):
            problems.append(
                f"docs/06-api-reference.md does not name the public handler "
                f"`{name}` - the reference is the page a caller is sent to, "
                "so it names everything")

    # the stale-excuse ratchet
    for name in sorted(NOT_A_HANDLER):
        category, replaced_by, _ = NOT_A_HANDLER[name]
        if category not in ("convention", "deferred", "superseded-design",
                            "corrected"):
            problems.append(f"NOT_A_HANDLER[{name}]: unknown category "
                            f"'{category}'")
        if name in known:
            problems.append(f"{name} is listed in NOT_A_HANDLER but IS a "
                            "handler now - delete the entry")
        if name not in seen_in_docs:
            problems.append(f"{name} is listed in NOT_A_HANDLER but appears "
                            "in no scanned doc - the prose it excused is "
                            "gone; delete the entry")
        if category in ("superseded-design", "corrected"):
            if not replaced_by or replaced_by not in public:
                problems.append(f"NOT_A_HANDLER[{name}]: replaced_by "
                                f"'{replaced_by}' is not a public handler")

    for p in problems:
        print("check-doc-handlers: " + p)
    if problems:
        print(f"check-doc-handlers: {len(problems)} problem(s)")
        return 1
    print(f"check-doc-handlers: OK ({len(public)} public handlers all named "
          f"in the api-reference; {len(seen_in_docs & known)} handler "
          f"name(s) referenced across {len(DOC_FILES)} doc(s) all resolve; "
          f"{len(NOT_A_HANDLER)} listed non-handler(s), none stale)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
