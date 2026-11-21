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
-- header tells a person to), builds the window, and then does what a person
-- would: opens the sample, follows the outline, zooms and scrolls, searches
-- with and without the flags, types a page label, clicks a link, a word and
-- a web address, drags out a box, draws in gray, saves a page, unlocks the
-- locked sample with a wrong and then the right password, runs every check
-- from the Checks tab and closes the document. A click is the message the
-- engine sends (mouseUp, returnInField, scrollbarDrag); a click or a drag ON
-- THE PAGE is the handler the demo's mouse handlers call with the point they
-- read (pvClickAt, pvSelectBox), since no pointer moves here. The native lane
-- runs it (the suite's .github/workflows/native-pdfxt.yml, job `engine`) and
-- wants BOTH an exit of 0 and a last line "DRIVE <passed> 0": an engine that
-- printed nothing must not read as a pass.
--
-- PDFXT_SHOT (optional) names a PNG to write of the window with the sample
-- searched for "needle", on the tab PDFXT_TAB (a key: out, find, txt, lnk,
-- draw, info or chk). It needs a display (xvfb-run).
--
-- WHAT THIS IS EVIDENCE OF: the demo's logic and its window on OXT-Beyond's
-- Linux engine without a display. It is not a person using the window.

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

-- One pixel of an image's imageData as "r,g,b".
function drPixel pData, pWidth, pX, pY
   local tAt
   put (pY * pWidth + pX) * 4 into tAt
   return byteToNum(byte tAt + 2 of pData) & comma & byteToNum(byte tAt + 3 of pData) & comma & byteToNum(byte tAt + 4 of pData)
end drPixel

on startup
   local tError, tWas, tDoc, tBox, tPath, tData, tPixel, tLog, tTab
   put 0 into sPassed
   put 0 into sFailed
   try
      set the revLibraryMapping["pdfxt"] to $PDFXT_LIB
      load extension from file $PDFXT_LCM
      drCheck the result is empty, "the extension loads", the result
      create stack kStack
      set the script of stack kStack to textDecode(URL ("binfile:" & $PDFXT_DEMO), "UTF-8")
      go stack kStack
      set the defaultStack to kStack
      send "preOpenStack" to stack kStack
      drCheck the width of stack kStack is 1180 and the height of stack kStack is 630, "the window is 1180 x 630", the rect of stack kStack
      drCheck field "uiStatus" begins with "Ready (pdfxt ABI 1; PDFium chromium/", "the status line names the library and its PDFium", field "uiStatus"
      drCheck the visible of field "view:hint" and not the visible of image "view:page" and field "out:h" is "No document is open.", \
            "it opens with no document, on the Outline tab", field "out:h"

      -- a second preOpenStack rebuilds nothing (the version guard)
      put the number of controls of card 1 of stack kStack into tWas
      send "preOpenStack" to stack kStack
      drCheck the number of controls of card 1 of stack kStack is tWas, "reopening adds no control", the number of controls of card 1 of stack kStack

      -- the sample, fitted to the view and drawn whole
      drClick the long id of button "tb:sample"
      drCheck field "tb:of" is "of 5" and field "tb:page" is 1 and field "uiStatus" begins with "Opened the sample: 5 page(s), PDF 1.7", \
            "The sample opens: five pages, PDF 1.7", field "uiStatus"
      drCheck the visible of image "view:page" and the width of image "view:page" is 346 and the height of image "view:page" is 448, \
            "page i is drawn at the size that fits the view", the width of image "view:page" && the height of image "view:page"
      drCheck field "draw:last" begins with "pdfRenderPage: the whole page, 346 x 448 pixels", "a page that fits is drawn whole", field "draw:last"
      drCheck the number of lines of field "out:list" is 8 and line 1 of field "out:list" begins with "Cover" \
            and field "out:h" is "Outline: 8 entries (pdfOutline)", "the outline lists eight entries", line 1 of field "out:list"

      -- the outline takes it to the turned page
      set the hilitedLine of field "out:list" to 5
      drClick the long id of field "out:list"
      drCheck field "tb:page" is 4 and the width of image "view:page" > the height of image "view:page", \
            "an outline entry goes to its page: the turned page, wider than tall", field "tb:page" && the width of image "view:page"
      drClick the long id of button "side:info"
      drCheck field "info:area" contains "842 x 595 points" and field "info:area" contains "A4, on its side" \
            and field "info:area" contains ("Turned" & tab & "90 degrees"), "the Info tab gives the size, the paper and the turn", field "info:area"
      drCheck field "info:area" contains "Title" & tab & "A short guide to pdfxt" and field "info:area" contains "print yes", \
            "and the document's information and permissions", line 5 to 8 of field "info:area"

      -- zoom and scroll
      drCheck field "tb:zoom" is "75%", "the turned page fits at 75%", field "tb:zoom"
      drClick the long id of button "tb:in"
      drCheck field "tb:zoom" is "100%" and field "draw:last" begins with "pdfRenderPageRegion: a window of 744 x 472 pixels" \
            and the visible of scrollbar "view:hs", "zoomed past the view, only the window in view is drawn", field "draw:last"
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
      drCheck the hilite of button "find:case" and field "find:sum" begins with "2 match(es)", "Capitals must match: two", field "find:sum"
      drClick the long id of button "find:words"
      drCheck field "find:sum" begins with "1 match(es)", "and whole words too: one", field "find:sum"
      drClick the long id of button "find:case"
      drCheck field "find:sum" begins with "2 match(es)", "whole words alone: two", field "find:sum"
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
      drCheck field "tb:page" is 1 and field "lnk:addr" contains "https://openxtalk.org/" and field "uiStatus" contains "Nothing was opened", \
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
      drCheck item 1 of tPixel is item 2 of tPixel and item 2 of tPixel is item 3 of tPixel and field "draw:last" begins with "pdfRenderPage", \
            "ticking Gray draws it gray", tPixel
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
      drCheck field "tb:of" is "of 1" and not the visible of field "lock:pw" and the visible of image "view:page", "secret opens it", field "uiStatus"
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

      drClick the long id of button "tb:close"
      drCheck field "tb:of" is empty and not the visible of image "view:page" and the visible of field "view:hint", "Close", field "tb:of"

      if $PDFXT_SHOT is not empty then
         put $PDFXT_TAB into tTab
         if tTab is empty then
            put "find" into tTab
         end if
         drClick the long id of button "tb:sample"
         drClick the long id of button "side:find"
         put "needle" into field "find:text"
         drClick the long id of button "find:go"
         drClick the long id of button ("side:" & tTab)
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
