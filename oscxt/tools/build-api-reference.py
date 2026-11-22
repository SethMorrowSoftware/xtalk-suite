#!/usr/bin/env python3
"""build-api-reference.py - write docs/api-reference.md from the doc blocks.

The reference is GENERATED from the `/** */` blocks of the member's binding
(EXTENSIONS in tools/runner_config.py), the same blocks the IDE dictionary
reads, so the two cannot say different things (the family's rule since
curlxt's hand-kept page went stale the first time a block changed,
2026-11-14; carried from xlsxt's generator). Byte-identical in oscxt, midixt
and artnetxt: what differs between them is read from tools/runner_config.py.

    python3 tools/build-api-reference.py           rewrite the file
    python3 tools/build-api-reference.py --check   exit 1 if it is stale

For each public handler: its signature line, its Summary, one bullet per
parameter line (`pName: ...`, continuation lines joined), its Returns, its
Description and its Example. The headings are the binding's own section
banners, in its order. The count in the first paragraph is counted here,
never typed.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import runner_config as CFG  # noqa: E402

OUT = os.path.join(ROOT, "docs", "api-reference.md")
MODULE, SOURCE = CFG.EXTENSIONS[0]
ELEMENT = re.compile(r"^([A-Za-z]\w*)(?:\s*\([^)]*\))?:\s*(.*)$")
HANDLER = re.compile(r"^public handler\s+(\w+)\s*(\(.*\).*)$")
BANNER = re.compile(r"^-- =+$")


def parse_block(text):
    """({element: text}, [(param, text)]) of one doc block."""
    elements, params = {}, []
    current = None
    for line in text.split("\n"):
        m = ELEMENT.match(line)
        if m and not line.startswith(" ") and (re.match(r"^p[A-Z]", m.group(1))
                                               or m.group(1) in ("Summary", "Returns", "Description", "Example")):
            name, rest = m.group(1), m.group(2)
            if name.startswith("p"):
                params.append([name, rest])
                current = params[-1]
            else:
                elements[name] = rest
                current = [name, None]
            continue
        if current is None:
            continue
        if line.strip() == "":
            if current[0] == "Example" and current[1] is None:
                continue
            current = None
            continue
        if current[1] is None:
            sep = "\n" if current[0] == "Example" else " "
            keep = line.rstrip() if current[0] == "Example" else line.strip()
            elements[current[0]] = (elements[current[0]] + sep + keep).strip("\n ") \
                if current[0] != "Example" else (elements[current[0]] + sep + keep).strip("\n")
        else:
            current[1] = (current[1] + " " + line.strip()).strip()
    return elements, params


def entries(text):
    """Yield ("section", title) and ("handler", name, signature, block)."""
    lines = text.split("\n")
    pending = None
    i = 0
    while i < len(lines):
        line = lines[i]
        if BANNER.match(line) and i + 2 < len(lines) and BANNER.match(lines[i + 2]):
            yield ("section", lines[i + 1][2:].strip())
            i += 3
            continue
        if line.startswith("/**"):
            j = i + 1
            body = []
            while not lines[j].startswith("*/"):
                body.append(lines[j])
                j += 1
            pending = "\n".join(body)
            i = j + 1
            continue
        m = HANDLER.match(line)
        if m and pending is not None:
            yield ("handler", m.group(1), m.group(1) + m.group(2).strip(), parse_block(pending))
            pending = None
        elif line.strip() and not line.lstrip().startswith("--"):
            pending = None
        i += 1


def plain(text):
    """<handlerName> links of the dictionary become code spans on the page."""
    return re.sub(r"<(%s\w+)>" % MODULE, r"`\1`", text)


def render(text):
    body, count, section = [], 0, None
    for e in entries(text):
        if e[0] == "section":
            section = e[1]
            continue
        _, name, sig, (elements, params) = e
        if "Summary" not in elements:
            continue
        if section is not None:
            body += ["## " + section, ""]
            section = None
        count += 1
        body += ["### `%s`" % name, "", "`%s`" % sig, "", plain(elements["Summary"]), ""]
        if params:
            body += ["- %s: %s" % (p, plain(d)) for p, d in params]
            body.append("")
        if elements.get("Returns"):
            body += ["Returns: " + plain(elements["Returns"]), ""]
        if elements.get("Description"):
            body += [plain(elements["Description"]), ""]
        if elements.get("Example"):
            body += ["```livecodescript", elements["Example"], "```", ""]
    head = ["# %s API reference" % CFG.MEMBER, "",
            "The %d public handlers of the `%s` library, from the doc blocks in `%s` (the IDE"
            % (count, MODULE, SOURCE),
            "dictionary reads the same blocks; `tools/build-api-reference.py` writes this file from them,",
            "and its `--check` is a gate). Read [getting-started.md](getting-started.md) first.", ""]
    return "\n".join(head + body)


def main(argv):
    text = render(open(os.path.join(ROOT, SOURCE), encoding="utf-8").read())
    if "--check" in argv:
        have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if have != text:
            print("build-api-reference: docs/api-reference.md is stale - run "
                  "python3 tools/build-api-reference.py")
            return 1
        print("build-api-reference: OK (docs/api-reference.md matches the doc blocks)")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("build-api-reference: wrote docs/api-reference.md")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
