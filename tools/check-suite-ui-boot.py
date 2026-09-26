#!/usr/bin/env python3
"""check-suite-ui-boot.py - BOOT the suite paste's board, headlessly, and drive
it the way a person does: build, a row's Run, the filters, Show, Copy, the
boot self-check, a close mid-run and a rebuild over an older paste's window.

WHY THIS EXISTS
---------------
D-23 (2026-09-24) gave the GENERATED suite paste the demos' card look: a
1200 x 640 board with one row per member, a scoped Run per row, a filtered
results pane and the demo boot self-check - the su* handlers of
tests/suite-selftest.core.livecodescript, which no engine had run when this
gate was written (Run all first ran on one on 2026-09-24; a row's Run, Show
and the filters still have not). The static gates prove the text reads the
way a checker reads it; nothing proved it RUNS. That is this tree's most expensive recorded failure shape (root
CLAUDE.md: shipped is not run; riptide's phase-8 card broke openStack twice
through a green gate set), so the board gets what every other window-building
script with an execution gate here has.

WHAT IT DOES
------------
It loads the GENERATED paste - the whole file, every folded harness and
embedded layer, the text a maintainer pastes (--paste names another copy; only
tools/test-suite-ui-boot.py passes one) - into riptide's stack runner
(riptide/tools/check-demo-boot.py, over the family interpreter
nostrxt/tools/lcs-interp.py), which models the engine's object world: cards,
controls and their properties, `there is`, chunk writes, the clipboard, the
screen lock. A ROOT tool reaches into a member directly; only a member's own
tools go through sibling(). The runner's three shared spelling rewrites apply,
each required to fire (the embedded riptide layer is why all three do). On top
of the runner this file adds the DELTA the board needs (below), then drives the
REAL routes: a button-1 mouseDown with a target, the armed tick delivered from
a modelled pendingMessages queue, the pump's ticks delivered until none remain,
and the filter, Show and Copy buttons pressed the same way. The scenarios, in
order, in ONE window (a maintainer opens the stack once and keeps pressing):

  build        every name the script uses exists, every rect fits 1200 x 640,
               no two rows overlap, the three results fields share one rect
               and exactly one shows; a second build builds nothing.
  routing      a right-click, a press on a field or a panel and the Run all
               button's mouseDown all pass on; the key check refuses nocloud
               and an unknown key.
  boot check   openStack's order (asserted from the source) with a scoped run
               standing in for its Run all: the self-check is green, its
               delayed probe restores the status line, the Boot check view
               shows the block and the report carries it above the summary.
  eight Runs   each FAST_SCOPES row through its own button: the Starting and
               Running status lines, the report's scope line, the summary
               last, the totals equal to the report's own PASS / FAIL / SKIP
               lines plus what each returned report folded in (riptide's is
               the fast tier's one), the row equal to the totals, every
               other row "not run",
               this row's pill from EXPECTED_PILLS, every pill on one of the
               kit's three grounds, the board check's note, a Finished status
               line in the verdict's colour, every line painted by its kind,
               no timer left - then Failures, Skips and its own Show.
  refusals     a second row press while one is armed, and while one is live,
               is refused with the warn status and arms nothing.
  Copy         mid-run the clipboard carries the counts, a blank line and the
               report WITH its trailer, and the answer says not finished;
               after the finish, without, and the answer says copied.
  close        closeStack with a Run armed cancels its tick; closeStack
               mid-run cancels the pump and frees everything.
  views        a live run with one synthetic member report per folded format
               merged through the REAL stMergeReturned / stMergeCounted inside
               a real tally: Failures holds every FAIL line and nothing else,
               Skips likewise, a member's Show is exactly the lines its row
               owns (derived from the design, not from the spans the code
               kept), every line is painted by its kind, and the RUN NOT
               FINISHED trailer shows exactly until the run finishes.
  Run-all      the tally handlers driven directly in the "all" scope that only
  accounting   Run all reaches: each block counts to its own row, each Show is
               its own lines, and the board check FAILS on a block counted
               outside every tally (so the check is proven able to fire).
  rebuild      a window stamped by an older paste, carrying the scaffold's
               retired controls and a stale board control, is swept and
               rebuilt; a foreign control (box2dxt's st_* prefix) survives;
               a scoped run drives the rebuilt window.
  transport    LAST, in an interpreter of its own, and the one scenario that
  holds        is not all-absent (work plan suite-wide #16): ENet and
               DataChannelXT as modelled natives beside ANOTHER stack that
               holds ENet once, with a live host, and has a live DataChannel
               peer. Open, enetxt's Run, a re-entry mid-run (runbook 5.2),
               cross's Run closed mid-run, a close at rest, a sodiumxt Run,
               datachannelxt's Run and an enetxt Run whose every
               enInitialize is refused. At each step the other stack's hold
               and host survive, the paste gives back exactly the holds it
               took (a refused one is none), and it never calls dcCleanup
               without a hold of its own. The model (EnetModel, DcModel) is
               each library's process-wide lifecycle as its shim keeps it and
               nothing else: no event ever arrives, so each loopback waits for
               its deadline, and the folded harnesses stop at their first
               unmodelled call (after their two counted inits).

THE PROFILE: ALL-ABSENT
-----------------------
Every NATIVE extension is absent: sx*, bt*, en*, dc*, the cx* extension half
and the raw b2* binding are neither installed as natives nor defined in the
paste, so each probe's guarded call raises "can't find handler" and fails
closed, as on an engine with nothing installed. The five EMBEDDED script
layers (coinxt's script half, onionxt, the b2k Kit, riptide, the nostrxt core)
are present, because they are in the paste. Only ENGINE builtins the probe
path reaches are installed: the runner's engine functions, sha1Digest
(nxWsAcceptFor's digest) and the three big-endian packers the shared riptide
rewrite writes for binaryEncode. The profile is asserted before anything runs,
and the probe's ten answers after the first run (EXPECTED_PROBE). The one
exception is the transport-holds scenario, which installs its two modelled
libraries in its own interpreter after every other scenario has run and
removes them before the gate reports.

THE FAST TIER, AND WHAT IS LEFT OUT OF IT
-----------------------------------------
Eight scopes run (FAST_SCOPES). The onionxt, nostrxt and holde-em scopes do
not, and neither does Run all (openStack's call, and the stRerun mouseUp),
because in this profile those run their members' FOLDED HARNESSES through the
model, and what that tests is the harnesses, whose own execution gates own
them - not the board. They are not slow here (onionxt 1.4 s), and each hits
something the board does not need modelled: onionxt's harness prints FAIL
lines on `the result` after a command (the runner never passes a command's
`return` to its caller's `the result`), nostrxt's recurses past Python's stack
limit in the model, and holde-em's dispatches its sections with `do`, which
the runner refuses (SLOW_SCOPES). Each reason is RE-MEASURED on every run
(scenario_slow_reasons, in a fresh interpreter per scope), so an excuse that
outlives its reason fails the gate: riptide's did for a day. riptide's scope
runs in the fast tier, the one that merges a RETURNED report (its no-SodiumXT
branch), so the totals rule counts what a merge folds in. What the left-out
scopes share with the fast tier is the board code this gate covers; the "all"
branch of the tallies is covered by the Run-all accounting scenario.

THE MODEL DELTAS, named and counted, and each must fire
-------------------------------------------------------
Everything below is a construct the board reaches that riptide's runner does
not model. Each hook counts its firings, and the gate FAILS on a delta that
never fired: a model hook nobody exercises is a stale excuse, the rule the
runner applies to its own source rewrites. The runner's surfaces the board
also relies on - the clipboard, stack custom properties (uSuUiVersion),
lock / unlock screen, formattedHeight - are the runner's, named in its header,
and are asserted on here rather than counted.

  send-in            `send X to me in N ms` queues X under an engine message id
                     (the runner's queue has no ids, so nothing could cancel
                     it) and puts that id in `the result`.
  pending-messages   `the pendingMessages`: one line per queued message in the
                     engine's id,time,message,object shape, earliest first.
  cancel             `cancel N` removes queued message N (an unknown id is a
                     no-op, as on the engine); fires when it removes one.
  timer-delivery     a queued message is delivered only when the driver asks,
                     earliest first, the clock advanced to its due time: the
                     engine's one script thread, never re-entered mid-handler.
  mouse-press        a click is mouseDown then mouseUp with `the target` set
                     and pWhich passed; the pass delta shows which message the
                     board passed on, so "not handled" is observable.
  pass               `pass <message>` records the message, then returns; the
                     runner returns without a record.
  autohilite         a push button whose autoHilite is true (the default for a
                     new button) is hilited for the press and un-hilited at
                     release - the LiveCode dictionary's rule, DOCUMENTED and
                     never observed here - so a script-set hilite survives a
                     click only where the builder turned autoHilite off, which
                     is what the filter buttons rely on.
  answer             `answer EXPR` records the text; the modelled person
                     presses OK at once.
  line-prop          `set the P of line N of field F to V` records V for line
                     N; a line past the field's text is REFUSED (unmodelled).
  field-replace      `put X into field F` replaces F's text AND drops its
                     per-line styling. STRICTER than any engine reading, on
                     purpose: a colour counts only if it was painted after the
                     last replace, so a painter that stopped painting cannot
                     pass on a stale colour.
  length-of          `the length of X`, a factor like `the number of chars of`
                     (the base interpreter has neither spelling of length).
  effective-filename `the effective filename of this stack` answers empty: the
                     paste's stack is not saved in the ritual, and the Kit's
                     b2kEnsureNativeLib, called by every probe, exits on empty.
  control-by-index   `the number of controls of this card`, `the short name of
                     control N of this card` and `delete control N of this
                     card`: suBuildReset's sweep of an older paste's window.
  native-command     a modelled extension COMMAND in statement position
                     (`enHostDestroy sEnServer`, a bare `enDeinitialize`)
                     reaches the model; the base reaches a native only as a
                     function. Fires only in the transport-holds scenario.

REFUSED rather than modelled: a read of `the visible` of a control that never
had it set (the engine says true, the runner would say empty; a check reading
either would be reading the model), and everything the runner refuses.

WHAT IT CANNOT SEE
------------------
RENDERING (a pill's colour here is a property value, not pixels; a caption
that clips is invisible), PARSING (the interpreter reads a wider language than
OXT compiles - the static gates and an engine pass own that), MESSAGE DELIVERY
(timers fire when this file says so; the engine's scheduling, another stack in
front of the defaultStack pins, and mouseDown acting on the press rather than
the release are OXT-PASS-RUNBOOK row 48), `is` FOLDING CASE (the interpreter's
`is` is case-SENSITIVE whatever `the caseSensitive` says, so a case defect in
suLineKind is invisible here), the three SLOW_SCOPES and Run all (the --full
profile below runs Run all, and so all three), and EVERY
PRESENT-EXTENSION PATH: with every native absent no loopback opens, no session
is taken and no member harness runs - bar the transport-holds scenario, whose
two libraries are a refcount and a peer table and no more (no event arrives,
no byte crosses). It settles LOGIC. It upgrades no honesty
label: what the 2026-09-24 engine runs did not show (a row's Run, Show, the
filters, the pills' look) stays "verified statically plus a headless UI boot;
needs an OXT pass" (D-23, runbook row 48).

THE --full PROFILE: RUN ALL OVER THE WHOLE PASTE, BEFORE AN ENGINE SESSION
--------------------------------------------------------------------------
`--full` (work plan suite-wide #14, closed 2026-09-26; its fixture is
tools/test-suite-ui-boot.py --full, run first). Everything above drives the
BOARD; this drives the RUN. It delivers the paste ritual (OXT-PASS-RUNBOOK
3.1: closeStack as the applied window closes, openStack as it reopens,
closeStack when done) to the WHOLE generated paste - every member folded,
every embedded layer present, every native absent, so each probe fails closed
and each native member's sections SKIP exactly as the paste's own probe
decides - and lets Run all run to its end the way an engine does. openStack
is suBuild, stCleanup, stRun with no scope (Run all, synchronously, up to its
`send "suPump"`) and suScRun (the boot self-check, which arms its one probe);
then the engine's timers, earliest first, until none is left. The maintainers'
engine runs launched Run all exactly so; the one they later pressed a second
time is the stRerun mouseUp, which this profile does not repeat. Then it
asserts what an engine session would otherwise be the first to show:

  - no section threw and the interpreter refused nothing, each NAMED by
    section, row, handler and line: a script error by where it was raised
    (the report says which section caught it), a refusal at the core
    runner's call it escaped from (CORE_RUNNERS), where it is handed on to
    that runner's own catch as a script error so every other section runs;
  - the totals are the report's own PASS / FAIL / SKIP lines plus what every
    merge folded in (counted from each report AS HANDED to stMergeReturned),
    the rows add up to them, the summary's printed table is the rows, and
    each row's pill is FULL_PILLS';
  - each folded member wrote exactly one outcome, its merged report or its
    SKIP line, and the present layers' harnesses are the ones that ran;
  - the report ends without RUN NOT FINISHED, and Copy results carries it so;
  - the boot self-check's block, green once its probe fires;
  - stTeardown ran once, from stFinish, and nothing is held after it or after
    the last closeStack;
  - no fold created or deleted a control, touched the clipboard, resized the
    window or wrote the message box (bar MSG_WRITERS); every "can't find
    handler" names an absent native or a NOT_IN_PASTE layer; the timers after
    openStack are exactly FULL_TIMERS; the delimiters are restored.

It prints the per-row table the run produced - labelled THE INTERPRETER'S
RUN, never an engine's (root rule 6) - with each row's seconds and the wall
time. It settles LOGIC, not parsing, runs no present-extension path, and
upgrades no label.

Its model deltas, FULL_DELTAS, live in its own subclass (FullInterp), each
with the engine's rule beside it, each counted and required to fire: `do`
(holde-em's he1heRunSection runs every section as `do pName`), `the result`
after a statement-position handler call (onionxt's harness reads it after
every command) and a bare `put` into the message box (holde-em's probe). The
fast tier keeps SuiteInterp without them, so its SLOW_SCOPES reasons stay
true of the model it measures them in. Two run-level settings, each named
where it is set: the clock (FULL_CLOCK, pinned by FULL_CLOCK_PIN) and
Python's frame limit (FULL_RECURSION, in a worker thread; the deepest handler
nesting is printed).

ITS FIRST RUNS (2026-09-26) found no fold-level fault in the paste. They
found two readings of the GATE's that were wrong for Run all, each fixed
where it lives: returned_merges read a merged report back from the text up to
the next section header, which in Run all ran on into the absent natives'
SKIP lines (five skips short); and two "can't find handler" probes name
layers the paste leaves out on purpose (NOT_IN_PASTE).

NOT A PER-PUSH GATE, and measured, not assumed. On 2026-09-26, on the
four-core machine that wrote it and beside another gate run (load about 4,
under nice), one --full run took 350 to 423 s of wall time, openStack's
synchronous Run all nearly all of it: nostrxt's folded harness 290 to 330 s,
holde-em's about 60 s, everything else a few seconds. Its fixture is five
such runs at once: 1137 s (about 19 minutes) for the clean run and its four
mutants, on that machine the same day. Per push that is about 25 more
minutes on a job (suite-gates.yml) that ran 1h22m to 2h43m in its fifteen
runs of 2026-09-21 to 09-24 against a 240-minute ceiling, in a block of
suite gates that are seconds each. What it would buy there is the fold-level
facts above, which change only when the paste is regenerated (once per batch,
the work plan's rule), and which the fast tier's board checks and each folded
member's own execution gate already cover in part on every push. So
build-all --gates does not run it; the runbook (3.2) names it as the
headless step before a regenerated paste goes onto an engine.

Usage:
  python3 tools/check-suite-ui-boot.py                 # the gate (fast tier)
  python3 tools/check-suite-ui-boot.py --verbose       # every check printed
  python3 tools/check-suite-ui-boot.py --paste PATH    # a mutated copy (fixtures)
  python3 tools/check-suite-ui-boot.py --full          # Run all, the whole
                                                       # paste (pre-session)
"""

import collections
import hashlib
import importlib.util
import os
import re
import shutil
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PASTE = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")
# A ROOT tool reaches into a member directly; sibling() is for member tools.
RUNNER = os.path.join(ROOT, "riptide", "tools", "check-demo-boot.py")

# COMPILED ONCE, LOOKED UP BY THE LITERAL - the family's idiom (riptide's
# runner and coinxt's wallet gate carry it): every statement of every driven
# handler passes through the hooks below.
_RX_CACHE = {}
_RXI_CACHE = {}


def _rx(pattern):
    p = _RX_CACHE.get(pattern)
    if p is None:
        p = _RX_CACHE[pattern] = re.compile(pattern)
    return p


def _rxi(pattern):
    p = _RXI_CACHE.get(pattern)
    if p is None:
        p = _RXI_CACHE[pattern] = re.compile(pattern, re.I)
    return p


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# The runner is needed before anything loads, so its absence is settled here
# as one paragraph (stderr, exit 2: a setup problem, not a board failure)
# rather than as the traceback importlib would print.
if not os.path.isfile(RUNNER):
    print("check-suite-ui-boot: %s is not present; this gate drives the paste "
          "through riptide's stack runner." % RUNNER, file=sys.stderr)
    sys.exit(2)
DB = _load("check_demo_boot", RUNNER)
LCS = DB.LCS            # the ONE interpreter module the runner drives
Thrown = LCS.Thrown


# ==========================================================================
# what the board must show, and why
# ==========================================================================

# The scopes this tier runs, in kSuKeys order: in this profile each member is
# absent and nothing it runs is a member harness.
FAST_SCOPES = ("sodiumxt", "torrentxt", "enetxt", "datachannelxt", "box2dxt",
               "coinxt", "riptide", "cross")
