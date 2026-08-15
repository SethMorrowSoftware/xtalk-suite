script "sodiumDemo"

-- sodium-demo.livecodescript - the SodiumXT showcase stack.
--
-- A professionally laid-out, self-building demo that makes one point clearly:
-- xTalk now has modern, authenticated cryptography that is easy to use. On open
-- it builds a branded, tabbed UI (no design work needed in the IDE), with one
-- panel per capability. Every panel shows the same story: your INPUT, a plain
-- sentence about WHAT the crypto does, the OUTPUT, and a colored STATUS line -
-- green for success, red when authentication correctly REJECTS tampering or a
-- wrong key. That rejection is the headline: unlike the old aes-256-cbc path,
-- these ciphers fail closed.
--
-- Tabs: Secret Key (passphrase encryption), Public Key (X25519 box + sealed
-- box), Signatures (ed25519), Hash/Files (BLAKE2b + C-side file ops), Identity
-- (deterministic keypairs from a passphrase), Rekey (in-session forward
-- secrecy), About (the pitch + a one-click self-test).
--
-- HOW TO USE (requires the SodiumXT extension installed so org.openxtalk
-- .library.sodium is loaded): open as a script-only stack, OR paste this as a
-- stack's script and `send "preOpenStack" to <that stack>`.
--
-- Conventions: bytes cross as Data (textEncode/textDecode at the boundary);
-- functions return a value, commands report; out-params pass a variable. The
-- sx* handlers throw on auth failure, so the demo wraps those in try/catch.
--
-- HONESTY (the suite convention): the sx* surface itself is engine-proven
-- (sxSelfTest ran 71 checks green on-engine 2026-08-12, per sodiumxt/
-- CLAUDE.md), but this DEMO's UI was unified onto the suite kit 2026-08-14,
-- so the stack as a whole is verified statically and needs an OXT re-pass.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kSdUiVersion = "sodium-kit2-1"

local sTab          -- active tab key: enc | key | sign | hash | about
local sEncBlob      -- last sealed base64 blob (Secret Key tab)
local sApk          -- Alice public key (Public Key tab)
local sAsk          -- Alice secret key
local sBpk          -- Bob public key
local sBsk          -- Bob secret key
local sBoxCt        -- last box ciphertext, base64 (canonical, not the display field)
local sSignPk       -- signing public key (Signatures tab)
local sSignSk       -- signing secret key
local sSignSig      -- last signature
local sSignMsg      -- the message that was signed
local sTPass        -- About self-test: passing checks
local sTFail        -- About self-test: failing checks
local sTLog         -- About self-test: running transcript

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

on preOpenStack
   buildUI
   showTab "enc"
end preOpenStack

on closeStack
   -- Deliberately a no-op: nothing persists between handlers here. The only
   -- handles this demo ever opens are secretstreams (Rekey tab, About
   -- self-test), and every one is freed inline on the same click - on the
   -- error paths too, now - so there is nothing left to release at close.
end closeStack

-- ==========================================================================
-- Palette. Kept as a function (its ~40 call sites survive), but every name
-- now maps onto the kit's tokens, so the whole stack recolors from the ONE
-- carried palette above (single-line ifs are checker-safe).
-- ==========================================================================

private function clr pName
   if pName is "headerBg" then return kUiAccent
   if pName is "headerText" then return kUiAccentText
   if pName is "headerSub" then return kUiAccentSub
   if pName is "appBg" then return kUiBg
   if pName is "panelBg" then return kUiCard
   if pName is "accent" then return kUiAccent
   if pName is "accentText" then return kUiAccentText
   if pName is "muted" then return kUiMuted
   if pName is "ink" then return kUiInk
   if pName is "ok" then return kUiOk
   if pName is "bad" then return kUiBad
   if pName is "tabIdle" then return kUiCardLine
   if pName is "mono" then return kUiCodeBg
   return "0,0,0"
end clr

-- ==========================================================================
-- Styled control factory, now THIN WRAPPERS over the kit builders so the ~90
-- per-tab call sites survive unchanged while the look comes from the ONE
-- carried block. Each wrapper keeps only the semantics the kit lacks (per-call
-- color/style, the primary/idle button split styleTab repaints). Names carry a
-- "prefix:role" tag: the prefix is the owning tab (or "ui" for chrome), so
-- showTab can toggle a panel by visibility and mouseUp can route by the role.
-- ==========================================================================

private command makeLabel pName, pRect, pText, pColorName, pSize, pStyle
   uiLabel pName, pText, pRect, pSize
   set the textStyle of field pName to pStyle
   set the foregroundColor of field pName to clr(pColorName)
end makeLabel

private command makeInput pName, pRect, pText
   uiInput pName, pRect
   put pText into field pName
end makeInput

private command makeMono pName, pRect
   uiArea pName, pRect
end makeMono

private command makeButton pName, pRect, pLabel, pPrimary
   uiButton pName, pLabel, pRect
   -- Flat, script-colored chrome: the primary/idle split (and styleTab's
   -- active-tab repaint) needs the background to actually show, which the
   -- engine's 3D default would swallow.
   set the showName of button pName to true
   set the textSize of button pName to 13
   set the textStyle of button pName to "bold"
   set the threeD of button pName to false
   set the borderWidth of button pName to 0
   set the opaque of button pName to true
   set the autoHilite of button pName to true
   if pPrimary then
      set the backgroundColor of button pName to clr("accent")
      set the foregroundColor of button pName to clr("accentText")
   else
      set the backgroundColor of button pName to clr("tabIdle")
      set the foregroundColor of button pName to clr("ink")
   end if
end makeButton

private command setStatus pName, pText, pState
   put pText into field pName
   if pState is "ok" then
      set the foregroundColor of field pName to clr("ok")
   else if pState is "bad" then
      set the foregroundColor of field pName to clr("bad")
   else
      set the foregroundColor of field pName to clr("muted")
   end if
end setStatus

-- Short hex preview of some bytes, for showing keys/digests without a wall of text.
private function shortHex pData, pMax
   local tHex
   put textDecode(sxBin2Hex(pData), "ascii") into tHex
   if the number of chars in tHex > pMax then
      return char 1 to pMax of tHex & "..."
   end if
   return tHex
