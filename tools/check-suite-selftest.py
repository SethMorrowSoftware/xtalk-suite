#!/usr/bin/env python3
"""check-suite-selftest.py - structural checks on the generated suite harness.

WHY THIS EXISTS. tests/suite-selftest.livecodescript is 4000+ lines assembled by
a script from six sources, and OXT cannot compile a .livecodescript headlessly.
So the ONE thing that would catch a bad merge - a compiler - is unavailable, and
every failure mode of a merge is silent:

  * two handlers with the same name is a compile error nobody sees until the
    engine session that was supposed to run the tests;
  * a CALL to a handler the merge dropped is, in LiveCodeScript, not an error at
    all in the common case - and where it is, it is one at RUN time, mid-suite;
  * WORST, a missing `constant` declaration does not fail either. An undeclared
    name evaluates to the literal string of its own name, so a folded harness
    that lost `constant kBip39Mnemonic` compares a real digest against the text
    "cx1kBip39Mnemonic" and reports a neat FAIL that reads exactly like a genuine
    defect in the library. That one would cost an engine session and a bug hunt.

None of those is hypothetical: the missing-declarations bug was real in the first
version of the generator and this check is what found it. The checks below are
the ones a compiler would have done, done statically.

THE GENERATOR IS THE PARSER (2026-09-24). This gate used to carry its own
strip_comments and declaration_names, "the same function as the generator's,
deliberately", kept in step by hand with a docstring admitting that nothing
enforced it. Two tools that must read one source identically were two copies
of a scanner, which is how this family's scanners have drifted before. It now
exec-loads tools/build-suite-selftest.py and calls the generator's own, so the
tool that WRITES the paste and the tool that CHECKS it cannot disagree about
what is code. The member tables (PREFIXES, ENTRY_POINTS, COUNTED) are derived
from the generator's MEMBERS rows for the same reason: a member added there is
checked here with no second edit, and one dropped there is refused by the
generator's assert_registry_covered and by check 17, not quietly unchecked.

THE CORE IS READ TOO (checks 10b and 13b-17). The paste is what runs; the core
(tests/suite-selftest.core.livecodescript) is what a person edits, and since
D-23 it is also a UI - a board with per-member Run, timers, and control names
on a card the folded harnesses share. The rules about the core's own
hand-written discipline are asked of the core, outside its three carried
blocks where the discipline belongs to a master and its drift gate.

Usage:  python3 tools/check-suite-selftest.py [PASTE] [--core CORE]
        (defaults: the committed tests/suite-selftest.livecodescript, and the
        generator's CORE; the fixture tools/test-suite-selftest.py points both
        at scratch copies. `--check` is accepted and ignored, as it always
        was: this tool only ever checks.)
"""

import argparse
import collections
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")


