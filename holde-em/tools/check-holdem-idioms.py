#!/usr/bin/env python3
"""holde-em's member-specific idiom gates for the .livecodescript layer.

This file is the hold-em lineage checker, RENAMED in the 2026-08-15 fold: the
canonical ``tools/check-livecodescript.py`` in this member is now the suite's
UNIFIED checker (byte-identical across every member, held by the suite's
``tools/check-checker-drift.py``). This gate runs IN ADDITION to it, because
eight of its checks have no counterpart in the unified checker and every one
of them has a recorded shipped-defect provenance in this member (CLAUDE.md
gotchas H6-H9, 2, 7, 10, 11, 29): the chunk-of-array-element refusal, the
bitwise-operator refusal, the engine-token declared-name check, the
undeclared-catch-variable check, the command-invoked-with-parens check, the
dynamic-property-name refusal, the message-box-prose refusal, and the
never-declared-k-constant half of the constant check. The overlap with the
unified checker (quotes, balance) is redundancy, not drift - this copy is
deliberately NOT registered in the drift gate. Porting these checks INTO the
unified checker (and retiring this file) is recorded follow-up work in the
suite's remaining-work document.

Carried from Box2Dxt's ``tools/check-livecodescript.py`` (where every check has
caught real breakage); adapted for this repo: targets are every
``.livecodescript`` under ``src/`` and ``examples/``, and the embedded-kit
drift check was dropped as not-yet-applicable (restore it if this repo ever
embeds a library between sentinels).

It checks every target for:

  1. Smart/curly quotes — U+2018/2019/201C/201D anywhere (even in a comment or
     string) fail to compile in OXT. Must be zero. Also backslash-escaped quotes
     (``\\"``): xTalk has no string escapes, so a literal quote is the ``quote``
     constant, concatenated — ``\\"`` breaks compilation.
  2. Handler balance — every ``on`` / ``command`` / ``function`` / ``getprop`` /
     ``setprop`` / ``before`` / ``after`` has a matching ``end <name>``.
  3. Control-structure balance — every block ``if … then`` / ``repeat`` /
     ``switch`` / ``try`` is closed by its ``end`` inside the handler that opens
     it. (Logical lines are reassembled across ``\\`` continuations and comments
     are stripped first, so multi-line ``if … then`` and ``else if`` do not
     false-positive.)
  4. The dangling-else pairing (a bare ``else`` after a single-line
     ``if … then <stmt>``), which the structural pass cannot see.
  5. Chunk expressions taken directly off an array element
     (``byte i of tA[j]``, ``item 1 of tA["k"]``) -- house gotcha H6: the
     engine throws a double/binary conversion error at runtime (found on
     holde-em's first OXT pass, in the seed-XOR path). Copy the element
     into a plain local, then chunk the local.
  6. Bitwise operators (``bitXor`` etc.) -- throw double/binary on OXT (H7).
  7. Declared locals/params whose name equals an engine token (``tAb`` == the
     ``tab`` constant, gotcha 2).
  8. ``k``-prefixed constant names used but never declared -- OXT resolves the
     bare word to its own text and it throws downstream (this silently broke
     heTestDealRun when the deal constants were dropped from the block) -- and
     ``k`` names used *lexically above* their declaration, which OXT silently
     evaluates to empty at runtime (gotcha 29).
  9. A ``local`` declared inside an ``if`` / ``repeat`` / ``switch`` / ``try``
     block -- it breaks compilation of the whole script (gotcha 11); locals must
     sit at the top of the handler.
 10. ``catch VAR`` whose VAR is not a declared local (gotcha H8), and a
     locally-declared COMMAND invoked with function-call syntax (gotcha 7).

Usage::

    python3 tools/check-holdem-idioms.py

Exit status is non-zero if any gate fails (suitable for CI and pre-commit use).
"""

import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = sorted(
    list((ROOT / "src").glob("*.livecodescript"))
    + list((ROOT / "examples").glob("*.livecodescript"))
)

SMART_QUOTES = {0x2018, 0x2019, 0x201C, 0x201D}
# Handler openers. The closer is always "end <name>"; "end if/repeat/switch/try"
# close control structures, not handlers, and are handled separately.
OPENERS = ("on", "command", "function", "getprop", "setprop", "before", "after")