# Left out, each with its MEASURED reason and the SIGNATURE that reason leaves
# (2026-09-24, re-measured 2026-09-25, this profile): ("threw", the start of
# the exception it raises) or ("fails", None: it finishes with FAIL lines).
# Checked against kSuKeys, so a new member must be placed in one list or the
# other, and scenario_slow_reasons RE-RUNS each one in a fresh interpreter
# and fails the gate if its signature is gone: an excuse nobody re-checks
# outlives its reason. riptide's did, from 8ea0f21 (the 7-key check it cited,
# fixed) until a review found it on 2026-09-25; it is in the fast tier now.
SLOW_SCOPES = {
    "onionxt": ("its folded harness runs (1.4 s) and prints FAIL lines "
                "(thirteen on 2026-09-25) on `the result` after a command, "
                "which the runner does not model: the harness is onionxt's, "
                "not the board", ("fails", None)),
    "nostrxt": ("its folded harness recurses past Python's stack limit in "
                "the model before it finishes", ("threw", "RecursionError")),
    "holde-em": ("its folded harness dispatches its sections with "
                 "`do pName`, which the runner refuses",
                 ("threw", "SyntaxError: unsupported statement: 'do pName'")),
}

# THE PROBE'S ANSWERS IN THIS PROFILE, read back after the first run. The
# absent half proves the profile is what it says; the present half proves the
# model ran each embedded layer's tripwire vector to the right answer (a model
# that mis-ran nxWsAcceptFor would print "the paste is damaged").
EXPECTED_PROBE = {
    "shavesodium": (False, "sxVersion is neither installed nor defined"),
    "shavetorrent": (False, "btStartSession is absent: the probe's catch"),
    "shaveenet": (False, "enLibraryVersion is absent"),
    "shavedc": (False, "dcLibraryVersion is absent"),
    "shavecoin": (False, "cxKeccak256 is the .lcb half, absent"),
    "shavebox2d": (False, "b2Version is the raw binding, absent (the Kit's "
                          "b2kEnsureNativeLib exits on an unsaved stack)"),
    "shaveonion": (True, "oxVersion is the embedded onionxt layer"),
    "shavecoinscript": (True, "cxHexEncode(0xdead) is the embedded coinxt "
                              "script half, computed in script"),
    "shaveriptidescript": (True, "rsZeroTarget() is the embedded riptide "
                                 "layer, 40 zeros"),
    "shavenostrscript": (True, "nxWsAcceptFor is the embedded nostrxt core: "
                               "sha1Digest and its own base64 over the RFC "
                               "6455 sample"),
}
# The names the probe calls, split by what the profile says about them.
ABSENT_NATIVES = ("sxVersion", "btStartSession", "enLibraryVersion",
                  "dcLibraryVersion", "cxKeccak256", "b2Version")
EMBEDDED_PROBES = ("oxVersion", "cxHexEncode", "rsZeroTarget",
                   "nxWsAcceptFor", "b2kEnsureNativeLib")
# The prefixes a NATIVE extension's handlers carry. Nothing installed as a
# native may carry one (the embedded layers are script handlers, not natives).
NATIVE_PREFIXES = ("sx", "bt", "en", "dc", "cx", "b2")

# EACH FAST SCOPE'S PILL, established by reading the run rather than by
# running it: (kind, text, reason). A scoped run counts EVERYTHING to its own
# row, the probe and the teardown included.
EXPECTED_PILLS = {
    "sodiumxt": ("wait", "absent",
                 "stSodiumSection and the deep block each SKIP (sHaveSodium "
                 "false): 0 passed, 2 skipped, and suPresent is false"),
    "torrentxt": ("wait", "unavailable",
                  "the sampler and the deep block SKIP; the probe cannot tell "
                  "not-installed from a live session, so torrentxt alone "
                  "reads unavailable"),
    "enetxt": ("wait", "absent",
               "the deep block, the seal, the loopback start and the budget's "
               "ENet half SKIP; the DC half is out of scope (a note)"),
    "datachannelxt": ("wait", "absent",
                      "the deep block, the seal and the DC loopback start "
                      "SKIP; the budget section belongs to the ENet loopback "
                      "and does not run"),
    "box2dxt": ("wait", "absent",
                "the deep block SKIPs: the Kit is embedded, the physics is "
                "native"),
    "coinxt": ("wait", "absent",
               "the sampler and the deep block SKIP; its script half IS "
               "embedded (sHaveCoinScript true) but suPresent needs both "
               "halves, so the row reads absent, not skipped"),
    "cross": ("ok", "OK",
              "identity, BEP44, the seal, both loopbacks and both budget "
              "halves SKIP, but stCrossOnionSection runs at the finish on the "
              "embedded onionxt layer and PASSES both its checks "
              "(capabilities advertised absent without SodiumXT; "
              "offlineAddress tracks SHA3's absence)"),
}

# FAIL lines a fast-tier run prints because of a MODEL limitation, not a
# defect: {exact report line: reason}. EMPTY, and that is measured: no fast
# scope prints a FAIL in this profile. A FAIL line not listed here fails the
# gate, and so does an entry no run printed (a stale excuse).
EXPECTED_MODEL_FAILS = {}

# The report's FRAME: what a scoped run writes OUTSIDE every tally, so no row
# owns it. Spelled as the core writes them; a changed title fails the member
# view check loudly rather than quietly re-owning lines.
DEEP_HEADER = ("== deep per-member self-tests (each member's own harness, "
               "folded in) ==")
BOOT_HEADER = ("== boot self-check (this window's own, run on open; NOT "
               "counted in the totals) ==")
SUMMARY_HEADER = "== summary =="
BOARD_FAIL = "FAIL  the rows account for every counted check"

# openStack, in its order (the boot scenario stands in for it with a scoped
# run; asserted so the stand-in cannot drift from it).
OPEN_STACK = ("suBuild", "stCleanup", "stRun", "suScRun")

# The paste's own timers: none may outlive a finished run.
CORE_TIMERS = ("suPump", "suRunTick")
TIMER_BOUND = 60


# ==========================================================================
# the model delta (see the header for each one's reason)
# ==========================================================================

DELTAS = collections.OrderedDict([
    ("send-in", "send X to me in N ms queues X under an engine message id"),
    ("pending-messages", "the pendingMessages, id,time,message,object"),
    ("cancel", "cancel N removes queued message N"),
    ("timer-delivery", "a queued message is delivered when the driver asks"),
    ("mouse-press", "mouseDown then mouseUp with the target and pWhich"),
    ("pass", "pass <message> is recorded"),
    ("autohilite", "an autoHilite button hilites for the press only"),
    ("answer", "answer EXPR is recorded"),
    ("line-prop", "set the P of line N of field F records a per-line value"),
    ("field-replace", "put X into field F drops F's per-line styling"),
    ("length-of", "the length of X"),
    ("effective-filename", "the effective filename of this stack is empty"),
    ("control-by-index", "controls of this card, by index"),
    ("native-command", "a modelled extension command in statement position"),
])
FIRED = collections.Counter()


def fire(name):
    FIRED[name] += 1


class SuiteWorld(DB.World):
    def __init__(self, sandbox):
        super().__init__(sandbox)
        self.pending = []           # [id, due_ms, message text]
        # Another open stack's timers: [id, due_ms, message, its long id].
        # `the pendingMessages` is engine-wide, so the paste SEES these, and
        # they are never delivered here; `cancel` can still remove them,
        # which is exactly the defect scenario_foreign_timers watches for.
        self.foreign = []
        self.next_msg_id = 3001
        self.answers = []
        self.passed = []            # message names, in the order passed
        # The modelled extension COMMANDS a statement may call (lower-case
        # names in LCS.HASHES). EMPTY in the all-absent profile; only
        # scenario_transport_holds fills it, for its own interpreter.
        self.native_commands = set()


class SuiteExpr(DB.DemoExpr):
    """The runner's expression surface plus the reads the board makes that
    it lacks: the pendingMessages, the length, the effective filename, and a
    card's controls by index."""

    def p_atom(self):
        # ws() first, for the reason the runner's own p_atom gives: these
        # branches are anchored regexes and a leading space makes them miss.
        self.ws()
        rest = self.s[self.i:]
        if rest[:4].lower() == "the ":
            m = _rxi(r'the\s+pendingMessages\b').match(rest)
            if m:
                self.i += m.end()
                fire("pending-messages")
                return self.ip.pending_text()
            m = _rxi(r'the\s+length\s+of\s+').match(rest)
            if m:
                # a FACTOR, bound like the base's `the number of chars of`:
                # `the length of X > N` compares the length
                self.i += m.end()
                fire("length-of")
                return len(str(LCS._disp(self.p_unary())))
            m = _rxi(r'the\s+effective\s+filename\s+of\s+this\s+stack\b').match(rest)
            if m:
                self.i += m.end()
                fire("effective-filename")
                return ""
            m = _rxi(r'the\s+number\s+of\s+controls\s+of\s+this\s+card\b').match(rest)
            if m:
                self.i += m.end()
                fire("control-by-index")
                return len(self.ip.world.current().controls)
            m = _rxi(r'the\s+short\s+name\s+of\s+control\s+(.+?)\s+of\s+this\s+card\b').match(rest)
            if m:
                self.i += m.end()
                fire("control-by-index")
                return self.ip.control_at(m.group(1), self.env).name
        return super().p_atom()


class SuiteInterp(DB.DemoInterp):
    def eval_expr(self, expr, env):
        return SuiteExpr(self, env).parse(expr)

    # -- the timer queue ----------------------------------------------------
    def pending_text(self):
        world = self.world
        out = []
        rows = [(mid, due, text, 'stack "%s"' % world.stack_name)
                for mid, due, text in world.pending]
        rows += [tuple(f) for f in world.foreign]
        for mid, due, text, target in sorted(rows, key=lambda p: (p[1], p[0])):
            words = text.split()
            out.append("%d,%.3f,%s,%s" % (mid, due / 1000.0,
                                          words[0] if words else "", target))
        return "\n".join(out)

    def pending_names(self):
        return [p[2].split()[0] for p in
                sorted(self.world.pending, key=lambda p: (p[1], p[0]))
                if p[2].split()]

    def parse_message(self, text):
        """A queued message's name and its arguments, parsed by this class's
        own expressions (the runner's deliver_sends does the same with its
        own)."""
        name = text.split()[0]
        rest = text[text.index(name) + len(name):].strip()
        return name, self._args(rest, {})

    def _args(self, rest, env):
        args = []
        if rest:
            p = SuiteExpr(self, env)
            p.s, p.i = rest, 0
            while True:
                args.append(p.p_or())
                p.ws()
                if p.i < len(p.s) and p.s[p.i] == ",":
                    p.i += 1
                    continue
                break
            if p.i < len(p.s):
                raise SyntaxError("trailing input in call %r" % rest)
        return args

    def control_at(self, idx_expr, env):
        card = self.world.current()
        n = int(LCS._n(self.eval_expr(idx_expr, env)))
        if not 1 <= n <= len(card.controls):
            raise Thrown("Chunk: no such object (control %d of %d)"
                         % (n, len(card.controls)))
        return card.controls[n - 1]

    # -- object properties --------------------------------------------------
    def obj_prop_get(self, m, exprobj):
        if m.group(2).lower() == "visible":
            kind, obj = self._objref(m, exprobj)
            if kind == "control" and "visible" not in obj.props:
                # REFUSED rather than chosen (see the header)
                raise SyntaxError("the visible of %s \"%s\" was never set: "
                                  "unmodelled" % (obj.ctype, obj.name))
        return super().obj_prop_get(m, exprobj)

    # -- statements ---------------------------------------------------------
    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        head = line.split(None, 1)
        w0 = head[0].lower() if head else ""
        world = self.world

        if w0 == "send":
            m = _rxi(r'send\s+(.+?)\s+to\s+me\s+in\s+(.+?)\s*'
                     r'(milliseconds|millisecs|ms|seconds|ticks)$').match(line)
            if m:
                msg = str(LCS._disp(self.eval_expr(m.group(1), env)))
                delay = LCS._n(self.eval_expr(m.group(2), env))
                unit = m.group(3).lower()
                if unit == "seconds":
                    delay *= 1000
                elif unit == "ticks":
                    delay = delay * 1000 / 60.0
                mid = world.next_msg_id
                world.next_msg_id += 1
                world.pending.append([mid, world.ms + max(0, int(delay)), msg])
                world.result = mid
                fire("send-in")
                return i + 1
        elif w0 == "cancel":
            m = _rxi(r'cancel\s+(.+)$').match(line)
            if m:
                mid = int(LCS._n(self.eval_expr(m.group(1), env)))
                before = len(world.pending) + len(world.foreign)
                world.pending = [p for p in world.pending if p[0] != mid]
                world.foreign = [f for f in world.foreign if f[0] != mid]
                if len(world.pending) + len(world.foreign) < before:
                    fire("cancel")
                return i + 1
        elif w0 == "pass":
            m = _rxi(r'pass\s+(\w+)$').match(line)
            if m:
                world.passed.append(m.group(1))
                fire("pass")
                raise LCS._Return("")
        elif w0 == "answer":
            m = _rxi(r'answer\s+(.+)$').match(line)
            if m:
                world.answers.append(str(LCS._disp(self.eval_expr(m.group(1),
                                                                  env))))
                world.result = ""
                fire("answer")
                return i + 1
        elif w0 == "set":
            m = _rxi(r'set\s+the\s+(\w+)\s+of\s+line\s+(.+?)\s+of\s+field\s+'
                     r'(.+?)\s+to\s+(.+)$').match(line)
            if m:
                n = int(LCS._n(self.eval_expr(m.group(2), env)))
                name = str(LCS._disp(self.eval_expr(m.group(3), env)))
                ctl = world.resolve("field", name)
                if ctl is None:
                    raise Thrown('Chunk: no such object (field "%s")' % name)
                count = len(LCS._split_chunks(ctl.content, "\n"))
                if not 1 <= n <= count:
                    raise SyntaxError("line %d of a %d-line field: a style "
                                      "past the text is not modelled"
                                      % (n, count))
                styles = getattr(ctl, "line_props", None)
                if styles is None:
                    styles = ctl.line_props = {}
                styles.setdefault(m.group(1).lower(), {})[n] = \
                    self.eval_expr(m.group(4), env)
                fire("line-prop")
                return i + 1
        elif w0 == "delete":
            m = _rxi(r'delete\s+control\s+(.+?)\s+of\s+this\s+card$').match(line)
            if m:
                ctl = self.control_at(m.group(1), env)
                world.current().controls.remove(ctl)
                fire("control-by-index")
                return i + 1
        elif w0 == "put":
            parts = LCS.split_outside_strings(line[4:], ("into", "after",
                                                         "before"))
            if parts and _rxi(r'field\s+').match(parts[2].strip()):
                self._put_field(parts, env)
                return i + 1
        elif w0 in world.native_commands:
            # a modelled extension COMMAND in statement position (`enHostDestroy
            # sEnServer`, a bare `enDeinitialize`): the base reaches natives
            # only as functions, so without this a statement call would be a
            # caught "can't find handler" and the model would never see it
            LCS.HASHES[w0](self._args(line[len(head[0]):].strip(), env))
            fire("native-command")
            return i + 1
        elif w0 in self.handlers:
            # a statement-position handler call, its arguments parsed by THIS
            # class's expressions (the runner's own branch builds a DemoExpr,
            # which cannot read the forms SuiteExpr adds)
            self.call(head[0], self._args(line[len(head[0]):].strip(), env))
            return i + 1
        return super()._exec_stmt(body, i, env)

    def _put_field(self, parts, env):
        """The runner's field write, plus field-replace: `into` drops every
        per-line style, `after` keeps them (the lines above the insertion do
        not move), `before` drops them (they all move)."""
        value = self.eval_expr(parts[0], env)
        prep, tgt = parts[1], parts[2].strip()
        m = _rxi(r'field\s+(.+?)(?:\s+of\s+card\s+(.+))?$').match(tgt)
        name = str(LCS._disp(self.eval_expr(m.group(1), env)))
        cardspec = None
        if m.group(2):
            cardspec = str(LCS._disp(self.eval_expr(m.group(2), env)))
        ctl = self.world.resolve("field", name, cardspec)
        if ctl is None:
            raise Thrown('Chunk: no such object (field "%s")' % name)
        v = str(LCS._disp(value))
        if prep == "after":
            ctl.content = ctl.content + v
            return
        ctl.content = v if prep == "into" else v + ctl.content
        if getattr(ctl, "line_props", None):
            ctl.line_props = {}
            fire("field-replace")


# ==========================================================================
# the engine surface the drive uses: clicks and ticks
# ==========================================================================

def press(ip, world, name, which=1, release=True):
    """One click on the control NAMED `name`: mouseDown, then (on release)
    mouseUp, with `the target` set. Returns (down_passed, up_passed, error);
    a *_passed is True when the board `pass`ed that message on."""
    ctl = world.anywhere(name)
    if ctl is None:
        return None, None, "there is no control %r to press" % name
    fire("mouse-press")
    world.target = (ctl.ctype, ctl.name)
    auto = (ctl.ctype == "button"
            and ctl.props.get("autohilite", True) is not False)
    if auto:
        ctl.props["hilite"] = True
        fire("autohilite")
    down = up = None
    try:
        n0 = len(world.passed)
        ip.call("mouseDown", [which])
        down = any(p.lower() == "mousedown" for p in world.passed[n0:])
        if release:
            n1 = len(world.passed)
            ip.call("mouseUp", [which])
            up = any(p.lower() == "mouseup" for p in world.passed[n1:])
    except Exception as exc:                            # noqa: BLE001
        return down, up, "%s: %s" % (type(exc).__name__, exc)
    finally:
        if auto:
            ctl.props["hilite"] = False
        world.target = None
    return down, up, None


def deliver_next(ip, world, only=None):
    """Deliver the earliest queued message (or the earliest named in `only`)
    and return its name, or None when there is none."""
    order = sorted(world.pending, key=lambda p: (p[1], p[0]))
    pick = next((p for p in order
                 if only is None or p[2].split()[0] in only), None)
    if pick is None:
        return None
    world.pending.remove(pick)
    world.ms = max(world.ms, pick[1])
    name, args = ip.parse_message(pick[2])
    fire("timer-delivery")
    ip.call(name, args)
    return name


