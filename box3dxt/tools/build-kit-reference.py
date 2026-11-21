#!/usr/bin/env python3
"""build-kit-reference.py - write docs/kit-reference.md from the Kit's doc
blocks, and hold the Kit's own header to its handlers.

The b3k Kit (src/box3dxt-kit.livecodescript) documents every handler of its
API in a `/** */` block, the blocks OXT-Beyond's dictionary reads. The page is
GENERATED from them, so the page and the dictionary cannot say different
things: box2dxt's hand-kept kit-reference.md named 242 of its Kit's 313
handlers before a gate held it (2026-09-24), and curlxt's hand-kept page went
stale the first time a block changed (2026-11-14).

    python3 tools/build-kit-reference.py           rewrite docs/kit-reference.md
    python3 tools/build-kit-reference.py --check   exit 1 if the page is stale
                                                   or a check below fails

--check also asks of the Kit what nothing else in this member asks (the
suite's dictionary gate asks the first two, but a published member stands
alone):

  1. Every public handler has a doc block but those in NOT_API, each with its
     reason, and NOT_API names nothing that is gone or documented.
  2. A block's parameters are its handler's own, every one, in order.
  3. The CHEAT SHEET in the header names every documented handler and every
     message the Kit dispatches, each as a whole word (`b3kCamZoomBy` does
     not name `b3kCamZoom`), because the header is the first thing a game
     maker reads and the only list of the API a pasted stack carries.
  4. Every b3k name in the header and in the hand-written pages (KNOWN_PAGES)
     is a public handler or a message the Kit dispatches: a rename that
     leaves the old name in prose is the rot this catches.

tools/test-kit-reference.py breaks each of these in memory and requires a
refusal (fixture before gate).
"""

import os
import re
import sys
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join("src", "box3dxt-kit.livecodescript")
OUT = os.path.join("docs", "kit-reference.md")
# Hand-written pages whose b3k names must all be real (check 4). The
# generated page is not here: it is held by being regenerated.
KNOWN_PAGES = [os.path.join("docs", "kit-guide.md"), "README.md"]

# Public handlers that are not API and so carry no doc block. The suite's
# tools/check-dictionary-docs.py exempts the same names, with the same
# reasons; each list holds its own side.
NOT_API = {
    "b3kStep": "the loop's timer message, sent by b3kStart and rescheduled by "
               "itself with send in; start the loop with b3kStart, never call it",
}

HANDLER = re.compile(r"^(command|function|on)\s+(b3k\w+)\b[ \t]*(.*)$")
PRIVATE = re.compile(r"^private\s+(command|function|on)\s+(\w+)")
ELEMENT = re.compile(r"^(Summary|Returns|Description|Example|References|Title|Author|Tags"
                     r"|p[A-Z]\w*):[ \t]*(.*)$")
BANNER = re.compile(r"^-- =+$")
NAME = re.compile(r"\bb3k\w+")
DISPATCH = re.compile(r'\bdispatch\s+"(b3k\w+)"')


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def parse_block(body):
    """[(element, [lines])] of one doc block, in order. An element runs to the
    next element line, blank lines included, as the dictionary reads it."""
    out = []
    for line in body.split("\n"):
        m = ELEMENT.match(line)
        if m:
            out.append([m.group(1), [m.group(2)] if m.group(2) else []])
        elif out:
            out[-1][1].append(line)
    for item in out:
        while item[1] and not item[1][-1].strip():
            item[1].pop()
        while item[1] and not item[1][0].strip():
            item[1].pop(0)
    return out


def paragraphs(lines):
    """Prose lines joined into paragraphs at the blank lines."""
    paras, cur = [], []
    for line in lines:
        if line.strip():
            cur.append(line.strip())
        elif cur:
            paras.append(" ".join(cur))
            cur = []
    if cur:
        paras.append(" ".join(cur))
    return paras


def params_of(rest):
    rest = rest.strip()
    return [p.strip() for p in rest.split(",")] if rest else []


def scan(text):
    """Everything the page and the checks need, read in one pass.

    Returns a dict: library (element list or None), items (("section", title)
    and ("handler", kind, name, params, block-or-None, line) in source order),
    public ({name: line}), orphans (line numbers of blocks no handler took)."""
    lines = text.split("\n")
    library, items, public, orphans = None, [], {}, []
    pending = None          # (line, element list)
    i = 0
    while i < len(lines):
        line = lines[i]
        if BANNER.match(line) and i + 2 < len(lines) and BANNER.match(lines[i + 2]) \
                and lines[i + 1].startswith("-- "):
            items.append(("section", lines[i + 1][3:].strip()))
            i += 3
            continue
        if line.startswith("/**"):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("*/"):
                j += 1
            block = parse_block("\n".join(lines[i + 1:j]))
            if pending is not None:
                orphans.append(pending[0])
            if block and block[0][0] == "Title":
                library = block
                pending = None
            else:
                pending = (i + 1, block)
            i = j + 1
            continue
        m = HANDLER.match(line)
        if m:
            kind, name, rest = m.groups()
            public[name] = i + 1
            items.append(("handler", kind, name, params_of(rest),
                          pending[1] if pending else None, i + 1))
            pending = None
        elif PRIVATE.match(line):
            if pending is not None:
                orphans.append(pending[0])
            pending = None
        elif line.strip() and not line.lstrip().startswith("--") and pending is not None:
            orphans.append(pending[0])
            pending = None
        i += 1
    if pending is not None:
        orphans.append(pending[0])
    return {"library": library, "items": items, "public": public, "orphans": orphans}


