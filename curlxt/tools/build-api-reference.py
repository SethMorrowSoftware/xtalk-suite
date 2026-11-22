#!/usr/bin/env python3
"""build-api-reference.py - write docs/api-reference.md from the doc blocks.

The reference is GENERATED from the `/** */` blocks of src/curl.lcb and
src/curl-helpers.livecodescript, the same blocks the IDE dictionary reads, so
the two cannot say different things. A hand-kept copy went stale the first
time a block changed (2026-11-14, the day this tool replaced it).

    python3 tools/build-api-reference.py           rewrite the file
    python3 tools/build-api-reference.py --check   exit 1 if it is stale

For each public handler: its signature line, its Summary, one bullet per
parameter line (`pName: ...`, continuation lines joined) and its Returns.
The tsNet calls are documented in docs/tsnet-compat.md, where the table of
their signature sources lives; this file points there.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "api-reference.md")
SOURCES = [
    ("The binding: src/curl.lcb", "src/curl.lcb", True),
    ("The helpers: src/curl-helpers.livecodescript",
     "src/curl-helpers.livecodescript", False),
]
ELEMENT = re.compile(r"^([A-Za-z]\w*)(?:\s*\([^)]*\))?:\s*(.*)$")
LCB_HANDLER = re.compile(r"^\s*public handler\s+(\w+)\s*(\(.*\).*)$")
LCS_HANDLER = re.compile(r"^(?:command|function|on)\s+(\w+)\s*(.*)$")


def parse_block(text):
    """Return {element: text} and an ordered list of (param, text)."""
    elements, params = {}, []
    current = None
    for line in text.split("\n"):
        m = ELEMENT.match(line)
        if m and not line.startswith(" "):
            name, rest = m.group(1), m.group(2)
            if re.match(r"^[prx][A-Z]", name):
                params.append([name, rest])
                current = params[-1]
            else:
                elements[name] = rest
                current = [name, None]
            continue
        if current is None:
            continue
        if line.strip() == "":
            current = None
            continue
        if current[1] is None:
            elements[current[0]] = (elements[current[0]] + " " + line.strip()).strip()
        else:
            current[1] = (current[1] + " " + line.strip()).strip()
    return elements, params


def entries(rel, is_lcb):
    text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    lines = text.split("\n")
    pending = None
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("/**"):
            j = i + 1
            body = []
            while not lines[j].startswith("*/"):
                body.append(lines[j])
                j += 1
            pending = "\n".join(body)
            i = j + 1
            continue
        pat = LCB_HANDLER if is_lcb else LCS_HANDLER
        m = pat.match(line)
        if m and pending is not None:
            name, rest = m.group(1), m.group(2).strip()
            sig = (name + rest) if is_lcb else (name + (" " + rest if rest else ""))
            yield name, sig, parse_block(pending)
            pending = None
        elif line.strip() and not line.lstrip().startswith("--"):
            pending = None
        i += 1


def render():
    out = ["# curlxt API reference", "",
           "Every public handler, from the doc blocks in the source (the IDE dictionary reads the same",
           "blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a",
           "gate). Every handler of the binding, and the helpers' requests and WebSocket calls, run on",
           "OXT-Beyond's headless Linux server engine in the native lane (`tests/engine-selftest.lc`;",
           "README, Status), and every WebSocket call ran in OXT-Beyond's IDE on Windows",
           "too (README, Status); the rest, the other IDEs and platforms need an OXT pass.", ""]
    for title, rel, is_lcb in SOURCES:
        out += ["## " + title, ""]
        for name, sig, (elements, params) in entries(rel, is_lcb):
            if "Summary" not in elements:
                continue
            out += ["### `%s`" % name, "", "`%s`" % sig, "", elements["Summary"], ""]
            if params:
                out += ["- %s: %s" % (p, d) for p, d in params]
                out.append("")
            if elements.get("Returns"):
                out += ["Returns: " + elements["Returns"], ""]
    out += ["## The tsNet calls", "", "See [tsnet-compat.md](tsnet-compat.md).", ""]
    return "\n".join(out)


def main(argv):
    text = render()
    if "--check" in argv:
        have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if have != text:
            print("build-api-reference: docs/api-reference.md is stale - run "
                  "python3 tools/build-api-reference.py")
            return 1
        print("build-api-reference: OK (docs/api-reference.md matches the doc blocks)")
        return 0
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("build-api-reference: wrote docs/api-reference.md")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
