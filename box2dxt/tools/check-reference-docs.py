#!/usr/bin/env python3
"""check-reference-docs.py - the two reference pages name the whole surface.

    python3 tools/check-reference-docs.py        # from the member root, or anywhere

WHY THIS EXISTS. docs/api-reference.md and docs/kit-reference.md are the
quick-lookup pages for the raw binding (every `public handler b2...` in
src/box2dxt.lcb) and the Kit (every `command|function|on b2k...` in
src/box2dxt-kit.livecodescript). Both drifted for months with nothing to hold
them: on 2026-08-26 the api page named 216 of 376 handlers and said so in its
own intro ("no gate holds that ratio"), and the kit page 242 of 313 - missing
b2kPlayerDuckSet and b2kPlayerTick, which the self-test drives by name. Both
were completed on 2026-09-24. A completed page with no gate is a page that
starts drifting again at the next handler somebody adds, so this is that gate.

WHAT IT ASKS, in both directions, per page:

  1. MISSING: every public handler of its layer appears in the page as a
     whole word. Whole word, not substring: `b2kSyncAll` must not satisfy
     `b2kSync`, and `b2Distance...` in prose must not satisfy anything.
  2. UNKNOWN: every `b2...` identifier the page names is real. A rename that
     leaves the old name in the page is the rot this catches (description
     rots; checks do not). An identifier that is not a handler is accepted
     only when the sources vouch for it: the Kit or the binding spells it as
     the start of a double-quoted string (`dispatch "b2kFrame"`, the
     `"b2kfr_"` control-name prefix), or the page writes it as a family with
     a trailing `...` that at least one real handler starts with
     (`b2AABB...`, `b2kAdd...`).

It does NOT judge the prose. "Named" is the floor: a row can still be wrong
about what a handler does, which is why the pages were written from the
source and why the source stays the authority for exact types.

FIXTURE BEFORE GATE. A scanner that silently matched nothing would print OK
over a page with no handlers in it, so before the real check this runs the
same functions over three in-memory mutations of the real pages and fails
unless each is caught: a handler's every mention removed; a handler that
survives only inside a longer name (the whole-word rule); an invented name
added. Nothing is written to disk.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LCB = os.path.join(ROOT, "src", "box2dxt.lcb")
KIT = os.path.join(ROOT, "src", "box2dxt-kit.livecodescript")
API_DOC = os.path.join(ROOT, "docs", "api-reference.md")
KIT_DOC = os.path.join(ROOT, "docs", "kit-reference.md")

IDENT = re.compile(r"\b(b2\w+)\b")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def raw_handlers(lcb_text):
    return re.findall(r"^public handler (b2\w+)\(", lcb_text, re.M)


def kit_handlers(kit_text):
    return re.findall(r"^(?:command|function|on)\s+(b2k\w+)\b", kit_text, re.M)


def check_page(doc_text, handlers, all_handlers, sources_text):
    """(missing, unknown) for one page: handlers of its layer the page never
    names, and b2 identifiers it names that nothing vouches for."""
    named = set(IDENT.findall(doc_text))
    missing = sorted(set(handlers) - named)
    unknown = []
    for name in sorted(named - set(all_handlers)):
        if ('"' + name) in sources_text:
            continue      # a dispatched message or a control-name prefix
        if re.search(r"\b" + re.escape(name) + r"\.\.\.", doc_text) and \
                any(h.startswith(name) and h != name for h in all_handlers):
            continue      # a family written as `prefix...`
        unknown.append(name)
    return missing, unknown


def fixtures(api_text, kit_text, raw, kitn, all_h, sources):
    """Prove the check can fail, on mutations of the real pages."""
    problems = []

    # (a) drop every whole-word mention of a handler the page does name
    victim = "b2kPlayerTick"
    dropped = re.sub(r"\b" + victim + r"\b", "REMOVED", kit_text)
    miss, _ = check_page(dropped, kitn, all_h, sources)
    if victim not in miss:
        problems.append(f"fixture: removing every {victim} left it unreported")

    # (b) the whole-word rule: b2kSync gone, b2kSyncAll/b2kSyncBodies kept
    victim = "b2kSync"
    if not re.search(r"\b" + victim + r"\w", kit_text):
        problems.append("fixture: the whole-word case needs a longer name "
                        "starting with b2kSync in the page; pick another pair")
    else:
        dropped = re.sub(r"\b" + victim + r"\b", "REMOVED", kit_text)
        miss, _ = check_page(dropped, kitn, all_h, sources)
        if victim not in miss:
            problems.append(f"fixture: {victim} surviving only inside longer "
                            "names was counted as named (substring match)")

    # (c) an invented name must be refused, on the raw page too
    fake = "b2NoSuchHandlerEver"
    _, unk = check_page(api_text + f"\n| `{fake}(x)` | nothing |\n", raw, all_h, sources)
    if fake not in unk:
        problems.append(f"fixture: an invented {fake} was accepted")
    return problems


def main():
    lcb_text, kit_src = read(LCB), read(KIT)
    raw, kitn = raw_handlers(lcb_text), kit_handlers(kit_src)
    if not raw or not kitn:
        print(f"check-reference-docs: FAIL - the scanner found {len(raw)} raw and "
              f"{len(kitn)} Kit handlers; a source moved or its declaration shape "
              f"changed, and a blind scan would pass anything")
        return 1
    all_h = set(raw) | set(kitn)
    sources = lcb_text + kit_src
    api_text, kit_text = read(API_DOC), read(KIT_DOC)

    problems = fixtures(api_text, kit_text, raw, kitn, all_h, sources)
    if problems:
        print("check-reference-docs: FAIL - the check itself is blind:")
        for p in problems:
            print(f"  {p}")
        return 1

    failed = False
    for label, text, layer in (("docs/api-reference.md", api_text, raw),
                               ("docs/kit-reference.md", kit_text, kitn)):
        missing, unknown = check_page(text, layer, all_h, sources)
        if missing:
            failed = True
            print(f"{label}: {len(missing)} public handler(s) never named - add a "
                  f"row written from the source:")
            for m in missing:
                print(f"  - {m}")
        if unknown:
            failed = True
            print(f"{label}: {len(unknown)} name(s) that are not a handler, a "
                  f"dispatched message, a quoted prefix in the sources, or a "
                  f"`family...` - renamed or removed?")
            for u in unknown:
                print(f"  - {u}")
    if failed:
        return 1
    print(f"check-reference-docs: OK (api-reference names all {len(raw)} raw "
          f"handlers, kit-reference all {len(kitn)} Kit handlers; no unknown "
          f"names; three blind-scan fixtures caught)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
