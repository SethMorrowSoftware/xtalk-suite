#!/usr/bin/env python3
"""build-preflight.py - generate tests/preflight.livecodescript, the ONE-PASTE
engine preflight: "can this machine run the pass at all?", answered in the first
minute of an engine session, in one screenshot.

WHY THIS EXISTS
    docs/OXT-PASS-RUNBOOK.md's PREREQ block is five hand-typed probes a tester
    runs one at a time in the message box, writing each result on a line with a
    blank after it. That is fine when engine time is plentiful; it is the wrong
    shape now that it is sparse (the runbook's own sparse-access plan budgets S1
    at SIXTY MINUTES). And the failure it is supposed to catch is not
    hypothetical: sodiumxt's committed `universal-mac` dylib is at ABI 6 against
    a binding that demands 10 with strict equality, so on a Mac every sodiumxt
    check - and everything downstream of it, which is most of the suite - is
    blocked. Discovered by hand, that costs the first quarter of the session.

WHAT IS GENERATED, AND WHY IT IS GENERATED RATHER THAN WRITTEN
    Six numbers. The expected ABI of each native member is a C macro in that
    member's shim, and the generated stack has to carry them into an engine that
    cannot see this repository. A hand-copied number is a number that goes stale
    silently at the next ABI bump - the exact failure mode this whole suite has
    a gate for everywhere else - so the numbers are EXTRACTED, `--check` is in
    the gate set, and a stale committed artifact fails the build.

    Extraction is also where three real cross-checks become free, and each one
    is a build failure rather than a note:

      1. THE C MACRO AND THE BINDING LITERAL MUST AGREE. Every member declares
         its expected ABI twice - once in C (`#define SXT_ABI_VERSION 10`) and
         once in the `.lcb` that binds to it (`constant kSXTABIVersion is 10`,
         or, in box2dxt's case, a bare `4` inside checkABI()). A shim bump that
         forgot the binding ships a library the binding refuses, which is the
         wrong-ABI hazard manufactured at home. Nothing in the tree compared the
         two before this file.
      2. EVERY ABI GUARD'S THROW MESSAGE MUST CONTAIN "ABI ". The generated
         stack classifies a caught error - ABI skew (a FAIL: the member is
         installed and unusable) versus member absent (a SKIP: legitimate) -
         and it can only do that by reading the thrown text, because five of the
         six guards are PRIVATE handlers that never expose the number they
         compared. Reword a guard message without this check and every skew on
         every engine quietly becomes an unclassified row.
      3. THE MAC HAZARD IS QUOTED FROM ITS SOURCE. The generated stack prints,
         on macOS only, that a SodiumXT skew there is the known recorded state
         rather than a new defect. The number in that sentence is read out of
         sodiumxt/CLAUDE.md's platform table, so it cannot drift from the
         member's own record of it.

    Each extractor ASSERTS ITS INPUT STILL EXISTS and fails loudly if it does
    not - the house rule the box2dxt fold mechanisms follow. A renamed guard or
    a reformatted table must fail this build; it must never leave a stale
    exemption or a silently-skipped check behind.

SHARE THE EXTRACTOR, DO NOT COPY IT
    `abi_constants()` below returns every member's ABI number with its citation
    and is deliberately importable. A binary-freshness gate (in flight as this
    was written) needs exactly the same six numbers to ask its own question -
    "does the committed `src/code/<arch>-<platform>/` library match the header?"
    - and two copies of this extraction would be two things to bump. Import it:

        import importlib.util  # tools/ is not a package
        ... load tools/build-preflight.py, then abi_constants()

Usage:
  python3 tools/build-preflight.py            # write tests/preflight.livecodescript
  python3 tools/build-preflight.py --check    # verify the committed copy is current
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OUT = os.path.join("tests", "preflight.livecodescript")

# The carried harness scaffold (window, counters, assertion plumbing, the Copy
# button). Carried the same way the onionxt standalones carry their libraries:
# read at build time, so `--check` pins this artifact to the master and
# tools/check-harness-scaffold-drift.py does not need to know about a generated
# file. The preflight is a harness in every respect that matters - it counts
# PASS/SKIP/FAIL and hands the tester a result to paste back - so writing a
# second window would fork the look the scaffold exists to keep singular.
SCAFFOLD = os.path.join("tools", "harness-scaffold.livecodescript")
SCAFFOLD_BEGIN = ("-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: "
                  "tools/harness-scaffold.livecodescript; gate: "
                  "tools/check-harness-scaffold-drift.py) ====")
SCAFFOLD_END = "-- ==== SUITE HARNESS SCAFFOLD v1 END ===="


class Member:
    """One native member: where its expected ABI is written, on both sides.

    `script_name` is what the generated table prints; `const` is the name of
    the LiveCodeScript constant the generated stack declares for it.
    """

    def __init__(self, key, script_name, const, c_path, c_macro, lcb_path):
        self.key = key
        self.script_name = script_name
        self.const = const
        self.c_path = c_path
        self.c_macro = c_macro
        self.lcb_path = lcb_path


# Order is the order of the generated table and of the probes.
MEMBERS = [
    Member("sodium", "SodiumXT", "kAbiSodium",
           os.path.join("sodiumxt", "src", "sodium_shim.h"), "SXT_ABI_VERSION",
           os.path.join("sodiumxt", "src", "sodium.lcb")),
    Member("torrent", "TorrentXT", "kAbiTorrent",
           os.path.join("torrentxt", "src", "btx_abi.h"), "BTX_ABI_VERSION",
           os.path.join("torrentxt", "src", "torrent.lcb")),
    Member("enet", "enetxt", "kAbiEnet",
           os.path.join("enetxt", "src", "enx_abi.h"), "ENX_ABI_VERSION",
           os.path.join("enetxt", "src", "enet.lcb")),
    Member("datachannel", "DataChannelXT", "kAbiDc",
           os.path.join("datachannelxt", "src", "dcx_abi.h"), "DCX_ABI_VERSION",
           os.path.join("datachannelxt", "src", "datachannel.lcb")),
    Member("coin", "CoinXT", "kAbiCoin",
           os.path.join("coinxt", "native", "coinxt.c"), "CNX_ABI_VERSION",
           os.path.join("coinxt", "src", "coinxt.lcb")),
    Member("box2d", "Box2Dxt", "kAbiBox2d",
           os.path.join("box2dxt", "src", "box2d_lc.c"), "LC_ABI_VERSION",
           os.path.join("box2dxt", "src", "box2dxt.lcb")),
]

# sodiumxt/CLAUDE.md's platform table row for the stale mac dylib. Quoted, not
# retyped: the member owns that fact.
MAC_ROW_RE = re.compile(
    r"^\|\s*`universal-mac`\s*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|", re.M)

# `put _sxt_abi_version() into tAbi` - the read that every ABI guard starts with.
ABI_READ_RE = re.compile(
    r"^\s*put\s+(_[A-Za-z0-9_]*abi_version)\(\)\s+into\s+([A-Za-z_]\w*)\s*$")
# `throw "..."` - the guard's message, on its own line.
THROW_RE = re.compile(r'^\s*throw\s+"([^"]*)"\s*$')


class BuildError(Exception):
    """A source this generator reads has moved, been reworded, or disagrees
    with its sibling. Always fatal: the alternative is generating a stack that
    tells somebody at an engine a number we did not actually read."""


def read(rel):
    path = os.path.join(ROOT, rel)
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        raise BuildError("%s does not exist - it is an input to "
                         "tools/build-preflight.py" % rel)


def c_abi(member):
    """The ABI number the member's C shim compiles in."""
    text = read(member.c_path)
    found = re.findall(r"^\s*#define\s+%s\s+(\d+)\s*$" % re.escape(member.c_macro),
                       text, re.M)
    if len(found) != 1:
        raise BuildError(
            "%s: expected exactly one `#define %s <n>` line, found %d - the "
            "macro moved or was renamed; fix MEMBERS in "
            "tools/build-preflight.py" % (member.c_path, member.c_macro, len(found)))
    return int(found[0])


