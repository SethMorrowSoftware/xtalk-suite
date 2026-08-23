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

THE HOLDE-EM HARNESS-REGION RATCHET, ADDED 2026-08-17, ADVISORY ON PURPOSE.
Every row in MEMBERS is (a library file) measured against (the folded harness),
and the two are different files, which is what lets the scan tell a test from
the code under test. holde-em has no such pair: its game and its harness are
ONE file, so the row it could not have is replaced by a REGION SPLIT of that
one file - which is the same move as the embedded-span cut above, done with a
boundary line instead of a sentinel:

    holde-em/src/holdem.livecodescript
      lines 1 .. <boundary>     the GAME - the denominator, 330 public he*
      <boundary> .. EOF         the HARNESS - the scanned text, 51 handlers

The boundary is `command heRunSelftest`, the first of the two entry points, and
it is RE-FOUND on every run rather than pinned to a line number. Everything
below it is a test (heTest*/heT*/heRunSection/heReport*), and the gate refuses
a build where it is not - a game handler written below the banner would
silently leave the denominator, which is a coverage number rising because the
thing it measures shrank.

THE TWO STRING CONVENTIONS ARE DIFFERENT ON PURPOSE, and that is the one part
of this worth reading twice. Reachability KEEPS literals; coverage BLANKS them:

  - Reachability asks "does this test run?", and this harness arms its sections
    by literal name - `heRunSection "heTestFoldRun"` reaching `do pName`. A
    literal is how a section is WIRED, so cutting them would report every
    section as dead. (This is the same walk, with the same deliberate
    over-approximation, as check 7d in tools/check-suite-selftest.py, which
    asks the opposite question of the same graph - what must NOT be reachable.
    The two share a shape; a fix to either is worth considering for the other.)
  - Coverage asks "is this handler CALLED?", and there a literal is a label
    until proven otherwise - the whole lesson of the section above. So the
    numerator scans through blank_string_literals(), the same function, not a
    copy with its own idea of the carve-out.