end shortHex

-- ==========================================================================
-- UI construction.
-- ==========================================================================

on buildUI
   -- Version-guarded rebuild: the old "is there a field" guard could not
   -- tell a current UI from a stale one saved by an earlier script, so a
   -- kit bump would silently keep the pre-kit controls forever.
   if the uSdUiVersion of this stack is kSdUiVersion and there is a field "ui:title" then
      exit buildUI
   end if
   clearGeneratedUI
   lock screen
   -- The chrome is the kit's: stack size, ground, title band, status line
   -- (820x640 is gated by tools/check-stack-size.py).
   uiChrome "SodiumXT - authenticated crypto for xTalk", 820, 640
   -- Probe the library through the ONE status line, so a stack that cannot
   -- run says so in red, at the top, immediately (sxVersion stays inside
   -- the try: with the extension missing the call itself throws).
   try
      uiStatus "Ready (" & sxVersion() & ").", "ok"
   catch tErr
      uiStatus "SodiumXT NOT loaded: install org.openxtalk.library.sodium and reopen.", "bad"
   end try

   -- Tab bar (the demo's own mechanism; styleTab recolors from clr's
   -- kit-token values).
   makeButton "ui:tabEncrypt", "24,76,128,104", "Secret Key", false
   makeButton "ui:tabKeys", "134,76,238,104", "Public Key", false
   makeButton "ui:tabSign", "244,76,348,104", "Signatures", false
   makeButton "ui:tabHash", "354,76,458,104", "Hash/Files", false
   makeButton "ui:tabSeed", "464,76,568,104", "Identity", false
   makeButton "ui:tabRoll", "574,76,678,104", "Rekey", false
   makeButton "ui:tabAbout", "684,76,788,104", "About", false

   -- Content card + honesty footer, both the kit's. The card is created
   -- BEFORE the tab content so it sits behind it in z-order.
   uiPanel "ui:panel", "24,112,796,604"
   uiFooter \
         "Backed by libsodium through the SodiumXT C shim. Every cipher" \
         & " here is authenticated: tampering and wrong keys are rejected." \
         & " The sx* surface is engine-proven (71 checks green 2026-08-12);" \
         & " this kit UI still needs an OXT re-pass.", \
         "24,610,796,638"

   buildEncTab
   buildKeyTab
   buildSignTab
   buildHashTab
   buildSeedTab
   buildRollTab
   buildAboutTab
   set the uSdUiVersion of this stack to kSdUiVersion
   unlock screen
end buildUI

-- The rebuild's clear pass: every generated control's short name carries a
-- ":" (the "prefix:role" scheme), while the kit's own chrome (uiTitle,
-- uiStatus, uiBand, uiFooter) has none - so the colon IS the ownership tag,
-- and the kit controls survive to be restyled in place by uiChrome.
private command clearGeneratedUI
   local tI
   lock screen
   repeat with tI = the number of fields of this card down to 1
      if the short name of field tI of this card contains ":" then
         delete field tI of this card
      end if
   end repeat
   repeat with tI = the number of buttons of this card down to 1
      if the short name of button tI of this card contains ":" then
         delete button tI of this card
      end if
   end repeat
   repeat with tI = the number of graphics of this card down to 1
      if the short name of graphic tI of this card contains ":" then
         delete graphic tI of this card
      end if
   end repeat
   unlock screen
end clearGeneratedUI

on buildEncTab
   makeLabel "enc:h", "48,126,748,154", "Passphrase-based authenticated encryption", "ink", 16, "bold"
   makeLabel "enc:exp", "48,158,748,224", "Step 1: type a passphrase and a message. Step 2: Encrypt seals it (a random salt + Argon2id derive the key; secretbox adds a Poly1305 tag). Step 3: Decrypt to recover it, or Flip a byte then Decrypt to watch the tag reject the tampered ciphertext.", "muted", 12, "plain"
   makeLabel "enc:lp", "48,234,300,256", "Passphrase", "ink", 12, "bold"
   makeInput "enc:pass", "48,258,430,286", "correct horse battery staple"
   makeLabel "enc:lm", "48,294,300,316", "Message", "ink", 12, "bold"
   makeInput "enc:msg", "48,318,748,372", "Meet at the docks at midnight."
   makeButton "enc:encrypt", "48,386,210,418", "1. Encrypt", true
   makeButton "enc:decrypt", "220,386,360,418", "2. Decrypt", false
   makeButton "enc:tamper", "560,386,748,418", "Flip a byte", false
   makeLabel "enc:lo", "48,426,748,446", "Sealed output (base64 of salt + nonce + ciphertext + MAC)", "muted", 11, "plain"
   makeMono "enc:out", "48,448,748,540"
   makeLabel "enc:status", "48,556,748,596", "Type a passphrase and a message, then click 1. Encrypt.", "muted", 12, "plain"
end buildEncTab

on buildKeyTab
   makeLabel "key:h", "48,126,748,154", "Public-key encryption (X25519)", "ink", 16, "bold"
   makeLabel "key:exp", "48,158,748,224", "Alice and Bob each hold a keypair. Alice encrypts to Bob's PUBLIC key; only Bob's SECRET key can open it, and a sealed box even hides who sent it. Work left to right: 1. Generate the keypairs, 2. Encrypt to Bob, 3. Bob opens. Then try the Eavesdropper.", "muted", 12, "plain"
   makeButton "key:gen", "48,234,330,266", "1. Generate keypairs", true
   makeMono "key:keys", "342,234,748,320"
   makeLabel "key:lm", "48,328,400,348", "Message from Alice to Bob", "ink", 12, "bold"
   makeInput "key:msg", "48,350,748,388", "For your eyes only, Bob."
   makeButton "key:box", "48,400,230,432", "2. Encrypt to Bob", true
   makeButton "key:open", "240,400,380,432", "3. Bob opens", false
   makeButton "key:eve", "560,400,748,432", "Eavesdropper tries", false
   makeMono "key:out", "48,442,748,540"
   makeLabel "key:status", "48,556,748,596", "Click 1. Generate keypairs to begin.", "muted", 12, "plain"
