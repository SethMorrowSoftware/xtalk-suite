#!/usr/bin/env python3
"""lcs-interp.py - a tiny interpreter for the LiveCodeScript subset that
src/coinxt.livecodescript is written in. TEST TOOLING; it is not shipped inside
the extension and no shipped code imports it.

WHY THIS EXISTS. OXT cannot compile or run a .livecodescript headlessly, so the
phase-3 encoders would otherwise ship having never executed once - a bad place
for Base58Check and bech32 to be, since a transcription slip there produces a
VALID-LOOKING wrong address. This runs the ACTUAL shipped file against the
published vectors (tools/check-script-vectors.py drives it), so that class of
bug is caught here rather than in a scarce engine session.

WHAT IT IS NOT. It is an approximation of the engine, not the engine. It does
NOT replace the OXT pass and nothing here promotes a handler out of "verified
statically". It models the documented semantics of the subset used - 1-based
chunk indexing, comma item delimiter, `is` comparison, arrays - and it REFUSES
anything outside that subset rather than guessing, because a silent mis-parse
would be worse than no tool at all. If it disagrees with the engine, the engine
is right and this file is the bug.

ONE NAMED DIVERGENCE FROM THE ENGINE, because a general disclaimer is not much
use when the specific gap is known. `is` is modelled here as CASE-SENSITIVE for
strings (see _eq), while a real xTalk engine compares case-INSENSITIVELY unless
`the caseSensitive` is true. This interpreter is therefore STRICTER than the
engine on that one operator: a case bug it reports is real, but a case bug it
misses could still be there, and code that relies on `is` being case-insensitive
would pass here and behave differently on OXT. The shipped file does not rely on
either behaviour - it routes every case-significant comparison through
cxCharIndex, cxCaseKind or cxCompareBytes, which compare byte values and are
exact under both - and that is precisely why it does not.

It is deliberately literal and slow (cxBitXor alone is 31 interpreted iterations
per call, and a bech32 checksum calls it hundreds of times). Speed is not the
point; running the real text is.

ENGINE-CONFIRMED 2026-08-24 (Windows x86_64, OXT 9.6.3): the suite paste ran
2373/0 with every harness section that PINS these modeled divergences green -
the 1e3 integer fold, the trailing-delimiter eat, case-folding `is`, the
array-compares-as-array rule, script-local scope. Confirmation for the PINNED
cases, not a proof of the whole model: an unpinned behavior is still a model.

EXTENDED 2026-08-23 FOR THE NOSTRXT PORT (nostrxt/docs/08-open-questions.md
question 9; the copy in nostrxt/tools/ is byte-identical and drift-gated).
The additions are exactly what nostrxt/src/nostrxt.livecodescript uses beyond
coinxt's subset, measured rather than guessed: command/on handler definitions
and statement-position handler calls; `exit <handler>`; chained array
subscripts (read and write, any depth); `the keys of` and
`is [not] among the keys of`; `repeat for each item`; the lineDelimiter as
modelled state beside the itemDelimiter, with `line` chunks and
`sort lines of`; the operators `contains` / `begins with` / `ends with` /
`is [not] an integer` / `is [not] a number`; textEncode/textDecode with a real
UTF-8 encoding; and base64Encode/base64Decode. Everything outside the union is
still refused loudly.

THE NAMED DIVERGENCES GREW WITH IT, same contract as the `is` note above
(stricter-than-engine is acceptable and documented; looser is a bug):
  - `contains` / `begins with` / `ends with` are modelled CASE-SENSITIVELY,
    like `is`. The engine folds case on all three unless `the caseSensitive`
    is set. Stricter, same reasoning as _eq.
  - `is an integer` / `is a number` model the ENGINE's coercion faithfully
    ("1e3" IS an integer to the engine - docs/OXT-ENGINE-NOTES and nostrxt's
    own gotcha 4), because the shipped script GUARDS against that fold with
    digit-run checks and a stricter model here would test the guard against a
    world where the hazard does not exist. (Since 2026-09-25 the forms
    Python's float() and the engine's MCU_strtor8 read differently are
    refused rather than answered: the third 2026-09-25 section below.)
  - `the keys of` returns keys in INSERTION order, one per line, each in the
    spelling it was FIRST stored under (see the key fold below). The engine
    documents no order at all, so any script that needs one must sort - the
    shipped files do (`sort lines of`) - and a script that silently relied on
    an order would pass here and misbehave on an engine. Stricter would be
    randomising; insertion order plus the sort discipline is enough for the
    corpus this runs.
  - `sort lines of` sorts case-insensitively (the engine default), ASCII only.
  - base64Encode wraps its output with a line break every 72 characters. The
    real engine wraps too, at a width nobody has measured on OXT
    (nostrxt/docs/08 question 1); the shipped callers strip ALL whitespace, so
    any positive wrap width exercises them and the width itself cannot matter
    to a caller that survives this model.
  - textDecode with "utf-8" replaces invalid sequences (U+FFFD) rather than
    throwing, so an encode-decode round trip DIFFERS on invalid input - which
    is exactly the validity probe the shipped NIP-44 unpad performs.
  - AN ARRAY OPERAND OF `is` IS COMPARED AS AN ARRAY, not folded to a
    string: a populated array `is empty` answers FALSE, an array with no
    keys answers TRUE against empty, and two arrays compare by content.
    This is modelled from the TREE'S OWN ENGINE EVIDENCE, not from engine
    folklore: riptide's engine-proven identity path (`put rsIdentityKeys(...)
    into tKeys` / `if tKeys is empty then return empty`) uses exactly this
    refusal discriminator and passed on two machines, which is only possible
    if a populated array is NOT empty to `is`. (A first draft of this
    extension modelled the classic array-folds-to-empty rule instead, and
    driving the unmodified nostrxt script immediately "found" a dead
    validation block - reproduce-before-fix then checked the model against
    the engine-proven corpus and the MODEL was the bug. Suspect the probe
    first.) _disp still refuses to stringify an array in every string
    context (concatenation, chunks, contains) - the coinxt lesson stands.

AND ARRAY KEYS FOLD CASE, ADDED 2026-09-24 (docs/OXT-ENGINE-NOTES.md 2.7,
OBSERVED 2026-09-15). Until this date an array was a Python dict and a key was
looked up by its exact spelling, so `tA["A"]` and `tA["a"]` were two elements
here and ONE on the engine: archivext's JSON reader shipped on that model with
a "keys looked up exactly" contract and met the engine red. That was LOOSER
than the engine in the one way the contract forbids - two keys differing only
in case never collided here, so a collision the engine really has could not
be seen by any execution gate - and it was not a stricter-is-fine divergence
like `is`, because the model gave a DIFFERENT answer, not a more cautious one.
Arrays are LcsArray now (a dict with a case-folded index beside it) and every
array operation the interpreter models goes through the _arr_* helpers below:
a subscript read, a subscript write at any depth, `is [not] among the keys
of`, array `is` array, and the deep copy at every binding (riptide's runner
routes `repeat for each key|element`, `split ... by`, and `delete variable`
through the same helpers). What is modelled, and on what evidence:
  - OBSERVED (note 2.7): with `the caseSensitive` false, a lookup, a write
    and `is among the keys of` all match a key whatever its case.
  - OBSERVED (note 2.7, "Does NOT mean"): `the keys of` answers each key's
    ORIGINAL spelling. WHICH spelling survives when two are written is the
    MODELLED choice, not an observation: the FIRST one stored keeps its
    spelling and later writes in another case replace only the value (the
    note's one document held a single spelling, so it cannot say).
  - ASSUMED, not observed with the property TRUE: `the caseSensitive`
    governs keys - note 2.7 states it, but only the default (false) was on
    the engine that day - so `set the caseSensitive to true` makes keys
    exact here. The property is modelled for array KEYS ONLY: `is`,
    `contains`, `offset` and the rest keep the named case-SENSITIVE
    divergences above. Its SCOPE is also an assumption, the LOCAL property
    the LiveCode dictionary documents ("reset to false when the current
    handler finishes executing"): every handler call starts at false and
    the caller's value comes back when the callee returns. That is a
    different scope from the delimiters, which this file holds as global
    state, the stricter reading (see ITEM_DELIMITER: note 2.3 has since
    OBSERVED the itemDelimiter handler-local on Windows and Linux, and the
    global model is kept on purpose); nothing in the tree has observed the
    scope of caseSensitive either way, and riptide's three painters set it
    true without ever resetting it, so a global model would let one painter
    silently turn every later array in a boot back into exact-spelling keys,
    the very gap this closes. Local is the scope under which a collision
    stays visible.
  - Two spellings can only coexist if written under caseSensitive true; a
    folded lookup then answers the EXACT spelling if present, else the first
    stored. Modelled; nothing in the corpus writes that shape.
  - The fold is Python's str.lower() per code point: exact for ASCII, which
    is every key the corpus writes on purpose. Beyond ASCII the engine's rule
    (a native table for native strings, Unicode folding for the rest) is
    unmeasured.
  - NOT modelled and still refused loudly, as before: `union`, `intersect`,
    `combine`, arrayEncode/arrayDecode, `the number of elements`, and
    `the number of keys of` (which does not even parse on an engine, note
    1.7). A Python caller (a gate's driver) still sees plain dict semantics
    on an LcsArray - `in`, `[]` and `.get` match spellings exactly - and a
    plain dict a driver hands in folds like any other array, through a scan.

AND A CHUNK STORE, ADDED 2026-09-11, for the same reason as the negative
range: `put X into item N of VAR` fell through to the plain-name assignment
and silently created a variable named after the chunk expression, so the
container kept its old value with no error - LOOSER than the engine, invisible
until holde-em's execution gate tampered a wire field and read "ok". Modelled
now (see assign / _chunk_store), and the plain-name branch REFUSES a target
that is not an identifier, so the next unmodelled container is loud.

AND ONE REFUSAL, ADDED 2026-09-08, which is a different KIND of entry from
every divergence above: those are modelling choices, this is a hard stop.
Numbers here are held to the engine's exact integer range (|v| <= 2^53) and
REFUSED past it, because python's arbitrary-precision int made this file
LOOSER than the engine on the one arithmetic that matters most - an 8-byte
little-endian accumulator answers 18446744073709551615 in python and
1.8446744073709552e+19 on OXT. Looser is the direction the contract forbids,
and this particular looseness was invisible to every other gate: a wide-integer
defect could pass the static checker AND every headless vector AND still be
wrong on an engine. See _exact(). The refusal is STRICTER than the engine,
which is allowed and is the point - the engine carries on with a rounded number
and tells nobody, and that is the failure this stop exists to make loud.

AND A SECOND REFUSAL OF THAT KIND, ADDED 2026-09-25: a comparison of two
numbers that the ENGINE answers differently from IEEE is REFUSED (Indistinct,
not a Thrown either) instead of answered. OBSERVED 2026-09-24 (OXT, Win32, the
suite paste's riptide fold; docs/OXT-ENGINE-NOTES.md 2.10): riptide's
rsReadBEu64 guarded a u64 with `tHi > (9007199254740992 - tLo) / 4294967296`,
and for hi = 2^21, lo = 1 - the value 2^53 + 1 - the engine ACCEPTED the
record. IEEE answers 2097152 > 2097151.99999999977 TRUE, and so did this file,
so every headless gate stayed green over a bound the engine does not enforce:
the two sides differ by 2^-32, 1.1e-16 of their size.
  The same day's second and third runs read riptide's two probe lines -
true,false,false,false and true,false,16,16 - so the engine's comparison has
a RELATIVE tolerance between 8 and 16 DBL_EPSILON (OBSERVED; engine note
2.10). The constant inside that bracket is the engine SOURCE's (DOCUMENTED,
read 2026-09-25), and riptide's third probe line then read it off an engine
to the digit (OBSERVED 2026-09-25 on Linux and then on Windows: `N is N + 1`
true at N = 450359962737050 and false one below): the numeric branch of engine/src/exec-logic.cpp's MCLogicIsEqualTo and MCLogicCompareTo,
the code behind `is` / `=`, `<>` / `is not`, `<`, `<=`, `>` and `>=`, calls
two numbers EQUAL when they differ by less than MC_EPSILON of the SMALLER
magnitude, or by less than MC_EPSILON outright when that magnitude is itself
below it, and engine/src/sysdefs.h defines MC_EPSILON as DBL_EPSILON * 10.0
(2.2e-15). exec-logic.cpp is byte-identical, and sysdefs.h's definition the
same, in OXT's own tree (github.com/OpenXTalk-org/OpenXTalk-Community-DPE,
master) and in livecode `develop-9.6` and `develop`. That rule reproduces the
first run's accept and every reading of the three probe lines - and so does
this file's refusal, which answers each probe the engine read as IEEE does
and refuses each it read otherwise (coinxt's check-script-vectors.py tier 0
holds it to all sixteen readings, riptide's tier 1c and coinxt's tier 4 to
the fourteen numeric ones). The same source compares PLAINLY in a `repeat with` bound
and in max() / min(), and `switch` matches its cases as TEXT, so those paths
are left as they were.
  The rule reaches past the probes. On the engine 0.1 + 0.2 is 0.3, 1e-20 is
0, and two INTEGERS compare equal once the smaller passes 1 / MC_EPSILON
(450359962737050, about 2^48.7) and they differ by less than MC_EPSILON of
it: at 2^53, `>` cannot tell integers up to 19 apart. A numeric-looking
string past 2^53 (and no longer than 384 characters, past which the engine
reads no string as a number) is ROUNDED to a double before it is compared, so
two different ones can be one number to `is` (engine note 2.11; see _eq,
whose text answer for those was unconditional until this date).
  REFUSED, not emulated, for the 2^53 stop's reasons: an emulated tolerance
would make every gate agree, silently, with a rule read off an engine only at
the points three probe lines touch (on two platforms, never on macOS), where
a refusal names the site to a person;
and a verdict that hangs on a difference of a few ulps is far more often a
defect in the SCRIPT than a design - an exact bound the engine does not
enforce is the class the 2026-09-24 run found. The test is the source's own
arithmetic, in doubles (_engine_equal), and _decided refuses only where the
OPERATOR's answer parts from IEEE. Equal numbers, numbers the rule keeps
apart, and a near pair on which the operator answers the same either way all
answer exactly as before: riptide's old bound at 2^53 - 1 compared 2097151 >
2097151.0000000002, a pair the engine calls equal, where `>` is false on
both, and it still answers. Only this file's own numbers are judged (an int
or a float, as _n makes them): a Python driver that substitutes a number type
of its own, to replay a comparison under a candidate engine rule, owns that
answer.
  MEASURED before it landed (2026-09-25), over every gate that runs script
through this file or riptide's runner - the run-gates.sh lists of coinxt,
nostrxt, riptide, nocloud, holde-em and torrentxt - with the tree's bounds
as they then stood. coinxt/CLAUDE.md trap 20 records what it refused, and
what the two rules the finding proposed instead (an absolute 1e-6, or a
tolerance applied without asking which operator) would have refused beside
it. RE-MEASURED 2026-09-26 over the tree that merged this with the day's
batch and engine records (the same lists, and the suite's board-boot gates;
the door logging AND raising, so every gate ran as it does): no refusal in
shipped script; the new ones were fixtures', listed in the same trap.

AND A THIRD, THE SAME DAY: an OPERAND the engine reads differently
(docs/OXT-ENGINE-NOTES.md 2.11; DOCUMENTED from the engine source, and two
of its forms OBSERVED 2026-09-25 on Linux and then on Windows: riptide's
third probe line read "1e999" is "2e999" and "1e5" is "100000" TRUE on both,
the source's prediction). MCLogicIsEqualTo and MCLogicCompareTo turn BOTH operands
into numbers whenever both convert, and only otherwise compare text; a text
converts through MCU_strtor8 (libfoundation/src/foundation-typeconvert.cpp):
MCU_strtol's integer parse, then C strtod over at most 384 characters, no
range check. So "1e5" is "100000" is TRUE on the engine, and until this date
this file compared those as text in `is` and answered false, while its `<`
family, `is a number` and arithmetic read text through Python's float(),
which reads more than strtod does. _read_text ports MCU_strtor8 line for
line, and every comparison and number reading here is held to it with 2.10's
policy: where this file's answer and the engine's are the same, it answers
as before; where they part, or where the note does not establish how the
engine reads the text at all, it REFUSES (Indistinct, citing 2.11) rather
than re-answer the engine's way or guess. What the two readings do with each
form (a text operand; "before" is this file until this date):

  form                         the engine (source)          before / now
  "12", "-3", "0012", "1.5",   a number                     a number / same
    "12.000", " 3 " (ASCII
    spaces either side)
  "1e5", "1E5", "+3", "3.",    a number (strtod; the        TEXT to `is`, a number
    ".5", "1e-999" (0)           integer parse for "3.")      elsewhere / `is` refused
                                                              where the answer moves
  "1e999" (+inf)               +inf, no range check         TEXT to `is`, a crash in
                                                              `<` / `is` refused where
                                                              it moves; `<` and
                                                              arithmetic Imprecise
  longer than 384 characters   TEXT, unless the integer     a number when it looked
    (strtod's path)              parse holds it (zero-        like a plain decimal /
                                 padded, or "12.000...")      refused where it moves
  "1_000", a digit outside     TEXT                         a number to float() /
    ASCII, an edge float()                                    refused wherever it was
    strips and C does not                                     read as one; ValueError
    ("\\x1c3"), spaces only                                    for the rest, as before
  "0x10"                       MCU_strtol's base 16, no     TEXT, or a ValueError /
                                 overflow check: NOT in the   UNSURE: refused unless
                                 note                         the two texts are one
  "0x1p3", "inf", "nan"        C99 strtod only: NOT in      TEXT or a crash /
                                 the note                     UNSURE, as above (NaN
                                                              never answered)
  a non-ASCII edge ("\\xa03")   a space or not by encoding   a number / UNSURE
                                 and locale: NOT in the note
  "" (empty)                   never a number to `is` and   `<>` read it as 0 /
                                 `<>`; 0 to the orderings     `<>` refused where it
                                                              moves; the rest agreed
  a Boolean                    never a number (text)        1 or 0 in `<` / refused

`is an integer` was already EXACT, as the engine's is (exec-math.cpp:
`d == floor(d)`, no tolerance), and stays so; it and `is a number` now refuse
the forms above where the two readings part. A refused COMPARISON that is an
operand of `and` / `or` is held back (_Undecided) and dropped where the other
operand settles the answer - the engine evaluates both operands (engine note
2.5) and gets a Boolean from each, so `false and X` is false whatever X reads
there - and raised where nothing settles it (2.10's refusals too). The
census that measured this change found the shape twice in the wallet, the
guard `X is an integer and X >= 0` over an EMPTY X, refused then because
riptide's runner ordered empty as TEXT. Text refused on its way into
arithmetic is never held back: that throws on the engine. A Boolean in
ARITHMETIC still reads as 1 or 0 here where the engine throws: named, not
changed (outside the comparison work, and Python drivers call _n on script
values). riptide's runner, which restates the `<` family and runs `switch`,
goes through the same helpers (_text_order_alike, _ordered_alike), now
orders an EMPTY operand as 0 against a number, as this file's `<` family and
the engine's MCLogicCompareTo do (the same census found the wallet's
cwSatToBtc printing an empty amount "-0.00000000" in the boot through the
old text ordering, where an engine prints "0.00000000"), and matches `case`
as TEXT, the engine's way (MCKeywordsExecSwitch). Held by coinxt's
check-script-vectors.py tier 0 (check_interp_number_text, with riptide's
third probe line as the engine READ it on Linux and on Windows, 2026-09-25,
item for item the source's prediction), the runner-model
tier of riptide's check-demo-boot.py, and nostrxt's tier 0; MEASURED over
every execution gate before it landed, and again over the merged tree on
2026-09-26 (coinxt/CLAUDE.md trap 20).
"""
import base64
import re

