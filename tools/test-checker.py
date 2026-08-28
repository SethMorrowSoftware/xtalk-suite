#!/usr/bin/env python3
"""test-checker.py - fixture tests for every member's check-livecodescript.py.

The family's CLAUDE.md files have long CLAIMED the checker copies were "tested
against the bug, all three legal forms, and a .lcb" - and no such test was
ever committed, which is exactly the unbacked-attestation shape the root
lesson book warns about ("shipped is not run"). This file makes the claim
true and keeps it true: every rule in the unified checker is exercised here
with a fixture that must FIRE and a neighbouring fixture that must NOT, and
the suite gate runs it on every push.

It runs the fixtures against EVERY member's copy, not a chosen one: the copies
are byte-identical (tools/check-checker-drift.py enforces that), so this is
cheap, and it means a member's copy is proven in the form the member actually
ships it.

    python3 tools/test-checker.py

Exit code 0 = every fixture behaved, 1 = a rule regressed somewhere.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEMBERS = ["sodiumxt", "torrentxt", "enetxt", "datachannelxt",
           "onionxt", "coinxt", "riptide", "nocloud", "box2dxt",
           "holde-em", "nostrxt"]

# (name, filename, source, must_contain) - must_contain None means the file
# must pass CLEAN; otherwise the checker must fail AND its output must contain
# the substring.
FIXTURES = [
    # -- rule 22: one name declared twice inside ONE handler ------------------
    # Added 2026-08-28, the day this repo's own tooling shipped one: a tidy-up
    # moved a declaration to the top of a handler in
    # tools/engine-probe.livecodescript and left the original in place, and
    # nothing caught it - rule 3 is .lcb only by deliberate measurement and
    # tools/check-duplicate-declarations.py is script-level by design. The third
    # and fourth fixtures are what make the rule mean anything: the same name in
    # a DIFFERENT handler is ordinary and must stay quiet, and mid-handler
    # `local` (legal LiveCodeScript, ~150 sites in engine-passed files) must not
    # be flagged merely for being mid-handler.
    ("duplicate local in one handler fires",
     "t.livecodescript",
     'on r22Handler\n   local tA, tB\n   put 1 into tA\n   local tB\n'
     '   put 2 into tB\nend r22Handler\n',
     "re-declares a name already declared"),
    ("a local re-declaring a PARAMETER fires",
     "t.livecodescript",
     'on r22Shadow pValue\n   local pValue\n   put 1 into pValue\n'
     'end r22Shadow\n',
     "already declared as a parameter"),
    ("the same name in a DIFFERENT handler is legal",
     "t.livecodescript",
     'on r22One\n   local tB\n   put 1 into tB\nend r22One\n\n'
     'on r22Two\n   local tB\n   put 2 into tB\nend r22Two\n',
     None),
    ("a mid-handler local that is NOT a duplicate is legal",
     "t.livecodescript",
     'on r22Mid\n   local tA\n   put 1 into tA\n   local tB\n'
     '   put 2 into tB\nend r22Mid\n',
     None),
    ("duplicate variable in one .lcb handler fires",
     "t.lcb",
     'library com.example.r22\n\npublic handler R22(in pX as Integer) returns Integer\n'
     '   variable tA as Integer\n   variable tA as Integer\n   put pX into tA\n'
     '   return tA\nend handler\n\nend library\n',
     "re-declares a name already declared"),
    # -- the zero-arg statement-call gate (the dcCleanup() engine failure) ----
    ("zero-arg call in statement position fires",
     "t.livecodescript",
     'on mouseUp\n   dcCleanup()\nend mouseUp\n',
     "zero-argument call"),
    ("bare zero-arg command is legal",
     "t.livecodescript",
     'on mouseUp\n   dcCleanup\nend mouseUp\n',
     None),
    ("one-argument call in statement position is legal",
     "t.livecodescript",
     'on mouseUp\n   dcFreePeer(sPeerA)\nend mouseUp\n',
     None),
    ("zero-arg call in EXPRESSION position is legal",
     "t.livecodescript",
     'on mouseUp\n   if dcCleanup() is 0 then\n      put 1 into tX\n   end if\nend mouseUp\n',
     None),
    ("LCB allows a zero-arg statement call",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   sPrepare()\nend handler\n\nend library\n',
     None),

    # -- switch (the sodiumxt-lineage gap that started the unification) ------
    ("switch/end switch balances in LCS",
     "t.livecodescript",
     'on tDispatch pKind\n   switch pKind\n      case "a"\n         put 1 into tX\n         break\n      default\n         break\n   end switch\nend tDispatch\n',
     None),
    ("end switch in a .lcb is refused (LCB has no switch)",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   end switch\nend handler\n\nend library\n',
     "unexpected `end switch`"),

    # -- constant declaration dialect (the carried-`is` slip, 2026-08-13) ----
    ("LCS refuses the Builder constant spelling (is)",
     "t.livecodescript",
     'constant kFoo is 1\non tGo\n   put kFoo into tX\nend tGo\n',
     "BUILDER spelling"),
    ("LCS accepts its own constant spelling (=)",
     "t.livecodescript",
     'constant kFoo = 1\non tGo\n   put kFoo into tX\nend tGo\n',
     None),
    ("LCB refuses the Script constant spelling (=)",
     "t.lcb",
     'library org.test.t\n\nconstant kFoo = 1\n\npublic handler tGo()\n   variable tX as Integer\n   put kFoo into tX\nend handler\n\nend library\n',
     "SCRIPT spelling"),
    ("LCB accepts its own constant spelling (is)",
     "t.lcb",
     'library org.test.t\n\nconstant kFoo is 1\n\npublic handler tGo()\n   variable tX as Integer\n   put kFoo into tX\nend handler\n\nend library\n',
     None),

    # -- `the number of keys of` (2026-08-18, enet-lan-chat's dashboard) -----
    # The engine reads `keys of X` as an OBJECT expression, so this raises
    # "Chunk: error in object expression" rather than counting anything.
    ("the number of keys of X is refused",
     "t.livecodescript",
     'on tGo\n   put the number of keys of sPeers into tN\nend tGo\n',
     "not a chunk"),
    ("the number of LINES of the keys of X is accepted (the proven idiom)",
     "t.livecodescript",
     'on tGo\n   put the number of lines of the keys of sPeers into tN\nend tGo\n',
     None),

    # -- engine-hostile constructs -------------------------------------------
    ("throw inside catch fires",
     "t.livecodescript",
     'on tGo\n   try\n      put 1 into tX\n   catch tErr\n      throw tErr\n   end try\nend tGo\n',
     "throw"),
    ("return inside catch is legal (engine-proven)",
     "t.livecodescript",
     'function tGo\n   try\n      put 1 into tX\n   catch tErr\n      return false\n   end try\n   return true\nend tGo\n',
     None),
    # tErr is declared here because the catch BODY references it - the
    # catch-variable rule (check 15) would rightly fire otherwise
    ("throw AFTER end try is legal",
     "t.livecodescript",
     'on tGo\n   local tKeep, tErr\n   try\n      put 1 into tX\n   catch tErr\n      put tErr into tKeep\n   end try\n   if tKeep is not empty then\n      throw tKeep\n   end if\nend tGo\n',
     None),
    ("repeat with ... step fires",
     "t.livecodescript",
     'on tGo\n   repeat with tI = 1 to 10 step 2\n      put tI into tX\n   end repeat\nend tGo\n',
     "step"),

    # -- ASCII discipline ------------------------------------------------
    ("a smart quote fires",
     "t.livecodescript",
     'on tGo\n   -- don’t\nend tGo\n',
     "curly quote"),
    ("an em dash fires",
     "t.livecodescript",
     'on tGo\n   -- a — b\nend tGo\n',
     "em dash"),
    ("generic non-ASCII fires",
     "t.livecodescript",
     'on tGo\n   -- café\nend tGo\n',
     "non-ASCII"),

    # -- lexer-level ---------------------------------------------------------
    ("an unterminated string fires",
     "t.livecodescript",
     'on tGo\n   put "oops into tX\nend tGo\n',
     "unterminated string"),
    ("an unterminated block comment fires",
     "t.lcb",
     'library org.test.t\n\n/* never closed\n\nend library\n',
     "unterminated /*"),

    # -- constants before use, both spellings --------------------------------
    ("LCS constant used above its declaration fires",
     "t.livecodescript",
     'function tGo\n   return kLate\nend tGo\n\nconstant kLate = "x"\n',
     "before its declaration"),
    ("LCS constant declared first is legal",
     "t.livecodescript",
     'constant kEarly = "x"\n\nfunction tGo\n   return kEarly\nend tGo\n',
     None),
    ("LCB constant used above its declaration fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo() returns String\n   return kLate\nend handler\n\nconstant kLate is "x"\n\nend library\n',
     "before its declaration"),

    # -- the prefixed-token-shadow trap ---------------------------------------
    ("tExt fires (spells `text`)",
     "t.livecodescript",
     'on tGo\n   put 1 into tExt\nend tGo\n',
     "reserved token"),
    ("tOp fires (spells `top`)",
     "t.livecodescript",
     'on tGo\n   put 1 into tOp\nend tGo\n',
     "reserved token"),
    ("tItle fires (spells `title`; a union-set token)",
     "t.livecodescript",
     'on tGo\n   put 1 into tItle\nend tGo\n',
     "reserved token"),
    ("sEnd fires (spells `send`; a union-set token)",
     "t.livecodescript",
     'on tGo\n   put 1 into sEnd\nend tGo\n',
     "reserved token"),
    ("tSuffix is a legal name",
     "t.livecodescript",
     'on tGo\n   put 1 into tSuffix\nend tGo\n',
     None),

    # -- does-not operator -----------------------------------------------------
    ("`does not contain` fires",
     "t.livecodescript",
     'on tGo\n   if tX does not contain "y" then\n      put 1 into tZ\n   end if\nend tGo\n',
     "does not begin/end"),

    # -- put prepositions -------------------------------------------------------
    ("`put X into Y after Y` fires",
     "t.livecodescript",
     'on tGo\n   put tX into tY after tY\nend tGo\n',
     "into` and `after"),
    ("a literal `after` inside a string is legal",
     "t.livecodescript",
     'on tGo\n   put "into the after" into tY\nend tGo\n',
     None),

    # -- LCB declarations at top -------------------------------------------------
    ("LCB variable below the first statement fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   variable tA as Number\n   put 1 into tA\n   variable tB as Number\nend handler\n\nend library\n',
     "TOP of the handler"),
    ("LCB variables at the top are legal",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   variable tA as Number\n   variable tB as Number\n   put 1 into tA\nend handler\n\nend library\n',
     None),

    # -- LCB module closure + imports + antipatterns + lowercase names -----------
    ("an unclosed library fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   put 1 into tA\nend handler\n',
     "never closed"),
    ("a foreign type without the foreign use fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo(in pBuf as Pointer)\n   put 1 into tA\nend handler\n\nend library\n',
     "com.livecode.foreign"),
    ("textEncode in a .lcb fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   put textEncode("x", "UTF-8") into tA\nend handler\n\nend library\n',
     "LiveCode Script function"),
    ("`the empty list` in a .lcb fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   put the empty list into tA\nend handler\n\nend library\n',
     "empty list"),
    ("an all-lowercase variable name fires",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo()\n   variable counter as Number\nend handler\n\nend library\n',
     "all-lowercase"),

    # -- LCS antipatterns ---------------------------------------------------------
    ("braces in LCS fire",
     "t.livecodescript",
     'on tGo\n   put {} into tA\nend tGo\n',
     "braces"),
    ("subscripting a function result fires",
     "t.livecodescript",
     'on tGo\n   put tFetch(1)["k"] into tA\nend tGo\n',
     "subscript a function result"),
    ("braces inside a string literal are legal",
     "t.livecodescript",
     'on tGo\n   put "function() { return 1; }" into tJs\nend tGo\n',
     None),

    # -- block balance, incl. the continuation-merged if header -------------------
    ("a wrapped if header still opens a block (continuation merge)",
     "t.livecodescript",
     'on tGo\n   if tA is 1 and \\\n         tB is 2 then\n      put 1 into tC\n   end if\nend tGo\n',
     None),
    ("a wrapped if header missing its end if fires",
     "t.livecodescript",
     'on tGo\n   if tA is 1 and \\\n         tB is 2 then\n      put 1 into tC\nend tGo\n',
     "never closed"),
    ("`end repeat` closing an if fires",
     "t.livecodescript",
     'on tGo\n   if tA is 1 then\n      put 1 into tC\n   end repeat\nend tGo\n',
     "does not match"),
    ("a # comment is a comment in LCS",
     "t.livecodescript",
     'on tGo\n   # if tA is 1 then\n   put 1 into tC\nend tGo\n',
     None),

    # -- the hold-em lineage checks (13-21), absorbed 2026-08-15 ---------------

    # check 13: bitwise operator written as a two-argument function call
    ("bitXor(a, b) function-call form fires",
     "t.livecodescript",
     'on tGo\n   put bitXor(tA, tB) into tC\nend tGo\n',
     "bitwise OPERATOR"),
    ("the bitwise operator form is legal",
     "t.livecodescript",
     'on tGo\n   put tA bitXor tB into tC\nend tGo\n',
     None),
    ("an operator with a parenthesised right operand is legal",
     "t.livecodescript",
     'on tGo\n   put tBits bitOr (tL) into tBits\nend tGo\n',
     None),
    ("unary bitNot inside an operand paren is legal (the Kit's mask clear)",
     "t.livecodescript",
     'on tGo\n   put tM bitAnd (bitNot 255) into tM\nend tGo\n',
     None),

    # check 14: a declared name that IS an engine token
    ("local tAb fires (IS the tab constant)",
     "t.livecodescript",
     'on tGo\n   local tAb\n   put 1 into tAb\nend tGo\n',
     "IS the engine token"),
    ("a parameter named cr fires (a hold-em-set token)",
     "t.livecodescript",
     'on tGo pStuff, cr\n   put 1 into tX\nend tGo\n',
     "IS the engine token"),
    ("a distinctive declared stem is legal",
     "t.livecodescript",
     'on tGo pKind\n   local tWorkA\n   put 1 into tWorkA\nend tGo\n',
     None),

    # check 15: an undeclared catch variable that the catch body references
    ("a referenced undeclared catch variable fires",
     "t.livecodescript",
     'on tGo\n   try\n      put 1 into tX\n   catch tBoom\n      put tBoom into tX\n   end try\nend tGo\n',
     "catch variable"),
    ("a declared catch variable is legal",
     "t.livecodescript",
     'on tGo\n   local tBoom\n   try\n      put 1 into tX\n   catch tBoom\n      put tBoom into tX\n   end try\nend tGo\n',
     None),
    ("an UNreferenced undeclared catch variable is legal (engine-proven)",
     "t.livecodescript",
     'function tGo\n   try\n      put 1 into tX\n   catch tBoom\n      return false\n   end try\n   return true\nend tGo\n',
     None),
    ("a script-level local satisfies the catch declaration",
     "t.livecodescript",
     'local sErr\n\non tGo\n   try\n      put 1 into tX\n   catch sErr\n      put sErr into tX\n   end try\nend tGo\n',
     None),

    # check 16: a locally-declared command called with () in expression position
    ("a command called as a function inside an expression fires",
     "t.livecodescript",
     'command tDoThing pA\n   put 1 into tX\nend tDoThing\n\non tGo\n   put tDoThing(1) into tY\nend tGo\n',
     "function-call syntax"),
    ("a command statement with a parenthesised first argument is legal",
     "t.livecodescript",
     'command tDoThing pA, pB\n   put 1 into tX\nend tDoThing\n\non tGo\n   tDoThing (tA), tB\nend tGo\n',
     None),
    ("a declared FUNCTION called with parens is legal",
     "t.livecodescript",
     'function tCalc pA\n   return pA + 1\nend tCalc\n\non tGo\n   put tCalc(1) into tY\nend tGo\n',
     None),

    # check 17: parenthesised dynamic property names
    ("`the (expr) of` fires",
     "t.livecodescript",
     'on tGo\n   set the ("uSeat" & 3) of me to 1\nend tGo\n',
     "dynamic property"),
    ("an ordinary property read is legal",
     "t.livecodescript",
     'on tGo\n   put the label of me into tX\nend tGo\n',
     None),
    ("`the (` inside a string literal is legal",
     "t.livecodescript",
     'on tGo\n   put "see the (docs) here" into tX\nend tGo\n',
     None),

    # check 18: `the message box` as a container
    ("`put ... into the message box` fires",
     "t.livecodescript",
     'on tGo\n   put tRpt into the message box\nend tGo\n',
     "container token is"),
    ("the msg container token is legal",
     "t.livecodescript",
     'on tGo\n   put tRpt into msg\nend tGo\n',
     None),
    ("`the message box` in a comment is legal",
     "t.livecodescript",
     'on tGo\n   -- run heRunSelftest in the message box\n   put 1 into tX\nend tGo\n',
     None),

    # check 19: a k-constant used but never declared
    ("a never-declared k-constant fires",
     "t.livecodescript",
     'on tGo\n   put kMissing into tX\nend tGo\n',
     "never declared"),
    ("a declared k-constant is legal",
     "t.livecodescript",
     'constant kPresent = 1\n\non tGo\n   put kPresent into tX\nend tGo\n',
     None),
    ("a comma-separated multi-constant declaration declares every name",
     "t.livecodescript",
     'constant kA1 = 1, kB2 = 2\n\non tGo\n   put kB2 into tX\nend tGo\n',
     None),

    # check 20: the dangling else
    ("a bare else after a single-line if fires",
     "t.livecodescript",
     'on tGo\n   if tA is 1 then put 2 into tB\n   else\n      put 3 into tB\n   end if\nend tGo\n',
     "bare `else`"),
    ("a bare else under a block if is legal",
     "t.livecodescript",
     'on tGo\n   if tA is 1 then\n      put 2 into tB\n   else\n      put 3 into tB\n   end if\nend tGo\n',
     None),
    ("an else carrying its statement is legal",
     "t.livecodescript",
     'on tGo\n   if tA is 1 then put 2 into tB\n   else put 3 into tB\nend tGo\n',
     None),

    # check 21: a backslash outside every string (the no-escapes rule)
    ("a C-style escaped quote fires",
     "t.livecodescript",
     'on tGo\n   put "say \\"hi\\" now" into tX\nend tGo\n',
     "backslash outside a string"),
    ("a one-backslash string literal is legal (path normalisation)",
     "t.livecodescript",
     'on tGo\n   replace "\\" with "/" in tPath\nend tGo\n',
     None),
]


def run_one(checker, workdir, name, filename, source, must_contain):
    path = os.path.join(workdir, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(source)
    proc = subprocess.run([sys.executable, checker, path],
                          capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    if must_contain is None:
        if proc.returncode != 0:
            return "expected CLEAN, got:\n%s" % out.strip()
        return None
    if proc.returncode == 0:
        return "expected a finding containing %r, got a clean pass" % must_contain
    if must_contain not in out:
        return ("expected the output to contain %r, got:\n%s"
                % (must_contain, out.strip()))
    return None


def main():
    failures = 0
    total = 0
    with tempfile.TemporaryDirectory() as workdir:
        for member in MEMBERS:
            checker = os.path.join(ROOT, member, "tools",
                                   "check-livecodescript.py")
            if not os.path.exists(checker):
                print("test-checker: MISSING %s" % checker)
                failures += 1
                continue
            for name, filename, source, must in FIXTURES:
                total += 1
                err = run_one(checker, workdir, name, filename, source, must)
                if err:
                    failures += 1
                    print("test-checker: FAIL [%s] %s\n  %s"
                          % (member, name, err.replace("\n", "\n  ")))
    if failures:
        print("test-checker: %d FAILURE(S) of %d fixture run(s)"
              % (failures, total))
        return 1
    print("test-checker: OK (%d fixtures x %d member copies = %d runs)"
          % (len(FIXTURES), len(MEMBERS), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
