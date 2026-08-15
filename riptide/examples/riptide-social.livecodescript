script "riptideSocialApp"

-- riptide-social.livecodescript - the Riptide Social flagship stack, phases
-- 1-4: one identity, one public feed, one follow, media over torrents, and
-- serverless encrypted DMs, on two self-building cards.
--
-- WHAT IT WALKS (RIPTIDE-SOCIAL-SPEC.md sections 10.3 phases 1-3): create or
-- unlock the Argon2id-sealed master seed (RIPTKEY1, a 97-byte file the APP
-- owns - the library does no file I/O), derive the identity, show the same
-- key as its two spellings (the 64-hex handle the feed publishes under, and
-- the .onion address), then publish signed posts + a signed BEP44 head over
-- the real DHT, follow another author - fetch their head, walk the post
-- chain back to the zero target, show every authorSig verdict - and MEDIA:
-- attach a file to a post (rsMediaCreate seeds it in place as a trackerless
-- torrent; the post carries only the 40-hex info-hash), and fetch a post's
-- media by hash (rsMediaFetch, sequential so a video can hand off to the
-- system player MID-download; fetching co-seeds, so followers are the CDN).
--
-- HONESTY (the suite convention): phases 1-2 HAVE THEIR PASS - and it was
-- the two-machine one. On 2026-08-13 the maintainer ran this stack on two
-- machines: identities created on both sides, feeds published and received
-- in BOTH directions through the real DHT. That run closed phase 2's
-- done-criterion (a second machine walks the chain and verifies every
-- authorSig - a post renders here only after rsIngestHead/rsIngestPost
-- verify it) and was the first to drive REAL btPoll DHT events into the
-- ingest verifiers, which the harness only ever fed synthetically. The
-- library underneath was already engine-passed (2026-08-12, 133/133).
-- Result text and machine environments were not captured with the report;
-- the record is the maintainer's dated account.
--
-- PHASE 3 IS DONE (2026-08-15, TWO MACHINES): a follower on the second
-- machine fetched and PLAYED an attached video, near instantly. A follower
-- cannot reach a video any other way, so this one result exercised the
-- whole stack end to end on real hardware: machine A published a head and
-- a media-bearing post to the DHT; machine B fetched that head, walked the
-- chain, VERIFIED the authorSig, surfaced the media info-hash from the
-- verified post, joined A's swarm, and played what came back. Phases 1-3
-- through the real UI, not the harness. (Not distinguished in the report:
-- whether playback began MID-download or after a fast complete transfer.)
--
-- PHASE 4 IS DONE TOO (2026-08-15, TWO MACHINES): chat worked BOTH WAYS -
-- the sealed RSI1 intro, the deterministic-role crypto_kx session, and the
-- pairwise secretstream over rp1 all carried real traffic between two
-- identities with NO SERVER anywhere. Reaching the Messages card to do it
-- also CONFIRMS the `go to card` navigation, which had been fixed but
-- unverified after the multi-card conversion shipped `... of me` object
-- references the engine rejects (reported and fixed the same day; see
-- riptide/CLAUDE.md).
--
-- STILL UNEXERCISED HERE (docs/two-machine-runbook.md is the script for
-- each): the CALL (phase 5, built 2026-08-15: a Call button on the
-- Messages card, one-blob SDP signalling as "O"/"A" messages over the
-- encrypted DM rail, then a DIRECT dc channel; STUN only, no TURN, by
-- design), the DEVICES card (phase 6 - the admission handshake, now
-- three-legged: challenge, response, and an RSL1 "W" WELCOME the host
-- signs over the joiner's own response signature, so the admission is
-- MUTUAL and the joiner finally gets a positive, authenticated verdict),
-- and the ANON card (phase 7, needs tor). The navigation and reference
-- forms are the ones the Feed and Messages cards proved; what has never
-- run is these flows themselves.
--
-- SETUP: install sodiumxt (REQUIRED - identity cannot exist without it) and
-- torrentxt (required for publish/fetch; identity still works without), then
-- put the riptide script library in the message path before opening:
--
--    start using stack "riptide"
--
-- ONE SESSION PER PROCESS (torrentxt's rule, runbook trap 5.1): this stack
-- takes THE TorrentXT session. Close every other torrent-flavoured stack
-- first, and restart OXT before re-pasting this script - a recompile orphans
-- the session for the rest of the engine launch.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; tools/check-ui-kit-drift.py holds
-- every copy byte-identical). Change the look in the master, never here.
--
-- SCOPE, said loudly: phases 5-7 are NOT here - no live sessions, no LAN
-- sync, no anonymous persona. The profile-meta head field is still
-- published EMPTY. DMs (phase 4, the Messages card) hold ONE conversation
-- at a time in this demo, in memory only - no history, no offline queue;
-- both ends must be running. Public feeds are PUBLIC: the DHT keeps
-- records until expiry, there is no deletion, and nothing here is
-- anonymity (spec section 9) - media rides ORDINARY BitTorrent swarms and
-- rp1 DM peers connect DIRECTLY, so both show your IP to the other side,
-- exactly as any torrent peer does.
--
-- KEYRING honesty: while unlocked, the identity seed lives in a script
-- local (the spec's one-keyring pattern) and OXT script memory is not
-- locked or reliably zeroed. Lock when done; never use a passphrase that
-- guards anything real in a demo.

-- ---- constants ---------------------------------------------------------------
constant kPollMs = 250
constant kDhtWaitMs = 25000
constant kWalkMax = 12
constant kNameMax = 64
-- phase 6 (LAN): the device-mesh port and a u32 protocol tag the enConnect
-- rider carries, so a mismatched app is refused before the crypto handshake
constant kLanPort = 27099
constant kLanProto = 1
-- phase 7 (anon persona): the onion's virtual + local forward ports
constant kAnonVirtualPort = 80
constant kAnonLocalPort = 8734
-- phase 5 (live sessions): the ICE server for the dc call. STUN only - a
-- TURN relay is a deliberate non-goal for the demo (spec 6); two peers
-- that need one will fail visibly instead of relaying silently.
constant kDmIce = "stun:stun.l.google.com:19302"
-- the intro freshness window (seconds either way): rsVerifyIntro leaves
-- timestamp policy to the app, and this is the app's policy - a captured
-- sealed intro replayed later is refused with its age named, bounding the
-- replay surface the recipient-binding already narrows
constant kDmIntroWindow = 600
-- bumped on any layout change so an existing stack rebuilds (the kit builders
-- re-rect existing controls by name, so no deletion pass is needed)
constant kRaUiVersion = "ra-ui-720p-6"

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

-- ---- state -------------------------------------------------------------------
local sCaps            -- rsProbeCapabilities() array, probed once at open
local sHaveLib         -- "true" once the riptide library answered at all
local sSession         -- THE TorrentXT session handle; this app owns it
local sIdSeed          -- identity seed Data(32) while unlocked (the keyring)
local sHandle          -- the identity's 64-hex public key
local sOnion           -- the identity as .onion (empty without a SHA3 provider)
local sSeq             -- monotonic head sequence (recovered from our own head)
local sMyLatest        -- our latest post's 40-hex target, or empty
local sPolling         -- "true" while the pump chain is armed
local sAwaitOwn        -- "true" while our own head lookup is in flight
local sFollowHandle    -- the author a fetch is walking
local sAwaitHead       -- "true" while their head lookup is in flight
local sWalkNext        -- the post target the walk is waiting on, or empty
local sWalkCount       -- posts verified so far in this walk
local sWaitUntil       -- ms deadline for the outstanding DHT request
local sPendingMediaPath -- file waiting to ride the NEXT post (phase 3)
local sMediaWatch      -- torrent handle of the media item the strip watches
-- phase 4 (DMs). The demo holds ONE conversation at a time, loudly: the
-- library supports any number, but a first pass a maintainer can verify on
-- two machines beats a chat manager nobody has run.
local sDmSeed          -- the DM subkey Data(32) while unlocked
local sDmKeys          -- rsDmKeys array (kx publicKey/secretKey/publicKeyHex)
local sMyPrekeyTarget  -- where my RSK1 prekey record lives (40 hex)
local sDmInbox         -- torrent handle of MY inbox phantom swarm
local sDmTheirInbox    -- torrent handle of the OUTBOUND target's inbox swarm
local sDmTarget        -- the handle I am dialing (outbound), or empty
local sDmTargetKx      -- their VERIFIED prekey kx public (64 hex)
local sDmAwaitDmHead   -- "true" while the outbound head lookup is in flight
local sDmAwaitPrekey   -- the 40-hex prekey target awaited, or empty
local sDmTheirHandle   -- per-peer: the authenticated handle behind an rp1 peer
local sDmRxKey         -- per-peer: session receive key
local sDmTxKey         -- per-peer: session transmit key
local sDmPush          -- per-peer: secretstream push handle (my outbound)
local sDmPull          -- per-peer: secretstream pull handle (their inbound)
local sDmActivePeer    -- the rp1 peer id of the live conversation, or empty
-- phase 6 (LAN device mesh). The master seed is retained while unlocked
-- (the spec's one-keyring pattern: it reconstructs every subkey on demand -
-- the LAN and anon rails both need it), cleared on Lock/close.
local sMasterSeed      -- the 32-byte master while unlocked (the keyring)
local sLanHost         -- the enet host handle (server or client), or empty
local sLanIsServer     -- "true" when hosting the mesh
local sLanName         -- this device's name in the mesh
local sLanServerPeer   -- a client's peer handle to the host
local sLanChallenges   -- server: peer id -> the challenge bytes I sent it
local sLanMyResponse   -- joiner: the response I sent (the welcome binds to it)
local sLanDevices      -- peer id -> the admitted device name
local sLanInit         -- "true" once enInitialize succeeded (teardown guard)
-- phase 7 (anon persona). A separate onion-only identity; the guard keeps
-- it from ever touching the DHT, a torrent, or rp1 (spec 9.3).
local sAnonService     -- the onionxt service handle while published, or empty
-- phase 5 (live sessions). ONE call at a time, riding the ACTIVE DM
-- conversation: the SDP offer/answer travel as kind-"O"/"A" messages
-- inside the established secretstream (the phase-4 rail), then the dc
-- channel is direct peer-to-peer.
local sDcInit          -- "true" once dcInit succeeded (teardown guard)
local sDcPeer          -- the dc peer handle while a call exists, or empty
local sDcChannel       -- the call's data-channel handle once known
local sDcAwaitLocal    -- "O"/"A" while waiting to ship our local SDP

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   raBuild
   raProbe
end openStack

on closeStack
   local tErr
   put empty into sPolling
   raDmTeardown
   raLanLeave
   raAnonStop
   if sSession is an integer and sSession > 0 then
      try
         btStopSession sSession
      catch tErr
         -- extension gone or session already dead; nothing to release
      end try
   end if
   -- the one mandatory enet teardown: destroys any surviving host and
   -- releases the socket layer. Bare command form, guarded so a missing
   -- extension cannot throw out of closeStack.
   if sLanInit is "true" then
      try
         enDeinitialize
      catch tErr
         -- extension not installed; nothing to release
      end try
      put empty into sLanInit
   end if
   -- and datachannelxt's mandatory quit call - BARE, never dcCleanup():
   -- the parenthesised statement spelling is the one-line bug that once
   -- took a whole 4400-line paste down (the suite CLAUDE.md story)
   if sDcInit is "true" then
      try
         dcCleanup
      catch tErr
         -- extension not installed; nothing to release
      end try
      put empty into sDcInit
   end if
   put empty into sSession
   put empty into sDmInbox
   put empty into sDmTheirInbox
   put empty into sMediaWatch
   put empty into sPendingMediaPath
   raClearKeys
end closeStack

on mouseUp
   switch the short name of the target
      case "raCreate"
         raCreate
         break
      case "raUnlock"
         raUnlock
         break
      case "raLock"
         raLock
         break
      case "raPost"
         raPost
         break
      case "raAttach"
         raAttach
         break
      case "raFetch"
         raFetch
         break
      case "raMediaGet"
         raMediaGet
         break
      case "raGoDm"
         go to card "raMessages"
         break
      case "raGoFeed"
         go to card 1
         break
      case "raGoLanFromFeed"
         go to card "raDevices"
         break
      case "raGoFeedFromLan"
         go to card 1
         break
      case "raLanHostBtn"
         raLanHost
         break
      case "raLanJoinBtn"
         raLanJoin
         break
      case "raLanLeaveBtn"
         raLanLeave
         break
      case "raGoAnonFromFeed"
         go to card "raAnon"
         break
      case "raGoFeedFromAnon"
         go to card 1
         break
      case "raAnonReveal"
         raAnonReveal
         break
      case "raAnonPublishBtn"
         raAnonPublish
         break
      case "raAnonStopBtn"
         raAnonStop
         break
      case "raDmStart"
         raDmStart
         break
      case "raDmSend"
         raDmSend
         break
      case "raDmCallBtn"
         raDmCall
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; the kit owns the look) --------------------
-- Two CARDS since phase 4 (the spec's one-stack-rails-behind-tabs answer):
-- card 1 is the feed (phases 1-3), card "raMessages" is the DM rail
-- (phase 4). The stack script owns every handler, so navigation is just
-- `go card`; the pump keeps running wherever you are.
command raBuild
   if the uUiVersion of this stack is kRaUiVersion then
      exit raBuild
   end if
   lock screen
   raBuildFeedCard
   raBuildDmCard
   raBuildLanCard
   raBuildAnonCard
   go to card 1
   set the uUiVersion of this stack to kRaUiVersion
   unlock screen
end raBuild

command raBuildFeedCard
   go to card 1
   -- two columns inside the family's 720p budget (1200 x 640, the
   -- check-stack-size.py cap): identity + my feed left, the reading pane right
   uiChrome "Riptide Social - identity + public feed + media (phases 1-4)", 1200, 640
   uiButton "raGoDm", "Messages >", "1080,4,1192,26"
   uiButton "raGoLanFromFeed", "Devices >", "968,4,1074,26"
   uiButton "raGoAnonFromFeed", "Anon >", "872,4,962,26"

   -- 1. identity
   uiSection "raSec1", "1. Identity: one sealed seed, two spellings of one key", "16,58,592,76"
   uiLabel "raIdL1", "key file:", "16,80,90,98", 11
   uiInput "raKeyFile", "94,80,440,100"
   put raKeyPath() into field "raKeyFile"
   uiButton "raCreate", "Create", "446,80,592,104"
   uiLabel "raIdL2", "passphrase:", "16,104,90,122", 11
   uiInput "raPassphrase", "94,104,440,124"
   uiButton "raUnlock", "Unlock", "446,108,516,132"
   uiButton "raLock", "Lock", "524,108,592,132"
   uiArea "raIdOut", "16,130,592,240"

   -- 2. my feed
   uiSection "raSec2", "2. My feed: post, then the signed head republishes", "16,246,592,264"
   uiLabel "raNameL", "display name:", "16,268,110,286", 11
   uiInput "raName", "114,268,340,288"
   put "riptide user" into field "raName"
   uiInput "raCompose", "16,292,440,340"
   uiButton "raPost", "Post", "446,292,592,316"
   uiButton "raAttach", "Attach", "446,320,592,340"
   uiArea "raMyFeed", "16,346,592,562"

   -- 3. follow
   uiSection "raSec3", "3. Follow: fetch a head, walk the chain, verify every signature", "608,58,1184,76"
   uiLabel "raHandleL", "author handle (64 hex):", "608,80,772,98", 11
   uiInput "raHandle", "776,80,1050,100"
   uiButton "raFetch", "Fetch feed", "1056,80,1184,104"
   uiArea "raTheirFeed", "608,110,1184,508"

   -- the phase-3 media strip: a walked post auto-fills the hash; Fetch
   -- joins the swarm sequentially, and the button becomes Play the moment
   -- the on-disk file is openable (mid-download, by design)
   uiLabel "raMediaL", "media hash:", "608,514,694,532", 11
   uiInput "raMediaHash", "698,514,1050,534"
   uiButton "raMediaGet", "Fetch + play", "1056,510,1184,534"
   uiCap "raMediaProg", empty, "608,540,1184,566"

   uiFooter \
         "Phases 1-3: public feeds are public, the DHT keeps records" \
         & " until expiry, nothing here is deletion or anonymity - and" \
         & " media rides ordinary BitTorrent swarms, so seeding or" \
         & " fetching shows your IP to its peers. While unlocked, the" \
         & " identity seed lives in unlocked engine memory: Lock when" \
         & " done, and never reuse a real passphrase in a demo. Phase 3 is" \
         & " done when a follower on a SECOND machine plays a video" \
         & " mid-download.", \
         "16,572,1184,632"