def deliver_all(ip, world, bound=TIMER_BOUND):
    """Every queued message, earliest first, until none remain; raises when
    the chain does not converge."""
    names = []
    while world.pending:
        if len(names) >= bound:
            raise RuntimeError("the timers did not converge in %d deliveries "
                               "(still queued: %s)"
                               % (bound, ", ".join(ip.pending_names())))
        names.append(deliver_next(ip, world))
    return names


# ==========================================================================
# the source and the profile
# ==========================================================================

def build_source(path, fail):
    """The paste the way the runner reads a stack: minus its `script "..."`
    line, the engine's non-literal-constant and one-line-if-else refusals
    applied, and riptide's three shared spelling rewrites, each required to
    fire (DB.build_source enforces all of it)."""
    src, _hits = DB.build_source(path, fail)
    return src


def install_engine_builtins(world):
    """ENGINE builtins only - never an extension (see THE PROFILE)."""
    DB.install_engine_functions(world)

    def _b(a):
        return str(LCS._disp(a)).encode("latin-1")

    LCS.HASHES.update({
        # nxWsAcceptFor's digest: the engine's own SHA-1
        "sha1digest": lambda a: hashlib.sha1(_b(a[0])).digest().decode(
            "latin-1"),
        # what riptide's shared rewrite writes for binaryEncode's n / N / NN,
        # defined exactly as its own gate defines them
        "rstbeu64": lambda a: int(LCS._n(a[0])).to_bytes(8, "big").decode(
            "latin-1"),
        "rstbeu32": lambda a: int(LCS._n(a[0])).to_bytes(4, "big").decode(
            "latin-1"),
        "rstbeu16": lambda a: int(LCS._n(a[0])).to_bytes(2, "big").decode(
            "latin-1"),
    })


# ==========================================================================
# the checks
# ==========================================================================

class Checker:
    """ck(label, ok, detail) for booleans and eq(label, got, want) for values:
    two names, because the wallet gate once shipped nine value-shaped checks
    through a boolean ck() and every one passed for any value."""

    def __init__(self, verbose):
        self.verbose = verbose
        self.n = 0
        self.failures = []
        self.scenario = ""

    def section(self, title):
        self.scenario = title
        if self.verbose:
            print("-- %s" % title)

    def ck(self, label, ok, detail=""):
        self.n += 1
        if ok:
            if self.verbose:
                print("  ok   %s" % label)
            return True
        text = "[%s] %s" % (self.scenario, label)
        if detail:
            text += "\n       " + str(detail).replace("\n", "\n       ")
        self.failures.append(text)
        print("  FAIL " + text)
        return False

    def eq(self, label, got, want):
        return self.ck(label, got == want,
                       "got:  %r\nwant: %r" % (got, want))

    def threw(self, label, exc):
        return self.ck(label, False, "%s: %s" % (type(exc).__name__, exc))


def _items(text):
    return [x for x in str(text).split(",") if x != ""]


def _lines(text):
    """Lines under the engine's one-trailing-delimiter rule."""
    return LCS._split_chunks(str(text), "\n")


def line_kind(line):
    """THE SPEC suLineKind implements (its header comment), written here
    independently so a defect there cannot also be the expectation."""
    w = line.split()
    w1 = w[0] if w else ""
    w2 = w[1] if len(w) > 1 else ""
    if w1 == "FAIL":
        return "fail"
    if w1 in ("PASS", "ok"):
        return "pass"
    if w1 in ("SKIP", "skip"):
        return "skip"
    if w1 == "--" and w2.startswith("(skipped"):
        return "skip"
    if w1 == "==":
        return "head"
    if w1 == "----":
        return "marker"
    if w1 == "--":
        return "sub"
    return "other"


def frame_mask(lines):
    """Which report lines no row owns, by the DESIGN (not by the spans the
    code recorded): stRun's opening three lines; the deep-harness header and
    its notes (written with no tally open); the boot section (uncounted); the
    summary, bar the board check's own FAIL and its two notes, which the core
    counts to a row. Each header takes the blank line stSection writes above
    it."""
    frame = [k < 3 for k in range(len(lines))]
    k = 0
    while k < len(lines):
        ln = lines[k]
        if ln not in (DEEP_HEADER, BOOT_HEADER, SUMMARY_HEADER):
            k += 1
            continue
        if k > 0 and lines[k - 1] == "":
            frame[k - 1] = True
        frame[k] = True
        j = k + 1
        while j < len(lines):
            if ln == SUMMARY_HEADER:
                if lines[j].startswith(BOARD_FAIL):
                    j += 3
                    continue
            elif ln == BOOT_HEADER:
                if not lines[j].startswith("      [boot] "):
                    break
            elif not lines[j].startswith("      "):
                break
            frame[j] = True
            j += 1
        k = j
    return frame


def owned_runs(report):
    """The runs of consecutive report lines a scoped run's row owns."""
    lines = _lines(report)
    mask = frame_mask(lines)
    runs, cur = [], []
    for k, ln in enumerate(lines):
        if mask[k]:
            if cur:
                runs.append(cur)
                cur = []
            continue
        cur.append(ln)
    if cur:
        runs.append(cur)
    return runs


def pill_grounds(ip):
    """The kit's pill ground per kind, READ FROM THE PASTE's uiPill (the
    carried kit block), never copied here: {"ok", "wait", "bad", None: the
    default}. A hand-copied colour goes stale silently."""
    _params, body = ip.handlers["uipill"]
    out, kind, in_chain = {}, "?", False
    for raw in body:
        s = raw.strip()
        m = _rx(r'^(?:else\s+)?if\s+pKind\s+is\s+"(\w+)"\s+then$').match(s)
        if m:
            kind, in_chain = m.group(1), True
            continue
        if s == "else" and in_chain:
            kind = None
            continue
        if s == "end if":
            in_chain = False
            continue
        m = _rx(r'^set\s+the\s+backgroundColor\s+of\s+graphic\s+\(pName\s*&'
                r'\s*"Bg"\)\s+to\s+"([\d,]+)"$').match(s)
        if m and in_chain and kind not in out:
            out[kind] = m.group(1)
    return out


class Board:
    """The driven stack: the interpreter, the world and the paste's own
    constants, with the reads every check shares."""

    def __init__(self, ip, world):
        self.ip, self.world = ip, world
        k = ip.constants
        self.keys = _items(k["kSuKeys"])
        self.names = _items(k["kSuNames"])
        self.no_harness = str(k["kSuNoHarness"])
        self.width = int(k["kStWidth"])
        self.height = int(k["kStHeight"])
        self.colors = dict((n, str(k[n])) for n in
                           ("kUiOk", "kUiWarn", "kUiBad", "kUiAccent"))
        self.pill = pill_grounds(ip)
        self.seen_fails = set()

    def g(self, name):
        return self.ip.globals.get(name.lower(), "")

    def num(self, name):
        return int(LCS._n(self.g(name)))

    def row(self, key):
        out = []
        for v in ("sSuP", "sSuF", "sSuS"):
            a = self.g(v)
            out.append(int(LCS._n(LCS._arr_get(a, key)
                                  if isinstance(a, dict) else "")))
        return tuple(out)

    def totals(self):
        return (self.num("sPassed"), self.num("sFailed"), self.num("sSkipped"))

    def ctl(self, name):
        return self.world.anywhere(name)

    def text(self, name):
        c = self.ctl(name)
        return "" if c is None else c.content

    def title_of(self, key):
        return self.names[self.keys.index(key)]

    def report(self):
        return str(self.g("sResultText"))

    def visible(self, name):
        c = self.ctl(name)
        # the engine's default for a created control is visible
        return c is not None and c.props.get("visible", True) is not False

    def line_color(self, name, n):
        c = self.ctl(name)
        styles = getattr(c, "line_props", None) or {}
        return styles.get("foregroundcolor", {}).get(n)

    def status(self):
        c = self.ctl("uiStatus")
        return ("", None) if c is None else (c.content,
                                             c.props.get("foregroundcolor"))

    def trailer(self):
        return str(self.ip.call("stReportText", []))[len(self.report()):]


def check_no_timers(c, board, also=()):
    left = [n for n in board.ip.pending_names()
            if n in CORE_TIMERS or n in also or n.lower().startswith("he1")]
    c.eq("no suPump, suRunTick or he1* message is left pending", left, [])


def check_delimiters(c):
    """The model holds the item and line delimiters as GLOBAL state (engine
    note 2.3, OBSERVED; the dictionary's local reading is its documented
    counterpoint), so a handler that sets one and returns without restoring
    it leaks it into everything after - here, visibly."""
    c.eq("no handler left the item or line delimiter changed",
         (LCS.ITEM_DELIMITER[0], LCS.LINE_DELIMITER[0]), (",", "\n"))


# ---- the profile ----------------------------------------------------------

def check_profile(c, ip):
    c.section("the all-absent profile")
    natives = sorted(k for k in LCS.HASHES if k.startswith(NATIVE_PREFIXES))
    c.eq("no native extension handler is installed", natives, [])
    defined = [n for n in ABSENT_NATIVES if n.lower() in ip.handlers]
    c.eq("no absent native is DEFINED in the paste (a script stand-in would "
         "answer its probe)", defined, [])
    missing = [n for n in EMBEDDED_PROBES if n.lower() not in ip.handlers]
    c.eq("every embedded probe target is defined in the paste", missing, [])
    body = tuple(ln.strip() for ln in ip.handlers["openstack"][1]
                 if ln.strip())
    c.eq("openStack is the four calls the boot scenario stands in for",
         body, OPEN_STACK)
    keys = _items(ip.constants["kSuKeys"])
    unplaced = [k for k in keys if k != str(ip.constants["kSuNoHarness"])
                and k not in FAST_SCOPES and k not in SLOW_SCOPES]
    c.eq("every row with a Run is in FAST_SCOPES or SLOW_SCOPES", unplaced,
         [])


def check_probe_answers(c, board):
    for var, (want, why) in EXPECTED_PROBE.items():
        got = board.g(var)
        c.ck("probe: %s is %s (%s)" % (var, want, why), LCS._eq(got, want),
             "got %r" % (got,))


# ---- the build ------------------------------------------------------------

def rect_of(ctl):
    return list(ctl.rect) if ctl is not None and ctl.rect else None


def row_controls(board, key):
    names = ["suName", "suNote", "suPill", "suCount", "suRun", "suShow"]
    out = [board.ctl(n + key) for n in names]
    out.append(board.ctl("suPill" + key + "Bg"))
    return [ct for ct in out if ct is not None]


def check_build(c, board):
    world, ip = board.world, board.ip
    c.eq("the window is %d x %d" % (board.width, board.height),
         (world.stack_props.get("width"), world.stack_props.get("height")),
         (board.width, board.height))
    c.eq("the board is stamped", world.stack_props.get("usuuiversion"),
         ip.constants["kSuUiVersion"])
    listed = _items(ip.constants["kSuScControls"])
    rows = _items(ip.call("suRowControls", []))
    missing = [n for n in listed + rows if world.anywhere(n) is None]
    c.eq("every kSuScControls and suRowControls() name exists", missing, [])
    names = [ct.name for ct in world.current().controls]
    dupes = sorted(set(n for n in names if names.count(n) > 1))
    c.eq("no control name is built twice", dupes, [])
    outside = []
    for ct in world.current().controls:
        r = rect_of(ct)
        if (r is None or r[0] < 0 or r[1] < 0 or r[2] > board.width
                or r[3] > board.height or r[0] > r[2] or r[1] > r[3]):
            outside.append("%s %s" % (ct.name, r))
    c.eq("every control rect lies inside 0..%d x 0..%d"
         % (board.width, board.height), outside, [])
    clashes = []
    for a_i, a in enumerate(board.keys):
        for b in board.keys[a_i + 1:]:
            for ca in row_controls(board, a):
                for cb in row_controls(board, b):
                    ra, rb = rect_of(ca), rect_of(cb)
                    if (max(ra[0], rb[0]) < min(ra[2], rb[2])
                            and max(ra[1], rb[1]) < min(ra[3], rb[3])):
                        clashes.append("%s/%s" % (ca.name, cb.name))
    c.eq("no two row controls of different rows overlap", clashes, [])
    views = ("stResults", "suView", "suBootLog")
    rects = set(tuple(rect_of(board.ctl(v)) or ()) for v in views)
    c.ck("stResults, suView and suBootLog share one rect", len(rects) == 1,
         repr(rects))
    c.eq("exactly one results view shows",
         sum(1 for v in views if board.visible(v)), 1)
    c.eq("nocloud has a caption and no Run",
         (board.ctl("suNote" + board.no_harness) is not None,
          board.ctl("suRun" + board.no_harness) is None), (True, True))
    c.eq("the scaffold's two buttons keep their names under the board's "
         "labels", (board.ctl("stRerun").props.get("label"),
                    board.ctl("stCopy").props.get("label")),
         ("Run all", "Copy results"))
    c.eq("the screen lock is balanced", world.locked, 0)


