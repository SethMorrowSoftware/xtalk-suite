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

That gap is invisible from the inside. The harness was 4300 lines running about
580 checks when this was written (34343 lines today), which reads as thorough,
and "is it thorough?" is not a question anyone re-asks after a number that size.
When it was first measured, 31 public handlers across the suite had never been
called by it - including CoinXT's cxHdDeriveChild (the single derivation step
the whole HD layer loops over) and both ABI-4 tweak entry points, which are what
make an xpub watch-only wallet agree with its xprv.

WHAT IT CHECKS. For every member, the public API surface - `public handler` in a
.lcb, top-level handlers in a src/ .livecodescript - must appear by name in the
SCANNED VIEW of tests/suite-selftest.livecodescript - comments stripped, the
embedded library spans cut, string literals blanked, the last two each with a
section below. Anything not named there must be listed in UNTESTABLE with the
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

STRING LITERALS ARE BLANKED BEFORE THE SCAN, AND THE NEXT GATE MUST USE THE SAME
CONVENTION. Until 2026-08-17 the hit scan was a bare `\\bname\\b` over text that
still held every string literal in the harness, so a handler counted as
exercised if a TEST LABEL happened to spell its name. That is not a theoretical
hole - it fired, in the worst direction available. TorrentXT's harness ends with
a section headed "not auto-checked - confirm by hand" whose three notes read:

    btMoveStorage + btRemoveTorrent(deleteFiles=true) are destructive;
    btSetFilePriorities needs a binary buffer; btAddTorrentWithResume
    needs async resume bytes; btAddMagnet is covered via btAddMagnetEx.

Four handlers - btMoveStorage, btSetFilePriorities, btAddTorrentWithResume and
btAddMagnet - had no other surviving mention anywhere in the scanned text. So
this gate was accepting, as its proof that they were exercised, a sentence whose
content is that they are not. (btAddMagnet is the instructive one: it HAS a real
call, in riptide's rsMediaFetch - inside the embedded riptide layer, which the
cut above correctly removes. Measure before the cut and it looks fine; measure
what the gate actually scans and it is a note.) The advertised 724/742 was
720/742 by the gate's own definition. That is the coinxt-constant-gate failure
again, in the same shape - a count of what was PARSED presented as a count of
what was CHECKED - and root CLAUDE.md's verdict on it applies unchanged: a gate
that overstates its coverage is worse than no gate, because it answers the
question nobody asks twice.

