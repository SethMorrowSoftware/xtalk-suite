#!/usr/bin/env python3
"""check-script-vectors.py - run the SHIPPED src/coinxt.livecodescript against
the published vectors, and check its constants against the reference.

WHY THIS EXISTS, AND WHAT IT IS WORTH. Phase 3 is pure LiveCodeScript, and OXT
cannot compile or run a .livecodescript headlessly. Every other layer of CoinXT
has something that executes it before a human sees it - the shim has
tools/coin-kat.py, the binding has the ASan self-test and the committed-library
driver in CI - and the encoders had nothing. That is a bad gap to leave in
Base58Check and bech32 specifically: a transcription slip in an alphabet or a
checksum constant does not crash, it produces a VALID-LOOKING WRONG ADDRESS.

So this runs the real file. tools/lcs-interp.py interprets the LiveCodeScript
subset the encoders are written in, the hash handlers they call are supplied by
the REAL native library through ctypes, and the answers are compared against
tools/coin_reference.py, which reproduces the published vectors independently.

WHAT IT DOES NOT DO. It does not replace the OXT pass and it promotes nothing
out of "verified statically". The interpreter is an approximation of the engine:
it models the documented semantics of the subset used and refuses everything
else, but only a real engine settles parser behaviour. What this buys is that a
LOGIC error is found here, in CI, instead of in a scarce engine session.

Two tiers, so it is useful in both environments:
  1. CONSTANTS, always, no compiler needed. The alphabets, the generator
     constants, the bech32m constant and the version bytes are extracted from
     the script text and compared against the reference. Beside them (1b,
     2026-09-25) the one handler of examples/coinxt-demo.livecodescript that
     decides an integer, cdWholeField, is lifted out and run, and the demo's
     build handlers are read to prove every counter goes through it: no
     other gate runs the demo.
  2. VECTORS, when a C compiler is available: the whole encoder surface driven
     through the interpreter against BIP-173, BIP-350, EIP-55, the RLP
     yellow-paper examples and a Base58Check worked example, and (row #10,
     2026-09-26) every integer argument the encoders write settled as
     digits at most 2^53, each guard planted back to the old spelling and
     required to fail its block. Beside them (2b, 2026-09-26) coinxt-demo's
     EIP-55 recipient check, lifted out and run with `is` as the
     interpreter reads it and folded as the engine does.
A missing compiler SKIPS tier 2 loudly; it never passes silently.

IT IS SLOW, AND THAT IS THE PRICE, NOT A DEFECT. Tier 2 takes a couple of
minutes, because it interprets the real file statement by statement and phase 4
does a lot of statements: a 24-word mnemonic round trip alone is a binary search
per word, and an xprv is base58 long division over 82 bytes. Profiling shows no
hot spot to fix - the cost is spread evenly over the expression parser, which is
what "runs the real text" means. Do not trade vectors away for seconds here; in
a money library the vectors are the product.

Usage:
  python3 tools/check-script-vectors.py            # per-check detail
  python3 tools/check-script-vectors.py --check    # terse
"""

import ctypes
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "src", "coinxt.livecodescript")
NATIVE = os.path.join(ROOT, "native")
VENDOR = os.path.join(NATIVE, "vendor")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REF = _load("coin_reference", os.path.join(HERE, "coin_reference.py"))
LCS = _load("lcs_interp", os.path.join(HERE, "lcs-interp.py"))


class Checker:
    def __init__(self, terse):
        self.terse = terse
        self.problems = []
        self.count = 0

    def ck(self, name, got, want):
        self.count += 1
        if got != want:
            self.problems.append(f"{name}\n      got  {got!r}\n      want {want!r}")
        elif not self.terse:
            print(f"  ok   {name}")

    def note(self, text):
        if not self.terse:
            print(text)


# --------------------------------------------------------------------- tier 0
def check_interp_model(c):
    """Pin the interpreter's chunk semantics to the engine-observed facts.

    The engine ignores ONE trailing delimiter when it counts chunks, and the
    2026-08-10 engine pass proved what happens when the model disagrees: the
    "m/" negative vector passed against an interpreter in which the check
    fires, while the engine never ran it. Now that cxHdDerivePath refuses a
    trailing separator outright, no script vector would notice the model
    regressing back to a bare split() - so the rule is pinned HERE, directly,
    against the facts the engine showed.
    """
    c.note("tier 0: the interpreter's chunk model (engine-observed 2026-08-10)")
    ip = LCS.Interp("")

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)

    c.ck('one trailing delimiter is invisible: "m," is ONE item',
         ev('the number of items of "m,"'), 1)
    c.ck('only one is: "a,," is two items', ev('the number of items of "a,,"'), 2)
    c.ck('"," is one (empty) item', ev('the number of items of ","'), 1)
    c.ck("the empty string has zero items", ev('the number of items of ""'), 0)
    c.ck('there is no empty second item of "m,"', ev('item 2 of "m,"'), "")
    c.ck("lines follow the same rule", ev("the number of lines of t", t="a\n"), 1)
    check_interp_key_fold(c)
    check_interp_compare(c)


# The key-fold fixture script: each handler is one question the engine
# answered (or the model had to choose), and check_interp_key_fold names
# which. Written as HANDLERS, not bare expressions, because two of the
# questions are about what a `set` does across a handler boundary.
_KEY_FOLD_SRC = """
function kfWriteReadOther
   local tA
   put 1 into tA["a"]
   return tA["A"]
end kfWriteReadOther
function kfAmongOther
   local tA
   put 1 into tA["a"]
   return "A" is among the keys of tA
end kfAmongOther
function kfNotAmong
   local tA
   put 1 into tA["a"]
   return "b" is not among the keys of tA
end kfNotAmong
function kfKeysOriginal
   local tA
   put 1 into tA["MixedCase"]
   return the keys of tA
end kfKeysOriginal
function kfSecondSpellingWrite
   local tA
   put 1 into tA["a"]
   put 2 into tA["A"]
   return the keys of tA
end kfSecondSpellingWrite
function kfSecondSpellingValue
   local tA
   put 1 into tA["a"]
   put 2 into tA["A"]
   return tA["a"]
end kfSecondSpellingValue
function kfNested
   local tA
   put "x" into tA["Name"]["Inner"]
   put "y" into tA["NAME"]["inner"]
   return tA["name"]["INNER"]
end kfNested
function kfNestedKeys
   local tA
   put "x" into tA["Name"]["Inner"]
   put "y" into tA["NAME"]["inner"]
   return the keys of tA["name"]
end kfNestedKeys
function kfCopyKeepsFold
   local tA, tB
   put 1 into tA["Key"]
   put tA into tB
   return tB["KEY"]
end kfCopyKeepsFold
function kfArrayIsArray
   local tA, tB
   put 1 into tA["k"]
   put 1 into tB["K"]
   return tA is tB
end kfArrayIsArray
function kfDefault
   return the caseSensitive
end kfDefault
function kfSensitiveKeys
   local tA
   set the caseSensitive to true
   put 1 into tA["a"]
   put 2 into tA["A"]
   return the keys of tA
end kfSensitiveKeys
function kfSensitiveRead
   local tA
   set the caseSensitive to true
   put 1 into tA["a"]
   return tA["A"] & "|" & ("A" is among the keys of tA)
end kfSensitiveRead
function kfSensitiveCaller
   set the caseSensitive to true
   return kfDefault() & "|" & the caseSensitive
end kfSensitiveCaller
function kfSetter
   set the caseSensitive to true
   return "set"
end kfSetter
function kfSetterLeaks
   local tA, tIgnored
   put kfSetter() into tIgnored
   put 1 into tA["a"]
   return tA["A"]
end kfSetterLeaks
"""


def check_interp_key_fold(c):
    """Pin the ARRAY-KEY FOLD (tools/lcs-interp.py header, 2026-09-24) to the
    engine's observed answers, and name the modelled choices as choices.

    Until 2026-09-24 the interpreter's arrays were case-sensitive Python dicts
    and the engine's are not (docs/OXT-ENGINE-NOTES.md 2.7, OBSERVED
    2026-09-15): `tA["A"]` read the element stored as `a` on the engine and
    read empty here, so no execution gate could see two keys collide. No
    script vector would notice the model regressing - this member's layer
    keys no array by case-significant text - so the rule is pinned here,
    directly, like the chunk rule above."""
    c.note("tier 0: the interpreter's array-key fold (engine notes 2.7)")
    ip = LCS.Interp(_KEY_FOLD_SRC)

    def run(handler):
        return ip.call(handler, [])

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)

    # OBSERVED 2026-09-15 (note 2.7): with the default caseSensitive a key
    # matches whatever its case, for a read and for `is among the keys of`,
    # and `the keys of` answers the ORIGINAL spelling.
    c.ck("OBSERVED: tA[\"A\"] reads the element stored as \"a\"",
         run("kfWriteReadOther"), 1)
    c.ck("OBSERVED: \"A\" is among the keys of an array keyed \"a\"",
         run("kfAmongOther"), True)
    c.ck("a key that folds onto nothing is still not among the keys",
         run("kfNotAmong"), True)
    c.ck("OBSERVED: the keys of answers the original spelling",
         run("kfKeysOriginal"), "MixedCase")
    # MODELLED (the header says so): a second spelling lands on the SAME
    # element, replacing its value, and the FIRST spelling is kept.
    c.ck("MODELLED: a write in another case is the same element (one key)",
         run("kfSecondSpellingWrite"), "a")
    c.ck("MODELLED: ... and it replaces the value",
         run("kfSecondSpellingValue"), 2)
    c.ck("the fold holds at every depth of a subscript chain",
         run("kfNested"), "y")
    c.ck("... one inner element, under its first spelling",
         run("kfNestedKeys"), "Inner")
    c.ck("an array copied across a binding keeps its fold",
         run("kfCopyKeepsFold"), 1)
    c.ck("array `is` array compares keys folded", run("kfArrayIsArray"), True)
    # A plain dict a Python driver hands in folds too (no index; a scan).
    c.ck("a driver's plain dict folds on read", ev('t["KEY"]', t={"key": "v"}),
         "v")
    c.ck("a driver's plain dict folds for `is among the keys of`",
         ev('"KEY" is among the keys of t', t={"key": "v"}), True)
    # ASSUMED (header): caseSensitive governs keys, and it is a LOCAL
    # property - false at every handler entry, the caller's value restored
    # on return, so a callee's `set` cannot leak out to its caller.
    c.ck("the caseSensitive defaults to false", run("kfDefault"), False)
    c.ck("ASSUMED: caseSensitive true keeps two spellings apart",
         run("kfSensitiveKeys"), "a\nA")
    c.ck("ASSUMED: ... and a lookup must then match the spelling",
         run("kfSensitiveRead"), "|false")
    c.ck("ASSUMED: a callee starts at false; the caller's true survives it",
         run("kfSensitiveCaller"), "false|true")
    c.ck("ASSUMED: a callee's `set the caseSensitive` does not leak out",
         run("kfSetterLeaks"), 1)
    c.ck("and nothing is left set once the handlers return",
         LCS.CASE_SENSITIVE[0], False)


# The comparison fixture script (2026-09-25). The two quotient bounds that
# shipped - riptide's rsReadBEu64 guard, which an engine was OBSERVED to let
# 2^53 + 1 through on 2026-09-24, and wallet-core's cwLeRead, the same form a
# byte at a time - and the exact-halves rule that replaced riptide's.
# cwLeRead is verbatim bar its name; the two u64 handlers keep their deciding
# lines verbatim and take the u32 halves as arguments instead of reading them
# from bytes. HANDLERS, so the refusal is met where a script meets it: inside
# a call, and under a `try` that must not eat it.
_COMPARE_SRC = """
function tcQuotientU64 pHi, pLo
   if pHi > (9007199254740992 - pLo) / 4294967296 then
      return empty
   end if
   return pHi * 4294967296 + pLo
end tcQuotientU64
function tcHalvesU64 pHi, pLo
   if pHi > 2097152 then
      return empty
   end if
   if pHi is 2097152 then
      if pLo is not 0 then
         return empty
      end if
   end if
   return pHi * 4294967296 + pLo
end tcHalvesU64
function tcQuotientLeRead pBytes
   local tValue, tI, tCount, tByte
   put the number of bytes of pBytes into tCount
   put 0 into tValue
   repeat with tI = tCount down to 1
      put byteToNum(byte tI of pBytes) into tByte
      if tValue > (9007199254740992 - tByte) / 256 then
         throw "cwLeRead: the value is over 2^53 and cannot be held exactly"
      end if
      put tValue * 256 + tByte into tValue
   end repeat
   return tValue
end tcQuotientLeRead
function tcCaught pHi, pLo
   local tErr
   try
      return tcQuotientU64(pHi, pLo)
   catch tErr
      return "caught: " & tErr
   end try
end tcCaught
function tcUlpLadder pBase, pUlps
   local tStep
   put 1 into tStep
   repeat while tStep <= 1073741824
      if pBase + tStep / pUlps > pBase then
         return tStep
      end if
      multiply tStep by 2
   end repeat
   return 0
end tcUlpLadder
"""

# RIPTIDE'S TWO PROBE LINES AS THE ENGINE READ THEM (OBSERVED 2026-09-24, the
# suite paste's second and third runs; engine note 2.10), beside what IEEE
# reads: (expression, the engine's reading, the IEEE reading). tcUlpLadder is
# the harness's rstUlpLadder, renamed.
_ENGINE_PROBE_READINGS = [
    ("1 + 1 / 10000000 > 1", "true", "true"),
    ("1 + 1 / 2251799813685248 > 1", "false", "true"),
    ("2097152 > (9007199254740992 - 1) / 4294967296", "false", "true"),
    ("1 + 23 / 4503599627370496 > 1 + 22 / 4503599627370496", "false", "true"),
    ("1 / 10000000000 > 0", "true", "true"),
    ("1073741824 + 1 / 2097152 > 1073741824", "false", "true"),
    ("tcUlpLadder(1, 4503599627370496)", "16", "1"),
    ("tcUlpLadder(8, 562949953421312)", "16", "1"),
]