def strip_comment(line):
    """Drop a trailing ``--`` line comment, but not a ``--`` inside a string.
    LiveCode strings have no backslash escapes, so a double quote always toggles
    in/out of a string."""
    out = []
    in_string = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            in_string = not in_string
            out.append(c)
        elif not in_string and c == "-" and i + 1 < len(line) and line[i + 1] == "-":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def strip_strings(code):
    """Remove double-quoted string literal *contents* (keep the quotes) so a
    token scan never matches inside a string. LiveCode strings have no escapes,
    so a double quote always toggles in/out."""
    out = []
    in_string = False
    for c in code:
        if c == '"':
            in_string = not in_string
            out.append(c)
        elif not in_string:
            out.append(c)
    return "".join(out)


def strip_block_comments(text):
    """Blank ``/* ... */`` block comments (LiveCode supports them), preserving
    newlines so line numbers stay aligned. Respects string literals and ``--``
    line comments: a ``/*`` inside either is not a block-comment start. Without
    this, prose in the file's header ``/* ... */`` block is scanned as code -- a
    constant name or a ``name (`` in a comment then false-positives the
    gotcha-29 / command-as-function checks. Returns text with block-comment
    characters replaced by spaces (newlines kept)."""
    out = []
    i, n = 0, len(text)
    in_string = in_block = in_line = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "\n":
            in_line = False
            out.append("\n")
            i += 1
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                out.append("  ")
                i += 2
            else:
                out.append(" ")
                i += 1
        elif in_line:                      # inside a -- comment: leave as-is for strip_comment
            out.append(c)
            i += 1
        elif in_string:
            out.append(c)
            if c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif c == "-" and nxt == "-":      # -- line comment: keep, per-line strip_comment removes it
            in_line = True
            out.append(c)
            i += 1
        elif c == "/" and nxt == "*":
            in_block = True
            out.append("  ")
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def logical_lines(text):
    """Yield ``(lineno, code)`` logical lines: comments stripped, and physical
    lines joined across a trailing ``\\`` continuation. ``lineno`` is the first
    physical line of the logical line, for reporting."""
    text = strip_block_comments(text)
    out = []
    buf = ""
    start = None
    for i, raw in enumerate(text.split("\n"), 1):
        if start is None:
            start = i
        code = strip_comment(raw)
        if code.rstrip().endswith("\\"):
            buf += code.rstrip()[:-1] + " "
        else:
            buf += code
            out.append((start, buf))
            buf = ""
            start = None
    if buf:
        out.append((start, buf))
    return out


def check_smart_quotes(text):
    bad = []
    for i, raw in enumerate(text.split("\n"), 1):
        hits = [c for c in raw if ord(c) in SMART_QUOTES]
        if hits:
            bad.append(f"  L{i}: smart quote(s) {''.join(sorted(set(hits)))} — use straight ASCII")
    return bad


def check_escaped_quotes(text):
    r"""A backslash-escaped quote (\") -- xTalk/LiveCode has NO string escapes, so \"
    is a line-continuation backslash followed by a string-terminating quote: the
    string ends early and the rest becomes stray tokens (a compile error). A literal
    double-quote inside a string is the `quote` constant, concatenated
    (`"a " & quote & "b" & quote`). Comments are stripped first (via logical_lines),
    so a \" inside a comment does not flag. This shipped once in heProbeKit."""
    errors = []
    for lineno, code in logical_lines(text):
        if '\\"' in code:
            errors.append(
                f"  L{lineno}: backslash-escaped quote (\\\") -- xTalk has no string "
                "escapes; a literal double-quote is the 'quote' constant, concatenated"
            )
    return errors


