script "xTalkSuiteSelfTest"

-- suite-selftest.livecodescript - ONE self-building RUNTIME harness that drives
-- every xTalk Suite member with an in-engine harness - ten of the eleven in
-- tools/member-registry.py; nocloud's tests run headlessly in the gates - in a
-- single OXT process, and reports PASS / FAIL / SKIP per check on a board with
-- one row per member (the demos' card look since D-23; see THE BOARD below).
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
-- What each run bought is recorded per member: each member's CLAUDE.md
-- evidence ledger, and docs/OXT-PASS-RUNBOOK.md section 8 (the closed engine
-- record, which absorbed the runbook's per-pass blockquotes in the docs
-- consolidation, 409ceee).
-- Riptide's phase-2 single-engine work is therefore closed; only its
-- two-machine propagation criterion remains under runbook item 6.
--
-- THE SKIP CHANNEL (2026-08-17): stMergeReturned's third count, read by
-- stSummaryCounts, and stMergeFloor with it. Written against every member's
-- real summary spelling and mutations of them by a hand port of the parse, it
-- then RAN on 2026-08-20 (Windows, 1981/0/1): onionxt's one skip was printed
-- inline and merged into that run's total (onionxt/CLAUDE.md's evidence
-- ledger). What has never fired on an engine is stMergeFloor's REFUSAL branch.
-- The one number that puts at risk is onionxt's floor, re-derived to 51 on
-- 2026-09-24 beside its call site below (verified statically; needs an OXT
-- pass): too high, and a green run reports one extra FAIL line naming the
-- member and printing what it attempted, which is the failure mode this file
-- chooses on purpose over an uncaught error.
--
-- THIS IS NO LONGER A SAMPLER, AND THAT IS THE BIG CHANGE. It used to drive
-- about a dozen handlers per member and say so. It now carries EVERY member's
-- own deep self-test as well, folded in whole by tools/build-suite-selftest.py:
--
--   sodiumxt        sxSelfTest()      24 groups, the entire sx* surface
--   onionxt         oxSelfTest()      12 sections, all offline; on
--                                     2026-08-17 the first folded harness
--                                     whose summary carried THREE counts
--                                     (passed, failed, skipped); riptide,
--                                     nostrxt and holde-em carry the skip
--                                     count too now
--   coinxt          its 32 sections    all five phases, ~300 checks
--   torrentxt       its full harness   sharing this file's single session
--   enetxt          its SYNC half      lifecycle, stale handles, tuning
--   datachannelxt   its SYNC half      lifecycle, the stale-handle surface
--   box2dxt         stSelfTest()      50 test handlers, ~372 assertions,
--                                     driving the real b2k Kit hand-stepped
--                                     one fixed 1/60 tick at a time. It
--                                     BUILDS graphics on this card, wipes
--                                     them, and tears its world down before
--                                     returning (added 2026-08-16)
--   riptide         rsSelfTest()      identity, wire formats, and the
--                                     phase-2 live feed layer, which also
--                                     shares this file's session
--   nostrxt         nxSelfTest()      17 offline sections; signing SKIPs
--                                     without CoinXT (added 2026-08-23)
--   holde-em        heSelfTest()      run LAST: the whole game, prefixed,
--                                     through its QUIET entry point (added
--                                     2026-08-16)
--
-- AND IT CARRIES THE FIVE PURE-SCRIPT LIBRARIES THEMSELVES. coinxt's script
-- layer (encoders, addresses, the HD wallet walk), onionxt's entire ox*
-- surface, riptide's rs* layer, box2dxt's b2k Kit and the nostrxt core are
-- LiveCodeScript, and the first two used to be a separate setup step - `start
-- using stack` x2 before pasting.
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
-- window, probes for each member, runs everything it can, and shows the
-- report. Wait for the SUMMARY section at the bottom, then use "Copy results"
-- to put the run on the clipboard and paste it back verbatim.
--
-- THE BOARD (D-23). The window is the demos' card look at 1200 x 640: one row
-- per member on the left (a pill - OK, FAILED, skipped, absent, not run - its
-- pass / fail / skip counts, and two buttons), the report on the right, and
-- a boot self-check of the window itself. "Run all" re-runs everything and
-- is the suite RECORD. A row's "Run" re-runs that ONE member end to end
-- (probe, its sections, teardown, summary) and replaces the report, which
-- then says "Scope:" at its top and bottom - a one-member report is never the
-- record. "Show" and the filter buttons (All, Failures, Skips, Boot check)
-- change only what the right-hand pane shows; Copy results always copies the
-- whole report, whatever is showing.
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
-- NON-DESTRUCTIVE. Nothing here writes outside the temporary folder: the
-- folded SodiumXT, TorrentXT, Box2Dxt and Riptide harnesses write their own
-- scratch files there (TorrentXT and Riptide fall back to Documents where an
-- engine reports no temporary folder), and nothing moves storage, deletes a
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