Measured 2026-08-17, the difference between the two conventions here is exactly
two names, and they are one of each kind - which is as clean a demonstration as
this tree is going to get:

    heHandStart     survives ONLY inside a test label ("ante: short SB posts
                    from the post-ante stack (heHandStart P0 fix)"). Nothing
                    calls the hotseat hand opener. Counting the label would have
                    been the btMoveStorage failure again, in a file carrying
                    7044 string literals in code to be wrong about.
    heProbeSodium   survives ONLY inside `heRunSection "heProbeSodium"`, which
                    IS the call - it is the last section of every run. Blanked
                    away, so it is carried in the worklist below under
                    `dispatch`, with the call site quoted and CHECKED.

THE NUMBER, AND WHAT IT MEANS - stated in full because four earlier attempts at
it gave four different answers (304/379, 161/313/66, 146/282/97, 174/205; those
are carried as history, not re-derived here) and every one of them measured
something slightly different. Note that all four say 379 and this says 381:
2026-08-17's heTestHelpersRun brought a handler with it and 07bbf4f brought
another later the same day, which is a small reminder that a figure written into
prose is a snapshot and this one is not:

    119 / 329   public he* handlers DEFINED IN THE GAME REGION that are named
                by the body of a harness-region handler REACHABLE from
                heSelfTest, comments stripped and string literals blanked.
                +1 (heProbeSodium, above) = 120 actually exercised.
                209 are named by nothing that runs.

                MOVED, and the paragraph above predicted it: 07bbf4f
                (2026-08-17) extracted heAwardedPot from the fold loop so an
                assertion could reach it, above the boundary, and every figure
                here shifted by one. The tool prints 120 / 330, +1 = 121 / 330,
                and the file now defines 381 public he* - 330 game + 51
                harness. 209 is unchanged, because the numerator and the
                denominator both grew. The four historical answers above stay
                as written; they are history.

Not a closure: a handler the game calls internally does not count, exactly as
cxMnemonicNormalize does not count for coinxt. The 7d-style closure of the same
graph scores 265/330, and that number is the inflation this whole file exists
to refuse. Whole-region scan and reachable-bodies scan agree today (120 both),
because every harness handler except the three interactive-delivery ones is
reachable - which the gate now checks, so an unwired test section is a failure
rather than a silent contributor to the numerator.

IT DOES NOT FAIL THE BUILD YET, and that is deliberate rather than unfinished.
209 is a real number and it has to be on the record BEFORE anything ratchets on
it, or the first person to look at a red gate goes looking for a convention
that makes it smaller - and this file's history is one long argument that the
convention is the thing you must not choose to fit the number. What IS enforced
is everything that would make the number a LIE: the boundary, the shape of the
region, the reachability of every section, and the one dispatch entry. See
holdem_region_report() for the exact split.

HOW THE ENFORCED HALF WAS CHECKED, AND WHAT IS STILL OWED. Each of those checks
was driven against a MUTATED temp copy of holdem.livecodescript on 2026-08-17 -
a second boundary line, a game handler moved below the banner, a section
unwired from heTestRunAllSections, the heProbeSodium dispatch deleted, an `end`
line renamed, heSelfTest renamed, the header block comment closed early,
heReportShow made reachable - and every one turned this row red while the
untouched tree stayed green. Two of them CHANGED the gate: the denominator
tripwire and the second capital in HOLDEM_TEST_NAME_RE both exist because a
mutation walked straight past the first version, and both comments say what
walked past. THOSE MUTATIONS ARE NOT COMMITTED, which by this repo's own
standard (tools/test-checker.py; root CLAUDE.md's "shipped is not run") makes
this paragraph an attestation and not yet a fixture. Arming the ratchet is the
moment to make it one.

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
    # nostrxt's TWO script files share the nx stem (nxr is the relay layer,
    # the oxh-to-ox relationship). The relay file is deliberately NOT
    # embedded in the paste (it defines the engine's socket handlers, which
    # the onionxt layer already defines), so its handlers are reached by the
    # folded harness's probe-guarded section: every nxr* name appears in a
    # real call that SKIPS at runtime in the paste and RUNS in the demo,
    # which is what keeps this row exemption-free.
    ("nostrxt", "nx", ["nostrxt/src/nostrxt.livecodescript",
                       "nostrxt/src/nostr-relay.livecodescript"]),
    # THE TWO POLL DISPATCHERS ARE NOT HERE, AND A ROW WOULD LIE (2026-08-19).
    # enetxt/examples/enet-helpers.livecodescript and its datachannelxt twin are
    # SHIPPED libraries - the layer every demo drives and every doc teaches -
    # and the enetxt/datachannelxt rows below scope to src/, so this gate has
    # never seen their 15 public handlers. Measured before anything was done
    # about it: the suite paste named ZERO of them.
    #
    # They are tested now (a section in each member harness, carried in by
    # tools/sync-demo-embeds.py so harness and library are one script), but a
    # ROW here would still be dishonest, and the reason is worth carrying:
    #
    #   the fold puts the library's own BODY into the paste, and the fold does
    #   not keep the sync-demo-embeds sentinels. cut_embedded_spans() below cuts
    #   `GENERATED EMBED` spans - the four script layers - so it cannot cut
    #   these. The scan would therefore count `command dcStartPolling` and the
    #   `send "dcChannelPollOnce"` INSIDE that library as coverage of itself,
    #   and report 8/8 for a surface whose tests deliberately arm neither.
    #
    # That is exactly the fake 309/309 this file's header records from before
    # the span cut existed, arrived at from the other direction. Ratcheting
    # these needs a way to tell an embedded library from a test - the sentinels
    # surviving the fold, most likely - not a row added on top of a number that
    # counts a library naming itself.
    #
    # BOX2DXT IS MEASURED AS ITS KIT, AND THE RAW b2* BINDING IS NOT IN THIS
    # RATCHET. That is a deliberate scope call, and the numbers behind it are
    # here so the next reader can re-take it rather than inherit it:
    #
    #   src/box2dxt-kit.livecodescript   313 public b2k* handlers - the
    #     game-facing API, pure LiveCodeScript, embedded in the suite paste
    #     and driven by box2dxt's folded harness. RATCHETED, below.
    #   src/box2dxt.lcb                  376 public b2* handlers - a 1:1
    #     binding over the C shim (373 foreign declarations, 370 of them
    #     binding into this member's own library; the bodies are checkABI +
    #     unsafe + call). NOT ratcheted. The other three binds are libc -
    #     _dlopen, _dlerror and _realpath, box2dxt.lcb:460/461/465 - which is
    #     why `grep -c 'binds to'` says 373 and `grep -c 'c:box2dxt>'` says
    #     370, and neither is wrong. This line used to say 374, retracted in
    #     root CLAUDE.md: that came from `grep -c 'foreign handler'`, which
    #     also matches box2dxt.lcb:16, a sentence of header PROSE about the
    #     foreign handlers. A number is only as good as the command that
    #     produced it, which is this file's own subject.
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
    # What that layer HAS, stated with the number rather than the adjective
    # (measured 2026-08-17 by GCOV, not by grep): tests/smoke_test.c drives
    # **194 of the 370 LC_API exports** - it drove 53 that morning - in
    # build-all.sh (Release) and under ASan/UBSan in native-box2dxt.yml's
    # sanitize job, and the Kit's own 313 handlers, every one of which is
    # exercised here, are what call into it.
    #
    # THE OLD BASELINE FOR THIS WAS 60, AND 60 WAS A GREP ARTIFACT. It came
    # from counting b2lc_* tokens in smoke_test.c, which also matched the
    # file's `extern` DECLARATION block - and six exports sat in that block
    # declared and never called by any line, so every count of "what the smoke
    # test reaches" had been counting them as covered. A declaration is not a
    # call: the same shipped-is-not-run lesson this file's own history turns
    # on, one level down in the toolchain. All six are called now.
    #
    # Signatures across that boundary are checked separately by
    # box2dxt/tools/check-lcb-signatures.py (370 binds vs 370 LC_API
    # definitions, return type + arity + per-parameter type).
    # What this layer does NOT have is a script-level ratchet, and that is an
    # open item, not a closed one.
    ("box2dxt (kit)", "b2k", ["box2dxt/src/box2dxt-kit.livecodescript"]),
    #
    # HOLDE-EM STILL HAS NO ROW IN THIS LIST, and it never can have one: every
    # row here is (a library file) measured against (the folded harness), and
    # holde-em has no such pair - its game and its 22-section harness are the
    # same 15k-line file. It is measured instead by the HARNESS-REGION RATCHET
    # at the bottom of this file, which splits that one file where the game
    # ends and the harness begins and then asks this list's question across the
    # cut. See HOLDEM_* below for what it measures and what it does not.
]

# The handlers an offline harness genuinely cannot reach, and why. Keep the
# reason specific: "hard to test" is not one of the two categories, and if a
# handler only needs a fixture then it belongs in a harness, not in here.
UNTESTABLE = {
    # --- onionxt: the engine's own socket callbacks --------------------------
    # OnionXT is pure script over engine sockets, and these are what the ENGINE
    # (or, for the two WATCHDOGS, a self-sent `send ... to me in <timeout>`)
    # calls back. The exemption each one carries is NARROWER than the reason
    # this block used to give, and the old reason was wrong twice:
    #   - "the harness has no way to mint a socket id" is about the ARGUMENT,
    #     but every one of these opens by TESTING that argument (against
    #     sControlSocket, or as a key into sSockToStream / sStreams) and exits
    #     on a miss. A synthetic id therefore exercises the guard and nothing
    #     else - which is a fine thing to be exempt from, but it is not the
    #     thing the text claimed.
    #   - "it would corrupt the state of whatever socket happened to share the
    #     id" was false in the direction that matters: the miss-exit makes 999999
    #     a clean no-op. The only way to collide is to name a LIVE id on purpose,
    #     and ours are predictable ("127.0.0.1:9050|oxs3"), so the real hazard is
    #     smaller and different from the one asserted.
    # What each reason below names instead is the leg PAST that guard - the
    # `read from socket` / `write to socket` / `close socket` work, and the
    # per-socket state only oxConnectControl or oxDial creates. Reaching it needs
    # an engine, not an argument.
    # AND NOTE THE LIMIT OF THAT: an exemption for a BODY is not an exemption for
    # its pure helpers. oxPeerAccepted's loopback guard (oxHostOfSocket +
    # oxHostIsLoopback) is pure string work, is NOT covered here, and is
    # fixture-tested offline in onionxt's harness section 10 - which is how the
    # 2026-08-17 fail-open in it was found, after this block had spent months
    # implying the whole path was unreachable.
    "oxCtlOpened": "engine-event: exits unless pSocketID IS the live control "
                   "socket, which only oxConnectControl's `open socket` mints; "
                   "past that guard it arms `read ... until crlf` and writes "
                   "PROTOCOLINFO to that socket",
    "oxCtlLine": "engine-event: same live-control-socket guard; past it the body "
                 "parses a reply/650 line and re-arms `read from socket`, so it "
                 "needs a control connection, not a string",
    "oxCtlDeadline": "WATCHDOG, not a socket callback: armed by `send ... to me "
                     "in kOxHandshakeTimeout`; exits unless pSocketID is the live "
                     "control socket, and the leg that matters calls "
                     "oxDisconnectControl (`close socket`)",
    "oxSocksOpened": "engine-event: exits on a sSockToStream miss; past it, writes "
                     "the 05 01 00 greeting to the socket and arms the 2-byte "
                     "method read",
    "oxSocksMethod": "engine-event: exits on a sSockToStream miss; past it, writes "
                     "the ATYP=3 CONNECT request to the socket and arms the 4-byte "
                     "reply-head read",
    "oxSocksReplyHead": "engine-event: exits on a sSockToStream miss; past it, "
                        "frames BND.ADDR by ATYP and arms the next `read from "
                        "socket` (a non-zero REP fails the stream closed here)",
    "oxSocksReplyLen": "engine-event: exits on a sSockToStream miss; past it, arms "
                       "the `read ... for <len+2>` that consumes the domain "
                       "BND.ADDR and port",
    "oxSocksReplyDone": "engine-event: exits on a sSockToStream miss; past it, "
                        "reports `open` to the app and arms the persistent stream "
                        "read on a socket that is now a tunnel",
    "oxStreamData": "engine-event: exits on a sSockToStream miss; past it, delivers "
                    "the chunk and re-arms `read from socket`, so it needs bytes "
                    "the engine actually read",
    "oxStreamDeadline": "WATCHDOG, not a socket callback, and its argument is a "
                        "STREAM HANDLE, not a socket id: armed by `send ... to me "
                        "in`; exits unless that stream has a socketID, which only "
                        "oxDial's `open socket` sets, and the leg past it fails the "
                        "stream closed (`close socket`)",
    "oxPeerAccepted": "engine-event: needs a socket `accept connections on port` "
                      "accepted - it reads from and closes that socket. Its "
                      "loopback guard is explicitly NOT exempt: oxHostOfSocket / "
                      "oxHostIsLoopback are pure and are fixture-tested offline in "
                      "onionxt's harness section 10",
    # --- onionxt: needs a real Tor daemon ------------------------------------
    # The honesty convention this repo uses for OnionXT is "verified statically;
    # needs an OXT pass + a live-Tor pass". These are the second half of that.
    # FOUR ENTRIES WERE DELETED FROM THIS BLOCK ON 2026-08-20, and the reason is
    # worth keeping because a stale excuse is the thing this gate is built to
    # refuse. oxPublishService, oxTransportListen, oxTransportSend and
    # oxTransportRecv were all exempted as "live-daemon", and none of the four
    # reasons survived a reading of the code. oxPublishService opens no socket
    # and starts no process: it validates arguments, fills sServices, and calls
    # oxCtlSend, which exits while sControlSocket is empty - what it needs is an
    # authenticated STATE, not a daemon. The other three are ONE-LINE WRAPPERS
    # over oxCreateServiceFromSeed, oxWrite and oxSetStreamCallback, each of
    # which this harness had already been testing offline for months under the
    # wrapped name. The exemption described what the WRAPPED handler does with a
    # live stream, not what the wrapper needs in order to be exercised. Each now
    # has a fail-closed check by its own name in onionxt/examples/onionxt-tests.
    "oxLaunchTor": "live-daemon: starts a real tor process",
    "oxStopTor": "live-daemon: stops a real tor process",
    "oxTransportDial": "live-daemon: dials through the SOCKS port - unlike the "
                       "other transport wrappers this one opens a socket "
                       "(oxDial), so its non-argument path cannot be reached "
                       "without a SOCKS listener",
}


# ==========================================================================
# holde-em: the harness-region ratchet. See the module docstring for the
# convention and the numbers; this block is the data it runs on.
# ==========================================================================
HOLDEM_SRC = os.path.join(ROOT, "holde-em", "src", "holdem.livecodescript")

# WHERE THE GAME ENDS. The file's own banner above this line reads "self-test
# harness (folded in ...)", but a banner is prose and prose gets reworded; the
# first ENTRY POINT is a handler definition, so a rename cannot leave this
# matching a stale comment. Everything from here to EOF is the harness.
HOLDEM_BOUNDARY_RE = re.compile(r'^command\s+heRunSelftest\b')

# The QUIET entry point, and the one the fold actually calls (he1heSelfTest).
# Seeding the walk here rather than at heRunSelftest is what keeps the
# interactive delivery path - report overlay, clipboard, msg - out of the
# numerator, which is the same line check 7d in tools/check-suite-selftest.py
# draws for the same reason.
HOLDEM_SEED = "heselftest"

# A TRIPWIRE ON THE DENOMINATOR, and it is here because a mutation test put it
# here rather than because it seemed prudent. `if not game_api` - the guard
# every MEMBERS row uses - is a floor of ONE, and the failure that matters is
# not the region vanishing, it is the region SHRINKING: a coverage ratio that
# improves because the thing it measures got smaller is the exact shape this
# file spends its docstring refusing.
# MEASURED 2026-08-17: delete the `*/` that closes holdem.livecodescript's
# 1041-line header and the block does NOT run to EOF, where strip_comments()
# would refuse it. It closes on the next stray `*/` in the file - which is
# inside the ordinary line comment `the bt*/session/rp1 calls are seams` - and
# swallows 2200 lines of game with it. The row went GREEN at 66/260: 69 public
# handlers had left the denominator and 15 gaps had left the worklist, and
# every printed number was smaller and wrong. 300 is a tripwire, not a target;
# if holde-em genuinely loses thirty public handlers, lower it and say why.
HOLDEM_API_FLOOR = 300

# What a handler BELOW the boundary is allowed to be called. Anything else
# down there is a game handler that has drifted past the banner, and it would
# leave the denominator silently - a coverage figure that improved because the
# thing being measured got smaller. `heTest` covers the sections
# (heTestFoldRun); `heT` + ANOTHER CAPITAL covers their helpers (heTAssert,
# heTNewHand, heTKatLog); the five spelled out are the two entry points, the
# per-section guard, and the report panel.
# THE SECOND CAPITAL IS THE WHOLE RULE, and a bare `^heT` was written here
# first. Measured: `^heT` also admits twelve REAL game handlers - heTableCreate,
# heTableInfohash, heTableJoin, heTableLogoPick, heTableLogoRender, heTableNew,
# heTempPath, heTimeoutPostOf, heTimeoutVerbOf, heTransportCycle,
# heTransportLabel, heTwoDigits - every one of which could then be written
# below the banner and quietly leave the denominator. The harness abbreviates
# (heTAct), the game spells words out (heTable), so the character after `heT`
# separates them exactly. Re-measured: zero game names match this, zero harness
# names fail it.
HOLDEM_TEST_NAME_RE = re.compile(
    r'^(?:heTest|heT[A-Z]|heRunSelftest$|heSelfTest$|heRunSection$'
    r'|heReportShow$|heReportHide$)')

# The harness-region handlers that are NOT reachable from heSelfTest, with the
# reason each one is allowed to be. All three are the INTERACTIVE delivery
# path: heRunSelftest is what a maintainer types into the message box, and it
# is the handler check 7d forbids the fold from reaching (overlay + clipboard +
# msg). Anything else unreachable is an unwired test section - a section that
# was written, is counted by nobody, and whose names would otherwise inflate
# this row. That is the shipped-is-not-run lesson at handler scale, so it is a
# failure rather than a note.
HOLDEM_DELIVERY = {
    "herunselftest": "the INTERACTIVE entry point; heSelfTest is the quiet one "
                     "and both drive one heTestRunAllSections",
    "hereportshow": "the report overlay heRunSelftest delivers into; check 7d "
                    "in tools/check-suite-selftest.py forbids the fold from "
                    "reaching it at all",
    "hereporthide": "the same overlay's Close button handler",
}

# THE WORKLIST: every public he* handler the game region defines that no
# reachable test names. IT IS NOT AN EXCUSE LIST, and the difference from
# UNTESTABLE above matters. UNTESTABLE carries a per-handler reason in one of
# two categories, both about the ENVIRONMENT, and it is enforced. This is a
# triage of DEBT: the categories say what stands between each handler and a
# test, so a later pass can attack the cheap 139 before the expensive 41, and
# the only entry here that is not debt is the single `dispatch` one.
#
# Each name was classified by what its OWN body does, not by what its callees
# do. That is the conservative direction for a worklist: heActionDo calls
# heUISetStatus, but its own body is arithmetic, so it lands in no-test where
# somebody will look at it - rather than in host-window where it would read as
# already accounted for. The evidence token for each non-obvious call is in
# the category comment; re-derive with a body scan, do not trust the grouping.
HOLDEM_WORKLIST = {
    # THE ONE ENTRY THAT IS NOT DEBT. heTestRunAllSections' last line is
    # `heRunSection "heProbeSodium"`, and heRunSection's body is `do pName` -
    # so this handler runs on every single execution of the harness. The
    # blanking convention removes the literal, by design, because the same
    # shape spells a test label. holdem_region_report() CHECKS the call site
    # rather than trusting this sentence, so the entry cannot outlive it.
    "dispatch": (
        "run on every pass, but only through `heRunSection \"<name>\"` -> "
        "`do pName`, which the literal-blanking convention cannot see",
        ["heProbeSodium"],
    ),
    # Bodies that call into torrentxt (bt*) or onionxt (ox*) directly:
    # btStartSession, btAddInfohash, btRp1Poll, oxDial, oxWrite, oxState,
    # oxCloseStream, oxCreateServiceFromSeed, oxSetStreamCallback ...
    # NOT an excuse: several of these open with holde-em's own netCap capture
    # mode (`if gGame["netCap"] is "true" then ... exit`), which is exactly how
    # the netsim sections drive the wire offline - so heNetTxTo and friends are
    # reachable for a test that sets it. Cheaper than they look; listed here
    # because the leg PAST that guard needs a session or a daemon.
    "live-transport": (
        "its own body calls torrentxt (bt*) or onionxt (ox*); the leg past "
        "holde-em's netCap capture guard needs a live session or daemon",
        ["heNetApplyWire", "heNetJoinSwarm", "heNetOnionCloseStream",
         "heNetOnionDial", "heNetOnionDrain", "heNetOnionFail",
         "heNetOnionPublish", "heNetOnionStandDown", "heNetOnionStatusTxt",
         "heNetPollTick", "heNetStart", "heNetStartOnion", "heNetStop",
         "heNetTxTo", "heOnionPeer", "heOnionStatus", "heOnionStreamEvt",
         "heProbeTorrent", "heTableCreate", "heTableJoin"],
    ),
    # b2k physics/atlas (b2kSheetFrames, b2kSpriteSetFrame, b2kSheetPersist),
    # `import`/`play audioClip`, or `the filename of this stack`. The Kit ones
    # are hard-blocked rather than merely awkward: check 7d refuses to let the
    # fold reach heKitTryInit at all, because a second b2k world would collide
    # with the one box2dxt's folded harness hand-steps in the same paste.
    "engine-media": (
        "its own body drives the b2k Kit, an audioClip, or the stack's file "
        "on disk - and the Kit half is forbidden outright by check 7d",
        ["heHasKit", "heKitReload", "heKitTryInit", "heProbeKit",
         "heProbeSounds", "heSndPlay", "heSndTryInit", "heStackFolder",
         "heUIShowCardIn"],
    ),
    # Bodies that create, delete, or read/write a property of a control on the
    # card. Testing them needs holde-em's own table built, and check 7d refuses
    # exactly that: heBuildTable would put a 1024x640 poker table on the
    # suite's card. Standalone these are testable; folded they are not, and
    # this gate measures the FOLDED harness.
    "host-window": (
        "its own body builds or mutates a control on the card; check 7d "
        "forbids the folded harness from building holde-em's table to have "
        "one",
        ["heBetSliderFromThumb", "heBetSliderHide", "heBetSliderShow",
         "heBetSliderSync", "heBuildHistory", "heBuildLobby",
         "heBuildSettings", "heBuildTable", "heDisableActions",
         "heEnableBtn", "heHistRefresh", "heHistSetVisible", "heHistVisible",
         "heHostModeCycle", "heHudRefresh", "heLobbyRefresh",
         "heLobbySetVisible", "heLobbyVisible", "heMakeActionButton",
         "heMakeAvatar", "heMakeCardSlot", "heMakeLabel", "heMakeSettingRow",
         "heRehydrateChrome", "heSeatAvatarRender", "heSeatChromeVisible",
         "heSeatFace", "heSettingsApply", "heSettingsCycle",
         "heSettingsIntervalRefresh", "heSettingsIntervalStash",
         "heSettingsRefresh", "heSettingsSetVisible", "heSettingsVisible",
         "heTableLogoRender", "heTransportCycle", "heUIClearCards",
         "heUIPromptToAct", "heUISetStatus", "heUIShowdownReveal",
         "heWipeChrome"],
    ),
    # THE REAL DEBT, and the only category with no excuse attached to it: 139
    # handlers whose bodies are arithmetic, list work, string work or state
    # transitions, every one of which a section could name today. heHandStart
    # is the one to read first - the hotseat hand opener, named in this harness
    # exactly once, inside a test LABEL. Others worth a first pass because they
    # are pure leaves: heRank5, heCardRankVal, heCardSuitVal, heTwoDigits,
    # heCountItems, heNextInList, heByteXor, heU32BEData, heHexId.
    "no-test": (
        "NO REASON - a pure or near-pure handler a section could name today, "
        "and none does. This is the debt, not an exemption",
        ["heActionDo", "heApplyCfg", "heApplyLevel", "heAuditDealLog",
         "heBetAfterAction", "heBetCloseStreet", "heBetFirstInHandAfter",
         "heBetInHandList", "heBetLiveCount", "heBetNextPending", "heBetPay",
         "heBetPayDead", "heBetSeatPending", "heByteXor", "heCallAmountFor",
         "heCancelPacedSteps", "heCardFace", "heCardRankVal",
         "heCardSuitVal", "heCfgBody", "heCfgDefaults", "heCfgEnsure",
         "heCountItems", "heCurrentPot", "heDealBoard", "heDeltaOfTxt",
         "heDrawUniform", "heEngineDo", "heEnvBodyText", "heEnvWireParse",
         "heFreshPrngState", "heHandLabel", "heHandLive", "heHandSettle",
         "heHandStart", "heHeaderTxt", "heHexId", "heHistHide", "heHistShow",
         "heHostModeLabel", "heHudMark", "heHudTick", "heIdentitySeedHex",
         "heIdentitySetup", "heInviteTxt", "heIsCardList", "heKenneyFrame",
         "heL2CardPointHex", "heL2ChainOrder", "heL2PointOkHex",
         "heL2VoidMark", "heLevel0Deck", "heLobbyHide", "heLobbyShow",
         "heLogAppend", "heLogField", "heNetApplySettle", "heNetAuditHand",
         "heNetBroadcast", "heNetBufferWire", "heNetComputeSettleTxt",
         "heNetContribCount", "heNetContribPosOk", "heNetDealFromSeeds",
         "heNetDealerBoard", "heNetDealerDeal", "heNetDealerPubHex",
         "heNetDrainBuffer", "heNetEngineFold", "heNetFoldGameWire",
         "heNetGameReact", "heNetHandReset", "heNetHandSeedHex",
         "heNetHostLost", "heNetMyContribPos", "heNetOnHandshake",
         "heNetOnRp1", "heNetOnionHello", "heNetOnionRedialGiveup",
         "heNetOracleDeal", "heNetParkHotseat", "heNetPubIsLive",
         "heNetRequestSync", "heNetRevealedDealA", "heNetSeatPos",
         "heNetSendToHost", "heNetSendWireTo", "heNetShowBoard",
         "heNetShowSeat", "heNetShowdownShow", "heNetTimeoutMiss",
         "heNetTimeoutRearm", "heNetTurnClockStart", "heNetTurnLimitSecs",
         "heNetWeDeal", "heNetXlatFlush", "heNetXlatFrom", "heNextHandTick",
         "heNextInList", "heNextLiveAfterPos", "hePaceMs",
         "hePrevLiveBeforePos", "heQuickAmount", "heRank5", "heReactToNotes",
         "heReadableErr", "heRevealStep", "heRosterHasKey", "heRotateAfter",
         "heRunoutStep", "heScheduleReveal", "heScheduleRunout",
         "heScheduleShowdown", "heSeatAvatarPick", "heSeatsAlive",
         "heSettingsHide", "heSettingsIntervalLabel", "heSettingsLevelLabel",
         "heSettingsShow", "heSettingsSoundsLabel", "heSettingsSpeedLabel",
         "heSettleStep", "heSndFilesFor", "heSndReload", "heSndVerb",
         "heSpeedMult", "heSpeedPace", "heStreamBlocksHex", "heSuitGlyph",
         "heTableLogoPick", "heTableNew", "heTempPath", "heTransportLabel",
         "heTwoDigits", "heU32BEData", "heUIHandStart",
         "heUIShowBoardStreet", "heUIShowHole", "heVerifyDetached"],
    ),
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


def strip_comments(text, what="the harness"):
    """Comment-free view. A handler named only in a comment is not exercised.

    Line count is PRESERVED, because literal_only_mentions() zips this view
    against the blanked one line by line.

    BLOCK COMMENTS ARE HANDLED, and the reason is holde-em rather than anything
    this gate used to read. /* ... */ is legal LiveCodeScript and
    holde-em/src/holdem.livecodescript opens with a 1041-line header changelog
    in one - prose about the game, naming most of its API. Scanned as code by
    the harness-region ratchet below, that header would hand the game's own
    changelog to the scan as though it were a test.
    MEASURED 2026-08-17, so this is a no-op everywhere else rather than a
    silent change of behaviour: `/*` appears ZERO times in
    tests/suite-selftest.livecodescript (the fold emits handler blocks only, so
    a header changelog never reaches it) and zero times in every source glob in
    MEMBERS. The upgrade changes no number in the table above; it is what makes
    the holde-em row honest. It also brings this function into step with its
    twin in tools/check-suite-selftest.py, which grew the same handling for the
    same file - two tools that read one source must read it identically.
    """
    out, in_block = [], False
    for raw in text.split("\n"):
        buf, i, instr = "", 0, False
        while i < len(raw):
            ch = raw[i]
            if in_block:
                if ch == "*" and raw[i + 1:i + 2] == "/":
                    in_block = False
                    i += 1
                i += 1
                continue
            if ch == '"':
                instr = not instr
                buf += ch
            elif not instr and ch == "-" and raw[i + 1:i + 2] == "-":
                break
            elif not instr and ch == "/" and raw[i + 1:i + 2] == "*":
                in_block = True
                i += 1
            else:
                buf += ch
            i += 1
        out.append(buf)
    if in_block:
        # Blanking to EOF would hide every handler below it - from the API
        # scan, which is the direction that quietly shrinks a denominator.
        raise SystemExit(f"check-suite-coverage: an unterminated /* block "
                         f"comment runs to the end of {what}.")
    return "\n".join(out)


def script_handler_names(src):
    """Top-level handler names in a comment-stripped .livecodescript.

    `private` is excluded by the anchor, which is the point: a private handler
    is not public API. Factored out so the holde-em region ratchet applies
    EXACTLY this rule to its two regions rather than a look-alike of it - the
    denominator of a coverage figure is not a place for two spellings.
    """
    return set(re.findall(r'^(?:command|function|on)\s+(\w+)', src, re.M))


def public_only(names, prefix):
    """The public-API filter, shared for the same reason as the scan above.

    `pfx1...` is a folded member harness's namespaced copy, never public API.
    `...Inner` is the untouched body behind an itemDelimiter save/restore
    wrapper (coinxt); the WRAPPER is the public handler and is checked.
    """
    return {n for n in names
            if n.lower().startswith(prefix)
            and not n.lower().startswith(prefix + "1")
            and not n.endswith("Inner")}


def public_api(prefix, patterns):
    """Every public handler a member exposes under its prefix."""
    names = set()
    for pattern in patterns:
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            src = strip_comments(open(path, encoding="utf-8").read(), path)
            if path.endswith(".lcb"):
                names |= set(re.findall(r'^public\s+handler\s+(\w+)', src, re.M))
            else:
                names |= script_handler_names(src)
    return public_only(names, prefix)


def holdem_handler_blocks(text):
    """name.lower() -> [body, ...] for every top-level he* handler in `text`.

    Deliberately the SAME parse as check 7d in tools/check-suite-selftest.py
    (which reads the folded he1* copy of this code) - one shape, two questions.
    The backreference in the `end` anchor is what makes it a block rather than
    a span to the next definition: a handler whose `end` line disagrees with
    its opening line yields no block at all, and the caller refuses that rather
    than measuring a region with a hole in it.
    """
    blocks = {}
    for m in re.finditer(r'^(?:private\s+)?(?:command|function|on)\s+(he\w+)\b'
                         r'(.*?)^end\s+\1\b', text, re.S | re.M):
        blocks.setdefault(m.group(1).lower(), []).append(m.group(2))
    return blocks


# --------------------------------------------------------------------------
# THE RAW b2* BINDING: AN ADVISORY ROW WITH A FLOOR, ADDED 2026-08-19.
#
# The block beside MEMBERS explains why box2dxt is ratcheted as its KIT and the
# raw binding is not: closing 245 handlers would mean writing ~245 assertions
# blind against a foreign-bound API in one pass. That call stands. What did NOT
# have to stand is the number being free to grow - a new b2* handler that no
# script anywhere names could land tomorrow and nothing would say so, which is
# how 245 became 245 in the first place.
#
# So this measures the same thing the prose already claims, and fails only on
# the three ways the baseline can stop matching the tree - the identical
# structure to the holde-em floor above:
#
#   unlisted  a b2* handler named by NO script and not in the baseline. The
#             floor: 245 cannot quietly become 246.
#   promoted  a baseline name a script now DOES name. Left in, it inflates
#             every later reading of "245".
#   stale     a baseline name the .lcb no longer declares (renamed/removed).
#
# CONVENTIONS MATCH THE GATE, NOT A GREP. Comments are stripped and string
# literals blanked before scanning, which is what makes this 131/245 rather
# than the 132/244 a raw token count gives - the pair root CLAUDE.md now
# records with that explanation.
B2_RAW_SCRIPTS = "box2dxt/**/*.livecodescript"
B2_RAW_LCB = "box2dxt/src/box2dxt.lcb"

B2_RAW_BASELINE = frozenset((
    "b2AABBLowerX", "b2AABBLowerY", "b2AABBUpperX", "b2AABBUpperY",
    "b2ApplyForceAt", "b2ApplyImpulseAt", "b2ApplyMassFromShapes",
    "b2BodyAABBUpdate", "b2BodyEnableContactEvents",
    "b2BodyEnableHitEvents", "b2BodyIsFixedRotation",
    "b2BodyIsSleepEnabled", "b2BodyJointAt", "b2BodyJointCount",
    "b2BodyLocalCenterX", "b2BodyLocalCenterY",
    "b2BodyLocalPointVelocityX", "b2BodyLocalPointVelocityY",
    "b2BodyLocalPointX", "b2BodyLocalPointY", "b2BodyLocalVectorX",
    "b2BodyLocalVectorY", "b2BodyMassDataUpdate", "b2BodyMoveCount",
    "b2BodyMoveFellAsleep", "b2BodyRotationalInertia", "b2BodyShapeAt",
    "b2BodyShapeCount", "b2BodyWorldPointVelocityX",
    "b2BodyWorldPointVelocityY", "b2BodyWorldPointX", "b2BodyWorldPointY",
    "b2BodyWorldVectorX", "b2BodyWorldVectorY", "b2ChainFriction",
    "b2ChainIsValid", "b2ChainRestitution", "b2ChainSegmentAt",
    "b2ChainSegmentCount", "b2ContactBeginCount", "b2ContactHitBodyA",
    "b2ContactHitBodyB", "b2ContactHitCount", "b2ContactHitNormalX",
    "b2ContactHitNormalY", "b2ContactHitSpeed", "b2ContactHitX",
    "b2ContactHitY", "b2DestroyChain", "b2DistanceCurrentLength",
    "b2DistanceEnableMotor", "b2DistanceIsLimitEnabled",
    "b2DistanceIsMotorEnabled", "b2DistanceIsSpringEnabled",
    "b2DistanceMaxLength", "b2DistanceMaxMotorForce",
    "b2DistanceMinLength", "b2DistanceMotorForce", "b2DistanceMotorSpeed",
    "b2DistanceSetMaxMotorForce", "b2DistanceSetMotorSpeed",
    "b2DistanceSpringDamping", "b2DistanceSpringHertz",
    "b2EnableSpeculative", "b2HitEventThreshold", "b2IsContinuousEnabled",
    "b2IsSleepingEnabled", "b2IsWarmStartingEnabled", "b2JointBodyA",
    "b2JointBodyB", "b2JointCollideConnected", "b2JointConstraintForceX",
    "b2JointConstraintForceY", "b2JointConstraintTorque",
    "b2JointLocalAnchorAX", "b2JointLocalAnchorAY", "b2JointLocalAnchorBX",
    "b2JointLocalAnchorBY", "b2JointType", "b2JointWakeBodies",
    "b2LoadNativeLib", "b2LoadNativeLibError", "b2LoadNativeLibHere",
    "b2MassDataCenterX", "b2MassDataCenterY", "b2MassDataInertia",
    "b2MassDataMass", "b2MaximumLinearSpeed", "b2MotorAngularOffset",
    "b2MotorCorrectionFactor", "b2MotorLinearOffsetX",
    "b2MotorLinearOffsetY", "b2MotorMaxForce", "b2MotorMaxTorque",
    "b2MotorSetAngularOffset", "b2MotorSetCorrectionFactor",
    "b2MotorSetLinearOffset", "b2MotorSetMaxForce", "b2MotorSetMaxTorque",
    "b2MouseMaxForce", "b2MouseSetMaxForce", "b2MouseSetSpringDamping",
    "b2MouseSetSpringHertz", "b2MouseSpringDamping", "b2MouseSpringHertz",
    "b2MouseTargetX", "b2MouseTargetY", "b2NewDynamicBody",
    "b2NewKinematicBody", "b2NewThreadedWorld", "b2OverlapPoint",
    "b2OverlapShape", "b2PrismaticEnableSpring",
    "b2PrismaticIsLimitEnabled", "b2PrismaticIsMotorEnabled",
    "b2PrismaticIsSpringEnabled", "b2PrismaticLowerLimit",
    "b2PrismaticMaxMotorForce", "b2PrismaticMotorForce",
    "b2PrismaticMotorSpeed", "b2PrismaticSetMotorSpeed",
    "b2PrismaticSetSpringDamping", "b2PrismaticSetSpringHertz",
    "b2PrismaticSpeed", "b2PrismaticSpringDamping",
    "b2PrismaticSpringHertz", "b2PrismaticUpperLimit", "b2QueryCount",
    "b2QueryFraction", "b2QueryNormalX", "b2QueryNormalY", "b2QueryShape",
    "b2QueryX", "b2QueryY", "b2RayShape", "b2RestitutionThreshold",
    "b2RevoluteEnableSpring", "b2RevoluteIsLimitEnabled",
    "b2RevoluteIsMotorEnabled", "b2RevoluteIsSpringEnabled",
    "b2RevoluteLowerLimit", "b2RevoluteMaxMotorTorque",
    "b2RevoluteMotorSpeed", "b2RevoluteMotorTorque",
    "b2RevoluteSetMaxMotorTorque", "b2RevoluteSetMotorSpeed",
    "b2RevoluteSetSpringDamping", "b2RevoluteSetSpringHertz",
    "b2RevoluteSpringDamping", "b2RevoluteSpringHertz",
    "b2RevoluteUpperLimit", "b2SensorBeginCount", "b2SetChainFriction",
    "b2SetChainRestitution", "b2SetHitEventThreshold",
    "b2SetJointCollideConnected", "b2SetMassData", "b2SetShapeCapsule",
    "b2SetShapeCircle", "b2SetShapeMaterialId", "b2SetShapePolygon",
    "b2SetShapeSegment", "b2SetTargetTransform", "b2ShapeAABBUpdate",
    "b2ShapeCapsuleRadius", "b2ShapeCapsuleUpdate", "b2ShapeCapsuleX1",
    "b2ShapeCapsuleX2", "b2ShapeCapsuleY1", "b2ShapeCapsuleY2",
    "b2ShapeCast", "b2ShapeCircleRadius", "b2ShapeCircleUpdate",
    "b2ShapeCircleX", "b2ShapeCircleY", "b2ShapeClosestPointX",
    "b2ShapeClosestPointY", "b2ShapeContactEventsEnabled",
    "b2ShapeDefEnableContactEvents", "b2ShapeDefEnableHitEvents",
    "b2ShapeDefEnablePreSolveEvents", "b2ShapeDefMaterialId",
    "b2ShapeDensity", "b2ShapeEnableContactEvents",
    "b2ShapeEnableHitEvents", "b2ShapeEnablePreSolveEvents",
    "b2ShapeEnableSensorEvents", "b2ShapeFriction",
    "b2ShapeHitEventsEnabled", "b2ShapeIsSensor", "b2ShapeMassDataUpdate",
    "b2ShapeMaterialId", "b2ShapePolygonCount", "b2ShapePolygonRadius",
    "b2ShapePolygonUpdate", "b2ShapePolygonVertexX",
    "b2ShapePolygonVertexY", "b2ShapeRayCast", "b2ShapeRayFraction",
    "b2ShapeRayNormalX", "b2ShapeRayNormalY", "b2ShapeRayX", "b2ShapeRayY",
    "b2ShapeRestitution", "b2ShapeSegmentUpdate", "b2ShapeSegmentX1",
    "b2ShapeSegmentX2", "b2ShapeSegmentY1", "b2ShapeSegmentY2",
    "b2ShapeSensorCapacity", "b2ShapeSensorEventsEnabled",
    "b2ShapeSensorOverlapAt", "b2ShapeSensorOverlapCount",
    "b2ShapeSensorOverlapsUpdate", "b2ShapeType", "b2WeldAngularDamping",
    "b2WeldAngularHertz", "b2WeldLinearDamping", "b2WeldLinearHertz",
    "b2WeldReferenceAngle", "b2WeldSetReferenceAngle",
    "b2WheelEnableLimit", "b2WheelIsLimitEnabled", "b2WheelIsMotorEnabled",
    "b2WheelIsSpringEnabled", "b2WheelLowerLimit", "b2WheelMaxMotorTorque",
    "b2WheelMotorSpeed", "b2WheelMotorTorque", "b2WheelSetLimits",
    "b2WheelSpringDamping", "b2WheelSpringHertz", "b2WheelUpperLimit",
    "b2WorldBodyCount", "b2WorldContactCount", "b2WorldCountersUpdate",
    "b2WorldGravityX", "b2WorldGravityY", "b2WorldIslandCount",
    "b2WorldJointCount", "b2WorldProfilePairs", "b2WorldProfileRefit",
    "b2WorldProfileSensors", "b2WorldShapeCount", "b2WorldThreadCount",
))


def box2dxt_raw_report():
    """The raw b2* binding measured against every script in the member."""
    problems, notes = [], []
    api = public_api("b2", [B2_RAW_LCB])
    if len(api) < 300:
        problems.append("box2dxt raw b2* scan found only %d public handler(s) - "
                        "the .lcb parse is broken, and a clean row would be a lie"
                        % len(api))
        return None, problems, notes
    blob = []
    for path in sorted(glob.glob(os.path.join(ROOT, B2_RAW_SCRIPTS),
                                 recursive=True)):
        text = open(path, encoding="utf-8", errors="replace").read()
        blob.append(blank_string_literals(strip_comments(text, path)))
    blob = "\n".join(blob)
    named = {n for n in api if re.search(r"\b" + re.escape(n) + r"\b", blob)}
    unnamed = api - named

    unlisted = sorted(unnamed - B2_RAW_BASELINE)
    promoted = sorted(B2_RAW_BASELINE & named)
    stale = sorted(B2_RAW_BASELINE - api)
    if unlisted:
        problems.append("box2dxt raw b2*: NEW UNNAMED handler(s) - no script in "
                        "the member names these, and they are not in the "
                        "recorded baseline: " + ", ".join(unlisted))
    if promoted:
        problems.append("box2dxt raw b2*: NOW NAMED (a script reaches these; "
                        "drop them from B2_RAW_BASELINE so the count stays "
                        "honest): " + ", ".join(promoted))
    if stale:
        problems.append("box2dxt raw b2*: BASELINE STALE (the .lcb no longer "
                        "declares these): " + ", ".join(stale))
    notes.append("box2dxt (raw b2* binding, ADVISORY with a FLOOR - see "
                 "B2_RAW_BASELINE in tools/check-suite-coverage.py)")
    notes.append("  %d/%d public b2* handlers are named by some script in the "
                 "member (comments stripped, string literals blanked)"
                 % (len(named), len(api)))
    notes.append("  %d named by nothing - the recorded baseline, not a failure. "
                 "Today: %d new / %d promoted / %d stale"
                 % (len(unnamed), len(unlisted), len(promoted), len(stale)))
    return (len(named), len(api), len(unnamed)), problems, notes


def holdem_region_report():
    """Measure holde-em by splitting its one file into game and harness.

    Returns (row, problems, notes). `problems` FAIL the build - every one of
    them is a way the printed number could become a lie. `notes` are the
    coverage figures themselves, which are advisory for now; see the module
    docstring for why the number goes on the record before the ratchet does.
    """
    problems, notes = [], []
    if not os.path.exists(HOLDEM_SRC):
        problems.append("holde-em: holde-em/src/holdem.livecodescript is gone, "
                        "so the harness-region ratchet is measuring nothing")
        return None, problems, notes
    bare = strip_comments(open(HOLDEM_SRC, encoding="utf-8").read(), HOLDEM_SRC)
    lines = bare.split("\n")

    # ---- the split ------------------------------------------------------
    at = [i for i, ln in enumerate(lines) if HOLDEM_BOUNDARY_RE.match(ln)]
    if len(at) != 1:
        problems.append(
            f"holde-em: the harness boundary `command heRunSelftest` matches "
            f"{len(at)} times in holdem.livecodescript (expected exactly 1). "
            f"Without a unique boundary there is no game region and no harness "
            f"region, and every number below it would be arbitrary.")
        return None, problems, notes
    game = "\n".join(lines[:at[0]])
    harness = "\n".join(lines[at[0]:])

    game_api = public_only(script_handler_names(game), "he")
    harness_api = public_only(script_handler_names(harness), "he")
    blocks = holdem_handler_blocks(harness)
    if not game_api or not blocks:
        problems.append("holde-em: the split produced an empty game region or "
                        "an empty harness region - the file's layout changed "
                        "and this ratchet is now checking nothing")
        return None, problems, notes
    if len(game_api) < HOLDEM_API_FLOOR:
        problems.append(
            f"holde-em: the game region defines only {len(game_api)} public he* "
            f"handlers, under the {HOLDEM_API_FLOOR} tripwire. Something has "
            f"eaten part of the denominator - a stray `*/` closing the header "
            f"block comment early is the measured way that happens - and every "
            f"number this row prints would be smaller and wrong. Check the "
            f"file's comment structure before touching HOLDEM_API_FLOOR.")
        return None, problems, notes

    # A GAME HANDLER MUST NOT DRIFT BELOW THE BANNER. If one does it leaves the
    # denominator, and a coverage percentage that improves because the thing it
    # measures got smaller is the worst reading this file can produce.
    for name in sorted(harness_api):
        if not HOLDEM_TEST_NAME_RE.match(name):
            problems.append(
                f"holde-em: {name} is defined BELOW the harness boundary but is "
                f"not test-shaped (heTest*, heT<Capital>*, heRunSelftest, "
                f"heSelfTest, heRunSection, heReportShow, heReportHide). "
                f"If it is game code, move it above "
                f"`command heRunSelftest` so it counts in the denominator; if it "
                f"is a new kind of harness handler, teach HOLDEM_TEST_NAME_RE.")
        if name.lower() not in blocks:
            problems.append(
                f"holde-em: {name} is defined in the harness region but its "
                f"`end {name}` line does not match, so it parses as no block at "
                f"all - the reachability walk cannot see through it and the "
                f"names in its body are invisible to the scan.")
    if HOLDEM_SEED not in blocks:
        problems.append("holde-em: heSelfTest is gone from the harness region. "
                        "It is the handler the fold calls (he1heSelfTest) and "
                        "the seed of this walk; without it nothing is reachable "
                        "and the row would read 0.")
        return None, problems, notes

    # ---- reachability: STRINGS ARE KEPT ---------------------------------
    # This harness arms its sections by literal name (`heRunSection
    # "heTestFoldRun"` -> `do pName`), so a literal is how a section is WIRED.
    # Over-approximating on purpose, exactly as check 7d does: any he* token in
    # a reachable body is an edge, so this can name a path that never executes
    # but it cannot miss one.
    reach, frontier = {HOLDEM_SEED}, [HOLDEM_SEED]
    while frontier:
        name = frontier.pop()
        for body in blocks.get(name, []):
            for tok in set(re.findall(r'\b(he\w+)\b', body)):
                low = tok.lower()
                if low in blocks and low not in reach:
                    reach.add(low)
                    frontier.append(low)

    for low, why in HOLDEM_DELIVERY.items():
        if low not in blocks:
            problems.append(
                f"holde-em: {low} is listed as unreachable-by-design ({why}) but "
                f"the harness region does not define it. A list that outlives "
                f"its entries reads like protection and is none.")
        elif low in reach:
            problems.append(
                f"holde-em: {low} is now REACHABLE from heSelfTest, and it is "
                f"the interactive delivery path ({why}). In the suite paste that "
                f"is an overlay and a clipboard write in somebody else's stack; "
                f"check 7d in tools/check-suite-selftest.py refuses it too.")
    for low in sorted(set(blocks) - reach - set(HOLDEM_DELIVERY)):
        problems.append(
            f"holde-em: {low} is defined in the harness region but nothing "
            f"reachable from heSelfTest calls it. A test section that is not in "
            f"heTestRunAllSections never runs - and every handler ITS body names "
            f"would otherwise count toward this row's numerator. Wire it up, or "
            f"add it to HOLDEM_DELIVERY with the reason it is not a test.")

    # ---- coverage: STRINGS ARE BLANKED ----------------------------------
    # Only the bodies that actually run, and only names that survive
    # blank_string_literals() - THE convention, called rather than copied.
    ran = "\n".join(b for low in sorted(reach) for b in blocks.get(low, []))
    scanned = blank_string_literals(ran)
    hit = {n for n in game_api
           if re.search(r'\b' + re.escape(n) + r'\b', scanned)}

    # ---- the worklist, held to the tree ---------------------------------
    listed, dup = {}, []
    for cat, (_reason, names) in HOLDEM_WORKLIST.items():
        for name in names:
            if name in listed:
                dup.append(f"{name} ({listed[name]} and {cat})")
            listed[name] = cat
    if dup:
        problems.append("holde-em: HOLDEM_WORKLIST lists these names twice, so "
                        "its per-category counts do not add up: "
                        + ", ".join(sorted(dup)))
    # The `dispatch` entry is the only one claiming a handler RUNS, so it is the
    # only one that can be checked rather than believed - and it is, against the
    # raw (unblanked) text of what actually runs.
    for name in HOLDEM_WORKLIST["dispatch"][1]:
        if not re.search(r'heRunSection\s+"' + re.escape(name) + r'"', ran):
            problems.append(
                f"holde-em: {name} is listed under `dispatch` - exercised via "
                f"`heRunSection \"{name}\"` - but no reachable body contains "
                f"that call any more. Either it is now a genuine gap and belongs "
                f"in no-test, or it is called some other way and this entry is "
                f"describing a call site that is gone.")

    dispatched = {n for n in HOLDEM_WORKLIST["dispatch"][1]
                  if n in game_api and n not in hit}
    gaps = game_api - hit - dispatched
    stale = sorted(n for n in listed if n not in game_api)
    promoted = sorted(n for n in listed if n in hit)
    unlisted = sorted(n for n in gaps if n not in listed)

    notes.append("holde-em (harness region, ADVISORY - see HOLDEM_* in "
                 "tools/check-suite-coverage.py)")
    notes.append(f"  {len(hit)}/{len(game_api)} public he* handlers in the GAME "
                 f"region are named by a body reachable from heSelfTest "
                 f"(comments stripped, string literals blanked)")
    notes.append(f"  +{len(dispatched)} dispatched by name through heRunSection, "
                 f"which the blanking cannot see = "
                 f"{len(hit) + len(dispatched)}/{len(game_api)} exercised")
    notes.append(f"  {len(gaps)} named by nothing that runs: "
                 + ", ".join(f"{len(names)} {cat}"
                             for cat, (_r, names) in HOLDEM_WORKLIST.items()
                             if cat != "dispatch"))
    notes.append(f"  harness region: {len(blocks)} handlers, {len(reach)} "
                 f"reachable from heSelfTest, "
                 f"{len(HOLDEM_DELIVERY)} interactive-delivery by design")
    # ARMED AS A FLOOR, 2026-08-19. The 209 standing gaps are NOT a failure -
    # ratcheting them would mean writing 209 assertions blind in one pass, and
    # this row exists to stop the number growing, not to pretend it is small.
    # What DOES fail is the three ways the recorded baseline can stop matching
    # the tree, and all three measured 0 on the day this was armed:
    #
    #   unlisted  a NEW gap - a public game handler exercised by nothing and
    #             claimed by no worklist category. This is the floor itself.
    #   promoted  a worklist entry a test now DOES reach. Left in, it is a
    #             standing excuse for debt already paid, and every later
    #             reading of "209" is inflated by it.
    #   stale     a worklist entry naming a handler holde-em no longer defines.
    #             A rename would otherwise leave a permanent exemption behind
    #             it - the exact failure `check-suite-coverage` already refuses
    #             for the onionxt per-handler reasons.
    #
    # The last two are the "a stale excuse cannot outlive its handler" rule
    # this file applies everywhere else; the row was advisory only because
    # nobody had separated them from the 209.
    if stale:
        problems.append("holde-em WORKLIST STALE (holde-em no longer defines "
                        "these; drop them from HOLDEM_WORKLIST): "
                        + ", ".join(stale))
    if promoted:
        problems.append("holde-em NOW EXERCISED (a test names these; drop them "
                        "from HOLDEM_WORKLIST so the gap count stays honest): "
                        + ", ".join(promoted))
    if unlisted:
        problems.append("holde-em NEW GAP (named by no test and in no "
                        "HOLDEM_WORKLIST category): " + ", ".join(unlisted))
    notes.append(f"  ARMED AS A FLOOR: the {len(gaps)} standing gap(s) are the "
                 f"recorded baseline and do not fail; a NEW gap, a promoted "
                 f"entry or a stale entry does. Today: "
                 f"{len(unlisted)} new / {len(promoted)} promoted / "
                 f"{len(stale)} stale")
    return (len(hit) + len(dispatched), len(game_api), len(gaps)), problems, notes


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

    # holde-em rides its own measurement, and its number is deliberately NOT
    # merged into the totals below. The rows above share one denominator rule
    # (a member's library file) and are enforced; this one splits a single file
    # by region and is advisory. Adding 121/330 into 724/742 would produce a
    # ratio that means neither thing, and the headline number is the one people
    # quote.
    holdem_row, holdem_problems, holdem_notes = holdem_region_report()
    problems.extend(holdem_problems)

    # Same shape, same reason, different surface: advisory row, enforced floor.
    b2_row, b2_problems, b2_notes = box2dxt_raw_report()
    problems.extend(b2_problems)
    holdem_notes = holdem_notes + [""] + b2_notes

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
        if holdem_row:
            hit, api, gapn = holdem_row
            print(f"{'holde-em*':16s} {hit:>6d}/{api:<5d} {'':>12s}"
                  f"   <-- {gapn} GAP(S), ADVISORY")
        print(f"{'':16s} {'':>12s} {'':>12s}")

    # Printed in BOTH modes, terse included: an advisory number that CI does not
    # record is a number nobody sees until somebody goes looking, and the whole
    # point of landing this row before it bites is that 209 is on the record.
    for note in holdem_notes:
        print(note)

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
