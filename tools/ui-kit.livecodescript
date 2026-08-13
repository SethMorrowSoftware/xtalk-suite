-- ui-kit.livecodescript - the suite's ONE demo look, as a carried block.
--
-- WHY THIS EXISTS. Every demo stack and harness in the family converged on
-- the same de-facto style (the blue title band, a status line, bold section
-- headers, mono data areas, the 237,239,243 ground) by copy-paste, which is
-- how the checker copies once drifted apart too. This file makes the look
-- OFFICIAL the same way the checker was fixed: one master block, carried
-- VERBATIM into each adopting stack, with tools/check-ui-kit-drift.py
-- failing the build on any divergence. A demo stays a single paste-and-run
-- file (the suite rule), and the suite still has one style.
--
-- THE STYLE, in five rules (the part a human should know before laying out
-- a new demo):
--   1. Geometry is the CALLER's: explicit rects, a 16px edge margin, 24px
--      button rows, 4-8px gutters. The kit owns the look, not the layout.
--   2. One title band (uiChrome) and ONE status line (uiStatus) at the top;
--      status color is semantic: ok green, warn amber, bad red, muted grey.
--      Probes report there, and a demo that cannot run says so in "bad".
--   3. Sections are numbered bold headers (uiSection); data and results are
--      mono areas (uiArea); entry fields are mono too (uiInput), because
--      hex, addresses and paths are what this suite's demos edit.
--   4. Every demo carries an honesty/custody footer (uiFooter): what the
--      stack is, what it is not, and its engine-evidence state.
--   5. Adopters place the block ABOVE their first use of a kUi* constant
--      (OXT resolves constants by lexical position) and keep it byte-exact:
--      a look change is made HERE and re-carried, never patched in place.
--
-- ADOPTION: copy everything between the BEGIN and END marker lines
-- (inclusive) into the adopting stack script, then add the file to the
-- ADOPTERS list in tools/check-ui-kit-drift.py. The gate fails on a stale
-- copy, an unregistered adopter, and a registered non-adopter alike.
--
-- FIRST ENGINE EVIDENCE 2026-08-13: the kit's chrome, status line, inputs,
-- areas and footer rendered and ran inside riptide-social's two-machine
-- pass (the riptide leg of runbook item 6), on both machines.

-- ==== SUITE UI KIT v1 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "237,239,243"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiOk = "20,120,40"
constant kUiWarn = "160,90,10"
constant kUiBad = "170,30,30"
constant kUiMuted = "90,96,110"
constant kUiMono = "Courier"

-- The window chrome every adopter shares: stack size, ground color, the
-- title band, and the one status line under it (write it with uiStatus).
command uiChrome pTitle, pWidth, pHeight
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & ",30", 15
   set the opaque of field "uiTitle" to true
   set the backgroundColor of field "uiTitle" to kUiAccent
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   uiLabel "uiStatus", empty, "16,34," & (pWidth - 16) & ",52", 11
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
      set the foregroundColor of field "uiStatus" to kUiMuted
   end if
end uiStatus

-- A numbered bold section header.
command uiSection pName, pText, pRect
   uiLabel pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
end uiSection

-- A static caption (idempotent, borderless, transparent).
command uiLabel pName, pText, pRect, pSize
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
end uiLabel

-- A one-line entry field, mono because hex, addresses and paths are what
-- this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the textSize of field pName to 11
   set the textFont of field pName to kUiMono
end uiInput

-- A read-only output/list area: mono, scrolling.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to kUiMono
end uiArea

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiLabel "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v1 END ====