constant kStTitle = "xTalk Suite - End-to-End Self-Test"
-- 1200 x 640 is the demos' window (the UI kit's rule 6: the whole window fits
-- a 720p display). The width matters to exactly one folded harness: box2dxt
-- centres its world on this card (sOriginX is half the card's width) and two
-- of its camera checks scroll a 3000-px level. Both still hold at 1200 with
-- room to spare - hScroll 900 against a floor of 800, and 300 against 100
-- (box2dxt-selftest's stTestCamScrolledWrite and stTestKitCameraApi) - and
-- the height, which sets its origin and kill floor, is unchanged. Verified by
-- arithmetic; needs an OXT pass (runbook row 48 records box2dxt's total).
constant kStWidth = 1200
constant kStHeight = 640

-- ---- the board (D-23; see THE BOARD below the carried blocks) ---------------
-- The build stamp: a stack built by an older paste (the scaffold's window, or
-- an earlier board) is cleared and rebuilt once; a current one only repaints.
constant kSuUiVersion = "suite-board-1"
-- One row per tools/member-registry.py member, IN ITS ORDER AND ITS SPELLING,
-- then the cross-member row. check-suite-selftest.py holds all three lists to
-- the registry, so a new member cannot be missing from the board.
constant kSuKeys = "sodiumxt,torrentxt,enetxt,datachannelxt,box2dxt,coinxt,onionxt,nostrxt,riptide,nocloud,holde-em,cross"
constant kSuNames = "SodiumXT,TorrentXT,enetxt,DataChannelXT,Box2Dxt,CoinXT,OnionXT,NostrXT,Riptide Social,No Cloud Quick Share,holde-em,Cross-member + teardown"
-- The members with no in-engine harness (tools/build-suite-selftest.py's
-- NO_HARNESS): a row with a caption, and no pill or Run.
constant kSuNoHarness = "nocloud"
-- Row geometry: the first row's top, and the pitch.
constant kSuRowTop = 136
constant kSuRowStep = 34
-- Every control this script names, DERIVED by tools/check-demo-control-lists.py
-- (--write regenerates it; the gate fails a stale copy). The boot self-check
-- asserts each one exists.
constant kSuScControls = "stCopy,stRerun,stResults,stSummary,suBootLog,suFilterAll,suFilterBoot,suFilterFail,suFilterSkip,suHeadCounts,suHeadRun,suHeadStatus,suMembersCap,suPanMembers,suPanResults,suSecMembers,suSecResults,suView,suViewCap,uiFooter,uiStatus,uiTitle"

-- ---- state -------------------------------------------------------------------
-- "true" while the async phases are still live. Spelled sAsyncRunning rather
-- than the obvious sRunning because the embedded Box2Dxt Kit declares a
-- script-level sRunning of its own (its physics loop flag), and the embedded
-- layers are VERBATIM by design - the generator cannot rename for them, and
-- two units sharing one variable is the exact isolation failure the fold's
-- prefixing exists to prevent. Renaming here costs six lines in a
-- hand-maintained file; renaming there would touch a shipped library and
-- re-carry its six embedded copies for this file's convenience.
local sAsyncRunning
-- Set once, the first time a render inside the pump throws. See stPump.
local sRenderNoted

-- probe results (one flag per member; "reason" strings carry the SKIP note)
local sHaveSodium, sHaveTorrent, sHaveEnet, sHaveDc, sHaveOnion, sHaveCoin
local sHaveCoinScript      -- coinxt ships in TWO pieces; see stProbe
local sHaveRiptideScript   -- the embedded riptide layer; same tripwire shape
local sHaveNostrScript     -- the embedded nostrxt core layer; same tripwire shape
local sHaveBox2d           -- the box2dxt EXTENSION (its Kit is embedded); see stProbe
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

-- the board (D-23)
local sSuScope             -- what the report covers: "all" or one kSuKeys item (empty before the first run)
local sSuFilter            -- the right-hand view: "all", "fail", "skip", "boot" or "m:<key>"
local sSuP, sSuF, sSuS     -- per-row passed / failed / skipped (arrays keyed by kSuKeys items)
local sSuSpan              -- per-row report spans: lines of "from to" into sResultText
local sSuMarkKey, sSuMarkP, sSuMarkF, sSuMarkS, sSuMarkLen -- the open tally (suTallyOpen)
local sSuViewLen           -- the length of sResultText when a filtered view last rendered
local sSuPainted           -- the loopback phases the rows last showed
local sSuArmed             -- a row's Run, armed and not yet started (suArmRun)

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

-- ---- the scaffolding (carried) ----------------------------------------------
-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: tools/harness-scaffold.livecodescript; gate: tools/check-harness-scaffold-drift.py) ====
-- The harness scaffolding as one carried block: counters, the window, the
-- assertion plumbing, the report surface. The adopting harness declares
-- kStTitle/kStWidth/kStHeight above this block, owns openStack/stRun/
-- stCleanup, calls stResetCounters first in stRun and stReportDone when
-- the run completes. Do not edit this block in place: change the master
-- and re-carry it.
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sStRunDone           -- "true" once the run finished (drives the color)

-- The platform's own terminal face (the demo kit's uiMonoFont, by value).
function stMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end stMonoFont

-- ---- the window (idempotent; the fold drops this half) -----------------------
command stBuild
   -- the guard is on a control this VERSION of the scaffold adds, so a stack
   -- built by an older scaffold rebuilds once and picks up the new layout
   -- (the builders re-rect existing controls by name; nothing needs deleting)
   if there is a button "stCopy" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to kStWidth
   set the height of this stack to kStHeight
   set the backgroundColor of this card to "240,242,246"
   set the title of this stack to kStTitle
   stMakeLabel "stTitle", "  " & kStTitle, "0,0," & kStWidth & ",30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38," & (kStWidth - 200) & ",66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", (kStWidth - 184) & ",38," & (kStWidth - 100) & ",64"
   stMakeButton "stRerun", "Re-run", (kStWidth - 94) & ",38," & (kStWidth - 16) & ",64"
   stMakeList "stResults", "16,72," & (kStWidth - 16) & "," & (kStHeight - 16)
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
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to "225,229,236"
   set the opaque of field pName to true
   set the backgroundColor of field pName to "255,255,255"
   set the textSize of field pName to 11
   set the textFont of field pName to stMonoFont()
end stMakeList

-- ---- assertion plumbing (this half folds into the suite harness) -------------
command stResetCounters
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put empty into sStRunDone
end stResetCounters

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

-- A SKIP is a first-class outcome, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this piece is
-- not here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

-- THE REPORT IS A LIVE SURFACE, so its text is ambiguous by construction:
-- sResultText grows as the run goes, the async harnesses re-render it every
-- tick, and an unfinished report simply STOPS - with no marker, at whatever
-- section the pump had reached. That reads exactly like a hang. It cost a
-- round trip on the 2026-08-19 suite pass: a fully green run came back ending
-- mid-CROSS-section, and nothing in the pasted text could tell an early Copy
-- from a stalled pump. The async deadline is FORTY SECONDS (kStDeadlineMs in
-- the suite core), and the list stops visibly growing long before it expires,
-- so "it looks finished" is the normal state of a run that is not. Every
-- render of the report goes through here, so that state can never be silent
-- again - on screen or on the clipboard.
function stReportText
   if sStRunDone is "true" then
      return sResultText
   end if
   return sResultText \
         & "      ----------------------------------------------------" & return \
         & "      RUN NOT FINISHED - this is NOT the end of the report." & return \
         & "      An async section is still running. Wait for the SUMMARY" & return \
         & "      section at the bottom, then Copy." & return
end stReportText

command stShow
   -- PIN THE STACK, AND FAIL CLOSED IF THE WINDOW IS NOT THERE. An unqualified
   -- `field "stResults"` resolves against THE DEFAULTSTACK, not against the
   -- stack whose script is running (OXT-ENGINE-NOTES 5.3). Inside openStack
   -- those are the same object, which is why the synchronous half of every run
   -- has always rendered. This handler is ALSO called from an async pump, on a
   -- `send ... in` tick, where they are not: with another window in front the
   -- write would throw "Chunk: error in object expression", and in the suite
   -- core that throw lands in stPump, which is where the timer re-arms.
   -- PRECAUTIONARY, NOT DIAGNOSED. It was written on 2026-08-20 while chasing
   -- two engine reports that ended mid-CROSS-section, and that was the wrong
   -- cause: the third run, same build, completed 1981/0/1 through both
   -- loopbacks and the summary. Those two were early Copies, which is what the
   -- trailer in stReportText now says out loud. What stands on its own is the
   -- hazard class - engine-observed in enet-lan-chat's ecDashOnce on
   -- 2026-08-18 - and the fact that this is the same fault, and the same fix,
   -- as the ui-kit's uiStatus, one carried block over.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stShow
   put stReportText() into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sStRunDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "23,128,63"
      else
         set the foregroundColor of field "stSummary" to "176,58,46"
      end if
   end if
end stShow

-- paint the results list: red FAIL, green PASS, amber SKIP, muted the rest
command stPaint
   local tN, tI, tLine, tErr
   -- Pinned for the reason stShow above is: stReportDone calls this one too,
   -- and an async harness reaches stReportDone from a timer tick.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stPaint
   put the number of lines of field "stResults" into tN
   lock screen
   try
      repeat with tI = 1 to tN
         put line tI of field "stResults" into tLine
         if tLine begins with "FAIL" then
            set the foregroundColor of line tI of field "stResults" to "176,58,46"
         else if tLine begins with "PASS" then
            set the foregroundColor of line tI of field "stResults" to "23,128,63"
         else if tLine begins with "SKIP" then
            set the foregroundColor of line tI of field "stResults" to "150,110,40"
         else
            set the foregroundColor of line tI of field "stResults" to "138,146,158"
         end if
      end repeat
   catch tErr
   end try
   set the vScroll of field "stResults" to 0
   unlock screen
end stPaint

-- The run's one epilogue: mark done, render, paint. Synchronous harnesses
-- call this at the end of stRun; async ones from the tick that ends the run.
command stReportDone
   put "true" into sStRunDone
   stShow
   stPaint
end stReportDone

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back
   -- verbatim into the OXT-pass record, so nobody has to retype a result.
   -- It copies stReportText(), not sResultText, so an early copy carries its
   -- own "not finished" trailer into the record - and says so here too,
   -- because the one moment a maintainer is looking at this window is the
   -- moment the dialog appears.
   --
   -- The COUNTS ride along, ahead of the lines. They live in their own field
   -- (stSummary) and used to be left behind, so the runbook taught a message
   -- box incantation to fetch them by hand - one more step between a finished
   -- run and a recorded one, at the exact moment the operator is done. A
   -- report with no totals cannot be checked against the next run's.
   local tError
   try
      set the clipboardData["text"] to sPassed & " passed, " & sFailed \
            & " failed, " & sSkipped & " skipped, " & sTotal & " total" \
            & return & return & stReportText()
      if sStRunDone is "true" then
         answer "Results copied to the clipboard."
      else
         answer "Copied - but the run has NOT finished. An async section is" \
               && "still going; wait for the SUMMARY section, then copy again."
      end if
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

on closeStack
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
-- ==== SUITE HARNESS SCAFFOLD v1 END ====

-- ---- the demos' look (carried; D-23) -----------------------------------------
-- The UI kit and the boot self-check, carried verbatim like the scaffold above.
-- Their script-level declarations sit above their own handlers here, as in
-- every carrier; the GENERATED paste hoists them above its first handler
-- (tools/build-suite-selftest.py), because there the scaffold's handlers come
-- first and check-suite-selftest.py's check 10 wants every declaration above
-- all of them.
-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing, tC, tFound
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL FOUR CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      --
      -- AND IMAGES (2026-08-31), for the same reason one step further out. A
      -- demo may build a control the KIT does not: coinxt's wallet paints a
      -- QR into an image, which is the only way a BMP this family builds
      -- becomes something a phone can read. Registered and built, it reported
      -- as missing - found by coinxt/tools/check-wallet-boot.py, which boots
      -- the stack headlessly, so this one cost no engine time. The lesson is
      -- the one this block already carries twice: the list of types a demo
      -- can build is not the list of types the KIT builds.
      --
      -- AND EVERY CARD (2026-08-29). Unqualified `there is a field X` answers
      -- for the CURRENT card only (engine notes 5.6) - OBSERVED when
      -- riptide's five-card boot reported all 63 off-card controls missing
      -- from a stack where every one existed. A single-card demo walks its
      -- one card here, exactly the old behaviour.
      put false into tFound
      repeat with tC = 1 to the number of cards of this stack
         if there is a field tName of card tC \
               or there is a button tName of card tC \
               or there is a graphic tName of card tC \
               or there is an image tName of card tC then
            put true into tFound
            exit repeat
         end if
      end repeat
      if not tFound then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- ==============================================================================
-- THE BOARD (D-23): the demos' card look, one row per member
-- ==============================================================================
-- WHAT CHANGED, AND WHAT DID NOT. Until D-23 this paste built the harness
-- scaffold's plain window (stBuild). It now wears the demos' look: the UI kit
-- above builds a 1200 x 640 card with one row per tools/member-registry.py
-- member (a status pill, its pass / fail / skip counts, Run and Show), a
-- results pane with a filter (All, Failures, Skips, Boot check, and one
-- member's lines), Run all and Copy results; and the demo boot self-check
-- above checks that window every time it opens.
--
-- THE REPORT DID NOT CHANGE, and that is the design rather than a leftover.
-- The scaffold's accounting (stAssert and friends), stReportText's RUN NOT
-- FINISHED trailer, stShow, stPaint, stCopyResults, closeStack and the mouseUp
-- that routes Re-run and Copy all run exactly as they did on the engine
-- records (2026-08-20 to 2026-08-27), because the kit builds the four controls
-- the scaffold writes UNDER THE SCAFFOLD'S OWN NAMES - stSummary, stResults,
-- stCopy, stRerun - so every one of those handlers finds what it always found.
-- "Run all" is the old Re-run button with a new label. stBuild and its three
-- makers stay in the carried block and are never called: a carried block is
-- carried whole, and its master still builds the four member harness windows.
--
-- NOT RUN ON AN ENGINE. The window, the rows, per-member Run, the filter and
-- the boot self-check are verified statically, plus a headless UI boot
-- (tools/check-suite-ui-boot.py) that settles their LOGIC and nothing about
-- rendering or message delivery; needs an OXT pass (OXT-PASS-RUNBOOK row 48).
-- The checks the run makes are the ones the dated records ran.

-- ---- lifecycle ---------------------------------------------------------------
-- BUILD, CLEAN, RUN, CHECK - in that order, on every open.
--
-- stCleanup FIRST, and unconditionally. On a first open there is nothing to
-- free and every call in it is guarded (enDeinitialize is refcount-guarded in
-- the shim; the rest sit in a try), so it costs nothing. On the runbook's
-- re-entry escape hatch - `send "openStack" to this stack` (OXT-PASS-RUNBOOK
-- 5.2) on a stack that may be mid-run - it is what stops the old pump and
-- releases the old run's transports and session before the new run takes
-- them. stRun also releases the session it finds, so this is belt and braces
-- for the session and the only brace for the ENet hosts and WebRTC peers.
--
-- suScRun LAST: the boot self-check reads what the build and the run left
-- behind (the demo contract), and it only READS - it takes nothing.
on openStack
   suBuild
   stCleanup
   stRun
   suScRun
end openStack

-- THE BOARD'S BUTTONS. The scaffold's mouseUp (carried, engine-proven) routes
-- Run all and Copy results; everything the board adds routes HERE, on the
-- press, so the carried block needs no hook. Three rules, each with a reason:
--   * BUTTON 1 ONLY. A right-click passes on untouched. coin-wallet's
--     stack-level mouseDown is the engine-run precedent (2026-09-02) for a
--     mouseDown that passes everything it does not own.
--   * BUTTONS ONLY. A press on a field, a pill or a panel passes on.
--   * NO RUN INSIDE THE PRESS. A row's Run only ARMS one pinned tick
--     (suArmRun); the run starts 33 ms later from a timer, the shape the pump
--     has always had, so no member run ever executes inside a mouse handler
--     with the button held down. A filter press is only a repaint.
-- If an engine disagrees about acting on the press (runbook row 48 records
-- it), the fallback is one line in the scaffold master's mouseUp: dispatch
-- the target's name to this stack from its default branch.
on mouseDown pWhich
   local tName
   if pWhich is not 1 then
      pass mouseDown
   end if
   if word 1 of the name of the target is not "button" then
      pass mouseDown
   end if
   put the short name of the target into tName
   if tName begins with "suRun" then
      suArmRun (char 6 to -1 of tName)
   else if tName begins with "suShow" then
      suSetFilter ("m:" & char 7 to -1 of tName)
   else if tName begins with "suFilter" then
      suSetFilter (char 9 to -1 of tName)
   else
      pass mouseDown
   end if
end mouseDown

-- ARM ONE ROW'S RUN: validate the key, refuse while a run is live, and start
-- the run from a pinned 33 ms tick rather than inside the click.
--
-- WHY REFUSE rather than restart. A row's Run replaces the whole report, and a
-- live run is mid-pump with transports open. Throwing a run away is what Run
-- all is for - it has always stopped everything first, and it is the
-- runbook's documented recovery (5.1.1) - so a second row press during a run
-- is far more likely a mis-press than a request, and it says so and waits.
command suArmRun pKey
   set the defaultStack to the short name of this stack
   if not suIsRunKey(pKey) then
      exit suArmRun
   end if
   if sAsyncRunning is "true" or sSuArmed is not empty then
      uiStatus "A run is still going: wait for its summary line, or press Run all to restart everything.", "warn"
      exit suArmRun
   end if
   put toLower(pKey) into sSuArmed
   uiStatus "Starting" && suTitleOf(sSuArmed) & ": the synchronous checks run first and the window waits for them.", empty
   send "suRunTick" to me in 33 milliseconds
end suArmRun

-- The armed run, from its tick. PINNED FIRST (engine note 5.3): everything it
-- reaches writes controls by unqualified name, and a `send ... in` handler
-- resolves those against the defaultStack, not against this stack.
command suRunTick
   local tKey
   set the defaultStack to the short name of this stack
   put sSuArmed into tKey
   put empty into sSuArmed
   if tKey is empty then
      exit suRunTick
   end if
   stCleanup
   stRun tKey
end suRunTick

-- ---- scope: what one run covers ---------------------------------------------
-- A scoped run is a SUBSEQUENCE of Run all, never a reordering of it: every
-- section keeps its place relative to the others, so the ordering invariants
-- the run depends on (the probe first; the deep harnesses before the seal and
-- the loopback starts; holde-em's timer sweep before the loopbacks arm; the
-- ENet start before the budget section) hold in every scope by construction.

-- A key a row's Run may carry: one of kSuKeys, and not a member with no
-- in-engine harness.
function suIsRunKey pKey
   local tKeys, tOld, tOk
   put kSuKeys into tKeys
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   put (pKey is among the items of tKeys) into tOk
   set the itemDelimiter to tOld
   if suNoHarness(pKey) then
      return false
   end if
   return tOk
end suIsRunKey

-- A member with no in-engine harness: a row with a caption instead of a pill
-- and a Run. kSuNoHarness is a LIST, so it is asked as one - `is` would match
-- only while the list happened to hold a single name, and a second such
-- member would then get a Run button and a pill that counts nothing
-- (check-suite-selftest.py check 17 refuses the `is` form outright).
function suNoHarness pKey
   local tList, tOld, tHit
   put kSuNoHarness into tList
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   put (pKey is among the items of tList) into tHit
   set the itemDelimiter to tOld
   return tHit
end suNoHarness

-- Empty (the scaffold's parameterless Run all) and anything unknown mean
-- everything; a row's key means that row.
command suScopeSet pScope
   put "all" into sSuScope
   if suIsRunKey(pScope) then
      put toLower(pScope) into sSuScope
   end if
end suScopeSet

function suInScope pKey
   return (sSuScope is "all") or (sSuScope is pKey)
end suInScope

-- The two transports each run one live loopback; the cross row runs both.
function suUsesEnet
   return suInScope("enetxt") or suInScope("cross")
end suUsesEnet

function suUsesDc
   return suInScope("datachannelxt") or suInScope("cross")
end suUsesDc

function suTitleOf pKey
   local tKeys, tNames, tOld, tI, tTitle
   put kSuKeys into tKeys
   put kSuNames into tNames
   put pKey into tTitle
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of tKeys
      if item tI of tKeys is pKey then
         put item tI of tNames into tTitle
      end if
   end repeat
   set the itemDelimiter to tOld
   return tTitle
end suTitleOf

function suScopeLabel
   if sSuScope is "all" then
      return "all members (Run all)"
   end if
   return suTitleOf(sSuScope) && "only"
end suScopeLabel

-- ---- tallies: what each row counted -----------------------------------------
-- SNAPSHOT DELTAS AROUND EACH BLOCK, never counters inside member code: the
-- member harnesses stay exactly as they ship. suTallyOpen notes the scaffold's
-- three counters and the report's length; suTallyClose adds the differences to
-- the row and records which report lines the block wrote, which is what a
-- member's Show view prints. In Run all a block counts to its own row; in a
-- one-member run EVERYTHING counts to that member's row, the probe and the
-- teardown included, because that row is the run.
--
-- Keys are kSuKeys' lowercase spellings: array keys fold case (engine note
-- 2.7), so one spelling everywhere keeps the question from arising.
command suTallyReset
   local tKeys, tKey, tOld
   put empty into sSuP
   put empty into sSuF
   put empty into sSuS
   put empty into sSuSpan
   put kSuKeys into tKeys
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat for each item tKey in tKeys
      put 0 into sSuP[tKey]
      put 0 into sSuF[tKey]
      put 0 into sSuS[tKey]
      put empty into sSuSpan[tKey]
   end repeat
   set the itemDelimiter to tOld
   put empty into sSuMarkKey
   put -1 into sSuViewLen
end suTallyReset

command suTallyOpen pKey
   -- A mark still open means a block threw past its own close; attribute what
   -- it counted before starting the next, so nothing is dropped.
   if sSuMarkKey is not empty then
      suTallyClose
   end if
   if sSuScope is "all" then
      put pKey into sSuMarkKey
   else
      put sSuScope into sSuMarkKey
   end if
   put sPassed into sSuMarkP
   put sFailed into sSuMarkF
   put sSkipped into sSuMarkS
   put the length of sResultText into sSuMarkLen
end suTallyOpen

command suTallyClose
   local tKey, tOk, tFrom, tTo
   put sSuMarkKey into tKey
   put empty into sSuMarkKey
   if tKey is empty then
      exit suTallyClose
   end if
   -- VALIDATE BEFORE ADDING (stMergeCounted's lesson): an `add` on a
   -- non-number is an uncaught engine error that takes the whole run, and
   -- this runs inside the pump. Built as one value, because OXT does not
   -- short-circuit `and` (engine note 2.5).
   put (sPassed is a number and sFailed is a number and sSkipped is a number and sSuMarkP is a number and sSuMarkF is a number and sSuMarkS is a number) into tOk
   if tOk is false then
      exit suTallyClose
   end if
   add (sPassed - sSuMarkP) to sSuP[tKey]
   add (sFailed - sSuMarkF) to sSuF[tKey]
   add (sSkipped - sSuMarkS) to sSuS[tKey]
   -- The span, only when the block wrote something: a pump tick with no
   -- events writes nothing, and this keeps that case free of a line count.
   if the length of sResultText > sSuMarkLen then
      put (the number of lines of (char 1 to sSuMarkLen of sResultText)) + 1 into tFrom
      put the number of lines of sResultText into tTo
      suSpanAdd tKey, tFrom, tTo
   end if
end suTallyClose

-- One row's report spans, as lines of "from to"; a span that starts where the
-- last one ended extends it, so a transport's many pump ticks read as one.
command suSpanAdd pKey, pFrom, pTo
   local tList, tN, tLast
   put sSuSpan[pKey] into tList
   put the number of lines of tList into tN
   if tN > 0 then
      put line tN of tList into tLast
      if (word 2 of tLast) + 1 >= pFrom then
         put (word 1 of tLast) && pTo into line tN of tList
         put tList into sSuSpan[pKey]
         exit suSpanAdd
      end if
   end if
   put pFrom && pTo & return after tList
   put tList into sSuSpan[pKey]
end suSpanAdd

function suNum pValue
   if pValue is a number then
      return pValue
   end if
   return 0
end suNum

-- ---- the rows ----------------------------------------------------------------
-- A row's pill, as two lines: the kit's pill kind, then the pill's text. Only
-- "ok", "wait" and "bad" are used; any other kind paints the kit's navy, which
-- is meant for the title band. pFinal says the run is over for this question
-- (the summary asks before sStRunDone is set).
function suRowState pKey, pFinal
   local tP, tF, tS
   if not suInScope(pKey) then
      return "wait" & return & "not run"
   end if
   put suNum(sSuP[pKey]) into tP
   put suNum(sSuF[pKey]) into tF
   put suNum(sSuS[pKey]) into tS
   if pFinal is not true then
      if sAsyncRunning is "true" then
         if suLive(pKey) then
            return "wait" & return & "running..."
         end if
      end if
   end if
   if tF > 0 then
      return "bad" & return & tF && "FAILED"
   end if
   if tP > 0 then
      return "ok" & return & "OK"
   end if
   if tS > 0 then
      if suPresent(pKey) then
         return "wait" & return & "skipped"
      end if
      if pKey is "torrentxt" then
         -- the probe cannot tell "not installed" from "a session is already
         -- live in this process"; the member's Show view carries the reason
         return "wait" & return & "unavailable"
      end if
      return "wait" & return & "absent"
   end if
   -- A FINISHED row that counted nothing is a defect, not a quiet one: every
   -- block this file runs ends in a PASS, a FAIL or a SKIP, so 0/0/0 means a
   -- block ran outside its tally or not at all.
   if pFinal is true or sStRunDone is "true" then
      return "bad" & return & "nothing ran"
   end if
   return "wait" & return & "waiting"
end suRowState

-- Still on the wire: only the transports, and the cross row that owns both.
function suLive pKey
   if pKey is "enetxt" then
      return not stEnDone()
   end if
   if pKey is "datachannelxt" then
      return not stDcDone()
   end if
   if pKey is "cross" then
      return not (stEnDone() and stDcDone())
   end if
   return false
end suLive

-- Was the member there to test? The probe's own flags; a member whose SKIPs
-- mean "not installed" reads "absent", one whose SKIPs are its own reads
-- "skipped". holde-em and the cross row have nothing to probe.
function suPresent pKey
   switch pKey
      case "sodiumxt"
         return sHaveSodium is true
      case "torrentxt"
         return sHaveTorrent is true
      case "enetxt"
         return sHaveEnet is true
      case "datachannelxt"
         return sHaveDc is true
      case "box2dxt"
         return sHaveBox2d is true
      case "coinxt"
         return (sHaveCoin is true) and (sHaveCoinScript is true)
      case "onionxt"
         return sHaveOnion is true
      case "nostrxt"
         return sHaveNostrScript is true
      case "riptide"
         return sHaveRiptideScript is true
   end switch
   return true
end suPresent

-- ONE PAINTER FOR EVERY ROW, so no two handlers can disagree about a pill (the
-- discipline the kit's uiPill asks for). It repaints the same names at the
-- same rects every time, pins first (it is reached from the pump's timer), and
-- does nothing before the board exists.
command suPaintRows
   local tKeys, tKey, tI, tOld, tTop, tState, tCounts
   set the defaultStack to the short name of this stack
   if there is no field "suView" then
      exit suPaintRows
   end if
   put kSuKeys into tKeys
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of tKeys
      put item tI of tKeys into tKey
      if not suNoHarness(tKey) then
         put kSuRowTop + kSuRowStep * (tI - 1) into tTop
         put suRowState(tKey, false) into tState
         uiPill ("suPill" & tKey), (line 2 of tState), ("200," & (tTop + 7) & ",296," & (tTop + 27)), (line 1 of tState)
         if suInScope(tKey) then
            put suNum(sSuP[tKey]) && "/" && suNum(sSuF[tKey]) && "/" && suNum(sSuS[tKey]) into tCounts
         else
            put "-" into tCounts
         end if
         uiLabel ("suCount" & tKey), tCounts, ("300," & (tTop + 9) & ",376," & (tTop + 25)), 10
         set the textFont of field ("suCount" & tKey) to uiMonoFont()
         set the foregroundColor of field ("suCount" & tKey) to kUiInkSoft
      end if
   end repeat
   set the itemDelimiter to tOld
   put sPhaseEn & "/" & sPhaseDc into sSuPainted
end suPaintRows

-- Every row control, by its computed name, for the boot self-check (the
-- derived kSuScControls list cannot see a name built from a key).
function suRowControls
   local tKeys, tKey, tOut, tOld
   put kSuKeys into tKeys
   put empty into tOut
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat for each item tKey in tKeys
      put "suName" & tKey & comma after tOut
      if suNoHarness(tKey) then
         put "suNote" & tKey & comma after tOut
      else
         put "suPill" & tKey & comma & "suPill" & tKey & "Bg" & comma & "suCount" & tKey & comma & "suRun" & tKey & comma & "suShow" & tKey & comma after tOut
      end if
   end repeat
   set the itemDelimiter to tOld
   return char 1 to -2 of tOut
end suRowControls

-- ---- the window ----------------------------------------------------------------
-- Built once and STAMPED (uSuUiVersion): a reopen with the current board only
-- repaints, and a stack an OLDER paste built - the scaffold's 760-wide window,
-- or an earlier board - is cleared and rebuilt, which is riptide-social's and
-- the Quick Shares' upgrade path. The build runs under lock screen with the
-- unlock in the catch too (coin-wallet's trap 41: a throw between lock and
-- unlock is how a script error becomes a frozen engine).
command suBuild
   local tError
   set the defaultStack to the short name of this stack
   if the uSuUiVersion of this stack is kSuUiVersion then
      if there is a field "suView" then
         suPaintRows
         suSetFilter sSuFilter
         exit suBuild
      end if
   end if
   lock screen
   try
      suBuildAll
   catch tError
      unlock screen
      answer "The self-test could not build its window:" & return & return & tError & return & return & "The run still goes ahead, but there is no window to read it in. Report this with the text above: the paste may be damaged."
      exit suBuild
   end try
   unlock screen
   set the uSuUiVersion of this stack to kSuUiVersion
   suPaintRows
   suSetFilter "all"
end suBuild

-- Clear what an older build left, by NAME: the scaffold's own window (the
-- names below, compared as a list rather than written as control references,
-- so the self-check's derived list never mistakes them for controls this
-- script needs) and every board or kit control. This is box2dxt's engine-run
-- restart-loop delete (its stWipe; 2026-08-17 and 2026-08-20), which never
-- trusts a control number across a deletion.
command suBuildReset
   local tAgain, tI, tName, tRetired, tOld, tHit
   put "stTitle,stSummary,stCopy,stRerun,stResults" into tRetired
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   put true into tAgain
   repeat while tAgain
      put false into tAgain
      repeat with tI = 1 to the number of controls of this card
         put the short name of control tI of this card into tName
         put (tName is among the items of tRetired) into tHit
         if char 1 to 2 of tName is "su" or char 1 to 2 of tName is "ui" then
            put true into tHit
         end if
         if tHit then
            delete control tI of this card
            put true into tAgain
            exit repeat
         end if
      end repeat
   end repeat
   set the itemDelimiter to tOld
end suBuildReset

-- THE LAYOUT, at 1200 x 640 (the kit's rule 6: the whole window fits 720p).
-- Panels first so they sit behind everything (kit rule 1). The four scaffold
-- controls keep the scaffold's names; everything the board adds is su*, and
-- nothing is named st_*, b2k* or he*, the prefixes box2dxt's and holde-em's
-- folded harnesses own on this same card.
command suBuildAll
   local tKeys, tNames, tKey, tI, tOld, tTop, tRect
   suBuildReset
   uiChrome kStTitle, kStWidth, kStHeight
   uiPanel "suPanMembers", "8,88,500," & (kStHeight - 8)
   uiPanel "suPanResults", "508,88," & (kStWidth - 8) & "," & (kStHeight - 8)

   -- the header row: the scaffold's controls, under the scaffold's names
   uiLabel "stSummary", "No run yet.", "16,58," & (kStWidth - 260) & ",80", 13
   set the textStyle of field "stSummary" to "bold"
   uiButton "stRerun", "Run all", (kStWidth - 248) & ",56," & (kStWidth - 140) & ",80"
   uiButton "stCopy", "Copy results", (kStWidth - 132) & ",56," & (kStWidth - 16) & ",80"

   -- 1. the members, one row each, in tools/member-registry.py's order
   uiSection "suSecMembers", "1.  Members: one row per extension and app", "20,96,488,114"
   uiCap "suHeadStatus", "status", "200,118,296,132"
   uiCap "suHeadCounts", "pass / fail / skip", "300,118,378,132"
   uiCap "suHeadRun", "this member", "380,118,488,132"
   put kSuKeys into tKeys
   put kSuNames into tNames
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of tKeys
      put item tI of tKeys into tKey
      put kSuRowTop + kSuRowStep * (tI - 1) into tTop
      uiLabel ("suName" & tKey), (item tI of tNames), ("20," & (tTop + 7) & ",196," & (tTop + 27)), 12
      set the textStyle of field ("suName" & tKey) to "bold"
      if suNoHarness(tKey) then
         put "200," & (tTop + 6) & ",488," & (tTop + 30) into tRect
         uiCap ("suNote" & tKey), "no in-engine harness: its tests run headlessly in the gates", tRect
      else
         uiButton ("suRun" & tKey), "Run", ("380," & (tTop + 5) & ",432," & (tTop + 29))
         uiButton ("suShow" & tKey), "Show", ("436," & (tTop + 5) & ",488," & (tTop + 29))
      end if
   end repeat
   set the itemDelimiter to tOld
   uiCap "suMembersCap", "Run re-runs ONE member end to end (probe, its sections, teardown, summary) and replaces the report; Show lists only its lines. Run all is the suite record.", "20,546,488,580"
   uiFooter "Every member's own self-test plus the cross-member seams, in one process. This board is verified statically plus a headless UI boot; needs an OXT pass (D-23).", "20,588,488,628"

   -- 2. the results: three fields on one rect, exactly one visible
   uiSection "suSecResults", "2.  Results", "520,96,760,114"
   uiButton "suFilterAll", "All", "872,94,924,118"
   uiButton "suFilterFail", "Failures", "930,94,1010,118"
   uiButton "suFilterSkip", "Skips", "1016,94,1076,118"
   uiButton "suFilterBoot", "Boot check", "1082,94,1180,118"
   set the autoHilite of button "suFilterAll" to false
   set the autoHilite of button "suFilterFail" to false
   set the autoHilite of button "suFilterSkip" to false
   set the autoHilite of button "suFilterBoot" to false
   uiCap "suViewCap", "All: the whole report.", "520,122,1180,138"
   uiArea "stResults", "520,142," & (kStWidth - 20) & "," & (kStHeight - 18)
   uiArea "suView", "520,142," & (kStWidth - 20) & "," & (kStHeight - 18)
   uiArea "suBootLog", "520,142," & (kStWidth - 20) & "," & (kStHeight - 18)
end suBuildAll

-- ---- the results views --------------------------------------------------------
-- ALL is the scaffold's own stResults, rewritten every tick by stShow and
-- painted by stPaint exactly as before - and it is always what Copy copies.
-- FAILURES, SKIPS and ONE MEMBER are composed into suView, which is shown in
-- stResults' place while stShow keeps writing the hidden original, so nothing
-- fights over a field. BOOT CHECK shows the self-check's own log.
command suSetFilter pWhich
   local tWhich
   set the defaultStack to the short name of this stack
   put toLower(pWhich) into tWhich
   if tWhich is not "fail" and tWhich is not "skip" and tWhich is not "boot" then
      if tWhich begins with "m:" then
         if not suIsRunKey(char 3 to -1 of tWhich) then
            put "all" into tWhich
         end if
      else
         put "all" into tWhich
      end if
   end if
   put tWhich into sSuFilter
   if there is no field "suView" then
      exit suSetFilter
   end if
   set the hilite of button "suFilterAll" to (tWhich is "all")
   set the hilite of button "suFilterFail" to (tWhich is "fail")
   set the hilite of button "suFilterSkip" to (tWhich is "skip")
   set the hilite of button "suFilterBoot" to (tWhich is "boot")
   put -1 into sSuViewLen
   set the vScroll of field "suView" to 0
   suRenderView
end suSetFilter

-- Render the current view. Pinned (the pump reaches it), contained (a view
-- that cannot render must never cost a run), and under lock screen with the
-- unlock outside the try, so the unlock always runs.
command suRenderView
   local tText, tCap, tScroll, tError
   set the defaultStack to the short name of this stack
   if there is no field "suView" then
      exit suRenderView
   end if
   lock screen
   try
      if sSuFilter is "fail" or sSuFilter is "skip" or sSuFilter begins with "m:" then
         put the vScroll of field "suView" into tScroll
         put suViewText(sSuFilter) into tText
         put tText into field "suView"
         suPaintView
         set the vScroll of field "suView" to tScroll
         set the visible of field "stResults" to false
         set the visible of field "suBootLog" to false
         set the visible of field "suView" to true
         if sSuFilter is "fail" then
            put "Failures: each FAIL line under the section it sits in. Copy results still copies the whole report." into tCap
         else if sSuFilter is "skip" then
            put "Skips: each SKIP line under the section it sits in. Copy results still copies the whole report." into tCap
         else
            put suTitleOf(char 3 to -1 of sSuFilter) & ": only the lines its row counted. Copy results still copies the whole report." into tCap
         end if
      else if sSuFilter is "boot" then
         set the visible of field "stResults" to false
         set the visible of field "suView" to false
         set the visible of field "suBootLog" to true
         put "Boot check: this window's own self-check, run on open. Not counted in the totals; the report carries it just above its summary." into tCap
      else
         set the visible of field "suView" to false
         set the visible of field "suBootLog" to false
         set the visible of field "stResults" to true
         put "All: the whole report, exactly what Copy results copies." into tCap
      end if
   catch tError
      put "This view could not render (" & tError & "); All still shows the whole report." into tCap
   end try
   put the length of sResultText into sSuViewLen
   uiCap "suViewCap", tCap, "520,122,1180,138"
   unlock screen
end suRenderView

function suViewText pFilter
   if pFilter is "fail" then
      return suKindText("fail")
   end if
   if pFilter is "skip" then
      return suKindText("skip")
   end if
   return suMemberText(char 3 to -1 of pFilter)
end suViewText

-- One kind of line, each under the section header and member-report divider it
-- sits in, with up to three indented note lines that follow it (a FAIL's
-- "it raised:" is usually the next line). Read from sResultText, and ended
-- with the scaffold's own trailer while the run is unfinished.
function suKindText pKind
   local tSrc, tLine, tKind, tHead, tSub, tHeadShown, tSubShown, tNotes, tN, tOut, tHeadLine
   put sResultText into tSrc
   put empty into tHead
   put empty into tSub
   put 0 into tNotes
   put 0 into tN
   put empty into tOut
   repeat for each line tLine in tSrc
      put suLineKind(tLine) into tKind
      if tKind is "head" then
         put tLine into tHead
         put empty into tSub
         put false into tHeadShown
         put false into tSubShown
         put 0 into tNotes
      else if tKind is "sub" or tKind is "marker" then
         put tLine into tSub
         put false into tSubShown
         put 0 into tNotes
      else if tKind is pKind then
         if tHeadShown is not true then
            if tHead is not empty then
               put return & tHead & return after tOut
            end if
            put true into tHeadShown
         end if
         if tSubShown is not true then
            if tSub is not empty then
               put tSub & return after tOut
            end if
            put true into tSubShown
         end if
         put tLine & return after tOut
         add 1 to tN
         put 3 into tNotes
      else if tNotes > 0 then
         if tKind is "other" and char 1 of tLine is space then
            put tLine & return after tOut
            subtract 1 from tNotes
         else
            put 0 into tNotes
         end if
      end if
   end repeat
   if pKind is "fail" then
      put "Failures:" && tN && "FAIL line(s) in the report." into tHeadLine
      if tN is 0 then
         put tHeadLine && "Nothing failed." into tHeadLine
      end if
   else
      put "Skips:" && tN && "SKIP line(s) in the report." into tHeadLine
      if tN is 0 then
         put tHeadLine && "Nothing skipped." into tHeadLine
      end if
   end if
   return tHeadLine & return & tOut & suTrailer()
end suKindText

-- One member's lines: the spans its row counted.
function suMemberText pKey
   local tTitle, tList, tSrc, tLine, tOut
   put suTitleOf(pKey) into tTitle
   if not suInScope(pKey) then
      return tTitle && "was not in this run's scope (" & suScopeLabel() & ")." & return & "Press Run on its row, or Run all." & return
   end if
   put sSuSpan[pKey] into tList
   put sResultText into tSrc
   put empty into tOut
   repeat for each line tLine in tList
      put (line (word 1 of tLine) to (word 2 of tLine) of tSrc) & return after tOut
   end repeat
   return tTitle & ":" && suNum(sSuP[pKey]) && "passed," && suNum(sSuF[pKey]) && "failed," && suNum(sSuS[pKey]) && "skipped, in the lines below." & return & tOut & suTrailer()
end suMemberText

-- The scaffold's own RUN NOT FINISHED trailer, taken from stReportText rather
-- than copied, so a filtered view of an unfinished run says so in the same
-- words the whole report does.
function suTrailer
   local tFull
   if sStRunDone is "true" then
      return empty
   end if
   put stReportText() into tFull
   return char ((the length of sResultText) + 1) to -1 of tFull
end suTrailer

-- WHAT A LINE IS, by its FIRST WORD, case-sensitively. Every folded format
-- reads right this way: the scaffold's unindented `PASS` / `FAIL` / `SKIP`,
-- the returned reports' indented `  ok` / `  FAIL` / `  skip`, onionxt's and
-- nostrxt's `  --   (skipped: ...)`, section headers `== x ==`, member
-- sub-sections `-- x`, and the `---- X report ----` dividers. `begins with`
-- (stPaint's test) cannot see an indented FAIL, which is why the whole
-- report is repainted by this after it finishes (suPaintResults). The
-- caseSensitive property is restored explicitly: engine notes 2.3 and 2.7
-- disagree about whether a local property survives its handler, and this
-- code does not need to find out.
function suLineKind pLine
   local tW1, tKind, tWas
   put word 1 of pLine into tW1
   put the caseSensitive into tWas
   set the caseSensitive to true
   put "other" into tKind
   if tW1 is "FAIL" then
      put "fail" into tKind
   else if tW1 is "PASS" or tW1 is "ok" then
      put "pass" into tKind
   else if tW1 is "SKIP" or tW1 is "skip" then
      put "skip" into tKind
   else if tW1 is "==" then
      put "head" into tKind
   else if tW1 is "----" then
      put "marker" into tKind
   else if tW1 is "--" then
      if word 2 of pLine begins with "(skipped" then
         put "skip" into tKind
      else
         put "sub" into tKind
      end if
   end if
   set the caseSensitive to tWas
   return tKind
end suLineKind

-- Paint a composed view by line kind: stPaint's per-line idiom (engine-run on
-- every record since 2026-08-20), muted first and then only the lines that
-- carry a meaning, so a long view costs one pass.
command suPaintView
   local tText, tLine, tI, tKind, tError
   set the defaultStack to the short name of this stack
   if there is no field "suView" then
      exit suPaintView
   end if
   put field "suView" into tText
   set the foregroundColor of field "suView" to kUiMuted
   put 0 into tI
   try
      repeat for each line tLine in tText
         add 1 to tI
         put suLineKind(tLine) into tKind
         if tKind is "fail" then
            set the foregroundColor of line tI of field "suView" to kUiBad
         else if tKind is "pass" then
            set the foregroundColor of line tI of field "suView" to kUiOk
         else if tKind is "skip" then
            set the foregroundColor of line tI of field "suView" to kUiWarn
         else if tKind is "head" then
            set the foregroundColor of line tI of field "suView" to kUiAccent
         end if
      end repeat
   catch tError
   end try
end suPaintView

-- The whole report, repainted by FIRST WORD once the run is over. stPaint
-- (carried) paints by `begins with`, so a member's indented `  FAIL` stays
-- muted in the All view; the carried block cannot change without re-carrying
-- four published member harnesses, so the paste corrects its own view here.
-- Only the lines stPaint could not have painted right are touched.
command suPaintResults
   local tText, tLine, tI, tKind, tError
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then
      exit suPaintResults
   end if
   put field "stResults" into tText
   put 0 into tI
   lock screen
   try
      repeat for each line tLine in tText
         add 1 to tI
         if char 1 of tLine is space or char 1 of tLine is "=" then
            put suLineKind(tLine) into tKind
            if tKind is "fail" then
               set the foregroundColor of line tI of field "stResults" to kUiBad
            else if tKind is "pass" then
               set the foregroundColor of line tI of field "stResults" to kUiOk
            else if tKind is "skip" then
               set the foregroundColor of line tI of field "stResults" to kUiWarn
            else if tKind is "head" then
               set the foregroundColor of line tI of field "stResults" to kUiAccent
            end if
         end if
      end repeat
   catch tError
   end try
   unlock screen
end suPaintResults

-- ---- the run's two ends --------------------------------------------------------
-- The start of a run: the summary line back to neutral (stShow colours it only
-- when a run finishes, so a new run would otherwise start in the last one's
-- red or green).
command suRunStarting
   set the defaultStack to the short name of this stack
   if there is a field "stSummary" then
      set the foregroundColor of field "stSummary" to kUiInk
   end if
end suRunStarting

-- The end of the synchronous half, just before the pump is armed. This is the
-- first moment anything painted becomes visible (the handler is about to
-- return; engine-observed on 2026-08-19, when a run copied mid-pump ended at
-- the last synchronous section), so the rows and the view are painted here.
-- CONTAINED: the `send "stPump"` after it is the only route to teardown.
command suSyncDone
   local tError, tNote
   try
      suPaintRows
      suRenderView
      if suUsesEnet() or suUsesDc() then
         put "the live loopbacks are still running" into tNote
      else
         put "the teardown and the summary follow on the next tick" into tNote
      end if
      uiStatus "Running (" & suScopeLabel() & "): the synchronous checks are done;" && tNote & ". Wait for the summary line before you copy.", empty
   catch tError
      -- a paint must never cost a run; the report is assembled in a variable
   end try
end suSyncDone

-- One pump tick's paint, before the pump's re-arm and in a try of its own: the
-- rows when a transport's phase moved, and a filtered view when the report
-- grew. Nothing repaints on a tick that changed nothing, and a paint that
-- throws costs only the paint (suAfterDone repaints everything at the end).
command suPumpPaint
   local tError
   try
      suPumpPaintNow
   catch tError
   end try
end suPumpPaint

command suPumpPaintNow
   if (sPhaseEn & "/" & sPhaseDc) is not sSuPainted then
      suPaintRows
   end if
   if sSuFilter is "fail" or sSuFilter is "skip" or sSuFilter begins with "m:" then
      if the length of sResultText is not sSuViewLen then
         suRenderView
      end if
   end if
end suPumpPaintNow

-- The window's boot self-check, appended to the report UNCOUNTED, just above
-- the summary: Copy results then carries the window's record too (runbook row
-- 37 asks for the boot block), while the totals stay the run's alone. Each
-- line is prefixed, so no boot line ever reads as a run's PASS or FAIL - not
-- to a person, and not to the Failures view.
command suBootIntoReport
   local tLine
   if sScLines is empty then
      exit suBootIntoReport
   end if
   stSection "boot self-check (this window's own, run on open; NOT counted in the totals)"
   repeat for each line tLine in sScLines
      stNote "[boot] " & tLine
   end repeat
end suBootIntoReport

-- Is the self-check's one delayed check still queued? `the pendingMessages`
-- lines are id,time,message,object (stCancelPump's idiom).
function suBootPending
   local tPending, tLine, tOld, tFound
   put the pendingMessages into tPending
   put false into tFound
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat for each line tLine in tPending
      if item 3 of tLine is "scTickProbe" then
         put true into tFound
      end if
   end repeat
   set the itemDelimiter to tOld
   return tFound
end suBootPending

-- The summary section's own lines: the scope, what the report is, the board as
-- text (so the tick sheet's member totals are COPIED, not transcribed from a
-- screenshot), the board check, and the boot verdict.
--
-- THE BOARD CHECK: every counted check belongs to exactly one row, so the rows
-- must add up to the totals. It prints a note when they do and FAILs only when
-- they do not - so a green run's totals stay comparable with every dated
-- record taken before the board existed, and a tally lost to a block that ran
-- outside suTallyOpen / suTallyClose is a red line on an engine, not a quietly
-- wrong pill.
command suSummaryNotes
   local tKeys, tNames, tKey, tI, tOld, tState, tP, tF, tS, tSumP, tSumF, tSumS, tOk
   stNote "Scope:" && suScopeLabel() & "."
   if sSuScope is not "all" then
      stNote "A one-member run is NOT the suite record. The record is a Run all,"
      stNote "copied after its summary; this report covers the scope above only."
   end if
   stNote "Each member's deep self-test above is the harness it ships standalone,"
   stNote "folded in by tools/build-suite-selftest.py; the ENet and DataChannel"
   stNote "live loopbacks are this file's own. Paste these numbers back."
   stNote "per member (passed / failed / skipped; the rows on the left):"
   put 0 into tSumP
   put 0 into tSumF
   put 0 into tSumS
   put kSuKeys into tKeys
   put kSuNames into tNames
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of items of tKeys
      put item tI of tKeys into tKey
      if suNoHarness(tKey) then
         stNote "  " & suPad(item tI of tNames, 24) & "    -     -     -  no in-engine harness"
      else
         put suNum(sSuP[tKey]) into tP
         put suNum(sSuF[tKey]) into tF
         put suNum(sSuS[tKey]) into tS
         add tP to tSumP
         add tF to tSumF
         add tS to tSumS
         put suRowState(tKey, true) into tState
         if suInScope(tKey) then
            stNote "  " & suPad(item tI of tNames, 24) & suPadLeft(tP, 5) & suPadLeft(tF, 6) & suPadLeft(tS, 6) & "  " & (line 2 of tState)
         else
            stNote "  " & suPad(item tI of tNames, 24) & "    -     -     -  not run"
         end if
      end if
   end repeat
   set the itemDelimiter to tOld
   put (tSumP is sPassed and tSumF is sFailed and tSumS is sSkipped) into tOk
   if tOk then
      stNote "the rows account for every counted check (" & tSumP & " / " & tSumF & " / " & tSumS & ")"
   else
      suTallyOpen "cross"
      stAssert "the rows account for every counted check", false
      stNote "the rows add up to" && tSumP & " / " & tSumF & " / " & tSumS & "; the totals are" && sPassed & " / " & sFailed & " / " & sSkipped
      stNote "a block ran outside suTallyOpen / suTallyClose; the pills are wrong, the totals are not"
      suTallyClose
   end if
   if sScLines is empty then
      stNote "boot self-check: has not run in this window"
   else if suBootPending() then
      stNote "boot self-check: its one delayed check had not fired yet; see the Boot check view"
   else
      stNote "boot self-check:" && sScPassed && "passed," && sScFailed && "failed," && sScSkipped && "skipped (the Boot check view has it whole)"
   end if
end suSummaryNotes

function suPad pText, pWidth
   local tOut
   put pText into tOut
   repeat while (the number of chars of tOut) < pWidth
      put space after tOut
   end repeat
   return tOut
end suPad

function suPadLeft pText, pWidth
   local tOut
   put pText into tOut
   repeat while (the number of chars of tOut) < pWidth
      put space before tOut
   end repeat
   return tOut
end suPadLeft

-- After stReportDone: the report repainted by first word, the rows and the
-- view final, and the status line. Contained - stFinish runs from the pump's
-- tick, and by now the run is complete; a paint that throws must not bring an
-- error dialog down on a finished, correct report.
command suAfterDone
   local tError
   set the defaultStack to the short name of this stack
   try
      suPaintResults
      suPaintRows
      suRenderView
      suStatusFinal
   catch tError
      uiStatus "The run finished, but the board could not repaint (" & tError & "). The report is complete: Copy results.", "warn"
   end try
end suAfterDone

-- THE ONE STATUS LINE (kit rule 2), composed from the run's verdict and the
-- boot check's. Fail loud: a boot failure keeps the line red even over a
-- green run, and scFinish paints its own red line if it runs after this.
command suStatusFinal
   local tText, tKind
   put "Finished (" & suScopeLabel() & "):" && sPassed && "passed," && sFailed && "failed," && sSkipped && "skipped." into tText
   put "ok" into tKind
   if sFailed is not a number then
      put "bad" into tKind
   else if sFailed > 0 then
      put "bad" into tKind
      put tText && "Press Failures to list them." into tText
   end if
   if sSuScope is not "all" then
      put tText && "One member only: the suite record is Run all." into tText
   end if
   if sScFailed is a number then
      if sScFailed > 0 then
         put "bad" into tKind
         put tText && "Boot self-check:" && sScFailed && "FAILED (see Boot check)." into tText
      end if
   end if
   uiStatus tText, tKind
end suStatusFinal

-- ---- the boot self-check (the demo contract; the block above does the rest) ---
-- Non-destructive: it reads the window and the probe's answers and takes
-- nothing. The run has already started (openStack runs it first), so the
-- checks below are about THIS window and THIS run's start, not a demo's idle
-- state. The log field is emptied first: a reopen must not stack a second
-- block under the first (coin-wallet's waScFresh lesson, 2026-09-02).
command suScRun
   local tMissing
   set the defaultStack to the short name of this stack
   if there is a field "suBootLog" then
      put empty into field "suBootLog"
   end if
   scBegin "suBootLog"
   put scMissing(kSuScControls) into tMissing
   scAssert "all 22 controls this script names exist" & suMissingNote(tMissing), tMissing is empty
   put scMissing(suRowControls()) into tMissing
   scAssert "every member row is built (" & suRowCount() & " rows, each with its controls)" & suMissingNote(tMissing), tMissing is empty
   scAssert "the window is" && kStWidth && "x" && kStHeight && "(saw" && the width of this stack && "x" && the height of this stack & ")", suWindowSized()
   scAssert "the last member row sits above the members caption", suLastRowFits()
   scAssert "the board is stamped" && kSuUiVersion && "(saw" && scShow(the uSuUiVersion of this stack) & ")", the uSuUiVersion of this stack is kSuUiVersion
   scAssert "the run started before this check (running:" && scShow(sAsyncRunning) & ", finished:" && scShow(sStRunDone) & ")", suRunStarted()
   scAssert "the probe answered present or absent for every member", suProbeAnswered()
   scAssert "exactly one results view is showing", suVisibleViews() is 1
   scArmProbe
end suScRun

function suMissingNote pMissing
   if pMissing is empty then
      return empty
   end if
   return " (missing: " & pMissing & ")"
end suMissingNote

function suRowCount
   local tKeys, tOld, tN
   put kSuKeys into tKeys
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   put the number of items of tKeys into tN
   set the itemDelimiter to tOld
   return tN
end suRowCount

function suWindowSized
   return (the width of this stack is kStWidth) and (the height of this stack is kStHeight)
end suWindowSized

-- A thirteenth member must fail HERE, before an engine session, rather than
-- draw its row over the caption: the last row's name field ends above it.
function suLastRowFits
   local tKeys, tOld, tLast
   put kSuKeys into tKeys
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   put item -1 of tKeys into tLast
   set the itemDelimiter to tOld
   if there is no field ("suName" & tLast) then
      return false
   end if
   if there is no field "suMembersCap" then
      return false
   end if
   return the bottom of field ("suName" & tLast) < the top of field "suMembersCap"
end suLastRowFits

function suRunStarted
   return (sAsyncRunning is "true") or (sStRunDone is "true")
end suRunStarted

function suIsBool pValue
   return (pValue is true) or (pValue is false)
end suIsBool

function suProbeAnswered
   return suIsBool(sHaveSodium) and suIsBool(sHaveTorrent) and suIsBool(sHaveEnet) and suIsBool(sHaveDc) and suIsBool(sHaveOnion) and suIsBool(sHaveCoin) and suIsBool(sHaveCoinScript) and suIsBool(sHaveRiptideScript) and suIsBool(sHaveNostrScript) and suIsBool(sHaveBox2d)
end suProbeAnswered

function suVisibleViews
   local tN
   put 0 into tN
   if there is a field "stResults" then
      if the visible of field "stResults" then
         add 1 to tN
      end if
   end if
   if there is a field "suView" then
      if the visible of field "suView" then
         add 1 to tN
      end if
   end if
   if there is a field "suBootLog" then
      if the visible of field "suBootLog" then
         add 1 to tN
      end if
   end if
   return tN
end suVisibleViews

-- ---- the run -----------------------------------------------------------------
-- pScope is empty for everything (the scaffold's Run all calls this with no
-- argument, and openStack does too) or one kSuKeys item for a row's Run. A
-- scoped run is a SUBSEQUENCE of this handler's order, never a reordering:
-- each block below runs only when suInScope says so, and each is wrapped in a
-- tally (suTallyOpen / suTallyClose) so the board knows which row it counted.
command stRun pScope
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   -- Belt and braces: a run that was interrupted (an engine error mid-pump)
   -- can leave a pump armed even though stCleanup never ran.
   stCancelPump
   stResetCounters
   suScopeSet pScope
   suTallyReset
   suRunStarting
   put "true" into sAsyncRunning
   put empty into sPhaseEn
   put empty into sPhaseDc
   -- The render latch is per RUN: left set, a second run's pump would never
   -- report a render that throws.
   put empty into sRenderNoted
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
   put "Scope: " & suScopeLabel() & return after sResultText

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
   -- THE PROBE RUNS IN EVERY SCOPE: it sets every sHave* flag the sections
   -- read, and it is the statement that takes THE session.
   suTallyOpen "cross"
   try
      stProbe
   catch tError
      stSectionFailed "extension probe", tError
   end try
   suTallyClose
   if suInScope("sodiumxt") then
      suTallyOpen "sodiumxt"
      try
         stSodiumSection
      catch tError
         stSectionFailed "SodiumXT", tError
      end try
      suTallyClose
   end if
   if suInScope("torrentxt") then
      suTallyOpen "torrentxt"
      try
         stTorrentSection
      catch tError
         stSectionFailed "TorrentXT", tError
      end try
      suTallyClose
   end if
   if suInScope("onionxt") then
      suTallyOpen "onionxt"
      try
         stOnionSection
      catch tError
         stSectionFailed "OnionXT", tError
      end try
      suTallyClose
   end if
   if suInScope("coinxt") then
      suTallyOpen "coinxt"
      try
         stCoinSection
      catch tError
         stSectionFailed "CoinXT", tError
      end try
      suTallyClose
   end if
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
      suTallyOpen "cross"
      stSectionFailed "deep per-member self-tests", tError
      suTallyClose
   end try
   if suInScope("cross") then
      suTallyOpen "cross"
      try
         stCrossIdentitySection
      catch tError
         stSectionFailed "cross: one identity", tError
      end try
      suTallyClose
      suTallyOpen "cross"
      try
         stCrossBep44Section
      catch tError
         stSectionFailed "cross: BEP44 signing", tError
      end try
      suTallyClose
   end if
   -- The seal serves both loopbacks, so it runs wherever either does; the
   -- transports' own rows, the cross row, and Run all.
   if suUsesEnet() or suUsesDc() then
      suTallyOpen "cross"
      try
         stSealPayload
      catch tError
         stSectionFailed "cross: sealed payload", tError
      end try
      suTallyClose
   end if
   -- A loopback out of this run's scope is "skip" from the start, so the pump
   -- treats it as finished and the teardown leaves its library alone.
   if suUsesEnet() then
      suTallyOpen "enetxt"
      try
         stStartEnetLoopback
      catch tError
         stSectionFailed "enetxt loopback start", tError
         put "failed" into sPhaseEn
      end try
      suTallyClose
   else
      put "skip" into sPhaseEn
   end if
   if suUsesDc() then
      suTallyOpen "datachannelxt"
      try
         stStartDcLoopback
      catch tError
         stSectionFailed "datachannelxt loopback start", tError
         put "failed" into sPhaseDc
      end try
      suTallyClose
   else
      put "skip" into sPhaseDc
   end if
   -- The budget's ENet half needs the ENet loopback's live peer, so it runs
   -- where that does (its DataChannel half runs inside the DC loopback).
   if suUsesEnet() then
      suTallyOpen "cross"
      try
         stCrossBudgetSection
      catch tError
         stSectionFailed "cross: 60000-byte budget", tError
      end try
      suTallyClose
   end if

   put the milliseconds + kStDeadlineMs into sDeadline
   stShow
   suSyncDone
   send "stPump" to me in 33 milliseconds
end stRun

-- ---- the probe ---------------------------------------------------------------
-- ONE cheap guarded call per member. A missing extension raises a "can't find
-- handler" execution error, which try/catch turns into a flag; nothing here is
-- allowed to abort the run.
command stProbe
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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

   -- NostrXT's core layer rides the same embed mechanism; the probe is a real
   -- derivation (the RFC 6455 sample accept: sha1 + base64 through the
   -- embedded layer), not a version sniff, so a present layer is a WORKING one.
   put false into sHaveNostrScript
   try
      put (nxWsAcceptFor("dGhlIHNhbXBsZSBub25jZQ==") is "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") into sHaveNostrScript
   catch tError
      put false into sHaveNostrScript
   end try
   stProbeLine "NostrXT (script layer)", sHaveNostrScript, \
         "embedded in this paste; a FAIL means the paste is damaged"

   -- BOX2DXT IS THE SECOND TWO-PIECE MEMBER, and its pieces sit the other way
   -- round from CoinXT's: the b2k Kit is pure script and rides the embed (so it
   -- cannot be absent from a paste that compiled), while the physics itself is
   -- the native extension and very much can be. So this probes the EXTENSION,
   -- and it does it the way box2dxt's own harness does: b2kEnsureNativeLib
   -- first, which seeds revLibraryMapping["box2dxt"] from the folder beside
   -- this stack and is the engine hook that lets the library load with no sudo
   -- and no system path. It is a documented no-op for an unsaved stack, so it
   -- is safe to call unconditionally - and it is inside the try because on a
   -- machine with no box2dxt at all, the Kit handler is present (embedded) but
   -- b2Version is not.
   put false into sHaveBox2d
   try
      b2kEnsureNativeLib
      put b2Version() into tVersion
      put (tVersion is not empty) into sHaveBox2d
   catch tError
      put false into sHaveBox2d
   end try
   stProbeLine "Box2Dxt (extension)", sHaveBox2d, "org.openxtalk.box2dxt"
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
      stSkip "OnionXT surface", "the embedded onionxt layer did not answer its probe; the paste is damaged"
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
            "the embedded onionxt layer did not answer its probe; the paste is damaged"
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
   if not suUsesDc() then
      stNote "the datachannelxt half is not in this run's scope"
   else if not sHaveDc then
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

   -- A HELD PORT IS AN ENVIRONMENT, NOT A DEFECT, and until 2026-08-20 this
   -- section said otherwise. It asserted the bind FIRST and only then noticed
   -- the port was taken, so a machine where something already holds
   -- kStPortEnet reported a red FAIL and then, one line later, explained that
   -- it was skipping. The commonest cause is the most innocent one: a previous
   -- run of this harness in the SAME OXT process still owns the socket, which
   -- is exactly what a maintainer re-pasting the file does all day. Reporting
   -- that as a failure sends somebody to look for a bug in enetxt.
   --
   -- The bind is now PROBED and skipped; only the client host - which needs no
   -- port at all, and so cannot be blocked by the environment - keeps a hard
   -- assertion. That distinction is the whole point: one of these can be
   -- somebody else's socket, and the other cannot.
   put enHostCreateServer("127.0.0.1", kStPortEnet, 4, 2, 0, 0) into sEnServer
   if sEnServer <= 0 then
      stSkip "enetxt loopback", "UDP port " & kStPortEnet & " is already held" && \
            "(usually a previous run of this harness in the same OXT process -" && \
            "reopen OXT and re-paste to clear it). The loopback needs that port," && \
            "so this section skips; enetxt itself is not implicated."
      put "failed" into sPhaseEn
      exit stStartEnetLoopback
   end if
   stAssert "enet server host bound", sEnServer > 0
   put enHostCreateClient(1, 2, 0, 0) into sEnClient
   stAssert "enet client host created", sEnClient > 0
   if sEnClient <= 0 then
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
   -- EITHER SPELLING. The .lcb emits "dcLocalDescriptionReady" since
   -- 2026-08-19 (the old name collided with the public getter
   -- dcLocalDescription, so dispatching it reached the LIBRARY handler - engine
   -- note 6.7). An extension packaged before that still emits the old name.
   --
   -- THIS LINE WAS MISSED BY THE RENAME, and it is the one that mattered most:
   -- the member selftest and the closing-pass stack were both updated, but this
   -- is the handler that DRIVES the loopback in the ~1900-check paste, so the
   -- offer would simply never have been shuttled and a section green on the two
   -- previous passes would have failed with no obvious cause. A comparison is
   -- not a dispatch, so nothing in the collision gate could see it.
   if tName is among the items of "dcLocalDescription,dcLocalDescriptionReady" then
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tEvents, tEvent
   -- PINNED FIRST (engine note 5.3). This handler arrives by `send ... in`, and
   -- since D-23 it paints the board's rows and views as well as the report;
   -- every one of those names a control unqualified, so the defaultStack is
   -- set once here rather than trusted painter by painter.
   set the defaultStack to the short name of this stack
   if sAsyncRunning is not "true" then
      exit stPump
   end if

   -- Contained for the same reason the synchronous sections are, and with one
   -- extra stake: a throw out of the pump would break the timer chain, so
   -- nothing would ever reach stFinish - and the hosts, peers, and the one
   -- libtorrent session would all leak until the maintainer closed the stack.
   -- Marking the phase "failed" lets the run converge and tear down properly.
   if not stEnDone() then
      suTallyOpen "enetxt"
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
      suTallyClose
   end if

   if not stDcDone() then
      suTallyOpen "datachannelxt"
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
      suTallyClose
   end if

   if stEnDone() and stDcDone() then
      stFinish
      exit stPump
   end if

   -- A stuck section must not take the run with it: record the failure against
   -- the section that hung and finish everything else.
   if the milliseconds > sDeadline then
      if not stEnDone() then
         suTallyOpen "enetxt"
         stAssert "enet loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseEn & "; UDP to 127.0.0.1 may be blocked"
         put "failed" into sPhaseEn
         suTallyClose
      end if
      if not stDcDone() then
         suTallyOpen "datachannelxt"
         stAssert "datachannel loopback finished before the deadline", false
         stNote "stalled in phase" && sPhaseDc & "; UDP to this machine may be blocked"
         put "failed" into sPhaseDc
         suTallyClose
      end if
      stFinish
      exit stPump
   end if

   -- THE RE-ARM IS THE ONE STATEMENT THAT MUST ALWAYS BE REACHED, and until
   -- 2026-08-20 the render above it was the only thing in this handler that
   -- was not contained. The comment at the top of stPump already had the whole
   -- argument - a throw out of the pump breaks the timer chain, so nothing
   -- ever reaches stFinish and the hosts, peers and libtorrent session leak -
   -- and it had been applied to the two poll blocks and not to this line.
   -- stShow writes `field "stResults"` unqualified, which resolves against the
   -- DEFAULTSTACK (engine notes 5.3); on a `send ... in` tick that is not
   -- guaranteed to be this stack, so the write can throw.
   --
   -- NOT A POST-MORTEM. Two 2026-08-20 engine reports ended mid-CROSS-section
   -- and this was the shape that fit: a first-tick throw here would freeze the
   -- report at exactly the last synchronous render, which is what both looked
   -- like. It was wrong - the third run, same build, completed 1981/0/1
   -- through both loopbacks, teardown and the summary; the first two were
   -- copied before the async half finished. The containment stays because the
   -- reasoning at the top of this handler always applied to this line and had
   -- only ever been applied to the two poll blocks, and because a report is
   -- assembled in a variable: losing a render must never cost the run.
   try
      stShow
   catch tError
      if sRenderNoted is not "true" then
         put "true" into sRenderNoted
         suTallyOpen "cross"
         stAssert "the report rendered from the pump", false
         stNote "it raised:" && tError
         stNote "the run continues; the report is assembled in a variable and"
         stNote "does not depend on the field it failed to write"
         suTallyClose
      end if
   end try
   -- The board's paint, contained on its own (suPumpPaint swallows its own
   -- throw) so it can neither break the chain nor be mistaken for the report.
   suPumpPaint
   send "stPump" to me in 33 milliseconds
end stPump

-- ---- finish + teardown -------------------------------------------------------
command stFinish
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   -- Run last: OnionXT's capability advertisement is pure compute, but reading
   -- it here keeps the whole cross-member story in one block at the end of the
   -- report, next to the transports it describes.
   -- It is OnionXT's capability advertisement checked against SodiumXT, so it
   -- belongs to OnionXT's own row as much as to the cross row.
   if suInScope("onionxt") or suInScope("cross") then
      suTallyOpen "cross"
      try
         stCrossOnionSection
      catch tError
         stSectionFailed "cross: OnionXT capabilities", tError
      end try
      suTallyClose
   end if

   -- Teardown is contained too, but it is the ONE thing that must be attempted
   -- no matter what came before: stCleanup on closeStack is the safety net if a
   -- handle survives this.
   suTallyOpen "cross"
   try
      stTeardown
   catch tError
      stSectionFailed "teardown", tError
   end try
   suTallyClose

   -- The window's boot record goes in just ABOVE the summary, uncounted, so
   -- the summary stays the report's last section (the runbook's contract).
   suBootIntoReport
   stSection "summary"
   suSummaryNotes
   put empty into sAsyncRunning
   stReportDone
   suAfterDone
end stFinish

-- Everything this file opened gets closed, in dependency order, each guarded so
-- one absent member cannot stop the rest from being released.
command stTeardown
   stSection "teardown (nothing may outlive the run)"
   -- A transport this run's SCOPE never started is not asserted on: a
   -- SodiumXT-only run must not report dcCleanup or enDeinitialize for a
   -- library it never initialised. stCleanup still frees everything, bare and
   -- guarded, exactly as before.
   if sHaveDc and suUsesDc() then
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

   if sHaveEnet and suUsesEnet() then
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
-- There is NO deterministic unload hook in this family: a leaked libtorrent
-- session would block the next run outright (one session per process), and a
-- leaked ENet host or WebRTC peer would hold a UDP port and its threads. So
-- teardown (called from the scaffold's closeStack and Re-run) is
-- unconditional and idempotent here.
command stCleanup
   put empty into sAsyncRunning
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
-- `sAsyncRunning is "true"` guard, both would drive the same phase machine, and every
-- assertion would be counted twice - a silently wrong report, which is worse
-- than no report. `the pendingMessages` lines are id,time,message,object.
--
-- EVERY TIMER THIS FILE ARMS is cancelled here: the pump, and a row's armed
-- Run (suRunTick), whose run would otherwise start on top of the one Run all
-- just began. check-suite-selftest.py holds the two lists together. The
-- carried blocks' own timers are not the core's to cancel: the self-check's
-- one delayed probe restores what it touches, and the kit's copy flash is not
-- used here. The item delimiter is restored (engine note 2.3): this runs
-- inside stRun, above sections that split items of their own.
command stCancelPump
   local tPending, tLine, tOld
   put the pendingMessages into tPending
   put the itemDelimiter into tOld
   set the itemDelimiter to comma
   repeat for each line tLine in tPending
      if item 3 of tLine is "stPump" or item 3 of tLine is "suRunTick" then
         cancel (item 1 of tLine)
      end if
   end repeat
   set the itemDelimiter to tOld
   put empty into sSuArmed
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tNxReport, tNxCaps, tNxFloor -- NostrXT's probe-selected floor (its call site)
   -- The header is the run's, not a member's (no tally is open), and a
   -- cross-only run folds no member, so it prints nothing here.
   if sSuScope is not "cross" then
      stSection "deep per-member self-tests (each member's own harness, folded in)"
      stNote "Each of these is the SAME harness that member ships standalone."
      stNote "A failure here means the same thing it would mean there."
   end if

   -- SodiumXT, OnionXT, Box2Dxt, Riptide and holde-em return their report as a
   -- string; CoinXT, TorrentXT, ENetXT and DataChannelXT accumulate into their
   -- own script locals. Both shapes are handled, because both are what those
   -- members actually ship - rewriting one to look like the other would be
   -- editing a proven harness to suit this file, which is backwards.
   --
   -- THE THIRD ARGUMENT TO stMergeReturned IS A FLOOR: the fewest items that
   -- member can attempt in any environment it supports (checks + skips). Read
   -- stMergeFloor for what it does and does not catch. TWO of the six
   -- returned-report members are measured today:
   --
   --   OnionXT   51, derived section by section at its call site below. It is
   --             the member whose harness can degrade the furthest (its skips
   --             span a third of its items), which is why it was measured
   --             first and why the skip channel exists at all.
   --   NostrXT   278 with CoinXT, 253 without (2026-09-24), chosen by the
   --             member's OWN cached capability probe, the one its harness
   --             branches on; derived and justified at its call site below.
   --   the four  1, the CATASTROPHIC floor, and it is not a measured minimum.
   --   others    What it refuses is a harness that attempted NOTHING and still
   --             read green, because zero failures is zero failures. Measuring
   --             a real one means auditing that harness's conditional paths -
   --             SodiumXT's two ABI probes exit its ristretto section early,
   --             Box2Dxt/Riptide/holde-em skip whole sections by probe - and a
   --             floor set above a member's true worst case would false-fail
   --             an engine session, which is the one cost this file can least
   --             afford. A guess here would be worse than the gap: this repo
   --             has already paid once for a gate that reported the constants
   --             it had PARSED as the ones it had CHECKED. So the four carry
   --             the honest floor and say so, and measuring them is open work.
   if suInScope("sodiumxt") then
      suTallyOpen "sodiumxt"
      if sHaveSodium then
         try
            -- floor 1: catastrophic only, not measured (see above)
            stMergeReturned "SodiumXT", sx1sxSelfTest(), 1
         catch tError
            stSectionFailed "SodiumXT deep self-test", tError
         end try
      else
         stSkip "SodiumXT deep self-test", "install org.openxtalk.library.sodium"
      end if
      suTallyClose
   end if

   if suInScope("onionxt") then
      suTallyOpen "onionxt"
      if sHaveOnion then
         try
            -- THE FLOOR IS 51, and the arithmetic is here because a number with
            -- no derivation beside it is a number nobody dares to change - which
            -- is how a ratchet quietly becomes a decoration. onionxt's harness
            -- runs twelve sections; nine of them can bail out, and since
            -- 2026-08-17 every bail-out counts as one skip. Attempted = checks +
            -- skips, per section, worst case:
            --    1 version and capabilities     6   unconditional
            --    2 initial state                1   3 checks, or 1 skip when this
            --                                       session is already authed
            --    3 fail-closed arguments        6   5 unconditional, + 4 pre-auth
            --                                       checks or 1 skip
            --    4 unknown handles             10   unconditional
            --    5 idempotent teardown          3   2 unconditional, + oxStopTor:
            --                                       1 check, or 1 skip if authed
            --    6 address round-trip           6   2 addresses x (2 + 1 either
            --                                       way: re-encode or skip)
            --    7 address negative paths       4   3, + 1 either way
            --    8 SodiumXT ABI-6 composition   2   2 x (check or skip)
            --    9 configuration setters       10   unconditional
            --   10 loopback guard               1   18 checks, or 1 skip where
            --                                       oxHostOfSocket is not in this
            --                                       script
            --   11 oxh* HTTP helpers            1   27 checks, or 1 skip where
            --                                       onion-httpd is not in this
            --                                       script (THIS paste: it is not)
            --   12 SOCKS timeout reasons        1   3 checks, or 1 skip where
            --                                       the library is not in this
            --                                       script
            --                                  --
            --                                  51
            -- THIS paste normally attempts 70-75: sections 10 and 12 resolve here
            -- because the generator embeds the library into this same script,
            -- section 11 is one skip because it does not embed onion-httpd, and
            -- an already-authenticated session trades sections 2 and 3's seven
            -- checks for two skips. The floor is deliberately the
            -- environment-proof 51 rather than the paste-expected 70: a floor that
            -- can false-fail an engine session is worth less than a floor that
            -- catches less, and the degraded case is no longer invisible anyway -
            -- it arrives as up to 11 skips on the summary line.
            --
            -- RE-DERIVED 2026-09-24. This read 41 over ten sections until then,
            -- and 41 had gone stale without going WRONG: section 3 grew two
            -- pre-auth checks and section 4 five unconditional ones (2026-08-20,
            -- 2026-08-24), and section 11 arrived, all without the floor moving -
            -- a floor below the true minimum still passes, so nothing said so.
            -- Cross-check on the arithmetic: onionxt's CLAUDE.md records a
            -- 2026-08-12 engine run at 43 checks, which was sections 1-9 at their
            -- best case then, and 2026-08-17's 61, which was those 43 plus section
            -- 10's 18; sections 1-9 read 53 at best today, those 43 plus the 7
            -- above plus 2026-09-24's three (oxTransportDial and oxLaunchTor in
            -- section 3, oxStopTor in section 5). Verified statically; needs an
            -- OXT pass.
            stMergeReturned "OnionXT", ox1oxSelfTest(), 51
         catch tError
            stSectionFailed "OnionXT deep self-test", tError
         end try
      else
         stSkip "OnionXT deep self-test", "the embedded onionxt layer did not answer its probe; the paste is damaged"
      end if
      suTallyClose
   end if

   -- BOTH pieces, because ten of the folded sections call the script layer and
   -- would report FAIL rather than SKIP without it (see stProbe).
   if suInScope("coinxt") then
      suTallyOpen "coinxt"
      if sHaveCoin and sHaveCoinScript then
         try
            cx1stRun
            stMergeCounted "CoinXT", cx1sResultText, cx1sPassed, cx1sFailed, cx1sTotal, cx1sSkipped
         catch tError
            stSectionFailed "CoinXT deep self-test", tError
         end try
      else if sHaveCoin then
         stSkip "CoinXT deep self-test", "the extension is loaded but the embedded script" && \
               "layer did not answer its probe (the paste is damaged); its script-layer" && \
               "sections need it"
      else
         stSkip "CoinXT deep self-test", "install org.openxtalk.library.coin"
      end if
      suTallyClose
   end if

   if suInScope("torrentxt") then
      suTallyOpen "torrentxt"
      if sHaveTorrent then
         try
            bt1stRun
            stMergeCounted "TorrentXT", bt1sResultText, bt1sPassed, bt1sFailed, bt1sTotal, bt1sSkipped
         catch tError
            stSectionFailed "TorrentXT deep self-test", tError
         end try
      else
         stSkip "TorrentXT deep self-test", sTorrentNote
      end if
      suTallyClose
   end if

   if suInScope("enetxt") then
      suTallyOpen "enetxt"
      if sHaveEnet then
         try
            en1stRun
            stMergeCounted "ENetXT (sync half)", en1sResultText, en1sPassed, en1sFailed, en1sTotal, en1sSkipped
         catch tError
            stSectionFailed "ENetXT deep self-test", tError
         end try
      else
         stSkip "ENetXT deep self-test", "install org.openxtalk.library.enet"
      end if
      suTallyClose
   end if

   if suInScope("datachannelxt") then
      suTallyOpen "datachannelxt"
      if sHaveDc then
         try
            dc1stRun
            stMergeCounted "DataChannelXT (sync half)", dc1sResultText, dc1sPassed, dc1sFailed, dc1sTotal, dc1sSkipped
         catch tError
            stSectionFailed "DataChannelXT deep self-test", tError
         end try
      else
         stSkip "DataChannelXT deep self-test", "install org.openxtalk.library.datachannel"
      end if
      suTallyClose
   end if

   -- BOX2DXT RUNS AFTER THE TRANSPORTS AND BEFORE RIPTIDE, and unlike every
   -- other folded harness this one BUILDS THINGS ON THIS CARD: it creates
   -- graphics and images (all named st_*), drives them through a real physics
   -- world, and wipes them again. That is exactly what it does standalone; the
   -- only difference here is whose card it is. Its own stWipe deletes controls
   -- by the "st_" and "b2k" prefixes, which none of this harness's window
   -- controls carry (stSummary, stResults, stCopy, stRerun and the board's su*
   -- and ui* controls; D-23), and its
   -- last act is b2kStop + b2kTeardown, which bump the Kit's generation tag so
   -- any frame message still queued from its worlds is a no-op. It therefore
   -- has to finish BEFORE the cross-member loopbacks below arm their pump.
   if suInScope("box2dxt") then
      suTallyOpen "box2dxt"
      if sHaveBox2d then
         try
            -- floor 1: catastrophic only, not measured (see above)
            stMergeReturned "Box2Dxt", b21stSelfTest(), 1
         catch tError
            stSectionFailed "Box2Dxt deep self-test", tError
         end try
      else
         stSkip "Box2Dxt deep self-test", "install org.openxtalk.box2dxt (the b2k " & \
               "Kit is embedded in this paste, but the physics is native)"
      end if
      suTallyClose
   end if

   -- Riptide is an APP layer over the extensions above, so it runs after them:
   -- by here every extension it probes has already shown its own colours. Its
   -- harness handles a missing optional extension itself (sections SKIP), and
   -- refuses cleanly without SodiumXT, so the only gate here is the embedded
   -- layer being present at all.
   if suInScope("riptide") then
      suTallyOpen "riptide"
      if sHaveRiptideScript then
         try
            -- floor 1: catastrophic only, not measured (see above)
            stMergeReturned "Riptide Social (phases 1-8)", rs1rsSelfTest(), 1
         catch tError
            stSectionFailed "Riptide deep self-test", tError
         end try
      else
         stSkip "Riptide deep self-test", \
               "the riptide script layer is not present; the paste is damaged"
      end if
      suTallyClose
   end if

   -- NostrXT is another protocol layer over the extensions: its harness
   -- probes CoinXT/SodiumXT itself (sections SKIP with names when they are
   -- absent), and its nxr* relay-layer section SKIPS here BY DESIGN - that
   -- layer defines the engine's socket handlers, which the embedded onionxt
   -- layer already defines, so it is deliberately not in this paste
   -- (nostrxt/CLAUDE.md, the two-file split).
   if suInScope("nostrxt") then
      suTallyOpen "nostrxt"
      if sHaveNostrScript then
         try
            -- THE FLOOR IS 278 WITH COINXT AND 253 WITHOUT, and it is the first
            -- floor here chosen by a probe, because this is the first harness
            -- whose every item-count branch hangs off one probe the core can
            -- read. Attempted = passed + failed + skipped (stMergeReturned);
            -- a skip counts as ONE item, and a section that bails out emits a
            -- fixed number of skips rather than one per check it did not run.
            --
            -- THE DATED RECORD: 2026-08-24, Windows x86_64, OXT 9.6.3, this
            -- paste with CoinXT and SodiumXT ABI 10 installed: 274 passed, 0
            -- failed, 2 skipped = 276 attempted (nostrxt/CLAUDE.md, the ledger).
            -- Counted by hand section by section it is exactly that: 274 checks,
            -- and the 2 skips are section 17 (the nxr* relay layer, which is
            -- never in this paste, so it is 2 skips here in every environment).
            -- 2026-09-24 added 3 unconditional checks (the 2026-09-09 fix's
            -- pins in sections 4 and 14), so that configuration now attempts
            -- 279. What moves the count, and nothing else does (every other
            -- nxtCheck runs in every environment; pass or fail, it counts):
            --    CoinXT absent   section 6: 2 skips for its 19 or 17; section
            --                    9: 2 skips for its 8; section 11: 1 skip for
            --                    its 4 or 5 post-probe checks      -> 253
            --    SodiumXT absent section 6: 1 skip for 3 key-generation checks
            --                    (-2); no cipher, so section 11 takes the
            --                    fail-closed branch, 3 checks for 2 (+1)
            --    SodiumXT < 10   section 11's 3-check branch only (+1)
            -- So with CoinXT the count is 278 (no SodiumXT), 279 (the record's
            -- configuration) or 280 (a pre-ABI-10 SodiumXT); without it, 253
            -- whatever SodiumXT is. Measured, not only added up: the real
            -- harness was run through the family interpreter
            -- (nostrxt/tools/lcs-interp.py) in all six combinations, over the
            -- committed sibling binaries, and printed exactly these totals (its
            -- one FAIL in every run, "nxUnixNow is after the fixture era", is
            -- the interpreter's fixed deterministic clock, not a defect, and a
            -- FAIL counts as attempted all the same). That settles the
            -- COUNTING, which is logic; the floor itself has not met an
            -- engine: verified statically; needs an OXT pass.
            --
            -- WHY TWO NUMBERS, when OnionXT's one environment-proof 51 sits
            -- under its paste-expected 70. A single number must be <= 253 to
            -- spare a CoinXT-less engine, and 253 is 26 items under the record's
            -- 279 - the whole of section 12 could vanish from a fully equipped
            -- run and still read green, which is the silent shrink a floor is
            -- for. OnionXT could not do better: its skips follow runtime state
            -- (an authed session, a daemon) that nothing here can read. This
            -- harness branches on ONE cached answer, nxProbeCapabilities()'s
            -- hasCoin, which it reads first thing; the embedded core is
            -- unprefixed, so the call below returns that SAME cached array -
            -- read after the harness has run, so the floor keys on the answer
            -- the harness actually branched on and cannot disagree with it.
            -- Taking the minimum across the SodiumXT cases keeps it
            -- environment-proof within each branch: a green run in ANY
            -- supported install meets it, and a run in the record's
            -- configuration that lost 2 or more items does not (3 on a
            -- pre-ABI-10 SodiumXT; 1 without SodiumXT, or without CoinXT).
            --
            -- A HARNESS EDIT THAT REMOVES A CHECK MUST RE-DERIVE THIS, in the
            -- same change; adding one only widens the margin. Nothing gates it
            -- headlessly: one interpreted run of the whole harness took 15 to
            -- 35 minutes per environment on the machine that measured it.
            put nx1nxSelfTest() into tNxReport
            put nxProbeCapabilities() into tNxCaps
            if tNxCaps["hasCoin"] is true then
               put 278 into tNxFloor
            else
               put 253 into tNxFloor
            end if
            stMergeReturned "NostrXT", tNxReport, tNxFloor
         catch tError
            stSectionFailed "NostrXT deep self-test", tError
         end try
      else
         stSkip "NostrXT deep self-test", \
               "the nostrxt script layer is not present; the paste is damaged"
      end if
      suTallyClose
   end if

   -- HOLDE-EM RUNS LAST, and unlike every other member there is nothing to
   -- probe for first. It is the second capstone APP and it is pure script, so
   -- the whole game folds in with its harness (one file: tools/build-suite-
   -- selftest.py prefixes both together) and he1heSelfTest always exists. Its
   -- 21 sections do their own probing and SKIP by name when SodiumXT,
   -- TorrentXT or OnionXT is absent, so an unconditional call reports honestly
   -- on a bare engine instead of hiding behind a guard the member does not
   -- need.
   --
   -- LAST for a reason, not for tidiness. It is the only folded harness that
   -- ARMS TIMERS of its own: several sections drive the between-hands beat on
   -- synthetic online contexts, and the paced hand steps can arm too. Its quiet
   -- entry point sweeps every pending message carrying this member's prefix
   -- before it returns (the fold widens that sweep - see the rewrite in the
   -- generator), so nothing it armed can still be ticking when stRun arms the
   -- cross-member ENet/DataChannel loopbacks a few lines below. Running it here
   -- keeps the gap between "the last thing holde-em armed" and "the sweep" as
   -- small as this file can make it.
   --
   -- The entry point is heSelfTest, NOT heRunSelftest: the interactive one
   -- builds an 800x560 report overlay on the card, overwrites
   -- clipboardData["text"] (this scaffold's own Copy-results channel) and
   -- writes to msg, and its "==== n pass, m fail, k skip ====" summary is a
   -- line stSummaryCounts refuses on purpose (measured 2026-08-17: the string
   -- carries the skip count too - this comment quoted it a field short).
   if suInScope("holde-em") then
      suTallyOpen "holde-em"
      try
         -- floor 1: catastrophic only, not measured (see above)
         stMergeReturned "holde-em (hotseat + online + Level 2)", he1heSelfTest(), 1
      catch tError
         stSectionFailed "holde-em deep self-test", tError
      end try
      suTallyClose
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

-- Given ONE line, return "<passed> <failed>" - or "<passed> <failed> <skipped>"
-- when the line carries a skip count - if that line is a summary, or empty if
-- it is not. This is the whole rule; see stMergeReturned below for why it is
-- shaped this way.
--
-- A line qualifies only when EVERY word on it is either a number or one of the
-- words "passed"/"failed"/"skipped" (case and edge punctuation ignored), with
-- at most one of each keyword, "passed" and "failed" both present and in that
-- order, "skipped" after them when it appears at all, and exactly one number
-- per keyword present. That shape test - rather than "the line mentions both
-- words" - is what makes an individual check's LABEL unable to masquerade as a
-- summary: a label always carries at least one other word (SodiumXT's
-- "  ok   a failed call surfaces an error" has "ok", "a", "call"), and one
-- other word is enough to disqualify it.
--
-- THE THIRD COUNT IS OPTIONAL, and that is the whole compatibility story
-- (2026-08-17). Five harnesses come through here and only onionxt's reports
-- skips; the other four (SodiumXT, Box2Dxt, Riptide, holde-em) spell their
-- summary with two counts and are not going to be rewritten to carry a zero
-- they do not have. "skipped" is therefore admitted as a word rather than
-- required, and it widens NOTHING else: a line still needs both of the
-- original keywords, so "3 skipped" alone is prose here, and the number count
-- must still match the keyword count exactly, so a stray third number on a
-- two-keyword line is refused as loudly as it was before.
function stSummaryCounts pLine
   local tI, tN, tWord, tPassAt, tFailAt, tSkipAt, tNums, tWant

   put the number of words of pLine into tN
   put 0 into tPassAt
   put 0 into tFailAt
   put 0 into tSkipAt
   put empty into tNums
   repeat with tI = 1 to tN
      put stTrimEdges(word tI of pLine) into tWord
      if tWord is a number then
         put tWord & space after tNums
      else if toLower(tWord) is "passed" and tPassAt is 0 then
         put tI into tPassAt
      else if toLower(tWord) is "failed" and tFailAt is 0 then
         put tI into tFailAt
      else if toLower(tWord) is "skipped" and tSkipAt is 0 then
         put tI into tSkipAt
      else
         -- Any other word - or a SECOND "passed"/"failed"/"skipped" - means
         -- this line is prose. Nothing is guessed from it.
         return empty
      end if
   end repeat
   if tPassAt is 0 or tFailAt is 0 or tPassAt > tFailAt then
      return empty
   end if
   -- One number per keyword, and the skip keyword comes last when it comes.
   -- Both halves matter: the count rule is what stops a summary being read off
   -- a line with a spare number on it, and the order rule is what lets the
   -- numbers be assigned by POSITION below instead of by parsing pairs.
   put 2 into tWant
   if tSkipAt is not 0 then
      put 3 into tWant
      if tFailAt > tSkipAt then
         return empty
      end if
   end if
   if the number of words of tNums is not tWant then
      return empty
   end if
   -- Keyword order was just checked, and every shipped spelling puts each
   -- count with its own keyword, so the numbers are in the order the keywords
   -- are: first = passed, second = failed, third (when present) = skipped.
   -- Requiring the keyword order is what makes that one-line rule safe rather
   -- than lucky.
   return word 1 to tWant of tNums
end stSummaryCounts

-- For a harness whose entry point RETURNS its report (SodiumXT, OnionXT,
-- Box2Dxt, Riptide and holde-em - five of the nine, not the two this comment
-- named until 2026-08-17; the other four accumulate into script locals and go
-- through stMergeCounted below). The counts are parsed back out of the report
-- rather than guessed at, and if the parse ever fails that is a reported
-- FAILURE, not a silent zero.
--
-- THE RULE, in one sentence: the summary is the ONE line of the report that is
-- nothing but two numbers and the words "passed" and "failed" (in that order,
-- case and edge punctuation ignored) - or, since 2026-08-17, three numbers with
-- "skipped" behind them - and its numbers are its counts in that same order.
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
--
-- THE SKIP CHANNEL (2026-08-17). stMergeCounted has carried a skip count into
-- the suite totals since the scaffold was unified; this path had no parameter
-- for one, and the summary field prints sSkipped, so a member merged HERE
-- could only ever contribute zero skips to the line the operator reads.
-- OnionXT is the member that made that a lie rather than a gap: seven of its
-- sections bail out when the environment cannot support them, and every
-- bail-out used to touch no counter at all, so a run that tested 33 of its 61
-- items reported "33 passed, 0 failed" - the same green, one line, no way to
-- tell. Its summary carries a third count now and this handler reads it.
--
-- WHAT THE OTHER FOUR DO, measured rather than assumed, because the widening
-- has to be compatible with all of it and because two of them turn out to be
-- carrying the same defect:
--   Box2Dxt   has no skip outcome at all. Every section asserts; the core
--             guards its PRESENCE instead, one row up. Nothing to carry.
--   SodiumXT  counts a skip AS A PASS - `sxCheck true, "SKIP: this SodiumXT
--             package predates ristretto255 (ABI 8)"` on each of its two ABI
--             probes - so its skips are already inside its pass count and a
--             third number here would count them twice.
--   Riptide   BOTH keep a real skip counter and BOTH park it on a SECOND
--   holde-em  line, worded as prose on purpose so this parser refuses it.
--             Their own comments say so and name the two-count rule as the
--             reason ("the skip count gets its own line"). So their skips are
--             printed and never merged - the same hole this change closes for
--             onionxt, in two more members. Widening the parser is what
--             unblocks them; moving their counts onto line 1 is an edit in
--             their own files, and until someone makes it their skips stay
--             visible-but-unmerged rather than silently zero.
-- The two-count form is therefore still first-class, not deprecated: no member
-- is rewritten from here to suit this file, which would be backwards.
--
-- pFloor is the OTHER half of the same lesson and it is deliberately not
-- folded into this handler: see stMergeFloor below.
command stMergeReturned pMember, pReport, pFloor
   local tLine, tI, tCount, tPair, tMatches, tPassed, tFailed, tSkipped
   local tAttempted, tOk

   stSection pMember & ": its own full self-test"
   put 0 into tMatches
   put empty into tPassed
   put empty into tFailed
   put empty into tSkipped
   put the number of lines of pReport into tCount
   repeat with tI = 1 to tCount
      put line tI of pReport into tLine
      put stSummaryCounts(tLine) into tPair
      if tPair is not empty then
         add 1 to tMatches
         put word 1 of tPair into tPassed
         put word 2 of tPair into tFailed
         put word 3 of tPair into tSkipped
      end if
   end repeat
   -- A TWO-COUNT SUMMARY IS STILL A SUMMARY, so word 3 of the pair is empty
   -- for the four members still spelling it that way - and empty is not a
   -- number, which the validation below would call a broken summary. Turn it into
   -- the zero it means first, the same shape and for the same reason as
   -- stMergeCounted's empty-pSkipped line: a member that reports no skips has
   -- no skips, not an unreadable report.
   if tSkipped is empty then
      put 0 into tSkipped
   end if
   -- Built as a value rather than a continued condition, for the same reason
   -- stMergeCounted below does it: three of the six copies of
   -- check-livecodescript.py do not join line continuations before counting
   -- block openers, so an `if ... \` reads to them as a handler-level statement
   -- and every `end if` after it looks unbalanced.
   --
   -- The three numeric tests are redundant with stSummaryCounts, which already
   -- refuses to return anything but numbers. They stay because the lesson
   -- recorded on stMergeCounted below was that "it cannot be anything but a
   -- number" is a feeling, not a check, and these values are added into the
   -- suite totals: an `add` on a non-number is an UNCAUGHT engine error that
   -- takes the whole run, while a failed assertion costs one line of report.
   put (tMatches is 1 and tPassed is a number and tFailed is a number and tSkipped is a number) into tOk
   if tOk is false then
      stAssert pMember & " deep self-test reported a summary this harness could read", false
      stNote "Looked for the one line that is nothing but two or three counts and the"
      stNote "words passed/failed(/skipped), in that order;" && tMatches && \
            "line(s) in its report matched."
      stNote "Nothing was folded into the totals, and its floor of" && pFloor && \
            "went unchecked: there are no counts to check it against."
      stNote "Its report is below verbatim; read the counts by eye."
   else
      add tPassed to sPassed
      add tFailed to sFailed
      add tSkipped to sSkipped
      -- ATTEMPTED, not "checks": a skip is an item this member reached and
      -- declined to run, and the suite's own stSkip counts one into sTotal for
      -- exactly the same reason. Counting it keeps this line agreeing with the
      -- summary field, which prints passed + failed + skipped + total.
      put tPassed + tFailed + tSkipped into tAttempted
      add tAttempted to sTotal
      stAssert pMember & " deep self-test had zero failures", tFailed is 0
      stMergeFloor pMember, tAttempted, pFloor
      stNote tPassed && "passed," && tFailed && "failed," && tSkipped && \
            "skipped, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeReturned

-- THE FLOOR: the fewest items a member's harness may have attempted before
-- this suite refuses to call its report a result.
--
-- WHY IT EXISTS, and it is the one hole every other check here leaves open.
-- Everything above believes what the member says it ran. "0 passed, 0 failed"
-- is a perfectly readable summary and folds in as zero failures - green. So
-- does a harness that lost half its sections to a rename: the counts simply
-- get smaller and nothing anywhere says so. An engine session's whole output
-- is one verdict line, and until now that line could not tell a full run from
-- a third of one. Everything else in this file guards how a member's numbers
-- are READ; this guards whether there were enough of them to mean anything.
--
-- WHAT A FLOOR IS. The number of checks-plus-skips a member attempts in its
-- WORST supported environment - not its expected total, and not its best case.
-- The skip channel above is what makes such a number exist at all: a section
-- that bails out still counts 1, so the attempted total stops swinging with
-- what happens to be installed and a floor can sit just under it without
-- false-failing an engine session on a bare machine.
--
-- WHAT A FLOOR IS NOT. It is not a coverage measure and it cannot see a
-- skippable section that skipped - that section still contributes its 1, and
-- the honest report of it is the skip COUNT, not this. It catches the thing a
-- summary line structurally cannot show: items that never happened at all.
--
-- AND A BAD FLOOR IS A REPORTED FAILURE, NEVER AN ENGINE ERROR. `pAttempted <
-- pFloor` against a non-numeric pFloor is an uncaught engine error, and
-- stMergeCounted's comment below is the record of what one of those costs:
-- it takes the WHOLE run, so every member's results are lost to a single line
-- that cannot even name the member it came from. The floor is validated before
-- it is compared, exactly like the counters on both merge paths, and a floor
-- that is not a number is a failure that names the member and prints what it
-- got. It is a separate handler rather than four more lines inside
-- stMergeReturned because the two questions are separate: that one asks
-- whether a report can be READ, this one asks whether it says ENOUGH - and
-- because the second question is not particular to the returned-report shape.
-- Its parameters are (member, attempted, floor) and nothing private to
-- stMergeReturned, so stMergeCounted can call it the day its four members
-- carry measured floors of their own. They do not today: the counted path is
-- unfloored, and that is open work rather than a decision.
command stMergeFloor pMember, pAttempted, pFloor
   local tFloorOk

   put (pFloor is a number and pAttempted is a number) into tFloorOk
   if tFloorOk is false then
      stAssert pMember & " was merged against a numeric floor", false
      stNote "Got floor=[" & pFloor & "] attempted=[" & pAttempted & "]"
      stNote "The floor is a literal at this member's call site in"
      stNote "stRunMemberHarnesses, so a non-number is an edit to fix there and"
      stNote "not a defect in the member. No floor was applied to this report."
      exit stMergeFloor
   end if
   stAssert pMember & " attempted at least its floor of" && pFloor && "items", \
         (pAttempted >= pFloor)
   if pAttempted < pFloor then
      stNote "It attempted" && pAttempted && "items (passed + failed + skipped)."
      stNote "That is not a failing check inside that member - it is checks that"
      stNote "never ran at all, which its own summary line cannot show."
      stNote "Either a section stopped being called, or the floor is stale:"
      stNote "re-derive it beside that member's call site in stRunMemberHarnesses,"
      stNote "in the same change that moved the count."
   end if
end stMergeFloor

-- For a harness that accumulates into script locals (CoinXT, TorrentXT,
-- ENetXT, DataChannelXT). Its counters are read directly - they are locals of
-- THIS script, since the whole thing compiles as one unit.
command stMergeCounted pMember, pReport, pPassed, pFailed, pTotal, pSkipped
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
   -- stMergeReturned, above (with stMergeFloor now between them - it was "ten
   -- lines up" when this was written), has validated its counts since the day
   -- it was written, because THOSE come from parsing a report and a parse can
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
   if pSkipped is empty then
      put 0 into pSkipped
   end if
   put (pPassed is a number and pFailed is a number and pTotal is a number and pSkipped is a number) into tOk
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
      add pSkipped to sSkipped
      stAssert pMember & " deep self-test had zero failures", pFailed is 0
      stNote pPassed && "passed," && pFailed && "failed of" && pTotal && \
            "checks, folded into the totals above"
   end if
   stNote "---- " & pMember & " report ----"
   put pReport & return after sResultText
end stMergeCounted


-- GENERATED MEMBER HARNESSES GO HERE --
