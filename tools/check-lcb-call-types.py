#!/usr/bin/env python3
"""check-lcb-call-types.py - script calls into .lcb, checked at the boundary.

WHY THIS EXISTS
    An engine reported, from a demo nobody could run headlessly:

        execution error at line 178 (call: type conversion error), char 1

    "type conversion error" is LiveCode BUILDER's error for a value that will
    not convert to a declared parameter type. Every public `.lcb` handler in
    this suite declares its parameter types, and NONE of the 630 has an
    optional parameter - so every one of them is a place where a script can
    hand the engine something it must refuse at runtime, on a GUI engine, in
    front of a human whose time is the scarce resource this tree is organised
    around.

    Nothing statically checked that boundary. `check-handler-calls.py` proves a
    called name EXISTS; `box2dxt/tools/check-lcb-signatures.py` proves the .lcb
    agrees with the C. Between them sat the one direction that actually failed:
    script -> .lcb, argument by argument.

WHAT IS DECIDABLE HERE, AND WHAT IS NOT
    Full type inference over LiveCodeScript is not on the table - it is an
    untyped language whose values coerce freely. Three things ARE decidable,
    and each one is a real runtime error rather than a style opinion:

    1. ARITY. Too few arguments is not "the rest default to empty" when the
       parameter is typed: empty does not convert to Integer. Too many is an
       error outright.

    2. AN EMPTIED HANDLE. A handler that does `put empty into sHost` is a
       handler that runs on a teardown path, and a call to a numeric-typed
       parameter in that same handler, with no guard before it, WILL be handed
       empty the second time that path runs. This is check 2, and it is how
       enet-lan-chat's `enHostDestroy sHost` was found - unguarded, one line
       above `put empty into sHost`, in a file that guards the same variable in
       ten other places.

    3. AN ABSENT EVENT KEY. Poll events are Arrays built by each module's
       `_parseRecord`, whose values are String or Data - never Integer - and
       whose keys come from that module's `_fieldKey`. A key `_fieldKey` cannot
       return reads as EMPTY, so passing it to a numeric parameter is a certain
       type conversion error. The valid key set is read from the .lcb, so this
       check cannot go stale against a renamed field.

THREE PARSING LESSONS ARE BUILT IN, EACH PAID FOR BY THIS FILE'S OWN DRAFTS
    - JOIN CONTINUATIONS FIRST. A trailing `\\` continues the statement. The
      first run reported 33 arity errors and every single one was a correct
      call split across two lines.
    - `end if` DOES NOT CLOSE A HANDLER. Treating any `end <word>` as the end
      of a handler truncated every handler body at its first conditional; the
      probe went blind to 2,226 of 5,720 argument positions and missed the very
      defect it was written to find.
    - THE SUBSCRIPT KEY IS GONE. Noise-stripping blanks string literals, so
      `pEvent["peer"]` arrives as `pEvent[]`. Check 3 therefore reads its keys
      from the RAW line, not the stripped one.

USAGE
    python3 tools/check-lcb-call-types.py
    Exit 0 when clean, 1 on any finding.
"""
import glob
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_spec = importlib.util.spec_from_file_location(
    "chc", os.path.join(ROOT, "tools", "check-handler-calls.py"))
_chc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_chc)
strip_noise = _chc.strip_noise

SIG = re.compile(r'^public handler (\w+)\s*\(([^)]*)\)(.*)$', re.M)
FIELDKEY = re.compile(r'private handler _fieldKey\b.*?\nend handler', re.S)
EVENTNAME = re.compile(r'private handler _eventName\b.*?\nend handler', re.S)
RETURNS_STR = re.compile(r'return\s+"([^"]*)"')
HANDLER_START = re.compile(
    r'^(?:private\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)')
BLOCK_END = re.compile(r'^end\s+(if|repeat|switch|try)\b', re.I)
END_ANY = re.compile(r'^end\s+(\w+)')

# Parameter types for which EMPTY is not a value. String and Data accept it.
NUMERIC = ("Integer", "Real", "Number", "Boolean")


def closes_handler(stripped, open_name):
    """`end if` is a BLOCK end, not a handler end - see the header."""
    if BLOCK_END.match(stripped):
        return False
    m = END_ANY.match(stripped)
    if not m:
        return False
    return open_name is None or m.group(1) == open_name


