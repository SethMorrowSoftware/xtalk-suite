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
            "rs1": "riptide"}

# What the core calls into each folded harness. If the generator ever renames or
# drops one of these, the suite harness compiles and then does nothing.
ENTRY_POINTS = ["sx1sxSelfTest", "ox1oxSelfTest", "cx1stRun", "bt1stRun",
                "en1stRun", "dc1stRun", "rs1rsSelfTest"]
COUNTED = ["cx1", "bt1", "en1", "dc1"]


def strip_comments(text):
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
        for part in line.split(","):
            part = part.split("=")[0].strip()
            if re.fullmatch(r'\w+', part):
                decl_names.append(part)
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
        for part in line.split(","):
            part = part.split("=")[0].strip()
            if re.fullmatch(r'\w+', part):
                declared.add(part)
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
    for bad in ("bt1stPaint", "cx1stShow", "en1stShow", "dc1stShow"):
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
    first_handler = None
    for i, line in enumerate(src.split("\n"), start=1):
        if re.match(r'^(?:private\s+)?(?:command|function|on)\s+\w+', line):
            first_handler = i
            break
    if first_handler is None:
        problems.append("no handlers found at all - the generated file is not "
                        "what this checker thinks it is")
    else:
        late = [(i, line.strip())
                for i, line in enumerate(src.split("\n"), start=1)
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
                 "riptide script layer"):
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