def binding_abi(member):
    """The ABI number the member's .lcb binding demands, plus the message its
    guard throws on skew.

    Found structurally rather than by a per-member pattern: locate the line that
    reads the native abi_version into a variable, then the `is not` comparison
    against THAT variable, then the throw beneath it. Structural because it has
    to survive the two shapes the family actually uses - a named constant in
    five members, a bare literal inside box2dxt's checkABI() - and because it
    must refuse ambiguity rather than guess: box2dxt reads abi_version at two
    sites (b2Version() hands the number to script and does NOT guard), and only
    the one with a comparison under it is the guard.
    """
    text = read(member.lcb_path)
    lines = text.split("\n")
    guards = []
    for i, line in enumerate(lines):
        m = ABI_READ_RE.match(line)
        if not m:
            continue
        var = m.group(2)
        cmp_re = re.compile(r"^\s*if\s+%s\s+is not\s+(\S+)\s+then\s*$"
                            % re.escape(var))
        operand = None
        message = None
        for probe in lines[i + 1:i + 8]:
            hit = cmp_re.match(probe)
            if hit:
                operand = hit.group(1)
                continue
            if operand is not None:
                thrown = THROW_RE.match(probe)
                if thrown:
                    message = thrown.group(1)
                    break
        if operand is not None:
            guards.append((operand, message, i + 1))
    if len(guards) != 1:
        raise BuildError(
            "%s: expected exactly one ABI guard (a `put _*abi_version() into X` "
            "followed by `if X is not <expected> then`), found %d - the guard "
            "was renamed or restructured; re-read it before trusting this "
            "generator" % (member.lcb_path, len(guards)))
    operand, message, where = guards[0]

    if operand.isdigit():
        value = int(operand)
    else:
        # a named constant: resolve it in the same file (LCB spells it `is`)
        consts = re.findall(r"^\s*constant\s+%s\s+is\s+(\d+)\s*$"
                            % re.escape(operand), text, re.M)
        if len(consts) != 1:
            raise BuildError(
                "%s:%d: the ABI guard compares against `%s`, which is declared "
                "%d times as a numeric constant in that file - resolve it by "
                "hand before this generator can quote it"
                % (member.lcb_path, where, operand, len(consts)))
        value = int(consts[0])

    if message is None:
        raise BuildError(
            "%s:%d: the ABI guard has no `throw \"...\"` line under its "
            "comparison - tests/preflight.livecodescript classifies a skew by "
            "reading that message, so it cannot be missing"
            % (member.lcb_path, where))
    # The generated stack's pfClassify() buckets a caught error by looking for
    # "abi " in it. The trailing space is load-bearing (it keeps an engine
    # message that merely says "capability" out of the skew bucket), so the
    # check is for the same spelling the stack looks for.
    if "abi " not in message.lower():
        raise BuildError(
            "%s:%d: the ABI guard throws %r, which does not contain \"ABI \" - "
            "tests/preflight.livecodescript's pfClassify() reads that word to "
            "tell an ABI SKEW (a FAIL) from an absent member (a SKIP). Restore "
            "the word, or teach pfClassify the new spelling in the same change."
            % (member.lcb_path, where, message))
    return value, message


