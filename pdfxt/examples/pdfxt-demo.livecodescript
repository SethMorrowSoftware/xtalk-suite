script "pdfxtDemo"

-- pdfxt-demo.livecodescript - the pdfxt showcase: a PDF viewer in one window.
--
-- It opens on a five-page sample this script carries and plays a short tour
-- of what the library does, one self-running scene at a time: a page drawn
-- deep into a zoom, where only the window in view is drawn; a word found,
-- with every match marked; a page read a character at a time and by a box
-- dragged over it; the outline and the links followed; a locked PDF opened
-- with a wrong and then the right password. Any click takes the window
-- back. Then it is a viewer: open a PDF of your own, turn its pages, zoom
-- and scroll, follow the outline and the links (a web address is shown, and
-- opened only if you ask), search, read the text of a page, of a box you
-- drag out and of the word you click, see the document's information and
-- permissions, change the drawing flags and save a page as a BMP picture.
-- The Checks tab runs every check in one click.
--
-- HOW TO USE (requires the pdfxt extension, org.openxtalk.library.pdfxt,
-- with its PDFium library beside it, as the package installs them): paste
-- this into a stack's script, then close and reopen that stack (or `send
-- "preOpenStack" to <that stack>` without closing). Opening this file itself
-- loads the script and builds no window - that is the engine, not this demo:
-- docs/OXT-ENGINE-NOTES.md 5.5. pdfxt has no browser build, so this stack
-- runs where the desktop libraries do. Without pdfxt the window still
-- builds, and says in red what is missing.
--
-- Conventions: pages and characters count from 1; sizes and rectangles are
-- in points (1/72 inch) from the TOP LEFT of the page as displayed. A call
-- that cannot do what it was asked returns 0 or empty and never throws;
-- pdfLastError() says why.
--
-- THE LOOK is OXT-Beyond's showcase look, the Render3D Tour's palette: a
-- dark window, the page on a darker stage, orange section labels, buttons
-- that light up. This script says every colour of every control and leaves
-- none to the system: under Windows' dark appearance OXT-Beyond gives a
-- field with no text colour of its own white text, and the suite kit's
-- white fields then drew white on white (the page number and the outline,
-- on the maintainer's Windows, 2026-11-21). There is no tick box, since the
-- system draws a tick box's words in its own theme's colours: a switch is a
-- button that is lit while it is on. So this stack does not carry the
-- suite UI kit; tools/check-ui-kit-drift.py records why. The two PDFs are
-- carried between their own marker lines, which tools/build-test-pdfs.py
-- writes (its --check is one of the member's gates).
--
-- MOTION is driven by a timer: each frame of a scene is one `send ... in`
-- message that draws with the screen locked and asks for the next, so the
-- engine is never held in a wait and a click is answered at once.
-- pvShowRun plays a scene through the same frames without the timer, for a
-- drive with no person at it (tests/demo-drive.livecodescript).
--
-- HONESTY (the suite convention): see the footer line this stack paints,
-- which is kept true to what has run.

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kPvUiVersion = "pdfxt-beyond-2"
constant kPvWidth = 1180
constant kPvHeight = 630
-- The page view on the card: the drawn part of the page sits inside it, the
-- two scroll bars outside it (right and below).
constant kPvViewL = 16
constant kPvViewT = 96
constant kPvViewR = 760
constant kPvViewB = 568
-- The column right of the stage, and the top of the scene's progress bar.
constant kPvSideL = 794
constant kPvSideR = 1164
constant kPvBarT = 266
-- The side panel's tabs, in order: key, then the label on its button.
constant kPvTabs = "out,find,txt,lnk,draw,info,chk"
constant kPvTabLabels = "Outline,Search,Text,Links,Draw,Info,Checks"
-- The switches: buttons the script lights while they are on.
constant kPvToggles = "find:case,find:words,lnk:show,draw:annots,draw:lcd,draw:gray,draw:print,draw:smooth"
-- The zooms + and - step through, in percent of a point to a pixel.
constant kPvZooms = "25,50,75,100,125,150,200,300,400,600,800"
-- A stranger's file can hold any number of matches, links and outline
-- entries; the window shows at most these.
constant kPvHits = 60
constant kPvLinkMax = 30
constant kPvFindMax = 300
constant kPvOutlineMax = 2000
-- The Draw tab's switches, and the flag each one adds to every drawing.
constant kPvFlagBoxes = "draw:annots,draw:lcd,draw:gray,draw:print,draw:smooth"
constant kPvFlagValues = "1,2,8,2048,28672"
-- Where the Draw tab's BMP picture sits.
constant kPvThumbAt = "1052,331"
-- The password bar over the top of the stage, and its three controls.
constant kPvLockBg = "24,104,752,138"
constant kPvLockMsg = "34,111,436,133"
constant kPvLockPw = "442,108,598,134"
constant kPvLockGo = "604,108,688,134"
-- The showcase: its scenes, the frames of each, and a frame's length.
constant kPvScenes = 5
constant kPvSceneNames = "Deep zoom,Find a word,Read a page,Outline & links,Unlock"
constant kPvSceneFrames = "240,280,215,330,140"
constant kPvFrameMs = 40
-- The look: OXT-Beyond's showcase palette (the Render3D Tour's), as r,g,b.
constant kPvPage = "18,21,31"
constant kPvPanel = "28,33,48"
constant kPvInk = "238,241,247"
constant kPvSoft = "169,178,199"
constant kPvAccent = "255,138,61"
constant kPvButton = "42,49,70"
-- and its additions: the stage under the page, a field's ground and line,
-- a chosen line on a Mac (pvChosenColor), and what the status line says
-- things with
constant kPvStage = "10,12,18"
constant kPvWell = "21,25,37"
constant kPvLine = "56,64,88"
constant kPvSelect = "60,76,120"
constant kPvOk = "96,214,142"
constant kPvWarn = "242,193,78"
constant kPvBad = "255,112,112"
-- A field's first line begins 6 pixels ABOVE its top margin (the engine's
-- TEXT_Y_OFFSET, engine note 5.19): a top margin of 6 puts the line at the
-- field's top edge, and each builder below adds the room it wants to that.
-- With the 1 of a margin "2,1,2,1", every label's words rose 5 pixels above
-- it, and on Windows the tops of the letters were cut off (2026-11-21).
constant kPvLift = 6
-- The room a window's title bar takes above its card, kept on the screen
-- when the window is moved onto it (pvPlaceWindow).
constant kPvTitleBar = 32

local sDoc          -- the open document's handle, or 0
local sSource       -- where it came from: "sample", "locked" or a file's path
local sPassword     -- the password it opened with, to open it again after the checks
local sWaiting      -- a source that is waiting for its password, or empty
local sPages        -- how many pages it has
local sPage         -- the page shown, from 1
local sOutline      -- pdfOutline of it, as the Outline tab lists it
local sZoom         -- pixels per point
local sFit          -- "page", "width", or empty for a zoom chosen with + and -
local sZoomW        -- the WHOLE page's size at this zoom, in pixels
local sZoomH
local sScrollX      -- the top left of the part shown, in pixels of the zoomed page
local sScrollY
local sImgL         -- where the drawn part sits on the card, and its size
local sImgT
local sImgW
local sImgH
local sFlags        -- the drawing flags the Draw tab adds up
local sLastDraw     -- which call drew the page last, its sizes and its time
local sLinks        -- pdfPageLinks of the page shown
local sNeedle       -- the last search: its text, and every match as page,start,count
local sFinds
local sFindAt       -- the match chosen in the list, or 0
local sHitRects     -- the rectangles of the matches on the page shown, in points
local sCurRects     -- and of the chosen match
local sSel          -- the box dragged out on the page, in points
local sCharRect     -- the box of the character last clicked, in points
local sAddress      -- the web address last shown (opened only on request)
local sDragging     -- a press on the page that has not been released
local sDragH
local sDragV
local sTab          -- the side panel's tab, one of kPvTabs
local sCkPass       -- Checks: passing checks
local sCkFail       -- Checks: failing checks
local sCkLog        -- Checks: the running transcript
local sShow         -- the scene playing, 1 to kPvScenes, or 0
local sShowAll      -- true while Play them all runs the scenes in turn
local sShowStep     -- the frame of the scene playing, from 1
local sShowMsg      -- the next frame's message, so that it can be cancelled
local sShowLog      -- what the scenes did, a line each, for a drive to read
local sShowPeak     -- the deepest zoom of the zoom scene, in percent
local sShowWindows  -- how many of its frames were drawn as a window
local sShowFit      -- the zoom that fitted the page when the zoom scene began
local sShowFromH    -- where the pointer's glide began, on the card
local sShowFromV

-- >>> BEGIN SAMPLE PDFS (tools/build-test-pdfs.py writes this block: change that script, then run it) >>>
-- The guide that "The sample" opens (5 pages, written by that script) and
-- tests/fixtures/locked.pdf (its password is secret), as base64 text cut into
-- constants of 2000 characters, and the one function that joins them.
constant kPvSample1 = "JVBERi0xLjcKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgL091dGxpbmVzIDIxIDAgUiAvUGFnZU1vZGUgL1VzZU91dGxpbmVzIC9QYWdlTGFiZWxzIDw8IC9OdW1zIFswIDw8IC9TIC9yID4+IDIgPDwgL1MgL0QgPj5dID4+ID4+CmVuZG9iagoyIDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvS2lkcyBbMyAwIFIgNCAwIFIgNSAwIFIgNiAwIFIgNyAwIFJdIC9Db3VudCA1ID4+CmVuZG9iagozIDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gL0NvbnRlbnRzIDggMCBSIC9SZXNvdXJjZXMgPDwgL0ZvbnQgPDwgL0YxIDEzIDAgUiAvRjIgMTQgMCBSID4+ID4+IC9Bbm5vdHMgWzE1IDAgUl0gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgOSAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgMTMgMCBSIC9GMiAxNCAwIFIgPj4gPj4gL0Fubm90cyBbMTYgMCBSIDE3IDAgUiAxOCAwIFJdID4+CmVuZG9iago1IDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gL0NvbnRlbnRzIDEwIDAgUiAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSAxMyAwIFIgL0YyIDE0IDAgUiA+PiA+PiA+PgplbmRvYmoKNiAwIG9iago8PCAvVHlwZSAvUGFnZSAvUGFyZW50IDIgMCBSIC9NZWRpYUJveCBbMCAwIDU5NSA4NDJdIC9Sb3RhdGUgOTAgL0NvbnRlbnRzIDExIDAgUiAvUmVzb3VyY2VzIDw8IC9Gb250IDw8IC9GMSAxMyAwIFIgL0YyIDE0IDAgUiA+PiA+PiA+PgplbmRvYmoKNyAwIG9iago8PCAvVHlwZSAvUGFnZSAvUGFyZW50IDIgMCBSIC9NZWRpYUJveCBbMCAwIDYxMiA3OTJdIC9Db250ZW50cyAxMiAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgMTMgMCBSIC9GMiAxNCAwIFIgPj4gPj4gL0Fubm90cyBbMTkgMCBSXSA+PgplbmRvYmoKOCAwIG9iago8PCAvTGVuZ3RoIDkyMyA+PgpzdHJlYW0KMC4xNzMgMC4zNTMgMC42MjcgcmcKMCA2NDIgNjEyIDE1MCByZQpmCjEuMDAwIDEuMDAwIDEuMDAwIHJnCkJUCi9GMiA0OCBUZgo3MiA3MDAgVGQKKHBkZnh0KSBUagpFVAoxLjAwMCAxLjAwMCAxLjAwMCByZwpCVAovRjEgMTYgVGYKNzIgNjY4IFRkCihBIHNob3J0IGd1aWRlLCBhbmQgdGhlIHNhbXBsZSB0aGUgZGVtbyBvcGVucykgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDYwMCBUZAoocGRmeHQgZHJhd3MgdGhlIHBhZ2VzIG9mIGEgUERGLCByZWFkcyB0aGVpciB0ZXh0LCBmaW5kcyB3b3JkcyBpbiBpdCwpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgo3MiA1ODQgVGQKKGZvbGxvd3MgaXRzIG91dGxpbmUgYW5kIGl0cyBsaW5rcywgYW5kIHRlbGxzIGEgc2NyaXB0IGFsbCBvZiBpdC4pIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9G"
constant kPvSample2 = "MSAxMiBUZgo3MiA1NjggVGQKKEl0IGJpbmRzIFBERml1bSwgdGhlIFBERiBlbmdpbmUgb2YgdGhlIENocm9taXVtIGJyb3dzZXIuKSBUagpFVAoxLjAwMCAwLjAwMCAwLjAwMCByZwo3MiA0MjAgMTAwIDEwMCByZQpmCjAuMDAwIDAuNjI3IDAuMDAwIHJnCjIyMiA0MjAgMTAwIDEwMCByZQpmCjAuMDAwIDAuMDAwIDEuMDAwIHJnCjM3MiA0MjAgMTAwIDEwMCByZQpmCjAuNTQxIDAuNTczIDAuNjIwIHJnCkJUCi9GMSAxMCBUZgo3MiA0MDAgVGQKKFRocmVlIHNxdWFyZXMsIHRvIHNlZSB0aGUgY29sb3VycyBjb21lIHRocm91Z2guKSBUagpFVAowLjA3OCAwLjMxNCAwLjc4NCByZwpCVAovRjEgMTIgVGYKNzIgMzQwIFRkCihodHRwczovL29wZW54dGFsay5vcmcvKSBUagpFVAowLjU0MSAwLjU3MyAwLjYyMCByZwpCVAovRjEgOSBUZgo3MiA0MCBUZAooQSBzaG9ydCBndWlkZSB0byBwZGZ4dCwgcGFnZSBpKSBUagpFVAoKZW5kc3RyZWFtCmVuZG9iago5IDAgb2JqCjw8IC9MZW5ndGggNDQ1ID4+CnN0cmVhbQowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjIgMjQgVGYKNzIgNzAwIFRkCihDb250ZW50cykgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDE0IFRmCjcyIDY1MCBUZAooMSBPcGVuaW5nIGEgZG9jdW1lbnQpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxNCBUZgo3MiA2MjQgVGQKKDIgRHJhd2luZyBwYWdlcykgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDE0IFRmCjcyIDU5OCBUZAooMyBUZXh0IGFuZCBzZWFyY2gpIFRqCkVUCjAuNTQxIDAuNTczIDAuNjIwIHJnCkJUCi9GMSAxMCBUZgo3MiA1NjAgVGQKKEVhY2ggbGluZSBhYm92ZSBpcyBhIGxpbmsgdG8gaXRzIHBhZ2UuKSBUagpFVAowLjU0MSAwLjU3MyAwLjYyMCByZwpCVAovRjEgOSBUZgo3MiA0MCBUZAooQSBzaG9ydCBndWlkZSB0byBwZGZ4dCwgcGFnZSBpaSkgVGoKRVQKCmVuZHN0cmVhbQplbmRvYmoKMTAgMCBvYmoKPDwgL0xlbmd0aCAxMDQwID4+CnN0cmVhbQowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjIgMjAgVGYKNzIgNzIwIFRkCigxIE9wZW5pbmcgYSBkb2N1bWVudCkgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDY5MCBUZAoocGRmT3BlbiBvcGVucyBhIGZpbGUgYnkgaXRzIHBhdGgsIGFuZCBQREZpdW0gcmVhZHMgZWFjaCBwYWdlIG9ubHkgd2hlbikgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDY3NCBUZAooaXQgaXMgYXNrZWQgZm9yLCBzbyBhIGxvbmcgZG9jdW1lbnQgb3BlbnMgYXQgb25jZS4gcGRmT3BlbkRhdGEgb3BlbnMgYSkgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDY1OCBUZAooUERGIHRoYXQgaXMgYWxyZWFkeSBpbiBtZW1vcnk6IHRoaXMgc2FtcGxlIGlzIG9uZSwgY2FycmllZCBpbnNpZGUgdGhlKSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKNzIgNjQyIFRkCihk"
constant kPvSample3 = "ZW1vIHN0YWNrIGFzIHRleHQgYW5kIGRlY29kZWQgYmVmb3JlIFBERml1bSBzZWVzIGl0LikgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YyIDE0IFRmCjcyIDYwMCBUZAooUGFzc3dvcmRzKSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKNzIgNTc4IFRkCihBIGxvY2tlZCBQREYgbmVlZHMgaXRzIHBhc3N3b3JkLiBwZGZPcGVuIGFuZCBwZGZPcGVuRGF0YSB0YWtlIGl0IGFzKSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKNzIgNTYyIFRkCih0aGVpciBzZWNvbmQgcGFyYW1ldGVyIGFuZCByZWZ1c2Ugd2l0aG91dCBpdCwgYW5kIHBkZkxhc3RFcnJvciBzYXlzKSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKNzIgNTQ2IFRkCih3aHkuIFRoZSBkZW1vJ3MgTG9ja2VkIHNhbXBsZSBvcGVucyB3aXRoIHRoZSB3b3JkIHNlY3JldC4pIFRqCkVUCjAuNTQxIDAuNTczIDAuNjIwIHJnCkJUCi9GMSA5IFRmCjcyIDQwIFRkCihBIHNob3J0IGd1aWRlIHRvIHBkZnh0LCBwYWdlIDEpIFRqCkVUCgplbmRzdHJlYW0KZW5kb2JqCjExIDAgb2JqCjw8IC9MZW5ndGggMTI5NCA+PgpzdHJlYW0KMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YyIDIwIFRmCjAgMSAtMSAwIDcwIDYwIFRtCigyIERyYXdpbmcgcGFnZXMpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgowIDEgLTEgMCAxMDAgNjAgVG0KKFRoaXMgcGFnZSBpcyBBNCB0dXJuZWQgb24gaXRzIHNpZGU6IHRoZSBmaWxlIHNheXMgL1JvdGF0ZSA5MCwgYW5kIGV2ZXJ5KSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKMCAxIC0xIDAgMTE2IDYwIFRtCihzaXplLCBkcmF3aW5nIGFuZCByZWN0YW5nbGUgcGRmeHQgcmV0dXJucyBpcyBvZiB0aGUgcGFnZSBhcyB5b3Ugc2VlIGl0LikgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjAgMSAtMSAwIDEzMiA2MCBUbQoocGRmUmVuZGVyUGFnZSBkcmF3cyBhIHdob2xlIHBhZ2UuIHBkZlJlbmRlclBhZ2VSZWdpb24gZHJhd3Mgb25seSB0aGUgcGFydCkgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjAgMSAtMSAwIDE0OCA2MCBUbQooYSB6b29tZWQtaW4gdmlld2VyIHNob3dzLCBzbyBtZW1vcnkgZm9sbG93cyB0aGUgd2luZG93LCBub3QgdGhlIHpvb20uKSBUagpFVAowLjE3MyAwLjM1MyAwLjYyNyByZwo0MjAgNjAgODAgNTYgcmUKZgowLjA5MCAwLjUwMiAwLjI0NyByZwozNjAgMTQwIDE0MCA1NiByZQpmCjAuODM5IDAuNTg4IDAuMTE4IHJnCjM5MCAyMjAgMTEwIDU2IHJlCmYKMC42OTAgMC4yMjcgMC4xODAgcmcKMzEwIDMwMCAxOTAgNTYgcmUKZgowLjAwMCAwLjUwMiAwLjUwMiByZwozNDAgMzgwIDE2MCA1NiByZQpmCjAuNDMxIDAuMjM1IDAuNTg4IHJnCjI4MCA0NjAgMjIwIDU2IHJlCmYKMC43ODAgMC44NDcgMC45NDUgcmcKNDcwLjAwIDY4MC4wMCBtCjQ3MC4w"
constant kPvSample4 = "MCA3NDAuNzUgNDIwLjc1IDc5MC4wMCAzNjAuMDAgNzkwLjAwIGMKMjk5LjI1IDc5MC4wMCAyNTAuMDAgNzQwLjc1IDI1MC4wMCA2ODAuMDAgYwoyNTAuMDAgNjE5LjI1IDI5OS4yNSA1NzAuMDAgMzYwLjAwIDU3MC4wMCBjCjQyMC43NSA1NzAuMDAgNDcwLjAwIDYxOS4yNSA0NzAuMDAgNjgwLjAwIGMKZgowLjU0MSAwLjU3MyAwLjYyMCByZwpCVAovRjEgMTAgVGYKMCAxIC0xIDAgNTMwIDYwIFRtCihTaGFwZXMgYXJlIGRyYXduIGFzIGN1cnZlcyBhbmQgbGluZXM6IHpvb20gaW4sIGFuZCB0aGVpciBlZGdlcyBzdGF5IHNoYXJwLikgVGoKRVQKMC41NDEgMC41NzMgMC42MjAgcmcKQlQKL0YxIDkgVGYKMCAxIC0xIDAgNTcwIDYwIFRtCihBIHNob3J0IGd1aWRlIHRvIHBkZnh0LCBwYWdlIDIpIFRqCkVUCgplbmRzdHJlYW0KZW5kb2JqCjEyIDAgb2JqCjw8IC9MZW5ndGggMTI5MyA+PgpzdHJlYW0KMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YyIDIwIFRmCjcyIDcyMCBUZAooMyBUZXh0IGFuZCBzZWFyY2gpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgo3MiA2OTAgVGQKKHBkZlBhZ2VUZXh0IHJldHVybnMgdGhlIHRleHQgb2YgYSBwYWdlIGluIHJlYWRpbmcgb3JkZXIsIGEgbGluZSBvZiB0aGUpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgo3MiA2NzQgVGQKKHBhZ2UgdG8gYSBsaW5lLiBwZGZQYWdlU2VhcmNoIGZpbmRzIGV2ZXJ5IHBsYWNlIGEgd29yZCBvY2N1cnMsIGFuZCkgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDY1OCBUZAoocGRmUGFnZVRleHRSZWN0cyBnaXZlcyB0aGUgcmVjdGFuZ2xlcyB0byBoaWdobGlnaHQuIFNlYXJjaCB0aGlzIHBhZ2UpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgo3MiA2NDIgVGQKKGZvciB0aGUgd29yZCBvbiB0aGUgbmV4dCBsaW5lLCB3aXRoIGFuZCB3aXRob3V0IHRoZSB0d28gZmxhZ3M6KSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjIgMTQgVGYKNzIgNjEwIFRkCihuZWVkbGUsIE5lZWRsZSwgbmVlZGxlcykgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YyIDE0IFRmCjcyIDU3MCBUZAooU2VhcmNoaW5nKSBUagpFVAowLjExMCAwLjEzMyAwLjE4MCByZwpCVAovRjEgMTIgVGYKNzIgNTQ4IFRkCihDYXBpdGFscyBtdXN0IG1hdGNoOiB0d28gb2YgdGhlIHRocmVlLiBXaG9sZSB3b3JkczogdHdvLCBzaW5jZSB0aGUpIFRqCkVUCjAuMTEwIDAuMTMzIDAuMTgwIHJnCkJUCi9GMSAxMiBUZgo3MiA1MzIgVGQKKHRoaXJkIGlzIGxvbmdlci4gQm90aCBmbGFnczogb25lLikgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQKL0YxIDEyIFRmCjcyIDUxNiBUZAooVGV4dCBvdXRzaWRlIEFTQ0lJIGNvbWVzIG91dCBhcyBpdHNlbGY6IGNhZlwzNTEsIG5hXDM1N3ZlLCBaXDM3NHJpY2gsIDI1IFwyNjBDLikgVGoKRVQKMC4xMTAgMC4xMzMgMC4xODAgcmcKQlQK"
constant kPvSample5 = "L0YxIDEyIFRmCjcyIDUwMCBUZAooRHJhZyBhIGJveCBhcm91bmQgd29yZHMgb24gYW55IHBhZ2UgdG8gcmVhZCB0aGUgdGV4dCBpbnNpZGUgaXQuKSBUagpFVAowLjA3OCAwLjMxNCAwLjc4NCByZwpCVAovRjEgMTIgVGYKNzIgNDYwIFRkCihCYWNrIHRvIHRoZSBjb250ZW50cykgVGoKRVQKMC41NDEgMC41NzMgMC42MjAgcmcKQlQKL0YxIDkgVGYKNzIgNDAgVGQKKEEgc2hvcnQgZ3VpZGUgdG8gcGRmeHQsIHBhZ2UgMykgVGoKRVQKCmVuZHN0cmVhbQplbmRvYmoKMTMgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhIC9FbmNvZGluZyAvV2luQW5zaUVuY29kaW5nID4+CmVuZG9iagoxNCAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EtQm9sZCAvRW5jb2RpbmcgL1dpbkFuc2lFbmNvZGluZyA+PgplbmRvYmoKMTUgMCBvYmoKPDwgL1R5cGUgL0Fubm90IC9TdWJ0eXBlIC9MaW5rIC9Cb3JkZXIgWzAgMCAwXSAvUmVjdCBbNzAgMzM1IDIwNiAzNTNdIC9BIDw8IC9TIC9VUkkgL1VSSSAoaHR0cHM6Ly9vcGVueHRhbGsub3JnLykgPj4gPj4KZW5kb2JqCjE2IDAgb2JqCjw8IC9UeXBlIC9Bbm5vdCAvU3VidHlwZSAvTGluayAvQm9yZGVyIFswIDAgMF0gL1JlY3QgWzcwIDY0NSAzMzAgNjY1XSAvRGVzdCBbNSAwIFIgL0ZpdF0gPj4KZW5kb2JqCjE3IDAgb2JqCjw8IC9UeXBlIC9Bbm5vdCAvU3VidHlwZSAvTGluayAvQm9yZGVyIFswIDAgMF0gL1JlY3QgWzcwIDYxOSAzMzAgNjM5XSAvRGVzdCBbNiAwIFIgL0ZpdF0gPj4KZW5kb2JqCjE4IDAgb2JqCjw8IC9UeXBlIC9Bbm5vdCAvU3VidHlwZSAvTGluayAvQm9yZGVyIFswIDAgMF0gL1JlY3QgWzcwIDU5MyAzMzAgNjEzXSAvRGVzdCBbNyAwIFIgL0ZpdF0gPj4KZW5kb2JqCjE5IDAgb2JqCjw8IC9UeXBlIC9Bbm5vdCAvU3VidHlwZSAvTGluayAvQm9yZGVyIFswIDAgMF0gL1JlY3QgWzcwIDQ1NSAxOTYgNDczXSAvRGVzdCBbNCAwIFIgL0ZpdF0gPj4KZW5kb2JqCjIwIDAgb2JqCjw8IC9UaXRsZSAoQSBzaG9ydCBndWlkZSB0byBwZGZ4dCkgL0F1dGhvciAoeFRhbGsgU3VpdGUpIC9TdWJqZWN0IChUaGUgc2FtcGxlIFBERiBvZiB0aGUgcGRmeHQgZGVtbyBzdGFjaykgL0tleXdvcmRzIChwZGYsIHBkZml1bSwgb3Blbnh0YWxrKSAvQ3JlYXRvciAocGRmeHQgdG9vbHMvYnVpbGQtdGVzdC1wZGZzLnB5KSAvUHJvZHVjZXIgKHBkZnh0IHRvb2xzL2J1aWxkLXRlc3QtcGRmcy5weSkgL0NyZWF0aW9uRGF0ZSAoRDoyMDI2MTEyMTAwMDAwMFopIC9Nb2REYXRlIChEOjIwMjYxMTIxMDAwMDAwWikgPj4KZW5kb2JqCjIxIDAgb2JqCjw8IC9UeXBlIC9PdXRsaW5lcyAvRmlyc3QgMjIgMCBSIC9MYXN0IDI5IDAgUiAvQ291bnQgOCA+PgplbmRvYmoKMjIgMCBvYmoKPDwgL1RpdGxlIChDb3ZlcikgL1BhcmVudCAyMSAwIFIgL05leHQgMjMgMCBSIC9EZXN0IFszIDAgUiAvRml0XSA+PgplbmRvYmoK"
constant kPvSample6 = "MjMgMCBvYmoKPDwgL1RpdGxlIChDb250ZW50cykgL1BhcmVudCAyMSAwIFIgL1ByZXYgMjIgMCBSIC9OZXh0IDI0IDAgUiAvRGVzdCBbNCAwIFIgL0ZpdF0gPj4KZW5kb2JqCjI0IDAgb2JqCjw8IC9UaXRsZSAoMSBPcGVuaW5nIGEgZG9jdW1lbnQpIC9QYXJlbnQgMjEgMCBSIC9QcmV2IDIzIDAgUiAvTmV4dCAyNiAwIFIgL0ZpcnN0IDI1IDAgUiAvTGFzdCAyNSAwIFIgL0NvdW50IDEgL0Rlc3QgWzUgMCBSIC9GaXRdID4+CmVuZG9iagoyNSAwIG9iago8PCAvVGl0bGUgKFBhc3N3b3JkcykgL1BhcmVudCAyNCAwIFIgL0Rlc3QgWzUgMCBSIC9YWVogNzIgNjIwIDBdID4+CmVuZG9iagoyNiAwIG9iago8PCAvVGl0bGUgKDIgRHJhd2luZyBwYWdlcykgL1BhcmVudCAyMSAwIFIgL1ByZXYgMjQgMCBSIC9OZXh0IDI3IDAgUiAvRGVzdCBbNiAwIFIgL0ZpdF0gPj4KZW5kb2JqCjI3IDAgb2JqCjw8IC9UaXRsZSAoMyBUZXh0IGFuZCBzZWFyY2gpIC9QYXJlbnQgMjEgMCBSIC9QcmV2IDI2IDAgUiAvTmV4dCAyOSAwIFIgL0ZpcnN0IDI4IDAgUiAvTGFzdCAyOCAwIFIgL0NvdW50IDEgL0Rlc3QgWzcgMCBSIC9GaXRdID4+CmVuZG9iagoyOCAwIG9iago8PCAvVGl0bGUgKFNlYXJjaGluZykgL1BhcmVudCAyNyAwIFIgL0Rlc3QgWzcgMCBSIC9YWVogNzIgNTkwIDBdID4+CmVuZG9iagoyOSAwIG9iago8PCAvVGl0bGUgKE9wZW5YVGFsayBvbiB0aGUgd2ViKSAvUGFyZW50IDIxIDAgUiAvUHJldiAyNyAwIFIgL0EgPDwgL1MgL1VSSSAvVVJJIChodHRwczovL29wZW54dGFsay5vcmcvKSA+PiA+PgplbmRvYmoKeHJlZgowIDMwCjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMTU4IDAwMDAwIG4gCjAwMDAwMDAyMzkgMDAwMDAgbiAKMDAwMDAwMDM5NCAwMDAwMCBuIAowMDAwMDAwNTYzIDAwMDAwIG4gCjAwMDAwMDA3MDIgMDAwMDAgbiAKMDAwMDAwMDg1MiAwMDAwMCBuIAowMDAwMDAxMDA4IDAwMDAwIG4gCjAwMDAwMDE5ODIgMDAwMDAgbiAKMDAwMDAwMjQ3OCAwMDAwMCBuIAowMDAwMDAzNTcxIDAwMDAwIG4gCjAwMDAwMDQ5MTggMDAwMDAgbiAKMDAwMDAwNjI2NCAwMDAwMCBuIAowMDAwMDA2MzYyIDAwMDAwIG4gCjAwMDAwMDY0NjUgMDAwMDAgbiAKMDAwMDAwNjYwMSAwMDAwMCBuIAowMDAwMDA2NzA5IDAwMDAwIG4gCjAwMDAwMDY4MTcgMDAwMDAgbiAKMDAwMDAwNjkyNSAwMDAwMCBuIAowMDAwMDA3MDMzIDAwMDAwIG4gCjAwMDAwMDczNDIgMDAwMDAgbiAKMDAwMDAwNzQxNiAwMDAwMCBuIAowMDAwMDA3NTAwIDAwMDAwIG4gCjAwMDAwMDc2MDAgMDAwMDAgbiAKMDAwMDAwNzc0OCAwMDAwMCBuIAowMDAwMDA3ODMyIDAwMDAwIG4gCjAwMDAwMDc5MzkgMDAwMDAgbiAKMDAwMDAwODA4NCAwMDAwMCBuIAowMDAwMDA4MTY4IDAwMDAwIG4gCnRyYWlsZXIKPDwgL1NpemUgMzAgL1Jvb3QgMSAwIFIgL0luZm8gMjAgMCBSIC9JRCBbPDEwMTExMjEzMTQxNTE2MTcxODE5MWExYjFjMWQxZTFmPiA8MTAxMTEyMTMx"
constant kPvSample7 = "NDE1MTYxNzE4MTkxYTFiMWMxZDFlMWY+XSA+PgpzdGFydHhyZWYKODI5NQolJUVPRgo="
constant kPvLocked1 = "JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCAxMzcgPj4Kc3RyZWFtCmq5fZHZ1OjFWksFgDbGWs09CLe4PbdFDDPFlBllm3iguTcd9ckKsp7hMtzDm+dLAW2bgxn7pZOJ4B9PMW/q+K+bHHugrTY8tBfWHPAohPvKNGXcxSNr5yR4ocl1HbZX9zaZQNVEP4BHNAbqN3QK0gsLBFXPMTls41Tc5QiX6vPZ5pJp+qoh3GV+CmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgL0VuY29kaW5nIC9XaW5BbnNpRW5jb2RpbmcgPj4KZW5kb2JqCjYgMCBvYmoKPDwgL1RpdGxlICg7XDMzMFwwMDFZXDIxMVwzNzRcMzAzXDI1NzZcMzEyXDAxN1wyMTNcMzIxXDAzNlwzMjRcMjQzXDI1MWhcMzcyXDM1MHxcMjM2KSA+PgplbmRvYmoKNyAwIG9iago8PCAvRmlsdGVyIC9TdGFuZGFyZCAvViAxIC9SIDIgL08gKFwyMjJcMzc2XDAxN0RUXDI1NUxcMjI2RGk/M1wzMDB8XDI2NU9YfVwzMTZcMDM2JlwyMDJcMzc2XDIzNlwzMTZcMjQ2XDAyMHpcMDM2XDM2NjBcMzM1KSAvVSAoVkE+XDM0MVwyNjQtT1wyMjVcMDAwI1wzMjJcMzU1cFBcMzIxXDAyMFwyNjRzXDAzNlwwMTcjY1wyNzVTXDAwMVwwMzdcMjAzXDAwNVwyNjRcMzA0XCgtKSAvUCAtOCA+PgplbmRvYmoKeHJlZgowIDgKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE1IDAwMDAwIG4gCjAwMDAwMDAwNjQgMDAwMDAgbiAKMDAwMDAwMDEyMSAwMDAwMCBuIAowMDAwMDAwMjQ3IDAwMDAwIG4gCjAwMDAwMDA0MzUgMDAwMDAgbiAKMDAwMDAwMDUzMiAwMDAwMCBuIAowMDAwMDAwNjM2IDAwMDAwIG4gCnRyYWlsZXIKPDwgL1NpemUgOCAvUm9vdCAxIDAgUiAvSW5mbyA2IDAgUiAvSUQgWzwxMDExMTIxMzE0MTUxNjE3MTgxOTFhMWIxYzFkMWUxZj4gPDEwMTExMjEzMTQxNTE2MTcxODE5MWExYjFjMWQxZTFmPl0gL0VuY3J5cHQgNyAwIFIgPj4Kc3RhcnR4cmVmCjg3NgolJUVPRgo="

-- The base64 of a sample: pWhich is "locked" for the locked page, anything
-- else for the guide.
function pvSampleBase64 pWhich
   if pWhich is "locked" then
      return kPvLocked1
   end if
   return kPvSample1 & kPvSample2 & kPvSample3 & kPvSample4 & kPvSample5 & kPvSample6 & kPvSample7
end pvSampleBase64
-- <<< END SAMPLE PDFS <<<

on preOpenStack
   if sDoc is empty then
      put 0 into sDoc
      put 0 into sPages
      put 0 into sPage
      put 1 into sZoom
      put "page" into sFit
      put 0 into sFlags
      put 0 into sFindAt
      put false into sDragging
      put 0 into sShow
      put false into sShowAll
   end if
   pvBuildUI
   pvPlaceWindow the working screenRects
   pvShowTab "out"
   if pvReady() then
      if sDoc is 0 then
         pvOpen "sample", empty
      else
         pvShowDocument
      end if
      pvSay "Ready (" & pdfLibraryVersion() & "). The tour plays by itself: click anything to take over.", "ok"
      -- The opening motion: the first scene starts as soon as the window
      -- is up, with nothing to click.
      pvShowCancel
      send "pvTourStart" to me in 250 milliseconds
      put the result into sShowMsg
   else
      put "This viewer needs pdfxt, and it is not here: install the pdfxt extension" \
            && "(org.openxtalk.library.pdfxt, with its PDFium beside it), then open this stack again." into field "view:hint"
      pvShowDocument
   end if
end preOpenStack

on closeStack
   -- Only this window's own document is closed. pdfShutdown would close
   -- every document of every stack in this engine, since PDFium is loaded
   -- once per process; the Checks tab calls it, and says so.
   pvStopShow
   pvCloseDocument
end closeStack

-- The window opens where it was last saved, and one saved on a bigger screen
-- can open partly off a smaller one (on Windows, 2026-11-21: saved at
-- 803,205, it reached 1983 across a screen 1821 wide). So unless it fits on
-- one of pScreens (the working screenRects: a rect a line, each screen
-- less its taskbar, menu bar or dock), it moves to the middle of the
-- first, its title bar kept on it. With no screen (an engine with no
-- display) nothing moves. The result says which: fits, moved or no screen.
command pvPlaceWindow pScreens
   local tRect, tScreen, tLeft, tTop
   put the rect of this stack into tRect
   repeat for each line tScreen in pScreens
      if item 3 of tScreen <= item 1 of tScreen then
         next repeat
      end if
      if item 1 of tRect >= item 1 of tScreen and item 2 of tRect >= item 2 of tScreen + kPvTitleBar \
            and item 3 of tRect <= item 3 of tScreen and item 4 of tRect <= item 4 of tScreen then
         return "fits"
      end if
   end repeat
   put line 1 of pScreens into tScreen
   if item 3 of tScreen <= item 1 of tScreen then
      return "no screen"
   end if
   put max(item 1 of tScreen, item 1 of tScreen + (item 3 of tScreen - item 1 of tScreen - the width of this stack) div 2) into tLeft
   put max(item 2 of tScreen + kPvTitleBar, item 2 of tScreen + (item 4 of tScreen - item 2 of tScreen - the height of this stack) div 2) into tTop
   set the topLeft of this stack to tLeft & comma & tTop
   return "moved"
end pvPlaceWindow

-- ==========================================================================
-- UI construction. Every generated control is named "prefix:role": "ui" the
-- window's own words, "tb" the toolbar, "view" the page and what lies over
-- it, "lock" the password bar, "show" the showcase, "side" the tab buttons,
-- and each tab's key its own controls. So one loop shows a tab and one
-- handler routes a click.
-- ==========================================================================

on pvBuildUI
   local tIndex, tKey, tLeft, tTop, tN
   -- Version-guarded rebuild: a saved stack keeps its controls, so only a
   -- layout bump (kPvUiVersion) rebuilds them.
   if the uPvUiVersion of this stack is kPvUiVersion and there is a button "side:out" then
      exit pvBuildUI
   end if
   pvClearUI
   lock screen
   -- About two hundred controls are made here; with messages locked the IDE
   -- is not told of each one (engine note 5.15).
   lock messages
   -- 1180 x 630 is held by tools/check-stack-size.py (every window fits 720p).
   set the width of this stack to kPvWidth
   set the height of this stack to kPvHeight
   set the title of this stack to "pdfxt - PDF Viewer"
   -- The stack's own colours are what a control without its own inherits;
   -- every control below says its own as well.
   set the backgroundColor of this stack to kPvPage
   set the foregroundColor of this stack to kPvInk
   set the hiliteColor of this stack to pvChosenColor()
   set the borderColor of this stack to kPvLine
   set the textSize of this stack to 12
   set the backgroundColor of this card to kPvPage

   -- The header: OXT-Beyond, the demo's name, what it does, who made it.
   pvLabel "ui:kicker", "OXT-BEYOND  /  PDFXT", "16,4,600,23", 11, kPvAccent, "bold"
   pvLabel "ui:title", "PDF Viewer", "16,19,156,56", 22, kPvInk, "bold"
   pvLabel "ui:about", "Pages drawn, searched and read by PDFium, in an ordinary image." \
         && "The two sample PDFs are inside this stack.", "160,29,960,51", 12, kPvSoft, empty
   pvLabel "ui:credit", "by Seth Morrow", "960,29,1164,51", 12, kPvInk, empty
   set the textAlign of field "ui:credit" to "right"

   pvButton "tb:open", "Open a PDF...", "16,58,124,84"
   pvButton "tb:sample", "The sample", "130,58,222,84"
   pvButton "tb:locked", "Locked sample", "228,58,340,84"
   pvButton "tb:close", "Close", "346,58,404,84"
   pvButton "tb:prev", "<", "424,58,452,84"
   pvInput "tb:page", "456,58,500,84"
   set the textAlign of field "tb:page" to "center"
   pvLabel "tb:of", empty, "504,60,556,82", 12, kPvSoft, empty
   pvButton "tb:next", ">", "558,58,586,84"
   pvButton "tb:out", "-", "604,58,632,84"
   pvLabel "tb:zoom", empty, "634,60,688,82", 12, kPvInk, "bold"
   set the textAlign of field "tb:zoom" to "center"
   pvButton "tb:in", "+", "690,58,718,84"
   pvButton "tb:fitp", "Fit page", "726,58,800,84"
   pvButton "tb:fitw", "Fit width", "806,58,884,84"
   pvLabel "tb:doc", empty, "896,60,1164,82", 12, kPvSoft, empty

   -- The stage: a frame, the dark desk, the drawn part of the page on it,
   -- then what lies over the page (made after the image, so it sits in
   -- front): the marks, the showcase's pointer, the scroll bars, the tag
   -- that says how the page was drawn, a scene's title, and the hint shown
   -- with no page. The marks are a fixed set made once and moved, never
   -- made and deleted per page.
   pvGfx "ui:frame", "8,90,784,592", kPvPanel, 10
   pvGfx "ui:desk", kPvViewL & comma & kPvViewT & comma & (kPvViewR + 16) & comma & (kPvViewB + 16), kPvStage, 0
   if there is no image "view:page" then
      create image
      set the name of the last image to "view:page"
   end if
   set the rect of image "view:page" to "100,100,110,110"
   set the blendLevel of image "view:page" to 0
   set the visible of image "view:page" to false
   repeat with tN = 1 to kPvHits
      pvMark "view:hl" & tN, "255,214,10", 55, 0
   end repeat
   pvMark "view:cur", "255,120,0", 45, 2
   repeat with tN = 1 to kPvLinkMax
      pvMark "view:ln" & tN, "90,150,255", 78, 1
   end repeat
   pvMark "view:char", "44,90,160", 60, 1
   pvMark "view:sel", "44,90,160", 82, 1
   pvGfx "view:ptr", "0,0,26,26", kPvAccent, 0
   set the style of graphic "view:ptr" to "oval"
   set the lineSize of graphic "view:ptr" to 2
   set the foregroundColor of graphic "view:ptr" to kPvInk
   set the blendLevel of graphic "view:ptr" to 20
   set the visible of graphic "view:ptr" to false
   pvBar "view:vs", kPvViewR & comma & kPvViewT & comma & (kPvViewR + 16) & comma & kPvViewB
   pvBar "view:hs", kPvViewL & comma & kPvViewB & comma & kPvViewR & comma & (kPvViewB + 16)
   pvLabel "view:hud", empty, "24,104,300,125", 11, kPvInk, "bold"
   pvTag "view:hud", 15
   pvLabel "view:title", empty, "188,508,588,550", 18, kPvInk, "bold"
   set the textAlign of field "view:title" to "center"
   pvTag "view:title", 8
   pvText "view:hint", "Open a PDF, or click The sample: a five-page guide this window carries.", "104,290,672,390", 14, kPvSoft
   set the textAlign of field "view:hint" to "center"

   -- The password bar, over the top of the stage while a document waits
   -- for its password (no page is shown then).
   pvGfx "lock:bg", kPvLockBg, kPvPanel, 8
   set the lineSize of graphic "lock:bg" to 1
   set the foregroundColor of graphic "lock:bg" to kPvAccent
   pvLabel "lock:msg", empty, kPvLockMsg, 12, kPvInk, empty
   pvInput "lock:pw", kPvLockPw
   pvButton "lock:go", "Unlock", kPvLockGo
   pvShowLock false, false

   -- The showcase: a button a scene (two rows of three, the last one plays
   -- them all), what the scene shows, and how far it has gone.
   pvLabel "show:h", "SHOWCASE", "794,86,1164,105", 11, kPvAccent, "bold"
   repeat with tIndex = 1 to kPvScenes + 1
      put kPvSideL + ((tIndex - 1) mod 3) * 125 into tLeft
      put 108 + ((tIndex - 1) div 3) * 30 into tTop
      if tIndex > kPvScenes then
         pvButton "show:all", "Play them all", tLeft & comma & tTop & comma & kPvSideR & comma & (tTop + 26)
      else
         pvButton "show:" & tIndex, tIndex & "." && item tIndex of kPvSceneNames, \
               tLeft & comma & tTop & comma & min(kPvSideR, tLeft + 120) & comma & (tTop + 26)
      end if
   end repeat
   repeat with tIndex = 1 to kPvScenes
      set the autoHilite of button ("show:" & tIndex) to false
   end repeat
   set the autoHilite of button "show:all" to false
   pvLabel "show:wh", "WHAT THIS SHOWS", "794,168,1164,187", 11, kPvAccent, "bold"
   pvText "show:about", pvSceneAbout(0), "794,188,1164,262", 12, kPvInk
   pvGfx "show:track", kPvSideL & comma & kPvBarT & comma & kPvSideR & comma & (kPvBarT + 4), kPvButton, 0
   pvGfx "show:fill", kPvSideL & comma & kPvBarT & comma & (kPvSideL + 1) & comma & (kPvBarT + 4), kPvAccent, 0
   set the visible of graphic "show:fill" to false

   -- The viewer's tabs: one row of seven, each lit while it is shown.
   put 0 into tIndex
   repeat for each item tKey in kPvTabs
      add 1 to tIndex
      put kPvSideL + (tIndex - 1) * 53 into tLeft
      pvButton "side:" & tKey, item tIndex of kPvTabLabels, tLeft & comma & "276," & (tLeft + 49) & ",300"
      set the textSize of button ("side:" & tKey) to 11
      set the autoHilite of button ("side:" & tKey) to false
   end repeat
   pvBuildOutline
   pvBuildFind
   pvBuildText
   pvBuildLinks
   pvBuildDraw
   pvBuildInfo
   pvBuildChecks

   -- The status line, and the honesty footer every demo carries.
   pvLabel "ui:status", empty, "16,592,1164,612", 12, kPvSoft, empty
   pvLabel "ui:footer", "PDFium (BSD 3-clause, Apache 2.0) draws every page through the pdfxt shim. Driven on" \
         && "OXT-Beyond's Linux engine, every check green (tests/demo-drive); the tour has played on Windows;" \
         && "macOS needs an OXT pass.", "16,612,1164,629", 10, kPvSoft, "italic"
   unlock messages
   set the uPvUiVersion of this stack to kPvUiVersion
   unlock screen
end pvBuildUI

-- The rebuild's clear pass: a generated control's short name carries a
-- ":", so the colon IS the ownership tag. A stack saved by the kit-look
-- version of this demo also has the kit's own chrome, which had none.
private command pvClearUI
   local tI, tOld
   lock screen
   lock messages
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
   repeat with tI = the number of images of this card down to 1
      if the short name of image tI of this card contains ":" then
         delete image tI of this card
      end if
   end repeat
   repeat with tI = the number of scrollbars of this card down to 1
      if the short name of scrollbar tI of this card contains ":" then
         delete scrollbar tI of this card
      end if
   end repeat
   repeat for each item tOld in "uiTitle,uiStatus,uiFooter"
      if there is a field tOld then
         delete field tOld
      end if
   end repeat
   if there is a graphic "uiBand" then
      delete graphic "uiBand"
   end if
   unlock messages
   unlock screen
end pvClearUI

-- ==========================================================================
-- The look's builders. Each makes its control if it is missing, then says
-- every colour it draws with (see THE LOOK at the top). A line of text is
-- given a height, half again its size: left to the font, a line is as tall
-- as the system that BUILT the stack wanted, and on Windows the tops of the
-- capitals were cut off (the Render3D Tour, 2026-11-21).
-- ==========================================================================

private command pvField pName, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the threeD of field pName to false
   set the showBorder of field pName to false
   set the borderWidth of field pName to 0
   set the vScrollbar of field pName to false
   set the hScrollbar of field pName to false
   set the textSize of field pName to pSize
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to round(pSize * 1.5)
   set the foregroundColor of field pName to kPvInk
   set the backgroundColor of field pName to kPvWell
   set the hiliteColor of field pName to pvChosenColor()
   set the borderColor of field pName to kPvLine
   -- a field's scroll bar is drawn with these, white when they are left to
   -- the system (OXT-Beyond's Linux engine, 2026-11-21)
   set the shadowColor of field pName to kPvLine
   set the topColor of field pName to kPvLine
   set the bottomColor of field pName to kPvLine
end pvField

-- The ground of a chosen line or of chosen words. Off a Mac the engine draws
-- chosen words in the field's ground colour, dark here, so the ground they
-- sit on must be light (the accent); on a Mac they keep the text colour,
-- light, so it must be dark.
function pvChosenColor
   if the platform is "MacOS" then
      return kPvSelect
   end if
   return kPvAccent
end pvChosenColor

-- Words nobody types into, on one line (pvLabel) or wrapped (pvText).
private command pvLabel pName, pText, pRect, pSize, pColor, pStyle
   pvField pName, pRect, pSize
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the dontWrap of field pName to true
   -- 4-item margins only: OXT ignored the single-number form on an engine
   -- pass (the suite kit's note). The top one centres the line in the
   -- field: kPvLift brings it down to the field's top edge, and half of the
   -- room the field has beyond the line's height brings it to the middle.
   set the margins of field pName to "2," & pvTopMargin(pName, 0) & ",2,1"
   set the foregroundColor of field pName to pColor
   if pStyle is empty then
      put "plain" into pStyle
   end if
   set the textStyle of field pName to pStyle
   put pText into field pName
end pvLabel

private command pvText pName, pText, pRect, pSize, pColor
   pvLabel pName, pText, pRect, pSize, pColor, empty
   set the dontWrap of field pName to false
   -- wrapped words start at the top, a pixel in
   set the margins of field pName to "2," & (kPvLift + 1) & ",2,1"
end pvText

-- The top margin that centres one line of field pName in it, the field's
-- border (pBorder pixels) left out: kPvLift, then half the room left over.
function pvTopMargin pName, pBorder
   return kPvLift + max(1, (the height of field pName - 2 * pBorder - the textHeight of field pName) div 2)
end pvTopMargin

-- A label with a ground of its own, part see-through: a tag over the page.
private command pvTag pName, pBlend
   set the opaque of field pName to true
   set the backgroundColor of field pName to kPvPage
   set the margins of field pName to "8," & pvTopMargin(pName, 0) & ",8,2"
   set the blendLevel of field pName to pBlend
   set the visible of field pName to false
end pvTag

-- A field to type into: dark, outlined, the platform's mono face.
private command pvInput pName, pRect
   pvField pName, pRect, 12
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the opaque of field pName to true
   set the dontWrap of field pName to true
   set the showBorder of field pName to true
   set the borderWidth of field pName to 1
   set the margins of field pName to "6," & pvTopMargin(pName, 1) & ",6,3"
   set the textFont of field pName to pvMonoFont()
end pvInput

-- Words to read and scroll: dark, outlined, mono.
private command pvArea pName, pRect
   pvField pName, pRect, 11
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to true
   set the dontWrap of field pName to false
   set the showBorder of field pName to true
   set the borderWidth of field pName to 1
   -- the first line two pixels inside the border (kPvLift brings it there)
   set the margins of field pName to "6," & (kPvLift + 2) & ",6,4"
   set the vScrollbar of field pName to true
   set the textFont of field pName to pvMonoFont()
end pvArea

-- A list to click a line of; pTabStops lines up its columns.
private command pvList pName, pRect, pTabStops
   pvArea pName, pRect
   set the listBehavior of field pName to true
   set the dontWrap of field pName to true
   set the tabStops of field pName to pTabStops
end pvList

-- A button: rounded and dark, its words light, lit (the accent) while it is
-- pressed. A tab, a scene and a switch are lit by the script instead.
private command pvButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
   set the style of button pName to "roundrect"
   set the opaque of button pName to true
   set the showBorder of button pName to false
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the hiliteBorder of button pName to false
   set the traversalOn of button pName to false
   set the textSize of button pName to 12
   set the textStyle of button pName to "plain"
   set the backgroundColor of button pName to kPvButton
   set the foregroundColor of button pName to kPvInk
   set the hiliteColor of button pName to kPvAccent
   set the borderColor of button pName to kPvLine
   set the autoHilite of button pName to true
   set the hilite of button pName to false
end pvButton

-- A switch, lit while it is on. Never a tick box: the system draws a tick
-- box's words in its own theme's colours, and under a dark theme they came
-- out white on white (the suite's physics demo on Windows, 2026-11-20).
private command pvToggle pName, pLabel, pRect, pOn
   pvButton pName, pLabel, pRect
   set the autoHilite of button pName to false
   set the hilite of button pName to pOn
end pvToggle

-- A filled shape: a rectangle, or rounded by pRadius.
private command pvGfx pName, pRect, pColor, pRadius
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   if pRadius > 0 then
      set the style of graphic pName to "roundrect"
      set the roundRadius of graphic pName to pRadius
   else
      set the style of graphic pName to "rectangle"
   end if
   set the antialiased of graphic pName to true
   set the filled of graphic pName to true
   set the lineSize of graphic pName to 0
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
end pvGfx

-- One mark of the page view: a rectangle, see-through by pBlend percent.
private command pvMark pName, pColor, pBlend, pLine
   pvGfx pName, "20,100,24,104", pColor, 0
   set the lineSize of graphic pName to pLine
   set the blendLevel of graphic pName to pBlend
   set the visible of graphic pName to false
end pvMark

-- A scroll bar; it lies down or stands up by the shape of its rect.
private command pvBar pName, pRect
   if there is no scrollbar pName then
      create scrollbar
      set the name of the last scrollbar to pName
   end if
   set the rect of scrollbar pName to pRect
   -- every colour it is drawn with, flat: left to the system its thumb and
   -- arrows are white (OXT-Beyond's Linux engine, 2026-11-21)
   set the threeD of scrollbar pName to false
   set the backgroundColor of scrollbar pName to kPvWell
   set the foregroundColor of scrollbar pName to kPvButton
   set the hiliteColor of scrollbar pName to kPvButton
   set the borderColor of scrollbar pName to kPvLine
   set the shadowColor of scrollbar pName to kPvLine
   set the topColor of scrollbar pName to kPvLine
   set the bottomColor of scrollbar pName to kPvLine
   set the visible of scrollbar pName to false
end pvBar

-- The platform's own terminal face for text, lists and logs. A missing face
-- falls back to the engine's default.
function pvMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end pvMonoFont

-- The status line, coloured by what it says: "ok", "warn", "bad", or
-- anything else for a plain remark. The stack is pinned first, since a
-- scene's frame arrives by timer (engine note 5.3).
command pvSay pText, pKind
   set the defaultStack to the short name of this stack
   if there is no field "ui:status" then
      exit pvSay
   end if
   put pText into field "ui:status"
   if pKind is "ok" then
      set the foregroundColor of field "ui:status" to kPvOk
   else if pKind is "warn" then
      set the foregroundColor of field "ui:status" to kPvWarn
   else if pKind is "bad" then
      set the foregroundColor of field "ui:status" to kPvBad
   else
      set the foregroundColor of field "ui:status" to kPvSoft
   end if
end pvSay

on pvBuildOutline
   pvLabel "out:h", empty, "794,308,1164,327", 11, kPvInk, "bold"
   pvList "out:list", "794,330,1164,556", "290"
   pvText "out:note", "pdfOutline: a level, a page and a title for each entry. Click one to go there.", "794,560,1164,592", 10, kPvSoft
end pvBuildOutline

on pvBuildFind
   pvInput "find:text", "794,308,1060,334"
   pvButton "find:go", "Find", "1066,308,1164,334"
   pvToggle "find:case", "Capitals must match", "794,340,976,364", false
   pvToggle "find:words", "Whole words", "982,340,1164,364", false
   pvLabel "find:sum", empty, "794,368,1164,387", 11, kPvInk, empty
   pvList "find:list", "794,390,1164,556", "52"
   pvButton "find:prev", "Previous", "794,562,890,588"
   pvButton "find:next", "Next", "896,562,992,588"
end pvBuildFind

on pvBuildText
   pvLabel "txt:h", empty, "794,308,1164,327", 11, kPvInk, "bold"
   pvArea "txt:page", "794,330,1164,446"
   pvLabel "txt:hs", empty, "794,450,1164,469", 11, kPvInk, "bold"
   pvArea "txt:sel", "794,472,1164,556"
   pvButton "txt:copy", "Copy", "794,562,890,588"
end pvBuildText

on pvBuildLinks
   pvToggle "lnk:show", "Outline every link on the page", "794,308,1164,332", true
   pvLabel "lnk:h", empty, "794,338,1164,357", 11, kPvInk, "bold"
   pvList "lnk:list", "794,360,1164,446", empty
   pvArea "lnk:addr", "794,452,1164,494"
   pvButton "lnk:open", "Open it in the browser", "794,500,984,526"
   pvText "lnk:note", "A link inside the document is followed when you click it. A web link's address" \
         && "was written by whoever made the file, so it is shown here first and opened only if you ask.", \
         "794,532,1164,592", 10, kPvSoft
end pvBuildLinks

on pvBuildDraw
   pvLabel "draw:h", "Drawing flags (pFlags of every pdfRender call)", "794,308,1164,327", 11, kPvInk, "bold"
   pvToggle "draw:annots", "Annotations and forms (1)", "794,331,1036,353", false
   pvToggle "draw:lcd", "Text for an LCD screen (2)", "794,357,1036,379", false
   pvToggle "draw:gray", "Gray (8)", "794,383,1036,405", false
   pvToggle "draw:print", "As for print (2048)", "794,409,1036,431", false
   pvToggle "draw:smooth", "No smoothing (28672)", "794,435,1036,457", false
   if there is no image "draw:thumb" then
      create image
      set the name of the last image to "draw:thumb"
   end if
   set the rect of image "draw:thumb" to kPvThumbAt & comma & (item 1 of kPvThumbAt + 100) & comma & (item 2 of kPvThumbAt + 100)
   pvLabel "draw:th", "pdfRenderPageBMP", "1044,435,1164,454", 10, kPvSoft, empty
   set the textAlign of field "draw:th" to "center"
   pvLabel "draw:lh", "The last drawing of the page", "794,462,1164,481", 11, kPvInk, "bold"
   -- three lines, the longest a drawing's description runs to: no scroll bar
   pvArea "draw:last", "794,484,1164,540"
   set the vScrollbar of field "draw:last" to false
   pvButton "draw:save", "Save this page as a BMP...", "794,544,1010,570"
   pvText "draw:note", "Saved at two pixels to the point (144 dots to the inch), with the flags above.", "794,572,1164,592", 10, kPvSoft
end pvBuildDraw

on pvBuildInfo
   pvArea "info:area", "794,308,1164,590"
   set the tabStops of field "info:area" to "92"
end pvBuildInfo

on pvBuildChecks
   pvButton "chk:run", "Run every check", "794,308,946,334"
   pvLabel "chk:sum", "Not run yet.", "952,311,1164,331", 11, kPvInk, empty
   pvText "chk:note", "Every public pdf handler, over the two PDFs this window carries. They end by closing" \
         && "every document and shutting PDFium down (pdfCloseAll, pdfShutdown); the document shown here" \
         && "is opened again after.", "794,338,1164,386", 10, kPvSoft
   pvArea "chk:log", "794,390,1164,590"
end pvBuildChecks

-- ==========================================================================
-- The side panel's tabs.
-- ==========================================================================

on pvShowTab pKey
   local tI, tName, tKey
   put pKey into sTab
   lock screen
   repeat with tI = 1 to the number of controls of this card
      put the short name of control tI of this card into tName
      if tName contains ":" then
         set the itemDelimiter to ":"
         put item 1 of tName into tKey
         set the itemDelimiter to comma
         if tKey is among the items of kPvTabs then
            set the visible of control tI of this card to (tKey is pKey)
         end if
      end if
   end repeat
   repeat for each item tKey in kPvTabs
      set the hilite of button ("side:" & tKey) to (tKey is pKey)
      if tKey is pKey then
         set the textStyle of button ("side:" & tKey) to "bold"
      else
         set the textStyle of button ("side:" & tKey) to "plain"
      end if
   end repeat
   -- the BMP picture is of the page shown, so with none it stays hidden
   if pKey is "draw" and sDoc is 0 then
      set the visible of image "draw:thumb" to false
   end if
   unlock screen
end pvShowTab


-- ==========================================================================
-- Messages: clicks, keys, the wheel, the scroll bars and a drag on the page.
-- A control's short name is "prefix:role".
-- ==========================================================================

on mouseUp pButton
   local tName, tPrefix, tRole
   if sDragging is true then
      pvEndDrag
      exit mouseUp
   end if
   put the short name of the target into tName
   if tName contains ":" then
      set the itemDelimiter to ":"
      put item 1 of tName into tPrefix
      put item 2 of tName into tRole
      set the itemDelimiter to comma
      if tPrefix is "show" then
         if tRole is "all" then
            pvPlay 1, true
         else if tRole is an integer then
            pvPlay tRole, false
         end if
         exit mouseUp
      end if
      -- Anything else is the person taking the window back from the tour.
      pvStopShow
      -- nested, not joined with `and`: the target's name is only asked of a
      -- button (engine note 2.5)
      if word 1 of the target is "button" then
         if tName is among the items of kPvToggles then
            set the hilite of the target to not the hilite of the target
            pvTicked tName
            exit mouseUp
         end if
      end if
      if tPrefix is "side" then
         if tRole is among the items of kPvTabs then
            pvShowTab tRole
         end if
      else if tPrefix is "tb" then
         pvToolbar tRole
      else if tName is "lock:go" then
         pvUnlock
      else if tName is "out:list" then
         pvOutlineClick
      else if tName is "find:go" then
         pvFind
      else if tName is "find:list" then
         pvFindShow the hilitedLine of field "find:list"
      else if tName is "find:prev" then
         pvFindStep -1
      else if tName is "find:next" then
         pvFindStep 1
      else if tName is "lnk:list" then
         pvLinkClick
      else if tName is "lnk:open" then
         pvOpenAddress
      else if tName is "txt:copy" then
         pvCopy
      else if tName is "draw:save" then
         pvAskSave
      else if tName is "chk:run" then
         pvRunChecks
      end if
   else
      pass mouseUp
   end if
end mouseUp

-- A press on the drawn page starts a click or a drag; anywhere else is the
-- engine's (a button's highlight, a field's caret). A press anywhere but on
-- a scene's button stops the tour where it is: the window is the person's.
on mouseDown pButton
   if not (the short name of the target begins with "show:") then
      pvStopShow
   end if
   if pvOnPage() then
      put true into sDragging
      put the mouseH into sDragH
      put the mouseV into sDragV
   else
      pass mouseDown
   end if
end mouseDown

on mouseMove pX, pY
   if sDragging is true then
      pvDragBox pX, pY
   end if
   pass mouseMove
end mouseMove

-- Released outside the control that was pressed: the same end of a drag.
on mouseRelease pButton
   if sDragging is true then
      pvEndDrag
   else
      pass mouseRelease
   end if
end mouseRelease

-- A key typed anywhere is the person too.
on keyDown pKey
   pvStopShow
   pass keyDown
end keyDown

on returnInField
   if pvEntered() is false then
      pass returnInField
   end if
end returnInField

on enterInField
   if pvEntered() is false then
      pass enterInField
   end if
end enterInField

-- Return in one of the three entry fields acts, and answers true; in any
-- other field it is the field's own return.
private function pvEntered
   local tName
   put the short name of the target into tName
   if tName is "tb:page" then
      pvGoTyped field "tb:page"
   else if tName is "find:text" then
      pvFind
   else if tName is "lock:pw" then
      pvUnlock
   else
      return false
   end if
   return true
end pvEntered

-- Left and right turn the page and up and down scroll it, unless the caret
-- is in a field, where the arrows are the field's.
on arrowKey pWhich
   pvStopShow
   if word 1 of the focusedObject is "field" then
      pass arrowKey
   end if
   if sDoc is 0 then
      pass arrowKey
   end if
   switch pWhich
      case "left"
         pvGo sPage - 1
         break
      case "right"
         pvGo sPage + 1
         break
      case "up"
         subtract 48 from sScrollY
         pvRender
         break
      case "down"
         add 48 to sScrollY
         pvRender
         break
      default
         pass arrowKey
   end switch
end arrowKey

-- The wheel arrives as rawKeyDown 65308 (down) and 65309 (up); over the page
-- it scrolls the page, anywhere else it is passed on to scroll a list.
on rawKeyDown pCode
   pvStopShow
   if pvOnPage() and (pCode is 65308 or pCode is 65309) then
      if pCode is 65308 then
         add 48 to sScrollY
      else
         subtract 48 from sScrollY
      end if
      pvRender
   else
      pass rawKeyDown
   end if
end rawKeyDown

on scrollbarDrag pPosition
   local tName
   pvStopShow
   put the short name of the target into tName
   if tName is "view:hs" then
      put round(pPosition) into sScrollX
      pvRender
   else if tName is "view:vs" then
      put round(pPosition) into sScrollY
      pvRender
   else
      pass scrollbarDrag
   end if
end scrollbarDrag

command pvToolbar pRole
   switch pRole
      case "open"
         pvAskOpen
         break
      case "sample"
         pvOpenSample "sample"
         break
      case "locked"
         pvOpenSample "locked"
         break
      case "close"
         pvCloseDocument
         pvShowDocument
         pvSay "Closed. Open a PDF, or click The sample.", "muted"
         break
      case "prev"
         pvGo sPage - 1
         break
      case "next"
         pvGo sPage + 1
         break
      case "in"
         pvZoom "in"
         break
      case "out"
         pvZoom "out"
         break
      case "fitp"
         pvZoom "page"
         break
      case "fitw"
         pvZoom "width"
         break
   end switch
end pvToolbar

command pvTicked pName
   if pName begins with "draw:" then
      pvReadFlags
      pvRender
      pvFillDraw
   else if pName is "lnk:show" then
      pvPaintMarks
   else if pName begins with "find:" then
      -- a search already made is made again with the new flags
      if sNeedle is not empty and sDoc > 0 then
         pvFind
      end if
   end if
end pvTicked

-- ==========================================================================
-- Opening and closing.
-- ==========================================================================

-- Says whether pdfxt and its PDFium are here, and paints the status line
-- red when they are not.
function pvReady
   local tError, tVersion
   try
      put pdfLibraryVersion() into tVersion
   catch tError
      pvSay "pdfxt is NOT loaded: install org.openxtalk.library.pdfxt and reopen this stack.", "bad"
      return false
   end try
   if pdfLoad(empty) is false then
      pvSay "pdfxt is loaded, but its PDFium is not: " & pdfLastError(), "bad"
      return false
   end if
   return true
end pvReady

command pvAskOpen
   local tPath
   if pvReady() is false then
      exit pvAskOpen
   end if
   answer file "Open a PDF" with type "PDF documents|pdf"
   put it into tPath
   if tPath is empty then
      exit pvAskOpen
   end if
   pvOpen tPath, empty
end pvAskOpen

-- pWhich: "sample" (the guide) or "locked" (the locked page).
command pvOpenSample pWhich
   if pvReady() is false then
      exit pvOpenSample
   end if
   pvOpen pWhich, empty
end pvOpenSample

-- Opens a document and shows its first page. pSource is "sample" or
-- "locked" (bytes this script carries, through pdfOpenData) or a file's
-- path (pdfOpen); pPassword is empty or its password. A document that
-- needs a password brings up the password bar instead.
command pvOpen pSource, pPassword
   local tDoc
   set the defaultStack to the short name of this stack
   pvCloseDocument
   if pSource is "sample" or pSource is "locked" then
      put pdfOpenData(base64Decode(pvSampleBase64(pSource)), pPassword) into tDoc
   else
      put pdfOpen(pSource, pPassword) into tDoc
   end if
   if tDoc is 0 then
      if pdfLastError() contains "password" then
         put pSource into sWaiting
         pvShowLock true, (pPassword is not empty)
         if pPassword is empty then
            pvSay "A password opens" && pvSourceName(pSource) & ": type it in the bar over the page.", "warn"
         else
            pvSay "That password did not open " & pvSourceName(pSource) & ".", "warn"
         end if
      else
         pvShowLock false, false
         pvSay "Could not open " & pvSourceName(pSource) & ": " & pdfLastError(), "bad"
      end if
      pvShowDocument
      exit pvOpen
   end if
   pvShowLock false, false
   put empty into sWaiting
   put tDoc into sDoc
   put pSource into sSource
   put pPassword into sPassword
   put pdfPageCount(tDoc) into sPages
   put 1 into sPage
   put "page" into sFit
   put 0 into sScrollX
   put 0 into sScrollY
   pvFillOutline
   put empty into field "find:list"
   put empty into field "find:sum"
   pvShowDocument
   pvSay "Opened " & pvSourceName(pSource) & ": " & sPages & " page(s), PDF " & (pdfFileVersion(tDoc) / 10) & ".", "ok"
end pvOpen

command pvUnlock
   if sWaiting is empty then
      exit pvUnlock
   end if
   pvOpen sWaiting, field "lock:pw"
end pvUnlock

command pvShowLock pOn, pWrong
   lock screen
   set the visible of graphic "lock:bg" to pOn
   set the visible of field "lock:msg" to pOn
   set the visible of field "lock:pw" to pOn
   set the visible of button "lock:go" to pOn
   if pOn then
      set the foregroundColor of field "lock:msg" to kPvInk
      if pWrong then
         put "That password did not open it. Try again:" into field "lock:msg"
         set the foregroundColor of field "lock:msg" to kPvWarn
      else if sWaiting is "locked" then
         put "Locked. Its password (the sample's is secret):" into field "lock:msg"
      else
         put "This PDF is locked. Type its password:" into field "lock:msg"
      end if
      put empty into field "lock:pw"
   end if
   unlock screen
end pvShowLock

command pvCloseDocument
   if sDoc > 0 then
      pdfClose sDoc
   end if
   put 0 into sDoc
   put empty into sSource
   put empty into sPassword
   put 0 into sPages
   put 0 into sPage
   put empty into sOutline
   put empty into sNeedle
   put empty into sFinds
   put 0 into sFindAt
   put empty into sHitRects
   put empty into sCurRects
   put empty into sLinks
   put empty into sSel
   put empty into sCharRect
   put empty into sAddress
end pvCloseDocument

function pvSourceName pSource
   if pSource is "sample" then
      return "the sample"
   else if pSource is "locked" then
      return "the locked sample"
   end if
   set the itemDelimiter to "/"
   return the last item of pSource
end pvSourceName

-- ==========================================================================
-- Pages: which one, at what zoom, and drawing the part in view.
-- ==========================================================================

command pvGo pPage
   set the defaultStack to the short name of this stack
   if sDoc is 0 or pPage is not an integer then
      exit pvGo
   end if
   put max(1, min(sPages, pPage)) into pPage
   if pPage is not sPage then
      put pPage into sPage
      put 0 into sScrollX
      put 0 into sScrollY
      put empty into sSel
      put empty into sCharRect
   end if
   pvShowDocument
end pvGo

-- What was typed in the page box: a page number, or a page's label (a
-- preface's "iv"), found with pdfPageLabel.
command pvGoTyped pText
   local tPage
   if sDoc is 0 then
      exit pvGoTyped
   end if
   if pText is an integer then
      pvGo pText
      exit pvGoTyped
   end if
   repeat with tPage = 1 to min(sPages, 5000)
      if pdfPageLabel(sDoc, tPage) is pText then
         pvGo tPage
         exit pvGoTyped
      end if
   end repeat
   pvSay "No page is numbered or labelled " & quote & pText & quote & ".", "warn"
   put sPage into field "tb:page"
end pvGoTyped

-- pHow: "in" or "out" (the next step of kPvZooms), "page" or "width" (fit
-- the view), or a percent.
command pvZoom pHow
   local tPct, tStep, tNew, tCX, tCY, tViewW, tViewH
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      exit pvZoom
   end if
   if pHow is "page" or pHow is "width" then
      put pHow into sFit
      pvRender
      exit pvZoom
   end if
   put round(sZoom * 100) into tPct
   put empty into tNew
   if pHow is "in" then
      repeat for each item tStep in kPvZooms
         if tStep > tPct then
            put tStep into tNew
            exit repeat
         end if
      end repeat
      if tNew is empty then
         put the last item of kPvZooms into tNew
      end if
   else if pHow is "out" then
      repeat for each item tStep in kPvZooms
         if tStep < tPct then
            put tStep into tNew
         end if
      end repeat
      if tNew is empty then
         put item 1 of kPvZooms into tNew
      end if
   else if pHow is a number then
      put max(item 1 of kPvZooms, min(the last item of kPvZooms, pHow)) into tNew
   else
      exit pvZoom
   end if
   -- keep the point at the middle of the view where it is
   put kPvViewR - kPvViewL into tViewW
   put kPvViewB - kPvViewT into tViewH
   put (sScrollX + min(tViewW, sZoomW) / 2) / sZoom into tCX
   put (sScrollY + min(tViewH, sZoomH) / 2) / sZoom into tCY
   put tNew / 100 into sZoom
   put empty into sFit
   put round(tCX * sZoom - tViewW / 2) into sScrollX
   put round(tCY * sZoom - tViewH / 2) into sScrollY
   pvRender
end pvZoom

-- Draws what the view shows. A page that fits is drawn whole with
-- pdfRenderPage; a page larger than the view is drawn with
-- pdfRenderPageRegion, which is told how large the whole page would be and
-- draws only the window of it in view: memory and time follow the window,
-- not the zoom.
command pvRender
   local tW, tH, tViewW, tViewH, tIW, tIH, tData, tStart, tCall, tHud
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      lock screen
      set the visible of image "view:page" to false
      set the visible of scrollbar "view:hs" to false
      set the visible of scrollbar "view:vs" to false
      set the visible of field "view:hint" to (sWaiting is empty)
      put empty into field "tb:zoom"
      put empty into sLastDraw
      pvHud empty
      pvPaintMarks
      unlock screen
      exit pvRender
   end if
   put kPvViewR - kPvViewL into tViewW
   put kPvViewB - kPvViewT into tViewH
   put pdfPageWidth(sDoc, sPage) into tW
   put pdfPageHeight(sDoc, sPage) into tH
   if tW <= 0 or tH <= 0 then
      pvSay "Page " & sPage & " has no size: " & pdfLastError(), "bad"
      exit pvRender
   end if
   if sFit is "page" then
      put min((tViewW - 24) / tW, (tViewH - 24) / tH) into sZoom
   else if sFit is "width" then
      put (tViewW - 24) / tW into sZoom
   end if
   put max(1, round(tW * sZoom)) into sZoomW
   put max(1, round(tH * sZoom)) into sZoomH
   put min(sZoomW, tViewW) into tIW
   put min(sZoomH, tViewH) into tIH
   put max(0, min(sScrollX, sZoomW - tIW)) into sScrollX
   put max(0, min(sScrollY, sZoomH - tIH)) into sScrollY
   put the milliseconds into tStart
   if tIW is sZoomW and tIH is sZoomH then
      put pdfRenderPage(sDoc, sPage, tIW, tIH, sFlags) into tData
      put "pdfRenderPage: the whole page," && tIW && "x" && tIH && "pixels" into tCall
      put "the whole page," && tIW && "x" && tIH into tHud
   else
      put pdfRenderPageRegion(sDoc, sPage, sZoomW, sZoomH, sScrollX, sScrollY, tIW, tIH, sFlags) into tData
      put "pdfRenderPageRegion: a window of" && tIW && "x" && tIH && "pixels at" && sScrollX & comma & sScrollY \
            && "of the" && sZoomW && "x" && sZoomH && "page" into tCall
      put "a" && tIW && "x" && tIH && "window of a" && sZoomW && "x" && sZoomH && "page" into tHud
   end if
   put the milliseconds - tStart into tStart
   if tData is empty then
      set the visible of image "view:page" to false
      pvSay "Page " & sPage & " could not be drawn: " & pdfLastError(), "bad"
      exit pvRender
   end if
   put tCall & ", at" && round(sZoom * 100) & "%, in" && tStart && "ms" into sLastDraw
   -- the drawn part is centred on an axis the page does not fill
   put kPvViewL + (tViewW - tIW) div 2 into sImgL
   put kPvViewT + (tViewH - tIH) div 2 into sImgT
   put tIW into sImgW
   put tIH into sImgH
   lock screen
   -- size first, then the pixels: imageData must be width x height x 4
   set the width of image "view:page" to tIW
   set the height of image "view:page" to tIH
   set the topLeft of image "view:page" to sImgL & comma & sImgT
   set the imageData of image "view:page" to tData
   set the visible of image "view:page" to true
   set the visible of field "view:hint" to false
   put round(sZoom * 100) & "%" into field "tb:zoom"
   put sLastDraw into field "draw:last"
   pvHud round(sZoom * 100) & "%   " & tHud & "   " & tStart && "ms"
   pvSyncBars
   pvPaintMarks
   unlock screen
end pvRender

-- The tag on the stage's corner: how the page shown was drawn, and how
-- long that took. Empty hides it.
private command pvHud pText
   if pText is empty then
      set the visible of field "view:hud" to false
      exit pvHud
   end if
   put pText into field "view:hud"
   set the width of field "view:hud" to the formattedWidth of field "view:hud" + 4
   set the left of field "view:hud" to kPvViewL + 8
   set the visible of field "view:hud" to true
end pvHud

-- The scroll bars follow the view. Their properties are set with messages
-- locked, so setting a thumb does not come back as a scrollbarDrag.
private command pvSyncBars
   lock messages
   if sZoomW > sImgW then
      set the startValue of scrollbar "view:hs" to 0
      set the endValue of scrollbar "view:hs" to sZoomW
      set the thumbSize of scrollbar "view:hs" to sImgW
      set the lineIncrement of scrollbar "view:hs" to 40
      set the pageIncrement of scrollbar "view:hs" to max(40, sImgW - 40)
      set the thumbPosition of scrollbar "view:hs" to sScrollX
      set the visible of scrollbar "view:hs" to true
   else
      set the visible of scrollbar "view:hs" to false
   end if
   if sZoomH > sImgH then
      set the startValue of scrollbar "view:vs" to 0
      set the endValue of scrollbar "view:vs" to sZoomH
      set the thumbSize of scrollbar "view:vs" to sImgH
      set the lineIncrement of scrollbar "view:vs" to 40
      set the pageIncrement of scrollbar "view:vs" to max(40, sImgH - 40)
      set the thumbPosition of scrollbar "view:vs" to sScrollY
      set the visible of scrollbar "view:vs" to true
   else
      set the visible of scrollbar "view:vs" to false
   end if
   unlock messages
end pvSyncBars

-- A point of the card, as points of the page shown.
function pvPageX pH
   return (pH - sImgL + sScrollX) / sZoom
end pvPageX

function pvPageY pV
   return (pV - sImgT + sScrollY) / sZoom
end pvPageY

function pvOnPage
   if sDoc is 0 then
      return false
   end if
   if the visible of image "view:page" is false then
      return false
   end if
   return the mouseLoc is within the rect of image "view:page"
end pvOnPage

-- Everything about the page shown: the toolbar, its links, its matches,
-- the tabs that describe it, and the drawing.
command pvShowDocument
   local tLabel
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      put empty into field "tb:page"
      put empty into field "tb:of"
      put empty into field "tb:doc"
      put empty into sLinks
      put empty into sHitRects
      put empty into sCurRects
      pvFillOutline
   else
      put sPage into field "tb:page"
      put "of" && sPages into field "tb:of"
      put pdfPageLabel(sDoc, sPage) into tLabel
      if tLabel is empty or tLabel is sPage then
         put pvSourceName(sSource) into field "tb:doc"
      else
         put pvSourceName(sSource) & ", the page labelled" && tLabel into field "tb:doc"
      end if
      put pdfPageLinks(sDoc, sPage) into sLinks
      pvComputeHits
   end if
   pvFillLinks
   pvFillText
   pvFillInfo
   pvRender
   pvFillDraw
end pvShowDocument

-- ==========================================================================
-- The marks over the page: matches, the chosen match, links, the clicked
-- character and the dragged box, all kept in points and placed by the zoom
-- and the scroll, clipped to the drawn part.
-- ==========================================================================

command pvComputeHits
   local tLine, tRects, tN
   put empty into sHitRects
   put empty into sCurRects
   if sDoc is 0 or sFinds is empty then
      exit pvComputeHits
   end if
   put 0 into tN
   repeat for each line tLine in sFinds
      if item 1 of tLine is sPage and tN < kPvHits then
         add 1 to tN
         put pdfPageTextRects(sDoc, sPage, item 2 of tLine, item 3 of tLine) into tRects
         if tRects is not empty then
            put tRects & return after sHitRects
         end if
      end if
   end repeat
   if sFindAt > 0 then
      put line sFindAt of sFinds into tLine
      if item 1 of tLine is sPage then
         put pdfPageTextRects(sDoc, sPage, item 2 of tLine, item 3 of tLine) into sCurRects
      end if
   end if
end pvComputeHits

command pvPaintMarks
   local tN, tI, tLine, tRect
   set the defaultStack to the short name of this stack
   lock screen
   put 0 into tN
   if sDoc > 0 then
      repeat for each line tRect in sHitRects
         if tRect is not empty and tN < kPvHits then
            add 1 to tN
            pvPlace "view:hl" & tN, tRect
         end if
      end repeat
   end if
   repeat with tI = tN + 1 to kPvHits
      set the visible of graphic ("view:hl" & tI) to false
   end repeat
   if sDoc > 0 and sCurRects is not empty then
      pvPlace "view:cur", line 1 of sCurRects
   else
      set the visible of graphic "view:cur" to false
   end if
   put 0 into tN
   if sDoc > 0 and the hilite of button "lnk:show" then
      repeat for each line tLine in sLinks
         if tN < kPvLinkMax then
            add 1 to tN
            set the itemDelimiter to tab
            put item 1 of tLine into tRect
            set the itemDelimiter to comma
            pvPlace "view:ln" & tN, tRect
         end if
      end repeat
   end if
   repeat with tI = tN + 1 to kPvLinkMax
      set the visible of graphic ("view:ln" & tI) to false
   end repeat
   if sDoc > 0 and sCharRect is not empty then
      pvPlace "view:char", sCharRect
   else
      set the visible of graphic "view:char" to false
   end if
   if sDoc > 0 and sSel is not empty then
      pvPlace "view:sel", sSel
   else
      set the visible of graphic "view:sel" to false
   end if
   unlock screen
end pvPaintMarks

-- Puts a mark over a rectangle of the page given in points
-- ("left,top,right,bottom"), or hides it when none of it is in view.
command pvPlace pName, pRect
   local tL, tT, tR, tB
   if the number of items of pRect is not 4 or the visible of image "view:page" is false then
      set the visible of graphic pName to false
      exit pvPlace
   end if
   put sImgL + round(item 1 of pRect * sZoom) - sScrollX into tL
   put sImgT + round(item 2 of pRect * sZoom) - sScrollY into tT
   put sImgL + round(item 3 of pRect * sZoom) - sScrollX into tR
   put sImgT + round(item 4 of pRect * sZoom) - sScrollY into tB
   put max(tL, sImgL) into tL
   put max(tT, sImgT) into tT
   put min(tR, sImgL + sImgW) into tR
   put min(tB, sImgT + sImgH) into tB
   if tR - tL < 1 or tB - tT < 1 then
      set the visible of graphic pName to false
      exit pvPlace
   end if
   set the rect of graphic pName to tL & comma & tT & comma & tR & comma & tB
   set the visible of graphic pName to true
end pvPlace

-- While the button is down: the box from where it went down to here.
command pvDragBox pX, pY
   local tL, tT, tR, tB
   put max(sImgL, min(sDragH, pX)) into tL
   put max(sImgT, min(sDragV, pY)) into tT
   put min(sImgL + sImgW, max(sDragH, pX)) into tR
   put min(sImgT + sImgH, max(sDragV, pY)) into tB
   if tR - tL >= 1 and tB - tT >= 1 then
      set the rect of graphic "view:sel" to tL & comma & tT & comma & tR & comma & tB
      set the visible of graphic "view:sel" to true
   end if
end pvDragBox

-- The button came up: a click where it barely moved, else a box.
command pvEndDrag
   local tH, tV
   put false into sDragging
   put the mouseH into tH
   put the mouseV into tV
   if abs(tH - sDragH) < 4 and abs(tV - sDragV) < 4 then
      pvClickAt pvPageX(sDragH), pvPageY(sDragV)
   else
      pvSelectBox pvPageX(min(tH, sDragH)), pvPageY(min(tV, sDragV)), pvPageX(max(tH, sDragH)), pvPageY(max(tV, sDragV))
   end if
end pvEndDrag

-- ==========================================================================
-- Clicking the page: a link, else the character and the word there.
-- ==========================================================================

-- pX, pY: a point of the page shown, in points from its top left. A link
-- comes first, since it sits over the text it covers.
command pvClickAt pX, pY
   local tLine, tRect, tIndex, tWord
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      exit pvClickAt
   end if
   repeat for each line tLine in sLinks
      set the itemDelimiter to tab
      put item 1 of tLine into tRect
      set the itemDelimiter to comma
      if pvInRect(pX, pY, tRect) then
         pvFollow tLine
         exit pvClickAt
      end if
   end repeat
   put pdfPageCharAt(sDoc, sPage, pX, pY, 3) into tIndex
   put empty into sSel
   if tIndex is 0 then
      put empty into sCharRect
      put "Clicked at" && pvNum(pX) & comma & pvNum(pY) && "points" into field "txt:hs"
      put "No character there (pdfPageCharAt answered 0)." into field "txt:sel"
      pvSay "No text at that point of the page.", "muted"
      pvPaintMarks
      exit pvClickAt
   end if
   put pdfPageCharBox(sDoc, sPage, tIndex) into sCharRect
   put pvWordAt(tIndex) into tWord
   put "Clicked at" && pvNum(pX) & comma & pvNum(pY) && "points" into field "txt:hs"
   put "Character" && tIndex && "of" && pdfPageCharCount(sDoc, sPage) & ":" && quote & pdfPageTextRange(sDoc, sPage, tIndex, 1) & quote & return \
         & "its box (pdfPageCharBox):" && sCharRect & return & "the word it is in:" && tWord into field "txt:sel"
   pvSay "Character" && tIndex && "is in the word" && quote & tWord & quote & ": the Text tab has the rest.", "ok"
   pvPaintMarks
end pvClickAt

function pvInRect pX, pY, pRect
   if the number of items of pRect is not 4 then
      return false
   end if
   return pX >= item 1 of pRect and pX <= item 3 of pRect and pY >= item 2 of pRect and pY <= item 4 of pRect
end pvInRect

-- The word around a character, read one character at a time: a range that
-- crosses a line break comes back shorter than it counts (PDFium counts the
-- break as two characters), so positions are only safe one by one.
function pvWordAt pIndex
   local tWord, tI, tChar, tCount
   put pdfPageTextRange(sDoc, sPage, pIndex, 1) into tWord
   if not pvIsWordChar(tWord) then
      return tWord
   end if
   put pdfPageCharCount(sDoc, sPage) into tCount
   repeat with tI = pIndex - 1 down to max(1, pIndex - 40)
      put pdfPageTextRange(sDoc, sPage, tI, 1) into tChar
      if not pvIsWordChar(tChar) then
         exit repeat
      end if
      put tChar before tWord
   end repeat
   repeat with tI = pIndex + 1 to min(tCount, pIndex + 40)
      put pdfPageTextRange(sDoc, sPage, tI, 1) into tChar
      if not pvIsWordChar(tChar) then
         exit repeat
      end if
      put tChar after tWord
   end repeat
   return tWord
end pvWordAt

function pvIsWordChar pChar
   if pChar is empty or the number of chars of pChar is not 1 then
      return false
   end if
   return offset(pChar, " ,.;:!?()[]/" & quote & tab & return) is 0
end pvIsWordChar

-- A box dragged out on the page, in points: the text inside it.
command pvSelectBox pLeft, pTop, pRight, pBottom
   local tText
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      exit pvSelectBox
   end if
   put pvNum(pLeft) & comma & pvNum(pTop) & comma & pvNum(pRight) & comma & pvNum(pBottom) into sSel
   put empty into sCharRect
   put pdfPageTextInRect(sDoc, sPage, pLeft, pTop, pRight, pBottom) into tText
   put "The text in the box" && sSel && "(pdfPageTextInRect)" into field "txt:hs"
   if tText is empty then
      put "No text inside that box." into field "txt:sel"
      pvSay "No text inside that box.", "muted"
   else
      put tText into field "txt:sel"
      pvSay "Read" && the number of chars of tText && "characters from the box: the Text tab shows them.", "ok"
   end if
   pvShowTab "txt"
   pvPaintMarks
end pvSelectBox

function pvNum pNumber
   return round(pNumber, 1)
end pvNum

-- ==========================================================================
-- Links.
-- ==========================================================================

command pvFillLinks
   local tLine, tList, tPage, tAddress, tN
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      put "No document is open." into field "lnk:h"
      put empty into field "lnk:list"
      exit pvFillLinks
   end if
   put 0 into tN
   repeat for each line tLine in sLinks
      add 1 to tN
      set the itemDelimiter to tab
      put item 2 of tLine into tPage
      put item 3 of tLine into tAddress
      set the itemDelimiter to comma
      if tPage > 0 then
         put "Goes to page" && tPage & pvLabelNote(tPage) & return after tList
      else
         put "Web:" && tAddress & return after tList
      end if
   end repeat
   if tList is not empty then
      delete the last char of tList
   end if
   put tList into field "lnk:list"
   put "Links on page" && sPage & ":" && tN && "(pdfPageLinks)" into field "lnk:h"
end pvFillLinks

-- " (labelled iv)" for a page whose label is not its number.
function pvLabelNote pPage
   local tLabel
   put pdfPageLabel(sDoc, pPage) into tLabel
   if tLabel is empty or tLabel is pPage then
      return empty
   end if
   return " (labelled" && tLabel & ")"
end pvLabelNote

command pvLinkClick
   local tLine
   put the hilitedLine of field "lnk:list" into tLine
   if tLine is not an integer then
      exit pvLinkClick
   end if
   if tLine > the number of lines of sLinks then
      exit pvLinkClick
   end if
   pvFollow line tLine of sLinks
end pvLinkClick

-- pLink: one line of pdfPageLinks. A page inside the document is followed;
-- a web address is only SHOWN, since a stranger wrote it.
command pvFollow pLink
   local tPage, tAddress
   set the itemDelimiter to tab
   put item 2 of pLink into tPage
   put item 3 of pLink into tAddress
   set the itemDelimiter to comma
   if tPage > 0 then
      pvGo tPage
      pvSay "A link inside the document: this is page" && tPage & pvLabelNote(tPage) & ".", "ok"
   else if tAddress is not empty then
      put tAddress into sAddress
      put "This link leads to" & return & tAddress into field "lnk:addr"
      pvShowTab "lnk"
      pvSay "A web link: its address is in the Links tab. Nothing was opened.", "warn"
   end if
end pvFollow

command pvOpenAddress
   if sAddress begins with "https://" or sAddress begins with "http://" then
      launch url sAddress
      pvSay "Asked the system to open" && sAddress & ".", "ok"
   else if sAddress is empty then
      pvSay "Click a web link on the page first: its address shows here before anything opens.", "warn"
   else
      pvSay "Only an http or https address is opened from here.", "warn"
   end if
end pvOpenAddress

-- ==========================================================================
-- The outline.
-- ==========================================================================

command pvFillOutline
   local tLine, tList, tLevel, tPage, tTitle, tLabel, tIndent, tI, tN
   set the defaultStack to the short name of this stack
   put empty into sOutline
   if sDoc > 0 then
      put pdfOutline(sDoc) into sOutline
   end if
   put 0 into tN
   repeat for each line tLine in sOutline
      add 1 to tN
      if tN > kPvOutlineMax then
         exit repeat
      end if
      set the itemDelimiter to tab
      put item 1 of tLine into tLevel
      put item 2 of tLine into tPage
      put item 3 of tLine into tTitle
      set the itemDelimiter to comma
      put empty into tIndent
      repeat with tI = 2 to min(tLevel, 8)
         put "   " after tIndent
      end repeat
      if tPage > 0 then
         put pdfPageLabel(sDoc, tPage) into tLabel
         if tLabel is empty then
            put tPage into tLabel
         end if
      else
         put "(web)" into tLabel
      end if
      put tIndent & tTitle & tab & tLabel & return after tList
   end repeat
   if tList is not empty then
      delete the last char of tList
   end if
   put tList into field "out:list"
   if sDoc is 0 then
      put "No document is open." into field "out:h"
   else if sOutline is empty then
      put "This document has no outline." into field "out:h"
   else
      put "Outline:" && the number of lines of sOutline && "entries (pdfOutline)" into field "out:h"
   end if
end pvFillOutline

command pvOutlineClick
   local tLine, tPage
   put the hilitedLine of field "out:list" into tLine
   if tLine is not an integer then
      exit pvOutlineClick
   end if
   set the itemDelimiter to tab
   put item 2 of line tLine of sOutline into tPage
   set the itemDelimiter to comma
   if tPage > 0 then
      pvGo tPage
      pvSay "Outline: went to page" && tPage & pvLabelNote(tPage) & ".", "ok"
   else
      pvSay "That entry leads outside this document: pdfOutline gives it page 0.", "warn"
   end if
end pvOutlineClick

-- ==========================================================================
-- Search.
-- ==========================================================================

command pvFind
   local tNeedle, tFlags, tPage, tHits, tLine, tCount, tPages, tList, tFrom, tContext, tLabel, tMore
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      pvSay "Open a PDF first, then search it.", "warn"
      exit pvFind
   end if
   put field "find:text" into tNeedle
   if tNeedle is empty then
      pvSay "Type a word to find.", "warn"
      exit pvFind
   end if
   put 0 into tFlags
   if the hilite of button "find:case" then
      add 1 to tFlags
   end if
   if the hilite of button "find:words" then
      add 2 to tFlags
   end if
   put tNeedle into sNeedle
   put empty into sFinds
   put 0 into sFindAt
   put 0 into tCount
   put 0 into tPages
   put false into tMore
   repeat with tPage = 1 to sPages
      put pdfPageSearch(sDoc, tPage, tNeedle, tFlags) into tHits
      if tHits is not empty then
         add 1 to tPages
         put pdfPageLabel(sDoc, tPage) into tLabel
         if tLabel is empty then
            put tPage into tLabel
         end if
         repeat for each line tLine in tHits
            if tCount >= kPvFindMax then
               put true into tMore
               exit repeat
            end if
            add 1 to tCount
            put tPage & comma & tLine & return after sFinds
            put max(1, item 1 of tLine - 24) into tFrom
            put pdfPageTextRange(sDoc, tPage, tFrom, item 2 of tLine + 48) into tContext
            replace return with space in tContext
            replace tab with space in tContext
            put "p." && tLabel & tab & tContext & return after tList
         end repeat
      end if
      if tMore then
         exit repeat
      end if
   end repeat
   if sFinds is not empty then
      delete the last char of sFinds
      delete the last char of tList
   end if
   put tList into field "find:list"
   if tCount is 0 then
      put "Not found (pdfPageSearch, flags" && tFlags & ")." into field "find:sum"
      pvComputeHits
      pvPaintMarks
      pvSay quote & tNeedle & quote && "is not in this document.", "warn"
      exit pvFind
   end if
   if tMore then
      put "The first" && tCount && "matches, on" && tPages && "page(s); there are more." into field "find:sum"
   else
      put tCount && "match(es) on" && tPages && "page(s), flags" && tFlags & "." into field "find:sum"
   end if
   pvFindShow 1
end pvFind

-- Shows match pIndex of the last search: its page, every match on that page
-- marked, the chosen one in orange and scrolled into view.
command pvFindShow pIndex
   local tLine, tPage, tRect, tL, tT, tR, tB
   set the defaultStack to the short name of this stack
   if sDoc is 0 or sFinds is empty or pIndex is not an integer then
      exit pvFindShow
   end if
   if pIndex < 1 or pIndex > the number of lines of sFinds then
      exit pvFindShow
   end if
   put pIndex into sFindAt
   put line pIndex of sFinds into tLine
   put item 1 of tLine into tPage
   if tPage is not sPage then
      put tPage into sPage
      put 0 into sScrollX
      put 0 into sScrollY
      put empty into sSel
      put empty into sCharRect
      pvShowDocument
   else
      pvComputeHits
      pvPaintMarks
   end if
   put line 1 of sCurRects into tRect
   if the number of items of tRect is 4 then
      put item 1 of tRect * sZoom into tL
      put item 2 of tRect * sZoom into tT
      put item 3 of tRect * sZoom into tR
      put item 4 of tRect * sZoom into tB
      if tL < sScrollX or tR > sScrollX + sImgW or tT < sScrollY or tB > sScrollY + sImgH then
         put round((tL + tR) / 2 - sImgW / 2) into sScrollX
         put round((tT + tB) / 2 - sImgH / 2) into sScrollY
         pvRender
      end if
   end if
   set the hilitedLine of field "find:list" to pIndex
   pvSay "Match" && pIndex && "of" && the number of lines of sFinds & ", on page" && tPage & pvLabelNote(tPage) & ".", "ok"
end pvFindShow

command pvFindStep pDelta
   local tNext, tCount
   if sFinds is empty then
      exit pvFindStep
   end if
   put the number of lines of sFinds into tCount
   put sFindAt + pDelta into tNext
   if tNext < 1 then
      put tCount into tNext
   else if tNext > tCount then
      put 1 into tNext
   end if
   pvFindShow tNext
end pvFindStep

-- ==========================================================================
-- Text, drawing and information.
-- ==========================================================================

command pvFillText
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      put "No document is open." into field "txt:h"
      put empty into field "txt:page"
      put empty into field "txt:hs"
      put empty into field "txt:sel"
      exit pvFillText
   end if
   put "Page" && sPage & ":" && pdfPageCharCount(sDoc, sPage) && "characters (pdfPageText)" into field "txt:h"
   put pdfPageText(sDoc, sPage) into field "txt:page"
   if sSel is empty and sCharRect is empty then
      put "Drag a box on the page, or click a word" into field "txt:hs"
      put "A box gives the text inside it (pdfPageTextInRect). A click gives the character there" \
            & " (pdfPageCharAt), its box (pdfPageCharBox) and the word it is in." into field "txt:sel"
   end if
end pvFillText

command pvCopy
   if field "txt:sel" is empty then
      exit pvCopy
   end if
   set the clipboardData["text"] to field "txt:sel"
   set the label of button "txt:copy" to "Copied"
   send "pvCopyBack" to me in 1200 milliseconds
end pvCopy

-- The Copy button's own word again, 1.2 seconds later. It arrives by
-- timer, so the stack is pinned first (engine note 5.3).
on pvCopyBack
   set the defaultStack to the short name of this stack
   if there is a button "txt:copy" then
      set the label of button "txt:copy" to "Copy"
   end if
end pvCopyBack

command pvReadFlags
   local tI
   put 0 into sFlags
   repeat with tI = 1 to the number of items of kPvFlagBoxes
      if the hilite of button (item tI of kPvFlagBoxes) then
         add item tI of kPvFlagValues to sFlags
      end if
   end repeat
end pvReadFlags

-- The Draw tab: the last drawing, and the page as a BMP file at most 100
-- pixels on its longer side (an image takes a BMP as its text and sizes
-- itself to it).
command pvFillDraw
   local tW, tH, tScale, tBmp
   set the defaultStack to the short name of this stack
   put sLastDraw into field "draw:last"
   if sDoc is 0 then
      set the visible of image "draw:thumb" to false
      exit pvFillDraw
   end if
   put pdfPageWidth(sDoc, sPage) into tW
   put pdfPageHeight(sDoc, sPage) into tH
   if tW <= 0 or tH <= 0 then
      exit pvFillDraw
   end if
   put 100 / max(tW, tH) into tScale
   put pdfRenderPageBMP(sDoc, sPage, max(1, round(tW * tScale)), max(1, round(tH * tScale)), sFlags) into tBmp
   if tBmp is empty then
      exit pvFillDraw
   end if
   set the text of image "draw:thumb" to tBmp
   set the topLeft of image "draw:thumb" to kPvThumbAt
   set the visible of image "draw:thumb" to (sTab is "draw")
end pvFillDraw

command pvAskSave
   local tPath
   if sDoc is 0 then
      pvSay "Open a PDF first.", "warn"
      exit pvAskSave
   end if
   ask file "Save the page as a BMP picture" with ("page-" & sPage & ".bmp")
   put it into tPath
   if tPath is empty then
      exit pvAskSave
   end if
   if not (tPath ends with ".bmp") then
      put ".bmp" after tPath
   end if
   pvSaveBMP tPath
end pvAskSave

-- Writes the page shown as a BMP file at two pixels to the point, smaller
-- if that would pass the library's limits (16384 a side, 40 million
-- pixels).
command pvSaveBMP pPath
   local tW, tH, tScale, tBmp
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      exit pvSaveBMP
   end if
   put pdfPageWidth(sDoc, sPage) into tW
   put pdfPageHeight(sDoc, sPage) into tH
   put min(2, 16384 / tW, 16384 / tH, sqrt(40000000 / (tW * tH))) into tScale
   put pdfRenderPageBMP(sDoc, sPage, max(1, trunc(tW * tScale)), max(1, trunc(tH * tScale)), sFlags) into tBmp
   if tBmp is empty then
      pvSay "The page could not be drawn: " & pdfLastError(), "bad"
      exit pvSaveBMP
   end if
   put tBmp into URL ("binfile:" & pPath)
   if the result is not empty then
      pvSay "Could not write " & pPath & ": " & the result, "bad"
      exit pvSaveBMP
   end if
   pvSay "Saved page" && sPage && "as a" && trunc(tW * tScale) && "x" && trunc(tH * tScale) && "BMP:" && pPath, "ok"
end pvSaveBMP

command pvFillInfo
   set the defaultStack to the short name of this stack
   put pvInfoText() into field "info:area"
end pvFillInfo

-- Everything the library says about the document and the page shown.
function pvInfoText
   local tOut, tError, tPerm, tTag, tW, tH, tPaper
   try
      put "Library" & tab & pdfLibraryVersion() & return after tOut
      put "PDFium" & tab & pvYes(pdfIsLoaded(), "loaded", "not loaded") & return after tOut
      put "Open now" & tab & pdfOpenCount() && "document(s) in this engine" & return after tOut
   catch tError
      return "pdfxt is not loaded."
   end try
   if sDoc is 0 then
      return tOut & return & "No document is open."
   end if
   put return & "Document" & tab & pvSourceName(sSource) & return after tOut
   put "Pages" & tab & sPages & return after tOut
   put "PDF version" & tab & (pdfFileVersion(sDoc) / 10) & return after tOut
   put pdfPermissions(sDoc) into tPerm
   put "Permissions" & tab & tPerm & ": print" && pvYes((tPerm bitAnd 4) is not 0, "yes", "no") \
         & ", change" && pvYes((tPerm bitAnd 8) is not 0, "yes", "no") \
         & ", copy" && pvYes((tPerm bitAnd 16) is not 0, "yes", "no") \
         & ", notes" && pvYes((tPerm bitAnd 32) is not 0, "yes", "no") \
         & " (the document's wishes: pdfxt reads it either way)" & return after tOut
   repeat for each item tTag in "Title,Author,Subject,Keywords,Creator,Producer,CreationDate,ModDate"
      put tTag & tab & pdfMetadata(sDoc, tTag) & return after tOut
   end repeat
   put pdfPageWidth(sDoc, sPage) into tW
   put pdfPageHeight(sDoc, sPage) into tH
   put pvPaper(tW, tH) into tPaper
   put return & "This page" & tab & sPage && "of" && sPages & pvLabelNote(sPage) & return after tOut
   put "Size" & tab & tW && "x" && tH && "points," && round(tW / 72, 2) && "x" && round(tH / 72, 2) && "in," \
         && round(tW / 72 * 25.4) && "x" && round(tH / 72 * 25.4) && "mm" after tOut
   if tPaper is not empty then
      put " (" & tPaper & ")" after tOut
   end if
   put return & "Turned" & tab & pdfPageRotation(sDoc, sPage) && "degrees by the file" & return after tOut
   put "Characters" & tab & pdfPageCharCount(sDoc, sPage) & return after tOut
   put "Links" & tab & the number of lines of sLinks after tOut
   return tOut
end pvInfoText

function pvYes pBool, pYes, pNo
   if pBool is true then
      return pYes
   end if
   return pNo
end pvYes

function pvPaper pW, pH
   if pvNear(pW, 612) and pvNear(pH, 792) then
      return "US Letter"
   else if pvNear(pW, 792) and pvNear(pH, 612) then
      return "US Letter, on its side"
   else if pvNear(pW, 595) and pvNear(pH, 842) then
      return "A4"
   else if pvNear(pW, 842) and pvNear(pH, 595) then
      return "A4, on its side"
   else if pvNear(pW, 612) and pvNear(pH, 1008) then
      return "US Legal"
   end if
   return empty
end pvPaper

function pvNear pA, pB
   return abs(pA - pB) < 1.5
end pvNear

-- ==========================================================================
-- Checks: every check, in one click. The same code is what a headless run
-- calls (pvCheckAll), so the window and the tests cannot drift apart.
-- ==========================================================================

command pvRunChecks
   local tReport, tSource, tPassword, tPage, tFit, tZoom
   set the defaultStack to the short name of this stack
   -- The checks close every document and shut PDFium down (they check those
   -- calls too), so the document this window shows is closed first and
   -- opened again after, on the same page.
   put sSource into tSource
   put sPassword into tPassword
   put sPage into tPage
   put sFit into tFit
   put sZoom into tZoom
   pvCloseDocument
   put pvCheckAll() into tReport
   put tReport into field "chk:log"
   if tSource is not empty then
      pvOpen tSource, tPassword
      if sDoc > 0 then
         put tFit into sFit
         put tZoom into sZoom
         pvGo tPage
      end if
   else
      pvShowDocument
   end if
   if sCkFail is 0 then
      put sCkPass && "checks passed, none failed." into field "chk:sum"
      set the foregroundColor of field "chk:sum" to kPvOk
      pvSay "Every check passed.", "ok"
   else
      put sCkPass && "passed," && sCkFail && "FAILED." into field "chk:sum"
      set the foregroundColor of field "chk:sum" to kPvBad
      pvSay sCkFail && "check(s) failed: the failing lines begin with FAIL.", "bad"
   end if
end pvRunChecks

private command pvCk pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sCkPass
      put "PASS  " & pLabel & return after sCkLog
   else
      add 1 to sCkFail
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sCkLog
   end if
end pvCk

-- One pixel of an imageData result as "r,g,b" (the first byte of each four
-- is unused by the engine).
function pvPixel pData, pWidth, pX, pY
   local tAt
   put (pY * pWidth + pX) * 4 into tAt
   return byteToNum(byte tAt + 2 of pData) & comma & byteToNum(byte tAt + 3 of pData) & comma & byteToNum(byte tAt + 4 of pData)
end pvPixel

function pvLabels pDoc
   local tPage, tOut
   repeat with tPage = 1 to pdfPageCount(pDoc)
      put pdfPageLabel(pDoc, tPage) & comma after tOut
   end repeat
   delete the last char of tOut
   return tOut
end pvLabels

function pvMatchCount pDoc, pNeedle, pFlags
   local tPage, tCount
   put 0 into tCount
   repeat with tPage = 1 to pdfPageCount(pDoc)
      add the number of lines of pdfPageSearch(pDoc, tPage, pNeedle, pFlags) to tCount
   end repeat
   return tCount
end pvMatchCount

-- The page each link of a page leads to, as one list.
function pvLinkPages pLinks
   local tLine, tOut
   set the itemDelimiter to tab
   repeat for each line tLine in pLinks
      put item 2 of tLine & comma after tOut
   end repeat
   set the itemDelimiter to comma
   delete the last char of tOut
   return tOut
end pvLinkPages

-- Returns the transcript; its last line is "SUMMARY <passed> <failed>".
function pvCheckAll
   local tDoc, tLocked, tBytes, tData, tPart, tBmp, tText, tBox, tHits, tRects, tOutline, tLinks, tWas, tError, tPath
   put 0 into sCkPass
   put 0 into sCkFail
   put empty into sCkLog
   try
      -- the library
      put "Library: " & pdfLibraryVersion() & return after sCkLog
      pvCk pdfABIVersion() is 1, "the library is at the ABI this binding wants", pdfABIVersion()
      pvCk pdfLibraryVersion() begins with "pdfxt ABI 1; PDFium chromium/", "it names the PDFium it was built for", pdfLibraryVersion()
      pvCk pdfLoad(empty) is true and pdfIsLoaded() is true, "PDFium loads from beside pdfxt", pdfLastError()

      -- opening from memory
      put base64Decode(pvSampleBase64("sample")) into tBytes
      put pdfOpenCount() into tWas
      put pdfOpenData(tBytes, empty) into tDoc
      put empty into tBytes
      pvCk tDoc > 0 and pdfIsOpen(tDoc) is true and pdfOpenCount() is tWas + 1, "the sample opens from bytes", pdfLastError()

      -- the document
      pvCk pdfPageCount(tDoc) is 5 and pdfFileVersion(tDoc) is 17, "five pages, PDF 1.7", pdfPageCount(tDoc) && pdfFileVersion(tDoc)
      pvCk pdfPermissions(tDoc) is 4294967295, "a file with no password allows everything", pdfPermissions(tDoc)
      pvCk pdfMetadata(tDoc, "Title") is "A short guide to pdfxt" and pdfMetadata(tDoc, "Author") is "xTalk Suite", \
            "its title and author", pdfMetadata(tDoc, "Title")
      pvCk pdfMetadata(tDoc, "Keywords") is "pdf, pdfium, openxtalk" and pdfMetadata(tDoc, "ModDate") is "D:20261121000000Z", \
            "its keywords, and a date as the file wrote it", pdfMetadata(tDoc, "ModDate")
      pvCk pvLabels(tDoc) is "i,ii,1,2,3", "page labels: two roman, then 1 to 3", pvLabels(tDoc)
      pvCk pdfPageSize(tDoc, 1) is "612,792" and pdfPageRotation(tDoc, 1) is 0, "page i is US Letter", pdfPageSize(tDoc, 1)
      pvCk pdfPageSize(tDoc, 4) is "842,595" and pdfPageRotation(tDoc, 4) is 90 and pdfPageWidth(tDoc, 4) is 842 \
            and pdfPageHeight(tDoc, 4) is 595, "the turned page reports the size it is shown at", pdfPageSize(tDoc, 4)

      -- drawing
      put pdfRenderPage(tDoc, 1, 306, 396, 0) into tData
      pvCk the number of bytes of tData is 306 * 396 * 4, "a page drawn at half size is width x height x 4 bytes", the number of bytes of tData
      pvCk pvPixel(tData, 306, 5, 5) is "44,90,160" and pvPixel(tData, 306, 60, 160) is "255,0,0" \
            and pvPixel(tData, 306, 150, 300) is "255,255,255", "the band, the red square and white paper", \
            pvPixel(tData, 306, 5, 5) && pvPixel(tData, 306, 60, 160)
      put pdfRenderPage(tDoc, 4, 421, 298, 0) into tData
      pvCk pvPixel(tData, 421, 44, 230) is "44,90,160" and pvPixel(tData, 421, 340, 180) is "199,216,241", \
            "the turned page draws upright: its first bar and its circle", pvPixel(tData, 421, 44, 230) && pvPixel(tData, 421, 340, 180)
      put pdfRenderPageRegion(tDoc, 1, 1224, 1584, 200, 600, 300, 200, 0) into tPart
      pvCk the number of bytes of tPart is 300 * 200 * 4 and pvPixel(tPart, 300, 50, 50) is "255,0,0" \
            and pvPixel(tPart, 300, 280, 100) is "0,160,0", "a window of a page at 200% is drawn on its own", \
            pvPixel(tPart, 300, 50, 50) && pvPixel(tPart, 300, 280, 100)
      put pdfRenderPageBMP(tDoc, 1, 204, 264, 0) into tBmp
      pvCk byte 1 to 2 of tBmp is "BM" and the number of bytes of tBmp is 54 + 612 * 264, "a page as a BMP file", the number of bytes of tBmp
      put pdfRenderPage(tDoc, 1, 306, 396, 8) into tData
      put pvPixel(tData, 306, 5, 5) into tText
      pvCk item 1 of tText is item 2 of tText and item 2 of tText is item 3 of tText and tText is not "44,90,160", \
            "flag 8 draws it gray", tText
      pvCk pdfRenderPage(tDoc, 1, 10000, 10000, 0) is empty and pdfLastError() is not empty, \
            "a drawing of more than 40 million pixels is refused, in words", pdfLastError()
      pvCk pdfRenderPage(tDoc, 9, 10, 10, 0) is empty and pdfLastError() contains "page", "a page that is not there is refused", pdfLastError()

      -- text
      put pdfPageText(tDoc, 5) into tText
      pvCk line 1 of tText is "3 Text and search" and the number of lines of tText is 13, "a page's text, a line of the page to a line", line 1 of tText
      pvCk pdfPageCharCount(tDoc, 5) is 618, "its characters as PDFium counts them (a line break is two)", pdfPageCharCount(tDoc, 5)
      pvCk pdfPageTextRange(tDoc, 5, 3, 4) is "Text", "a range of them", pdfPageTextRange(tDoc, 5, 3, 4)
      pvCk ("caf" & numToCodepoint(233) & ", na" & numToCodepoint(239) & "ve, Z" & numToCodepoint(252) & "rich, 25 " & numToCodepoint(176) & "C") is in tText, \
            "text outside ASCII comes out as itself", the number of chars of tText
      pvCk pdfPageTextInRect(tDoc, 5, 60, 166, 300, 190) is "needle, Needle, needles", "the text inside a box", pdfPageTextInRect(tDoc, 5, 60, 166, 300, 190)
      put pdfPageCharBox(tDoc, 5, 3) into tBox
      pvCk the number of items of tBox is 4 and pdfPageCharAt(tDoc, 5, (item 1 of tBox + item 3 of tBox) / 2, (item 2 of tBox + item 4 of tBox) / 2, 1) is 3, \
            "the character at the middle of a character's box is that character", tBox
      pvCk pdfPageCharAt(tDoc, 5, 500, 400, 1) is 0, "no character where the page is empty", pdfPageCharAt(tDoc, 5, 500, 400, 1)

      -- search
      pvCk the number of lines of pdfPageSearch(tDoc, 5, "needle", 0) is 3 and the number of lines of pdfPageSearch(tDoc, 5, "needle", 1) is 2 \
            and the number of lines of pdfPageSearch(tDoc, 5, "needle", 2) is 2 and the number of lines of pdfPageSearch(tDoc, 5, "needle", 3) is 1, \
            "needle: 3 matches, 2 with capitals matching, 2 as whole words, 1 with both", pdfPageSearch(tDoc, 5, "needle", 0)
      pvCk pdfPageSearch(tDoc, 5, "caf" & numToCodepoint(233), 0) is "473,4", "a word outside ASCII is found", pdfPageSearch(tDoc, 5, "caf" & numToCodepoint(233), 0)
      pvCk pvMatchCount(tDoc, "PDFium", 0) is 3, "PDFium three times in the document", pvMatchCount(tDoc, "PDFium", 0)
      put pdfPageSearch(tDoc, 5, "needle", 3) into tHits
      put pdfPageTextRects(tDoc, 5, item 1 of tHits, item 2 of tHits) into tRects
      pvCk the number of lines of tRects is 1 and the number of items of tRects is 4, "a match on one line covers one rectangle", tRects
      pvCk the number of lines of pdfPageTextRects(tDoc, 1, 1, 10) is 2, "a run across a line break covers one rectangle a line", pdfPageTextRects(tDoc, 1, 1, 10)

      -- outline and links
      put pdfOutline(tDoc) into tOutline
      pvCk the number of lines of tOutline is 8, "eight outline entries", the number of lines of tOutline
      set the itemDelimiter to tab
      pvCk line 4 of tOutline is ("2" & tab & "3" & tab & "Passwords") and item 2 of line 8 of tOutline is 0 \
            and item 3 of line 8 of tOutline is "OpenXTalk on the web", "a nested entry, and one that leaves the document (page 0)", line 4 of tOutline
      set the itemDelimiter to comma
      pvCk pvLinkPages(pdfPageLinks(tDoc, 2)) is "3,4,5", "the contents page links to pages 3, 4 and 5", pvLinkPages(pdfPageLinks(tDoc, 2))
      put pdfPageLinks(tDoc, 1) into tLinks
      pvCk tLinks is ("70,439,206,457" & tab & "0" & tab & "https://openxtalk.org/"), "the cover's web link: its box, page 0 and its address", tLinks
      pvCk pvLinkPages(pdfPageLinks(tDoc, 5)) is "2" and pdfPageLinks(tDoc, 3) is empty, "a link back to the contents; a page with none", pdfPageLinks(tDoc, 5)

      -- the locked page
      put base64Decode(pvSampleBase64("locked")) into tBytes
      pvCk pdfOpenData(tBytes, empty) is 0 and pdfLastError() contains "password", "the locked page needs its password", pdfLastError()
      pvCk pdfOpenData(tBytes, "wrong") is 0, "a wrong password does not open it", pdfLastError()
      put pdfOpenData(tBytes, "secret") into tLocked
      pvCk tLocked > 0 and line 1 of pdfPageText(tLocked, 1) is "Hello pdfxt", "secret opens it", pdfLastError()
      pvCk (pdfPermissions(tLocked) bitAnd 4) is 0 and (pdfPermissions(tLocked) bitAnd 16) is 16, \
            "it asks not to be printed, and allows copying", pdfPermissions(tLocked)

      -- refusals, closing and shutting down
      pvCk pdfOpenData("this is not a PDF at all", empty) is 0 and pdfLastError() is not empty, "bytes that are not a PDF are refused, in words", pdfLastError()
      put the temporary folder & "/pdfxt-demo-no-such-file.pdf" into tPath
      pvCk pdfOpen(tPath, empty) is 0 and pdfLastError() is not empty, "a file that is not there is refused", pdfLastError()
      pvCk pdfPageCount(0) is 0 and pdfPageText(0, 1) is empty and pdfIsOpen(0) is false, "handle 0 reads as nothing", pdfPageCount(0)
      pdfClose tLocked
      pvCk pdfIsOpen(tLocked) is false and pdfPageCount(tLocked) is 0, "a closed handle is dead", pdfIsOpen(tLocked)
      pdfClose tLocked
      pvCk pdfOpenCount() is tWas + 1, "and closing it twice is harmless", pdfOpenCount()
      pvCk pdfCloseAll() is tWas + 1 and pdfOpenCount() is 0, "close all closes every document and says how many", pdfOpenCount()
      pdfShutdown
      pvCk pdfIsLoaded() is false and pdfIsOpen(tDoc) is false, "shutdown stops PDFium", pdfIsLoaded()
      put pdfOpenData(base64Decode(pvSampleBase64("sample")), empty) into tDoc
      pvCk tDoc > 0 and pdfIsLoaded() is true and pdfPageCount(tDoc) is 5, "the next open starts it again", pdfLastError()
      pdfClose tDoc
   catch tError
      pvCk false, "the checks ran to their end", line 1 of tError
   end try
   put "SUMMARY" && sCkPass && sCkFail after sCkLog
   return sCkLog
end pvCheckAll

-- ==========================================================================
-- The showcase: five scenes, each one thing the library does, played by
-- the window itself. A scene is a function of its frame number that does
-- that frame's part and answers false after its last; pvShowTick plays one
-- frame on a timer and asks for the next, so nothing ever waits. When the
-- window opens it plays them all, one after another (pvTourStart); a click
-- on a scene's button plays that one; any other click, key or turn of the
-- wheel stops it where it is (pvStopShow), and the person has the viewer.
-- ==========================================================================

-- The words under WHAT THIS SHOWS for a scene, or for none (0).
function pvSceneAbout pScene
   switch pScene
      case 1
         return "1. Deep zoom. Each frame is a new drawing by PDFium at the zoom asked for. Past the size of the view," \
               && "pdfRenderPageRegion draws only the window you see, so 1000% costs what the fitted page does, and the letters stay sharp."
      case 2
         return "2. Find a word. pdfPageSearch finds every place a word occurs; pdfPageTextRects gives the boxes to mark." \
               && "Two flags narrow it: capitals must match (2 of 3 here), whole words (2), both (1)."
      case 3
         return "3. Read a page. pdfPageText reads it in order and pdfPageCharBox places each character. A box dragged" \
               && "over the page gives the words inside it; a click finds the character there and its word."
      case 4
         return "4. Outline and links. pdfOutline gives the outline, pdfPageLinks each link's box and where it leads." \
               && "A link inside the document is followed; a web address is only shown, since a stranger wrote it."
      case 5
         return "5. Unlock. A locked PDF opens only with its password: a wrong one is refused, and pdfLastError says why." \
               && "The right one opens it, and pdfPermissions says what its author allows: no printing, here."
   end switch
   return "When this window opens it plays the five scenes in turn. Click one to see it again, or take over: open" \
         && "a PDF of your own, turn its pages, zoom, search, click a word or drag a box over the page to read it."
end pvSceneAbout

-- The tour, as the window opens: every scene in turn. It arrives by timer,
-- so the stack is pinned first (engine note 5.3).
on pvTourStart
   set the defaultStack to the short name of this stack
   put empty into sShowMsg
   pvPlay 1, true
end pvTourStart

-- Plays scene pScene; with pAll true the scenes after it follow. pArm false
-- leaves the first frame for the caller to play (pvShowRun).
command pvPlay pScene, pAll, pArm
   set the defaultStack to the short name of this stack
   pvShowCancel
   if pvReady() is false then
      put "The scenes need pdfxt, and it is not here: the line under the page says what is missing." into field "show:about"
      exit pvPlay
   end if
   if pScene is not an integer then
      exit pvPlay
   end if
   if pScene < 1 or pScene > kPvScenes then
      exit pvPlay
   end if
   pvShowClean
   put pScene into sShow
   put (pAll is true) into sShowAll
   put 0 into sShowStep
   put empty into sShowLog
   pvShowLights
   put pvSceneAbout(pScene) into field "show:about"
   if pArm is not false then
      pvShowArm 20
   end if
end pvPlay

-- One frame of the scene playing, by timer, and the next one asked for:
-- the time the frame took is taken off the wait, so the motion keeps its
-- pace while the page is drawn.
on pvShowTick
   local tStart, tMore
   set the defaultStack to the short name of this stack
   put empty into sShowMsg
   if sShow is 0 then
      exit pvShowTick
   end if
   put the milliseconds into tStart
   put pvShowFrame() into tMore
   if sShow is 0 then
      exit pvShowTick
   end if
   if tMore then
      pvShowArm max(5, kPvFrameMs - (the milliseconds - tStart))
   else if pvShowNext() then
      -- a breath between two scenes of the tour
      pvShowArm 500
   end if
end pvShowTick

private command pvShowArm pDelay
   send "pvShowTick" to me in pDelay milliseconds
   put the result into sShowMsg
end pvShowArm

-- The next frame of the scene playing, drawn with the screen locked. True
-- while the scene has frames to come.
function pvShowFrame
   local tMore
   add 1 to sShowStep
   lock screen
   switch sShow
      case 1
         put pvSceneZoom(sShowStep) into tMore
         break
      case 2
         put pvSceneFind(sShowStep) into tMore
         break
      case 3
         put pvSceneRead(sShowStep) into tMore
         break
      case 4
         put pvSceneLinks(sShowStep) into tMore
         break
      case 5
         put pvSceneUnlock(sShowStep) into tMore
         break
      default
         put false into tMore
   end switch
   pvShowTitle sShowStep
   pvShowFade
   pvShowProgress
   unlock screen
   return tMore
end pvShowFrame

-- A scene has ended: the next one of the tour begins (true), or the show
-- is over (false).
function pvShowNext
   if sShowAll and sShow < kPvScenes then
      pvShowClean
      add 1 to sShow
      put 0 into sShowStep
      pvShowLights
      put pvSceneAbout(sShow) into field "show:about"
      return true
   end if
   pvShowEnd
   return false
end pvShowNext

-- The show is over. After the whole tour the sample is put back on its
-- cover, as the window opened.
command pvShowEnd
   local tWasAll, tWas
   put sShowAll into tWasAll
   put sShow into tWas
   put 0 into sShow
   put false into sShowAll
   pvShowCancel
   pvShowClean
   pvShowLights
   pvShowProgress
   if tWasAll then
      pvOpen "sample", empty
      pvShowTab "out"
      put "That was the tour. Click a scene to see it again, or take over: open a PDF of your own, turn its" \
            && "pages, zoom, search, click a word or drag a box over the page to read it." into field "show:about"
      pvSay "The tour is over: the viewer is yours.", "ok"
   else if tWas > 0 then
      pvSay "Scene" && tWas && "is over. Everything it did is a click away in the viewer.", "ok"
   end if
end pvShowEnd

-- The person took over: the scene stops where it is, and so does a tour
-- that has not begun yet.
command pvStopShow
   set the defaultStack to the short name of this stack
   pvShowCancel
   if sShow is 0 then
      exit pvStopShow
   end if
   put 0 into sShow
   put false into sShowAll
   pvShowClean
   pvShowLights
   pvShowProgress
   put "Stopped where it was: the viewer is yours. Click a scene to watch one again." into field "show:about"
end pvStopShow

-- No frame of this stack's show is left queued: the one it knows of, and
-- any other a re-entry could have left (two chains would race).
private command pvShowCancel
   local tLine
   if sShowMsg is not empty then
      cancel sShowMsg
      put empty into sShowMsg
   end if
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine is "pvShowTick" or item 3 of tLine is "pvTourStart" then
         if item 4 to -1 of tLine is the long id of me then
            cancel item 1 of tLine
         end if
      end if
   end repeat
end pvShowCancel

-- What a scene leaves over the page, taken away.
private command pvShowClean
   lock screen
   set the blendLevel of image "view:page" to 0
   set the visible of graphic "view:ptr" to false
   set the visible of field "view:title" to false
   pvShowPulse 78
   pvLockPlace 0
   unlock screen
end pvShowClean

-- The scene's button lit while it plays, and Play them all during the tour.
private command pvShowLights
   local tI
   repeat with tI = 1 to kPvScenes
      set the hilite of button ("show:" & tI) to (tI is sShow)
   end repeat
   set the hilite of button "show:all" to sShowAll
end pvShowLights

private command pvShowProgress
   local tTotal, tW
   if sShow is 0 then
      set the visible of graphic "show:fill" to false
      exit pvShowProgress
   end if
   put item sShow of kPvSceneFrames into tTotal
   put round((kPvSideR - kPvSideL) * min(1, sShowStep / tTotal)) into tW
   if tW < 1 then
      set the visible of graphic "show:fill" to false
   else
      set the rect of graphic "show:fill" to kPvSideL & comma & kPvBarT & comma & (kPvSideL + tW) & comma & (kPvBarT + 4)
      set the visible of graphic "show:fill" to true
   end if
end pvShowProgress

-- The scene's name over the bottom of the stage as it begins, fading.
private command pvShowTitle pStep
   if pStep is 1 then
      put sShow & "." && item sShow of kPvSceneNames into field "view:title"
      set the blendLevel of field "view:title" to 8
      set the visible of field "view:title" to true
   else if pStep > 24 and pStep <= 36 then
      set the blendLevel of field "view:title" to min(100, 8 + (pStep - 24) * 8)
   else if pStep is 37 then
      set the visible of field "view:title" to false
   end if
end pvShowTitle

-- A page a scene turns to comes up out of the dark over a few frames.
private command pvShowFade
   local tBlend
   if the visible of image "view:page" then
      put the blendLevel of image "view:page" into tBlend
      if tBlend > 0 then
         set the blendLevel of image "view:page" to max(0, tBlend - 15)
      end if
   end if
end pvShowFade

private command pvShowTurned pWas
   if sPage is not pWas then
      set the blendLevel of image "view:page" to 75
   end if
end pvShowTurned

private command pvShowGo pPage
   local tWas
   put sPage into tWas
   pvGo pPage
   pvShowTurned tWas
end pvShowGo

-- The sample, open and unlocked, for a scene that shows it. False when it
-- would not open (pvOpen has said why).
private function pvShowSample
   if sSource is not "sample" or sDoc is 0 then
      pvOpen "sample", empty
   end if
   return sDoc > 0
end pvShowSample

-- 0 before frame pFrom, 1 after pTo, and between them a smooth start and
-- stop (smoothstep).
function pvEase pStep, pFrom, pTo
   local tT
   if pStep <= pFrom then
      return 0
   end if
   if pStep >= pTo then
      return 1
   end if
   put (pStep - pFrom) / (pTo - pFrom) into tT
   return tT * tT * (3 - 2 * tT)
end pvEase

-- The page shown at pZoom pixels to the point, with its point pX,pY in the
-- middle of the view (or as near as the page's edges allow).
command pvViewAt pZoom, pX, pY
   put empty into sFit
   put pZoom into sZoom
   put round(pX * pZoom - (kPvViewR - kPvViewL) / 2) into sScrollX
   put round(pY * pZoom - (kPvViewB - kPvViewT) / 2) into sScrollY
   pvRender
end pvViewAt

private command pvShowZoomTo pZoom, pX, pY
   pvViewAt pZoom, pX, pY
   put max(sShowPeak, round(pZoom * 100)) into sShowPeak
   if sLastDraw begins with "pdfRenderPageRegion" then
      add 1 to sShowWindows
   end if
end pvShowZoomTo

-- 1. Deep zoom: into the cover's title, along it, and out again. The
-- title's letters are 48 points tall at 72,92 of the page; at 1000% one
-- letter fills the view.
function pvSceneZoom pStep
   local tE, tF
   if pStep is 1 then
      if pvShowSample() is false then
         return false
      end if
      put 0 into sShowPeak
      put 0 into sShowWindows
      pvShowTab "draw"
      pvGo 1
      pvZoom "page"
      put sZoom into sShowFit
   else if pStep >= 8 and pStep <= 80 then
      put pvEase(pStep, 8, 80) into tE
      put pvEase(pStep, 8, 56) into tF
      pvShowZoomTo sShowFit * (10 / sShowFit) ^ tE, 306 + (86 - 306) * tF, 396 + (80 - 396) * tF
   else if pStep >= 96 and pStep <= 165 then
      pvShowZoomTo 10, 86 + (182 - 86) * pvEase(pStep, 96, 165), 80
   else if pStep >= 179 and pStep <= 228 then
      put pvEase(pStep, 179, 228) into tE
      pvShowZoomTo 10 * (sShowFit / 10) ^ tE, 182 + (306 - 182) * tE, 80 + (396 - 80) * tE
   else if pStep is 229 then
      pvZoom "page"
   else if pStep >= 240 then
      put "zoom: deepest" && sShowPeak & "%," && sShowWindows && "frames drawn as a window, back at" \
            && round(sZoom * 100) & "%" & return after sShowLog
      return false
   end if
   return true
end pvSceneZoom

-- 2. Find a word: "needle" typed and found, each match chosen in turn, the
-- two flags switched on and off, then "PDFium" across the document.
function pvSceneFind pStep
   local tN, tWas
   put sPage into tWas
   if pStep is 1 then
      if pvShowSample() is false then
         return false
      end if
      pvShowTab "find"
      set the hilite of button "find:case" to false
      set the hilite of button "find:words" to false
      put empty into field "find:text"
      put empty into field "find:list"
      put empty into field "find:sum"
      put empty into sNeedle
      put empty into sFinds
      put 0 into sFindAt
      pvGo 1
      pvZoom "page"
   else if pStep >= 8 and pStep <= 25 then
      put min(6, (pStep - 8) div 3 + 1) into tN
      put char 1 to tN of "needle" into field "find:text"
   else if pStep is 28 or pStep is 207 then
      set the hilite of button "find:go" to true
   else if pStep is 31 then
      set the hilite of button "find:go" to false
      -- close enough to read the marks
      put empty into sFit
      put 1.4 into sZoom
      pvFind
      pvShowTurned tWas
      put "find: needle" && pvShowCount() & return after sShowLog
   else if pStep is 50 or pStep is 66 or pStep is 82 or pStep is 232 or pStep is 254 then
      pvFindStep 1
      pvShowTurned tWas
   else if pStep is 100 then
      pvShowFlip "find:case"
      put "find: capitals" && pvShowCount() & return after sShowLog
   else if pStep is 125 then
      pvShowFlip "find:words"
      put "find: capitals and whole words" && pvShowCount() & return after sShowLog
   else if pStep is 150 then
      pvShowFlip "find:case"
      put "find: whole words" && pvShowCount() & return after sShowLog
   else if pStep is 172 then
      pvShowFlip "find:words"
   else if pStep is 186 then
      put empty into field "find:text"
   else if pStep >= 188 and pStep <= 203 then
      put min(6, (pStep - 188) div 3 + 1) into tN
      put char 1 to tN of "PDFium" into field "find:text"
   else if pStep is 210 then
      set the hilite of button "find:go" to false
      put "page" into sFit
      pvFind
      pvShowTurned tWas
      put "find: PDFium" && pvShowCount() && "on" && pvShowPages() && "pages" & return after sShowLog
   else if pStep >= 280 then
      return false
   end if
   return true
end pvSceneFind

-- A switch thrown by the scene, as a click would.
private command pvShowFlip pName
   set the hilite of button pName to not the hilite of button pName
   pvTicked pName
end pvShowFlip

-- How many matches the last search found, and on how many pages.
function pvShowCount
   if sFinds is empty then
      return 0
   end if
   return the number of lines of sFinds
end pvShowCount

function pvShowPages
   local tLine, tPages
   repeat for each line tLine in sFinds
      if item 1 of tLine is not among the items of tPages then
         put item 1 of tLine & comma after tPages
      end if
   end repeat
   return the number of items of tPages
end pvShowPages

-- 3. Read a page: the first sixty characters read one by one, a box dragged
-- over the Passwords paragraph, then a click on a word.
function pvSceneRead pStep
   local tN, tHits, tBox, tE
   if pStep is 1 then
      if pvShowSample() is false then
         return false
      end if
      pvShowTab "txt"
      put empty into sSel
      put empty into sCharRect
      pvGo 3
      pvViewAt 1.5, 280, 160
      pvFillText
   else if pStep >= 8 and pStep <= 67 then
      put pStep - 7 into tN
      put pdfPageCharBox(sDoc, sPage, tN) into sCharRect
      put "Reading character" && tN && "of" && pdfPageCharCount(sDoc, sPage) && "(pdfPageCharBox)" into field "txt:hs"
      put pdfPageTextRange(sDoc, sPage, 1, tN) into field "txt:sel"
      pvPaintMarks
   else if pStep is 72 then
      put empty into sCharRect
      put "A box dragged over the page..." into field "txt:hs"
      put empty into field "txt:sel"
      pvPaintMarks
   else if pStep >= 74 and pStep <= 120 then
      put pvEase(pStep, 74, 120) into tE
      put "66,178," & round(66 + 420 * tE) & comma & round(178 + 74 * tE) into sSel
      pvPaintMarks
   else if pStep is 121 then
      pvSelectBox 66, 178, 486, 252
      put "read: the box holds" && the number of chars of field "txt:sel" && "characters" & return after sShowLog
   else if pStep is 160 then
      -- the middle of the third letter of the first whole word "password"
      put pdfPageSearch(sDoc, sPage, "password", 2) into tHits
      if tHits is not empty then
         put pdfPageCharBox(sDoc, sPage, item 1 of line 1 of tHits + 2) into tBox
         if the number of items of tBox is 4 then
            pvClickAt (item 1 of tBox + item 3 of tBox) / 2, (item 2 of tBox + item 4 of tBox) / 2
         end if
      end if
      put "read: the word clicked is" && the last word of the last line of field "txt:sel" & return after sShowLog
   else if pStep >= 215 then
      return false
   end if
   return true
end pvSceneRead

-- 4. Outline and links: each outline entry in turn, then the contents
-- page's links lit, followed by a pointer, and the cover's web link shown.
function pvSceneLinks pStep
   local tK, tWas, tPage
   if pStep is 1 then
      if pvShowSample() is false then
         return false
      end if
      pvShowTab "out"
      pvGo 1
      pvZoom "page"
      set the hilitedLines of field "out:list" to empty
   else if pStep >= 8 and pStep <= 134 then
      if (pStep - 8) mod 18 is 0 then
         put (pStep - 8) div 18 + 1 into tK
         if tK <= the number of lines of sOutline then
            put sPage into tWas
            set the hilitedLine of field "out:list" to tK
            pvOutlineClick
            pvShowTurned tWas
            set the itemDelimiter to tab
            put item 2 of line tK of sOutline into tPage
            set the itemDelimiter to comma
            if tPage > 0 then
               put "outline:" && tPage & return after sShowLog
            else
               put "outline: web" & return after sShowLog
            end if
         end if
      end if
   else if pStep is 152 then
      pvShowTab "lnk"
      set the hilite of button "lnk:show" to true
      pvShowGo 2
      put "links: page 2 has" && the number of lines of sLinks & return after sShowLog
   else if pStep >= 156 and pStep <= 186 then
      pvShowPulse round(50 + 28 * cos((pStep - 156) * pi / 7.5))
   else if pStep is 187 then
      pvShowPulse 78
   else if pStep is 188 then
      set the width of graphic "view:ptr" to 26
      set the height of graphic "view:ptr" to 26
      set the loc of graphic "view:ptr" to the loc of image "view:page"
      set the visible of graphic "view:ptr" to true
   else if pStep >= 190 and pStep <= 212 then
      pvShowGlide pStep, 190, 212, 200, 189
   else if pStep >= 214 and pStep <= 217 then
      pvShowPress pStep - 213
   else if pStep is 218 then
      pvShowClick 200, 189
   else if pStep >= 226 and pStep <= 248 then
      pvShowGlide pStep, 226, 248, 133, 328
   else if pStep >= 250 and pStep <= 253 then
      pvShowPress pStep - 249
   else if pStep is 254 then
      pvShowClick 133, 328
   else if pStep is 266 then
      pvShowGo 1
   else if pStep >= 270 and pStep <= 292 then
      pvShowGlide pStep, 270, 292, 138, 448
   else if pStep >= 294 and pStep <= 297 then
      pvShowPress pStep - 293
   else if pStep is 298 then
      pvShowClick 138, 448
   else if pStep is 320 then
      set the visible of graphic "view:ptr" to false
   else if pStep >= 330 then
      return false
   end if
   return true
end pvSceneLinks

-- The links outlined on the page, all at one see-through level.
private command pvShowPulse pBlend
   local tI
   repeat with tI = 1 to kPvLinkMax
      set the blendLevel of graphic ("view:ln" & tI) to pBlend
   end repeat
end pvShowPulse

-- The pointer glides, frame pFrom to pTo, to the point pX,pY of the page.
private command pvShowGlide pStep, pFrom, pTo, pX, pY
   local tE, tH, tV
   if pStep is pFrom then
      put item 1 of the loc of graphic "view:ptr" into sShowFromH
      put item 2 of the loc of graphic "view:ptr" into sShowFromV
   end if
   put pvEase(pStep, pFrom, pTo) into tE
   put sImgL + round(pX * sZoom) - sScrollX into tH
   put sImgT + round(pY * sZoom) - sScrollY into tV
   set the loc of graphic "view:ptr" to round(sShowFromH + (tH - sShowFromH) * tE) & comma & round(sShowFromV + (tV - sShowFromV) * tE)
   set the visible of graphic "view:ptr" to true
end pvShowGlide

-- A press, in four frames: the pointer shrinks and comes back.
private command pvShowPress pN
   local tLoc, tSize
   put the loc of graphic "view:ptr" into tLoc
   put item pN of "22,17,17,22" into tSize
   set the width of graphic "view:ptr" to tSize
   set the height of graphic "view:ptr" to tSize
   set the loc of graphic "view:ptr" to tLoc
end pvShowPress

-- The click the pointer made: pvClickAt, as the mouse handlers call it.
private command pvShowClick pX, pY
   local tWas, tLoc
   put the loc of graphic "view:ptr" into tLoc
   set the width of graphic "view:ptr" to 26
   set the height of graphic "view:ptr" to 26
   set the loc of graphic "view:ptr" to tLoc
   put sPage into tWas
   put empty into sAddress
   pvClickAt pX, pY
   if sAddress is not empty then
      put "link: web" && sAddress & return after sShowLog
   else
      pvShowTurned tWas
      put "link: page" && sPage & return after sShowLog
   end if
end pvShowClick

-- 5. Unlock: the locked sample asks for its password; a wrong one is typed
-- and refused (the bar shakes), then the right one opens it.
function pvSceneUnlock pStep
   local tN
   if pStep is 1 then
      pvShowTab "info"
      pvOpen "locked", empty
      if sWaiting is not "locked" then
         put "unlock: the locked sample did not ask for a password" & return after sShowLog
         return false
      end if
      put "unlock: it asks for its password" & return after sShowLog
   else if pStep >= 8 and pStep <= 29 then
      put min(11, (pStep - 8) div 2 + 1) into tN
      put char 1 to tN of "open sesame" into field "lock:pw"
   else if pStep is 33 or pStep is 81 then
      set the hilite of button "lock:go" to true
   else if pStep is 36 then
      set the hilite of button "lock:go" to false
      pvUnlock
      if sDoc is 0 and sWaiting is "locked" then
         put "unlock: a wrong password is refused" & return after sShowLog
      end if
   else if pStep >= 37 and pStep <= 52 then
      pvLockPlace round(10 * sin((pStep - 37) * pi / 2.5) * (52 - pStep) / 15)
   else if pStep is 53 then
      pvLockPlace 0
   else if pStep >= 60 and pStep <= 77 then
      put min(6, (pStep - 60) div 3 + 1) into tN
      put char 1 to tN of "secret" into field "lock:pw"
   else if pStep is 84 then
      set the hilite of button "lock:go" to false
      pvUnlock
      if sDoc > 0 then
         set the blendLevel of image "view:page" to 90
         put "unlock: secret opens it; permissions" && pdfPermissions(sDoc) & return after sShowLog
      end if
   else if pStep >= 140 then
      return false
   end if
   return true
end pvSceneUnlock

-- The password bar, pDX pixels to the side of where it lives.
private command pvLockPlace pDX
   set the rect of graphic "lock:bg" to pvMoved(kPvLockBg, pDX)
   set the rect of field "lock:msg" to pvMoved(kPvLockMsg, pDX)
   set the rect of field "lock:pw" to pvMoved(kPvLockPw, pDX)
   set the rect of button "lock:go" to pvMoved(kPvLockGo, pDX)
end pvLockPlace

function pvMoved pRect, pDX
   return (item 1 of pRect + pDX) & comma & item 2 of pRect & comma & (item 3 of pRect + pDX) & comma & item 4 of pRect
end pvMoved

-- For a drive with no person at it: plays scene pScene (and with pAll the
-- scenes after it) to the end through the same frames, without the timer.
-- pUntil, when it is a frame number, stops the first scene there, mid-way:
-- a picture of a scene at work.
command pvShowRun pScene, pAll, pUntil
   local tMore, tGuard
   set the defaultStack to the short name of this stack
   pvPlay pScene, pAll, false
   put 0 into tGuard
   repeat while sShow > 0 and tGuard < 5000
      add 1 to tGuard
      put pvShowFrame() into tMore
      if pUntil is an integer and sShowStep >= pUntil then
         exit repeat
      end if
      if tMore is false then
         get pvShowNext()
      end if
   end repeat
end pvShowRun

-- The scene playing and its frame, and whether the tour is on.
function pvShowNow
   return sShow & comma & sShowStep & comma & sShowAll
end pvShowNow

function pvShowLog
   return sShowLog
end pvShowLog
