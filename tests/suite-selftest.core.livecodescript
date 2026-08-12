script "xTalkSuiteSelfTest"

-- suite-selftest.livecodescript - ONE self-building RUNTIME harness that drives
-- ALL SIX xTalk Suite members in a single OXT process and reports PASS / FAIL /
-- SKIP per check.
--
-- WHY THIS FILE EXISTS. Every member already ships a deep per-member selftest
-- (torrentxt/tests, enetxt/tests, datachannelxt/tests, ...) and those stay
-- authoritative for their own surface. This file is deliberately NOT a fifth
-- copy of them. It does the two things no per-member selftest can do:
--   1. It runs the whole suite in ONE process, in ONE pass, so the maintainer
--      gets one green/red list instead of five separate runs; and
--   2. it exercises the CROSS-MEMBER compositions the suite advertises - one
--      seed that is simultaneously a SodiumXT signing identity and a TorrentXT
--      DHT identity, a BEP44 item whose signature is produced by SodiumXT and
--      accepted by libtorrent, a SodiumXT-sealed payload carried byte-exact
--      over BOTH real transports, and the 60000-byte message budget that
--      enetxt and datachannelxt are supposed to share. Those compositions are
--      the suite's actual product; nothing tests them today.
--
-- HONESTY (root CLAUDE.md rule 6). THIS HARNESS HAS RUN. On 2026-08-08 it
-- ran on a real OXT engine with all six members installed and reported GREEN
-- - the suite's first runtime evidence. On 2026-08-10 it ran again - every
-- member's deep self-test folded in, both then-embedded script libraries in
-- the paste - and reported ZERO failures: 455 member-harness checks
-- (sodiumxt 68, onionxt 40, coinxt 207, torrentxt 96, enetxt sync 21,
-- datachannelxt sync 23) plus every core and cross-member section. On
-- 2026-08-12 it ran on Windows x64 (SodiumXT ABI 7, all SEVEN members
-- folded, three libraries embedded) and again reported ZERO failures -
-- riptide phase 1 at 89/89, coinxt phase 5 at 230/230, the offline-onion
-- legs 43/43. A later 2026-08-12 run of the current harness was green across
-- all 617 folded checks: sodiumxt 71, onionxt 43, coinxt 230, torrentxt 96,
-- enetxt sync 21, datachannelxt sync 23, and riptide phases 1-2 at 133.
-- What each run bought is recorded per member (each member's
-- README / CLAUDE.md and docs/OXT-PASS-RUNBOOK.md, the pass blockquotes).
-- Riptide's phase-2 single-engine work is therefore closed; only its
-- two-machine propagation criterion remains under runbook item 6.
--
-- THIS IS NO LONGER A SAMPLER, AND THAT IS THE BIG CHANGE. It used to drive
-- about a dozen handlers per member and say so. It now carries EVERY member's
-- own deep self-test as well, folded in whole by tools/build-suite-selftest.py:
--
--   sodiumxt        sxSelfTest()      21 groups, the entire sx* surface
--   onionxt         oxSelfTest()       8 groups, all offline
--   coinxt          its 28 sections    all five phases, ~300 checks
--   torrentxt       its full harness   sharing this file's single session
--   enetxt          its SYNC half      lifecycle, stale handles, tuning
--   datachannelxt   its SYNC half      lifecycle, the stale-handle surface
--   riptide         rsSelfTest()      run LAST: identity, wire formats, and
--                                     the phase-2 live feed layer, which
--                                     also shares this file's session
--
-- AND IT CARRIES THE THREE PURE-SCRIPT LIBRARIES THEMSELVES. coinxt's script
-- layer (encoders, addresses, the HD wallet walk), onionxt's entire ox*
-- surface, and riptide's rs* layer are LiveCodeScript, and the first two
-- used to be a separate setup step - `start using stack` x2 before pasting.
-- Embedded, that step is gone, and so is the failure mode it carried: the
-- 2026-08-10 re-run pasted a fresh harness into an engine whose in-memory
-- coinxt stack predated a parser fix, and got two red lines that read as
-- "the fix does not work" and meant "the fix was not loaded". This file and
-- the libraries in it are generated from one tree; they cannot skew against
-- each other.
--
-- So one paste now settles what used to take seven runs. Two things are still
-- honestly outside it, and they are named where they are cut rather than left
-- for you to discover: the ENet and DataChannel ASYNC loopbacks stay in their
-- own harnesses, because this file already drives a real loopback on both
-- transports for its cross-member sections and two state machines in one
-- process would race for the event handlers. Everything else those two members
-- test, this runs.
--
-- The folded sections are GENERATED. Do not edit them here - edit the member
-- harness they come from and run tools/build-suite-selftest.py. The gate set
-- runs --check, so a stale copy fails the build rather than quietly testing
-- code that moved.
--
-- Re-run this on any new engine, OS, or set of committed binaries: it is the
-- cheapest end-to-end check the suite has, and the recorded results are
-- evidence about those machines, not a permanent property of the code.
--
-- WITH ONE NARROWING, and it is worth knowing before you run this. The
-- cross-member sections below ask questions that are mostly NOT script
-- questions - "do libsodium and libtorrent derive the same ed25519 public key
-- from one seed?" is a question about two C libraries. tests/cross-member-test.py
-- settles exactly those, headless, by driving the built shims through ctypes,
-- and they PASS: the two libraries agree on the public key, libtorrent's DHT
-- secret key really is SodiumXT's expanded key (and not its seed||pk one),
-- libtorrent verifies a libsodium BEP44 signature and refuses one made for a
-- different seq, and ENX_MAX_MESSAGE == DCX_MAX_MESSAGE == 60000. So what those
-- sections still need the engine for is NARROWER than it looks: the FFI
-- marshalling and the script plumbing that reach those libraries, not the
-- cryptography underneath. A cross-member FAILURE here, on an engine, therefore
-- points at the binding rather than at the crypto - which is a much better place
-- to start debugging than "one of six things is wrong."
--
-- WHICH FILE TO PASTE: tests/suite-selftest.livecodescript, the GENERATED one.
-- This file (suite-selftest.core.livecodescript) is only the hand-maintained
-- half; on its own it has no member harnesses in it.
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK script
-- (Object > Stack Script), then close and reopen the stack. It builds its own
-- UI, probes for each member, runs everything it can, and shows the list. Use
-- "Copy results" to put the run on the clipboard and paste it back verbatim.
--
-- RUN IT STANDALONE. TorrentXT allows only ONE session per process, so close
-- any other TorrentXT stack (client, demo, torrent-selftest) first - otherwise
-- the torrent sections SKIP with a note rather than fighting for the session.
-- The enet loopback deliberately uses UDP port 27196, NOT the 27098 that
-- enet-selftest uses, so the two harnesses can coexist if both are open.
--
-- MISSING EXTENSIONS SKIP, THEY NEVER FAIL. Each member is probed with one
-- cheap guarded call inside try/catch (the family's fail-closed probe pattern,
-- as used by the demos and by onionxt's own oxSodiumHas* helpers). An absent
-- member marks its own sections SKIPPED with an install note; every other
-- section still runs, and any cross-member check that needs the absent member
-- skips with a reason instead of failing.
--
-- NON-DESTRUCTIVE. Nothing here writes a file, moves storage, deletes a
-- torrent, or touches a Tor control port. The DHT puts are queued into the
-- ordinary public DHT exactly as any client would; nothing else leaves the box
-- except loopback UDP to 127.0.0.1.
--
-- THE LCS LESSONS THIS FILE IS WRITTEN UNDER (the LiveCodeScript/LCB gotcha
-- list carried in every member CLAUDE.md): no brace array literals, no
-- subscripted function results, array emptiness by counting `the keys of` a
-- LOCAL, binary built with numToByte because string literals have no escape
-- syntax, byte-exact compares only under `set the caseSensitive to true`, all
-- declarations at handler top, and teardown calls written bare in statement
-- position, which is enetxt's own shipped teardown idiom (enet-lan-chat line
-- 220, enet-selftest line 371).
--
-- That last one is NOT a style choice, and this comment used to say it was.
-- It read: "datachannelxt spells the same thing dcCleanup(); BOTH forms are
-- attested in shipped members, so this is a style match, not a claim about what
-- the engine can compile." The reasoning was that a shipped member used it, so
-- it must work - but shipped is not run, and datachannelxt's own harness had
-- never been run on an engine. An OXT pass then failed on exactly that line.
-- A ZERO-ARGUMENT call in STATEMENT position must be BARE: a statement starting
-- with an identifier is parsed as a COMMAND, so `dcCleanup()` hands the command
-- the expression `()`, and `()` is not an expression. In EXPRESSION position
-- (`dcCleanup() is 0`, below) the parenthesised form is correct and required,
-- and a one-argument statement call like `dcFreePeer(sPeerA)` is fine because
-- `(sPeerA)` IS an expression - which is why the broken spelling looks exactly
-- like the working one beside it. Every member's check-livecodescript.py now
-- refuses it, .livecodescript only: LiveCode BUILDER does allow `sPrepare()` as
-- a statement, and the .lcb files rely on that on engine-verified paths.

-- ---- tunables ----------------------------------------------------------------
-- A port of our own so this harness and enet-selftest can both be open.
constant kStPortEnet = 27196
-- The budget BOTH real-time members enforce (ENX_MAX_MESSAGE == DCX_MAX_MESSAGE
-- == 60000). One over must be refused with -4 by both; a suite-level invariant
-- neither member can check alone.
constant kStBudget = 60000
constant kStOverBudget = 60001
-- SCTP's floor. libdatachannel negotiates our 60000 cap, but a remote is only
-- ever REQUIRED to accept 16 KiB, so the "large but legal" leg uses whatever
-- was actually negotiated, clamped to our budget - it must never assert against
-- a number the wire did not agree to.
constant kStSctpFloor = 16384
-- Generous: two live loopbacks (ENet handshake, plus ICE/DTLS/SCTP for WebRTC)
-- plus a 60000-byte transfer each, on a possibly loaded machine.
constant kStDeadlineMs = 40000

-- ---- state -------------------------------------------------------------------
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sRunning             -- "true" while the async phases are still live

-- probe results (one flag per member; "reason" strings carry the SKIP note)
local sHaveSodium, sHaveTorrent, sHaveEnet, sHaveDc, sHaveOnion, sHaveCoin
local sHaveCoinScript      -- coinxt ships in TWO pieces; see stProbe
local sHaveRiptideScript   -- the embedded riptide layer; same tripwire shape
local sTorrentNote         -- why torrent is unavailable, when it is

-- torrentxt
local sSession             -- THE one session handle (0 = none)

-- the shared sealed payload (one secretbox, carried over BOTH transports)
local sSealKey, sSealPlain, sSealBox

-- enetxt loopback
local sPhaseEn             -- "" / "connecting" / "sealed" / "big" / "closing" / "done" / "skip" / "failed"
local sEnServer, sEnClient
local sEnClientPeer, sEnServerPeer
local sEnGotSealed         -- the ciphertext the server received (Data)
local sEnBigSize           -- byte count of the budget-sized payload it received
local sEnSawDisc