def abi_constants():
    """{key: {...}} for every native member - THE shared extractor.

    Each entry carries the number, both sources it was read from, and the
    guard's throw message. Import this rather than re-deriving it: the six
    numbers have exactly two homes each, and a third copy is a third thing to
    bump.
    """
    out = {}
    for member in MEMBERS:
        from_c = c_abi(member)
        from_binding, message = binding_abi(member)
        if from_c != from_binding:
            raise BuildError(
                "ABI SKEW IN THE TREE: %s says %s is %d, but %s's guard demands "
                "%d. One of the two was bumped without the other, which ships a "
                "library the binding refuses on every platform. Fix the lagging "
                "side; do not silence this."
                % (member.c_path, member.c_macro, from_c,
                   member.lcb_path, from_binding))
        out[member.key] = {
            "name": member.script_name,
            "const": member.const,
            "abi": from_c,
            "c_cite": "%s (%s)" % (member.c_path, member.c_macro),
            "lcb_cite": member.lcb_path,
            "guard_message": message,
        }
    return out


def mac_stale_abi():
    """The ABI the committed universal-mac sodiumxt dylib is recorded at."""
    text = read(os.path.join("sodiumxt", "CLAUDE.md"))
    found = MAC_ROW_RE.findall(text)
    if len(found) != 1:
        raise BuildError(
            "sodiumxt/CLAUDE.md: expected exactly one `| `universal-mac` | <n> |` "
            "platform-table row, found %d. The generated preflight tells a "
            "tester on a Mac that a SodiumXT skew there is the KNOWN state and "
            "quotes that number from this table, so the row cannot be guessed. "
            "Restore the row, or update MAC_ROW_RE in tools/build-preflight.py "
            "if the table was deliberately reshaped." % len(found))
    return int(found[0])


def scaffold_block():
    """The carried harness scaffold, markers included."""
    text = read(SCAFFOLD)
    lines = text.split("\n")
    begins = [i for i, l in enumerate(lines) if l.strip() == SCAFFOLD_BEGIN]
    ends = [i for i, l in enumerate(lines) if l.strip() == SCAFFOLD_END]
    if len(begins) != 1 or len(ends) != 1 or ends[0] <= begins[0]:
        raise BuildError(
            "%s: expected exactly one BEGIN and one END marker in that order "
            "(found %d/%d) - the scaffold master's markers are a contract with "
            "tools/check-harness-scaffold-drift.py and with this generator"
            % (SCAFFOLD, len(begins), len(ends)))
    return "\n".join(lines[begins[0]:ends[0] + 1])


# ---------------------------------------------------------------------------
# The stack itself. Everything outside the @PLACEHOLDER@s is fixed text: the
# generated half is the six numbers, their citations, and the two mac-hazard
# figures. Placeholders are substituted, never formatted, so a `%` or a brace in
# the script text stays exactly what it is.
# ---------------------------------------------------------------------------

