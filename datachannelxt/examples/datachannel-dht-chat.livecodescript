script "DataChannelDhtChat"

-- datachannel-dht-chat.livecodescript - THE FLAGSHIP DEMO: serverless P2P chat
-- between two machines, anywhere on the internet, with NO infrastructure of
-- your own. The two halves of the family close a loop here:
--
--   TorrentXT's DHT (BEP44 mutable items)  = the rendezvous + signaling channel
--   DataChannelXT's WebRTC data channel    = the actual conversation
--
-- WebRTC needs the peers to exchange one SDP description each (plus ICE
-- candidates) over SOME existing channel before the direct link exists - and
-- the BitTorrent DHT is a channel every internet machine can reach without an
-- account, a server, or a port forward. So: the host publishes its offer as a
-- signed DHT item, the joiner reads it and publishes its answer the same way,
-- ICE punches the NATs, and from then on the chat rides a direct, encrypted
-- (DTLS) WebRTC channel - the DHT's job is over after the handshake.
--
-- THE ROOM CODE IS A KEYPAIR. "Host a room" asks TorrentXT for a fresh random
-- ed25519 keypair and hands you its 64-hex SEED as the room code. The joiner
-- derives the SAME keypair from the code (btDhtKeypair is deterministic on a
-- seed), so BOTH sides can sign+publish mutable items under one public key -
-- the code is a shared write-capability for one signaling mailbox, and it is
-- single-use by construction (every Host click mints a new one). Give it to
-- your friend over anything you trust; note that whoever knows it can read
-- the SDP blobs (which contain your IP addresses) and could squat the mailbox,
-- so treat a room code like a phone number you hand to one person.
--
-- THE WIRE FORMAT (a BEP44 value is capped at 1000 bytes; a non-trickle SDP
-- with candidates can exceed it, so blobs are compressed and chunked):
--
--   head item, mutable, salt "wx-o" (offer) / "wx-a" (answer):
--     "DXC1" & kind & rest
--       kind "D": rest = zlib(body)                     - it fit directly
--       kind "C": rest = comma-list of 40-hex targets   - fetch + concatenate
--                 the immutable chunk items, in order, to get zlib(body)
--   body (after decompress): nonce LF type LF sdp
--
-- The NONCE pairs an answer to the exact offer it answers: the answerer echoes
-- the offer's nonce, and the host ignores any answer that does not echo its
-- CURRENT nonce. That is what makes "Reconnect" safe under the same room code
-- even though stale items float around the DHT for a couple of hours - a new
-- offer carries a new nonce, so leftovers from the previous attempt cannot be
-- mistaken for fresh signaling (BEP44 seq also rises on every republish, but
-- the nonce check is the simpler, role-symmetric guard).
--
-- REQUIREMENTS: BOTH extensions installed - DataChannelXT
-- (org.openxtalk.library.datachannel) AND TorrentXT
-- (org.openxtalk.library.torrent) - plus the dataChannelHelpers stack from
-- this folder for the dc event dispatch. The TorrentXT poll loop is inlined
-- below (a dozen lines) so this demo does not depend on TorrentXT's example
-- files, only on its extension. Each dependency is probed once at startup and
-- fails closed with a clear install message; nothing crashes when one is
-- missing.
--
-- HOW TO RUN IT (two machines, ideally on different networks):
--   1. Install both extensions on both machines. Open dataChannelHelpers and
--      this script as stacks (the helpers are embedded here already; open this
--      stack - it builds its UI on first open).
--   2. Machine A clicks "Host a room", waits for "offer published", and sends
--      the room code to machine B (chat, email, carrier pigeon).
--   3. Machine B pastes the code and clicks Join. Watch the status walk:
--      fetch offer -> publish answer -> connecting -> OPEN. Expect first
--      contact to take roughly 10-30 s (two DHT round-trips plus ICE).
--   4. Type. The messages now travel peer-to-peer over DTLS - close the DHT
--      out of your mind; it was only the introduction.
--   If both NATs are hostile (rare), add a TURN server line to the ICE field
--   on BOTH sides: turn:user:pass@host:port?transport=udp - the status line
--   shows whether the final path is direct or relayed.
--
-- HONESTY (the suite convention): every dc* and bt* handler used here is
-- individually engine-proven, but this two-machine walkthrough has no
-- recorded engine run and the UI was unified onto the suite kit 2026-08-14 -
-- the stack as a whole is verified statically; needs an OXT pass (the
-- closing pass's section E drives the same handshake shape).
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- datachannelxt/examples/datachannel-helpers.livecodescript ----

-- datachannel-helpers.livecodescript - the script-side poll dispatcher and
-- sugar for DataChannelXT. Insert this script into the message path (e.g.
-- `start using stack "dataChannelHelpers"` or as a behavior) so any stack can
-- drive WebRTC data channels with plain event handlers instead of a manual
-- poll loop.
--
-- The model (carried from TorrentXT/ShowControl): the engine NEVER calls back
-- into script. libdatachannel fires its callbacks on its own threads; the
-- native shim queues every event; we drain that queue on a timer with ONE FFI
-- round-trip (dcPoll), then `send` one semantic message per event. Throughput
-- and event integrity are independent of the poll cadence - only worst-case
-- latency scales with it - so the interval is a documented latency/CPU knob.
-- Data channels are REAL-TIME transport: poll at 16-33 ms for a live feel
-- (games, cursors), 100+ ms for chat-grade traffic.
--
-- The messages dispatched to the target (each with the event array as its
-- parameter; keys per docs/api-reference.md):
--   dcLocalDescription  pEvent["peer"], ["sdp"], ["sdpType"] - SHIP THESE to
--   dcLocalCandidate    pEvent["candidate"], ["mid"]           the far peer
--   dcStateChange       pEvent["state"] (see dcStateName below)
--   dcGatheringStateChange  pEvent["state"]
--   dcChannelIncoming   pEvent["channel"], ["label"], ["protocol"]
--   dcChannelOpen       pEvent["channel"] - NOW you can send
--   dcChannelClosed     pEvent["channel"]
--   dcMessage           pEvent["text"] (a text send) OR ["payload"] (binary)
--   dcChannelError      pEvent["error"]
--   dcBufferedLow       pEvent["channel"] - resume sending (backpressure)
--   dcQueueOverflow     pEvent["dropped"] - the app stopped polling too long
-- plus a catch-all "dataChannelEvent" fired for EVERY event.

-- script-local poll state (declared at top; LiveCode Script script-locals)
local sPollTarget       -- object that receives the semantic event messages
local sPollInterval     -- milliseconds between drains (the latency/CPU knob)
local sPolling          -- "true" while the timer loop is armed
local sPollNote         -- most recent dispatch failure, "" while healthy

-- dcStartPolling TARGET, INTERVALMS
-- Begin draining events and dispatching them to TARGET. If TARGET is empty,
-- events go to the current card. INTERVALMS defaults to 33 (about 30 Hz -
-- real-time feel without measurable CPU cost). Calling it again while polling
-- re-points the target and the interval (last caller wins); it does NOT arm a
-- second chain.
command dcStartPolling pTarget, pIntervalMs
   if pTarget is empty then
      put the long id of this card into sPollTarget
   else
      put pTarget into sPollTarget
   end if
   if pIntervalMs is empty or pIntervalMs is not a number or pIntervalMs < 1 then
      put 33 into sPollInterval
   else
      put pIntervalMs into sPollInterval
   end if
   -- Arm the chain ONCE - the guard enet-helpers has carried since it was
   -- written, and the one this file lacked. A second chain does not duplicate
   -- EVENTS: each pass drains the whole queue in one dcPoll, so the second
   -- chain mostly finds it empty. What doubles, permanently, is the FFI drain
   -- RATE and the timer churn - and neither chain can be stood down on its
   -- own, because both read this one flag. Every in-tree caller
   -- (datachannel-loopback, datachannel-dht-chat) arms once at startup, so
   -- this is a trap laid for the NEXT caller rather than a live regression.
   if sPolling is not "true" then
      put "true" into sPolling
      -- kick the loop immediately; it reschedules itself
      send "dcChannelPollOnce" to me in 0 milliseconds
   end if
end dcStartPolling

-- Stop the timer loop. Safe to call when not polling. (This stops DELIVERY
-- only - the native queue keeps buffering, bounded, until you poll again or
-- call dcCleanup.)
command dcStopPolling
   put "false" into sPolling
end dcStopPolling

-- One drain pass: pull all pending events with a single dcPoll, dispatch
-- each, then reschedule.
--
-- WHY THIS IS WRAPPED, AND WHY THE WRAP IS NOT BELT-AND-BRACES.
-- The 2026-08-18 Linux pass reported, on hosting a chat:
--
--   execution error at line 178 (call: type conversion error), char 1
--
-- - line 178 of the merged demo being the `dispatch tName` below. That is the
-- whole product of an engine session: a statement, and a phrase. It does not
-- say which EVENT was in flight, whether the target still resolved, or
-- whether the throw came from the dispatch itself or from a handler it
-- reached, and those are three different bugs. Static reading could not tell
-- them apart either: `dispatch <name> to <obj> with <array>` is proven
-- on-engine elsewhere in this suite (onion-httpd routes an array of headers
-- that way and serves real pages), so the obvious suspect is already ruled
-- out. So this pass now records what it saw.
--
-- It also STOPS TAKING THE CHAIN DOWN. An uncaught throw here kills the timer
-- and the app goes quiet with no further symptom - the failure mode that makes
-- an intermittent event bug cost several passes instead of one. Each event is
-- isolated: one bad event is reported and skipped, the rest of the drain and
-- every later drain still run. The note is READ, not printed, because printing
-- from a library into an app it knows nothing about is how a diagnostic
-- becomes a nuisance: see dcPollLastError.
command dcChannelPollOnce
   local tEvents, tEvent, tName, tErr, tTarget, tProbe
   if sPolling is not "true" then
      exit dcChannelPollOnce
   end if
   -- Resolve the target ONCE per pass and prove it still RESOLVES. A long id
   -- whose object has gone (a closed stack, a rebuilt card) is the classic way
   -- a dispatch target goes stale.
   --
   -- The probe is a guarded property READ, not `there is an object tTarget`.
   -- That spelling reads better and nothing in this suite has ever compiled
   -- it, so putting it here would risk trading a reported error for an
   -- unreported one in three demo files at once. The try/catch shape below is
   -- the one box2dxt's harness uses to re-resolve a stale long id, and it has
   -- run green on an engine.
   put sPollTarget into tTarget
   put empty into tProbe
   if tTarget is not empty then
      try
         put the short name of tTarget into tProbe
      catch tErr
         put empty into tProbe
      end try
   end if
   if tProbe is empty then
      put the long id of this card into tTarget
      if sPollNote is empty then
         put "poll target no longer resolves; fell back to this card" into sPollNote
      end if
   end if
   -- THE DRAIN IS INSIDE THE TRY TOO, and the first version of this wrap got
   -- that wrong. It guarded the dispatch, because the engine had named the
   -- dispatch line - but the NEXT report named datachannel.lcb line 234, which
   -- is inside dcPoll's buffer helper. That throw happens HERE, on the way in,
   -- and an unguarded `put dcPoll() into tEvents` takes the timer chain down
   -- before any dispatch is attempted. Guarding only the half you have already
   -- been shown is how a diagnostic costs two passes instead of one.
   put empty into tEvents
   try
      put dcPoll() into tEvents
   catch tErr
      if sPollNote is empty then
         put "dcPoll failed: " & line 1 of tErr into sPollNote
      end if
      -- Do NOT stop polling: a transient drain failure must not silently end
      -- the app's event delivery. Reschedule below and try again.
      put empty into tEvents
   end try
   repeat for each element tEvent in tEvents
      put tEvent["name"] into tName
      try
         if tName is not empty then
            dispatch tName to tTarget with tEvent
         end if
         -- also fire a catch-all so one handler can observe the whole stream
         dispatch "dataChannelEvent" to tTarget with tEvent
      catch tErr
         -- Keep the FIRST failure: it is the one with a clean cause. Later
         -- ones are usually the same bug repeating at 10 Hz, and overwriting
         -- would leave whichever event happened to be last.
         if sPollNote is empty then
            put "dispatch of" && tName & " failed: " & line 1 of tErr into sPollNote
         end if
      end try
   end repeat
   -- Reschedule (the native queue keeps buffering between drains). The
   -- interval is guarded because `in () milliseconds` on an empty value is
   -- itself a type conversion error - and a poll loop that dies while
   -- reporting a poll error would be a poor diagnostic.
   if sPollInterval is not a number or sPollInterval < 1 then
      put 33 into sPollInterval
   end if
   send "dcChannelPollOnce" to me in (sPollInterval) milliseconds
end dcChannelPollOnce

-- dcPollLastError() -- empty while the dispatcher is healthy; otherwise the
-- FIRST dispatch failure since the last dcPollClearError, naming the event.
-- An app that shows this in its own log turns "the demo went quiet" into a
-- line a maintainer can act on.
function dcPollLastError
   return sPollNote
end dcPollLastError

-- Clear it, so an app can report each distinct failure once rather than
-- repeating one line forever.
command dcPollClearError
   put empty into sPollNote
end dcPollClearError

-- dcStateName N -- map a kPeerState* int to a label for status displays.
function dcStateName pState
   switch pState
      case 0
         return "new"
      case 1
         return "connecting"
      case 2
         return "connected"
      case 3
         return "disconnected"
      case 4
         return "failed"
      case 5
         return "closed"
      default
         return "unknown"
   end switch
end dcStateName

-- dcGatheringName N -- map a kGathering* int to a label.
function dcGatheringName pState
   switch pState
      case 0
         return "new"
      case 1
         return "gathering"
      case 2
         return "complete"
      default
         return "unknown"
   end switch
end dcGatheringName

-- dcFormatBytes N -- a small humaniser for buffered-amount displays.
function dcFormatBytes pBytes
   local tUnits, tVal, tI, tSavedDelim, tOut
   if pBytes is empty or pBytes is not a number then
      return "0 B"
   end if
   put "B,KiB,MiB,GiB" into tUnits
   put pBytes into tVal
   put 1 into tI
   -- TWO reads need the comma, not one: the loop guard COUNTS the units and
   -- the return picks one. The `set` used to sit BETWEEN them, so the guard
   -- counted under whatever delimiter was in force rather than the one this
   -- data is written in - and under any delimiter but comma that string is a
   -- ONE-item list, so the loop never runs and a gigabyte reports itself in
   -- bytes. Set once before the FIRST read; restore before returning, since a
   -- humaniser has no business changing its caller's delimiter (the family's
   -- LCS gotcha: itemDelimiter is global mutable state - set it immediately
   -- before use, and put back what you found). Not a precaution: holde-em's
   -- v0.15 audit found three real leaks of exactly this shape - heStackFolder
   -- returning with the delimiter left at a slash, heSwapExt at a dot - and
   -- answered all three with save-and-restore.
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   repeat while tVal >= 1024 and tI < the number of items of tUnits
      put tVal / 1024 into tVal
      add 1 to tI
   end repeat
   put (the round of (tVal * 10) / 10) && (item tI of tUnits) into tOut
   set the itemDelimiter to tSavedDelim
   return tOut