def check_interp_compare(c):
    """Pin the COMPARISON REFUSAL (tools/lcs-interp.py header, 2026-09-25):
    the interpreter refuses (LCS.Indistinct) a numeric comparison whose
    answer on the engine is not the IEEE answer, and answers every other one
    exactly as before.

    Until 2026-09-25 it compared the IEEE way, and on 2026-09-24 an engine
    did not (docs/OXT-ENGINE-NOTES.md 2.10): riptide's u64 bound refused
    2^53 + 1 in every headless gate and let it through on OXT. The rule the
    refusal applies is the engine SOURCE's (engine/src/exec-logic.cpp: equal
    within 10 * DBL_EPSILON of the smaller magnitude), DOCUMENTED, one
    observation deep - so what is pinned here is the MODEL: that it refuses
    the observed defect and its wallet-core twin, that the replacement rule
    and ordinary comparisons pass untouched, and where the source's constant
    puts the edge. No script vector would notice the model regressing to
    IEEE once the shipped bounds are rewritten, so it is pinned here,
    directly, like the chunk and key rules above.
    """
    c.note("tier 0: comparisons the engine answers differently are refused "
           "(engine notes 2.10)")
    ip = LCS.Interp(_COMPARE_SRC)

    def outcome(fn):
        # a script's own throw is an ANSWER here (the old IEEE verdict of the
        # wallet-core bound is its throw), never mistaken for the refusal
        try:
            return "answered %r" % (fn(),)
        except LCS.Indistinct as exc:
            return "refused: %s" % exc
        except LCS.Thrown as exc:
            return "threw %r" % (exc.msg,)

    def verdict(fn):
        got = outcome(fn)
        return "refused" if got.startswith("refused") else got

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)

    def le(n):
        return "".join(chr(x) for x in n.to_bytes(8, "little"))

    def where(env):
        # a label must stay readable: a 400-digit operand is named by size
        def short(v):
            text = repr(v)
            return text if len(text) <= 24 else "<%d chars>" % len(str(v))
        return "".join(" %s=%s" % (k, short(v)) for k, v in env.items())

    top = 2 ** 53

    # (a) THE DEFECT. IEEE says 2097152 > 2097151.9999999998 and refuses the
    # record; the engine calls the pair equal and ACCEPTED it (OBSERVED).
    got = outcome(lambda: ip.call("tcQuotientU64", [2 ** 21, 1]))
    c.ck("OBSERVED case: riptide's quotient bound at 2^53 + 1 is REFUSED, "
         "not answered", got.split(":")[0], "refused")
    c.ck("... the refusal names both operands",
         "`2097152 > 2097151.9999999998`" in got, True)
    c.ck("... and the expression they came from",
         "`pHi > (9007199254740992 - pLo) / 4294967296`" in got, True)
    c.ck("... and cites the engine note", "OXT-ENGINE-NOTES.md 2.10" in got,
         True)
    c.ck("wallet-core's quotient bound at 2^53 + 1 (0.0039 apart at 3.5e13, "
         "which an absolute tolerance would miss) is REFUSED",
         verdict(lambda: ip.call("tcQuotientLeRead", [le(top + 1)])),
         "refused")
    c.ck("a script `try` cannot swallow the refusal",
         verdict(lambda: ip.call("tcCaught", [2 ** 21, 1])), "refused")
    c.ck("it is neither a script error nor the 2^53 stop",
         (issubclass(LCS.Indistinct, LCS.Thrown),
          issubclass(LCS.Indistinct, LCS.Imprecise)), (False, False))
    # The same two lines everywhere ELSE answer as they always have: EQUAL
    # operands (exactly 2^53), and a near pair on which `>` is false both in
    # IEEE and on the engine (2^53 - 1: 2097151 against 2097151.0000000002,
    # a pair the engine calls equal). Refusing that would refuse a verdict
    # the two share - the operator-aware rule's reason to exist.
    c.ck("the quotient bound at exactly 2^53 (operands equal) answers",
         verdict(lambda: ip.call("tcQuotientU64", [2 ** 21, 0])),
         "answered %r" % top)
    c.ck("... and at 2^53 - 1, where `>` is false on both, answers",
         verdict(lambda: ip.call("tcQuotientU64", [2 ** 21 - 1, 2 ** 32 - 1])),
         "answered %r" % (top - 1))
    c.ck("wallet-core's bound reads 2^53 - 1 as before",
         verdict(lambda: ip.call("tcQuotientLeRead", [le(top - 1)])),
         "answered %r" % (top - 1))

    # HELD TO THE ENGINE'S OWN READINGS, not only to its source: where the
    # engine read a probe as IEEE does, the interpreter must ANSWER, and say
    # the same; where it read otherwise, the interpreter must REFUSE. Eight
    # observations, and the refusal has to agree with every one.
    for expr, engine_read, ieee_read in _ENGINE_PROBE_READINGS:
        got = outcome(lambda: ip.eval_expr(expr, {}))
        if got.startswith("answered "):
            got = "answered " + str(LCS._disp(ip.eval_expr(expr, {})))
        elif got.startswith("refused"):
            got = "refused"
        want = ("answered " + engine_read if engine_read == ieee_read
                else "refused")
        c.ck("OBSERVED: the engine read `%s` as %s (IEEE: %s)"
             % (expr, engine_read, ieee_read), got, want)

    # (b) THE REPLACEMENT: the bound decided on the u32 halves, every
    # comparison between integers below 2^32 at least 1 apart, answers on
    # both sides of 2^53 and is never refused.
    for hi, lo, want in ((2 ** 21, 1, ""), (2 ** 21, 0, top),
                         (2 ** 21 - 1, 2 ** 32 - 1, top - 1),
                         (2 ** 21 + 1, 0, ""), (0, 0, 0)):
        c.ck("the exact-halves rule answers hi %d, lo %d" % (hi, lo),
             verdict(lambda: ip.call("tcHalvesU64", [hi, lo])),
             "answered %r" % (want,))

    # (c) ORDINARY COMPARISONS, UNTOUCHED: clearly separated or equal.
    for expr, env, want in [
            ("3 > 2", {}, True), ("2 < 3", {}, True), ("2 >= 2", {}, True),
            ("2 <= 1", {}, False), ("2 <> 3", {}, True), ("2 is 2", {}, True),
            ("2 is 3", {}, False), ('"5" is 5', {}, True),
            ("0.5 < 0.75", {}, True), ("0.1 + 0.2 < 0.5", {}, True),
            ("t is u", {"t": 1, "u": 1.0}, True),
            ("t is u", {"t": 0.25, "u": "0.25"}, True),
            ("t > u", {"t": 4294967296, "u": 4294967295}, True),
            ("t > u", {"t": 1700000000001, "u": 1700000000000}, True),
            ("t > u", {"t": 0.30000001, "u": 0.3}, True),
            ("t > 0", {"t": 1e-9}, True),
            ("t > u", {"t": top, "u": top - 21}, True),
            ('"9007199254740995" is "9007199254740995"', {}, True),
            # past 384 characters the engine reads no string as a number
            # (R8L), so two long digit runs compare as TEXT on both sides
            ("t is u", {"t": "1" * 400, "u": "1" * 399 + "2"}, False)]:
        c.ck("untouched: %s%s" % (expr, where(env)),
             verdict(lambda: ev(expr, **env)), "answered %r" % (want,))

    # WHERE THE SOURCE'S RULE BITES, pinned as the model's reading of it
    # (MC_EPSILON = 10 * DBL_EPSILON of the smaller magnitude; DOCUMENTED).
    for expr, env in [
            ("0.1 + 0.2 is 0.3", {}), ("0.1 + 0.2 <> 0.3", {}),
            ("0.1 + 0.2 is not 0.3", {}), ("0.1 + 0.2 > 0.3", {}),
            ("t > 0", {"t": 1e-20}),
            ("t > u", {"t": top, "u": top - 19}),
            ("t <= u", {"t": top, "u": top - 1}),
            # past 2^53 a numeric string is ROUNDED before it is compared:
            # 9007199254740994 and ...995 are one double apart and one number
            # to the engine, where the text says two
            ('"9007199254740994" is "9007199254740995"', {}),
            # and one of 309 to 384 digits overflows to infinity, so any two
            # such strings are one number there
            ("t is u", {"t": "1" * 320, "u": "1" * 319 + "2"})]:
        c.ck("refused: %s%s" % (expr, where(env)),
             verdict(lambda: ev(expr, **env)), "refused")
    # ... and where it does not, although the pair is inside the tolerance:
    # the operator answers the same on both.
    c.ck("inside the tolerance, `<` agrees (false on both): answered",
         verdict(lambda: ev("t < u", t=top, u=top - 1)), "answered False")
    c.ck("inside the tolerance, `>=` agrees (true on both): answered",
         verdict(lambda: ev("t >= u", t=top, u=top - 1)), "answered True")

    # A PYTHON DRIVER'S OWN NUMBER TYPE IS NOT JUDGED: a tier that replays a
    # comparison under a candidate engine rule (a float subclass, a wrapper
    # answering the six operators) owns the answer. Checked as exact types
    # in the interpreter; this pins it, so a "tidier" isinstance cannot
    # quietly turn every such replay into a refusal.
    class Replayed(float):
        pass

    c.ck("a driver's own number type is compared, not refused",
         verdict(lambda: ev("t > u", t=Replayed(2097152.0),
                            u=Replayed((top - 1) / 4294967296))),
         "answered True")
    check_interp_number_text(c)


# RIPTIDE'S THIRD PROBE LINE (riptide/tests/riptide-selftest.livecodescript,
# "numeric compare probe 3", added 2026-09-25) AS THE ENGINE READ IT:
# OBSERVED 2026-09-25 on Linux and then on Windows, character for character
# alike (the D-23 suite paste; engine notes 2.10 and 2.11, runbook section
# 8), and item for item what the engine SOURCE predicted (exec-logic.cpp's
# rule and MCU_strtor8's parse). The second column is that reading, the third
# what this interpreter answered before 2026-09-25 (items 1 and 2 as TEXT,
# the rest the IEEE way). Each expression as the harness spells it. Items 3
# to 8 are 2.10's rule and read through tiers 1c and 4 as well; items 1 and 2
# are 2.11's parse, and this is the one gate that holds the interpreter to
# them.
_ENGINE_PROBE3_READINGS = [
    ('"1e999" is "2e999"', "true", "false"),
    ('"1e5" is "100000"', "true", "false"),
    ("1 / 1000000000000000 > 0", "false", "true"),
    ("1 / 100000000000000 > 0", "true", "true"),
    ("562949953421312 < 562949953421313", "false", "true"),
    ("281474976710656 < 281474976710657", "true", "true"),
    ("450359962737050 is 450359962737051", "true", "false"),
    ("450359962737049 is 450359962737050", "false", "false"),
]


def check_interp_number_text(c):
    """Pin the TEXT-AS-NUMBER refusal (tools/lcs-interp.py header, the
    second 2026-09-25 section; docs/OXT-ENGINE-NOTES.md 2.11): the engine
    turns BOTH operands of a comparison into numbers whenever both parse
    (MCU_strtor8: an integer parse, then C strtod over at most 384
    characters), so "1e5" is "100000" is TRUE there, and until this date the
    interpreter read every exponent-form text as TEXT in `is` and answered
    false - no headless gate could see a hex digest or a token compare equal
    to a different one. The interpreter now answers only where its reading
    and the engine's give the same answer, and REFUSES (LCS.Indistinct, the
    class the 2.10 refusal uses; its message names engine note 2.11) where
    they part, or where the note does not establish how the engine reads a
    form at all (hex, inf and nan words, a non-ASCII edge), rather than
    guess. The table in the interpreter's header is what these rows hold.

    Each row says what the ENGINE answers and the row's want is what the
    INTERPRETER must do: answer, or refuse. The engine's answers are its
    source's (DOCUMENTED), bar riptide's third probe line, which an engine
    READ on Linux and on Windows on 2026-09-25 exactly as the source
    predicted: its items 1 and 2 (`"1e999" is "2e999"`, `"1e5" is "100000"`,
    both true) are the two forms here that are OBSERVED. A regression to the
    old reading fails the refusal rows; an over-eager refusal fails the
    answer rows.
    """
    c.note("tier 0: text the engine reads as a number is refused where the "
           "answer moves (engine notes 2.11)")
    ip = LCS.Interp(_COMPARE_SRC + _NUMBER_TEXT_SRC)

    def ev(expr, **env):
        return LCS._Expr(ip, dict(env)).parse(expr)

    def verdict(fn):
        try:
            got = fn()
        except LCS.Indistinct as exc:
            return "refused" if "2.1" in str(exc) else "refused, uncited"
        except LCS.Imprecise:
            return "refused (Imprecise)"
        except LCS.Thrown as exc:
            return "threw %r" % (exc.msg,)
        except Exception as exc:                         # noqa: BLE001
            return "crashed: %s" % type(exc).__name__
        return "answered %s" % (str(LCS._disp(got)),)

    def short(env):
        def one(v):
            text = repr(v)
            return text if len(text) <= 24 else "<%d chars>" % len(str(v))
        return "".join(" %s=%s" % (k, one(v)) for k, v in env.items())

    # PROBE 3, AS THE ENGINE READ IT (Linux and Windows, 2026-09-25):
    # refuse each item the engine read differently from the old reading,
    # answer the three it read the same, and say so in the label.
    for expr, engine_read, old in _ENGINE_PROBE3_READINGS:
        want = ("answered " + old if engine_read == old else "refused")
        c.ck("OBSERVED (probe 3, Linux and Windows 2026-09-25): the engine "
             "read `%s` as %s, the old reading %s" % (expr, engine_read, old),
             verdict(lambda: ev(expr)), want)

    # `is`: (expression, env, the engine's answer from its source, want).
    top = "9" * 20
    for expr, env, engine, want in [
            # forms note 2.11 establishes, where the old text reading parts
            ('"1e5" is "100000"', {}, "true", "refused"),
            ('"1E5" is "1e5"', {}, "true", "refused"),
            ('"+3" is "3"', {}, "true", "refused"),
            ('"3." is "3"', {}, "true", "refused"),
            ('"1e999" is "2e999"', {}, "true", "refused"),
            ('"1e-999" is 0', {}, "true", "refused"),
            ('".5" is 0.5', {}, "true", "refused"),
            ("t is u", {"t": "12e4", "u": 120000}, "true", "refused"),
            # ... and where it does not part: answered
            ('"1e5" is "1e5"', {}, "true", "answered true"),
            ('"1e5" is "abc"', {}, "false", "answered false"),
            ('"1e10" is "2e10"', {}, "false", "answered false"),
            ('" 3" is "3"', {}, "true", "answered true"),
            ("t is 3", {"t": "3 "}, "true", "answered true"),
            ('"0012" is "12"', {}, "true", "answered true"),
            ('"1_000" is 1000', {}, "false", "answered false"),
            ('"" is 0', {}, "false", "answered false"),
            ("t is 3", {"t": "0" * 400 + "3"}, "true", "answered true"),
            # the integer parse also takes a point and zeros, at any length
            ("t is 12", {"t": "12." + "0" * 400}, "true", "answered true"),
            ('"12a" is "12"', {}, "false", "answered false"),
            # text after the integer parse's number makes the whole TEXT,
            # never a strtod retry (MCU_strtor8 answers on the integer parse
            # whatever its remainder; 2026-09-26, a mutant that read "12 5"
            # as 12 survived every row above)
            ('"12 5" is "12"', {}, "false", "answered false"),
            # a point right after 0x is text before strtod ever runs (the
            # early `p[1] == 'x'` test), where C99's strtod reads 0x.8 as 0.5
            ('"0x.8" is "0.5"', {}, "false", "answered false"),
            ("t is u", {"t": top, "u": top}, "true", "answered true"),
            # past Python's 4300-digit int() limit: text to the engine (too
            # long for strtod, too wide for the integer parse), and the width
            # test must not convert it (a ValueError until 2026-09-26)
            ("t is u", {"t": "1" * 5000, "u": "1" * 5000}, "true",
             "answered true"),
            ("t is u", {"t": "1" * 5000, "u": "2" * 5000}, "false",
             "answered false"),
            # forms the note does NOT establish: refused unless identical
            ('"0x10" is "16"', {}, "unknown", "refused"),
            ('"0x10" is "0x10"', {}, "true", "answered true"),
            ('"0x10" is "abc"', {}, "false", "answered false"),
            ('"inf" is "1e999"', {}, "unknown", "refused"),
            ('"nan" is "nan"', {}, "unknown", "refused"),
            ("t is 3", {"t": "\xa03"}, "unknown", "refused"),
            ('t is "100000"', {"t": "\xa01e5"}, "unknown", "refused"),
            # forms Python reads as numbers and the engine never does
            ("t is 3", {"t": "\u0663"}, "false", "refused"),
            ("t is 3", {"t": "\x1c3"}, "false", "refused"),
            ("t is 1.5", {"t": "1.5" + "0" * 400}, "false", "refused")]:
        c.ck("`is`: %s%s (the engine: %s)" % (expr, short(env), engine),
             verdict(lambda: ev(expr, **env)), want)

    # `<>` is the engine's `is not` (MCLogicEvalIsNotEqualTo), never an
    # ordering: an EMPTY operand is not turned into 0 there.
    for expr, env, engine, want in [
            ('"" <> 0', {}, "true", "refused"),
            ('"" <> 5', {}, "true", "answered true"),
            ('"1e5" <> "100000"', {}, "false", "answered false"),
            ("t <> 3", {"t": "\u0663"}, "true", "refused")]:
        c.ck("`<>`: %s%s (the engine: %s)" % (expr, short(env), engine),
             verdict(lambda: ev(expr, **env)), want)

    # ORDERING (MCLogicCompareTo: an empty operand IS 0 here, a Boolean is
    # text, and text orders as text).
    for expr, env, engine, want in [
            ('"1e5" > 99999', {}, "true", "answered true"),
            ('" 3 " < 4', {}, "true", "answered true"),
            ('"" < 1', {}, "true", "answered true"),
            ('" " < 1', {}, "text order", "refused"),
            ('"1_0" > 5', {}, "text order", "refused"),
            ('"inf" > 5', {}, "unknown", "refused"),
            ('"0x10" > 5', {}, "unknown", "refused"),
            ("t > 0", {"t": True}, "text order", "refused"),
            ("t < 5", {"t": "\u0663"}, "text order", "refused")]:
        c.ck("ordering: %s%s (the engine: %s)" % (expr, short(env), engine),
             verdict(lambda: ev(expr, **env)), want)
    c.ck('ordering: "1e999" > 5 (the engine: true, +inf) is not answered',
         verdict(lambda: ev('"1e999" > 5')).startswith("refused"), True)

    # `is a number` / `is an integer` (MCMathEvalIsAnInteger: the number,
    # then `d == floor(d)` EXACTLY - no tolerance; so 1 + 2^-50 is not one).
    for expr, env, engine, want in [
            ('"1e3" is an integer', {}, "true", "answered true"),
            ('" 3 " is an integer', {}, "true", "answered true"),
            ('"3." is an integer', {}, "true", "answered true"),
            ('"2.5" is an integer', {}, "false", "answered false"),
            ('"12 5" is a number', {}, "false", "answered false"),
            ("1 + 1 / 1125899906842624 is an integer", {}, "false",
             "answered false"),
            ("1 + 1 / 1125899906842624 is a number", {}, "true",
             "answered true"),
            ('"1e999" is a number', {}, "true", "answered true"),
            ('"1e999" is an integer', {}, "true", "refused"),
            ('"0x10" is a number', {}, "unknown", "refused"),
            ('"inf" is a number', {}, "unknown", "refused"),
            ('"nan" is an integer', {}, "unknown", "refused"),
            ('"1_0" is a number', {}, "false", "refused"),
            ("t is a number", {"t": "\u0663"}, "false", "refused"),
            ('"" is a number', {}, "false", "answered false"),
            ('"abc" is not a number', {}, "true", "answered true")]:
        c.ck("%s%s (the engine: %s)" % (expr, short(env), engine),
             verdict(lambda: ev(expr, **env)), want)

    # ARITHMETIC on text: the engine throws where the text is not a number;
    # a Python float() that reads more than strtod must not quietly compute.
    for expr, env, want in [
            ('"1e5" + 1', {}, "answered 100001"),
            ('" 3 " + 1', {}, "answered 4"),
            ('"+3" + 1', {}, "answered 4"),
            ('"1_0" + 1', {}, "refused"),
            ("t + 1", {"t": "\u0663"}, "refused"),
            ('"  " + 1', {}, "refused"),
            ('"nan" + 1', {}, "refused")]:
        c.ck("arithmetic: %s%s" % (expr, short(env)),
             verdict(lambda: ev(expr, **env)), want)

    # THE REFUSAL NAMES ITS SITE: both operands, the operator, the note.
    got = verdict(lambda: ip.call("tnDigestIs", ["12e4", "120000"]))
    c.ck("inside a handler, `is` over two number-like texts is refused",
         got, "refused")
    try:
        ip.call("tnDigestIs", ["12e4", "120000"])
        msg = ""
    except LCS.Indistinct as exc:
        msg = str(exc)
    c.ck("... and the message names both operands, the operator, the "
         "expression and engine note 2.11",
         ('"12e4"' in msg and '"120000"' in msg and "`is`" in msg
          and "pA is pB" in msg and "2.11" in msg), True)
    c.ck("a script `try` cannot swallow it",
         verdict(lambda: ip.call("tnCaughtIs", ["12e4", "120000"])),
         "refused")
    c.ck("a letter prefix keeps the same digests off the number path "
         "(the 2026-09-25 fixes' form)",
         verdict(lambda: ip.call("tnPrefixedIs", ["12e4", "120000"])),
         "answered false")

    # AN `and` / `or` THE ANSWER DOES NOT HANG ON. The engine evaluates both
    # operands (engine note 2.5) and a comparison gives it a Boolean, so
    # `false and X` is false and `true or X` true whatever X reads there: a
    # refused comparison is held back (LCS._Undecided) and dropped where the
    # other operand settles the answer, and refused where nothing does.
    # Found by the census that measured this change: coin-wallet's
    # waCpfpBuild guards with `pRec["fee"] is an integer and pRec["fee"] >=
    # 0`, which compared an EMPTY fee through riptide's runner (as text
    # there then, as 0 on the engine) and answers false either way.
    for expr, want in [
            ("false and 0.1 + 0.2 is 0.3", "answered false"),
            ("0.1 + 0.2 is 0.3 and false", "answered false"),
            ("true or 0.1 + 0.2 is 0.3", "answered true"),
            ('"12e4" is "120000" or true', "answered true"),
            ('"12e4" is "120000" and false', "answered false"),
            ("not 0.1 + 0.2 is 0.3 or true", "answered true"),
            ("true and 0.1 + 0.2 is 0.3", "refused"),
            ("0.1 + 0.2 is 0.3 or false", "refused"),
            ("not 0.1 + 0.2 is 0.3", "refused"),
            ('false or "12e4" is "120000"', "refused"),
            # stricter than it need be, and pinned so a change is seen: a
            # parenthesised comparison is settled at its own parentheses
            ("(0.1 + 0.2 is 0.3) and false", "refused"),
            # text refused on its way into ARITHMETIC is never held back:
            # that throws on the engine, and a throw is no Boolean
            ('false and "1_0" + 1 > 0', "refused")]:
        c.ck("and / or: %s" % expr, verdict(lambda: ev(expr)), want)
    c.ck("inside a handler, a guard whose first half is false settles it",
         verdict(lambda: ip.call("tnMaskedAnd", [0, "12e4", "120000"])),
         "answered not")
    c.ck("... and one whose first half is true does not",
         verdict(lambda: ip.call("tnMaskedAnd", [1, "12e4", "120000"])),
         "refused")