# COMPILED ONCE, LOOKED UP BY THE LITERAL (2026-09-11). A profile of a wallet
# boot put over five hundred million `re.match(pattern, s, re.I)` calls at a
# third of the runtime, and almost none of that was matching: the module-level
# function re-resolves the compiled pattern through re's own cache on every
# call and pays the RegexFlag enum descriptor for the `re.I` beside it. These
# two return the compiled pattern for a literal, so a call site reads the same
# and costs one dict lookup. The patterns stay inline where the code is.
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


class Thrown(Exception):
    def __init__(self, msg):
        self.msg = msg
        super().__init__(msg)


class Imprecise(Exception):
    """An integer the ENGINE could not have held exactly, produced where the
    script is doing exact integer arithmetic.

    Deliberately NOT a Thrown: an interpreted `try ... catch` must not be able
    to swallow it. This is a statement about the TOOL's fidelity ("what you
    just computed would be a different number on an engine"), not a script
    error the script gets to handle."""


class Indistinct(Exception):
    """A comparison (or a number read from text) that the ENGINE answers
    differently from this file, or that this file cannot tell how the engine
    answers. Two causes, one class, each message citing its engine note:
    two unequal numbers close enough that the engine's comparison calls them
    equal (2.10; see _decided and the header), and an operand the engine
    READS differently - text it turns into a number where this file compared
    text, text this file's float() turned into a number where the engine
    compares text, or a form whose reading the note does not establish
    (2.11; see _read_text and the header's third 2026-09-25 section).

    NOT a Thrown and NOT an Imprecise, on purpose. Not a Thrown for
    Imprecise's reason (a script `try` must not swallow a statement about the
    tool's fidelity); not an Imprecise because a driver that catches that one
    reads it as "a value went past 2^53", and this is a different fact about
    a different operation."""


def _refuse(msg):
    """Every refusal is DECIDED here, so it has one door: a measurement (a
    census that logs each refusal and lets the old answer stand, to find
    every site in one run of every gate) replaces this one function and
    nothing else. Every caller is written to fall through to the answer this
    file gave before the refusal existed. (_Undecided re-raises a refusal
    this door already decided; it decides none of its own.)"""
    raise Indistinct(msg)


class _Undecided(object):
    """The value of a COMPARISON the interpreter refused, held back while an
    `and` / `or` around it may still settle the answer without it.

    The engine evaluates BOTH operands of `and` and `or` (engine note 2.5),
    and a comparison always gives it a Boolean, so `false and X` is false
    and `true or X` is true whatever X reads there. A guard written the
    house way round - `X is an integer and X >= 0`, `X is not an integer or
    X < 0` - still compares X when the first half has already decided, and
    a refusal there is irrelevant to the answer (the census that measured
    this found the wallet's two, over an EMPTY X that riptide's runner then
    ordered as text). So p_cmp hands a refused comparison up as this
    value, p_and / p_or drop it where the other operand decides (and ONLY
    there: `not` passes it through), and p_or re-raises it when nothing did,
    so it never outlives the expression it came from. Only a comparison's
    own refusal is held back: text refused on its way into ARITHMETIC
    (`X + 0`) raises at once, because that throws on the engine, and a
    thrown error is no Boolean for `and` to mask. Every other use - text,
    arithmetic, truth, hashing - re-raises the refusal."""
    __slots__ = ("msg",)

    def __init__(self, msg):
        self.msg = msg

    def _stop(self, *_args):
        raise Indistinct(self.msg)

    def __repr__(self):
        return "<undecided comparison: %s>" % self.msg[:80]

    __bool__ = __str__ = __hash__ = __len__ = __iter__ = _stop
    __eq__ = __ne__ = __lt__ = __le__ = __gt__ = __ge__ = _stop
    __add__ = __radd__ = __sub__ = __rsub__ = __mul__ = __rmul__ = _stop
    __truediv__ = __rtruediv__ = __neg__ = __float__ = __int__ = _stop
    __index__ = __contains__ = __getitem__ = __format__ = _stop


def _both(ip, v, r):
    """`v and r` with either possibly _Undecided: a definite false decides
    (the engine's answer is false whatever the other reads), else the
    undecided one stands, else true."""
    uv, ur = isinstance(v, _Undecided), isinstance(r, _Undecided)
    if (not uv and not ip.truth(v)) or (not ur and not ip.truth(r)):
        return False
    return v if uv else (r if ur else True)


def _either(ip, v, r):
    """`v or r`, the same way round: a definite true decides."""
    uv, ur = isinstance(v, _Undecided), isinstance(r, _Undecided)
    if (not uv and ip.truth(v)) or (not ur and ip.truth(r)):
        return True
    return v if uv else (r if ur else False)


class Bytes(str):
    """xTalk does not distinguish a byte string from a text string; both are
    sequences of chars. We model everything as a python str of code points
    0..255, which is what byteToNum/numToByte imply."""


def split_outside_strings(line, words):
    """Split `line` at the first of `words` that appears OUTSIDE a string
    literal, as a whole word. Returns (before, word, after) or None.

    A non-greedy regex cannot do this, and getting it wrong is silent. The
    statement

        put "OXT script variables are not locked memory. A seed typed into
             this" & return after tOut

    splits at the `into` INSIDE its own message, leaving an unterminated
    string as the value expression - which surfaces far from the cause, as a
    ValueError out of the string scanner. Found 2026-08-31 by coinxt's boot
    gate on a paint handler no other gate had ever executed. The engine has
    a real tokenizer and never had this problem; this is the model catching
    up with it."""
    low = line.lower()
    i, instr = 0, False
    while i < len(line):
        c = line[i]
        if c == '"':
            instr = not instr
            i += 1
            continue
        if not instr:
            for w in words:
                n = len(w)
                if low[i:i + n] == w:
                    before_ok = i == 0 or not (line[i - 1].isalnum()
                                               or line[i - 1] == "_")
                    j = i + n
                    after_ok = j >= len(line) or not (line[j].isalnum()
                                                      or line[j] == "_")
                    if before_ok and after_ok:
                        return line[:i].rstrip(), w, line[j:].lstrip()
        i += 1
    return None


# `the caseSensitive`, as modelled state: FALSE is the engine default, and it
# is what makes array keys fold (engine notes 2.7). A LOCAL property - Interp.
# call resets it at every handler entry and restores the caller's value on
# the way out; see the header for why that scope, and that it is assumed.
CASE_SENSITIVE = [False]

_MISS = object()


