#!/usr/bin/env python3
"""check-dictionary-docs.py - the doc blocks the OXT-Beyond dictionaries read.

WHY THIS EXISTS
    OXT-Beyond ships the libraries in CORPUS below built in, and both of its
    dictionaries list a library's handlers from `/** ... */` doc blocks in
    the library's source: LiveCode's Dictionary parses them when the IDE
    loads the extension, the text dictionary when Beyond's docs build runs
    (both through Beyond's ide-support/revdocsparser.livecodescript). The
    parser is forgiving in the worst way: it keeps a doc block until the
    next ENTRY it recognises and gives the block to that entry. A block
    above a private handler, a constant or a stray `on` message therefore
    documents whatever public handler comes next, under the wrong name, and
    nothing complains. A missing block is silent too: the handler is simply
    absent from both dictionaries. This gate makes both visible.

WHAT IT CHECKS, per CORPUS file
    1. THE LIBRARY ENTRY: an .lcb file has one block directly above its
       `library` line; a script library's FIRST block is its library entry
       (the parser's rule) and must carry a `Title:` line, and a second block
       must open before any handler, or the parser hands the first block to
       that handler instead.
    2. NO ORPHAN BLOCK: every other block is followed (blank lines and `--`,
       `#`, `//` comments aside) by a documented handler line: `public
       handler` in .lcb, a non-private `on`/`command`/`function` in script.
    3. EVERY BLOCK HAS A `Summary:` line, and its parameter lines (`pName:`
       or `pName (type):`) name exactly the handler's parameters, no more,
       no fewer.
    4. COVERAGE: every public handler is documented, bar the script
       handlers in EXEMPT with a reason (send targets and engine messages
       the library needs in the message path but nobody calls). A stale
       exemption (the handler is gone, documented, or private) fails. An
       exempt handler is declared `on`: the parser asks a doc block of
       every `command` and `function` of a script library and logs
       "Required documentation not found" for one without (at every
       dictionary build, and at every start of the web IDE before
       2026-10-20), while it takes an `on` handler for a message. The
       engine reads `command` as `on` (both are HT_MESSAGE), so the
       keyword changes nothing else.
    5. LINKS: every `<name>` in a block names a handler documented
       somewhere in the CORPUS, or the dictionary renders a dead link.
    6. SCRIPT BLOCKS HOLD NO CODE SHAPES: inside a .livecodescript block no
       line starts, at any indent, with a word that opens or closes a
       handler or a declaration (on, command, function, end, local,
       constant, ...). The engine skips a block comment, but the family's
       line-based tools do not: the interpreter, the suite paste generator
       and check-cross-library-names.py cut only `--` comments, so an
       example `on closeStack` there reads as a second closeStack.
    7. NO PROSE LINE READS AS AN ELEMENT: the parser starts a new element
       at ANY line that opens with one word and a colon (its
       __elementRegex), so a description wrapped to put "automatic:" or
       "it:" first on a line is cut there. In an entry the cut-off text is
       glued back without its line break and the space after the colon
       ("automatic:creating"), or, for a word the parser knows ("it" is a
       return value), filed under that element; in a library block the
       parser stops reading the library entry at the first name it does
       not know (it logs "invalid library-level element") and the rest of
       the library's description is lost. Found 2026-10-12 by running the
       real parser over the corpus: nostr-relay's library entry stopped at
       "Call <nxrShutdown> from", and dcCreateChannel grew a return value
       named "It". So every such line in a block must name an element the
       corpus uses (LIBRARY_ELEMENTS, ENTRY_ELEMENTS) or, in an entry, one
       of the handler's parameters, and no element but Example may appear
       twice in one block (a second one replaces the first). Rewrap the
       prose so another word leads the line.

    It does not judge the prose; that is review. It mirrors the parser's
    entry rules, so a change to Beyond's revdocsparser can outdate it.

USAGE
    python3 tools/check-dictionary-docs.py [--root DIR]
    Exit 0 when every check holds, 1 otherwise.
    tools/test-dictionary-docs.py fixture-proves each check fires.

A member that leaves the suite takes its CORPUS rows with it
(docs/MEMBER-REPO-SPLIT.md section 8).
"""
import argparse
import os
import re
import sys