def check_structure(text):
    """Single pass that proves handler-name matching *and* control-structure
    balance. Returns a list of human-readable error strings.

    ``repeat`` / ``switch`` / ``try`` are unambiguous blocks, matched strictly.
    ``if`` is matched leniently: LiveCode allows single-line ``if … then X`` and
    hybrid chains (``if … then X`` / ``else if … then`` block / ``end if``), so a
    block ``if … then`` is pushed but an ``end if`` with no open ``if`` is
    ignored rather than flagged. A truly unclosed block ``if`` is still caught,
    because its open frame trips the end-of-handler "unclosed" check below."""
    errors = []
    handler = None          # (name, lineno) of the open handler, or None
    ctrl = []               # stack of (kind, lineno) inside the current handler

    for lineno, code in logical_lines(text):
        low = code.strip().lower()
        if not low:
            continue
        toks = low.split()

        if handler is None:
            if toks[0] in OPENERS:
                handler = (toks[1] if len(toks) > 1 else "?", lineno)
                ctrl = []
            continue

        # --- inside a handler ---
        if toks[0] == "end" and len(toks) >= 2 and toks[1] in ("if", "repeat", "switch", "try"):
            kind = toks[1]
            if kind == "if":
                if ctrl and ctrl[-1][0] == "if":
                    ctrl.pop()                   # else: hybrid chain / stray — leniently ignore
            elif ctrl and ctrl[-1][0] == kind:
                ctrl.pop()
            else:
                errors.append(f"  L{lineno}: stray 'end {kind}' in handler '{handler[0]}'")
        elif toks[0] == "end":
            name = toks[1] if len(toks) > 1 else ""
            if ctrl:
                kind, opened = ctrl[-1]
                errors.append(
                    f"  handler '{handler[0]}' (L{handler[1]}): unclosed '{kind}' opened at L{opened}"
                )
            elif name != handler[0]:
                errors.append(f"  L{lineno}: 'end {name}' closes handler '{handler[0]}' (L{handler[1]})")
            handler = None
            ctrl = []
        elif re.match(r"^if\b", low) and re.search(r"\bthen$", low):
            ctrl.append(("if", lineno))          # block if; "else if" starts with "else", so excluded
        elif toks[0] == "repeat":
            ctrl.append(("repeat", lineno))
        elif toks[0] == "switch":
            ctrl.append(("switch", lineno))
        elif low == "try":
            ctrl.append(("try", lineno))
        elif toks[0] == "local" and ctrl:
            # a 'local' nested inside an if/repeat/switch/try block breaks
            # compilation of the whole script on OXT (gotcha 11); declarations
            # must sit at the top of the handler, before any control structure.
            kind, opened = ctrl[-1]
            errors.append(
                f"  L{lineno}: 'local' declared inside '{kind}' (opened L{opened}) in "
                f"handler '{handler[0]}' -- declare locals at the top of the handler (gotcha 11)"
            )

    if handler is not None:
        errors.append(f"  handler '{handler[0]}' (L{handler[1]}): never closed (missing 'end {handler[0]}')")
    return errors


CHUNK_OF_ELEMENT = re.compile(
    r"\b(byte|char|item|word|line|token)\b[^\n]*?\bof\s+[A-Za-z_][A-Za-z0-9_]*\s*\[")


def check_chunk_of_element(text):
    """A chunk expression whose source is an array element (``byte i of
    tA[j]``) throws a double/binary conversion error at runtime on OXT --
    confirmed on holde-em's first OXT pass (heXorSeedsA), invisible to the
    compiler. The rule: copy the element to a plain local, chunk the local.
    Plurals (``the number of bytes of ...``) do not match; a bracket later
    on the line without an ``of`` directly before it does not match."""
    errors = []
    for lineno, code in logical_lines(text):
        if CHUNK_OF_ELEMENT.search(code):
            errors.append(
                f"  L{lineno}: chunk of an array element -- copy the element to a"
                " plain local first (house gotcha H6)"
            )
    return errors


# Whole-token names that the engine reads as a constant/keyword regardless of
# case: a variable named ``tAb`` IS the ``tab`` constant (gotcha 2). Only bare
# collisions matter -- ``tType`` is fine, ``type`` is not. Kept to tokens a
# prefixed variable could plausibly spell by accident.
RESERVED_NAMES = set("""
tab cr lf crlf return linefeed formfeed space comma colon quote backslash slash
null empty nan pi true false zero one two three four five six seven eight nine ten
up down eof it me id the end then else repeat while until for of in is or and not
to into after before put get set send exit next pass global local constant
char byte word line item token element each number length offset result target
message type name owner rect loc text top bottom width height key value sound
cursor paint sort merge param params
""".split())

DECL_OPENERS = ("command", "function", "on", "getprop", "setprop", "before", "after")