def _fold(key):
    """The spelling a key is INDEXED under when case folds (see the header:
    exact for ASCII, str.lower() beyond it). A non-string key - only ever in
    a dict a Python driver built - is its own fold."""
    return key.lower() if isinstance(key, str) else key


class LcsArray(dict):
    """An xTalk ARRAY: a dict keyed by each key's STORED spelling (the first
    one written, which is what `the keys of` answers), plus `_ix`, a map from
    the folded spelling to that stored one. Every mutator a Python caller can
    reach keeps the index true, because a stale index is a SILENT miss - a
    key that exists answering empty - which is exactly the looser-than-engine
    failure this class exists to end.

    The interpreter never reads or writes one through `[]` or `in`: those keep
    the plain dict contract (exact spellings) for the Python drivers that set
    up and inspect interpreter state, and the folding lives in the _arr_*
    helpers, which accept a plain dict too. `_mixed` is set once two stored
    spellings share a fold (possible only under caseSensitive true); until
    then a delete never has to rescan."""
    __slots__ = ("_ix", "_mixed")

    def __init__(self, *args, **kw):
        dict.__init__(self, *args, **kw)
        self._reindex()

    def _reindex(self):
        ix, mixed = {}, False
        for k in dict.keys(self):
            f = _fold(k)
            if f in ix:
                mixed = True
            else:
                ix[f] = k
        self._ix, self._mixed = ix, mixed

    def _noted(self, k):
        f = _fold(k)
        was = self._ix.get(f, _MISS)
        if was is _MISS:
            self._ix[f] = k
        elif was != k:
            self._mixed = True

    def _forgot(self, k):
        f = _fold(k)
        if self._ix.get(f, _MISS) != k:
            return
        del self._ix[f]
        if self._mixed:
            for other in dict.keys(self):
                if _fold(other) == f:
                    self._ix[f] = other
                    break

    def __setitem__(self, k, v):
        if not dict.__contains__(self, k):
            self._noted(k)
        dict.__setitem__(self, k, v)

    def __delitem__(self, k):
        dict.__delitem__(self, k)
        self._forgot(k)

    def pop(self, k, *default):
        if dict.__contains__(self, k):
            v = dict.pop(self, k)
            self._forgot(k)
            return v
        return dict.pop(self, k, *default)

    def popitem(self):
        k, v = dict.popitem(self)
        self._forgot(k)
        return k, v

    def setdefault(self, k, default=None):
        if not dict.__contains__(self, k):
            self[k] = default
        return dict.__getitem__(self, k)

    def update(self, *args, **kw):
        for k, v in dict(*args, **kw).items():
            self[k] = v

    def __ior__(self, other):
        self.update(other)
        return self

    def clear(self):
        dict.clear(self)
        self._ix, self._mixed = {}, False

    def copy(self):
        out = LcsArray.__new__(LcsArray)
        dict.__init__(out, self)
        out._ix, out._mixed = dict(self._ix), self._mixed
        return out

    __copy__ = copy

    def __deepcopy__(self, memo):
        # a gate snapshots ip.globals with copy.deepcopy; the generic path
        # would rebuild the dict through __setitem__ AFTER restoring the
        # slots, which works, but spelling it out keeps the index an exact
        # copy rather than a re-derivation
        import copy as _cp
        out = LcsArray.__new__(LcsArray)
        memo[id(self)] = out
        dict.__init__(out, ((k, _cp.deepcopy(v, memo))
                            for k, v in dict.items(self)))
        out._ix, out._mixed = dict(self._ix), self._mixed
        return out


def _arr_folded(arr, key):
    """The STORED spelling of the element `key` folds onto, or None. Used only
    after an exact-spelling miss, and only while case folds."""
    f = _fold(key)
    if isinstance(arr, LcsArray):
        return arr._ix.get(f)
    for k in arr:
        # a plain dict a Python driver handed in: no index, so scan (these
        # are small, and every binding copies them into an LcsArray anyway)
        if _fold(k) == f:
            return k
    return None


def _arr_key(arr, key):
    """The stored spelling that `arr[key]` addresses on the engine, or None.
    The exact spelling wins when present (it can differ from the folded
    answer only when two spellings coexist, a caseSensitive-true shape)."""
    if dict.__contains__(arr, key):
        return key
    if CASE_SENSITIVE[0]:
        return None
    return _arr_folded(arr, key)


def _arr_get(arr, key):
    """`arr[key]` as a VALUE: the element, or empty when there is none (the
    engine's behaviour for a missing key)."""
    v = dict.get(arr, key, _MISS)
    if v is not _MISS:
        return v
    if CASE_SENSITIVE[0]:
        return ""
    k = _arr_folded(arr, key)
    return "" if k is None else dict.__getitem__(arr, k)


def _arr_has(arr, key):
    """`key is among the keys of arr`."""
    return _arr_key(arr, key) is not None


def _arr_set(arr, key, value):
    """`put value into arr[key]`: an element that folds onto an existing key
    REPLACES that element's value and keeps its first spelling (the modelled
    choice, header); only a new element is stored under this spelling."""
    k = _arr_key(arr, key)
    if k is None:
        arr[key] = value            # LcsArray.__setitem__ indexes the spelling
    else:
        dict.__setitem__(arr, k, value)


def _arr_del(arr, key):
    """`delete variable arr[key]`: removes the element the key folds onto; a
    missing key is a no-op, as on the engine."""
    k = _arr_key(arr, key)
    if k is not None:
        del arr[k]


def _arr_eq(a, b):
    """Two arrays compare equal when every key of one addresses an equal
    element of the other under the CURRENT case rule (so {"a": 1} is {"A": 1}
    by default). Leaves compare as python values, exactly as the plain dict
    `==` this replaces did - a change to leaf comparison would be a second
    model change, and this one is about keys."""
    if len(a) != len(b):
        return False
    for k, v in dict.items(a):
        kb = _arr_key(b, k)
        if kb is None:
            return False
        w = dict.__getitem__(b, kb)
        if isinstance(v, dict) or isinstance(w, dict):
            if not (isinstance(v, dict) and isinstance(w, dict)
                    and _arr_eq(v, w)):
                return False
        elif v != w:
            return False
    return True


def _copy(v):
    """xTalk ARRAYS ARE VALUES, not references: `put tA into tB` copies, and a
    later write through tB leaves tA alone. Python dicts are references, so
    every place a value crosses a binding - assignment, argument, return -
    copies. Without this, cxHdNeuter (`put pNode into tNode`, then blank the
    private key) would silently blank the CALLER's node and the interpreter
    would model a bug the engine does not have. The copy is an LcsArray
    whatever went in, so a plain dict a Python driver planted is indexed from
    its first binding on; an LcsArray's index is copied, not re-derived."""
    if not isinstance(v, dict):
        return v
    out = LcsArray.__new__(LcsArray)
    dict.__init__(out, {k: _copy(x) for k, x in dict.items(v)})
    if isinstance(v, LcsArray):
        out._ix, out._mixed = dict(v._ix), v._mixed
    else:
        out._reindex()
    return out


# The engine holds every number as an IEEE double, so an INTEGER is exact only
# while |v| <= 2^53. Python's int is arbitrary-precision, which made this
# interpreter LOOSER than the engine on exactly the arithmetic that matters
# most here: an 8-byte little-endian accumulator returns 18446744073709551615
# in python and 1.8446744073709552e+19 on OXT. That is the one direction this
# file's contract forbids ("stricter-than-engine is acceptable and documented;
# looser is a bug"), and it is invisible to every other gate - a wide-integer
# defect could pass the static checker AND every headless vector AND still be
# wrong on an engine.
#
# So every value that reaches arithmetic, and every arithmetic RESULT, is held
# to the engine's exact range and REFUSED past it. Refusing rather than
# emulating the double is the deliberate choice, and it is this file's existing
# posture ("it REFUSES anything outside the subset rather than guessing"): a
# silently-rounded answer here would just move the silence, while a refusal
# names the site. Refusing is STRICTER than the engine, which is allowed; the
# engine would carry on with a rounded value.
_EXACT_INT_MAX = 2 ** 53   # 9007199254740992


def _exact(v):
    """Return v, or refuse it as outside the engine's exact integer range.

    Applies to a python int (exact by construction) and to an INTEGRAL float,
    because both mean the script is treating the value as a whole number. A
    non-integral float is left alone: it is approximate on any engine and the
    script is not claiming otherwise."""
    if isinstance(v, int) and not isinstance(v, bool):
        if -_EXACT_INT_MAX <= v <= _EXACT_INT_MAX:
            return v
    elif isinstance(v, float):
        if v != v or v in (float("inf"), float("-inf")):
            raise Imprecise(
                "arithmetic produced %r, which no engine double holds as a "
                "number" % (v,))
        if v != int(v) or -_EXACT_INT_MAX <= v <= _EXACT_INT_MAX:
            return v
    else:
        return v
    raise Imprecise(
        "the value %s exceeds 2^53, the largest integer an engine double holds "
        "exactly. On OXT this arithmetic yields a ROUNDED number, so the "
        "script is wrong there even though it is right here. Split the value "
        "(bytes, hex or decimal digits) instead of accumulating it - see the "
        "no-big-integer discipline in coinxt/src/coinxt.livecodescript."
        % (v,))


def _n(v):
    """Coerce to number the way xTalk does when arithmetic is applied.

    Text is read by Python's float(), which reads MORE than the engine's
    MCU_strtor8 (engine note 2.11; _read_text): "1_000", digits outside
    ASCII, an edge Python calls whitespace and C does not, a fraction past
    384 characters, and a string of spaces (0 here) are all text there, so
    arithmetic on them THROWS on an engine where this file computed. Since
    2026-09-25 such text is refused (Indistinct) rather than read, and so is
    text the note does not say how the engine reads (inf and nan words, a
    non-ASCII edge); text float() rejects raises its ValueError as before.
    A Boolean still reads as 1 or 0 here, where the engine refuses it: a
    named divergence outside the comparison work, recorded in the header."""
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        return _exact(v)
    raw = str(v)
    s = raw.strip()
    if s == "":
        if raw != "":
            _refuse_number_text(raw, _read_text(raw))
        return 0
    try:
        f = float(s)
    except ValueError:
        # text float() rejects stays a ValueError, bar a form the engine
        # may read ("0x10"), which is refused by name
        reading = _read_text(raw)
        if reading[0] == _READ_UNSURE:
            _refuse_number_text(raw, reading, read_here=False)
        raise
    if f != f or f in (_INF, -_INF):
        # no engine double this file holds: the 2^53 stop (Imprecise), as
        # before, unless the note does not establish the text at all
        reading = _read_text(raw)
        if reading[0] == _READ_UNSURE:
            _refuse_number_text(raw, reading)
        return _exact(f)
    # the 2^53 stop FIRST, as before: past it `is` answers by the text
    # (see _eq), whatever the engine's reading
    value = _exact(int(f) if f == int(f) else f)
    reading = _read_text(raw)
    if reading[0] != _READ_NUMBER:
        _refuse_number_text(raw, reading)
    return value


# THE ENGINE'S COMPARISON, as its source writes it (the constant DOCUMENTED;
# the tolerance RELATIVE and between 8 and 16 DBL_EPSILON, OBSERVED 2026-09-24;
# the header's 2026-09-25 section has the record, and why a disagreement is
# REFUSED rather than emulated). engine/src/exec-logic.cpp's MCLogicIsEqualTo
# and MCLogicCompareTo - behind `is` / `=`, `<>` / `is not`, and `<`, `<=`,
# `>`, `>=` - skip IEEE equality for two numbers and call them EQUAL when
#     t_min = min(|l|, |r|)
#     t_min <  MC_EPSILON:   |l - r|           < MC_EPSILON
#     t_min >= MC_EPSILON:   |l - r| / t_min   < MC_EPSILON
# with `#define MC_EPSILON (DBL_EPSILON * 10.0)` in engine/src/sysdefs.h.
# _engine_equal is that arithmetic, in doubles, the way the C does it.
_MC_EPSILON = 2.0 ** -52 * 10.0     # DBL_EPSILON * 10.0 = 2.220446049250313e-15

# The engine's answer for each operator once it has called the pair EQUAL
# (MCLogicCompareTo answers 0, and `>` is `order > 0`, `>=` is `order >= 0`,
# ...). `is` stands for `=` as well; `is not` is p_cmp's negation of `is`.
_ON_ENGINE_EQUAL = {"is": True, "<>": False, "<": False, ">": False,
                    "<=": True, ">=": True}

# The longest string the engine will read as a number: MCU_strtor8 in
# libfoundation/src/foundation-typeconvert.cpp (`#define R8L 384`, the same
# source reading) answers "not a number" for anything longer, so `is` falls
# back to comparing TEXT - a 428-digit hex that happens to be all digits,
# like holde-em's kKatEnv0ContentHex, is never a number there.
_R8L = 384

# The number types this file makes: _n answers an int or a float, and a bool
# never reaches a numeric comparison. Checked as EXACT types, not with
# isinstance: a Python driver that hands a comparison a number type of its
# own (a gate replaying the comparison under a candidate engine rule, with a
# float subclass or a wrapper that answers the six operators itself) has
# taken the answer over, and this check must not second-guess it.
_PLAIN_NUMBER = (int, float)