def header_lines(text):
    """The leading comment block of the Kit: its banner, start and cheat sheet."""
    out = []
    for line in text.split("\n"):
        if not line.startswith("--"):
            break
        out.append(line)
    return out


def header_span(head, title):
    """The header lines after the banner line naming `title`, up to the next
    banner line (a line of `=` with or without a title in it)."""
    start = None
    for i, line in enumerate(head):
        if title in line and "=====" in line:
            start = i + 1
            break
    if start is None:
        return None
    end = start
    while end < len(head) and "=====" not in head[end]:
        end += 1
    return head[start:end]


def dispatched(text):
    return sorted(set(DISPATCH.findall(text)))


def anchor(title):
    """GitHub's heading anchor: lower case, punctuation but - and _ dropped,
    spaces to hyphens."""
    a = re.sub(r"[^\w\- ]", "", title.lower())
    return a.replace(" ", "-")


def check(text, pages=None):
    """Problems with the Kit (checks 1 to 4). `pages` maps a page's name to
    its text for check 4; None reads KNOWN_PAGES from disk."""
    problems = []
    info = scan(text)
    public = info["public"]
    handlers = [e for e in info["items"] if e[0] == "handler"]
    if len(handlers) < 100:
        return ["the scan found %d public b3k handlers; the Kit moved or its "
                "handler lines changed shape, and a blind scan passes anything" % len(handlers)]
    if info["library"] is None:
        problems.append("no library block (a /** */ block starting Title:) in the Kit")
    for line in info["orphans"]:
        problems.append("the doc block at line %d belongs to no public b3k handler" % line)

    # 1. every public handler documented, bar NOT_API; NOT_API not stale
    documented = []
    for _, kind, name, params, block, line in handlers:
        if block is None:
            if name not in NOT_API:
                problems.append("%s (line %d) is public with no doc block; document it, "
                                "make it private, or add it to NOT_API with a reason"
                                % (name, line))
            continue
        if name in NOT_API:
            problems.append("%s is in NOT_API but has a doc block; take it out of NOT_API"
                            % name)
        documented.append(name)
        elements = [e for e, _ in block]
        if "Summary" not in elements:
            problems.append("%s: its doc block has no Summary" % name)
        # 2. the block's parameters are the handler's own, in order
        named = [e for e in elements if re.match(r"^p[A-Z]", e)]
        if named != params:
            problems.append("%s: the doc block names parameters %s but the handler "
                            "takes %s" % (name, named or "none", params or "none"))
    for name in NOT_API:
        if name not in public:
            problems.append("NOT_API names %s, which is no public handler of the Kit" % name)

    messages = dispatched(text)
    if not messages:
        problems.append("the scan found no `dispatch \"b3k...\"` in the Kit; a blind "
                        "scan accepts any name as a message")
    known = set(public) | set(messages)

    # 3. the cheat sheet names every documented handler and every message
    head = header_lines(text)
    cheat = header_span(head, "CHEAT SHEET")
    if cheat is None:
        problems.append("the Kit's header has no CHEAT SHEET banner")
    else:
        named = set(NAME.findall("\n".join(cheat)))
        for name in documented:
            if name not in named:
                problems.append("the header's CHEAT SHEET does not name %s" % name)
        for name in messages:
            if name not in named:
                problems.append("the header's CHEAT SHEET does not name the message %s" % name)

    # 4. every b3k name in the header and the hand-written pages is real
    if pages is None:
        pages = {}
        for rel in KNOWN_PAGES:
            if os.path.exists(os.path.join(ROOT, rel)):
                pages[rel] = read(rel)
            else:
                problems.append("%s is missing (named in KNOWN_PAGES)" % rel)
    sources = [("the Kit's header", "\n".join(head))] + sorted(pages.items())
    for label, body in sources:
        for name in sorted(set(NAME.findall(body))):
            if name not in known:
                problems.append("%s names %s, which is neither a public handler nor a "
                                "message of the Kit" % (label, name))
    return problems


