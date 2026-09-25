#!/usr/bin/env python3
"""test-demo-selfcheck-drift.py - prove the self-check gates FIRE.

These fixtures exist because one of the checks they now cover was DEAD. The
drift gate's fourth failure mode - "a demo that ships the plumbing and reports
nothing" - was written as `"scBegin" not in text` against the whole file, and
every adopter carries the master block, which DEFINES `command scBegin`. The
substring is present by construction, so the branch was unreachable, and the
gate had shipped and passed for a day while claiming a check it could not make.

The mutations are applied to REAL adopters and restored in a finally block, so
what is tested is the gate as build-all.sh runs it, not a hand-built fixture
that resembles it. That distinction is the one root CLAUDE.md records under
"Component verified, system claimed".

THE SUITE CORE AND THE PASTE (D-23, 2026-09-24). The suite paste's hand-written
half, tests/suite-selftest.core.livecodescript, became a self-check adopter
(prefix "su"), and the gate gained a module-level GENERATED_CARRIERS table that
skips the GENERATED paste, tests/suite-selftest.livecodescript, by exact path.
The second table of cases (CORE_CASES) proves each of those claims can fail:
  (a) suScRun's scArmProbe deleted   - the core is really held to the contract;
  (b) suScRun dropped from openStack - and to the reachability half of it;
  (c) a byte copy of the paste planted in tests/ is an unregistered carrier
      while the real paste is not - the skip is by path, never by content;
  (d) GENERATED_CARRIERS emptied     - the paste itself is flagged, so the
      table is the load-bearing skip (the paste has no "GENERATED - do not
      edit" banner, on purpose: root CLAUDE.md);
and for check-demo-control-lists.py, which reads this gate's ADOPTERS:
  (e) the core's `uiArea "suView"` build line deleted - suView is still
      painted, so the unbuilt-reference check must name it;
  (f) the HARNESS SCAFFOLD pair taken out of its SPANS - derive(core) then
      picks up stTitle from the carried stBuild (which the core never calls)
      and the list check names it; with the pair in place derive(core) does
      not, so the cut is load-bearing.
Each of these must print its OWN sentence, not merely exit non-zero - the
"fired for the wrong reason" trap recorded at the third case in CASES - and
every needle is asserted to exist exactly once before it is mutated. Files are
read and restored as BYTES and compared afterwards, so a restore that
translated a newline cannot pass for one that did not.

USAGE
    python3 tools/test-demo-selfcheck-drift.py
"""

import importlib.util
import io
import os
import re
import sys
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DRIFT = load("check-demo-selfcheck-drift.py")
LISTS = load("check-demo-control-lists.py")

EC = os.path.join(ROOT, "enetxt", "examples", "enet-lan-chat.livecodescript")


def run(mod, argv=None):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            rc = mod.main(argv) if argv is not None else mod.main()
        except TypeError:
            rc = mod.main([])
    return rc, buf.getvalue()


def with_mutation(path, mutate):
    """Apply mutate(text)->text, run both gates, restore. Returns (rc_drift, rc_lists)."""
    original = open(path, encoding="utf-8").read()
    try:
        open(path, "w", encoding="utf-8").write(mutate(original))
        rc_d, _ = run(DRIFT)
        rc_l, _ = run(LISTS, [])
        return rc_d, rc_l
    finally:
        open(path, "w", encoding="utf-8").write(original)


def _strip_asserts(text, handler):
    """Remove every scAssert/scSkip line from ONE handler's body."""
    m = re.search(r"^command\s+%s\b" % handler, text, re.M)
    end = re.search(r"^end\s+%s\b" % handler, text[m.end():], re.M)
    lo, hi = m.end(), m.end() + end.start()
    body = re.sub(r"^\s*sc(?:Assert|Skip)\b.*(?:\\\n.*)*$", "",
                  text[lo:hi], flags=re.M)
    return text[:lo] + body + text[hi:]


