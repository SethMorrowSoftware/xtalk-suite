#!/usr/bin/env python3
"""build-standalone.py - bundle the OnionXT libraries and an example app into ONE
self-contained, self-building .livecodescript (no `start using` wiring needed).

You can use the pieces two ways:
  - as LIBRARIES (start using onionxt + onion-httpd, app on top) - best for real
    projects; the sources under src/ and examples/ are the single source of truth;
  - as ONE stack script - paste a generated standalone into a single mainstack's
    stack script and it self-builds its UI, no wiring.

This script generates the second from the first, so there is no duplicated code to
keep in sync. It refuses to build if the parts have colliding constant / handler /
script-local names (a merged script would fail on the engine otherwise).

Two standalones are produced:
  1. the file-sharing spike     -> examples/onion-httpd/standalone.livecodescript
     (onionxt + onion-httpd + the minimal Share-a-Folder spike);
  2. the full tabbed demo       -> examples/onionxt-demo-standalone.livecodescript
     (onionxt + onion-httpd + the self-test harness + the tabbed demo, so the demo
     can dial, host a page, share a folder, and run its About-tab self-test with
     nothing else loaded).

Usage:
  python3 tools/build-standalone.py           # write every standalone
  python3 tools/build-standalone.py --check    # verify the committed files are current
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Shared preamble. Each TARGET's own header (below) is appended after this.
BANNER = """\
-- GENERATED - do not edit by hand. Regenerate with tools/build-standalone.py after
-- changing any source it concatenates (the sources of truth listed below). It joins
-- the OnionXT libraries and an example app into one script, so you can paste it
-- straight into a single mainstack's stack script with no "start using" wiring:
-- every ox* / oxh* / demo handler lives in the one script and self-builds the UI on
-- preOpenStack. (For a real project, prefer the libraries; this is paste-and-run.)
"""


# Order matters: constants must be declared before use, and each part only uses its
# own (and earlier parts') names, so the libraries come first, then the app.
_ONIONXT = ("OnionXT library", "src/onionxt.livecodescript")
_HTTPD = ("onion-httpd library", "src/onion-httpd.livecodescript")


class Target:
    """One standalone: an output path, an ordered list of (label, source) parts,
    and a short header describing how to run it."""

    def __init__(self, out, parts, header):
        self.out = out
        self.parts = parts
        self.header = header


TARGETS = [
    Target(
        out="examples/onion-httpd/standalone.livecodescript",
        parts=[_ONIONXT, _HTTPD, ("file-sharing spike", "examples/onion-httpd/spike.livecodescript")],
        header="""\
-- standalone.livecodescript - OnionXT onion-service FILE SHARING, ALL IN ONE stack.
--
-- TO TEST: new mainstack -> Object menu -> Stack Script -> paste this whole file ->
-- Apply. Have a tor daemon with the control port enabled (see the OnionXT README
-- Troubleshooting). Then reopen the stack (so preOpenStack builds the UI), click
-- Start, then Share Folder, and open the printed .onion in Tor Browser.
""",
    ),
    Target(
        out="examples/onionxt-demo-standalone.livecodescript",
        parts=[
            _ONIONXT,
            _HTTPD,
            ("self-test harness", "examples/onionxt-tests.livecodescript"),
            ("tabbed demo app", "examples/onionxt-demo.livecodescript"),
        ],
        header="""\
-- onionxt-demo-standalone.livecodescript - the FULL OnionXT tabbed demo, ALL IN ONE
-- stack script: dial through Tor, host a page or share a folder over an onion (via
-- the bundled onion-httpd layer), the offline address tools, and the About-tab
-- self-test (the bundled onionxt-tests harness). Nothing else needs loading.
--
-- TO TEST: new mainstack -> Object menu -> Stack Script -> paste this whole file ->
-- Apply. Have a tor daemon with the control port enabled (see the OnionXT README
-- Troubleshooting); load sodiumxt too for the seed-derived onion / SAFECOOKIE paths.
-- Reopen the stack (so preOpenStack builds the UI), then Connect on the Status tab,
-- and use the Dial / Service / Address / About tabs. Open a published .onion in Tor
-- Browser (keep the demo running).
""",
    ),
]

HANDLER_RE = re.compile(
    r"\s*(?:private\s+)?(?:on|command|function|getter|setter)\s+([A-Za-z_][A-Za-z0-9_]*)")
CONST_RE = re.compile(r"\s*constant\s+([A-Za-z_][A-Za-z0-9_]*)")
LOCAL_RE = re.compile(r"\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")


def names(text):
    """Declared constant names, handler names, and top-of-script local names."""
    consts, handlers, script_locals = set(), set(), set()
    seen_handler = False
    for line in text.splitlines():
        stripped = line.split("--", 1)[0]
        m = CONST_RE.match(stripped)
        if m:
            consts.add(m.group(1))
        m = HANDLER_RE.match(stripped)
        if m:
            handlers.add(m.group(1))
            seen_handler = True
        m = LOCAL_RE.match(stripped)
        if m and not seen_handler:      # a script-local lives above the first handler
            script_locals.add(m.group(1))
    return consts, handlers, script_locals


def build(target):
    """Concatenate one target's parts into a single script, refusing on any
    constant / handler / script-local name collision (the merged script would fail
    to compile on the engine otherwise)."""
    owner = {"constant": {}, "handler": {}, "script-local": {}}
    collisions = []
    chunks = [target.header + "--\n" + BANNER]
    for label, rel in target.parts:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            text = handle.read()
        consts, handlers, script_locals = names(text)
        for kind, found in (("constant", consts), ("handler", handlers),
                            ("script-local", script_locals)):
            for name in sorted(found):
                if name in owner[kind]:
                    collisions.append(
                        f"{kind} `{name}` in {rel} collides with {owner[kind][name]}")
                else:
                    owner[kind][name] = rel
        bar = "-- " + "=" * 72
        chunks.append(f"\n\n{bar}\n-- ==== {label}  ({rel})\n{bar}\n\n{text.rstrip()}\n")
    if collisions:
        sys.stderr.write(
            f"build-standalone: NAME COLLISIONS in {target.out} (merged script would fail):\n")
        for c in collisions:
            sys.stderr.write("  " + c + "\n")
        sys.exit(2)
    return "\n".join(chunks)


def main(argv):
    check = "--check" in argv[1:]
    stale = False
    for target in TARGETS:
        content = build(target)
        out_path = os.path.join(ROOT, target.out)
        if check:
            try:
                with open(out_path, encoding="utf-8") as handle:
                    current = handle.read()
            except FileNotFoundError:
                current = None
            if current != content:
                print(f"build-standalone: {target.out} is STALE; run tools/build-standalone.py")
                stale = True
            else:
                print(f"build-standalone: {target.out} is up to date")
        else:
            with open(out_path, "w", encoding="utf-8") as handle:
                handle.write(content)
            print(f"build-standalone: wrote {target.out} ({content.count(chr(10)) + 1} lines)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