THE CONVENTION, spelled out because a second gate is about to be built on it.
Every double-quoted literal is blanked to spaces - the quotes are kept, so line
lengths survive and a blanked line is still readable when dumped - EXCEPT on a
line where `do`, `dispatch`, `send` or `stThrows` appears OUTSIDE a literal.
There the raw line is kept, because on such a line a name inside a literal IS a
call site: `do "get" && pHandler` is how cx1stThrows2 drives the handler it is
given, and `send "b2kFell" to me` is how the b2k Kit dispatches. Measured
2026-08-17, the carve-out fires on 72 lines and is load-bearing for exactly one
handler - cxBech32EncodeValues, whose three surviving mentions are all
cx1stThrows2 dispatches (720/742 with the carve-out, 719/742 without it). Two
details of it are deliberate:

  - The keyword test runs on the BLANKED line, not the raw one, so prose that
    merely contains the word cannot carve itself out. Measured both ways:
    matching raw carves 86 lines, matching blanked carves 72, and the coverage
    total is identical - the 14 lost were all prose ("what do ya want for
    nothing?", the Jefe HMAC vector, three copies; "static terrain helpers do
    not enter the control table"). Same answer, 14 fewer places to be wrong.
  - The carve-out is the one place this gate fails OPEN, so its keyword list is
    a fixed literal set and has to stay short. Widening it - to `put`, say -
    would quietly reopen the hole this section exists to close.

LiveCodeScript has no backslash escapes inside a literal (a quote is written as
the `quote` constant), so toggling on `"` is exact rather than approximate -
the same assumption strip_comments() below has always made. Blanking is per
line, because a literal cannot span a physical line break even under a `\\`
continuation.

THE HOLDE-EM HARNESS-REGION RATCHET MUST SCAN THROUGH blank_string_literals()
TOO. That is the open item at the bottom of MEMBERS, and it is the single worst
place to skip this: holde-em is one 15k-line file where the game's prose, its
wire-protocol names, its `send`-armed message names and its test labels all sit
beside the API being measured. Scanned with literals in, it would report a
number that reads as proof of a coverage it has not got - which is the failure
this section just closed, arriving somewhere with far more string literals to
be wrong about.

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
    # BOX2DXT IS MEASURED AS ITS KIT, AND THE RAW b2* BINDING IS NOT IN THIS
    # RATCHET. That is a deliberate scope call, and the numbers behind it are
    # here so the next reader can re-take it rather than inherit it:
    #
    #   src/box2dxt-kit.livecodescript   313 public b2k* handlers - the
    #     game-facing API, pure LiveCodeScript, embedded in the suite paste
    #     and driven by box2dxt's folded harness. RATCHETED, below.
    #   src/box2dxt.lcb                  376 public b2* handlers - a 1:1
    #     binding over the C shim (374 foreign declarations for 376 public
    #     handlers; the bodies are checkABI + unsafe + call). NOT ratcheted.
    #
    # The reason is measurement, not convenience. Of those 376, the Kit names
    # 131 and **245 are named by no script anywhere in box2dxt** - not the
    # Kit, not the six example stacks, not the harness. Ratcheting them here
    # would mean writing ~375 new assertions against a foreign-bound API in
    # one pass, with no engine to run them on, into the file the whole suite
    # is pasted from. box2dxt's own CLAUDE.md records its measured base rate
    # for new tests as "5 Kit bugs : 5 harness bugs - expect first-contact
    # arithmetic errors", so that trade buys a near-certain red suite run in
    # exchange for a number. The alternative - 375 allowlist entries sharing
    # one reason - is the "gate that overstates its coverage" this repo
    # already learned to distrust (coinxt's constant gate, root CLAUDE.md).
    #
    # What that layer HAS: tests/smoke_test.c drives the C ABI under
    # ASan/UBSan in build-all.sh and in native-box2dxt.yml, and the Kit's own
    # 313 handlers - every one of which is exercised here - are what call it.
    # What it does NOT have is a script-level ratchet, and that is an open
    # item, not a closed one.
    ("box2dxt (kit)", "b2k", ["box2dxt/src/box2dxt-kit.livecodescript"]),
    #
    # HOLDE-EM HAS NO ROW HERE, AND THAT IS A DECISION WITH NUMBERS BEHIND IT
    # rather than an omission. It was folded into the suite harness on
    # 2026-08-16; what follows is what a `("holde-em", "he", [...])` row would
    # actually measure, so the next reader can re-take the call instead of
    # inheriting it.
    #
    #   holde-em/src/holdem.livecodescript   ONE 15,276-line paste-and-run stack
    #     holding 379 public he* handlers - the game AND its 21-section harness
    #     in the same file. There is no second file, so there is no glob that
    #     isolates a subset either.
    #
    # Measured against the harness this gate actually scans:
    #
    #   0 / 379   as this gate is written. The fold prefixes every name the
    #             file defines, so the shipped spelling is he1heShuffleDeck and
    #             `\bheShuffleDeck\b` matches nothing inside it. A row added
    #             blind would fail with 379 phantom gaps on the day it landed.
    #   379 / 379 with the scan taught about the he1 prefix. Permanently, and
    #             on the day the row is added - because the folded section is
    #             the GAME, and the game names its own API: heHandStart calls
    #             heShuffleDeck, the react engine names every wire handler. Not
    #             one of those mentions is a test.
    #   163 / 379 counting only the names a heTest*/heProbe* body mentions
    #             directly - the closest thing to an honest number, and not one
    #             this gate can compute, because it has no way to tell a test
    #             from the code under test inside one file.
    #
    # That 379/379 is the whole reason the row is absent. It is exactly the
    # failure the embedded-span cut above exists to prevent ("a library's body
    # names nearly its whole own API"), arriving where there is nothing to cut:
    # coinxt, onionxt, riptide and the b2k Kit keep their library in a SEPARATE
    # file that is embedded (and cut) while their tests are folded, so the
    # scan sees tests naming a library. holde-em's tests and its library are
    # the same handlers' neighbours in the same file. A row here would be a
    # gate that answers a question nobody asks twice - the coinxt-constant-gate
    # lesson in root CLAUDE.md, and worse than no gate because the number would
    # read as proof.
    #
    # What that layer HAS instead, all of it in tools/build-all.sh --gates:
    # seven KAT mirrors (evaluator, betting/settlement, shuffle, protocol
    # incl. the Level 2 ristretto twins, fold, atlas, sounds) plus
    # tools/logic-fuzz.py, which checks the same logic against a SECOND,
    # independently written evaluator and settlement rather than against the
    # port. What it does NOT have is a name-level ratchet, and that is an open
    # item: closing it needs a way to scan the harness REGION of a
    # single-file member, which no mechanism in this suite has today.
]