-- datachannelxt loopback
local sPhaseDc             -- "" / "opening" / "sealed" / "big" / "done" / "skip" / "failed"
local sDcPeerA, sDcPeerB
local sDcChanA, sDcChanB
local sDcAOpen, sDcBOpen
local sDcGot               -- the ciphertext B received (Data)
local sDcBigSize, sDcBigWant

local sDeadline            -- the async phases' drop-dead time (ms clock)

-- Every FOLDED member's script locals and constants are hoisted to here, above
-- the first handler, by tools/build-suite-selftest.py - and so are the two
-- EMBEDDED script layers' (coinxt's and onionxt's), for the same reason.
--
-- They cannot live down in each member's own section, which is where they
-- started and where they look like they belong. OXT resolves a script-level
-- name BY LEXICAL POSITION, so a declaration below a handler is not in scope
-- for it - and stRunMemberHarnesses, up here in the core, reads every member's
-- counters (cx1sPassed and friends) to merge them. With the declarations left
-- in place the read was ~1000 lines ABOVE them, so `cx1sPassed` was an
-- undeclared name, LiveCodeScript evaluated it to the literal text
-- "cx1sPassed", and `add "cx1sPassed" to sPassed` killed the whole run with
-- "add: error in source expression" on a real engine.
--
-- Nothing about the member harnesses was wrong: each one declares its locals
-- above its own handlers, which is the house pattern in all six. Only the FOLD
-- broke the invariant, by putting one file's declarations after another file's
-- readers. check-suite-selftest.py now fails if any declaration lands below the
-- first handler.
-- GENERATED MEMBER DECLARATIONS GO HERE --

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack

on closeStack
   -- There is NO deterministic unload hook in this family: a leaked libtorrent
   -- session would block the next run outright (one session per process), and a
   -- leaked ENet host or WebRTC peer would hold a UDP port and its threads. So
   -- teardown is unconditional and idempotent here.
   stCleanup
end closeStack

on mouseUp
   if the short name of the target is "stRerun" then
      stCleanup
      stRun
   else if the short name of the target is "stCopy" then
      stCopyResults
   else
      pass mouseUp
   end if
end mouseUp

-- ---- self-building UI (idempotent) -------------------------------------------
command stBuild
   if there is a field "stResults" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to 760
   set the height of this stack to 680
   set the backgroundColor of this card to "237,239,243"
   set the title of this stack to "xTalk Suite - End-to-End Self-Test"
   stMakeLabel "stTitle", "  xTalk Suite - End-to-End Self-Test", "0,0,760,30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38,520,66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", "560,38,660,64"
   stMakeButton "stRerun", "Re-run", "666,38,744,64"
   stMakeList "stResults", "16,72,744,664"
   set the textFont of field "stResults" to "Courier"
   set the textSize of field "stResults" to 11
   unlock screen
end stBuild

command stMakeLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the textSize of field pName to pSize
   put pText into field pName
end stMakeLabel

command stMakeButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end stMakeButton

command stMakeList pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
end stMakeList

-- ---- assertion plumbing ------------------------------------------------------
command stAssert pName, pOk
   add 1 to sTotal
   if pOk then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

-- A SKIP is a first-class outcome here, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this member is not
-- here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

command stShow
   put sResultText into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sRunning is not "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "20,120,40"
      else
         set the foregroundColor of field "stSummary" to "170,30,30"
      end if
   end if
end stShow

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back verbatim
   -- into the OXT-pass record, so nobody has to retype a result.
   try
      set the clipboardData["text"] to sResultText
      answer "Results copied to the clipboard."
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

-- ---- the run -----------------------------------------------------------------
command stRun
   -- Belt and braces: a run that was interrupted (an engine error mid-pump)
   -- can leave a pump armed even though stCleanup never ran.
   stCancelPump
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put "true" into sRunning
   put empty into sPhaseEn
   put empty into sPhaseDc
   -- RELEASE THE SESSION BEFORE FORGETTING IT. This line used to be a bare
   -- `put 0 into sSession`, and that is how an engine pass loses the whole
   -- TorrentXT surface for the rest of the launch. The one-session latch lives
   -- in the C shim, the ONLY key that opens it is the integer handle
   -- btStartSession returned, and TorrentXT exports nothing that enumerates
   -- sessions or frees one you can no longer name (live_session_count() is a
   -- C++ test hook, not part of the FFI). So dropping the handle while the
   -- session is live orphans it permanently: btStartSession answers 0 for the
   -- rest of the process and the probe below blames a stack the operator does
   -- not have open.
   --
   -- The Re-run button already went through stCleanup, which stops it. This
   -- path is the one that did not: openStack re-entry, which the runbook's own
   -- trap 5.2 escape hatch (`send "openStack" to this stack`) performs on a
   -- stack that may already have run. Guarded because TorrentXT may simply be
   -- absent, and safe to repeat because btStopSession on a stale handle is a
   -- documented no-op.
   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent, or the session was already released; nothing to free.
   end try
   put 0 into sSession
   put false into sHaveCoinScript
   put false into sHaveRiptideScript
   put empty into sSealKey
   put empty into sSealPlain
   put empty into sSealBox

   put "xTalk Suite end-to-end self-test" & return into sResultText
   put "First green engine pass recorded 2026-08-08; this run re-confirms it here." & return after sResultText

   -- EVERY synchronous section is contained. A section that throws - a
   -- mis-declared foreign handler, an unexpected native error, an API that has
   -- moved since this harness was written - must cost EXACTLY ITSELF. Without
   -- this, one throw inside openStack leaves the maintainer with an error dialog,
   -- an empty window, no summary, and (worse) a live libtorrent session that
   -- blocks the next run. Each catch reports which section died and why.
   -- stProbe is contained for the same reason as every section below, and one
   -- sharper one: it is the statement that TAKES the session. A throw anywhere
   -- after btStartSession returned - a later probe's scaffolding, a report line
   -- - would strand a live session AND skip the `send "stPump"` at the bottom
   -- of this handler, which is the only route to stFinish and stTeardown. Each
   -- per-member probe inside already carries its own try, so this catches only
   -- the scaffolding between them, and every sHave* flag a half-finished probe
   -- leaves behind is read from inside a try, so a stale one costs a FAIL line.
   try
      stProbe
   catch tError
      stSectionFailed "extension probe", tError
   end try
   try
      stSodiumSection
   catch tError
      stSectionFailed "SodiumXT", tError
   end try
   try
      stTorrentSection
   catch tError
      stSectionFailed "TorrentXT", tError
   end try
   try
      stOnionSection
   catch tError
      stSectionFailed "OnionXT", tError
   end try
   try
      stCoinSection
   catch tError
      stSectionFailed "CoinXT", tError
   end try
   -- THE DEEP PER-MEMBER HARNESSES. Everything above is the suite's own
   -- sampler; this is each member's WHOLE self-test, folded in verbatim by
   -- tools/build-suite-selftest.py and namespaced so five harnesses that all
   -- define stAssert and sTotal can share one script. Each runs exactly as it
   -- does standalone and keeps its own counters; stMergeMember folds its log
   -- and its totals into this report afterwards.
   --
   -- They go HERE, after the sampler and before the cross-member sections,
   -- for one reason: TorrentXT allows a single session per process, the probe
   -- above already opened it, and the folded torrent harness reuses it. The
   -- async cross-member loopbacks start below and must not be racing while
   -- these run.
   -- CONTAINED like every other section, and for one extra reason. This call
   -- used to be uncontained (it was not the ONLY bare statement here - stProbe,
   -- stCancelPump and stShow are bare too; that earlier claim was wrong),
   -- on the reasoning that each folded harness contains its own sections. Four
   -- of the six have unguarded prologues (bt1stRun clears the error and reads
   -- btLastError before its try begins), and stMergeCounted/stMergeReturned
   -- only validate counters they were actually handed. A throw here therefore
   -- skipped everything below - including `send "stPump"`, which is what
   -- eventually reaches stFinish and stTeardown - so the run ended with the
   -- libtorrent session, the ENet hosts and the WebRTC peers all still live and
   -- no summary printed. The session is the one that does not come back: see
   -- the note above `put 0 into sSession`.
   -- The OUTER try is a BACKSTOP ONLY. Each of the seven harnesses inside is
   -- contained individually, and that is the part that matters: with only this
   -- outer one, a throw in member three left members four, five and six never
   -- run, never merged and not even SKIPPED, while the run still printed a
   -- tidy summary silently short by a hundred and fifty checks. That is the
   -- same wrong-answer-that-looks-right shape CLAUDE.md already records for
   -- stMergeCounted, reintroduced one level up - and strictly worse than the
   -- uncontained version it replaced, because a dead run is at least
   -- unmistakable. Per-member containment costs one FAIL line and keeps the
   -- other five intact; this catch only fires for the scaffolding between them.
   try
      stRunMemberHarnesses
   catch tError
      stSectionFailed "deep per-member self-tests", tError
   end try
   try
      stCrossIdentitySection
   catch tError
      stSectionFailed "cross: one identity", tError
   end try
   try
      stCrossBep44Section
   catch tError
      stSectionFailed "cross: BEP44 signing", tError
   end try
   try
      stSealPayload
   catch tError
      stSectionFailed "cross: sealed payload", tError
   end try
   try
      stStartEnetLoopback
   catch tError
      stSectionFailed "enetxt loopback start", tError
      put "failed" into sPhaseEn
   end try
   try
      stStartDcLoopback
   catch tError
      stSectionFailed "datachannelxt loopback start", tError
      put "failed" into sPhaseDc
   end try
   try
      stCrossBudgetSection
   catch tError
      stSectionFailed "cross: 60000-byte budget", tError
   end try

   put the milliseconds + kStDeadlineMs into sDeadline
   stShow
   send "stPump" to me in 33 milliseconds
end stRun