end buildKeyTab

on buildSignTab
   makeLabel "sign:h", "48,126,748,154", "Digital signatures (ed25519)", "ink", 16, "bold"
   makeLabel "sign:exp", "48,158,748,224", "Sign a statement with a SECRET key; anyone with the matching PUBLIC key can verify it. Steps: 1. Generate a keypair, 2. Sign the statement, 3. Verify. Then edit one character of the statement and Verify again - the signature no longer matches.", "muted", 12, "plain"
   makeButton "sign:gen", "48,234,330,266", "1. Generate keypair", true
   makeMono "sign:keys", "342,234,748,300"
   makeLabel "sign:lm", "48,308,400,328", "Statement to sign", "ink", 12, "bold"
   makeInput "sign:msg", "48,330,748,370", "I, Alice, authorize the release of version 1.0."
   makeButton "sign:sign", "48,382,210,414", "2. Sign", true
   makeButton "sign:verify", "220,382,360,414", "3. Verify", false
   makeLabel "sign:lo", "48,422,748,442", "Signature (64 bytes, hex)", "muted", 11, "plain"
   makeMono "sign:out", "48,444,748,540"
   makeLabel "sign:status", "48,556,748,596", "Click 1. Generate keypair, then Sign. Edit the statement and Verify to see it fail.", "muted", 12, "plain"
end buildSignTab

on buildHashTab
   makeLabel "hash:h", "48,126,748,154", "Hashing and file encryption", "ink", 16, "bold"
   makeLabel "hash:exp", "48,158,748,214", "BLAKE2b is a fast cryptographic fingerprint - hash text or a whole file (streamed in C, so size is no object). Below, encrypt or decrypt a file with a passphrase: Argon2id derives the key and the salt is stored in the .enc, so the same passphrase decrypts it.", "muted", 12, "plain"
   makeLabel "hash:lm", "48,220,400,240", "Text to hash", "ink", 12, "bold"
   makeInput "hash:msg", "48,242,748,280", "The quick brown fox jumps over the lazy dog"
   makeButton "hash:hash", "48,290,260,320", "Hash text (BLAKE2b-256)", true
   makeMono "hash:out", "48,328,748,416"
   makeLabel "hash:lf", "48,424,748,444", "File encryption (passphrase)", "ink", 13, "bold"
   makeLabel "hash:lpass", "48,452,150,472", "Passphrase", "ink", 12, "bold"
   makeInput "hash:pass", "150,450,470,478", "correct horse battery staple"
   makeButton "hash:hashfile", "48,488,210,518", "Hash a file...", false
   makeButton "hash:encfile", "220,488,400,518", "Encrypt a file...", true
   makeButton "hash:decfile", "410,488,590,518", "Decrypt a file...", false
   makeLabel "hash:status", "48,556,748,596", "Hash text above, or use a passphrase to encrypt or decrypt a file (you choose where to save).", "muted", 12, "plain"
end buildHashTab

on buildSeedTab
   makeLabel "seed:h", "48,126,748,154", "Deterministic keypairs from a passphrase", "ink", 16, "bold"
   makeLabel "seed:exp", "48,158,748,242", "A random keypair must be backed up or it is lost forever. Instead, let your passphrase BE your identity: Argon2id turns it into a 32-byte seed, and the seed derives the keypair. The same passphrase (with the same salt) always rebuilds the EXACT same keys - so there is nothing to store, and you become yourself again on any device just by typing it. One extra character is a wholly different identity.", "muted", 12, "plain"
   makeLabel "seed:lp", "48,250,300,272", "Passphrase", "ink", 12, "bold"
   makeInput "seed:pass", "48,274,430,302", "correct horse battery staple"
   makeButton "seed:derive", "48,314,300,346", "Derive my identity", true
   makeLabel "seed:lo", "48,356,748,376", "Derived public keys (hex) and the proof they are reproducible", "muted", 11, "plain"
   makeMono "seed:out", "48,378,748,540"
   makeLabel "seed:status", "48,556,748,596", "Type a passphrase and click Derive my identity. Derive again to see identical keys; change one character for a new identity.", "muted", 12, "plain"
end buildSeedTab

on buildRollTab
   makeLabel "roll:h", "48,126,748,154", "Forward secrecy: rekeying a live stream", "ink", 16, "bold"
   makeLabel "roll:exp", "48,158,748,242", "A streaming session (secretstream) can rekey in mid-flight. After a rekey the previous key is gone: anyone who copied the key at the start can no longer read what is sent AFTER the rekey. Type two lines - one before the rekey, one after - then run the demo. The up-to-date receiver reads both; a receiver still holding the old key reads only the first, and the post-rekey line is rejected.", "muted", 12, "plain"
   makeLabel "roll:l1", "48,250,400,270", "Message sent BEFORE the rekey", "ink", 12, "bold"
   makeInput "roll:before", "48,272,748,300", "Ready on channel one."
   makeLabel "roll:l2", "48,308,400,328", "Message sent AFTER the rekey", "ink", 12, "bold"
   makeInput "roll:after", "48,330,748,358", "Rotating keys now - any earlier capture is useless."
   makeButton "roll:run", "48,370,320,402", "Run the forward-secrecy demo", true
   makeMono "roll:out", "48,414,748,540"
   makeLabel "roll:status", "48,556,748,596", "Type two messages, then run the demo to watch a rekey lock the old key out of everything that follows.", "muted", 12, "plain"
end buildRollTab

on buildAboutTab
   makeLabel "about:h", "48,126,748,154", "SodiumXT", "ink", 16, "bold"
   makeLabel "about:exp", "48,158,748,300", "SodiumXT brings modern, audited cryptography to OpenXTalk and the xTalk family through one library: authenticated encryption (secretbox and AEAD), Argon2id password hashing, a streaming cipher for large files, X25519 public-key boxes and sealed boxes, ed25519 signatures, BLAKE2b and HMAC-SHA256 hashing, key derivation and key exchange, and a real CSPRNG. It wraps libsodium behind a flat C ABI with a thin LiveCode Builder layer, so any xTalk app can drop its hand-rolled crypto and just call sx*. Every cipher here authenticates: tampering and wrong keys fail closed.", "muted", 12, "plain"
   makeLabel "about:hint", "48,306,748,348", "New here? Open the Secret Key tab, type a passphrase, click Encrypt, then click Flip a byte and Decrypt - watch the tampering get rejected. That rejection is the whole point.", "accent", 12, "bold"
   makeButton "about:selftest", "48,356,300,388", "Run the full self-test", true
   makeMono "about:out", "48,398,748,540"
   makeLabel "about:status", "48,556,748,596", "Click Run the full self-test to check every primitive against the live library.", "muted", 12, "plain"
