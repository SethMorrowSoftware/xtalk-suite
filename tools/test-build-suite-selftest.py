#!/usr/bin/env python3
"""test-build-suite-selftest.py - prove the suite paste generator's REFUSALS
fire, and that its declaration hoist does exactly what it says.

WHY THIS FILE EXISTS
    tools/build-suite-selftest.py grew four refusals and one rewrite of the
    output with D-23, and every one of them is invisible on a good tree: a
    refusal that never fires reads exactly like a refusal that cannot fire,
    and `--check` only proves the committed paste equals what the generator
    produces TODAY, whatever that is. So each is driven here the way the build
    drives the generator - generate(), the function main() writes from, with
    CORE (or one Member's path) pointed at a SCRATCH copy - and made to fail on
    the defect it exists for:

      1. a hand-written `local` below a core handler, outside every carried
         block, is refused and the refusal names the line (the hoist exists
         for carried blocks only; the core keeps its own discipline);
      2. with the hoist switched OFF, the paste the generator writes fails
         tools/check-suite-selftest.py's check 10 when that gate is run on it
         - which proves the hoist is load-bearing, and that the gate would
         catch its loss (fixture before gate: exercised as the build runs it);
      3. a declaration continued onto a second line inside a carried block is
         refused (hoisting the first line would strand the tail);
      4. riptide's session rewrite, whose source text moved under it, is
         refused rather than silently not applied;
      5. a registry member with neither a harness nor a NO_HARNESS reason is
         refused by name;
      6. and on the real core, the positive half: each carried block in the
         output is its MASTER's block with the declarations that sat below
         the core's first handler removed and one HOIST_NOTE line where the
         first of them was, and every hoisted line sits above the paste's
         first handler exactly once.

    It never writes tests/suite-selftest.livecodescript: main() is not called,
    and every generated text goes to a temporary directory.

    python3 tools/test-build-suite-selftest.py
Exit 0 when every refusal fires and the baseline holds; 1 otherwise.
"""

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
GATE = os.path.join(TOOLS, "check-suite-selftest.py")
DRIFT_GATES = ("check-harness-scaffold-drift.py", "check-ui-kit-drift.py",
               "check-demo-selfcheck-drift.py")
HANDLER = re.compile(r'^(?:private\s+)?(?:command|function|on)\s+\w+')
DECL = re.compile(r'^(?:local|constant)\s')