def _load_tool(filename):
    """Exec-load a neighbouring tool by path (there is no package here)."""
    spec = importlib.util.spec_from_file_location(
        filename.replace("-", "_").replace(".py", ""), os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


BUILD = _load_tool("build-suite-selftest.py")
REGISTRY = _load_tool("member-registry.py")
CONTROLS = _load_tool("check-demo-control-lists.py")

# The prefixes tools/build-suite-selftest.py assigns, and the member each names.
PREFIXES = {m.prefix: m.member for m in BUILD.MEMBERS}

# What the core calls into each folded harness. If the generator ever renames or
# drops one of these, the suite harness compiles and then does nothing.
ENTRY_POINTS = [m.prefix + m.entry for m in BUILD.MEMBERS]
# The harnesses that accumulate into their own script locals, which the core
# reads BY NAME (stMergeCounted); the others return their report.
COUNTED = [m.prefix for m in BUILD.MEMBERS if m.shape == "counted"]

# What the engine delivers to this stack without anyone in the script calling
# it: the entries of check 13b's call graph (every timer the core arms joins
# them).
EVENTS = ("openStack", "mouseDown", "mouseUp", "closeStack")

# The one statement check 15 requires first in every timer the core arms.
PIN = "set the defaultstack to the short name of this stack"


def strip_comments(text, what):
    """Comment-free view: the GENERATOR'S scan, so the two tools read a source
    identically (see the module docstring). Line count is PRESERVED, so the
    checks can report line numbers, and string literals are KEPT.

    Block comments are the reason the scan is stateful: /* ... */ is legal
    LiveCodeScript and holde-em keeps a 926-line header changelog in one, where
    prose wraps to lines like `on every wire during the netplay section)` -
    read as code, a handler named `every`. fold() and embed() emit handler
    BLOCKS only, so a header changelog never reaches the paste; what can is a
    /* */ written inside a handler body, whose column-0 prose would otherwise
    be a phantom handler to checks 1 and 4 and a phantom late `local` to
    check 10.

    The generator refuses an unterminated block with a message about "a
    source file"; this re-raises it naming the file this gate was reading.
    """
    try:
        return BUILD.strip_comments(text)
    except SystemExit:
        raise SystemExit(
            f"check-suite-selftest: an unterminated /* block comment runs to the "
            f"end of {what}. Blanking it would hide every handler below it from "
            f"these checks.")


# The names ONE `local`/`constant` line declares, string literals removed
# BEFORE the comma split - the generator's function, for the reason its
# docstring gives: `constant kKatL2Perm1 = "35,31,39,12"` would otherwise inject
# 31, 39 and 12 as declared names, so check 1b reports phantom duplicates and
# check 2's `declared` set silently ABSORBS real names that appear in a string.
declaration_names = BUILD.declaration_names


def blank_literals(line):
    """The line with every string literal's CONTENT replaced by spaces.

    LENGTH-PRESERVING, so a column found here indexes the literal-kept line
    too: the checks that ask "is this a statement" read this view, and the
    ones that then need the literal (a send's target) read the other at the
    same column. LiveCodeScript has no string escapes, so quotes always pair;
    a comment-free line cannot hold an unpaired one.
    """
    out, instr = [], False
    for ch in line:
        if ch == '"':
            instr = not instr
            out.append(ch)
        else:
            out.append(" " if instr else ch)
    return "".join(out)


def handler_spans(view_lines):
    """[(name, first, last)] 0-based inclusive line indexes of every column-0
    handler in a comment-free view, plus the name of one left unterminated
    (or None)."""
    opener = re.compile(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', re.I)
    out, i = [], 0
    while i < len(view_lines):
        m = opener.match(view_lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        end = re.compile(r'^\s*end\s+' + re.escape(name) + r'\s*$', re.I)
        j = i + 1
        while j < len(view_lines) and not end.match(view_lines[j]):
            j += 1
        if j >= len(view_lines):
            return out, name
        out.append((name, i, j))
        i = j + 1
    return out, None


def carried_lines(lines):
    """Indexes of every line inside one of the core's three carried blocks,
    marker lines included. The markers are the generator's CARRIED_SPANS,
    which it reads from the drift gates that own them."""
    inside = set()
    for begin, end in BUILD.CARRIED_SPANS:
        b = [i for i, ln in enumerate(lines) if ln.strip() == begin]
        e = [i for i, ln in enumerate(lines) if ln.strip() == end]
        if len(b) == 1 and len(e) == 1 and b[0] < e[0]:
            inside.update(range(b[0], e[0] + 1))
    return inside


def statements(blank_lines, rows):
    """(row, column, first word) of every statement that STARTS on one of
    `rows`: at the line's start unless the line continues the one above
    (a trailing backslash), and after every `then` / `else` - a one-line if
    carries a statement too. Read from the literal-BLANKED view, so a word in
    a label is never a statement."""
    for i in sorted(set(rows)):
        blank = blank_lines[i]
        continued = i > 0 and blank_lines[i - 1].rstrip().endswith("\\")
        starts = [] if continued else [0]
        starts += [m.end() for m in re.finditer(r'\b(?:then|else)\b', blank, re.I)]
        for s in starts:
            m = re.match(r'\s*([A-Za-z_]\w*)', blank[s:])
            if m:
                yield i, s + m.start(1), m.group(1)


def message_target(kept, blank, col, word):
    """For a `send`/`dispatch` statement at `col`: (target, literal?, delayed?).

    `target` is the first word of the message when it is a string literal
    (`send "stPump" to me in 33 milliseconds` -> stPump), also when the literal
    opens a parenthesised expression (the kit's copy flash), which is how the
    engine will see it; `literal?` is True only for a BARE literal, the form
    check 14 accepts; `delayed?` says the statement arms a timer (`in <time>`
    after the message)."""
    rest = col + len(word)
    m = re.match(r'\s*(\(\s*)?"', blank[rest:])
    if not m:
        return None, False, False
    q = rest + m.end() - 1
    close = kept.find('"', q + 1)
    if close < 0:
        return None, False, False
    words = kept[q + 1:close].split()
    target = words[0] if words else None
    if word.lower() == "dispatch":
        return target, m.group(1) is None, False
    delayed = re.search(r'\bin\b', blank[close + 1:], re.I) is not None
    return target, m.group(1) is None, delayed


def main(argv):
    ap = argparse.ArgumentParser(
        prog="check-suite-selftest.py",
        description="Structural checks on the generated suite self-test.")
    ap.add_argument("paste", nargs="?", default=GEN,
                    help="the generated paste (default: the committed one)")
    ap.add_argument("--core", default=BUILD.CORE,
                    help="the hand-written core (default: the generator's)")
    ap.add_argument("--check", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args(argv[1:])
    paste_rel = os.path.relpath(os.path.abspath(args.paste), ROOT)
    core_rel = os.path.relpath(os.path.abspath(args.core), ROOT)
    if not os.path.exists(args.paste):
        print(f"check-suite-selftest: {paste_rel} is missing")
        return 1
    if not os.path.exists(args.core):
        print(f"check-suite-selftest: {core_rel} is missing")
        return 1
    src = open(args.paste, encoding="utf-8").read()
    bare = strip_comments(src, paste_rel)
    problems = []

    def fail(check, msg):
        problems.append((check, msg))

    # ---- 1. no duplicate handler names (this one IS a compile error) --------
    defs = re.findall(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', bare, re.M)
    seen, dups = set(), set()
    for n in defs:
        (dups if n.lower() in seen else seen).add(n.lower())
    if dups:
        fail("1", "duplicate handler names (the script will not compile): "
                  + ", ".join(sorted(dups)))

    # ---- 1b. no duplicate script-level declarations -------------------------
    # Worse than a duplicate handler, because it is not obviously an error at
    # all: two units silently SHARE one variable and perturb each other's
    # state - exactly the isolation the fold's prefixing exists to guarantee,
    # and a hazard the embedded (unprefixed) script layers reintroduce. The
    # generator refuses to write such a file; this re-checks the committed one.
    decl_names = []
    for line in re.findall(r'^(?:local|constant)\s+([^\n]+)$', bare, re.M):
        decl_names.extend(declaration_names(line))
    seen, dup_decls = set(), set()
    for n in decl_names:
        (dup_decls if n.lower() in seen else seen).add(n.lower())
    if dup_decls:
        fail("1b", "duplicate script-level declarations (two units would "
                   "silently share one variable): "
                   + ", ".join(sorted(dup_decls)))

    # ---- 2. every script-level name a folded harness uses is declared -------
    # This is the silent one. Collect the script-level declarations, then look
    # for prefixed s*/k* names used anywhere that were never declared.
    declared = set()
    for line in re.findall(r'^\s*(?:local|constant)\s+([^\n]+)$', bare, re.M):
        declared.update(declaration_names(line))
    handler_names = {n for n in defs}
    used = set()
    for pfx in PREFIXES:
        used |= set(re.findall(r'\b(' + pfx + r'[sk][A-Z]\w*)\b', bare))
    undeclared = sorted(n for n in used if n not in declared and n not in handler_names)
    if undeclared:
        fail("2",
             "script-level names used but never declared - LiveCodeScript would "
             "evaluate each as the literal text of its own name, so these would "
             "produce plausible-looking FAILs rather than an error: "
             + ", ".join(undeclared[:12])
             + (f" (+{len(undeclared) - 12} more)" if len(undeclared) > 12 else ""))

    # ---- 3. the core's integration surface still exists ---------------------
    lower = {n.lower() for n in defs}
    for entry in ENTRY_POINTS:
        if entry.lower() not in lower:
            fail("3", f"the core calls {entry}, which is not defined")
    for pfx in COUNTED:
        for suffix in ("sResultText", "sPassed", "sFailed", "sTotal"):
            if pfx + suffix not in declared:
                fail("3", f"the core reads {pfx}{suffix}, which is not declared")

    # ---- 4. every folded harness is actually present and non-trivial -------
    for pfx, member in PREFIXES.items():
        n = len([d for d in defs if d.startswith(pfx)])
        if n < 5:
            fail("4", f"{member} folded in only {n} handlers under `{pfx}` - "
                      f"the fold silently dropped almost everything")

    # ---- 5. the async cuts held ---------------------------------------------
    # enetxt and datachannelxt must NOT bring their async loopbacks in: two
    # state machines in one process race for the event handlers.
    for pfx, member in (("en1", "enetxt"), ("dc1", "datachannelxt")):
        body = re.search(r'^command ' + pfx + r'stRun\b(.*?)^end ' + pfx + r'stRun',
                         src, re.S | re.M)
        if body is None:
            fail("5", f"{member}: no {pfx}stRun to check the async cut in")
            continue
        if "GENERATED CUT" not in body.group(1):
            fail("5", f"{member}: {pfx}stRun has no generated cut marker, so "
                      f"its async loopback may have been folded in")
        if re.search(r'send\s+"', body.group(1)):
            fail("5", f"{member}: {pfx}stRun still arms a timer, so the async "
                      f"half was folded in and will race the core's loopback")

    # ---- 6. torrentxt reuses the core's single session ----------------------
    if "put sSession into bt1sSession" not in src:
        fail("6", "torrentxt does not reuse the core's session; it would open a "
                  "second one, fail, and skip its entire surface while looking green")

    # ---- 6b. riptide reads the core's session on EVERY call -----------------
    # Check 6's alias is taken once per run by a harness that runs once per
    # run. Riptide's rstAcquireSession is called from four sections, and its
    # standalone head returns a CACHED handle whenever one is set - so the
    # alias the fold used to take on the FIRST call won over the core's handle
    # forever after. The core stops THE session and takes a new one on every
    # run (stCleanup, then the probe), so from the second run in one launch
    # (Run all, or since D-23 a row's Run) riptide's DM and live-feed sections
    # talked to a stopped session: calls that answer negative, in sections
    # that then read like library defects. The generator now replaces the
    # whole body; these are the three ways back to the defect:
    #   * the core's handle is written into the cache on the read path
    #     (`put sSession into rs1sRsTestSession`);
    #   * no btStartSession anywhere in it: a session started here is one
    #     nothing in the paste would ever stop (the core's teardown knows only
    #     its own handle), so TorrentXT is lost for the rest of the launch
    #     (OXT-PASS-RUNBOOK 5.1.1);
    #   * no `return` before the first read of sSession: an early return of
    #     the cached handle is exactly the head that went stale.
    # Asked of the comment-free view with string literals KEPT, so a start
    # spelled through `do` or `value(...)` is seen as well.
    rip = re.search(r'^(?:private\s+)?(?:command|function)\s+rs1rstAcquireSession\b'
                    r'(.*?)^end\s+rs1rstAcquireSession\b', bare, re.S | re.M | re.I)
    if rip is None:
        fail("6b", "rs1rstAcquireSession is gone from the paste, so nothing "
                   "shows riptide's sections read the core's session rather "
                   "than a cached or self-started one")
    else:
        rbody = rip.group(1).split("\n")
        if not re.search(r'\bput\s+sSession\s+into\s+rs1sRsTestSession\b',
                         rip.group(1), re.I):
            fail("6b", "rs1rstAcquireSession no longer puts the core's sSession "
                       "into rs1sRsTestSession, so riptide's sections can run on "
                       "a handle cached by an earlier run - a session the core "
                       "has already stopped")
        starts = [ln.strip() for ln in rbody if re.search(r'\bbtStartSession\b', ln, re.I)]
        if starts:
            fail("6b", f"rs1rstAcquireSession can start a session ({starts[0]!r}). "
                       f"In this paste that session belongs to nobody: the core's "
                       f"teardown stops only its own handle, so TorrentXT is lost "
                       f"for the rest of the launch. Zero must mean SKIP.")
        first_read = next((k for k, ln in enumerate(rbody)
                           if re.search(r'\bsSession\b', ln)), None)
        early = [ln.strip() for ln in rbody[:first_read if first_read is not None else len(rbody)]
                 if re.search(r'\breturn\b', ln, re.I)]
        if early:
            fail("6b", f"rs1rstAcquireSession returns before it reads the core's "
                       f"sSession ({early[0]!r}) - the cached-handle head that "
                       f"kept a stopped session alive from the second run on")

    # ---- 7. the folded teardowns stay UNREACHABLE ---------------------------
    # en1stCleanup calls enDeinitialize and dc1stCleanup calls dcCleanup. Both
    # are folded in as dead code, and both MUST stay dead: the core runs its own
    # ENet and DataChannel loopbacks for the cross-member sections, and either
    # teardown would pull the transport out from under them mid-run. Wiring one
    # of these up is the obvious-looking "fix" for a leak that does not exist -
    # the sync halves destroy everything they create - so it is checked.
    # bt1stCleanup joined the list after an adversarial review noticed the
    # asymmetry, and it is the one of the three that would fail QUIETLY. It
    # calls btStopSession on bt1sSession, which the fold has made an alias for
    # the CORE's handle. Freeing it mid-run does not throw; it just makes every
    # later torrent call answer negative - and stCrossBep44Section's sharpest
    # check is `btDhtPutSigned(..., tWrongHex) < 0`, which a freed handle also
    # satisfies. That fail-closed assertion would go green while proving nothing
    # about signature verification.
    #
    # WIDENED 2026-09-24. This asked "does a LINE BEGIN with the name", which
    # is the question the first defect answered: a bare statement call. It
    # could not see the other ways LiveCodeScript reaches a handler -
    # `do "en1stCleanup"`, `send "dc1stCleanup" to me in 1 tick`,
    # `dispatch "bt1stCleanup"`, `value("en1stCleanup()")`, or a one-line
    # `if ... then en1stCleanup` - and D-23's board routes its buttons by NAME,
    # which is where a new call would most likely arrive as a string. So each
    # name may now occur NOWHERE except its own command and end lines, asked of
    # the comment-free view with string literals KEPT (a literal is how every
    # one of those spellings names it). A comment that mentions one is prose
    # and does not count; tools/test-suite-selftest.py proves both directions.
    bare_lines = bare.split("\n")
    raw_lines = src.split("\n")
    for h, what in (("en1stCleanup", "enDeinitialize"), ("dc1stCleanup", "dcCleanup"),
                    ("bt1stCleanup", "btStopSession on the core's own session handle")):
        own = re.compile(r'^\s*(?:(?:private\s+)?command|end)\s+' + h + r'\s*$', re.I)
        rows = sorted({bare.count("\n", 0, m.start())
                       for m in re.finditer(r'\b' + h + r'\b', bare, re.I)})
        callers = [(i, raw_lines[i].strip()) for i in rows
                   if not own.match(bare_lines[i])]
        if callers:
            i, text = callers[0]
            fail("7", f"{h} is named outside its own definition (line {i + 1}: "
                      f"{text!r}"
                      + (f", and {len(callers) - 1} more" if len(callers) > 1 else "")
                      + f"), but it runs {what}, which would tear down the "
                        f"transport the core's own loopback is using. It must "
                        f"stay unreachable - by statement, send, dispatch, do or "
                        f"value alike.")

    # ---- 7b. box2dxt: the Kit is embedded ONCE, and the message path holds ---
    # Two deliberate decisions, both silent if they regress.
    #
    # ONE COPY OF THE KIT. box2dxt's harness is a paste-and-run stack, so it
    # carries a verbatim copy of src/box2dxt-kit.livecodescript between
    # sentinels (its own tools/sync-embedded-kit.py owns that region). The
    # generator CUTS that copy and embeds the Kit once, from src/, as a script
    # layer. If the cut ever stopped matching, all 313 b2k* handlers would be
    # defined twice - check 1 above would catch it, but not say why - so the
    # positive invariant is checked here: exactly one definition of a handler
    # only the Kit defines, and no leftover sentinel from the harness's copy.
    for sentinel in ("-- >>> BEGIN EMBEDDED KIT >>>", "-- <<< END EMBEDDED KIT <<<"):
        if sentinel in src:
            fail("7b", f"the harness still carries box2dxt's own embedded-Kit "
                       f"sentinel ({sentinel!r}), so the fold brought a SECOND "
                       f"copy of the Kit in alongside the embedded layer")
    if len([d for d in defs if d.lower() == "b2ksteponce"]) != 1:
        fail("7b", "b2kStepOnce is not defined exactly once - the b2k Kit is "
                   "either missing from the paste or in it twice")
    #
    # THE MESSAGE PATH. The Kit dispatches b2kFell/b2kSensorEnter/b2kContact BY
    # LITERAL NAME to the object that registered as the frame/contact target.
    # The fold prefixes every other name box2dxt's harness defines; these three
    # are kept, because a b21b2kFell would never be dispatched to - and the three
    # checks that prove the Kit's message path works (as opposed to its polling
    # accessors) would report 0 events and read like a dispatcher defect.
    for receiver in ("b2kFell", "b2kSensorEnter", "b2kContact"):
        if not re.search(r'^on\s+' + receiver + r'\b', src, re.M):
            fail("7b", f"{receiver} is not defined at its real name - the fold "
                       f"prefixed a message receiver the embedded Kit dispatches "
                       f"by literal name, so those events will never arrive")
        if re.search(r'\bb21' + receiver + r'\b', src):
            fail("7b", f"b21{receiver} exists - the fold renamed a message "
                       f"receiver the embedded Kit dispatches by literal name")

    # ---- 7c. box2dxt's own window did not come with it -----------------------
    # It hangs its window off the CARD hooks and a builder of its own, so
    # DROP_HANDLERS' openStack/closeStack set does not cover it. Left in, `on
    # openCard` would rebuild an 860x640 window over the suite's the moment this
    # stack's card opened.
    for gone in ("b21buildStUI", "b21openCard", "b21closeCard"):
        if re.search(r'^(?:command|on|function)\s+' + gone + r'\b', src, re.M):
            fail("7c", f"{gone} survived the fold; box2dxt's own window would "
                       f"be built over the suite's")

    # ---- 7d. holde-em: the LIVE game stays out of the harness's reach -------
    # holde-em is the one member whose fold carries a whole APPLICATION, not a
    # test file: the game and its harness are the same 15k-line stack, so
    # everything the game can do is in this paste whether the harness calls it
    # or not. Every hazard below is therefore a REACHABILITY question, and the
    # answer has to be re-asked on every build - a new call site in a section is
    # the cheapest possible way to wire one of these up by accident.
    #
    # The closure is deliberately an OVER-approximation: any he1* name mentioned
    # anywhere in a reachable handler's body (comments stripped, strings KEPT -
    # this harness dispatches its sections with `do pName` off string literals)
    # counts as an edge. It can therefore report a path that never executes,
    # which is the safe direction; it cannot miss one.
    he_blocks = {}
    for m in re.finditer(r'^(?:private\s+)?(?:command|function|on)\s+(he1\w+)\b'
                         r'(.*?)^end\s+\1\b', bare, re.S | re.M):
        he_blocks.setdefault(m.group(1).lower(), []).append(m.group(2))
    if not he_blocks:
        fail("7d", "holde-em folded in no he1* handlers at all - this whole "
                   "block of checks is now checking nothing")
    else:
        reach, frontier = {"he1heselftest"}, ["he1heselftest"]
        while frontier:
            name = frontier.pop()
            for body in he_blocks.get(name, []):
                for tok in set(re.findall(r'\b(he1\w+)\b', body)):
                    low = tok.lower()
                    if low in he_blocks and low not in reach:
                        reach.add(low)
                        frontier.append(low)
        # Each of these would be silent, and each is a DIFFERENT kind of silent.
        forbidden = {
            "he1heNetStart":
                "btStartSession - a SECOND libtorrent session in a process that "
                "allows exactly one, and the core already opened it during its "
                "probe. It is also the ONLY writer of he1gGame[\"session\"], "
                "which is what keeps the reachable he1heNetStop from ever "
                "handing the core's live handle to btStopSession",
            "he1heRunSelftest":
                "the INTERACTIVE entry point: it builds an 800x560 report "
                "overlay on the card, overwrites clipboardData[\"text\"] (this "
                "scaffold's own Copy-results channel) and writes to msg",
            "he1heBuildTable":
                "it builds holde-em's entire 1024x640 poker table - every seat, "
                "the felt, the board and the action row - on the suite's card",
            "he1heReportShow":
                "it creates the report overlay's graphic, field and button on "
                "whatever card this paste is running on",
            "he1heProbeTorrent":
                "btStartSession - the SECOND of holde-em's two session openers, "
                "and the one that reads as harmless because it is a diagnostic. "
                "It is unreachable today (nothing in the folded closure calls "
                "it), so this entry is a TRIPWIRE rather than a fix: the "
                "one-session-per-process rule is a property of the paste, not of "
                "any one handler, and naming only heNetStart would let a future "
                "section wire the probe up and take the core's session with it",
            "he1heKitTryInit":
                "it starts a b2k physics world and loads card atlases, which "
                "would collide with the world box2dxt's folded harness "
                "hand-steps a few sections earlier",
        }
        # A NAMED HAZARD THAT NO LONGER EXISTS IS A STALE EXCUSE, and this repo
        # has already paid for one gate that could not tell "checked" from
        # "parsed" (coinxt's constant gate, root CLAUDE.md). If a handler above
        # is renamed or deleted, its entry silently stops guarding anything
        # while still reading like protection - so the list is held to the
        # tree in BOTH directions: reachable is a failure, and absent is a
        # failure.
        for name in forbidden:
            if name.lower() not in he_blocks:
                fail("7d",
                     f"{name} is named in this gate's forbidden set but is not "
                     f"defined in the folded harness at all. Either it was "
                     f"renamed - in which case this entry now guards nothing and "
                     f"must be updated to the new name - or it is gone and the "
                     f"entry should be deleted. A hazard list that outlives its "
                     f"hazards is worse than no list.")
        for name, why in forbidden.items():
            if name.lower() in reach:
                fail("7d",
                     f"{name} is REACHABLE from he1heSelfTest, and it runs {why}. "
                     f"Either the call is a mistake, or the hazard has been "
                     f"handled and this entry should say so.")
        # NAMING THE FIVE HANDLERS ABOVE SAYS WHAT MUST NOT BE CALLED; this
        # says what must not HAPPEN, which is the half that survives a rename
        # or a new handler nobody thought to list. Measured at the fold: the
        # closure of he1heSelfTest creates no control, deletes none, never
        # resizes or retitles the stack, and never touches clipboardData. Those
        # are the four ways this member could damage a paste it is a guest in -
        # the suite core owns the window, and clipboardData is the scaffold's
        # own Copy-results channel. (What the closure DOES reach, and why it is
        # allowed: the sound path's `set the defaultStack`, `import audioClip`
        # and `play audioClip`, all three inside heSndTryInit/heSndPlay and all
        # fail-closed behind heStackFolder returning empty for an unsaved stack
        # and gSndOk never being set. They are named here so that "the scan
        # found nothing" cannot be confused with "the scan looks for nothing".)
        guest = (
            (r'^\s*create\s+', "creates a control on the host's card"),
            (r'^\s*delete\s+(?:field|button|graphic|image|control)\b',
             "deletes a control on the host's card"),
            (r'set\s+the\s+(?:rect|width|height|title)\s+of\s+this\s+stack',
             "resizes or retitles the host's window"),
            (r'\bclipboardData\b',
             "writes the clipboard, which is the suite scaffold's own "
             "Copy-results channel"),
        )
        for name in sorted(reach):
            for body in he_blocks.get(name, []):
                for ln in body.split("\n"):
                    for pat, what in guest:
                        if re.search(pat, ln, re.I):
                            fail("7d",
                                 f"{name} is reachable from he1heSelfTest and "
                                 f"{what}: {ln.strip()!r}. holde-em is a guest "
                                 f"in this paste; the core owns the window.")
        # The second half of the bt1stCleanup argument, stated as a fact rather
        # than left as reasoning: he1heNetStop IS reachable and does call
        # btStopSession, so what makes that harmless is that the handle it
        # passes can only ever be empty. Nothing but he1heNetStart may write it.
        for m in re.finditer(r'^.*\binto\s+he1gGame\["session"\].*$', bare, re.M):
            line = m.group(0)
            owner = None
            for name, bodies in he_blocks.items():
                if any(line in b for b in bodies):
                    owner = name
                    break
            if owner != "he1henetstart":
                fail("7d",
                     f"he1gGame[\"session\"] is written outside he1heNetStart "
                     f"({line.strip()!r}, in {owner}). he1heNetStop is reachable "
                     f"from the harness and passes that value to btStopSession; "
                     f"the ONLY reason that cannot free the core's session is "
                     f"that nothing the harness reaches ever puts a real handle "
                     f"there.")
        # The pending-message sweep. Standalone it matches the "heNet" stem,
        # which is a FRAGMENT of a name and so survives the fold's rename
        # untouched while every message this member arms is prefixed - a sweep
        # that matches nothing, in the handler whose whole job is to leave no
        # timer ticking in somebody else's paste. The generator rewrites it to
        # the member prefix (which also widens it over the paced hand steps).
        sweep = re.search(r'^command he1heTestSweepNetTimers\b(.*?)'
                          r'^end he1heTestSweepNetTimers', bare, re.S | re.M)
        if sweep is None:
            fail("7d", "he1heTestSweepNetTimers is gone; nothing cancels the "
                       "timers holde-em's sections arm, so its next-hand beat "
                       "fires into the core's async loopback phase")
        elif 'begins with "he1"' not in sweep.group(1):
            fail("7d",
                 "he1heTestSweepNetTimers no longer sweeps by the member prefix. "
                 "The standalone \"heNet\" stem cannot survive the rename (it is "
                 "not a name, so nothing renames it) and would match none of the "
                 "prefixed messages this harness arms - a silent no-op.")

    # ---- 7e. holde-em's own window and engine hooks did not come with it -----
    # Its harness is headless (every UI touch is guarded and fails closed), but
    # the STACK around it is not. preOpenStack is the loud one: two lines that
    # set this stack's rect and title, so left in it would silently turn the
    # suite's window into a 1024x640 stack called "holde-em" the moment the
    # paste opened. The five scrollbar messages belong to the bet slider and
    # guard on a control name; they are inert here only because nothing in the
    # suite window happens to be called "heBetSlider".
    for gone in ("he1preOpenStack", "he1openStack", "he1closeStack",
                 "he1mouseUp", "he1scrollbarDrag", "he1scrollbarLineInc",
                 "he1scrollbarLineDec", "he1scrollbarPageInc",
                 "he1scrollbarPageDec"):
        if re.search(r'^(?:command|on|function)\s+' + gone + r'\b', src, re.M):
            fail("7e", f"{gone} survived the fold; holde-em's own stack "
                       f"chrome would run on the suite's window")

    # ---- 8. coinxt is probed as TWO pieces ----------------------------------
    # It is the only member that ships an extension AND a separate script layer,
    # and ten of its folded sections call the script. Probing only the extension
    # would make a script layer that did not load look like ten library defects
    # instead of one damaged paste - the most expensive possible way to spend an
    # engine session. Both probes, and a guard that SKIPS rather than runs.
    # (The layer used to be a `start using stack "coinxt"` setup step; since
    # 2026-08-10 the generator EMBEDS it, so what the script probe catches now
    # is a damaged or missing embed, and the messages say so.)
    if "sHaveCoinScript" not in src:
        fail("8", "the harness does not probe coinxt's SCRIPT layer separately. "
                  "The layer is EMBEDDED in this paste, so a damaged or missing "
                  "embed would report as ten FAILs rather than one skip naming "
                  "the damage")
    elif "sHaveCoin and sHaveCoinScript" not in src:
        fail("8", "coinxt's deep harness is not guarded on BOTH sHaveCoin and "
                  "sHaveCoinScript, so it would run its script-layer sections "
                  "against an embedded layer that did not answer its probe")

    # ---- 9. nothing from a member's own window survived --------------------
    for bad in ("bt1stShow", "bt1stPaint", "cx1stShow", "cx1stPaint",
                "en1stShow", "en1stPaint", "dc1stShow", "dc1stPaint"):
        m = re.search(r'^command ' + bad + r'\b(.*?)^end ' + bad, src, re.S | re.M)
        if m and m.group(1).strip():
            fail("9", f"{bad} should be a no-op stub (the core owns the UI) "
                      f"but has a body")

    # ---- 10. EVERY declaration is above EVERY handler -----------------------
    # OXT resolves a script-level name by LEXICAL POSITION, so a `local` below a
    # handler is not in scope for it - and LiveCodeScript does not error on an
    # unresolved name, it evaluates it to the literal text of its own name. So
    # the failure is silent until something does arithmetic on it.
    #
    # Check 2 above already proves every name a folded harness uses is DECLARED.
    # That is not the same as declared IN SCOPE, and the difference cost an
    # engine run: each member's declarations were emitted inside that member's
    # own section, which is where they sit in the member's own file and looks
    # right - but the fold puts coinxt's section ~1000 lines BELOW the core's
    # stRunMemberHarnesses, which reads cx1sPassed to merge the totals. The
    # engine read the string "cx1sPassed" and died on
    # `add "cx1sPassed" to sPassed` with "add: error in source expression".
    #
    # The generator now hoists every folded declaration above the first handler.
    # This is the invariant that makes that stay true, and it is deliberately
    # blunt: position, not reachability. Anything subtler would need to know
    # which handler reads what, which is how the first version got it wrong.
    #
    # Asked of the COMMENT-FREE view, not the raw text, while reporting the
    # raw line: strip_comments preserves the line count precisely so these
    # numbers stay usable. Raw, a folded block-comment changelog would supply
    # both halves of a false alarm - a prose line opening `on ...` taken for
    # the first handler, and every real declaration below it then "late".
    lines_raw = src.split("\n")
    lines_bare = bare.split("\n")
    first_handler = None
    for i, line in enumerate(lines_bare, start=1):
        if re.match(r'^(?:private\s+)?(?:command|function|on)\s+\w+', line):
            first_handler = i
            break
    if first_handler is None:
        fail("10", "no handlers found at all - the generated file is not "
                   "what this checker thinks it is")
    else:
        late = [(i, lines_raw[i - 1].strip())
                for i, line in enumerate(lines_bare, start=1)
                if i > first_handler and re.match(r'^(?:local|constant)\s', line)]
        if late:
            fail("10",
                 f"{len(late)} script-level declaration(s) appear BELOW the first "
                 f"handler (line {first_handler}), so any handler above them reads "
                 f"an undeclared name - which LiveCodeScript silently evaluates to "
                 f"the literal text of that name:\n      "
                 + "\n      ".join(f"line {i}: {t}" for i, t in late[:6])
                 + ("\n      ..." if len(late) > 6 else ""))

    # ---- 10b. every CORE declaration was MOVED, not dropped or doubled ------
    # Check 10 asks where the declarations ARE; it cannot see one that is not
    # there. Since D-23 the generator MOVES declarations: the core carries the
    # UI kit and the demo self-check verbatim, and their constants and locals
    # sit below the scaffold's handlers - legal in the core, against check 10
    # in the paste - so hoist_core_declarations lifts them to the declaration
    # marker. A move is a delete and an insert, and either half can go wrong
    # alone. A lost insert leaves a name undeclared, which evaluates to its
    # own spelling (engine note 2.1): the Failures view would hand
    # `set the foregroundColor ... to kUiBad` the TEXT "kUiBad", and the boot
    # self-check's sScLines would stop being ONE script-level log shared by
    # the handlers that write and read it. A doubled insert is a duplicate
    # declaration. So every column-0 declaration line of
    # the core (comment-free, trailing space ignored) must appear in the paste
    # ABOVE its first handler exactly as many times as the core has it -
    # which covers the core's own declarations, the carried scaffold's, and
    # every hoisted one alike.
    core_src = open(args.core, encoding="utf-8").read()
    core_raw = core_src.split("\n")
    core_view = strip_comments(core_src, core_rel).split("\n")
    core_blank = [blank_literals(ln) for ln in core_view]
    core_decls = collections.Counter(
        ln.rstrip() for ln in core_view if re.match(r'^(?:local|constant)\s', ln))
    if not core_decls:
        fail("10b", f"{core_rel} declares nothing at column 0 - that is not the "
                    f"core, and this check is checking nothing")
    elif first_handler is not None:
        above = collections.Counter(ln.rstrip() for ln in lines_bare[:first_handler - 1])
        dropped = [d for d in core_decls if above[d] < core_decls[d]]
        doubled = [d for d in core_decls if above[d] > core_decls[d]]
        if dropped:
            fail("10b",
                 f"{len(dropped)} declaration(s) of the core are missing from "
                 f"the paste above its first handler (line {first_handler}) - "
                 f"moved and not put back, or left below it. Each evaluates to "
                 f"the literal text of its own name wherever it is read:\n      "
                 + "\n      ".join(dropped[:6])
                 + ("\n      ..." if len(dropped) > 6 else ""))
        if doubled:
            fail("10b",
                 f"{len(doubled)} declaration(s) of the core appear MORE often "
                 f"above the paste's first handler than in the core - a hoist "
                 f"that copied instead of moving:\n      "
                 + "\n      ".join(doubled[:6])
                 + ("\n      ..." if len(doubled) > 6 else ""))

    # ---- 11. the embedded script layers are present, balanced, and whole ----
    # tools/build-suite-selftest.py embeds coinxt's and onionxt's pure-script
    # libraries between sentinel lines. Their absence would mean the harness
    # again tests whatever stale copy happens to be loaded in the engine - the
    # failure mode the embed exists to close - and unbalanced sentinels would
    # break check-suite-coverage.py's cut, which is what keeps the libraries'
    # own bodies from counting as coverage of themselves.
    begin_re = re.compile(r'^-- >>> GENERATED EMBED: (.+) >>> --$')
    end_re = re.compile(r'^-- <<< GENERATED EMBED: (.+) <<< --$')
    span_lines, stack, seen_spans = {}, [], set()
    for i, line in enumerate(src.split("\n"), start=1):
        m = begin_re.match(line)
        if m:
            stack.append(m.group(1))
            seen_spans.add(m.group(1))
            span_lines.setdefault(m.group(1), [])
            continue
        m = end_re.match(line)
        if m:
            if not stack or stack[-1] != m.group(1):
                fail("11", f"line {i}: embed sentinel end '{m.group(1)}' has "
                           f"no matching begin")
            else:
                stack.pop()
            continue
        if stack:
            span_lines[stack[-1]].append(line)
    for name in stack:
        fail("11", f"embed sentinel begin '{name}' never ends")
    for want in ("coinxt script layer", "onionxt script layer",
                 "riptide script layer", "box2dxt-kit script layer",
                 "nostrxt script layer"):
        if want not in seen_spans:
            fail("11", f"no embedded span '{want}' - the harness no longer "
                       f"carries that library, so its folded tests run "
                       f"against whatever stale copy the engine has loaded")
        elif len(span_lines.get(want, [])) < 500:
            fail("11", f"embedded span '{want}' is only "
                       f"{len(span_lines.get(want, []))} lines - a fragment, "
                       f"not the library")

    # ---- 12. the embedded layers' script-level names are declared -----------
    # Check 2 protects the FOLDED harnesses by their prefixes; the embedded
    # libraries are unprefixed, so their s*/k* names need the same proof: a
    # declaration the generator's hoist missed would not error, it would
    # evaluate to the literal text of its own name inside a LIBRARY handler -
    # a wrong address or a dead socket state machine, not a red test line.
    embedded_bare = strip_comments("\n".join(
        "\n".join(lines) for lines in span_lines.values()), paste_rel)
    embedded_used = set(re.findall(r'\b([sk][A-Z]\w*)\b', embedded_bare))
    handler_names_exact = set(defs)
    undeclared_embed = sorted(
        n for n in embedded_used
        if n not in declared and n not in handler_names_exact)
    if undeclared_embed:
        fail("12",
             "embedded-layer script-level names used but never declared (the "
             "generator's declaration hoist missed them): "
             + ", ".join(undeclared_embed[:12])
             + (f" (+{len(undeclared_embed) - 12} more)"
                if len(undeclared_embed) > 12 else ""))

    # ---- the core's own call structure (checks 13b-17 read it) ---------------
    core_handlers, unterminated = handler_spans(core_view)
    if unterminated is not None:
        fail("13b", f"{core_rel}: handler {unterminated} never ends, so the "
                    f"core's call graph cannot be read")
    by_name = {}
    for name, a, b in core_handlers:
        by_name.setdefault(name.lower(), []).append((a, b))
    carried = carried_lines(core_raw)
    own_rows = [i for i in range(len(core_view)) if i not in carried]

    # ---- 13b. each entry point is CALLED, not merely defined ---------------
    # Check 3 proves each member's entry point EXISTS in the paste. A harness
    # that exists and is never called is the quietest failure this file can
    # have: before D-23 the run was simply shorter and still green. Since D-23
    # every call sits under `if suInScope("<member>")` in stRunMemberHarnesses
    # and every block under a tally, which are new ways to cut one off with an
    # innocent-looking edit - a scope test spelled with the wrong key, a block
    # moved into a helper nothing calls, a call left only in a label.
    #
    # So the question is reachability through the CORE's own call graph, from
    # what the engine delivers without being asked: openStack, mouseDown,
    # mouseUp and closeStack, and every timer the core arms (a literal
    # `send ... in`). An edge is a core handler's name, or an entry point's,
    # in a reachable handler's comment-free body with string literals BLANKED
    # (a name in a test label is not a call), plus the literal target of a
    # `send` or `dispatch`, which is. It is an over-approximation - a call in a
    # branch that never runs still counts - so it proves each harness is WIRED
    # to an event, not that it executes; the board check in the run's summary
    # (a row that counted nothing reads "nothing ran") is the runtime half.
    entry_low = {e.lower(): e for e in ENTRY_POINTS}
    all_rows = range(len(core_view))
    armed_all = []
    for i, col, word in statements(core_blank, all_rows):
        if word.lower() == "send":
            target, _, delayed = message_target(core_view[i], core_blank[i], col, word)
            if target and delayed:
                armed_all.append(target)

    def edges(first, last):
        out = set()
        rows = range(first + 1, last)
        for i in rows:
            for tok in re.findall(r'\b(\w+)\b', core_blank[i]):
                low = tok.lower()
                if low in by_name or low in entry_low:
                    out.add(low)
        for i, col, word in statements(core_blank, rows):
            if word.lower() in ("send", "dispatch"):
                target, _, _ = message_target(core_view[i], core_blank[i], col, word)
                if target:
                    out.add(target.lower())
        return out

    events_here = [e for e in EVENTS if e.lower() in by_name]
    roots = {e.lower() for e in events_here} | {t.lower() for t in armed_all}
    reach, frontier = set(roots), list(roots)
    while frontier:
        name = frontier.pop()
        for a, b in by_name.get(name, []):
            for nxt in edges(a, b):
                if nxt not in reach:
                    reach.add(nxt)
                    frontier.append(nxt)
    if not events_here:
        fail("13b", f"{core_rel} defines none of {', '.join(EVENTS)} - nothing "
                    f"the engine delivers reaches the core, and this check is "
                    f"checking nothing")
    unreached = [e for e in ENTRY_POINTS if e.lower() not in reach]
    for e in unreached:
        fail("13b",
             f"{e} is not reachable from the core's events or timers "
             f"({', '.join(events_here + sorted(set(armed_all)))}). The paste "
             f"defines it (check 3), but no chain of calls from anything the "
             f"engine delivers ends in it, so that member's deep self-test "
             f"never runs; its row would read 'nothing ran', and a run that "
             f"skipped it would otherwise look complete.")

    # ---- 14. the core NAMES every handler it reaches ------------------------
    # Checks 7, 13b and 15, check-timer-stack-pin.py and the coverage ratchet
    # all read the core's calls STATICALLY, and four spellings defeat every one
    # of them at once, because each computes the handler's name at run time:
    # `do`, `dispatch` and `call` statements, and `value(...)`. So does a
    # `send` whose message is not a string literal. The core has none of them
    # today - the one computed send in it is the kit's copy flash, inside a
    # carried block whose master and drift gate own it - so the rule costs
    # nothing and keeps every static gate able to see the core. STATEMENT
    # position only (a line's start, and after `then`/`else`, where a one-line
    # if puts a statement), in the literal-BLANKED view: the core's own report
    # text says "call site" twice, and a word in a label is not a statement.
    # `value(` is refused anywhere in code, where it can only be a call.
    for i, col, word in statements(core_blank, own_rows):
        low = word.lower()
        if low in ("do", "dispatch", "call"):
            fail("14", f"{core_rel} line {i + 1} is a `{low}` statement "
                       f"({core_raw[i].strip()!r}). It names its handler at run "
                       f"time, so no static gate can see the call; name the "
                       f"handler directly, or `send` it a literal.")
        elif low == "send":
            target, literal, _ = message_target(core_view[i], core_blank[i], col, word)
            if not literal:
                fail("14", f"{core_rel} line {i + 1} sends a computed message "
                           f"({core_raw[i].strip()!r}). Every send in the core "
                           f"names its handler as a string literal, so checks "
                           f"13b and 15 can see what it arms.")
    for i in own_rows:
        if re.search(r'\bvalue\s*\(', core_blank[i], re.I):
            fail("14", f"{core_rel} line {i + 1} evaluates a computed "
                       f"expression with value(...) ({core_raw[i].strip()!r}); "
                       f"no static gate can see what it calls.")

    # ---- 15. every core timer is cancellable, pinned, and the core's --------
    # A timer is the one kind of call that outlives the handler that made it,
    # and each property below has a failure behind it:
    #   * CANCELLED BY stCancelPump. Without the cancel, Re-run would arm a
    #     second pump beside a pending one; both would pass the running guard
    #     and every assertion would count twice (stCancelPump's own comment
    #     has the argument). D-23 added a second timer (a row's armed Run,
    #     suRunTick) and extended the cancel list BY HAND, and the core's
    #     comment promises that this gate "holds the two lists together" - in
    #     both directions, because a cancel entry nothing arms is a stale
    #     excuse that reads like protection.
    #   * NOT he1*. holde-em's folded harness sweeps every pending message that
    #     begins with its member prefix before it returns (the generator widens
    #     its sweep to exactly that), so a core timer spelled he1* would be
    #     cancelled mid-run by a guest: the pump gone, the run never finished.
    #   * PINNED FIRST. A `send ... in` handler resolves every unqualified
    #     control against the DEFAULTSTACK (engine note 5.3), and the board
    #     paints by unqualified name. check-timer-stack-pin.py asks whether each
    #     reachable control write is pinned somewhere above it; this asks the
    #     stricter thing the core promises in its comments ("PINNED FIRST"):
    #     the pin is the timer's first executable statement, so no line added
    #     later can slip in above it.
    armed = []
    for i, col, word in statements(core_blank, own_rows):
        if word.lower() == "send":
            target, literal, delayed = message_target(core_view[i], core_blank[i], col, word)
            if target and delayed:
                armed.append((i, target))
    cancel = []
    for a, b in by_name.get("stcancelpump", []):
        for i in range(a + 1, b):
            cancel += re.findall(r'\bitem\s+3\s+of\s+\w+\s+is\s+"([^"]*)"',
                                 core_view[i], re.I)
    if "stcancelpump" not in by_name:
        fail("15", f"{core_rel} has no stCancelPump, so nothing cancels the "
                   f"timers it arms; Re-run would start a second chain beside "
                   f"the first and count every assertion twice")
    elif not cancel:
        fail("15", "stCancelPump names no message (`item 3 of ... is \"...\"`), "
                   "so it cancels nothing - or its comparison was rewritten into "
                   "a shape this check cannot read, which must be fixed here")
    cancel_low = {c.lower() for c in cancel}
    armed_low = {t.lower() for _, t in armed}
    for i, target in armed:
        where = f"{core_rel} line {i + 1}"
        if target.lower() not in cancel_low:
            fail("15", f"{where} arms {target}, which stCancelPump does not "
                       f"cancel ({', '.join(cancel) or 'nothing'}). A Re-run "
                       f"would leave it pending beside the new run.")
        if target.lower().startswith("he1"):
            fail("15", f"{where} arms {target}: holde-em's folded sweep cancels "
                       f"every pending message that begins with he1, so this "
                       f"timer would be cancelled by a guest mid-run.")
        blocks = by_name.get(target.lower(), [])
        if not blocks:
            fail("15", f"{where} arms {target}, which the core does not define - "
                       f"a timer into a handler that is not the core's (or not "
                       f"anyone's) cannot be held to the pin")
        for a, b in blocks:
            first = None
            for k in range(a + 1, b):
                s = core_view[k].strip()
                if not s or re.match(r'local\b', s, re.I):
                    continue
                first = (k, s)
                break
            if first is None or re.sub(r'\s+', ' ', first[1]).lower() != PIN:
                fail("15", f"{target} (armed at {where}) does not pin the "
                           f"defaultStack first: its first statement is "
                           + (f"{first[1]!r} (line {first[0] + 1})" if first else "missing")
                           + f". A `send ... in` handler resolves unqualified "
                             f"controls against the defaultStack (engine note "
                             f"5.3); make `set the defaultStack to the short "
                             f"name of this stack` its first line.")
    for c in cancel:
        if c.lower() not in armed_low:
            fail("15", f"stCancelPump cancels {c}, which the core never arms "
                       f"(outside its carried blocks). A cancel entry for a "
                       f"timer that is gone guards nothing and hides the next "
                       f"one; remove it, or arm it where it belongs.")

    # ---- 16a. the board's control names are the board's --------------------
    # The core builds its window on the SAME card the folded harnesses use, and
    # two of them treat control names as theirs: box2dxt builds and wipes
    # graphics named st_* and b2k* (its stWipe deletes by those prefixes) and
    # writes field "stReport" whenever one exists; holde-em's harness guards
    # its UI touches on he* names. A board control under any of those would be
    # deleted mid-run, overwritten with another member's report, or written by
    # a guest. So no literal control name the core builds or references may
    # take one, derived by check-demo-control-lists.py's own derive_split (the
    # parse the boot self-check's list comes from, carried blocks cut), and
    # every name the core COMPUTES for a kit builder - one per row - must open
    # with the literal "su", the one prefix nothing else on this card uses. A
    # computed name that does not open with a literal cannot be proved, so it
    # is refused too.
    refs, built = CONTROLS.derive_split(args.core)
    clashes = sorted(n for n in refs | built
                     if n.lower().startswith(("st_", "b2k"))
                     or re.match(r'he[A-Z]', n) or n.lower() == "streport")
    for n in clashes:
        fail("16a", f"{core_rel} names a control {n!r}, a name a folded harness "
                    f"owns on this card (box2dxt wipes st_* and b2k* and writes "
                    f"stReport; holde-em guards on he*). Name it su*.")
    ctl_text = CONTROLS.demo_source(args.core)
    kit_builders = CONTROLS.builders() | CONTROLS.local_builders(ctl_text)
    computed = 0
    if kit_builders:
        pat = re.compile(r'^\s*(%s)\s+\((.*)$' % "|".join(
            sorted(map(re.escape, kit_builders), key=len, reverse=True)), re.M)
        for m in pat.finditer(ctl_text):
            computed += 1
            lit = re.match(r'\s*"([^"]*)"', m.group(2))
            if lit is None or not lit.group(1).startswith("su"):
                fail("16a", f"{core_rel}: {m.group(1)} builds a computed name "
                            f"({m.group(0).strip()!r}) that does not open with "
                            f"the literal \"su\", so nothing proves it cannot "
                            f"collide with a folded harness's controls.")

    # ---- 17. the board has one row per registry member, in its order -------
    # A LiveCodeScript paste cannot read tools/member-registry.py, so the core
    # spells the members as constants: kSuKeys (the rows, then "cross"),
    # kSuNames (their titles, then the cross row's) and kSuNoHarness (the rows
    # with a caption instead of a Run). Those are hand-copied lists, and root
    # CLAUDE.md's lesson is that hand-copied lists go stale silently: a twelfth
    # member would get no row, a renamed one a row that counts nothing. The
    # generator already refuses a registry member with neither a harness nor a
    # NO_HARNESS reason; this holds the board to the same table, and each
    # harness member to its scope test in stRunMemberHarnesses - without
    # `if suInScope("<member>")` its harness either never runs or runs in
    # every scope, counting into whichever row's Run was pressed.
    def core_constant(name):
        hits = [re.match(r'^constant\s+' + name + r'\s*=\s*"([^"]*)"\s*$', ln, re.I)
                for ln in core_view]
        hits = [h for h in hits if h]
        if len(hits) != 1:
            fail("17", f"{core_rel} must declare `constant {name}` exactly once, "
                       f"as one string literal; found {len(hits)}")
            return None
        return hits[0].group(1).split(",")

    reg_names = [m.name for m in REGISTRY.MEMBERS]
    reg_titles = [m.title for m in REGISTRY.MEMBERS]
    keys = core_constant("kSuKeys")
    titles = core_constant("kSuNames")
    noh = core_constant("kSuNoHarness")
    if keys is not None and keys != reg_names + ["cross"]:
        fail("17", f"kSuKeys is {','.join(keys)!r}; tools/member-registry.py "
                   f"says the rows are {','.join(reg_names + ['cross'])!r} (every "
                   f"member in the registry's order and spelling, then cross)")
    if titles is not None and (titles[:len(reg_titles)] != reg_titles
                               or len(titles) != len(reg_titles) + 1
                               or not titles[-1].strip()):
        fail("17", f"kSuNames is {','.join(titles)!r}; it must be the registry's "
                   f"titles in order ({','.join(reg_titles)!r}) and then one "
                   f"non-empty title for the cross row")
    if noh is not None:
        noh = [x for x in noh if x]
        if noh != sorted(BUILD.NO_HARNESS):
            fail("17", f"kSuNoHarness is {','.join(noh)!r}; the generator's "
                       f"NO_HARNESS is {','.join(sorted(BUILD.NO_HARNESS))!r}")
        for x in noh:
            if keys is not None and x not in keys:
                fail("17", f"kSuNoHarness names {x!r}, which is not a row in "
                           f"kSuKeys")
        # kSuNoHarness IS A LIST, so it must be ASKED as one. Found while
        # writing this check: the core compared a row key to it with `is` at
        # five sites (suIsRunKey, suPaintRows, suRowControls, suBuildAll,
        # suSummaryNotes), which is right only while the constant names ONE
        # member - a second NO_HARNESS member would equal neither row, and
        # each would get a Run button, a pill and a tally that counts nothing
        # (reading "nothing ran" on an engine). The core now asks through
        # suNoHarness (`is among the items of`, the delimiter restored), and
        # this refuses the `is` form OUTRIGHT rather than only once the list
        # grows: a tripwire that waits for the second member fires in the
        # same commit that adds it, which is one commit too late to be cheap.
        eq = [i + 1 for i in own_rows
              if re.search(r'\bis\s+(?:not\s+)?kSuNoHarness\b', core_blank[i], re.I)]
        if eq:
            fail("17", f"the core compares a row key to kSuNoHarness with `is` "
                       f"({core_rel} lines {', '.join(map(str, eq))}); it is a "
                       f"list, and `is` matches only a one-item list. Ask "
                       f"suNoHarness(key) instead.")
    runner = by_name.get("strunmemberharnesses", [])
    runner_text = "\n".join("\n".join(core_view[a + 1:b]) for a, b in runner)
    if not runner:
        fail("17", f"{core_rel} has no stRunMemberHarnesses")
    for m in BUILD.MEMBERS:
        if keys is not None and m.member not in keys:
            fail("17", f"the generator folds {m.member}, which has no row in "
                       f"kSuKeys, so its checks would count into no row")
        if runner and not re.search(r'(?i:\bif\s+suInScope)\(\s*"' + re.escape(m.member)
                                    + r'"\s*\)', runner_text):
            fail("17", f"stRunMemberHarnesses has no `if suInScope(\"{m.member}\")`, "
                       f"so {m.member}'s harness either never runs or runs in "
                       f"every scope")

    if problems:
        print("check-suite-selftest: FAILED")
        for check, p in problems:
            print(f"  - [check {check}] " + p)
        return 1
    counts = {pfx: len([d for d in defs if d.startswith(pfx)]) for pfx in PREFIXES}
    print(f"check-suite-selftest: OK ({len(defs)} handlers, no collisions, "
          f"all declarations present; folded: "
          + ", ".join(f"{PREFIXES[p]}={c}" for p, c in counts.items())
          + f"; core: {sum(core_decls.values())} declarations above the first "
            f"handler, {len(ENTRY_POINTS)} entry points reachable from "
            f"{len(events_here)} events and {len(set(armed_all))} timers, "
            f"{len(armed)} timer arm(s) cancelled and pinned, "
            f"{len(refs | built)} literal and {computed} computed control "
            f"names clear, {len(reg_names)} registry rows on the board)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