end buildAboutTab

-- ==========================================================================
-- Tab switching.
-- ==========================================================================

on showTab pKey
   local tI
   local tN
   local tPre
   put pKey into sTab
   set the itemDelimiter to ":"
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI into tN
      put item 1 of tN into tPre
      if tPre is "enc" or tPre is "key" or tPre is "sign" or tPre is "hash" or tPre is "seed" or tPre is "roll" or tPre is "about" then
         set the visible of control tI to (tPre is pKey)
      end if
   end repeat
   restyleTabs
end showTab

on restyleTabs
   styleTab "ui:tabEncrypt", (sTab is "enc")
   styleTab "ui:tabKeys", (sTab is "key")
   styleTab "ui:tabSign", (sTab is "sign")
   styleTab "ui:tabHash", (sTab is "hash")
   styleTab "ui:tabSeed", (sTab is "seed")
   styleTab "ui:tabRoll", (sTab is "roll")
   styleTab "ui:tabAbout", (sTab is "about")
end restyleTabs

on styleTab pName, pActive
   if pActive then
      set the backgroundColor of button pName to clr("accent")
      set the foregroundColor of button pName to clr("accentText")
   else
      set the backgroundColor of button pName to clr("tabIdle")
      set the foregroundColor of button pName to clr("ink")
   end if
end styleTab

-- ==========================================================================
-- Click routing: a control's short name is "prefix:role"; dispatch by prefix.
-- ==========================================================================

on mouseUp
   local tName
   local tPrefix
   local tRole
   put the short name of the target into tName
   set the itemDelimiter to ":"
   put item 1 of tName into tPrefix
   put item 2 of tName into tRole
   if tPrefix is "ui" then
      handleChrome tRole
   else if tPrefix is "enc" then
      handleEnc tRole
   else if tPrefix is "key" then
      handleKey tRole
   else if tPrefix is "sign" then
      handleSign tRole
   else if tPrefix is "hash" then
      handleHash tRole
   else if tPrefix is "seed" then
      handleSeed tRole
   else if tPrefix is "roll" then
      handleRoll tRole
   else if tPrefix is "about" then
      handleAbout tRole
   end if
end mouseUp

on handleChrome pRole
   if pRole is "tabEncrypt" then
      showTab "enc"
   else if pRole is "tabKeys" then
      showTab "key"
   else if pRole is "tabSign" then
      showTab "sign"
   else if pRole is "tabHash" then
      showTab "hash"
   else if pRole is "tabSeed" then
      showTab "seed"
   else if pRole is "tabRoll" then
      showTab "roll"
   else if pRole is "tabAbout" then
      showTab "about"
   end if
end handleChrome

-- ==========================================================================
-- Secret Key tab: passphrase -> Argon2id -> secretbox, with a tamper demo.
-- ==========================================================================

on handleEnc pRole
   if pRole is "encrypt" then
      doEncrypt
   else if pRole is "decrypt" then
      doDecrypt
   else if pRole is "tamper" then
      doTamper
   end if
end handleEnc

