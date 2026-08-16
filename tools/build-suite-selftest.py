#!/usr/bin/env python3
"""build-suite-selftest.py - assemble tests/suite-selftest.livecodescript, the
ONE harness a maintainer pastes into an OXT stack to exercise the whole suite.

WHY THIS IS GENERATED AND NOT WRITTEN BY HAND. Every member already ships a deep
self-test, and those are authoritative for their own surface. Copying them into a
suite harness by hand would create a second copy of each that drifts the moment
anyone touches the original - and a drifted test harness is worse than no harness,
because it reports green about code that no longer exists. So the suite harness is
BUILT from the member harnesses, and `--check` (in the gate set) fails if the
committed file is not what the sources currently produce. Same pattern, and the
same reason, as onionxt/tools/build-standalone.py.

TWO MARKERS, AND WHY THE SECOND ONE EXISTS. The core carries
`-- GENERATED MEMBER DECLARATIONS GO HERE --` (above every handler) and
`-- GENERATED MEMBER HARNESSES GO HERE --` (at the bottom), and each member's
fold is split between them. That split is not tidiness. OXT resolves a
script-level name BY LEXICAL POSITION, and LiveCodeScript does not error on an
unresolved one - it evaluates it to the LITERAL TEXT of its own name. The first
version emitted each member's declarations inside that member's own section,
which is exactly where they sit in the member's own file. Correct there,
catastrophic here: the fold puts coinxt's section ~1000 lines BELOW the core's
stRunMemberHarnesses, and that handler reads cx1sPassed to merge the totals, so
the engine read the string "cx1sPassed" and the run died on
`add "cx1sPassed" to sPassed`. 106 declarations were below the first handler;
the counters were just the first to do arithmetic on one. Two files that are
each correct alone can be wrong concatenated, because file A's handlers now sit
above file B's declarations - which is the whole hazard of this tool.

WHAT IT PRODUCES. A single script-only stack script:

    tests/suite-selftest.core.livecodescript   the hand-maintained part: the UI,
                                               the per-member probe, the runner,
                                               and the CROSS-MEMBER sections that
                                               no per-member harness can have
  + each member's own harness, namespaced      the deep per-member coverage

THE NAMESPACING RULE, AND WHY IT IS TOTAL. A .livecodescript compiles as one
unit, so two handlers with the same name is a compile error, and the member
harnesses collide hard: all five define stAssert, stSection, stRun, stBuild,
openStack and mouseUp, and four of them define sTotal/sPassed/sFailed. The
temptation is to keep one copy of the "shared" scaffolding and let everyone call
it. This does NOT do that. EVERY name a member file defines - handler, script
local, constant - is prefixed, including its own copy of stAssert and its own
counters. Two reasons:

  1. The scaffolding is not actually identical. stRepeatByte has three different
     implementations across three members, and they disagree at pCount = 0.
     Sharing one of them would silently change what another member's harness
     tests.
  2. A member's harness then behaves in here EXACTLY as it does on its own. No
     folded section can perturb another's counters, log, or state, so a failure
     in the suite harness means the same thing as a failure in the member one.

The core reads each member's (prefixed) counters and log afterwards and merges
them into the unified report. That is the only coupling.

WHAT IS FOLDED IN, AND WHAT IS DELIBERATELY NOT. Three members are pure,
offline and synchronous, so they fold in whole:
  sodiumxt   sxSelfTest()   21 groups
  onionxt    oxSelfTest()    8 groups, all offline (no Tor daemon needed)
  coinxt     stRun          28 sections
box2dxt joined them 2026-08-16 and is the odd one, because its harness is a
paste-and-run STACK rather than a test file: it carries a verbatim copy of the
b2k Kit between sentinels (its own tools/sync-embedded-kit.py owns that
region), it hangs its window off the CARD hooks instead of the stack ones, and
three of the names it defines are MESSAGE RECEIVERS the Kit dispatches by
literal name. So its row uses all three of the mechanisms below - strip_spans
cuts the carried Kit (the real one is embedded once, from src/, as a script
layer), drop_extra drops the window builder the card hooks called, and
keep_names holds b2kFell/b2kSensorEnter/b2kContact at their real spelling, since
a b21b2kFell would simply never be dispatched to.
holde-em joined the same day and is the SECOND paste-and-run stack, but it needs
almost none of that, because it differs in the one way that decides the shape:
the game and its harness are THE SAME FILE. Everything else here folds a test
file and embeds its library separately; here there is nothing to embed, so the
whole 15k-line game rides in prefixed alongside the tests that drive it - and
that is exactly why prefixing is safe rather than merely tidy. The reason
coinxt, onionxt, riptide and the b2k Kit embed VERBATIM is that their tests must
reach a separate library by its real names; when both sides are renamed together
nothing can be left behind. Measured on that file: of 6950 string literals in
code, rename() touches 45, and every one is either a message name armed by
`send` / dispatched by `do` (which must move with its handler) or prose in a
test label naming a handler (which rename() rewrites on purpose). No KAT vector,
wire body, domain tag or hex pin changes. Its row therefore uses only drop_extra
(its stack chrome - preOpenStack, which would resize the suite's window to
1024x640, and the bet slider's five scrollbar messages) plus one rewrite, for
the pending-message sweep; the row itself carries the reasoning for both.
Three are not, and each is handled explicitly rather than fudged:
  torrentxt  synchronous, but TorrentXT allows exactly ONE session per process.
             Folded whole, with its session acquisition rewritten to reuse the
             core's if the core already opened one.
  enetxt     synchronous up to its async loopback, which owns UDP ports and
  datachannelxt  event handlers. The SYNC PREFIX is folded (lifecycle, stale
             handles, tuning, teardown); the async loopback is not, because the
             core already drives a real loopback on both transports for its
             cross-member sections and two state machines in one process would
             race. The per-member harness stays the place for that depth, and
             the generated file says so where the cut is.

Every cut point and rewrite below is ASSERTED against the source. If a member
harness is edited such that a marker moves, this build FAILS rather than quietly
dropping a section - a silently shorter test suite is the failure mode this whole
file exists to prevent.

THE SCRIPT LAYERS ARE EMBEDDED, VERBATIM, AND THAT IS A DIFFERENT OPERATION
FROM FOLDING. coinxt and onionxt each ship part (coinxt) or all (onionxt) of
their public API as pure LiveCodeScript - src/coinxt.livecodescript and
src/onionxt.livecodescript - which used to be the runbook's "two `start using`
lines the harness cannot do for you". That setup step cost a real engine pass:
on 2026-08-10 a maintainer re-pasted a freshly built harness into an engine
whose in-memory coinxt stack predated a parser fix, and the run reported the
EXACT two failures the fix had closed - red lines that read as "the fix does
not work" and actually meant "the fix was not loaded". A harness that carries
its own copy of the code it tests cannot skew against it: the generator builds
both from one tree, and --check pins the pair to the sources.

Unlike the member harnesses, the layers are NOT prefixed. The whole point is
that the folded tests call cxHdDerivePath and oxIsValidAddress by their real
names; a renamed copy would be a second implementation nobody ships. That makes
name collisions the embed's one hazard - a library handler colliding with the
core, the other library, or a folded name is a compile error at paste time, on
an engine, which is the most expensive place to learn it - so this build fails
on ANY duplicate handler or script-level declaration in the assembled output.

Each embedded span (and its hoisted declarations) sits between sentinel lines
(EMBED_BEGIN/EMBED_END below). check-suite-coverage.py CUTS those spans before
it scans for calls, and that is load-bearing, not cosmetic: the library's own
body mentions nearly every library handler (cxMnemonicToSeed calls
cxMnemonicNormalize, the dispatchers name every callback), so an uncut scan
would score coinxt and onionxt at permanent 100% coverage - every future
handler "exercised" by its own definition, and that gate structurally dead for
the two members that need it most.

That cut is also why holde-em has NO ROW in check-suite-coverage.py. The cut
works because a library and the tests that drive it live in two files: fold the
tests, embed and cut the library, and what is left is tests naming a library.
holde-em is one file, so there is nothing to cut, and the same scan pointed at
its folded section measures the GAME naming its own API - 379/379, permanently,
from the day such a row were added. The measurement and the reasoning are
written out beside the MEMBERS list in that tool rather than left implicit here.

Usage:
  python3 tools/build-suite-selftest.py            # write the generated file
  python3 tools/build-suite-selftest.py --check    # fail if it is out of date
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CORE = os.path.join(ROOT, "tests", "suite-selftest.core.livecodescript")
OUT = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")

# Handlers a member harness defines that belong to ITS OWN standalone UI. The
# core owns the window here, so these are dropped. Any of them still called from
# folded code gets an empty stub (see STUB_IF_CALLED) rather than a dangling call.
DROP_HANDLERS = {
    "openstack", "closestack", "mouseup",
    # box2dxt's harness hangs its window off the CARD hooks rather than the
    # stack ones, and they are the same hazard by a different name: left in,
    # `on openCard` would rebuild that member's 860x640 window over the suite's
    # the moment this stack's card opened, and `on closeCard` would run its
    # teardown on a card close the suite core knows nothing about.
    "opencard", "closecard",
    "stbuild", "stmakelabel", "stmakebutton", "stmakelist",
    "stshow", "stcopyresults", "stpaint",
    # scaffold v1: the platform-mono helper is called only from the dropped
    # window half; stResetCounters/stReportDone are NOT here - members call
    # them mid-run, and stReportDone's stShow/stPaint calls hit the stubs
    "stmonofont",
}

# Of those, the ones a member's runner still calls mid-run. They become no-op
# commands: the core reads the member's log directly, so a member repainting its
# own (absent) field has nothing to do.
STUB_IF_CALLED = {"stshow", "stpaint"}


class Member:
    def __init__(self, key, path, prefix, entry, title, note,
                 cut_before=None, rewrites=(), strip_spans=(), drop_extra=(),
                 keep_names=()):
        self.key = key
        self.path = os.path.join(ROOT, path)
        self.prefix = prefix
        self.entry = entry          # handler the core calls, BEFORE prefixing
        self.title = title
        self.note = note
        self.cut_before = cut_before  # truncate the entry handler at this marker
        self.rewrites = rewrites      # (must_find, replace_with) applied to the source
        # (begin_sentinel, end_sentinel) pairs cut out of the source BEFORE
        # anything else looks at it. box2dxt's harness is a paste-and-run stack
        # that carries a verbatim copy of the b2k Kit between sentinels (its own
        # tools/sync-embedded-kit.py owns that region), and this file embeds the
        # Kit ONCE, from src/, as a script layer. Without the cut the assembly
        # would define all 313 b2k* handlers twice - a compile error at paste
        # time, on an engine.
        self.strip_spans = strip_spans
        # Handlers beyond DROP_HANDLERS that belong to this member's own window.
        # Asserted present, so a rename in the member harness fails this build
        # instead of quietly leaving its window builder in the suite paste.
        self.drop_extra = tuple(drop_extra)
        # Names this member defines that must NOT be prefixed. The only honest
        # reason is that something OUTSIDE the renamed text dispatches them BY
        # LITERAL NAME - the engine, or an embedded library - so a prefixed copy
        # would never be found and the checks that depend on it would fail while
        # looking like a defect in the member.
        self.keep_names = tuple(keep_names)


# The suite's members, in the order the unified harness runs them. Order matters
# once: torrentxt must see the core's session, and the core opens it during the
# probe, which runs first either way.
MEMBERS = [
    Member(
        "sodium", "sodiumxt/examples/sodium-tests.livecodescript", "sx1",
        "sxSelfTest", "SodiumXT: the full sx* self-test",
        "21 groups: encoding, hashing, secretbox, AEAD, pwhash, KDF, "
        "secretstream, signing, box, seal, key exchange, padding.",
    ),
    Member(
        "onion", "onionxt/examples/onionxt-tests.livecodescript", "ox1",
        "oxSelfTest", "OnionXT: the full ox* self-test",
        "8 groups, all OFFLINE - no Tor daemon is started or contacted. "
        "The live-Tor paths stay in onionxt's own demo.",
    ),
    Member(
        "coin", "coinxt/tests/coin-selftest.livecodescript", "cx1",
        "stRun", "CoinXT: the full cx* self-test",
        "28 sections across all four phases: hashes, the secp256k1 curve, the "
        "encoders and addresses, BIP-39/32/44, and the fail-closed regressions.",
    ),
    Member(
        "torrent", "torrentxt/tests/torrent-selftest.livecodescript", "bt1",
        "stRun", "TorrentXT: the full bt* self-test",
        "Synchronous throughout. Reuses the suite's single session rather than "
        "opening a second one, which TorrentXT does not allow.",
        rewrites=(
            # TorrentXT permits exactly one session per process and the core
            # already opened one during the probe. Without this the folded
            # harness would take its own "could not start a session" branch and
            # skip everything - green, and testing nothing. The core's handle is
            # written as @CORESESSION@ because a literal `sSession` here would be
            # renamed to the member's own local along with everything else.
            ("""   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tErr
      -- TorrentXT absent, or already released; nothing to free.
   end try
   put 0 into sSession
   -- START INTO A TEMPORARY. This used to be `put btStartSession() into
   -- sSession`, which on a REFUSAL wrote 0 over a still-live handle in the same
   -- statement - destroying the only key to the very session it had just been
   -- refused, and guaranteeing that every later run in this launch would be
   -- refused too. Commit to sSession only on success.
   try
      put btStartSession() into tNewSession
      put true into tStartOk
   catch tErr
      put 0 into tNewSession
   end try
   if tNewSession is not empty and tNewSession > 0 then
      put tNewSession into sSession
   end if""",
             """   -- GENERATED (tools/build-suite-selftest.py): TorrentXT allows exactly ONE
   -- session per process, and the suite core opens one during its probe. Reuse
   -- it rather than fighting for a second - starting one here would fail, this
   -- harness would take its cannot-start branch, and the whole torrent surface
   -- would report as skipped while looking perfectly green.
   --
   -- THE RELEASE IS SWALLOWED BY THIS REWRITE ON PURPOSE. The standalone
   -- harness releases any session IT left behind before asking for one, which
   -- is correct there and actively harmful here: bt1sSession is an ALIAS for
   -- the core's handle, so on a second run in one process the folded copy would
   -- btStopSession the session the cross-member BEP44 sections are still using.
   -- It was folded in once, caught by reading the generated file, and the
   -- rewrite's span was widened to cover it. The core does that job for both.
   if @CORESESSION@ > 0 then
      put @CORESESSION@ into sSession
      put true into tStartOk
   else
      try
         put btStartSession() into sSession
         put true into tStartOk
      catch tErr
         put 0 into sSession
      end try
   end if"""),
        ),
    ),
    Member(
        "enet", "enetxt/tests/enet-selftest.livecodescript", "en1",
        "stRun", "ENetXT: the synchronous half of the en* self-test",
        "Lifecycle, stale-handle no-ops, tuning and abrupt teardown. The async "
        "loopback is NOT folded in - the core drives a real ENet loopback of its "
        "own below, and two state machines in one process would race for the "
        "event handlers. Run enetxt/tests/enet-selftest.livecodescript for that.",
        cut_before='   stSection "loopback: hosts + connect (async)"',
    ),
    Member(
        "dc", "datachannelxt/tests/datachannel-selftest.livecodescript", "dc1",
        "stRun", "DataChannelXT: the synchronous half of the dc* self-test",
        "Lifecycle and the stale-handle surface. The async loopback is NOT "
        "folded in, for the same reason as ENetXT's; the core negotiates a real "
        "peer connection below. Run datachannelxt's own harness for that.",
        cut_before='   stSection "loopback: create + negotiate (async)"',
    ),
    Member(
        "box2d", "box2dxt/examples/box2dxt-selftest.livecodescript", "b21",
        "stSelfTest", "Box2Dxt: the full b2k Kit self-test",
        "43 test handlers driving the REAL Kit deterministically: the world "
        "started PAUSED and hand-stepped one fixed 1/60 tick at a time, the "
        "keyboard replaced by b2kInputInject, and every assertion a lesson this "
        "member learned on real hardware - fixed-step determinism, frame-exact "
        "contact and sensor events, the chain ghost rule, one-way platforms, "
        "presence polling through sleeping bodies, the player controller's feel "
        "contract (coyote, jump buffer, drop-through, ladders, duck, swim, "
        "double jump, wall jump, dash, moving-platform carry), sprites and "
        "sheets, tones, camera, queries, joints and teardown hygiene. It builds "
        "and destroys its own graphics on this card, wipes them, and tears the "
        "world down before returning.",
        # ONE copy of the Kit, and this is where it comes from. box2dxt's
        # examples are paste-and-run stacks, so each one carries a verbatim copy
        # of src/box2dxt-kit.livecodescript between sentinels that its own
        # tools/sync-embedded-kit.py owns. Folding that copy in AND embedding
        # the Kit as a script layer below would define all 313 b2k* handlers
        # twice - a compile error the maintainer meets at paste time, on an
        # engine. The copy is cut here; the layer is the one that ships.
        strip_spans=(("-- >>> BEGIN EMBEDDED KIT >>>",
                      "-- <<< END EMBEDDED KIT <<<"),),
        # The window builder. DROP_HANDLERS covers the hooks that CALL it
        # (openCard/closeCard/mouseUp); this is the 860x640 window itself, which
        # would otherwise sit in the paste resizing the suite's stack the moment
        # anything reached it.
        drop_extra=("buildStUI",),
        # NOT prefixed, and this is the one place in this file where that is
        # true of a folded harness. These three are MESSAGE RECEIVERS: the Kit
        # dispatches them BY LITERAL NAME (`dispatch "b2kFell" to sFrameObj`)
        # from inside the embedded layer, which this file never renames. A
        # prefixed copy would simply never be found, gMsgEnters/gMsgContacts
        # would stay 0, and the three checks that prove the Kit's message path
        # works would FAIL while reading like a real defect in the dispatcher.
        keep_names=("b2kFell", "b2kSensorEnter", "b2kContact"),
    ),
    Member(
        "riptide", "riptide/tests/riptide-selftest.livecodescript", "rs1",
        "rsSelfTest", "Riptide Social (phases 1-2): the rs* self-test",
        "The capstone app's harness: the KDF subkey tree, identity to handle "
        "to onion, the RIPTKEY1 key file, the RSH1/RSP1 framings, the post "
        "chain, and the phase-2 live feed layer (BEP44 buffers, ingest "
        "verifiers, and real puts and lookups against the suite's session) - "
        "all against the same golden vectors the Python oracle pins. No "
        "network is awaited; sections needing coinxt, onionxt or torrentxt "
        "SKIP when those are absent, and the whole crypto set skips without "
        "SodiumXT.",
        rewrites=(
            # Same one-session-per-process constraint the torrent member's
            # rewrite handles: the core opened THE session during its probe,
            # so the folded copy must alias it - a second btStartSession here
            # would be refused and the live-feed section would SKIP while
            # looking perfectly green. The standalone start (into a
            # temporary, committed only on success) stays as the fallback for
            # the no-core-session case.
            ("""   try
      put btStartSession() into tNew
   catch tErr
      put 0 into tNew
   end try
   if tNew is not empty and tNew > 0 then
      put tNew into sRsTestSession
   end if""",
             """   -- GENERATED (tools/build-suite-selftest.py): TorrentXT allows exactly
   -- ONE session per process and the suite core already opened it during
   -- its probe. Alias the core's handle instead of asking for a second -
   -- the ask would be refused, and this member's live-feed section would
   -- SKIP while looking perfectly green.
   if @CORESESSION@ > 0 then
      put @CORESESSION@ into tNew
   else
      try
         put btStartSession() into tNew
      catch tErr
         put 0 into tNew
      end try
   end if
   if tNew is not empty and tNew > 0 then
      put tNew into sRsTestSession
   end if"""),
        ),
    ),
    Member(
        "holdem", "holde-em/src/holdem.livecodescript", "he1",
        "heSelfTest", "holde-em: the full he* self-test",
        "21 sections over the whole game, driven through heSelfTest - the QUIET "
        "entry point (report returned as a value, no control built, no "
        "clipboard, no overlay), not the interactive heRunSelftest. The "
        "7-card evaluator and the betting engine and side-pot settlement; the "
        "deal ladder (integer PRNG, the Level 0 commit-reveal keyed stream, "
        "the Level 2 ristretto mental-poker algebra and its void-and-audit "
        "machine with DLEQ proofs); the signed transcript wire, the lobby, "
        "three-context netplay and deck-oracle loopbacks, the onion "
        "transport's headless slice, and the whole liveness layer. Every "
        "section that needs SodiumXT, TorrentXT or OnionXT SKIPs by name when "
        "it is absent, and every live leg (a tor daemon, a second machine) "
        "SKIPs too, so the folded run is offline and synchronous throughout.",
        # WHY THIS IS A PREFIXED FOLD AND NOT A VERBATIM SCRIPT-LAYER EMBED.
        # holde-em is the second member whose harness lives in a paste-and-run
        # stack, but it is unlike box2dxt in the one way that decides the shape:
        # the game and its tests are THE SAME FILE. The reason coinxt, onionxt,
        # riptide and the b2k Kit embed verbatim is that their tests must reach a
        # SEPARATE library by its real names; here renaming moves both sides
        # together, so nothing can be left behind. Measured on this file: of 6950
        # string literals in code, rename() touches 45, and every one is either a
        # message name armed by `send` / dispatched by `do` (which MUST move with
        # its handler) or prose in a test label naming a handler (which rename()
        # rewrites on purpose). No KAT vector, wire body, domain tag or hex pin
        # changes. Verbatim, by contrast, would put 389 unprefixed handlers and
        # 192 declarations into a paste that already carries 928 and 625 -
        # colliding on openStack/closeStack/mouseUp today, which embed() has no
        # way to drop, and leaving an open-ended collision surface after that.
        #
        # AND ONE NAME SETTLES IT ON ITS OWN: `on b2kFrame`. box2dxt's folded
        # harness calls `b2kFrameTarget the long id of me`, and in this paste
        # `me` is THIS stack - so a verbatim `on b2kFrame` would start receiving
        # the embedded Kit's frame messages during box2dxt's deterministic
        # hand-stepping. One member perturbing another is precisely what the
        # total namespacing exists to prevent. Prefixed, he1b2kFrame is
        # dispatched by nobody, which is exactly what happens standalone: this
        # stack calls b2kFrameTarget NOWHERE (carried gotcha 19).
        drop_extra=(
            # The engine hooks and the bet slider's scrollbar messages - the ones
            # DROP_HANDLERS does not already cover. They are here rather than in
            # that global set because drop_extra is ASSERTED: a rename in
            # holde-em fails this build instead of quietly leaving its window
            # code in the suite paste.
            #
            # preOpenStack is the loud one. Its two lines are `set the rect of
            # this stack to kHeStackRect` and `set the title of this stack` - so
            # left in, the suite's window would silently become a 1024x640 stack
            # titled "holde-em 0.24.1" the moment this paste's stack opened.
            "preOpenStack",
            # The five scrollbar messages belong to the bet slider. Each one
            # guards on `the short name of the target is "heBetSlider"` and
            # otherwise passes, so they are inert here - but inert BECAUSE no
            # control in the suite window happens to carry that name, which is
            # luck rather than a property. An unhandled message passes on by
            # itself, so dropping them is behaviour-identical and stops relying
            # on the coincidence.
            "scrollbarDrag", "scrollbarLineInc", "scrollbarLineDec",
            "scrollbarPageInc", "scrollbarPageDec",
        ),
        rewrites=(
            # THE PENDING-MESSAGE SWEEP, widened - and it had to change at all
            # because a FRAGMENT of a name is not a name. heTestSweepNetTimers
            # cancels its own timers with `begins with "heNet"`, and "heNet" is
            # not something this file declares, so the rename leaves the literal
            # exactly as written while renaming every message the harness arms.
            # The sweep would have matched nothing and said nothing: a silent
            # no-op in the one handler whose entire job is to leave no timer
            # running inside somebody else's paste.
            #
            # It is WIDENED to the member prefix on top of that, and the narrow
            # spelling is right standalone for the reason its own comment gives
            # (heHudTick and the paced hand steps belong to a REAL table, and
            # stopping a maintainer's HUD because they ran the harness would be a
            # new bug). There is no real table in a suite paste, and the
            # reachable closure of this harness arms four NON-heNet sends as
            # well: the paced hand steps. Left armed, the next-hand tick fires
            # seconds later - inside the core's async loopback phase, after this
            # member has already reported - into heHandStart, which DEALS A HAND
            # on the harness's leftover state. The member prefix is exactly the
            # right net: everything it catches is holde-em's, and no other unit
            # in this paste has a name that begins with it.
            ("""   repeat for each line tMsgLine in the pendingMessages
      if item 3 of tMsgLine begins with "heNet" then
         cancel item 1 of tMsgLine
      end if
   end repeat""",
             """   -- GENERATED (tools/build-suite-selftest.py): the sweep is by the MEMBER
   -- PREFIX here, not by the heNet stem the standalone harness uses. Two
   -- reasons, and the first one is a silent failure rather than a judgement
   -- call. (1) The stem is a FRAGMENT of a name, not a name, so the fold's
   -- rename cannot move it: every message this harness arms is prefixed, the
   -- literal is not, and the sweep would match nothing while looking exactly
   -- like the code that was reviewed. (2) The stem is deliberately narrow
   -- standalone -- heHudTick and the paced hand steps belong to a real table
   -- and must survive a harness run -- and there is no real table here. This
   -- harness's reachable closure also arms heNextHandTick, heRevealStep,
   -- heRunoutStep and heSettleStep; left armed, the next-hand tick fires into
   -- the core's async loopback phase, seconds after this member has already
   -- reported, and lands in heHandStart, which deals a hand. The prefix is the
   -- exact net: every name it catches is this member's, and nothing else in
   -- this paste is spelled that way.
   repeat for each line tMsgLine in the pendingMessages
      if item 3 of tMsgLine begins with "@PREFIX@" then
         cancel item 1 of tMsgLine
      end if
   end repeat"""),
        ),
    ),
]


class Layer:
    def __init__(self, key, path, title, note):
        self.key = key
        self.path = os.path.join(ROOT, path)
        self.title = title
        self.note = note


# The pure-script API layers, embedded VERBATIM (no prefixing - the folded
# tests must reach these handlers by their real names). onionxt also ships
# src/onion-httpd.livecodescript; it is NOT here because it is an app over the
# ox* surface, not part of it - check-suite-coverage.py measures the ox* API
# against src/onionxt.livecodescript only, and embedding an app nobody's test
# calls would be dead weight in every paste.
SCRIPT_LAYERS = [
    Layer(
        "coinxt", "coinxt/src/coinxt.livecodescript",
        "CoinXT script layer (the real library, embedded)",
        "Encoders, addresses and the whole HD layer - the half of coinxt's API "
        "that is pure script. Embedded so one paste carries the code its tests "
        "test; no `start using stack` step, and no way to run new tests against "
        "a stale library.",
    ),
    Layer(
        "onionxt", "onionxt/src/onionxt.livecodescript",
        "OnionXT script layer (the real library, embedded)",
        "The entire ox* surface - OnionXT is pure LiveCodeScript over engine "
        "sockets. Embedded for the same reason as coinxt's layer; its engine "
        "socket callbacks (socketError and friends) ride along, which is "
        "correct - the engine delivers them to the object that opened the "
        "socket, and in this paste that is this stack.",
    ),
    Layer(
        "box2dxt-kit", "box2dxt/src/box2dxt-kit.livecodescript",
        "Box2Dxt b2k Kit (the real Kit, embedded)",
        "The whole b2k* surface - the friendly pixels/degrees/y-down toolkit "
        "over the raw b2* extension, and the layer box2dxt's harness actually "
        "drives. It is pure LiveCodeScript, so it embeds exactly like coinxt's "
        "and onionxt's layers do; the folded harness above calls it by its real "
        "names, and the physics underneath still needs the native extension "
        "(the core probes for it and SKIPS the whole section when it is "
        "absent).",
    ),
    Layer(
        "riptide", "riptide/src/riptide.livecodescript",
        "Riptide script layer (the real library, embedded)",
        "The rs* surface of the capstone app - pure script over the installed "
        "extensions, phase 1 (identity + the feed wire formats). Embedded so "
        "the folded riptide harness tests the code it ships with, same as the "
        "coinxt and onionxt layers.",
    ),
]

# Sentinels around every embedded span. check-suite-coverage.py cuts these
# spans out before scanning for calls (a library calling itself is not a test),
# so the format is a CONTRACT between the two tools - change it in both or the
# coverage gate fails loudly (it refuses a harness with no spans to cut).
EMBED_BEGIN = "-- >>> GENERATED EMBED: {name} >>> --"
EMBED_END = "-- <<< GENERATED EMBED: {name} <<< --"


def strip_comments(text):
    """Comment-free view, for finding DEFINITIONS only. Never used for output.

    LINE COUNT IS PRESERVED, and that is load-bearing rather than tidy:
    split_handlers reads its STRUCTURE from this view and slices its OUTPUT
    from the original text at the same indices, so a single dropped line would
    misalign every handler boundary below it.

    BLOCK COMMENTS ARE COMMENTS TOO. /* ... */ is legal LiveCodeScript and
    holde-em keeps its entire 926-line header changelog in one, where prose
    wraps at the margin - so a line of that changelog begins `on every wire
    during the netplay section)`. Read as code, that is a handler named
    `every`: split_handlers died on "unterminated handler every", and
    defined_names harvested `every` into the set rename() prefixes, which
    substitutes on word boundaries and would have rewritten the word wherever
    it appeared. This is the same phantom-definition class that
    tools/check-handler-calls.py grew its own block-comment strip for in the
    2026-08-15 fold (31 phantoms, suite-wide), arriving at the generator.

    It follows that sibling's scan - stateful across lines, opening and
    closing mid-line, repeatably - and differs from it in exactly ONE way, on
    purpose. check-handler-calls strips blocks BEFORE line comments and
    strings, so a `/*` sitting inside a `--` comment opens a block there. This
    scanner already tracks both, so it can get the precedence right instead:
    `--` outside a string ends the line (a `/*` after it is prose), and a `/*`
    inside a string is data. That is not academic - holde-em carries
    `bt*/session` and `l2v_*/l0_*` inside line comments today, and they are
    harmless only because no `/*` happens to precede them, which is luck
    rather than a property of the tree.

    An UNTERMINATED block is REFUSED, not blanked to end-of-file. Blanking
    would delete every handler below it and hand back a shorter harness that
    still looks perfectly green - the failure mode this whole file exists to
    prevent.
    """
    out, in_block = [], False
    for raw in text.split("\n"):
        buf, i, instr = "", 0, False
        while i < len(raw):
            ch = raw[i]
            if in_block:
                # Inside /* */ nothing is code: not a quote, not a --, not an
                # opener. Only the closing delimiter means anything.
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
        raise SystemExit(
            "build-suite-selftest: an unterminated /* block comment runs to the "
            "end of a source file. Blanking it would silently delete every "
            "handler below it and fold in a shorter harness that still reports "
            "green; close the comment at its source instead.")
    return "\n".join(out)


def declaration_names(line):
    """The names ONE `local`/`constant` line declares.

    STRING LITERALS COME OUT BEFORE THE COMMA SPLIT, which is the entire
    reason this is a function rather than two inline loops. A comma is both
    the separator between declarations on one line and an ordinary character
    inside a string, so `constant kKatL2Perm1 = "35,31,39,12"` splits into
    four parts and injects 31, 39 and 12 into the name set.

    Neither consequence is cosmetic. The set defined_names builds goes to
    rename(), which substitutes on WORD BOUNDARIES, so a folded holde-em
    would have that very constant rewritten to "35,he131,he139,12" and every
    bare 31 in its arithmetic turned into he131 - test data silently
    corrupted by the tool whose job was to carry it across verbatim. The same
    set reaches assert_no_duplicate_definitions, where two KAT constants that
    merely share a value report that value as a duplicate DECLARATION, and
    the build refuses an assembly that is perfectly sound.

    The removal is naive on purpose and exactly right here: LiveCodeScript
    has no string escape syntax, so quotes always pair. Same substitution,
    for the same stated reason, as tools/check-handler-calls.py's strip_noise.
    """
    names = []
    for part in re.sub(r'"[^"]*"', '""', line).split(","):
        part = part.split("=")[0].strip()
        if re.fullmatch(r'\w+', part):
            names.append(part)
    return names


def preamble_declarations(preamble):
    """The preamble lines that really declare something, in ORIGINAL spelling.

    Matched against the comment-free view and returned as the source wrote
    them: these lines are HOISTED INTO THE OUTPUT, so a trailing `-- why`
    must survive, while a `local gRpt, gPassN` quoted inside a block-comment
    changelog must not be mistaken for the real thing. Before strip_comments
    knew about /* */ the two were indistinguishable, and the commented-out one
    would have been hoisted as a genuine declaration.
    """
    view = strip_comments("\n".join(preamble)).split("\n")
    if len(view) != len(preamble):
        raise SystemExit("build-suite-selftest: the comment-free view of the "
                         "preamble lost lines; the declaration hoist cannot be "
                         "trusted to pick the right ones.")
    return [orig for orig, seen in zip(preamble, view)
            if re.match(r'^\s*(?:local|constant)\s', seen)]


def defined_names(text):
    """Every handler, script local and constant the file defines."""
    bare = strip_comments(text)
    names = set(re.findall(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)',
                           bare, re.M))
    for line in re.findall(r'^\s*(?:local|constant)\s+(.+)$', bare, re.M):
        names.update(declaration_names(line))
    return names


def rename(text, names, prefix):
    """Prefix every defined name, at its definition and at every call site.

    Word-boundary substitution over the whole text, comments included: a comment
    that names a handler should name the one that is actually there, or the next
    reader is misled about which code they are looking at.
    """
    if not names:
        return text
    pattern = re.compile(r'\b(' + "|".join(sorted(map(re.escape, names),
                                                  key=len, reverse=True)) + r')\b')
    return pattern.sub(lambda m: prefix + m.group(1), text)


def split_handlers(text):
    """[(name_lower, block_text)] in source order, plus the leading preamble.

    STRUCTURE COMES FROM THE COMMENT-FREE VIEW; OUTPUT IS SLICED FROM THE
    ORIGINAL. Only code can open a handler, close one, or nest a block, so
    every decision below is made against `view` - but every line handed back
    is `lines`, because the fold ships comments through verbatim (rename()
    deliberately rewrites them too, so a comment names the handler that is
    actually there). Asking the raw text these questions is what made a line
    of holde-em's block-comment changelog - `on every wire during the netplay
    section)` - open a handler named `every` that no `end every` ever closed.
    """
    lines = text.split("\n")
    view = strip_comments(text).split("\n")
    if len(view) != len(lines):
        raise SystemExit("build-suite-selftest: the comment-free view lost lines, "
                         "so every handler boundary below would be sliced from the "
                         "wrong place in the source.")
    blocks, preamble, i = [], [], 0
    opener = re.compile(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', re.I)
    while i < len(lines):
        m = opener.match(view[i])
        if not m:
            preamble.append(lines[i])
            i += 1
            continue
        name = m.group(1)
        end = re.compile(r'^end\s+' + re.escape(name) + r'\b', re.I)
        j, depth = i + 1, 0
        while j < len(lines):
            s = view[j].strip()
            if re.match(r'^(if\b.*\bthen$|repeat\b|try\b|switch\b)', s, re.I):
                depth += 1
            elif re.match(r'^end\s+(if|repeat|try|switch)\b', s, re.I):
                depth -= 1
            elif depth <= 0 and end.match(s):
                break
            j += 1
        if j >= len(lines):
            raise SystemExit(f"build-suite-selftest: unterminated handler {name}")
        blocks.append((name.lower(), name, "\n".join(lines[i:j + 1])))
        i = j + 1
    return preamble, blocks


def strip_span(src, begin, end, who, path):
    """Remove one sentinel-delimited region, sentinels included.

    Both sentinels are REQUIRED and must appear exactly once, in order. A
    silently missing sentinel would fold the region in - which for box2dxt
    means 313 duplicate handler definitions, i.e. a compile error at paste time
    on an engine - and a silently unmatched one would swallow the rest of the
    file. Neither is allowed to be a fallback.
    """
    lines = src.split("\n")
    at = {}
    for want in (begin, end):
        hits = [i for i, ln in enumerate(lines) if ln.rstrip() == want]
        if len(hits) != 1:
            raise SystemExit(
                f"build-suite-selftest: {who}: expected exactly one line "
                f"{want!r} in {os.path.relpath(path, ROOT)}, found {len(hits)}. "
                f"The member harness was restructured; re-read it and update "
                f"strip_spans rather than folding in a region this file also "
                f"embeds from its own source.")
        at[want] = hits[0]
    if at[end] <= at[begin]:
        raise SystemExit(f"build-suite-selftest: {who}: {end!r} comes before "
                         f"{begin!r}; the span cannot be cut safely.")
    return "\n".join(lines[:at[begin]] + lines[at[end] + 1:])


def assert_no_declaration_dropped(src, preamble, who, path):
    """Every script-level declaration must be in the PREAMBLE, because the
    preamble is all the hoist can see.

    READ THIS BEFORE TRUSTING THIS GUARD (corrected 2026-08-16, the day it was
    added). It does NOT catch "a declaration written between two handlers":
    split_handlers appends every top-level non-handler line wherever it sits, so
    those are already in the preamble and are hoisted correctly. On any real
    source the two counts below are equal by construction and this never fires.
    What it DOES catch is the narrow case it can: a column-0 local/constant
    written INSIDE a handler body, which split_handlers cannot see.

    The guard was added on a misreading of split_handlers, and the mutation test
    that "proved" it drove this function with a hand-built preamble matching the
    docstring rather than one the pipeline produces. Keeping it is cheap and the
    narrow case is real; believing its original description is not.

    split_handlers returns only the LEADING run of non-handler lines, so a
    `local` or `constant` written BETWEEN two handlers - perfectly legal, and
    the house pattern in any file that groups a subsystem's state next to its
    handlers - is silently dropped by both fold() and embed(). Silently is the
    problem: LiveCodeScript evaluates an undeclared name as the literal text of
    its own name, so the paste compiles and then compares a digest against the
    string "kSomething", or does arithmetic on the word "gPassN". That is the
    same failure the declaration hoist exists to prevent, arriving by a
    different door.

    check-suite-selftest.py's check 12 catches the s*/k* half of it after the
    fact; it cannot catch a g* or any other spelling, and it should not be the
    first thing to notice. This is measured at the source, where the message
    can name the file and the line.
    """
    bare = strip_comments(src)
    total = len(re.findall(r'^(?:local|constant)\s', bare, re.M))
    # Both sides are counted through the comment strip, or the check reports
    # nonsense on a file that quotes a `local` line inside a block comment:
    # the preamble would hold it (it is a raw line) while `total` would not,
    # and the difference would come out NEGATIVE.
    in_pre = len([ln for ln in preamble_declarations(preamble)
                  if re.match(r'^(?:local|constant)\s', ln)])
    if total != in_pre:
        missed = [ln.strip() for ln in strip_comments("\n".join(
            src.split("\n")[len(preamble):])).split("\n")
            if re.match(r'^(?:local|constant)\s', ln)]
        raise SystemExit(
            f"build-suite-selftest: {who}: {total - in_pre} script-level "
            f"declaration(s) in {os.path.relpath(path, ROOT)} sit BELOW its "
            f"first handler, where the declaration hoist cannot see them. They "
            f"would be dropped from the assembly WITHOUT an error: "
            f"LiveCodeScript evaluates an undeclared name as the literal text "
            f"of its own name, so the paste would compile and then compare "
            f"against, or do arithmetic on, a string.\n"
            f"  first few: " + ", ".join(missed[:5]) + "\n"
            f"  Move them above the first handler in that file, or teach this "
            f"tool to collect declarations from the whole file - but not "
            f"silently.")


def fold(member):
    """The namespaced, trimmed body of one member harness."""
    src = open(member.path, encoding="utf-8").read()

    for begin, end in member.strip_spans:
        src = strip_span(src, begin, end, member.key, member.path)

    for must_find, replace_with in member.rewrites:
        if must_find not in src:
            raise SystemExit(
                f"build-suite-selftest: {member.key}: a required rewrite no longer "
                f"matches its source. The member harness changed under it; update "
                f"the rewrite in tools/build-suite-selftest.py rather than letting "
                f"the fold silently do the wrong thing.\n"
                f"  wanted to find:\n{must_find}")
        src = src.replace(must_find, replace_with, 1)

    names = defined_names(src)
    # KEEP_NAMES: defined here, but dispatched from OUTSIDE this text by literal
    # name, so a prefixed copy would simply never be found. Asserted defined, so
    # a rename in the member harness fails this build rather than leaving a
    # permanent no-op exemption behind it.
    unknown_keep = sorted(n for n in member.keep_names if n not in names)
    if unknown_keep:
        raise SystemExit(
            f"build-suite-selftest: {member.key}: keep_names lists "
            f"{', '.join(unknown_keep)}, which this harness does not define any "
            f"more. Either the handler was renamed (update keep_names) or it was "
            f"deleted (drop the entry) - a stale keep_names entry protects "
            f"nothing and hides the next one.")
    names -= set(member.keep_names)
    src = rename(src, names, member.prefix)
    # @CORESESSION@ is a deliberate placeholder, substituted AFTER the rename so
    # it survives it: the torrent rewrite has to reach the CORE's sSession, and
    # anything spelled `sSession` before this point becomes the member's own.
    src = src.replace("@CORESESSION@", "sSession")
    # @PREFIX@ is the same placeholder trick pointed the other way, and it exists
    # for a hazard rename() cannot fix by itself: a FRAGMENT of a name is not a
    # name. holde-em's harness sweeps its own pending messages with
    # `begins with "heNet"`, which is correct standalone and matches NOTHING once
    # every message this member arms has been prefixed - a silent no-op exactly
    # where a silent no-op is most expensive. A rewrite has to spell the folded
    # prefix, and spelling it literally would duplicate the Member row's own
    # `prefix` argument, so a prefix change would quietly stop matching. This
    # keeps one source of truth, substituted here (after the rename) for the same
    # reason @CORESESSION@ is: written earlier it would itself be renamed.
    src = src.replace("@PREFIX@", member.prefix)
    preamble, blocks = split_handlers(src)

    entry = (member.prefix + member.entry).lower()
    if not any(n == entry for n, _, _ in blocks):
        raise SystemExit(f"build-suite-selftest: {member.key}: no entry handler "
                         f"{member.prefix + member.entry}")

    # drop_extra is spelled in the member's OWN names; compare after prefixing.
    drop_extra = {n.lower() for n in member.drop_extra}
    seen_extra = set()

    kept = []
    for name, spelling, block in blocks:
        base = name[len(member.prefix):] if name.startswith(member.prefix.lower()) else name
        if base in drop_extra:
            seen_extra.add(base)
            continue
        if base in DROP_HANDLERS:
            if base in STUB_IF_CALLED:
                kept.append(f"-- GENERATED: {spelling} drove this harness's own window.\n"
                            f"-- The suite owns the UI and reads the member's log directly,\n"
                            f"-- so there is nothing left for it to repaint.\n"
                            f"command {spelling}\nend {spelling}")
            continue
        if name == entry and member.cut_before:
            # Rename the marker with the ORIGINAL name set: `src` is already
            # renamed, so its defined names are the prefixed ones and the raw
            # marker would never match.
            marker = rename(member.cut_before, names, member.prefix)
            if marker not in block:
                raise SystemExit(
                    f"build-suite-selftest: {member.key}: the async cut marker is gone "
                    f"from {member.entry}. The harness was restructured; re-read it and "
                    f"update cut_before, rather than folding in an async section that "
                    f"will race the core.\n  wanted: {member.cut_before}")
            head = block.split(marker)[0].rstrip()
            head += (
                f"\n\n   -- GENERATED CUT (tools/build-suite-selftest.py). Everything below\n"
                f"   -- this point in {os.path.relpath(member.path, ROOT)}\n"
                f"   -- is the ASYNC loopback, and it is deliberately not folded in: it\n"
                f"   -- owns ports and event handlers that the suite's own cross-member\n"
                f"   -- loopback below is already using. Run that member's harness on its\n"
                f"   -- own for the async depth.\n"
                f"   {member.prefix}stNote \"async loopback not run here - see the note in this section\"\n"
                f"end {spelling}")
            kept.append(head)
            continue
        kept.append(block)

    missing_extra = sorted(drop_extra - seen_extra)
    if missing_extra:
        raise SystemExit(
            f"build-suite-selftest: {member.key}: drop_extra lists "
            f"{', '.join(missing_extra)}, which this harness does not define any "
            f"more. A stale drop entry is an excuse for a handler that is gone, "
            f"and it would silently stop dropping the one that replaced it.")

    # THE PREAMBLE'S DECLARATIONS COME TOO, and forgetting them is a silent
    # disaster rather than a compile error: LiveCodeScript treats an undeclared
    # name as a literal string of itself, so a folded harness missing its
    # `constant kBip39Mnemonic` would not fail to compile - it would compare a
    # digest against the text "cx1kBip39Mnemonic" and report a tidy FAIL that
    # looks like a real defect. The member's `script "name"` line is dropped (the
    # core supplies the one this file needs) and so is its prose, which stays
    # readable in the source file this section names.
    assert_no_declaration_dropped(src, preamble, member.key, member.path)
    decls = preamble_declarations(preamble)
    if not decls:
        raise SystemExit(f"build-suite-selftest: {member.key}: no local/constant "
                         f"declarations found in the preamble - the parse is wrong, "
                         f"and folding it in would silently break every constant.")
    # The declarations are returned SEPARATELY and hoisted above every handler
    # in the file (see the marker in the core). Leaving them here, in the
    # member's own section, is what they look like they want - each member file
    # declares its locals above its own handlers - but the fold puts one
    # member's section BELOW the core's handlers, and the core reads every
    # member's counters to merge them. OXT resolves a script-level name by
    # lexical position, so that read saw an undeclared name, LiveCodeScript
    # evaluated it to the literal text of its own name, and the run died on
    # `add "cx1sPassed" to sPassed`. Same silent-name failure the preamble check
    # below guards against, arriving by placement instead of by omission.
    decl_block = (f"-- ---- {member.title} ----\n" + "\n".join(decls))
    body = "\n\n".join(kept)
    header = (
        f"-- {'=' * 74}\n"
        f"-- {member.title}\n"
        f"--\n"
        + "\n".join(f"-- {ln}" for ln in wrap(member.note, 74)) + "\n"
        f"--\n"
        f"-- GENERATED from {os.path.relpath(member.path, ROOT)} by\n"
        f"-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and\n"
        f"-- rebuild, or the next build will overwrite you. Every name below is\n"
        f"-- prefixed `{member.prefix}` so this harness cannot collide with, or be\n"
        f"-- perturbed by, any other member's copy of the same scaffolding.\n"
        f"-- {'=' * 74}\n"
    )
    return decl_block, header + "\n" + body


def embed(layer):
    """One script layer, verbatim: (hoisted declarations, body), both wrapped
    in EMBED sentinels.

    Verbatim means every handler keeps its name and its text. What does move:
    the `script "name"` line goes (the core supplies this file's), and the
    script-level declarations hoist to the core's declaration marker like every
    folded member's do - same reason, the lexical-position scope rule; the
    library's own handlers sit BELOW the core's in the assembly, but nothing
    guarantees a future edit keeps every reader below every declaration, and
    check-suite-selftest.py's position invariant is deliberately blunt.
    Inter-handler comment banners are dropped with the rest of the preamble,
    exactly as fold() does; the source file stays the readable copy.
    """
    src = open(layer.path, encoding="utf-8").read()
    lines = src.split("\n")
    if lines and re.match(r'^script\s+"', lines[0]):
        src = "\n".join(lines[1:])

    preamble, blocks = split_handlers(src)
    assert_no_declaration_dropped(src, preamble, layer.key, layer.path)
    decls = preamble_declarations(preamble)
    if not decls:
        raise SystemExit(f"build-suite-selftest: {layer.key}: no script-level "
                         f"declarations found in its layer - the parse is wrong, "
                         f"and embedding it would silently break every constant.")
    # A layer that parses to almost nothing is a parse failure, not a small
    # library: both real layers define 70+ handlers. Mirrors check 4 in
    # check-suite-selftest.py, but at build time, where the fix is cheap.
    if len(blocks) < 30:
        raise SystemExit(f"build-suite-selftest: {layer.key}: only {len(blocks)} "
                         f"handlers parsed from {os.path.relpath(layer.path, ROOT)} "
                         f"- the split dropped most of the file; embedding this "
                         f"would paste a fragment that cannot compile.")

    decl_name = f"{layer.key} script layer declarations"
    body_name = f"{layer.key} script layer"
    decl_block = (EMBED_BEGIN.format(name=decl_name) + "\n"
                  + f"-- ---- {layer.title} ----\n"
                  + "\n".join(decls) + "\n"
                  + EMBED_END.format(name=decl_name))
    header = (
        f"-- {'=' * 74}\n"
        f"-- {layer.title}\n"
        f"--\n"
        + "\n".join(f"-- {ln}" for ln in wrap(layer.note, 74)) + "\n"
        f"--\n"
        f"-- GENERATED from {os.path.relpath(layer.path, ROOT)} by\n"
        f"-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and\n"
        f"-- rebuild. Names are NOT prefixed: this is the library itself, and the\n"
        f"-- folded tests above must reach it by its real names.\n"
        f"-- {'=' * 74}\n"
    )
    body = (EMBED_BEGIN.format(name=body_name) + "\n"
            + header + "\n"
            + "\n\n".join(b for _, _, b in blocks) + "\n"
            + EMBED_END.format(name=body_name))
    return decl_block, body


def assert_no_duplicate_definitions(text):
    """Refuse an assembly that defines any name twice.

    A duplicate HANDLER is a compile error the maintainer meets at paste time,
    on an engine. A duplicate SCRIPT-LEVEL declaration is worse: it is not
    obviously an error at all, so two units silently SHARE one variable and
    perturb each other's state - the exact isolation the prefixing exists to
    guarantee. Neither can arise from the members' own files (each compiles
    standalone); only this assembly can create one, so this build refuses it
    rather than shipping it. check-suite-selftest.py re-checks the committed
    file; this catches it where the fix is cheapest.
    """
    bare = strip_comments(text)
    handlers = re.findall(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)',
                          bare, re.M)
    seen, dup_h = set(), set()
    for n in handlers:
        (dup_h if n.lower() in seen else seen).add(n.lower())
    decls = []
    for line in re.findall(r'^(?:local|constant)\s+([^\n]+)$', bare, re.M):
        decls.extend(declaration_names(line))
    seen, dup_d = set(), set()
    for n in decls:
        (dup_d if n.lower() in seen else seen).add(n.lower())
    if dup_h or dup_d:
        msg = ["build-suite-selftest: the assembled harness defines a name twice; "
               "refusing to write it."]
        if dup_h:
            msg.append("  duplicate handlers (a compile error at paste time): "
                       + ", ".join(sorted(dup_h)))
        if dup_d:
            msg.append("  duplicate script-level declarations (two units would "
                       "silently share one variable): " + ", ".join(sorted(dup_d)))
        msg.append("  If an embedded layer gained a name the core or another unit "
                   "already uses, rename it at its source - the embed is verbatim "
                   "by design and cannot rename for you.")
        raise SystemExit("\n".join(msg))


def wrap(text, width):
    words, line, out = text.split(), "", []
    for w in words:
        if len(line) + len(w) + 1 > width:
            out.append(line)
            line = w
        else:
            line = (line + " " + w).strip()
    if line:
        out.append(line)
    return out


def generate():
    core = open(CORE, encoding="utf-8").read()
    marker = "-- GENERATED MEMBER HARNESSES GO HERE --"
    if marker not in core:
        raise SystemExit(f"build-suite-selftest: {CORE} has no '{marker}' line")
    decl_marker = "-- GENERATED MEMBER DECLARATIONS GO HERE --"
    if decl_marker not in core:
        raise SystemExit(f"build-suite-selftest: {CORE} has no '{decl_marker}' line")

    parts = [fold(m) for m in MEMBERS]
    embeds = [embed(l) for l in SCRIPT_LAYERS]
    declarations = ("\n\n".join(p[0] for p in parts)
                    + "\n\n" + "\n\n".join(e[0] for e in embeds))
    folded = "\n\n\n".join(p[1] for p in parts)
    embed_banner = (
        "-- " + "=" * 74 + "\n"
        "-- THE TWO PURE-SCRIPT LIBRARIES THEMSELVES, embedded by\n"
        "-- tools/build-suite-selftest.py so that one paste carries the code its\n"
        "-- tests test. These used to be a separate setup step (`start using\n"
        "-- stack` x2), and that step cost an engine pass on 2026-08-10: a fresh\n"
        "-- harness ran against a stale in-memory coinxt stack and reported the\n"
        "-- two failures its parser fix had already closed. Embedded, the harness\n"
        "-- and the library are built from one tree and cannot skew.\n"
        "--\n"
        "-- NOT renamed, unlike the folded tests below: this is the real library,\n"
        "-- and the tests must call it by its real names. If you also have these\n"
        "-- loaded via `start using`, calls from THIS script resolve to the copies\n"
        "-- here (same-script wins), so the run still tests the embedded tree.\n"
        "-- " + "=" * 74 + "\n"
    )
    embedded = "\n\n\n".join(e[1] for e in embeds)
    banner = (
        "-- " + "=" * 74 + "\n"
        "-- EVERYTHING BELOW THIS LINE IS GENERATED. Do not edit it here.\n"
        "--\n"
        "-- It is each member's OWN self-test, folded in by\n"
        "-- tools/build-suite-selftest.py with every name it defines prefixed, so\n"
        "-- that five harnesses which all define stAssert, stRun and sTotal can\n"
        "-- share one script. Each keeps its own scaffolding and its own counters\n"
        "-- and therefore behaves here exactly as it does standalone; the core\n"
        "-- above reads each one's log and totals afterwards and merges them.\n"
        "--\n"
        "-- To change a check, edit the member harness it comes from and run\n"
        "--     python3 tools/build-suite-selftest.py\n"
        "-- The gate set runs --check, so a stale file fails the build.\n"
        "-- " + "=" * 74 + "\n"
    )
    text = (core
            .replace(decl_marker, declarations)
            .replace(marker, embed_banner + "\n" + embedded + "\n\n\n"
                     + banner + "\n" + folded))
    assert_no_duplicate_definitions(text)
    return text


def main(argv):
    text = generate()
    if "--check" in argv[1:]:
        if not os.path.exists(OUT):
            print("build-suite-selftest: tests/suite-selftest.livecodescript is missing")
            return 1
        if open(OUT, encoding="utf-8").read() != text:
            print("build-suite-selftest: tests/suite-selftest.livecodescript is STALE.\n"
                  "  A member harness changed and the suite harness was not rebuilt, so\n"
                  "  the file a maintainer would paste into an engine is not the one the\n"
                  "  sources describe. Run:  python3 tools/build-suite-selftest.py")
            return 1
        print("build-suite-selftest: tests/suite-selftest.livecodescript is up to date")
        return 0
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)
    handlers = len(re.findall(r'^(?:private\s+)?(?:command|function|on)\s+\w+',
                              text, re.M))
    print(f"build-suite-selftest: wrote tests/suite-selftest.livecodescript "
          f"({len(text.splitlines())} lines, {handlers} handlers, "
          f"{len(MEMBERS)} member harnesses folded in, "
          f"{len(SCRIPT_LAYERS)} script layers embedded)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