_NUMBER_TEXT_SRC = """
function tnDigestIs pA, pB
   return pA is pB
end tnDigestIs
function tnCaughtIs pA, pB
   local tErr
   try
      return tnDigestIs(pA, pB)
   catch tErr
      return "caught: " & tErr
   end try
end tnCaughtIs
function tnPrefixedIs pA, pB
   return ("h" & pA) is ("h" & pB)
end tnPrefixedIs
function tnMaskedAnd pN, pA, pB
   if pN > 0 and pA is pB then
      return "same"
   end if
   return "not"
end tnMaskedAnd
"""


# --------------------------------------------------------------------- tier 1
def check_constants(c, text):
    """The tables that are transcribed by hand, compared against the reference.

    An alphabet is 58 characters in a specific order that IS the digit mapping;
    one transposed pair silently decodes to a different number. This is the
    cheapest possible check for the likeliest possible bug.
    """
    c.note("constants (no compiler needed)")
    consts = dict(re.findall(r'^constant\s+(\w+)\s*=\s*"([^"]*)"', text, re.M))
    nums = dict(re.findall(r'^constant\s+(\w+)\s*=\s*(-?\d+)\s*$', text, re.M))
    c.ck("the Base58 alphabet matches the reference",
         consts.get("kCxBase58Alphabet"), REF.B58)
    c.ck("the bech32 charset matches the reference",
         consts.get("kCxBech32Charset"), REF.CHARSET)
    c.ck("the hex digits are lowercase 0-f", consts.get("kCxHexDigits"), "0123456789abcdef")
    c.ck("the bech32m constant matches BIP-350",
         int(nums.get("kCxBech32mConst", -1)), REF.BECH32M_CONST)
    c.ck("the bech32 length cap is 90", int(nums.get("kCxBech32MaxLen", -1)), 90)
    c.ck("the mainnet P2PKH version byte is 0", int(nums.get("kCxVersionP2PKH", -1)), 0)
    c.ck("the mainnet HRP is bc", consts.get("kCxHrpMainnet"), "bc")
    c.ck("the mainnet WIF version byte is 0x80",
         int(nums.get("kCxWifVersionMainnet", -1)), REF.WIF_VERSION_MAIN)
    c.ck("the testnet WIF version byte is 0xef",
         int(nums.get("kCxWifVersionTestnet", -1)), REF.WIF_VERSION_TEST)
    # The polymod generator constants live inline, not as named constants.
    gen = re.search(r'put\s+"([\d,]+)"\s+into\s+tGen', text)
    want = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    c.ck("the bech32 polymod generator constants match BIP-173",
         [int(x) for x in gen.group(1).split(",")] if gen else None, want)


# -------------------------------------------------------------------- tier 1b
DEMO = os.path.join(ROOT, "examples", "coinxt-demo.livecodescript")


def check_demo_fields(c):
    """coinxt-demo's integer fields (work-plan row #8, 2026-09-25).

    The demo is not run by any gate, and its build handlers read five
    Ethereum counters, two satoshi amounts and an output index straight from
    fields. They asked `is an integer` (the vout nothing at all), which the
    engine answers yes for "1e20" and for twenty nines, and the arithmetic
    after it (cxHexOfInt, cxUIntToBytesLE) rounded either past 2^53 with no
    error (suite engine note 2.4), so a signed transaction could carry a
    nonce other than the one typed. Every counter now goes through
    cdWholeField, which is lifted out of the SHIPPED demo and run here:
    digits only, at most fifteen, decided on the text before any number
    exists. The build handlers are then read, every field they read found
    by the scan, to prove each one is a counter routed through it or text
    named with a reason, and that none is asked `is an integer` any more.
    No compiler needed; this tier runs where tier 2 SKIPs.
    """
    c.note("\ncoinxt-demo's integer fields (no compiler needed)")
    text = open(DEMO, encoding="utf-8").read()
    m = re.search(r'^function cdWholeField\b.*?^end cdWholeField\b', text, re.S | re.M)
    c.ck("coinxt-demo carries cdWholeField", m is not None, True)
    if m is None:
        return
    ip = LCS.Interp(m.group(0))

    def run(value):
        try:
            return ip.call("cdWholeField", [value, "the nonce"])
        except LCS.Thrown as thrown:
            return "refused: %s" % thrown.msg
        except LCS.Imprecise:
            return "let past 2^53 (the interpreter's stop fired)"
        except Exception as exc:                        # noqa: BLE001
            return "stopped: %s: %s" % (type(exc).__name__, str(exc)[:60])

    for value, want in (("5", 5), (" 42 \n", 42), ("0", 0),
                        ("999999999999999", 999999999999999), ("000000000000005", 5)):
        c.ck("cdWholeField reads %r as %d" % (value, want), run(value), want)
    for value in ("1000000000000000", "99999999999999999999"):
        c.ck("cdWholeField refuses %s: more than fifteen digits, before any "
             "arithmetic" % value, run(value),
             "refused: the nonce has more than 15 digits, past what this demo "
             "holds exactly")
    for value in ("1e20", "3.0", "+3", "-1", "abc", "0x10", "5 6"):
        c.ck("cdWholeField refuses %r: digits only" % value, run(value),
             "refused: the nonce must be a whole number, digits only")
    for value in ("", " \t\n"):
        c.ck("cdWholeField refuses %r: no number at all" % value, run(value),
             "refused: the nonce must be a whole number")

    def code_only(body):
        # comments cut with the string state tracked (root CLAUDE.md,
        # "comments versus literals"): the handlers' own notes quote the old
        # `is an integer` form, and a note is not a test
        out = []
        for line in body.split("\n"):
            quoted, cut = False, len(line)
            for i, ch in enumerate(line):
                if ch == '"':
                    quoted = not quoted
                elif not quoted and line.startswith("--", i):
                    cut = i
                    break
            out.append(line[:cut])
        return "\n".join(out)
    # THE FIELDS ARE DERIVED FROM THE HANDLERS, NOT LISTED (2026-09-26). This
    # tier first named the seven counters it knew of, and the eighth,
    # cdBtcVout, went on to cxBtcOutpoint as typed ("3.5" encoded as vout 3,
    # an empty field as vout 0) under a docstring that said every counter was
    # proven: a hand list is the question already answered (root CLAUDE.md,
    # "a gate is bounded by the question it asks"). Now every field a build
    # handler READS must go through cdWholeField or be named below as text,
    # with the reason; a field written (`into field`) is output. A new field
    # has to be classified before this passes, and an excuse no handler
    # reads any more fails as stale.
    not_counters = {
        "cdBtcPrev": "a txid: 64 hex, checked by cxBtcOutpoint's decode",
        "cdBtcDest": "an address, checked by cxSegwitAddressDecode",
        "cdEthTo": "an address, checked by cdEthAddressHex",
        "cdEthValue": "wei as HEX (it exceeds 2^53), checked by cdCleanHex",
    }
    handlers = ("cdEthBuild", "cdBtcBuild")
    read_as_text = set()
    for handler in handlers:
        body = re.search(r'^command %s\b(.*?)^end %s\b' % (handler, handler),
                         text, re.S | re.M)
        c.ck("coinxt-demo carries %s" % handler, body is not None, True)
        body = code_only(body.group(1)) if body else ""
        written = set(re.findall(r'\binto field "(cd\w+)"', body))
        reads = [f for f in re.findall(r'\bfield "(cd\w+)"', body) if f not in written]
        c.ck("%s reads fields at all (the scan found its target)" % handler,
             len(reads) > 0, True)
        for field in sorted(set(reads)):
            if field in not_counters:
                read_as_text.add(field)
                continue
            c.ck("%s reads field %s through cdWholeField" % (handler, field),
                 re.search(r'cdWholeField\(field "%s"' % field, body) is not None
                 and len(re.findall(r'\bfield "%s"' % field, body))
                 == len(re.findall(r'cdWholeField\(field "%s"' % field, body)),
                 True)
        c.ck("and %s asks no field `is an integer`" % handler,
             re.search(r'\bis (not )?an integer\b', body) is not None, False)
    c.ck("every field excused as text is still read by a build handler",
         sorted(set(not_counters) - read_as_text), [])


# ------------------------------------------------------------------- tier 2b
# coinxt-demo's EIP-55 check, under the ENGINE's case rule (2026-09-26).
# cdEthAddressHex decided "did the caller write a checksum?" with `tPlain is
# not toLower(tPlain)`. `is` folds case on an engine (`the caseSensitive`
# defaults to false, and it is a handler-local property nothing there set),
# so that test was false for every address and the checksum never ran: a
# mixed-case address with one mistyped letter went into the transaction as
# typed. The interpreter's `is` is case-SENSITIVE (coinxt CLAUDE.md trap 22),
# which is why no run of the demo's logic could have seen it. This tier lifts
# the three handlers out of the SHIPPED demo, runs them over the real script
# layer and the shim's Keccak, and asks the same four questions twice: with
# the interpreter's `is`, and with `is` folded the way the engine folds it.
# Then it plants the old test back and requires the folded run to ACCEPT the
# corrupted address, so the fold is proven to see the class it is here for.
_DEMO_ETH_LIFT = ("cdCleanHex", "cdEthAddressHex", "cdIsMixedCase")
_DEMO_ETH_FIXED = "if cdIsMixedCase(tPlain) is true then"
_DEMO_ETH_OLD = "if tPlain is not toLower(tPlain) then"
# the EIP-55 specification's first example, the same with ONE letter's case
# flipped (so its checksum fails), and the two single-case spellings, which
# claim no checksum
_EIP55_GOOD = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
_EIP55_BAD = "0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"


def _demo_eth_unit(layer, demo_text, old=False):
    """The layer plus the three demo handlers, as shipped (or with the old
    mixed-case test planted back). The interpreter models neither `word`
    nor `toLower`, so `word 1 of X` is rewritten to a call answered below
    (asserted to happen exactly twice) and both are answered natively."""
    parts = []
    for name in _DEMO_ETH_LIFT:
        m = re.search(r"^function %s\b.*?^end %s\b[^\n]*" % (name, name),
                      demo_text, re.S | re.M)
        if m is None:
            return None, "coinxt-demo no longer defines %s" % name
        parts.append(m.group(0))
    lifted = "\n\n".join(parts)
    if lifted.count(_DEMO_ETH_FIXED) != 1:
        return None, "cdEthAddressHex no longer carries its mixed-case test"
    if old:
        lifted = lifted.replace(_DEMO_ETH_FIXED, _DEMO_ETH_OLD)
    lifted, words = re.subn(r"\bword 1 of (\w+)\b", r"fxWordOne(\1)", lifted)
    if words != 2:
        return None, "expected `word 1 of` twice in the lifted handlers, found %d" % words
    return LCS.Interp(layer + "\n" + lifted), ""


def check_demo_eth_address(c, layer):
    c.note("\ncoinxt-demo's EIP-55 check, under the interpreter's `is` and the "
           "engine's case fold")
    demo_text = open(DEMO, encoding="utf-8").read()
    saved = {k: LCS.HASHES.get(k) for k in ("fxwordone", "tolower")}
    real_eq = LCS._eq

    def folded_eq(a, b):
        # the engine's default for text: case folds (numbers and arrays keep
        # the interpreter's own answer)
        if real_eq(a, b):
            return True
        if isinstance(a, (dict, bool)) or isinstance(b, (dict, bool)):
            return False
        return str(LCS._disp(a)).lower() == str(LCS._disp(b)).lower()

    def run(ip, address):
        try:
            return "accepted " + str(LCS._disp(ip.call("cdEthAddressHex", [address])))
        except LCS.Thrown as exc:
            msg = str(exc.msg)
            return "refused: checksum" if "FAILS its EIP-55 checksum" in msg \
                else "refused: " + msg[:60]

    lower = _EIP55_GOOD[2:].lower()
    want = {_EIP55_GOOD: "accepted " + lower,
            _EIP55_BAD: "refused: checksum",
            _EIP55_GOOD.lower(): "accepted " + lower,
            "0x" + _EIP55_GOOD[2:].upper(): "accepted " + lower}
    what = {_EIP55_GOOD: "the EIP-55 example (mixed case, checksum good)",
            _EIP55_BAD: "it with one letter's case flipped (checksum bad)",
            _EIP55_GOOD.lower(): "it all-lowercase (no checksum claimed)",
            "0x" + _EIP55_GOOD[2:].upper(): "it all-uppercase (no checksum claimed)"}
    LCS.HASHES["fxwordone"] = lambda args: (str(LCS._disp(args[0])).split() or [""])[0]
    LCS.HASHES["tolower"] = lambda args: str(LCS._disp(args[0])).lower()
    try:
        ip, why = _demo_eth_unit(layer, demo_text)
        c.ck("the three handlers lift out of the shipped demo", why, "")
        if ip is None:
            return
        old_ip, why = _demo_eth_unit(layer, demo_text, old=True)
        for rule in ("interpreter", "engine"):
            if rule == "engine":
                LCS._eq = folded_eq
            try:
                c.ck("the %s rule is the one in force: \"A\" is \"a\"" % rule,
                     ip.eval_expr('"A" is "a"', {}), rule == "engine")
                for address in want:
                    c.ck("cdEthAddressHex, %s `is`: %s" % (rule, what[address]),
                         run(ip, address), want[address])
                # the old test, planted back: blind under the engine's rule
                c.ck("and the OLD mixed-case test, %s `is`, %s the flipped letter"
                     % (rule, "accepts" if rule == "engine" else "refuses"),
                     run(old_ip, _EIP55_BAD),
                     "accepted " + lower if rule == "engine" else "refused: checksum")
            finally:
                LCS._eq = real_eq
    finally:
        LCS._eq = real_eq
        for k, v in saved.items():
            if v is None:
                LCS.HASHES.pop(k, None)
            else:
                LCS.HASHES[k] = v