end dcFormatBytes

-- <<< END EMBEDDED LIBRARIES <<<

constant kWxUiVersion = "dhtchat-kit2-1"
-- Ticks (of kWxTickMs) before the joiner is TOLD the offer is not there yet,
-- and the gathering watchdog's own deadline. Neither aborts anything - the
-- retries are the design - they just stop a silent wait from reading as a
-- hang (the enet closing-pass lesson).
constant kWxOfferHintTicks = 25
constant kWxGatherMs = 20000

-- The wire format above, pinned. kWxMagic versions the blob; bump it (and both
-- sides) on ANY change to the framing. The chunk size stays comfortably under
-- the 1000-byte BEP44 value cap (bencoding overhead included); the head budget
-- decides direct-vs-chunked for the compressed body.
constant kWxMagic = "DXC1"
constant kWxSaltOffer = "wx-o"
constant kWxSaltAnswer = "wx-a"
constant kWxChunkBytes = 900
constant kWxHeadBudget = 950

-- Cadences. Signaling rides the DHT, so seconds are the natural unit: the
-- far-side lookup repeats every tick, and our own items are republished every
-- kWxRepubTicks ticks (a lookup misses now and then; republishing also resets
-- the ~2 h item lifetime). The dc poll below is 100 ms - chat-grade latency -
-- and the bt poll 300 ms; both are latency knobs, never correctness knobs.
constant kWxTickMs = 4000
constant kWxRepubTicks = 12
constant kWxFetchTriesMax = 25