CASES = [
    # (label, mutate, expect drift fires, expect lists fires)
    ("the only real scBegin call is deleted",
     lambda t: t.replace('   scBegin "ecLog"\n', "", 1), True, False),
    ("scArmProbe is deleted (the probe never fires, the report never ends)",
     lambda t: t.replace("   scArmProbe\n", "", 1), True, False),
    # ANCHOR THE MUTATION TO THE HANDLER, not to the first match in the file.
    # The unanchored version matched scTickProbe's own scAssert - inside the
    # CARRIED BLOCK, which sits above ecScRun - and deleted everything down to
    # ecScRun's scArmProbe, taking the control-list constant with it. The gate
    # then fired for the wrong reason and the fixture recorded a pass it had not
    # earned. A mutation that does not do what its label says is worse than no
    # mutation, because the label is what the next reader trusts.
    ("every assertion in ecScRun is removed",
     lambda t: _strip_asserts(t, "ecScRun"), True, False),
    ("the run handler is no longer called from openStack",
     lambda t: t.replace("\n   ecScRun\n", "\n", 1), True, False),
    ("one line of the carried block is edited",
     lambda t: t.replace("command scAssert pName, pOk",
                         "command scAssert pName, pOk -- tweak", 1), True, False),
    ("a phantom control name is added to the list",
     lambda t: t.replace('constant kEcScControls = "',
                         'constant kEcScControls = "ecGhost,', 1), False, True),
    ("a real control name is dropped from the list",
     lambda t: t.replace("ecAddr,", "", 1), False, True),
    ("the assertion's count disagrees with the list",
     lambda t: re.sub(r'"all \d+ controls', '"all 999 controls', t, count=1),
     False, True),
]


# ---- the suite core and the generated paste (D-23) --------------------------

CORE = os.path.join("tests", "suite-selftest.core.livecodescript")
PASTE = os.path.join("tests", "suite-selftest.livecodescript")
# sorts last in tests/ and names what it is, so a crashed run that somehow
# left it behind is obvious in `git status`
PLANT = os.path.join("tests", "zz-selfcheck-carrier-copy.livecodescript")
SCAFFOLD_SPAN = ("==== SUITE HARNESS SCAFFOLD v1 BEGIN",
                 "==== SUITE HARNESS SCAFFOLD v1 END")


class Refused(Exception):
    """A precondition failed: the case cannot prove what its label says."""


def _bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        return fh.read()


def _write(rel, data):
    with open(os.path.join(ROOT, rel), "wb") as fh:
        fh.write(data)


@contextlib.contextmanager
def edited(rel, needle, replacement):
    """Replace needle, which must occur EXACTLY ONCE, in a REAL file; the
    original bytes go back in a finally."""
    original = _bytes(rel)
    text = original.decode("utf-8")
    n = text.count(needle)
    if n != 1:
        raise Refused("%s: needle found %d times (want exactly 1): %r"
                      % (rel, n, needle))
    try:
        _write(rel, text.replace(needle, replacement, 1).encode("utf-8"))
        yield
    finally:
        _write(rel, original)


@contextlib.contextmanager
def planted(rel, data):
    """A file that exists only for the case; never overwrites a real one."""
    if os.path.exists(os.path.join(ROOT, rel)):
        raise Refused("%s already exists - refusing to overwrite a file this "
                      "fixture did not plant" % rel)
    try:
        _write(rel, data)
        yield
    finally:
        if os.path.exists(os.path.join(ROOT, rel)):
            os.remove(os.path.join(ROOT, rel))


@contextlib.contextmanager
def patched(mod, name, value):
    """Monkeypatch one module-level table of a gate, restored after."""
    old = getattr(mod, name)
    setattr(mod, name, value)
    try:
        yield
    finally:
        setattr(mod, name, old)


def _paste_is_a_carrier():
    # a copy of the paste (or the unskipped paste) can only be "flagged" if
    # the paste carries the block at all: exactly one, the core's, as built
    n = _bytes(PASTE).decode("utf-8").count(DRIFT.BEGIN)
    if n != 1:
        raise Refused("%s carries %d self-check BEGIN markers (want 1)"
                      % (PASTE, n))