# --------------------------------------------------------------------- tier 2
def find_cc():
    for cc in (os.environ.get("CC"), "cc", "gcc", "clang"):
        if not cc:
            continue
        try:
            subprocess.run([cc, "--version"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            return cc
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


def build_var(name):
    """One shell variable out of native/build.sh - the single source of truth
    for what the shipped library is made of and how it is compiled."""
    with open(os.path.join(NATIVE, "build.sh"), encoding="utf-8") as fh:
        m = re.search(name + r'="([^"]*)"', fh.read(), re.S)
    if m is None:
        raise SystemExit(f"check-script-vectors: could not read {name} from native/build.sh")
    return [p.strip() for p in m.group(1).replace("\\\n", " ").split() if p.strip()]


def vendor_sources():
    return [os.path.join(VENDOR, p[len("$ven/"):]) for p in build_var("vendor_src")]


def secp_sources():
    return [os.path.join(VENDOR, p[len("$ven/"):]) for p in build_var("secp_src")]


def build(cc, out):
    """Two compile groups, as native/build.sh does it: upstream libsecp256k1's
    units need their own warning scope, and their secp256k1.c shares a BASENAME
    with trezor-crypto's, so objects derived from it must not collide."""
    cflags = build_var("secp_cppflags")
    objs = []
    outdir = os.path.dirname(os.path.abspath(out))
    for src in secp_sources():
        obj = os.path.join(outdir, "secp_" + os.path.basename(src)[:-2] + ".o")
        subprocess.run([cc, "-O2", *build_var("secp_warn"), *cflags,
                        "-fPIC", "-c", src, "-o", obj], check=True)
        objs.append(obj)
    subprocess.run([cc, "-O2", *cflags, "-isystem", VENDOR, "-fPIC", "-shared",
                    os.path.join(NATIVE, "coinxt.c"), *vendor_sources(), *objs,
                    "-o", out],
                   check=True)


def wire_hashes(lib):
    """The .lcb handlers the script calls, supplied by the real shim. What is
    under test is the script's own logic over genuine crypto."""
    for fn in ("cnx_sha256", "cnx_ripemd160", "cnx_keccak256"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lib.cnx_pubkey_decompress.restype = ctypes.c_int
    lib.cnx_pubkey_decompress.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                          ctypes.c_char_p, ctypes.c_size_t]

    def digest(fn, n):
        def go(args):
            data = to_bytes(args[0])
            out = ctypes.create_string_buffer(n)
            if getattr(lib, fn)(data, len(data), out) != 0:
                raise RuntimeError(f"{fn} failed")
            return to_str(out.raw[:n])
        return go

    LCS.HASHES["cxsha256"] = digest("cnx_sha256", 32)
    LCS.HASHES["cxripemd160"] = digest("cnx_ripemd160", 20)
    LCS.HASHES["cxkeccak256"] = digest("cnx_keccak256", 32)

    def decompress(args):
        data = to_bytes(args[0])
        out = ctypes.create_string_buffer(65)
        if lib.cnx_pubkey_decompress(data, len(data), out, 65) != 0:
            raise RuntimeError("cnx_pubkey_decompress failed")
        return to_str(out.raw[:65])

    LCS.HASHES["cxpubkeydecompress"] = decompress

    # ---- phase 4: what the HD layer calls into the shim for -----------------
    lib.cnx_hmac_sha512.restype = ctypes.c_int
    lib.cnx_hmac_sha512.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                    ctypes.c_char_p, ctypes.c_size_t,
                                    ctypes.c_char_p]
    lib.cnx_pbkdf2_hmac_sha512.restype = ctypes.c_int
    lib.cnx_pbkdf2_hmac_sha512.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_uint32, ctypes.c_char_p,
                                           ctypes.c_size_t]
    lib.cnx_pubkey_from_seckey.restype = ctypes.c_int
    lib.cnx_pubkey_from_seckey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_int, ctypes.c_char_p,
                                           ctypes.c_size_t]
    for fn in ("cnx_seckey_tweak_add", "cnx_pubkey_tweak_add"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
                      ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_bip39_wordlist.restype = ctypes.c_int
    lib.cnx_bip39_wordlist.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_bip39_wordlist_len.restype = ctypes.c_size_t

    def hmac512(args):
        key, msg = to_bytes(args[0]), to_bytes(args[1])
        out = ctypes.create_string_buffer(64)
        if lib.cnx_hmac_sha512(key, len(key), msg, len(msg), out) != 0:
            raise RuntimeError("cnx_hmac_sha512 failed")
        return to_str(out.raw[:64])

    def pbkdf2(args):
        pw, salt = to_bytes(args[0]), to_bytes(args[1])
        rounds, outlen = int(LCS._n(args[2])), int(LCS._n(args[3]))
        out = ctypes.create_string_buffer(outlen)
        if lib.cnx_pbkdf2_hmac_sha512(pw, len(pw), salt, len(salt), rounds,
                                      out, outlen) != 0:
            raise RuntimeError("cnx_pbkdf2_hmac_sha512 failed")
        return to_str(out.raw[:outlen])

    def publickey(args):
        sk = to_bytes(args[0])
        compressed = str(LCS._disp(args[1])).lower() == "true" if len(args) > 1 else True
        n = 33 if compressed else 65
        out = ctypes.create_string_buffer(n)
        rc = lib.cnx_pubkey_from_seckey(sk, len(sk), 1 if compressed else 0, out, n)
        if rc != 0:
            # The .lcb wrapper throws on a non-zero status; so must this, or
            # the script's own error paths would never be exercised.
            raise LCS.Thrown(f"CoinXT: cxPublicKey: status {rc}")
        return to_str(out.raw[:n])

    def tweak(fn, n):
        def go(args):
            a, t = to_bytes(args[0]), to_bytes(args[1])
            out = ctypes.create_string_buffer(n)
            rc = getattr(lib, fn)(a, len(a), t, len(t), out, n)
            if rc != 0:
                raise LCS.Thrown(f"CoinXT: {fn}: status {rc}")
            return to_str(out.raw[:n])
        return go

    def wordlist(_args):
        n = lib.cnx_bip39_wordlist_len()
        out = ctypes.create_string_buffer(n)
        if lib.cnx_bip39_wordlist(out, n) != 0:
            raise RuntimeError("cnx_bip39_wordlist failed")
        return to_str(out.raw[:n])

    # ---- WIF: the range check both directions make ---------------------------
    # cxSeckeyIsValid answers false for zero / >= order / a wrong length
    # (statuses -1, -2, -4) and throws on anything else, mirroring the .lcb
    # wrapper exactly - the WIF handlers' fail-closed paths depend on that
    # split, so approximating it would test a different library.
    lib.cnx_seckey_verify.restype = ctypes.c_int
    lib.cnx_seckey_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t]

    def seckeyisvalid(args):
        sk = to_bytes(args[0])
        rc = lib.cnx_seckey_verify(sk, len(sk))
        if rc == 0:
            return True
        if rc in (-1, -2, -4):
            return False
        raise LCS.Thrown(f"CoinXT: cxSeckeyIsValid: status {rc}")

    # ---- ABI 6: what the Taproot script handlers call into the shim ---------
    # cxTaprootTweak slices a 33-byte record (x-only output key || parity) and
    # asks the shim for the key width rather than writing 32 down again, so
    # both the call and the accessor have to be here or the script's own
    # slicing would not be what runs.
    lib.cnx_taproot_tweak_pubkey.restype = ctypes.c_int
    lib.cnx_taproot_tweak_pubkey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                             ctypes.c_char_p, ctypes.c_size_t,
                                             ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_xonly_pubkey_len.restype = ctypes.c_size_t

    def taproottweakpubkey(args):
        internal, root = to_bytes(args[0]), to_bytes(args[1])
        out = ctypes.create_string_buffer(33)
        rc = lib.cnx_taproot_tweak_pubkey(internal, len(internal),
                                          root if root else None, len(root), out, 33)
        if rc != 0:
            # The .lcb wrapper throws on a non-zero status, so this must too or
            # the script's refusal paths would never execute.
            raise LCS.Thrown(f"CoinXT: cxTaprootTweakPubkey: status {rc}")
        return to_str(out.raw[:33])

    LCS.HASHES["cxtaproottweakpubkey"] = taproottweakpubkey
    LCS.HASHES["cxxonlypubkeylen"] = lambda _args: lib.cnx_xonly_pubkey_len()

    # ---- ABI 7: point addition, for BIP-352 receiving -----------------------
    lib.cnx_pubkey_combine.restype = ctypes.c_int
    lib.cnx_pubkey_combine.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                       ctypes.c_char_p, ctypes.c_size_t]

    def pubkeycombine(args):
        keys = to_bytes(args[0])
        out = ctypes.create_string_buffer(33)
        rc = lib.cnx_pubkey_combine(keys if keys else None, len(keys), out, 33)
        if rc != 0:
            raise LCS.Thrown(f"CoinXT: cxPubkeyCombine: status {rc}")
        return to_str(out.raw[:33])

    LCS.HASHES["cxpubkeycombine"] = pubkeycombine

    LCS.HASHES["cxhmacsha512"] = hmac512
    LCS.HASHES["cxpbkdf2hmacsha512"] = pbkdf2
    LCS.HASHES["cxpublickey"] = publickey
    LCS.HASHES["cxseckeytweakadd"] = tweak("cnx_seckey_tweak_add", 32)
    LCS.HASHES["cxpubkeytweakadd"] = tweak("cnx_pubkey_tweak_add", 33)
    LCS.HASHES["cxbip39wordlist"] = wordlist
    LCS.HASHES["cxseckeyisvalid"] = seckeyisvalid


def to_bytes(s):
    return bytes(ord(ch) & 0xFF for ch in str(LCS._disp(s)))


def to_str(b):
    return "".join(chr(x) for x in b)


# BIP-341's published wallet test vectors, the fields this layer can check:
# (internal x-only key, merkle root or "", expected x-only output key, expected
# BIP-350 address). Entry 0 is the KEY-PATH-ONLY case - the merkle root is the
# specification's EMPTY BYTE STRING, not 32 zero bytes - which is the one that
# separates a correct implementation from a plausible wrong one.
#   source: https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json
TAPROOT_SCRIPT_VECTORS = [
    ("d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d",
     "",
     "53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343",
     "bc1p2wsldez5mud2yam29q22wgfh9439spgduvct83k3pm50fcxa5dps59h4z5"),
    ("187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27",
     "5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21",
     "147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3",
     "bc1pz37fc4cn9ah8anwm4xqqhvxygjf9rjf2resrw8h8w4tmvcs0863sa2e586"),
    ("93478e9488f956df2396be2ce6c5cced75f900dfa18e7dabd2428aae78451820",
     "c525714a7f49c28aedbbba78c005931a81c234b2f6c99a73e4d06082adc8bf2b",
     "e4d810fd50586274face62b8a807eb9719cef49c04177cc6b76a9a4251d5450e",
     "bc1punvppl2stp38f7kwv2u2spltjuvuaayuqsthe34hd2dyy5w4g58qqfuag5"),
]

# BIP-340 test vector 5's public key: a 32-byte value that is NOT the abscissa
# of any curve point. Used where an x-only key must be REFUSED rather than
# quietly tweaked into a plausible address.
OFF_CURVE_XONLY = "eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34"

G33 = bytes.fromhex("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
G65 = bytes.fromhex("0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
                    "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8")

BECH32_VALID = [
    "A12UEL5L", "a12uel5l",
    "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
    "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
    "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
    "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
    "?1ezyfcl",
]
BECH32_INVALID = [
    ("an HRP character out of range", "\x201nwldj5"),
    ("an HRP character 0x7f", "\x7f1axkwrx"),
    ("longer than 90 characters",
     "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx"),
    ("no separator", "pzry9x0s0muk"),
    ("an empty HRP", "1pzry9x0s0muk"),
    ("a data character outside the charset", "x1b4n0q5v"),
    ("a checksum shorter than six characters", "li1dgmt3"),
    ("a checksum computed over an uppercase HRP", "A1G7SGD8"),
    ("an empty HRP (2)", "10a06t8"),
    ("an empty HRP (3)", "1qzzfhee"),
]
SEGWIT = [
    ("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4", "bc", 0,
     "751e76e8199196d454941c45d1b3a323f1433bd6"),
    ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", "tb", 0,
     "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262"),
    ("bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y", "bc", 1,
     "751e76e8199196d454941c45d1b3a323f1433bd6751e76e8199196d454941c45d1b3a323f1433bd6"),
    ("BC1SW50QGDZ25J", "bc", 16, "751e"),
    ("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", "bc", 2, "751e76e8199196d454941c45d1b3a323"),
    ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", "bc", 1,
     "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
]
# BIP-350's rule is a PAIRING and has two halves. Testing only the v0 half
# leaves the other rule untested, which mutation testing caught: disabling the
# "v1+ must be bech32m" branch changed nothing observable. The v1-with-bech32
# case is CONSTRUCTED from the reference rather than quoted, so it is provably
# the thing being described - a valid v1 program under the WRONG checksum.
def _wrong_spec(version, prog_hex, spec):
    """A VALID address body under the WRONG checksum algorithm for its witness
    version. Both halves have to be constructed rather than quoted, and the
    reason is worth recording: BIP-350's published invalid vector for this case
    (BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5) has a checksum that verifies as
    NEITHER bech32 nor bech32m, so a decoder rejects it at the checksum and never
    reaches the version/spec pairing at all. Mutation testing caught exactly
    that: disabling the pairing rule changed nothing observable. These two do
    reach it, because their checksums are correct - for the wrong algorithm.
    """
    prog = bytes.fromhex(prog_hex)
    return REF.bech32_encode("bc", [version] + REF.convertbits(prog, 8, 5), spec)


