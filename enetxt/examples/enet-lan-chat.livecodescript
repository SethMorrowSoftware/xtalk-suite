script "EnetLanChat"

-- enet-lan-chat.livecodescript - the Part III.7 milestone-3 demo: a LAN chat
-- that exercises the whole enetxt surface in the smallest useful app. One
-- machine clicks HOST (it becomes the server and a chatter); others enter its
-- ip[:port] and JOIN. The server relays every line to every peer with ONE
-- enBroadcast; presence (joins/leaves, with addresses) rides the
-- enetConnect/enetDisconnect events; the status line shows live peer count
-- and (clients) the RTT from enPeerStatus.
--
-- What to look at as a template:
--   * PUMP OR NOTHING - enStartPolling arms the heartbeat; nothing in ENet
--     progresses without it. 33 ms here (real-time feel).
--   * The server is ALSO a client of itself logically: its own lines go
--     straight to the log and out via enBroadcast; client lines go enSendText
--     to the server, which relays them.
--   * Channel 0 carries chat (reliable); the connect data carries a tiny
--     protocol version so mismatched builds refuse loudly.
--   * closeStack calls enDeinitialize - the one mandatory teardown (bare
--     command form: OXT cannot compile a zero-argument `name()` statement).
--
-- HOW TO USE (two+ machines on a LAN, or two stacks on one machine):
--   1. Install the enetxt extension on both. Open enet-helpers and this
--      script as stacks ("start using stack" the helpers first).
--   2. Machine A clicks Host. Machine B types A's ip (port defaults to
--      27099) and clicks Join. Chat.
--
-- HONESTY (the suite convention): every en* call here is individually
-- engine-proven (member selftest green through 2026-08-13), but this stack
-- has not run BETWEEN TWO REAL MACHINES, and its UI was unified onto the
-- suite kit 2026-08-14 - so the stack as a whole is verified statically and
-- needs an OXT pass (the two-machine leg is the closing pass's item 6).
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kEcUiVersion = "enetchat-kit2-1"
-- The connect-data protocol version: the server refuses a mismatch loudly
-- instead of garbling. Bump when the wire meaning of messages changes.
constant kEcProto = 1
constant kEcPort = 27099

-- ---- script-local state (declared at top) ------------------------------------
local sHost             -- our ENet host handle (server or client; 0/empty = none)
local sIsServer         -- "true" when we hosted
local sServerPeer       -- client role: the peer handle to the server
local sPeers            -- server role: array peer -> display address
local sReady            -- "true" once hosting/joined and (client) connected
local sHaveEn           -- "true" once the extension probe succeeded
local sDashOn           -- "true" while the 1 Hz dashboard chain may reschedule

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
   ecBuild
   ecStart
end openStack

on closeStack
   ecStop
end closeStack

on mouseUp
   switch the short name of the target
      case "ecHost"
         ecHost
         break
      case "ecJoin"
         ecJoin
         break
      case "ecLeave"
         ecLeave
         break
      case "ecSend"
         ecSendLine
         break
      default
         pass mouseUp
   end switch
end mouseUp

on returnInField
   switch the short name of the target
      case "ecMsg"
         ecSendLine
         break
      case "ecAddr"
         ecJoin
         break
      default
         pass returnInField
   end switch
end returnInField

-- ---- self-building UI (idempotent; rebuilds on a version bump) ----------------
command ecBuild
   if the uEcUiVersion of this stack is kEcUiVersion and there is a field "ecMsg" then
      exit ecBuild
   end if
   ecClearGeneratedUI
   lock screen
   uiChrome "enetxt LAN chat - reliable UDP, one broadcast, zero servers", 560, 600
   uiCap "ecTagline", "One machine Hosts; everyone else Joins its address. Lines relay through the host over reliable channel 0; joins and leaves announce themselves.", "16,56,544,90"
   -- host / join row
   uiButton "ecHost", "Host (port 27099)", "16,96,180,126"
   uiCap "ecAddrCap", "or join host at ip[:port]:", "190,98,350,116"
   uiInput "ecAddr", "190,120,470,144"
   uiButton "ecJoin", "Join", "476,118,544,148"
   -- name + leave
   uiCap "ecNameCap", "Your name:", "16,156,100,174"
   uiInput "ecName", "100,154,280,178"
   uiButton "ecLeave", "Leave", "416,152,544,180"
   -- log + message box (the status line is the kit's, under the title band)
   uiArea "ecLog", "16,188,544,508"
   uiInput "ecMsg", "16,516,420,542"
   uiButton "ecSend", "Send", "430,514,544,544"
   uiFooter \
         "Chat relays through the host IN THE CLEAR on your LAN - this is a" \
         & " transport demo, not a private messenger. Every en* handler is" \
         & " engine-proven; the two-machine run of THIS stack is the leg" \
         & " still open (runbook item 6).", \
         "16,552,544,596"
   set the uEcUiVersion of this stack to kEcUiVersion
   unlock screen
end ecBuild

command ecClearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card begins with "ec" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card begins with "ec" then
         delete button tI of this card
      end if
   end repeat
   unlock screen
end ecClearGeneratedUI

-- ---- startup / teardown ------------------------------------------------------
command ecStart
   local tR
   -- probe the extension with a guarded call; fail closed with a clear
   -- message when it is missing (the family's SodiumXT probe pattern)
   put empty into sHaveEn
   try
      put enInitialize() into tR
   catch tErr
      ecLog "The enetxt extension is not installed (org.openxtalk.library.enet) - install it and reopen this stack."
      uiStatus "enetxt NOT loaded: install org.openxtalk.library.enet and reopen.", "bad"
      exit ecStart
   end try
   if tR is not 0 then
      ecLog "enetxt failed to initialise:" && enLastError()
      uiStatus "enetxt failed to initialise - see the log.", "bad"
      exit ecStart
   end if
   put "true" into sHaveEn
   ecLog "Ready (" & enLibraryVersion() & "). Host a room or Join one."
   uiStatus "Ready (" & enLibraryVersion() & "). Host, or Join a host's address.", "ok"
   -- arm the dashboard chain ONCE; a re-fired openStack must not stack a
   -- second chain (the dht-chat re-entrancy rule)
   if sDashOn is not "true" then
      put "true" into sDashOn
      send "ecDashOnce" to me in 800 milliseconds
   end if
end ecStart

command ecStop
   put "false" into sDashOn
   if sHost is not empty and sHost is not 0 then
      enHostDestroy sHost
   end if
   put empty into sHost
   put empty into sServerPeer
   put empty into sPeers
   put "false" into sReady
   try
      enStopPolling
   catch tErr
      -- helpers stack already gone; nothing was polling
   end try
   -- the one mandatory teardown: destroys any surviving hosts and releases
   -- the socket layer (bare command form - see the header comment). Guarded
   -- like the ecStart probe: when the extension is missing, quitting the
   -- stack must not throw out of closeStack.
   try
      enDeinitialize
   catch tErr
      -- extension not installed; nothing to release
   end try
end ecStop

-- ---- host / join / leave -----------------------------------------------------
command ecHost
   if sHaveEn is not "true" then
      ecLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit ecHost
   end if
   if sHost is not empty and sHost is not 0 then
      ecLog "Already hosting or joined - Leave first."
      exit ecHost
   end if
   put enHostCreateServer("", kEcPort, 32, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      ecLog "Could not host (port in use?):" && enLastError()
      put empty into sHost
      exit ecHost
   end if
   put "true" into sIsServer
   put empty into sPeers
   put "true" into sReady
   enStartPolling sHost, the long id of this card, 33
   ecLog "Hosting on port" && kEcPort & ". Others: enter this machine's ip and Join."
end ecHost

command ecJoin
   local tAddr, tHost, tPort, tOldDelim
   if sHaveEn is not "true" then
      ecLog "enetxt is not loaded - install org.openxtalk.library.enet and reopen."
      exit ecJoin
   end if
   if sHost is not empty and sHost is not 0 then
      ecLog "Already hosting or joined - Leave first."
      exit ecJoin
   end if
   put ecTrim(the text of field "ecAddr") into tAddr
   if tAddr is empty then
      ecLog "Enter the host's ip (or ip:port) first."
      exit ecJoin
   end if
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to ":"
   put item 1 of tAddr into tHost
   if the number of items of tAddr > 1 then
      put item 2 of tAddr into tPort
   else
      put kEcPort into tPort
   end if
   set the itemDelimiter to tOldDelim
   if tPort is not a number then
      put kEcPort into tPort
   end if
   put enHostCreateClient(1, 2, 0, 0) into sHost
   if sHost is 0 or sHost is empty then
      ecLog "Could not create a client host:" && enLastError()
      put empty into sHost
      exit ecJoin
   end if
   put "false" into sIsServer
   put enConnect(sHost, tHost, tPort, 2, kEcProto) into sServerPeer
   if sServerPeer is 0 or sServerPeer is empty then
      ecLog "Could not start connecting:" && enLastError()
      enHostDestroy sHost
      put empty into sHost
      exit ecJoin
   end if
   enStartPolling sHost, the long id of this card, 33
   ecLog "Connecting to" && tHost & ":" & tPort & "..."
   uiStatus "Connecting to" && tHost & ":" & tPort & "...", empty
   send "ecJoinWatch" to me in 15000 milliseconds
end ecJoin

-- The join watchdog: ENet retries quietly for ~30 s before giving up, so a
-- blocked port reads as a hang. Name the usual causes while it still tries;
-- the definitive verdict arrives in enetDisconnect below.
command ecJoinWatch
   if sIsServer is "true" or sReady is "true" then
      exit ecJoinWatch
   end if
   if sHost is empty or sHost is 0 then
      exit ecJoinWatch
   end if
   ecLog "* still connecting. Usual causes, in order: (1) the HOST machine's firewall blocks inbound UDP" && kEcPort && "- allow the engine for private networks over there; (2) different networks (guest wifi isolates devices); (3) the host is not actually hosting"
end ecJoinWatch

command ecLeave
   if sHost is empty or sHost is 0 then
      exit ecLeave
   end if
   -- polite goodbye when we are a connected client; the host just vanishes
   -- (its peers all see enetDisconnect within their timeout)
   if sIsServer is not "true" and sServerPeer is not empty and sServerPeer is not 0 then
      enDisconnect sServerPeer, 0
      enFlush sHost
   end if
   enStopPolling sHost
   enHostDestroy sHost
   put empty into sHost
   put empty into sServerPeer
   put empty into sPeers
   put "false" into sReady
   ecLog "Left."
   uiStatus "Not connected.", empty
end ecLeave

-- ---- events (dispatched by enet-helpers) -------------------------------------

on enetConnect pEvent
   if sIsServer is "true" then
      -- refuse a protocol mismatch loudly instead of garbling later
      if pEvent["data"] is not kEcProto then
         ecLog "* refused a peer with protocol" && pEvent["data"] && "(we speak" && kEcProto & ")"
         enDisconnectNow pEvent["peer"], 0
         exit enetConnect
      end if
      put pEvent["address"] into sPeers[pEvent["peer"]]
      ecLog "* " & pEvent["address"] && "joined (" & the number of keys of sPeers & " here)"
      ecRelay "* " & pEvent["address"] && "joined"
   else
      put "true" into sReady
      ecLog "* connected - say something!"
      uiStatus "Connected.", "ok"
   end if
end enetConnect

on enetDisconnect pEvent
   if sIsServer is "true" then
      if pEvent["peer"] is among the keys of sPeers then
         ecLog "* " & sPeers[pEvent["peer"]] && "left"
         ecRelay "* " & sPeers[pEvent["peer"]] && "left"
         delete variable sPeers[pEvent["peer"]]
      end if
   else
      if sReady is "true" then
         ecLog "* disconnected from the host"
         uiStatus "Not connected.", empty
      else
         -- no enetConnect ever arrived, so this is ENet giving up on the
         -- CONNECT, not a goodbye - say so, and name the usual causes
         ecLog "* could not connect (ENet gave up). Host-machine firewall (inbound UDP" && kEcPort & ")? Same network? Host actually hosting?"
         uiStatus "Connect FAILED - see the log.", "bad"
      end if
      put "false" into sReady
      -- either way the half-open client host is useless now; release it so
      -- Join works again without a manual Leave first
      enStopPolling sHost
      enHostDestroy sHost
      put empty into sHost
      put empty into sServerPeer
   end if
end enetDisconnect

on enetReceive pEvent
   local tLine
   put textDecode(pEvent["payload"], "utf-8") into tLine
   if sIsServer is "true" then
      -- a client's line: show it here and relay to everyone (including the
      -- sender - the echo doubles as their delivery receipt)
      ecLog tLine
      ecRelay tLine
   else
      ecLog tLine
   end if
end enetReceive

on enetError pEvent
   ecLog "* transport error:" && pEvent["error"]
end enetError

-- ---- sending -----------------------------------------------------------------
command ecSendLine
   local tBody, tName, tLine, tR
   put ecTrim(the text of field "ecMsg") into tBody
   if tBody is empty then
      exit ecSendLine
   end if
   if sHost is empty or sHost is 0 then
      ecLog "Host or Join first."
      exit ecSendLine
   end if
   put ecTrim(the text of field "ecName") into tName
   if tName is empty then
      put "me" into tName
   end if
   put tName & ": " & tBody into tLine
   if sIsServer is "true" then
      ecLog tLine
      ecRelay tLine
   else
      if sReady is not "true" then
         ecLog "Not connected yet."
         exit ecSendLine
      end if
      put enSendText(sServerPeer, 0, tLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         ecLog "Send failed (" & tR & "):" && enLastError()
         exit ecSendLine
      end if
   end if
   set the text of field "ecMsg" to ""
end ecSendLine

-- Server fanout: ONE broadcast reaches every connected peer. The return is
-- checked because a failed relay is invisible to every participant including
-- the host - the one silent failure this demo cannot afford.
command ecRelay pLine
   local tR
   if sIsServer is "true" and sHost is not empty and sHost is not 0 then
      put enBroadcastText(sHost, 0, pLine, 0) into tR -- 0 = reliable
      if tR is not 0 then
         ecLog "* relay FAILED (" & tR & "):" && enLastError()
      end if
   end if
end ecRelay

-- ---- the 1 Hz dashboard ------------------------------------------------------
command ecDashOnce
   local tPS
   -- the chain dies with the stack: ecStop clears the flag and this exit
   -- path does NOT reschedule (the old version rescheduled unconditionally
   -- and outlived closeStack forever)
   if sDashOn is not "true" then
      exit ecDashOnce
   end if
   send "ecDashOnce" to me in 1000 milliseconds
   if sHost is empty or sHost is 0 then
      exit ecDashOnce
   end if
   if sIsServer is "true" then
      uiStatus "Hosting on port" && kEcPort && "-" && the number of keys of sPeers && "peer(s)", "ok"
   else if sServerPeer is not empty and sServerPeer is not 0 then
      put enPeerStatus(sServerPeer) into tPS
      if the number of lines of the keys of tPS is 0 then
         uiStatus "Peer status unavailable.", empty
      else if tPS["state"] is 5 then
         uiStatus "Connected -" && tPS["rtt"] & " ms rtt -" && tPS["address"], "ok"
      else
         uiStatus "Peer state:" && enStateName(tPS["state"]), empty
      end if
   end if
end ecDashOnce

-- ---- small helpers -----------------------------------------------------------
command ecLog pMsg
   if there is no field "ecLog" then
      exit ecLog
   end if
   put pMsg & return after field "ecLog"
   set the vscroll of field "ecLog" to the formattedHeight of field "ecLog"
end ecLog

function ecTrim pText
   return word 1 to -1 of pText
end ecTrim