# The extensions OXT-Beyond ships (its tools/oxt/xtalk-extensions.json),
# by their source file in this repository.
CORPUS = [
    "sodiumxt/src/sodium.lcb",
    "torrentxt/src/torrent.lcb",
    "torrentxt/examples/torrent-helpers.livecodescript",
    "enetxt/src/enet.lcb",
    "enetxt/examples/enet-helpers.livecodescript",
    "datachannelxt/src/datachannel.lcb",
    "datachannelxt/examples/datachannel-helpers.livecodescript",
    "box2dxt/src/box2dxt.lcb",
    "box2dxt/src/box2dxt-kit.livecodescript",
    "coinxt/src/coinxt.lcb",
    "coinxt/src/coinxt.livecodescript",
    "onionxt/src/onionxt.livecodescript",
    "onionxt/src/onion-httpd.livecodescript",
    "nostrxt/src/nostrxt.livecodescript",
    "nostrxt/src/nostr-relay.livecodescript",
]

# Script handlers that are public only because the engine or a `send`
# must reach them: {file: {handler: reason}}. Each is left out of the
# dictionaries on purpose.
EXEMPT = {
    "enetxt/examples/enet-helpers.livecodescript": {
        "enetPollOnce": "send target of enStartPolling's pump timer (one pump pass that reschedules itself); not API",
    },
    "datachannelxt/examples/datachannel-helpers.livecodescript": {
        "dcChannelPollOnce": "send target of dcStartPolling's poll timer (one drain pass that reschedules itself); not API",
    },
    "box2dxt/src/box2dxt-kit.livecodescript": {
        "b2kStep": "the loop's timer message, sent by b2kStart and rescheduled by itself with send in; start the loop with b2kStart, never call it",
    },
    "onionxt/src/onionxt.livecodescript": {
        "oxCtlOpened": "open socket message for the control connection; engine-called, not API (docs/05 lists it under handlers the engine calls)",
        "oxCtlLine": "read-until-crlf message of the control connection; engine-called, not API",
        "oxCtlDeadline": "self-sent watchdog (send ... in) for the control handshake; not API",
        "oxSocksOpened": "open socket message for a SOCKS dial; engine-called, not API",
        "oxSocksMethod": "read message of the SOCKS method selection; engine-called, not API",
        "oxSocksReplyHead": "read message of the SOCKS reply head; engine-called, not API",
        "oxSocksReplyLen": "read message of the SOCKS BND.ADDR length byte; engine-called, not API",
        "oxSocksReplyDone": "read message of the SOCKS reply tail; engine-called, not API",
        "oxStreamData": "read message of a live stream; engine-called, not API",
        "oxStreamDeadline": "self-sent watchdog (send ... in) for a dial handshake; not API",
        "oxPeerAccepted": "accept connections message of a service listener; engine-called, not API",
        "socketError": "engine socket message; thin wrapper over oxSocketError (documented), not API",
        "socketClosed": "engine socket message; thin wrapper over oxSocketClosed (documented), not API",
        "socketTimeout": "engine socket message; thin wrapper over oxSocketTimeout (documented), not API",
    },
    "onionxt/src/onion-httpd.livecodescript": {
        "oxhPeer": "OnionXT peer callback that oxhServe registers; reached by dispatch, not API",
        "oxhStream": "OnionXT stream callback set by oxhPeer; reached by dispatch, not API",
        "oxhClose": "send target (send ... in) that closes a served connection after the response; not API",
    },
    "nostrxt/src/nostr-relay.livecodescript": {
        "nxrWsOpened": "with-message target of nxrConnect's open socket; engine-called, the API reference says never call it by hand",
        "nxrWsData": "with-message target of the relay's persistent socket read; engine-called, not API",
        "nxrDeadline": "send ... in target of nxrConnect's handshake watchdog (takes a relay handle); not API",
        "socketError": "engine socket message; thin wrapper over nxrSocketError, which is the documented API",
        "socketClosed": "engine socket message; thin wrapper over nxrSocketClosed, which is the documented API",
        "socketTimeout": "engine socket message; thin wrapper over nxrSocketTimeout, which is the documented API",
    },
}

LCB_HANDLER = re.compile(r"^\s*public\s+handler\s+([A-Za-z_]\w*)\s*\(([^)]*)\)")
LCB_LIBRARY = re.compile(r"^\s*library\s+\S+")
LCS_HANDLER = re.compile(r"^\s*(on|command|function|getProp|setProp)\s+([A-Za-z_]\w*)\b(.*)$", re.I)
LCS_PRIVATE = re.compile(r"^\s*private\s+(on|command|function)\s+([A-Za-z_]\w*)", re.I)
PARAM_LINE = re.compile(r"^\s*([a-z][A-Z]\w*)\s*(\([^)]*\))?\s*:")
ANY_NAME_LINE = re.compile(r"^\s*([A-Za-z_]\w*)\s*(\([^)]*\))?\s*:")
LINK = re.compile(r"<([A-Za-z_][\w.]*)>")
COMMENT_LINE = re.compile(r"^\s*(--|#|//)")
CODE_SHAPE = re.compile(r"^\s*(on|command|function|getProp|setProp|private|end|"
                        r"local|constant|global|script)\b", re.I)
