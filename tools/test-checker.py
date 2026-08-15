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
           "holde-em"]

# (name, filename, source, must_contain) - must_contain None means the file
# must pass CLEAN; otherwise the checker must fail AND its output must contain
# the substring.
FIXTURES = [
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

    # -- engine-hostile constructs -------------------------------------------
    ("throw inside catch fires",
     "t.livecodescript",
     'on tGo\n   try\n      put 1 into tX\n   catch tErr\n      throw tErr\n   end try\nend tGo\n',
     "throw"),
    ("return inside catch is legal (engine-proven)",
     "t.livecodescript",
     'function tGo\n   try\n      put 1 into tX\n   catch tErr\n      return false\n   end try\n   return true\nend tGo\n',
     None),
    ("throw AFTER end try is legal",
     "t.livecodescript",
     'on tGo\n   local tKeep\n   try\n      put 1 into tX\n   catch tErr\n      put tErr into tKeep\n   end try\n   if tKeep is not empty then\n      throw tKeep\n   end if\nend tGo\n',
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