def scenario_build(c, board):
    c.section("build")
    # the grounds every pill check compares against, read from the paste's
    # uiPill: all four kinds found, and four different colours, or those
    # checks would be comparing against nothing
    c.ck("the kit's four pill grounds were read from uiPill",
         set(board.pill) == {"ok", "wait", "bad", None}
         and len(set(board.pill.values())) == 4, repr(board.pill))
    check_build(c, board)
    c.eq("All is the view after a build",
         [v for v in ("stResults", "suView", "suBootLog")
          if board.visible(v)], ["stResults"])
    before = [(ct.name, rect_of(ct)) for ct in board.world.current().controls]
    try:
        board.ip.call("suBuild", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("a second suBuild runs", exc)
    after = [(ct.name, rect_of(ct)) for ct in board.world.current().controls]
    c.ck("a second build (the current stamp) creates, deletes and moves "
         "nothing", after == before, "%d controls, then %d"
         % (len(before), len(after)))
    # A person resizes the window (a new mainstack is resizable) and the
    # stack is reopened: the stamped build must put the size back, or the
    # boot self-check's 1200 x 640 line goes red over a green run (review,
    # 2026-09-25).
    world = board.world
    world.stack_props["width"], world.stack_props["height"] = 1400, 700
    try:
        board.ip.call("suBuild", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suBuild over a resized window runs", exc)
    c.eq("a stamped build over a resized window puts it back to %d x %d"
         % (board.width, board.height),
         (world.stack_props.get("width"), world.stack_props.get("height")),
         (board.width, board.height))
    return True


# ---- routing --------------------------------------------------------------

def scenario_routing(c, board):
    ip, world = board.ip, board.world
    c.section("routing: what the board's mouseDown passes on")
    for label, name, which, release in (
            ("a right-click on a row's Run", "suRunsodiumxt", 3, True),
            ("a press on a field (the results view)", "stResults", 1, True),
            ("a press on a pill (a field)", "suPillcoinxt", 1, True),
            ("a press on a panel (a graphic)", "suPanMembers", 1, True),
            ("the Run all button's mouseDown (its mouseUp is the scaffold's "
             "Run all, which this tier does not run)", "stRerun", 1, False)):
        filt = board.g("sSuFilter")
        down, up, err = press(ip, world, name, which, release)
        c.ck("%s: mouseDown passes" % label, err is None and down is True,
             err or "mouseDown was handled")
        if release:
            c.ck("%s: mouseUp passes" % label, up is True, "mouseUp handled")
        c.eq("%s: nothing is armed and the view is unchanged" % label,
             (ip.pending_names(), board.g("sSuArmed"), board.g("sSuFilter")),
             ([], "", filt))
    for key in (board.no_harness, "nosuchmember", ""):
        try:
            ip.call("suArmRun", [key])
        except Exception as exc:                        # noqa: BLE001
            c.threw("suArmRun %r runs" % key, exc)
            continue
        c.eq("suArmRun refuses %r silently (no Run to arm)" % key,
             (ip.pending_names(), board.g("sSuArmed")), ([], ""))


# ---- one scoped run, through the row's button -----------------------------

def arm_and_start(c, board, key):
    """Press suRun<key> and deliver the armed tick: the run's synchronous
    half has run and its pump is queued. False on anything else."""
    ip, world = board.ip, board.world
    down, up, err = press(ip, world, "suRun" + key)
    if not c.ck("the Run press on %s is handled on mouseDown (and its mouseUp "
                "passes)" % key, err is None and down is False and up is True,
                err or "down passed=%r up passed=%r" % (down, up)):
        return False
    c.eq("the press armed exactly one suRunTick", ip.pending_names(),
         ["suRunTick"])
    c.eq("sSuArmed names the row", board.g("sSuArmed"), key)
    c.ck("the status line says which run is starting",
         board.status()[0].startswith("Starting %s:" % board.title_of(key)),
         repr(board.status()))
    try:
        got = deliver_next(ip, world, only=("suRunTick",))
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suRunTick runs the scoped run", exc)
    c.eq("the armed tick was delivered", got, "suRunTick")
    # suSyncDone's status line: which scope, and what is still to come
    loop = key in ("enetxt", "datachannelxt", "cross")
    c.ck("the status line says the synchronous half is done and what is "
         "still to come", board.status()[0].startswith(
             "Running (%s only): the synchronous checks are done; %s"
             % (board.title_of(key),
                "the live loopbacks are still running" if loop
                else "the teardown and the summary follow on the next tick")),
         repr(board.status()))
    c.eq("a new run starts its summary line neutral (suRunStarting), "
         "whatever the last run's verdict was",
         board.ctl("stSummary").props.get("foregroundcolor"),
         str(ip.constants["kUiInk"]))
    return c.eq("the run's synchronous half ends live, its pump armed",
                (board.g("sAsyncRunning"), ip.pending_names(),
                 board.g("sSuArmed")), ("true", ["suPump"], ""))


def finish(c, board, label="the pump runs to the finish"):
    try:
        deliver_all(board.ip, board.world)
        return True
    except Exception as exc:                            # noqa: BLE001
        return c.threw(label, exc)


FOLDED_NOTE = (r'^\s+(\d+) passed, (\d+) failed, (\d+) skipped, folded into '
               r'the totals above$')
REPORT_NOTE = r'^\s+---- .+ report ----$'
SECTION_HEAD = r'^== .* ==$'


def returned_merges(lines, reports=None):
    """Each returned-report merge in a finished report, as (folded, own):
    the (P, F, S) stMergeReturned's note says it added to the totals, and the
    PASS / FAIL / SKIP lines of the member's verbatim report that are spelled
    the scaffold's way and so were counted as the core's own.

    `reports`, when given, is each merge's verbatim report AS HANDED to
    stMergeReturned, in merge order (the --full profile records them), and
    its lines are counted. Without it, the report is read back from the text:
    the lines after the "---- <member> report ----" note, up to the next
    section header - true of a SCOPED run only. In Run all the core writes the
    next members' SKIP lines straight after a verbatim report with no header
    between (the absent natives' deep self-tests follow OnionXT's), and that
    read took them as OnionXT's own: five skips short on the --full profile's
    first run, 2026-09-26."""
    out = []
    notes = 0
    for k, ln in enumerate(lines):
        m = _rx(FOLDED_NOTE).match(ln)
        if not m:
            continue
        folded = tuple(int(x) for x in m.groups())
        if reports is not None:
            text = reports[notes] if notes < len(reports) else ""
            notes += 1
            out.append((folded, tuple(
                sum(1 for x in _lines(text) if x.startswith(pfx))
                for pfx in ("PASS  ", "FAIL  ", "SKIP  "))))
            continue
        j = k + 1
        if j < len(lines) and _rx(REPORT_NOTE).match(lines[j]):
            j += 1
        own = [0, 0, 0]
        while j < len(lines) and not _rx(SECTION_HEAD).match(lines[j]):
            for i, pfx in enumerate(("PASS  ", "FAIL  ", "SKIP  ")):
                if lines[j].startswith(pfx):
                    own[i] += 1
            j += 1
        out.append((folded, tuple(own)))
    return out


def check_finished(c, board, scope, merged=None, boot_whole=True,
                   reports=None):
    """Everything a finished scoped run leaves behind. `merged` is
    (verbatim lines, (P, F, S) folded in) when the views scenario merged
    synthetic reports; None for a plain run, whose totals must be exactly the
    report's own PASS / FAIL / SKIP lines. `boot_whole` is False only where
    the self-check's delayed probe fired AFTER the report was finished, so
    the report carries the block as it stood then: a prefix of it.
    `reports` is every returned report as merged (returned_merges says why
    Run all needs them)."""
    ip, world = board.ip, board.world
    report = board.report()
    lines = _lines(report)
    c.eq("sStRunDone is true", board.g("sStRunDone"), "true")
    c.eq("sAsyncRunning is empty", board.g("sAsyncRunning"), "")
    c.ck("sSession is 0", LCS._eq(board.g("sSession"), 0),
         repr(board.g("sSession")))
    check_no_timers(c, board)
    c.eq("the screen lock is balanced", world.locked, 0)
    want = "Scope: %s" % ("all members (Run all)" if scope == "all"
                          else board.title_of(scope) + " only")
    c.eq("the report's third line is its scope",
         lines[2] if len(lines) > 2 else None, want)
    heads = [k for k, ln in enumerate(lines) if _rx(r'^== .* ==$').match(ln)]
    c.eq("the report's last section is the summary",
         lines[heads[-1]] if heads else None, SUMMARY_HEADER)
    sc_lines = _lines(board.g("sScLines"))
    if sc_lines:
        c.ck("the boot section is in the report and precedes the summary",
             BOOT_HEADER in lines
             and lines.index(BOOT_HEADER) < heads[-1])
        if BOOT_HEADER in lines:
            k = lines.index(BOOT_HEADER) + 1
            got_boot = []
            while k < len(lines) and lines[k].startswith("      [boot] "):
                got_boot.append(lines[k])
                k += 1
            want_boot = ["      [boot] " + ln for ln in sc_lines]
            if not boot_whole:
                want_boot = want_boot[:max(1, len(got_boot))]
            c.eq("it is the self-check's block%s, every line prefixed [boot]"
                 % ("" if boot_whole else " as it stood at the finish"),
                 got_boot, want_boot)
    got = board.totals()
    base = [sum(1 for ln in lines if ln.startswith(p))
            for p in ("PASS  ", "FAIL  ", "SKIP  ")]
    if merged is None:
        # The core's own lines, plus what each RETURNED report's merge says it
        # folded in, less any line in that report spelled the scaffold's way
        # (holde-em's PASS lines), which the plain count already took once.
        # Until 2026-09-25 this was the core's lines alone, true only while no
        # fast scope merged a report: riptide's did the moment a review moved
        # it into the fast tier.
        adj = returned_merges(lines, reports)
        if reports is not None:
            c.eq("one merge note per report handed to stMergeReturned",
                 len(adj), len(reports))
        c.eq("the totals are the report's own PASS / FAIL / SKIP lines plus "
             "what each returned report folded in (%d merged)" % len(adj),
             got, tuple(base[k] + sum(f[k] - o[k] for f, o in adj)
                        for k in range(3)))
    else:
        verbatim, folded = merged
        own = [sum(1 for ln in verbatim if ln.startswith(p))
               for p in ("PASS  ", "FAIL  ", "SKIP  ")]
        c.eq("the totals are the core's own lines plus what the merges "
             "folded in", got, tuple(base[k] - own[k] + folded[k]
                                     for k in range(3)))
    c.eq("sTotal is their sum", board.num("sTotal"), sum(got))
    # The Skips view counts SKIP-kind lines; the summary prints the totals.
    # They disagreed on the 2026-09-24 engine report (10 lines, 3 skipped:
    # riptide's and holde-em's skip counts were printed and never merged),
    # and this gate took both numbers from the same report lines, so it held
    # the disagreement as correct. Found by review, 2026-09-25.
    c.eq("the report's SKIP-kind lines are the totals' skipped count (the "
         "Skips view and the summary agree)",
         sum(1 for ln in lines if line_kind(ln) == "skip"), got[2])
    check_rows(c, board, scope, got, expected=merged is None)
    note = "the rows account for every counted check (%d / %d / %d)" % got
    c.ck("the summary carries the board check's note",
         any(ln.strip() == note for ln in lines), note)
    c.ck("and no board FAIL", not any(ln.startswith(BOARD_FAIL)
                                      for ln in lines))
    if merged is None:
        fails = [ln for ln in lines if ln.startswith("FAIL  ")]
        board.seen_fails.update(fails)
        c.eq("no FAIL line beyond EXPECTED_MODEL_FAILS",
             [ln for ln in fails if ln not in EXPECTED_MODEL_FAILS], [])
    text, colour = board.status()
    c.ck("the status line reads Finished", text.startswith("Finished ("),
         repr(text))
    c.eq("the status line's colour follows the verdict", colour,
         board.colors["kUiBad"] if got[1] else board.colors["kUiOk"])
    c.eq("stSummary carries the totals", board.text("stSummary"),
         "%d passed, %d failed, %d skipped, %d total" % (got + (sum(got),)))
    c.eq("stResults holds the finished report", board.text("stResults"),
         board.report())
    c.eq("every line of the All view is painted by its kind - FAIL kUiBad, "
         "the indented ones by suPaintResults", misfits(board, "stResults"),
         [])
    return got


def misfits(board, field):
    """The lines of `field` NOT painted the colour their kind (line_kind,
    the spec) calls for: FAIL kUiBad, a pass kUiOk, a skip kUiWarn, a section
    header kUiAccent. First six, for the report."""
    wrong = []
    for n, ln in enumerate(_lines(board.text(field)), 1):
        colour = {"fail": board.colors["kUiBad"],
                  "pass": board.colors["kUiOk"],
                  "skip": board.colors["kUiWarn"],
                  "head": board.colors["kUiAccent"]}.get(line_kind(ln))
        if colour is not None and board.line_color(field, n) != colour:
            wrong.append("line %d (%s): %r" % (n, line_kind(ln), ln[:60]))
    return wrong[:6]


def check_rows(c, board, scope, totals, expected=True):
    """Every row after a run: out of scope reads "not run", in scope carries
    its counts, and (a plain fast-scope run only - `expected`) the pill
    EXPECTED_PILLS established for it."""
    off_ground = []
    for key in board.keys:
        if key == board.no_harness:
            continue
        pill, bg = board.ctl("suPill" + key), board.ctl("suPill" + key + "Bg")
        ground = bg.props.get("backgroundcolor") if bg is not None else None
        if ground not in (board.pill.get("ok"), board.pill.get("wait"),
                          board.pill.get("bad")):
            off_ground.append("%s=%s" % (key, ground))
        counts = board.text("suCount" + key)
        if scope != "all" and key != scope:
            c.eq("row %s reads not run" % key,
                 (pill.content if pill else None, ground, counts),
                 ("not run", board.pill.get("wait"), "-"))
            continue
        row = board.row(key)
        if scope == key:
            c.eq("row %s counted the whole run (a scoped run's row IS the "
                 "run)" % key, row, tuple(totals))
        c.eq("row %s's counts label" % key, counts, "%d / %d / %d" % row)
        want = EXPECTED_PILLS.get(key)
        if want is not None and scope == key and expected:
            c.eq("row %s's pill (%s)" % (key, want[2]),
                 (pill.content if pill else None, ground),
                 (want[1], board.pill.get(want[0])))
    c.eq("every pill's ground is one of the kit's ok / wait / bad colours, "
         "never the navy default %s" % board.pill.get(None), off_ground, [])


def scenario_runs(c, board):
    """Each fast scope through its row's Run, then its finished report
    through Failures, Skips and its own Show: seven different frames (cross
    has no deep-harness header, enetxt a budget note, coinxt two sampler
    sections), so the member view's derivation meets each of them."""
    ip, world = board.ip, board.world
    for key in FAST_SCOPES:
        c.section("Run %s" % key)
        if not (arm_and_start(c, board, key) and finish(c, board)):
            continue
        check_finished(c, board, key)
        for which, button in (("fail", "suFilterFail"),
                              ("skip", "suFilterSkip")):
            text = check_filter(c, board, which, button, False)
            if text is not None:
                check_kind_view(c, board, which, text, False)
        text = check_filter(c, board, "m:" + key, "suShow" + key, False)
        if text is not None:
            check_member_view(c, board, key, text, False)
        press(ip, world, "suFilterAll")


# ---- the boot self-check --------------------------------------------------

def scenario_boot(c, board):
    """openStack's order - suBuild (done), stCleanup (suRunTick's first
    call), stRun, suScRun - with a scoped run standing in for Run all."""
    ip, world = board.ip, board.world
    c.section("boot self-check (openStack's order; a cross run stands in "
              "for Run all)")
    if not arm_and_start(c, board, "cross"):
        return False
    check_probe_answers(c, board)
    try:
        ip.call("suScRun", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suScRun runs", exc)
    c.eq("the run's pump and the self-check's one delayed probe are queued",
         ip.pending_names(), ["suPump", "scTickProbe"])
    if not finish(c, board, "the pump and the probe are delivered"):
        return False
    lines = _lines(board.report())
    c.ck("the summary says the probe had not fired when it was written "
         "(the pump's 33 ms tick lands before the probe's 400)",
         "      boot self-check: its one delayed check had not fired yet; "
         "see the Boot check view" in lines)
    check_finished(c, board, "cross", boot_whole=False)
    sc = _lines(board.g("sScLines"))
    c.eq("the self-check is green", (board.num("sScFailed"),
                                     board.num("sScSkipped")), (0, 0))
    c.eq("it passed one line per PASS it logged, and ran something",
         (board.num("sScPassed"),
          sum(1 for ln in sc if ln.startswith("PASS  ")) > 0),
         (sum(1 for ln in sc if ln.startswith("PASS  ")), True))
    c.ck("its last line is the green verdict",
         sc and sc[-1].strip().startswith("boot self-check GREEN"),
         repr(sc[-1:] if sc else None))
    c.eq("the Boot check log holds exactly the block",
         board.text("suBootLog"), str(board.g("sScLines")))
    text, colour = board.status()
    c.ck("the delayed probe restored the status line's text and colour",
         text.startswith("Finished (") and colour == board.colors["kUiOk"],
         repr((text, colour)))
    down, _up, err = press(ip, world, "suFilterBoot")
    c.ck("the Boot check press is handled", err is None and down is False,
         err or "passed")
    c.eq("the Boot check view shows alone",
         [v for v in ("stResults", "suView", "suBootLog")
          if board.visible(v)], ["suBootLog"])
    c.ck("and its caption says so",
         board.text("suViewCap").startswith("Boot check:"),
         repr(board.text("suViewCap")))
    press(ip, world, "suFilterAll")
    check_no_timers(c, board, also=("scTickProbe",))
    return True


# ---- refusals, Copy, close ------------------------------------------------

WARN_TEXT = "A run is still going"


def scenario_foreign_timers(c, board):
    """Another open harness's timers must survive this paste. The paste's
    pump was "stPump" until 2026-09-25, the name enet-selftest's and
    datachannel-selftest's pumps use, and stCancelPump cancels by name from
    the engine-wide `the pendingMessages`; every demo arms its own
    "scTickProbe", which suBootPending used to read as this board's."""
    ip, world = board.ip, board.world
    c.section("another stack's timers (enet-selftest's pump, a demo's probe)")
    mid = world.next_msg_id
    world.next_msg_id += 2
    world.foreign = [[mid, world.ms + 5000, "stPump",
                      'stack "enetSelfTest"'],
                     [mid + 1, world.ms + 5000, "scTickProbe",
                      'stack "sodiumDemo"']]
    try:
        ip.call("stCancelPump", [])
        pending = ip.call("suBootPending", [])
    except Exception as exc:                            # noqa: BLE001
        world.foreign = []
        return c.threw("stCancelPump and suBootPending run", exc)
    c.eq("stCancelPump leaves another stack's pump and probe queued",
         sorted(f[2] for f in world.foreign), ["scTickProbe", "stPump"])
    c.eq("suBootPending does not read another demo's pending probe as this "
         "board's (this board's has fired)", str(pending).lower(), "false")
    world.foreign = []
    return True


def check_refused(c, board, key, want_pending, want_armed, when):
    ip, world = board.ip, board.world
    down, _up, err = press(ip, world, "suRun" + key)
    c.ck("%s: the press on %s is handled" % (when, key),
         err is None and down is False, err or "passed")
    text, colour = board.status()
    c.ck("%s: it is refused with the warn status" % when,
         text.startswith(WARN_TEXT) and colour == board.colors["kUiWarn"],
         repr((text, colour)))
    c.eq("%s: nothing new is armed" % when,
         (ip.pending_names(), board.g("sSuArmed")), (want_pending, want_armed))


def scenario_refusals(c, board):
    ip, world = board.ip, board.world
    c.section("refusals: a second Run while one is armed, and while one is "
              "live")
    down, _up, err = press(ip, world, "suRuncoinxt")
    if not c.ck("the first Run arms", err is None and down is False
                and ip.pending_names() == ["suRunTick"],
                err or repr(ip.pending_names())):
        return False
    check_refused(c, board, "sodiumxt", ["suRunTick"], "coinxt",
                  "armed, not started")
    deliver_next(ip, world, only=("suRunTick",))
    c.eq("the armed run started, live", (board.g("sAsyncRunning"),
                                          ip.pending_names()),
         ("true", ["suPump"]))
    check_refused(c, board, "torrentxt", ["suPump"], "", "live")
    if finish(c, board):
        check_finished(c, board, "coinxt")
    return True


def scenario_copy(c, board):
    ip, world = board.ip, board.world
    c.section("Copy results, mid-run and after the finish")
    if not arm_and_start(c, board, "enetxt"):
        return False
    for live in (True, False):
        if not live and not finish(c, board):
            return False
        n = len(world.answers)
        down, up, err = press(ip, world, "stCopy")
        c.ck("(%s) Copy: mouseDown passes and the scaffold's mouseUp handles "
             "it" % ("live" if live else "finished"),
             err is None and down is True and up is False,
             err or "down passed=%r up passed=%r" % (down, up))
        p, f, s = board.totals()
        want = ("%d passed, %d failed, %d skipped, %d total\n\n"
                % (p, f, s, board.num("sTotal"))
                + str(ip.call("stReportText", [])))
        c.eq("(%s) the clipboard is the counts, a blank line and the report"
             % ("live" if live else "finished"),
             world.clipboard.get("text"), want)
        c.eq("(%s) the report on it %s the RUN NOT FINISHED trailer"
             % (("live", "carries") if live else ("finished", "lacks")),
             "RUN NOT FINISHED" in str(world.clipboard.get("text")), live)
        said = world.answers[n:]
        c.ck("(%s) one answer, and it says %s" % (
            "live" if live else "finished",
            "not finished" if live else "copied"),
             len(said) == 1 and said[0].startswith(
                 "Copied - but the run has NOT finished" if live
                 else "Results copied to the clipboard."), repr(said))
    check_finished(c, board, "enetxt")
    return True


def scenario_close(c, board):
    """closeStack is stCleanup: it must cancel EVERY timer the core arms - an
    armed Run's tick as well as a live run's pump - or the next open starts a
    run on top of the old one."""
    ip, world = board.ip, board.world
    c.section("closeStack while a Run is armed, and mid-run")
    down, _up, err = press(ip, world, "suRunbox2dxt")
    if not c.ck("a Run arms", err is None and down is False
                and ip.pending_names() == ["suRunTick"],
                err or repr(ip.pending_names())):
        return False
    try:
        ip.call("closeStack", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("closeStack runs", exc)
    c.eq("closing with a Run armed cancels its tick and forgets it",
         (ip.pending_names(), board.g("sSuArmed")), ([], ""))
    if not arm_and_start(c, board, "datachannelxt"):
        return False
    try:
        ip.call("closeStack", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("closeStack runs", exc)
    c.eq("closing mid-run cancels the pump and stops the run",
         (ip.pending_names(), board.g("sAsyncRunning")), ([], ""))
    c.eq("and frees what the run held",
         (str(board.g("sSession")), board.g("sPhaseEn"),
          board.g("sPhaseDc")), ("0", "skip", "skip"))
    c.eq("the screen lock is balanced", board.world.locked, 0)
    return True


# ---- the views ------------------------------------------------------------

# One synthetic report per folded report format, merged through the REAL
# stMergeReturned / stMergeCounted inside a real tally, exactly as
# stRunMemberHarnesses merges a member. Each carries a FAIL (with an indented
# note under it where the format has one), a pass and a skip in its own
# spelling, and (P, F, S) is what the merge FOLDS INTO THE TOTALS by the
# core's documented rules: a returned report's summary line, a counted
# report's counters. (Until 2026-09-25 riptide's and holde-em's skip counts
# were prose on line 2, printed and never merged, and this list asserted
# that as correct - (1, 1, 0) below - so the gate held the very disagreement
# a review then found on the board: a row reading 0 skipped over SKIP lines.)
SYNTHETIC = [
    # SodiumXT's shape: keyword-first summary as the LAST line
    ("returned", "Synthetic SodiumXT-shape report", "\n".join([
        "version:",
        "  ok   synthetic sodium: a check that passed",
        "  FAIL synthetic sodium: a check that failed",
        "      observed: synthetic sodium detail",
        "----",
        "PASSED: 1   FAILED: 1"]), None, (1, 1, 0)),
    # OnionXT's and NostrXT's: three counts first, `  --   (skipped: ...)`
    ("returned", "Synthetic OnionXT-shape report", "\n".join([
        "2 passed, 1 failed, 1 skipped",
        "-- initial state",
        "  ok   synthetic onion: a check that passed",
        "  FAIL synthetic onion: a refusal that did not refuse",
        "      observed: synthetic onion detail",
        "  --   (skipped: synthetic onion: no tor daemon here)",
        "  ok   synthetic onion: a second pass"]), None, (2, 1, 1)),
    # Riptide's (and holde-em's, since 2026-09-25): three counts first, a
    # prose line saying what the skips are, `  skip` lines
    ("returned", "Synthetic Riptide-shape report", "\n".join([
        "1 passed, 1 failed, 1 skipped",
        "(the skips are optional dependencies; see the log)",
        "----------------------------------------",
        "-- identity",
        "  ok   synthetic riptide: a check that passed",
        "  FAIL synthetic riptide: a tamper that verified",
        "  skip synthetic riptide: the live leg (no session)"]), None,
     (1, 1, 1)),
    # the counted members' (coinxt, torrentxt, enetxt, datachannelxt): the
    # scaffold's own unindented lines, the counters handed over separately
    ("counted", "Synthetic counted-shape report", "\n".join([
        "",
        "== synthetic counted section ==",
        "PASS  synthetic counted: a check that passed",
        "FAIL  synthetic counted: a check that failed",
        "      synthetic counted detail",
        "SKIP  synthetic counted: the live leg  (no extension)"]),
     (1, 1, 3, 1), (1, 1, 1)),
]


def merge_synthetic(c, board, key, reports):
    """Merge each report into row `key`, each in its own tally, the way
    stRunMemberHarnesses merges a member. Returns (verbatim report lines,
    folded (P, F, S)) or None."""
    ip = board.ip
    verbatim, folded = [], [0, 0, 0]
    for shape, member, text, counters, folds in reports:
        try:
            ip.call("suTallyOpen", [key])
            if shape == "returned":
                ip.call("stMergeReturned", [member, text, 1])
            else:
                p, f, t, s = counters
                ip.call("stMergeCounted", [member, text, p, f, t, s])
            ip.call("suTallyClose", [])
        except Exception as exc:                        # noqa: BLE001
            c.threw("merging %s" % member, exc)
            return None
        verbatim.extend(_lines(text))
        for j in range(3):
            folded[j] += folds[j]
    return verbatim, tuple(folded)


def view_body(text):
    """A composed view minus its trailer (the ruled line and after)."""
    lines = _lines(text)
    for k, ln in enumerate(lines):
        if ln.strip().startswith("RUN NOT FINISHED"):
            return lines[:max(0, k - 1)]
    return lines


FILTER_BUTTONS = ("suFilterAll", "suFilterFail", "suFilterSkip",
                  "suFilterBoot")


def check_filter(c, board, which, button, live):
    """Press a filter (or Show) button through the real route and check the
    view it leaves. Returns suView's text when that is the view showing."""
    ip, world = board.ip, board.world
    tag = "live" if live else "finished"
    down, _up, err = press(ip, world, button)
    c.ck("(%s) the %s press is handled on mouseDown" % (tag, button),
         err is None and down is False, err or "mouseDown passed")
    c.eq("(%s) sSuFilter after %s" % (tag, button), board.g("sSuFilter"),
         which)
    want = {"all": "stResults", "boot": "suBootLog"}.get(which, "suView")
    c.eq("(%s) exactly one results view shows, and it is %s" % (tag, want),
         [v for v in ("stResults", "suView", "suBootLog")
          if board.visible(v)], [want])
    lit = [b for b in FILTER_BUTTONS if board.ctl(b) is not None
           and board.ctl(b).props.get("hilite") is True]
    c.eq("(%s) the filter buttons' hilite marks the view after the release"
         % tag, lit, [button] if button in FILTER_BUTTONS else [])
    cap = board.text("suViewCap")
    lead = {"all": "All:", "fail": "Failures:", "skip": "Skips:",
            "boot": "Boot check:"}.get(which)
    if lead is None:
        lead = board.title_of(which[2:]) + ":"
    c.ck("(%s) the caption names the view" % tag, cap.startswith(lead),
         repr(cap))
    if want != "suView":
        return None
    text = board.text("suView")
    if live:
        c.ck("(live) the view ends with the scaffold's own RUN NOT FINISHED "
             "trailer", text.endswith(board.trailer())
             and "RUN NOT FINISHED" in board.trailer(), repr(text[-120:]))
    else:
        c.ck("(finished) no RUN NOT FINISHED trailer",
             "RUN NOT FINISHED" not in text, repr(text[-120:]))
    c.eq("(%s) every line of the %s view is painted by its kind, FAIL lines "
         "kUiBad" % (tag, which), misfits(board, "suView"), [])
    return text


def check_kind_view(c, board, kind, text, live):
    tag = "live" if live else "finished"
    want = [ln for ln in _lines(board.report()) if line_kind(ln) == kind]
    body = view_body(text)
    c.eq("(%s) the %s view holds every %s line of the report, in order"
         % (tag, kind, kind.upper()),
         [ln for ln in body if line_kind(ln) == kind], want)
    c.eq("(%s) and no line of another kind" % tag,
         [ln for ln in body if line_kind(ln) in ("fail", "pass", "skip")
          and line_kind(ln) != kind], [])
    word = "Failures:" if kind == "fail" else "Skips:"
    c.ck("(%s) its first line counts them (%d)" % (tag, len(want)),
         bool(body) and body[0].startswith("%s %d " % (word, len(want))),
         repr(body[:1]))
    return want


def check_member_view(c, board, key, text, live):
    """Show <key> must print EXACTLY the lines its row owns - derived from
    the design (frame_mask), not from the spans the code recorded - under a
    title with the row's counts, then the trailer while unfinished."""
    tag = "live" if live else "finished"
    runs = owned_runs(board.report())
    want = ("%s: %d passed, %d failed, %d skipped, in the lines below.\n"
            % ((board.title_of(key),) + board.row(key))
            + "".join("\n".join(run) + "\n" for run in runs)
            + (board.trailer() if live else ""))
    if text == want:
        return c.ck("(%s) Show %s is exactly the lines its row owns"
                    % (tag, key), True)
    got_l, want_l = text.split("\n"), want.split("\n")
    k = next((j for j in range(min(len(got_l), len(want_l)))
              if got_l[j] != want_l[j]), min(len(got_l), len(want_l)))
    return c.ck("(%s) Show %s is exactly the lines its row owns" % (tag, key),
                False, "first difference at view line %d:\n got:  %r\nwant: %r"
                % (k + 1, got_l[k] if k < len(got_l) else None,
                   want_l[k] if k < len(want_l) else None))


def scenario_views(c, board, key="sodiumxt"):
    """A LIVE scoped run with one synthetic report per folded format merged
    into its row, then every filter through the real route, before and after
    the pump finishes the run.

    One report arrives while the Failures view is SHOWING, and the pump's own
    per-tick paint (suPumpPaint) is called for it directly, the way a tick
    calls it: in this profile no loopback goes live, so the pump finishes on
    its first tick and never reaches its paint or its re-arm."""
    ip, world = board.ip, board.world
    c.section("views: Failures, Skips and Show %s over all four folded "
              "formats" % key)
    if not arm_and_start(c, board, key):
        return False
    first = merge_synthetic(c, board, key, SYNTHETIC[:-1])
    if first is None:
        return False
    check_filter(c, board, "fail", "suFilterFail", True)
    last = merge_synthetic(c, board, key, SYNTHETIC[-1:])
    if last is None:
        return False
    merged = (first[0] + last[0],
              tuple(first[1][k] + last[1][k] for k in range(3)))
    try:
        ip.call("suPumpPaint", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("the pump's paint runs", exc)
    view = board.text("suView")
    c.ck("(live) the pump's paint re-renders a showing Failures view when "
         "the report grew", "FAIL  synthetic counted: a check that failed"
         in _lines(view), repr(view[-160:]))
    check_kind_view(c, board, "fail", view, True)
    synth_fails = [ln for _s, _m, t, _c, _f in SYNTHETIC for ln in _lines(t)
                   if line_kind(ln) == "fail"]
    # THE ORDER IS DELIBERATE: the live pass ENDS on Failures and the
    # finished pass BEGINS on it, so the finish's re-render (suAfterDone) and
    # the next press rewrite a view whose FAIL lines sit on the same line
    # numbers as the live one's. A painter that stopped painting after the
    # finish would pass there on the live render's colours - which is what the
    # field-replace delta exists to refuse (test-suite-ui-boot.py, mutant h).
    orders = {True: ("skip", "member", "all", "fail"),
              False: ("fail", "skip", "member", "all")}
    for live in (True, False):
        if not live:
            if not finish(c, board):
                return False
        tag = "live" if live else "finished"
        for which in orders[live]:
            if which == "fail":
                text = check_filter(c, board, "fail", "suFilterFail", live)
                if text is None:
                    continue
                fails = check_kind_view(c, board, "fail", text, live)
                c.ck("(%s) the synthetic FAIL lines, indented and not, are "
                     "all among them" % tag,
                     len(synth_fails) == 4 and all(ln in fails
                                                   for ln in synth_fails),
                     repr(synth_fails))
                c.eq("(%s) a FAIL's indented note follows it into the view"
                     % tag, sum(1 for ln in view_body(text) if ln.strip()
                                .startswith("observed: synthetic")), 2)
            elif which == "skip":
                text = check_filter(c, board, "skip", "suFilterSkip", live)
                if text is not None:
                    check_kind_view(c, board, "skip", text, live)
            elif which == "member":
                text = check_filter(c, board, "m:" + key, "suShow" + key,
                                    live)
                if text is not None:
                    check_member_view(c, board, key, text, live)
            else:
                check_filter(c, board, "all", "suFilterAll", live)
    got = check_finished(c, board, key, merged=merged)
    c.eq("the row reads N FAILED on the kit's bad ground",
         (board.text("suPill" + key),
          board.ctl("suPill" + key + "Bg").props.get("backgroundcolor")),
         ("%d FAILED" % got[1], board.pill.get("bad")))
    c.ck("the status line says to press Failures",
         "Press Failures" in board.status()[0], repr(board.status()))
    down, _up, err = press(ip, world, "suShowcoinxt")
    c.ck("Show on a row this run did not cover says so, and how to run it",
         err is None and board.text("suView").startswith(
             "CoinXT was not in this run's scope (SodiumXT only).\nPress Run "
             "on its row, or Run all."), err or repr(board.text("suView")))
    press(ip, world, "suFilterAll")
    return True


# ---- the Run-all accounting -----------------------------------------------

def scenario_all_accounting(c, board):
    """The "all" branch of the tallies, which only Run all reaches and this
    tier cannot afford: the tally handlers driven directly, in stRun's own
    order of calls (counters, scope, tallies), each block through the real
    merge handlers, then Show pressed on each row and the summary's board
    check run twice - once balanced, once with a block counted outside every
    tally, where it must FAIL."""
    ip, world = board.ip, board.world
    c.section("Run-all accounting (the tally handlers driven directly)")
    keys = ["sodiumxt", "coinxt", "holde-em", "sodiumxt"]
    try:
        ip.call("stResetCounters", [])
        ip.call("suScopeSet", [""])
        ip.call("suTallyReset", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("the Run-all prologue runs", exc)
    c.eq("an empty scope is all members", board.g("sSuScope"), "all")
    # what each row must hold, computed from what each block WROTE (the
    # core's own column-0 lines, the verbatim report's excluded) plus what its
    # merge folded in - never from the tallies under test
    want_rows = dict((k, [0, 0, 0]) for k in board.keys)
    lines_at = []
    for k, (shape, member, text, counters, folds) in enumerate(SYNTHETIC):
        key = keys[k]
        start = len(_lines(board.report()))
        try:
            ip.call("suTallyOpen", [key])
            if shape == "returned":
                ip.call("stMergeReturned", [member, text, 1])
            else:
                p, f, t, s = counters
                ip.call("stMergeCounted", [member, text, p, f, t, s])
            ip.call("suTallyClose", [])
        except Exception as exc:                        # noqa: BLE001
            return c.threw("merging %s into %s" % (member, key), exc)
        end = len(_lines(board.report()))
        lines_at.append((key, start, end))
        wrote = _lines(board.report())[start:end]
        for j, p in enumerate(("PASS  ", "FAIL  ", "SKIP  ")):
            want_rows[key][j] += (folds[j]
                                  + sum(1 for ln in wrote if ln.startswith(p))
                                  - sum(1 for ln in _lines(text)
                                        if ln.startswith(p)))
    # one plain block per remaining pill text: a pass (OK), and a lone SKIP
    # on a row whose member the probe found present (skipped), absent
    # (absent) and torrentxt's own (unavailable); every other row counts
    # nothing (waiting, and nothing ran once final)
    try:
        for key, verb, args, j in (
                ("cross", "stAssert", ["a cross-member check", True], 0),
                ("nostrxt", "stSkip", ["a check its layer skipped", "why"], 2),
                ("enetxt", "stSkip", ["a check with no extension", "why"], 2),
                ("torrentxt", "stSkip", ["a check with no session", "why"],
                 2)):
            ip.call("suTallyOpen", [key])
            ip.call(verb, args)
            ip.call("suTallyClose", [])
            want_rows[key][j] += 1
    except Exception as exc:                            # noqa: BLE001
        return c.threw("the plain blocks", exc)
    c.eq("in all members every block counted to its OWN row",
         dict((k, board.row(k)) for k in board.keys
              if k != board.no_harness),
         dict((k, tuple(v)) for k, v in want_rows.items()
              if k != board.no_harness))
    lines = _lines(board.report())
    # each row owns exactly the lines written while its tally was open
    for key in ("sodiumxt", "coinxt", "holde-em"):
        mine = [(a, b) for k2, a, b in lines_at if k2 == key]
        runs = [lines[a:b] for a, b in mine]
        want = ("%s: %d passed, %d failed, %d skipped, in the lines below.\n"
                % ((board.title_of(key),) + board.row(key))
                + "".join("\n".join(run) + "\n" for run in runs)
                + board.trailer())
        down, _up, err = press(ip, world, "suShow" + key)
        got = board.text("suView")
        c.ck("Show %s prints exactly the blocks that counted to it, apart "
             "when they were apart" % key, err is None and got == want,
             err or "got %d lines, want %d" % (len(_lines(got)),
                                              len(_lines(want))))
    rows = [board.row(k) for k in board.keys if k != board.no_harness]
    c.eq("and the rows add up to the totals",
         tuple(sum(r[j] for r in rows) for j in range(3)), board.totals())
    try:
        ip.call("suPaintRows", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suPaintRows runs", exc)
    for key in ("sodiumxt", "coinxt", "holde-em"):
        c.eq("row %s's pill reads its failures" % key,
             board.text("suPill" + key), "%d FAILED" % board.row(key)[1])
    for key, want, why in (
            ("cross", "OK", "passes and nothing failed"),
            ("nostrxt", "skipped", "only skips, its layer present"),
            ("enetxt", "absent", "only skips, the extension absent"),
            ("torrentxt", "unavailable", "only skips, and the probe cannot "
                                         "tell absent from held"),
            ("box2dxt", "waiting", "nothing counted, the run unfinished")):
        c.eq("row %s's pill reads %s (%s)" % (key, want, why),
             board.text("suPill" + key), want)
    c.eq("a row that counted nothing reads nothing ran once final (bad)",
         str(ip.call("suRowState", ["box2dxt", True])), "bad\nnothing ran")
    check_rows(c, board, "all", board.totals())
    # THE BOARD CHECK, both ways: balanced it writes its note; with one
    # check counted outside every tally it must FAIL - the proof that the
    # check the seven Runs pass is able to fire at all
    try:
        n0 = len(_lines(board.report()))
        ip.call("suSummaryNotes", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suSummaryNotes runs", exc)
    new = _lines(board.report())[n0:]
    c.ck("balanced, the board check writes its note and no FAIL",
         any(ln.strip().startswith("the rows account for every counted "
                                   "check (") for ln in new)
         and not any(ln.startswith(BOARD_FAIL) for ln in new), repr(new))
    cross = board.row("cross")
    try:
        ip.call("stAssert", ["a check no tally saw", True])
        n0 = len(_lines(board.report()))
        f0 = board.totals()[1]
        ip.call("suSummaryNotes", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suSummaryNotes runs over an untallied check", exc)
    new = _lines(board.report())[n0:]
    c.ck("unbalanced, the board check FAILS and says what went wrong",
         any(ln.startswith(BOARD_FAIL) for ln in new)
         and board.totals()[1] == f0 + 1
         and any("a block ran outside suTallyOpen" in ln for ln in new),
         repr(new))
    c.eq("and that FAIL counts to the cross row", board.row("cross"),
         (cross[0], cross[1] + 1, cross[2]))
    press(ip, world, "suFilterAll")
    return True


# ---- the rebuild ----------------------------------------------------------

def scenario_rebuild(c, board):
    """A window an OLDER paste built: the scaffold's controls (retired names
    the board re-creates, and stTitle, which it does not), a stale board
    control, an older stamp - and a foreign st_* control box2dxt's folded
    harness owns on this same card, which must survive the sweep."""
    ip, world = board.ip, board.world
    c.section("rebuild over an older paste's window")
    card = world.current()
    for ctype, name, rect in (("field", "stTitle", [0, 0, 760, 30]),
                              ("field", "suOldBoardField", [8, 8, 40, 20]),
                              ("graphic", "st_ball", [10, 400, 30, 420])):
        ct = DB.Control(ctype, name)
        ct.rect = rect
        card.controls.append(ct)
    world.stack_props["usuuiversion"] = "suite-board-0"
    try:
        ip.call("suBuild", [])
    except Exception as exc:                            # noqa: BLE001
        return c.threw("suBuild over the older window runs", exc)
    c.eq("the scaffold's retired stTitle and the stale board control are "
         "gone", [n for n in ("stTitle", "suOldBoardField")
                  if world.anywhere(n) is not None], [])
    c.ck("the foreign st_ball survives the sweep",
         world.anywhere("st_ball") is not None)
    check_build(c, board)
    card.controls[:] = [ct for ct in card.controls if ct.name != "st_ball"]
    c.section("Run cross on the rebuilt window")
    if arm_and_start(c, board, "cross") and finish(c, board):
        check_finished(c, board, "cross")
    return True


# ==========================================================================
# the transports' process-wide holds (work plan suite-wide #16)
# ==========================================================================
#
# The ONE scenario that is not all-absent. ENet and DataChannelXT are
# installed as modelled natives in a fresh interpreter of their own, after
# every other scenario has run, and removed again before the gate reports:
# the model is a model of each library's PROCESS-WIDE lifecycle and nothing
# else (no events arrive, so each loopback waits for its deadline), which is
# all the question needs. ANOTHER stack is open beside the paste: it holds
# ENet once and has one live host, and it has one live DataChannel peer.

ENX_ERR_NATIVE = -5         # enetxt/src/enx_abi.h: enet_initialize failed


class EnetModel:
    """enetxt's initialisation as its shim keeps it (enetxt/src/enet_shim.cpp,
    enx_initialize / enx_deinitialize over g_init_count): an initialize adds
    one hold (a FIRST one can fail, and then adds nothing); a deinitialize
    takes one away, never below zero, and the one that reaches zero destroys
    EVERY live host in the process, whichever stack made it. `other` holds
    belong to the other stack, with one host of its own; every call this
    interpreter makes is the paste's."""

    def __init__(self, other=1, init_fails=False):
        self.count = other
        self.init_fails = init_fails
        self.next = 0x10001
        self.hosts = {}             # handle -> "other" | "paste"
        if other:
            self.hosts[self._mint()] = "other"
        self.took = 0               # the paste's initializes that returned 0
        self.gave = 0               # the paste's deinitializes
        self.worst = 0              # the most the paste ever gave beyond what it took
        self.attempts = 0           # host creations the paste asked for
        self.other_host_lost = False

    def _mint(self):
        h = self.next
        self.next += 1
        return h

    def initialize(self, a):
        if self.count <= 0 and self.init_fails:
            return ENX_ERR_NATIVE
        self.count += 1
        self.took += 1
        return 0

    def deinitialize(self, a):
        self.gave += 1
        self.worst = max(self.worst, self.gave - self.took)
        if self.count <= 0:
            return 0
        self.count -= 1
        if self.count == 0:
            if "other" in self.hosts.values():
                self.other_host_lost = True
            self.hosts.clear()
        return 0

    def create(self, a):
        self.attempts += 1
        if self.count <= 0:
            return 0                # "call enInitialize first"
        h = self._mint()
        self.hosts[h] = "paste"
        return h

    def connect(self, a):
        return self._mint() if int(LCS._n(a[0])) in self.hosts else 0

    def destroy(self, a):
        self.hosts.pop(int(LCS._n(a[0])), None)
        return 0

    def paste_hosts(self):
        return sorted(h for h, who in self.hosts.items() if who == "paste")


class DcModel:
    """datachannelxt's lifecycle as its shim keeps it (datachannelxt/src/
    datachannel_shim.cpp, dcx_init / dcx_cleanup): dcInit is an idempotent
    one-time init with NO count, and dcCleanup frees EVERY peer and channel
    in the process however many dcInit calls came first. The other stack has
    one live peer. What the paste can promise is to call dcCleanup only while
    it holds an init of its own since its last dcCleanup; a call without one
    is recorded."""

    def __init__(self):
        self.next = 0x20001
        self.peers = {self._mint(): "other"}
        self.channels = set()
        self.holding = False        # a paste dcInit since its last dcCleanup
        self.cleanups = 0
        self.unpaired = 0           # dcCleanup calls made without a hold
        self.other_peer_lost = False

    def _mint(self):
        h = self.next
        self.next += 1
        return h

    def init(self, a):
        self.holding = True
        return 0

    def cleanup(self, a):
        self.cleanups += 1
        if not self.holding:
            self.unpaired += 1
        self.holding = False
        if "other" in self.peers.values():
            self.other_peer_lost = True
        self.peers.clear()
        self.channels.clear()
        return 0

    def state(self, a):
        return 0 if int(LCS._n(a[0])) in self.peers else -1

    def create_peer(self, a):
        h = self._mint()
        self.peers[h] = "paste"
        return h

    def create_channel(self, a):
        if int(LCS._n(a[0])) not in self.peers:
            return 0
        h = self._mint()
        self.channels.add(h)
        return h

    def free_peer(self, a):
        self.peers.pop(int(LCS._n(a[0])), None)
        return 0

    def free_channel(self, a):
        self.channels.discard(int(LCS._n(a[0])))
        return 0

    def paste_peers(self):
        return sorted(h for h, who in self.peers.items() if who == "paste")


# The statement-position COMMANDS the paste calls on the two libraries. The
# two releases are here because the pre-fix core called them bare, and the
# fixture's planted old code must reach the model the way the engine would.
TRANSPORT_COMMANDS = ("enhostdestroy", "endeinitialize", "dccleanup",
                      "dcfreepeer", "dcfreechannel", "dcclosechannel")


def install_transports(world, models):
    """Install (or re-point) the modelled natives at models["en"] and
    models["dc"], which a step may replace; returns the names installed so the
    caller can remove every one."""
    en = lambda name: (lambda a: getattr(models["en"], name)(a))   # noqa: E731
    dc = lambda name: (lambda a: getattr(models["dc"], name)(a))   # noqa: E731
    funcs = {
        "enlibraryversion": lambda a: "enet 1.3.18",
        "eninitialize": en("initialize"),
        "endeinitialize": en("deinitialize"),
        "enhostcreateserver": en("create"),
        "enhostcreateclient": en("create"),
        "enconnect": en("connect"),
        "enhostdestroy": en("destroy"),
        # no event ever arrives: the loopback waits for its deadline
        "enpoll": lambda a: {},
        "ensend": lambda a: -4 if len(str(LCS._disp(a[2]))) > 60000 else 0,
        "endisconnect": lambda a: 0,
        "dclibraryversion": lambda a: "libdatachannel v0.24.5",
        "dcinit": dc("init"),
        "dccleanup": dc("cleanup"),
        "dcpeerstate": dc("state"),
        "dccreatepeer": dc("create_peer"),
        "dccreatechannel": dc("create_channel"),
        "dcpoll": lambda a: {},
        "dcfreepeer": dc("free_peer"),
        "dcfreechannel": dc("free_channel"),
        "dcclosechannel": lambda a: 0,
    }
    LCS.HASHES.update(funcs)
    world.native_commands = set(TRANSPORT_COMMANDS)
    return list(funcs)


def check_other_intact(c, models, when, paste_hosts=0, dc_lost_ok=False):
    """The other stack's side after `when`, and the paste's pairing: the
    count it holds is untouched, its host alive, no deinitialize given back
    beyond what the paste took, and no dcCleanup without a hold."""
    en, dc = models["en"], models["dc"]
    c.eq("%s: the other stack's ENet hold is intact and the paste holds "
         "nothing (the count is back to 1)" % when, en.count, 1)
    c.eq("%s: the paste never gave back an ENet hold it did not take" % when,
         en.worst, 0)
    c.ck("%s: the other stack's ENet host is alive" % when,
         not en.other_host_lost)
    c.eq("%s: the paste's own hosts are destroyed" % when,
         len(en.paste_hosts()), paste_hosts)
    c.eq("%s: no dcCleanup without a DataChannel hold of the paste's own"
         % when, dc.unpaired, 0)
    if not dc_lost_ok:
        c.ck("%s: the other stack's DataChannel peer is alive" % when,
             not dc.other_peer_lost)


def drive_past_deadline(c, board, label):
    """One live pump tick (nothing arrives), then the clock past the run's
    deadline and every queued message delivered: the loopbacks FAIL on the
    deadline, as on an engine with blocked loopback UDP (trap 5.5), and the
    run reaches stFinish and stTeardown."""
    ip, world = board.ip, board.world
    try:
        deliver_next(ip, world, only=("suPump",))
        world.ms = max(world.ms, int(LCS._n(board.g("sDeadline"))) + 1)
        deliver_all(ip, world)
        return True
    except Exception as exc:                            # noqa: BLE001
        return c.threw(label, exc)


def start_row(c, board, key):
    """A row's Run through its button and its armed tick; True when the run
    is live with its pump queued."""
    ip, world = board.ip, board.world
    _down, _up, err = press(ip, world, "suRun" + key)
    if not c.ck("the %s Run press arms its tick" % key,
                err is None and ip.pending_names() == ["suRunTick"],
                err or repr(ip.pending_names())):
        return False
    try:
        deliver_next(ip, world, only=("suRunTick",))
    except Exception as exc:                            # noqa: BLE001
        return c.threw("the %s run's tick runs" % key, exc)
    return c.eq("the %s run is live, its pump queued" % key,
                (board.g("sAsyncRunning"), ip.pending_names()),
                ("true", ["suPump"]))


def held(board):
    return (int(LCS._n(board.g("sSuEnHeld"))), int(LCS._n(board.g("sSuDcHeld"))))


def scenario_transport_holds(c, src, sandbox):
    """Work plan suite-wide #16: open, a row's Run on each transport, a
    re-entry mid-run, a close mid-run and a close at rest, with another
    stack's ENet hold, host and DataChannel peer beside the paste. At every
    step the other stack's hold is intact, and the paste gives back exactly
    the holds it took (a refused initialize taken as none)."""
    c.section("the transports' process-wide holds (another stack holds "
              "ENet and a DataChannel peer)")
    world = SuiteWorld(tempfile.mkdtemp(dir=sandbox, prefix="holds-"))
    ip = SuiteInterp(src, world)
    install_engine_builtins(world)
    models = {"en": EnetModel(), "dc": DcModel()}
    names = install_transports(world, models)
    try:
        # THE MODEL CAN FIRE. Two unpaired deinitializes against a hold of
        # one take the other stack's host, and a dcCleanup without a hold is
        # recorded: every "intact" check below is a check that could fail.
        probe = EnetModel()
        probe.deinitialize([])
        probe.deinitialize([])
        c.ck("[MODEL] an unpaired deinitialize ends the other stack's host",
             probe.other_host_lost and probe.worst == 2 and probe.count == 0)
        dprobe = DcModel()
        dprobe.cleanup([])
        c.ck("[MODEL] a dcCleanup without a hold is recorded and frees the "
             "other stack's peer", dprobe.unpaired == 1
             and dprobe.other_peer_lost)

        ip.call("suBuild", [])
        board = Board(ip, world)
        # OPEN: openStack's order up to its run (suBuild, then stCleanup
        # before anything was initialised); scenario_boot asserts the order
        ip.call("stCleanup", [])
        check_other_intact(c, models, "open (stCleanup before any run)")

        # enetxt's row: the fold's two holds and the loopback's one
        if not start_row(c, board, "enetxt"):
            return False
        en = models["en"]
        c.eq("the enetxt run took three holds (the folded harness's two and "
             "the loopback's one) and counts them",
             (en.count, en.took, held(board)[0]), (4, 3, 3))
        c.eq("the loopback made its two hosts under the paste's own hold",
             len(en.paste_hosts()), 2)
        if not drive_past_deadline(c, board, "the enetxt run finishes"):
            return False
        check_other_intact(c, models, "after an enetxt run")
        c.eq("the run gave back exactly its three", (en.gave, held(board)[0]),
             (3, 0))
        lines = _lines(board.report())
        c.ck("the teardown asserted the release, and passed",
             "PASS  enDeinitialize returns 0" in lines,
             [ln for ln in lines if "enDeinitialize" in ln])

        # RE-ENTRY mid-run (runbook 5.2): openStack's first two steps on a
        # live run, then the new run it starts (an enetxt run stands in for
        # Run all, as in scenario_boot)
        if not start_row(c, board, "enetxt"):
            return False
        c.eq("a second enetxt run holds three again", en.count, 4)
        ip.call("suBuild", [])
        ip.call("stCleanup", [])
        c.eq("re-entry's stCleanup cancelled the live run's pump",
             ip.pending_names(), [])
        check_other_intact(c, models, "re-entry mid-run (suBuild, stCleanup)")
        ip.call("stRun", ["enetxt"])
        c.eq("the re-entered run holds three of its own", en.count, 4)
        if not drive_past_deadline(c, board, "the re-entered run finishes"):
            return False
        check_other_intact(c, models, "after the re-entered run")

        # the cross row: the loopback's hold only (its fold is enetxt's)
        # and a DataChannel hold; CLOSED mid-run
        if not start_row(c, board, "cross"):
            return False
        c.eq("the cross run holds ENet once and DataChannelXT once",
             held(board), (1, 1))
        dc = models["dc"]
        try:
            ip.call("closeStack", [])
        except Exception as exc:                        # noqa: BLE001
            return c.threw("closeStack mid-run runs", exc)
        check_other_intact(c, models, "closeStack mid-run", dc_lost_ok=True)
        c.eq("closing mid-run gave back both holds, dcCleanup once",
             (held(board), dc.cleanups), ((0, 0), 1))
        c.eq("and freed the paste's own peers", dc.paste_peers(), [])
        # A DataChannel run STILL frees another stack's peers: dcCleanup is
        # process-wide and uncounted in its shim, the residual the core's
        # header names. Asserted so the model's DataChannel half is proven
        # able to see a lost peer, which the steps above and below rely on.
        c.ck("[RESIDUAL] a run that holds DataChannelXT still ends the other "
             "stack's peer (dcCleanup is uncounted: close DataChannel stacks "
             "first, the header says)", dc.other_peer_lost)

        # CLOSE at rest, then a sodiumxt row, with the other peer back
        models["dc"] = dc = DcModel()
        try:
            ip.call("closeStack", [])
        except Exception as exc:                        # noqa: BLE001
            return c.threw("closeStack at rest runs", exc)
        check_other_intact(c, models, "closeStack at rest")
        gave = en.gave
        if not start_row(c, board, "sodiumxt") or not finish(c, board):
            return False
        check_other_intact(c, models, "after a sodiumxt run")
        c.eq("a run that never touched a transport called neither release",
             (en.gave - gave, dc.cleanups), (0, 0))

        # datachannelxt's row: one dcCleanup, paired, for three dcInits
        if not start_row(c, board, "datachannelxt"):
            return False
        c.eq("the datachannelxt run holds three (the fold's two, the "
             "loopback's one)", held(board)[1], 3)
        if not drive_past_deadline(c, board, "the datachannelxt run finishes"):
            return False
        check_other_intact(c, models, "after a datachannelxt run",
                           dc_lost_ok=True)
        c.eq("dcCleanup once, with the paste's own hold", (dc.cleanups,
                                                           held(board)[1]),
             (1, 0))

        # A REFUSED initialize is no hold: nobody else holds ENet and the
        # library cannot start, so every enInitialize fails
        models["en"] = en = EnetModel(other=0, init_fails=True)
        if not start_row(c, board, "enetxt"):
            return False
        c.eq("three refused enInitialize calls are counted as no hold",
             (en.took, held(board)[0]), (0, 0))
        c.eq("and the loopback stopped at the refusal: no host was attempted",
             en.attempts, 0)
        c.eq("the loopback reads failed, not a held port",
             board.g("sPhaseEn"), "failed")
        if not finish(c, board, "the refused run finishes"):
            return False
        c.eq("the paste gave back nothing it did not take", (en.gave,
                                                             en.worst), (0, 0))
        check_no_timers(c, board)
        return True
    finally:
        for name in names:
            LCS.HASHES.pop(name, None)
        world.native_commands = set()


# ==========================================================================
# THE --full PROFILE: Run all over the whole paste, as openStack starts it
# ==========================================================================
#
# Everything above drives the BOARD, through the fast scopes only (the
# three SLOW_SCOPES and Run all are left out). This profile is the other half: the paste ritual (runbook 3.1 step 4, close the
# window and reopen it; step 5, close it when done) delivered to the whole
# generated file, every member folded, every native absent, and Run all let
# run to its end through the pump - then the fold-level facts an engine
# session would otherwise be the first to show. The header's THE --full
# PROFILE section has the why and the numbers; this is the machinery.

# The model's clock for this profile: 2026-09-26 00:00:00 UTC. The base's
# fixed `the seconds` is 1700000000 (2023-11-14), EXACTLY the boundary of
# nostrxt's fixture era, and the folded nostrxt harness asserts that now is
# after it (`nxUnixNow() > 1700000000`): on the base's clock that one check
# fails in every interpreted run (the core's NostrXT floor comment records it
# as the interpreter's clock, not a defect). An engine's clock is the wall
# clock, which no session will ever read at 2023 again. Fixed rather than
# real so a run reproduces; pinned by FULL_CLOCK_PIN, the harness's own line,
# which must read ok (proof the clock reached a harness, not only a variable).
FULL_CLOCK = 1790380800
FULL_CLOCK_PIN = "  ok   nxUnixNow is after the fixture era"

# PYTHON'S limits, not the engine's. Every handler level costs the model
# about twenty-five Python frames (a statement, its expression parser's
# levels, the call), so the folded nostrxt harness, which nests past a
# hundred handler levels, overruns Python's default 1000 frames (the fast
# tier's re-measured SLOW_SCOPES reason). The run goes in a worker thread with
# a stack big enough for FULL_RECURSION frames; the deepest handler nesting
# the run reached is printed, and a RecursionError is still a refusal
# reported by name, never a pass.
FULL_RECURSION = 40000
FULL_THREAD_STACK = 512 * 1024 * 1024

# The engine's open and close messages, in the ritual's order. The model
# delivers each one the paste HANDLES, and asserts that is exactly
# RITUAL_HANDLED: a fold that brings back a preOpenStack or an openCard
# (holde-em's and box2dxt's are dropped on purpose) fails here until its
# delivery is modelled, rather than being silently never sent.
RITUAL_MESSAGES = ("closeStack", "closeCard", "suspendStack", "preOpenStack",
                   "preOpenCard", "openCard", "openStack", "resumeStack")
RITUAL_HANDLED = ("closeStack", "openStack")

# The core's RUNNER handlers: every section they call sits inside a try/catch
# of theirs (stRun's per-section trys, stRunMemberHarnesses' per-member trys,
# stFinish's two, suPump's two). A model REFUSAL is not a script error, so no
# script catch sees it: it would escape openStack and take the whole run. At
# a call a runner makes, FullInterp records it BY NAME (section, row, handler,
# line) and rethrows it as a script error, so the runner's catch reports that
# section and every other section still runs - and the gate fails on it.
CORE_RUNNERS = ("strun", "strunmemberharnesses", "stfinish", "supump")

# The timers Run all leaves after openStack returns, in delivery order, in
# this profile: the pump's first tick finds both loopbacks "skip" (no native)
# and finishes the run; then the boot self-check's one delayed probe. A timer
# a folded harness armed and never swept would be delivered too, and named.
FULL_TIMERS = ["suPump", "scTickProbe"]

# EACH ROW'S PILL AFTER RUN ALL, in this profile, with the reason: the six
# natives are absent (torrentxt alone reads unavailable, EXPECTED_PILLS says
# why; coinxt's script half is embedded but suPresent needs both halves); the
# four present script layers' folded harnesses run and pass; the cross row
# runs the probe, the teardown and stCrossOnionSection, and skips the rest.
FULL_PILLS = {
    "sodiumxt": ("wait", "absent"), "torrentxt": ("wait", "unavailable"),
    "enetxt": ("wait", "absent"), "datachannelxt": ("wait", "absent"),
    "box2dxt": ("wait", "absent"), "coinxt": ("wait", "absent"),
    "onionxt": ("ok", "OK"), "nostrxt": ("ok", "OK"), "riptide": ("ok", "OK"),
    "holde-em": ("ok", "OK"), "cross": ("ok", "OK"),
}
# The folded harnesses that RUN in this profile (the rest SKIP by probe).
FULL_MERGED = ("onionxt", "nostrxt", "riptide", "holde-em")

# The ONE handler that may write the message box, and why: holde-em's
# he1heProbeSodium echoes its report with a bare `put` by design (the folded
# he1heSelfTest's header records it as the quiet entry point's one honest
# exception, harmless in a host paste). Any other writer is a fold that
# reaches msg, which an engine session shows as a message box popping open.
MSG_WRITERS = ("he1heprobesodium",)

# The model deltas THIS profile adds, each counted and each required to fire.
FULL_DELTAS = collections.OrderedDict([
    ("do", "do EXPR runs the text as statements in the calling handler"),
    ("command-result", "a statement-position handler call sets the result"),
    ("msg-put", "a bare put writes the message box"),
])

# `the result` after a handler call, and the call-position branch below:
# the words a statement can start with that are ENGINE statements, never a
# handler call, whatever the paste defines.
_STATEMENT_WORDS = frozenset((
    "put", "get", "set", "send", "cancel", "pass", "answer", "delete", "do",
    "if", "else", "end", "repeat", "switch", "case", "default", "break",
    "try", "catch", "return", "exit", "next", "local", "global", "constant",
    "throw", "add", "subtract", "multiply", "divide", "sort", "split",
    "replace", "create", "go", "hide", "show", "lock", "unlock", "wait"))


def _is_bare_put(line):
    """`put EXPR` with no into / after / before outside its strings."""
    return LCS.split_outside_strings(line[4:], ("into", "after",
                                                "before")) is None


class FullWorld(SuiteWorld):
    def __init__(self, sandbox):
        super().__init__(sandbox)
        self.msg = ""               # the message box
        self.msg_writers = []       # which handler wrote it, per write


class FullInterp(SuiteInterp):
    """SuiteInterp plus the three constructs Run all reaches that the fast
    tier never does (FULL_DELTAS), and the bookkeeping that names a fault:
    the handler stack, the statement each frame is on, where every script
    error was raised, the refusals, the calls, and each row's time."""

    def __init__(self, src, world):
        super().__init__(src, world)
        self.stack = []             # handler names, outermost first
        self.where = []             # the statement each frame is on
        self.max_depth = 0
        self.calls = collections.Counter()
        # (message, handler, line, row) for each script error, where it was
        # RAISED; the probes raise hundreds, so the newest are kept
        self.thrown = collections.deque(maxlen=50000)
        self.faults = []            # refusals, each a dict naming it
        self.row_time = collections.Counter()
        self._tally = None
        self.controls_at_run = None  # the card's controls as stRun began
        self.merged_reports = []    # each report handed to stMergeReturned

    def _row(self):
        return str(self.globals.get("ssumarkkey", "")) or "(no row)"

    def call(self, name, args):
        low = name.lower()
        self.stack.append(name)
        self.where.append("")
        self.calls[low] += 1
        if len(self.stack) > self.max_depth:
            self.max_depth = len(self.stack)
        if low == "strun" and self.controls_at_run is None:
            self.controls_at_run = [ct.name for ct in
                                    self.world.current().controls]
        if low == "sutallyopen":
            self._tally = (str(LCS._disp(args[0])) if args else "",
                           time.time())
        elif low == "sutallyclose" and self._tally is not None:
            self.row_time[self._tally[0]] += time.time() - self._tally[1]
            self._tally = None
        elif low == "stmergereturned" and len(args) > 1:
            self.merged_reports.append(str(LCS._disp(args[1])))
        caller = self.stack[-2].lower() if len(self.stack) > 1 else ""
        try:
            return super().call(name, args)
        except (LCS._Return, LCS._Exit, LCS._Next, Thrown, DB._Break):
            raise
        except Exception as exc:                        # noqa: BLE001
            if caller not in CORE_RUNNERS:
                raise
            # A REFUSAL at a runner's call: named, then handed to the
            # runner's own catch as a script error (see CORE_RUNNERS).
            fault = getattr(exc, "full_origin", None) or {
                "handler": name, "line": "", "row": self._row()}
            fault = dict(fault, section=name, caller=self.stack[-2],
                         error="%s: %s" % (type(exc).__name__, exc))
            self.faults.append(fault)
            t = Thrown("the interpreter refused (%s): %s"
                       % (type(exc).__name__, exc))
            # the report's section line is attributed to the REFUSED
            # statement, not to the runner line that now raises
            t.full_origin = fault
            self.thrown.append((str(t.msg), fault.get("handler", name),
                                fault.get("line", ""), fault.get("row", "")))
            raise t
        finally:
            self.stack.pop()
            self.where.pop()

    def _origin(self, line):
        return {"handler": self.stack[-1] if self.stack else "(top level)",
                "line": line, "row": self._row(),
                "stack": " > ".join(self.stack[-6:])}

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        if self.where:
            self.where[-1] = line
        try:
            return self._full_stmt(body, i, env, line)
        except (LCS._Return, LCS._Exit, LCS._Next, DB._Break):
            raise
        except Thrown as t:
            # where it was RAISED: the innermost statement sees it first
            if not hasattr(t, "full_origin"):
                t.full_origin = self._origin(line)
                self.thrown.append((str(t.msg), t.full_origin["handler"],
                                    line, t.full_origin["row"]))
            raise
        except Exception as exc:                        # noqa: BLE001
            if not hasattr(exc, "full_origin"):
                try:
                    exc.full_origin = self._origin(line)
                except (AttributeError, TypeError):
                    pass
            raise

    def _full_stmt(self, body, i, env, line):
        head = line.split(None, 1)
        w0 = head[0].lower() if head else ""
        world = self.world
        if w0 == "do":
            # THE ENGINE'S `do` (LiveCode dictionary, `do`, DOCUMENTED): the
            # text is compiled and run as statements IN THE CALLING HANDLER,
            # its locals and `it` visible. holde-em's he1heRunSection runs
            # each section as `do pName` (engine-run on 2026-09-24 and
            # 2026-09-25: its folded harness's sections all reported).
            text = str(LCS._disp(self.eval_expr(line[2:].strip(), env)))
            fire("do")
            self._exec(text.split("\n"), env)
            return i + 1
        if w0 == "put" and _is_bare_put(line):
            # `put EXPR` with no container writes the MESSAGE BOX (LiveCode
            # dictionary, `put`, DOCUMENTED). Recorded, and who wrote it.
            world.msg = str(LCS._disp(self.eval_expr(line[3:].strip(), env)))
            world.msg_writers.append(self.stack[-1] if self.stack else "")
            fire("msg-put")
            return i + 1
        if (w0 in self.handlers and w0 not in _STATEMENT_WORDS
                and w0 not in world.native_commands):
            # A statement-position handler call. THE ENGINE SETS `the result`
            # to what a command handler RETURNS (LiveCode dictionary,
            # `return`, DOCUMENTED; OBSERVED through onionxt's harness, which
            # reads `the result` after every oxDial / oxClose / oxWrite
            # command and ran 74/0/1 on the 2026-09-24 engine, where this
            # model without the rule printed thirteen FAIL lines), and to
            # empty when it returns none (the dictionary's reading; the
            # model's, never separately observed). SuiteInterp's own branch
            # discards the value; this one keeps it.
            r = self.call(head[0], self._args(line[len(head[0]):].strip(),
                                              env))
            world.result = "" if r is None else r
            fire("command-result")
            return i + 1
        return super()._exec_stmt(body, i, env)


def _deep_blocks(ip):
    """Each member block of stRunMemberHarnesses, read from the paste: {key:
    (merge labels, skip labels)} - the `stMergeReturned "X"` / `stMergeCounted
    "X"` section it writes when its member ran, and the `stSkip "Y deep
    self-test"` line it writes when not. Read, never copied, so a relabel in
    the core moves the check with it."""
    blocks, key = collections.OrderedDict(), None
    for raw in ip.handlers["strunmemberharnesses"][1]:
        s = raw.strip()
        m = _rx(r'^if\s+suInScope\("([\w-]+)"\)\s+then$').match(s)
        if m:
            key = m.group(1)
            blocks.setdefault(key, (set(), set()))
            continue
        if key is None:
            continue
        m = _rx(r'stMerge(?:Returned|Counted)\s+"([^"]+)"').search(s)
        if m:
            blocks[key][0].add(m.group(1))
        m = _rx(r'^stSkip\s+"([^"]+ deep self-test)"').match(s)
        if m:
            blocks[key][1].add(m.group(1))
    return blocks


def attribute(ip, text):
    """The newest recorded script error whose message this report text
    carries: 'handler, at `line` (row)'. Empty when none matches."""
    for msg, handler, line, row in reversed(ip.thrown):
        if len(msg) > 3 and msg in text:
            return "raised in %s, at `%s` (row %s)" % (handler, line[:100],
                                                       row)
    return ""


def section_faults(ip, lines):
    """Every section the report says threw (the core's stSectionFailed:
    'FAIL  <section> section ran to completion', then 'it raised: <error>'),
    and every FAIL line a member's own guard wrote for a throw (holde-em's
    'FAIL  <section> THREW: <error>'), each attributed to where it was raised."""
    out = []
    for k, ln in enumerate(lines):
        s = ln.strip()
        m = _rx(r'^FAIL\s+(.+) section ran to completion$').match(s)
        if m:
            nxt = lines[k + 1].strip() if k + 1 < len(lines) else ""
            err = nxt[len("it raised:"):].strip() \
                if nxt.startswith("it raised:") else "(no error line)"
            out.append("section %r threw: %s; %s"
                       % (m.group(1), err, attribute(ip, err) or
                          "origin not recorded"))
            continue
        if s.startswith("FAIL") and ("THREW" in s or "threw" in s):
            out.append("%s; %s" % (s[:160], attribute(ip, s) or
                                   "origin not recorded"))
    return out


def summary_table(lines):
    """The summary's per-member table as printed: {title: (P, F, S, state)}
    for the rows it counted (a not-run or no-harness row has no numbers)."""
    out, inside = {}, False
    for ln in lines:
        if ln.strip().startswith("per member (passed / failed / skipped"):
            inside = True
            continue
        if not inside:
            continue
        m = _rx(r'^ {8}(\S.*?)\s+(\d+)\s+(\d+)\s+(\d+)  (.+)$').match(ln)
        if m:
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)),
                               int(m.group(4)), m.group(5))
            continue
        if not ln.startswith("        "):
            break
    return out


def print_full_table(board, ip, wall, sync_s):
    """The per-row table THE INTERPRETER'S RUN produced - labelled so it is
    never mistaken for an engine's record (root CLAUDE.md rule 6)."""
    print("check-suite-ui-boot --full: THE INTERPRETER'S RUN of Run all "
          "(the family interpreter over the generated paste, every native "
          "absent). NOT an engine's run: record an engine's totals from an "
          "engine.")
    print("  %-26s %7s %7s %8s  %-12s %8s" % ("row", "passed", "failed",
                                              "skipped", "pill", "seconds"))
    for key, title in zip(board.keys, board.names):
        if key == board.no_harness:
            print("  %-26s %7s %7s %8s  %-12s %8s" % (title, "-", "-", "-",
                                                      "no harness", "-"))
            continue
        p, f, s = board.row(key)
        print("  %-26s %7d %7d %8d  %-12s %8.1f"
              % (title, p, f, s, board.text("suPill" + key),
                 ip.row_time.get(key, 0.0)))
    p, f, s = board.totals()
    print("  %-26s %7d %7d %8d  (the summary line: %s)"
          % ("totals", p, f, s, board.text("stSummary")))
    print("  wall time %.1f s (openStack's synchronous Run all %.1f s); the "
          "deepest handler nesting %d; %d handler calls"
          % (wall, sync_s, ip.max_depth, sum(ip.calls.values())))


def run_full(c, path):
    """The --full profile, start to end. Returns nothing; every finding is a
    check on `c`."""
    t0 = time.time()
    sandbox = tempfile.mkdtemp(prefix="suite-ui-full-")
    clock = LCS.SECONDS[0]
    LCS.SECONDS[0] = FULL_CLOCK             # before the World seeds from it
    try:
        def fail(msg):
            c.ck("the paste reads the way the runner reads a stack", False,
                 msg)
            raise RuntimeError(msg)

        src = build_source(path, fail)
        world = FullWorld(sandbox)
        ip = FullInterp(src, world)
        install_engine_builtins(world)
        _run_full(c, ip, world, t0)
    finally:
        LCS.SECONDS[0] = clock
        shutil.rmtree(sandbox, ignore_errors=True)


def _run_full(c, ip, world, t0):
    c.section("--full: the all-absent profile and the ritual")
    natives = sorted(k for k in LCS.HASHES if k.startswith(NATIVE_PREFIXES))
    c.eq("no native extension handler is installed", natives, [])
    c.eq("no absent native is DEFINED in the paste",
         [n for n in ABSENT_NATIVES if n.lower() in ip.handlers], [])
    c.eq("the engine open/close messages the paste handles are exactly the "
         "ones this profile delivers (a new one needs its delivery modelled)",
         [n for n in RITUAL_MESSAGES if n.lower() in ip.handlers],
         list(RITUAL_HANDLED))
    c.eq("openStack is the four calls the ritual runs",
         tuple(ln.strip() for ln in ip.handlers["openstack"][1]
               if ln.strip()), OPEN_STACK)

    # THE RITUAL (runbook 3.1): step 4 closes the window the paste was
    # applied in - closeStack on a script whose every local is empty - and
    # reopens it: openStack, which builds the board and runs Run all
    # synchronously up to its first `send "suPump"`, then the boot
    # self-check, which arms its one probe. Then the engine's timers, earliest
    # first, until none is left: the pump's ticks to stFinish, the probe.
    c.section("--full: close, reopen (openStack runs Run all), the timers")
    try:
        ip.call("closeStack", [])
    except Exception as exc:                            # noqa: BLE001
        return report_escape(c, ip, "the first closeStack (a fresh script)",
                             exc)
    t_open = time.time()
    try:
        ip.call("openStack", [])
    except Exception as exc:                            # noqa: BLE001
        return report_escape(c, ip, "openStack (Run all's synchronous half)",
                             exc)
    sync_s = time.time() - t_open
    board = Board(ip, world)
    try:
        delivered = deliver_all(ip, world)
    except Exception as exc:                            # noqa: BLE001
        return report_escape(c, ip, "the timers after openStack", exc)
    c.eq("the timers delivered after openStack, in order (a harness's "
         "unswept timer would be here)", delivered, FULL_TIMERS)
    check_full_run(c, ip, world, board)

    # Copy results, the way every recorded engine report came back (4.1)
    c.section("--full: Copy results after the finish")
    n = len(world.answers)
    down, up, err = press(ip, world, "stCopy")
    c.ck("Copy results is handled by the scaffold's mouseUp",
         err is None and down is True and up is False,
         err or "down passed=%r up passed=%r" % (down, up))
    p, f, s = board.totals()
    c.eq("the clipboard is the counts, a blank line and the report",
         world.clipboard.get("text"),
         "%d passed, %d failed, %d skipped, %d total\n\n" %
         (p, f, s, board.num("sTotal")) + board.report())
    c.ck("and it carries no RUN NOT FINISHED trailer",
         "RUN NOT FINISHED" not in str(world.clipboard.get("text")))
    c.ck("the answer says copied", world.answers[n:][:1] and
         world.answers[n].startswith("Results copied to the clipboard."),
         repr(world.answers[n:]))

    # step 5: close the window when done
    c.section("--full: closeStack when done (runbook 3.1 step 5)")
    try:
        ip.call("closeStack", [])
    except Exception as exc:                            # noqa: BLE001
        return report_escape(c, ip, "the last closeStack", exc)
    c.eq("closing after the run leaves no timer, no session, no hold",
         (ip.pending_names(), str(board.g("sSession")),
          str(board.g("sSuEnHeld")) in ("", "0"),
          str(board.g("sSuDcHeld")) in ("", "0")), ([], "0", True, True))
    check_delimiters(c)
    c.section("--full: refusals and throws, by name")
    refused = ["%s (called by %s; row %s): %s, in %s at `%s`"
               % (f["section"], f["caller"], f["row"], f["error"],
                  f["handler"], f["line"][:100]) for f in ip.faults]
    c.ck("the interpreter refused nothing (each named: section, row, "
         "handler, line)", not refused, "\n".join(refused))
    print_full_table(board, ip, time.time() - t0, sync_s)


def report_escape(c, ip, when, exc):
    """A failure that escaped every script catch AND every runner boundary
    (a refusal in stRun's own lines, in the pump, in a timer): the run is
    dead, so this names where and stops."""
    origin = getattr(exc, "full_origin", None) or {}
    return c.ck("%s ran without escaping the model" % when, False,
                "%s: %s\n  in %s, at `%s` (row %s)\n  stack: %s"
                % (type(exc).__name__, exc, origin.get("handler", "?"),
                   str(origin.get("line", "?"))[:120], origin.get("row", "?"),
                   origin.get("stack", "?")))


def check_full_run(c, ip, world, board):
    """The fold-level facts, after the last timer."""
    lines = _lines(board.report())
    c.section("--full: the finished run (check_finished, scope all)")
    check_probe_answers(c, board)
    check_finished(c, board, "all", boot_whole=False,
                   reports=ip.merged_reports)

    c.section("--full: no section threw or was refused")
    faults = section_faults(ip, lines)
    # printed as lines, never as a repr: a name must read verbatim
    c.ck("no section threw, and no member's guard caught a throw (each "
         "named with where it was raised)", not faults, "\n".join(faults))

    c.section("--full: the rows and the totals")
    rows = dict((k, board.row(k)) for k in board.keys
                if k != board.no_harness)
    c.eq("the rows add up to the totals line",
         tuple(sum(r[j] for r in rows.values()) for j in range(3)),
         board.totals())
    table = summary_table(lines)
    want = dict((board.title_of(k), rows[k]) for k in rows)
    c.eq("the summary's printed table is the rows, row by row",
         dict((t, v[:3]) for t, v in table.items()), want)
    c.eq("each row's pill after Run all (FULL_PILLS)",
         dict((k, (board.text("suPill" + k),
                   board.ctl("suPill" + k + "Bg").props.get(
                       "backgroundcolor"))) for k in rows),
         dict((k, (FULL_PILLS[k][1], board.pill.get(FULL_PILLS[k][0])))
              for k in rows if k in FULL_PILLS))
    c.eq("FULL_PILLS names exactly the rows with a harness",
         sorted(FULL_PILLS), sorted(rows))
    c.eq("every row with a harness counted something (none reads "
         "nothing ran)", [k for k, r in rows.items() if sum(r) == 0], [])

    c.section("--full: every folded member reported once")
    blocks = _deep_blocks(ip)
    heads = set(ln for ln in lines if _rx(SECTION_HEAD).match(ln))
    ran, wrong = [], []
    for key, (merges, skips) in blocks.items():
        merged = [m for m in merges
                  if lines.count("== %s: its own full self-test ==" % m)]
        skipped = [s for s in skips if any(
            ln.startswith("SKIP  " + s + "  ") or ln == "SKIP  " + s
            for ln in lines)]
        if len(merged) + len(skipped) != 1:
            wrong.append("%s: merged %s, skipped %s" % (key, merged, skipped))
        if merged:
            ran.append(key)
    c.eq("each folded member's block wrote exactly one outcome (its merged "
         "report or its SKIP line)", wrong, [])
    c.eq("the folded harnesses that ran are the present layers' "
         "(FULL_MERGED)", sorted(ran), sorted(FULL_MERGED))
    c.eq("no merged report's section header appears twice",
         sorted(h for h in heads if lines.count(h) > 1
                and h.endswith(": its own full self-test ==")), [])
    c.ck("the model's clock reached a harness (FULL_CLOCK_PIN)",
         FULL_CLOCK_PIN in lines, FULL_CLOCK_PIN)

    c.section("--full: teardown ran")
    c.eq("stFinish ran once and stTeardown ran once, from it",
         (ip.calls["stfinish"], ip.calls["stteardown"]), (1, 1))
    teardown = "== teardown (nothing may outlive the run) =="
    c.eq("the report carries the teardown section once", lines.count(
        teardown), 1)
    if teardown in lines:
        at = lines.index(teardown)
        member_heads = [k for k, ln in enumerate(lines)
                        if ln.endswith(": its own full self-test ==")]
        c.ck("after every member's section and before the boot block and the "
             "summary", all(k < at for k in member_heads)
             and at < lines.index(SUMMARY_HEADER)
             and (BOOT_HEADER not in lines or at < lines.index(BOOT_HEADER)),
             "teardown at line %d" % (at + 1))
    c.eq("nothing is held after the teardown (session, ENet, DataChannel)",
         (str(board.g("sSession")), str(board.g("sSuEnHeld")) in ("", "0"),
          str(board.g("sSuDcHeld")) in ("", "0")), ("0", True, True))

    c.section("--full: the boot self-check")
    sc = _lines(board.g("sScLines"))
    c.eq("the self-check is green once its probe fired",
         (board.num("sScFailed"), board.num("sScSkipped")), (0, 0))
    c.ck("its last line is the green verdict",
         sc and sc[-1].strip().startswith("boot self-check GREEN"),
         repr(sc[-1:] if sc else None))
    c.eq("the Boot check log holds exactly the block",
         board.text("suBootLog"), str(board.g("sScLines")))
    c.ck("the summary says the probe had not fired when it was written (the "
         "pump's first tick finished the run at 33 ms; the probe is at 400)",
         "      boot self-check: its one delayed check had not fired yet; "
         "see the Boot check view" in lines)
    text, colour = board.status()
    c.ck("the status line reads Finished, in the verdict's colour",
         text.startswith("Finished (all members (Run all)):")
         and colour == board.colors["kUiBad" if board.totals()[1]
                                    else "kUiOk"], repr((text, colour)))

    c.section("--full: what the folds may not touch")
    c.eq("no control was created or deleted by the run (a folded harness "
         "decorating the board)", [ct.name for ct in world.current().controls],
         ip.controls_at_run)
    c.eq("the window is still %d x %d" % (board.width, board.height),
         (world.stack_props.get("width"), world.stack_props.get("height")),
         (board.width, board.height))
    c.eq("the clipboard is untouched until Copy results", world.clipboard, {})
    c.eq("only MSG_WRITERS wrote the message box",
         sorted(set(w.lower() for w in world.msg_writers) - set(MSG_WRITERS)),
         [])
    c.ck("and what it holds is holde-em's probe report",
         world.msg.startswith("SodiumXT probe (holde-em "), repr(world.msg[:80]))
    missing, layers = missing_handlers(ip)
    c.eq("every can't-find-handler the run raised names an ABSENT native or "
         "a NOT_IN_PASTE layer (an engine builtin the model lacks, or a "
         "fold's misspelt call, would be named here)", missing, [])
    c.eq("every NOT_IN_PASTE probe was raised by some run (a stale excuse "
         "is an exemption for a probe that is gone)",
         sorted(set(NOT_IN_PASTE) - layers), [])


# Script layers the paste DELIBERATELY does not carry, whose absence a folded
# harness probes by calling one of their handlers and SKIPs on the "can't
# find handler": {the probed name: why the layer is not in the paste}.
NOT_IN_PASTE = {
    "nxrVersion": "nostrxt's relay layer (nxr*) defines the engine's socket "
                  "handlers, which the embedded onionxt layer already "
                  "defines, so it is not in the paste (the core's NostrXT "
                  "comment); the folded harness's relay section SKIPs",
    "oxhTrim": "onion-httpd's oxh* helpers are embedded in demos only, "
               "never the paste (root CLAUDE.md, the carrier sets); the "
               "folded onionxt harness's oxh* section SKIPs",
}


def missing_handlers(ip):
    """(the handler names the run's "can't find handler" errors named that
    are neither an absent native's - a native prefix, and not defined in the
    paste - nor a NOT_IN_PASTE layer's, the NOT_IN_PASTE names seen)."""
    out, layers = set(), set()
    for msg, _h, _l, _r in ip.thrown:
        m = (_rx(r"can't find handler: (\w+)").search(msg)
             or _rx(r"can't find handler \(unknown function (\w+)\)")
             .search(msg))
        if not m:
            continue
        name = m.group(1)
        if name in NOT_IN_PASTE and name.lower() not in ip.handlers:
            layers.add(name)
        elif not (name.lower().startswith(NATIVE_PREFIXES)
                  and name.lower() not in ip.handlers):
            out.add(name)
    return sorted(out), layers


def main_full(path, verbose):
    """--full in a worker thread whose stack holds FULL_RECURSION frames."""
    c = Checker(verbose)
    t0 = time.time()
    box = {}

    def work():
        try:
            run_full(c, path)
        except Exception as exc:                        # noqa: BLE001
            box["exc"] = exc

    old = sys.getrecursionlimit()
    sys.setrecursionlimit(FULL_RECURSION)
    threading.stack_size(FULL_THREAD_STACK)
    try:
        worker = threading.Thread(target=work, name="suite-ui-full")
        worker.start()
        worker.join()
    finally:
        threading.stack_size(0)
        sys.setrecursionlimit(old)
    if "exc" in box:
        c.threw("the --full profile ran to its end", box["exc"])
    return finish_report(c, t0, full=True)


# ==========================================================================
# the drive
# ==========================================================================

def slow_outcome(src, sandbox, key):
    """Run one left-out scope in a FRESH interpreter (a scope that throws
    leaves its board mid-run, so none is reused) and say how it ended:
    ("threw", "Type: message"), ("fails", the FAIL lines) or ("clean", [])."""
    world = SuiteWorld(tempfile.mkdtemp(dir=sandbox, prefix="slow-"))
    ip = SuiteInterp(src, world)
    install_engine_builtins(world)
    ip.call("suBuild", [])
    board = Board(ip, world)
    try:
        press(ip, world, "suRun" + key)
        deliver_next(ip, world, only=("suRunTick",))
        deliver_all(ip, world)
    except Exception as exc:                            # noqa: BLE001
        return ("threw", "%s: %s" % (type(exc).__name__, exc))
    fails = [ln for ln in _lines(board.report())
             if ln.lstrip().startswith("FAIL")]
    return ("fails", fails) if fails else ("clean", [])


def scenario_slow_reasons(c, src, sandbox):
    """Each SLOW_SCOPES reason still holds, or the gate fails: a left-out
    scope that now runs clean belongs in FAST_SCOPES."""
    c.section("the left-out scopes' reasons, re-measured")
    for key in sorted(SLOW_SCOPES):
        reason, (kind, start) = SLOW_SCOPES[key]
        try:
            got_kind, detail = slow_outcome(src, sandbox, key)
        except Exception as exc:                        # noqa: BLE001
            c.threw("the %s scope's re-run set up" % key, exc)
            continue
        if got_kind == "clean":
            c.ck("%s still fails in the model for its stated reason" % key,
                 False, "it ran CLEAN: a stale excuse - move it to "
                 "FAST_SCOPES (it was left out because %s)" % reason)
        elif kind == "threw":
            c.ck("%s still throws %s" % (key, start), got_kind == "threw"
                 and str(detail).startswith(start),
                 "%s: %s" % (got_kind, str(detail)[:200]))
        else:
            c.ck("%s still finishes with FAIL lines" % key,
                 got_kind == "fails", "%s: %s" % (got_kind, detail[:2]))


def main(argv):
    verbose = "--verbose" in argv
    path = PASTE
    if "--paste" in argv:
        k = argv.index("--paste")
        if k + 1 >= len(argv):
            print("usage: check-suite-ui-boot.py [--full] [--verbose] "
                  "[--paste PATH]")
            return 2
        path = argv[k + 1]
    if "--full" in argv:
        return main_full(path, verbose)
    t0 = time.time()
    c = Checker(verbose)
    sandbox = tempfile.mkdtemp(prefix="suite-ui-boot-")
    try:
        def fail(msg):
            print("check-suite-ui-boot: %s" % msg)
            sys.exit(1)

        src = build_source(path, fail)
        world = SuiteWorld(sandbox)
        try:
            ip = SuiteInterp(src, world)
        except Exception as exc:                        # noqa: BLE001
            print("check-suite-ui-boot: the paste did not parse: %s: %s"
                  % (type(exc).__name__, exc))
            return 1
        install_engine_builtins(world)
        check_profile(c, ip)
        c.section("the first build (suBuild on a fresh stack)")
        try:
            ip.call("suBuild", [])
        except Exception as exc:                        # noqa: BLE001
            c.threw("suBuild runs", exc)
            return finish_report(c, t0)
        board = Board(ip, world)
        for scenario in (scenario_build, scenario_routing, scenario_boot,
                         scenario_runs, scenario_foreign_timers,
                         scenario_refusals, scenario_copy,
                         scenario_close, scenario_views,
                         scenario_all_accounting, scenario_rebuild):
            try:
                scenario(c, board)
            except Exception as exc:                    # noqa: BLE001
                c.threw("the scenario ran to its end", exc)
            check_no_timers(c, board)
            check_delimiters(c)
        scenario_slow_reasons(c, src, sandbox)
        # LAST, in an interpreter of its own: the one scenario with modelled
        # natives, removed again before anything else reads LCS.HASHES
        try:
            scenario_transport_holds(c, src, sandbox)
        except Exception as exc:                        # noqa: BLE001
            c.threw("the transport-holds scenario ran to its end", exc)
        check_delimiters(c)
        c.section("EXPECTED_MODEL_FAILS")
        c.eq("every EXPECTED_MODEL_FAILS entry was printed by some run (a "
             "stale entry is an excuse for a failure that is gone)",
             sorted(set(EXPECTED_MODEL_FAILS) - board.seen_fails), [])
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
    return finish_report(c, t0)


def finish_report(c, t0, full=False):
    elapsed = time.time() - t0
    deltas = FULL_DELTAS if full else DELTAS
    c.section("the model")
    c.eq("every model delta fired (a hook nobody exercises is a stale "
         "excuse)", [n for n in deltas if FIRED[n] == 0], [])
    print("check-suite-ui-boot: deltas fired: %s" % ", ".join(
        "%s x%d" % (n, FIRED[n]) for n in deltas))
    if c.failures:
        print("check-suite-ui-boot: %d of %d check(s) FAILED (%.1fs)"
              % (len(c.failures), c.n, elapsed))
        return 1
    if full:
        print("check-suite-ui-boot --full: OK (%d checks, %.1fs): the paste "
              "ritual (close, reopen, close) delivered to the WHOLE generated "
              "paste, every member folded and every native absent; Run all "
              "ran to its end through the pump; no section threw or was "
              "refused; the rows add up to the totals; the report ends "
              "without RUN NOT FINISHED; the boot self-check is green; the "
              "teardown ran; no fold touched a control, the clipboard or "
              "the window. The interpreter's run, not an engine's: logic "
              "only; it upgrades no label, and every present-extension path "
              "is still unrun here." % (c.n, elapsed))
        return 0
    print("check-suite-ui-boot: OK (%d checks, %.1fs): the board built and "
          "rebuilt over an older window; %s ran through their rows' Run; the "
          "filters, Show, Copy, the refusals, a close mid-run and the boot "
          "self-check held, all-absent profile; and beside another stack's "
          "modelled ENet hold and DataChannel peer, open, row Runs, a "
          "re-entry and closes gave back exactly the holds the paste took. "
          "NOT RUN in this fast tier: "
          "the %s scopes and Run all (their folded harnesses, not the "
          "board). NOT SEEN: rendering, parsing, message delivery, "
          "case-folding `is`, and every present-extension path bar the "
          "two transports' holds. Logic only; "
          "needs an OXT pass." % (c.n, elapsed, ", ".join(FAST_SCOPES),
                                  ", ".join(sorted(SLOW_SCOPES))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
