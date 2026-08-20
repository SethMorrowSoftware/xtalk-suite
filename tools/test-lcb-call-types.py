#!/usr/bin/env python3
"""test-lcb-call-types.py - fixtures for tools/check-lcb-call-types.py.

Three of that gate's drafts were wrong in ways that made it report CLEAN over
the very defect it was written to find, and each wrong draft is reproduced here
as a MUTATION so the fixtures can be shown to discriminate rather than merely
to pass:

  join       - not joining `\\` continuations reported 33 correct calls as
               arity errors.
  handlerend - treating `end if` as the end of a handler truncated every
               handler at its first conditional, hiding 2,226 of 5,720
               argument positions AND the enet defect.
  guards     - knowing only `is empty`/`is 0` reported code guarded by
               `if sEnClient <= 0 ... exit` as unguarded. A checker that
               cannot read the guard the code wrote reports its vocabulary,
               not a bug.

The root CLAUDE.md's rule is that a gate must be exercised THE WAY THE BUILD
DRIVES IT, so the last check runs the real tree through the real entry point.

USAGE
    python3 tools/test-lcb-call-types.py
    python3 tools/test-lcb-call-types.py --mutate
"""
import importlib.util
import os
import re
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location(
    "clct", os.path.join(ROOT, "tools", "check-lcb-call-types.py"))
clct = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(clct)

SIGS = {
    "dcFreePeer": ("x.lcb", [("pPeer", "Integer")]),
    "dcSendText": ("x.lcb", [("pChannel", "Integer"), ("pText", "String")]),
    "dcSetRemote": ("x.lcb", [("pPeer", "Integer"), ("pSdp", "String"),
                              ("pType", "String")]),
}
KEYS = {"peer", "channel", "payload", "sdp", "state"}

# (label, source, how many findings, a substring the finding must contain)
FIXTURES = [
    ("a correct one-argument call is clean",
     "on foo\n   dcFreePeer sPeer\nend foo\n", 0, ""),

    ("too few arguments is an arity finding",
     "on foo\n   dcSetRemote tPeer, tSdp\nend foo\n", 1, "ARITY"),

    ("too many arguments is an arity finding",
     "on foo\n   dcFreePeer tA, tB\nend foo\n", 1, "ARITY"),

    ("a call SPLIT ACROSS LINES is correct, not an arity error",
     "on foo\n   dcSetRemote tPeer, \\\n         tSdp, tType\nend foo\n", 0, ""),

    ("a handler that empties the handle, unguarded, is a finding",
     "on foo\n   dcFreePeer sPeer\n   put empty into sPeer\nend foo\n",
     1, "EMPTIED HANDLE"),

    ("...and guarding it clears the finding",
     "on foo\n   if sPeer is not empty then\n      dcFreePeer sPeer\n"
     "   end if\n   put empty into sPeer\nend foo\n", 0, ""),

    # The guard is DELIBERATELY not the first term of the `if`. Written as
    # `if sPeer > 0 then`, this fixture passed even with the numeric guard
    # vocabulary removed - the generic "if <var> ..." rule caught it, so the
    # fixture proved nothing about the rule it was named for. A fixture that
    # a different rule also satisfies is not a test of this one.
    ("a NUMERIC guard also clears it",
     "on foo\n   if tReady is \"yes\" and sPeer > 0 then\n"
     "      dcFreePeer sPeer\n   end if\n"
     "   put empty into sPeer\nend foo\n", 0, ""),

    ("the finding survives an `end if` BEFORE the call",
     "on foo\n   if tX is 1 then\n      put 1 into tY\n   end if\n"
     "   dcFreePeer sPeer\n   put empty into sPeer\nend foo\n",
     1, "EMPTIED HANDLE"),

    ("an event key the module does not define is a finding",
     'on foo pEvent\n   dcFreePeer pEvent["nosuchkey"]\nend foo\n',
     1, "EVENT KEY"),

    ("a real event key is clean",
     'on foo pEvent\n   dcFreePeer pEvent["peer"]\nend foo\n', 0, ""),

    ("a STRING parameter is never an empty-conversion finding",
     'on foo pEvent\n   dcSendText 1, pEvent["nosuchkey"]\nend foo\n', 0, ""),

    ("a name that is not an .lcb handler is ignored entirely",
     "on foo\n   someLocalThing tA, tB, tC, tD\nend foo\n", 0, ""),
]


def run_source(src):
    """Drive check_file exactly as main() does, on a temp file."""
    fd, path = tempfile.mkstemp(suffix=".livecodescript", dir=ROOT)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(src)
        rel = os.path.relpath(path, ROOT)
        found, _ = clct.check_file(rel, SIGS, KEYS)
        return found
    finally:
        os.unlink(path)


def run_fixtures():
    bad = []
    for label, src, want_n, want_sub in FIXTURES:
        got = run_source(src)
        if len(got) != want_n:
            bad.append(f"{label}: got {len(got)} finding(s), want {want_n}"
                       + (f" -> {[g[4] for g in got]}" if got else ""))
        elif want_sub and want_sub not in got[0][4]:
            bad.append(f"{label}: finding was {got[0][4]!r}, want {want_sub!r}")
    return bad