# The handlers an offline harness genuinely cannot reach, and why. Keep the
# reason specific: "hard to test" is not one of the two categories, and if a
# handler only needs a fixture then it belongs in a harness, not in here.
UNTESTABLE = {
    # --- torrentxt: three handlers the harness must not run ------------------
    # Added 2026-08-17, when blanking string literals stopped this gate
    # counting torrentxt's own "not auto-checked - confirm by hand" note as
    # proof the handlers it names were exercised. The note's reasons were
    # always honest; they just were not entries. A fourth name in that note -
    # btAddMagnet - is NOT here: it was excused as "covered via btAddMagnetEx",
    # which is an argument about shape rather than a test (the two take
    # different argument counts, so the plain form's marshalling was never
    # exercised), so it got a real check in torrentxt's harness instead.
    #
    # These three stay excused because running them in an automated harness
    # would either destroy data or require bytes only a live swarm produces.
    # Each is on the runbook's manual list: torrentxt's "destructive-handler
    # manual pass" (REMAINING-WORK B.7).
    "btMoveStorage": "destructive: relocates a torrent's storage on disk; "
                     "manual pass only (REMAINING-WORK B.7)",
    "btSetFilePriorities": "needs a binary priority buffer sized to a real "
                           "torrent's file list, which needs metadata from a "
                           "live swarm; manual pass only",
    "btAddTorrentWithResume": "needs async resume bytes, which only a real "
                              "btSaveResumeData round trip produces; the "
                              "resume path is runbook B.7's restart pass",

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
REQUIRED_EMBEDS = {"coinxt script layer", "onionxt script layer",
                   "box2dxt-kit script layer"}


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


# The carve-out for the literal blanking below: the spellings that make a name
# inside a string a genuine call site rather than prose about one. IGNORECASE
# because LiveCodeScript keywords are case-insensitive, though measured
# 2026-08-17 it changes nothing in this tree (all 72 carved lines are lowercase).
# THIS IS THE ONE PLACE THIS GATE FAILS OPEN - keep the list short and literal.
DISPATCH_RE = re.compile(r'\bdo\b|\bdispatch\b|\bsend\b|stThrows', re.I)


def blank_literals_in_line(raw):
    """One line with every double-quoted literal blanked to spaces.

    The quotes stay so the line keeps its length (and stays legible if it is
    ever printed). Toggling on `"` is exact, not a heuristic: LiveCodeScript has
    no in-literal escape - a quote character is the `quote` constant - so there
    is no such thing as an embedded, escaped quote to be fooled by.
    """
    buf, instr = "", False
    for ch in raw:
        if ch == '"':
            instr = not instr
            buf += ch
        elif instr:
            buf += " "
        else:
            buf += ch
    return buf


def blank_string_literals(text):
    """Literal-free view, minus the dispatch carve-out. THE convention.

    See the module docstring for why this exists and what it cost to learn. The
    holde-em harness-region ratchet must scan through THIS function, not a copy
    of it with its own idea of the carve-out.
    """
    out = []
    for raw in text.split("\n"):
        blanked = blank_literals_in_line(raw)
        # The keyword test runs on the BLANKED line on purpose. Matched against
        # the raw line, any note containing the word "do" or "send" carves ITSELF
        # out and hands its literals back to the scan - measured, that is 14 of
        # 86 lines here and every one of them prose.
        out.append(raw if DISPATCH_RE.search(blanked) else blanked)
    return "\n".join(out)


def literal_only_mentions(name, mentioned, harness):
    """The lines where `name` survives commenting-out but not the blanking.

    Worth the extra pass purely for the failure message: after the blanking, a
    maintainer who greps the harness for a handler this gate has just called a
    gap FINDS the name and concludes the gate is broken. It is not - the mention
    is a label. Quote the line back at them and the argument is over.
    """
    pat = re.compile(r'\b' + re.escape(name) + r'\b')
    return [a.strip() for a, b in zip(mentioned.split("\n"), harness.split("\n"))
            if pat.search(a) and not pat.search(b)]


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
    # Two views, because the failure message needs the difference between them:
    # `mentioned` is what a grep of the harness would find, `harness` is what
    # counts as a call.
    mentioned = strip_comments(cut)
    harness = blank_string_literals(mentioned)

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
            detail = []
            for gap in gaps:
                shown = literal_only_mentions(gap, mentioned, harness)
                if shown:
                    detail.append(f"{gap}\n         named ONLY inside a string "
                                  f"literal, which is not a call: "
                                  f"{shown[0][:100]}")
                else:
                    detail.append(gap)
            problems.append(
                f"{member}: {len(gaps)} public handler(s) are never called by the "
                f"suite harness and are not listed as untestable:\n      "
                + "\n      ".join(detail)
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
