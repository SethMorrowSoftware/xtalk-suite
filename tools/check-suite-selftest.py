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

Usage:  python3 tools/check-suite-selftest.py [--check]
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GEN = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")

# The prefixes tools/build-suite-selftest.py assigns, and the member each names.
PREFIXES = {"sx1": "sodiumxt", "ox1": "onionxt", "cx1": "coinxt",
            "bt1": "torrentxt", "en1": "enetxt", "dc1": "datachannelxt",
            "rs1": "riptide", "b21": "box2dxt", "he1": "holde-em",
            "nx1": "nostrxt"}

# What the core calls into each folded harness. If the generator ever renames or
# drops one of these, the suite harness compiles and then does nothing.
ENTRY_POINTS = ["sx1sxSelfTest", "ox1oxSelfTest", "cx1stRun", "bt1stRun",
                "en1stRun", "dc1stRun", "rs1rsSelfTest", "b21stSelfTest",
                "he1heSelfTest", "nx1nxSelfTest"]
COUNTED = ["cx1", "bt1", "en1", "dc1"]


def strip_comments(text):
    """Comment-free view of the generated file. Line count is PRESERVED, so
    check 10 can report the line numbers it finds.

    THIS IS THE SAME FUNCTION AS tools/build-suite-selftest.py's, deliberately
    - the generator refuses to WRITE a file with a defect, and this re-checks
    the COMMITTED one, so the two must read a source identically or a future
    fold produces a file the generator accepts and this gate rejects. Keep
    them in step by hand; nothing enforces it yet.

    Block comments are the reason both grew past a line-comment scan.
    /* ... */ is legal LiveCodeScript and holde-em keeps a 926-line header
    changelog in one, where prose wraps to lines like `on every wire during
    the netplay section)` - read as code, a handler named `every`.

    BE PRECISE ABOUT WHAT REACHES THIS FILE, because it is narrower than it
    first looks: fold() and embed() emit only handler BLOCKS, so a header
    changelog sits in the preamble and is dropped - it never gets here. What
    does get here is a /* */ written INSIDE a handler body, which ships
    verbatim like every other comment. A column-0 line of prose in one is
    then a phantom handler to checks 1 and 4, and a phantom `local` below the
    first handler to check 10 - a gate failure describing a declaration that
    is not there. Defensive, therefore, rather than load-bearing today; the
    load-bearing half is that the two tools must read a source IDENTICALLY,
    or the generator writes a file this gate refuses.
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
        raise SystemExit(
            "check-suite-selftest: an unterminated /* block comment runs to the "
            "end of tests/suite-selftest.livecodescript. Blanking it would hide "
            "every handler below it from these checks.")
    return "\n".join(out)


def declaration_names(line):
    """The names ONE `local`/`constant` line declares, string literals removed
    BEFORE the comma split.

    The generator's twin carries the full reasoning. The short version: a
    comma separates declarations AND sits inside strings, so
    `constant kKatL2Perm1 = "35,31,39,12"` would inject 31, 39 and 12 as
    declared names - check 1b then reports a wall of phantom duplicate
    declarations for any two KAT constants that merely share a value, and
    check 2's `declared` set silently ABSORBS real names that appear in such a
    string, which is the direction that hides a defect rather than inventing
    one.
    """
    names = []
    for part in re.sub(r'"[^"]*"', '""', line).split(","):
        part = part.split("=")[0].strip()
        if re.fullmatch(r'\w+', part):
            names.append(part)
    return names


def main(argv):
    if not os.path.exists(GEN):
        print("check-suite-selftest: tests/suite-selftest.livecodescript is missing")
        return 1
    src = open(GEN, encoding="utf-8").read()
    bare = strip_comments(src)
    problems = []

    # ---- 1. no duplicate handler names (this one IS a compile error) --------
    defs = re.findall(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', bare, re.M)
    seen, dups = set(), set()
    for n in defs:
        (dups if n.lower() in seen else seen).add(n.lower())
    if dups:
        problems.append("duplicate handler names (the script will not compile): "
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
        problems.append("duplicate script-level declarations (two units would "
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
        problems.append(
            "script-level names used but never declared - LiveCodeScript would "
            "evaluate each as the literal text of its own name, so these would "
            "produce plausible-looking FAILs rather than an error: "
            + ", ".join(undeclared[:12])
            + (f" (+{len(undeclared) - 12} more)" if len(undeclared) > 12 else ""))

    # ---- 3. the core's integration surface still exists ---------------------
    lower = {n.lower() for n in defs}
    for entry in ENTRY_POINTS:
        if entry.lower() not in lower:
            problems.append(f"the core calls {entry}, which is not defined")
    for pfx in COUNTED:
        for suffix in ("sResultText", "sPassed", "sFailed", "sTotal"):
            if pfx + suffix not in declared:
                problems.append(f"the core reads {pfx}{suffix}, which is not declared")

    # ---- 4. every folded harness is actually present and non-trivial -------
    for pfx, member in PREFIXES.items():
        n = len([d for d in defs if d.startswith(pfx)])
        if n < 5:
            problems.append(f"{member} folded in only {n} handlers under `{pfx}` - "
                            f"the fold silently dropped almost everything")

    # ---- 5. the async cuts held ---------------------------------------------
    # enetxt and datachannelxt must NOT bring their async loopbacks in: two
    # state machines in one process race for the event handlers.
    for pfx, member in (("en1", "enetxt"), ("dc1", "datachannelxt")):
        body = re.search(r'^command ' + pfx + r'stRun\b(.*?)^end ' + pfx + r'stRun',
                         src, re.S | re.M)
        if body is None:
            problems.append(f"{member}: no {pfx}stRun to check the async cut in")
            continue
        if "GENERATED CUT" not in body.group(1):
            problems.append(f"{member}: {pfx}stRun has no generated cut marker, so "
                            f"its async loopback may have been folded in")
        if re.search(r'send\s+"', body.group(1)):
            problems.append(f"{member}: {pfx}stRun still arms a timer, so the async "
                            f"half was folded in and will race the core's loopback")

    # ---- 6. torrentxt reuses the core's single session ----------------------
    if "put sSession into bt1sSession" not in src:
        problems.append("torrentxt does not reuse the core's session; it would open a "
                        "second one, fail, and skip its entire surface while looking green")

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
    for h, what in (("en1stCleanup", "enDeinitialize"), ("dc1stCleanup", "dcCleanup"),
                    ("bt1stCleanup", "btStopSession on the core's own session handle")):
        callers = [ln.strip() for ln in src.split("\n")
                   if re.match(r'^\s*' + h + r'\b', ln)
                   and not re.match(r'^\s*(command|end)\b', ln.strip())]
        if callers:
            problems.append(f"{h} is called ({callers[0]!r}), but it runs {what}, which "
                            f"would tear down the transport the core's own loopback is "
                            f"using. It must stay unreachable.")

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
            problems.append(f"the harness still carries box2dxt's own embedded-Kit "
                            f"sentinel ({sentinel!r}), so the fold brought a SECOND "
                            f"copy of the Kit in alongside the embedded layer")
    if len([d for d in defs if d.lower() == "b2ksteponce"]) != 1:
        problems.append("b2kStepOnce is not defined exactly once - the b2k Kit is "
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
            problems.append(f"{receiver} is not defined at its real name - the fold "
                            f"prefixed a message receiver the embedded Kit dispatches "
                            f"by literal name, so those events will never arrive")
        if re.search(r'\bb21' + receiver + r'\b', src):
            problems.append(f"b21{receiver} exists - the fold renamed a message "
                            f"receiver the embedded Kit dispatches by literal name")

    # ---- 7c. box2dxt's own window did not come with it -----------------------
    # It hangs its window off the CARD hooks and a builder of its own, so
    # DROP_HANDLERS' openStack/closeStack set does not cover it. Left in, `on
    # openCard` would rebuild an 860x640 window over the suite's the moment this
    # stack's card opened.
    for gone in ("b21buildStUI", "b21openCard", "b21closeCard"):
        if re.search(r'^(?:command|on|function)\s+' + gone + r'\b', src, re.M):
            problems.append(f"{gone} survived the fold; box2dxt's own window would "
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
        problems.append("holde-em folded in no he1* handlers at all - this whole "
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
                problems.append(
                    f"{name} is named in this gate's forbidden set but is not "
                    f"defined in the folded harness at all. Either it was "
                    f"renamed - in which case this entry now guards nothing and "
                    f"must be updated to the new name - or it is gone and the "
                    f"entry should be deleted. A hazard list that outlives its "
                    f"hazards is worse than no list.")
        for name, why in forbidden.items():
            if name.lower() in reach:
                problems.append(
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
                            problems.append(
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
                problems.append(
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
            problems.append("he1heTestSweepNetTimers is gone; nothing cancels the "
                            "timers holde-em's sections arm, so its next-hand beat "
                            "fires into the core's async loopback phase")
        elif 'begins with "he1"' not in sweep.group(1):
            problems.append(
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
            problems.append(f"{gone} survived the fold; holde-em's own stack "
                            f"chrome would run on the suite's window")

    # ---- 8. coinxt is probed as TWO pieces ----------------------------------
    # It is the only member that ships an extension AND a separate script layer,
    # and ten of its folded sections call the script. Probing only the extension
    # makes a missing `start using stack "coinxt"` look like ten library defects
    # instead of one setup step - the most expensive possible way to spend an
    # engine session. Both probes, and a guard that SKIPS rather than runs.
    if "sHaveCoinScript" not in src:
        problems.append("the harness does not probe coinxt's SCRIPT layer separately; a "
                        "missing `start using stack \"coinxt\"` would report as ten FAILs "
                        "rather than one skip")
    elif "sHaveCoin and sHaveCoinScript" not in src:
        problems.append("coinxt's deep harness is not guarded on BOTH sHaveCoin and "
                        "sHaveCoinScript, so it would run its script-layer sections "
                        "against handlers that are not loaded")

    # ---- 9. nothing from a member's own window survived --------------------
    for bad in ("bt1stShow", "bt1stPaint", "cx1stShow", "cx1stPaint",
                "en1stShow", "en1stPaint", "dc1stShow", "dc1stPaint"):
        m = re.search(r'^command ' + bad + r'\b(.*?)^end ' + bad, src, re.S | re.M)
        if m and m.group(1).strip():
            problems.append(f"{bad} should be a no-op stub (the core owns the UI) "
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
        problems.append("no handlers found at all - the generated file is not "
                        "what this checker thinks it is")
    else:
        late = [(i, lines_raw[i - 1].strip())
                for i, line in enumerate(lines_bare, start=1)
                if i > first_handler and re.match(r'^(?:local|constant)\s', line)]
        if late:
            problems.append(
                f"{len(late)} script-level declaration(s) appear BELOW the first "
                f"handler (line {first_handler}), so any handler above them reads "
                f"an undeclared name - which LiveCodeScript silently evaluates to "
                f"the literal text of that name:\n      "
                + "\n      ".join(f"line {i}: {t}" for i, t in late[:6])
                + ("\n      ..." if len(late) > 6 else ""))

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
                problems.append(f"line {i}: embed sentinel end '{m.group(1)}' has "
                                f"no matching begin")
            else:
                stack.pop()
            continue
        if stack:
            span_lines[stack[-1]].append(line)
    for name in stack:
        problems.append(f"embed sentinel begin '{name}' never ends")
    for want in ("coinxt script layer", "onionxt script layer",
                 "riptide script layer", "box2dxt-kit script layer",
                 "nostrxt script layer"):
        if want not in seen_spans:
            problems.append(f"no embedded span '{want}' - the harness no longer "
                            f"carries that library, so its folded tests run "
                            f"against whatever stale copy the engine has loaded")
        elif len(span_lines.get(want, [])) < 500:
            problems.append(f"embedded span '{want}' is only "
                            f"{len(span_lines.get(want, []))} lines - a fragment, "
                            f"not the library")

    # ---- 12. the embedded layers' script-level names are declared -----------
    # Check 2 protects the FOLDED harnesses by their prefixes; the embedded
    # libraries are unprefixed, so their s*/k* names need the same proof: a
    # declaration the generator's hoist missed would not error, it would
    # evaluate to the literal text of its own name inside a LIBRARY handler -
    # a wrong address or a dead socket state machine, not a red test line.
    embedded_bare = strip_comments("\n".join(
        "\n".join(lines) for lines in span_lines.values()))
    embedded_used = set(re.findall(r'\b([sk][A-Z]\w*)\b', embedded_bare))
    handler_names_exact = set(defs)
    undeclared_embed = sorted(
        n for n in embedded_used
        if n not in declared and n not in handler_names_exact)
    if undeclared_embed:
        problems.append(
            "embedded-layer script-level names used but never declared (the "
            "generator's declaration hoist missed them): "
            + ", ".join(undeclared_embed[:12])
            + (f" (+{len(undeclared_embed) - 12} more)"
               if len(undeclared_embed) > 12 else ""))

    if problems:
        print("check-suite-selftest: FAILED")
        for p in problems:
            print("  - " + p)
        return 1
    counts = {pfx: len([d for d in defs if d.startswith(pfx)]) for pfx in PREFIXES}
    print(f"check-suite-selftest: OK ({len(defs)} handlers, no collisions, "
          f"all declarations present; folded: "
          + ", ".join(f"{PREFIXES[p]}={c}" for p, c in counts.items()) + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