on doEncrypt
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSalt
   local tKey
   local tBox
   if field "enc:pass" is empty then
      setStatus "enc:status", "Enter a passphrase first.", "bad"
      exit doEncrypt
   end if
   -- Guarded (fleet audit): with the library missing, the first sx* call
   -- throws, and an unhandled throw here dies silently instead of landing
   -- in this tab's status line.
   try
      put sxRandomBytes(16) into tSalt
      put sxPwHash(textEncode(field "enc:pass", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
      put sxSecretBox(textEncode(field "enc:msg", "utf-8"), tKey) into tBox
      put textDecode(sxBin2Base64(tSalt & tBox), "ascii") into sEncBlob
   catch tErr
      setStatus "enc:status", "Encrypt failed:" && tErr, "bad"
      exit doEncrypt
   end try
   put sEncBlob into field "enc:out"
   setStatus "enc:status", "Sealed" && (the number of bytes in textEncode(field "enc:msg", "utf-8")) & "-byte message into" && (the number of bytes in (tSalt & tBox)) & " bytes. Now try Decrypt, or Flip a byte.", "ok"
end doEncrypt

on doDecrypt
   local tRaw
   local tSalt
   local tBox
   local tKey
   if sEncBlob is empty then
      setStatus "enc:status", "Nothing to decrypt yet - click Encrypt first.", "bad"
      exit doDecrypt
   end if
   -- The base64 decode and the KDF sit INSIDE the try (fleet audit): both
   -- are sx* calls that throw with the library missing, and they used to
   -- run before any catch existed.
   try
      put sxBase642Bin(textEncode(sEncBlob, "ascii")) into tRaw
      if the number of bytes in tRaw < 17 then
         setStatus "enc:status", "That is not a valid sealed blob.", "bad"
         exit doDecrypt
      end if
      put byte 1 to 16 of tRaw into tSalt
      put byte 17 to -1 of tRaw into tBox
      put sxPwHash(textEncode(field "enc:pass", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
      put "Recovered: " & textDecode(sxSecretBoxOpen(tBox, tKey), "utf-8") into field "enc:out"
      setStatus "enc:status", "Decrypted and authenticated. The Poly1305 tag verified.", "ok"
   catch tErr
      setStatus "enc:status", "REJECTED: wrong passphrase, or the ciphertext was tampered with.", "bad"
   end try
end doDecrypt

-- Flip one byte of the sealed blob in place, to show open() rejects it.
on doTamper
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tRaw
   local tLen
   local tPos
   if sEncBlob is empty then
      setStatus "enc:status", "Encrypt something first, then flip a byte.", "bad"
      exit doTamper
   end if
   -- Guarded (fleet audit): the decode/re-encode pair throws with the
   -- library missing.
   try
      put sxBase642Bin(textEncode(sEncBlob, "ascii")) into tRaw
      put the number of bytes in tRaw into tLen
      put 17 + (tLen - 17) div 2 into tPos
      put numToByte(byteToNum(byte tPos of tRaw) bitXor 1) into byte tPos of tRaw
      put textDecode(sxBin2Base64(tRaw), "ascii") into field "enc:out"
   catch tErr
      setStatus "enc:status", "Could not flip a byte:" && tErr, "bad"
      exit doTamper
   end try
   put field "enc:out" into sEncBlob
   setStatus "enc:status", "Flipped one ciphertext byte. Now click Decrypt - it must be rejected.", "muted"
end doTamper

-- ==========================================================================
-- Public Key tab: X25519 box + sealed box between Alice and Bob.
-- ==========================================================================

on handleKey pRole
   if pRole is "gen" then
      doKeygen
   else if pRole is "box" then
      doBox
   else if pRole is "open" then
      doBoxOpen
   else if pRole is "eve" then
      doBoxEve
   end if
end handleKey

on doKeygen
   sxBoxKeypair sApk, sAsk
   sxBoxKeypair sBpk, sBsk
   put "Alice public: " & shortHex(sApk, 32) & return & "Bob public:   " & shortHex(sBpk, 32) & return & "(secret keys held privately by each party)" into field "key:keys"
   put empty into field "key:out"
   setStatus "key:status", "Two X25519 keypairs generated. Encrypt a message from Alice to Bob.", "ok"
end doKeygen

on doBox
   local tBox
   if sApk is empty then
      setStatus "key:status", "Generate keypairs first.", "bad"
      exit doBox
   end if
   put sxBox(textEncode(field "key:msg", "utf-8"), sBpk, sAsk) into tBox
   put textDecode(sxBin2Base64(tBox), "ascii") into sBoxCt
   put sBoxCt into field "key:out"
   setStatus "key:status", "Encrypted to Bob's public key with Alice's secret key. Click Bob opens.", "ok"
end doBox

on doBoxOpen
   local tBox
   if sBoxCt is empty then
      setStatus "key:status", "Encrypt a message first.", "bad"
      exit doBoxOpen
   end if
   put sxBase642Bin(textEncode(sBoxCt, "ascii")) into tBox
   try
      put "Bob reads: " & textDecode(sxBoxOpen(tBox, sApk, sBsk), "utf-8") into field "key:out"
      setStatus "key:status", "Bob opened it with his secret key and Alice's public key.", "ok"
   catch tErr
      setStatus "key:status", "REJECTED.", "bad"
   end try
end doBoxOpen

-- An eavesdropper holding the wrong secret key cannot open the box.
on doBoxEve
   local tBox
   local tEpk
   local tEsk
   if sBoxCt is empty then
      setStatus "key:status", "Encrypt a message first.", "bad"
      exit doBoxEve
   end if
   put sxBase642Bin(textEncode(sBoxCt, "ascii")) into tBox
   sxBoxKeypair tEpk, tEsk
   try
      get sxBoxOpen(tBox, sApk, tEsk)
      setStatus "key:status", "Unexpected: the eavesdropper opened it (should not happen).", "bad"
   catch tErr
      setStatus "key:status", "REJECTED: a third party with the wrong key cannot open Bob's box.", "ok"
   end try
end doBoxEve

-- ==========================================================================
-- Signatures tab: ed25519 sign / verify, including the tamper case.
-- ==========================================================================

on handleSign pRole
   if pRole is "gen" then
      doSignGen
   else if pRole is "sign" then
      doSign
   else if pRole is "verify" then
      doVerify
   end if
end handleSign

on doSignGen
   sxSignKeypair sSignPk, sSignSk
   put "public key: " & shortHex(sSignPk, 48) into field "sign:keys"
   put empty into field "sign:out"
   put empty into sSignSig
   setStatus "sign:status", "Signing keypair generated. Type a statement and Sign it.", "ok"
end doSignGen

on doSign
   if sSignSk is empty then
      setStatus "sign:status", "Generate a signing keypair first.", "bad"
      exit doSign
   end if
   put field "sign:msg" into sSignMsg
   put sxSignDetached(textEncode(sSignMsg, "utf-8"), sSignSk) into sSignSig
   put textDecode(sxBin2Hex(sSignSig), "ascii") into field "sign:out"
   setStatus "sign:status", "Signed. Now Verify - or edit the statement first and watch it fail.", "ok"
end doSign

on doVerify
   if sSignSig is empty then
      setStatus "sign:status", "Sign a statement first.", "bad"
      exit doVerify
   end if
   if sxSignVerifyDetached(sSignSig, textEncode(field "sign:msg", "utf-8"), sSignPk) then
      setStatus "sign:status", "VALID: the signature matches this exact statement.", "ok"
   else
      setStatus "sign:status", "INVALID: the statement was changed since it was signed.", "bad"
   end if
end doVerify

-- ==========================================================================
-- Hash & Files tab.
-- ==========================================================================

on handleHash pRole
   if pRole is "hash" then
      doHashText
   else if pRole is "hashfile" then
      doHashFile
   else if pRole is "encfile" then
      doEncFile
   else if pRole is "decfile" then
      doDecFile
   end if
end handleHash

on doHashText
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   -- Guarded to mirror its sibling doHashFile (fleet audit): the same
   -- missing-library throw applies to the in-memory hash.
   try
      put "BLAKE2b-256:" && return & textDecode(sxBin2Hex(sxHash(textEncode(field "hash:msg", "utf-8"), 32)), "ascii") into field "hash:out"
      setStatus "hash:status", "Hashed. Change one character of the text and hash again to see a totally different digest.", "ok"
   catch tErr
      setStatus "hash:status", "Could not hash that text:" && tErr, "bad"
   end try
end doHashText

on doHashFile
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tPath
   answer file "Choose a file to hash:"
   put it into tPath
   if tPath is empty then
      exit doHashFile
   end if
   try
      put "File: " & tPath & return & "BLAKE2b-256:" && return & textDecode(sxBin2Hex(sxHashFile(tPath, 32)), "ascii") into field "hash:out"
      setStatus "hash:status", "Hashed the file chunk-by-chunk C-side - the bytes never entered a variable.", "ok"
   catch tErr
      setStatus "hash:status", "Could not hash that file:" && tErr, "bad"
   end try
end doHashFile

-- Encrypt a file with a passphrase. The .enc is self-contained: a 16-byte
-- random salt is stored at the front, then the authenticated secretstream.
-- You choose where to save it (ask file).
on doEncFile
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSrc
   local tDest
   local tTmp
   local tSalt
   local tKey
   if field "hash:pass" is empty then
      setStatus "hash:status", "Enter a passphrase for the file first.", "bad"
      exit doEncFile
   end if
   answer file "Choose a file to encrypt:"
   put it into tSrc
   if tSrc is empty then
      exit doEncFile
   end if
   ask file "Save the encrypted file as:" with (tSrc & ".enc")
   put it into tDest
   if tDest is empty then
      exit doEncFile
   end if
   put tDest & ".tmp" into tTmp
   -- The salt draw and the KDF sit INSIDE the try (fleet audit): both are
   -- sx* calls that used to run before the catch existed.
   try
      put sxRandomBytes(16) into tSalt
      put sxPwHash(textEncode(field "hash:pass", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
      sxEncryptFile tSrc, tTmp, tKey
      put tSalt & url ("binfile:" & tTmp) into url ("binfile:" & tDest)
      put "Encrypted (passphrase-derived key, salt stored in the file):" & return & tSrc & return & "  ->  " & tDest into field "hash:out"
      setStatus "hash:status", "Encrypted. Decrypt a file with the SAME passphrase to recover it.", "ok"
   catch tErr
      setStatus "hash:status", "Could not encrypt that file:" && tErr, "bad"
   end try
   if there is a file tTmp then
      delete file tTmp
   end if
end doEncFile

-- Decrypt a .enc made above: read off the salt, re-derive the key from the
-- passphrase, and decrypt the rest. A wrong passphrase, or a tampered or
-- truncated file, is rejected. You choose where to save the result.
on doDecFile
   local tEnc
   local tDest
   local tTmp
   local tRaw
   local tSalt
   local tBody
   local tKey
   local tSuggest
   if field "hash:pass" is empty then
      setStatus "hash:status", "Enter the passphrase the file was encrypted with.", "bad"
      exit doDecFile
   end if
   answer file "Choose a .enc file to decrypt:"
   put it into tEnc
   if tEnc is empty then
      exit doDecFile
   end if
   put url ("binfile:" & tEnc) into tRaw
   if the number of bytes in tRaw < 17 then
      setStatus "hash:status", "That file is too small to be a SodiumXT .enc file.", "bad"
      exit doDecFile
   end if
   put byte 1 to 16 of tRaw into tSalt
   put byte 17 to -1 of tRaw into tBody
   if tEnc ends with ".enc" then
      put char 1 to -5 of tEnc into tSuggest
   else
      put tEnc & ".decrypted" into tSuggest
   end if
   ask file "Save the decrypted file as:" with tSuggest
   put it into tDest
   if tDest is empty then
      exit doDecFile
   end if
   put tDest & ".tmp" into tTmp
   put tBody into url ("binfile:" & tTmp)
   -- The KDF sits INSIDE the try (fleet audit): it is an sx* call that
   -- used to run before the catch existed.
   try
      put sxPwHash(textEncode(field "hash:pass", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tKey
      sxDecryptFile tTmp, tDest, tKey
      put "Decrypted and authenticated:" & return & tEnc & return & "  ->  " & tDest into field "hash:out"
      setStatus "hash:status", "Decrypted successfully - the authentication tag verified.", "ok"
   catch tErr
      setStatus "hash:status", "REJECTED: wrong passphrase, or the file was tampered with or truncated.", "bad"
   end try
   if there is a file tTmp then
      delete file tTmp
   end if
end doDecFile

-- ==========================================================================
-- Identity tab: a passphrase deterministically rebuilds the SAME keypair.
-- Argon2id(passphrase, fixed salt) -> 32-byte seed -> sxBoxKeypairFromSeed /
-- sxKeyExchangeKeypairFromSeed. The same passphrase always yields the same
-- keys, so there is nothing to back up; a different passphrase is a wholly
-- different identity. (A login system would store a per-user salt; here we
-- WANT the same passphrase to rebuild the identity, so the salt is fixed.)
-- ==========================================================================

on handleSeed pRole
   if pRole is "derive" then
      doSeedDerive
   end if
end handleSeed

on doSeedDerive
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSalt
   local tSeed
   local tSeed2
   local tBoxPk
   local tBoxSk
   local tBoxPk2
   local tBoxSk2
   local tKxPk
   local tKxSk
   local tTypoPk
   local tTypoSk
   local tSealed
   local tReport
   if field "seed:pass" is empty then
      setStatus "seed:status", "Enter a passphrase first.", "bad"
      exit doSeedDerive
   end if
   -- A FIXED 16-byte salt makes the derivation reproducible on purpose: the
   -- same passphrase must reach the same seed. crypto_pwhash needs 16 salt bytes.
   -- The whole derivation is guarded (fleet audit): every line is an sx*
   -- call that throws with the library missing, and none had a catch.
   put textEncode("SodiumXT-Demo-16", "utf-8") into tSalt
   try
      put sxPwHash(textEncode(field "seed:pass", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tSeed
      sxBoxKeypairFromSeed tSeed, tBoxPk, tBoxSk
      sxKeyExchangeKeypairFromSeed tSeed, tKxPk, tKxSk
      -- The NEW capability: a seed deterministically fixes the keypair. Derive it
      -- a second time from the same seed and compare the public keys constant-time.
      sxBoxKeypairFromSeed tSeed, tBoxPk2, tBoxSk2
      -- One extra character in the passphrase is a completely different identity.
      put sxPwHash(textEncode(field "seed:pass" & "!", "utf-8"), tSalt, 32, "2", sxPwMemInteractive()) into tSeed2
      sxBoxKeypairFromSeed tSeed2, tTypoPk, tTypoSk
      put "box public key:  " & shortHex(tBoxPk, 48) & return into tReport
      put "kx  public key:  " & shortHex(tKxPk, 48) & return & return after tReport
      if sxMemEqual(tBoxPk, tBoxPk2) then
         put "same seed -> keypair: IDENTICAL (verified constant-time)" & return after tReport
      else
         put "same seed -> keypair: DIFFERENT (unexpected!)" & return after tReport
      end if
      put "one extra character -> " & shortHex(tTypoPk, 24) & "... (a different identity)" & return & return after tReport
      -- Prove it is a genuine, usable keypair: seal a note to it and open it back.
      put sxSeal(textEncode("hello, future me", "utf-8"), tBoxPk) into tSealed
   catch tErr
      setStatus "seed:status", "Derive failed:" && tErr, "bad"
      exit doSeedDerive
   end try
   try
      put "real keypair: sealed a note to it and reopened it, got: " & textDecode(sxSealOpen(tSealed, tBoxPk, tBoxSk), "utf-8") after tReport
   catch tErr
      put "real keypair: FAILED to open the sealed note (unexpected)" after tReport
   end try
   put tReport into field "seed:out"
   setStatus "seed:status", "Your passphrase deterministically rebuilt the SAME keypair - nothing to store. Retype it anywhere to be you again; change a character for a new identity.", "ok"
end doSeedDerive

-- ==========================================================================
-- Rekey tab: secretstream rekey gives in-session forward secrecy. Two
-- receivers start from one shared key; after a rekey, only the receiver that
-- rekeyed too can read on. The other (standing in for a key captured at the
-- start of the session) is locked out of everything sent after the rekey.
-- ==========================================================================

on handleRoll pRole
   if pRole is "run" then
      doRollDemo
   end if
end handleRoll

on doRollDemo
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tKey
   local tHeader
   local tNoAd
   local tSender
   local tRecv
   local tStale
   local tTag
   local tCtA
   local tCtB
   local tReport
   local tFailed
   -- Free-what-you-open (fleet audit): three secretstream handles open at
   -- the top and used to be freed only on the straight-line path, so a
   -- throw mid-demo leaked all three. The body now runs guarded and the
   -- frees below run on BOTH paths.
   put "false" into tFailed
   try
      put sxRandomBytes(32) into tKey
      put textEncode("", "utf-8") into tNoAd
      -- One shared session key and header. tRecv is the up-to-date partner; tStale
      -- copied the SAME key at the start and never rekeys (our stand-in attacker).
      put sxSecretStreamInitPush(tKey, tHeader) into tSender
      put sxSecretStreamInitPull(tKey, tHeader) into tRecv
      put sxSecretStreamInitPull(tKey, tHeader) into tStale
      put "one session key shared; two receivers start from it" & return & return into tReport
      -- Chunk one, before any rekey: both receivers can read it.
      put sxSecretStreamPush(tSender, textEncode(field "roll:before", "utf-8"), tNoAd, false) into tCtA
      put "-- before the rekey --" & return after tReport
      put "  sent:       " & field "roll:before" & return after tReport
      put "  current rx: " & textDecode(sxSecretStreamPull(tRecv, tCtA, tNoAd, tTag), "utf-8") & return after tReport
      put "  stale rx:   " & textDecode(sxSecretStreamPull(tStale, tCtA, tNoAd, tTag), "utf-8") & return & return after tReport
      -- Rekey the sender and the current receiver together; the stale one does not.
      sxSecretStreamRekey tSender
      sxSecretStreamRekey tRecv
      put "** sender and current receiver rekey; the stale key is left behind **" & return & return after tReport
      -- Chunk two, after the rekey.
      put sxSecretStreamPush(tSender, textEncode(field "roll:after", "utf-8"), tNoAd, true) into tCtB
      put "-- after the rekey --" & return after tReport
      put "  sent:       " & field "roll:after" & return after tReport
      put "  current rx: " & textDecode(sxSecretStreamPull(tRecv, tCtB, tNoAd, tTag), "utf-8") & return after tReport
      put "  stale rx:   " after tReport
      try
         put textDecode(sxSecretStreamPull(tStale, tCtB, tNoAd, tTag), "utf-8") & " (unexpected - should have failed)" & return after tReport
      catch tErr
         put "REJECTED - the old key cannot read past a rekey (forward secrecy)" & return after tReport
      end try
   catch tErr
      setStatus "roll:status", "Demo failed:" && tErr, "bad"
      put "true" into tFailed
   end try
   -- Free only what was actually opened (a throw at init leaves the later
   -- handles empty), and guard the frees themselves: with the library
   -- missing they would throw again out of the error path.
   try
      if tSender is not empty then
         sxFreeStream tSender
      end if
      if tRecv is not empty then
         sxFreeStream tRecv
      end if
      if tStale is not empty then
         sxFreeStream tStale
      end if
   catch tErr
      -- the library is gone; there is nothing left to free
   end try
   if tFailed is "true" then
      exit doRollDemo
   end if
   put tReport into field "roll:out"
   setStatus "roll:status", "The current receiver read both messages; the stale-key receiver read only the first. A rekey locks the old key out of everything that follows.", "ok"
end doRollDemo

-- ==========================================================================
-- About tab: a compact self-test against the live library.
-- ==========================================================================

on handleAbout pRole
   if pRole is "selftest" then
      doSelfTest
   end if
end handleAbout

on doSelfTest
   local tErr -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tKey
   local tBox
   local tPk
   local tSk
   local tSig
   local tR
   local tInRange
   local tNoAd
   local tHdr
   local tPushH
   local tPullH
   local tCa
   local tCb
   local tTag
   local tRkOk
   put 0 into sTPass
   put 0 into sTFail
   -- Guarded like the buildUI probe (fleet audit): with the library
   -- missing, sxVersion is the first throw and used to kill the handler.
   try
      put "Running checks against" && sxVersion() & return & return into sTLog
   catch tErr
      setStatus "about:status", "SodiumXT NOT loaded: install org.openxtalk.library.sodium and reopen.", "bad"
      exit doSelfTest
   end try

   -- The run itself is guarded too (free-what-you-open): it opens two
   -- secretstream handles, and a throw mid-run used to abort the handler
   -- with them still open. The catch frees whatever was left, then reports.
   try

      -- secretbox round trip, then a wrong key must be rejected
      put sxRandomBytes(32) into tKey
      put sxSecretBox(textEncode("hello", "utf-8"), tKey) into tBox
      checkInto (textDecode(sxSecretBoxOpen(tBox, tKey), "utf-8") is "hello"), "secretbox round trip"
      checkInto (not openSucceeds(tBox, sxRandomBytes(32))), "secretbox rejects a wrong key"

      -- Argon2id and BLAKE2b pinned to published known-answer vectors
      checkInto (textDecode(sxBin2Hex(sxPwHash(textEncode("password", "utf-8"), textEncode("AAAAAAAAAAAAAAAA", "utf-8"), 32, "2", "1048576")), "ascii") is "7216b4357104ed7f8a4e900e9cc7a63a0786855abe0b59340053ee43f841228a"), "Argon2id known-answer vector"
      checkInto (textDecode(sxBin2Hex(sxHash(textEncode("abc", "utf-8"), 32)), "ascii") is "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"), "BLAKE2b-256(abc) vector"

      -- ed25519 sign / verify, and the tamper case
      sxSignKeypair tPk, tSk
      put sxSignDetached(textEncode("release", "utf-8"), tSk) into tSig
      checkInto (sxSignVerifyDetached(tSig, textEncode("release", "utf-8"), tPk)), "ed25519 signature verifies"
      checkInto (not sxSignVerifyDetached(tSig, textEncode("RELEASE", "utf-8"), tPk)), "altered message fails verification"

      -- the CSPRNG produces values strictly inside [0, upperBound) - check the
      -- upper bound too (a bare ">= 0" can never fail, so it proves nothing)
      put true into tInRange
      repeat 256 times
         put sxRandomUniform(2) into tR
         if tR < 0 or tR >= 2 then
            put false into tInRange
            exit repeat
         end if
      end repeat
      checkInto tInRange, "uniform random stays in [0, 2) over 256 draws"

      -- seeded keypairs are deterministic: one seed always fixes the same keypair
      put sxRandomBytes(32) into tKey
      sxBoxKeypairFromSeed tKey, tPk, tSk
      sxBoxKeypairFromSeed tKey, tR, tBox
      checkInto (sxMemEqual(tPk, tR)), "seeded keypair is deterministic (same seed, same key)"

      -- secretstream rekey: a matched rekey keeps sync; an unmatched one must fail
      put sxRandomBytes(32) into tKey
      put textEncode("", "utf-8") into tNoAd
      put sxSecretStreamInitPush(tKey, tHdr) into tPushH
      put sxSecretStreamPush(tPushH, textEncode("before", "utf-8"), tNoAd, false) into tCa
      sxSecretStreamRekey tPushH
      put sxSecretStreamPush(tPushH, textEncode("after", "utf-8"), tNoAd, true) into tCb
      sxFreeStream tPushH
      put sxSecretStreamInitPull(tKey, tHdr) into tPullH
      get sxSecretStreamPull(tPullH, tCa, tNoAd, tTag)
      sxSecretStreamRekey tPullH
      checkInto (textDecode(sxSecretStreamPull(tPullH, tCb, tNoAd, tTag), "utf-8") is "after"), "secretstream stays in sync when both ends rekey"
      sxFreeStream tPullH
      put false into tRkOk
      put sxSecretStreamInitPull(tKey, tHdr) into tPullH
      get sxSecretStreamPull(tPullH, tCa, tNoAd, tTag)
      try
         get sxSecretStreamPull(tPullH, tCb, tNoAd, tTag)
      catch tErr
         put true into tRkOk
      end try
      sxFreeStream tPullH
      checkInto tRkOk, "an unmatched rekey locks the old key out of later chunks"

      -- ed25519 seed -> expanded key (a reproducible identity key): known-answer
      -- vector for the fixed seed 0x42 x 32 (the letter B is 0x42).
      put textEncode("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "ascii") into tKey
      checkInto (textDecode(sxBin2Hex(sxSignSeedToExpandedKey(tKey)), "ascii") is "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6eeda66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90"), "ed25519 seed-to-expanded-key known-answer vector"

      -- HMAC-SHA256 over an arbitrary-length key: RFC 4231 Test Case 2.
      checkInto (textDecode(sxBin2Hex(sxHmacSha256(textEncode("Jefe", "utf-8"), textEncode("what do ya want for nothing?", "utf-8"))), "ascii") is "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), "HMAC-SHA256 matches RFC 4231 Test Case 2"

   catch tErr
      -- free what the aborted run left open; the frees are guarded
      -- themselves because the likeliest cause IS a missing library,
      -- and sxFreeStream is idempotent so a freed handle is a no-op
      try
         if tPushH is not empty then
            sxFreeStream tPushH
         end if
         if tPullH is not empty then
            sxFreeStream tPullH
         end if
      catch tErrFree
         -- nothing left to free
      end try
      put sTLog into field "about:out"
      setStatus "about:status", "Self-test ABORTED:" && tErr, "bad"
      exit doSelfTest
   end try

   put return & (sTPass + sTFail) & " checks run." after sTLog
   put sTLog into field "about:out"
   if sTFail is 0 then
      setStatus "about:status", "ALL " & sTPass & " CHECKS PASSED against the live libsodium.", "ok"
   else
      setStatus "about:status", sTFail && "check(s) FAILED - see the log.", "bad"
   end if
end doSelfTest

-- Record one check into the running self-test transcript (script-local state).
private command checkInto pCond, pLabel
   if pCond then
      add 1 to sTPass
      put "  ok    " & pLabel & return after sTLog
   else
      add 1 to sTFail
      put "  FAIL  " & pLabel & return after sTLog
   end if
end checkInto

-- True if opening the box with this key succeeds (no throw).
private function openSucceeds pBox, pKey
   try
      get sxSecretBoxOpen(pBox, pKey)
      return true
   catch tErr
      return false
   end try
end openSucceeds