def load(filename):
    """A FRESH copy of a tool, so one case's monkeypatch cannot leak into the
    next."""
    spec = importlib.util.spec_from_file_location(
        "fixture_" + filename.replace("-", "_").replace(".py", ""),
        os.path.join(TOOLS, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def refused(gen):
    """Run generate(); return the refusal's text, or None if it wrote a paste."""
    try:
        gen.generate()
    except SystemExit as exc:
        return str(exc.code)
    return None


def swap(text, needle, replacement, label):
    n = text.count(needle)
    if n != 1:
        raise SystemExit(f"test-build-suite-selftest: FIXTURE STALE - {label}: "
                         f"needle found {n} time(s), want exactly 1:\n{needle}")
    return text.replace(needle, replacement, 1)


def first_handler(view_lines):
    return next(i for i, ln in enumerate(view_lines) if HANDLER.match(ln))


def main():
    results = []

    def verdict(ok, label, detail=""):
        results.append(ok)
        print(f"  {'ok  ' if ok else 'FAIL'} {label}")
        if not ok and detail:
            print("       " + str(detail).replace("\n", "\n       "))

    gen0 = load("build-suite-selftest.py")
    real_core = open(gen0.CORE, encoding="utf-8").read()

    with tempfile.TemporaryDirectory(prefix="build-suite-selftest-fixture-") as tmp:
        scratch_core = os.path.join(tmp, "suite-selftest.core.livecodescript")

        def with_core(text):
            gen = load("build-suite-selftest.py")
            with open(scratch_core, "w", encoding="utf-8") as fh:
                fh.write(text)
            gen.CORE = scratch_core
            return gen

        # ---- 1. a hand-written late declaration outside every carried block
        anchor = "end openStack\n"
        late = swap(real_core, anchor, anchor + "local sLate\n", "openStack's end")
        want_line = late.split("\n").index("local sLate") + 1
        msg = refused(with_core(late))
        verdict(msg is not None and "local sLate" in msg
                and f"core line {want_line} " in msg,
                "1. `local sLate` below a core handler, outside any carried "
                "block, is refused and named by its line", msg)

        # ---- 2. the hoist switched off: the paste fails check 10 -----------
        gen = load("build-suite-selftest.py")
        gen.hoist_core_declarations = lambda core: (core, [])
        text = gen.generate()
        unhoisted = os.path.join(tmp, "unhoisted-paste.livecodescript")
        with open(unhoisted, "w", encoding="utf-8") as fh:
            fh.write(text)
        proc = subprocess.run([sys.executable, GATE, unhoisted],
                              capture_output=True, text=True, cwd=ROOT)
        out = proc.stdout + proc.stderr
        verdict(proc.returncode == 1 and "[check 10] " in out and "kUiBg" in out,
                "2. with hoist_core_declarations as the identity, the generated "
                "paste FAILS check-suite-selftest check 10", out)

        # ---- 3. a continued declaration inside a carried block -------------
        cont = swap(real_core, "local sScPassed, sScFailed, sScSkipped\n",
                    "local sScPassed, sScFailed, \\\n   sScSkipped\n",
                    "the self-check's counters")
        msg = refused(with_core(cont))
        verdict(msg is not None and "continued onto the next line" in msg,
                "3. a backslash-continued declaration inside a carried block is "
                "refused", msg)

        # ---- 4. riptide's rewrite needle drifted ---------------------------
        gen = load("build-suite-selftest.py")
        rip = [m for m in gen.MEMBERS if m.member == "riptide"]
        if len(rip) != 1 or not rip[0].rewrites:
            verdict(False, "4. riptide's Member row carries its session rewrite",
                    "no riptide row with a rewrite: the fixture is stale")
        else:
            source = open(rip[0].path, encoding="utf-8").read()
            needle = rip[0].rewrites[0][0]
            drifted = swap(source, needle,
                           needle.replace("<= 0 then return 0", "< 1 then return 0"),
                           "riptide's rewrite needle")
            if needle in drifted:
                verdict(False, "4. the drift really moves riptide's needle",
                        "the drifted source still contains the needle")
            else:
                scratch_member = os.path.join(tmp, "riptide-selftest.livecodescript")
                with open(scratch_member, "w", encoding="utf-8") as fh:
                    fh.write(drifted)
                rip[0].path = scratch_member
                msg = refused(gen)
                verdict(msg is not None and msg.startswith("build-suite-selftest: riptide:")
                        and "required rewrite no longer matches" in msg,
                        "4. riptide's session rewrite, drifted in its source, is "
                        "refused rather than skipped", msg)

        # ---- 5. NO_HARNESS emptied -----------------------------------------
        gen = load("build-suite-selftest.py")
        gen.NO_HARNESS = {}
        msg = refused(gen)
        verdict(msg is not None and "nocloud" in msg
                and "neither a folded harness nor a NO_HARNESS reason" in msg,
                "5. with NO_HARNESS emptied, the registry member without a "
                "harness (nocloud) is refused by name", msg)

    # ---- 6. baseline: the hoist on the real core ---------------------------
    gen = load("build-suite-selftest.py")
    text = gen.generate()
    out_lines = text.split("\n")
    out_view = gen.strip_comments(text).split("\n")
    out_first = first_handler(out_view)
    core_lines = real_core.split("\n")
    core_view = gen.strip_comments(real_core).split("\n")
    core_first = first_handler(core_view)
    _, hoisted = gen.hoist_core_declarations(real_core)

    drift = [load(name) for name in DRIFT_GATES]
    verdict(tuple(gen.CARRIED_SPANS) == tuple((d.BEGIN, d.END) for d in drift),
            "6. the generator's CARRIED_SPANS are the three drift gates' markers")
    moved_total = 0
    for d in drift:
        master = open(os.path.join(ROOT, d.MASTER), encoding="utf-8").read().split("\n")
        mb = [i for i, ln in enumerate(master) if ln.strip() == d.BEGIN]
        me = [i for i, ln in enumerate(master) if ln.strip() == d.END]
        cb = [i for i, ln in enumerate(core_lines) if ln.strip() == d.BEGIN]
        ob = [i for i, ln in enumerate(out_lines) if ln.strip() == d.BEGIN]
        oe = [i for i, ln in enumerate(out_lines) if ln.strip() == d.END]
        label = os.path.basename(d.MASTER)
        if not (len(mb) == len(me) == len(cb) == len(ob) == len(oe) == 1):
            verdict(False, f"6. {label}: one block in the master, the core and "
                           f"the paste", (mb, me, cb, ob, oe))
            continue
        master_span = master[mb[0]:me[0] + 1]
        if core_lines[cb[0]:cb[0] + len(master_span)] != master_span:
            verdict(False, f"6. {label}: the core carries the master's block "
                           f"verbatim (run its drift gate)")
            continue
        # The master's block, minus the column-0 declarations that sit below
        # the core's first handler, with ONE HOIST_NOTE where the first was.
        expected, moved = [], 0
        for k, line in enumerate(master_span):
            if cb[0] + k > core_first and DECL.match(core_view[cb[0] + k]):
                if moved == 0:
                    expected.append(gen.HOIST_NOTE)
                moved += 1
                continue
            expected.append(line)
        moved_total += moved
        got = out_lines[ob[0]:oe[0] + 1]
        verdict(got == expected,
                f"6. {label}: the paste's block is the master's with its "
                f"{moved} late declaration(s) replaced by one HOIST_NOTE"
                if moved else
                f"6. {label}: the paste's block is the master's, line for line "
                f"(its declarations sit above the core's first handler)",
                f"got {len(got)} lines, expected {len(expected)}")
    verdict(moved_total == len(hoisted) and moved_total > 0,
            "6. every declaration taken out of a block is one the hoist returned "
            f"({moved_total} taken, {len(hoisted)} hoisted)")
    placed = [h for h in hoisted
              if out_lines[:out_first].count(h) == 1 and h not in out_lines[out_first:]]
    verdict(len(placed) == len(hoisted),
            f"6. every hoisted line sits above the paste's first handler "
            f"(line {out_first + 1}) exactly once, and nowhere below it",
            sorted(set(hoisted) - set(placed))[:6])

    if all(results):
        print(f"test-build-suite-selftest: OK ({len(results)} checks: five "
              f"refusals fire, the hoist moves {len(hoisted)} declaration(s) "
              f"out of the carried blocks and nothing else)")
        return 0
    print("test-build-suite-selftest: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