def parse_params(text):
    text = text.strip()
    if not text:
        return []
    out = []
    for part in text.split(","):
        part = part.strip()
        m = re.match(r'^(?:in|out|inout)?\s*(\w+)\s+as\s+(.+)$', part)
        out.append((m.group(1), m.group(2).strip()) if m else (part, "?"))
    return out


def load_lcb():
    """Public handler signatures, the event-field keys, and the event NAMES."""
    sigs, fieldkeys, events = {}, set(), []
    for lcb in sorted(glob.glob(os.path.join(ROOT, "*", "src", "*.lcb"))):
        text = open(lcb, encoding="utf-8").read()
        rel = os.path.relpath(lcb, ROOT)
        pub = set()
        for m in SIG.finditer(text):
            sigs[m.group(1)] = (rel, parse_params(m.group(2)))
            pub.add(m.group(1))
        fk = FIELDKEY.search(text)
        if fk:
            fieldkeys |= {k for k in RETURNS_STR.findall(fk.group(0)) if k}
        en = EVENTNAME.search(text)
        if en:
            for name in RETURNS_STR.findall(en.group(0)):
                if name:
                    events.append((rel, name, name in pub))
    return sigs, fieldkeys, events


def check_event_names(events, sigs):
    """CHECK 4: an event name may not equal a public handler name.

    xTalk has ONE message namespace, so a dispatched event name is resolved
    exactly like a call. If the module that emits the event also EXPORTS a
    handler of that name, the library wins and the app's `on <name>` is never
    reached - silently, because an unhandled dispatch is not an error.

    That is not hypothetical. `_eventName` returned "dcLocalDescription", which
    is also `dcLocalDescription(in pPeer as Integer)`, so the poll pump handed
    the getter an event Array and the engine answered "cannot convert value".
    datachannel-loopback had shipped `on dcLocalDescription` since the day it
    was written and it had never fired once; the getting-started guide taught
    the same unreachable shape.
    """
    out = []
    for rel, name, clashes in events:
        if clashes:
            lcb_rel, params = sigs[name]
            shape = ", ".join(f"{n} as {t}" for n, t in params) or ""
            out.append((rel, 0, "_eventName", name,
                        f"EVENT NAME COLLISION: the dispatched event {name!r} is also "
                        f"a public handler {name}({shape}) in {lcb_rel} - one message "
                        "namespace, so the library wins and no app handler is ever "
                        "reached", f'return "{name}"'))
    return out


def join_continuations(text):
    """[(first_physical_line, joined_text)] - see the header."""
    out, buf, start = [], "", 0
    for i, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = i
        s = line.rstrip()
        if s.endswith("\\"):
            buf += s[:-1] + " "
            continue
        out.append((start, buf + s))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def split_args(s):
    """Top-level commas only: not inside (), [] or a string."""
    parts, depth, buf, quoted = [], 0, [], False
    for ch in s:
        if quoted:
            buf.append(ch)
            if ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
            buf.append(ch)
            continue
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if "".join(buf).strip():
        parts.append("".join(buf))
    return [p.strip() for p in parts if p.strip()]


def match_paren(s, start):
    depth, i, quoted = 0, start, False
    while i < len(s):
        ch = s[i]
        if quoted:
            if ch == '"':
                quoted = False
        elif ch == '"':
            quoted = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def call_sites(line, stripped, sigs):
    """[(name, [arg, ...])] for every LCB call on one joined line."""
    found = []
    for m in re.finditer(r'\b([A-Za-z_]\w*)\s*\(', line):
        if m.group(1) not in sigs:
            continue
        end = match_paren(line, m.end() - 1)
        if end > 0:
            found.append((m.group(1), split_args(line[m.end():end])))
    m = re.match(r'^([A-Za-z_]\w*)(?:\s+(.*))?$', stripped)
    if m and m.group(1) in sigs:
        rest = (m.group(2) or "").strip()
        if not rest.startswith("("):
            found.append((m.group(1), split_args(rest)))
    return found


