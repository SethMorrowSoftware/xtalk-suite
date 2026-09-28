#!/usr/bin/env python3
"""test-demo-boot.py - mutation-proves that check-demo-boot.py FIRES.

The family law (root CLAUDE.md): exercise a gate the way the build runs it,
because a gate that has gone blind reports OK and the discriminating test is
what makes the OK mean anything. Each fixture seeds a REAL defect - each one
drawn from the class that actually shipped on 2026-08-29 - into a COPY of
the shipped demo, runs the boot gate on the copy exactly as build-all runs
it (a subprocess, --check, --file), and requires a non-zero exit. A final
run against the unmodified file must PASS, or the fixtures prove nothing.

The seeded defects, and what each stands in for:
  1. A non-literal `constant` value - the compile-killer that took the
     whole one-unit stack script down (also check 22's territory; this
     gate must catch it too, because it catches it by EXECUTING).
  2. A missing card builder - a rail whose UI never comes to exist.
  3. An unguarded write into a control that is never built - the runtime
     `Chunk`-class error at openStack, the second 2026-08-29 failure shape.
  4. A registered control whose builder line is gone - the world-level
     control check.
  5. The LAN receive state keyed by the raw device NAME again (2026-09-24)
     - the pre-fix keying, under which the engine's array-key case fold
     (root engine note 2.7) merged devices "Phone" and "phone" into one
     replay slot. Not from 2026-08-29's class: this one is here because
     the model's own arrays do not fold, so the boot's LAN drive is the
     only thing that can see it, and a check nobody has watched fail is
     the blind-gate shape this file exists to rule out.
  6. The demo's wire-integer orderings spelled with bare operators again
     (2026-09-25): the LAN replay guard, the feed-state MAX, the feed
     claim's change test and both head-watermark handlers, all at once.
     The engine calls integers one apart EQUAL from about 4.5e14 (root
     docs/OXT-ENGINE-NOTES.md 2.10) and this model compared the IEEE way
     (since 2026-09-25 it refuses such a pair instead), so only the boot's
     seq-order drive, which runs them under the engine's rule, sees them as
     the wrong ANSWERS they are there. One seeded copy, one gate run, and EVERY one of
     the drive's deciding checks must be among the failures: a drive that
     caught one of five would pass a plain "the gate fired".
  7. The draft change detection spelled with bare `is not` again
     (2026-09-26, work plan riptide #12): raLanSyncTick's two tests
     (`sLanDraftLast`, `sLanDraftSeen`) and raDmTypingTick's
     (`sDcTypingSeen`). The engine compares two number-like drafts as
     NUMBERS (root docs/OXT-ENGINE-NOTES.md 2.11), so an edit from 12 to
     0012 was no change and a draft reading nan never equalled itself. The
     model reads plain decimals as numbers too and refuses the pairs the
     engine reads otherwise, so the boot's draft-change drive sees each old
     line as a missed edit or a refusal; as in 6, every deciding check must
     be among the failures.
  7b/7c. The same three sites spelled with an `n` (7b) or an `i` (7c) on
     both sides (2026-09-27 review): the two prefixes the sites' own
     comment rules out ("n" & "an" spells nan, "i" & "nf" and "i" &
     "nfinity" two spellings of infinity), which passed the drive green
     until it held a draft reading "an" and edited "nf" to "nfinity". Each
     wrong fix is seeded and its rows must fail.
  8. The 2026-09-27 review's three bare comparisons put back: the embedded
     library's UTF-8 round trip (`textEncode(...) is pBytes`, which never
     calls a nan equal to itself, so a "nan" draft the tick sends was refused
     by the receiver), raProfileLine's restatement of it, and raHandleRp1's
     inbox match (`pEvent["infoHashV1"] is rsInboxId(sDmTarget)`, two 40-hex
     ids compared as numbers when both read as one). Each drive's deciding
     rows must fail.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-demo-boot.py")
DEMO = os.path.join(MEMBER, "examples", "riptide-social.livecodescript")


def run_gate(path):
    r = subprocess.run([sys.executable, GATE, "--check", "--file", path],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def mutate(src, old, new, label):
    if src.count(old) != 1:
        print("test-demo-boot: fixture %r is stale - its anchor %r is not "
              "unique in the shipped demo (found %d); update the fixture"
              % (label, old[:60], src.count(old)))
        sys.exit(1)
    return src.replace(old, new)


def main():
    with open(DEMO, "r", encoding="utf-8") as fh:
        clean = fh.read()

    fixtures = [
        ("a non-literal constant kills the one-unit compile",
         'constant kNxDefaultRelayOne = "wss://relay.damus.io"',
         'constant kNxDefaultRelayOne = "wss://" & "relay.damus.io"'),
        ("a dropped card builder is a missing card",
         "   raBuildNostrCard\n",
         "\n"),
        ("an unguarded write to an unbuilt control fails the boot",
         "   raBuild\n   raProbe\n",
         '   raBuild\n   put "x" into field "raNoSuchControl"\n   raProbe\n'),
        ("a control that is registered but never built is caught",
         'uiButton "raNxCopyNpub", "Copy", "476,78,592,102"\n',
         "\n"),
        ("LAN state keyed by the raw device name folds case-variants "
         "together",
         "   return tHex\nend raLanDevKey\n",
         "   return pName\nend raLanDevKey\n"),
    ]

    # Fixture 6: (shipped text, the spelling it replaced), and the drive's
    # checks that must each FAIL on the seeded copy.
    ordering = [
        ('   return rsSeqCompare(pValue, pLast) is "above"\n'
         'end raLanIsNewer\n',
         '   return not (pValue <= pLast)\n'
         'end raLanIsNewer\n'),
        ('      if rsSeqCompare(tRec["feedSeq"], tMine) is "above" then\n',
         '      if tRec["feedSeq"] > tMine then\n'),
        ('         if rsSeqCompare(sSeq, sLanFeedLast) is not "equal" then\n',
         '         if sSeq is not sLanFeedLast then\n'),
        ('      if rsSeqCompare(pSeq, tSeen) is "above" then\n',
         '      if pSeq > tSeen then\n'),
        ('   put rsSeqCompare(tSeen, tFloor) into tOrder\n'
         '   if tOrder is "above" then\n'
         '      return tSeen\n'
         '   end if\n'
         '   if tOrder is empty then\n'
         '      return empty\n'
         '   end if\n',
         '   if tSeen > tFloor then\n'
         '      return tSeen\n'
         '   end if\n'),
    ]
    ordering_must_fail = [
        "seq order: a draft one seq newer near 2^53 is APPLIED",
        "seq order: a presence tick one newer is applied",
        "seq order: a media offer one seq newer is applied",
        "seq order: a feed seq one above ours is adopted",
        "seq order: a feed seq one above the last broadcast is SENT",
        "seq order: a head one newer raises the watermark",
        "seq order: the watermark is the HIGHER of seen and floor",
    ]

    # Fixture 7: the same shape as 6, for the draft change detection.
    draft_change = [
        ('      -- compared as TEXT, a letter on both sides (raLanSyncTick says '
         'why)\n'
         '      if ("t" & tText) is not ("t" & sDcTypingSeen) then\n',
         '      if tText is not sDcTypingSeen then\n'),
        ('      if ("t" & tText) is not ("t" & sLanDraftSeen) then\n',
         '      if tText is not sLanDraftSeen then\n'),
        ('      put (("t" & tText) is not ("t" & sLanDraftLast)) into '
         'tDraftChanged\n'
         '      if tDraftChanged and tNow >= sLanDraftNextOk then\n',
         '      if tText is not sLanDraftLast and tNow >= sLanDraftNextOk '
         'then\n'),
    ]
    draft_change_must_fail = [
        "draft change: an edit from 12 to 0012",
        "draft change: an edit from 1 to 1.0",
        "draft change: an edit from 100000 to 1e5",
        "draft change: an edit from 16 to 0x10",
        "draft change: an edit from inf to Infinity",
        "draft change: a draft reading nan is sent ONCE",
        "draft change: a DM compose edit from 12 to 0012",
        "draft change: a DM compose edit from 1 to 1.0",
        "draft change: a DM compose edit from 100000 to 1e5",
        "draft change: a DM compose edit from 16 to 0x10",
        "draft change: a DM compose edit from inf to Infinity",
        "draft change: an unedited DM compose reading nan",
    ]

    # Fixtures 7b and 7c: the three draft sites with a prefix the sites'
    # own comment rules out. (shipped, seeded) pairs built from fixture 7's
    # shipped texts, so the three stay one list.
    def prefixed(letter):
        return [(new_text, new_text.replace('("t" & ', '("%s" & ' % letter))
                for new_text, _old in draft_change]

    prefix_n_must_fail = [
        "draft change: a draft reading an (an n prefix makes it nan) is "
        "sent ONCE",
        "draft change: an unedited DM compose reading an (an n prefix "
        "makes it nan)",
    ]
    prefix_i_must_fail = [
        "draft change: an edit from nf to nfinity",
        "draft change: a DM compose edit from nf to nfinity",
    ]

    # Fixture 8: the review's three bare comparisons put back.
    review_lines = [
        ('   set the caseSensitive to true\n'
         '   return ("b" & textEncode(tDecoded, "UTF-8")) is ("b" & pBytes)\n',
         '   return textEncode(tDecoded, "UTF-8") is pBytes\n'),
        ('   set the caseSensitive to true\n'
         '   if ("b" & textEncode(tName, "UTF-8")) is not ("b" & tBytes) then\n',
         '   if textEncode(tName, "UTF-8") is not tBytes then\n'),
        ('            if ("h" & toLower(pEvent["infoHashV1"])) is ("h" & '
         'rsInboxId(sDmTarget)) then\n',
         '            if pEvent["infoHashV1"] is rsInboxId(sDmTarget) then\n'),
    ]
    review_must_fail = [
        "draft change: a draft reading nan from another device is APPLIED",
        "profile line: a profile name reading nan is SHOWN",
        "profile line: a profile name reading NaN is SHOWN",
        # (the own-swarm row is not here: the old line answers identical
        # text true on every reading, so it passes there by design; the
        # upper-case spelling is two number spellings, refused)
        "inbox match: ...spelled in upper case too",
        "inbox match: a peer in ANOTHER swarm whose id also overflows is "
        "NOT introduced to",
    ]

    failed = 0
    for label, old, new in fixtures:
        mutated = mutate(clean, old, new, label)
        with tempfile.NamedTemporaryFile("w", suffix=".livecodescript",
                                         delete=False,
                                         encoding="utf-8") as fh:
            fh.write(mutated)
            tmp = fh.name
        try:
            rc, out = run_gate(tmp)
            if rc == 0:
                failed += 1
                print("FAIL  %s: the gate did NOT fire\n%s"
                      % (label, out[-400:]))
            else:
                print("PASS  %s" % label)
        finally:
            os.unlink(tmp)

    def seeded_run(label, pairs, must_fail):
        """One seeded copy, one gate run: every check in must_fail must be
        among the FAIL lines (a drive that caught one of five would pass a
        plain "the gate fired"). Returns 1 if the fixture misbehaved."""
        seeded = clean
        for old, new in pairs:
            seeded = mutate(seeded, old, new, label)
        with tempfile.NamedTemporaryFile("w", suffix=".livecodescript",
                                         delete=False,
                                         encoding="utf-8") as fh:
            fh.write(seeded)
            tmp = fh.name
        try:
            rc, out = run_gate(tmp)
            fail_lines = [ln for ln in out.splitlines() if "FAIL" in ln]
            missed = [want for want in must_fail
                      if not any(want in ln for ln in fail_lines)]
            if rc == 0 or missed:
                print("FAIL  %s: exit %d; checks that did NOT fire: %s\n%s"
                      % (label, rc, missed, out[-400:]))
                return 1
            print("PASS  %s (%d checks fired)" % (label, len(must_fail)))
            return 0
        finally:
            os.unlink(tmp)

    seeded_fixtures = [
        ("the demo's wire-integer orderings spelled with bare operators "
         "again are each caught", ordering, ordering_must_fail),
        ("the demo's draft change detection spelled with bare `is not` "
         "again is caught at every edit", draft_change,
         draft_change_must_fail),
        ("the draft change detection spelled with an n prefix (nan) is "
         "caught", prefixed("n"), prefix_n_must_fail),
        ("the draft change detection spelled with an i prefix (inf) is "
         "caught", prefixed("i"), prefix_i_must_fail),
        ("the review's bare round-trip and inbox compares put back are each "
         "caught", review_lines, review_must_fail),
    ]
    for label, pairs, must_fail in seeded_fixtures:
        failed += seeded_run(label, pairs, must_fail)

    rc, out = run_gate(DEMO)
    if rc != 0:
        failed += 1
        print("FAIL  the UNMODIFIED demo must pass (else the fixtures "
              "prove nothing)\n%s" % out[-400:])
    else:
        print("PASS  the unmodified demo boots green")

    if failed:
        print("test-demo-boot: %d fixture(s) misbehaved" % failed)
        return 1
    print("test-demo-boot: OK (%d seeded defects caught, clean run passes)"
          % (len(fixtures) + len(seeded_fixtures)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
