#!/usr/bin/env python3
"""check-cross-library-names.py - one name, one library, across the suite.

WHY THIS EXISTS
    The suite's promise is that its members INTEROPERATE: any app may load
    several libraries side by side, and any demo may embed several into one
    paste-and-run file. Both put every library's names into ONE namespace -
    xTalk has a single message namespace for handlers, and a concatenated
    embed shares one file scope for column-0 declarations. Yet no gate
    checked names ACROSS libraries: check-duplicate-declarations.py is
    per-file by design, sync-demo-embeds.py compares only the combinations a
    demo actually registers, and build-suite-selftest.py only the layers the
    paste actually carries. A pair of libraries never co-embedded today was
    checked by nothing, and "not checked" became "not true" the day nostrxt
    landed: measured 2026-08-23, the enet and datachannel helper layers
    shared four script-local names (sPolling and friends - the same name
    that already reached an engine once, OXT-ENGINE-NOTES 1.6), and two
    libraries defined the engine's socket messages with only one of them
    passing foreign sockets on. Both are fixed; this gate is what keeps the
    fix true.

WHAT IT CHECKS, over the LIBRARY CORPUS below
    1. HANDLERS ARE UNIQUE, public and private alike: no handler name is
       defined in two corpus files. Private handlers count because a demo
       embed concatenates files, and two privates with one name are a hard
       compile error at paste time. The engine's own socket message names
       (socketError / socketClosed / socketTimeout) are the one exception -
       they CANNOT be unique, which is why they get check 2 instead.
    2. ENGINE SOCKET MESSAGES PASS: every corpus file that defines one of
       the engine's socket messages must `pass` it inside that handler, so
       a library acts on its OWN sockets and hands the rest down the message
       path. Swallowing another library's socket event is a silent HANG no
       other gate can see (the family rule two shipping apps re-derived
       independently; docs/OXT-ENGINE-NOTES.md's message-path notes). This
       is a static floor: it proves the pass EXISTS, not that the act-only-
       on-own logic above it is right - that stays the reviewer's job.
    3. COLUMN-0 DECLARATIONS ARE UNIQUE: no script-level `local` or
       `constant` name is declared in two corpus files, so ANY pair of
       libraries can be co-embedded into one file without a collision -
       not just the pairs registered today.
    4. PUBLIC NAMES CARRY THEIR PREFIX: every public handler in a corpus
       file begins with one of that file's registered prefixes (engine
       messages exempt). This is the ratchet that catches the NEXT
       collision before it exists: an unprefixed public is a collision
       waiting for a second library to want the same word.

WHAT IS DELIBERATELY OUT OF THE CORPUS
    Stack-shaped files: demos, harnesses and the apps (nocloud, holde-em,
    the quickshare stacks). A stack's handlers live in its own message path
    - they are opened, not `start using`-ed - so they do not enter another
    stack's namespace, and the combinations that DO share a file (a demo
    plus its embedded libraries) are collision-checked pairwise by
    sync-demo-embeds.py and build-suite-selftest.py at generation time.
    Their socketError pass-through duty is documented per member
    (torrent-quickshare's NOT_EMBEDDED entry is the standing record).

USAGE
    python3 tools/check-cross-library-names.py
    Exit 0 when every check holds, 1 otherwise.
    tools/test-cross-library-names.py mutation-proves each check fires.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The library corpus: every file an app may load, or a demo may embed,
# alongside the others - with the public prefixes each has registered
# (mirroring tools/check-handler-calls.py's prefix registry).
SCRIPT_LIBS = {
    "coinxt/src/coinxt.livecodescript": ("cx",),
    "onionxt/src/onionxt.livecodescript": ("ox",),
    "onionxt/src/onion-httpd.livecodescript": ("oxh",),
    "box2dxt/src/box2dxt-kit.livecodescript": ("b2k",),
    "riptide/src/riptide.livecodescript": ("rs",),
    "nostrxt/src/nostrxt.livecodescript": ("nx",),
    "nostrxt/src/nostr-relay.livecodescript": ("nxr",),
    "enetxt/examples/enet-helpers.livecodescript": ("en",),
    "datachannelxt/examples/datachannel-helpers.livecodescript": ("dc",),
    "coinxt/examples/wallet-core.livecodescript": ("cw",),
}

LCB_LIBS = {
    "sodiumxt/src/sodium.lcb": ("sx",),
    "torrentxt/src/torrent.lcb": ("bt",),
    "enetxt/src/enet.lcb": ("en",),
    "datachannelxt/src/datachannel.lcb": ("dc",),
    "coinxt/src/coinxt.lcb": ("cx",),
    "box2dxt/src/box2dxt.lcb": ("b2",),
}

ENGINE_MESSAGES = ("socketError", "socketClosed", "socketTimeout")

HANDLER_RE = re.compile(
    r"^(private\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)", re.M)
DECL_RE = re.compile(r"^(?:local|constant)\s+(.+)$", re.M)
LCB_PUB_RE = re.compile(r"^\s*public handler\s+(\w+)", re.M)
IDENT_RE = re.compile(r"[A-Za-z_]\w*$")


def strip_comments(text):
    return "\n".join(ln.split("--", 1)[0] for ln in text.split("\n"))


def handler_bodies(code):
    """name -> body text, for the pass-discipline check."""
    bodies, name, buf = {}, None, []
    for ln in code.split("\n"):
        m = HANDLER_RE.match(ln)
        if m:
            name, buf = m.group(2), []
            continue
        if name is not None:
            if re.match(r"^end\s+" + re.escape(name) + r"\b", ln.strip()):
                bodies[name] = "\n".join(buf)
                name = None
            else:
                buf.append(ln)
    return bodies


def main(argv):
    problems = []
    owners_handler = {}     # name -> first owning file
    owners_decl = {}

    for rel, prefixes in sorted(SCRIPT_LIBS.items()):
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            problems.append(f"{rel}: registered in the corpus but missing - "
                            "update the registry with the move, do not let it "
                            "rot")
            continue
        code = strip_comments(open(path, encoding="utf-8").read())
        bodies = handler_bodies(code)
        for is_private, name in HANDLER_RE.findall(code):
            if name in ENGINE_MESSAGES:
                # check 2: the pass-discipline floor
                body = bodies.get(name, "")
                if not re.search(r"^\s*pass\s+" + name + r"\b", body, re.M):
                    problems.append(
                        f"{rel}: defines the engine message `{name}` without "
                        f"a `pass {name}` - a foreign library's socket event "
                        "dies here silently (the message-path hang rule)")
                continue
            if name in owners_handler and owners_handler[name] != rel:
                problems.append(
                    f"handler `{name}` is defined in BOTH "
                    f"{owners_handler[name]} and {rel} - two libraries "
                    "cannot share a name in one message path or one embed")
            owners_handler.setdefault(name, rel)
            if not is_private:
                if not any(name.startswith(p) for p in prefixes):
                    problems.append(
                        f"{rel}: public handler `{name}` does not carry this "
                        f"library's prefix ({' / '.join(prefixes)}) - an "
                        "unprefixed public is the next collision waiting")
        for rest in DECL_RE.findall(code):
            rest = rest.split("=", 1)[0]
            for piece in rest.split(","):
                piece = piece.strip()
                if not IDENT_RE.fullmatch(piece):
                    continue
                if piece in owners_decl and owners_decl[piece] != rel:
                    problems.append(
                        f"script-level `{piece}` is declared in BOTH "
                        f"{owners_decl[piece]} and {rel} - co-embedding "
                        "those two files is a compile error at paste time")
                owners_decl.setdefault(piece, rel)

    for rel, prefixes in sorted(LCB_LIBS.items()):
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            problems.append(f"{rel}: registered in the corpus but missing - "
                            "update the registry with the move")
            continue
        text = open(path, encoding="utf-8").read()
        for name in LCB_PUB_RE.findall(text):
            if name in owners_handler and owners_handler[name] != rel:
                problems.append(
                    f"handler `{name}` is defined in BOTH "
                    f"{owners_handler[name]} and {rel}")
            owners_handler.setdefault(name, rel)
            if not any(name.startswith(p) for p in prefixes):
                problems.append(
                    f"{rel}: public handler `{name}` does not carry this "
                    f"extension's prefix ({' / '.join(prefixes)})")

    for p in problems:
        print("check-cross-library-names: " + p)
    if problems:
        print(f"check-cross-library-names: {len(problems)} problem(s)")
        return 1
    print(f"check-cross-library-names: OK ({len(owners_handler)} handler "
          f"name(s) and {len(owners_decl)} script-level name(s) across "
          f"{len(SCRIPT_LIBS) + len(LCB_LIBS)} library file(s), each owned "
          "by exactly one; every engine socket message passes; every public "
          "name carries its prefix)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
