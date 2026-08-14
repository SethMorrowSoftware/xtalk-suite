script "riptideSocialApp"

-- riptide-social.livecodescript - the Riptide Social flagship stack, phases
-- 1-3: one identity, one public feed, one follow, media over torrents, on
-- one self-building card.
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
-- the record is the maintainer's dated account. The PHASE-3 media strip
-- (2026-08-14) is verified statically only; its done-criterion - a
-- follower on a second machine plays a video mid-download - still needs
-- its two-machine pass.
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
-- SCOPE, said loudly: phases 4-7 are NOT here - no DMs (rsInboxId /
-- rsRoomId / rsDmSeed exist but are phase-4 fuel), no live sessions, no
-- LAN sync, no anonymous persona. Prekey and profile-meta head fields are
-- published EMPTY (phase-4 material). Public feeds are PUBLIC: the DHT
-- keeps records until expiry, there is no deletion, and nothing here is
-- anonymity (spec section 9) - and media rides ORDINARY BitTorrent swarms,
-- so seeding or fetching an attachment shows your IP to its peers, exactly
-- as any torrent does.
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
-- bumped on any layout change so an existing stack rebuilds (the kit builders
-- re-rect existing controls by name, so no deletion pass is needed)
constant kRaUiVersion = "ra-ui-720p-2"

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

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   raBuild
   raProbe
end openStack

on closeStack
   local tErr
   put empty into sPolling
   if sSession is an integer and sSession > 0 then
      try
         btStopSession sSession
      catch tErr
         -- extension gone or session already dead; nothing to release
      end try
   end if
   put empty into sSession
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
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; the kit owns the look) --------------------
command raBuild
   if the uUiVersion of this stack is kRaUiVersion then
      exit raBuild
   end if
   lock screen
   -- two columns inside the family's 720p budget (1200 x 640, the
   -- check-stack-size.py cap): identity + my feed left, the reading pane right
   uiChrome "Riptide Social - identity + public feed + media (phases 1-3)", 1200, 640

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
   set the uUiVersion of this stack to kRaUiVersion
   unlock screen
end raBuild

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
   else
      put "no session: posts stay disabled until TorrentXT is available." & return after field "raIdOut"
   end if
end raIdentityReady

command raLock
   raClearKeys
   put "LOCKED: the identity seed left memory. Unlock to publish again." & return into field "raIdOut"
end raLock

command raClearKeys
   put empty into sIdSeed
   put empty into sHandle
   put empty into sOnion
   put 0 into sSeq
   put empty into sMyLatest
   put empty into sAwaitOwn
end raClearKeys

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
   end if
   raExpire
   raMediaPaint
   send "raPoll" to me in kPollMs milliseconds
end raPoll

-- The deadline half: the walk keys every request by the exact target it
-- awaits, so a DHT that never answers expires visibly instead of hanging.
command raExpire
   if the milliseconds <= sWaitUntil then
      exit raExpire
   end if
   if sAwaitOwn is "true" then
      put empty into sAwaitOwn
      put "no head found for your key (fresh identity, or not yet propagated); starting at seq 0." & return after field "raIdOut"
   end if
   if sAwaitHead is "true" then
      put empty into sAwaitHead
      put "the DHT did not answer for that head in time; try again in a minute (bootstrap takes a moment)." & return after field "raTheirFeed"
   end if
   if sWalkNext is not empty then
      put "the DHT did not answer for post target" && sWalkNext && "in time; walk abandoned." & return after field "raTheirFeed"
      put empty into sWalkNext
   end if
end raExpire

command raHandleEvent pEvent
   local tHead, tPost, tNext, tOk, tKeyCount
   switch pEvent["name"]
      case "dhtMutableItem"
         if sAwaitOwn is "true" then
            put rsIngestHead(pEvent, sHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitOwn
               put tHead["seq"] into sSeq
               if tHead["latestPostTarget"] is not rsZeroTarget() then
                  put tHead["latestPostTarget"] into sMyLatest
               end if
               put "recovered your head: seq" && sSeq & comma && "latest post" && tHead["latestPostTarget"] & return after field "raIdOut"
            end if
         end if
         if sAwaitHead is "true" then
            put rsIngestHead(pEvent, sFollowHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitHead
               put "head VERIFIED for" && tHead["displayName"] && "(seq" && tHead["seq"] & ")" & return after field "raTheirFeed"
               if tHead["latestPostTarget"] is rsZeroTarget() then
                  put "no posts yet." & return after field "raTheirFeed"
               else
                  put tHead["latestPostTarget"] into sWalkNext
                  put 0 into sWalkCount
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     put "lookup refused:" && rsLastError() & return after field "raTheirFeed"
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtImmutableItem"
         if sWalkNext is not empty and pEvent["target"] is sWalkNext then
            put rsIngestPost(pEvent, sWalkNext, sFollowHandle) into tPost
            put the number of lines of the keys of tPost into tKeyCount
            if tKeyCount is 0 then
               put "post REFUSED (tamper or wrong author):" && rsLastError() & return after field "raTheirFeed"
               put empty into sWalkNext
            else
               add 1 to sWalkCount
               put "post" && sWalkCount && "[t=" & tPost["timestamp"] & "] authorSig VERIFIED:" && tPost["text"] & return after field "raTheirFeed"
               if tPost["mediaTargets"] is not empty then
                  -- a verified post's media list is trustworthy (it sat
                  -- under the authorSig); surface it and pre-fill the strip
                  -- with the first hash so Fetch + play is one click
                  put "  media attachment(s):" && tPost["mediaTargets"] & return after field "raTheirFeed"
                  if field "raMediaHash" is empty then
                     put item 1 of tPost["mediaTargets"] into field "raMediaHash"
                  end if
               end if
               put tPost["prevPostTarget"] into tNext
               if tNext is rsZeroTarget() then
                  put "chain COMPLETE:" && sWalkCount && "post(s), every authorSig verified." & return after field "raTheirFeed"
                  put empty into sWalkNext
               else if sWalkCount >= kWalkMax then
                  put "stopped at the" && kWalkMax & "-post demo cap; the chain continues at" && tNext & return after field "raTheirFeed"
                  put empty into sWalkNext
               else
                  put tNext into sWalkNext
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     put "lookup refused:" && rsLastError() & return after field "raTheirFeed"
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
   put rsBuildHead(sSeq, tName, tTarget, empty, sOnion, empty) into tHead
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
   set the itemDelimiter to "/"
   put item -1 of sPendingMediaPath into tShortName
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
   if the text of field "raMediaProg" is not tLine then
      set the text of field "raMediaProg" to tLine
   end if
   if the label of button "raMediaGet" is not tLabel then
      set the label of button "raMediaGet" to tLabel
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
