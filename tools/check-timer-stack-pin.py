#!/usr/bin/env python3
"""check-timer-stack-pin.py - a delayed message must know which stack it is on.

WHY THIS EXISTS
    An unqualified control reference - `field "uiStatus"`, `button pBtn` -
    resolves against **the defaultStack**, not against the stack whose script
    is running. Inside `openStack` those are the same thing, which is why every
    demo's startup status line has always worked. A handler that arrives from
    `send ... in` has no such guarantee: with another stack in front, the write
    lands on the wrong stack or resolves to nothing.

    On 2026-08-18 enet-lan-chat's once-a-second dashboard threw
    "Chunk: error in object expression" REPEATEDLY, from `uiStatus`. The same
    fault was present in datachannel-dht-chat and did NOT throw, because that
    demo guards with `if there is a field` - so its status line just stopped
    updating. Silently. That is the worse of the two outcomes and it is the one
    a human is least likely to report, which is the argument for a gate rather
    than a fix.

WHAT IT CHECKS
    A handler armed by `send ... to me in ...` must pin the defaultStack if
    anything REACHABLE from it touches an unqualified control. The pin is
    `set the defaultStack to the short name of this stack` - holde-em's idiom,
    engine-proven there, whose own comment names this hazard.

    "Reachable" is a closure over the handlers defined in the SAME FILE, plus
    the ui* kit master. The first version knew about ONE carried block - the ui
    kit - so it asked "does this armed handler call an unpinned ui* handler?"
    and never asked the same question about anything else, including the OTHER
    carried block. `stPump` in the suite core is armed by
    `send "stPump" to me in 33 milliseconds` and calls `stShow`, which writes
    `field "stResults"` unqualified; the gate read stPump's own body, found no
    control reference, checked the kit list, and passed. A one-callee-list
    check is a check for the bug you already found - the ONE hop the ui-kit
    fix had already closed.

    Widening it to a real closure on 2026-08-20 found 40 unpinned timer chains
    across 15 files: every demo's own xxLog / xxRefresh / xxSetStatus helper,
    reached from its poll or dashboard tick. None of those 40 is a diagnosed
    engine failure. What IS diagnosed is the class: enet-lan-chat's ecDashOnce
    threw "Chunk: error in object expression" REPEATEDLY on 2026-08-18 through
    the kit's uiStatus, and these are the same shape one call deeper. They were
    pinned at the timer entry point, which is where the ambiguity starts and
    the only place one line covers everything downstream.

    A HANDLER THAT PINS IS A WALL. The walk stops there rather than reporting
    what it calls, because everything below a pin already runs with the
    defaultStack set - following through would name hazards that cannot happen.

TWO PARSING TRAPS, BOTH PAID FOR BY THIS FILE'S DRAFTS
    - THE ARMED NAME MUST COME FROM RAW TEXT. Noise-stripping blanks string
      literals, so `send "ecDashOnce" to me in` becomes `send "" to me in` and
      the probe found ZERO armed handlers across the whole tree while printing
      nothing at all. It is the third time in one session that literal-blanking
      made a scanner silently blind; a scanner that needs the CONTENT of a
      literal must read the raw line.
    - A SEND CAN BE COMPUTED. The kit arms its own callback as
      `send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200`, which
      a `send "(\\w+)"` pattern does not match - so the one kit handler that
      genuinely needed the pin was invisible to the first draft.

USAGE
    python3 tools/check-timer-stack-pin.py
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

HSTART = re.compile(r'^(?:private\s+)?(?:command|function|on|getprop|setprop)\s+(\w+)')
BLOCK_END = re.compile(r'^end\s+(if|repeat|switch|try)\b', re.I)
END_ANY = re.compile(r'^end\s+(\w+)')
# both spellings: send "name" to me in ... / send ("name" && ...) to me in ...
ARMED = re.compile(r'send\s+\(?\s*"(\w+)"[^\n]*?\bto\s+me\s+in\b')
CTRL = re.compile(r'\b(field|button|graphic|image|scrollbar|player)\s+'
                  r'("[^"]*"|\w+)(?!\s+of\b)')
PIN = "defaultStack"
KIT = os.path.join(ROOT, "tools", "ui-kit.livecodescript")


def handler_bodies(text):
    bodies, name, acc = {}, None, []
    for line in text.splitlines():
        s = line.strip()
        m = HSTART.match(s)
        if m:
            name, acc = m.group(1), []
            continue
        if name and not BLOCK_END.match(s) and END_ANY.match(s):
            bodies[name] = "\n".join(acc)
            name = None
            continue
        if name is not None:
            acc.append(s)
    return bodies


WORD = re.compile(r"[A-Za-z_]\w*")


def reaches_unpinned(start, bodies, mentions, unpinned):
    """Walk the same-file call graph from `start`, stopping at any handler
    that pins. Returns the path to the first unpinned control-toucher, or None.

    A handler that pins is a WALL, not just a clean node: everything it calls
    runs with the defaultStack already set, so following through it would
    report a hazard that cannot happen."""
    seen, queue = {start}, [(start, [start])]
    while queue:
        name, path = queue.pop(0)
        if name in unpinned:
            return path
        for nxt in sorted(mentions.get(name, ())):
            if nxt in seen or nxt not in bodies:
                continue
            if PIN in bodies[nxt]:
                continue
            seen.add(nxt)
            queue.append((nxt, path + [nxt]))
    return None


def main(argv):
    kit_bodies = handler_bodies(strip_noise(open(KIT, encoding="utf-8").read()))
    kit_unpinned = {n for n, b in kit_bodies.items()
                    if n.startswith("ui") and CTRL.search(b) and PIN not in b}

    findings, nfiles, narmed = [], 0, 0
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel.startswith(".git"):
            continue
        raw = open(path, encoding="utf-8", errors="replace").read()
        armed = set(ARMED.findall(raw))     # RAW: see the header
        if not armed:
            continue
        nfiles += 1
        bodies = handler_bodies(strip_noise(raw))
        # one tokenise per body, intersected with the file's own handler names:
        # a name-by-name regex sweep is quadratic and this file walks a 36k-line
        # generated harness.
        known = set(bodies)
        mentions = {n: (set(WORD.findall(b)) & known) - {n}
                    for n, b in bodies.items()}
        unpinned = {n for n, b in bodies.items()
                    if CTRL.search(b) and PIN not in b}
        for h in sorted(armed):
            body = bodies.get(h)
            if body is None:
                continue
            narmed += 1
            if PIN in body:
                continue
            own = CTRL.search(body)
            if own:
                findings.append((rel, h, f"touches {own.group(0).strip()!r} "
                                 "unqualified"))
                continue
            hit = reaches_unpinned(h, bodies, mentions, unpinned)
            if hit and len(hit) > 1:
                findings.append((rel, h, "reaches " + " -> ".join(hit[1:])
                                 + ", which touches a control unqualified "
                                 "and does not pin"))
                continue
            for k in sorted(kit_unpinned):
                if re.search(r'\b' + k + r'\b', body):
                    findings.append((rel, h, f"calls {k}, which touches a control "
                                     "unqualified and does not pin"))
                    break

    for rel, h, why in findings:
        print(f"{rel}: {h}() is armed by `send ... to me in` and {why}.\n"
              "    Add: set the defaultStack to the short name of this stack")
    if findings:
        print(f"check-timer-stack-pin: {len(findings)} finding(s)")
        return 1
    if narmed == 0:
        print("check-timer-stack-pin: found NO armed handlers - the scan is "
              "broken, and a clean report would be a lie")
        return 1
    print(f"check-timer-stack-pin: OK ({narmed} delayed handler(s) across "
          f"{nfiles} file(s); {len(kit_unpinned)} kit handler(s) touch controls "
          "unqualified and none is reachable from one)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