end raBuildFeedCard

command raBuildDmCard
   if there is no card "raMessages" then
      create card
      set the name of this card to "raMessages"
   end if
   go to card "raMessages"
   uiChrome "Riptide Social - Messages (phase 4: encrypted DMs over rp1)", 1200, 640
   uiButton "raGoFeed", "< Feed", "1080,4,1192,26"

   uiSection "raDmSec1", "1. My inbox: the phantom swarm strangers reach you in", "16,58,592,76"
   uiCap "raDmMine", "Unlock on the Feed card first; the inbox derives from your identity.", "16,82,592,124"
   uiArea "raDmLog", "16,130,592,562"

   uiSection "raDmSec2", "2. Conversation: sealed first contact, then a private stream", "608,58,1184,76"
   uiLabel "raDmToL", "to handle (64 hex):", "608,80,748,98", 11
   uiInput "raDmTo", "752,80,1050,100"
   uiButton "raDmStart", "Start DM", "1056,80,1116,104"
   uiButton "raDmCallBtn", "Call", "1122,80,1184,104"
   uiArea "raDmChat", "608,110,1184,498"
   uiInput "raDmMsg", "608,506,1050,528"
   uiButton "raDmSend", "Send", "1056,504,1184,528"

   uiFooter \
         "DMs are end-to-end encrypted (a sealed RSI1 intro, then a" \
         & " secretstream in each direction) - but rp1 peers see your IP," \
         & " exactly as any torrent peer does, and this demo holds ONE" \
         & " conversation at a time. Sessions live in memory only: Lock" \
         & " or close ends them, there is no history. Phase 4 is done" \
         & " when TWO machines exchange authenticated encrypted DMs" \
         & " with no server.", \
         "16,572,1184,632"
end raBuildDmCard

-- Phase 6: the LAN device mesh. Your own devices (all sharing your master
-- seed) meet on the LAN and prove they are yours with the challenge/response
-- above; a stranger on the same Wi-Fi cannot answer. This is enet, not the
-- DHT: host on one device, Join by IP on the others.
command raBuildLanCard
   if there is no card "raDevices" then
      create card
      set the name of this card to "raDevices"
   end if
   go to card "raDevices"
   uiChrome "Riptide Social - Devices (phase 6: your own LAN device mesh)", 1200, 640
   uiButton "raGoFeedFromLan", "< Feed", "1080,4,1192,26"

   uiSection "raLanSec1", "1. This device: host the mesh, or join one on your LAN", "16,58,592,76"
   uiLabel "raLanNameL", "device name:", "16,80,110,98", 11
   uiInput "raLanName", "114,80,340,100"
   put "this device" into field "raLanName"
   uiButton "raLanHostBtn", "Host", "446,80,516,104"
   uiButton "raLanLeaveBtn", "Leave", "524,80,592,104"
   uiLabel "raLanToL", "host address (IP):", "16,108,130,126", 11
   uiInput "raLanTo", "134,108,340,128"
   uiButton "raLanJoinBtn", "Join", "446,108,592,132"
   uiArea "raLanLog", "16,138,592,562"

   uiSection "raLanSec2", "2. Admitted devices (each proved it shares your master seed)", "608,58,1184,76"
   uiArea "raLanDevices", "608,80,1184,562"

   uiFooter \
         "This is your OWN devices only, on one LAN: admission is a" \
         & " signature under a key only a holder of your master seed can" \
         & " derive, so a stranger on the same Wi-Fi is refused. It never" \
         & " touches the internet or your followers. Unlock on the Feed" \
         & " card first. Phase 6 is done when a device that shares the" \
         & " master joins and a stranger is refused.", \
         "16,572,1184,632"
end raBuildLanCard

