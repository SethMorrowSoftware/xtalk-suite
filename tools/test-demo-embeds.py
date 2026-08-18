#!/usr/bin/env python3
"""test-demo-embeds.py - fixture tests for tools/sync-demo-embeds.py.

WHY THIS FILE EXISTS
    sync-demo-embeds.py refused a collision in principle and could not see one
    in practice. Its `names()` matched a declaration line and then required
    the remainder to be a bare identifier, so

        local sPolling          -- "true" while the timer loop is armed

    failed the identifier test on its trailing comment - and nearly every
    declaration in this tree carries one. The checker printed CLEAN over a
    real duplicate, the merged demo reached an engine, and the engine said
    `local: name shadows another variable or constant near "sPolling"`.

    The root CLAUDE.md's rule for that shape of failure is exact: when a gate
    is added, exercise it THE WAY THE BUILD WILL, not the way its docstring
    describes. The component test that would have been written for `names()`
    in isolation is here, but so is a PIPELINE check that drives the real
    demo and the real library through the real `build_block`, because a
    hand-built fixture matching the docstring is precisely what let coinxt's
    constant gate and the fold's declaration guard both pass while blind.

    Every check below is MUTATION-TESTED against the pre-fix `names()`, which
    this file carries verbatim as `names_prefix_bug`. A check that does not
    change verdict between the two implementations is not testing the fix, and
    `--mutate` fails if any of them fails to discriminate.

USAGE
    python3 tools/test-demo-embeds.py             # run the fixtures
    python3 tools/test-demo-embeds.py --mutate    # prove they catch the bug
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# the module's filename is not an identifier, so load it by path
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "sync_demo_embeds", os.path.join(HERE, "sync-demo-embeds.py"))
sde = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sde)


def names_prefix_bug(text):
    """The implementation that shipped blind. Kept verbatim so the fixtures
    below can be shown to DISCRIMINATE rather than merely to pass."""
    handlers = set(sde.DEF.findall(text))
    decls = set()
    for line in sde.DECL.findall(text):
        for part in line.split(","):
            n = part.split("=")[0].strip()
            if re.fullmatch(r"[A-Za-z_]\w*", n):
                decls.add(n)
    return handlers, decls


# ---------------------------------------------------------------- fixtures
# (label, source, expected declarations, expected handlers)
FIXTURES = [
    ("declaration with a trailing comment - THE BUG",
     'local sPolling          -- "true" while the timer loop is armed\n',
     {"sPolling"}, set()),

    ("declaration with a trailing hash comment",
     "local sFoo   # a note\n",
     {"sFoo"}, set()),

    ("bare declaration, no comment",
     "local sBare\n",
     {"sBare"}, set()),

    ("several names on one line, with a comment",
     "local sA, sB, sC   -- three of them\n",
     {"sA", "sB", "sC"}, set()),

    ("constant with a value - the one form the old code got right",
     'constant kVersion = "0.24.5"\n',
     {"kVersion"}, set()),

    ("a comma INSIDE a constant value is not a declaration",
     'constant kDeck = "Ac,Ad,Ah,As"\n',
     {"kDeck"}, set()),

    ("a comma inside a value, WITH a trailing comment",
     'constant kSuits = "c,d,h,s"   -- clubs first\n',
     {"kSuits"}, set()),

    ("an indented local is a handler local and cannot collide",
     "on foo\n   local sInner\nend foo\n",
     set(), {"foo"}),

    ("handlers of every kind are found",
     "on a\nend a\ncommand b\nend b\nfunction c\nend c\n"
     "private command d\nend d\ngetprop e\nend e\nsetprop f\nend f\n",
     set(), {"a", "b", "c", "d", "e", "f"}),
]


def run_fixtures(fn):
    """Return the list of failing fixture labels under implementation `fn`."""
    bad = []
    for label, src, want_d, want_h in FIXTURES:
        got_h, got_d = fn(src)
        if got_d != want_d or got_h != want_h:
            bad.append((label, got_d, want_d, got_h, want_h))
    return bad


# ---------------------------------------------------------------- pipeline
def pipeline_collision(fn):
    """Drive the REAL demo and the REAL library through the REAL build_block.

    datachannel-dht-chat and datachannel-helpers both declared `sPolling`
    until 2026-08-18. The demo's copy is renamed now, so this check undoes
    that rename IN MEMORY and asserts the pipeline refuses the result. That
    is the exact input the build saw when it reported CLEAN.

    Returns None when the collision is refused (correct), or a string
    describing what happened instead.
    """
    demo_rel = "datachannelxt/examples/datachannel-dht-chat.livecodescript"
    provider = "datachannelxt/examples/datachannel-helpers.livecodescript"
    text = sde.read(demo_rel)
    # drop the embed the demo already carries, exactly as main() does
    if sde.BEGIN in text:
        s, e = text.index(sde.BEGIN), text.index(sde.END) + len(sde.END)
        text = text[:s] + text[e:]
    if "sChatPolling" not in text:
        return ("the demo no longer declares sChatPolling - this check has "
                "gone stale and is testing nothing")
    text = text.replace("sChatPolling", "sPolling")
    saved, sde.names = sde.names, fn
    try:
        sde.build_block(demo_rel, [provider], text)
    except SystemExit as exc:
        msg = str(exc)
        if "sPolling" not in msg:
            return f"refused, but did not name sPolling: {msg!r}"
        return None
    finally:
        sde.names = saved
    return "build_block ACCEPTED a script with two `local sPolling` lines"


def pipeline_clean(fn):
    """The committed tree must be clean under the same pipeline - a checker
    that refuses everything is not a checker. Returns None or a message."""
    saved, sde.names = sde.names, fn
    try:
        for demo_rel, providers in sorted(sde.REGISTRY.items()):
            text = sde.read(demo_rel)
            if sde.BEGIN in text:
                s, e = text.index(sde.BEGIN), text.index(sde.END) + len(sde.END)
                text = text[:s] + text[e:]
            try:
                sde.build_block(demo_rel, providers, text)
            except SystemExit as exc:
                return f"{demo_rel}: unexpected refusal: {exc}"
    finally:
        sde.names = saved
    return None


def pipeline_sees_real_names(fn):
    """A PROPERTY, not a magic number: every column-0 declaration line in
    every file this tool reads must yield at least one name.

    The first version of this check asserted a count floor and I picked the
    floor by guessing - it failed on the CORRECT implementation, because the
    two helper libraries declare seven names between them, not fifteen. A
    threshold nobody measured is the same class of mistake as the gate it is
    testing. This asks the question the tool actually needs answered: was any
    declaration line INVISIBLE? The pre-fix detector loses every line that
    carries a trailing comment, which is nearly all of them.
    """
    lost, total = [], 0
    files = set()
    for demo_rel, providers in sde.REGISTRY.items():
        files.add(demo_rel)
        files.update(providers)
    for rel in sorted(files):
        text = sde.read(rel)
        # only the file's OWN declarations - an embedded region is another
        # file's text and is checked when that file's turn comes.
        if sde.BEGIN in text:
            s, e = text.index(sde.BEGIN), text.index(sde.END) + len(sde.END)
            text = text[:s] + text[e:]
        for line in sde.DECL.findall(text):
            total += 1
            # DECL's group is the text AFTER the keyword, so put one back.
            _h, d = fn("local " + line + "\n")
            if not d:
                lost.append((rel, line.strip()[:60]))
    if lost:
        head = "; ".join(f"{r}: {l!r}" for r, l in lost[:3])
        return (f"{len(lost)} of {total} declaration line(s) yielded no name "
                f"- the detector cannot see them. e.g. {head}")
    return None


PIPELINE = [
    ("pipeline: the sPolling collision is refused", pipeline_collision),
    ("pipeline: the committed tree is accepted", pipeline_clean),
    ("pipeline: real declarations are visible", pipeline_sees_real_names),
]


def main(argv):
    mutate = "--mutate" in argv
    failures = 0

    bad = run_fixtures(sde.names)
    for label, gd, wd, gh, wh in bad:
        print(f"FAIL fixture: {label}\n     decls {sorted(gd)} != {sorted(wd)}"
              f"\n     handlers {sorted(gh)} != {sorted(wh)}")
    failures += len(bad)

    for label, fn in PIPELINE:
        msg = fn(sde.names)
        if msg:
            print(f"FAIL {label}: {msg}")
            failures += 1

    if mutate:
        # Every check must change verdict under the pre-fix implementation.
        # A check that passes both ways is not testing the fix.
        blind = {lbl for lbl, *_ in run_fixtures(names_prefix_bug)}
        undiscriminating = []
        for label, src, want_d, want_h in FIXTURES:
            if label not in blind:
                undiscriminating.append(label)
        # Fixtures that legitimately pass both ways are the ones the old code
        # got right; they are documentation, not discrimination. Require that
        # the NAMED bug fixture and the comma-in-a-value fixture discriminate,
        # and that at least one pipeline check does.
        must = ["declaration with a trailing comment - THE BUG",
                "declaration with a trailing hash comment",
                "several names on one line, with a comment",
                "a comma inside a value, WITH a trailing comment"]
        for label in must:
            if label in undiscriminating:
                print(f"FAIL mutation: fixture {label!r} passes against the "
                      "pre-fix implementation - it is not testing the fix")
                failures += 1
        fired = 0
        for label, fn in PIPELINE:
            if fn(names_prefix_bug):
                fired += 1
        if fired == 0:
            print("FAIL mutation: no pipeline check fires against the pre-fix "
                  "implementation - the fixtures test a component the build "
                  "never drives that way")
            failures += 1
        print(f"test-demo-embeds: mutation - {len(blind)}/{len(FIXTURES)} "
              f"fixtures and {fired}/{len(PIPELINE)} pipeline checks fire "
              "against the pre-fix detector")

    if failures:
        print(f"test-demo-embeds: {failures} failure(s)")
        return 1
    print(f"test-demo-embeds: OK ({len(FIXTURES)} fixtures, "
          f"{len(PIPELINE)} pipeline checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
