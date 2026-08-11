#!/usr/bin/env python3
"""check-suite-coverage.py - does the pasteable suite harness actually exercise
the suite?

WHY THIS EXISTS. tools/build-suite-selftest.py guarantees that the harness a
maintainer pastes into an engine is CURRENT - that it is exactly what the member
harnesses produce. It says nothing at all about whether those harnesses are
COMPLETE. Those are different questions, and only the first one had a gate. A
member could ship a new public handler, never test it, and every gate in the
repo would stay green: the generated file would be perfectly up to date with a
harness that does not touch the new code.

That gap is invisible from the inside. The harness is 4300 lines and runs about
580 checks, which reads as thorough, and "is it thorough?" is not a question
anyone re-asks after seeing a number that size. When it was first measured, 31
public handlers across the suite had never been called by it - including
CoinXT's cxHdDeriveChild (the single derivation step the whole HD layer loops
over) and both ABI-4 tweak entry points, which are what make an xpub watch-only
wallet agree with its xprv.

WHAT IT CHECKS. For every member, the public API surface - `public handler` in a
.lcb, top-level handlers in a src/ .livecodescript - must appear by name in
tests/suite-selftest.livecodescript, or be listed in UNTESTABLE below with the
reason it cannot run in an offline paste-into-a-stack harness. There are only
two honest reasons, and both are about the environment rather than the code:

  live-daemon   the handler talks to something that is not there (a Tor daemon)
  engine-event  the ENGINE calls it, on a socket event; a caller never does

Anything else is a gap, and this gate fails on it. It also fails on a STALE
allowlist entry, so a handler that gets deleted or renamed cannot leave a
permanent excuse behind it.

WHAT IT DELIBERATELY DOES NOT CHECK. That a handler is called is not that it is
tested well: a name appearing once in a harness that ignores its result would
pass here. This gate is a floor, not a ceiling. The depth of a check is the
member vector gate's job (coinxt/tools/check-script-vectors.py and friends);
this one exists so that a handler cannot be missed ENTIRELY without somebody
writing down why.

THE EMBEDDED SCRIPT LAYERS ARE CUT OUT FIRST, AND THE GATE FAILS IF IT CANNOT
FIND THEM. tools/build-suite-selftest.py embeds coinxt's and onionxt's pure-
script libraries into the harness verbatim, between sentinel lines, so that one
paste carries the code its tests test. A library's body names nearly its whole
own API - cxMnemonicToSeed calls cxMnemonicNormalize, the socket dispatchers
name every callback - and none of those mentions is a TEST. Scanned uncut, the
harness scores both members at a permanent 100% (measured: 309/309, the 18
live-daemon/engine-event exemptions silently absorbed), and every future
handler arrives pre-"exercised" by its own definition. So the spans between the
sentinels are removed before the scan, and their ABSENCE is an error rather
than a fallback: a harness with no spans to cut means the embed contract
changed under this gate, and scanning it whole would fail open.

Usage:
  python3 tools/check-suite-coverage.py            # print the table
  python3 tools/check-suite-coverage.py --check    # same, terse, for the gates
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HARNESS = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")

# member -> (public-handler prefix, source globs that define the public API)
MEMBERS = [
    ("sodiumxt", "sx", ["sodiumxt/src/*.lcb", "sodiumxt/src/*.livecodescript"]),
    ("onionxt", "ox", ["onionxt/src/onionxt.livecodescript"]),
    ("coinxt", "cx", ["coinxt/src/*.lcb", "coinxt/src/coinxt.livecodescript"]),
    ("torrentxt", "bt", ["torrentxt/src/*.lcb", "torrentxt/src/*.livecodescript"]),
    ("enetxt", "en", ["enetxt/src/*.lcb", "enetxt/src/*.livecodescript"]),
    ("datachannelxt", "dc", ["datachannelxt/src/*.lcb",
                             "datachannelxt/src/*.livecodescript"]),
    # riptide is the capstone APP, not an extension, but its rs* surface is a
    # public API its folded harness must reach, so it rides the same ratchet.
    ("riptide", "rs", ["riptide/src/riptide.livecodescript"]),
]

# The handlers an offline harness genuinely cannot reach, and why. Keep the
# reason specific: "hard to test" is not one of the two categories, and if a
# handler only needs a fixture then it belongs in a harness, not in here.
UNTESTABLE = {
    # --- onionxt: the engine's own socket callbacks --------------------------
    # OnionXT is pure script over engine sockets, and these are what the ENGINE
    # calls when one of them does something. They take a socket id the harness
    # has no way to mint, and they mutate per-socket state keyed by it, so
    # calling them with a synthetic id would not exercise the real path - it
    # would corrupt the state of whatever socket happened to share the id.
    "oxCtlOpened": "engine-event: socket callback, engine supplies the socket id",
    "oxCtlLine": "engine-event: socket callback, engine supplies the socket id",
    "oxCtlDeadline": "engine-event: socket timeout callback",
    "oxSocksOpened": "engine-event: socket callback, engine supplies the socket id",
    "oxSocksMethod": "engine-event: SOCKS5 handshake step, driven by socket reads",
    "oxSocksReplyHead": "engine-event: SOCKS5 reply step, driven by socket reads",
    "oxSocksReplyLen": "engine-event: SOCKS5 reply step, driven by socket reads",
    "oxSocksReplyDone": "engine-event: SOCKS5 reply step, driven by socket reads",
    "oxStreamData": "engine-event: stream read callback",
    "oxStreamDeadline": "engine-event: stream timeout callback",
    "oxPeerAccepted": "engine-event: inbound connection callback",
    # --- onionxt: needs a real Tor daemon ------------------------------------
    # The honesty convention this repo uses for OnionXT is "verified statically;
    # needs an OXT pass + a live-Tor pass". These are the second half of that.
    "oxLaunchTor": "live-daemon: starts a real tor process",
    "oxStopTor": "live-daemon: stops a real tor process",
    "oxPublishService": "live-daemon: publishes a hidden service over the control port",
    "oxTransportDial": "live-daemon: dials through the SOCKS port",
    "oxTransportListen": "live-daemon: listens as a hidden service",
    "oxTransportSend": "live-daemon: writes to a live Tor stream",
    "oxTransportRecv": "live-daemon: reads from a live Tor stream",
}


# The sentinel format is a CONTRACT with tools/build-suite-selftest.py (its
# EMBED_BEGIN/EMBED_END); change it there and here together. REQUIRED_EMBEDS
# guards the dangerous direction only - spans DISAPPEARING, which would fail
# open as inflated coverage. A new span appearing (a third member growing a
# script layer) is cut automatically without being listed here.
EMBED_BEGIN_RE = re.compile(r'^-- >>> GENERATED EMBED: (.+) >>> --$')
EMBED_END_RE = re.compile(r'^-- <<< GENERATED EMBED: (.+) <<< --$')
REQUIRED_EMBEDS = {"coinxt script layer", "onionxt script layer"}


def cut_embedded_spans(text):
    """Drop every generated-embed span. Returns (kept, names_seen, problems).

    Strict about pairing: an unmatched begin means the cut would swallow the
    rest of the file, and an unmatched end means an embedded span leaked into
    the scan - both are reported rather than guessed around.
    """
    kept, names, stack, problems = [], set(), [], []
    for i, line in enumerate(text.split("\n"), start=1):
        m = EMBED_BEGIN_RE.match(line)
        if m:
            stack.append((m.group(1), i))
            names.add(m.group(1))
            continue
        m = EMBED_END_RE.match(line)
        if m:
            if not stack or stack[-1][0] != m.group(1):
                problems.append(f"line {i}: embed end '{m.group(1)}' has no "
                                f"matching begin")
            else:
                stack.pop()
            continue
        if not stack:
            kept.append(line)
    for name, i in stack:
        problems.append(f"line {i}: embed begin '{name}' never ends, so the cut "
                        f"would swallow everything after it")
    return "\n".join(kept), names, problems


def strip_comments(text):
    """Comment-free view. A handler named only in a comment is not exercised."""
    out = []
    for raw in text.split("\n"):
        buf, i, instr = "", 0, False
        while i < len(raw):
            ch = raw[i]
            if ch == '"':
                instr = not instr
                buf += ch
            elif not instr and ch == "-" and raw[i + 1:i + 2] == "-":
                break
            else:
                buf += ch
            i += 1
        out.append(buf)
    return "\n".join(out)


def public_api(prefix, patterns):
    """Every public handler a member exposes under its prefix."""
    names = set()
    for pattern in patterns:
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            src = strip_comments(open(path, encoding="utf-8").read())
            if path.endswith(".lcb"):
                names |= set(re.findall(r'^public\s+handler\s+(\w+)', src, re.M))
            else:
                names |= set(re.findall(r'^(?:command|function|on)\s+(\w+)',
                                        src, re.M))
    # `pfx1...` is a folded member harness's namespaced copy, never public API.
    # `...Inner` is the untouched body behind an itemDelimiter save/restore
    # wrapper (coinxt); the WRAPPER is the public handler and is checked.
    return {n for n in names
            if n.lower().startswith(prefix)
            and not n.lower().startswith(prefix + "1")
            and not n.endswith("Inner")}


def main(argv):
    terse = "--check" in argv[1:]

    if not os.path.exists(HARNESS):
        print("check-suite-coverage: tests/suite-selftest.livecodescript is missing "
              "- run tools/build-suite-selftest.py")
        return 1
    raw = open(HARNESS, encoding="utf-8").read()
    cut, embeds_seen, cut_problems = cut_embedded_spans(raw)
    if cut_problems:
        print("check-suite-coverage: FAILED (the embedded-span sentinels are "
              "damaged; cannot scan honestly)")
        for p in cut_problems:
            print(f"  - {p}")
        return 1
    missing_embeds = REQUIRED_EMBEDS - embeds_seen
    if missing_embeds:
        print("check-suite-coverage: FAILED")
        print("  - the harness has no embedded span(s) for: "
              + ", ".join(sorted(missing_embeds)))
        print("    Scanning it whole would count each library's own body as "
              "coverage of itself and this gate would never fail again for "
              "that member. The embed contract with tools/build-suite-selftest.py "
              "changed; update both sides together.")
        return 1
    harness = strip_comments(cut)

    problems = []
    rows = []
    every_name = set()
    total_api = total_hit = total_excused = 0

    for member, prefix, patterns in MEMBERS:
        api = public_api(prefix, patterns)
        if not api:
            problems.append(f"{member}: parsed NO public handlers - the source "
                            f"layout changed and this gate is now checking nothing")
            continue
        every_name |= api
        hit = {n for n in api if re.search(r'\b' + re.escape(n) + r'\b', harness)}
        missing = api - hit
        excused = {n for n in missing if n in UNTESTABLE}
        gaps = sorted(missing - excused)
        total_api += len(api)
        total_hit += len(hit)
        total_excused += len(excused)
        rows.append((member, len(hit), len(api), len(excused), gaps))
        if gaps:
            problems.append(
                f"{member}: {len(gaps)} public handler(s) are never called by the "
                f"suite harness and are not listed as untestable:\n      "
                + "\n      ".join(gaps)
                + f"\n      Add a check to that member's own harness and rerun "
                  f"tools/build-suite-selftest.py, or - only if it genuinely "
                  f"cannot run offline - add it to UNTESTABLE in "
                  f"tools/check-suite-coverage.py with the reason.")

    # A stale excuse is worse than none: it reads as a considered decision about
    # a handler that no longer exists, and it hides the next one that lands.
    stale = sorted(set(UNTESTABLE) - every_name)
    if stale:
        problems.append("these names are listed as untestable but no member "
                        "defines them any more (renamed or deleted?): "
                        + ", ".join(stale))

    if not terse:
        print(f"{'member':16s} {'exercised':>12s} {'untestable':>12s}")
        for member, hit, api, excused, gaps in rows:
            flag = "" if not gaps else f"   <-- {len(gaps)} GAP(S)"
            print(f"{member:16s} {hit:>6d}/{api:<5d} {excused:>12d}{flag}")
            for gap in gaps:
                print(f"{'':18s}{gap}")
        print(f"{'':16s} {'':>12s} {'':>12s}")

    if problems:
        print("check-suite-coverage: FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check-suite-coverage: OK ({total_hit}/{total_api} public handlers "
          f"exercised by the suite harness, {total_excused} documented as "
          f"needing a live daemon or an engine socket event)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