def _engine_equal(a, b):
    """True when the engine's comparison calls two numbers equal (above).
    float() is exact here: an int that reaches a comparison came through
    _exact, so it is at most 2^53."""
    fa, fb = float(a), float(b)
    if fa == fb:
        return True
    da, db = abs(fa), abs(fb)
    t_min = da if da < db else db
    if t_min < _MC_EPSILON:
        return abs(fa - fb) < _MC_EPSILON
    return abs(fa - fb) / t_min < _MC_EPSILON


def _decided(a, b, op, where=None):
    """Return quietly when the engine answers `a op b` as IEEE - and so this
    file - does; REFUSE it (Indistinct) when it does not.

    The two part only when a and b are unequal and the engine calls them
    equal, and then only for an operator whose answer moves: `is` and `<>`
    always, `>` and `<=` only when a > b in IEEE, `<` and `>=` only when
    a < b - whatever the order, the engine's answer is _ON_ENGINE_EQUAL[op].
    OPERATOR-AWARE on purpose, and the corpus shows why: riptide's old u64
    bound compared 2097151 > 2097151.0000000002 for the VALID seq 2^53 - 1,
    a pair the engine calls equal, where `>` is false either way and the
    record parses on both. Refusing that line would refuse a verdict the
    engine and this file share; at 2^53 + 1 the same line compared 2097152
    > 2097151.9999999998, true here and false there, and that one is the
    defect. `where` is the expression text when the caller has it, so the
    refusal names its site."""
    if type(a) not in _PLAIN_NUMBER or type(b) not in _PLAIN_NUMBER:
        return
    if a == b or not _engine_equal(a, b):
        return
    engine = _ON_ENGINE_EQUAL[op]
    ieee = {"is": False, "<>": True, "<": a < b, ">": a > b, "<=": a <= b,
            ">=": a >= b}[op]
    if ieee == engine:
        return
    gap = abs(float(a) - float(b))
    smaller = min(abs(float(a)), abs(float(b)))
    if smaller < _MC_EPSILON:
        how = ("the smaller is within MC_EPSILON (10 * DBL_EPSILON) of zero, "
               "where the engine calls any two numbers less than MC_EPSILON "
               "apart EQUAL")
    else:
        how = ("that is %.2g of the smaller, and the engine calls two numbers "
               "EQUAL when they differ by less than MC_EPSILON (10 * "
               "DBL_EPSILON) of the smaller" % (gap / smaller))
    _refuse(
        "`%r %s %r`%s: the engine does not answer this comparison the IEEE "
        "way. The two numbers differ by %r; %s (a relative tolerance, "
        "OBSERVED on OXT 2026-09-24; its constant from "
        "engine/src/exec-logic.cpp, DOCUMENTED; docs/OXT-ENGINE-NOTES.md "
        "2.10). So on OXT this `%s` answers %s, where IEEE answers %s. Decide "
        "a bound with exact integers that differ by at least 1 at a modest "
        "magnitude (the u32 halves, the leading bytes), never against a "
        "quotient."
        % (a, op, b, (" in `%s`" % where) if where else "", gap, how, op,
           str(engine).lower(), str(ieee).lower()))


# HOW THE ENGINE READS TEXT AS A NUMBER (docs/OXT-ENGINE-NOTES.md 2.11;
# DOCUMENTED from the source, 2026-09-25; exponent-form and overflowing text
# OBSERVED the same day on Linux and Windows, no other form; the header's
# third 2026-09-25 section has the table and the policy). MCLogicIsEqualTo
# and MCLogicCompareTo turn BOTH operands into numbers whenever both
# convert, and compare numbers (2.10's rule) before they ever compare text.
# A text converts through MCExecContext::ConvertToNumber ->
# MCTypeConvertStringToReal (which refuses a string that cannot be held in
# the platform's native encoding) -> MCU_strtor8
# (libfoundation/src/foundation-typeconvert.cpp): first MCU_strtol, an
# integer parse, and only if that fails, C strtod over at most R8L (384)
# characters, with no range check. The port below is that code, line for
# line where it decides anything, with one change: a form whose reading the
# note does not establish - a hexadecimal integer (MCU_strtol's base-16
# branch, unchecked for overflow), a form C99's strtod reads and an older C
# library does not (a hex float, inf, nan), an edge character outside ASCII
# (a space or not by the platform's encoding and C locale), or a decision
# that rests on the width of libfoundation's integer_t - answers UNSURE
# instead of a guess, and a caller refuses wherever the answer could move.
_C_SPACE = " \t\n\v\f\r"          # C isspace() over ASCII, in every locale
_INTEGER_MAX = 2 ** 31 - 1        # libfoundation's INTEGER_MAX (int32_t)
_HEX_DIGITS = "0123456789abcdefABCDEF"
_INF = float("inf")

_READ_EMPTY = "empty"      # "": no number to `is`, 0 to `<` (the source)
_READ_TEXT = "text"        # the engine compares it as text (certain)
_READ_NUMBER = "number"    # the engine reads it as this number (certain)
_READ_UNSURE = "unsure"    # the note does not establish the reading

# What can begin a text MCU_strtor8 accepts, once C spaces are skipped: a
# digit, a sign, a point, or the first letter of inf / nan. Anything else
# settles it as text without a scan (most text compared in a gate).
_NUMBER_STARTS = frozenset("0123456789+-.iInN")
# ... and the ASCII characters that settle it the other way, looked up once
_OPENS_TEXT = frozenset(chr(c) for c in range(1, 128)) - _NUMBER_STARTS \
    - frozenset(_C_SPACE)

# The subject sequences of C strtod: the decimal form every C library reads,
# and the forms only C99's reads (a hex float, inf / infinity, nan / nan(...)).
_STRTOD_DECIMAL = re.compile(
    r'[+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?')
_STRTOD_C99_ONLY = re.compile(
    r'[+-]?(?:0[xX](?:[0-9a-fA-F]+\.?[0-9a-fA-F]*|\.[0-9a-fA-F]+)'
    r'(?:[pP][+-]?[0-9]+)?'
    r'|[iI][nN][fF](?:[iI][nN][iI][tT][yY])?'
    r'|[nN][aA][nN](?:\([0-9A-Za-z_]*\))?)')
_WIDE_DECIMAL = re.compile(r'[+-]?([0-9]+)(?:\.0*)?')

_UNSURE_HEX = ("a hexadecimal integer, which MCU_strtol reads in base 16 with "
               "no overflow check; engine note 2.11 does not name the form")
_UNSURE_C99 = ("a form C99's strtod reads (a hex float, inf, nan) and an "
               "older C library does not; engine note 2.11 does not say "
               "which library the engine was built against")
_UNSURE_EDGE = ("a character outside ASCII (or a NUL) at its edge, a space "
                "to the engine or not by the platform's native encoding and "
                "C locale, which engine note 2.11 does not establish")
_UNSURE_WIDTH = ("longer than 384 characters, so whether the engine's integer "
                 "parse holds it rests on the width of libfoundation's "
                 "integer_t, which engine note 2.11 does not establish")


def _strtol(s):
    """MCU_strtol as MCU_strtor8 calls it (no delimiter, reals false,
    octals false - `the convertOctals`, which no script here sets), over an
    ASCII string with no NUL. Answers (done, value, rest, how): `how` is
    "hex" when the base-16 branch read it, "overflow" when the decimal
    digits tripped its int32 guard (the caller goes on to strtod)."""
    n = len(s)
    i = 0
    while i < n and s[i] in _C_SPACE:
        i += 1
    if i == n:
        return False, 0, "", ""
    neg = s[i] == "-"
    if s[i] in "+-":
        i += 1
        if i == n:
            return False, 0, "", ""
    start = n - i                     # C's startlength, spaces after included
    base = 10
    if s[i] == "0" and n - i > 2 and s[i + 1] in "xX":
        base = 16
        i += 2
    value = 0
    while i < n:
        ch = s[i]
        if "0" <= ch <= "9":
            v = ord(ch) - 48
            # C: `base < 16 && value > INTEGER_MAX / base - v`
            if base < 16 and value > _INTEGER_MAX // 10 - v:
                return False, 0, "", "overflow"
            value = value * base + v
        elif ch in _C_SPACE:
            while i < n and s[i] in _C_SPACE:
                i += 1
            break
        elif ch == ".":
            # an integer may END in a point and zeros ("12.", "12.000")
            if start > 1:
                i += 1
                while i < n and s[i] == "0":
                    i += 1
                if i == n:
                    break
                if s[i] in _C_SPACE:
                    i += 1
                    break
            return False, 0, "", ""
        elif base == 16 and ch in "abcdefABCDEF":
            value = value * 16 + int(ch, 16)
        else:
            return False, 0, "", ""
        i += 1
    while i < n and s[i] in _C_SPACE:
        i += 1
    return True, (-value if neg else value), s[i:], ("hex" if base == 16
                                                       else "")


def _read_text_uncached(s):
    """(kind, value, why) for the text s: how MCU_strtor8 reads it (above)."""
    if s == "":
        return _READ_EMPTY, None, ""
    if not s.isascii() or "\0" in s:
        # A character outside ASCII is never a digit, sign or point to C, so
        # INSIDE the text it settles it as text; at an EDGE it may be a
        # space the parse skips (the encoding and locale decide), so text
        # that would read as a number without it is unsure.
        core = s.strip(_C_SPACE)
        lo, hi = 0, len(core)
        while lo < hi and (not core[lo].isascii() or core[lo] == "\0"
                           or core[lo] in _C_SPACE):
            lo += 1
        while hi > lo and (not core[hi - 1].isascii() or core[hi - 1] == "\0"
                           or core[hi - 1] in _C_SPACE):
            hi -= 1
        inner = core[lo:hi]
        if (inner != core and inner and inner.isascii() and "\0" not in inner
                and _read_text(inner)[0] != _READ_TEXT):
            return _READ_UNSURE, None, _UNSURE_EDGE
        return _READ_TEXT, None, ""
    core = s.strip(_C_SPACE)
    if not core or core[0] not in _NUMBER_STARTS:
        return _READ_TEXT, None, ""
    done, value, rest, how = _strtol(s)
    if done:
        # MCU_strtor8 answers here whatever the rest is: text after the
        # integer makes the whole a non-number, never a strtod retry
        if rest:
            return _READ_TEXT, None, ""
        if how == "hex":
            return _READ_UNSURE, None, _UNSURE_HEX
        return _READ_NUMBER, value, ""
    p = s.lstrip(_C_SPACE)
    if len(p) > 1 and ((p[1] in "xX" and (len(p) == 2 or p[2] not in _HEX_DIGITS))
                       or p[1] in "+-"):
        return _READ_TEXT, None, ""
    if len(p) > _R8L:
        wide = _WIDE_DECIMAL.fullmatch(core)
        # the width test is on the DIGITS, never through int(): Python refuses
        # to convert more than 4300 digits (a ValueError, 2026-09-26: a
        # 5000-digit text compared with itself crashed here, where the engine
        # compares it as text and this file had answered)
        digits = wide.group(1).lstrip("0") if wide else ""
        if how == "overflow" and wide and (
                len(digits) < 19
                or (len(digits) == 19 and int(digits) < 2 ** 63)):
            return _READ_UNSURE, None, _UNSURE_WIDTH
        return _READ_TEXT, None, ""
    m = _STRTOD_DECIMAL.match(p)
    if m and not p[m.end():].strip(_C_SPACE):
        return _READ_NUMBER, float(m.group(0)), ""
    m = _STRTOD_C99_ONLY.match(p)
    if m and not p[m.end():].strip(_C_SPACE):
        return _READ_UNSURE, None, _UNSURE_C99
    return _READ_TEXT, None, ""


_READ_CACHE = {}


def _read_text(s):
    """_read_text_uncached, remembered for short texts: the gates compare
    the same few literals and small numbers millions of times."""
    if not s or (s[0] not in _NUMBER_STARTS and s[0] not in _C_SPACE
                 and s[0].isascii() and s[0] != "\0"):
        return (_READ_EMPTY, None, "") if not s else (_READ_TEXT, None, "")
    if len(s) > 64:
        return _read_text_uncached(s)
    got = _READ_CACHE.get(s)
    if got is None:
        if len(_READ_CACHE) > 65536:
            _READ_CACHE.clear()
        got = _READ_CACHE[s] = _read_text_uncached(str(s))
    return got


def _read_operand(v, empty_is_zero):
    """How the engine reads one comparison operand: (kind, value, why).
    `empty_is_zero` for the ordering operators, whose MCLogicCompareTo
    converts an empty operand to 0; `is` and `<>` (MCLogicIsEqualTo) never
    convert an empty one. A Boolean never converts (ConvertToNumber refuses
    the type), and neither does an array."""
    if isinstance(v, bool):
        return _READ_TEXT, None, ""
    if isinstance(v, (int, float)):
        return _READ_NUMBER, v, ""
    if isinstance(v, dict):
        return _READ_TEXT, None, ""
    got = _read_text(v if isinstance(v, str) else str(_disp(v)))
    if empty_is_zero and got[0] == _READ_EMPTY:
        return _READ_NUMBER, 0, ""
    return got


