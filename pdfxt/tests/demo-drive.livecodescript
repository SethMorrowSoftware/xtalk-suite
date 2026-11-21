script "pdfxtDemoDrive"
-- demo-drive.livecodescript - examples/pdfxt-demo.livecodescript driven on a
-- real engine with no person at it.
--
--    PDFXT_LCM=<pdfxt.lcm> PDFXT_LIB=<library, no extension> \
--    PDFXT_DEMO=examples/pdfxt-demo.livecodescript \
--       <OXT-Beyond>/LiveCode-Community -ui tests/demo-drive.livecodescript
--
-- PDFium must be beside the library (pdfium.so next to pdfxt.so), as the
-- build leaves it. It puts the demo's script on a new stack (as the demo's
-- header tells a person to) and builds the window, which opens on the
-- sample and starts its tour by itself. The drive lets the engine's own
-- timer play the first frames (the opening motion), stops the tour as a
-- click would, then plays each of the five scenes to its end through the
-- demo's own frames (pvShowRun, the frames without the timer) and reads
-- what each one did. Then it does what a person would: follows the
-- outline, zooms and scrolls, searches with and without the flags, types a
-- page label, clicks a link, a word and a web address, drags out a box,
-- draws in gray, saves a page, unlocks the locked sample with a wrong and
-- then the right password, runs every check from the Checks tab, starts a
-- scene with its button and closes the document. A click is the message
-- the engine sends (mouseUp, returnInField, scrollbarDrag); a click or a
-- drag ON THE PAGE is the handler the demo's mouse handlers call with the
-- point they read (pvClickAt, pvSelectBox), since no pointer moves here.
-- The look is held too: every field and button of the window says its own
-- colours (under Windows' dark appearance a field without them got white
-- text on a white ground), and no button is a tick box. The native lane
-- runs it (the suite's .github/workflows/native-pdfxt.yml, job `engine`)
-- and wants BOTH an exit of 0 and a last line "DRIVE <passed> 0": an
-- engine that printed nothing must not read as a pass.
--
-- PDFXT_SHOT (optional) names a PNG to write of the window: with
-- PDFXT_SCENE ("scene,frame", e.g. "1,90") the sample with that scene
-- stopped at that frame, otherwise the sample searched for "needle" on the
-- tab PDFXT_TAB (a key: out, find, txt, lnk, draw, info or chk). It needs
-- a display (xvfb-run).
--
-- WHAT THIS IS EVIDENCE OF: the demo's logic, its motion and its window on
-- OXT-Beyond's Linux engine without a display. It is not a person using the
-- window, and it does not see colours on a screen: a dark system appearance
-- is held only as "every colour is the stack's own".

constant kStack = "pdfxtDemoRun"

local sPassed, sFailed, sOut

command drCheck pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sPassed
      put "PASS  " & pLabel & return after sOut
   else
      add 1 to sFailed
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sOut
   end if
end drCheck

-- A click on a control of the demo, as the engine delivers one: the
-- message goes to the control and up to the stack script's mouseUp.
command drClick pControl
   dispatch "mouseUp" to pControl with 1
end drClick

-- Return typed in an entry field of the demo.
command drReturn pField
   dispatch "returnInField" to field pField of card 1 of stack kStack
end drReturn

-- One of the demo's own handlers, with what its mouse handlers would pass.
command drCall pHandler, pA, pB, pC, pD
   dispatch pHandler to stack kStack with pA, pB, pC, pD
end drCall

-- One of the demo's own functions that take nothing, answered.
function drAsk pFunction
   return value(pFunction & "()", stack kStack)
end drAsk

-- One pixel of an image's imageData as "r,g,b".
function drPixel pData, pWidth, pX, pY
   local tAt
   put (pY * pWidth + pX) * 4 into tAt
   return byteToNum(byte tAt + 2 of pData) & comma & byteToNum(byte tAt + 3 of pData) & comma & byteToNum(byte tAt + 4 of pData)
end drPixel

-- Is a message of that name waiting in the engine's queue (send ... in)?
function drPending pMessage
   local tLine
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine is pMessage then
         return true
      end if
   end repeat
   return false
end drPending

-- The controls of the window that leave a colour to the system, a line
-- each, or empty: a field with no text colour of its own (under Windows'
-- dark appearance OXT-Beyond gives it white), an opaque field or a button
-- with no ground of its own, a list with no colour for its chosen line,
-- and any tick box or radio button, whose words the system draws in its
-- own theme's colours.
function drUnpainted
   local tI, tName, tStyle, tOut
   repeat with tI = 1 to the number of fields of card 1 of stack kStack
      put the short name of field tI of card 1 of stack kStack into tName
      if the foregroundColor of field tI of card 1 of stack kStack is empty then
         put "field" && tName && "(its text)" & return after tOut
      end if
      if the opaque of field tI of card 1 of stack kStack then
         if the backgroundColor of field tI of card 1 of stack kStack is empty then
            put "field" && tName && "(its ground)" & return after tOut
         end if
      end if
      if the listBehavior of field tI of card 1 of stack kStack then
         if the hiliteColor of field tI of card 1 of stack kStack is empty then
            put "field" && tName && "(its chosen line)" & return after tOut
         end if
      end if
   end repeat
   repeat with tI = 1 to the number of buttons of card 1 of stack kStack
      put the short name of button tI of card 1 of stack kStack into tName
      put the style of button tI of card 1 of stack kStack into tStyle
      if tStyle is "checkbox" or tStyle is "radioButton" then
         put "button" && tName && "(a" && tStyle & ")" & return after tOut
      end if
      if the foregroundColor of button tI of card 1 of stack kStack is empty \
            or the backgroundColor of button tI of card 1 of stack kStack is empty then
         put "button" && tName && "(its colours)" & return after tOut
      end if
   end repeat
   return tOut
end drUnpainted

on startup
   local tError, tWas, tDoc, tBox, tPath, tData, tPixel, tLog, tTab, tNow, tScene
   put 0 into sPassed
   put 0 into sFailed
   try
      -- first without pdfxt: the window still builds and works, says in
      -- red what is missing, and plays nothing
      create stack "pdfxtDemoBare"
      set the script of stack "pdfxtDemoBare" to textDecode(URL ("binfile:" & $PDFXT_DEMO), "UTF-8")
      go stack "pdfxtDemoBare"
      set the defaultStack to "pdfxtDemoBare"
      send "preOpenStack" to stack "pdfxtDemoBare"
      drCheck field "ui:status" begins with "pdfxt is NOT loaded" and the foregroundColor of field "ui:status" is "255,112,112" \
            and the visible of field "view:hint" and field "view:hint" contains "needs pdfxt" and not drPending("pvTourStart"), \
            "without pdfxt the window says in red what is missing, and plays nothing", field "ui:status"
      dispatch "mouseUp" to button "show:1" of card 1 of stack "pdfxtDemoBare" with 1
      dispatch "mouseUp" to button "side:find" of card 1 of stack "pdfxtDemoBare" with 1
      drCheck field "show:about" begins with "The scenes need pdfxt" and not drPending("pvShowTick") \
            and the hilite of button "side:find" and the visible of field "find:text", \
            "a scene's button says why it cannot play, and the tabs still work", field "show:about"
      -- not the defaultStack when it goes: deleting the defaultStack and then
      -- creating a stack killed this engine (engine note 5.17)
      set the defaultStack to the short name of me
      delete stack "pdfxtDemoBare"

      set the revLibraryMapping["pdfxt"] to $PDFXT_LIB
      load extension from file $PDFXT_LCM
      drCheck the result is empty, "the extension loads", the result
      create stack kStack
      set the script of stack kStack to textDecode(URL ("binfile:" & $PDFXT_DEMO), "UTF-8")
      go stack kStack
      set the defaultStack to kStack
      send "preOpenStack" to stack kStack
      drCheck the width of stack kStack is 1180 and the height of stack kStack is 630, "the window is 1180 x 630", the rect of stack kStack
      drCheck field "ui:status" begins with "Ready (pdfxt ABI 1; PDFium chromium/", "the status line names the library and its PDFium", field "ui:status"
      drCheck field "ui:kicker" contains "OXT-BEYOND" and field "ui:title" is "PDF Viewer" and field "ui:credit" is "by Seth Morrow", \
            "the header: OXT-Beyond, the demo's name, and who made it", field "ui:kicker" && field "ui:title" && field "ui:credit"
      drCheck the backgroundColor of stack kStack is "18,21,31" and the foregroundColor of stack kStack is "238,241,247", \
            "the window is dark and its words light", the backgroundColor of stack kStack && the foregroundColor of stack kStack
      put drUnpainted() into tLog
      drCheck tLog is empty, "every field and button says its own colours, and none is a tick box", tLog
      drCheck field "tb:of" is "of 5" and the visible of image "view:page" and the width of image "view:page" is 346 \
            and field "out:h" is "Outline: 8 entries (pdfOutline)", "it opens on the sample, drawn whole, with its outline", field "tb:of" && field "out:h"

      -- the opening motion: the tour is queued as the window opens, and the
      -- engine's own timer plays its first frames with nothing clicked
      drCheck drPending("pvTourStart") and item 1 of drAsk("pvShowNow") is 0, "the tour is queued as the window opens", the pendingMessages
      wait 1200 milliseconds with messages
      put drAsk("pvShowNow") into tNow
      drCheck item 1 of tNow is 1 and item 2 of tNow >= 6 and item 3 of tNow is true, \
            "a second later, scene 1 is playing by itself, as the first of the tour", tNow
      drCheck the hilite of button "show:1" and the hilite of button "show:all" and field "show:about" begins with "1. Deep zoom", \
            "its button is lit, with Play them all, and it says what it shows", field "show:about"
      drCheck drPending("pvShowTick") and the visible of field "view:hud" and field "view:hud" contains "%", \
            "the next frame is queued, and the tag says how the page was drawn", field "view:hud"
      drClick the long id of button "side:find"
      put drAsk("pvShowNow") into tNow
      drCheck item 1 of tNow is 0 and not drPending("pvShowTick") and not the hilite of button "show:1" \
            and field "show:about" begins with "Stopped where it was", "a click stops it where it is, with nothing left queued", tNow
      drCheck the hilite of button "side:find" and the visible of field "find:text" and not the visible of field "out:list", \
            "and the click did what it does: the Search tab", the hilite of button "side:find"

      -- a second preOpenStack rebuilds nothing (the version guard), and
      -- queues the tour again, which stopping takes away before it begins
      put the number of controls of card 1 of stack kStack into tWas
      send "preOpenStack" to stack kStack
      drCheck the number of controls of card 1 of stack kStack is tWas, "reopening adds no control", the number of controls of card 1 of stack kStack
      drCheck drPending("pvTourStart"), "reopening queues the tour again", the pendingMessages
      drCall "pvStopShow"
      drCheck not drPending("pvTourStart") and not drPending("pvShowTick"), "stopping before it begins leaves nothing queued", the pendingMessages

      -- each scene of the showcase, played to its end through its own frames
      drCall "pvShowRun", 1
      put drAsk("pvShowLog") into tLog
      put tLog after sOut
      drCheck tLog begins with "zoom: deepest 1000%," and word 4 of tLog > 100 and tLog contains "back at 57%" and field "tb:zoom" is "57%", \
            "1. Deep zoom: to 1000%, drawn as a window frame after frame, and back to the fitted page", tLog
      drCall "pvShowRun", 2
      put drAsk("pvShowLog") into tLog
      put tLog after sOut
      drCheck line 1 to 4 of tLog is ("find: needle 3" & return & "find: capitals 2" & return & "find: capitals and whole words 1" & return & "find: whole words 2") \
            and line 5 of tLog is "find: PDFium 3 on 2 pages", "2. Find a word: needle 3 times, then 2, 1 and 2 with the flags; PDFium 3 times on two pages", tLog
      drCheck field "find:text" is "PDFium" and field "find:sum" begins with "3 match(es) on 2 page(s)" and not the hilite of button "find:case" \
            and not the hilite of button "find:words", "and the Search tab is left with its last search, the flags off", field "find:sum"
      drCall "pvShowRun", 3
      put drAsk("pvShowLog") into tLog
      put tLog after sOut
      drCheck word 5 of line 1 of tLog > 100 and line 2 of tLog is "read: the word clicked is password", \
            "3. Read a page: the text inside a box, and the word under a click", tLog
      drCheck field "txt:sel" contains "the word it is in: password" and the visible of graphic "view:char", \
            "the Text tab names the word, and its character is marked on the page", field "txt:sel"
      drCall "pvShowRun", 4
      put drAsk("pvShowLog") into tLog
      put tLog after sOut
      replace return with "|" in tLog
      drCheck tLog is "outline: 1|outline: 2|outline: 3|outline: 3|outline: 4|outline: 5|outline: 5|outline: web|links: page 2 has 3|link: page 5|link: page 2|link: web https://openxtalk.org/|", \
            "4. Outline and links: every entry followed, the contents page's links, two followed and a web address shown", tLog
      drCheck field "lnk:addr" contains "https://openxtalk.org/" and not the visible of graphic "view:ptr" and field "ui:status" begins with "Scene 4 is over", \
            "the address is left in the Links tab, the pointer put away, and the status says the scene is over", field "ui:status"
      drCall "pvShowRun", 5
      put drAsk("pvShowLog") into tLog
      put tLog after sOut
      drCheck line 1 to 2 of tLog is ("unlock: it asks for its password" & return & "unlock: a wrong password is refused") \
            and line 3 of tLog begins with "unlock: secret opens it", "5. Unlock: asked for, a wrong password refused, the right one opens it", tLog
      drCheck field "tb:of" is "of 1" and field "info:area" contains "print no" and not the visible of field "lock:pw", \
            "the unlocked page is shown, with its permissions", field "tb:of"
      drCall "pvShowRun", 4, true
      put drAsk("pvShowLog") into tLog
      drCheck tLog contains "link: web https://openxtalk.org/" and tLog contains "unlock: secret opens it", \
            "Play them all plays the scenes in turn (here from 4 to the last)", tLog
      drCheck field "tb:of" is "of 5" and field "tb:page" is 1 and field "show:about" begins with "That was the tour" \
            and not the hilite of button "show:all" and field "ui:status" is "The tour is over: the viewer is yours.", \
            "after the tour the sample is back on its cover, and the window is the person's", field "show:about"
      drCheck item 1 of drAsk("pvShowNow") is 0 and not drPending("pvShowTick"), "and nothing of the show is left running", drAsk("pvShowNow")
      put drUnpainted() into tLog
      drCheck tLog is empty, "after the tour, every colour is still the stack's own", tLog

      -- the sample, fitted to the view and drawn whole
      drClick the long id of button "tb:sample"
      drCheck field "tb:of" is "of 5" and field "tb:page" is 1 and field "ui:status" begins with "Opened the sample: 5 page(s), PDF 1.7", \
            "The sample opens: five pages, PDF 1.7", field "ui:status"
      drCheck the visible of image "view:page" and the width of image "view:page" is 346 and the height of image "view:page" is 448, \
            "page i is drawn at the size that fits the view", the width of image "view:page" && the height of image "view:page"
      drCheck field "draw:last" begins with "pdfRenderPage: the whole page, 346 x 448 pixels" \
            and field "view:hud" begins with "57%   the whole page, 346 x 448", "a page that fits is drawn whole, and the tag says so", field "draw:last"
      drCheck the number of lines of field "out:list" is 8 and line 1 of field "out:list" begins with "Cover" \
            and field "out:h" is "Outline: 8 entries (pdfOutline)", "the outline lists eight entries", line 1 of field "out:list"

      -- the outline takes it to the turned page
      set the hilitedLine of field "out:list" to 5
      drClick the long id of field "out:list"
      drCheck field "tb:page" is 4 and the width of image "view:page" > the height of image "view:page", \
            "an outline entry goes to its page: the turned page, wider than tall", field "tb:page" && the width of image "view:page"
      drClick the long id of button "side:info"
      drCheck the hilite of button "side:info" and not the hilite of button "side:out" and the visible of field "info:area", \
            "the tab shown is the one lit", the hilite of button "side:info"
      drCheck field "info:area" contains "842 x 595 points" and field "info:area" contains "A4, on its side" \
            and field "info:area" contains ("Turned" & tab & "90 degrees"), "the Info tab gives the size, the paper and the turn", field "info:area"
      drCheck field "info:area" contains "Title" & tab & "A short guide to pdfxt" and field "info:area" contains "print yes", \
            "and the document's information and permissions", line 5 to 8 of field "info:area"

      -- zoom and scroll
      drCheck field "tb:zoom" is "75%", "the turned page fits at 75%", field "tb:zoom"
      drClick the long id of button "tb:in"
      drCheck field "tb:zoom" is "100%" and field "draw:last" begins with "pdfRenderPageRegion: a window of 744 x 472 pixels" \
            and the visible of scrollbar "view:hs", "zoomed past the view, only the window in view is drawn", field "draw:last"
      drCheck field "view:hud" begins with "100%   a 744 x 472 window of a 842 x 595 page", "and the tag on the page says so", field "view:hud"
      set the thumbPosition of scrollbar "view:hs" to 50
      dispatch "scrollbarDrag" to scrollbar "view:hs" of card 1 of stack kStack with 50
      drCheck field "draw:last" contains "pixels at 50,", "the scroll bar moves the window", field "draw:last"
      drClick the long id of button "tb:fitw"
      drCheck field "tb:zoom" is "86%", "Fit width", field "tb:zoom"
      drClick the long id of button "tb:fitp"
      drCheck field "tb:zoom" is "75%" and not the visible of scrollbar "view:hs", "Fit page, with no scroll bar", field "tb:zoom"

      -- search, with every match marked
      drClick the long id of button "side:find"
      put "needle" into field "find:text"
      drClick the long id of button "find:go"
      drCheck field "find:sum" begins with "3 match(es) on 1 page(s)" and the number of lines of field "find:list" is 3 \
            and line 1 of field "find:list" begins with "p. 3", "needle: three matches on the page labelled 3", field "find:sum"
      drCheck field "tb:page" is 5 and the visible of graphic "view:hl3" and not the visible of graphic "view:hl4" \
            and the visible of graphic "view:cur", "its page is shown with the three marked and the first chosen", field "tb:page"
      drClick the long id of button "find:next"
      drCheck the hilitedLine of field "find:list" is 2, "Next chooses the second", the hilitedLine of field "find:list"
      drClick the long id of button "find:case"
      drCheck the hilite of button "find:case" and field "find:sum" begins with "2 match(es)", "Capitals must match (lit): two", field "find:sum"
      drClick the long id of button "find:words"
      drCheck the hilite of button "find:words" and field "find:sum" begins with "1 match(es)", "and whole words too: one", field "find:sum"
      drClick the long id of button "find:case"
      drCheck not the hilite of button "find:case" and field "find:sum" begins with "2 match(es)", "whole words alone: two", field "find:sum"
      drClick the long id of button "find:words"
      put "PDFium" into field "find:text"
      drReturn "find:text"
      drCheck field "find:sum" begins with "3 match(es) on 2 page(s)" and field "tb:page" is 1, "Return searches too: PDFium, three times on two pages", field "find:sum"
      put "no such words anywhere" into field "find:text"
      drClick the long id of button "find:go"
      drCheck field "find:sum" begins with "Not found" and not the visible of graphic "view:hl1", "a search with no match clears the marks", field "find:sum"

      -- a page by its number and by its label
      put "5" into field "tb:page"
      drReturn "tb:page"
      drCheck line 1 of field "txt:page" is "3 Text and search" and field "txt:h" begins with "Page 5: 618 characters", \
            "a typed page number; the Text tab has its text", field "txt:h"
      put "ii" into field "tb:page"
      drReturn "tb:page"
      drCheck field "tb:page" is 2 and field "tb:doc" is "the sample, the page labelled ii", "a typed label finds its page", field "tb:doc"

      -- links: one inside the document is followed, a web address only shown
      drCheck the number of lines of field "lnk:list" is 3 and line 1 of field "lnk:list" is "Goes to page 3 (labelled 1)", \
            "the contents page has three links", line 1 of field "lnk:list"
      drCall "pvClickAt", 200, 137
      drCheck field "tb:page" is 3, "a click on a contents line goes to its page", field "tb:page"
      drCall "pvGo", 1
      drCall "pvClickAt", 130, 448
      drCheck field "tb:page" is 1 and field "lnk:addr" contains "https://openxtalk.org/" and field "ui:status" contains "Nothing was opened", \
            "a web link shows its address and opens nothing", field "lnk:addr"
      drCheck the visible of field "lnk:list" and the visible of graphic "view:ln1", "the Links tab shows, and the link is outlined on the page", the visible of graphic "view:ln1"

      -- a word clicked, and a box dragged out
      put pdfOpenData(base64Decode(value("pvSampleBase64(" & quote & "sample" & quote & ")", stack kStack)), empty) into tDoc
      put pdfPageCharBox(tDoc, 3, 5) into tBox
      pdfClose tDoc
      drCall "pvGo", 3
      drCall "pvClickAt", (item 1 of tBox + item 3 of tBox) / 2, (item 2 of tBox + item 4 of tBox) / 2
      drCheck field "txt:sel" contains "Character 5 of 530" and field "txt:sel" contains "the word it is in: Opening" \
            and the visible of graphic "view:char", "a click on a word names the character and the word", field "txt:sel"
      drCall "pvGo", 5
      drCall "pvSelectBox", 60, 166, 300, 190
      drCheck field "txt:sel" is "needle, Needle, needles" and the visible of graphic "view:sel" and the visible of field "txt:page", \
            "a box gives the text inside it, on the Text tab", field "txt:sel"

      -- drawing: the flags, the BMP picture, a page saved
      drCall "pvGo", 1
      drClick the long id of button "side:draw"
      drCheck the visible of image "draw:thumb" and the height of image "draw:thumb" is 100, "the Draw tab shows the page as a BMP", \
            the width of image "draw:thumb" && the height of image "draw:thumb"
      put drPixel(the imageData of image "view:page", the width of image "view:page", 5, 5) into tPixel
      drCheck tPixel is "44,90,160", "page i's band is the accent colour", tPixel
      drClick the long id of button "draw:gray"
      put drPixel(the imageData of image "view:page", the width of image "view:page", 5, 5) into tPixel
      drCheck the hilite of button "draw:gray" and item 1 of tPixel is item 2 of tPixel and item 2 of tPixel is item 3 of tPixel \
            and field "draw:last" begins with "pdfRenderPage", "Gray, lit, draws it gray", tPixel
      drClick the long id of button "draw:gray"
      put the temporary folder & "/pdfxt-demo-drive-page.bmp" into tPath
      drCall "pvSaveBMP", tPath
      put URL ("binfile:" & tPath) into tData
      drCheck byte 1 to 2 of tData is "BM" and the number of bytes of tData is 54 + 1224 * 3 * 1584, "a page saved as a BMP at two pixels to the point", \
            the number of bytes of tData
      delete file tPath

      -- the locked sample
      drClick the long id of button "tb:locked"
      drCheck the visible of field "lock:pw" and field "lock:msg" contains "secret" and not the visible of image "view:page", \
            "the locked sample asks for its password", field "lock:msg"
      put "nope" into field "lock:pw"
      drClick the long id of button "lock:go"
      drCheck field "lock:msg" begins with "That password did not open it", "a wrong password is refused", field "lock:msg"
      put "secret" into field "lock:pw"
      drReturn "lock:pw"
      drCheck field "tb:of" is "of 1" and not the visible of field "lock:pw" and the visible of image "view:page", "secret opens it", field "ui:status"
      drClick the long id of button "side:info"
      drCheck field "info:area" contains "print no" and field "info:area" contains "copy yes", "its permissions: no printing", field "info:area"

      -- every check, from the Checks tab
      drClick the long id of button "side:chk"
      drClick the long id of button "chk:run"
      put field "chk:log" into tLog
      put tLog & return after sOut
      drCheck the last line of tLog begins with "SUMMARY" and the last word of tLog is 0 and word 2 of the last line of tLog >= 40, \
            "Run every check: all pass", the last line of tLog
      drCheck field "chk:sum" contains "none failed" and field "tb:of" is "of 1", "the window says so, and shows its document again", field "chk:sum"

      -- a scene's button plays that scene; any other click takes it back
      drClick the long id of button "show:2"
      drCheck item 1 of drAsk("pvShowNow") is 2 and drPending("pvShowTick") and the hilite of button "show:2" \
            and not the hilite of button "show:all", "a scene's button plays that scene alone", drAsk("pvShowNow")
      drClick the long id of button "side:out"
      drCheck item 1 of drAsk("pvShowNow") is 0 and not drPending("pvShowTick") and not the hilite of button "show:2", \
            "and a click anywhere else stops it", drAsk("pvShowNow")

      drClick the long id of button "tb:close"
      drCheck field "tb:of" is empty and not the visible of image "view:page" and the visible of field "view:hint" \
            and not the visible of field "view:hud", "Close", field "tb:of"

      if $PDFXT_SHOT is not empty then
         drClick the long id of button "tb:sample"
         put $PDFXT_SCENE into tScene
         if tScene is not empty then
            drCall "pvShowRun", item 1 of tScene, false, item 2 of tScene
         else
            put $PDFXT_TAB into tTab
            if tTab is empty then
               put "find" into tTab
            end if
            drClick the long id of button "side:find"
            put "needle" into field "find:text"
            drClick the long id of button "find:go"
            drClick the long id of button ("side:" & tTab)
         end if
         export snapshot from rect (the rect of card 1 of stack kStack) of card 1 of stack kStack to file $PDFXT_SHOT as PNG
      end if
   catch tError
      drCheck false, "the drive ran to its end", tError
   end try
   write sOut & "DRIVE" && sPassed && sFailed & return to stdout
   if sFailed is 0 and sPassed > 0 then
      quit 0
   end if
   quit 1
end startup