-- One public STUN server resolves reflexive addresses for the common case.
-- TURN (for NAT pairs STUN cannot crack) is a paid/self-hosted resource, so it
-- ships empty - the field is editable and documented in the tooltip.
constant kWxDefaultIce = "stun:stun.l.google.com:19302"

-- ---- script-local state (declared at top) ------------------------------------
local sSession          -- TorrentXT session handle (0/empty = none)
local sHaveBt           -- "true" once the TorrentXT probe succeeds
local sHaveDc           -- "true" once the DataChannelXT probe succeeds
local sChatPolling      -- "true" while THIS DEMO's timer loops are armed.
                        -- Renamed from sPolling 2026-08-18: the embedded
                        -- dataChannelHelpers declares its own sPolling for the
                        -- dc poll chain, and two script-level locals of one name
                        -- in one script is a hard compile error - "name shadows
                        -- another variable or constant". They were always two
                        -- different flags; before the embed they lived in two
                        -- stacks, so nothing collided.
local sDhtReady         -- "true" once the DHT has nodes (gates a helpful log)
local sRole             -- "host" / "join" / empty
local sPhase            -- idle/gathering/waiting-answer/fetch-offer/connecting/open/lost
local sKeys             -- array publicKey/secretKey/seed for the room mailbox
local sCode             -- the 64-hex room code (the keypair seed)
local sPeer             -- our peer connection handle
local sChan             -- our data channel handle
local sNonce            -- host: the current offer's nonce; join: the echoed one
local sSeenOfferNonce   -- join: last offer nonce already answered (dedup guard)
local sSeenAnswerNonce  -- host: last answer nonce already applied (dedup guard)
local sTicks            -- signal-tick counter (drives the republish cadence)
local sLoggedPut        -- "true" after logging one put confirm per publish
local sPubHead          -- our last-published head value (Data) - for republish
local sPubChunks        -- array 1..N -> chunk bytes - republished with the head
local sPubCount         -- number of chunks in sPubChunks (0 = direct head)
local sFetchTargets     -- comma-list of 40-hex chunk targets being fetched
local sFetchHave        -- array target -> chunk bytes received so far
local sFetchTries       -- ticks spent fetching (bounded by kWxFetchTriesMax)

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
-- ==== SUITE UI KIT v2 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   wxBuild
   wxStart
end openStack

on closeStack
   wxStop
end closeStack

on mouseUp
   switch the short name of the target
      case "wxHost"
         wxHost
         break
      case "wxJoin"
         wxJoin
         break
      case "wxCopy"
         wxCopyCode
         break
      case "wxSend"
         wxSendMessage
         break
      case "wxDrop"
         wxDisconnect
         break
      case "wxAgain"
         wxReconnect
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- Enter in the message box sends; Enter in the code box joins.
on returnInField
   switch the short name of the target
      case "wxMsg"
         wxSendMessage
         break
      case "wxCode"
         wxJoin
         break
      default
         pass returnInField
   end switch