def _shown(v):
    """An operand as a refusal message spells it: text quoted (escaped, and
    cut in the middle past 60 characters), a number bare."""
    if isinstance(v, bool) or isinstance(v, (int, float)):
        return str(_disp(v)) if isinstance(v, bool) else repr(v)
    text = str(v) if isinstance(v, str) else repr(v)
    if len(text) > 60:
        text = "%s...%s (%d chars)" % (text[:28], text[-24:], len(text))
    return '"%s"' % text.encode("unicode_escape").decode("ascii").replace(
        '"', '\\"')


def _nan_like(v):
    return isinstance(v, str) and "nan" in v.lower()


def _refuse_number_text(raw, reading, read_here=True):
    """_n met text the engine reads differently from Python's float(), or
    may: arithmetic on it throws on an engine where this file computed, or
    the other way about."""
    kind, _value, why = reading
    _refuse(
        "%s: %s, and the engine %s (MCU_strtor8: an integer parse, then C "
        "strtod over at most 384 characters; docs/OXT-ENGINE-NOTES.md 2.11). "
        "So on OXT arithmetic or a numeric comparison on it is not what it "
        "is here. Validate the text before it is used as a number (digits "
        "only, `is an integer`)."
        % (_shown(raw),
           ("this file's float() reads that text as a number" if read_here
            else "this file's float() does not read that text as a number"),
           ("reads it as text" if kind != _READ_UNSURE
            else "may or may not: it is " + why)))


def _refuse_reading(a, b, op, ka, kb, engine, here):
    """A comparison whose operands the engine reads differently from this
    file (engine note 2.11): name both, the operator, both answers."""
    if engine is None:
        why = kb[2] if kb[0] == _READ_UNSURE else ka[2]
        what = ("engine note 2.11 does not establish how the engine reads "
                "one operand - %s - so this file will not guess whether this "
                "`%s` answers true or false" % (why, op))
    else:
        what = ("the engine reads %s (MCU_strtor8: an integer parse, then C "
                "strtod over at most 384 characters) and compares %s, so on "
                "OXT this `%s` answers %s, where this file (%s) answers %s"
                % ("both as NUMBERS (%r and %r)" % (ka[1], kb[1])
                   if ka[0] == _READ_NUMBER and kb[0] == _READ_NUMBER
                   else "at least one as TEXT",
                   "those" if ka[0] == _READ_NUMBER and kb[0] == _READ_NUMBER
                   else "the text", op, str(engine).lower(), here,
                   str(not engine).lower()))
    _refuse(
        "`%s %s %s`: %s (docs/OXT-ENGINE-NOTES.md 2.11). Compare a digest, "
        "token or key with a letter prefixed to both sides, or byte by byte; "
        "compare a count only after `is an integer` has admitted it."
        % (_shown(a), op, _shown(b), what))


def _text_is_checked(a, b, sa, sb, same):
    """`is` answered by the TEXT (`same`): return quietly where the engine
    answers the same, REFUSE where it reads both operands as numbers and
    answers otherwise, or where it cannot be told. The engine compares text
    whenever either operand is not a number (or is empty), so that half
    always agrees - modulo `the caseSensitive`, whose `is` divergence is the
    header's first, named and unchanged."""
    # the common case first, without a scan: either side empty, or opening
    # with a character no number can open with, is text to the engine
    if (not sa or not sb or sa[0] in _OPENS_TEXT or sb[0] in _OPENS_TEXT):
        return
    ka = _read_operand(a, False)
    if ka[0] in (_READ_TEXT, _READ_EMPTY):
        return
    kb = _read_operand(b, False)
    if kb[0] in (_READ_TEXT, _READ_EMPTY):
        return
    if ka[0] == _READ_NUMBER and kb[0] == _READ_NUMBER:
        engine = _engine_equal(ka[1], kb[1])
        if engine != same:
            _refuse_reading(a, b, "is", ka, kb, engine, "by the text")
        return
    # an operand the note does not establish, facing a number or another:
    # IDENTICAL text reads alike whichever way it is read, bar a NaN
    if same and not (_nan_like(sa) or _nan_like(sb)):
        return
    _refuse_reading(a, b, "is", ka, kb, None, "by the text")


def _ordered_alike(v, r, a, b, op, where):
    """After p_cmp's _n turned both operands of `<`, `<=`, `>`, `>=` or `<>`
    into numbers: _n refuses text the engine reads otherwise, which leaves
    two operands it turned into numbers that the engine never does - a
    Boolean (text there) and, for `<>`, an EMPTY one (`<>` is the engine's
    `is not`, which only equals empty to empty; the orderings do read empty
    as 0)."""
    for x in (v, r):
        if isinstance(x, bool):
            _refuse(
                "`%s %s %s` in `%s`: %s is a Boolean, which the engine never "
                "turns into a number - it compares \"true\" and \"false\" as "
                "TEXT - where this file compared 1 and 0 "
                "(docs/OXT-ENGINE-NOTES.md 2.11)"
                % (_shown(v), op, _shown(r), where, _shown(x)))
            return
    if op == "<>":
        ev = isinstance(v, str) and v == ""
        er = isinstance(r, str) and r == ""
        if ev != er and not (a != b):
            _refuse(
                "`%s <> %s` in `%s`: `<>` is the engine's `is not` "
                "(MCLogicIsEqualTo), which never turns an EMPTY operand into "
                "a number, so on OXT this answers true, where this file read "
                "empty as 0 and answered false (docs/OXT-ENGINE-NOTES.md "
                "2.11). Test for empty first." % (_shown(v), _shown(r), where))


def _text_order_alike(v, r, op, where):
    """riptide's runner orders two operands as TEXT unless Python reads both
    as numbers (check-demo-boot.py's p_cmp): return quietly where the engine
    orders them the same way, REFUSE where it reads both as numbers and
    answers otherwise (an empty operand is 0 to the orderings), or cannot
    be told."""
    zero = op != "<>"
    ka = _read_operand(v, zero)
    if ka[0] in (_READ_TEXT, _READ_EMPTY):
        return
    kb = _read_operand(r, zero)
    if kb[0] in (_READ_TEXT, _READ_EMPTY):
        return
    sa, sb = str(_disp(v)).lower(), str(_disp(r)).lower()
    text = {">=": sa >= sb, "<=": sa <= sb, ">": sa > sb, "<": sa < sb,
            "<>": sa != sb}[op]
    if ka[0] == _READ_NUMBER and kb[0] == _READ_NUMBER:
        x, y = ka[1], kb[1]
        eq = _engine_equal(x, y)
        engine = {">=": eq or x > y, "<=": eq or x < y,
                  ">": not eq and x > y, "<": not eq and x < y,
                  "<>": not eq}[op]
        if engine != text:
            _refuse_reading(v, r, op, ka, kb, engine,
                            "by the text, in `%s`" % where)
        return
    if sa == sb and not (_nan_like(sa) or _nan_like(sb)):
        return
    _refuse_reading(v, r, op, ka, kb, None, "by the text, in `%s`" % where)