# Beyond's revdocsparser __elementRegex, verbatim: a line it matches starts a
# new element named by group 1 (check 7). Spaces only, as there: a leading
# tab does not match.
ELEMENT_LINE = re.compile(r"^ *([tT]he [rR]esult|\w+) *(?:\(( *(?:optional |in |out |inout )?<?\w*>?)"
                          r" *\))? *: *(.*)")
# The element names the corpus's blocks use (check 7). The parser knows more
# (Version, Requires, Syntax, Related, ...); add one here when a block needs
# it, so that a prose line that happens to start with one still fails.
LIBRARY_ELEMENTS = {"Title", "Author", "Summary", "Description", "Tags"}
ENTRY_ELEMENTS = {"Summary", "Description", "Returns", "Example", "References", "Tags"}
REPEATABLE = {"Example"}


def lcb_params(text):
    out = []
    for part in text.split(","):
        words = part.split()
        if not words:
            continue
        if words[0] in ("in", "out", "inout"):
            words = words[1:]
        if words:
            out.append(words[0])
    return out


def lcs_params(rest):
    rest = rest.split("--")[0].split("#")[0]
    out = []
    for part in rest.split(","):
        name = part.strip().lstrip("@").strip()
        if name:
            out.append(name.split()[0])
    return out


def scan(path, text):
    """Yield ("block", lineno, body) and ("code", lineno, line) items,
    skipping blank lines, line comments and non-doc block comments."""
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("/**") and not s.startswith("/**/"):
            start = i + 1
            body = []
            rest = s[3:]
            while True:
                if "*/" in rest:
                    body.append(rest[:rest.index("*/")].rstrip("*"))
                    break
                body.append(rest)
                i += 1
                if i >= len(lines):
                    yield ("error", start, "unterminated /** block")
                    return
                rest = lines[i]
            yield ("block", start, "\n".join(body))
        elif s.startswith("/*"):
            rest = s[2:]
            while "*/" not in rest:
                i += 1
                if i >= len(lines):
                    return
                rest = lines[i]
        elif s and not COMMENT_LINE.match(line):
            yield ("code", i + 1, line)
        i += 1


def check_elements(path, lineno, body, allowed, params, what, problems):
    """Check 7: every line the parser reads as an element names one the
    corpus uses, or a parameter, and none but Example twice."""
    seen = {}
    for k, bl in enumerate(body.split("\n")):
        m = ELEMENT_LINE.match(bl)
        if not m:
            continue
        el = m.group(1)
        if el in params:
            continue
        if el not in allowed:
            problems.append(f"{path}:{lineno + k}: the docs parser reads this line of {what} as a "
                            f"new element named {el!r}, which cuts the text above it: "
                            f"{bl.strip()[:50]} (rewrap so another word leads the line)")
            continue
        if el in seen and el not in REPEATABLE:
            problems.append(f"{path}:{lineno + k}: {what} has a second {el}: line (the first is at "
                            f"line {seen[el]}); the parser keeps only one")
        seen.setdefault(el, lineno + k)


def check_block(path, lineno, body, name, params, problems):
    check_elements(path, lineno, body, ENTRY_ELEMENTS, params, f"the block of {name}", problems)
    if not re.search(r"^\s*Summary:\s*\S", body, re.M):
        problems.append(f"{path}:{lineno}: the block of {name} has no Summary: line")
    documented = []
    for bl in body.split("\n"):
        m = ANY_NAME_LINE.match(bl)
        # a parameter of the handler, whatever its spelling (b2kCorner's
        # are c and s), or a line shaped like one (pX:, rX:) that names
        # none of them
        if m and (m.group(1) in params or PARAM_LINE.match(bl)):
            documented.append(m.group(1))
    want = [p for p in params]
    for p in want:
        if p not in documented:
            problems.append(f"{path}:{lineno}: {name} does not document its parameter {p}")
    for p in documented:
        if p not in want:
            problems.append(f"{path}:{lineno}: {name} documents {p}, which is not one of its parameters")