end returnInField

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command wxBuild
   if the uWxUiVersion of this stack is kWxUiVersion and there is a field "wxMsg" then
      exit wxBuild
   end if
   wxClearGeneratedUI
   lock screen
   uiChrome "P2P chat - WebRTC data channel, DHT-signalled, no server anywhere", 560, 640
   uiCap "wxTagline", "One side Hosts and sends the room code to the other, who Joins. The BitTorrent DHT carries the WebRTC handshake; the chat itself is a direct, DTLS-encrypted data channel between the two machines.", "16,56,544,102"
   -- host / join row
   uiButton "wxHost", "Host a room", "16,106,150,136"
   uiCap "wxCodeCap", "Room code (yours after Host; paste your friend's to Join):", "160,104,544,122"
   uiInput "wxCode", "160,124,470,148"
   uiButton "wxJoin", "Join", "476,122,544,152"
   uiButton "wxCopy", "Copy code", "16,142,150,168"
   -- ICE servers
   uiCap "wxIceCap", "ICE servers (one URI per line; add a turn: line if both NATs are hostile):", "16,176,544,194"
   uiInput "wxIce", "16,196,544,228"
   put kWxDefaultIce into field "wxIce"
   -- your name
   uiCap "wxNameCap", "Your name:", "16,236,100,254"
   uiInput "wxName", "100,234,280,258"
   uiButton "wxDrop", "Disconnect", "290,232,410,260"
   uiButton "wxAgain", "Reconnect", "416,232,544,260"
   -- combined event + chat log (the status line is the kit's, under the band)
   uiArea "wxLog", "16,268,544,540"
   -- message box + send
   uiInput "wxMsg", "16,548,420,574"
   uiButton "wxSend", "Send", "430,546,544,576"
   uiFooter \
         "The room code is a write-capability: anyone who has it can read the" \
         & " handshake blobs (they contain your addresses) until the chat" \
         & " opens. The chat itself is direct and DTLS-encrypted. Verified" \
         & " statically; needs an OXT pass.", \
         "16,582,544,634"
   wxAddTips
   set the uWxUiVersion of this stack to kWxUiVersion
   unlock screen
end wxBuild

command wxClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "wx" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "wx" then
         delete button tI of this card
      end if
   end repeat
   unlock screen
end wxClearGeneratedUI

command wxAddTips
   set the tooltip of button "wxHost" to "Mint a fresh room code and publish a WebRTC offer under it on the DHT."
   set the tooltip of field "wxCode" to "The room code IS a 64-hex signing-key seed: both sides derive the same DHT mailbox from it. Single-use; treat it like a phone number."
   set the tooltip of button "wxJoin" to "Derive the mailbox from the pasted code, fetch the host's offer, and publish your answer."
   set the tooltip of field "wxIce" to "ICE server URIs, one per line. STUN discovers your public address; a turn:user:pass@host:port?transport=udp line relays when a direct path is impossible (credentials are secrets in ordinary memory)."
   set the tooltip of button "wxDrop" to "Tear down the peer connection (the session and room keys stay; Reconnect restarts the handshake)."
   set the tooltip of button "wxAgain" to "Redo the handshake under the SAME room code: the host publishes a fresh offer (new nonce), the joiner waits for it. Click on both sides."
   set the tooltip of field "wxMsg" to "Type and press Enter. Messages ride the direct WebRTC channel - up to 60000 bytes each (bulk belongs to TorrentXT)."
end wxAddTips

-- ---- startup: probes, session, loops -----------------------------------------
-- Each extension is probed with a cheap guarded call (the family's SodiumXT
-- probe pattern): when one is missing the demo fails CLOSED - buttons log a
-- clear install message and nothing else breaks.
command wxStart
   if sChatPolling is "true" then
      exit wxStart -- a re-fired openStack must not stack a second set of loops
   end if
   put wxProbeDc() into sHaveDc
   put wxProbeBt() into sHaveBt
   if sHaveDc is not "true" then
      wxLog "DataChannelXT is not installed (org.openxtalk.library.datachannel) - install it and reopen this stack."
   end if
   if sHaveBt is not "true" then
      wxLog "TorrentXT is not installed (org.openxtalk.library.torrent) - it provides the DHT that carries the signaling. Install it and reopen this stack."
   end if
   if sHaveDc is not "true" or sHaveBt is not "true" then
      wxSetStatus "Missing extension - see the log."
      exit wxStart
   end if
   -- the DTLS certificate is generated lazily on first use; warming it now
   -- shaves it off the first connect
   -- BARE: see the note on dcCleanup below. A zero-argument call written
   -- dcInit() in statement position does not compile.
   dcInit
   btStartSession
   put the result into sSession
   if sSession is 0 or sSession is empty then
      wxLog "Could not start a TorrentXT session (is another TorrentXT stack open?):" && btLastError()
      put 0 into sSession
      wxSetStatus "No session - see the log."
      exit wxStart
   end if
   btSetBool sSession, "enable_dht", true
   -- reload the saved DHT routing table (if any) for a faster bootstrap
   if the uWxDhtState of this stack is not empty then
      btDhtLoadState sSession, the uWxDhtState of this stack
   end if
   btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
   btDhtAddBootstrap sSession, "router.utorrent.com", 6881
   btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
   put "idle" into sPhase
   put "true" into sChatPolling
   put "false" into sDhtReady
   wxLog "Ready. DHT bootstrapping - Host (or Join) once the node count in the status line is above zero."
   -- dc events dispatch through the helpers (100 ms = chat-grade latency);
   -- the bt drain is the inline loop below (300 ms - DHT signaling is slow
   -- anyway). Both intervals are latency knobs, never correctness knobs. The
   -- helpers stack is a FILE dependency, so its absence is caught here, closed.
   try
      dcStartPolling the long id of this card, 100
   catch tErr
      put "false" into sChatPolling
      wxLog "The poll dispatcher is missing. It is EMBEDDED in this file, so this means the embedded copy is damaged - re-paste the whole file, or run tools/sync-demo-embeds.py."
      wxSetStatus "Helpers stack missing - see the log."
      exit wxStart
   end try
   -- ONE of each timer chain, armed once for the stack's life; every loop
   -- no-ops (but keeps rescheduling) when its phase has nothing to do. Arming
   -- per-action instead would stack chains on every Reconnect.
   send "wxBtPollOnce" to me in 0 milliseconds
   send "wxSignalTick" to me in kWxTickMs milliseconds
   send "wxDashOnce" to me in 800 milliseconds
end wxStart

command wxStop
   put "false" into sChatPolling
   try
      dcStopPolling
   catch tErr
      -- helpers stack already gone; nothing was polling
   end try
   -- keep the routing table warm for the next open (the channels precedent)
   if sSession is not empty and sSession is not 0 then
      set the uWxDhtState of this stack to btDhtSaveState(sSession)
   end if
   -- dcCleanup frees every peer/channel and joins the native threads - the one
   -- contract every DataChannelXT app must honour before quitting
   if sHaveDc is "true" then
      -- BARE, not dcCleanup(). `()` is not an expression, so a zero-argument
      -- call in statement position fails to compile; enetxt's shipped
      -- teardown (enDeinitialize) is the same idiom.
      dcCleanup
   end if
   if sSession is not empty and sSession is not 0 then
      btStopSession sSession
   end if
   put empty into sSession
   put empty into sPeer
   put empty into sChan
   put "idle" into sPhase
end wxStop

function wxProbeDc
   try
      get dcLibraryVersion()
      return "true"
   catch tErr
      return "false"
   end try
end wxProbeDc

function wxProbeBt
   try
      get btLastError()
      return "true"
   catch tErr
      return "false"
   end try
end wxProbeBt

-- ---- host / join -------------------------------------------------------------
command wxHost
   local tKp
   if not wxReadyCheck() then
      exit wxHost
   end if
   if sPeer is not empty and sPeer is not 0 then
      wxLog "Already in a room - Disconnect first (or Reconnect to redo the handshake)."
      exit wxHost
   end if
   -- a FRESH keypair per hosted room: the seed is the code, so codes are
   -- single-use and stale DHT leftovers can never belong to this room
   put btDhtKeypair("") into tKp
   if tKp["seed"] is empty then
      wxLog "Could not create a room keypair:" && btLastError()
      exit wxHost
   end if
   put tKp into sKeys
   put tKp["seed"] into sCode
   set the text of field "wxCode" to sCode
   put "host" into sRole
   wxLog "Room minted. Send the code to your friend (Copy code), then wait here."
   wxBeginOffer
end wxHost

command wxJoin
   local tCode, tKp
   if not wxReadyCheck() then
      exit wxJoin
   end if
   if sPeer is not empty and sPeer is not 0 then
      wxLog "Already in a room - Disconnect first."
      exit wxJoin
   end if
   put toLower(wxTrim(the text of field "wxCode")) into tCode
   if not matchText(tCode, "^[0-9a-f]{64}$") then
      wxLog "Paste a 64-hex room code first (the host's Copy code button provides it)."
      exit wxJoin
   end if
   -- deterministic: the same seed yields the same keypair on both machines
   put btDhtKeypair(tCode) into tKp
   if tKp["publicKey"] is empty then
      wxLog "Could not derive the room keypair:" && btLastError()
      exit wxJoin
   end if
   put tKp into sKeys
   put tCode into sCode
   put "join" into sRole
   put "fetch-offer" into sPhase
   put empty into sSeenOfferNonce
   put 0 into sTicks
   wxClearFetch
   wxLog "Looking for the host's offer on the DHT (a lookup takes a few seconds; retrying every" && (kWxTickMs div 1000) && "s)..."
   -- fire the first lookup now; the standing signal tick carries the retries
   get btDhtGetMutable(sSession, sKeys["publicKey"], kWxSaltOffer)
end wxJoin

command wxCopyCode
   if sCode is empty then
      wxLog "Host a room first - the code appears after Host."
      exit wxCopyCode
   end if
   set the clipboardData["text"] to sCode
   wxLog "Room code copied to the clipboard."
end wxCopyCode

-- Everything both buttons need before any DHT/WebRTC work can start.
function wxReadyCheck
   if sHaveDc is not "true" or sHaveBt is not "true" then
      wxLog "Both extensions are required - see the startup message above."
      return false
   end if
   if sSession is 0 or sSession is empty then
      wxLog "No TorrentXT session - reopen the stack."
      return false
   end if
   return true
end wxReadyCheck

-- Create our peer + channel and start gathering. Host-side: this triggers the
-- offer. The nonce minted here is the offer's identity - the answer must echo
-- it, and Reconnect mints a new one, which is what invalidates stale items.
command wxBeginOffer
   put dcCreatePeer(wxIceServers()) into sPeer
   if sPeer is 0 or sPeer is empty then
      wxLog "Could not create a peer connection:" && dcLastError()
      put empty into sPeer
      exit wxBeginOffer
   end if
   put dcCreateChannel(sPeer, "chat") into sChan
   if sChan is 0 or sChan is empty then
      wxLog "Could not create the data channel:" && dcLastError()
      dcFreePeer(sPeer)
      put empty into sPeer
      exit wxBeginOffer
   end if
   put wxRandomNonce() into sNonce
   put empty into sSeenAnswerNonce
   put "gathering" into sPhase
   send "wxGatherWatch" to me in kWxGatherMs milliseconds
   put 0 into sTicks
   wxClearFetch
   wxClearPublished
   wxLog "Gathering network candidates (STUN)..."
end wxBeginOffer

command wxDisconnect
   if sPeer is not empty and sPeer is not 0 then
      dcFreePeer(sPeer)
   end if
   put empty into sPeer
   put empty into sChan
   put "idle" into sPhase
   wxClearFetch
   wxLog "Disconnected. The room keys are kept - Reconnect redoes the handshake under the same code."
end wxDisconnect

-- Redo the handshake under the SAME room code. The host publishes a fresh
-- offer (fresh nonce -> the old answer is unmistakably stale); the joiner
-- goes back to polling for an offer whose nonce it has not answered yet.
-- Click it on BOTH sides; order does not matter.
command wxReconnect
   if sRole is empty or sKeys["publicKey"] is empty then
      wxLog "Nothing to reconnect - Host or Join first."
      exit wxReconnect
   end if
   if sPeer is not empty and sPeer is not 0 then
      dcFreePeer(sPeer)
      put empty into sPeer
      put empty into sChan
   end if
   if sRole is "host" then
      wxLog "Reissuing the invitation under the same room code..."
      wxBeginOffer
   else
      put "fetch-offer" into sPhase
      put 0 into sTicks
      wxClearFetch
      wxLog "Waiting for the host to reissue the offer (the host must click Reconnect too)..."
   end if
end wxReconnect

-- The ICE list crosses as one newline-separated string; the field is already
-- in that shape. Empty is legal (host candidates only - LAN peers still work).
function wxIceServers
   return wxTrim(the text of field "wxIce")
end wxIceServers

-- ---- publish: our description -> the DHT mailbox -----------------------------
-- Called when OUR gathering completes: the local description now CONTAINS the
-- candidates (the non-trickle one-blob shape - the only sane one over a
-- transport with multi-second latency; trickling candidates through the DHT
-- would race the ~2 h it takes them to matter).
command wxPublishLocal
   local tSdp, tKind, tBody, tZip, tSalt, tHead, tChunk, tTarget, tTargets, tI, tR
   put dcLocalDescription(sPeer) into tSdp
   if tSdp is empty then
      wxLog "Gathering finished but no local description exists - " & dcLastError()
      exit wxPublishLocal
   end if
   if sRole is "host" then
      put kWxSaltOffer into tSalt
   else
      put kWxSaltAnswer into tSalt
   end if
   -- body: nonce LF type LF sdp (the joiner echoes the offer's nonce)
   put sNonce & numToChar(10) & dcLocalDescriptionType(sPeer) & numToChar(10) & tSdp into tBody
   put compress(textEncode(tBody, "UTF-8")) into tZip
   put empty into sPubChunks
   put 0 into sPubCount
   if the number of bytes in tZip <= kWxHeadBudget then
      -- it fits in the head item directly
      put kWxMagic & "D" & tZip into tHead
   else
      -- chunk the compressed body into immutable items; the head carries the
      -- ordered target list. Immutable items are content-addressed (the
      -- target IS the sha1 of the value), so integrity is free and a
      -- republish lands on the same targets.
      put "" into tTargets
      put 0 into tI
      repeat while the number of bytes in tZip > 0
         add 1 to tI
         put byte 1 to kWxChunkBytes of tZip into tChunk
         delete byte 1 to kWxChunkBytes of tZip
         put tChunk into sPubChunks[tI]
         put btDhtPutImmutable(sSession, tChunk) into tTarget
         if tTarget is empty then
            wxLog "Chunk publish failed:" && btLastError()
            exit wxPublishLocal
         end if
         if tTargets is not "" then
            put "," after tTargets
         end if
         put tTarget after tTargets
      end repeat
      put tI into sPubCount
      put kWxMagic & "C" & tTargets into tHead
   end if
   put tHead into sPubHead
   put "false" into sLoggedPut
   put btDhtPutMutable(sSession, sKeys["publicKey"], sKeys["secretKey"], tSalt, tHead) into tR
   if tR is not 0 then
      wxLog "Publish failed:" && btLastError()
      exit wxPublishLocal
   end if
   if sRole is "host" then
      put "waiting-answer" into sPhase
      wxLog "Offer published" & wxChunkNote() & ". Waiting for someone to Join with the code..."
   else
      put "connecting" into sPhase
      wxLog "Answer published" & wxChunkNote() & ". Connecting..."
   end if
end wxPublishLocal

function wxChunkNote
   if sPubCount > 0 then
      return " (" & sPubCount && "chunks)"
   end if
   return ""
end wxChunkNote

-- Republish our head + chunks verbatim (BEP44 seq rises automatically in the
-- native layer). Cheap insurance against a lookup that raced the first put
-- and against item expiry while a room sits open waiting.
command wxRepublish
   local tI, tR
   if sPubHead is empty then
      exit wxRepublish
   end if
   repeat with tI = 1 to sPubCount
      put btDhtPutImmutable(sSession, sPubChunks[tI]) into tR
      if tR < 0 then
         wxLog "* chunk republish" && tI && "FAILED (" & tR & "):" && btLastError()
      end if
   end repeat
   if sRole is "host" then
      put btDhtPutMutable(sSession, sKeys["publicKey"], sKeys["secretKey"], kWxSaltOffer, sPubHead) into tR
   else
      put btDhtPutMutable(sSession, sKeys["publicKey"], sKeys["secretKey"], kWxSaltAnswer, sPubHead) into tR
   end if
   -- the old version put this into tR and never read it - a dead session
   -- would have stopped every republish silently, which is the one failure
   -- the republish cadence exists to defend against
   if tR < 0 then
      wxLog "* head republish FAILED (" & tR & "):" && btLastError()
      wxSetStatus "Republish failing - the session may be gone. See the log.", "bad"
   end if
end wxRepublish

-- The gathering watchdog: non-trickle signaling publishes ONLY when ICE
-- gathering completes, so a machine whose STUN is blocked sits in
-- "gathering" forever with nothing on the wire and nothing on screen. Name
-- it; the phase machine is untouched (gathering may still complete late).
command wxGatherWatch
   if sPhase is not "gathering" then
      exit wxGatherWatch
   end if
   wxLog "* still gathering candidates after" && (kWxGatherMs div 1000) && "s: STUN may be blocked on this network. Chat may still work LAN-only; a turn: line in the ICE field is the fix for the general case."
   wxSetStatus "ICE gathering is slow - STUN blocked? See the log.", "warn"
end wxGatherWatch

-- ---- the signal tick: poll the far side, retry chunks, republish -------------
-- ONE standing chain (armed in wxStart). Reschedules FIRST so no body path can
-- kill the loop, then no-ops unless a handshake is actually in flight.
command wxSignalTick
   local tWant
   if sChatPolling is not "true" then
      exit wxSignalTick -- the chain ends with the stack
   end if
   send "wxSignalTick" to me in kWxTickMs milliseconds
   if sRole is empty then
      exit wxSignalTick
   end if
   -- phases that are DONE with the DHT do not tick
   if sPhase is "open" or sPhase is "idle" or sPhase is "lost" then
      exit wxSignalTick
   end if
   add 1 to sTicks
   -- a joiner still offer-less after the hint window is TOLD so, once - a
   -- wrong or stale code otherwise reads as an indefinite silent hang
   if sRole is "join" and sPhase is "fetch-offer" and sTicks is kWxOfferHintTicks then
      wxLog "* still no offer after" && ((kWxOfferHintTicks * kWxTickMs) div 1000) && "s. Is the host online with THIS exact code? Codes are single-use: Reconnect on both sides mints a fresh handshake."
      wxSetStatus "Still looking for the host's offer - see the log.", "warn"
   end if
   -- what is the far side's mailbox slot for my role?
   if sRole is "host" and sPhase is "waiting-answer" then
      put kWxSaltAnswer into tWant
   else if sRole is "join" and sPhase is "fetch-offer" then
      put kWxSaltOffer into tWant
   else
      put "" into tWant
   end if
   if tWant is not "" then
      get btDhtGetMutable(sSession, sKeys["publicKey"], tWant)
   end if
   -- chunk fetches outstanding? re-request the missing ones (a DHT lookup is
   -- best-effort; retries are the norm, not the exception)
   wxRetryFetch
   -- keep our own items alive/fresh while the handshake is in flight
   if sTicks mod kWxRepubTicks is 0 then
      wxRepublish
   end if
end wxSignalTick

-- ---- the inline TorrentXT drain ----------------------------------------------
-- The one FFI round-trip per pass rule. Only the four DHT event kinds this
-- demo cares about are handled; everything else is ignored. (Inlined instead
-- of using TorrentXT's torrent-helpers stack so this folder stays standalone -
-- the demo needs TorrentXT's EXTENSION, not its example files.)
command wxBtPollOnce
   local tEvents, tEvent
   if sChatPolling is not "true" then
      exit wxBtPollOnce
   end if
   if sSession is not empty and sSession is not 0 then
      put btPoll(sSession) into tEvents
      repeat for each element tEvent in tEvents
         switch tEvent["name"]
            case "dhtBootstrap"
               wxLog "DHT is up."
               break
            case "dhtPut"
               -- one confirm per publish is plenty; republishes stay quiet
               if sLoggedPut is not "true" then
                  put "true" into sLoggedPut
                  wxLog "Signaling stored on the DHT (" & tEvent["numSuccess"] && "nodes)."
               end if
               break
            case "dhtMutableItem"
               wxOnMutableItem tEvent
               break
            case "dhtImmutableItem"
               wxOnImmutableItem tEvent
               break
         end switch
      end repeat
   end if
   send "wxBtPollOnce" to me in 300 milliseconds
end wxBtPollOnce

-- A mutable-item lookup came back. Route by salt + role/phase; anything that
-- does not parse as a current blob is quietly ignored (stale runs, other
-- people's noise, an empty not-found result).
command wxOnMutableItem pEvent
   if pEvent["publicKey"] is not sKeys["publicKey"] then
      exit wxOnMutableItem
   end if
   if sRole is "join" and pEvent["salt"] is kWxSaltOffer and sPhase is "fetch-offer" then
      wxTryHead pEvent["value"]
   else if sRole is "host" and pEvent["salt"] is kWxSaltAnswer and sPhase is "waiting-answer" then
      wxTryHead pEvent["value"]
   end if
end wxOnMutableItem

-- A head item: direct body, or a chunk list to fetch.
command wxTryHead pValue
   local tKind, tRest, tTarget
   if the number of bytes in pValue < 6 then
      exit wxTryHead -- not found yet / not ours
   end if
   if byte 1 to 4 of pValue is not kWxMagic then
      exit wxTryHead -- some other (or older-format) tenant; ignore
   end if
   put byte 5 of pValue into tKind
   put byte 6 to -1 of pValue into tRest
   if tKind is "D" then
      wxApplyRemote tRest
   else if tKind is "C" then
      put textDecode(tRest, "UTF-8") into tRest
      -- same list as before? the fetch is already running - let it retry
      if tRest is sFetchTargets then
         exit wxTryHead
      end if
      put tRest into sFetchTargets
      put empty into sFetchHave
      put 0 into sFetchTries
      wxLog "Fetching" && (the number of items of sFetchTargets) && "signaling chunks..."
      repeat for each item tTarget in sFetchTargets
         get btDhtGetImmutable(sSession, tTarget)
      end repeat
   end if
end wxTryHead

-- A chunk arrived. Immutable items are content-addressed, so matching the
-- 40-hex target against our want-list is both the routing AND the integrity
-- check. When the set completes, concatenate in HEAD order (identical chunks
-- would share a target; the per-position copy below handles even that).
command wxOnImmutableItem pEvent
   local tTarget, tZip, tOne
   put pEvent["target"] into tTarget
   if sFetchTargets is "" or sFetchTargets is empty then
      exit wxOnImmutableItem
   end if
   if tTarget is not among the items of sFetchTargets then
      exit wxOnImmutableItem
   end if
   if the number of bytes in pEvent["value"] is 0 then
      exit wxOnImmutableItem -- not-found result; the tick will retry
   end if
   put pEvent["value"] into sFetchHave[tTarget]
   -- complete?
   repeat for each item tOne in sFetchTargets
      if sFetchHave[tOne] is empty then
         exit wxOnImmutableItem
      end if
   end repeat
   put "" into tZip
   repeat for each item tOne in sFetchTargets
      put sFetchHave[tOne] after tZip
   end repeat
   wxClearFetch
   wxApplyRemote tZip
end wxOnImmutableItem

command wxRetryFetch
   local tTarget
   if sFetchTargets is "" or sFetchTargets is empty then
      exit wxRetryFetch
   end if
   add 1 to sFetchTries
   if sFetchTries > kWxFetchTriesMax then
      wxLog "Could not fetch every signaling chunk (the publisher may have left). Reconnect on both sides to retry."
      wxClearFetch
      exit wxRetryFetch
   end if
   repeat for each item tTarget in sFetchTargets
      if sFetchHave[tTarget] is empty then
         get btDhtGetImmutable(sSession, tTarget)
      end if
   end repeat
end wxRetryFetch

command wxClearFetch
   put "" into sFetchTargets
   put empty into sFetchHave
   put 0 into sFetchTries
end wxClearFetch

-- Forget what we last published, so a new handshake's republish cadence can
-- never resurrect the previous attempt's blob (the nonce guard would reject
-- it anyway; this just stops the noise at the source).
command wxClearPublished
   put empty into sPubHead
   put empty into sPubChunks
   put 0 into sPubCount
end wxClearPublished

-- ---- apply the far side's blob -----------------------------------------------
-- pZip is the compressed body. Anything malformed is logged once and dropped -
-- the DHT is a public place and this parse is the boundary.
command wxApplyRemote pZip
   local tBody, tNonce, tKind, tSdp, tCut, tRestOffset
   try
      put textDecode(decompress(pZip), "UTF-8") into tBody
   catch tErr
      wxLog "Ignored a signaling blob that would not decompress (stale or foreign)."
      exit wxApplyRemote
   end try
   -- body = nonce LF type LF sdp; split on the first two LFs only (the SDP
   -- itself is full of line breaks, so a lineDelimiter walk would mangle it)
   put offset(numToChar(10), tBody) into tCut
   if tCut is 0 then
      exit wxApplyRemote
   end if
   put char 1 to (tCut - 1) of tBody into tNonce
   delete char 1 to tCut of tBody
   put offset(numToChar(10), tBody) into tCut
   if tCut is 0 then
      exit wxApplyRemote
   end if
   put char 1 to (tCut - 1) of tBody into tKind
   delete char 1 to tCut of tBody
   put tBody into tSdp
   if sRole is "join" then
      wxApplyOffer tNonce, tKind, tSdp
   else
      wxApplyAnswer tNonce, tKind, tSdp
   end if
end wxApplyRemote

-- Join side: a (possibly re-issued) offer. The nonce dedup means the same
-- offer delivered twice - normal, DHT lookups return whatever nodes still
-- hold - is answered exactly once.
command wxApplyOffer pNonce, pKind, pSdp
   local tR
   if pKind is not "offer" then
      exit wxApplyOffer
   end if
   if pNonce is sSeenOfferNonce then
      exit wxApplyOffer -- already answered this exact offer
   end if
   -- a NEW offer while an old peer lingers = the host reconnected; follow it
   if sPeer is not empty and sPeer is not 0 then
      dcFreePeer(sPeer)
      put empty into sPeer
      put empty into sChan
   end if
   put dcCreatePeer(wxIceServers()) into sPeer
   if sPeer is 0 or sPeer is empty then
      wxLog "Could not create a peer connection:" && dcLastError()
      put empty into sPeer
      exit wxApplyOffer
   end if
   put pNonce into sSeenOfferNonce
   put pNonce into sNonce -- echoed into our answer blob
   put "gathering" into sPhase
   send "wxGatherWatch" to me in kWxGatherMs milliseconds
   wxClearPublished
   wxLog "Offer received. Building the answer (STUN)..."
   -- applying a remote OFFER makes libdatachannel produce the answer and start
   -- gathering; our own dcGatheringStateChange==complete publishes it. The
   -- channel itself arrives from the far side via dcChannelIncoming.
   put dcSetRemoteDescription(sPeer, pSdp, "offer") into tR
   if tR is not 0 then
      wxLog "Could not apply the offer:" && dcLastError()
   end if
end wxApplyOffer

-- Host side: an answer. Only the answer to the CURRENT offer counts.
command wxApplyAnswer pNonce, pKind, pSdp
   local tR
   if pKind is not "answer" then
      exit wxApplyAnswer
   end if
   if pNonce is not sNonce then
      exit wxApplyAnswer -- an answer to a previous offer (stale run); ignore
   end if
   if pNonce is sSeenAnswerNonce then
      exit wxApplyAnswer -- already applied
   end if
   put pNonce into sSeenAnswerNonce
   put "connecting" into sPhase
   wxLog "Answer received. Connecting..."
   put dcSetRemoteDescription(sPeer, pSdp, "answer") into tR
   if tR is not 0 then
      wxLog "Could not apply the answer:" && dcLastError()
   end if
end wxApplyAnswer

-- ---- DataChannelXT events (dispatched by dataChannelHelpers) -----------------

on dcGatheringStateChange pEvent
   -- 2 == complete -> the local description now contains every candidate;
   -- publish the one blob (the non-trickle shape; see wxPublishLocal)
   if pEvent["peer"] is sPeer and pEvent["state"] is 2 and sPhase is "gathering" then
      wxPublishLocal
   end if
end dcGatheringStateChange

on dcStateChange pEvent
   local tPair, tPath
   if pEvent["peer"] is not sPeer then
      exit dcStateChange
   end if
   switch pEvent["state"]
      case 2 -- connected
         put dcSelectedCandidatePair(sPeer) into tPair
         put wxPathLabel(tPair) into tPath
         wxLog "Peer connected -" && tPath
         break
      case 3 -- disconnected
      case 4 -- failed
         put "lost" into sPhase
         wxLog "Connection" && dcStateName(pEvent["state"]) & ". Reconnect (both sides) redoes the handshake; add a TURN line first if this keeps happening."
         break
      case 5 -- closed
         if sPhase is not "idle" then
            put "lost" into sPhase
            wxLog "Peer closed."
         end if
         break
   end switch
end dcStateChange

on dcChannelIncoming pEvent
   -- the joiner learns its channel here (the host made its own in wxBeginOffer)
   if pEvent["peer"] is sPeer then
      put pEvent["channel"] into sChan
   end if
end dcChannelIncoming

on dcChannelOpen pEvent
   if pEvent["channel"] is sChan then
      put "open" into sPhase
      wxLog "--- Channel open. The DHT's work is done; everything below is a direct DTLS link. Say something! ---"
   end if
end dcChannelOpen

on dcChannelClosed pEvent
   if pEvent["channel"] is sChan and sPhase is "open" then
      put "lost" into sPhase
      wxLog "Channel closed."
   end if
end dcChannelClosed

on dcMessage pEvent
   if pEvent["channel"] is not sChan then
      exit dcMessage
   end if
   if pEvent["text"] is not empty then
      wxLog pEvent["text"]
   else
      wxLog "(received" && the number of bytes in pEvent["payload"] && "binary bytes)"
   end if
end dcMessage

on dcChannelError pEvent
   wxLog "Channel error:" && pEvent["error"]
end dcChannelError

on dcQueueOverflow pEvent
   -- only possible if the poll loop stalls for a long time (a modal dialog
   -- left open); the native queue sheds newest-first and reports honestly
   wxLog "Warning:" && pEvent["dropped"] && "events were shed while the app was not polling."
end dcQueueOverflow

-- ---- chat --------------------------------------------------------------------
command wxSendMessage
   local tBody, tName, tLine, tR
   put wxTrim(the text of field "wxMsg") into tBody
   if tBody is empty then
      exit wxSendMessage
   end if
   if sChan is empty or sChan is 0 or not dcChannelIsOpen(sChan) then
      wxLog "The channel is not open yet - wait for the open line (or Reconnect)."
      exit wxSendMessage
   end if
   put wxTrim(the text of field "wxName") into tName
   if tName is empty then
      put "me" into tName
   end if
   put tName & ": " & tBody into tLine
   put dcSendText(sChan, tLine) into tR
   if tR is not 0 then
      wxLog "Send failed (" & tR & "):" && dcLastError()
      exit wxSendMessage
   end if
   wxLog "You: " & tBody
   set the text of field "wxMsg" to ""
end wxSendMessage

-- ---- the 1 Hz dashboard ------------------------------------------------------
command wxDashOnce
   local tDht, tState, tLine, tPollErr
   if sChatPolling is not "true" then
      exit wxDashOnce
   end if
   -- Surface a dispatcher failure ONCE, in the demo's own log, and clear it.
   -- The helpers keep the note rather than printing it, because a library
   -- that writes into an app it knows nothing about is a nuisance; this is
   -- the app choosing to show it. Without this, a throw inside the poll
   -- dispatch is invisible: the events simply stop arriving and the window
   -- looks idle, which is how the 2026-08-18 hosting failure presented.
   put dcPollLastError() into tPollErr
   if tPollErr is not empty then
      dcPollClearError
      wxLog "Event dispatch problem:" && tPollErr
      wxLog "(The chat keeps polling. Please report this line - it names the event the engine refused.)"
   end if
   put btDhtState(sSession) into tDht
   if sDhtReady is not "true" and tDht["nodes"] is a number and tDht["nodes"] > 0 then
      put "true" into sDhtReady
   end if
   put "DHT nodes:" && tDht["nodes"] into tLine
   if sRole is not empty then
      put tLine && "| role:" && sRole && "| step:" && sPhase into tLine
   end if
   if sPeer is not empty and sPeer is not 0 then
      put dcPeerState(sPeer) into tState
      put tLine && "| peer:" && dcStateName(tState) into tLine
   end if
   wxSetStatus tLine
   send "wxDashOnce" to me in 1000 milliseconds
end wxDashOnce

-- ---- small helpers -----------------------------------------------------------
command wxSetStatus pText, pKind
   -- the kit's status line under the title band; pKind (ok/warn/bad/empty)
   -- colors it semantically, and the one-argument call sites stay muted
   if there is a field "uiStatus" then
      uiStatus pText, pKind
   end if
end wxSetStatus

command wxLog pMsg
   if there is no field "wxLog" then
      exit wxLog
   end if
   put pMsg & return after field "wxLog"
   set the vscroll of field "wxLog" to the formattedHeight of field "wxLog"
end wxLog

-- Direct or relayed? "typ relay" in either selected candidate means the
-- traffic rides a TURN server; anything else is a genuine direct path.
function wxPathLabel pPair
   if pPair["remoteCandidate"] is empty and pPair["localCandidate"] is empty then
      return "path not reported yet"
   end if
   if pPair["localCandidate"] contains "typ relay" or pPair["remoteCandidate"] contains "typ relay" then
      return "RELAYED through TURN (no direct path was possible)"
   end if
   return "DIRECT path (NAT traversal succeeded)"
end wxPathLabel

-- 8 hex chars; a disambiguator, not a secret (the room code is the secret).
function wxRandomNonce
   local tHex, tI
   put "" into tHex
   repeat with tI = 1 to 8
      put char (random(16)) of "0123456789abcdef" after tHex
   end repeat
   return tHex
end wxRandomNonce

function wxTrim pText
   return word 1 to -1 of pText
end wxTrim