SEGWIT_INVALID = [
    # The published vector, kept: it is a real BIP-350 invalid case (bad checksum).
    ("a corrupt version 0 address", "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5"),
    # And the two that actually exercise the BIP-350 pairing rule.
    ("a version 0 address carrying a VALID bech32m checksum",
     _wrong_spec(0, "751e76e8199196d454941c45d1b3a323f1433bd6", "bech32m")),
    ("a version 1 address carrying a VALID bech32 checksum",
     _wrong_spec(1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", "bech32")),
    ("a mixed-case address", "bc1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4"),
    ("a witness version above 16", "BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R"),
    ("an empty data section", "bc1gmk9yu"),
]
EIP55 = ["0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
         "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
         "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
         "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"]

# The entropy column of the official BIP-39 english vectors (trezor's
# english.json). Only the entropy is written down: the mnemonic and the seed
# come from REF, which derives them and self-checks the wordlist against the
# SHA-256 BIP-39 publishes. Copying 14 mnemonics and 14 seeds by hand would add
# 28 chances to make a transcription error and zero checking power.
BIP39_ENTROPY = [
    "00000000000000000000000000000000", "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
    "80808080808080808080808080808080", "ffffffffffffffffffffffffffffffff",
    "000000000000000000000000000000000000000000000000",
    "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
    "808080808080808080808080808080808080808080808080",
    "0000000000000000000000000000000000000000000000000000000000000000",
    "8080808080808080808080808080808080808080808080808080808080808080",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    "9e885d952ad362caeb4efe34a8e91bd2", "c0ba5a8e914111210f2bd131f3d5e08d",
    "23db8160a31d3e0dca3688ed941adbf3",
    "066dca1a2bb7e8a1db2832148ce9933eea0f3ac9548d793112d9a95c9407efad",
]

# BIP-32's own test vectors 1, 2 and 3, written out in full because THESE are
# the published artifact - the whole point is that CoinXT's serialization
# matches the strings in the BIP, not that it matches our own model twice.
# Vector 3 is in the BIP specifically because its master private key has a
# leading zero byte, which is where "strip leading zeros" bugs surface.
BIP32_VECTORS = [
    ("000102030405060708090a0b0c0d0e0f", [
        ("m",
         "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
         "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"),
        ("m/0'",
         "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7",
         "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"),
        ("m/0'/1",
         "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs",
         "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ"),
        ("m/0'/1/2'/2/1000000000",
         "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76",
         "xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy"),
    ]),
    ("fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2"
     "9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542", [
        ("m",
         "xprv9s21ZrQH143K31xYSDQpPDxsXRTUcvj2iNHm5NUtrGiGG5e2DtALGdso3pGz6ssrdK4PFmM8NSpSBHNqPqm55Qn3LqFtT2emdEXVYsCzC2U",
         "xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB"),
    ]),
    ("4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4ac"
     "ba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be", [
        ("m",
         "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6",
         "xpub661MyMwAqRbcEZVB4dScxMAdx6d4nFc9nvyvH3v4gJL378CSRZiYmhRoP7mBy6gSPSCYk6SzXPTf3ND1cZAceL7SfJ1Z3GC8vBgp2epUt13"),
    ]),
]

# The published addresses for the "abandon ... about" test mnemonic - the most
# widely cross-checked wallet in existence, and the closest thing to an
# interoperability oracle that does not require a wallet to hand. The m/84'
# entries are BIP-84's own test vectors.
BIP44_ADDRESSES = [
    ("m/44'/0'/0'/0/0", "p2pkh", "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"),
    ("m/84'/0'/0'/0/0", "p2wpkh", "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"),
    ("m/84'/0'/0'/0/1", "p2wpkh", "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g"),
    ("m/84'/0'/0'/1/0", "p2wpkh", "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el"),
    ("m/44'/60'/0'/0/0", "eth", "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"),
]


def _even_hex(n):
    """A non-negative integer as minimal big-endian hex, padded to whole bytes -
    the shape a wei-scale field crosses to the script as (cxHexDecode wants an
    even length; cxStripLeadingZeroBytes then makes it canonical for RLP)."""
    h = format(n, "x")
    return ("0" + h) if len(h) % 2 else h


def _phase5_fixture():
    """Everything the phase-5 executing checks consume, derived once from the
    oracle. The ECDSA signatures are RFC 6979 deterministic, so the oracle's
    exact (r, s) can be fed straight to the encoders here - what is under test is
    the SCRIPT's DER / sighash / varint / witness / RLP / transaction
    serialization over genuine crypto, not a signer in the interpreter."""
    ver, lock = 1, 17
    txid0 = "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"
    txid1 = "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"
    op0 = REF.btc_outpoint(bytes.fromhex(txid0), 0)
    op1 = REF.btc_outpoint(bytes.fromhex(txid1), 1)
    seq0, seq1 = 0xffffffee, 0xffffffff
    spk0 = "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
    spk1 = "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
    out0 = REF.btc_output(0x06b22c20, bytes.fromhex(spk0))
    out1 = REF.btc_output(0x0d519390, bytes.fromhex(spk1))
    sc0 = "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac"
    sc1 = "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac"
    ins, outs = [(op0, seq0), (op1, seq1)], [out0, out1]
    d0 = REF.btc_sighash_legacy(ver, ins, outs, 0, bytes.fromhex(sc0), lock)
    d1 = REF.btc_sighash_segwit(ver, ins, outs, 1, bytes.fromhex(sc1), 0x23c34600, lock)
    r0, s0, _ = REF.ecdsa_sign_recoverable(
        bytes.fromhex("bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"), d0)
    r1, s1, _ = REF.ecdsa_sign_recoverable(
        bytes.fromhex("619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"), d1)
    sig0 = REF.der_encode(r0, s0) + b"\x01"
    sig1 = REF.der_encode(r1, s1) + b"\x01"
    pub1 = "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
    wit1 = (REF.varint(2) + REF.varint(len(sig1)) + sig1
            + REF.varint(len(pub1) // 2) + bytes.fromhex(pub1))
    scriptsig0 = (bytes([len(sig0)]) + sig0).hex()
    raw, txid = REF.btc_tx(ver, ins, outs, lock,
                           [bytes([len(sig0)]) + sig0, b""],
                           [[], [sig1, bytes.fromhex(pub1)]])
    assert raw.hex() == REF.BIP143_SIGNED_TX, "fixture drifted from the oracle"
    to, sk46 = "3535353535353535353535353535353535353535", bytes.fromhex("46" * 32)
    h155 = REF.eth_legacy_sighash(9, 20 * 10**9, 21000, bytes.fromhex(to), 10**18, b"", 1)
    r155, s155, recid155 = REF.ecdsa_sign_recoverable(sk46, h155)
    raw155, txhash155 = REF.eth_legacy_encode(9, 20 * 10**9, 21000, bytes.fromhex(to),
                                              10**18, b"", 1, sk46)
    h1559 = REF.eth_1559_sighash(1, 0, 10**9, 20 * 10**9, 21000, bytes.fromhex(to), 10**17, b"")
    r1559, s1559, recid1559 = REF.ecdsa_sign_recoverable(sk46, h1559)
    raw1559, txhash1559 = REF.eth_1559_encode(1, 0, 10**9, 20 * 10**9, 21000,
                                              bytes.fromhex(to), 10**17, b"", sk46)
    return {
        "txid0": txid0, "op0": op0, "spk0": spk0,
        "outpoints": op0.hex() + "," + op1.hex(), "sequences": f"{seq0},{seq1}",
        "outputs": out0.hex() + "," + out1.hex(), "sc0": sc0, "sc1": sc1,
        "d0": d0, "d1": d1, "rs0": (r0, s0),
        "compact0": r0.to_bytes(32, "big") + s0.to_bytes(32, "big"),
        "witness1": sig1.hex() + "," + pub1, "wit1": wit1,
        # scriptSigs = [scriptsig0, ""] and witnesses = ["", wit1]: the
        # trailing-empty and leading-empty shapes the reference tx needs.
        "scriptsigs": scriptsig0 + ",", "witnesses": "," + wit1.hex(), "txid": txid,
        "ethTo": to, "ethGasPrice": _even_hex(20 * 10**9), "ethValue": _even_hex(10**18),
        "h155": h155, "recid155": recid155,
        "r155hex": r155.to_bytes(32, "big").hex(), "s155hex": s155.to_bytes(32, "big").hex(),
        "raw155": raw155, "txhash155": txhash155,
        "m1559prio": _even_hex(10**9), "m1559fee": _even_hex(20 * 10**9),
        "v1559": _even_hex(10**17), "h1559": h1559, "recid1559": recid1559,
        "r1559hex": r1559.to_bytes(32, "big").hex(), "s1559hex": s1559.to_bytes(32, "big").hex(),
        "raw1559": raw1559, "txhash1559": txhash1559,
    }


def check_vectors(c, ip):
    def call(fn, *args):
        return ip.call(fn, [to_str(a) if isinstance(a, (bytes, bytearray)) else a
                            for a in args])

    def throws(fn, *args):
        try:
            call(fn, *args)
            return False
        except LCS.Thrown:
            return True

    def throw_text(fn, *args):
        """The MESSAGE a refusal throws, not just the fact that it threw.

        Added 2026-08-16 after a mutation SURVIVED: deleting cxTaprootTweak's
        merkle-root length guard changed nothing this gate could see, because
        the shim refuses the same input a layer down with CNX_ERR_BADLEN and
        `throws` cannot tell the two apart. The guard is real, but what it
        actually buys is a message that names the handler and the argument
        instead of a generic "a buffer had the wrong length" - so that is what
        has to be asserted, or the guard is untested by construction."""
        try:
            call(fn, *args)
            return "(did not throw)"
        except LCS.Thrown as exc:
            return str(exc)

    c.note("\nhex")
    c.ck("cxHexEncode", call("cxHexEncode", bytes.fromhex("00ff10ab")), "00ff10ab")
    c.ck("cxHexDecode accepts mixed case",
         to_bytes(call("cxHexDecode", "00FF10ab")).hex(), "00ff10ab")
    c.ck("cxHexDecode rejects an odd length", throws("cxHexDecode", "abc"), True)
    c.ck("cxHexDecode rejects a non-hex character", throws("cxHexDecode", "zz"), True)

    c.note("\ncomposed hashes")
    for data in (b"", b"abc", b"hello world"):
        c.ck(f"cxHash160({data!r})", to_bytes(call("cxHash160", data)).hex(),
             REF.hash160(data).hex())
        c.ck(f"cxHash256({data!r})", to_bytes(call("cxHash256", data)).hex(),
             REF.hash256(data).hex())

    c.note("\nBase58Check")
    payload = bytes.fromhex("00010966776006953D5567439E5E39F86A0D273BEE")
    c.ck("encodes the worked example", call("cxBase58CheckEncode", payload),
         "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM")
    c.ck("decodes it back",
         to_bytes(call("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM")).hex(),
         payload.hex())
    c.ck("rejects a corrupt checksum",
         throws("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvN"), True)
    c.ck("rejects a character outside the alphabet",
         throws("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtj0O"), True)
    for n in (1, 2, 5):
        p = bytes(n) + bytes.fromhex("deadbeef")
        c.ck(f"preserves {n} leading zero byte(s) as leading ones",
             call("cxBase58CheckEncode", p), REF.b58check_encode(p))

    c.note("\nWIF (wallet import format)")
    # The Bitcoin wiki's worked-example key. The expectations are DERIVED from
    # the reference, whose import self-check anchors the mainnet/uncompressed
    # form to the wiki's published string - so these four are pinned to a
    # public artifact, not to the script agreeing with itself.
    wif_sk = bytes.fromhex("0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d")
    for network in ("mainnet", "testnet"):
        for compressed in (False, True):
            wif = REF.wif_encode(wif_sk, network, compressed)
            c.ck(f"encodes {network} compressed={str(compressed).lower()}",
                 call("cxWifEncode", wif_sk.hex(), network, compressed), wif)
            got = ip.call("cxWifDecode", [wif])
            c.ck(f"  and decodes back to the key, the network and the flag",
                 (got["seckey"], got["network"], LCS._disp(got["compressed"])),
                 (wif_sk.hex(), network, "true" if compressed else "false"))
    # The refusals, one per failure mode the decoder names. Each malformed body
    # is CONSTRUCTED through the reference's own b58check encoder so its
    # checksum is valid and the check under test is provably the one reached
    # (the _wrong_spec lesson above: a bad checksum masks every later check).
    c.ck("rejects a corrupt checksum",
         throws("cxWifDecode", REF.wif_encode(wif_sk, "mainnet", False)[:-1] + "k"), True)
    c.ck("rejects an xprv (wrong payload length)",
         throws("cxWifDecode", BIP32_VECTORS[0][1][0][1]), True)
    c.ck("rejects an unknown version byte",
         throws("cxWifDecode", REF.b58check_encode(b"\x01" + wif_sk + b"\x01")), True)
    c.ck("rejects a trailing byte that is not the 0x01 marker",
         throws("cxWifDecode", REF.b58check_encode(b"\x80" + wif_sk + b"\x02")), True)
    c.ck("rejects a zero key", throws("cxWifDecode", REF.b58check_encode(b"\x80" + bytes(32))), True)
    c.ck("rejects a key at or above the group order",
         throws("cxWifDecode", REF.b58check_encode(b"\x80" + b"\xff" * 32 + b"\x01")), True)
    c.ck("cxWifEncode refuses a short key",
         throws("cxWifEncode", wif_sk[:31].hex(), "mainnet", True), True)
    c.ck("cxWifEncode refuses non-hex", throws("cxWifEncode", "zz" * 32, "mainnet", True), True)
    c.ck("cxWifEncode refuses a zero key",
         throws("cxWifEncode", "00" * 32, "mainnet", True), True)
    c.ck("cxWifEncode refuses an unknown network",
         throws("cxWifEncode", wif_sk.hex(), "regtest", True), True)
    c.ck("cxWifEncode refuses a non-boolean compressed flag",
         throws("cxWifEncode", wif_sk.hex(), "mainnet", "yes"), True)

    c.note("\nBIP-173 valid strings")
    for s in BECH32_VALID:
        c.ck(f"accepts {s[:32]}", throws("cxBech32DecodeValues", s), False)
    c.note("\nBIP-173 invalid strings")
    for name, s in BECH32_INVALID:
        c.ck(f"rejects {name}", throws("cxBech32DecodeValues", s), True)

    c.note("\nBIP-173 / BIP-350 SegWit addresses")
    for addr, hrp, ver, prog in SEGWIT:
        c.ck(f"encodes {addr[:24]}",
             call("cxSegwitAddressEncode", hrp, ver, bytes.fromhex(prog)), addr.lower())
        got = ip.call("cxSegwitAddressDecode", [hrp, addr])
        c.ck(f"decodes {addr[:24]}",
             (int(LCS._n(got["version"])), to_bytes(got["program"]).hex()), (ver, prog))
    c.note("\nBIP-350 invalid SegWit addresses")
    for name, addr in SEGWIT_INVALID:
        c.ck(f"rejects {name}", throws("cxSegwitAddressDecode", "bc", addr), True)

    c.note("\naddresses from the generator G (private key 1)")
    c.ck("cxBtcAddressP2PKH", call("cxBtcAddressP2PKH", G33), REF.p2pkh(G33))
    c.ck("cxBtcAddressP2WPKH is the published BIP-173 vector",
         call("cxBtcAddressP2WPKH", G33), "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    c.ck("cxBtcAddressP2TR is the published BIP-350 vector",
         call("cxBtcAddressP2TR", G65[1:33]),
         "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0")
    c.ck("cxBtcAddressP2WPKH refuses an uncompressed key",
         throws("cxBtcAddressP2WPKH", G65), True)
    c.ck("cxBtcAddressP2TR refuses a 33-byte key", throws("cxBtcAddressP2TR", G33), True)

    # ---- BIP-341: the tweak, and the address builder that applies it --------
    # The ABI-6 additions, executed through the REAL script over the REAL shim.
    # Every expectation is BIP-341's own published wallet vector or is derived
    # by tools/coin_reference.py's independent model (itself anchored to those
    # vectors at import) - never by the library under test.
    c.note("\nBIP-341 Taproot (cxTaprootTweak, cxBtcAddressP2TRFromInternal)")

    def tweak(internal, root):
        got = ip.call("cxTaprootTweak", [to_str(internal), to_str(root)])
        return to_bytes(got["outputKey"]), int(LCS._n(got["parity"]))

    for i, (ipub_hex, root_hex, want_out, want_addr) in enumerate(TAPROOT_SCRIPT_VECTORS):
        ipub = bytes.fromhex(ipub_hex)
        root = bytes.fromhex(root_hex) if root_hex else b""
        out, parity = tweak(ipub, root)
        label = "no merkle root" if not root_hex else "script-tree root"
        c.ck(f"vector {i} ({label}): output key", out.hex(), want_out)
        # The vector file publishes only x-only keys, so the parity byte has no
        # published expectation; it comes from the independent model instead.
        c.ck(f"vector {i}: parity byte", parity,
             REF.taproot_tweak_pubkey(ipub, root or None)[1])
        c.ck(f"vector {i}: bech32m address",
             call("cxBtcAddressP2TRFromInternal", ipub, root), want_addr)

    # THE CONSENSUS DISTINCTION, at the script layer this time: an EMPTY merkle
    # root is the specification's empty byte string and NOT 32 zero bytes. If
    # the script ever passed one for the other, every key-path-only address it
    # produced would be wrong and would still look like an address.
    ipub0 = bytes.fromhex(TAPROOT_SCRIPT_VECTORS[0][0])
    c.ck("an empty merkle root is not a 32-zero root",
         tweak(ipub0, b"")[0] != tweak(ipub0, bytes(32))[0], True)
    c.ck("  the zero root is accepted, not refused (it is a legal commitment)",
         tweak(ipub0, bytes(32))[0].hex(),
         REF.taproot_tweak_pubkey(ipub0, bytes(32))[0].hex())

    # cxBtcAddressP2TR is UNCHANGED and must stay unchanged: it encodes the
    # OUTPUT key it is given and never tweaks. Asserting that the two handlers
    # disagree on the same 32 bytes is what stops a future edit from quietly
    # making the old one tweak - which would turn every existing correct call
    # into a DOUBLE tweak, i.e. a valid-looking unspendable address.
    c.ck("cxBtcAddressP2TR still does NOT tweak",
         call("cxBtcAddressP2TR", ipub0) != call("cxBtcAddressP2TRFromInternal", ipub0, b""),
         True)
    c.ck("  it still encodes the key it is given, unchanged",
         call("cxBtcAddressP2TR", ipub0), REF.p2tr(ipub0))

    c.ck("cxTaprootTweak refuses a 33-byte internal key",
         throws("cxTaprootTweak", G33, b""), True)
    c.ck("cxTaprootTweak refuses a 31-byte merkle root",
         throws("cxTaprootTweak", ipub0, bytes(31)), True)
    # ... and refuses it IN ITS OWN WORDS. Without this the script-level guard
    # is invisible to the gate: the shim rejects a 31-byte root too, so
    # deleting the guard leaves a throw either way (measured - that mutation
    # survived until this check existed). What the guard buys is a message that
    # names the handler and the argument.
    c.ck("  in its own words, naming the handler and the merkle root",
         "cxTaprootTweak" in throw_text("cxTaprootTweak", ipub0, bytes(31))
         and "merkle root" in throw_text("cxTaprootTweak", ipub0, bytes(31)),
         True)
    c.ck("cxTaprootTweak refuses an internal key that is not on the curve",
         throws("cxTaprootTweak", bytes.fromhex(OFF_CURVE_XONLY), b""), True)
    c.ck("cxBtcAddressP2TRFromInternal refuses a 33-byte key",
         throws("cxBtcAddressP2TRFromInternal", G33, b""), True)

    c.ck("cxEthAddress from a compressed key", call("cxEthAddress", G33),
         REF.eth_address(G65))
    c.ck("cxEthAddress from an uncompressed key", call("cxEthAddress", G65),
         REF.eth_address(G65))

    c.note("\nEIP-55")
    for a in EIP55:
        c.ck(f"checksums {a[:12]}", call("cxEthAddressChecksum", a.lower()), a)
        c.ck(f"recognises {a[:12]} as checksummed",
             LCS._disp(call("cxEthAddressIsChecksummed", a)), "true")
    c.ck("reports an all-lowercase address as NOT checksummed",
         LCS._disp(call("cxEthAddressIsChecksummed",
                        "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")), "false")

    c.note("\nRLP")
    lorem = b"Lorem ipsum dolor sit amet, consectetur adipisicing elit"
    for data, want in ((b"dog", "83646f67"), (b"", "80"), (b"\x0f", "0f"),
                       (b"\x04\x00", "820400"), (lorem, REF.rlp_encode(lorem).hex())):
        c.ck(f"encodes {data[:20]!r}", to_bytes(call("cxRlpEncodeBytes", data)).hex(), want)
    cat_dog = to_bytes(call("cxRlpEncodeBytes", b"cat")) + to_bytes(call("cxRlpEncodeBytes", b"dog"))
    c.ck("encodes the list [cat, dog]",
         to_bytes(call("cxRlpEncodeList", cat_dog)).hex(), "c88363617483646f67")
    c.ck("encodes the empty list", to_bytes(call("cxRlpEncodeList", b"")).hex(), "c0")
    for enc, kind, payload in (("83646f67", "bytes", "646f67"), ("80", "bytes", ""),
                               ("c88363617483646f67", "list", "8363617483646f67"),
                               (REF.rlp_encode(lorem).hex(), "bytes", lorem.hex())):
        got = ip.call("cxRlpDecode", [to_str(bytes.fromhex(enc))])
        c.ck(f"decodes {enc[:14]}", (got["kind"], to_bytes(got["payload"]).hex()),
             (kind, payload))
    c.ck("rejects a single byte below 0x80 wrapped in a length prefix",
         throws("cxRlpDecode", bytes.fromhex("8100")), True)
    c.ck("rejects a leading zero in a long length",
         throws("cxRlpDecode", bytes.fromhex("b90040" + "00" * 64)), True)

    # ---- the regression set ------------------------------------------------
    # One vector per defect an adversarial review found in the code above, each
    # of which the vectors that preceded it could not catch. They are grouped
    # here rather than scattered because what they have in common is the point:
    # every one of them FAILED OPEN - a wrong answer that looked like a right
    # one - which is the only failure mode on this surface that matters.
    c.note("\nfail-closed regressions (one per defect found by review)")

    # EIP-55's whole purpose. The handler used to compare a value with itself
    # (cxEthAddressChecksum lowercases before hashing, so both sides were the
    # same string) and answered true to every mixed-case address. The four
    # positive vectors above could not see it, because a true positive is what
    # a tautology also returns.
    for name, addr in (
            ("one letter's case flipped", "0xfb6916095ca1df60bB79Ce92cE3Ea74c37c5d359"),
            ("the last letter upper-cased", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"),
            ("every letter's case flipped", "0x5AaEB6053f3e94c9B9a09F33669435e7eF1bEaEd")):
        c.ck(f"a corrupted EIP-55 address is refused ({name})",
             LCS._disp(call("cxEthAddressIsChecksummed", addr)), "false")

    # An in-band error sentinel over arbitrary bytes is always wrong. This is a
    # real bech32m v1 address whose 32-byte witness program begins with the
    # bytes 45 52 52 4F 52, and the decoder used to read that as its own failure
    # string and reject an address this file had just produced.
    prog = b"ERROR" + bytes(range(27))
    addr = call("cxSegwitAddressEncode", "bc", 1, prog)
    c.ck("an address encodes when its program spells ERROR",
         addr, REF.segwit_encode("bc", 1, prog))
    got = ip.call("cxSegwitAddressDecode", ["bc", addr])
    c.ck("  and decodes back to the same program",
         (int(LCS._n(got["version"])), to_bytes(got["program"]).hex()), (1, prog.hex()))

    # hash160 hashes anything, so without a length and prefix check every one of
    # these produced a well-formed, checksummed, permanently unspendable address.
    for name, key in (("an empty key", b""), ("a 20-byte hash", bytes(20)),
                      ("33 bytes tagged 0x04", b"\x04" + bytes(32)),
                      ("65 bytes tagged 0x02", b"\x02" + bytes(64)),
                      ("a 34-byte key", b"\x02" + bytes(33))):
        c.ck(f"cxBtcAddressP2PKH refuses {name}", throws("cxBtcAddressP2PKH", key), True)
    c.ck("cxBtcAddressP2PKH still accepts an uncompressed key",
         call("cxBtcAddressP2PKH", G65), REF.p2pkh(G65))

    # `char (n) of` a 32-character charset returns EMPTY past the end, so an
    # out-of-range value used to emit nothing at all: a string one character
    # short, with a checksum over data that is not in it.
    c.ck("cxBech32EncodeValues refuses a value of 32",
         throws("cxBech32EncodeValues", "bc", "0,32,1", "bech32"), True)
    c.ck("cxBech32EncodeValues refuses a negative value",
         throws("cxBech32EncodeValues", "bc", "0,-1", "bech32"), True)
    c.ck("cxBech32EncodeValues refuses a fractional value",
         throws("cxBech32EncodeValues", "bc", "0,1.5", "bech32"), True)
    # WHOLE, DECIDED EXACTLY (2026-09-25; work-plan row #8). The guard was
    # `tIndex is not trunc(tIndex)`, and the engine's `is` calls numbers
    # within 10 DBL_EPSILON EQUAL (suite engine note 2.10), so the first two
    # went through there; this interpreter answered the old guard the IEEE
    # way, refusing them anyway (since 2026-09-25 it refuses to DECIDE the old
    # guard there instead), which is why check-wallet-vectors.py's tier 4
    # carries the proof under the engine's rule. The shipped guard is exact
    # (`is an integer`), so it answers here. What these pin is the MESSAGE (the file's
    # own refusal, not an engine error from trunc() of a non-number) and the
    # empty item, which the engine converts to 0 and the old chain encoded.
    whole = ("CoinXT: cxBech32EncodeValues: every data value must be a whole "
             "number between 0 and 31.")
    for label, values in (("one ulp above 3", "0,3.0000000000000004"),
                          ("-1e-15, within 2.2e-15 of zero", "0,-0.000000000000001"),
                          ("an empty item", "0,,1"),
                          ("a value that is not a number", "0,x")):
        c.ck("cxBech32EncodeValues refuses %s, by name" % label,
             throw_text("cxBech32EncodeValues", "bc", values, "bech32"), whole)
    for alias in ("3.0", "+3", "3e0"):
        c.ck("0,%s (whole to the engine) encodes exactly as 0,3" % alias,
             call("cxBech32EncodeValues", "bc", "0," + alias, "bech32"),
             call("cxBech32EncodeValues", "bc", "0,3", "bech32"))
    # An uppercase HRP used to give a MIXED-case string, which BIP-173 forbids
    # and which this file's own decoder rejects.
    c.ck("an uppercase HRP is refused rather than mixed into the output",
         throws("cxSegwitAddressEncode", "BC", 0, bytes(20)), True)
    c.ck("an empty HRP is refused", throws("cxBech32EncodeValues", "", "0", "bech32"), True)
    c.ck("a result over 90 characters is refused",
         throws("cxBech32EncodeValues", "bc", ",".join(["0"] * 90), "bech32"), True)

    # ---- phase 4 ------------------------------------------------------------
    # These matter more than anything above them, because they are the only
    # part of CoinXT that can be wrong WITHOUT FAILING. A mis-packed mnemonic
    # is still twelve English words; a mis-derived path is still a valid
    # address. Nothing tells the user until the funds are somewhere they
    # cannot reach, so every one of these is a published vector.
    c.note("\nBIP-39 (official Trezor english vectors)")
    for h in BIP39_ENTROPY:
        ent = bytes.fromhex(h)
        want = REF.bip39_mnemonic(ent)
        got = call("cxMnemonicFromEntropy", ent)
        c.ck(f"{len(ent)}-byte entropy {h[:12]} -> {len(want.split())} words", got, want)
        c.ck(f"  and back to entropy", to_bytes(call("cxMnemonicToEntropy", got)).hex(), h)
        c.ck(f"  seed with the TREZOR passphrase",
             to_bytes(call("cxMnemonicToSeed", got, "TREZOR")).hex(),
             REF.bip39_seed(want, "TREZOR").hex())
    twelve = REF.bip39_mnemonic(bytes(16))
    c.ck("an empty passphrase gives the plain seed",
         to_bytes(call("cxMnemonicToSeed", twelve, "")).hex(), REF.bip39_seed(twelve).hex())
    c.ck("cxMnemonicValidate accepts a good mnemonic",
         LCS._disp(call("cxMnemonicValidate", twelve)), "true")
    c.ck("rejects a wrong checksum word",
         LCS._disp(call("cxMnemonicValidate", " ".join(["abandon"] * 12))), "false")
    c.ck("rejects a word outside the list",
         LCS._disp(call("cxMnemonicValidate", " ".join(["zzzz"] * 11 + ["about"]))), "false")
    c.ck("rejects a word count BIP-39 does not define",
         LCS._disp(call("cxMnemonicValidate", " ".join(["abandon"] * 11))), "false")
    c.ck("normalizes tabs, newlines and runs of spaces",
         LCS._disp(call("cxMnemonicValidate", "\t " + twelve.replace(" ", "  ") + "\n")), "true")
    c.ck("cxMnemonicFromEntropy refuses a length BIP-39 does not define",
         throws("cxMnemonicFromEntropy", bytes(17)), True)
    # The wordlist reaches the script through the shim, so check the script's
    # own view of it rather than trusting that the C side got it right.
    # cxBip39Wordlist is an .lcb handler, so it comes from the wired library
    # rather than from the script; go to it the way the script's own calls do.
    wl = to_bytes(LCS.HASHES["cxbip39wordlist"]([]))
    c.ck("the wordlist the script sees is the normative one",
         hashlib.sha256(("\n".join(wl[i:i + 8].decode().rstrip(" ")
                                   for i in range(0, len(wl), 8)) + "\n").encode()).hexdigest(),
         REF.WORDLIST_SHA256)

    c.note("\nBIP-32 (official test vectors 1-3)")
    for seed_hex, paths in BIP32_VECTORS:
        master = call("cxHdFromSeed", bytes.fromhex(seed_hex))
        for path, want_prv, want_pub in paths:
            node = call("cxHdDerivePath", master, path)
            c.ck(f"seed {seed_hex[:8]} {path} xprv", call("cxXprv", node), want_prv)
            c.ck(f"seed {seed_hex[:8]} {path} xpub", call("cxXpub", node), want_pub)
    # Vector 3 exists precisely because its master private key has a leading
    # zero byte, which is where a "strip leading zeros" bignum bug shows up.
    c.note("\nBIP-32 structure")
    master = call("cxHdFromSeed", bytes.fromhex(BIP32_VECTORS[0][0]))
    acct = call("cxHdDerivePath", master, "m/0'")
    watch = call("cxHdNeuter", acct)
    c.ck("cxHdNeuter leaves the source node's private key intact",
         acct["seckey"] != "", True)
    c.ck("a watch-only node derives the same non-hardened child",
         call("cxXpub", call("cxHdDerivePath", watch, "m/1")),
         call("cxXpub", call("cxHdDerivePath", acct, "m/1")))
    c.ck("a watch-only node cannot serialize an xprv",
         throws("cxXprv", watch), True)
    c.ck("a watch-only node cannot derive a hardened child",
         throws("cxHdDerivePath", watch, "m/0'"), True)
    c.ck("h and H are accepted as hardened markers",
         call("cxXprv", call("cxHdDerivePath", master, "m/0h")), call("cxXprv", acct))
    # "m/" and "m/0'/" are the trailing-separator fail-open the 2026-08-10
    # engine pass caught: they only test anything now that lcs-interp counts
    # items the way the engine does (one trailing delimiter is invisible).
    for bad in ("0/1", "m/", "m/0'/", "/", "m/1'2", "m/ 1", "m/1e3", "m/2147483648", "m/1.0"):
        c.ck(f"rejects the path {bad!r}", throws("cxHdDerivePath", master, bad), True)
    c.ck("rejects a seed shorter than 16 bytes", throws("cxHdFromSeed", bytes(15)), True)
    c.ck("rejects a seed longer than 64 bytes", throws("cxHdFromSeed", bytes(65)), True)

    # cxHdDeriveChild is the single CKD step the path walker loops over, and it
    # is public API in its own right. Everything above reaches it only THROUGH
    # cxHdDerivePath, so a defect in argument handling at the public entry
    # point - a hardened index misread, a bad bound - would not show up.
    c.note("\nBIP-32 single-step derivation (cxHdDeriveChild)")
    _, want_h0_prv, _ = BIP32_VECTORS[0][1][1]
    c.ck("one hardened step reaches the published m/0' xprv",
         call("cxXprv", call("cxHdDeriveChild", master, 2147483648)), want_h0_prv)
    c.ck("a normal step agrees with the path walker",
         call("cxXprv", call("cxHdDeriveChild", acct, 1)),
         call("cxXprv", call("cxHdDerivePath", master, "m/0'/1")))
    c.ck("index 0 is not treated as hardened",
         call("cxXprv", call("cxHdDeriveChild", master, 0)),
         call("cxXprv", call("cxHdDerivePath", master, "m/0")))
    c.ck("each step advances the depth by one",
         int(LCS._n(call("cxHdDeriveChild", acct, 1)["depth"])), 2)
    c.ck("rejects an index at or above 2^32",
         throws("cxHdDeriveChild", master, 4294967296), True)
    c.ck("rejects a negative index", throws("cxHdDeriveChild", master, -1), True)
    c.ck("a watch-only node cannot take a hardened step",
         throws("cxHdDeriveChild", watch, 2147483648), True)

    # cxMnemonicNormalize on its own. Every other BIP-39 handler runs it first,
    # so if it were wrong they would all be wrong TOGETHER and would agree with
    # each other - the round trips above would still close.
    c.note("\nBIP-39 normalization (cxMnemonicNormalize)")
    c.ck("strips surrounding whitespace",
         call("cxMnemonicNormalize", "  " + twelve + "  "), twelve)
    c.ck("an already-clean mnemonic is unchanged",
         call("cxMnemonicNormalize", twelve), twelve)
    c.ck("it is idempotent",
         call("cxMnemonicNormalize", call("cxMnemonicNormalize", "  " + twelve + " ")),
         twelve)
    c.ck("tabs, newlines and runs of spaces collapse to single spaces",
         call("cxMnemonicNormalize", "abandon\tabandon\n  abandon "),
         "abandon abandon abandon")
    c.ck("whitespace only normalizes to empty",
         call("cxMnemonicNormalize", "   "), "")
    c.ck("a normalized mnemonic gives the same seed as the clean one",
         to_bytes(call("cxMnemonicToSeed",
                       call("cxMnemonicNormalize", "\n" + twelve + "\t"), "")).hex(),
         REF.bip39_seed(twelve).hex())

    # ---- the itemDelimiter guard ------------------------------------------
    # `item` reads the CURRENT delimiter, and the interpreter holds it as
    # GLOBAL state, the reading templates/CLAUDE.md rule 5 gave when these
    # guards went in: an app that set it and did not restore it would get
    # silently wrong answers here. Measured then, under this model: a hostile
    # delimiter made cxBtcAddressP2WPKH fail outright and cxMnemonicValidate
    # answer FALSE to a perfectly good twelve-word backup. Every guarded
    # handler must now be indifferent to it, AND must hand the caller's
    # setting back untouched - including when it throws. On Windows and Linux
    # the engine makes both halves automatic (engine note 2.3: the
    # itemDelimiter is handler-LOCAL there, OBSERVED 2026-09-24 and 09-25), so
    # this section proves the guards, not an engine exposure; macOS has not
    # run the probe.
    c.note("\nindifference to a hostile itemDelimiter")
    hostile = "\t"
    guarded = [
        ("cxBech32EncodeValues", ("bc", "0,1,2", "bech32")),
        ("cxSegwitAddressEncode", ("bc", 0, bytes(20))),
        ("cxBtcAddressP2WPKH", (G33,)),
        ("cxBtcAddressP2TR", (G65[1:33],)),
        ("cxBtcAddressP2PKH", (G33,)),
        ("cxMnemonicToEntropy", (twelve,)),
        ("cxMnemonicValidate", (twelve,)),
    ]
    for name, args in guarded:
        want = call(name, *args)
        LCS.ITEM_DELIMITER[0] = hostile
        try:
            got = call(name, *args)
        finally:
            LCS.ITEM_DELIMITER[0] = ","
        c.ck(f"{name} is indifferent to the delimiter", got, want)
    # The decoders take their own shapes; check one of each, and the restore.
    addr = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    want_v = int(LCS._n(ip.call("cxSegwitAddressDecode", ["bc", addr])["version"]))
    LCS.ITEM_DELIMITER[0] = hostile
    try:
        got_v = int(LCS._n(ip.call("cxSegwitAddressDecode", ["bc", addr])["version"]))
        left_ok = LCS.ITEM_DELIMITER[0] == hostile
        # ... and that a THROW does not leak a changed delimiter either.
        try:
            ip.call("cxSegwitAddressDecode", ["bc", addr[:-1] + "5"])
            threw = False
        except LCS.Thrown:
            threw = True
        left_after_throw = LCS.ITEM_DELIMITER[0] == hostile
    finally:
        LCS.ITEM_DELIMITER[0] = ","
    c.ck("cxSegwitAddressDecode is indifferent to the delimiter", got_v, want_v)
    c.ck("  and hands the caller's delimiter back", left_ok, True)
    c.ck("  a corrupt address still throws", threw, True)
    c.ck("  and the throw path restores it too", left_after_throw, True)

    c.note("\nBIP-44 end to end (mnemonic -> seed -> path -> address)")
    seed = call("cxMnemonicToSeed", twelve, "")
    for path, kind, want in BIP44_ADDRESSES:
        node = call("cxHdDerivePath", call("cxHdFromSeed", seed), path)
        if kind == "p2pkh":
            got = call("cxBtcAddressP2PKH", node["pubkey"])
        elif kind == "p2wpkh":
            got = call("cxBtcAddressP2WPKH", node["pubkey"])
        else:
            got = call("cxEthAddressChecksum", call("cxEthAddress", node["pubkey"]))
        c.ck(f"{path} -> {kind}", got, want)

    # ---- phase 5: transactions ---------------------------------------------
    # These EXECUTE the transaction layer, which is the whole point of running it
    # here: phase 5 is pure script over the phase 1-4 primitives, so a defect in
    # its serialization is invisible until something runs it - and until this set
    # existed, nothing did (the oracle rebuilds the tx, but never through the
    # script). The signatures fed to the encoders are the oracle's own RFC 6979
    # deterministic (r, s), so no signer is needed in the interpreter.
    #
    # THIS SET EARNED ITS KEEP THE DAY IT WAS WRITTEN. The whole-transaction check
    # failed on the first run and it was a real, would-be-red engine defect: the
    # BIP-143 tx has a trailing EMPTY scriptSig (input 1 is segwit, its sig is in
    # the witness), and the engine ignores ONE trailing delimiter when it counts
    # items - so cxBtcTxEncode's strict "items == tCount" guard read the list as
    # short and REFUSED to assemble the reference transaction outright. Fixed by
    # reading every list by index and bounding the guard to "too long only"; the
    # regression vector is the whole-transaction check below.
    c.note("\nphase 5: Bitcoin transaction pieces")
    F = _phase5_fixture()
    for n in (0, 1, 252, 253, 65535, 65536, 4294967295, 4294967296):
        c.ck(f"cxVarInt({n})", to_bytes(call("cxVarInt", n)).hex(), REF.varint(n).hex())
    c.ck("cxVarInt refuses a negative count", throws("cxVarInt", -1), True)
    c.ck("cxBtcOutpoint (txid reversed + LE vout)",
         to_bytes(call("cxBtcOutpoint", F["txid0"], 0)).hex(), F["op0"].hex())
    c.ck("cxBtcOutpoint refuses a 31-byte txid", throws("cxBtcOutpoint", "00" * 31, 0), True)
    c.ck("cxBtcOutput (LE amount + script)",
         to_bytes(call("cxBtcOutput", 0x06b22c20, F["spk0"])).hex(),
         REF.btc_output(0x06b22c20, bytes.fromhex(F["spk0"])).hex())

    c.note("\nphase 5: BIP-143 native-P2WPKH sighashes")
    c.ck("cxBtcSighashLegacy (input 0, SIGHASH_ALL)",
         to_bytes(call("cxBtcSighashLegacy", 1, F["outpoints"], F["sequences"], 1,
                       F["sc0"], F["outputs"], 17, 1)).hex(), F["d0"].hex())
    c.ck("cxBtcSighashSegwit (input 1, BIP-143)",
         to_bytes(call("cxBtcSighashSegwit", 1, F["outpoints"], F["sequences"], 2,
                       F["sc1"], 0x23c34600, F["outputs"], 17, 1)).hex(), F["d1"].hex())
    # The CRITICAL fail-open the review caught: a BIP-143 preimage without
    # hashOutputs signs a payment to anywhere. An empty outputs list is refused.
    c.ck("cxBtcSighashSegwit refuses an empty outputs list",
         throws("cxBtcSighashSegwit", 1, F["outpoints"], F["sequences"], 2,
                F["sc1"], 0x23c34600, "", 17, 1), True)
    # A SIGHASH TYPE THIS BUILDER DOES NOT IMPLEMENT IS REFUSED, NOT
    # APPROXIMATED. Neither preimage builder branches on the type: both always
    # commit to every prevout, sequence and output, which is SIGHASH_ALL. The
    # type byte was nonetheless appended verbatim, so asking for SINGLE got a
    # digest that SAYS 3 over data hashed as if it were 1 - a signature that
    # looks right, verifies nowhere, and commits to outputs the signer believed
    # it had excluded. throw_text, not throws: the surrounding guards (index
    # range, parallel lists) refuse some of these inputs too, so only the
    # MESSAGE distinguishes "refused for the right reason".
    for _ty, _label in ((0, "0"), (2, "SIGHASH_NONE"), (3, "SIGHASH_SINGLE"),
                        (0x81, "ALL|ANYONECANPAY"), (0x83, "SINGLE|ANYONECANPAY")):
        c.ck("cxBtcSighashLegacy refuses " + _label,
             "only SIGHASH_ALL" in throw_text(
                 "cxBtcSighashLegacy", 1, F["outpoints"], F["sequences"], 1,
                 F["sc0"], F["outputs"], 17, _ty), True)
        c.ck("cxBtcSighashSegwit refuses " + _label,
             "only SIGHASH_ALL" in throw_text(
                 "cxBtcSighashSegwit", 1, F["outpoints"], F["sequences"], 2,
                 F["sc1"], 0x23c34600, F["outputs"], 17, _ty), True)
    c.ck("cxBtcSighashLegacy refuses an out-of-range input index",
         throws("cxBtcSighashLegacy", 1, F["outpoints"], F["sequences"], 3,
                F["sc0"], F["outputs"], 17, 1), True)
    c.ck("cxBtcSighashSegwit refuses non-parallel outpoint/sequence lists",
         throws("cxBtcSighashSegwit", 1, F["outpoints"], "4294967295", 1,
                F["sc1"], 0x23c34600, F["outputs"], 17, 1), True)

    c.note("\nphase 5: DER, witness, whole transaction")
    c.ck("cxDerEncode (input 0 signature)",
         to_bytes(call("cxDerEncode", F["compact0"])).hex(), REF.der_encode(*F["rs0"]).hex())
    c.ck("cxDerEncode refuses a signature that is not 64 bytes",
         throws("cxDerEncode", "\x00" * 63), True)
    c.ck("cxBtcWitness (count + sig + pubkey)",
         to_bytes(call("cxBtcWitness", F["witness1"])).hex(), F["wit1"].hex())
    c.ck("cxBtcWitness of an empty stack is a single 00",
         to_bytes(call("cxBtcWitness", "")).hex(), REF.varint(0).hex())
    # THE REGRESSION VECTOR. F["scriptsigs"] is "<sig0>," - a trailing empty item
    # for input 1's absent scriptSig - which the engine counts as ONE item. The
    # old strict guard refused this exact reference transaction; this asserts it
    # now assembles byte for byte. One vector per defect, per the review rule.
    c.ck("cxBtcTxEncode assembles the BIP-143 tx (trailing-empty scriptSig)",
         to_bytes(call("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
                       F["witnesses"], F["outputs"], 17)).hex(), REF.BIP143_SIGNED_TX)
    c.ck("cxBtcTxid (non-witness serialization, reversed)",
         call("cxBtcTxid", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
              F["outputs"], 17), F["txid"].hex())
    c.ck("cxBtcTxEncode refuses zero inputs",
         throws("cxBtcTxEncode", 1, "", "", "", "", F["outputs"], 17), True)
    c.ck("cxBtcTxEncode refuses a non-parallel sequence list",
         throws("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], "4294967295",
                F["witnesses"], F["outputs"], 17), True)
    # A witness list may not carry MORE entries than inputs (the extras would be
    # dropped). A SHORT one cannot be rejected: [wit, ""] and [wit] are the same
    # string under the chunk rule, so a missing trailing witness reads as empty.
    c.ck("cxBtcTxEncode refuses a witness list longer than the input count",
         throws("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
                F["witnesses"] + "," + F["wit1"].hex(), F["outputs"], 17), True)

    c.note("\nphase 5: Ethereum EIP-155 and EIP-1559")
    c.ck("cxEthLegacySighash matches the EIP-155 example",
         to_bytes(call("cxEthLegacySighash", 9, F["ethGasPrice"], 21000, F["ethTo"],
                       F["ethValue"], "", 1)).hex(), F["h155"].hex())
    res155 = call("cxEthLegacyEncode", 9, F["ethGasPrice"], 21000, F["ethTo"], F["ethValue"],
                  "", 1, F["recid155"], F["r155hex"], F["s155hex"])
    c.ck("cxEthLegacyEncode raw (v = 37)", res155["raw"], F["raw155"].hex())
    c.ck("cxEthLegacyEncode txhash", res155["txhash"], F["txhash155"].hex())
    c.ck("cxEth1559Sighash matches the typed-tx digest",
         to_bytes(call("cxEth1559Sighash", 1, 0, F["m1559prio"], F["m1559fee"], 21000,
                       F["ethTo"], F["v1559"], "")).hex(), F["h1559"].hex())
    res1559 = call("cxEth1559Encode", 1, 0, F["m1559prio"], F["m1559fee"], 21000, F["ethTo"],
                   F["v1559"], "", F["recid1559"], F["r1559hex"], F["s1559hex"])
    c.ck("cxEth1559Encode raw (0x02 envelope)", res1559["raw"], F["raw1559"].hex())
    c.ck("cxEth1559Encode txhash", res1559["txhash"], F["txhash1559"].hex())
    check_integer_arguments(c, call, F)


# ---- phase 5: the integer arguments, settled as digits (row #10) ----------
#
# WORK-PLAN coinxt row #10 (2026-09-26). cxUIntToBytesLE (amounts, vout,
# sequence, version, locktime), cxHexOfInt (nonce, gas, chain id, recovery
# id) and cxVarInt encoded whatever number they were handed. Digit text past
# 2^53 became the bytes of its ROUNDED neighbour on the engine with no error
# (suite engine note 2.4), and "1e3", "3.0", "+3" and an empty value were
# numbers to the arithmetic, so a transaction could carry a nonce, an amount
# or a vout other than the one written. cxCheckedWhole settles each one at
# the library boundary now: a non-empty run of ASCII digits, at most 2^53,
# decided on the digits.
#
# EVERY REFUSAL HERE FAILS ON THE OLD CODE, and in one of two ways, both
# visible as a failed row rather than a crash: past 2^53 the interpreter
# STOPS (its `_exact` refuses the arithmetic the engine would round), which
# `outcome` reports as a stop, not as the message; and a malformed spelling
# ENCODED, which reports as bytes. The controls pass either way: 2^53 itself
# is written exactly, and the old refusals keep their words.
_ROW10_OVER = "the most this encoder writes exactly."
_ROW10_DIGITS = "must be a whole number written in digits."


def check_integer_arguments(c, call, F):
    c.note("\nphase 5: integer arguments settled as digits, at most 2^53 "
           "(work-plan row #10)")
    top = 2 ** 53

    def outcome(fn, *args):
        """What the handler did: its bytes (hex), its array, or its refusal,
        with the interpreter's own stops named so a vector cannot crash."""
        try:
            got = call(fn, *args)
        except LCS.Thrown as thrown:
            return "refused: %s" % thrown.msg
        except LCS.Imprecise:
            return "stopped: the interpreter's 2^53 stop (the engine rounds)"
        except LCS.Indistinct:
            return "stopped: the interpreter refused to decide (engine note 2.10/2.11)"
        except Exception as exc:                        # noqa: BLE001
            return "stopped: %s: %s" % (type(exc).__name__, str(exc)[:80])
        if isinstance(got, dict):
            return got
        return to_bytes(got).hex()

    def refused(who, what, why):
        if why == "over":
            return ("refused: CoinXT: %s: %s is more than 9007199254740992, %s"
                    % (who, what, _ROW10_OVER))
        return "refused: CoinXT: %s: %s %s" % (who, what, _ROW10_DIGITS)

    # ---- cxVarInt: the count --------------------------------------------
    c.ck("cxVarInt(2^53) is written exactly (the bound itself)",
         outcome("cxVarInt", top), REF.varint(top).hex())
    c.ck("cxVarInt reads a count with leading zeros as its digits",
         outcome("cxVarInt", "000" + str(top)), REF.varint(top).hex())
    for label, value in (("2^53 + 1", top + 1), ("2^53 + 1 as digit text", str(top + 1)),
                         ("twenty nines", "9" * 20)):
        c.ck("cxVarInt refuses %s by name, before any arithmetic" % label,
             outcome("cxVarInt", value), refused("cxVarInt", "the count", "over"))
    for value in ("1e3", "3.0", "+3", " 3", "", "0x10", "3 ", "x"):
        c.ck("cxVarInt refuses %r: not written in digits" % value,
             outcome("cxVarInt", value), refused("cxVarInt", "the count", "digits"))
    c.ck("and a negative count keeps its old refusal, word for word",
         outcome("cxVarInt", -1), "refused: CoinXT: cxVarInt: the count must not be negative.")

    # ---- cxUIntToBytesLE, through the public handlers that reach it -------
    spk = F["spk0"]
    c.ck("cxBtcOutput writes an amount of 2^53 exactly",
         outcome("cxBtcOutput", top, spk), REF.btc_output(top, bytes.fromhex(spk)).hex())
    for label, value in (("2^53 + 1", top + 1), ("twenty nines", "9" * 20)):
        c.ck("cxBtcOutput refuses an amount of %s by name" % label,
             outcome("cxBtcOutput", value, spk),
             refused("cxUIntToBytesLE", "the value", "over"))
    for value in ("1e8", "150000000.0", "+1000", ""):
        c.ck("cxBtcOutput refuses an amount written %r" % value,
             outcome("cxBtcOutput", value, spk),
             refused("cxUIntToBytesLE", "the value", "digits"))
    c.ck("cxBtcOutpoint writes vout 4294967295, the widest four bytes hold",
         outcome("cxBtcOutpoint", F["txid0"], 4294967295),
         REF.btc_outpoint(bytes.fromhex(F["txid0"]), 4294967295).hex())
    c.ck("and still refuses 4294967296 as not fitting (the old refusal)",
         outcome("cxBtcOutpoint", F["txid0"], 4294967296),
         "refused: CoinXT: cxUIntToBytesLE: the value does not fit in the "
         "requested width.")
    c.ck("cxBtcOutpoint refuses a vout written 1e1 (it wrote vout 10)",
         outcome("cxBtcOutpoint", F["txid0"], "1e1"),
         refused("cxUIntToBytesLE", "the value", "digits"))
    # a sequence reaches the encoder through the itemDelimiter wrapper, which
    # captures a refusal and throws it after `end try` (trap 13): the MESSAGE
    # must come through it unchanged
    c.ck("cxBtcTxEncode refuses a sequence written 1e9, message intact through "
         "the delimiter wrapper",
         outcome("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"],
                 "1e9," + F["sequences"].split(",")[1], F["witnesses"], F["outputs"], 17),
         refused("cxUIntToBytesLE", "the value", "digits"))
    c.ck("cxBtcTxEncode refuses a locktime of 2^53 + 1 by name",
         outcome("cxBtcTxEncode", 1, F["outpoints"], F["scriptsigs"], F["sequences"],
                 F["witnesses"], F["outputs"], top + 1),
         refused("cxUIntToBytesLE", "the value", "over"))

    # ---- cxHexOfInt: the Ethereum counters --------------------------------
    to = F["ethTo"]
    gp, val = F["ethGasPrice"], F["ethValue"]
    c.ck("cxEthLegacySighash signs a nonce of 2^53 exactly",
         outcome("cxEthLegacySighash", top, gp, 21000, to, val, "", 1),
         REF.eth_legacy_sighash(top, 20 * 10**9, 21000, bytes.fromhex(to), 10**18,
                                b"", 1).hex())
    c.ck("cxEthLegacySighash refuses a nonce of 2^53 + 1 by name",
         outcome("cxEthLegacySighash", top + 1, gp, 21000, to, val, "", 1),
         refused("cxHexOfInt", "the value", "over"))
    for label, args in (("a gas limit written 21e3 (it signed gas 21000)",
                         (9, gp, "21e3", to, val, "", 1)),
                        ("a chain id written 1.0", (9, gp, 21000, to, val, "", "1.0")),
                        ("an EMPTY nonce (it signed nonce 0)", ("", gp, 21000, to, val, "", 1))):
        c.ck("cxEthLegacySighash refuses %s" % label,
             outcome("cxEthLegacySighash", *args),
             refused("cxHexOfInt", "the value", "digits"))
    c.ck("cxEth1559Sighash refuses a chain id of 2^53 + 1 by name",
         outcome("cxEth1559Sighash", top + 1, 0, F["m1559prio"], F["m1559fee"], 21000,
                 to, F["v1559"], ""),
         refused("cxHexOfInt", "the value", "over"))
    c.ck("cxEth1559Encode refuses a y-parity written 1e0 (it wrote 1)",
         outcome("cxEth1559Encode", 1, 0, F["m1559prio"], F["m1559fee"], 21000, to,
                 F["v1559"], "", "1e0", F["r1559hex"], F["s1559hex"]),
         refused("cxHexOfInt", "the value", "digits"))

    # ---- cxEthLegacyEncode: v is COMPUTED from the chain id ---------------
    # v = recid + 2 * chainId + 35, and EIP-155 has room for a recovery id of
    # 0 or 1 only: 2 on chain 1 is v = 39, which IS chain 2's v at id 0 (the
    # 2026-09-26 review; row #10's first bound took secp256k1's 0 to 3 and
    # let 2 and 3 through to that confusion). So the chain id is bounded
    # where v still fits at recid 1: 4503599627370478. At that bound and
    # recid 1, v is exactly 2^53, and the raw transaction is the reference's
    # RLP over the same fields, byte for byte.
    edge = 4503599627370478
    rr, ss = F["r155hex"], F["s155hex"]
    fields = [REF._rlp_uint(9), REF._rlp_uint(20 * 10**9), REF._rlp_uint(21000),
              REF.rlp_encode(bytes.fromhex(to)), REF._rlp_uint(10**18), REF.rlp_encode(b""),
              REF._rlp_uint(1 + 2 * edge + 35), REF._rlp_uint(int(rr, 16)),
              REF._rlp_uint(int(ss, 16))]
    got = outcome("cxEthLegacyEncode", 9, gp, 21000, to, val, "", edge, 1, rr, ss)
    c.ck("cxEthLegacyEncode writes chain id %d with recid 1 (v = 2^53) exactly" % edge,
         got["raw"] if isinstance(got, dict) else got,
         REF._rlp_list_join(fields).hex())
    for label, chain in (("one past it", edge + 1), ("2^53", top)):
        c.ck("cxEthLegacyEncode refuses a chain id of %s by name, before v is "
             "computed" % label,
             outcome("cxEthLegacyEncode", 9, gp, 21000, to, val, "", chain, 0, rr, ss),
             "refused: CoinXT: cxEthLegacyEncode: the chain id is more than %d, %s"
             % (edge, _ROW10_OVER))
    for recid, reads in ((2, "chain 2's v at id 0"), (3, "chain 2's v at id 1"),
                         (4, "chain 3's v at id 0")):
        c.ck("cxEthLegacyEncode refuses a recovery id of %d (on chain 1 it wrote "
             "v = %d, %s)" % (recid, recid + 2 + 35, reads),
             outcome("cxEthLegacyEncode", 9, gp, 21000, to, val, "", 1, recid, rr, ss),
             "refused: CoinXT: cxEthLegacyEncode: the recovery id is more than 1, %s"
             % _ROW10_OVER)
    # the control beside them: chain 2 at id 0 is v = 39, the spelling id 2 on
    # chain 1 used to write, and it stays written for the chain that owns it
    got = outcome("cxEthLegacyEncode", 9, gp, 21000, to, val, "", 2, 0, rr, ss)
    c.ck("and chain 2 at recovery id 0 still writes v = 39 (control)",
         REF.rlp_decode(bytes.fromhex(got["raw"]))[6].hex()
         if isinstance(got, dict) else got, "27")
    c.ck("cxEthLegacyEncode refuses an empty recovery id",
         outcome("cxEthLegacyEncode", 9, gp, 21000, to, val, "", 1, "", rr, ss),
         refused("cxEthLegacyEncode", "the recovery id", "digits"))


# EACH GUARD, UNDONE (row #10). The shipped line and the spelling that stands
# where the guard was (the argument taken as it came, which is what every
# encoder did before 2026-09-26); the block above must fail on each, so a
# revert, a rename or a vector that cannot see its encoder fails the gate.
# The shipped line must occur exactly once.
_ROW10_MUTATIONS = (
    ("cxVarInt's count, taken as it came",
     [('   put cxCheckedWhole(pN, "9007199254740992", "cxVarInt", "the count") into tN\n',
       '   put pN into tN\n')]),
    ("cxUIntToBytesLE's value, taken as it came",
     [('   put cxCheckedWhole(pValue, "9007199254740992", "cxUIntToBytesLE", \\\n'
       '         "the value") into tRest\n', '   put pValue into tRest\n')]),
    ("cxHexOfInt's value, taken as it came",
     [('   put cxCheckedWhole(pValue, "9007199254740992", "cxHexOfInt", "the value") \\\n'
       '         into tValue\n', '   put pValue into tValue\n')]),
    ("cxEthLegacyEncode's recovery id and chain id, taken as they came",
     [('   put cxCheckedWhole(pRecid, "1", "cxEthLegacyEncode", "the recovery id") \\\n'
       '         into tRecid\n', '   put pRecid into tRecid\n'),
      ('   put cxCheckedWhole(pChainId, "4503599627370478", "cxEthLegacyEncode", \\\n'
       '         "the chain id") into tChain\n', '   put pChainId into tChain\n')]),
    # A PLAUSIBLE WRONG FIX, not a revert: row #10's first bound, secp256k1's
    # recovery ids 0 to 3 and the chain id that leaves room for 3. It passes
    # every refusal above but ids 2 and 3, which it writes as chain 2's v
    # (the 2026-09-26 review), so the block must fail on it.
    ("cxEthLegacyEncode's recovery id bounded at 3 (secp256k1's range, not "
     "EIP-155's)",
     [('   put cxCheckedWhole(pRecid, "1", "cxEthLegacyEncode", "the recovery id") \\\n'
       '         into tRecid\n',
       '   put cxCheckedWhole(pRecid, "3", "cxEthLegacyEncode", "the recovery id") \\\n'
       '         into tRecid\n'),
      ('   put cxCheckedWhole(pChainId, "4503599627370478", "cxEthLegacyEncode", \\\n'
       '         "the chain id") into tChain\n',
       '   put cxCheckedWhole(pChainId, "4503599627370477", "cxEthLegacyEncode", \\\n'
       '         "the chain id") into tChain\n')]),
)


def check_row10_fires(c, text, F):
    c.note("\nphase 5: every row #10 guard, undone, fails its vectors")
    for label, pairs in _ROW10_MUTATIONS:
        counts = [text.count(new) for new, _old in pairs]
        c.ck("the shipped script carries the guard exactly once (%s)" % label,
             counts, [1] * len(pairs))
        if counts != [1] * len(pairs):
            continue
        mutated = text
        for new, old in pairs:
            mutated = mutated.replace(new, old)
        unit = LCS.Interp(mutated)

        def call(fn, *args, _unit=unit):
            return _unit.call(fn, [to_str(a) if isinstance(a, (bytes, bytearray)) else a
                                   for a in args])
        inner = Checker(True)
        try:
            check_integer_arguments(inner, call, F)
        except Exception as exc:                        # noqa: BLE001
            inner.problems.append("stopped: %s: %s" % (type(exc).__name__, exc))
        c.ck("%s, undone, FAILS its vectors" % label, len(inner.problems) > 0, True)





# BIP-341 wallet-test-vectors.json, transcribed MECHANICALLY from the
# fetched file (bitcoin/bips bip-0341), 2026-08-23: the shared unsigned tx
# as the comma lists the script handlers take, all 7 keyPathSpending rows
# (the complete sighash type set), and all 6 script trees with their
# published leaf hashes, merkle roots and control blocks. Never hand-edit
# a value here; re-transcribe from the source file.
TAPROOT_FIXTURE = {'version': 2, 'locktime': 500000000, 'outpoints': '7de20cbff686da83a54981d2b9bab3586f4ca7e48f57f5b55963115f3b334e9c01000000,d7b7cab57b1393ace2d064f4d4a2cb8af6def61273e127517d44759b6dafdd9900000000,f8e1f583384333689228c5d28eac13366be082dc57441760d957275419a4184200000000,f0689180aa63b30cb162a73c6d2a38b7eeda2a83ece74310fda0843ad604853b01000000,aa5202bdf6d8ccd2ee0f0202afbbb7461d9264a25e5bfd3c5a52ee1239e0ba6c00000000,956149bdc66faa968eb2be2d2faa29718acbfe3941215893a2a3446d32acd05000000000,e664b9773b88c09c32cb70a2a3e4da0ced63b7ba3b22f848531bbb1d5d5f4c9401000000,e9aa6b8e6c9de67619e6a3924ae25696bb7b694bb677a632a74ef7eadfd4eabf00000000,a778eb6a263dc090464cd125c466b5a99667720b1c110468831d058aa1b82af101000000', 'sequences': '0,4294967295,4294967295,4294967294,4294967294,0,0,4294967295,4294967295', 'amounts': '420000000,462000000,294000000,504000000,630000000,378000000,672000000,546000000,588000000', 'spks': '512053a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343,5120147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3,76a914751e76e8199196d454941c45d1b3a323f1433bd688ac,5120e4d810fd50586274face62b8a807eb9719cef49c04177cc6b76a9a4251d5450e,512091b64d5324723a985170e4dc5a0f84c041804f2cd12660fa5dec09fc21783605,00147dd65592d0ab2fe0d0257d571abf032cd9db93dc,512075169f4001aa68f15bbed28b218df1d0a62cbbcf1188c6665110c293c907b831,5120712447206d7a5238acc7ff53fbe94a3b64539ad291c7cdbc490b7577e4b17df5,512077e30a5522dd9f894c3f8b8bd4c4b2cf82ca7da8a3ea6a239655c39c050ab220', 'outputs': '00ca9a3b000000001976a91406afd46bcdfd22ef94ac122aa11f241244a37ecc88ac,807840cb0000000020ac9a87f5594be208f8532db38cff670c450ed2fea8fcdefcc9a663f78bab962b', 'inputs': [{'index': 1, 'hashType': 3, 'sigHash': '2514a6272f85cfa0f45eb907fcb0d121b808ed37c6ea160a5a9046ed5526d555'}, {'index': 2, 'hashType': 131, 'sigHash': '325a644af47e8a5a2591cda0ab0723978537318f10e6a63d4eed783b96a71a4d'}, {'index': 4, 'hashType': 1, 'sigHash': 'bf013ea93474aa67815b1b6cc441d23b64fa310911d991e713cd34c7f5d46669'}, {'index': 5, 'hashType': 0, 'sigHash': '4f900a0bae3f1446fd48490c2958b5a023228f01661cda3496a11da502a7f7ef'}, {'index': 7, 'hashType': 2, 'sigHash': '15f25c298eb5cdc7eb1d638dd2d45c97c4c59dcaec6679cfc16ad84f30876b85'}, {'index': 8, 'hashType': 130, 'sigHash': 'cd292de50313804dabe4685e83f923d2969577191a3e1d2882220dca88cbeb10'}, {'index': 9, 'hashType': 129, 'sigHash': 'cccb739eca6c13a8a89e6e5cd317ffe55669bbda23f2fd37b0f18755e008edd2'}], 'trees': [{'internal': '187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27', 'tree': {'id': 0, 'script': '20d85a959b0290bf19bb89ed43c916be835475d013da4b362117393e25a48229b8ac', 'leafVersion': 192}, 'leafHashes': ['5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21'], 'merkleRoot': '5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21', 'controlBlocks': ['c1187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27']}, {'internal': '93478e9488f956df2396be2ce6c5cced75f900dfa18e7dabd2428aae78451820', 'tree': {'id': 0, 'script': '20b617298552a72ade070667e86ca63b8f5789a9fe8731ef91202a91c9f3459007ac', 'leafVersion': 192}, 'leafHashes': ['c525714a7f49c28aedbbba78c005931a81c234b2f6c99a73e4d06082adc8bf2b'], 'merkleRoot': 'c525714a7f49c28aedbbba78c005931a81c234b2f6c99a73e4d06082adc8bf2b', 'controlBlocks': ['c093478e9488f956df2396be2ce6c5cced75f900dfa18e7dabd2428aae78451820']}, {'internal': 'ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592', 'tree': [{'id': 0, 'script': '20387671353e273264c495656e27e39ba899ea8fee3bb69fb2a680e22093447d48ac', 'leafVersion': 192}, {'id': 1, 'script': '06424950333431', 'leafVersion': 250}], 'leafHashes': ['8ad69ec7cf41c2a4001fd1f738bf1e505ce2277acdcaa63fe4765192497f47a7', 'f224a923cd0021ab202ab139cc56802ddb92dcfc172b9212261a539df79a112a'], 'merkleRoot': '6c2dc106ab816b73f9d07e3cd1ef2c8c1256f519748e0813e4edd2405d277bef', 'controlBlocks': ['c0ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592f224a923cd0021ab202ab139cc56802ddb92dcfc172b9212261a539df79a112a', 'faee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf37865928ad69ec7cf41c2a4001fd1f738bf1e505ce2277acdcaa63fe4765192497f47a7']}, {'internal': 'f9f400803e683727b14f463836e1e78e1c64417638aa066919291a225f0e8dd8', 'tree': [{'id': 0, 'script': '2044b178d64c32c4a05cc4f4d1407268f764c940d20ce97abfd44db5c3592b72fdac', 'leafVersion': 192}, {'id': 1, 'script': '07546170726f6f74', 'leafVersion': 192}], 'leafHashes': ['64512fecdb5afa04f98839b50e6f0cb7b1e539bf6f205f67934083cdcc3c8d89', '2cb2b90daa543b544161530c925f285b06196940d6085ca9474d41dc3822c5cb'], 'merkleRoot': 'ab179431c28d3b68fb798957faf5497d69c883c6fb1e1cd9f81483d87bac90cc', 'controlBlocks': ['c1f9f400803e683727b14f463836e1e78e1c64417638aa066919291a225f0e8dd82cb2b90daa543b544161530c925f285b06196940d6085ca9474d41dc3822c5cb', 'c1f9f400803e683727b14f463836e1e78e1c64417638aa066919291a225f0e8dd864512fecdb5afa04f98839b50e6f0cb7b1e539bf6f205f67934083cdcc3c8d89']}, {'internal': 'e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6f', 'tree': [{'id': 0, 'script': '2072ea6adcf1d371dea8fba1035a09f3d24ed5a059799bae114084130ee5898e69ac', 'leafVersion': 192}, [{'id': 1, 'script': '202352d137f2f3ab38d1eaa976758873377fa5ebb817372c71e2c542313d4abda8ac', 'leafVersion': 192}, {'id': 2, 'script': '207337c0dd4253cb86f2c43a2351aadd82cccb12a172cd120452b9bb8324f2186aac', 'leafVersion': 192}]], 'leafHashes': ['2645a02e0aac1fe69d69755733a9b7621b694bb5b5cde2bbfc94066ed62b9817', 'ba982a91d4fc552163cb1c0da03676102d5b7a014304c01f0c77b2b8e888de1c', '9e31407bffa15fefbf5090b149d53959ecdf3f62b1246780238c24501d5ceaf6'], 'merkleRoot': 'ccbd66c6f7e8fdab47b3a486f59d28262be857f30d4773f2d5ea47f7761ce0e2', 'controlBlocks': ['c0e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6fffe578e9ea769027e4f5a3de40732f75a88a6353a09d767ddeb66accef85e553', 'c0e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6f9e31407bffa15fefbf5090b149d53959ecdf3f62b1246780238c24501d5ceaf62645a02e0aac1fe69d69755733a9b7621b694bb5b5cde2bbfc94066ed62b9817', 'c0e0dfe2300b0dd746a3f8674dfd4525623639042569d829c7f0eed9602d263e6fba982a91d4fc552163cb1c0da03676102d5b7a014304c01f0c77b2b8e888de1c2645a02e0aac1fe69d69755733a9b7621b694bb5b5cde2bbfc94066ed62b9817']}, {'internal': '55adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312d', 'tree': [{'id': 0, 'script': '2071981521ad9fc9036687364118fb6ccd2035b96a423c59c5430e98310a11abe2ac', 'leafVersion': 192}, [{'id': 1, 'script': '20d5094d2dbe9b76e2c245a2b89b6006888952e2faa6a149ae318d69e520617748ac', 'leafVersion': 192}, {'id': 2, 'script': '20c440b462ad48c7a77f94cd4532d8f2119dcebbd7c9764557e62726419b08ad4cac', 'leafVersion': 192}]], 'leafHashes': ['f154e8e8e17c31d3462d7132589ed29353c6fafdb884c5a6e04ea938834f0d9d', '737ed1fe30bc42b8022d717b44f0d93516617af64a64753b7a06bf16b26cd711', 'd7485025fceb78b9ed667db36ed8b8dc7b1f0b307ac167fa516fe4352b9f4ef7'], 'merkleRoot': '2f6b2c5397b6d68ca18e09a3f05161668ffe93a988582d55c6f07bd5b3329def', 'controlBlocks': ['c155adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312d3cd369a528b326bc9d2133cbd2ac21451acb31681a410434672c8e34fe757e91', 'c155adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312dd7485025fceb78b9ed667db36ed8b8dc7b1f0b307ac167fa516fe4352b9f4ef7f154e8e8e17c31d3462d7132589ed29353c6fafdb884c5a6e04ea938834f0d9d', 'c155adf4e8967fbd2e29f20ac896e60c3b0f1d5b0efa9d34941b5958c7b0a0312d737ed1fe30bc42b8022d717b44f0d93516617af64a64753b7a06bf16b26cd711f154e8e8e17c31d3462d7132589ed29353c6fafdb884c5a6e04ea938834f0d9d']}]}



def check_taproot_bip341(c, ip):
    """BIP-341 (2026-08-23): the sighash builder and the script-path tree,
    EXECUTED against the published wallet vectors. The keyPathSpending rows
    cover the complete sighash type set (0/1/2/3 and the three ANYONECANPAY
    forms); the trees pin every published leaf hash, merkle root and control
    block. The script-path sighash has NO published vector in the wallet
    file, so it is cross-checked against tools/coin_reference.py instead -
    two implementations agreeing, said plainly rather than dressed up as a
    published pin."""
    f = TAPROOT_FIXTURE
    c.note("BIP-341 taproot sighash + script tree (published wallet vectors)")
    for row in f["inputs"]:
        got = ip.call("cxBtcSighashTaproot",
                      [f["version"], f["outpoints"], f["sequences"],
                       f["amounts"], f["spks"], f["outputs"],
                       row["index"], f["locktime"], row["hashType"], ""])
        c.ck(f"keyPathSpending input {row['index'] - 1} (type "
             f"{row['hashType']:#x}) sighash",
             got.encode("latin-1").hex(), row["sigHash"])

    def leaf(node):
        return ip.call("cxTapLeafHash", [node["leafVersion"], node["script"]])

    def fold(node):
        """(root_hex, [(leaf_hex, path_items)...]) via the SCRIPT handlers."""
        if isinstance(node, dict):
            lh = leaf(node)
            return lh, [(lh, [])]
        rl, ll = fold(node[0])
        rr, lr = fold(node[1])
        root = ip.call("cxTapBranchHash", [rl, rr])
        return root, ([(h, p + [rr]) for h, p in ll] +
                      [(h, p + [rl]) for h, p in lr])

    for t_i, tree in enumerate(f["trees"]):
        root, leaves = fold(tree["tree"])
        c.ck(f"tree {t_i}: every leaf hash matches the published list",
             [h for h, _ in leaves], tree["leafHashes"])
        c.ck(f"tree {t_i}: the merkle root folds to the published root",
             root, tree["merkleRoot"])
        for l_i, ((lh, path), cb) in enumerate(zip(leaves,
                                                   tree["controlBlocks"])):
            ver_par = int(cb[:2], 16)
            got = ip.call("cxTapControlBlock",
                          [ver_par & 0xfe, ver_par & 1, tree["internal"],
                           ",".join(path)])
            c.ck(f"tree {t_i} leaf {l_i}: the control block assembles "
                 "byte for byte", got, cb)

    # the script-path sighash: oracle cross-check (no published vector).
    lh0 = ip.call("cxTapLeafHash", [0xc0, "20" + "aa" * 32 + "ac"])
    got = ip.call("cxBtcSighashTaproot",
                  [f["version"], f["outpoints"], f["sequences"], f["amounts"],
                   f["spks"], f["outputs"], 1, f["locktime"], 0, lh0])
    want = REF.btc_sighash_taproot(
        f["version"], f["locktime"],
        [bytes.fromhex(x) for x in f["outpoints"].split(",")],
        [int(x) for x in f["amounts"].split(",")],
        [bytes.fromhex(x) for x in f["spks"].split(",")],
        [int(x) for x in f["sequences"].split(",")],
        [bytes.fromhex(x) for x in f["outputs"].split(",")],
        0, 0, tapleaf=bytes.fromhex(lh0))
    c.ck("script-path sighash agrees with the independent model "
         "(no published vector; two implementations)",
         got.encode("latin-1").hex(), want.hex())

    # refusals: what the builder must REFUSE, in the same change as what it
    # must produce (the adversarial-review lesson).
    def throws(label, args):
        try:
            ip.call("cxBtcSighashTaproot", args)
        except LCS.Thrown:
            c.ck(label, True, True)
            return
        c.ck(label, "did not throw", "a throw")
    base = [f["version"], f["outpoints"], f["sequences"], f["amounts"],
            f["spks"], f["outputs"], 1, f["locktime"], 0, ""]
    bad = list(base); bad[8] = 128
    throws("0x80 alone is refused (not a BIP-341 type)", bad)
    bad = list(base); bad[8] = 5
    throws("an unknown sighash type is refused", bad)
    bad = list(base); bad[3] = ",".join(f["amounts"].split(",")[:-1])
    throws("a short amounts list is refused (the lists must be parallel)", bad)
    bad = list(base); bad[6] = 3; bad[8] = 3
    throws("SIGHASH_SINGLE past the last output is refused", bad)
    bad = list(base); bad[9] = "ab" * 16 + "cd"
    throws("a wrong-length tapleaf hash is refused", bad)
    try:
        ip.call("cxTapLeafHash", [0xc1, "51"])
        c.ck("an odd leaf version is refused", "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("an odd leaf version is refused", True, True)
    try:
        ip.call("cxTapBranchHash", ["ab" * 31, "cd" * 32])
        c.ck("a short branch child is refused", "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("a short branch child is refused", True, True)
    try:
        ip.call("cxTapControlBlock", [0xc0, 2, "aa" * 32, ""])
        c.ck("a parity outside 0/1 is refused", "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("a parity outside 0/1 is refused", True, True)
    # 0x50 is even but RESERVED (BIP-341: a control block starting 0x50 would
    # be read as the annex), so both builders must refuse it - and the model
    # must agree, or the gate would be pinning a disagreement.
    try:
        REF.tap_leaf_hash(0x50, bytes.fromhex("51"))
        c.ck("the model refuses leaf version 0x50", "did not raise", "a raise")
    except ValueError:
        c.ck("the model refuses leaf version 0x50", True, True)
    try:
        ip.call("cxTapLeafHash", [0x50, "51"])
        c.ck("leaf version 0x50 is refused (annex ambiguity)",
             "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("leaf version 0x50 is refused (annex ambiguity)", True, True)
    try:
        ip.call("cxTapControlBlock", [0x50, 0, "aa" * 32, ""])
        c.ck("a 0x50 control block is refused (it IS the annex marker)",
             "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("a 0x50 control block is refused (it IS the annex marker)", True, True)
    try:
        ip.call("cxTapControlBlock", [0xc0, 0, "aa" * 32,
                                      ",".join(["ab" * 32] * 129)])
        c.ck("a 129-node merkle path is refused (BIP-341 caps it at 128)",
             "did not throw", "a throw")
    except LCS.Thrown:
        c.ck("a 129-node merkle path is refused (BIP-341 caps it at 128)",
             True, True)


def main(argv):
    terse = "--check" in argv[1:]
    c = Checker(terse)
    if not os.path.exists(SCRIPT):
        print("check-script-vectors: src/coinxt.livecodescript is missing")
        return 1
    text = open(SCRIPT, encoding="utf-8").read()

    check_interp_model(c)
    check_constants(c, text)
    check_demo_fields(c)

    cc = find_cc()
    if cc is None:
        print("check-script-vectors: SKIP the vector run (no C compiler found, so the "
              "native hashes the script calls are unavailable). The constants above "
              "still ran.")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            lib_path = os.path.join(tmp, "libcoinxt_script.so")
            try:
                build(cc, lib_path)
            except subprocess.CalledProcessError as exc:
                print(f"check-script-vectors: BUILD FAILED ({exc})")
                return 1
            wire_hashes(ctypes.CDLL(lib_path))
            ip = LCS.Interp(text)
            c.note(f"\nrunning the shipped script ({len(ip.handlers)} handlers, "
                   f"{len(ip.constants)} constants) through tools/lcs-interp.py")
            check_vectors(c, ip)
            check_row10_fires(c, text, _phase5_fixture())
            check_taproot_bip341(c, ip)
            check_demo_eth_address(c, text)

    if c.problems:
        print("check-script-vectors: FAILED")
        for p in c.problems:
            print(f"  - {p}")
        return 1
    # A FLOOR ON THE COUNT, so a refactor that quietly stops running most of the
    # vectors cannot print OK. "All the checks passed" and "hardly any checks
    # ran" look identical on the way out otherwise, and on this surface the
    # second one is indistinguishable from a green build. Raise it when the set
    # grows; it exists to catch collapse, not to track the exact number.
    floor = 20 if cc is None else 300
    if c.count < floor:
        print(f"check-script-vectors: FAILED - only {c.count} checks ran, expected at "
              f"least {floor}. Something stopped the vector set early.")
        return 1
    print(f"check-script-vectors: OK ({c.count} checks against the published vectors)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