-- Phase 7: the anonymous persona. A separate onion-only identity derived
-- from the same master. This card shows its two spellings and, loudly, the
-- deanonymization guard (spec 9.3): the transports it may and may NOT use.
command raBuildAnonCard
   if there is no card "raAnon" then
      create card
      set the name of this card to "raAnon"
   end if
   go to card "raAnon"
   uiChrome "Riptide Social - Anon persona (phase 7: onion-only identity)", 1200, 640
   uiButton "raGoFeedFromAnon", "< Feed", "1080,4,1192,26"

   uiSection "raAnonSec1", "1. Your anonymous persona (a separate key, same master seed)", "16,58,592,76"
   uiButton "raAnonReveal", "Reveal persona 0", "16,80,220,104"
   uiButton "raAnonPublishBtn", "Publish onion", "228,80,432,104"
   uiButton "raAnonStopBtn", "Unpublish", "440,80,592,104"
   uiArea "raAnonOut", "16,110,592,562"

   uiSection "raAnonSec2", "2. The deanonymization guard (9.3): what this persona may touch", "608,58,1184,76"
   uiArea "raAnonGuard", "608,80,1184,562"

   uiFooter \
         "The anon persona is a DIFFERENT key from your public identity," \
         & " reachable ONLY as an onion service - it never publishes to the" \
         & " DHT, seeds a torrent, or opens an rp1 peer (that would leak its" \
         & " IP and link it to your public feed). The guard enforces that at" \
         & " every transport branch. Publishing needs onionxt + a running" \
         & " tor daemon. Cross-posting or correlated timing can still link" \
         & " your personas: the tool removes the easy links, not the hard" \
         & " ones (spec 9).", \
         "16,572,1184,632"
end raBuildAnonCard

-- ---- probes (fail closed, name the missing piece) ----------------------------
command raProbe
   local tErr
   put empty into sHaveLib
   try
      put rsProbeCapabilities() into sCaps
      put "true" into sHaveLib
   catch tErr
      -- library absent; reported below
   end try
   if sHaveLib is not "true" then
      uiStatus "Riptide library NOT in the message path: start using stack" && quote & "riptide" & quote & ".", "bad"
   else if sCaps["canCrypto"] is not true then
      uiStatus "SodiumXT missing, and identity cannot exist without it: install org.openxtalk.library.sodium.", "bad"
   else if sCaps["hasTorrent"] is not true then
      uiStatus "Offline mode (TorrentXT absent): identity works; publish and fetch are disabled.", "warn"
   else if sCaps["hasSha3"] is not true then
      uiStatus "Ready, minus the .onion spelling: no SHA3 provider is loaded (SodiumXT ABI 7 serves sxSha3_256; CoinXT's cxSha3_256 is the fallback).", "warn"
   else
      uiStatus "Ready: SodiumXT + TorrentXT + SHA3 all present.", "ok"
   end if
end raProbe

-- ---- 1. identity -------------------------------------------------------------
command raCreate
   local tPass, tPath, tFolder, tSeed, tSealed, tSaved, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot create an identity without the library and SodiumXT (see above).", "bad"
      exit raCreate
   end if
   put field "raPassphrase" into tPass
   if the number of chars of tPass < 8 then
      put "REFUSED: use a passphrase of at least 8 characters." & return into field "raIdOut"
      exit raCreate
   end if
   put field "raKeyFile" into tPath
   if there is a file tPath then
      put "REFUSED: a key file already exists at" && tPath & return \
            & "Unlock it, or point the key-file field somewhere new." & return into field "raIdOut"
      exit raCreate
   end if
   put false into tFailed
   try
      put rsGenerateMasterSeed() into tSeed
      if tSeed is empty then
         throw "rsGenerateMasterSeed:" && rsLastError()
      end if
      put rsSealMasterSeed(tSeed, tPass) into tSealed
      if tSealed is empty then
         throw "rsSealMasterSeed:" && rsLastError()
      end if
      -- the folder half of the write, itemDelimiter guarded (global state)
      put the itemDelimiter into tSaved
      set the itemDelimiter to "/"
      put item 1 to -2 of tPath into tFolder
      set the itemDelimiter to tSaved
      if tFolder is not empty and there is no folder tFolder then
         create folder tFolder
      end if
      put tSealed into url ("binfile:" & tPath)
      if there is no file tPath then
         throw "the key file did not write; check the path and permissions"
      end if
      put rsIdentitySeed(tSeed) into sIdSeed
      put rsDmSeed(tSeed) into sDmSeed
      put tSeed into sMasterSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tSeed
   put empty into tSealed
   if tFailed then
      put "Create failed:" && tErr & return into field "raIdOut"
      exit raCreate
   end if
   put "Identity CREATED and sealed (RIPTKEY1, Argon2id) at:" && tPath & return into field "raIdOut"
   put "Write the passphrase down; the seed cannot be recovered without it." & return after field "raIdOut"
   raIdentityReady
end raCreate

command raUnlock
   local tPass, tPath, tRaw, tMaster, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot unlock without the library and SodiumXT (see above).", "bad"
      exit raUnlock
   end if
   put field "raPassphrase" into tPass
   put field "raKeyFile" into tPath
   if there is no file tPath then
      put "REFUSED: no key file at" && tPath & return into field "raIdOut"
      exit raUnlock
   end if
   put false into tFailed
   try
      put url ("binfile:" & tPath) into tRaw
      put rsOpenMasterSeed(tRaw, tPass) into tMaster
      if tMaster is empty then
         throw rsLastError()
      end if
      put rsIdentitySeed(tMaster) into sIdSeed
      put rsDmSeed(tMaster) into sDmSeed
      put tMaster into sMasterSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tMaster
   put empty into tRaw
   if tFailed then
      put "Unlock failed:" && tErr & return into field "raIdOut"
      exit raUnlock
   end if
   put "Identity UNLOCKED from" && tPath & return into field "raIdOut"
   raIdentityReady
end raUnlock