def check_file(path, text, exempt, problems, documented_names, links):
    is_lcb = path.endswith(".lcb")
    pending = None
    library_seen = False
    blocks_seen = 0
    handlers_seen = 0
    public = {}
    keyword = {}
    documented = set()
    private = set()
    for kind, lineno, item in scan(path, text):
        if kind == "error":
            problems.append(f"{path}:{lineno}: {item}")
            continue
        if kind == "block":
            blocks_seen += 1
            if not is_lcb:
                for k, bl in enumerate(item.split("\n")):
                    if CODE_SHAPE.match(bl):
                        problems.append(f"{path}:{lineno + k}: a block line reads as code to the "
                                        f"line-based tools: {bl.strip()[:50]}")
            for m in LINK.finditer(item):
                links.append((path, lineno, m.group(1)))
            if pending is not None:
                if not is_lcb and blocks_seen == 2 and handlers_seen == 0 and not library_seen:
                    if not re.search(r"^\s*Title:\s*\S", pending[1], re.M):
                        problems.append(f"{path}:{pending[0]}: the library block has no Title: line")
                    check_elements(path, pending[0], pending[1], LIBRARY_ELEMENTS, [],
                                   "the library block", problems)
                    library_seen = True
                else:
                    problems.append(f"{path}:{pending[0]}: orphan doc block (another block follows it)")
            pending = (lineno, item)
            continue
        line = item
        if is_lcb:
            if LCB_LIBRARY.match(line):
                if pending is None:
                    problems.append(f"{path}:{lineno}: no doc block above the library line")
                else:
                    check_elements(path, pending[0], pending[1], LIBRARY_ELEMENTS, [],
                                   "the library block", problems)
                    library_seen = True
                pending = None
                continue
            m = LCB_HANDLER.match(line)
            if m:
                name, params = m.group(1), lcb_params(m.group(2))
                public[name] = lineno
                if pending is not None:
                    check_block(path, pending[0], pending[1], name, params, problems)
                    documented.add(name)
                pending = None
                continue
        else:
            m = LCS_PRIVATE.match(line)
            if m:
                private.add(m.group(2))
            else:
                m = LCS_HANDLER.match(line)
                if m:
                    handlers_seen += 1
                    name = m.group(2)
                    public[name] = lineno
                    keyword[name] = m.group(1).lower()
                    if pending is not None:
                        check_block(path, pending[0], pending[1], name, lcs_params(m.group(3)), problems)
                        documented.add(name)
                    pending = None
                    continue
        if pending is not None:
            problems.append(f"{path}:{pending[0]}: orphan doc block (followed by: {line.strip()[:60]})")
            pending = None
    if pending is not None:
        problems.append(f"{path}:{pending[0]}: orphan doc block at the end of the file")
    if not library_seen:
        problems.append(f"{path}: no library doc block")
    for name, lineno in sorted(public.items(), key=lambda x: x[1]):
        if name in documented:
            continue
        if name in exempt:
            continue
        problems.append(f"{path}:{lineno}: public handler {name} has no doc block")
    for name in sorted(exempt):
        if name not in public:
            problems.append(f"{path}: stale exemption {name} (no such public handler)")
        elif name in documented:
            problems.append(f"{path}: stale exemption {name} (it is documented)")
        elif keyword.get(name, "on") != "on":
            problems.append(f"{path}:{public[name]}: exempt handler {name} is declared "
                            f"`{keyword[name]}`; declare it `on`, or Beyond's docs parser "
                            f"logs 'Required documentation not found' for it")
    documented_names.update(documented)
    return len(documented)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    problems = []
    names = set()
    links = []
    total = 0
    for rel in CORPUS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            problems.append(f"{rel}: missing (a CORPUS row with no file)")
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read().replace("\r\n", "\n")
        total += check_file(rel, text, EXEMPT.get(rel, {}), problems, names, links)
    for rel in EXEMPT:
        if rel not in CORPUS:
            problems.append(f"{rel}: EXEMPT row for a file outside CORPUS")
    for rel, lineno, name in links:
        if name not in names:
            problems.append(f"{rel}:{lineno}: <{name}> links to no documented handler")
    if problems:
        for p in problems:
            print("check-dictionary-docs: " + p)
        print(f"check-dictionary-docs: FAILED ({len(problems)} problem(s))")
        return 1
    print(f"check-dictionary-docs: OK ({total} handler(s) documented across {len(CORPUS)} "
          f"library file(s), {sum(len(v) for v in EXEMPT.values())} exempt with a reason)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