def check_file(rel, sigs, fieldkeys):
    raw = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
    stripped_text = strip_noise(raw)
    lines = join_continuations(stripped_text)
    raw_lines = join_continuations(raw)
    raw_by_start = {ln: t for ln, t in raw_lines}

    # Handler bodies, so "this handler empties it" is a handler-local fact.
    bodies, name, acc = {}, None, []
    for _, line in lines:
        s = line.strip()
        m = HANDLER_START.match(s)
        if m:
            name, acc = m.group(1), []
            continue
        if closes_handler(s, name):
            if name:
                bodies[name] = "\n".join(acc)
            name = None
            continue
        if name is not None:
            acc.append(s)

    out, positions = [], 0
    cur, guarded = None, set()
    for lineno, line in lines:
        s = line.strip()
        m = HANDLER_START.match(s)
        if m:
            cur, guarded = m.group(1), set()
            continue
        if closes_handler(s, cur):
            cur = None
            continue
        # Guards SEEN SO FAR in this handler.
        #
        # THE NUMERIC COMPARISONS ARE NOT OPTIONAL. The first version knew only
        # `is empty` and `is 0`, and reported stStartEnetLoopback as unguarded
        # two lines below `if sEnServer <= 0 or sEnClient <= 0 then ... exit` -
        # a guard that is stricter than the one it was asking for. A checker
        # that cannot read the guard the code actually wrote does not report a
        # bug, it reports its own vocabulary.
        guarded |= set(re.findall(r'\b([spt][A-Za-z_]\w*)\s+is\s+(?:not\s+)?empty', s))
        guarded |= set(re.findall(r'\b([spt][A-Za-z_]\w*)\s+is\s+(?:not\s+)?0\b', s))
        guarded |= set(re.findall(r'\b([spt][A-Za-z_]\w*)\s*(?:<=|>=|<|>|=)\s*[01]\b', s))
        guarded |= set(re.findall(r'\b([spt][A-Za-z_]\w*)\s+is\s+(?:not\s+)?an?\s+'
                                  r'(?:integer|number)\b', s))
        guarded |= set(re.findall(r'\bif\s+([spt][A-Za-z_]\w*)\s', s))

        for cname, args in call_sites(line, s, sigs):
            lcb_rel, params = sigs[cname]
            if len(args) != len(params):
                out.append((rel, lineno, cur, cname,
                            f"ARITY: {len(args)} argument(s) for {len(params)} "
                            f"parameter(s) ({lcb_rel})", s[:100]))
                continue
            for i, arg in enumerate(args):
                pname, ptype = params[i]
                if ptype not in NUMERIC:
                    continue
                positions += 1
                sub = re.fullmatch(r'(p[A-Z]\w*)\[[^\]]*\]', arg)
                if sub:
                    # Read the KEY from the raw line; strip_noise blanked it.
                    keys = re.findall(re.escape(sub.group(1)) + r'\["([^"]*)"\]',
                                      raw_by_start.get(lineno, ""))
                    for k in keys:
                        if k and k not in fieldkeys:
                            out.append((rel, lineno, cur, cname,
                                        f"EVENT KEY: {sub.group(1)}[\"{k}\"] is not an "
                                        f"event field, so it is EMPTY, and {pname} is "
                                        f"{ptype}", s[:100]))
                    continue
                if not re.fullmatch(r'[spt][A-Za-z_]\w*', arg):
                    continue
                if arg in guarded:
                    continue
                body = bodies.get(cur, "")
                if not re.search(r'put\s+empty\s+into\s+' + re.escape(arg) + r'\b', body):
                    continue
                out.append((rel, lineno, cur, cname,
                            f"EMPTIED HANDLE: {cur}() sets {arg} to empty, and {pname} "
                            f"is {ptype} - guard it before the call", s[:100]))
    return out, positions


def main(argv):
    sigs, fieldkeys, events = load_lcb()
    if len(sigs) < 300 or len(fieldkeys) < 5 or len(events) < 5:
        print(f"check-lcb-call-types: read only {len(sigs)} signature(s) and "
              f"{len(fieldkeys)} event key(s) and {len(events)} event name(s) - "
              "the .lcb parse is broken, and a clean report would be a lie")
        return 1
    findings, positions, nfiles = check_event_names(events, sigs), 0, 0
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel.startswith(".git"):
            continue
        nfiles += 1
        f, p = check_file(rel, sigs, fieldkeys)
        findings += f
        positions += p
    for (rel, lineno, handler, cname, why, src) in findings:
        where = f"{handler}()" if handler else "<top level>"
        print(f"{rel}:{lineno}: in {where}, call to {cname}\n"
              f"    {why}\n"
              f"    {src}")
    if findings:
        print(f"check-lcb-call-types: {len(findings)} finding(s)")
        return 1
    print(f"check-lcb-call-types: OK ({nfiles} script file(s), {len(sigs)} public "
          f".lcb handlers, {positions} argument(s) checked into a "
          f"{'/'.join(NUMERIC)} parameter, {len(events)} event name(s) checked "
          "against the handler namespace)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