-- The shared tail of create and unlock: derive the public spellings, start
-- the session, and recover our head sequence from the DHT rather than from
-- local guesswork (republishing under a LOWER seq than the network holds is
-- refused by BEP44, so the network's number is the truthful one).
command raIdentityReady
   local tOk
   put rsHandleFromSeed(sIdSeed) into sHandle
   put rsOnionFromHandle(sHandle) into sOnion
   put "handle (the key your feed publishes under):" & return & "  " & sHandle & return after field "raIdOut"
   if sOnion is empty then
      put "onion spelling: unavailable (no SHA3 provider; identity still works)" & return after field "raIdOut"
   else
      put "the SAME key as an onion identity:" & return & "  " & sOnion & return after field "raIdOut"
   end if
   put 0 into sSeq
   put empty into sMyLatest
   raStartSession
   if sSession is an integer and sSession > 0 then
      put rsRequestHead(sSession, sHandle) into tOk
      if tOk is true then
         put "true" into sAwaitOwn
         put the milliseconds + kDhtWaitMs into sWaitUntil
         put "recovering your head from the DHT (fresh identities start at seq 0)..." & return after field "raIdOut"
      end if
      raDmBringUp
   else
      put "no session: posts stay disabled until TorrentXT is available." & return after field "raIdOut"
   end if
end raIdentityReady

-- Phase 4 bring-up, run once per unlock: derive the kx prekey pair,
-- publish the signed RSK1 record (so the NEXT head names it and strangers
-- can seal to a key that provably belongs to you), and join your own
-- inbox swarm so intros can arrive. Degrades line by line with reasons -
-- an inbox that failed to join disables inbound DMs and nothing else.
command raDmBringUp
   local tPrekey, tH
   if sDmSeed is empty then
      exit raDmBringUp
   end if
   put rsDmKeys(sDmSeed) into sDmKeys
   if sDmKeys is empty then
      raDmLog "DM keys failed:" && rsLastError()
      exit raDmBringUp
   end if
   put rsBuildPrekey(sDmKeys["publicKeyHex"], sIdSeed) into tPrekey
   if tPrekey is empty then
      raDmLog "prekey record refused:" && rsLastError()
      exit raDmBringUp
   end if
   put rsPublishImmutable(sSession, tPrekey) into sMyPrekeyTarget
   if sMyPrekeyTarget is empty then
      raDmLog "prekey publish failed:" && rsLastError()
   else
      raDmLog "prekey published at" && sMyPrekeyTarget & \
            "; your next post's head will advertise it."
   end if
   put rsDmJoinInbox(sSession, sHandle, raMediaFolder()) into tH
   if tH is empty then
      raDmLog "inbox join failed (inbound DMs disabled):" && rsLastError()
      put empty into sDmInbox
   else
      put tH into sDmInbox
      raDmLog "inbox open at swarm" && rsInboxId(sHandle) & \
            "; strangers who follow you can now knock."
   end if
   raDmPaintMine
end raDmBringUp

-- The inbox status cap on the Messages card, painted on state change.
command raDmPaintMine
   local tLine
   if sHandle is empty then
      put "Unlock on the Feed card first; the inbox derives from your identity." into tLine
   else
      if sMyPrekeyTarget is empty then
         put "prekey: NOT published. " into tLine
      else
         put "prekey: published. " into tLine
      end if
      if sDmInbox is empty then
         put "inbox: NOT joined." after tLine
      else
         put "inbox: joined (swarm" && rsInboxId(sHandle) & ")." after tLine
      end if
   end if
   if there is a field "raDmMine" of card "raMessages" then
      if the text of field "raDmMine" of card "raMessages" \
            is not tLine then
         set the text of field "raDmMine" of card "raMessages" to tLine
      end if
   end if
end raDmPaintMine

command raDmLog pLine
   if there is a field "raDmLog" of card "raMessages" then
      put pLine & return after field "raDmLog" of card "raMessages"
   end if
end raDmLog

command raDmChatLine pLine
   if there is a field "raDmChat" of card "raMessages" then
      put pLine & return after field "raDmChat" of card "raMessages"
   end if
end raDmChatLine

private function raDmShort pHandleHex
   return char 1 to 8 of pHandleHex & "..."
end raDmShort

command raLock
   raClearKeys
   put "LOCKED: the identity seed left memory. Unlock to publish again." & return into field "raIdOut"
end raLock

command raClearKeys
   raDmTeardown
   raLanLeave
   raAnonStop
   put empty into sIdSeed
   put empty into sDmSeed
   put empty into sDmKeys
   put empty into sMasterSeed
   put empty into sHandle
   put empty into sOnion
   put 0 into sSeq
   put empty into sMyLatest
   put empty into sMyPrekeyTarget
   put empty into sAwaitOwn
end raClearKeys

-- End every DM conversation: free the secretstream handles (SodiumXT has
-- no unload hook; sxFreeStream is idempotent) and forget the per-peer
-- state. The inbox swarms stay in the session - they carry no secrets.
command raDmTeardown
   local tPeer, tErr
   raDcTeardown
   repeat for each key tPeer in sDmPush
      try
         sxFreeStream sDmPush[tPeer]
      catch tErr
         -- already gone; free is best-effort by design
      end try
   end repeat
   repeat for each key tPeer in sDmPull
      try
         sxFreeStream sDmPull[tPeer]
      catch tErr
         -- already gone
      end try
   end repeat
   put empty into sDmPush
   put empty into sDmPull
   put empty into sDmTheirHandle
   put empty into sDmRxKey
   put empty into sDmTxKey
   put empty into sDmActivePeer
   put empty into sDmTarget
   put empty into sDmTargetKx
   put empty into sDmAwaitDmHead
   put empty into sDmAwaitPrekey
end raDmTeardown

-- ---- the session + the pump --------------------------------------------------
-- The app owns THE one TorrentXT session (the library never does), pumps
-- btPoll on one standing timer chain, and hands DHT events to the ingest
-- verifiers. Each drain rides a try: a throw out of the pump would break
-- the chain and orphan the session (runbook trap 5.1.1).
command raStartSession
   local tSession, tErr
   if sSession is an integer and sSession > 0 then
      exit raStartSession
   end if
   if sHaveLib is not "true" or sCaps["hasTorrent"] is not true then
      exit raStartSession
   end if
   try
      put btStartSession() into tSession
      if tSession > 0 then
         put tSession into sSession
         btSetBool sSession, "enable_dht", true
         btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
         btDhtAddBootstrap sSession, "router.utorrent.com", 6881
         btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
      end if
   catch tErr
      uiStatus "TorrentXT session failed:" && tErr, "bad"
   end try
   if sSession is an integer and sSession > 0 and sPolling is not "true" then
      put "true" into sPolling
      send "raPoll" to me in kPollMs milliseconds
   end if
end raStartSession

command raPoll
   local tEvents, tEvent, tErr
   if sPolling is not "true" then
      exit raPoll
   end if
   if sSession is an integer and sSession > 0 then
      try
         put btPoll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            raHandleEvent tEvent
         end repeat
      catch tErr
         -- one bad drain must not kill the chain; the next tick retries
      end try
      -- the rp1 stream (DM peers + frames) drains beside the DHT stream;
      -- inert until a swarm is joined, and guarded the same way
      try
         put btRp1Poll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            raHandleRp1 tEvent
         end repeat
      catch tErr
         -- rp1 not enabled yet, or a bad drain; the next tick retries
      end try
   end if
   -- the enet mesh (phase 6) pumps on the SAME timer - enet is pump-or-
   -- nothing, so a missed drain is a stalled mesh; guarded like the others
   if sLanHost is not empty and sLanHost is not 0 then
      try
         put enPoll(sLanHost) into tEvents
         repeat for each element tEvent in tEvents
            raHandleEnet tEvent
         end repeat
      catch tErr
         -- host torn down mid-drain; the next tick sees it gone
      end try
   end if
   -- the dc call (phase 5): drain its events, and ship our one-blob SDP
   -- the moment gathering completes (non-trickle signalling over the DM
   -- stream); guarded like the others so a dc hiccup cannot kill the pump
   if sDcInit is "true" then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            raHandleDc tEvent
         end repeat
      catch tErr
         -- dc torn down mid-drain; the next tick sees it gone
      end try
   end if
   if sDcAwaitLocal is not empty and sDcPeer is not empty then
      try
         raDmCallShipLocal
      catch tErr
         -- a failed ship retries next tick; teardown clears the flag
      end try
   end if
   raExpire
   raMediaPaint
   send "raPoll" to me in kPollMs milliseconds
end raPoll

-- Append a status line to a Feed-card (card 1) field from anywhere, safely.
-- The pump and its handlers run on whatever card the user is viewing, but
-- the feed status fields live only on card 1; a bare cross-card reference
-- throws, and several callers run outside raPoll's try, so a throw here
-- would kill the pump. Qualify to card 1 and guard existence, exactly as
-- raDmLog / raLanLog / raAnonLog do for their own cards.
command raFeedNote pFieldName, pLine
   if there is a field pFieldName of card 1 then
      put pLine & return after field pFieldName of card 1
   end if
end raFeedNote

-- The deadline half: the walk keys every request by the exact target it
-- awaits, so a DHT that never answers expires visibly instead of hanging.
command raExpire
   if the milliseconds <= sWaitUntil then
      exit raExpire
   end if
   -- The pump runs from every card since phase 4, but these status fields
   -- live on the Feed card (card 1). Clear the state flags UNCONDITIONALLY
   -- (they must expire wherever the user is), then land the message on card
   -- 1, guarded - a bare cross-card field reference throws "no such object"
   -- and, because raExpire runs OUTSIDE raPoll's try, that throw would kill
   -- the whole pump. raFeedNote qualifies + guards, like raDmLog et al.
   if sAwaitOwn is "true" then
      put empty into sAwaitOwn
      raFeedNote "raIdOut", "no head found for your key (fresh identity, or not yet propagated); starting at seq 0."
   end if
   if sAwaitHead is "true" then
      put empty into sAwaitHead
      raFeedNote "raTheirFeed", "the DHT did not answer for that head in time; try again in a minute (bootstrap takes a moment)."
   end if
   if sWalkNext is not empty then
      raFeedNote "raTheirFeed", "the DHT did not answer for post target" && sWalkNext && "in time; walk abandoned."
      put empty into sWalkNext
   end if
   if sDmAwaitDmHead is "true" then
      put empty into sDmAwaitDmHead
      raDmLog "no head arrived for" && raDmShort(sDmTarget) && \
            "in time; Start DM again in a minute."
   end if
   if sDmAwaitPrekey is not empty then
      raDmLog "their prekey record did not arrive in time; Start DM again."
      put empty into sDmAwaitPrekey
   end if
end raExpire

command raHandleEvent pEvent
   local tHead, tPost, tNext, tOk, tKeyCount
   switch pEvent["name"]
      case "dhtMutableItem"
         if sDmAwaitDmHead is "true" and sDmTarget is not empty then
            put rsIngestHead(pEvent, sDmTarget) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sDmAwaitDmHead
               if tHead["prekeyTarget"] is rsZeroTarget() then
                  raDmLog raDmShort(sDmTarget) && "publishes no prekey" && \
                        "(their app predates DMs); cannot open a channel."
               else
                  put tHead["prekeyTarget"] into sDmAwaitPrekey
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sDmAwaitPrekey) into tOk
                  if tOk is true then
                     raDmLog "head verified; fetching their prekey record..."
                  else
                     raDmLog "prekey lookup refused:" && rsLastError()
                     put empty into sDmAwaitPrekey
                  end if
               end if
            end if
         end if
         if sAwaitOwn is "true" then
            put rsIngestHead(pEvent, sHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitOwn
               put tHead["seq"] into sSeq
               if tHead["latestPostTarget"] is not rsZeroTarget() then
                  put tHead["latestPostTarget"] into sMyLatest
               end if
               raFeedNote "raIdOut", "recovered your head: seq" && sSeq & comma && "latest post" && tHead["latestPostTarget"]
            end if
         end if
         if sAwaitHead is "true" then
            put rsIngestHead(pEvent, sFollowHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitHead
               raFeedNote "raTheirFeed", "head VERIFIED for" && tHead["displayName"] && "(seq" && tHead["seq"] & ")"
               if tHead["latestPostTarget"] is rsZeroTarget() then
                  raFeedNote "raTheirFeed", "no posts yet."
               else
                  put tHead["latestPostTarget"] into sWalkNext
                  put 0 into sWalkCount
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     raFeedNote "raTheirFeed", "lookup refused:" && rsLastError()
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtImmutableItem"
         if sDmAwaitPrekey is not empty and pEvent["target"] is sDmAwaitPrekey then
            raDmPrekeyArrived pEvent["value"]
         end if
         if sWalkNext is not empty and pEvent["target"] is sWalkNext then
            put rsIngestPost(pEvent, sWalkNext, sFollowHandle) into tPost
            put the number of lines of the keys of tPost into tKeyCount
            if tKeyCount is 0 then
               raFeedNote "raTheirFeed", "post REFUSED (tamper or wrong author):" && rsLastError()
               put empty into sWalkNext
            else
               add 1 to sWalkCount
               raFeedNote "raTheirFeed", "post" && sWalkCount && "[t=" & tPost["timestamp"] & "] authorSig VERIFIED:" && tPost["text"]
               if tPost["mediaTargets"] is not empty then
                  -- a verified post's media list is trustworthy (it sat
                  -- under the authorSig); surface it and pre-fill the strip
                  -- with the first hash so Fetch + play is one click
                  raFeedNote "raTheirFeed", "  media attachment(s):" && tPost["mediaTargets"]
                  -- itemDelimiter is global mutable state; set it right
                  -- before the item read (an earlier handler may have left
                  -- it as "/"), and target card 1's field, guarded
                  set the itemDelimiter to comma
                  if there is a field "raMediaHash" of card 1 then
                     if field "raMediaHash" of card 1 is empty then
                        put item 1 of tPost["mediaTargets"] into \
                              field "raMediaHash" of card 1
                     end if
                  end if
               end if
               put tPost["prevPostTarget"] into tNext
               if tNext is rsZeroTarget() then
                  raFeedNote "raTheirFeed", "chain COMPLETE:" && sWalkCount && "post(s), every authorSig verified."
                  put empty into sWalkNext
               else if sWalkCount >= kWalkMax then
                  raFeedNote "raTheirFeed", "stopped at the" && kWalkMax & "-post demo cap; the chain continues at" && tNext
                  put empty into sWalkNext
               else
                  put tNext into sWalkNext
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     raFeedNote "raTheirFeed", "lookup refused:" && rsLastError()
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtPut"
         -- store confirmations arrive here; the publish calls already
         -- validated synchronously, so these stay quiet in the demo
         break
   end switch
end raHandleEvent

-- ---- 2. my feed --------------------------------------------------------------
command raPost
   local tText, tName, tPost, tTarget, tHead, tOk, tMediaHash
   if sIdSeed is empty then
      uiStatus "Unlock (or create) your identity before posting.", "warn"
      exit raPost
   end if
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot publish.", "bad"
      exit raPost
   end if
   put field "raCompose" into tText
   if tText is empty then
      uiStatus "Nothing to post: the compose field is empty.", "warn"
      exit raPost
   end if
   put field "raName" into tName
   if the number of chars of tName > kNameMax then
      uiStatus "The display name is over the 64-byte head budget; shorten it.", "warn"
      exit raPost
   end if
   -- the attachment seeds FIRST, so a refusal (file moved, torrent error)
   -- aborts the post rather than publishing a hash nobody can fetch
   put empty into tMediaHash
   if sPendingMediaPath is not empty then
      put rsMediaCreate(sSession, sPendingMediaPath) into tMediaHash
      if tMediaHash is empty then
         uiStatus "rsMediaCreate refused:" && rsLastError(), "bad"
         exit raPost
      end if
   end if
   put rsBuildPost(the seconds, sMyLatest, tText, tMediaHash, sIdSeed) into tPost
   if tPost is empty then
      uiStatus "rsBuildPost refused:" && rsLastError(), "bad"
      exit raPost
   end if
   put rsPublishPost(sSession, tPost) into tTarget
   if tTarget is empty then
      uiStatus "rsPublishPost failed:" && rsLastError(), "bad"
      exit raPost
   end if
   add 1 to sSeq
   -- since phase 4 the head advertises the prekey target, so a reader can
   -- open a DM to any author whose post they verified
   put rsBuildHead(sSeq, tName, tTarget, sMyPrekeyTarget, sOnion, empty) \
         into tHead
   if tHead is empty then
      subtract 1 from sSeq
      uiStatus "rsBuildHead refused:" && rsLastError(), "bad"
      exit raPost
   end if
   put rsPublishHead(sSession, tHead, sIdSeed) into tOk
   if tOk is not true then
      subtract 1 from sSeq
      uiStatus "rsPublishHead failed:" && rsLastError(), "bad"
      exit raPost
   end if
   put tTarget into sMyLatest
   if tMediaHash is empty then
      put "seq" && sSeq & ":" && tText & return & "  ->" && tTarget & return before field "raMyFeed"
   else
      put "seq" && sSeq & ":" && tText & return & "  ->" && tTarget & return & "  media seeding:" && tMediaHash & return before field "raMyFeed"
      put empty into sPendingMediaPath
      set the label of button "raAttach" to "Attach"
   end if
   put empty into field "raCompose"
   uiStatus "Posted, and the signed head republished at seq" && sSeq & ".", "ok"
end raPost

-- The attachment picker: choose now, seed at post time (the session is
-- guaranteed then, and a cancelled post leaves nothing seeding). A second
-- click clears the pending choice.
command raAttach
   local tShortName
   if sPendingMediaPath is not empty then
      put empty into sPendingMediaPath
      set the label of button "raAttach" to "Attach"
      uiStatus "Attachment cleared.", empty
      exit raAttach
   end if
   answer file "Choose a photo or video to attach (it seeds from where it is):"
   if it is empty then
      exit raAttach
   end if
   put it into sPendingMediaPath
   -- itemDelimiter is global mutable state; take the leaf, then RESTORE it
   -- to comma (the pump's raHandleEvent reads comma-joined media lists, and
   -- leaving it as "/" made item 1 return the whole list)
   set the itemDelimiter to "/"
   put item -1 of sPendingMediaPath into tShortName
   set the itemDelimiter to comma
   set the label of button "raAttach" to "Clear attach"
   uiStatus "Attached" && quote & tShortName & quote & \
         "- it rides the next post and seeds from its current location.", empty
end raAttach

-- ---- 3. follow ---------------------------------------------------------------
command raFetch
   local tHandle, tOk
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot fetch.", "bad"
      exit raFetch
   end if
   put toLower(word 1 of field "raHandle") into tHandle
   if the number of chars of tHandle is not 64 then
      uiStatus "A handle is 64 hex characters (the author's public key).", "warn"
      exit raFetch
   end if
   put tHandle into sFollowHandle
   put empty into sWalkNext
   put 0 into sWalkCount
   put "true" into sAwaitHead
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put empty into field "raTheirFeed"
   put rsRequestHead(sSession, sFollowHandle) into tOk
   if tOk is not true then
      put empty into sAwaitHead
      uiStatus "rsRequestHead refused:" && rsLastError(), "bad"
      exit raFetch
   end if
   uiStatus "Asking the DHT for" && sFollowHandle & "...", empty
end raFetch

-- ---- phase 4: DMs ------------------------------------------------------------
-- The outbound dance (Start DM): fetch their head -> fetch + VERIFY their
-- RSK1 prekey -> join their inbox swarm -> on each rp1-capable handshake
-- there, send the sealed intro plus my stream header. Only the real
-- recipient can open the seal; a bystander's stream never authenticates
-- (its first ciphertext fails the pull), so wrong peers fall away without
-- a byte of plaintext. Inbound is the mirror: an intro arrives in MY
-- inbox, is opened + verified, and I answer with my own header.

command raDmStart
   local tHandle, tOk
   if sIdSeed is empty or sDmKeys is empty then
      uiStatus "Unlock (or create) your identity before starting a DM.", "warn"
      exit raDmStart
   end if
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: DMs need the network.", "bad"
      exit raDmStart
   end if
   put toLower(word 1 of field "raDmTo" of card "raMessages") \
         into tHandle
   if the number of chars of tHandle is not 64 then
      uiStatus "A handle is 64 hex characters (from the author's Feed card).", "warn"
      exit raDmStart
   end if
   if tHandle is sHandle then
      uiStatus "That is your own handle; DM someone else.", "warn"
      exit raDmStart
   end if
   put tHandle into sDmTarget
   put empty into sDmTargetKx
   put "true" into sDmAwaitDmHead
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put rsRequestHead(sSession, sDmTarget) into tOk
   if tOk is not true then
      put empty into sDmAwaitDmHead
      uiStatus "rsRequestHead refused:" && rsLastError(), "bad"
      exit raDmStart
   end if
   raDmLog "dialing" && raDmShort(sDmTarget) & ": fetching their head..."
   uiStatus "Fetching their head from the DHT...", empty
end raDmStart

-- Their prekey record arrived: check the content address, verify the
-- author signature, and only then join their inbox swarm. A prekey that
-- fails EITHER check is a swapped key - refusing it here is what keeps
-- first contact readable only by the person the post chain belongs to.
command raDmPrekeyArrived pValue
   local tParsed, tH
   if rsImmutableTarget(pValue) is not sDmAwaitPrekey then
      raDmLog "a prekey answer did not hash to its target; ignored."
      exit raDmPrekeyArrived
   end if
   put empty into sDmAwaitPrekey
   put rsVerifyPrekey(pValue, sDmTarget) into tParsed
   if tParsed is empty then
      raDmLog "their prekey record FAILED verification:" && rsLastError()
      exit raDmPrekeyArrived
   end if
   put tParsed["kxPub"] into sDmTargetKx
   put rsDmJoinInbox(sSession, sDmTarget, raMediaFolder()) into tH
   if tH is empty then
      raDmLog "could not join their inbox swarm:" && rsLastError()
      exit raDmPrekeyArrived
   end if
   put tH into sDmTheirInbox
   raDmLog "prekey VERIFIED; waiting in their inbox swarm for a peer" && \
         "(the DHT introduces you - give it a minute)..."
end raDmPrekeyArrived

-- One rp1 event. Peer ids are stable per connection (the rp1-chat rule);
-- everything DM-shaped is keyed by them.
command raHandleRp1 pEvent
   local tPeer, tFrame, tOpened, tParsed, tPlain, tTag, tErr
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "rp1Handshake"
         if pEvent["supportsRp1"] is not "1" then
            break
         end if
         -- a capable peer in the OUTBOUND target's inbox swarm gets the
         -- sealed intro + my stream header; anyone else is inbound-side
         -- and speaks first
         if sDmTarget is not empty and sDmTargetKx is not empty then
            if pEvent["infoHashV1"] is rsInboxId(sDmTarget) then
               raDmIntroduceTo tPeer
            end if
         end if
         break
      case "rp1Message"
         put rsDmParseFrame(pEvent["payload"]) into tFrame
         if tFrame is empty then
            break
         end if
         switch tFrame["kind"]
            case "I"
               put rsDmOpenIntro(tFrame["payload"], sHandle, sDmSeed) \
                     into tOpened
               if tOpened is empty then
                  raDmLog "an intro arrived that is not for me; ignored" && \
                        "(" & rsLastError() & ")"
                  break
               end if
               -- the freshness window (app policy; the library verifies
               -- authorship and addressing, the app bounds replay in time)
               if tOpened["timestamp"] < the seconds - kDmIntroWindow or \
                     tOpened["timestamp"] > the seconds + kDmIntroWindow then
                  raDmLog "a STALE intro from" && \
                        raDmShort(tOpened["senderHandle"]) && "(" & \
                        the seconds - tOpened["timestamp"] && \
                        "seconds old) was refused - a replay, or a badly" && \
                        "skewed clock."
                  break
               end if
               raDmLog "DM intro from" && raDmShort(tOpened["senderHandle"]) \
                     && "- answering with my stream header."
               raDmSessionUp tPeer, tOpened["senderHandle"], \
                     tOpened["senderKxPub"]
               break
            case "H"
               if sDmRxKey[tPeer] is empty then
                  break
               end if
               try
                  put sxSecretStreamInitPull(sDmRxKey[tPeer], \
                        tFrame["payload"]) into sDmPull[tPeer]
               catch tErr
                  raDmLog "their stream header failed:" && tErr
                  break
               end try
               -- the channel-open moment is also when the compose box
               -- binds to this peer; a peer that never authenticates
               -- (first "M" pull fails) is dropped right back off it
               put tPeer into sDmActivePeer
               raDmChatLine "-- channel open with" && \
                     raDmShort(sDmTheirHandle[tPeer]) && "--"
               break
            case "M"
               if sDmPull[tPeer] is empty then
                  break
               end if
               try
                  put sxSecretStreamPull(sDmPull[tPeer], \
                        tFrame["payload"], empty, tTag) into tPlain
               catch tErr
                  -- wrong peer or tamper: this connection never becomes a
                  -- conversation; drop its DM state, keep the swarm
                  raDmLog "a stream message failed authentication;" && \
                        "dropping that peer."
                  raDmDropPeer tPeer
                  break
               end try
               put rsDmParseMessage(tPlain) into tParsed
               if tParsed is empty then
                  raDmLog "an authenticated but malformed message;" && \
                        "dropping that peer."
                  raDmDropPeer tPeer
                  break
               end if
               if tParsed["kind"] is "T" then
                  raDmChatLine raDmShort(sDmTheirHandle[tPeer]) & ":" && \
                        tParsed["text"]
               else if tParsed["kind"] is "O" then
                  raDmCallIncoming tParsed["text"]
               else if tParsed["kind"] is "A" then
                  raDmCallAnswered tParsed["text"]
               end if
               break
         end switch
         break
      case "rp1PeerDisconnected"
         if sDmTheirHandle[tPeer] is not empty then
            raDmChatLine "-- " & raDmShort(sDmTheirHandle[tPeer]) && \
                  "disconnected --"
         end if
         raDmDropPeer tPeer
         break
   end switch
end raHandleRp1

-- Outbound first contact to one peer in the target's inbox swarm.
command raDmIntroduceTo pPeer
   local tIntro, tSealed, tFrame, tOk
   if sDmTheirHandle[pPeer] is not empty then
      exit raDmIntroduceTo
   end if
   put rsBuildIntro(the seconds, sDmTarget, sDmKeys["publicKeyHex"], \
         sIdSeed) into tIntro
   if tIntro is empty then
      raDmLog "intro build refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   put rsDmSealIntro(tIntro, sDmTargetKx) into tSealed
   if tSealed is empty then
      raDmLog "intro seal refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   put rsDmFrame("I", tSealed) into tFrame
   if tFrame is empty then
      exit raDmIntroduceTo
   end if
   put rsDmSend(sSession, pPeer, tFrame) into tOk
   if tOk is not true then
      raDmLog "intro send refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   raDmLog "sealed intro sent to peer" && pPeer & \
         "; opening my stream side..."
   raDmSessionUp pPeer, sDmTarget, sDmTargetKx
end raDmIntroduceTo

-- Shared by both directions: derive the pairwise session for this peer,
-- start MY push stream, and send its header. The pull side arrives as
-- their "H" frame and is inited in the dispatcher.
command raDmSessionUp pPeer, pTheirHandle, pTheirKxPub
   local tSess, tHeader, tFrame, tOk, tErr
   if sDmPush[pPeer] is not empty then
      exit raDmSessionUp
   end if
   put rsDmSessionKeys(sHandle, sDmKeys, pTheirHandle, pTheirKxPub) \
         into tSess
   if tSess is empty then
      raDmLog "session derivation refused:" && rsLastError()
      exit raDmSessionUp
   end if
   put pTheirHandle into sDmTheirHandle[pPeer]
   put tSess["rx"] into sDmRxKey[pPeer]
   put tSess["tx"] into sDmTxKey[pPeer]
   try
      put sxSecretStreamInitPush(sDmTxKey[pPeer], tHeader) into \
            sDmPush[pPeer]
   catch tErr
      raDmLog "stream init failed:" && tErr
      raDmDropPeer pPeer
      exit raDmSessionUp
   end try
   put rsDmFrame("H", tHeader) into tFrame
   if tFrame is empty then
      raDmLog "header frame refused:" && rsLastError()
      raDmDropPeer pPeer
      exit raDmSessionUp
   end if
   put rsDmSend(sSession, pPeer, tFrame) into tOk
   if tOk is not true then
      raDmLog "header send refused:" && rsLastError()
      raDmDropPeer pPeer
      exit raDmSessionUp
   end if
end raDmSessionUp

-- Forget one peer's DM state, freeing its stream handles (idempotent).
command raDmDropPeer pPeer
   local tErr
   if sDmPush[pPeer] is not empty then
      try
         sxFreeStream sDmPush[pPeer]
      catch tErr
      end try
   end if
   if sDmPull[pPeer] is not empty then
      try
         sxFreeStream sDmPull[pPeer]
      catch tErr
      end try
   end if
   delete variable sDmPush[pPeer]
   delete variable sDmPull[pPeer]
   delete variable sDmTheirHandle[pPeer]
   delete variable sDmRxKey[pPeer]
   delete variable sDmTxKey[pPeer]
   if sDmActivePeer is pPeer then
      put empty into sDmActivePeer
   end if
end raDmDropPeer

command raDmSend
   local tBody, tOk
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      uiStatus "No open conversation yet: Start DM and wait for the" && \
            "channel-open line.", "warn"
      exit raDmSend
   end if
   put field "raDmMsg" of card "raMessages" into tBody
   if tBody is empty then
      exit raDmSend
   end if
   put raDmSendMessage("T", tBody) into tOk
   if tOk is not true then
      uiStatus "send refused:" && rsLastError(), "bad"
      exit raDmSend
   end if
   raDmChatLine "you:" && tBody
   set the text of field "raDmMsg" of card "raMessages" to empty
end raDmSend

-- One message of any kind into the ACTIVE conversation's secretstream.
-- "T" is chat; "O"/"A" carry the phase-5 SDP signalling over the same
-- authenticated encrypted rail (the whole point of the kinds existing).
-- Returns true/false. rsSetError is PRIVATE to the library, so a failure
-- here that is not a library refusal logs its reason to the chat directly
-- (callers guard the no-conversation case before calling).
private function raDmSendMessage pKind, pBody
   local tMsg, tCipher, tFrame, tOk, tErr
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      return false
   end if
   put rsDmMessageBody(pKind, the seconds, pBody) into tMsg
   if tMsg is empty then
      return false
   end if
   try
      put sxSecretStreamPush(sDmPush[sDmActivePeer], tMsg, empty, false) \
            into tCipher
   catch tErr
      raDmChatLine "-- send failed: stream push:" && tErr && "--"
      return false
   end try
   put rsDmFrame("M", tCipher) into tFrame
   if tFrame is empty then
      return false
   end if
   put rsDmSend(sSession, sDmActivePeer, tFrame) into tOk
   return tOk is true
end raDmSendMessage

-- ---- phase 5: the live session (a dc call over the DM rail) ------------------
-- The cold-start problem phase 5 exists to solve is ALREADY solved by
-- phase 4: the secretstream is an authenticated, encrypted, ordered
-- channel between exactly the two of us, so the SDP offer/answer ride it
-- as kind-"O"/"A" messages (no dead drop needed - that design remains in
-- dht-chat for the no-prior-contact case). One-blob signalling: we wait
-- for ICE gathering to COMPLETE, then ship a single SDP carrying its
-- candidates; the far side does the same. libdatachannel auto-negotiates:
-- the caller's first dcCreateChannel triggers the offer, and applying an
-- offer auto-generates the answer. Once the channel opens, the payload
-- path is DIRECT peer-to-peer - the rp1 rail carried only the signalling.

-- Lazily bring datachannelxt up once. Returns "true" or logs why not.
private function raDcEnsureInit
   local tR, tErr
   if sDcInit is "true" then
      return "true"
   end if
   try
      put dcInit() into tR
   catch tErr
      raDmChatLine "-- calls need dataChannelXT (org.openxtalk.library.datachannel); not installed --"
      return "false"
   end try
   if tR is not 0 then
      raDmChatLine "-- dataChannelXT failed to initialise:" && dcLastError() && "--"
      return "false"
   end if
   put "true" into sDcInit
   return "true"
end raDcEnsureInit

-- The Call button: start a call on the active conversation, or hang up.
command raDmCall
   local tChan
   if sDcPeer is not empty then
      raDmChatLine "-- you hung up --"
      get raDmSendMessage("T", "(hung up)")
      raDcTeardown
      exit raDmCall
   end if
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      uiStatus "Open a conversation first: a call rides the DM channel.", "warn"
      exit raDmCall
   end if
   -- the persona guard, at the one branch that opens a NEW transport
   if not rsPersonaAllows(false, "dc") then
      raDmChatLine "-- the guard refused a dc call; this is a bug --"
      exit raDmCall
   end if
   if raDcEnsureInit() is not "true" then
      exit raDmCall
   end if
   put dcCreatePeer(kDmIce) into sDcPeer
   if sDcPeer is 0 or sDcPeer is empty then
      raDmChatLine "-- dcCreatePeer failed:" && dcLastError() && "--"
      put empty into sDcPeer
      exit raDmCall
   end if
   -- the first channel triggers the offer (auto-negotiation)
   put dcCreateChannel(sDcPeer, "riptide-call") into tChan
   if tChan is 0 or tChan is empty then
      raDmChatLine "-- dcCreateChannel failed:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCall
   end if
   put tChan into sDcChannel
   put "O" into sDcAwaitLocal
   raDmChatLine "-- calling: gathering ICE candidates... --"
end raDmCall

-- An SDP offer arrived inside the secretstream (the far side pressed Call).
command raDmCallIncoming pSdp
   local tR
   if sDcPeer is not empty then
      raDmChatLine "-- incoming call ignored: already in one --"
      exit raDmCallIncoming
   end if
   if raDcEnsureInit() is not "true" then
      exit raDmCallIncoming
   end if
   put dcCreatePeer(kDmIce) into sDcPeer
   if sDcPeer is 0 or sDcPeer is empty then
      raDmChatLine "-- dcCreatePeer failed:" && dcLastError() && "--"
      put empty into sDcPeer
      exit raDmCallIncoming
   end if
   put dcSetRemoteDescription(sDcPeer, pSdp, "offer") into tR
   if tR is not 0 then
      raDmChatLine "-- their offer was refused:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCallIncoming
   end if
   -- auto-negotiation generates our answer; ship it when gathering is done
   put "A" into sDcAwaitLocal
   raDmChatLine "-- incoming call: answering (gathering candidates)... --"
end raDmCallIncoming

-- Their answer arrived: apply it and let ICE connect.
command raDmCallAnswered pSdp
   local tR
   if sDcPeer is empty then
      exit raDmCallAnswered
   end if
   put dcSetRemoteDescription(sDcPeer, pSdp, "answer") into tR
   if tR is not 0 then
      raDmChatLine "-- their answer was refused:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCallAnswered
   end if
   raDmChatLine "-- answer applied; connecting... --"
end raDmCallAnswered

-- Ship our one-blob local SDP once ICE gathering completes (called from
-- the pump while sDcAwaitLocal is armed). kGatheringComplete is 2.
command raDmCallShipLocal
   local tSdp, tKind
   if dcGatheringState(sDcPeer) is not 2 then
      exit raDmCallShipLocal
   end if
   put dcLocalDescription(sDcPeer) into tSdp
   if tSdp is empty then
      exit raDmCallShipLocal
   end if
   put sDcAwaitLocal into tKind
   put empty into sDcAwaitLocal
   if raDmSendMessage(tKind, tSdp) is true then
      if tKind is "O" then
         raDmChatLine "-- offer sent over the encrypted DM channel --"
      else
         raDmChatLine "-- answer sent; connecting... --"
      end if
   else
      raDmChatLine "-- could not send the SDP; hang up and retry --"
   end if
end raDmCallShipLocal

-- One dc event (drained by the pump).
command raHandleDc pEvent
   local tPair
   switch pEvent["name"]
      case "dcChannelIncoming"
         -- the callee learns the call channel here; open follows
         put pEvent["channel"] into sDcChannel
         break
      case "dcChannelOpen"
         if pEvent["channel"] is not sDcChannel then
            break
         end if
         put dcSelectedCandidatePair(sDcPeer) into tPair
         raDmChatLine "-- CALL CONNECTED: direct peer-to-peer channel open --"
         if tPair["localCandidate"] is not empty then
            raDmChatLine "--   via" && tPair["localCandidate"] && "--"
         end if
         -- one greeting proves the direct path carries data both ways
         get dcSendText(sDcChannel, "live from" && raDmShort(sHandle))
         break
      case "dcMessage"
         if pEvent["text"] is not empty then
            raDmChatLine "-- call:" && pEvent["text"] && "--"
         end if
         break
      case "dcChannelClosed"
         if pEvent["channel"] is sDcChannel then
            raDmChatLine "-- call ended --"
            raDcTeardown
         end if
         break
      case "dcStateChange"
         -- kPeerStateFailed 4 / kPeerStateClosed 5 end the call; anything
         -- else is progress
         if sDcPeer is not empty and pEvent["peer"] is sDcPeer then
            if pEvent["state"] is 4 or pEvent["state"] is 5 then
               raDmChatLine "-- call failed or closed (state" && \
                     pEvent["state"] & ") --"
               raDcTeardown
            end if
         end if
         break
   end switch
end raHandleDc

-- End the call and free the dc handles (dcFreePeer frees its channels
-- too; idempotent). The DM conversation stays up - only the call dies.
command raDcTeardown
   local tErr
   if sDcPeer is not empty then
      try
         dcFreePeer sDcPeer
      catch tErr
         -- extension gone or peer already freed
      end try
   end if
   put empty into sDcPeer
   put empty into sDcChannel
   put empty into sDcAwaitLocal
end raDcTeardown

-- ---- phase 6: the LAN device mesh --------------------------------------------
-- enet, not the DHT: your devices meet on the LAN and prove they share
-- your master seed. Admission is a first-message challenge/response (the
-- enConnect rider is only a u32 protocol tag). The host challenges every
-- new peer; a peer that answers with a signature the host's OWN master
-- verifies is admitted, everyone else is dropped. All the crypto is the
-- gated rsLan* layer; this is the enet transport around it.

-- Lazily bring enet up once (refcounted global init). Returns "true" on
-- success; fail-closed with a logged reason.
private function raLanEnsureInit
   local tR, tErr
   if sLanInit is "true" then
      return "true"
   end if
   try
      put enInitialize() into tR
   catch tErr
      raLanLog "enetxt is not installed (org.openxtalk.library.enet); the device mesh needs it."
      return "false"
   end try
   if tR is not 0 then
      raLanLog "enetxt failed to initialise:" && enLastError()
      return "false"
   end if
   put "true" into sLanInit
   return "true"
end raLanEnsureInit

command raLanHost
   local tHost, tErr
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the mesh admission needs your master seed.", "warn"
      exit raLanHost
   end if
   if sLanHost is not empty then
      raLanLog "Already on a mesh; Leave first."
      exit raLanHost
   end if
   if raLanEnsureInit() is not "true" then
      exit raLanHost
   end if
   put raLanMyName() into sLanName
   -- bind on EVERY interface ("" - the proven LAN spelling), a small peer
   -- cap, two channels, unmetered
   try
      put enHostCreateServer("", kLanPort, 32, 2, 0, 0) into tHost
   catch tErr
      raLanLog "could not create the host:" && tErr
      exit raLanHost
   end try
   if tHost is empty or tHost is 0 then
      raLanLog "could not create the host:" && enLastError()
      exit raLanHost
   end if
   put tHost into sLanHost
   put "true" into sLanIsServer
   put empty into sLanChallenges
   put empty into sLanDevices
   raLanLog "Hosting the mesh on port" && kLanPort & \
         ". On your other devices, Join this device's LAN IP."
   raLanPaintDevices
end raLanHost

command raLanJoin
   local tIp, tHost, tPeer, tErr
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the mesh admission needs your master seed.", "warn"
      exit raLanJoin
   end if
   if sLanHost is not empty then
      raLanLog "Already on a mesh; Leave first."
      exit raLanJoin
   end if
   put word 1 of field "raLanTo" of card "raDevices" into tIp
   if tIp is empty then
      uiStatus "Type the host device's LAN IP address first.", "warn"
      exit raLanJoin
   end if
   if raLanEnsureInit() is not "true" then
      exit raLanJoin
   end if
   put raLanMyName() into sLanName
   try
      put enHostCreateClient(1, 2, 0, 0) into tHost
   catch tErr
      raLanLog "could not create the client host:" && tErr
      exit raLanJoin
   end try
   if tHost is empty or tHost is 0 then
      raLanLog "could not create the client host:" && enLastError()
      exit raLanJoin
   end if
   put tHost into sLanHost
   put "false" into sLanIsServer
   put empty into sLanDevices
   -- optimistic peer handle now; the enetConnect event confirms it. The
   -- rider is our u32 protocol tag, checked by the host before the crypto.
   try
      put enConnect(sLanHost, tIp, kLanPort, 2, kLanProto) into tPeer
   catch tErr
      raLanLog "connect failed:" && tErr
      raLanLeave
      exit raLanJoin
   end try
   if tPeer is empty or tPeer is 0 then
      raLanLog "connect failed:" && enLastError()
      raLanLeave
      exit raLanJoin
   end if
   put tPeer into sLanServerPeer
   raLanLog "connecting to" && tIp & "; waiting for the host's challenge..."
   raLanPaintDevices
end raLanJoin

command raLanLeave
   local tErr
   if sLanHost is not empty and sLanHost is not 0 then
      try
         enHostDestroy sLanHost
      catch tErr
         -- extension gone or host already dead
      end try
   end if
   put empty into sLanHost
   put empty into sLanIsServer
   put empty into sLanServerPeer
   put empty into sLanChallenges
   put empty into sLanMyResponse
   put empty into sLanDevices
   raLanPaintDevices
end raLanLeave

-- One enet event. The host challenges each new peer; the joiner answers
-- the challenge; the host verifies and admits or drops.
command raHandleEnet pEvent
   local tPeer, tName, tChallenge, tNonce, tResp, tRec, tKind, tErr
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "enetConnect"
         if sLanIsServer is "true" then
            -- refuse a mismatched protocol before spending a challenge
            if pEvent["data"] is not kLanProto then
               raLanLog "refused a peer speaking protocol" && \
                     pEvent["data"] & "; dropping."
               try
                  enDisconnectNow tPeer, 0
               catch tErr
               end try
               break
            end if
            put sxRandomBytes(32) into tNonce
            put rsLanBuildChallenge(sLanName, tNonce) into tChallenge
            if tChallenge is empty then
               raLanLog "challenge build refused:" && rsLastError()
               break
            end if
            put tChallenge into sLanChallenges[tPeer]
            raLanSend tPeer, tChallenge
         end if
         -- a client just waits for the challenge to arrive as a message
         break
      case "enetReceive"
         put rsLanRecordKind(pEvent["payload"]) into tKind
         if tKind is "C" and sLanIsServer is not "true" then
            -- joiner: sign the host's challenge under our master, and keep
            -- the response - the host's welcome must be bound to it
            put rsLanBuildResponse(pEvent["payload"], sLanName, \
                  sMasterSeed) into tResp
            if tResp is empty then
               raLanLog "response build refused:" && rsLastError()
               break
            end if
            put tResp into sLanMyResponse
            raLanSend tPeer, tResp
            raLanLog "answered the host's challenge; awaiting the welcome."
         else if tKind is "W" and sLanIsServer is not "true" then
            -- joiner: the host's welcome must prove IT shares the master,
            -- for THIS handshake (mutual auth - and the positive signal
            -- the joiner previously never got)
            put rsLanVerifyWelcome(pEvent["payload"], sLanMyResponse, \
                  sMasterSeed) into tName
            if tName is empty then
               raLanLog "the host FAILED to prove itself (not your" && \
                     "device):" && rsLastError() & "; leaving."
               raLanLeave
               break
            end if
            put tName into sLanDevices[tPeer]
            raLanLog "ADMITTED - the host" && quote & tName & quote && \
                  "proved it shares your master. Mesh is mutual."
            raLanPaintDevices
         else if tKind is "R" and sLanIsServer is "true" then
            -- host: verify against the challenge WE sent this peer
            put sLanChallenges[tPeer] into tChallenge
            if tChallenge is empty then
               break
            end if
            put rsLanVerifyResponse(pEvent["payload"], tChallenge, \
                  sMasterSeed) into tName
            if tName is empty then
               raLanLog "a peer FAILED admission (not your device):" && \
                     rsLastError() & "; dropping."
               try
                  enDisconnectNow tPeer, 0
               catch tErr
               end try
               delete variable sLanChallenges[tPeer]
               break
            end if
            put tName into sLanDevices[tPeer]
            delete variable sLanChallenges[tPeer]
            raLanLog "admitted" && quote & tName & quote & \
                  "(it proved it shares your master)."
            -- prove ourselves BACK (mutual auth): the welcome is bound to
            -- this joiner's response, so it admits no other session
            put rsLanBuildWelcome(pEvent["payload"], sLanName, sMasterSeed) \
                  into tChallenge
            if tChallenge is empty then
               raLanLog "welcome build refused:" && rsLastError()
            else
               raLanSend tPeer, tChallenge
            end if
            raLanPaintDevices
         end if
         break
      case "enetDisconnect"
         if sLanDevices[tPeer] is not empty then
            raLanLog quote & sLanDevices[tPeer] & quote && "left the mesh."
            delete variable sLanDevices[tPeer]
            raLanPaintDevices
         end if
         if tPeer is sLanServerPeer then
            raLanLog "the host went away; Leave and re-Join to reconnect."
            put empty into sLanServerPeer
         end if
         break
   end switch
end raHandleEnet

-- Which RSL1 record is this (by its 5th byte, the kind), or empty. A
-- lighter touch than a full parse just to route in the dispatcher.
private function rsLanRecordKind pBytes
   if the number of bytes in pBytes < 5 then return empty
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not "RSL1" then
      return empty
   end if
   return textDecode(byte 5 of pBytes, "ASCII")
end rsLanRecordKind

private command raLanSend pPeer, pBytes
   local tErr
   try
      enSend pPeer, 0, pBytes, 0
   catch tErr
      raLanLog "send to peer" && pPeer && "failed:" && tErr
   end try
end raLanSend

private function raLanMyName
   local tName
   put word 1 to -1 of field "raLanName" of card "raDevices" into tName
   if tName is empty then put "device" into tName
   return char 1 to 32 of tName
end raLanMyName

command raLanLog pLine
   if there is a field "raLanLog" of card "raDevices" then
      put pLine & return after field "raLanLog" of card "raDevices"
   end if
end raLanLog

command raLanPaintDevices
   local tRows, tPeer
   if there is no field "raLanDevices" of card "raDevices" then
      exit raLanPaintDevices
   end if
   if sLanHost is empty then
      put "Not on a mesh. Host this device, or Join another by its LAN IP." into tRows
   else if the number of keys of sLanDevices is 0 then
      if sLanIsServer is "true" then
         put "Hosting. No devices admitted yet." into tRows
      else
         put "Joining. Waiting for admission..." into tRows
      end if
   else
      put empty into tRows
      repeat for each key tPeer in sLanDevices
         put sLanDevices[tPeer] & return after tRows
      end repeat
      if the last char of tRows is return then
         delete the last char of tRows
      end if
   end if
   if the text of field "raLanDevices" of card "raDevices" is not tRows then
      set the text of field "raLanDevices" of card "raDevices" to tRows
   end if
end raLanPaintDevices

-- ---- phase 7: the anonymous persona ------------------------------------------
-- Everything here is the gated rsAnon*/rsPersonaAllows layer. Revealing is
-- pure and offline; publishing needs onionxt + tor. The guard panel is a
-- live read of rsPersonaAllows, so it can never drift from the policy the
-- library actually enforces.

command raAnonReveal
   local tHandle, tOnion, tOut
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the anon persona derives from your master seed.", "warn"
      exit raAnonReveal
   end if
   put rsAnonHandle(sMasterSeed, 0) into tHandle
   if tHandle is empty then
      put "Could not derive the anon persona:" && rsLastError() into tOut
   else
      put "anon persona 0 handle (a DIFFERENT key from your public one):" \
            & return & "  " & tHandle & return into tOut
      put rsAnonOnion(sMasterSeed, 0) into tOnion
      if tOnion is empty then
         put "onion address: unavailable (no SHA3 provider loaded)." & return \
               after tOut
      else
         put "reachable ONLY at this onion (share it out of band, never post it):" \
               & return & "  " & tOnion & return after tOut
      end if
      put return & "To an outside observer this key and your public handle" \
            && "are unlinkable - as long as you never cross-post or correlate" \
            && "their timing yourself." after tOut
   end if
   set the text of field "raAnonOut" of card "raAnon" to tOut
   raAnonPaintGuard
end raAnonReveal

-- The guard panel: a LIVE read of rsPersonaAllows for every transport, so
-- what the user sees is exactly what the library enforces.
command raAnonPaintGuard
   local tRows, tT, tList
   put "transport      anon persona   public persona" & return & \
         "---------      ------------   --------------" & return into tRows
   -- every transport the guard knows, so the panel is a TRUE full read (the
   -- feed and media rails were the two an anon persona most needs kept off)
   put "onion,dht,torrent,rp1,enet,dc,feed,media" into tList
   set the itemDelimiter to comma
   repeat for each item tT in tList
      put rsPadRight(tT, 15) after tRows
      if rsPersonaAllows(true, tT) then
         put rsPadRight("allowed", 15) after tRows
      else
         put rsPadRight("REFUSED", 15) after tRows
      end if
      if rsPersonaAllows(false, tT) then
         put "allowed" after tRows
      else
         put "REFUSED" after tRows
      end if
      put return after tRows
   end repeat
   put return & "The anon persona may use ONLY the onion. Every other" & \
         return & "transport is refused fail-closed - that is what keeps" & \
         return & "its .onion unlinkable from your public DHT presence." \
         after tRows
   if there is a field "raAnonGuard" of card "raAnon" then
      if the text of field "raAnonGuard" of card "raAnon" is not tRows \
            then
         set the text of field "raAnonGuard" of card "raAnon" to tRows
      end if
   end if
end raAnonPaintGuard

private function rsPadRight pText, pWidth
   local tOut
   put pText into tOut
   repeat while the number of chars in tOut < pWidth
      put space after tOut
   end repeat
   return tOut
end rsPadRight

command raAnonPublish
   local tService
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first.", "warn"
      exit raAnonPublish
   end if
   if sCaps["hasOnion"] is not true then
      raAnonLog "onionxt is not installed; the anon persona cannot be served. Install org.openxtalk.library.onion and run a tor daemon."
      exit raAnonPublish
   end if
   if sAnonService is not empty then
      raAnonLog "Already published; Unpublish first."
      exit raAnonPublish
   end if
   -- the guard, asserted at the one branch that could leak: publishing IS
   -- an onion action, which the anon persona is allowed - but we route it
   -- through the same policy the rest of the app uses, so this call site
   -- can never quietly become a non-onion one
   if not rsPersonaAllows(true, "onion") then
      raAnonLog "the guard refused an onion publish - this is a bug, not a normal path."
      exit raAnonPublish
   end if
   put rsAnonCreateService(sMasterSeed, 0, kAnonVirtualPort, kAnonLocalPort) \
         into tService
   if tService is empty then
      raAnonLog "publish failed:" && rsLastError()
      exit raAnonPublish
   end if
   put tService into sAnonService
   raAnonLog "onion service requested (handle" && tService & \
         "); tor publishes the descriptor in a few seconds. Serve your feed at the local port with onion-httpd."
end raAnonPublish

command raAnonStop
   local tErr
   if sAnonService is empty then
      exit raAnonStop
   end if
   try
      oxRemoveService sAnonService
   catch tErr
      -- onionxt gone or service already down; nothing to release
   end try
   put empty into sAnonService
   raAnonLog "anon onion unpublished."
end raAnonStop

command raAnonLog pLine
   if there is a field "raAnonOut" of card "raAnon" then
      put pLine & return after field "raAnonOut" of card "raAnon"
   end if
end raAnonLog

-- ---- phase 3: the media strip ------------------------------------------------
-- One button, two moods. While the watched item is not yet openable the
-- click is Fetch: join the swarm for the hash in the field, sequentially
-- (pieces arrive front-first), and start watching. Once the on-disk file
-- exists for THAT hash the click is Play: hand the file to the system
-- player - mid-download on purpose, which is the phase-3 done-criterion.
-- Fetching your OWN hash lands on the library's find path and plays the
-- original file instantly (the seeder's copy is already complete).
command raMediaGet
   local tHash, tH, tS, tPlayable
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot fetch media.", "bad"
      exit raMediaGet
   end if
   put toLower(word 1 of field "raMediaHash") into tHash
   if tHash is empty then
      uiStatus "Paste a 40-hex media info-hash first (a walked post fills it in).", "warn"
      exit raMediaGet
   end if
   put false into tPlayable
   if sMediaWatch is an integer and sMediaWatch > 0 then
      put rsMediaStatus(sMediaWatch) into tS
      if tS is an array then
         if toLower(tS["infoHashV1"]) is tHash and tS["filePath"] is not empty then
            if there is a file tS["filePath"] then
               put true into tPlayable
            end if
         end if
      end if
   end if
   if tPlayable is true then
      launch document tS["filePath"]
      uiStatus "Handed" && tS["filePath"] && "to the system player" && \
            "(sequential fetch, so the front of the file is there first).", "ok"
      exit raMediaGet
   end if
   put rsMediaFetch(sSession, tHash, raMediaFolder(), true) into tH
   if tH is empty then
      uiStatus "rsMediaFetch refused:" && rsLastError(), "bad"
      exit raMediaGet
   end if
   put tH into sMediaWatch
   uiStatus "Fetching media" && tHash && "- sequential; co-seeding starts as pieces arrive.", empty
end raMediaGet

-- The media progress line, at the poll cadence and painted only on change
-- (the single-thread playbook): one rsMediaStatus snapshot per tick, one
-- repaint per actual difference.
command raMediaPaint
   local tS, tLine, tPct, tLabel
   if sMediaWatch is not an integer or sMediaWatch <= 0 then
      exit raMediaPaint
   end if
   put rsMediaStatus(sMediaWatch) into tS
   if tS is not an array then
      -- the handle went stale (torrent removed, session gone): stop
      -- watching rather than stomping rsLastError four times a second
      put empty into sMediaWatch
      exit raMediaPaint
   end if
   put the round of (tS["progress"] * 100) into tPct
   put "media:" && tPct & "% -" && tS["numPeers"] && "peer(s)" into tLine
   if tS["isSeeding"] is 1 then
      put " - complete, now co-seeding" after tLine
   end if
   if tS["filePath"] is empty then
      put " - waiting for metadata from the swarm" after tLine
      put "Fetch + play" into tLabel
   else
      put " -" && tS["filePath"] after tLine
      put "Play now" into tLabel
   end if
   -- card-1 controls, but raMediaPaint runs every tick from any card and
   -- OUTSIDE raPoll's try; a bare reference would throw off-card and kill
   -- the pump, so qualify to card 1 and guard existence
   if there is a field "raMediaProg" of card 1 then
      if the text of field "raMediaProg" of card 1 is not tLine then
         set the text of field "raMediaProg" of card 1 to tLine
      end if
   end if
   if there is a button "raMediaGet" of card 1 then
      if the label of button "raMediaGet" of card 1 is not tLabel then
         set the label of button "raMediaGet" of card 1 to tLabel
      end if
   end if
end raMediaPaint

-- Where fetched media lands: a dedicated folder under documents, created
-- on demand - rsMediaFetch refuses a folder that does not exist, so a
-- failed create surfaces there with the path in the message.
function raMediaFolder
   local tBase
   put specialFolderPath("documents") into tBase
   if tBase is empty then
      put specialFolderPath("temporary") into tBase
   end if
   put tBase & "/Riptide-media" into tBase
   if there is no folder tBase then
      create folder tBase
   end if
   return tBase
end raMediaFolder

-- ---- helpers -----------------------------------------------------------------
-- The default key-file location, the family preferences idiom (fall back
-- rather than fail on a platform with no preferences folder). The field is
-- editable, so this is only the starting suggestion.
function raKeyPath
   local tBase
   put specialFolderPath("preferences") into tBase
   if tBase is empty then
      put specialFolderPath("application data") into tBase
   end if
   if tBase is empty then
      put specialFolderPath("documents") into tBase
   end if
   return tBase & "/Riptide/identity.riptkey"
end raKeyPath