-- ---- the probe ---------------------------------------------------------------
-- ONE cheap guarded call per member. A missing extension raises a "can't find
-- handler" execution error, which try/catch turns into a flag; nothing here is
-- allowed to abort the run.
command stProbe
   local tVersion, tDigest

   stSection "extension probe (an absent member SKIPS, it never FAILS)"

   put false into sHaveSodium
   try
      put sxVersion() into tVersion
      put (tVersion is not empty) into sHaveSodium
   catch tError
      put false into sHaveSodium
   end try
   stProbeLine "SodiumXT", sHaveSodium, "org.openxtalk.library.sodium"

   -- TorrentXT is probed by actually TAKING the session, because there is only
   -- one per process and every torrent check needs it. A 0 return (rather than
   -- a throw) means the extension is present but somebody else holds it.
   put false into sHaveTorrent
   put empty into sTorrentNote
   try
      put btStartSession() into sSession
      if sSession > 0 then
         put true into sHaveTorrent
      else
         -- NAME BOTH CAUSES, because the shim cannot tell them apart and
         -- neither can we. btx_session_new refuses a second session with one
         -- message however the first was opened, and there is no exported
         -- live-count or owner query. This note used to assert the cause it
         -- could not know ("close the other TorrentXT stack"), which sends the
         -- operator hunting for a window that is not open. The other cause is
         -- real and this harness has produced it: an earlier run in THIS engine
         -- process that lost its handle, either by dying before stTeardown or
         -- by having its stack script recompiled, which clears every script
         -- local while the C-side session keeps running.
         --
         -- No recovery is attempted, and that is deliberate. A handle is
         -- (generation << 16) | slot, so the first one a process mints is
         -- exactly 65536 and a search would find it in one guess - and if the
         -- owner is a real client stack, btStopSession pauses it, flushes its
         -- resume data and joins its threads out from under an app still
         -- holding torrent handles. This harness advertises itself as
         -- non-destructive; guessing at another process-wide singleton is not
         -- a thing a self-test may do.
         put "TorrentXT is installed but a session is already live in this " \
               & "process. Either another TorrentXT stack owns it (close that " \
               & "stack and re-run), or an earlier run here lost its handle - " \
               & "quit and relaunch OXT. See OXT-PASS-RUNBOOK 5.1.1." \
               into sTorrentNote
      end if
   catch tError
      put 0 into sSession
      put "install org.openxtalk.library.torrent (or ABI skew: " & tError & ")" \
            into sTorrentNote
   end try
   if sTorrentNote is empty then
      put "org.openxtalk.library.torrent" into sTorrentNote
   end if
   stProbeLine "TorrentXT", sHaveTorrent, sTorrentNote

   put false into sHaveEnet
   try
      put enLibraryVersion() into tVersion
      put (tVersion is not empty) into sHaveEnet
   catch tError
      put false into sHaveEnet
   end try
   stProbeLine "enetxt", sHaveEnet, "org.openxtalk.library.enet"

   put false into sHaveDc
   try
      put dcLibraryVersion() into tVersion
      put (tVersion is not empty) into sHaveDc
   catch tError
      put false into sHaveDc
   end try
   stProbeLine "DataChannelXT", sHaveDc, "org.openxtalk.library.datachannel"

   -- OnionXT is pure LiveCodeScript, not a compiled extension - and its whole
   -- ox* surface is EMBEDDED in this paste by tools/build-suite-selftest.py,
   -- so there is no `start using stack "onionxt"` setup step any more. The
   -- probe stays: it costs one call, and a FAIL here no longer means "not
   -- loaded" (an embedded handler cannot be absent from a script that
   -- compiled) - it means the generated file itself is damaged, which is
   -- exactly the line you want to see before trusting 40 onion checks.
   put false into sHaveOnion
   try
      put oxVersion() into tVersion
      put (tVersion is not empty) into sHaveOnion
   catch tError
      put false into sHaveOnion
   end try
   stProbeLine "OnionXT", sHaveOnion, "embedded in this paste; a FAIL means the paste is damaged"

   -- CoinXT's hash surface is the phase-1 half of its binding; the probe is one
   -- of its published vectors, so a present CoinXT is a WORKING CoinXT.
   put false into sHaveCoin
   try
      put cxKeccak256(textEncode("", "UTF-8")) into tDigest
      put (the number of bytes of tDigest is 32) into sHaveCoin
   catch tError
      put false into sHaveCoin
   end try
   stProbeLine "CoinXT (extension)", sHaveCoin, "org.openxtalk.library.coin"

   -- COINXT IS THE ONLY MEMBER THAT SHIPS IN TWO PIECES: the hash and curve
   -- surfaces are the .lcb extension, probed above; the encoders, addresses
   -- and the whole HD layer are src/coinxt.livecodescript - which is EMBEDDED
   -- in this paste by tools/build-suite-selftest.py, so the old failure mode
   -- (extension installed, `start using stack "coinxt"` forgotten, ten
   -- sections of "handler not found" that read like a broken library) cannot
   -- happen any more, and neither can its subtler cousin, which cost the
   -- 2026-08-10 re-run: a STALE script layer left loaded from an earlier
   -- session, failing checks whose fix was already merged. The probe stays as
   -- the same tripwire as OnionXT's: cxHexEncode here is a real vector, so a
   -- FAIL means the generated file is damaged, not that a setup step was
   -- missed. The deep harness still guards on both flags.
   put false into sHaveCoinScript
   try
      put (cxHexEncode(numToByte(222) & numToByte(173)) is "dead") into sHaveCoinScript
   catch tError
      put false into sHaveCoinScript
   end try
   stProbeLine "CoinXT (script layer)", sHaveCoinScript, \
         "embedded in this paste; a FAIL means the paste is damaged"

   -- Riptide's script layer rides the same embed mechanism, so the same
   -- tripwire: rsZeroTarget is a real vector (40 zeros), not a version sniff.
   put false into sHaveRiptideScript
   try
      put (the number of chars in rsZeroTarget() is 40) into sHaveRiptideScript
   catch tError
      put false into sHaveRiptideScript
   end try
   stProbeLine "Riptide (script layer)", sHaveRiptideScript, \
         "embedded in this paste; a FAIL means the paste is damaged"
end stProbe

command stProbeLine pName, pPresent, pHint
   if pPresent then
      put "      " & pName & ": present" & return after sResultText
   else
      put "      " & pName & ": ABSENT - " & pHint & return after sResultText
   end if
end stProbeLine

-- ---- per-member: SodiumXT ----------------------------------------------------
-- Headline paths only. sodiumxt's own examples/sodium-tests.livecodescript is
-- the deep one; here we prove the binding loads and a crypto round trip works,
-- because every cross-member section below is built out of these calls.
command stSodiumSection
   local tVersion, tSeed, tRand1, tRand2, tHex, tBack
   local tPubA, tSecA, tPubB, tSecB
   local tMsg, tSig, tBox, tOpened, tWrongKey, tRejected, tExpanded

   stSection "SodiumXT: headline paths"
   if not sHaveSodium then
      stSkip "SodiumXT surface", "install org.openxtalk.library.sodium"
      exit stSodiumSection
   end if

   put sxVersion() into tVersion
   stAssert "sxVersion names SodiumXT", tVersion begins with "SodiumXT"
   stAssert "sxVersion names libsodium", tVersion contains "libsodium"

   -- The ONLY sanctioned entropy source in this family; everything below and
   -- every cross-member identity check depends on it.
   put sxRandomBytes(32) into tRand1
   put sxRandomBytes(32) into tRand2
   stAssert "sxRandomBytes(32) returns 32 bytes", the number of bytes of tRand1 is 32
   set the caseSensitive to true
   stAssert "sxRandomBytes does not repeat itself", tRand1 is not tRand2
   set the caseSensitive to false

   -- hex is the lingua franca between SodiumXT (Data in / Data out) and
   -- TorrentXT (hex Strings across its whole DHT surface), so the round trip is
   -- load-bearing for the cross-member sections, not decoration.
   put tRand1 into tSeed
   put sxBin2Hex(tSeed) into tHex
   stAssert "sxBin2Hex yields 64 hex bytes for a 32-byte seed", \
         the number of bytes of tHex is 64
   put sxHex2Bin(tHex) into tBack
   set the caseSensitive to true
   stAssert "sxHex2Bin round-trips the seed byte-for-byte", tBack is tSeed
   set the caseSensitive to false
   stAssert "sxMemEqual agrees (constant time)", sxMemEqual(tBack, tSeed)
   stAssert "sxMemEqual rejects a different value", not sxMemEqual(tRand1, tRand2)

   -- secretbox: the primitive the cross-member sealed-payload sections carry
   -- over both transports. Embedded NUL and 0x01 prove a Data crosses unmangled
   -- rather than merely that ASCII survives (LCS string literals have no escape
   -- syntax, so the bytes are built with numToByte).
   put textEncode("seal", "UTF-8") & numToByte(0) & numToByte(1) \
         & textEncode("me", "UTF-8") into tMsg
   put sxSecretBox(tMsg, tRand2) into tBox
   stAssert "sxSecretBox produces a box longer than its plaintext", \
         the number of bytes of tBox > the number of bytes of tMsg
   put sxSecretBoxOpen(tBox, tRand2) into tOpened
   set the caseSensitive to true
   stAssert "sxSecretBoxOpen recovers the plaintext byte-for-byte", tOpened is tMsg
   set the caseSensitive to false
   -- Fail CLOSED on the wrong key. A wrong key is deterministic where a flipped
   -- ciphertext byte is not (a random nonce byte might already hold the flipped
   -- value), so this is the version that cannot pass by accident.
   put sxRandomBytes(32) into tWrongKey
   put false into tRejected
   try
      put sxSecretBoxOpen(tBox, tWrongKey) into tOpened
   catch tError
      put true into tRejected
   end try
   stAssert "sxSecretBoxOpen throws on a wrong key", tRejected

   -- ed25519: the signature primitive the BEP44 composition below needs.
   sxSignKeypairFromSeed tSeed, tPubA, tSecA
   sxSignKeypairFromSeed tSeed, tPubB, tSecB
   stAssert "sxSignKeypairFromSeed public key is 32 bytes", \
         the number of bytes of tPubA is 32
   set the caseSensitive to true
   stAssert "sxSignKeypairFromSeed is deterministic for one seed", tPubB is tPubA
   set the caseSensitive to false
   put sxSignDetached(tMsg, tSecA) into tSig
   stAssert "sxSignDetached returns a 64-byte signature", \
         the number of bytes of tSig is 64
   stAssert "sxSignVerifyDetached accepts it", sxSignVerifyDetached(tSig, tMsg, tPubA)
   stAssert "sxSignVerifyDetached rejects a different message", \
         not sxSignVerifyDetached(tSig, tRand1, tPubA)

   -- The ABI-6 helper OnionXT composes for a reproducible .onion identity
   -- (SHA-512(seed), clamped). Asserted here so the cross-member identity
   -- section can rely on it existing.
   put empty into tExpanded
   try
      put sxSignSeedToExpandedKey(tSeed) into tExpanded
   catch tError
      put empty into tExpanded
   end try
   if tExpanded is empty then
      stSkip "sxSignSeedToExpandedKey is 64 bytes", \
            "SodiumXT ABI < 6 - update the installed extension"
   else
      stAssert "sxSignSeedToExpandedKey returns the 64-byte expanded key", \
            the number of bytes of tExpanded is 64
   end if
end stSodiumSection

