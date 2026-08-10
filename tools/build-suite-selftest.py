#!/usr/bin/env python3
"""build-suite-selftest.py - assemble tests/suite-selftest.livecodescript, the
ONE harness a maintainer pastes into an OXT stack to exercise the whole suite.

WHY THIS IS GENERATED AND NOT WRITTEN BY HAND. Every member already ships a deep
self-test, and those are authoritative for their own surface. Copying them into a
suite harness by hand would create a second copy of each that drifts the moment
anyone touches the original - and a drifted test harness is worse than no harness,
because it reports green about code that no longer exists. So the suite harness is
BUILT from the member harnesses, and `--check` (in the gate set) fails if the
committed file is not what the sources currently produce. Same pattern, and the
same reason, as onionxt/tools/build-standalone.py.

TWO MARKERS, AND WHY THE SECOND ONE EXISTS. The core carries
`-- GENERATED MEMBER DECLARATIONS GO HERE --` (above every handler) and
`-- GENERATED MEMBER HARNESSES GO HERE --` (at the bottom), and each member's
fold is split between them. That split is not tidiness. OXT resolves a
script-level name BY LEXICAL POSITION, and LiveCodeScript does not error on an
unresolved one - it evaluates it to the LITERAL TEXT of its own name. The first
version emitted each member's declarations inside that member's own section,
which is exactly where they sit in the member's own file. Correct there,
catastrophic here: the fold puts coinxt's section ~1000 lines BELOW the core's
stRunMemberHarnesses, and that handler reads cx1sPassed to merge the totals, so
the engine read the string "cx1sPassed" and the run died on
`add "cx1sPassed" to sPassed`. 106 declarations were below the first handler;
the counters were just the first to do arithmetic on one. Two files that are
each correct alone can be wrong concatenated, because file A's handlers now sit
above file B's declarations - which is the whole hazard of this tool.

WHAT IT PRODUCES. A single script-only stack script:

    tests/suite-selftest.core.livecodescript   the hand-maintained part: the UI,
                                               the per-member probe, the runner,
                                               and the CROSS-MEMBER sections that
                                               no per-member harness can have
  + each member's own harness, namespaced      the deep per-member coverage

THE NAMESPACING RULE, AND WHY IT IS TOTAL. A .livecodescript compiles as one
unit, so two handlers with the same name is a compile error, and the member
harnesses collide hard: all five define stAssert, stSection, stRun, stBuild,
openStack and mouseUp, and four of them define sTotal/sPassed/sFailed. The
temptation is to keep one copy of the "shared" scaffolding and let everyone call
it. This does NOT do that. EVERY name a member file defines - handler, script
local, constant - is prefixed, including its own copy of stAssert and its own
counters. Two reasons:

  1. The scaffolding is not actually identical. stRepeatByte has three different
     implementations across three members, and they disagree at pCount = 0.
     Sharing one of them would silently change what another member's harness
     tests.
  2. A member's harness then behaves in here EXACTLY as it does on its own. No
     folded section can perturb another's counters, log, or state, so a failure
     in the suite harness means the same thing as a failure in the member one.

The core reads each member's (prefixed) counters and log afterwards and merges
them into the unified report. That is the only coupling.

WHAT IS FOLDED IN, AND WHAT IS DELIBERATELY NOT. Three members are pure,
offline and synchronous, so they fold in whole:
  sodiumxt   sxSelfTest()   21 groups
  onionxt    oxSelfTest()    8 groups, all offline (no Tor daemon needed)
  coinxt     stRun          28 sections
Three are not, and each is handled explicitly rather than fudged:
  torrentxt  synchronous, but TorrentXT allows exactly ONE session per process.
             Folded whole, with its session acquisition rewritten to reuse the
             core's if the core already opened one.
  enetxt     synchronous up to its async loopback, which owns UDP ports and
  datachannelxt  event handlers. The SYNC PREFIX is folded (lifecycle, stale
             handles, tuning, teardown); the async loopback is not, because the
             core already drives a real loopback on both transports for its
             cross-member sections and two state machines in one process would
             race. The per-member harness stays the place for that depth, and
             the generated file says so where the cut is.

Every cut point and rewrite below is ASSERTED against the source. If a member
harness is edited such that a marker moves, this build FAILS rather than quietly
dropping a section - a silently shorter test suite is the failure mode this whole
file exists to prevent.

Usage:
  python3 tools/build-suite-selftest.py            # write the generated file
  python3 tools/build-suite-selftest.py --check    # fail if it is out of date
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CORE = os.path.join(ROOT, "tests", "suite-selftest.core.livecodescript")
OUT = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")

# Handlers a member harness defines that belong to ITS OWN standalone UI. The
# core owns the window here, so these are dropped. Any of them still called from
# folded code gets an empty stub (see STUB_IF_CALLED) rather than a dangling call.
DROP_HANDLERS = {
    "openstack", "closestack", "mouseup",
    "stbuild", "stmakelabel", "stmakebutton", "stmakelist",
    "stshow", "stcopyresults", "stpaint",
}

# Of those, the ones a member's runner still calls mid-run. They become no-op
# commands: the core reads the member's log directly, so a member repainting its
# own (absent) field has nothing to do.
STUB_IF_CALLED = {"stshow", "stpaint"}


class Member:
    def __init__(self, key, path, prefix, entry, title, note,
                 cut_before=None, rewrites=()):
        self.key = key
        self.path = os.path.join(ROOT, path)
        self.prefix = prefix
        self.entry = entry          # handler the core calls, BEFORE prefixing
        self.title = title
        self.note = note
        self.cut_before = cut_before  # truncate the entry handler at this marker
        self.rewrites = rewrites      # (must_find, replace_with) applied to the source


# The suite's members, in the order the unified harness runs them. Order matters
# once: torrentxt must see the core's session, and the core opens it during the
# probe, which runs first either way.
MEMBERS = [
    Member(
        "sodium", "sodiumxt/examples/sodium-tests.livecodescript", "sx1",
        "sxSelfTest", "SodiumXT: the full sx* self-test",
        "21 groups: encoding, hashing, secretbox, AEAD, pwhash, KDF, "
        "secretstream, signing, box, seal, key exchange, padding.",
    ),
    Member(
        "onion", "onionxt/examples/onionxt-tests.livecodescript", "ox1",
        "oxSelfTest", "OnionXT: the full ox* self-test",
        "8 groups, all OFFLINE - no Tor daemon is started or contacted. "
        "The live-Tor paths stay in onionxt's own demo.",
    ),
    Member(
        "coin", "coinxt/tests/coin-selftest.livecodescript", "cx1",
        "stRun", "CoinXT: the full cx* self-test",
        "28 sections across all four phases: hashes, the secp256k1 curve, the "
        "encoders and addresses, BIP-39/32/44, and the fail-closed regressions.",
    ),
    Member(
        "torrent", "torrentxt/tests/torrent-selftest.livecodescript", "bt1",
        "stRun", "TorrentXT: the full bt* self-test",
        "Synchronous throughout. Reuses the suite's single session rather than "
        "opening a second one, which TorrentXT does not allow.",
        rewrites=(
            # TorrentXT permits exactly one session per process and the core
            # already opened one during the probe. Without this the folded
            # harness would take its own "could not start a session" branch and
            # skip everything - green, and testing nothing. The core's handle is
            # written as @CORESESSION@ because a literal `sSession` here would be
            # renamed to the member's own local along with everything else.
            ("""   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tErr
      -- TorrentXT absent, or already released; nothing to free.
   end try
   put 0 into sSession
   -- START INTO A TEMPORARY. This used to be `put btStartSession() into
   -- sSession`, which on a REFUSAL wrote 0 over a still-live handle in the same
   -- statement - destroying the only key to the very session it had just been
   -- refused, and guaranteeing that every later run in this launch would be
   -- refused too. Commit to sSession only on success.
   try
      put btStartSession() into tNewSession
      put true into tStartOk
   catch tErr
      put 0 into tNewSession
   end try
   if tNewSession is not empty and tNewSession > 0 then
      put tNewSession into sSession
   end if""",
             """   -- GENERATED (tools/build-suite-selftest.py): TorrentXT allows exactly ONE
   -- session per process, and the suite core opens one during its probe. Reuse
   -- it rather than fighting for a second - starting one here would fail, this
   -- harness would take its cannot-start branch, and the whole torrent surface
   -- would report as skipped while looking perfectly green.
   --
   -- THE RELEASE IS SWALLOWED BY THIS REWRITE ON PURPOSE. The standalone
   -- harness releases any session IT left behind before asking for one, which
   -- is correct there and actively harmful here: bt1sSession is an ALIAS for
   -- the core's handle, so on a second run in one process the folded copy would
   -- btStopSession the session the cross-member BEP44 sections are still using.
   -- It was folded in once, caught by reading the generated file, and the
   -- rewrite's span was widened to cover it. The core does that job for both.
   if @CORESESSION@ > 0 then
      put @CORESESSION@ into sSession
      put true into tStartOk
   else
      try
         put btStartSession() into sSession
         put true into tStartOk
      catch tErr
         put 0 into sSession
      end try
   end if"""),
        ),
    ),
    Member(
        "enet", "enetxt/tests/enet-selftest.livecodescript", "en1",
        "stRun", "ENetXT: the synchronous half of the en* self-test",
        "Lifecycle, stale-handle no-ops, tuning and abrupt teardown. The async "
        "loopback is NOT folded in - the core drives a real ENet loopback of its "
        "own below, and two state machines in one process would race for the "
        "event handlers. Run enetxt/tests/enet-selftest.livecodescript for that.",
        cut_before='   stSection "loopback: hosts + connect (async)"',
    ),
    Member(
        "dc", "datachannelxt/tests/datachannel-selftest.livecodescript", "dc1",
        "stRun", "DataChannelXT: the synchronous half of the dc* self-test",
        "Lifecycle and the stale-handle surface. The async loopback is NOT "
        "folded in, for the same reason as ENetXT's; the core negotiates a real "
        "peer connection below. Run datachannelxt's own harness for that.",
        cut_before='   stSection "loopback: create + negotiate (async)"',
    ),
]


def strip_comments(text):
    """Comment-free view, for finding DEFINITIONS only. Never used for output."""
    out = []
    for raw in text.split("\n"):
        buf, i, instr = "", 0, False
        while i < len(raw):
            ch = raw[i]
            if ch == '"':
                instr = not instr
                buf += ch
            elif not instr and ch == "-" and raw[i + 1:i + 2] == "-":
                break
            else:
                buf += ch
            i += 1
        out.append(buf)
    return "\n".join(out)


def defined_names(text):
    """Every handler, script local and constant the file defines."""
    bare = strip_comments(text)
    names = set(re.findall(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)',
                           bare, re.M))
    for line in re.findall(r'^\s*(?:local|constant)\s+(.+)$', bare, re.M):
        for part in line.split(","):
            part = part.split("=")[0].strip()
            if re.fullmatch(r'\w+', part):
                names.add(part)
    return names


def rename(text, names, prefix):
    """Prefix every defined name, at its definition and at every call site.

    Word-boundary substitution over the whole text, comments included: a comment
    that names a handler should name the one that is actually there, or the next
    reader is misled about which code they are looking at.
    """
    if not names:
        return text
    pattern = re.compile(r'\b(' + "|".join(sorted(map(re.escape, names),
                                                  key=len, reverse=True)) + r')\b')
    return pattern.sub(lambda m: prefix + m.group(1), text)


def split_handlers(text):
    """[(name_lower, block_text)] in source order, plus the leading preamble."""
    lines = text.split("\n")
    blocks, preamble, i = [], [], 0
    opener = re.compile(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', re.I)
    while i < len(lines):
        m = opener.match(lines[i])
        if not m:
            preamble.append(lines[i])
            i += 1
            continue
        name = m.group(1)
        end = re.compile(r'^end\s+' + re.escape(name) + r'\b', re.I)
        j, depth = i + 1, 0
        while j < len(lines):
            s = lines[j].strip()
            if re.match(r'^(if\b.*\bthen$|repeat\b|try\b|switch\b)', s, re.I):
                depth += 1
            elif re.match(r'^end\s+(if|repeat|try|switch)\b', s, re.I):
                depth -= 1
            elif depth <= 0 and end.match(s):
                break
            j += 1
        if j >= len(lines):
            raise SystemExit(f"build-suite-selftest: unterminated handler {name}")
        blocks.append((name.lower(), name, "\n".join(lines[i:j + 1])))
        i = j + 1
    return preamble, blocks


def fold(member):
    """The namespaced, trimmed body of one member harness."""
    src = open(member.path, encoding="utf-8").read()

    for must_find, replace_with in member.rewrites:
        if must_find not in src:
            raise SystemExit(
                f"build-suite-selftest: {member.key}: a required rewrite no longer "
                f"matches its source. The member harness changed under it; update "
                f"the rewrite in tools/build-suite-selftest.py rather than letting "
                f"the fold silently do the wrong thing.\n"
                f"  wanted to find:\n{must_find}")
        src = src.replace(must_find, replace_with, 1)

    names = defined_names(src)
    src = rename(src, names, member.prefix)
    # @CORESESSION@ is a deliberate placeholder, substituted AFTER the rename so
    # it survives it: the torrent rewrite has to reach the CORE's sSession, and
    # anything spelled `sSession` before this point becomes the member's own.
    src = src.replace("@CORESESSION@", "sSession")
    preamble, blocks = split_handlers(src)

    entry = (member.prefix + member.entry).lower()
    if not any(n == entry for n, _, _ in blocks):
        raise SystemExit(f"build-suite-selftest: {member.key}: no entry handler "
                         f"{member.prefix + member.entry}")

    kept = []
    for name, spelling, block in blocks:
        base = name[len(member.prefix):] if name.startswith(member.prefix.lower()) else name
        if base in DROP_HANDLERS:
            if base in STUB_IF_CALLED:
                kept.append(f"-- GENERATED: {spelling} drove this harness's own window.\n"
                            f"-- The suite owns the UI and reads the member's log directly,\n"
                            f"-- so there is nothing left for it to repaint.\n"
                            f"command {spelling}\nend {spelling}")
            continue
        if name == entry and member.cut_before:
            # Rename the marker with the ORIGINAL name set: `src` is already
            # renamed, so its defined names are the prefixed ones and the raw
            # marker would never match.
            marker = rename(member.cut_before, names, member.prefix)
            if marker not in block:
                raise SystemExit(
                    f"build-suite-selftest: {member.key}: the async cut marker is gone "
                    f"from {member.entry}. The harness was restructured; re-read it and "
                    f"update cut_before, rather than folding in an async section that "
                    f"will race the core.\n  wanted: {member.cut_before}")
            head = block.split(marker)[0].rstrip()
            head += (
                f"\n\n   -- GENERATED CUT (tools/build-suite-selftest.py). Everything below\n"
                f"   -- this point in {os.path.relpath(member.path, ROOT)}\n"
                f"   -- is the ASYNC loopback, and it is deliberately not folded in: it\n"
                f"   -- owns ports and event handlers that the suite's own cross-member\n"
                f"   -- loopback below is already using. Run that member's harness on its\n"
                f"   -- own for the async depth.\n"
                f"   {member.prefix}stNote \"async loopback not run here - see the note in this section\"\n"
                f"end {spelling}")
            kept.append(head)
            continue
        kept.append(block)

    # THE PREAMBLE'S DECLARATIONS COME TOO, and forgetting them is a silent
    # disaster rather than a compile error: LiveCodeScript treats an undeclared
    # name as a literal string of itself, so a folded harness missing its
    # `constant kBip39Mnemonic` would not fail to compile - it would compare a
    # digest against the text "cx1kBip39Mnemonic" and report a tidy FAIL that
    # looks like a real defect. The member's `script "name"` line is dropped (the
    # core supplies the one this file needs) and so is its prose, which stays
    # readable in the source file this section names.
    decls = [ln for ln in preamble
             if re.match(r'^\s*(?:local|constant)\s', ln)]
    if not decls:
        raise SystemExit(f"build-suite-selftest: {member.key}: no local/constant "
                         f"declarations found in the preamble - the parse is wrong, "
                         f"and folding it in would silently break every constant.")
    # The declarations are returned SEPARATELY and hoisted above every handler
    # in the file (see the marker in the core). Leaving them here, in the
    # member's own section, is what they look like they want - each member file
    # declares its locals above its own handlers - but the fold puts one
    # member's section BELOW the core's handlers, and the core reads every
    # member's counters to merge them. OXT resolves a script-level name by
    # lexical position, so that read saw an undeclared name, LiveCodeScript
    # evaluated it to the literal text of its own name, and the run died on
    # `add "cx1sPassed" to sPassed`. Same silent-name failure the preamble check
    # below guards against, arriving by placement instead of by omission.
    decl_block = (f"-- ---- {member.title} ----\n" + "\n".join(decls))
    body = "\n\n".join(kept)
    header = (
        f"-- {'=' * 74}\n"
        f"-- {member.title}\n"
        f"--\n"
        + "\n".join(f"-- {ln}" for ln in wrap(member.note, 74)) + "\n"
        f"--\n"
        f"-- GENERATED from {os.path.relpath(member.path, ROOT)} by\n"
        f"-- tools/build-suite-selftest.py. DO NOT EDIT HERE - edit that file and\n"
        f"-- rebuild, or the next build will overwrite you. Every name below is\n"
        f"-- prefixed `{member.prefix}` so this harness cannot collide with, or be\n"
        f"-- perturbed by, any other member's copy of the same scaffolding.\n"
        f"-- {'=' * 74}\n"
    )
    return decl_block, header + "\n" + body


def wrap(text, width):
    words, line, out = text.split(), "", []
    for w in words:
        if len(line) + len(w) + 1 > width:
            out.append(line)
            line = w
        else:
            line = (line + " " + w).strip()
    if line:
        out.append(line)
    return out


def generate():
    core = open(CORE, encoding="utf-8").read()
    marker = "-- GENERATED MEMBER HARNESSES GO HERE --"
    if marker not in core:
        raise SystemExit(f"build-suite-selftest: {CORE} has no '{marker}' line")
    decl_marker = "-- GENERATED MEMBER DECLARATIONS GO HERE --"
    if decl_marker not in core:
        raise SystemExit(f"build-suite-selftest: {CORE} has no '{decl_marker}' line")

    parts = [fold(m) for m in MEMBERS]
    declarations = "\n\n".join(p[0] for p in parts)
    folded = "\n\n\n".join(p[1] for p in parts)
    banner = (
        "-- " + "=" * 74 + "\n"
        "-- EVERYTHING BELOW THIS LINE IS GENERATED. Do not edit it here.\n"
        "--\n"
        "-- It is each member's OWN self-test, folded in by\n"
        "-- tools/build-suite-selftest.py with every name it defines prefixed, so\n"
        "-- that five harnesses which all define stAssert, stRun and sTotal can\n"
        "-- share one script. Each keeps its own scaffolding and its own counters\n"
        "-- and therefore behaves here exactly as it does standalone; the core\n"
        "-- above reads each one's log and totals afterwards and merges them.\n"
        "--\n"
        "-- To change a check, edit the member harness it comes from and run\n"
        "--     python3 tools/build-suite-selftest.py\n"
        "-- The gate set runs --check, so a stale file fails the build.\n"
        "-- " + "=" * 74 + "\n"
    )
    return (core
            .replace(decl_marker, declarations)
            .replace(marker, banner + "\n" + folded))


def main(argv):
    text = generate()
    if "--check" in argv[1:]:
        if not os.path.exists(OUT):
            print("build-suite-selftest: tests/suite-selftest.livecodescript is missing")
            return 1
        if open(OUT, encoding="utf-8").read() != text:
            print("build-suite-selftest: tests/suite-selftest.livecodescript is STALE.\n"
                  "  A member harness changed and the suite harness was not rebuilt, so\n"
                  "  the file a maintainer would paste into an engine is not the one the\n"
                  "  sources describe. Run:  python3 tools/build-suite-selftest.py")
            return 1
        print("build-suite-selftest: tests/suite-selftest.livecodescript is up to date")
        return 0
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)
    handlers = len(re.findall(r'^(?:private\s+)?(?:command|function|on)\s+\w+',
                              text, re.M))
    print(f"build-suite-selftest: wrote tests/suite-selftest.livecodescript "
          f"({len(text.splitlines())} lines, {handlers} handlers, "
          f"{len(MEMBERS)} member harnesses folded in)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
