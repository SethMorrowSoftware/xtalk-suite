script "SuiteStartHere"

-- start-here.livecodescript - the suite's front door. Download the repo,
-- open THIS file in OpenXTalk (File > Open Stack), and you get a clickable
-- directory of every sample, demo and harness stack, listed by the relative
-- path it has in this repository. Click a path to read what it is and what
-- it needs; Open (or double-click) launches it in place.
--
-- HOW IT RESOLVES PATHS: a script-only stack opened from disk knows its own
-- file path (`the filename of this stack`), and this file lives at the
-- REPOSITORY ROOT - so every entry is simply root + the relative path shown.
-- Nothing is copied or installed; the stacks open from where the download
-- put them. If the status line reports missing files, the download is
-- incomplete or this file was moved out of the repo root.
--
-- WHAT OPENING DOES (the paste ritual, automated): a script-only file is
-- TEXT - on this engine, going to the file does not produce a built
-- window (maintainer-observed on OXT, 2026-08-14). What has worked on
-- every engine pass is the documented ritual: make a stack, set its
-- script, open it. So that is exactly what Open does: read the file,
-- CREATE an invisible host stack named by the file's own `script "..."`
-- line, SET its script (a compile error surfaces right here, with the
-- demo's name on it), GO to it so openStack builds the window, nudge
-- openStack once if the card arrived empty, then reveal the finished
-- window. Helper stacks (the poll dispatchers, the coinxt/riptide script
-- layers) get the same treatment minus the window: created invisibly,
-- then `start using` BY NAME - nothing ever depends on loading a stack
-- FILE. Relaunching raises the running window; a closed one reopens with
-- its script refreshed from disk (never yanked under a running stack).
--
-- WHAT IT CANNOT DO FOR YOU: install the native extensions. Each entry
-- names what it needs (Tools > Extension Manager ids are in each member's
-- README); a demo opened without its extension fails CLOSED with a red
-- status line naming the missing piece - that is the family contract, not
-- a launcher bug.
--
-- WHY THE NUDGE IS SAFE: the openStack nudge fires only when the opened
-- card has ZERO controls - and an unbuilt stack has run nothing: no
-- timers to double-arm, no session to re-open. Every demo's build is
-- idempotent and version-guarded on top of that.
--
-- HONESTY (the suite convention): this launcher is verified statically
-- and needs an OXT pass - but its launch mechanism is no longer a bet:
-- create-stack + set-script + openStack is the exact ritual every
-- recorded engine pass has performed by hand.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kSlUiVersion = "start-here-1"

-- ---- script-local state (declared at top) ------------------------------------
local sLineEntry        -- array: list line number -> registry line ("" = spacer)
local sSelected         -- the currently shown registry line (empty = none)
local sTorrentOpened    -- "true" once a session-holding stack was opened

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
   slBuild
   slProbe
end openStack

on mouseUp
   switch the short name of the target
      case "slList"
         slShowDetail the hilitedLine of field "slList"
         break
      case "slOpen"
         slOpenSelected
         break
      case "slCopyPath"
         slCopyPath
         break
      case "slHelp"
         slHelp
         break
      default
         pass mouseUp
   end switch
end mouseUp

on mouseDoubleUp
   if the short name of the target is "slList" then
      slShowDetail the hilitedLine of field "slList"
      slOpenSelected
   else
      pass mouseDoubleUp
   end if
end mouseDoubleUp

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command slBuild
   if the uSlUiVersion of this stack is kSlUiVersion and there is a field "slList" then
      exit slBuild
   end if
   slClearGeneratedUI
   lock screen
   uiChrome "xTalk Suite - start here", 1200, 640
   -- LEFT: the directory itself - every runnable stack, by repo-relative path
   uiTable "slList", "16,58,676,596", empty
   -- RIGHT: what the selected stack is, wants, and how to launch it
   uiPanel "slCard", "692,58,1184,560"
   uiWrap "slName", "Click a stack on the left.", "708,74,1168,98", 14
   set the textStyle of field "slName" to "bold"
   uiInput "slPath", "708,106,1088,130"
   set the lockText of field "slPath" to true
   set the traversalOn of field "slPath" to false
   set the backgroundColor of field "slPath" to kUiCodeBg
   set the borderColor of field "slPath" to kUiCodeLine
   set the dontWrap of field "slPath" to true
   uiButton "slCopyPath", "Copy", "1096,104,1168,132"
   uiCap "slNeedsCap", "Needs:", "708,142,1168,158"
   uiWrap "slNeeds", empty, "708,160,1168,212", 11
   uiCap "slHelpersCap", "Put in use first (the launcher does this for you):", "708,220,1168,236"
   uiWrap "slHelpers", empty, "708,238,1168,262", 11
   set the textFont of field "slHelpers" to uiMonoFont()
   uiWrap "slDesc", empty, "708,274,1168,380", 11
   uiWrap "slNote", empty, "708,388,1168,472", 11
   set the foregroundColor of field "slNote" to kUiWarn
   uiButton "slOpen", "Open this stack", "708,506,880,538"
   uiButton "slHelp", "Setup help", "896,506,1010,538"
   set the tooltip of button "slOpen" to "Launch the selected stack from where the download put it (double-clicking its path does the same)."
   set the tooltip of button "slHelp" to "The three-step setup, in plain language."
   set the tooltip of field "slPath" to "The file's location inside the downloaded folder - click Copy to copy it."
   uiFooter \
         "ONE torrent session per process: open one torrent-flavoured stack" \
         & " (client, channels, quickshare, rp1 chat, dht chat, riptide," \
         & " nocloud, the harnesses) per OXT launch, and restart OXT between" \
         & " them. Extensions install via Tools > Extension Manager - each" \
         & " member's README has the id. This launcher is verified" \
         & " statically; needs an OXT pass.", \
         "16,604,1184,636"
   slFillList
   set the uSlUiVersion of this stack to kSlUiVersion
   unlock screen
end slBuild

command slClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "sl" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "sl" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card begins with "sl" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end slClearGeneratedUI

-- ---- the registry ------------------------------------------------------------
-- One line per runnable stack: relpath|helpers|needs|note|description.
-- Helpers are repo-relative files put in use BEFORE opening (comma list).
-- "SESSION" in the note marks the one-torrent-session-per-process stacks.
-- Kept by hand ON PURPOSE (a glob cannot write descriptions);
-- tools/check-launcher-registry.py fails the build when this list and the
-- tree disagree, so it cannot rot.
function slRegistry
   local tR
   put "sodiumxt/examples/sodium-demo.livecodescript||the sodiumxt extension (org.openxtalk.library.sodium)||A tabbed tour of the crypto surface: authenticated boxes, signatures, hashing, file crypto, deterministic identities from a passphrase, and key rollover." & return into tR
   put "coinxt/examples/coinxt-demo.livecodescript|coinxt/src/coinxt.livecodescript|the coinxt extension (org.openxtalk.library.coin); sodiumxt only for Generate new|This is a demo, not a wallet - never type a mnemonic that guards real funds.|From a mnemonic to addresses to a SIGNED Bitcoin and Ethereum transaction, every step decoded on screen." & return after tR
   put "enetxt/examples/enet-lan-chat.livecodescript|enetxt/examples/enet-helpers.livecodescript|the enetxt extension (org.openxtalk.library.enet)|Two machines on a LAN (or two stacks on one machine). Allow the engine through the HOST machine's firewall - inbound UDP 27099.|Reliable-UDP LAN chat: one machine Hosts, everyone else Joins its ip. One broadcast relays every line." & return after tR
   put "datachannelxt/examples/datachannel-loopback.livecodescript|datachannelxt/examples/datachannel-helpers.livecodescript|the datachannelxt extension (org.openxtalk.library.datachannel)||Two WebRTC peers in ONE stack, signaling shuttled in script: the whole pipeline (offer/answer, ICE, DTLS, SCTP) with zero infrastructure." & return after tR
   put "datachannelxt/examples/datachannel-dht-chat.livecodescript|datachannelxt/examples/datachannel-helpers.livecodescript|datachannelxt AND torrentxt extensions|Two machines, ideally on different networks. SESSION: uses the one torrent session.|P2P chat where the BitTorrent DHT carries the WebRTC handshake - no server anywhere, then the chat rides the direct encrypted channel." & return after tR
   put "torrentxt/examples/torrent-client.livecodescript||the torrentxt extension (org.openxtalk.library.torrent)|SESSION: one torrent stack per OXT launch.|The full client: add magnets/files/URLs, seed, inspect, tune, save resume data - the whole bt* surface in one window." & return after tR
   put "torrentxt/examples/torrent-dht-channels.livecodescript||torrentxt; sodiumxt for the private-feed features|SESSION: one torrent stack per OXT launch.|Serverless publish/subscribe: signed channel feeds over BEP44 mutable items, with content-addressed releases." & return after tR
   put "torrentxt/examples/torrent-quickshare.livecodescript||torrentxt; sodiumxt for passphrase locking; onionxt + a tor daemon for Private/Tor|SESSION: one torrent stack per OXT launch.|Send a file with a code, privately over Tor, or via a web link - the small sibling of the nocloud app." & return after tR
   put "torrentxt/examples/torrent-rp1-chat.livecodescript||the torrentxt extension|Two machines. SESSION: one torrent stack per OXT launch.|The rp1 transport test: a phantom swarm, a DHT rendezvous, and opaque bytes peer to peer - the channel Riptide rides." & return after tR
   put "onionxt/examples/onionxt-demo-standalone.livecodescript||a local tor daemon with ControlPort 9051 (or Tor Browser: 9151)|GENERATED all-in-one (sources: onionxt/src + onionxt/examples).|Tor from xTalk: control-port status, anonymous dials, hosting v3 onion services, self-authenticating addresses." & return after tR
   put "onionxt/examples/onion-httpd/standalone.livecodescript||a local tor daemon with ControlPort 9051|GENERATED all-in-one.|The smallest onion site: pick a folder, get a .onion, serve it - three buttons." & return after tR
   put "riptide/examples/riptide-social.livecodescript|riptide/src/riptide.livecodescript|sodiumxt AND torrentxt; coinxt or sodiumxt ABI 7 for the onion spelling|Two machines to see propagation. SESSION: uses the one torrent session.|The capstone: one sealed identity, signed public feeds published and verified over the real DHT (phases 1-2)." & return after tR
   put "nocloud/src/nocloudquickshare.livecodescript||torrentxt; sodiumxt and onionxt optional (each feature fails closed without its piece)|SESSION: one torrent stack per OXT launch.|The SHIPPED app: No Cloud Quick Share - send any file to anyone, no server, no account, no size limit." & return after tR
   put "tests/suite-selftest.livecodescript||every extension you have (absent ones SKIP, not fail)|SESSION: starts the one torrent session. GENERATED from the member harnesses.|The whole suite's self-test in one window: ~600 checks across all six members plus riptide, with a Copy-results button for the pass record." & return after tR
   put "tests/suite-closing-pass.livecodescript||varies by section (each says what it needs)|Two machines for sections B-E; a tor binary for F. SESSION.|The remaining runbook legs as a checklist: ENet chat, torrent resume-from-disk, rp1 chat, DHT-signalled WebRTC, live Tor." & return after tR
   put "enetxt/tests/enet-selftest.livecodescript||the enetxt extension||enetxt's own deep harness: the sync surface plus a live async loopback on this machine." & return after tR
   put "datachannelxt/tests/datachannel-selftest.livecodescript||the datachannelxt extension||datachannelxt's own deep harness: stale-handle surface plus a live in-process loopback." & return after tR
   put "torrentxt/tests/torrent-selftest.livecodescript||the torrentxt extension|SESSION: one torrent stack per OXT launch.|torrentxt's own deep harness: 96 checks over the whole bt* surface." & return after tR
   put "coinxt/tests/coin-selftest.livecodescript|coinxt/src/coinxt.livecodescript|the coinxt extension||coinxt's own deep harness: every phase against the published vectors, 230 checks." & return after tR
   return tR
end slRegistry

-- Fill the directory list: full repo-relative paths, mono, with a blank
-- line between top-level groups - the paths themselves ARE the layout.
command slFillList
   local tOldDelim, tLine, tRel, tGroup, tLastGroup, tLineNo, tText
   put empty into sLineEntry
   put empty into tText
   put 0 into tLineNo
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      set the itemDelimiter to "|"
      put item 1 of tLine into tRel
      set the itemDelimiter to "/"
      put item 1 of tRel into tGroup
      set the itemDelimiter to tOldDelim
      if tLastGroup is not empty and tGroup is not tLastGroup then
         put return after tText
         add 1 to tLineNo
      end if
      put tGroup into tLastGroup
      put tRel & return after tText
      add 1 to tLineNo
      put tLine into sLineEntry[tLineNo]
   end repeat
   -- drop the trailing return so the list has no phantom last line
   if the last char of tText is return then
      delete the last char of tText
   end if
   put tText into field "slList"
end slFillList

-- ---- the probe: does the tree around this file look like the repo? -----------
command slProbe
   local tRoot, tOldDelim, tLine, tRel, tMissing, tCount
   put slRoot() into tRoot
   if tRoot is empty then
      uiStatus "Open this stack FROM THE REPO (File > Open Stack on start-here.livecodescript) so relative paths can resolve.", "bad"
      exit slProbe
   end if
   put 0 into tCount
   put empty into tMissing
   put the itemDelimiter into tOldDelim
   repeat for each line tLine in slRegistry()
      set the itemDelimiter to "|"
      put item 1 of tLine into tRel
      set the itemDelimiter to tOldDelim
      if there is a file (tRoot & "/" & tRel) then
         add 1 to tCount
      else
         put tRel & comma & space after tMissing
      end if
   end repeat
   if tMissing is empty then
      uiStatus tCount && "stacks found under" && tRoot & ". Click one; double-click (or Open) launches it.", "ok"
   else
      uiStatus "MISSING from the download:" && char 1 to -3 of tMissing && "- incomplete clone, or this file moved out of the repo root.", "bad"
   end if
end slProbe

-- The repo root is simply the folder this file lives in.
function slRoot
   local tOldDelim, tFile, tRoot
   put the filename of this stack into tFile
   if tFile is empty then
      return empty
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put item 1 to -2 of tFile into tRoot
   set the itemDelimiter to tOldDelim
   return tRoot
end slRoot

-- ---- selection + detail ------------------------------------------------------
command slShowDetail pLine
   local tOldDelim, tEntry, tRel, tHelpers, tNeeds, tNote, tDesc
   if pLine is not a number or sLineEntry[pLine] is empty then
      exit slShowDetail
   end if
   put sLineEntry[pLine] into tEntry
   put tEntry into sSelected
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "|"
   put item 1 of tEntry into tRel
   put item 2 of tEntry into tHelpers
   put item 3 of tEntry into tNeeds
   put item 4 of tEntry into tNote
   put item 5 of tEntry into tDesc
   set the itemDelimiter to tOldDelim
   -- the name is the file's own basename; the path is the point, so it gets
   -- the code box and the Copy button
   uiWrap "slName", slBasename(tRel), "708,74,1168,98", 14
   set the textStyle of field "slName" to "bold"
   put tRel into field "slPath"
   put tNeeds into field "slNeeds"
   if tHelpers is empty then
      put "(nothing - it is self-contained)" into field "slHelpers"
   else
      put tHelpers into field "slHelpers"
   end if
   put tDesc into field "slDesc"
   put tNote into field "slNote"
end slShowDetail

function slBasename pRel
   local tOldDelim, tName
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put the last item of pRel into tName
   set the itemDelimiter to tOldDelim
   return tName
end slBasename

-- Plain-language setup, for someone who has never used the suite. An
-- answer dialog on purpose: it waits until read, and needs no layout.
command slHelp
   answer "GETTING SET UP, in three steps:" & return & return \
         & "1. You already did the hard part - this window opening means" \
         && "the download works." & return & return \
         & "2. Most stacks need one or two EXTENSIONS installed in" \
         && "OpenXTalk (Tools > Extension Manager). Click any stack in the" \
         && "list and its card says exactly which ones it needs; each" \
         && "member folder's README.md has the install walkthrough." \
         & return & return \
         & "3. Click a stack, then Open. If something is missing, the" \
         && "stack itself says so in red at the top - install what it" \
         && "names and reopen it. Nothing here can damage anything:" \
         && "every stack fails safe." titled "Setup help"
end slHelp

command slCopyPath
   local tErr
   if sSelected is empty then
      exit slCopyPath
   end if
   try
      set the clipboardData["text"] to the text of field "slPath"
      uiCopyFlash "slCopyPath"
   catch tErr
      -- clipboard unavailable; the path is on screen to copy by hand
   end try
end slCopyPath

-- ---- launching ---------------------------------------------------------------
command slOpenSelected
   local tOldDelim, tRoot, tRel, tHelpers, tNote, tHelper, tErr, tFailed
   local tHelperName, tName
   if sSelected is empty then
      uiStatus "Click a stack in the list first.", "warn"
      exit slOpenSelected
   end if
   put slRoot() into tRoot
   if tRoot is empty then
      uiStatus "Open this stack FROM THE REPO so relative paths can resolve.", "bad"
      exit slOpenSelected
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "|"
   put item 1 of sSelected into tRel
   put item 2 of sSelected into tHelpers
   put item 4 of sSelected into tNote
   set the itemDelimiter to tOldDelim
   if there is no file (tRoot & "/" & tRel) then
      uiStatus tRel && "is not in the download - see the missing list above.", "bad"
      exit slOpenSelected
   end if
   -- the one-session rule is the family's sharpest trap: warn at the moment
   -- it is about to be walked into, not only in the footer
   if tNote contains "SESSION" then
      if sTorrentOpened is "true" then
         uiStatus "A session-holding stack was already opened from here - if" && slBasename(tRel) && "cannot start a session, restart OXT and open it first.", "warn"
      else
         put "true" into sTorrentOpened
      end if
   end if
   -- helpers first, each named as it goes in use, so a failure points at
   -- the exact file rather than at the demo that later cannot find it.
   -- Same recipe as the demo itself, minus the window: prepared as a named
   -- in-memory stack, then put in use BY NAME.
   put empty into tFailed
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   repeat for each item tHelper in tHelpers
      if tFailed is empty then
         put slPrepareStack(tRoot & "/" & tHelper) into tHelperName
         if tHelperName is empty then
            put tHelper into tFailed
         else
            try
               start using stack tHelperName
            catch tErr
               put tHelper into tFailed
            end try
         end if
      end if
   end repeat
   set the itemDelimiter to tOldDelim
   if tFailed is not empty then
      -- slPrepareStack already painted the specific red status; this line
      -- only covers the start-using throw
      if tErr is not empty then
         uiStatus "Could not put" && tFailed && "in use:" && tErr, "bad"
      end if
      exit slOpenSelected
   end if
   -- now the stack itself: prepare, open (openStack builds the window),
   -- nudge once if the card arrived empty, then reveal the finished window
   put slPrepareStack(tRoot & "/" & tRel) into tName
   if tName is empty then
      exit slOpenSelected
   end if
   try
      go stack tName
   catch tErr
      uiStatus "Could not open" && tName & ":" && tErr, "bad"
      exit slOpenSelected
   end try
   if the number of controls of card 1 of stack tName is 0 then
      send "openStack" to stack tName
   end if
   set the visible of stack tName to true
   if sTorrentOpened is "true" and tNote contains "SESSION" then
      uiStatus "Opened" && tName && "from" && tRel & ". Its own status line takes it from here.", "ok"
   else
      uiStatus "Opened" && tName && "from" && tRel & ".", "ok"
   end if
end slOpenSelected

-- The heart of the launcher: turn a script-only FILE into a live, named,
-- in-memory stack, the way every engine pass has done it by hand. Returns
-- the stack's name, or empty AFTER painting the red status itself.
function slPrepareStack pPath
   local tScript, tName, tErr
   if there is no file pPath then
      uiStatus pPath && "is missing from the download.", "bad"
      return empty
   end if
   put url ("file:" & pPath) into tScript
   if tScript is empty then
      uiStatus "Could not read" && pPath & ":" && the result, "bad"
      return empty
   end if
   put slScriptName(line 1 of tScript, pPath) into tName
   -- the `script "Name"` header is FILE metadata, not script: strip it
   -- before the text becomes a live stack script
   if line 1 of tScript begins with "script " then
      delete line 1 of tScript
   end if
   if there is a stack tName then
      -- already in memory from an earlier launch. If its window is open,
      -- leave it exactly alone (never yank a script under a running
      -- stack); if it is closed, refresh the script from disk so a
      -- freshly pulled repo is what reopens (the stale-in-memory-stack
      -- lesson the suite harness embed exists for).
      if tName is not among the lines of the openStacks then
         try
            set the script of stack tName to tScript
         catch tErr
            uiStatus "The script of" && tName && "did not compile:" && tErr, "bad"
            return empty
         end try
      end if
      return tName
   end if
   try
      create invisible stack tName
      set the script of stack tName to tScript
   catch tErr
      uiStatus "Could not prepare" && tName & ":" && tErr, "bad"
      if there is a stack tName then
         delete stack tName
      end if
      return empty
   end try
   return tName
end slPrepareStack

-- The stack's name comes from the file's own `script "Name"` first line;
-- the file's basename stands in if that line is ever missing or unquoted.
function slScriptName pLine1, pPath
   local tOldDelim, tName
   if pLine1 begins with "script " then
      put char 8 to -1 of pLine1 into tName
      replace quote with empty in tName
      put word 1 to -1 of tName into tName
      if tName is not empty then
         return tName
      end if
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to "/"
   put the last item of pPath into tName
   set the itemDelimiter to tOldDelim
   replace ".livecodescript" with empty in tName
   return tName
end slScriptName