def check_reserved_names(text):
    """Flag any declared local or handler parameter whose name case-insensitively
    equals an engine token (the ``tAb`` == ``tab`` trap, gotcha 2). Uses the
    comment-stripped logical lines so a keyword in prose never false-positives."""
    errors = []
    for lineno, code in logical_lines(text):
        low = code.strip()
        toks = low.split()
        if not toks:
            continue
        first = toks[0].lower()
        if first == "local":
            decl = low[len(toks[0]):]
        elif first in DECL_OPENERS and len(toks) >= 2:
            # everything after the handler name is the (comma-separated) params
            decl = low.split(None, 2)[2] if len(toks) >= 3 else ""
        else:
            continue
        for part in decl.split(","):
            name = part.strip().lstrip("@").split("[")[0].strip()
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name) and name.lower() in RESERVED_NAMES:
                errors.append(
                    f"  L{lineno}: variable/param '{name}' IS the engine token "
                    f"'{name.lower()}' (gotcha 2) — rename to a distinctive stem"
                )
    return errors


BITWISE = re.compile(r"\b(bitXor|bitAnd|bitOr|bitNot)\b", re.IGNORECASE)


def check_bitwise(text):
    """Bitwise operators (``bitXor``/``bitAnd``/``bitOr``/``bitNot``) throw a
    double/binary conversion error at runtime on this OXT engine (found the
    hard way in the seed-XOR path). They are valid LiveCode syntax, so no
    structural check sees them; the fix is pure integer arithmetic (see
    ``heByteXor`` — div/mod/add only). Flag any use so it cannot slip back in."""
    errors = []
    for lineno, code in logical_lines(text):
        m = BITWISE.search(code)
        if m:
            errors.append(
                f"  L{lineno}: bitwise operator '{m.group(1)}' — throws double/binary on "
                "OXT; use pure integer arithmetic (div/mod/add, e.g. heByteXor)"
            )
    return errors


K_CONST_DECL = re.compile(r"^\s*constant\s+(k[A-Za-z0-9]+)\s*=")
K_CONST_USE = re.compile(r"\b(k[A-Z][A-Za-z0-9]*)\b")


def check_undeclared_kconsts(text):
    """Flag any k-prefixed constant NAME that is used but never declared with
    ``constant kName = ...`` in the same file, OR used *lexically above* its
    declaration. The ``k`` prefix is the family's reserved marker for a constant
    (CLAUDE.md gotcha 3), so a used ``k...`` name with no declaration is a
    paste/typo bug: OXT resolves the bare word to its own text (or errors under
    explicitVariables), which then flows into a hash or hex decode and throws at
    runtime -- invisible to every other gate. This exact defect silently broke
    heTestDealRun when the deal constants were dropped from the block (nine kKat...
    names used, none declared).

    Use-before-declaration is a SEPARATE, equally invisible defect (gotcha 29):
    OXT resolves constant names by FILE POSITION, so a use lexically above the
    ``constant`` line compiles clean and silently evaluates to EMPTY at runtime.
    We record each name's first declaration line and flag any use whose line is
    below it. String literals are stripped first so a k-word inside a message
    never false-flags."""
    declared = {}  # name -> first declaration lineno
    for lineno, code in logical_lines(text):
        m = K_CONST_DECL.match(code)
        if m and m.group(1) not in declared:
            declared[m.group(1)] = lineno
    errors = []
    seen = set()
    for lineno, code in logical_lines(text):
        bare = strip_strings(code)
        if K_CONST_DECL.match(bare):
            continue  # the declaration line itself
        for name in K_CONST_USE.findall(bare):
            if name not in declared:
                if name not in seen:
                    seen.add(name)
                    errors.append(
                        f"  L{lineno}: constant '{name}' is used but never declared "
                        "(a 'k' name with no 'constant ... =' -- OXT reads it as its own "
                        "text and it throws downstream; complete the --gen-xtalk paste)"
                    )
            elif lineno < declared[name] and (name, "order") not in seen:
                seen.add((name, "order"))
                errors.append(
                    f"  L{lineno}: constant '{name}' is used above its declaration "
                    f"(L{declared[name]}) -- OXT resolves constants by file position, so "
                    "a use before the declaration silently evaluates to empty at runtime "
                    "(gotcha 29); move the declaration up (constants belong at the top)"
                )
    return errors


