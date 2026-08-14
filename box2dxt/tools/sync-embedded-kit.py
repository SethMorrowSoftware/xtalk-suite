#!/usr/bin/env python3
"""Keep the embedded copy of the Kit in each example in sync with the canonical
source, ``src/box2dxt-kit.livecodescript``.

The example stacks (``examples/*.livecodescript``) are deliberately
self-contained — you paste the whole file into a stack script and it runs — so
each one embeds a verbatim copy of the Kit. To stop those copies silently
drifting from the real Kit, the embedded region is delimited by sentinel
comments and this tool owns everything between them. ``src/`` stays the single
source of truth; the embedded copies are generated artifacts.

Usage::

    python3 tools/sync-embedded-kit.py            # rewrite the embedded copies
    python3 tools/sync-embedded-kit.py --check    # verify they are in sync (CI)

``--check`` exits non-zero (and lists the offenders) when an embedded copy no
longer matches the canonical Kit, so CI fails until ``sync-embedded-kit.py`` is
re-run and the result committed.
"""

import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
KIT = ROOT / "src" / "box2dxt-kit.livecodescript"
EXAMPLES = [
    ROOT / "examples" / "box2dxt-demo.livecodescript",
    ROOT / "examples" / "box2dxt-contraption-builder.livecodescript",
    ROOT / "examples" / "box2dxt-spike-gamekit.livecodescript",
    ROOT / "examples" / "box2dxt-platformer.livecodescript",
    ROOT / "examples" / "box2dxt-selftest.livecodescript",
    ROOT / "examples" / "box2dxt-slingshot.livecodescript",
]

BEGIN = "-- >>> BEGIN EMBEDDED KIT >>>"
END = "-- <<< END EMBEDDED KIT <<<"


def _index_of(lines, sentinel, path):
    matches = [i for i, line in enumerate(lines) if line.rstrip() == sentinel]
    if not matches:
        raise SystemExit(
            f"{path}: missing sentinel {sentinel!r} — cannot locate the embedded Kit."
        )
    if len(matches) > 1:
        raise SystemExit(f"{path}: sentinel {sentinel!r} appears more than once.")
    return matches[0]


def render(example_text, kit_lines, path):
    """Return *example_text* with the region between the sentinels replaced by
    the canonical Kit. The sentinels themselves (and everything outside them —
    the example's banner and its GUI code) are preserved exactly."""
    lines = example_text.split("\n")
    begin = _index_of(lines, BEGIN, path)
    end = _index_of(lines, END, path)
    if end <= begin:
        raise SystemExit(f"{path}: END sentinel must come after BEGIN.")
    return "\n".join(lines[: begin + 1] + kit_lines + lines[end:])


def main(argv):
    check = "--check" in argv
    unknown = [a for a in argv if a not in ("--check",)]
    if unknown:
        raise SystemExit(f"unknown argument(s): {' '.join(unknown)}")

    kit_lines = KIT.read_text().split("\n")
    if kit_lines and kit_lines[-1] == "":
        kit_lines = kit_lines[:-1]  # drop the artifact of the file's trailing newline

    drift = []
    for example in EXAMPLES:
        current = example.read_text()
        updated = render(current, kit_lines, example)
        if updated != current:
            drift.append(example)
            if not check:
                example.write_text(updated)

    rel = lambda p: p.relative_to(ROOT)
    if check:
        if drift:
            print("Embedded Kit copy is OUT OF SYNC with src/box2dxt-kit.livecodescript:")
            for d in drift:
                print(f"  - {rel(d)}")
            print("Fix: python3 tools/sync-embedded-kit.py  (then commit the result)")
            return 1
        print("Embedded Kit copies are in sync.")
        return 0

    for d in drift:
        print(f"updated {rel(d)}")
    if not drift:
        print("Embedded Kit copies already in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
