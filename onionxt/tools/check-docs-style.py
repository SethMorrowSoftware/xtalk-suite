#!/usr/bin/env python3
"""
check-docs-style.py - the house-style gate for prose (Markdown).

House style (CLAUDE.md, README): no em/en dashes and no smart/curly quotes
anywhere, even in docs. The curly quotes fail OXT compilation if they ever leak
into a script; the dashes are a style rule the whole family follows. The script
gate tools/check-livecodescript.py enforces this for .lcb / .livecodescript; this
tool enforces the same banned-character set for .md, portably (no locale- or
grep-PCRE-dependent Unicode escapes).

Run with no arguments to check every .md under the repo, or pass explicit paths.
Exits non-zero if any banned character is found.
"""

import os
import sys

BANNED_CHARS = {
    "‘": "left single curly quote",
    "’": "right single curly quote",
    "“": "left double curly quote",
    "”": "right double curly quote",
    "–": "en dash (use a hyphen)",
    "—": "em dash (use a hyphen)",
}


def discover(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", "build")]
        for name in filenames:
            if name.endswith(".md"):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def check_file(path, problems):
    with open(path, "r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            for col, ch in enumerate(line, start=1):
                if ch in BANNED_CHARS:
                    problems.append(f"{path}:{lineno}: banned character at "
                                    f"column {col}: {BANNED_CHARS[ch]}")


def main(argv):
    targets = argv[1:] if len(argv) > 1 else discover(".")
    if not targets:
        print("check-docs-style: no .md files found")
        return 0
    problems = []
    for path in targets:
        check_file(path, problems)
    if problems:
        for p in problems:
            print(p)
        print(f"\ncheck-docs-style: {len(problems)} problem(s) in "
              f"{len(targets)} file(s)")
        return 1
    print(f"check-docs-style: OK ({len(targets)} file(s) checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