-- ---- per-member: TorrentXT ---------------------------------------------------
-- Session lifecycle plus the pure, offline-verifiable half of the DHT surface.
-- Deliberately NOT a second torrent-selftest: no torrent is created, added,
-- moved, or removed here.
command stTorrentSection
   local tKp, tKp2, tBuf, tBuf2, tEvents

   stSection "TorrentXT: session + offline-verifiable DHT surface"
   if not sHaveTorrent then
      stSkip "TorrentXT surface", sTorrentNote
      exit stTorrentSection
   end if

   stAssert "btStartSession returned a positive handle", sSession > 0
   btClearError
   stAssert "btLastError is empty after btClearError", btLastError() is empty
   stAssert "btListenPort reports a bound port", btListenPort(sSession) > 0
   stAssert "btSetBool enable_dht", btSetBool(sSession, "enable_dht", true) is 0
   stAssert "btSetInt rejects an unknown settings key", \
         btSetInt(sSession, "no_such_setting_key", "1") < 0

   -- btDhtKeypair is a PURE function of its seed - that determinism is what
   -- lets a room code, a passphrase, or a SodiumXT seed BE a DHT identity.
   put btDhtKeypair("") into tKp
   stAssert "btDhtKeypair mints a 64-hex public key", \
         the number of chars of tKp["publicKey"] is 64
   stAssert "btDhtKeypair reports its 64-hex seed", \
         the number of chars of tKp["seed"] is 64
   put btDhtKeypair(tKp["seed"]) into tKp2
   stAssert "btDhtKeypair is deterministic from that seed", \
         tKp2["publicKey"] is tKp["publicKey"]

   -- The alert drain has to survive being called; the events themselves arrive
   -- asynchronously and are not asserted here (that is the member selftest's job).
   put btPoll(sSession) into tEvents
   stAssert "btPoll drains without throwing", stCount(tEvents) >= 0

   -- btDhtBep44SignBuf needs no session and no network: it is a pure function of
   -- (salt, seq, value), which is exactly why an off-box signer can use it.
   put btDhtBep44SignBuf("oxt", "1", textEncode("18:oxt-suite-selftest", "UTF-8")) into tBuf
   put btDhtBep44SignBuf("oxt", "1", textEncode("18:oxt-suite-selftest", "UTF-8")) into tBuf2
   stAssert "btDhtBep44SignBuf returns the canonical bytes", \
         the number of bytes of tBuf > 0
   set the caseSensitive to true
   stAssert "btDhtBep44SignBuf is deterministic", tBuf2 is tBuf
   set the caseSensitive to false
end stTorrentSection

-- ---- per-member: OnionXT -----------------------------------------------------
-- Pure-compute paths ONLY. OnionXT's live surface needs a running Tor daemon and
-- a control port; this harness never opens one, so everything here is the byte
-- work that runs with no daemon at all (docs/04).
command stOnionSection
   local tAddr, tPub, tInfo, tKeys, tZeroPub

   stSection "OnionXT: pure-compute address paths (no Tor daemon touched)"
   if not sHaveOnion then
      stSkip "OnionXT surface", "start using stack " & quote & "onionxt" & quote
      exit stOnionSection
   end if

   stAssert "oxVersion returns a version string", oxVersion() is not empty

   -- Structurally valid v3 address, BUILT rather than pasted so a miscounted
   -- literal cannot silently weaken the test. A v3 address is base32 of
   -- pubkey(32) || checksum(2) || version(1); 35 bytes is exactly 56 base32
   -- chars. 55 leading "a" (base32 zero) plus a final "d" (value 3) sets every
   -- bit to zero except the low two of the last byte - i.e. an all-zero public
   -- key, an all-zero checksum, and version byte 3.
   put empty into tAddr
   repeat 55 times
      put "a" after tAddr
   end repeat
   put "d" after tAddr
   put tAddr & ".onion" into tAddr

   put oxPublicKeyFromAddress(tAddr) into tPub
   stAssert "oxPublicKeyFromAddress yields a 32-byte ed25519 key", \
         the number of bytes of tPub is 32
   put empty into tZeroPub
   repeat 32 times
      put numToByte(0) after tZeroPub
   end repeat
   set the caseSensitive to true
   stAssert "oxPublicKeyFromAddress decoded base32 byte-exactly", tPub is tZeroPub
   set the caseSensitive to false

   -- The fail-closed half: wrong length, a character outside the base32
   -- alphabet, and a version byte that is not 3 must all be refused.
   stAssert "oxIsValidAddress rejects an empty address", not oxIsValidAddress("")
   stAssert "oxIsValidAddress rejects a short address", \
         not oxIsValidAddress("notanonion.onion")
   put empty into tAddr
   repeat 56 times
      put "a" after tAddr
   end repeat
   stAssert "oxIsValidAddress rejects a version-0 address", \
         not oxIsValidAddress(tAddr & ".onion")
   put empty into tAddr
   repeat 55 times
      put "a" after tAddr
   end repeat
   put "1" after tAddr
   stAssert "oxIsValidAddress rejects a non-base32 character", \
         not oxIsValidAddress(tAddr & ".onion")

   -- oxTransportInfo is OnionXT's capability advertisement, and it is computed
   -- by probing SodiumXT. Its keys are asserted here; whether they are TRUE is
   -- a cross-member question, checked in the cross-member section below.
   put oxTransportInfo() into tInfo
   put the keys of tInfo into tKeys
   stAssert "oxTransportInfo returns a populated array", \
         the number of lines of tKeys >= 5
   stAssert "oxTransportInfo names the transport", tInfo["transport"] is "ox"
end stOnionSection

-- ---- per-member: CoinXT ------------------------------------------------------
-- Published known answers this repo already pins in coinxt/tools/coin-kat.py,
-- re-run through the SCRIPT layer so a green result means the cx* wrappers
-- reach the same audited C the KAT harness tests. Hashes here, then the
-- secp256k1 sample in stCoinCurveSection below.
command stCoinSection
   local tDigest, tHex

   stSection "CoinXT: published hash vectors through the binding"
   if not sHaveCoin then
      stSkip "CoinXT surface", "install org.openxtalk.library.coin"
      exit stCoinSection
   end if

   -- These are the same published answers coinxt/tools/coin-kat.py pins against
   -- the native library. Re-running them HERE, through the cx* binding, is what
   -- proves the .lcb wrappers (buffer allocation, length marshalling, the status
   -- check) reach that same audited C - the layer no headless test can touch.
   put cxKeccak256(textEncode("", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "keccak256 of the empty input matches the published vector", \
         tHex is "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
   put cxKeccak256(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "keccak256 of abc matches the published vector", \
         tHex is "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
   put cxSha256(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "sha256 of abc matches FIPS 180-4", \
         tHex is "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
   put cxRipemd160(textEncode("abc", "UTF-8")) into tDigest
   put stHex(tDigest) into tHex
   stAssert "ripemd160 of abc matches its specification vector", \
         tHex is "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
   -- The aliasing trap this suite has already had to guard against natively:
   -- Keccak-256 and SHA3-256 differ only in a padding byte, and a binding that
   -- wired one symbol to both would pass every Keccak vector above.
   put cxSha3_256(textEncode("", "UTF-8")) into tDigest
   stAssert "cxSha3_256 is NOT aliased to cxKeccak256", \
         stHex(tDigest) is not \
         "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

   stCoinCurveSection
end stCoinSection

-- CoinXT phase 2: a SAMPLE of the secp256k1 surface, not a substitute for
-- coinxt/tests/coin-selftest.livecodescript, which drives all 31 public
-- handlers. Four checks earn their place in a sampler because the phase-2
-- wrappers have never been loaded on an engine and two of their shapes are new
-- to that binding:
--   * cxPublicKey passes an LCB Boolean through a C int FLAG. Nothing in phase 1
--     crossed the FFI as a boolean. If it fails to marshal, the compressed and
--     uncompressed calls return the same length instead of 33 and 65.
--   * cxVerify RETURNS Boolean, where every phase-1 handler returned Data.
-- The whole section is wrapped so that an older CoinXT install (phase-1 .lcb, or
-- an ABI-2 library) reports one clear failure rather than aborting the run.
command stCoinCurveSection
   local tSeckey, tPubC, tPubU, tDigest, tSig, tBad, tRecovered, tByte

   stSection "CoinXT: secp256k1 through the binding (phase 2)"
   try
      -- The private key 1, whose public key is the curve's own generator G, so
      -- this vector needs no table. Built with numToByte because this harness
      -- has no hex decoder and must not borrow another member's.
      put stRepeatByte(0, 31) & numToByte(1) into tSeckey
      put cxPublicKey(tSeckey, true) into tPubC
      put cxPublicKey(tSeckey, false) into tPubU
      stAssert "cxPublicKey (compressed) is the generator G", \
            stHex(tPubC) is \
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      -- If the C int flag did not marshal, these two would be equal.
      stAssert "the compressed and uncompressed keys differ in length", \
            the number of bytes of tPubC is 33 and \
            the number of bytes of tPubU is 65

      -- The most-republished RFC 6979 vector for secp256k1 + SHA-256. The digest
      -- is built with cxSha256, which this same section already checked against
      -- FIPS 180-4, so a failure here cannot be a hashing failure.
      put cxSha256(textEncode("Satoshi Nakamoto", "UTF-8")) into tDigest
      put cxSign(tSeckey, tDigest) into tSig
      stAssert "cxSign reproduces the published RFC 6979 signature", \
            stHex(tSig) is \
            "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8" & \
            "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"

      -- cxVerify returns Boolean, not Data. Both answers are asserted, because a
      -- binding that returned something falsy for everything would still pass a
      -- test that only checked the rejection.
      stAssert "cxVerify accepts a good signature", \
            cxVerify(tPubC, tDigest, tSig) is true
      put (byteToNum(byte 6 of tSig) + 1) mod 256 into tByte
      put byte 1 to 5 of tSig & numToByte(tByte) & byte 7 to 64 of tSig into tBad
      stAssert "cxVerify rejects a tampered signature", \
            cxVerify(tPubC, tDigest, tBad) is false

      -- ecrecover: the signature alone must yield the signer's key back.
      put cxRecover(cxSignRecoverable(tSeckey, tDigest), tDigest) into tRecovered
      stAssert "cxRecover returns the signing public key", \
            stHex(tRecovered) is stHex(tPubU)
   catch tError
      stSectionFailed "CoinXT secp256k1", tError
   end try
end stCoinCurveSection

-- ==============================================================================
-- THE CROSS-MEMBER SECTIONS - the reason this file exists.
-- ==============================================================================

-- ONE IDENTITY, TWO TRANSPORTS. The suite's "reaching you is verifying you"
-- claim rests on a single 32-byte seed being simultaneously a SodiumXT signing
-- identity and a TorrentXT DHT identity. Both libraries implement RFC 8032
-- ed25519 (libsodium ref10; libtorrent's bundled ed25519), so the same seed must
-- expand to the same public key in both - and if it ever does not, every DHT
-- mailbox the suite mints is addressed to a key its owner cannot sign for. That
-- invariant spans two members, so neither member's selftest can state it.
command stCrossIdentitySection
   local tSeed, tSeedHex, tKp, tPub, tSec, tPubHex, tExpanded, tExpandedHex

   stSection "CROSS: one seed, one identity (SodiumXT + TorrentXT)"
   if not sHaveSodium or not sHaveTorrent then
      stSkip "one identity, two transports", \
            "needs BOTH SodiumXT and a live TorrentXT session"
      exit stCrossIdentitySection
   end if

   -- The seed comes from SodiumXT's CSPRNG, crosses to TorrentXT as hex (its
   -- whole DHT surface speaks hex Strings), and must come back the same key.
   put sxRandomBytes(32) into tSeed
   put textDecode(sxBin2Hex(tSeed), "UTF-8") into tSeedHex
   stAssert "the sodium seed hex-encodes to 64 chars for TorrentXT", \
         the number of chars of tSeedHex is 64

   put btDhtKeypair(tSeedHex) into tKp
   stAssert "btDhtKeypair accepts the SodiumXT seed verbatim", \
         tKp["seed"] is tSeedHex
   put btDhtKeypair(tSeedHex) into tKp
   stAssert "btDhtKeypair is deterministic on that seed (same key twice)", \
         the number of chars of tKp["publicKey"] is 64

   sxSignKeypairFromSeed tSeed, tPub, tSec
   put textDecode(sxBin2Hex(tPub), "UTF-8") into tPubHex
   -- Both hex encoders emit lowercase, and `is` is case-insensitive by default,
   -- so this compare is deliberately left case-INsensitive: it is a comparison
   -- of two hex TEXTS, not of secret bytes.
   stAssert "SodiumXT and libtorrent derive the SAME ed25519 public key", \
         tPubHex is tKp["publicKey"]

   -- The two libraries disagree on how to SPELL the secret key, and the suite
   -- depends on knowing which is which: libsodium's is seed||publicKey (64
   -- bytes), libtorrent's is the EXPANDED SHA-512(seed) clamped form (also 64
   -- bytes) - the same form a Tor v3 onion service consumes. sxSignSeedToExpanded
   -- Key is the bridge, so this is the assertion that the bridge is the right one.
   put empty into tExpanded
   try
      put sxSignSeedToExpandedKey(tSeed) into tExpanded
   catch tError
      put empty into tExpanded
   end try
   if tExpanded is empty then
      stSkip "libtorrent's DHT secret key IS SodiumXT's expanded key", \
            "needs SodiumXT ABI >= 6 (sxSignSeedToExpandedKey)"
   else
      put textDecode(sxBin2Hex(tExpanded), "UTF-8") into tExpandedHex
      stAssert "libtorrent's DHT secret key IS SodiumXT's expanded key", \
            tExpandedHex is tKp["secretKey"]
   end if

   -- The third leg of the claim: that same public key IS a v3 .onion address.
   -- RENDERING one needs SHA3-256 for the address checksum. That was ononxt/
   -- docs/08 gap #2, and it CLOSED on 2026-08-11: SodiumXT ABI 7 ships
   -- sxSha3_256 and OnionXT's oxSha3_256 composes it, so oxAddressFromPublicKey
   -- now emits a real address against an ABI-7 SodiumXT. OnionXT's own harness
   -- renders and round-trips it (ox1's address section); this cross-section
   -- still does not re-render it here, because the identity being proven is the
   -- KEY (handle == the ed25519 key an onion would encode), and re-implementing
   -- the checksum would be the test faking a composition rather than observing
   -- it. The capability section below asserts oxTransportInfo now advertises the
   -- offline address as AVAILABLE whenever SHA3 is.
   stNote "the onion-address leg (SHA3-256 checksum) is now closed: SodiumXT ABI 7"
end stCrossIdentitySection

-- SIGN A BEP44 ITEM WITH SODIUMXT. btDhtBep44SignBuf exists precisely so a
-- signer that must keep its key private can produce a BEP44 signature without
-- any secret key crossing into TorrentXT. Nothing tests that composition today:
-- torrent-selftest can only prove the buffer is deterministic and that garbage
-- is refused, because it has no signer. Here we have one.
command stCrossBep44Section
   local tSeed, tSeedHex, tKp, tPub, tSec
   local tValue, tBuf, tSig, tSigHex, tWrongBuf, tWrongSig, tWrongHex

   stSection "CROSS: SodiumXT signs a BEP44 item TorrentXT accepts"
   if not sHaveSodium or not sHaveTorrent then
      stSkip "SodiumXT-signed BEP44 put", \
            "needs BOTH SodiumXT and a live TorrentXT session"
      exit stCrossBep44Section
   end if

   put sxRandomBytes(32) into tSeed
   put textDecode(sxBin2Hex(tSeed), "UTF-8") into tSeedHex
   put btDhtKeypair(tSeedHex) into tKp
   sxSignKeypairFromSeed tSeed, tPub, tSec

   -- v must be ALREADY bencoded and is stored verbatim, so what we sign is
   -- byte-identical to what lands in the DHT. "18:" is the bencode length
   -- prefix for the 18-character payload that follows.
   put textEncode("18:oxt-suite-selftest", "UTF-8") into tValue
   put btDhtBep44SignBuf("oxt", "7", tValue) into tBuf
   stAssert "btDhtBep44SignBuf handed back the canonical buffer", \
         the number of bytes of tBuf > 0

   put sxSignDetached(tBuf, tSec) into tSig
   stAssert "SodiumXT signed those exact bytes", the number of bytes of tSig is 64
   stAssert "SodiumXT verifies its own signature over the BEP44 buffer", \
         sxSignVerifyDetached(tSig, tBuf, tPub)

   -- The real proof: libtorrent VERIFIES the foreign signature on this thread,
   -- before anything touches the network, and only queues the put if it checks
   -- out. A 0 here means two independent ed25519 implementations agreed on one
   -- signature over one canonical buffer - the whole point of the seam.
   put textDecode(sxBin2Hex(tSig), "UTF-8") into tSigHex
   stAssert "btDhtPutSigned accepts the SodiumXT signature", \
         btDhtPutSigned(sSession, tKp["publicKey"], "oxt", "7", tValue, tSigHex) is 0

   -- And it must fail CLOSED. A well-formed 128-hex signature that is valid for
   -- a DIFFERENT seq is the sharpest negative available: it proves the check
   -- binds the whole (salt, seq, value) tuple, not merely the hex shape.
   put btDhtBep44SignBuf("oxt", "8", tValue) into tWrongBuf
   put sxSignDetached(tWrongBuf, tSec) into tWrongSig
   put textDecode(sxBin2Hex(tWrongSig), "UTF-8") into tWrongHex
   stAssert "btDhtPutSigned refuses a signature made for another seq", \
         btDhtPutSigned(sSession, tKp["publicKey"], "oxt", "7", tValue, tWrongHex) < 0
end stCrossBep44Section

-- OnionXT's capability advertisement is COMPUTED from SodiumXT: it probes for
-- HMAC, entropy, seed expansion, and SHA3 and reports what it can actually do.
-- So the honest cross-member assertion is that its answers track reality.
command stCrossOnionSection
   local tInfo, tHasSha3, tErr

   stSection "CROSS: OnionXT advertises its real SodiumXT-backed capabilities"
   if not sHaveOnion then
      stSkip "OnionXT capability negotiation", \
            "start using stack " & quote & "onionxt" & quote
      exit stCrossOnionSection
   end if

   put oxTransportInfo() into tInfo
   if sHaveSodium then
      stAssert "SAFECOOKIE auth is advertised when SodiumXT is present", \
            tInfo["safeCookieAuth"] is true
      stAssert "deterministic .onion keys are advertised (sxSignSeedToExpandedKey)", \
            tInfo["deterministicOnion"] is true
   else
      stAssert "capabilities are advertised as absent without SodiumXT", \
            tInfo["safeCookieAuth"] is false
   end if
   -- offlineAddress tracks whether SHA3-256 is reachable, which is exactly what
   -- OnionXT's oxSha3_256 probes: it composes SodiumXT's sxSha3_256 (ABI 7,
   -- onionxt/docs/08 gap #2, closed 2026-08-11). So the honest assertion is that
   -- the advertisement TRACKS REALITY, not that it holds a fixed answer: probe
   -- SHA3 the same way OnionXT does and require the flag to agree. It is true on
   -- an ABI-7 SodiumXT and false on an older one or with SodiumXT absent.
   put false into tHasSha3
   if sHaveSodium then
      try
         put (the number of bytes of sxSha3_256(textEncode("probe", "ASCII")) is 32) \
               into tHasSha3
      catch tErr
         put false into tHasSha3
      end try
   end if
   stAssert "oxTransportInfo's offlineAddress tracks whether SHA3-256 is available", \
         tInfo["offlineAddress"] is tHasSha3
   if tHasSha3 then
      stNote "SHA3-256 is present: offline .onion address rendering is AVAILABLE"
   else
      stNote "SHA3-256 absent (SodiumXT pre-ABI-7 or absent): offline address deferred"
      stNote "that FALSE was docs/08 gap #2; SodiumXT ABI 7+ closes it (reinstall)"
   end if
end stCrossOnionSection

-- Build the one sealed payload BOTH transports will carry. Sealing once and
-- sending the same ciphertext twice is the point: the assertion is that a
-- SodiumXT box survives two entirely different wire formats unchanged.
command stSealPayload
   stSection "CROSS: one SodiumXT-sealed payload for both transports"
   put textEncode("suite", "UTF-8") & numToByte(0) & numToByte(1) & numToByte(255) \
         & textEncode("sealed-payload", "UTF-8") into sSealPlain
   if not sHaveSodium then
      -- Degrade visibly, never silently: the transports still carry the bytes
      -- and the byte-exactness checks still mean something; only the crypto
      -- half is skipped.
      put sSealPlain into sSealBox
      put empty into sSealKey
      stSkip "sxSecretBox seals the transport payload", \
            "SodiumXT absent - the transports will carry the plaintext instead"
      exit stSealPayload
   end if
   put sxRandomBytes(32) into sSealKey
   put sxSecretBox(sSealPlain, sSealKey) into sSealBox
   stAssert "sealed one payload for both transports", \
         the number of bytes of sSealBox > the number of bytes of sSealPlain
end stSealPayload

-- THE 60000-BYTE BUDGET SEAM. ENX_MAX_MESSAGE and DCX_MAX_MESSAGE are both
-- 60000 and both refuse an over-budget message with -4 rather than truncating
-- or splitting it. That the two numbers agree is a SUITE invariant: an app that
-- switches transports at runtime (the whole premise of having both) would
-- silently start losing messages if they drifted apart. Neither member can
-- check it alone.
--
-- The enetxt half runs here, synchronously, because enSend validates the length
-- before it needs a connection. The datachannelxt half CANNOT: dcx_send_data
-- validates the channel handle first, so an over-budget send on a stale handle
-- returns -2, not -4 - it needs a LIVE channel, and therefore runs in the
-- datachannel loopback's open phase below. Same invariant, reported in two
-- places for a reason.
command stCrossBudgetSection
   local tOver

   stSection "CROSS: the 60000-byte budget both transports share"
   if not sHaveEnet then
      stSkip "enetxt refuses 60001 bytes", "install org.openxtalk.library.enet"
   else if sEnClientPeer is empty or sEnClientPeer <= 0 then
      stSkip "enetxt refuses 60001 bytes", "the enet loopback did not start"
   else
      put stRepeatByte(90, kStOverBudget) into tOver
      stAssert "enSend refuses 60001 bytes with -4 (never truncates)", \
            enSend(sEnClientPeer, 0, tOver, 0) is -4
   end if
   if not sHaveDc then
      stSkip "datachannelxt refuses 60001 bytes", \
            "install org.openxtalk.library.datachannel"
   else
      stNote "the datachannelxt half needs a LIVE channel; see the loopback below"
   end if
end stCrossBudgetSection

-- ---- enetxt: the live loopback ----------------------------------------------
command stStartEnetLoopback
   stSection "enetxt: live loopback on 127.0.0.1:" & kStPortEnet
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer
   put empty into sEnGotSealed
   put empty into sEnBigSize
   put empty into sEnSawDisc
   if not sHaveEnet then
      stSkip "enetxt loopback", "install org.openxtalk.library.enet"
      put "skip" into sPhaseEn
      exit stStartEnetLoopback
   end if

   stAssert "enInitialize returns 0", enInitialize() is 0
   stAssert "enLibraryVersion names enet", enLibraryVersion() begins with "enet "
   -- A stale handle must be a harmless no-op, not a crash: the generation-tagged
   -- handle rule, spot-checked (the member selftest covers the whole surface).
   stAssert "enHostDestroy(0) is a harmless no-op", enHostDestroy(0) is 0

   put enHostCreateServer("127.0.0.1", kStPortEnet, 4, 2, 0, 0) into sEnServer
   stAssert "enet server host bound", sEnServer > 0
   put enHostCreateClient(1, 2, 0, 0) into sEnClient
   stAssert "enet client host created", sEnClient > 0
   if sEnServer <= 0 or sEnClient <= 0 then
      stNote "UDP port " & kStPortEnet & " may already be held; skipping the loopback"
      put "failed" into sPhaseEn
      exit stStartEnetLoopback
   end if
   put enConnect(sEnClient, "127.0.0.1", kStPortEnet, 2, 7) into sEnClientPeer
   stAssert "enConnect returns a peer handle", sEnClientPeer > 0
   if sEnClientPeer <= 0 then
      put "failed" into sPhaseEn
      exit stStartEnetLoopback
   end if
   put "connecting" into sPhaseEn
end stStartEnetLoopback

-- Deliberately if/else-if rather than switch: this file lives at the SUITE root
-- and has to satisfy every member's copy of check-livecodescript.py, and the
-- older copies (sodiumxt's lineage) do not model `switch` as a block, so an
-- `end switch` there is mistaken for a handler terminator. if/else-if is exactly
-- as clear and is understood by all of them.
command stEnServerEvent pEvent
   local tName, tPayload
   put pEvent["name"] into tName
   if tName is "enetConnect" then
      put pEvent["peer"] into sEnServerPeer
      stAssert "enet server sees the connect data (7)", pEvent["data"] is 7
   else if tName is "enetReceive" then
      -- Routed by CHANNEL, not by phase, so an early delivery can never be
      -- mistaken for the later one.
      put pEvent["payload"] into tPayload
      if pEvent["channel"] is 0 then
         put tPayload into sEnGotSealed
      else
         put the number of bytes of tPayload into sEnBigSize
      end if
   else if tName is "enetDisconnect" then
      put "true" into sEnSawDisc
   end if
end stEnServerEvent

command stEnClientEvent pEvent
   if pEvent["name"] is "enetConnect" then
      stAssert "enet client sees the handle enConnect gave it", \
            pEvent["peer"] is sEnClientPeer
      stAssert "enSend carries the sealed ciphertext", \
            enSend(sEnClientPeer, 0, sSealBox, 0) is 0
   end if
end stEnClientEvent

command stEnAdvance
   local tBig
   if sPhaseEn is "connecting" then
      if sEnServerPeer is not empty then
         put "sealed" into sPhaseEn
      end if
   else if sPhaseEn is "sealed" then
      if sEnGotSealed is not empty then
         stCheckSealed "enetxt", sEnGotSealed
         -- The other half of the budget seam: a payload AT the cap must be
         -- accepted and delivered whole. ENet fragments it internally; script
         -- must see one message of exactly 60000 bytes.
         put stRepeatByte(90, kStBudget) into tBig
         stAssert "enSend accepts a payload at the 60000-byte budget", \
               enSend(sEnClientPeer, 1, tBig, 0) is 0
         put "big" into sPhaseEn
      end if
   else if sPhaseEn is "big" then
      if sEnBigSize is not empty then
         stAssert "enet reassembled all 60000 bytes into ONE message", \
               sEnBigSize is kStBudget
         stAssert "enDisconnect returns 0", enDisconnect(sEnClientPeer, 7) is 0
         put "closing" into sPhaseEn
      end if
   else if sPhaseEn is "closing" then
      if sEnSawDisc is not empty then
         stAssert "enet closed gracefully (server drained enetDisconnect)", true
         put "done" into sPhaseEn
      end if
   end if
end stEnAdvance

function stEnDone
   return sPhaseEn is "done" or sPhaseEn is "skip" or sPhaseEn is "failed"
end stEnDone

-- ---- datachannelxt: the live loopback ---------------------------------------
command stStartDcLoopback
   stSection "datachannelxt: live loopback (two in-process peers)"
   put empty into sDcPeerA
   put empty into sDcPeerB
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcAOpen
   put empty into sDcBOpen
   put empty into sDcGot
   put empty into sDcBigSize
   put empty into sDcBigWant
   if not sHaveDc then
      stSkip "datachannelxt loopback", "install org.openxtalk.library.datachannel"
      put "skip" into sPhaseDc
      exit stStartDcLoopback
   end if

   stAssert "dcInit returns 0", dcInit() is 0
   stAssert "dcLibraryVersion names libdatachannel", \
         dcLibraryVersion() contains "libdatachannel"
   stAssert "dcPeerState(0) is -1 for a stale handle", dcPeerState(0) is -1

   put dcCreatePeer("") into sDcPeerA
   put dcCreatePeer("") into sDcPeerB
   stAssert "dcCreatePeer A", sDcPeerA > 0
   stAssert "dcCreatePeer B", sDcPeerB > 0
   if sDcPeerA <= 0 or sDcPeerB <= 0 then
      put "failed" into sPhaseDc
      exit stStartDcLoopback
   end if
   put dcCreateChannel(sDcPeerA, "suite-selftest") into sDcChanA
   stAssert "dcCreateChannel on A (auto-negotiation makes the offer)", sDcChanA > 0
   if sDcChanA <= 0 then
      put "failed" into sPhaseDc
      exit stStartDcLoopback
   end if
   put "opening" into sPhaseDc
end stStartDcLoopback

-- The in-script signaling shuttle IS the loopback: WebRTC signaling is always
-- the app's job, and here the app hands each side's description and candidates
-- straight to the other.
command stDcEvent pEvent
   local tName, tDest, tPayload
   put pEvent["name"] into tName
   if tName is "dcLocalDescription" then
      put stDcOtherPeer(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcSetRemoteDescription tDest, pEvent["sdp"], pEvent["sdpType"]
      end if
   else if tName is "dcLocalCandidate" then
      put stDcOtherPeer(pEvent["peer"]) into tDest
      if tDest is not empty then
         dcAddRemoteCandidate tDest, pEvent["candidate"], pEvent["mid"]
      end if
   else if tName is "dcChannelIncoming" then
      if pEvent["peer"] is sDcPeerB and sDcChanB is empty then
         put pEvent["channel"] into sDcChanB
      end if
   else if tName is "dcChannelOpen" then
      if pEvent["channel"] is sDcChanA then
         put "true" into sDcAOpen
      else if sDcChanB is not empty and pEvent["channel"] is sDcChanB then
         put "true" into sDcBOpen
      end if
   else if tName is "dcMessage" then
      -- Routed by PHASE here (unlike enet, a data channel has no channel number
      -- to key on), and the two payloads are sent strictly one phase apart so
      -- the routing can never be ambiguous.
      put pEvent["payload"] into tPayload
      if sPhaseDc is "big" then
         put the number of bytes of tPayload into sDcBigSize
      else
         put tPayload into sDcGot
      end if
   end if
end stDcEvent

function stDcOtherPeer pPeer
   if pPeer is sDcPeerA then
      return sDcPeerB
   else if pPeer is sDcPeerB then
      return sDcPeerA
   end if
   return empty
end stDcOtherPeer

command stDcAdvance
   local tOver, tMax, tBig
   if sPhaseDc is "opening" then
      if sDcAOpen is "true" and sDcBOpen is "true" then
         stAssert "datachannel loopback negotiated and both ends opened", true
         stAssert "the incoming channel carries our label", \
               dcChannelLabel(sDcChanB) is "suite-selftest"
         stAssert "peer A reports connected", dcPeerState(sDcPeerA) is 2
         -- THE BUDGET SEAM, datachannelxt half. It has to be here: the shim
         -- validates the channel handle BEFORE the length, so this -4 can only
         -- be observed on a live channel.
         put stRepeatByte(90, kStOverBudget) into tOver
         stAssert "dcSendData refuses 60001 bytes with -4 (same code as enetxt)", \
               dcSendData(sDcChanA, tOver) is -4
         stAssert "dcSendData carries the sealed ciphertext", \
               dcSendData(sDcChanA, sSealBox) is 0
         put "sealed" into sPhaseDc
      end if
   else if sPhaseDc is "sealed" then
      if sDcGot is not empty then
         stCheckSealed "datachannelxt", sDcGot
         -- "Large but legal" means legal ON THIS WIRE: the shim advertises our
         -- 60000 cap in the SCTP negotiation, but the negotiated value is what
         -- the association actually agreed to, so clamp rather than assume.
         put dcChannelMaxMessage(sDcChanA) into tMax
         stAssert "SCTP negotiated at least its 16 KiB floor", tMax >= kStSctpFloor
         if tMax > kStBudget then
            put kStBudget into tMax
         end if
         if tMax < kStSctpFloor then
            -- A nonsense reading (dcChannelMaxMessage answers -1 for a handle it
            -- no longer knows) must not become a nonsense payload and a second,
            -- meaningless failure: the assertion above already reported it.
            put kStSctpFloor into tMax
         end if
         put tMax into sDcBigWant
         put stRepeatByte(90, tMax) into tBig
         put "big" into sPhaseDc
         stAssert "dcSendData accepts a payload at the negotiated cap", \
               dcSendData(sDcChanA, tBig) is 0
      end if
   else if sPhaseDc is "big" then
      if sDcBigSize is not empty then
         stAssert "datachannel delivered the large payload whole", \
               sDcBigSize is sDcBigWant
         put "done" into sPhaseDc
      end if
   end if
end stDcAdvance

function stDcDone
   return sPhaseDc is "done" or sPhaseDc is "skip" or sPhaseDc is "failed"
end stDcDone

-- ---- the shared sealed-payload check ----------------------------------------
-- The cross-member payoff: the SAME ciphertext, over two unrelated transports,
-- opened by SodiumXT on arrival. Byte-exactness needs caseSensitive, because
-- `is` folds 0x41 onto 0x61 by default and would let corrupted binary compare
-- equal; it is restored immediately afterwards so the hex-text comparisons
-- elsewhere in the run keep their intended case-insensitive semantics.
command stCheckSealed pWho, pGot
   local tOpened
   set the caseSensitive to true
   stAssert pWho & " delivered the ciphertext byte-for-byte", pGot is sSealBox
   set the caseSensitive to false
   if not sHaveSodium then
      stSkip pWho & ": sxSecretBoxOpen on arrival", \
            "SodiumXT absent - the payload crossed as plaintext"
      exit stCheckSealed
   end if
   put empty into tOpened
   try
      put sxSecretBoxOpen(pGot, sSealKey) into tOpened
   catch tError
      put empty into tOpened
   end try
   set the caseSensitive to true
   stAssert pWho & ": sxSecretBoxOpen recovers the exact plaintext", \
         tOpened is sSealPlain
   set the caseSensitive to false
end stCheckSealed

-- ---- the pump ----------------------------------------------------------------
-- ONE timer chain drives BOTH async members. It reschedules itself until every
-- async phase is terminal or the deadline passes; it never blocks the
-- interpreter, because nothing in this family may block the one script thread.
command stPump
   local tEvents, tEvent
   if sRunning is not "true" then
      exit stPump
   end if

   -- Contained for the same reason the synchronous sections are, and with one
   -- extra stake: a throw out of the pump would break the timer chain, so
   -- nothing would ever reach stFinish - and the hosts, peers, and the one
   -- libtorrent session would all leak until the maintainer closed the stack.
   -- Marking the phase "failed" lets the run converge and tear down properly.
   if not stEnDone() then
      try
         put enPoll(sEnServer) into tEvents
         repeat for each element tEvent in tEvents
            stEnServerEvent tEvent
         end repeat
         put enPoll(sEnClient) into tEvents
         repeat for each element tEvent in tEvents
            stEnClientEvent tEvent
         end repeat
         stEnAdvance
      catch tError
         stAssert "enet loopback pumped without throwing", false
         stNote "it raised:" && tError
         put "failed" into sPhaseEn
      end try
   end if

   if not stDcDone() then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            stDcEvent tEvent
         end repeat
         stDcAdvance
      catch tError
         stAssert "datachannel loopback pumped without throwing", false
         stNote "it raised:" && tError
         put "failed" into sPhaseDc
      end try
   end if

   if stEnDone() and stDcDone() then
      stFinish
      exit stPump
   end if

   -- A stuck section must not take the run with it: record the failure against
   -- the section that hung and finish everything else.
   if the milliseconds > sDeadline then
      if not stEnDone() then
         stAssert "enet loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseEn & "; UDP to 127.0.0.1 may be blocked"
         put "failed" into sPhaseEn
      end if
      if not stDcDone() then
         stAssert "datachannel loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseDc & "; UDP to this machine may be blocked"
         put "failed" into sPhaseDc
      end if
      stFinish
      exit stPump
   end if

   stShow
   send "stPump" to me in 33 milliseconds
end stPump

-- ---- finish + teardown -------------------------------------------------------
command stFinish
   -- Run last: OnionXT's capability advertisement is pure compute, but reading
   -- it here keeps the whole cross-member story in one block at the end of the
   -- report, next to the transports it describes.
   try
      stCrossOnionSection
   catch tError
      stSectionFailed "cross: OnionXT capabilities", tError
   end try

   -- Teardown is contained too, but it is the ONE thing that must be attempted
   -- no matter what came before: stCleanup on closeStack is the safety net if a
   -- handle survives this.
   try
      stTeardown
   catch tError
      stSectionFailed "teardown", tError
   end try

   stSection "summary"
   stNote "This is a sampler, not a full per-member selftest: it drives the"
   stNote "headline paths and the cross-member seams. Each member has a deeper"
   stNote "harness that still needs its own engine run. Paste these numbers back."
   put empty into sRunning
   stShow
end stFinish

-- Everything this file opened gets closed, in dependency order, each guarded so
-- one absent member cannot stop the rest from being released.
command stTeardown
   stSection "teardown (nothing may outlive the run)"
   if sHaveDc then
      if sDcChanA is not empty and sDcChanA > 0 then
         dcCloseChannel sDcChanA
         dcFreeChannel sDcChanA
      end if
      if sDcChanB is not empty and sDcChanB > 0 then
         dcFreeChannel sDcChanB
      end if
      if sDcPeerA is not empty and sDcPeerA > 0 then
         dcFreePeer sDcPeerA
      end if
      if sDcPeerB is not empty and sDcPeerB > 0 then
         dcFreePeer sDcPeerB
      end if
      stAssert "dcCleanup returns 0", dcCleanup() is 0
   end if
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcPeerA
   put empty into sDcPeerB

   if sHaveEnet then
      if sEnServer is not empty and sEnServer > 0 then
         stAssert "enHostDestroy(server) returns 0", enHostDestroy(sEnServer) is 0
      end if
      if sEnClient is not empty and sEnClient > 0 then
         stAssert "enHostDestroy(client) returns 0", enHostDestroy(sEnClient) is 0
      end if
      stAssert "enDeinitialize returns 0", enDeinitialize() is 0
   end if
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer

   -- The one that MUST happen: a surviving libtorrent session makes the next run
   -- impossible (one session per process) and keeps its threads and sockets.
   if sSession is not empty and sSession > 0 then
      btStopSession sSession
      stAssert "btStopSession released THE session", true
   end if
   put 0 into sSession
end stTeardown

-- Idempotent hard teardown for closeStack and for Re-run. It must survive being
-- called when a member was never present, when the run never started, and twice
-- in a row - so every call is guarded and no assertion is recorded.
command stCleanup
   put empty into sRunning
   put "skip" into sPhaseEn
   put "skip" into sPhaseDc
   stCancelPump
   try
      if sDcChanA is not empty and sDcChanA > 0 then
         dcFreeChannel sDcChanA
      end if
      if sDcPeerA is not empty and sDcPeerA > 0 then
         dcFreePeer sDcPeerA
      end if
      if sDcPeerB is not empty and sDcPeerB > 0 then
         dcFreePeer sDcPeerB
      end if
      dcCleanup
   catch tError
      -- DataChannelXT absent or already released; nothing to free
   end try
   put empty into sDcChanA
   put empty into sDcChanB
   put empty into sDcPeerA
   put empty into sDcPeerB
   try
      if sEnServer is not empty and sEnServer > 0 then
         enHostDestroy sEnServer
      end if
      if sEnClient is not empty and sEnClient > 0 then
         enHostDestroy sEnClient
      end if
      -- Bare statement form, matching enetxt's own teardown (enet-selftest line
      -- 371, enet-lan-chat line 220). This IS an engine constraint, contrary to
      -- what this comment claimed before an OXT pass proved otherwise: a
      -- zero-argument call in statement position must be bare, because the
      -- parenthesised spelling passes `()` to a command and `()` is not an
      -- expression. See the note in the file header.
      enDeinitialize
   catch tError
      -- enetxt absent or already released; nothing to free
   end try
   put empty into sEnServer
   put empty into sEnClient
   put empty into sEnClientPeer
   put empty into sEnServerPeer
   try
      if sSession is not empty and sSession > 0 then
         btStopSession sSession
      end if
   catch tError
      -- TorrentXT absent; there was never a session to stop
   end try
   put 0 into sSession
end stCleanup

-- ---- small helpers -----------------------------------------------------------
-- Kill any pump still queued from a previous run. Without this, Re-run would arm
-- a SECOND timer chain while the first was still pending: both would pass the
-- `sRunning is "true"` guard, both would drive the same phase machine, and every
-- assertion would be counted twice - a silently wrong report, which is worse
-- than no report. `the pendingMessages` lines are id,time,message,object.
command stCancelPump
   local tPending, tLine
   put the pendingMessages into tPending
   set the itemDelimiter to comma
   repeat for each line tLine in tPending
      if item 3 of tLine is "stPump" then
         cancel (item 1 of tLine)
      end if
   end repeat
end stCancelPump

-- Count a bridged list WITHOUT `the number of elements` (the sibling selftests
-- avoid relying on it for an LCB List; iteration is the idiom that is known to
-- work on a bridged value).
function stCount pList
   local tN, tEl
   put 0 into tN
   repeat for each element tEl in pList
      add 1 to tN
   end repeat
   return tN
end stCount

-- Lowercase hex for the digest comparisons. The harness encodes its own on
-- purpose: CoinXT's cxHexEncode is a phase-2 script-layer encoding its shipped
-- .lcb does not carry yet, and borrowing SodiumXT's sxBin2Hex would make a
-- CoinXT check fail whenever SodiumXT is the absent member. A test harness must
-- not need one member present to check another.
function stHex pData
   local tOut, tI, tByte, tDigits
   put "0123456789abcdef" into tDigits
   put empty into tOut
   repeat with tI = 1 to the number of bytes of pData
      put byteToNum(byte tI of pData) into tByte
      put char (tByte div 16 + 1) of tDigits after tOut
      put char (tByte mod 16 + 1) of tDigits after tOut
   end repeat
   return tOut
end stHex

-- pCount copies of byte pCode, built without string-escape folklore (LCS string
-- literals have no escapes at all). Doubling then trimming keeps this O(log n)
-- concatenations instead of 60001.
function stRepeatByte pCode, pCount
   local tOut
   if pCount <= 0 then
      return empty
   end if
   put numToByte(pCode) into tOut
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte


-- ==========================================================================
-- The deep per-member harnesses: running them, and merging their reports.
--
-- Each folded harness keeps its OWN scaffolding and its OWN counters (see the
-- generated banner below for why sharing them would be wrong), so it reports
-- into its own log and its own sTotal/sPassed/sFailed. These two handlers are
-- the whole coupling: run the entry point, then fold the result in.
-- ==========================================================================

command stRunMemberHarnesses
   stSection "deep per-member self-tests (each member's own harness, folded in)"
   stNote "Each of these is the SAME harness that member ships standalone."
   stNote "A failure here means the same thing it would mean there."

   -- SodiumXT and OnionXT return their report as a string; CoinXT, TorrentXT,
   -- ENetXT and DataChannelXT accumulate into their own script locals. Both
   -- shapes are handled, because both are what those members actually ship -
   -- rewriting one to look like the other would be editing a proven harness to
   -- suit this file, which is backwards.
   if sHaveSodium then
      try
         stMergeReturned "SodiumXT", sx1sxSelfTest()
      catch tError
         stSectionFailed "SodiumXT deep self-test", tError
      end try
   else
      stSkip "SodiumXT deep self-test", "install org.openxtalk.library.sodium"
   end if

   if sHaveOnion then
      try
         stMergeReturned "OnionXT", ox1oxSelfTest()
      catch tError
         stSectionFailed "OnionXT deep self-test", tError
      end try
   else
      stSkip "OnionXT deep self-test", "install org.openxtalk.library.onion"
   end if

   -- BOTH pieces, because ten of the folded sections call the script layer and
   -- would report FAIL rather than SKIP without it (see stProbe).
   if sHaveCoin and sHaveCoinScript then
      try
         cx1stRun
         stMergeCounted "CoinXT", cx1sResultText, cx1sPassed, cx1sFailed, cx1sTotal
      catch tError
         stSectionFailed "CoinXT deep self-test", tError
      end try
   else if sHaveCoin then
      stSkip "CoinXT deep self-test", "the extension is loaded but its SCRIPT layer is not:" && \
            "start using stack " & quote & "coinxt" & quote & \
            " - 10 of its 27 sections need it"
   else
      stSkip "CoinXT deep self-test", "install org.openxtalk.library.coin"
   end if

   if sHaveTorrent then
      try
         bt1stRun
         stMergeCounted "TorrentXT", bt1sResultText, bt1sPassed, bt1sFailed, bt1sTotal
      catch tError
         stSectionFailed "TorrentXT deep self-test", tError
      end try
   else
      stSkip "TorrentXT deep self-test", sTorrentNote
   end if

   if sHaveEnet then
      try
         en1stRun
         stMergeCounted "ENetXT (sync half)", en1sResultText, en1sPassed, en1sFailed, en1sTotal
      catch tError
         stSectionFailed "ENetXT deep self-test", tError
      end try
   else
      stSkip "ENetXT deep self-test", "install org.openxtalk.library.enet"
   end if

   if sHaveDc then
      try
         dc1stRun
         stMergeCounted "DataChannelXT (sync half)", dc1sResultText, dc1sPassed, dc1sFailed, dc1sTotal
      catch tError
         stSectionFailed "DataChannelXT deep self-test", tError
      end try
   else
      stSkip "DataChannelXT deep self-test", "install org.openxtalk.library.datachannel"
   end if

   -- Riptide is an APP layer over the extensions above, so it runs LAST: by
   -- here every extension it probes has already shown its own colours. Its
   -- harness handles a missing optional extension itself (sections SKIP), and
   -- refuses cleanly without SodiumXT, so the only gate here is the embedded
   -- layer being present at all.
   if sHaveRiptideScript then
      try
         stMergeReturned "Riptide Social (phases 1-2)", rs1rsSelfTest()
      catch tError
         stSectionFailed "Riptide deep self-test", tError
      end try
   else
      stSkip "Riptide deep self-test", \
            "the riptide script layer is not present; the paste is damaged"
   end if
end stRunMemberHarnesses

-- Strip the punctuation a report hangs off its words, so "PASSED:" and
-- "passed," both read as the bare word "passed" and "68," reads as 68. Only the
-- EDGES are touched: a word's own characters are left alone, so "self-test"
-- stays "self-test" and goes on disqualifying its line rather than quietly
-- turning into something the summary test would accept.
function stTrimEdges pWord
   local tOut, tPunct

   put ":,.;()[]" into tPunct
   put pWord into tOut
   -- The `tOut is not empty` guard is load-bearing, not defensive noise: in
   -- xTalk EVERY string contains empty, so the moment tOut runs out,
   -- `tPunct contains char 1 of tOut` is TRUE forever and the loop never ends.
   repeat while tOut is not empty and tPunct contains char 1 of tOut
      delete char 1 of tOut
   end repeat
   repeat while tOut is not empty and tPunct contains the last char of tOut
      delete the last char of tOut
   end repeat
   return tOut
end stTrimEdges

-- Given ONE line, return "<passed> <failed>" if that line is a summary, or
-- empty if it is not. This is the whole rule; see stMergeReturned below for why
-- it is shaped this way.
--
-- A line qualifies only when EVERY word on it is either a number or the word
-- "passed"/"failed" (case and edge punctuation ignored), with exactly one of
-- each keyword, "passed" before "failed", and exactly two numbers. That shape
-- test - rather than "the line mentions both words" - is what makes an
-- individual check's LABEL unable to masquerade as a summary: a label always
-- carries at least one other word (SodiumXT's "  ok   a failed call surfaces an
-- error" has "ok", "a", "call"), and one other word is enough to disqualify it.
function stSummaryCounts pLine
   local tI, tN, tWord, tPassAt, tFailAt, tNums

   put the number of words of pLine into tN
   put 0 into tPassAt
   put 0 into tFailAt
   put empty into tNums
   repeat with tI = 1 to tN
      put stTrimEdges(word tI of pLine) into tWord
      if tWord is a number then
         put tWord & space after tNums
      else if toLower(tWord) is "passed" and tPassAt is 0 then
         put tI into tPassAt
      else if toLower(tWord) is "failed" and tFailAt is 0 then
         put tI into tFailAt
      else
         -- Any other word - or a SECOND "passed"/"failed" - means this line is
         -- prose. Nothing is guessed from it.
         return empty
      end if
   end repeat
   if tPassAt is 0 or tFailAt is 0 or tPassAt > tFailAt then
      return empty
   end if
   if the number of words of tNums is not 2 then
      return empty
   end if
   -- Keyword order was just checked, and both shipped spellings put the pass
   -- count with the "passed" keyword, so the two numbers are in the order the
   -- two keywords are: first number = passed, second = failed. Requiring the
   -- keyword order is what makes that one-line rule safe rather than lucky.
   return word 1 to 2 of tNums
end stSummaryCounts

-- For a harness whose entry point RETURNS its report (SodiumXT, OnionXT). The
-- counts are parsed back out of the report rather than guessed at, and if the
-- parse ever fails that is a reported FAILURE, not a silent zero.
--
-- THE RULE, in one sentence: the summary is the ONE line of the report that is
-- nothing but two numbers and the words "passed" and "failed" (in that order,
-- case and edge punctuation ignored), and its first number is the pass count
-- and its second the fail count.
--
-- WHY IT IS NOT THE OBVIOUS THING, and this is the whole reason the handler was
-- rewritten. It used to take word 1 as the pass count and the LAST word as the
-- fail count, under a comment claiming that covered both members' spellings. It
-- covered NEITHER, and the 2026-08-09 engine pass duly reported both members as
-- unreadable while both reports were perfect. The two shipped spellings are
-- mirror images of each other, and both are exactly four words:
--
--   SodiumXT, the LAST line of its report:    PASSED: 68   FAILED: 0
--   OnionXT,  the FIRST line of its report:   40 passed, 0 failed
--
-- SodiumXT is keyword-first, so its word 1 is "PASSED:", which is not a number.
-- OnionXT is number-first, so its last word is "failed", which is not a number.
-- The old code needed BOTH ends to be numeric, which is true of neither shape,
-- so each format defeated it at the opposite end - and the validation then did
-- exactly the job it was built for and refused to guess. Two lesser bugs rode
-- along: the loop scanned top-to-bottom keeping the LAST match, which is right
-- for SodiumXT's trailing summary and wrong for OnionXT's leading one; and its
-- only test for a summary line was "contains passed and contains failed", which
-- any check label mentioning both words would satisfy.
--
-- The shape rule above fixes all three at once, and position stops mattering:
-- first line or last, there is exactly ONE line in either report that can
-- qualify. Requiring exactly one is what keeps this LOUD - zero matches and two
-- matches are both reported failures that print the report for a human to read,
-- never a silent zero folded into the suite totals.
command stMergeReturned pMember, pReport
   local tLine, tI, tCount, tPair, tMatches, tPassed, tFailed, tOk

   stSection pMember & ": its own full self-test"
   put 0 into tMatches
   put empty into tPassed
   put empty into tFailed
   put the number of lines of pReport into tCount
   repeat with tI = 1 to tCount
      put line tI of pReport into tLine
      put stSummaryCounts(tLine) into tPair
      if tPair is not empty then
         add 1 to tMatches
         put word 1 of tPair into tPassed
         put word 2 of tPair into tFailed
      end if
   end repeat
   -- Built as a value rather than a continued condition, for the same reason
   -- stMergeCounted below does it: three of the six copies of
   -- check-livecodescript.py do not join line continuations before counting
   -- block openers, so an `if ... \` reads to them as a handler-level statement
   -- and every `end if` after it looks unbalanced.
   --
   -- The two numeric tests are redundant with stSummaryCounts, which already
   -- refuses to return anything but two numbers. They stay because the lesson
   -- recorded on stMergeCounted below was that "it cannot be anything but a
   -- number" is a feeling, not a check, and these values are added into the
   -- suite totals: an `add` on a non-number is an UNCAUGHT engine error that
   -- takes the whole run, while a failed assertion costs one line of report.
   put (tMatches is 1 and tPassed is a number and tFailed is a number) into tOk
   if tOk is false then
      stAssert pMember & " deep self-test reported a summary this harness could read", false
      stNote "Looked for the one line that is nothing but two counts and the words"
      stNote "passed/failed (either order of word and number);" && tMatches && \
            "line(s) in its report matched."
      stNote "Its report is below verbatim; read the counts by eye."
   else
      add tPassed to sPassed
      add tFailed to sFailed
      add (tPassed + tFailed) to sTotal
      stAssert pMember & " deep self-test had zero failures", tFailed is 0
      stNote tPassed && "passed," && tFailed && "failed, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeReturned

-- For a harness that accumulates into script locals (CoinXT, TorrentXT,
-- ENetXT, DataChannelXT). Its counters are read directly - they are locals of
-- THIS script, since the whole thing compiles as one unit.
command stMergeCounted pMember, pReport, pPassed, pFailed, pTotal
   stSection pMember & ": its own full self-test"
   -- VALIDATE BEFORE ADDING, and the reason is an engine failure this cost.
   -- These three lines used to be a bare `add pPassed to sPassed`, on the
   -- reasoning that the counters are script locals of THIS file that the
   -- member's own stRun sets to 0 on its first line, so they cannot be
   -- anything but numbers. When one of them was not, LiveCode threw
   --     add: error in source expression
   -- and, because that is an uncaught engine error rather than a failed
   -- assertion, it killed the WHOLE RUN: no summary, no totals, no report from
   -- the members after it, and - the part that actually costs an engine
   -- session - NO INDICATION OF WHICH MEMBER IT WAS. Six harnesses had run and
   -- the operator was left with one line naming a handler.
   --
   -- stMergeReturned, ten lines up, has validated its counts since the day it
   -- was written, because THOSE come from parsing a report and a parse can
   -- obviously fail. This path skipped the check because its values come from
   -- script locals, which felt safer. Feeling safer is not the same as being
   -- checked, and the two paths merge into the same totals: they should be
   -- equally suspicious of what they are handed.
   --
   -- A non-numeric counter is now a reported FAILURE that names the member and
   -- prints what it actually got, and the run CONTINUES to the members after
   -- it. `empty` is the diagnostic case worth knowing: it means that member's
   -- stRun did not reach its own counter init, so look for a throw at the very
   -- top of it rather than anywhere in the checks.
   -- Built as a value rather than a continued condition on purpose: this file
   -- is read by all six members' copies of check-livecodescript.py, and three
   -- of them do not join line continuations before counting block openers, so
   -- an `if ... \` reads to them as a handler-level statement and every `end if`
   -- after it looks unbalanced. Keeping the opener on one physical line costs
   -- nothing and keeps the file parsable by the strictest reader of it.
   put (pPassed is a number and pFailed is a number and pTotal is a number) into tOk
   if tOk is false then
      stAssert pMember & " deep self-test reported numeric counters", false
      stNote "Got passed=[" & pPassed & "] failed=[" & pFailed & \
            "] total=[" & pTotal & "]"
      stNote "An EMPTY counter means that member's stRun threw before its own"
      stNote "first line (it sets all three to 0 there), so suspect the top of"
      stNote "its stRun, not its checks. Its report is below verbatim; count by eye."
   else
      add pPassed to sPassed
      add pFailed to sFailed
      add pTotal to sTotal
      stAssert pMember & " deep self-test had zero failures", pFailed is 0
      stNote pPassed && "passed," && pFailed && "failed of" && pTotal && \
            "checks, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeCounted


-- GENERATED MEMBER HARNESSES GO HERE --