TEMPLATE = '''\
-- preflight.livecodescript - the xTalk suite's ONE-PASTE ENGINE PREFLIGHT.
--
-- GENERATED - do not edit by hand. Regenerate with tools/build-preflight.py
-- (its --check runs in the gate set), and edit the generator, never this file:
-- the six expected-ABI numbers below are READ from the C shims, so a hand edit
-- here is a number that no longer traces to anything.
--
-- WHY THIS FILE EXISTS. Engine access is sparse (docs/OXT-PASS-RUNBOOK.md's
-- sparse-access plan budgets a whole session at sixty minutes), and the
-- expensive way to lose one is not a red check - it is discovering at minute
-- fifteen that the INSTALL cannot run the thing you sat down to run. The
-- wrong-ABI hazard is live and recorded: a member's binding compares the native
-- library's ABI against its own with STRICT EQUALITY and throws on any skew, so
-- one stale library blocks that whole member and everything built on it. This
-- paste answers "can this machine run the pass at all?" in the first minute, as
-- ONE table you can screenshot into the record.
--
-- TO RUN: new mainstack -> Object menu -> Stack Script -> paste this whole file
-- -> Apply -> close and reopen the stack (openStack builds the window and
-- runs). No daemon, no second machine, no `start using` step, nothing to
-- install first - the point is to run BEFORE all of that is known to work.
--
-- WHAT A GREEN RUN PROVES, EXACTLY. That each listed extension LOADS in this
-- engine and that its own ABI guard accepted the library shipped inside it. For
-- five of the six that is an INFERENCE and this file says so in the table: the
-- guards are PRIVATE handlers that compare native-against-binding and throw,
-- so a call that returned proves equality without ever exposing the number.
-- Box2Dxt is the exception - b2Version() hands the native ABI back to script -
-- so its row is the one real found-vs-expected comparison here.
--
-- WHAT IT DOES NOT DO. It runs no member's test surface (that is the suite
-- paste, tests/suite-selftest.livecodescript, and this is not a substitute for
-- it); it does not probe the tor daemon (a control-port dial is asynchronous,
-- needs the onionxt script layer in the message path, and has side effects -
-- runbook 2.3's torrc and its "Opening Control listener" log line stay that
-- test); and it cannot see this repository, only what is installed in the
-- engine it is running in. A SKIP here means "not installed on THIS machine",
-- never "missing from the suite".
--
-- Honesty label: verified statically; needs an OXT pass. Not one line of this
-- file has run on an engine.

-- ---- expected ABI, read from the C shims -------------------------------------
-- GENERATED. Each number is the macro named beside it, and tools/build-preflight.py
-- proves it equals the literal that member's own .lcb binding compares against
-- before it writes this file - so these six lines and the twelve places they
-- come from cannot disagree without failing the suite build.
@ABICONSTANTS@

constant kStTitle = "xTalk Suite - engine preflight"
constant kStWidth = 720
constant kStHeight = 560

-- ---- state -------------------------------------------------------------------
-- The table is built up as the probes run and printed ONCE, because a table
-- split across six places in a log is not a table and does not screenshot.
local sRows                -- one preformatted row per member
local sDetails             -- version strings, and the raw text of anything thrown
local sSeen                -- the member names already in sRows (one row each)
local sSession             -- the torrent session this run took (0 = none held)
local sEnetUp              -- "true" while an enInitialize is unbalanced
local sDcUp                -- "true" while a dcInit is unbalanced

-- ---- the scaffolding (carried) -----------------------------------------------
-- Carried verbatim from tools/harness-scaffold.livecodescript by the generator,
-- which is why this file is not registered in tools/check-harness-scaffold-drift.py:
-- generated carriers are pinned to the master by their own freshness gate
-- (--check), exactly as the onionxt standalones are. It also carries the Copy
-- results button, which is how this run reaches the OXT-pass record without
-- anybody retyping a table.
@SCAFFOLD@

-- ---- the run -----------------------------------------------------------------

on openStack
   stBuild
   stRun
end openStack

-- Release anything a probe took. Every probe already balances itself inline, so
-- this is the belt-and-braces path the scaffold's Re-run button and closeStack
-- go through - and it matters more here than in a member harness: a preflight
-- that leaked the single libtorrent session would break the very run it exists
-- to de-risk (runbook 5.1.1), and these flags are the only record of what this
-- stack took.
command stCleanup
   local tError, tRc

   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent, or the session was already released: nothing to free.
   end try
   put 0 into sSession

   try
      if sEnetUp is "true" then
         put enDeinitialize() into tRc
      end if
   catch tError
      -- enetxt absent, or already deinitialized.
   end try
   put "false" into sEnetUp

   try
      if sDcUp is "true" then
         -- EXPRESSION position, so the parentheses are REQUIRED. The STATEMENT
         -- spelling of a zero-argument call must be BARE (`dcCleanup`): the
         -- parenthesised statement hands the parser `()`, which is not an
         -- expression, and one such line took a whole 4400-line paste with it
         -- on 2026-08-09. Same characters, opposite verdict.
         put dcCleanup() into tRc
      end if
   catch tError
      -- DataChannelXT absent, or already cleaned up.
   end try
   put "false" into sDcUp
end stCleanup

command stRun
   local tError

   stResetCounters
   put empty into sRows
   put empty into sSeen
   put empty into sDetails
   put 0 into sSession
   put "false" into sEnetUp
   put "false" into sDcUp

   put "xTalk Suite - engine preflight" & return into sResultText
   put "Can this machine run the pass at all? One paste, no setup, no daemon." & return after sResultText
   put "An absent member SKIPS. A member whose ABI does not match FAILS - that" & return after sResultText
   put "member, and everything downstream of it, cannot be tested here today." & return after sResultText

   -- Every section is CONTAINED, for the reason the suite harness records: a
   -- throw must cost EXACTLY ITSELF. A preflight that died on its second member
   -- would be read as a verdict about the machine when it is a defect in here.
   try
      pfEngineSection
   catch tError
      stSectionFailed "engine facts", tError
   end try

   stSection "extensions (guarded: absent SKIPS, wrong ABI FAILS)"
   try
      pfProbeSodium
   catch tError
      stSectionFailed "SodiumXT probe", tError
      pfRecord "SodiumXT", kAbiSodium, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeTorrent
   catch tError
      stSectionFailed "TorrentXT probe", tError
      pfRecord "TorrentXT", kAbiTorrent, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeEnet
   catch tError
      stSectionFailed "enetxt probe", tError
      pfRecord "enetxt", kAbiEnet, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeDc
   catch tError
      stSectionFailed "DataChannelXT probe", tError
      pfRecord "DataChannelXT", kAbiDc, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeCoin
   catch tError
      stSectionFailed "CoinXT probe", tError
      pfRecord "CoinXT", kAbiCoin, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeBox2d
   catch tError
      stSectionFailed "Box2Dxt probe", tError
      pfRecord "Box2Dxt", kAbiBox2d, "?", "PROBE ERROR", tError
   end try
   try
      pfProbeScriptLayers
   catch tError
      stSectionFailed "script layers", tError
   end try

   pfTableSection
   pfDetailSection
   pfNextSection
   stReportDone
end stRun

-- ---- what engine is this? ----------------------------------------------------
-- The runbook carries a recorded green run whose platform was never captured,
-- and a result you cannot attribute to a machine is a result you cannot re-use.
-- Each fact sits in its OWN try and each is spelled out rather than looked up
-- through a variable: a computed property name (`the (tName) of ...`) is
-- engine-shaky on OXT and refused by the static gate, and losing the whole
-- header because one engine build lacks one property would be the wrong trade.
command pfEngineSection
   local tError, tValue

   stSection "engine"

   put "(unavailable)" into tValue
   try
      put the platform into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "platform:       " & tValue

   put "(unavailable)" into tValue
   try
      put the processor into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "processor:      " & tValue

   put "(unavailable)" into tValue
   try
      put the systemVersion into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "systemVersion:  " & tValue

   put "(unavailable)" into tValue
   try
      put the version into tValue
   catch tError
      put "(unavailable: " & tError & ")" into tValue
   end try
   stNote "engine version: " & tValue
end pfEngineSection

-- ---- the probes --------------------------------------------------------------
-- ORDER OF OPERATIONS INSIDE EACH PROBE IS THE POINT, and it is not tidiness.
-- Each one calls a handler that runs its member's ABI GUARD FIRST, and never one
-- that skips it. enLibraryVersion, dcLibraryVersion and btLastError all reach
-- into the native library with NO guard in front of them - which is precisely
-- what you must not do to a possibly-mismatched binary, since refusing before
-- any call that could corrupt memory is the whole reason those guards exist. So
-- the guarded call goes first, and a version string is read only afterwards,
-- once the library has been established to be the right one.

command pfProbeSodium
   local tError, tOk, tVersion

   put "false" into tOk
   put empty into tVersion
   try
      -- sxVersion() runs sPrepare() - the ABI guard plus libsodium's init -
      -- before it reads anything, so a returned string is proof of both.
      put sxVersion() into tVersion
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try
   pfReport "SodiumXT", kAbiSodium, tOk, tError, tVersion
end pfProbeSodium

command pfProbeTorrent
   local tError, tOk, tDetail

   put "false" into tOk
   put empty into tDetail
   try
      -- btStartSession() runs _checkABI() BEFORE it creates anything, so even
      -- the 0 return below is proof the ABI matched - the guard threw or it did
      -- not. Taking the session is the only guarded torrent entry point there
      -- is, so this takes it and gives it straight back: there is exactly one
      -- per process and the pass itself needs it.
      put btStartSession() into sSession
      put "true" into tOk
      if sSession > 0 then
         btStopSession sSession
         put 0 into sSession
      else
         put "loaded and the ABI guard passed, but a session was already live in this process - quit and relaunch OXT before any torrent-bearing paste (runbook 5.1.1)" into tDetail
      end if
   catch tError
      put "false" into tOk
      put 0 into sSession
   end try
   pfReport "TorrentXT", kAbiTorrent, tOk, tError, tDetail
end pfProbeTorrent

command pfProbeEnet
   local tError, tOk, tDetail, tRc

   put "false" into tOk
   put empty into tDetail
   try
      -- enInitialize() is the cheapest GUARDED entry point (it is refcounted,
      -- and enLibraryVersion() carries no guard at all), so it goes first and
      -- is balanced immediately afterwards.
      put enInitialize() into tRc
      put "true" into tOk
      put "true" into sEnetUp
      if tRc is not 0 then
         put "enInitialize returned " & tRc & " - the ABI guard still passed" into tDetail
      else
         put enLibraryVersion() into tDetail
      end if
      put enDeinitialize() into tRc
      put "false" into sEnetUp
   catch tError
      put "false" into tOk
   end try
   pfReport "enetxt", kAbiEnet, tOk, tError, tDetail
end pfProbeEnet

command pfProbeDc
   local tError, tOk, tDetail, tRc

   put "false" into tOk
   put empty into tDetail
   try
      -- dcInit() is the guarded one; dcLibraryVersion() is not. dcInit also
      -- warms the DTLS certificate, so this is the same call a real app makes
      -- at startup.
      put dcInit() into tRc
      put "true" into tOk
      put "true" into sDcUp
      if tRc is not 0 then
         put "dcInit returned " & tRc & " - the ABI guard still passed" into tDetail
      else
         put dcLibraryVersion() into tDetail
      end if
      -- EXPRESSION position: the parentheses are REQUIRED here and forbidden in
      -- the statement spelling. See the note in stCleanup.
      put dcCleanup() into tRc
      put "false" into sDcUp
   catch tError
      put "false" into tOk
   end try
   pfReport "DataChannelXT", kAbiDc, tOk, tError, tDetail
end pfProbeDc

command pfProbeCoin
   local tError, tOk

   put "false" into tOk
   try
      -- cxCheckABI is `returns nothing` and throws on skew, so silence is the
      -- pass and there is no value to inspect. BARE, because a zero-argument
      -- call in STATEMENT position must not carry parentheses.
      cxCheckABI
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try
   pfReport "CoinXT", kAbiCoin, tOk, tError, "the extension half; CoinXT's script layer has its own row below"
end pfProbeCoin

command pfProbeBox2d
   local tError, tOk, tFound

   put "false" into tOk
   put empty into tFound

   -- The Kit's loader assist, in its OWN try and deliberately ignored. It seeds
   -- revLibraryMapping from the folder beside this stack, which is what lets a
   -- Linux box load box2dxt.so with no sudo and no LD_LIBRARY_PATH - but it
   -- lives in the b2k Kit script, which this paste does not carry. Its absence
   -- is not a verdict about box2dxt, so it must not be able to make one: the
   -- suite harness can afford one try around both because it embeds the Kit.
   try
      b2kEnsureNativeLib
   catch tError
      put empty into tError
   end try

   try
      -- THE ONE MEMBER THAT HANDS THE NUMBER BACK. b2Version() returns the
      -- native b2lc_abi_version() with no guard in front of it, so this row is
      -- a real reading rather than the inference the other five rows make - and
      -- a skew shows up here as a NUMBER instead of a thrown message.
      put b2Version() into tFound
      put "true" into tOk
   catch tError
      put "false" into tOk
   end try

   if tOk is not "true" then
      pfReport "Box2Dxt", kAbiBox2d, "false", tError, empty
      exit pfProbeBox2d
   end if
   if tFound is kAbiBox2d then
      stAssert "Box2Dxt native ABI is " & kAbiBox2d & " (read, not inferred)", true
      pfRecord "Box2Dxt", kAbiBox2d, tFound, "LOADED", "b2Version() read the native ABI directly"
   else
      stAssert "Box2Dxt native ABI is " & kAbiBox2d & " (b2Version reported " & tFound & ")", false
      pfRecord "Box2Dxt", kAbiBox2d, tFound, "ABI SKEW", \\
            "b2Version() returned " & tFound & "; the binding refuses anything but " & kAbiBox2d & " at world creation"
   end if
end pfProbeBox2d

-- The members that ship a SECOND, pure-script half (or, for nostrxt, ARE pure
-- script). None is needed for the suite paste - which embeds them - so an
-- absent one is a SKIP with the one line that makes it run, not a defect.
command pfProbeScriptLayers
   local tError, tVersion, tHex

   stSection "pure-script layers (only their own demos need these loaded)"

   put empty into tVersion
   try
      put oxVersion() into tVersion
   catch tError
      put empty into tVersion
   end try
   if tVersion is not empty then
      stAssert "OnionXT script layer is in the message path", true
      pfNote "OnionXT: " & tVersion
   else
      stSkip "OnionXT script layer", "open onionxt/src/onionxt.livecodescript and start using it - the suite paste embeds it, so this is not needed for that run"
   end if

   put empty into tHex
   try
      -- A real vector rather than a version sniff: cxHexEncode of the two bytes
      -- 222,173 is "dead", so a present script layer is a WORKING one.
      put cxHexEncode(numToByte(222) & numToByte(173)) into tHex
   catch tError
      put empty into tHex
   end try
   if tHex is "dead" then
      stAssert "CoinXT script layer answers a known vector", true
   else if tHex is empty then
      stSkip "CoinXT script layer", "start using stack " & quote & "coinxt" & quote & " - the suite paste embeds it, so this is not needed for that run"
   else
      stAssert "CoinXT script layer answers a known vector", false
      pfNote "CoinXT script layer: cxHexEncode returned " & tHex & " where " & quote & "dead" & quote & " was expected"
   end if

   put empty into tHex
   try
      -- A real vector again: nxHexEncode of the same two bytes through the
      -- nostrxt core (its own hex, not coinxt's), so a present layer WORKS.
      put nxHexEncode(numToByte(222) & numToByte(173)) into tHex
   catch tError
      put empty into tHex
   end try
   if tHex is "dead" then
      stAssert "NostrXT script layer answers a known vector", true
   else if tHex is empty then
      stSkip "NostrXT script layer", "start using stack " & quote & "nostrxt" & quote & " - the suite paste embeds it, so this is not needed for that run"
   else
      stAssert "NostrXT script layer answers a known vector", false
      pfNote "NostrXT script layer: nxHexEncode returned " & tHex & " where " & quote & "dead" & quote & " was expected"
   end if
end pfProbeScriptLayers

-- ---- the table ---------------------------------------------------------------

command pfTableSection
   local tI, tCount

   stSection "THE TABLE - found vs expected (screenshot this)"
   stNote pfRow("member", "expected", "found", "verdict")
   stNote pfRow("------", "--------", "-----", "-------")
   put the number of lines of sRows into tCount
   repeat with tI = 1 to tCount
      stNote line tI of sRows
   end repeat
   stNote ""
   stNote "'= expected' is an INFERENCE, and an honest one: that member's ABI"
   stNote "guard is private, compares with strict equality, and did not throw."
   stNote "Box2Dxt's found column is a READING - b2Version() returns the number."
end pfTableSection

command pfDetailSection
   local tI, tCount

   stSection "details (version strings, and the exact text of anything thrown)"
   put the number of lines of sDetails into tCount
   if tCount is 0 then
      stNote "nothing to add: no probe threw, and no member reported a version."
      exit pfDetailSection
   end if
   repeat with tI = 1 to tCount
      stNote line tI of sDetails
   end repeat
end pfDetailSection

command pfNextSection
   local tError, tPlatform

   stSection "what to do with this"
   stNote "If the summary above says 0 failed, this install can run the pass:"
   stNote "go to the suite paste, tests/suite-selftest.livecodescript (S1 item 1)."
   stNote "A SKIP is not a defect - that member is not installed HERE."
   stNote "An ABI SKEW row is a BLOCKED member: it, and everything downstream"
   stNote "of it, cannot be tested on this machine until that library is"
   stNote "rebuilt and repackaged. Record the block and run what still runs."

   put empty into tPlatform
   try
      put the platform into tPlatform
   catch tError
      put empty into tPlatform
   end try
   if tPlatform is "MacOS" then
      -- Quoted from sodiumxt/CLAUDE.md's platform table by the generator, so
      -- these two numbers cannot drift from the member's own record of them.
      stNote ""
      stNote "MACOS: a SodiumXT ABI SKEW above is the KNOWN RECORDED STATE here,"
      stNote "not a new defect - the committed universal-mac dylib is at ABI @MACABI@"
      stNote "against this binding's @SODIUMABI@ (sodiumxt/CLAUDE.md's platform table;"
      stNote "runbook section 2.1's warning). Record it once and move to what a"
      stNote "Mac CAN run today (runbook S5); it needs the release workflow mac dispatch or the manual lipo build."
   end if

   stNote ""
   stNote "The tor daemon is NOT probed here: runbook 2.3's torrc and its"
   stNote quote & "Opening Control listener" & quote & " log line stay the S2/S4 prerequisite."
   stNote "This whole file is unexecuted until you run it: verified statically;"
   stNote "needs an OXT pass. Report anything it gets wrong as a defect in it."
end pfNextSection

-- ---- reporting plumbing ------------------------------------------------------

-- ONE place decides PASS / SKIP / FAIL, because the three are not
-- interchangeable and confusing them is exactly how a preflight lies. ABSENT is
-- a SKIP: the machine legitimately does not have that member, and that must
-- never read as a defect. SKEW is a FAIL: the member is installed and unusable,
-- which is the whole reason this file exists. Anything unclassified is ALSO a
-- FAIL, printed raw - an error we cannot name is a result to report, not one to
-- round down to a skip.
command pfReport pName, pExpected, pOk, pError, pDetail
   local tKind

   if pOk is "true" then
      stAssert pName && "loads; its ABI guard accepted the installed library (expects ABI " & pExpected & ")", true
      pfRecord pName, pExpected, "= expected", "LOADED", pDetail
      exit pfReport
   end if

   put pfClassify(pError) into tKind
   if tKind is "absent" then
      stSkip pName && "(expects ABI " & pExpected & ")", "not installed in this engine"
      pfRecord pName, pExpected, "-", "NOT INSTALLED", pError
   else if tKind is "skew" then
      stAssert pName && "ABI matches the installed native library", false
      pfRecord pName, pExpected, "MISMATCH", "ABI SKEW", pError
   else
      stAssert pName && "probe ran without an unexpected error", false
      pfRecord pName, pExpected, "?", "UNCLASSIFIED", pError
   end if
end pfReport

-- Which of the three things happened, read off the thrown text - because five
-- of the six guards are private handlers that never expose the number they
-- compared, so the message is all there is.
--
-- THE FAMILY'S SIX ABI GUARDS ALL SAY "ABI " IN THEIR MESSAGE, and
-- tools/build-preflight.py re-proves that against all six .lcb sources every
-- time it runs: a reworded guard fails the suite build instead of quietly
-- turning every skew on every engine into an UNCLASSIFIED row. The trailing
-- space is load-bearing - it is what keeps an engine message that merely says
-- "capability" (c-ap-ABI-lity) out of the skew bucket.
function pfClassify pError
   local tText

   put toLower(pError) into tText
   if tText contains "abi " then
      return "skew"
   end if
   -- The ABSENT spelling is the ENGINE's, not ours, and this file has never run
   -- on one - so it matches loosely and prints the raw text either way. A miss
   -- here costs a mislabelled row; it can never cost the fact itself.
   if tText contains "handler" then
      return "absent"
   end if
   if tText contains "not found" then
      return "absent"
   end if
   if tText contains "can't find" then
      return "absent"
   end if
   return "unknown"
end pfClassify

-- FIRST WRITE WINS, and that is what makes the table complete rather than
-- merely usually complete. Each probe records its own row, and stRun records a
-- PROBE ERROR row from the catch around it - so a member whose probe died in
-- its own scaffolding still HAS a row (a missing row reads as "not checked",
-- which is the one thing this file must never say by accident), and a member
-- that threw after recording does not get a second one.
command pfRecord pName, pExpected, pFound, pVerdict, pDetail
   if pName is among the lines of sSeen then
      exit pfRecord
   end if
   put pName & return after sSeen
   put pfRow(pName, pExpected, pFound, pVerdict) & return after sRows
   if pDetail is not empty then
      put pfPad(pName & ":", 16) & pDetail & return after sDetails
   end if
end pfRecord

command pfNote pText
   put pText & return after sDetails
end pfNote

function pfRow pName, pExpected, pFound, pVerdict
   return pfPad(pName, 16) & pfPad(pExpected, 10) & pfPad(pFound, 13) & pVerdict
end pfRow

-- Left-justify pText in pWidth columns. The table has to line up in the report
-- field's mono face to be one screenshot; a value LONGER than its column pushes
-- its row out rather than being truncated, because a truncated ABI number is
-- exactly the small lie this file exists to prevent.
function pfPad pText, pWidth
   local tOut, tI, tNeed

   put pText into tOut
   put pWidth - the number of chars of pText into tNeed
   repeat with tI = 1 to tNeed
      put space after tOut
   end repeat
   return tOut
end pfPad
'''


