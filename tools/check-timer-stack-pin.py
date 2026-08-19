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
    A handler armed by `send ... to me in ...` must pin the defaultStack if it,
    or any ui* kit handler it calls, touches an unqualified control. The pin is
    `set the defaultStack to the short name of this stack` - holde-em's idiom,
    engine-proven there, whose own comment names this hazard.

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