# ------------------------------------------------------------------ mutations
def mutate(which):
    """Install a known-wrong draft; returns a restore callable."""
    if which == "join":
        orig = clct.join_continuations
        clct.join_continuations = lambda t: list(
            enumerate(t.splitlines(), 1))
        return lambda: setattr(clct, "join_continuations", orig)
    if which == "handlerend":
        orig = clct.closes_handler
        clct.closes_handler = lambda s, n: bool(clct.END_ANY.match(s))
        return lambda: setattr(clct, "closes_handler", orig)
    if which == "guards":
        orig = clct.re.findall

        def narrow(pat, s, *a, **k):
            # drop the numeric-comparison and is-a-number guard vocabularies
            if "<=|>=" in pat or "integer|number" in pat:
                return []
            return orig(pat, s, *a, **k)
        clct.re.findall = narrow
        return lambda: setattr(clct.re, "findall", orig)
    raise ValueError(which)


MUTATIONS = {
    "join": "a call SPLIT ACROSS LINES is correct, not an arity error",
    "handlerend": "the finding survives an `end if` BEFORE the call",
    "guards": "a NUMERIC guard also clears it",
}


def check_event_name_fixtures():
    """CHECK 4, driven the way load_lcb() feeds it: (file, name, clashes)."""
    bad = []
    got = clct.check_event_names([("x.lcb", "dcFreePeer", True)], SIGS)
    if len(got) != 1 or "EVENT NAME COLLISION" not in got[0][4]:
        bad.append("an event name equal to a public handler is not reported")
    got = clct.check_event_names([("x.lcb", "dcSomethingHappened", False)], SIGS)
    if got:
        bad.append("a non-colliding event name was reported")
    # and the real tree, at the real entry point: the one historical collision
    # must stay fixed, so this fails again if _eventName is ever reverted.
    _sigs, _keys, events = clct.load_lcb()
    if not any(n == "dcLocalDescriptionReady" for _, n, _ in events):
        bad.append("the .lcb no longer emits dcLocalDescriptionReady - the "
                   "collision fix has been reverted or renamed")
    if any(n == "dcLocalDescription" for _, n, _ in events):
        bad.append("the .lcb emits dcLocalDescription as an EVENT again; it is "
                   "a public getter, so no app handler could ever be reached")
    return bad


def check_event_literal_fixtures():
    """CHECK 5, driven the way load_lcb() feeds it."""
    bad = []
    EV = [("x.lcb", "dcLocalDescriptionReady", False),
          ("x.lcb", "dcLocalCandidate", False)]

    def run(src):
        fd, path = tempfile.mkstemp(suffix=".livecodescript", dir=ROOT)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(src)
            saved = clct.glob.glob
            # only look at the temp file
            clct.glob.glob = lambda pat, **k: [path] if "livecodescript" in pat else saved(pat, **k)
            try:
                return clct.check_event_literals(EV)
            finally:
                clct.glob.glob = saved
        finally:
            os.unlink(path)

    got = run('on foo pEvent\n   put pEvent["name"] into tN\n'
              '   if tN is "dcLocalDescription" then\n      put 1 into tX\n   end if\nend foo\n')
    if len(got) != 1 or "EVENT LITERAL" not in got[0][4]:
        bad.append("a retired event literal is not reported")

    got = run('on foo pEvent\n   put pEvent["name"] into tN\n'
              '   if tN is among the items of "dcLocalDescription,dcLocalDescriptionReady" then\n'
              '      put 1 into tX\n   end if\nend foo\n')
    if got:
        bad.append("the old,new transition pairing was reported")

    got = run('on foo pEvent\n   put pEvent["name"] into tN\n'
              '   if tN is "dcLocalCandidate" then\n      put 1 into tX\n   end if\nend foo\n')
    if got:
        bad.append("a currently-emitted event literal was reported")

    got = run('on foo\n   send "dcChannelPollOnce" to me in 33 milliseconds\nend foo\n')
    if got:
        bad.append("a TIMER message name was reported as an event literal")

    got = run('on foo pEvent\n   put pEvent["name"] into tN\n'
              '   if tN is "dcLocalDescription" then\n'
              '      put "dcLocalDescriptionReady" into tN\n   end if\nend foo\n')
    if got:
        bad.append("a mapping shim (assigns the current name) was reported")
    return bad


def main(argv):
    failures = 0
    for msg in check_event_literal_fixtures():
        print(f"FAIL event-literal: {msg}")
        failures += 1
    for msg in check_event_name_fixtures():
        print(f"FAIL event-name: {msg}")
        failures += 1
    for msg in run_fixtures():
        print(f"FAIL fixture: {msg}")
        failures += 1

    # the way the build drives it: the real tree, the real entry point
    rc = clct.main([])
    if rc != 0:
        print("FAIL pipeline: the committed tree does not pass its own gate")
        failures += 1

    if "--mutate" in argv:
        for which, label in MUTATIONS.items():
            restore = mutate(which)
            try:
                broken = {m.split(":")[0] for m in run_fixtures()}
            finally:
                restore()
            if label not in broken:
                print(f"FAIL mutation {which!r}: fixture {label!r} still passes "
                      "against the known-wrong draft - it is not testing the fix")
                failures += 1
        print(f"test-lcb-call-types: mutation - all {len(MUTATIONS)} known-wrong "
              "drafts are caught by a named fixture")

    if failures:
        print(f"test-lcb-call-types: {failures} failure(s)")
        return 1
    print(f"test-lcb-call-types: OK ({len(FIXTURES)} fixtures + 4 event-name + 5 event-literal checks + the real tree)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