def case_core_no_arm():
    return edited(CORE, "   scArmProbe\nend suScRun\n", "end suScRun\n")


def case_core_not_reached():
    return edited(CORE, "   stRun\n   suScRun\nend openStack\n",
                  "   stRun\nend openStack\n")


def case_planted_copy():
    _paste_is_a_carrier()
    return planted(PLANT, _bytes(PASTE))


def case_no_generated_carriers():
    if list(DRIFT.GENERATED_CARRIERS) != [PASTE]:
        raise Refused("GENERATED_CARRIERS is %r, want exactly the paste"
                      % sorted(DRIFT.GENERATED_CARRIERS))
    _paste_is_a_carrier()
    return patched(DRIFT, "GENERATED_CARRIERS", {})


def case_core_suview_unbuilt():
    return edited(CORE, '   uiArea "suView", "520,142," & (kStWidth - 20) & '
                  '"," & (kStHeight - 18)\n', "")


def _spans_without_scaffold():
    if LISTS.SPANS.count(SCAFFOLD_SPAN) != 1:
        raise Refused("check-demo-control-lists.py SPANS holds the HARNESS "
                      "SCAFFOLD pair %d times (want 1)"
                      % LISTS.SPANS.count(SCAFFOLD_SPAN))
    return [sp for sp in LISTS.SPANS if sp != SCAFFOLD_SPAN]


def case_scaffold_span_uncut():
    return patched(LISTS, "SPANS", _spans_without_scaffold())


# (label, context factory, drift fires, lists fires, sentences the drift gate
#  must print, sentences the list gate must print, sentences the drift gate
#  must NOT print). Sentences are regexes over each gate's output.
CORE_CASES = [
    ("(a) the core's scArmProbe is deleted from suScRun",
     case_core_no_arm, True, False,
     [re.escape(CORE) + r": suScRun calls scArmProbe 0 times \(want 1\)"],
     [], []),
    ("(b) suScRun is no longer called from the core's openStack",
     case_core_not_reached, True, False,
     [re.escape(CORE) + r": suScRun is never reached from openStack or "
      r"preOpenStack"], [], []),
    ("(c) a byte copy of the paste elsewhere in tests/ is an unregistered "
     "carrier; the real paste is still skipped (by path, not content)",
     case_planted_copy, True, False,
     [re.escape(PLANT) + r": carries the self-check block but is not "
      r"registered in ADOPTERS"],
     [], [re.escape(PASTE) + r": carries the self-check block"]),
    ("(d) GENERATED_CARRIERS emptied: the paste itself is flagged "
     "(the skip is load-bearing)",
     case_no_generated_carriers, True, False,
     [re.escape(PASTE) + r": carries the self-check block but is not "
      r"registered in ADOPTERS"], [], []),
    ("(e) the core's uiArea \"suView\" build line is deleted: suView is "
     "referenced and never built",
     case_core_suview_unbuilt, False, True,
     [], [re.escape(CORE) + r": \d+ control\(s\) are referenced and never "
          r"built: [^\n]*\bsuView\b"], []),
    ("(f) the HARNESS SCAFFOLD span is not cut: the core's list omits the "
     "carried stBuild's stTitle",
     case_scaffold_span_uncut, False, True,
     [], [re.escape(CORE) + r": kSuScControls omits \d+ control\(s\) the "
          r"source uses: [^\n]*\bstTitle\b"], []),
]


def check_scaffold_cut():
    """Case (f) again, directly on derive(): the scaffold cut is what keeps
    stTitle off the core's list. Returns the problems found."""
    core = os.path.join(ROOT, CORE)
    try:
        uncut = _spans_without_scaffold()
    except Refused as exc:
        return ["CANNOT PROVE: (f) derive(core): %s" % exc]
    out = []
    if "stTitle" in LISTS.derive(core):
        out.append("SURVIVED: (f) derive(core) names stTitle WITH the "
                   "scaffold span cut - the cut is not working")
    with patched(LISTS, "SPANS", uncut):
        if "stTitle" not in LISTS.derive(core):
            out.append("SURVIVED: (f) derive(core) lacks stTitle even with "
                       "the scaffold span uncut - the case cannot show that "
                       "the cut matters")
    return out