def build():
    """The whole generated stack, as text."""
    constants = abi_constants()
    lines = []
    for member in MEMBERS:
        entry = constants[member.key]
        lines.append("-- %s, cross-checked against %s"
                     % (entry["c_cite"], entry["lcb_cite"]))
        lines.append("constant %s = %d" % (entry["const"], entry["abi"]))
    block = "\n".join(lines)

    text = TEMPLATE
    text = text.replace("@ABICONSTANTS@", block)
    text = text.replace("@SCAFFOLD@", scaffold_block())
    text = text.replace("@MACABI@", str(mac_stale_abi()))
    text = text.replace("@SODIUMABI@", str(constants["sodium"]["abi"]))
    # An unsubstituted @NAME@ would reach the engine as literal text inside a
    # report line, where it reads like a broken install rather than like a bug
    # in this generator - so it fails the build here instead.
    left = re.findall(r"@[A-Z0-9]+@", text)
    if left:
        raise BuildError("unsubstituted placeholder(s) %s in the template"
                         % ", ".join(sorted(set(left))))
    return text


def main(argv):
    check = "--check" in argv[1:]
    try:
        content = build()
    except BuildError as err:
        sys.stderr.write("build-preflight: FAILED - %s\n" % err)
        return 2

    out_path = os.path.join(ROOT, OUT)
    if check:
        try:
            with open(out_path, encoding="utf-8") as handle:
                current = handle.read()
        except FileNotFoundError:
            current = None
        if current != content:
            print("build-preflight: %s is STALE; run tools/build-preflight.py" % OUT)
            return 1
        print("build-preflight: %s is up to date (%d ABI constants, "
              "each proved equal in its C shim and its .lcb binding)"
              % (OUT, len(MEMBERS)))
        return 0

    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(content)
    print("build-preflight: wrote %s (%d lines, %d ABI constants)"
          % (OUT, content.count("\n") + 1, len(MEMBERS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