def link(text, documented):
    """<b3kName> of the dictionary: a link to its entry when it has one."""
    def one(m):
        n = m.group(1)
        return "[`%s`](#%s)" % (n, anchor(n)) if n in documented else "`%s`" % n
    return re.sub(r"<(b3k\w+)>", one, text)


def render(text):
    info = scan(text)
    handlers = [e for e in info["items"] if e[0] == "handler" and e[4] is not None]
    documented = {e[2] for e in handlers}
    head = header_lines(text)
    start = header_span(head, "60-SECOND START") or []
    cheat = header_span(head, "CHEAT SHEET") or []

    def uncomment(lines):
        out = [l[3:] if l.startswith("-- ") else l[2:] for l in lines]
        while out and not out[-1].strip():
            out.pop()
        while out and not out[0].strip():
            out.pop(0)
        return textwrap.dedent("\n".join(out)).split("\n")

    body, sections, section = [], [], None
    for e in info["items"]:
        if e[0] == "section":
            section = e[1]
            continue
        _, kind, name, params, block, _ = e
        if block is None:
            continue
        if section is not None:
            sections.append(section)
            body += ["## " + section, ""]
            section = None
        if kind == "function":
            sig = "%s(%s)" % (name, ", ".join(params))
        else:
            sig = (name + " " + ", ".join(params)).strip()
        body += ["### `%s`" % name, "", "`%s`" % sig, ""]
        elements = dict((k, v) for k, v in block)
        body += [link(p, documented) for p in paragraphs(elements.get("Summary", []))] + [""]
        prm = [(k, v) for k, v in block if re.match(r"^p[A-Z]", k)]
        if prm:
            body += ["- `%s`: %s" % (k, link(" ".join(paragraphs(v)), documented)) for k, v in prm]
            body.append("")
        if elements.get("Returns"):
            body += ["Returns: " + link(" ".join(paragraphs(elements["Returns"])), documented), ""]
        for p in paragraphs(elements.get("Description", [])):
            body += [link(p, documented), ""]
        if elements.get("Example"):
            body += ["```", "\n".join(elements["Example"]), "```", ""]
        if elements.get("References"):
            refs = re.findall(r"(b3k\w+)\s*\(handler\)", " ".join(elements["References"]))
            if refs:
                body += ["See also: " + ", ".join(
                    "[`%s`](#%s)" % (r, anchor(r)) if r in documented else "`%s`" % r
                    for r in refs), ""]

    lib = dict((k, v) for k, v in (info["library"] or []))
    not_api = ", ".join("`%s` (%s)" % (n, why) for n, why in sorted(NOT_API.items()))
    page = ["# box3dxt Kit reference (`b3k...`)", "",
            "The %d handlers of the Kit's API, from the doc blocks in `src/box3dxt-kit.livecodescript`"
            % len(handlers),
            "(OXT-Beyond's dictionary reads the same blocks; `tools/build-kit-reference.py` writes this",
            "file from them, and its `--check` is a gate). New to the Kit? Read",
            "[kit-guide.md](kit-guide.md) first: it goes from an empty stack to a game. The raw binding",
            "under the Kit is in [api-reference.md](api-reference.md).", ""]
    page += [link(p, documented) + "\n" for p in paragraphs(lib.get("Description", []))]
    page += ["Not listed, because it is not API: %s." % not_api, ""]
    page += ["## 60-second start", "", "```"] + uncomment(start) + ["```", ""]
    page += ["## Cheat sheet", "", "The Kit's own header carries this list; `--check` holds it to the",
             "handlers below and to the messages the Kit sends (%s)." %
             ", ".join("`%s`" % m for m in dispatched(text)), "",
             "```"] + uncomment(cheat) + ["```", ""]
    page += ["## Contents", ""] + ["- [%s](#%s)" % (s, anchor(s)) for s in sections] + [""]
    return "\n".join(page + body)


def main(argv):
    text = read(KIT)
    page = render(text)
    if "--check" in argv:
        problems = check(text)
        have = read(OUT) if os.path.exists(os.path.join(ROOT, OUT)) else ""
        if have != page:
            problems.append("docs/kit-reference.md is stale - run python3 tools/build-kit-reference.py")
        if problems:
            print("build-kit-reference: FAIL")
            for p in problems:
                print("  " + p)
            return 1
        n = len([e for e in scan(text)["items"] if e[0] == "handler" and e[4] is not None])
        print("build-kit-reference: OK (docs/kit-reference.md matches the doc blocks; "
              "%d documented handlers, every one in the header's cheat sheet; every b3k "
              "name in the header and %d pages is real)" % (n, len(KNOWN_PAGES)))
        return 0
    with open(os.path.join(ROOT, OUT), "w", encoding="utf-8") as f:
        f.write(page)
    print("build-kit-reference: wrote docs/kit-reference.md")
    problems = check(text)
    for p in problems:
        print("  note: " + p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
