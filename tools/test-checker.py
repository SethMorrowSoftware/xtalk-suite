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
ships it. Each copy reads every fixture in ONE run (each fixture its own
file, its verdict read from the lines naming that file, the run required to
end in the summary line for exactly that many files).

Check 23's fixtures include the comparisons the 2026-09-25 hex fixes replaced
(MUST refuse) and the lines that replaced them (MUST pass), generated from
git; see FIX_COMMITS below.

    python3 tools/test-checker.py                    # every member's copy
    python3 tools/test-checker.py --checker PATH     # one file (a mutant)
    python3 tools/test-checker.py --print-history    # regenerate FIX_*_LINES

Exit code 0 = every fixture behaved, 1 = a rule regressed somewhere.
"""
import os
import re
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

    # -- constant VALUES must be literals (check 22) -------------------------
    # The bug this is standing in for shipped in riptide-social and took the
    # WHOLE stack script down - a .livecodescript is one compilation unit, so
    # the symptom was a stack that opened with no UI and no error to point at,
    # found by opening it rather than by any gate. The legal fixtures matter
    # as much as the firing one: the multi-declaration form is real, and
    # box2dxt's builder writes it with commas INSIDE quoted colour values.
    ("LCS constant with a concatenation value fires",
     "t.livecodescript",
     'constant kX = "a" & return & "b"\n\non tGo\n   put kX into tY\nend tGo\n',
     "non-literal value"),
    ("LCS constant with an arithmetic value fires",
     "t.livecodescript",
     'constant kX = 60 * 1000\n\non tGo\n   put kX into tY\nend tGo\n',
     "non-literal value"),
    ("LCS constant naming another constant fires",
     "t.livecodescript",
     'constant kA = 1\nconstant kB = kA\n\non tGo\n   put kB into tY\nend tGo\n',
     "non-literal value"),
    ("LCS string, integer, negative and decimal constants are legal",
     "t.livecodescript",
     'constant kS = "hi"\nconstant kI = 200\nconstant kN = -10\n'
     'constant kD = 0.05\n\non tGo\n   put kS & kI & kN & kD into tY\nend tGo\n',
     None),
    ("LCS multi-declaration constants are legal",
     "t.livecodescript",
     'constant kA = 1500, kB = 320\n\non tGo\n   put kA + kB into tY\nend tGo\n',
     None),
    ("LCS a comma INSIDE a quoted constant value is not a split",
     "t.livecodescript",
     'constant kCol = "26,28,35", kCol2 = "44,48,58"\n\n'
     'on tGo\n   put kCol && kCol2 into tY\nend tGo\n',
     None),
    ("LCB constant values are NOT checked (its own dialect, `is`)",
     "t.lcb",
     'library org.test.t\n\nconstant kX is 1\n\npublic handler tGo() returns '
     'Integer\n   return kX\nend handler\n\nend library\n',
     None),

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

    # check 23: a hex-shaped operand meets a bare comparison (engine note
    # 2.11). The 2026-09-25 fixes' own OLD and NEW lines are fixtures too,
    # generated from git below (FIX_OLD_LINES / FIX_NEW_LINES); these pin
    # each shape and each exclusion on its own.
    ("two hex-named operands under bare `is` fire",
     "t.livecodescript",
     'on tGo\n   if tOurHash is sTheirHash then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("ONE hex-named operand against a plain-named one fires",
     "t.livecodescript",
     'on tGo\n   if tA["from"] is not pFromPubHex then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("a call ending in Hex against an element by index fires",
     "t.livecodescript",
     'on tGo\n   if heSeedCommitHex(tSeed) is not pCommitsA[tPos] then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("an element by index of a Hex-named array fires",
     "t.livecodescript",
     'on tGo\n   if pSeedsHexA[tI] is tOther then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("a literal key naming a token fires (quickshare's edit gate)",
     "t.livecodescript",
     'function tGo pRequest\n   return (pRequest["x-edit-token"] is sEditSession)\nend tGo\n',
     "meets a bare"),
    ("`=` between two nonces fires",
     "t.livecodescript",
     'on tGo\n   if tNonce = sNonce then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("`<>` between two txids fires",
     "t.livecodescript",
     'on tGo\n   if tTxid <> pTxid then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("ordering two txids fires (the number path orders some pairs as numbers)",
     "t.livecodescript",
     'function tGo pA, pB\n   if pA["txid"] < pB["txid"] then\n      return true\n   end if\n   return false\nend tGo\n',
     "meets a bare"),
    ("a chunk of a hex value fires",
     "t.livecodescript",
     'on tGo\n   if char 1 to 8 of tHex is sPrefix then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("toLower of a hex value fires (case is not the number path)",
     "t.livecodescript",
     'on tGo\n   if toLower(tHash) is toLower(pWant) then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("an EMPTY-literal concatenation is still bare",
     "t.livecodescript",
     'on tGo\n   if ("" & tTok) is ("" & sTok) then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("a DIGIT prefix is still bare (\"0\" & a number-like text is number-like)",
     "t.livecodescript",
     'on tGo\n   if ("0" & tHex) is ("0" & sHex) then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("a command statement's first argument fires (the command name is not the operand)",
     "t.livecodescript",
     'on tGo\n   nxtCheck tDigest is tWant, "the digest"\nend tGo\n',
     "meets a bare"),
    ("a continuation-merged comparison fires",
     "t.livecodescript",
     'on tGo\n   if tQ is 1 or \\\n         tHeadHex is not sHeadHex then\n      put 1 into tX\n   end if\nend tGo\n',
     "meets a bare"),
    ("a letter prefix on both sides is legal (the 2026-09-25 fix)",
     "t.livecodescript",
     'on tGo\n   if ("t" & tTok) is not ("t" & sCwToken) then\n      put 1 into tX\n   end if\nend tGo\n',
     None),
    ("a helper carrying the comparison is legal",
     "t.livecodescript",
     'on tGo\n   if not heHexEq(tA["from"], pFromPubHex) and stSameHex(stHex(tA), stHex(tB)) then\n      put 1 into tX\n   end if\n   if cxCompareBytes(tOurHash, tTheirHash) is 0 then\n      put 2 into tX\n   end if\nend tGo\n',
     None),
    ("empty on one side is legal",
     "t.livecodescript",
     'on tGo\n   if pFromPubHex is not empty and tHex is empty then\n      put 1 into tX\n   end if\nend tGo\n',
     None),
    ("a string or number literal on one side is legal",
     "t.livecodescript",
     'on tGo\n   if tHex is "abc" or tNonce is 0 or tNonce is -1 then\n      put 1 into tX\n   end if\nend tGo\n',
     None),
    ("a declared constant is a literal, the paste's prefixed fold name included",
     "t.livecodescript",
     'constant rs1kGoldHex = "ab"\n\non tGo\n   if rs1rstHex(tOut) is rs1kGoldHex then\n      put 1 into tX\n   end if\nend tGo\n',
     None),
    ("a chunk of a constant is a literal (coin-selftest's PBKDF2 prefix, measured)",
     "t.livecodescript",
     'constant kSeed = "ab"\n\non tGo\n   stAssert "prefix", stHex(tShort) is char 1 to 40 of kSeed\nend tGo\n',
     None),
    ("a numeric expression is compared as a number on purpose (sodium-demo's shortHex, measured)",
     "t.livecodescript",
     'function tGo pMax\n   if the number of chars in tHex > pMax or length(tHex) is tWant then\n      return 1\n   end if\n   return 0\nend tGo\n',
     None),
    ("a comparison inside a comment is not code",
     "t.livecodescript",
     'on tGo\n   -- if tHex is sHex then\n   # if tNonce = sNonce then\n   put 1 into tX\nend tGo\n',
     None),
    ("a comparison inside a string literal is not code",
     "t.livecodescript",
     'on tGo\n   put "if tHex is sHex then" into tDoc\nend tGo\n',
     None),
    ("type, containment and existence tests are not comparisons of two values",
     "t.livecodescript",
     'on tGo\n   if tHex is a number or tHex is among the lines of tList or tTok is not in tText then\n      put 1 into tX\n   end if\n   if there is a file tPathHex then\n      put 2 into tX\n   end if\nend tGo\n',
     None),
    ("the measured false positives stay out: Key, Sig and Id name no hex here",
     "t.livecodescript",
     'on tGo\n   if sDrawKey[pRef] is tKey or sSheetPath[pName] is tSig then\n      put 1 into tX\n   end if\n   if tGotId is not pId then\n      put 2 into tX\n   end if\nend tGo\n',
     None),
    ("check 23 is .livecodescript only (LCB compares String as text)",
     "t.lcb",
     'library org.test.t\n\npublic handler tGo(in pAHex as String, in pBHex as String) returns Boolean\n   return pAHex is pBHex\nend handler\n\nend library\n',
     None),
]


# --- check 23's history fixtures -------------------------------------------
# The comparisons the 2026-09-25 fixes replaced (MUST refuse) and the lines
# that replaced them (MUST pass), GENERATED from git, never typed: a hunk of
# `git show --unified=0 <sha> -- <paths>` qualifies when one of its added
# code lines carries a fix marker (heHexEq, or a letter prefix); its removed
# code lines that compare are OLD, its added lines that carry a marker are
# NEW. Committed here because CI checks the suite out ONE commit deep, so
# the commits are not there to read; main() re-extracts and compares
# whenever they are, so this list cannot drift from the history it claims.
# Regenerate with `python3 tools/test-checker.py --print-history`.
FIX_COMMITS = (
    ("9d6f8da", ("nocloud/src/nocloudquickshare.livecodescript",
                 "torrentxt/examples/torrent-quickshare.livecodescript",
                 "datachannelxt/examples/datachannel-dht-chat.livecodescript")),
    ("9f8c297", ("holde-em/src/holdem.livecodescript",)),
)
FIX_MARKERS = ("heHexEq(", '("t" & ', '("n" & ')
FIX_OLD_LINES = [
    ('9d6f8da', 'if pNonce is sSeenOfferNonce then'),
    ('9d6f8da', 'if pNonce is not sNonce then'),
    ('9d6f8da', 'if pNonce is sSeenAnswerNonce then'),
    ('9d6f8da', 'if tTok is not sCwToken then'),
    ('9d6f8da', 'if tTok is not sCwToken then'),
    ('9f8c297', 'if pFromPubHex is not empty and tA["from"] is not pFromPubHex then'),
    ('9f8c297', 'if pExpectedPrevHex is not empty and tA["prev"] is not pExpectedPrevHex then'),
    ('9f8c297', 'if heSeedCommitHex(pSeedsHexA[tSeatPos]) is not pCommitsA[tSeatPos] then'),
    ('9f8c297', 'if heSeedCommitHex(pSeedsHexA[tSeatPos]) is not pCommitsA[tSeatPos] then'),
    ('9f8c297', 'if tBaseHex is pPointHex then'),
    ('9f8c297', 'if tRedoneHex is not tOutHex then'),
    ('9f8c297', 'if tRedoneHex is pOutHex then'),
    ('9f8c297', 'if tZRedHex is not tZHex then'),
    ('9f8c297', 'if tLhsHex is not tRhsHex then'),
    ('9f8c297', 'if tLhsHex is not tRhsHex then'),
    ('9f8c297', 'if heL2CommitKeyHex(tRkA[tPosI]) is not tCkStored then'),
    ('9f8c297', 'else if gGame["hostPubHex"] is not tPubHex then'),
    ('9f8c297', 'if (tTypeTxt is "cfg" or tTypeTxt is "roster") and tFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if tA["table"] is not gGame["tableIdHex"] then'),
    ('9f8c297', 'if tA["prev"] is not gGame["chainHeadHex"] then'),
    ('9f8c297', 'if tFromHex is not gGame["hostPubHex"] and not heRosterHasKey(tFromHex) then'),
    ('9f8c297', 'if tFromHex is gGame["hostPubHex"] then'),
    ('9f8c297', 'if tPub is pPubHex then'),
    ('9f8c297', 'if tA["prev"] is not gGame["chainHeadHex"] then'),
    ('9f8c297', 'if tPub is not empty and tPub is not gGame["hostPubHex"] then'),
    ('9f8c297', 'else if tElected is gGame["idPubHex"] then'),
    ('9f8c297', 'if heNetOracleDeal() and pFromHex is gGame["hostPubHex"] then'),
    ('9f8c297', 'if pPubHex is gGame["idPubHex"] then'),
    ('9f8c297', 'if gGame["oracleHost"] is "true" and tPubHex is gGame["idPubHex"] then'),
    ('9f8c297', 'if gGame["oracleHost"] is "true" and tPubHex is gGame["idPubHex"] then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if tHex is gGame["idPubHex"] then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if pFromHex is not tDealerPub then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'if pFromHex is not tDealerPub then'),
    ('9f8c297', 'if heSeedCommitHex(tHex) is not gGame["oDeal"]["commitsBy"][tPos] then'),
    ('9f8c297', 'if pFromHex is not gGame["hostPubHex"] then'),
    ('9f8c297', 'or tHeadHex is not gGame["rcptHeadHex"]'),
    ('9f8c297', 'if tFromSeat is 0 and not (heNetOracleDeal() and pFromHex is gGame["hostPubHex"]) then'),
    ('9f8c297', 'if tCkptHead is not empty and tHeadHex is not tCkptHead then'),
    ('9f8c297', 'if not heIsHex(tSeedHex, 64) or heSeedCommitHex(tSeedHex) is not gGame["oDeal"]["commitsBy"][tPos] then'),
    ('9f8c297', 'if tKeyPub is gGame["idPubHex"] then'),
]
FIX_NEW_LINES = [
    ('9d6f8da', 'if ("n" & pNonce) is ("n" & sSeenOfferNonce) then'),
    ('9d6f8da', 'if ("n" & pNonce) is not ("n" & sNonce) then'),
    ('9d6f8da', 'if ("n" & pNonce) is ("n" & sSeenAnswerNonce) then'),
    ('9d6f8da', 'if ("t" & tTok) is not ("t" & sCwToken) then'),
    ('9d6f8da', 'if ("t" & tTok) is not ("t" & sCwToken) then'),
    ('9f8c297', 'if pFromPubHex is not empty and not heHexEq(tA["from"], pFromPubHex) then'),
    ('9f8c297', 'if pExpectedPrevHex is not empty and not heHexEq(tA["prev"], pExpectedPrevHex) then'),
    ('9f8c297', 'if not heHexEq(heSeedCommitHex(pSeedsHexA[tSeatPos]), pCommitsA[tSeatPos]) then'),
    ('9f8c297', 'if not heHexEq(heSeedCommitHex(pSeedsHexA[tSeatPos]), pCommitsA[tSeatPos]) then'),
    ('9f8c297', 'if heHexEq(tBaseHex, pPointHex) then'),
    ('9f8c297', 'if not heHexEq(tRedoneHex, tOutHex) then'),
    ('9f8c297', 'if heHexEq(tRedoneHex, pOutHex) then'),
    ('9f8c297', 'if not heHexEq(tZRedHex, tZHex) then'),
    ('9f8c297', 'if not heHexEq(tLhsHex, tRhsHex) then'),
    ('9f8c297', 'if not heHexEq(tLhsHex, tRhsHex) then'),
    ('9f8c297', 'if not heHexEq(heL2CommitKeyHex(tRkA[tPosI]), tCkStored) then'),
    ('9f8c297', 'else if not heHexEq(gGame["hostPubHex"], tPubHex) then'),
    ('9f8c297', 'if (tTypeTxt is "cfg" or tTypeTxt is "roster") and not heHexEq(tFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(tA["table"], gGame["tableIdHex"]) then'),
    ('9f8c297', 'if not heHexEq(tA["prev"], gGame["chainHeadHex"]) then'),
    ('9f8c297', 'if not heHexEq(tFromHex, gGame["hostPubHex"]) and not heRosterHasKey(tFromHex) then'),
    ('9f8c297', 'if heHexEq(tFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if heHexEq(tPub, pPubHex) then'),
    ('9f8c297', 'if not heHexEq(tA["prev"], gGame["chainHeadHex"]) then'),
    ('9f8c297', 'if tPub is not empty and not heHexEq(tPub, gGame["hostPubHex"]) then'),
    ('9f8c297', 'else if heHexEq(tElected, gGame["idPubHex"]) then'),
    ('9f8c297', 'if heNetOracleDeal() and heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if heHexEq(pPubHex, gGame["idPubHex"]) then'),
    ('9f8c297', 'if gGame["oracleHost"] is "true" and heHexEq(tPubHex, gGame["idPubHex"]) then'),
    ('9f8c297', 'if gGame["oracleHost"] is "true" and heHexEq(tPubHex, gGame["idPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if heHexEq(tHex, gGame["idPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, tDealerPub) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, tDealerPub) then'),
    ('9f8c297', 'if not heHexEq(heSeedCommitHex(tHex), gGame["oDeal"]["commitsBy"][tPos]) then'),
    ('9f8c297', 'if not heHexEq(pFromHex, gGame["hostPubHex"]) then'),
    ('9f8c297', 'or not heHexEq(tHeadHex, gGame["rcptHeadHex"])'),
    ('9f8c297', 'if tFromSeat is 0 and not (heNetOracleDeal() and heHexEq(pFromHex, gGame["hostPubHex"])) then'),
    ('9f8c297', 'if tCkptHead is not empty and not heHexEq(tHeadHex, tCkptHead) then'),
    ('9f8c297', 'else if not heHexEq(heSeedCommitHex(tSeedHex), gGame["oDeal"]["commitsBy"][tPos]) then'),
    ('9f8c297', 'if heHexEq(tKeyPub, gGame["idPubHex"]) then'),
    ('9f8c297', 'heTAssert "helpers: heHexEq keeps two overflowing 64-hex texts apart (bare is: equal on the engine)", heHexEq(tHexA, tHexB) & "," & heIsHex(tHexA, 64) & "," & heIsHex(tHexB, 64), "false,true,true"'),
    ('9f8c297', 'heTAssert "helpers: heHexEq keeps 1e5 and 100000 apart (bare is: equal on the engine)", heHexEq("1e5", "100000"), "false"'),
    ('9f8c297', 'heTAssert "helpers: heHexEq keeps the 64-zero genesis head and 0 apart (bare is: equal everywhere)", heHexEq(kHeGenesisPrev, "0") & "," & heHexEq(kHeGenesisPrev, kHeGenesisPrev), "false,true"'),
    ('9f8c297', 'heTAssert "helpers: heHexEq calls a hex text equal to itself", heHexEq(tHexA, tHexA), "true"'),
    ('9f8c297', 'heTAssert "helpers: heHexEq is case-blind, as hex is (an honest commit in either case passes)", heHexEq(toUpper(kKatCommit1), kKatCommit1), "true"'),
]


def _fix_code_lines(lines):
    """Code lines of one side of a hunk: continuations merged, comment-only
    lines dropped (a comment is not a comparison)."""
    out, buf = [], ""
    for ln in lines:
        s = ln.strip()
        if buf:
            s = buf + " " + s
            buf = ""
        if s.endswith("\\"):
            buf = s[:-1].rstrip()
            continue
        if not s or s.startswith("--") or s.startswith("#"):
            continue
        out.append(s)
    if buf:
        out.append(buf)
    return out


def extract_fix_lines(root):
    """(old, new) from the fix commits, or None when this clone lacks them."""
    old, new = [], []
    for sha, paths in FIX_COMMITS:
        have = subprocess.run(["git", "-C", root, "cat-file", "-e",
                               sha + "^{commit}"], capture_output=True)
        if have.returncode != 0:
            return None
        diff = subprocess.run(["git", "-C", root, "show", "--format=",
                               "--unified=0", sha, "--"] + list(paths),
                              capture_output=True, text=True,
                              check=True).stdout
        hunks, cur = [], None
        for ln in diff.split("\n"):
            if ln.startswith("@@"):
                cur = ([], [])
                hunks.append(cur)
            elif cur is not None and ln.startswith("-") and \
                    not ln.startswith("---"):
                cur[0].append(ln[1:])
            elif cur is not None and ln.startswith("+") and \
                    not ln.startswith("+++"):
                cur[1].append(ln[1:])
        for removed, added in hunks:
            added_code = _fix_code_lines(added)
            if not any(m in a for a in added_code for m in FIX_MARKERS):
                continue
            for r in _fix_code_lines(removed):
                if re.search(r"\bis\b|=|<>", r):
                    old.append((sha, r))
            for a in added_code:
                if any(m in a for m in FIX_MARKERS):
                    new.append((sha, a))
    return old, new


def wrap_fix_line(line):
    """One extracted line as a complete script that no OTHER rule refuses:
    its k-constants declared, an `if` closed, an `else if` given its `if`,
    a bare `or ...` continuation given the `if` it continued."""
    head = "".join('constant %s = "x"\n' % k for k in
                   sorted(set(re.findall(r"\bk[A-Z][A-Za-z0-9_]*", line))))
    low = line.lower()
    if low.startswith("or ") or low.startswith("and "):
        line = "if tQ is 1 " + line + " then"
        low = line.lower()
    if low.startswith("else if") and low.endswith("then"):
        body = ("   if tQ is 1 then\n      put 1 into tX\n   %s\n"
                "      put 2 into tX\n   end if\n" % line)
    elif low.startswith("if") and low.endswith("then"):
        body = "   %s\n      put 1 into tX\n   end if\n" % line
    else:
        body = "   %s\n" % line
    return head + "on tGo\n" + body + "end tGo\n"


for _sha, _line in FIX_OLD_LINES:
    FIXTURES.append(("%s OLD line refused: %s" % (_sha, _line[:60]),
                     "t.livecodescript", wrap_fix_line(_line),
                     "meets a bare"))
for _sha, _line in FIX_NEW_LINES:
    FIXTURES.append(("%s NEW line passes: %s" % (_sha, _line[:60]),
                     "t.livecodescript", wrap_fix_line(_line), None))


def run_copy(checker, workdir):
    """Every fixture through ONE checker run, as its own file: one process
    per member copy rather than one per fixture (check 23's history set more
    than doubled the fixture count, and the box running the gates is shared).
    Each file's verdict is read from the lines that name it, and the run
    must end in the summary line for exactly that many files, so a checker
    that crashes or skips a file fails loudly instead of reading as clean.
    -> list of (name, error) for the fixtures that misbehaved."""
    paths = []
    for i, (name, filename, source, must) in enumerate(FIXTURES):
        d = os.path.join(workdir, "f%03d" % i)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, filename)
        with open(path, "w", encoding="utf-8") as f:
            f.write(source)
        paths.append(path)
    proc = subprocess.run([sys.executable, checker] + paths,
                          capture_output=True, text=True)
    out = (proc.stdout + proc.stderr).strip().split("\n")
    want_ok = "check-livecodescript: OK (%d file(s) checked)" % len(paths)
    want_bad = re.compile(r"^check-livecodescript: \d+ problem\(s\) in %d "
                          r"file\(s\)$" % len(paths))
    if not out or not (out[-1] == want_ok or want_bad.match(out[-1])):
        return [("(the whole run)", "the checker did not end in its "
                 "summary line for %d files:\n%s"
                 % (len(paths), "\n".join(out[-15:])))]
    bad = []
    for (name, filename, source, must), path in zip(FIXTURES, paths):
        mine = [ln for ln in out if ln.startswith(path + ":")]
        if must is None:
            if mine:
                bad.append((name, "expected CLEAN, got:\n%s"
                            % "\n".join(mine)))
        elif not mine:
            bad.append((name, "expected a finding containing %r, got a "
                        "clean pass" % must))
        elif not any(must in ln for ln in mine):
            bad.append((name, "expected the output to contain %r, got:\n%s"
                        % (must, "\n".join(mine))))
    return bad


def check_history():
    """Re-extract check 23's history fixtures when the commits are here.
    -> (ok, message)."""
    got = extract_fix_lines(ROOT)
    if got is None:
        return True, ("history: SKIPPED (the fix commits are not in this "
                      "clone; the committed extraction was used as is)")
    old, new = got
    if old != FIX_OLD_LINES or new != FIX_NEW_LINES:
        return False, ("history: the committed FIX_OLD_LINES/FIX_NEW_LINES "
                       "differ from a fresh extraction (%d/%d committed, "
                       "%d/%d extracted) - regenerate with --print-history"
                       % (len(FIX_OLD_LINES), len(FIX_NEW_LINES), len(old),
                          len(new)))
    return True, ("history: OK (%d OLD and %d NEW lines re-extracted from %s "
                  "match the committed fixtures)"
                  % (len(old), len(new),
                     ", ".join(sha for sha, _ in FIX_COMMITS)))


def main(argv):
    if "--print-history" in argv:
        got = extract_fix_lines(ROOT)
        if got is None:
            print("test-checker: the fix commits are not in this clone")
            return 1
        for name, rows in zip(("FIX_OLD_LINES", "FIX_NEW_LINES"), got):
            print("%s = [" % name)
            for sha, line in rows:
                print("    (%r, %r)," % (sha, line))
            print("]")
        return 0
    # --checker PATH runs the fixtures against ONE file (a mutant, in a
    # scratch directory) instead of every member's copy
    copies = [(m, os.path.join(ROOT, m, "tools", "check-livecodescript.py"))
              for m in MEMBERS]
    if "--checker" in argv:
        copies = [("--checker", argv[argv.index("--checker") + 1])]
    failures = 0
    total = 0
    with tempfile.TemporaryDirectory() as workdir:
        for member, checker in copies:
            if not os.path.exists(checker):
                print("test-checker: MISSING %s" % checker)
                failures += 1
                continue
            total += len(FIXTURES)
            for name, err in run_copy(checker, os.path.join(workdir, member)):
                failures += 1
                print("test-checker: FAIL [%s] %s\n  %s"
                      % (member, name, err.replace("\n", "\n  ")))
    ok, msg = check_history()
    print("test-checker: " + msg)
    if not ok:
        failures += 1
    if failures:
        print("test-checker: %d FAILURE(S) of %d fixture run(s)"
              % (failures, total))
        return 1
    print("test-checker: OK (%d fixtures x %d member copies = %d runs)"
          % (len(FIXTURES), len(copies), total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