def run_core_cases():
    """The D-23 cases. Returns how many did not prove their label."""
    bad = 0
    for label, factory, want_d, want_l, say_d, say_l, deny_d in CORE_CASES:
        try:
            with factory():
                rc_d, out_d = run(DRIFT)
                rc_l, out_l = run(LISTS, [])
        except Refused as exc:
            bad += 1
            print("  CANNOT PROVE: %s\n      %s" % (label, exc))
            continue
        why = []
        if (rc_d != 0) != want_d:
            why.append("drift gate: expected %s, got exit %d"
                       % ("fire" if want_d else "pass", rc_d))
        if (rc_l != 0) != want_l:
            why.append("list gate:  expected %s, got exit %d"
                       % ("fire" if want_l else "pass", rc_l))
        for pat in say_d:
            if not re.search(pat, out_d):
                why.append("drift gate: missing sentence /%s/" % pat)
        for pat in say_l:
            if not re.search(pat, out_l):
                why.append("list gate:  missing sentence /%s/" % pat)
        for pat in deny_d:
            if re.search(pat, out_d):
                why.append("drift gate: printed a sentence it must not: /%s/"
                           % pat)
        if why:
            bad += 1
            print("  SURVIVED: %s" % label)
            for w in why:
                print("      %s" % w)
            for name, out in (("drift", out_d), ("list", out_l)):
                print("      %s output:\n" % name + "\n".join(
                    "        " + l for l in out.rstrip("\n").split("\n")))
    for p in check_scaffold_cut():
        bad += 1
        print("  " + p)
    return bad


def main():
    before = {rel: _bytes(rel)
              for rel in (os.path.relpath(EC, ROOT), CORE, PASTE)}
    if os.path.exists(os.path.join(ROOT, PLANT)):
        print("test-demo-selfcheck-drift: %s exists before the run - remove it"
              % PLANT)
        return 1
    rc_d, out_d = run(DRIFT)
    rc_l, out_l = run(LISTS, [])
    if rc_d != 0 or rc_l != 0:
        print("test-demo-selfcheck-drift: the tree is not clean to begin with")
        print(out_d + out_l)
        return 1

    bad = 0
    for label, mutate, want_d, want_l in CASES:
        got_d, got_l = with_mutation(EC, mutate)
        ok_d = (got_d != 0) == want_d
        ok_l = (got_l != 0) == want_l
        if not (ok_d and ok_l):
            bad += 1
            print("  SURVIVED: %s" % label)
            if not ok_d:
                print("      drift gate: expected %s, got exit %d"
                      % ("fire" if want_d else "pass", got_d))
            if not ok_l:
                print("      list gate:  expected %s, got exit %d"
                      % ("fire" if want_l else "pass", got_l))
    bad += run_core_cases()
    if bad:
        print("test-demo-selfcheck-drift: %d mutation(s) SURVIVED" % bad)
        return 1

    # And the tree is restored, byte for byte - compared on the bytes rather
    # than inferred from the gates going green again - and the plant is gone.
    for rel, data in before.items():
        if _bytes(rel) != data:
            print("test-demo-selfcheck-drift: %s was NOT restored" % rel)
            return 1
    if os.path.exists(os.path.join(ROOT, PLANT)):
        print("test-demo-selfcheck-drift: %s was left behind" % PLANT)
        return 1
    rc_d, _ = run(DRIFT)
    rc_l, _ = run(LISTS, [])
    if rc_d != 0 or rc_l != 0:
        print("test-demo-selfcheck-drift: the tree was NOT restored")
        return 1
    # CORE_CASES' (f) is proven twice (through the gate, and on derive()
    # directly), but it is one mutation, so it counts once
    print("test-demo-selfcheck-drift: OK (%d mutation(s), every one caught, "
          "tree restored)" % (len(CASES) + len(CORE_CASES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
