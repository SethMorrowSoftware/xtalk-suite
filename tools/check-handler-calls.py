#!/usr/bin/env python3
"""check-handler-calls.py - every suite handler CALLED must actually EXIST.

WHY THIS GATE EXISTS
    A release audit found onionxt's flagship round-trip example calling
    `sxHashKey(...)` - a SodiumXT handler that has never existed (the real ones
    are sxHash and sxHashKeyed). It passed every gate we had: the static checker
    validates syntax and OXT footguns, not whether a name resolves. The example
    was therefore dead on arrival at its first line, and only a human running it
    on an engine would ever have found out.

    That failure mode is systemic in this suite: six members call into each
    other by name across a boundary no compiler checks, and the ONLY runtime
    that could catch a typo is a GUI engine we cannot run headless. So this gate
    does the resolution statically: it collects every handler the suite defines
    anywhere, then flags every family-prefixed call that resolves to nothing.

WHAT IT CHECKS
    1. UNKNOWN HANDLER (an error). A call to sx*/bt*/en*/dc*/ox*/oxh*/cx* that
       nothing in the repository defines. This is the sxHashKey class and it is
       always a bug.
    2. ARITY (an error) for the parenthesised call form only - `f(a, b)` - where
       the argument count can be read unambiguously. Command-form calls
       (`btAddMagnet sSession, tURI, tPath`) are deliberately NOT arity-checked:
       line continuations and optional trailing arguments make a naive count
       produce false alarms, and a false alarm in a gate is worse than a missed
       one because it teaches people to ignore the gate.

WHAT IT DELIBERATELY DOES NOT DO
    It does not type-check, and it does not know whether a handler is a command
    or a function. It answers exactly one question - "does this name exist?" -
    and answers it exhaustively.

USAGE
    python3 tools/check-handler-calls.py            # scan the whole suite
    python3 tools/check-handler-calls.py <file>...  # scan specific files
    Exit 0 when clean, 1 when anything unresolved is found.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Handlers that are called on purpose while NOT existing yet, each with the
# reason it is tolerated. An entry here is a standing admission of a gap, not a
# way to quiet the gate: the call site must fail closed (a guarded call with a
# clear error), and the entry gets DELETED the day the handler ships - at which
# point this gate becomes the proof that the composition now resolves.
KNOWN_MISSING = {
    # Empty since 2026-08-11: sxSha3_256 (the one former entry, onionxt's
    # deferred gap #2) shipped in SodiumXT ABI 7, so this gate now PROVES that
    # composition resolves instead of tolerating it. The mechanism stays for
    # the next deliberate gap: an entry here is a standing admission, not a
    # way to quiet the gate.
}

# The family prefixes. Order matters: oxh must be tried before ox so an oxh*
# call is not mis-attributed to OnionXT's core ox* surface. rs is the riptide
# app layer (pure script over the extension surfaces); he is the holde-em app
# layer (same shape, added in the 2026-08-15 fold).
PREFIXES = ("oxh", "sx", "bt", "en", "dc", "ox", "cx", "rs", "he")

# A family-prefixed identifier: prefix + an uppercase letter + more word chars.
# The uppercase letter is what keeps ordinary words (an "enough" in a comment,
# a variable named "extra") out of the candidate set.
CALL_RE = re.compile(r"\b((?:oxh|sx|bt|en|dc|ox|cx|rs|he)[A-Z]\w*)\b")

# Handler definitions we harvest to build the "exists" set.
LCB_PUBLIC_RE = re.compile(r"^\s*public handler\s+(\w+)\s*\(([^)]*)\)", re.M)
LCB_ANY_RE = re.compile(r"^\s*(?:private\s+|public\s+)?(?:foreign\s+)?handler\s+(\w+)\s*\(([^)]*)\)", re.M)
# `private command oxhSendBytes ...` is the dominant style in this codebase, so
# the modifier is NOT optional decoration - omitting it here made the gate
# report 1022 phantom "undefined" handlers on its first run.
LCS_DEF_RE = re.compile(
    r"^\s*(?:private\s+|public\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)([^\n]*)$", re.M)


def strip_noise(text):
    """Remove comments and string literals so neither can create a phantom call.

    A doc comment that mentions sxFoo, or an error message containing a handler
    name, is prose - not a call - and must not be flagged. Block comments
    (/* ... */) are legal LCS and holde-em keeps its whole header changelog in
    one - until the 2026-08-15 fold this function only knew line comments, so
    prose in a block comment leaked into the candidate set.
    """
    out = []
    in_block = False
    for line in text.splitlines():
        if in_block:
            idx = line.find("*/")
            if idx == -1:
                continue
            line = line[idx + 2:]
            in_block = False
        # a block comment may open (and close) mid-line, repeatedly
        while True:
            idx = line.find("/*")
            if idx == -1:
                break
            end = line.find("*/", idx + 2)
            if end == -1:
                line = line[:idx]
                in_block = True
                break
            line = line[:idx] + line[end + 2:]
        # LiveCodeScript / LCB line comments: -- and #, plus // in .lcb.
        for marker in ("--", "//"):
            idx = line.find(marker)
            if idx != -1:
                line = line[:idx]
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        # Drop double-quoted string literals (LCS has no escape syntax, so a
        # naive pairwise removal is exactly right here).
        line = re.sub(r'"[^"]*"', '""', line)
        out.append(line)
    return "\n".join(out)


def collect_definitions():
    """Every handler name the repository defines, with an arity where known.

    Deliberately repo-wide rather than per-member: the poll dispatchers
    (btStartPolling, dcStartPolling, ...) live in each member's example helper
    stack, not in its .lcb, and a call to one of those is perfectly valid.
    """
    defined = {}

    def note(name, arity):
        # First definition wins for arity; a later one only fills in a gap.
        if name not in defined or defined[name] is None:
            defined[name] = arity

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "build", "build-asan", "build-tsan", "__pycache__")
                       and not d.startswith("build-")]
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            if fn.endswith(".lcb"):
                text = open(path, encoding="utf-8", errors="replace").read()
                for m in LCB_ANY_RE.finditer(text):
                    params = [p for p in m.group(2).split(",") if p.strip()]
                    note(m.group(1), len(params))
            elif fn.endswith(".livecodescript"):
                text = strip_noise(open(path, encoding="utf-8", errors="replace").read())
                for m in LCS_DEF_RE.finditer(text):
                    rest = m.group(2).strip()
                    params = [p for p in rest.split(",") if p.strip()] if rest else []
                    note(m.group(1), len(params))
    return defined


def script_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "build", "build-asan", "build-tsan", "__pycache__")
                       and not d.startswith("build-")]
        for fn in sorted(filenames):
            if fn.endswith((".livecodescript", ".lcb")):
                yield os.path.join(dirpath, fn)


def split_args(argstr):
    """Count top-level comma-separated arguments, ignoring nested parens."""
    if not argstr.strip():
        return 0
    depth = 0
    count = 1
    for ch in argstr:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "," and depth == 0:
            count += 1
    return count


def check_file(path, defined, problems):
    raw = open(path, encoding="utf-8", errors="replace").read()
    text = strip_noise(raw)
    # Names this file defines itself are calls-in-waiting, not unknowns.
    lines = text.splitlines()
    for lineno, line in enumerate(lines, 1):
        for m in CALL_RE.finditer(line):
            name = m.group(1)
            # A definition line is not a call.
            before = line[:m.start()].strip().lower()
            if before.endswith(("command", "function", "on", "handler")):
                continue
            if name not in defined:
                if name in KNOWN_MISSING:
                    continue
                rel = os.path.relpath(path, ROOT)
                problems.append(f"{rel}:{lineno}: calls '{name}', which nothing in the suite defines")
                continue
            # Parenthesised form only: arity is unambiguous there.
            rest = line[m.end():]
            if rest.startswith("("):
                depth = 0
                for i, ch in enumerate(rest):
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            args = split_args(rest[1:i])
                            want = defined[name]
                            if want is not None and args != want:
                                rel = os.path.relpath(path, ROOT)
                                problems.append(
                                    f"{rel}:{lineno}: '{name}' called with {args} argument(s), "
                                    f"but it is defined with {want}")
                            break
                    elif ch in "\"'":
                        break


def main(argv):
    targets = [os.path.abspath(a) for a in argv[1:]] or list(script_files())
    defined = collect_definitions()
    problems = []
    for path in targets:
        check_file(path, defined, problems)
    if problems:
        for p in problems:
            print("check-handler-calls: " + p)
        print(f"check-handler-calls: {len(problems)} unresolved call(s)")
        return 1
    print(f"check-handler-calls: OK ({len(targets)} file(s), "
          f"{len(defined)} handler(s) known)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