HANDLER_DECL = re.compile(r"^\s*(?:command|function|on|getprop|setprop)\s+(\w+)\s*(.*)$", re.I)
END_ANY = re.compile(r"^\s*end\s+(\w+)\s*$", re.I)
LOCAL_DECL = re.compile(r"^\s*local\s+(.+)$", re.I)
CATCH_STMT = re.compile(r"\bcatch\s+(\w+)", re.I)
# words that follow "end" as a control-structure close, not a handler close
_CTRL_ENDS = {"if", "repeat", "switch", "try"}


def check_undeclared_catch(text):
    """Flag a ``catch VAR`` whose VAR is not declared as a local or parameter of
    the enclosing handler. On strict OXT an undeclared variable referenced in the
    catch body throws a SECONDARY error at the moment the catch fires -- so the
    real failure is masked and the handler dies with an opaque "error in function
    handler". This is invisible to every other gate and to a quick read (the catch
    only misbehaves when it actually fires), and it is exactly what made
    heProbeSodium/heProbeTorrent/heDeckFromStreamKey blow up once their try
    bodies started throwing. Every catch variable must be a declared local (the
    family pattern; e.g. heTableNew declares tErr)."""
    errors = []
    cur = None
    declared = set()
    for lineno, code in logical_lines(text):
        bare = strip_strings(code)
        em = END_ANY.match(bare)
        if em:
            # only 'end <handlername>' closes a handler; end if/repeat/switch/try don't
            if cur is not None and em.group(1).lower() == cur.lower():
                cur = None
                declared = set()
            continue
        hm = HANDLER_DECL.match(bare)
        if hm and cur is None:
            cur = hm.group(1)
            declared = set()
            params = hm.group(2).strip()
            if params:
                for p in params.split(","):
                    tok = p.strip().lstrip("@").split()
                    if tok:
                        declared.add(tok[0].lower())
            continue
        lm = LOCAL_DECL.match(bare)
        if lm and cur is not None:
            for v in lm.group(1).split(","):
                tok = v.strip().split()
                if tok:
                    declared.add(tok[0].lower())
            continue
        for var in CATCH_STMT.findall(bare):
            if cur is not None and var.lower() not in declared:
                errors.append(
                    f"  L{lineno}: catch variable '{var}' in handler '{cur}' is not "
                    f"declared as a local -- an undeclared catch var throws on strict "
                    f"OXT when the catch fires (declare it: 'local ... {var}')"
                )
    return errors


CALL_PAREN = re.compile(r"\b(\w+)\s*\(")


def check_command_as_function(text):
    """Flag a locally-declared COMMAND (``command X`` / ``on X``) that is invoked
    with function-call syntax ``X(...)``. On this engine a command called as a
    function throws at the call site -- the body never even runs -- which is what
    made heRunSelftest's ``put ... heProbeSodium() ...`` blow up with "error in
    function handler" pointing at the call line. A command reports via ``the
    result`` or writes its output directly; only a ``function`` may be called with
    ``()`` (CLAUDE.md gotcha 7). Sibling/engine functions (sx*/bt*/b2k*, textEncode,
    ...) are not declared here as commands, so they never false-flag."""
    commands = set()
    functions = set()
    for _, code in logical_lines(text):
        bare = strip_strings(code)
        m = HANDLER_DECL.match(bare)
        if not m or END_ANY.match(bare):
            continue
        kw = bare.strip().split()[0].lower()
        if kw == "function":
            functions.add(m.group(1).lower())
        elif kw in ("command", "on"):
            commands.add(m.group(1).lower())
    # a name declared as BOTH (shouldn't happen) is treated as callable -- skip it
    suspect = commands - functions
    errors = []
    seen = set()
    for lineno, code in logical_lines(text):
        bare = strip_strings(code)
        if HANDLER_DECL.match(bare) and not END_ANY.match(bare):
            continue  # the declaration line's own "name (params" is not a call
        for m in CALL_PAREN.finditer(bare):
            name = m.group(1)
            if name.lower() not in suspect:
                continue
            # A command STATEMENT with a parenthesised first argument --
            # `heMakeLabel (x & "y"), z` -- is legal. That only happens when the
            # command name leads the statement (nothing but whitespace before it,
            # or right after `then`/`else`). The bug is a command name used inside
            # an EXPRESSION (`put ... heProbeSodium() ...`), where real text
            # precedes it. So skip the leading-token position, flag the rest.
            before = bare[:m.start()].strip()
            if before == "" or before.split()[-1].lower() in ("then", "else"):
                continue
            if (lineno, name) in seen:
                continue
            seen.add((lineno, name))
            errors.append(
                f"  L{lineno}: command '{name}' is called with function-call "
                f"syntax '{name}(...)' -- a command called as a function throws "
                f"on this engine (call it as a statement; a function may use '()')"
            )
    return errors