class Interp:
    def __init__(self, src):
        self.constants = {}
        self.handlers = {}
        # SCRIPT-LEVEL `local` declarations: file-scope state shared by every
        # handler (an error slot, a capability cache). Modelled as visible
        # file-wide; the engine actually resolves script-level names by
        # LEXICAL POSITION (the suite's 106-declaration fold lesson), which
        # is not modelled here because the corpus declares its script-locals
        # at the top of the file, where the two rules agree - the family
        # checker and the fold machinery are what hold that discipline.
        self.globals = {}
        self._parse(src)

    # ---------------------------------------------------------------- parsing
    def _parse(self, src):
        lines = []
        for raw in src.split("\n"):
            # strip comments (-- to end of line), outside strings
            out, i, instr = "", 0, False
            while i < len(raw):
                c = raw[i]
                if c == '"':
                    instr = not instr
                    out += c
                elif not instr and c == "-" and i + 1 < len(raw) and raw[i + 1] == "-":
                    break
                else:
                    out += c
                i += 1
            lines.append(out.rstrip())
        # join continuation lines ending in backslash
        joined, buf = [], ""
        for ln in lines:
            if ln.endswith("\\"):
                buf += ln[:-1]
            else:
                joined.append(buf + ln)
                buf = ""
        i = 0
        while i < len(joined):
            ln = joined[i].strip()
            m = _rx(r'constant\s+(\w+)\s*=\s*(.+)$').match(ln)
            if m:
                self.constants[m.group(1)] = self.eval_expr(m.group(2), {})
                i += 1
                continue
            m = _rx(r'local\s+(.+)$').match(ln)
            if m:
                for v in m.group(1).split(","):
                    self.globals.setdefault(v.strip().lower(), "")
                i += 1
                continue
            m = _rx(r'(?:private\s+)?(?:function|command|on)\s+(\w+)\s*(.*)$').match(ln)
            if m:
                name, params = m.group(1), m.group(2)
                plist = [p.strip() for p in params.split(",") if p.strip()]
                body, i = self._collect(joined, i + 1, name)
                self.handlers[name.lower()] = (plist, body)
                continue
            i += 1

    def _collect(self, lines, i, name):
        body = []
        depth = 0
        while i < len(lines):
            s = lines[i].strip()
            low = s.lower()
            if _rx(r'^end\s+' + re.escape(name.lower()) + r'\b').match(low) and depth == 0:
                return body, i + 1
            if _rx(r'^(if\b.*\bthen$|repeat\b|try\b)').match(low):
                depth += 1
            elif _rx(r'^end\s+(if|repeat|try)\b').match(low):
                depth -= 1
            body.append(lines[i])
            i += 1
        raise SyntaxError(f"unterminated handler {name}")

    # -------------------------------------------------------------- execution
    def call(self, name, args):
        key = name.lower()
        if key not in self.handlers:
            raise NameError(f"no handler {name}")
        params, body = self.handlers[key]
        env = {}
        for idx, p in enumerate(params):
            env[p.lower()] = _copy(args[idx]) if idx < len(args) else ""
        # `the caseSensitive` is a LOCAL property (assumed; header): the
        # callee starts at the engine default, and whatever it sets does not
        # outlive it - the finally covers a throw and every _Return alike.
        was_cs = CASE_SENSITIVE[0]
        CASE_SENSITIVE[0] = False
        try:
            self._exec(body, env)
        except _Return as r:
            return r.value
        finally:
            CASE_SENSITIVE[0] = was_cs
        return ""

    def _exec(self, body, env):
        i = 0
        while i < len(body):
            i = self._exec_stmt(body, i, env)

    def _block(self, body, i, opener_re, closer_re):
        """Return (inner, index_after_end) for a block starting at body[i]."""
        depth, j, inner = 0, i + 1, []
        while j < len(body):
            s = body[j].strip().lower()
            if _rx(r'^(if\b.*\bthen$|repeat\b|try\b)').match(s):
                depth += 1
            elif _rx(r'^end\s+(if|repeat|try)\b').match(s):
                if depth == 0:
                    return inner, j + 1
                depth -= 1
            inner.append(body[j])
            j += 1
        raise SyntaxError("unterminated block")

    def _exec_stmt(self, body, i, env):
        line = body[i].strip()
        if not line:
            return i + 1
        low = line.lower()

        # --- if / else if / else
        m = _rxi(r'if\s+(.*)\s+then$').match(line)
        if m:
            inner, after = self._block(body, i, None, None)
            # split inner on top-level else
            branches, cur, depth = [], [], 0
            cond = m.group(1)
            conds = [cond]
            for ln in inner:
                s = ln.strip().lower()
                if _rx(r'^(if\b.*\bthen$|repeat\b|try\b)').match(s):
                    depth += 1
                elif _rx(r'^end\s+(if|repeat|try)\b').match(s):
                    depth -= 1
                if depth == 0 and _rx(r'^else\s+if\s+.*\s+then$').match(s):
                    branches.append(cur); cur = []
                    conds.append(_rxi(r'else\s+if\s+(.*)\s+then$').match(ln.strip()).group(1))
                    continue
                if depth == 0 and s == "else":
                    branches.append(cur); cur = []
                    conds.append(None)
                    continue
                cur.append(ln)
            branches.append(cur)
            for c, b in zip(conds, branches):
                if c is None or self.truth(self.eval_expr(c, env)):
                    self._exec(b, env)
                    break
            return after

        # --- try / catch. Only the two-part form the script layer uses; there
        # is no `finally` here because nothing in the file has one, and
        # inventing semantics for a construct we do not ship would be exactly
        # the silent-mis-parse this interpreter refuses to do.
        if low == "try":
            inner, after = self._block(body, i, None, None)
            tryb, catchb, var, depth, seen = [], [], None, 0, False
            for ln in inner:
                s = ln.strip().lower()
                if _rx(r'^(if\b.*\bthen$|repeat\b|try\b)').match(s):
                    depth += 1
                elif _rx(r'^end\s+(if|repeat|try)\b').match(s):
                    depth -= 1
                mm = _rxi(r'^catch\s+(\w+)$').match(ln.strip())
                if depth == 0 and mm and not seen:
                    seen, var = True, mm.group(1).lower()
                    continue
                (catchb if seen else tryb).append(ln)
            if not seen:
                raise SyntaxError("try without catch")
            try:
                self._exec(tryb, env)
            except Thrown as t:
                env[var] = t.msg
                self._exec(catchb, env)
            return after

        # --- repeat forms
        m = _rxi(r'repeat\s+with\s+(\w+)\s*=\s*(.+?)\s+down\s+to\s+(.+)$').match(line)
        if m:
            var, a, b = m.group(1).lower(), m.group(2), m.group(3)
            inner, after = self._block(body, i, None, None)
            k, end = _n(self.eval_expr(a, env)), _n(self.eval_expr(b, env))
            while k >= end:
                env[var] = k
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
                k -= 1
            return after
        m = _rxi(r'repeat\s+with\s+(\w+)\s*=\s*(.+?)\s+to\s+(.+?)(?:\s+step\s+(.+))?$').match(line)
        if m:
            var, a, b, st = m.group(1).lower(), m.group(2), m.group(3), m.group(4)
            inner, after = self._block(body, i, None, None)
            start, end = _n(self.eval_expr(a, env)), _n(self.eval_expr(b, env))
            step = _n(self.eval_expr(st, env)) if st else 1
            k = start
            while (step > 0 and k <= end) or (step < 0 and k >= end):
                env[var] = k
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
                k += step
            return after
        m = _rxi(r'repeat\s+while\s+(.+)$').match(line)
        if m:
            cond = m.group(1)
            inner, after = self._block(body, i, None, None)
            guard = 0
            while self.truth(self.eval_expr(cond, env)):
                guard += 1
                if guard > 2_000_000:
                    raise RuntimeError("repeat while did not terminate")
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
            return after
        # `repeat forever` - always paired with an `exit repeat` in the corpus;
        # the same runaway guard as `repeat while`, because an interpreter
        # that can hang is an interpreter whose failures nobody reads.
        if low == "repeat forever":
            inner, after = self._block(body, i, None, None)
            guard = 0
            while True:
                guard += 1
                if guard > 2_000_000:
                    raise RuntimeError("repeat forever did not terminate")
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
            return after
        # `repeat for each item VAR in EXPR` - the one for-each form the corpus
        # uses. The engine iterates a SNAPSHOT of the container, so the list is
        # materialised before the first pass and a mutation inside the loop
        # cannot change the iteration.
        m = _rxi(r'repeat\s+for\s+each\s+item\s+(\w+)\s+in\s+(.+)$').match(line)
        if m:
            var, src_expr = m.group(1).lower(), m.group(2)
            inner, after = self._block(body, i, None, None)
            items = _split_chunks(str(_disp(self.eval_expr(src_expr, env))),
                                  ITEM_DELIMITER[0])
            for it in items:
                env[var] = it
                try:
                    self._exec(inner, env)
                except _Next:
                    pass
                except _Exit:
                    break
            return after

        # --- simple statements
        if low.startswith("local "):
            for v in line[6:].split(","):
                env.setdefault(v.strip().lower(), "")
            return i + 1
        if low in ("exit repeat",):
            raise _Exit()
        if low in ("next repeat",):
            raise _Next()
        m = _rxi(r'return\b\s*(.*)$').match(line)
        if m:
            raise _Return(_copy(self.eval_expr(m.group(1), env))
                          if m.group(1).strip() else "")
        m = _rxi(r'throw\s+(.+)$').match(line)
        if m:
            raise Thrown(str(self.eval_expr(m.group(1), env)))
        m = _rxi(r'add\s+(.+?)\s+to\s+(.+)$').match(line)
        if m:
            tgt = m.group(2).strip()
            self.assign(tgt, _exact(_n(self.eval_expr(tgt, env)) + _n(self.eval_expr(m.group(1), env))), env)
            return i + 1
        m = _rxi(r'subtract\s+(.+?)\s+from\s+(.+)$').match(line)
        if m:
            tgt = m.group(2).strip()
            self.assign(tgt, _exact(_n(self.eval_expr(tgt, env)) - _n(self.eval_expr(m.group(1), env))), env)
            return i + 1
        m = _rxi(r'multiply\s+(.+?)\s+by\s+(.+)$').match(line)
        if m:
            tgt = m.group(1).strip()
            self.assign(tgt, _exact(_n(self.eval_expr(tgt, env)) * _n(self.eval_expr(m.group(2), env))), env)
            return i + 1
        m = _rxi(r'set\s+the\s+itemDelimiter\s+to\s+(.+)$').match(line)
        if m:
            ITEM_DELIMITER[0] = str(_disp(self.eval_expr(m.group(1), env)))
            return i + 1
        m = _rxi(r'set\s+the\s+lineDelimiter\s+to\s+(.+)$').match(line)
        if m:
            LINE_DELIMITER[0] = str(_disp(self.eval_expr(m.group(1), env)))
            return i + 1
        # `set the caseSensitive to X` - modelled for array KEYS only, and
        # local to the running handler (Interp.call restores it); `is` and
        # its kin keep their named case-sensitive divergence either way.
        m = _rxi(r'set\s+the\s+caseSensitive\s+to\s+(.+)$').match(line)
        if m:
            CASE_SENSITIVE[0] = self.truth(self.eval_expr(m.group(1), env))
            return i + 1
        # `sort lines of VAR` - ascending, case-insensitive (the engine
        # default), which is all the corpus asks of it (canonicalising a key
        # list before iteration). International collation is NOT modelled;
        # every sorted list in the corpus is ASCII.
        m = _rxi(r'sort\s+lines\s+of\s+(\w+)$').match(line)
        if m:
            tgt = m.group(1)
            s = str(_disp(self.eval_expr(tgt, env)))
            parts = _split_chunks(s, LINE_DELIMITER[0])
            parts.sort(key=lambda x: x.lower())
            self.assign(tgt, LINE_DELIMITER[0].join(parts), env)
            return i + 1
        m = _rxi(r'get\s+(.+)$').match(line)
        if m:
            # `get EXPR` evaluates EXPR and puts the value in `it`. The script
            # layer uses it to call a validator for its THROW, discarding the
            # return - so the evaluation is the whole point and `it` is not read.
            env["it"] = self.eval_expr(m.group(1), env)
            return i + 1
        m = _rxi(r'replace\s+(.+?)\s+with\s+(.+?)\s+in\s+(\w+)$').match(line)
        if m:
            tgt = m.group(3).strip()
            old = str(_disp(self.eval_expr(m.group(1), env)))
            new = str(_disp(self.eval_expr(m.group(2), env)))
            self.assign(tgt, str(_disp(self.eval_expr(tgt, env))).replace(old, new), env)
            return i + 1
        m = _rxi(r'delete\s+char\s+(.+?)\s+to\s+(.+?)\s+of\s+(.+)$').match(line)
        if m:
            a, b, tgt = int(_n(self.eval_expr(m.group(1), env))), int(_n(self.eval_expr(m.group(2), env))), m.group(3).strip()
            s = str(self.eval_expr(tgt, env))
            self.assign(tgt, s[:a - 1] + s[b:], env)
            return i + 1
        # STRING-AWARE, not a non-greedy regex: see split_outside_strings.
        parts = (split_outside_strings(line[4:], ("into", "after", "before"))
                 if _rxi(r'put\s').match(line) else None)
        if parts:
            val, prep, tgt = parts[0], parts[1], parts[2].strip()
            v = self.eval_expr(val, env)
            if prep == "into":
                self.assign(tgt, v, env)
            else:
                cur = self.eval_expr(tgt, env)
                cur = "" if cur == "" else str(cur)
                self.assign(tgt, (cur + str(v)) if prep == "after" else (str(v) + cur), env)
            return i + 1
        # `exit <handlerName>` - return-with-no-value from anywhere in the
        # handler (the corpus uses it in command-shaped handlers). `exit
        # repeat` was consumed above, so any exit reaching here names a
        # handler; the name is not checked against the enclosing one because
        # the checker already enforces that pairing statically.
        m = _rxi(r'exit\s+(\w+)$').match(line)
        if m and m.group(1).lower() != "repeat":
            raise _Return("")
        # A statement-position HANDLER CALL (`nxSetError "..."`, or bare with
        # no arguments - the zero-arg form must be bare, which the family
        # checker enforces; the parenthesised spelling is the engine trap this
        # interpreter must not quietly accept either, and does not: it would
        # arrive here as a call whose one argument is `()` and fail to parse).
        m = _rx(r'([A-Za-z_]\w*)\s*(.*)$').match(line)
        if m and m.group(1).lower() in self.handlers:
            args = []
            rest = m.group(2).strip()
            if rest:
                p = _Expr(self, env)
                p.s, p.i = rest, 0
                while True:
                    args.append(p.p_or())
                    p.ws()
                    if p.i < len(p.s) and p.s[p.i] == ",":
                        p.i += 1
                        continue
                    break
                if p.i < len(p.s):
                    raise SyntaxError(f"trailing input in call {line!r}")
            self.call(m.group(1), args)
            return i + 1
        raise SyntaxError(f"unsupported statement: {line!r}")

    def subscript_chain(self, target, env):
        """`name[k1][k2]...` -> (lowercased name, [evaluated keys]), or None
        when `target` does not start with a subscripted name.

        A bracket CHAIN (`tTags[tI][tJ]`, any depth), each key itself a full
        expression, scanned with depth counting so a subscripted key
        (`tA[tB[1]]`) cannot split the chain in the wrong place. Shared by
        assign and by riptide's runner's `delete variable`, so a write and a
        delete address an element the same way."""
        m = _rx(r'^(\w+)\s*\[').match(target)
        if not m:
            return None
        name = m.group(1).lower()
        keys, i = [], len(m.group(1))
        while i < len(target) and target[i] in " \t":
            i += 1
        while i < len(target) and target[i] == "[":
            depth, j = 1, i + 1
            while j < len(target) and depth:
                if target[j] == "[":
                    depth += 1
                elif target[j] == "]":
                    depth -= 1
                j += 1
            if depth:
                raise SyntaxError(f"unbalanced subscript in {target!r}")
            keys.append(str(_disp(self.eval_expr(target[i + 1:j - 1], env))))
            i = j
            while i < len(target) and target[i] in " \t":
                i += 1
        if i != len(target):
            raise SyntaxError(f"cannot assign to {target!r}")
        return name, keys

    def assign(self, target, value, env):
        # A CHUNK STORE: `put X into item|line|char|byte N of CONTAINER`.
        # Until 2026-09-11 this fell through to the plain-name branch below
        # and silently created a variable NAMED "item 6 of ttampered" - the
        # container untouched, no error, and the script's next read of it
        # answering the OLD value. That is the LOOSER-than-engine direction
        # the header's contract forbids, and it was invisible for the same
        # reason the negative-range defect was: no shipped source that any
        # gate ran had written the form. holde-em's harness does (it tampers
        # a wire's sixth field to prove verify drops it), and its execution
        # gate read "ok" for a tampered wire on its first run. The container
        # is stored back through this same function, so a bracket chain
        # works as a container too. The plain-name branch now REFUSES any
        # target that is not an identifier, so the next unmodelled form is
        # loud rather than a variable nobody reads.
        m = _rxi(r'^(item|line|char|character|byte)\s+(.+?)\s+of\s+'
                     r'(\w+(?:\s*\[.*\])?)$').match(target)
        if m:
            unit = m.group(1).lower()
            n = int(_n(self.eval_expr(m.group(2), env)))
            container = m.group(3).strip()
            cur = str(_disp(self.eval_expr(container, env)))
            self.assign(container, _chunk_store(unit, n, cur, str(_disp(value))), env)
            return
        chain = self.subscript_chain(target, env)
        if chain:
            # Each step addresses its element through the key fold (engine
            # notes 2.7): `put 1 into tA["X"]["y"]` lands in the element an
            # earlier `tA["x"]["Y"]` created, under that first spelling.
            name, keys = chain
            store = (self.globals if (name not in env and name in self.globals)
                     else env)
            if not isinstance(store.get(name), dict):
                store[name] = LcsArray()
            node = store[name]
            for k in keys[:-1]:
                child = _arr_get(node, k)
                if not isinstance(child, dict):
                    child = LcsArray()
                    _arr_set(node, k, child)
                node = child
            _arr_set(node, keys[-1], _copy(value))
            return
        low = target.strip().lower()
        if not _rx(r'^[a-z_]\w*$').match(low):
            raise SyntaxError(f"cannot assign to {target!r} (unmodelled container)")
        if low not in env and low in self.globals:
            self.globals[low] = _copy(value)
            return
        env[low] = _copy(value)

    def truth(self, v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    # ------------------------------------------------------------- expressions
    def eval_expr(self, expr, env):
        return _Expr(self, env).parse(expr)


class _Return(Exception):
    def __init__(self, value): self.value = value


class _Exit(Exception): pass
class _Next(Exception): pass


class _Expr:
    """Recursive-descent evaluator for the expression subset used."""

    def __init__(self, interp, env):
        self.ip, self.env = interp, env

    def parse(self, s):
        self.s, self.i = s.strip(), 0
        v = self.p_or()
        self.ws()
        if self.i < len(self.s):
            raise SyntaxError(f"trailing input in {s!r} at {self.s[self.i:]!r}")
        return v

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t":
            self.i += 1

    def kw(self, *words):
        # The hottest helper in a boot (130 million calls in one profile):
        # every expression tier asks it for its keywords after every atom.
        # The first character rules out nearly every word before any slice
        # is taken, which is most of what it used to spend.
        self.ws()
        s, i = self.s, self.i
        n = len(s)
        if i >= n:
            return None
        c0 = s[i].lower()
        for w in words:
            if w[0] != c0:
                continue
            j = i + len(w)
            if s[i:j].lower() == w and (j == n or not s[j].isalnum()):
                self.i = j
                return w
        return None

    # `and` / `or` evaluate BOTH operands, as the engine does (engine note
    # 2.5). A refused comparison arrives as an _Undecided, which a definite
    # operand on the other side can settle (_both, _either); what nothing
    # settles is raised at the top of the expression, here in p_or, so an
    # _Undecided never leaves the expression it was made in.
    def p_or(self):
        v = self.p_and()
        while True:
            save = self.i
            if self.kw("or"):
                r = self.p_and()
                v = _either(self.ip, v, r)
            else:
                self.i = save
                if isinstance(v, _Undecided):
                    raise Indistinct(v.msg)
                return v

    def p_and(self):
        v = self.p_not()
        while True:
            save = self.i
            if self.kw("and"):
                r = self.p_not()
                v = _both(self.ip, v, r)
            else:
                self.i = save
                return v

    def p_not(self):
        if self.kw("not"):
            v = self.p_not()
            # `not` of a Boolean is a Boolean: an undecided one stays so
            return v if isinstance(v, _Undecided) else not self.ip.truth(v)
        return self.p_cmp()

    def p_cmp(self):
        v = self.p_concat()
        while True:
            save = self.i
            if self.kw("contains"):
                r = self.p_concat()
                v = str(_disp(r)) in str(_disp(v))
                continue
            if self.kw("begins"):
                assert self.kw("with"), f"expected `with` in {self.s!r}"
                r = self.p_concat()
                v = str(_disp(v)).startswith(str(_disp(r)))
                continue
            if self.kw("ends"):
                assert self.kw("with"), f"expected `with` in {self.s!r}"
                r = self.p_concat()
                v = str(_disp(v)).endswith(str(_disp(r)))
                continue
            if self.kw("is"):
                neg = bool(self.kw("not"))
                if self.kw("among"):
                    assert self.kw("the") and self.kw("keys") and self.kw("of"), \
                        f"expected `the keys of` in {self.s!r}"
                    target = self.p_concat()
                    # folded, as the engine answers it (engine notes 2.7)
                    hit = (isinstance(target, dict)
                           and _arr_has(target, str(_disp(v))))
                    v = (not hit) if neg else hit
                    continue
                save2 = self.i
                if self.kw("an", "a"):
                    word = self.kw("integer", "number", "array")
                    if word == "array":
                        hit = isinstance(v, dict)
                        v = (not hit) if neg else hit
                        continue
                    if word:
                        try:
                            hit = _is_numeric(v, word == "integer")
                            v = (not hit) if neg else hit
                        except Indistinct as exc:
                            # held back for an `and` / `or` to settle
                            # (_Undecided), naming its site (engine note 2.11)
                            v = _Undecided("in `%s`: %s" % (self.s, exc))
                        continue
                    self.i = save2
                r = self.p_concat()
                try:
                    hit = _eq(v, r)
                    v = (not hit) if neg else hit
                except Indistinct as exc:
                    # _eq cannot see the expression; the refusal names it,
                    # held back for an `and` / `or` to settle (_Undecided)
                    v = _Undecided("in `%s`: %s" % (self.s, exc))
                continue
            self.ws()
            for op in (">=", "<=", "<>", ">", "<"):
                if self.s[self.i:self.i + len(op)] == op:
                    self.i += len(op)
                    r = self.p_concat()
                    # coerced HERE, in p_cmp's own frame: a gate that replays
                    # comparisons under a candidate engine rule finds the
                    # comparison sites by the function that calls _n
                    # (riptide's u64 replay does, 2026-09-24). _n refuses a
                    # text the engine reads otherwise (engine note 2.11)
                    try:
                        a, b = _n(v), _n(r)
                        # refused where the engine's tolerant comparison
                        # parts from IEEE (the header, 2026-09-25) ...
                        _decided(a, b, op, self.s)
                        # ... and where the engine never turns an operand
                        # into a number at all: a Boolean, and empty under
                        # `<>`, which is the engine's `is not` (2.11)
                        _ordered_alike(v, r, a, b, op, self.s)
                        v = {">=": a >= b, "<=": a <= b, ">": a > b,
                             "<": a < b, "<>": a != b}[op]
                    except Indistinct as exc:
                        # a refused comparison is held back for an `and` /
                        # `or` to settle (_Undecided); p_or raises it if
                        # nothing does. The operands were evaluated first,
                        # so text refused on its way into ARITHMETIC inside
                        # them has already raised, as it must
                        v = _Undecided("in `%s` (`%s`): %s"
                                       % (self.s, op, exc))
                    break
            else:
                self.i = save
                return v

    def p_concat(self):
        v = self.p_add()
        while True:
            self.ws()
            if self.s[self.i:self.i + 2] == "&&":
                self.i += 2
                v = str(_disp(v)) + " " + str(_disp(self.p_add()))
            elif self.s[self.i:self.i + 1] == "&":
                self.i += 1
                v = str(_disp(v)) + str(_disp(self.p_add()))
            else:
                return v

    def p_add(self):
        v = self.p_mul()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in "+-":
                op = self.s[self.i]; self.i += 1
                r = self.p_mul()
                v = _exact(_n(v) + _n(r) if op == "+" else _n(v) - _n(r))
            else:
                return v

    def p_mul(self):
        v = self.p_unary()
        while True:
            self.ws()
            if self.i < len(self.s) and self.s[self.i] in "*/":
                op = self.s[self.i]; self.i += 1
                r = self.p_unary()
                v = _exact(_n(v) * _n(r) if op == "*" else _n(v) / _n(r))
            else:
                return v

    def p_unary(self):
        self.ws()
        if self.i < len(self.s) and self.s[self.i] == "-":
            self.i += 1
            return -_n(self.p_unary())
        return self.p_atom()

    def p_atom(self):
        self.ws()
        if self.i >= len(self.s):
            return ""
        c = self.s[self.i]
        if c == "(":
            self.i += 1
            v = self.p_or()
            self.ws()
            assert self.s[self.i] == ")", f"expected ) in {self.s!r}"
            self.i += 1
            return v
        if c == '"':
            j = self.s.index('"', self.i + 1)
            v = self.s[self.i + 1:j]
            self.i = j + 1
            return v
        if c.isdigit():
            j = self.i
            while j < len(self.s) and (self.s[j].isdigit() or self.s[j] == "."):
                j += 1
            txt = self.s[self.i:j]; self.i = j
            return float(txt) if "." in txt else _exact(int(txt))
        # `the number of X of Y`
        if self.kw("the"):
            if self.kw("itemdelimiter"):
                return ITEM_DELIMITER[0]
            if self.kw("linedelimiter"):
                return LINE_DELIMITER[0]
            if self.kw("seconds"):
                # deterministic tooling: a fixed epoch a driver may set, never
                # the wall clock (a gate that reads real time is a gate whose
                # failures cannot be reproduced).
                return SECONDS[0]
            if self.kw("casesensitive"):
                return CASE_SENSITIVE[0]
            if self.kw("keys"):
                # `the keys of EXPR`: one key per line, INSERTION order (the
                # engine documents no order; see the named divergences above),
                # each in its STORED spelling - the first one written, since
                # a later write in another case lands on the same element
                # (engine notes 2.7; which spelling survives is modelled).
                assert self.kw("of"), f"expected `of` in {self.s!r}"
                target = self.p_concat()
                if not isinstance(target, dict):
                    return ""
                return "\n".join(target.keys())
            if self.kw("number"):
                assert self.kw("of")
                unit = self.kw("bytes", "chars", "characters", "items", "lines")
                assert self.kw("of")
                # The target is a FACTOR: `the number of lines of X & "/" & Y`
                # is `(count of X) & "/" & Y` and `... of X < 1` is
                # `(count of X) < 1`. Until 2026-09-11 the target was parsed
                # at the concatenation tier, so `&` and `+` after the target
                # were folded INTO it - a model of a binding the engine does
                # not have. The evidence is holde-em's harness, which asserts
                # `the number of lines of tOutboxTxt & "/" & char 1 to 3 of
                # line 1 of tOutboxTxt` against "1/r!" and passed on two
                # engines (2026-08-20, 2026-08-24); the idiom `the number of
                # lines of tList & " lines"` is everyday LiveCode. The three
                # "chunk-binding" sites coinxt and nocloud rewrote to locals
                # in 2026-09 were findings of THIS model, not of an engine,
                # and are harmless either way.
                target = self.p_unary()
                s = str(_disp(target))
                if unit in ("bytes", "chars", "characters"):
                    return len(s)
                if unit == "items":
                    return len(_split_chunks(s, ITEM_DELIMITER[0]))
                return len(_split_chunks(s, LINE_DELIMITER[0]))
            raise SyntaxError(f"unsupported `the` expression in {self.s!r}")
        # chunk expressions: byte/char/item/line N [to M] of EXPR
        unit = self.kw("byte", "bytes", "char", "chars", "character", "item",
                       "items", "line", "lines")
        if unit:
            a = self.p_add()
            b = None
            if self.kw("to"):
                b = self.p_add()
            assert self.kw("of"), f"expected `of` in {self.s!r}"
            target = self.p_atom()
            return _chunk(unit, int(_n(a)), None if b is None else int(_n(b)), target)
        # identifier: constant, variable, array ref, or function call
        m = _rx(r'[A-Za-z_]\w*').match(self.s[self.i:])
        if not m:
            raise SyntaxError(f"cannot parse {self.s[self.i:]!r}")
        name = m.group(0)
        self.i += len(name)
        low = name.lower()
        if low in ("true", "false"):
            return low == "true"
        if low == "empty":
            return ""
        # The named literals for characters that cannot be written inside a
        # quoted string without ambiguity.
        if low in ("comma", "space", "tab", "quote", "return", "cr", "lf",
                   "linefeed", "crlf"):
            # `return`/`cr`/`lf`/`linefeed` are all LINEFEED in LiveCodeScript
            # (the engine's cr has been 0x0A since classic MacOS days ended);
            # crlf is the two-byte network form.
            return {"comma": ",", "space": " ", "tab": "\t", "quote": '"',
                    "return": "\n", "cr": "\n", "lf": "\n",
                    "linefeed": "\n", "crlf": "\r\n"}[low]
        self.ws()
        if self.i < len(self.s) and self.s[self.i] == "[":
            # a bracket CHAIN: each step reads one key; a missing key or a
            # non-array node answers empty, the engine's behaviour. The
            # exact-spelling hit is inlined (the hottest read in a boot); a
            # miss goes through the fold (engine notes 2.7) in _arr_get.
            v = self.env.get(low, self.ip.globals.get(low, {}))
            while self.i < len(self.s) and self.s[self.i] == "[":
                self.i += 1
                key = str(_disp(self.p_or()))
                self.ws()
                assert self.s[self.i] == "]"
                self.i += 1
                if isinstance(v, dict):
                    got = dict.get(v, key, _MISS)
                    v = _arr_get(v, key) if got is _MISS else got
                else:
                    v = ""
                self.ws()
            return v
        if self.i < len(self.s) and self.s[self.i] == "(":
            self.i += 1
            args = []
            self.ws()
            if self.s[self.i] != ")":
                while True:
                    args.append(self.p_or())
                    self.ws()
                    if self.s[self.i] == ",":
                        self.i += 1
                        continue
                    break
            assert self.s[self.i] == ")", f"expected ) in {self.s!r}"
            self.i += 1
            return _builtin_or_handler(self.ip, name, args)
        if name in self.ip.constants:
            return self.ip.constants[name]
        if low in self.env:
            return self.env[low]
        if low in self.ip.globals:
            return self.ip.globals[low]
        if low in self.ip.handlers:
            return _builtin_or_handler(self.ip, name, [])
        return ""


def _disp(v):
    if isinstance(v, dict):
        # An array has no string value in xTalk. Rendering one as Python's
        # `{'a': 1}` would let a chunk expression or a concatenation quietly
        # produce nonsense, so this refuses instead - the same reason the rest
        # of the interpreter raises on anything outside the modelled subset.
        raise TypeError("an array has no string value; index it or use its keys")
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return v


def _eq(a, b):
    if isinstance(a, dict) or isinstance(b, dict):
        if isinstance(a, dict) and isinstance(b, dict):
            return _arr_eq(a, b)            # keys fold (engine notes 2.7)
        arr, other = (a, b) if isinstance(a, dict) else (b, a)
        return len(arr) == 0 and str(_disp(other)) == ""
    if isinstance(a, bool) or isinstance(b, bool):
        return str(_disp(a)).lower() == str(_disp(b)).lower()
    # Two NUMBERS, and below two numeric-looking strings, are compared the way
    # the engine compares numbers, which is not IEEE equality (_decided; the
    # header, 2026-09-25): refused where the two part, answered as before
    # everywhere else. _n is called from THIS frame, as in p_cmp, because a
    # gate that replays comparisons finds the sites by the function that
    # calls it.
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        a, b = _n(a), _n(b)
        _decided(a, b, "is")
        return a == b
    sa, sb = str(_disp(a)), str(_disp(b))
    # THIS FILE'S READING, unchanged since before 2026-09-25: two texts that
    # look like plain decimals are numbers, anything else is text. The
    # engine's reading is MCU_strtor8's (_read_text; engine note 2.11), and
    # wherever the two would give different ANSWERS the comparison is
    # refused, never re-answered the engine's way (the header's third
    # 2026-09-25 section has the table and the why).
    if not (sa.strip() and sb.strip()
            and _rx(r'-?\d+(\.\d+)?').fullmatch(sa.strip())
            and _rx(r'-?\d+(\.\d+)?').fullmatch(sb.strip())):
        same = sa == sb
        # answered by the TEXT: refused where the engine reads both as
        # numbers and answers otherwise ("1e5" is "100000" is true there)
        _text_is_checked(a, b, sa, sb, same)
        return same
    try:
        # _n refuses a text the engine does not read as this number (a
        # digit outside ASCII, a Python-only space, past 384 characters)
        na, nb = _n(sa), _n(sb)
    except (Imprecise, OverflowError):
        # A numeric string past 2^53 (or past any double): the engine turns
        # BOTH strings into doubles - rounding them - and compares those, so
        # two different strings can be one number there, while this branch
        # answers by the text. Until 2026-09-25 the text answer was given
        # unconditionally (a bare `except Exception` here swallowed _n's
        # 2^53 refusal and every other); it is given now only where the
        # engine would agree with it, and REFUSED where it would not:
        # "9007199254740994" is "9007199254740995" is TRUE on the engine
        # (the second rounds to ...996, one double away, inside the
        # tolerance) and false by the text. (A string that ROUNDS to 2^53 or
        # below, like "9007199254740993", never gets here: _n answers the
        # rounded number, which is the engine's reading too.) A string
        # longer than _R8L is not a number to the engine at all (the
        # integer parse gives up on it first), so a pair with one of those
        # compares as TEXT there too, and answers here.
        same = sa == sb
        _text_is_checked(a, b, sa, sb, same)
        return same
    _decided(na, nb, "is")
    return na == nb


def _split_chunks(s, d):
    # The engine ignores ONE trailing delimiter when it chunks a string:
    # "m," is ONE item, "a,," is two, "," is one (empty) item. Modelling this
    # with a bare Python split() over-counts by one whenever the string ends
    # with the delimiter, and that mismatch is exactly how cxHdDerivePath's
    # "m/" fail-open stayed invisible to this gate while failing on the real
    # engine (pass of 2026-08-10): the gate's own negative vector exercised
    # the check against a model in which the check fires, and the engine
    # never ran it. Items were engine-observed; lines follow the same
    # documented chunk rule.
    if s == "":
        return []
    if s.endswith(d):
        s = s[:-len(d)]
    return s.split(d)


def _negative_index(i, count):
    """xTalk counts a NEGATIVE chunk index from the end: -1 is the last
    element, -2 the one before it. Fixed 2026-08-28; before that this
    function did not exist and _chunk simply CLAMPED a negative start to 1
    and handed a negative end straight to a Python slice, so
    `char -3 to -1 of "abcdef"` came back "abcde" instead of "def" - wrong
    at both ends, and silently.

    It was latent rather than active: neither coinxt's nor nostrxt's shipped
    source uses a negative range, so no gate was reading a wrong answer. It
    surfaced when riptide's execution gate met `byte 10 to -1 of pFileBytes`,
    the engine-proven idiom rsOpenMasterSeed has used since phase 1 - which
    is the point worth keeping: the tool was not wrong about anything it had
    been asked, and a member with a slightly different dialect habit was all
    it took. Positive indices are untouched, deliberately, so nothing that
    passed before can change."""
    if i is None or i >= 0:
        return i
    return count + 1 + i


def _chunk(unit, a, b, target):
    s = str(_disp(target))
    if unit.startswith("item") or unit.startswith("line"):
        d = ITEM_DELIMITER[0] if unit.startswith("item") else LINE_DELIMITER[0]
        parts = _split_chunks(s, d)
        a = _negative_index(a, len(parts))
        b = _negative_index(b, len(parts))
        if b is None:
            return parts[a - 1] if 1 <= a <= len(parts) else ""
        if a < 1:
            a = 1
        return d.join(parts[a - 1:b])
    a = _negative_index(a, len(s))
    b = _negative_index(b, len(s))
    if b is None:
        return s[a - 1] if 1 <= a <= len(s) else ""
    if a < 1:
        a = 1
    if b < 0:
        return ""
    return s[a - 1:b]


def _chunk_store(unit, n, cur, val):
    """The engine's chunk STORE. An item or line past the end is reached by
    padding with delimiters (`put "x" into item 4 of "a,b"` is "a,b,,x"); a
    negative index counts from the end under the same one-trailing-delimiter
    rule the reader applies; a char or byte replaces one character, or
    appends when N is exactly one past the end. Anything else (a store past
    the end of a string, a zero or unreachable index) is REFUSED, because the
    engine's answer there has not been observed and a guess would be silent."""
    if unit in ("item", "line"):
        d = ITEM_DELIMITER[0] if unit == "item" else LINE_DELIMITER[0]
        raw = cur.split(d) if cur != "" else []
        n = _negative_index(n, len(_split_chunks(cur, d)))
        if n < 1:
            raise SyntaxError(f"chunk store into {unit} {n}: not modelled")
        while len(raw) < n:
            raw.append("")
        raw[n - 1] = val
        return d.join(raw)
    n = _negative_index(n, len(cur))
    if 1 <= n <= len(cur):
        return cur[:n - 1] + val + cur[n:]
    if n == len(cur) + 1:
        return cur + val
    raise SyntaxError(f"chunk store into {unit} {n} of a {len(cur)}-char string: not modelled")


def _py_numeric(v, want_int):
    """`is a number` / `is an integer` as this file read them until
    2026-09-25, through Python's float(): the operand is parsed as a number
    first, so "1e3" IS an integer (the named divergence in the header - the
    shipped scripts guard against exactly this fold with digit-run checks,
    and a stricter model would test those guards against a world without the
    hazard). riptide's runner still asks this question to choose between
    ordering two operands as numbers or as text."""
    try:
        s = str(_disp(v)).strip()
    except TypeError:
        return False
    if s == "":
        return False
    try:
        f = float(s)
    except ValueError:
        return False
    return f == int(f) if want_int else True


def _is_numeric(v, want_int):
    """`is a number` / `is an integer`, answered as _py_numeric answers them
    wherever the ENGINE answers the same, and refused (Indistinct) where it
    does not or cannot be told (engine note 2.11; the header's third
    2026-09-25 section). The engine (exec-math.cpp, MCMathEvalIsANumber and
    MCMathEvalIsAnInteger) asks ConvertToNumber - MCU_strtor8 for text, so
    "0x10" is a number there and "1_0" or a digit outside ASCII is not -
    and then `d == floor(d)`, EXACTLY: no tolerance, so 1 + 2^-50 is not an
    integer on either side, and "1e999" (+inf) is one there, where this
    file's int() cannot hold it."""
    kind, value, _why = _read_operand(v, False)
    engine = kind == _READ_NUMBER and (
        not want_int or value in (_INF, -_INF) or value == int(value))
    try:
        legacy, crashed = _py_numeric(v, want_int), False
    except (OverflowError, ValueError):
        legacy, crashed = None, True
    if kind == _READ_UNSURE or crashed or legacy != engine:
        _refuse(
            "`%s is %s`: this file's float() answers %s, and the engine's "
            "MCU_strtor8 %s (docs/OXT-ENGINE-NOTES.md 2.11). Validate the "
            "text with a digit-run check before it is trusted as a number."
            % (_shown(v), "an integer" if want_int else "a number",
               "nothing (it cannot hold the value)" if crashed
               else str(legacy).lower(),
               ("may not read it the same way: it is " + _why)
               if kind == _READ_UNSURE
               else "answers " + str(engine).lower()))
    return _py_numeric(v, want_int) if crashed else legacy


HASHES = {}

# ---------------------------------------------------------------------------
# `the itemDelimiter`, modelled rather than hardcoded.
#
# This used to be a hidden assumption: item chunks split on "," unconditionally,
# so a script's dependence on the engine default was INVISIBLE here. An
# adversarial review flagged exactly that, when the family took the property for
# GLOBAL MUTABLE STATE (templates/CLAUDE.md rule 5): an app may set it and not
# restore it, and any script that reads `item` afterwards then silently parses
# something else. That is the model this file keeps: ONE delimiter for the whole
# run, set and restored by the script, never reset at a handler call.
#
# THE ENGINE IS NOT THAT (engine note 2.3, OBSERVED 2026-09-24 on Windows and
# 2026-09-25 on Linux, both directions; the LiveCode dictionary's claim; no Mac
# run): there the itemDelimiter is HANDLER-LOCAL - a called handler starts at
# comma, and a callee's set ends when it returns. The global model is kept on
# purpose. It is the STRICTER reading for a leak: every unrestored set stays
# visible to a gate here, where a local model would forgive it at the return,
# so the family's save/set/restore discipline stays checkable headlessly while
# macOS and the lineDelimiter are unprobed. Two limits follow from it. A gate
# that runs the published vectors under a HOSTILE caller delimiter proves a
# guard those engines make redundant, not an exposure they have. And the model
# is BLIND to the converse: a callee that relies on inheriting its caller's
# non-comma delimiter parses as intended here and under comma on those engines.
# ---------------------------------------------------------------------------
ITEM_DELIMITER = [","]

# The lineDelimiter, the same modelled-global-state story as the item
# delimiter above: the corpus saves, sets, uses and restores it around every
# line-shaped parse, and modelling it is what lets a gate prove that
# discipline rather than assume it.
LINE_DELIMITER = ["\n"]

# `the seconds`, as a settable constant (see the note at its read site).
SECONDS = [1700000000]


def set_item_delimiter(ch):
    """Set the modelled delimiter. Returns the previous value, so a caller can
    restore it the way the family's own rule requires."""
    was = ITEM_DELIMITER[0]
    ITEM_DELIMITER[0] = ch
    return was


def _builtin_or_handler(ip, name, args):
    low = name.lower()
    if low == "bytetonum":
        s = str(_disp(args[0]))
        return ord(s[0]) if s else 0
    if low == "numtobyte":
        return chr(int(_n(args[0])) % 256)
    if low == "numtochar":
        return chr(int(_n(args[0])))
    if low == "chartonum":
        s = str(_disp(args[0]))
        return ord(s[0]) if s else 0
    if low == "trunc":
        return int(_n(args[0]))
    if low == "textencode":
        # 1-arg / non-UTF-8 stays the identity the coinxt vectors use (ASCII);
        # "utf-8"/"utf8" performs the real encoding, TEXT code points in to a
        # 0..255 byte string out - the model the Bytes docstring above states.
        enc = str(_disp(args[1])).lower() if len(args) > 1 else ""
        if enc in ("utf-8", "utf8"):
            return str(_disp(args[0])).encode("utf-8").decode("latin-1")
        return str(_disp(args[0]))          # ASCII only in our vectors
    if low == "textdecode":
        enc = str(_disp(args[1])).lower() if len(args) > 1 else ""
        if enc in ("utf-8", "utf8"):
            # invalid sequences become U+FFFD rather than raising - the
            # documented divergence that makes the shipped encode-decode
            # round-trip validity probe behave the way it was designed to.
            return str(_disp(args[0])).encode("latin-1").decode("utf-8", errors="replace")
        return str(_disp(args[0]))
    if low == "base64encode":
        raw = str(_disp(args[0])).encode("latin-1")
        enc = base64.b64encode(raw).decode("ascii")
        # the engine wraps; the width is a modelled guess (header note) that
        # any whitespace-stripping caller is indifferent to.
        return "\n".join(enc[k:k + 72] for k in range(0, len(enc), 72))
    if low == "base64decode":
        txt = re.sub(r"\s+", "", str(_disp(args[0])))
        try:
            return base64.b64decode(txt.encode("ascii"), validate=False).decode("latin-1")
        except Exception:
            return ""
    if low in ("offset", "byteoffset"):
        # `offset(needle, hay[, skip])` and its byte twin. The THIRD argument
        # is the engine's skip count, and the answer is RELATIVE to the
        # skipped prefix (LiveCode: "the value returned is relative to this
        # starting point"): offset("c", "abcabc", 3) is 3, not 6. Added
        # 2026-09-15 for archivext's JSON reader, which jumps from token to
        # token with it rather than walking every byte - the shipped file
        # calls it hundreds of times per document, so a model that only knew
        # the two-argument form would have refused the whole reader. Byte
        # and char forms coincide here because every value is a latin-1
        # code-point string (the Bytes docstring above).
        hay, nee = str(_disp(args[1])), str(_disp(args[0]))
        skip = int(_n(args[2])) if len(args) > 2 else 0
        if skip < 0:
            skip = 0
        if nee == "":
            return 0
        pos = hay.find(nee, skip)
        return 0 if pos < 0 else pos - skip + 1
    if low in HASHES:
        return HASHES[low](args)
    if low in ip.handlers:
        return ip.call(name, args)
    raise NameError(f"unknown function {name}")