def check_dynamic_prop(text):
    """Check 11 (H9): a parenthesised dynamic property name -- ``the (expr) of
    obj`` / ``set the (expr) of obj to ...``. Property names in xTalk are
    compile-time tokens; the computed-name form is not portable OXT. It shipped
    once (v0.14.0 stored avatar paths in per-seat props built as
    ``"uHeAvatarPath" & N``) and was caught in the pre-OXT-pass re-audit. The
    portable shape is ONE property holding a line-/item-indexed list (the
    uHeAvatarPaths pattern). Strings and comments are stripped first, so prose
    that mentions the form does not flag."""
    errors = []
    for lineno, code in logical_lines(text):
        scan = strip_strings(code)
        if re.search(r"\bthe\s*\(", scan, re.IGNORECASE):
            errors.append(
                f"  L{lineno}: parenthesised dynamic property name ('the (expr) of ...')"
                " -- not portable xTalk (H9); hold the data in ONE property indexed"
                " by line/item instead"
            )
    return errors


def check_msgbox_prose(text):
    """Check 12: ``the message box`` used in CODE as a container reference.
    ``put x into the message box`` does not compile on OXT -- the message box
    CONTAINER is the single token ``msg`` (gotcha 13's family: the
    dictionary's prose name is not the compilable token). Shipped once
    (v0.17.1's report delivery) and threw at first run. Strings and comments
    are stripped first, so prose that mentions the form does not flag."""
    errors = []
    for lineno, code in logical_lines(text):
        scan = strip_strings(code)
        if re.search(r"\bthe\s+message\s+box\b", scan, re.IGNORECASE):
            errors.append(
                f"  L{lineno}: 'the message box' is dictionary prose, not a container"
                " -- the message box container token is 'msg' (put x into msg)"
            )
    return errors


def check_dangling_else(text):
    """A single-line ``if … then <stmt>`` directly followed by a BARE ``else``
    line. LiveCode/OXT binds that else to the single-line if (the dangling-else
    rule), so the bare else opens a block belonging to the *inner* if — its
    ``end if`` then closes the wrong frame and the *outer* block-if is left
    open, surfacing as a baffling "missing end if" at the handler's end. Legal
    neighbours are ``else <statement>`` (single-line chain) or a bare ``else``
    under a block ``if … then``; this exact pairing is the only broken one,
    and the purely structural pass above cannot see it."""
    errors = []
    lines = logical_lines(text)
    for (ln, code), (ln2, nxt) in zip(lines, lines[1:]):
        low = code.strip().lower()
        nlow = nxt.strip().lower()
        if (
            re.match(r"^if\b.+\bthen\s+\S", low)
            and not re.search(r"\bthen$", low)
            and nlow == "else"
        ):
            errors.append(
                f"  L{ln2}: bare 'else' after single-line 'if … then <stmt>' (L{ln}) — "
                "OXT binds the else to the inner if; make that if block-form"
            )
    return errors


def main():
    if not TARGETS:
        print("no .livecodescript files yet (src/ and examples/ are empty) — nothing to gate.")
        return 0

    failures = 0
    for path in TARGETS:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        problems = []
        problems += check_smart_quotes(text)
        problems += check_escaped_quotes(text)
        problems += check_structure(text)
        problems += check_dangling_else(text)
        problems += check_chunk_of_element(text)
        problems += check_bitwise(text)
        problems += check_reserved_names(text)
        problems += check_undeclared_kconsts(text)
        problems += check_undeclared_catch(text)
        problems += check_command_as_function(text)
        problems += check_dynamic_prop(text)
        problems += check_msgbox_prose(text)
        if problems:
            failures += 1
            print(f"FAIL  {rel}")
            for p in problems:
                print(p)
        else:
            print(f"ok    {rel}")

    print()
    if failures:
        print(f"FAILED — {failures} check(s) need attention.")
        return 1
    print("All .livecodescript gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
