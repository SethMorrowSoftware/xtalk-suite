script "pdfxtDemo"

-- pdfxt-demo.livecodescript - the pdfxt showcase: a PDF viewer in one window.
--
-- It opens a PDF from a file, or from bytes this script carries (the
-- sample, a five-page guide, and a locked page whose password is secret),
-- and shows all of what the library does: a page drawn whole or, zoomed in,
-- only the part in view; the outline; the links (one inside the document is
-- followed, a web address is shown and opened only if you ask); search, with
-- every match marked on the page; the text of a page, of a box you drag out
-- and of the word you click; the document's information and permissions; the
-- drawing flags; a page saved as a BMP picture. The Checks tab runs every
-- check in one click.
--
-- HOW TO USE (requires the pdfxt extension, org.openxtalk.library.pdfxt,
-- with its PDFium library beside it, as the package installs them): paste
-- this into a stack's script, then close and reopen that stack (or `send
-- "preOpenStack" to <that stack>` without closing). Opening this file itself
-- loads the script and builds no window - that is the engine, not this demo:
-- docs/OXT-ENGINE-NOTES.md 5.5. pdfxt has no browser build, so this stack
-- runs where the desktop libraries do.
--
-- Conventions: pages and characters count from 1; sizes and rectangles are
-- in points (1/72 inch) from the TOP LEFT of the page as displayed. A call
-- that cannot do what it was asked returns 0 or empty and never throws;
-- pdfLastError() says why.
--
-- HONESTY (the suite convention): see the footer line this stack paints,
-- which is kept true to what has run.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; the drift gate holds every copy
-- byte-identical). Change the look in the master, never here. The two PDFs
-- are carried between their own marker lines, which tools/build-test-pdfs.py
-- writes (its --check is one of the member's gates).

-- Bump when the generated UI changes so a saved stack rebuilds its controls.
constant kPvUiVersion = "pdfxt-kit2-1"
constant kPvWidth = 1180
constant kPvHeight = 630
-- The page view on the card: the drawn part of the page sits inside it, the
-- two scroll bars outside it (right and below).
constant kPvViewL = 16
constant kPvViewT = 92
constant kPvViewR = 760
constant kPvViewB = 564
-- The side panel's tabs, in order: key, then the label on its button.
constant kPvTabs = "out,find,txt,lnk,draw,info,chk"
constant kPvTabLabels = "Outline,Search,Text,Links,Draw,Info,Checks"
-- The zooms + and - step through, in percent of a point to a pixel.
constant kPvZooms = "25,50,75,100,125,150,200,300,400,600,800"
-- A stranger's file can hold any number of matches, links and outline
-- entries; the window shows at most these.
constant kPvHits = 60
constant kPvLinkMax = 30
constant kPvFindMax = 300
constant kPvOutlineMax = 2000
-- The Draw tab's boxes, and the flag each one adds to every drawing.
constant kPvFlagBoxes = "draw:annots,draw:lcd,draw:gray,draw:print,draw:smooth"
constant kPvFlagValues = "1,2,8,2048,28672"

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
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
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
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
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
-- ---- contextual menus -------------------------------------------------------
--
-- A RIGHT-CLICK MENU, as one hidden popup button per menu.
--
-- The engine's contextual menu is a BUTTON whose style is "menu" and whose
-- menuMode is "popup": its text is the item list, one per line, `popup`
-- shows it at a point, and choosing an item sends `menuPick` with the item's
-- LABEL. The button needs no script - with no handler of its own the message
-- walks the hierarchy and arrives at the card and then the stack, which is
-- where an adopter's router already lives.
--
-- OPT-IN, AND THAT IS DELIBERATE. This block is carried byte-identical by
-- every demo in the suite, so a kit that BUILT a menu would change eighteen
-- stacks to serve one. Nothing here runs unless an adopter calls
-- uiContextMenu, and a demo that never does is unchanged in behaviour.
--
-- NONE OF THIS HAS RUN ON AN ENGINE. `popup`, `menuMode` and `menuPick` are
-- documented LiveCode and OpenXTalk is a fork of it, but this suite has never
-- exercised a menu and the headless runners model no mouse button at all - so
-- an adopter's right-click handler belongs in a `try`, and losing the menu
-- must never cost the ordinary click. uiPopupMenu answers whether it worked
-- rather than throwing, so the caller can decide.

command uiContextMenu pName, pItems
   -- One hidden popup button, created once and refilled on every call so a
   -- menu can change with the screen it belongs to. The rect is small and
   -- inside the window because a stack's controls are measured by
   -- tools/check-stack-size.py whether they are visible or not.
   if there is no button pName then
      -- THE KIT'S OWN IDIOM, and not `create button pName`. Every other
      -- builder in this block creates the control unnamed and then names the
      -- last one, which is the spelling the family's headless runners model
      -- and the one every adopter has already been through an engine with.
      create button
      set the name of the last button to pName
   end if
   set the style of button pName to "menu"
   set the menuMode of button pName to "popup"
   set the text of button pName to pItems
   set the rect of button pName to "2,2,18,18"
   set the visible of button pName to false
end uiContextMenu

function uiPopupMenu pName
   -- WHICH menu, recorded before it opens. menuPick carries the item's label
   -- and nothing else, so an adopter with two menus would otherwise have to
   -- keep every label in the stack globally unique - a constraint that is
   -- invisible until the day two screens both want "Copy".
   --
   -- Answers true or false rather than throwing: on an engine without popup
   -- menus the right thing is for the click to do nothing, not for the
   -- adopter's mouseDown to die.
   local tError
   if there is no button pName then
      return false
   end if
   set the uUiMenu of this stack to pName
   try
      popup button pName at the clickLoc
   catch tError
      set the uUiMenu of this stack to empty
      return false
   end try
   return true
end uiPopupMenu

function uiMenuSource
   -- The name of the menu the last menuPick came from.
   return the uUiMenu of this stack
end uiMenuSource

-- ==== SUITE UI KIT v2 END ====

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
   end if
   pvBuildUI
   pvShowTab "out"
   if pvReady() then
      if sDoc is 0 then
         uiStatus "Ready (" & pdfLibraryVersion() & "). Open a PDF, or click The sample.", "ok"
      end if
   end if
   pvShowDocument
end preOpenStack

on closeStack
   -- Only this window's own document is closed. pdfShutdown would close
   -- every document of every stack in this engine, since PDFium is loaded
   -- once per process; the Checks tab calls it, and says so.
   pvCloseDocument
end closeStack

-- ==========================================================================
-- UI construction. Every generated control is named "prefix:role": "tb" the
-- toolbar, "view" the page and its marks, "lock" the password bar, "side"
-- the tab buttons, "ui" the chrome, and each tab's key its own controls. So
-- one loop shows a tab and one handler routes a click.
-- ==========================================================================

on pvBuildUI
   local tIndex, tKey, tLeft, tTop, tN
   -- Version-guarded rebuild: a saved stack keeps its controls, so only a
   -- kit or layout bump (kPvUiVersion) rebuilds them.
   if the uPvUiVersion of this stack is kPvUiVersion and there is a button "side:out" then
      exit pvBuildUI
   end if
   pvClearUI
   lock screen
   -- About a hundred controls are made here; with messages locked the IDE
   -- is not told of each one (engine note 5.15).
   lock messages
   -- 1180 x 630 is held by tools/check-stack-size.py (every window fits 720p).
   uiChrome "pdfxt - PDF pages, text, search and outline", kPvWidth, kPvHeight

   uiButton "tb:open", "Open a PDF...", "16,58,124,84"
   uiButton "tb:sample", "The sample", "130,58,222,84"
   uiButton "tb:locked", "Locked sample", "228,58,340,84"
   uiButton "tb:close", "Close", "346,58,404,84"
   uiButton "tb:prev", "<", "424,58,452,84"
   uiInput "tb:page", "456,58,500,84"
   uiLabel "tb:of", empty, "504,62,556,82", 11
   uiButton "tb:next", ">", "558,58,586,84"
   uiButton "tb:out", "-", "604,58,632,84"
   uiLabel "tb:zoom", empty, "634,62,688,82", 11
   set the textAlign of field "tb:zoom" to "center"
   uiButton "tb:in", "+", "690,58,718,84"
   uiButton "tb:fitp", "Fit page", "726,58,800,84"
   uiButton "tb:fitw", "Fit width", "806,58,884,84"
   uiLabel "tb:doc", empty, "896,62,1164,82", 11
   set the foregroundColor of field "tb:doc" to kUiInkSoft

   -- The page view: a desk, the drawn part of the page on it, then the marks
   -- drawn over the page (made after the image, so they sit in front of it),
   -- then the scroll bars. The marks are a fixed set made once and moved,
   -- never made and deleted per page.
   uiGfx "ui:desk", kPvViewL & comma & kPvViewT & comma & (kPvViewR + 16) & comma & (kPvViewB + 16)
   set the style of graphic "ui:desk" to "rectangle"
   set the filled of graphic "ui:desk" to true
   set the backgroundColor of graphic "ui:desk" to "206,212,222"
   set the lineSize of graphic "ui:desk" to 0
   if there is no image "view:page" then
      create image
      set the name of the last image to "view:page"
   end if
   set the rect of image "view:page" to "100,100,110,110"
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
   pvBar "view:vs", kPvViewR & comma & kPvViewT & comma & (kPvViewR + 16) & comma & kPvViewB
   pvBar "view:hs", kPvViewL & comma & kPvViewB & comma & kPvViewR & comma & (kPvViewB + 16)
   uiWrap "view:hint", "Open a PDF, or click The sample: a five-page guide this window carries.", "104,300,688,340", 13
   set the textAlign of field "view:hint" to "center"
   set the foregroundColor of field "view:hint" to kUiInkSoft

   -- The password bar, over the top of the view while a document waits for
   -- its password (no page is shown then).
   uiGfx "lock:bg", "24,96,752,126"
   set the filled of graphic "lock:bg" to true
   set the backgroundColor of graphic "lock:bg" to kUiCard
   set the foregroundColor of graphic "lock:bg" to kUiCardLine
   set the lineSize of graphic "lock:bg" to 1
   uiLabel "lock:msg", empty, "32,101,440,121", 11
   uiInput "lock:pw", "444,98,600,124"
   uiButton "lock:go", "Unlock", "606,98,690,124"
   pvShowLock false, false

   -- The side panel: a card behind seven tab buttons in two rows.
   uiPanel "ui:side", "788,92,1164,580"
   put 0 into tIndex
   repeat for each item tKey in kPvTabs
      add 1 to tIndex
      if tIndex <= 4 then
         put 798 + (tIndex - 1) * 90 into tLeft
         put 100 into tTop
      else
         put 798 + (tIndex - 5) * 90 into tLeft
         put 128 into tTop
      end if
      uiButton "side:" & tKey, item tIndex of kPvTabLabels, tLeft & comma & tTop & comma & (tLeft + 86) & comma & (tTop + 24)
   end repeat
   pvBuildOutline
   pvBuildFind
   pvBuildText
   pvBuildLinks
   pvBuildDraw
   pvBuildInfo
   pvBuildChecks

   uiFooter \
         "PDFium (BSD 3-clause and Apache 2.0) draws and reads every page, through the pdfxt C shim. This window" \
         & " has been driven on OXT-Beyond's Linux engine without a display, every check green" \
         & " (tests/demo-drive.livecodescript); used by a person, it is verified statically; needs an OXT pass.", \
         "16,584,1164,626"
   unlock messages
   set the uPvUiVersion of this stack to kPvUiVersion
   unlock screen
end pvBuildUI

-- The rebuild's clear pass: a generated control's short name carries a
-- ":", while the kit's own chrome (uiTitle, uiStatus, uiBand, uiFooter) has
-- none - so the colon IS the ownership tag.
private command pvClearUI
   local tI
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
   unlock messages
   unlock screen
end pvClearUI

-- One mark of the page view: a rectangle, see-through by pBlend percent.
private command pvMark pName, pColor, pBlend, pLine
   uiGfx pName, "20,100,24,104"
   set the style of graphic pName to "rectangle"
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
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
   set the visible of scrollbar pName to false
end pvBar

-- A tick box: its tick and its words, with no button frame. The kit's tick
-- boxes are driven from script (autoHilite off), so mouseUp flips them.
private command pvTick pName, pLabel, pRect, pOn
   uiCheckbox pName, pLabel, pRect
   set the showBorder of button pName to false
   set the shadow of button pName to false
   set the opaque of button pName to false
   set the hiliteBorder of button pName to false
   set the threeD of button pName to false
   set the hilite of button pName to pOn
end pvTick

on pvBuildOutline
   uiLabel "out:h", empty, "798,160,1154,178", 11
   set the textStyle of field "out:h" to "bold"
   uiTable "out:list", "798,182,1154,546", "290"
   uiCap "out:note", "pdfOutline: a level, a page and a title for each entry. Click one to go there.", "798,550,1154,572"
end pvBuildOutline

on pvBuildFind
   uiInput "find:text", "798,162,1040,188"
   uiButton "find:go", "Find", "1046,161,1154,189"
   pvTick "find:case", "Capitals must match", "798,194,970,214", false
   pvTick "find:words", "Whole words", "976,194,1154,214", false
   uiLabel "find:sum", empty, "798,218,1154,236", 11
   uiTable "find:list", "798,240,1154,540", "52"
   set the dontWrap of field "find:list" to true
   uiButton "find:prev", "Previous", "798,546,900,572"
   uiButton "find:next", "Next", "906,546,1008,572"
end pvBuildFind

on pvBuildText
   uiLabel "txt:h", empty, "798,160,1154,178", 11
   set the textStyle of field "txt:h" to "bold"
   uiArea "txt:page", "798,182,1154,392"
   uiLabel "txt:hs", empty, "798,398,1154,416", 11
   set the textStyle of field "txt:hs" to "bold"
   uiArea "txt:sel", "798,420,1154,540"
   uiButton "txt:copy", "Copy", "798,546,900,572"
end pvBuildText

on pvBuildLinks
   pvTick "lnk:show", "Outline every link on the page", "798,162,1154,182", true
   uiLabel "lnk:h", empty, "798,188,1154,206", 11
   set the textStyle of field "lnk:h" to "bold"
   uiTable "lnk:list", "798,210,1154,420", empty
   set the dontWrap of field "lnk:list" to true
   uiArea "lnk:addr", "798,428,1154,480"
   uiButton "lnk:open", "Open it in the browser", "798,486,980,512"
   uiCap "lnk:note", "A link inside the document is followed when you click it. A web link's address" \
         & " was written by whoever made the file, so it is shown here first and opened only if you ask.", \
         "798,518,1154,572"
end pvBuildLinks

on pvBuildDraw
   uiLabel "draw:h", "Drawing flags (pFlags of every pdfRender call)", "798,160,1154,178", 11
   set the textStyle of field "draw:h" to "bold"
   pvTick "draw:annots", "Annotations and form fields (1)", "798,182,1154,202", false
   pvTick "draw:lcd", "Text sharpened for an LCD screen (2)", "798,204,1154,224", false
   pvTick "draw:gray", "Gray (8)", "798,226,1154,246", false
   pvTick "draw:print", "As for print (2048)", "798,248,1154,268", false
   pvTick "draw:smooth", "No smoothing of text, images or lines (28672)", "798,270,1154,290", false
   uiLabel "draw:lh", "The last drawing of the page", "798,298,1154,316", 11
   set the textStyle of field "draw:lh" to "bold"
   uiArea "draw:last", "798,320,1154,372"
   uiLabel "draw:th", "The page as a BMP file (pdfRenderPageBMP)", "798,380,1154,398", 11
   set the textStyle of field "draw:th" to "bold"
   if there is no image "draw:thumb" then
      create image
      set the name of the last image to "draw:thumb"
   end if
   set the rect of image "draw:thumb" to "798,404,898,504"
   uiButton "draw:save", "Save this page as a BMP...", "960,404,1154,430"
   uiCap "draw:note", "Saved at two pixels to the point (144 dots to the inch), with the flags above.", "960,436,1154,500"
end pvBuildDraw

on pvBuildInfo
   uiArea "info:area", "798,160,1154,572"
   set the tabStops of field "info:area" to "92"
   set the dontWrap of field "info:area" to false
end pvBuildInfo

on pvBuildChecks
   uiButton "chk:run", "Run every check", "798,162,950,188"
   uiLabel "chk:sum", "Not run yet.", "956,166,1154,186", 11
   uiCap "chk:note", "Every public pdf handler, over the two PDFs this window carries. They end by closing" \
         & " every document and shutting PDFium down (pdfCloseAll, pdfShutdown); the document shown here" \
         & " is opened again after.", "798,194,1154,240"
   uiArea "chk:log", "798,244,1154,572"
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
      -- nested, not joined with `and`: an image has no style to ask for, and
      -- `and` may ask both sides (engine note 2.5)
      if word 1 of the target is "button" then
         if the style of the target is "checkbox" then
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
-- engine's (a button's highlight, a field's caret).
on mouseDown pButton
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
         uiStatus "Closed. Open a PDF, or click The sample.", "muted"
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
      uiStatus "pdfxt is NOT loaded: install org.openxtalk.library.pdfxt and reopen this stack.", "bad"
      return false
   end try
   if pdfLoad(empty) is false then
      uiStatus "pdfxt is loaded, but its PDFium is not: " & pdfLastError(), "bad"
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
            uiStatus pvSourceName(pSource) & " is locked: type its password in the bar over the page.", "warn"
         else
            uiStatus "That password did not open " & pvSourceName(pSource) & ".", "warn"
         end if
      else
         pvShowLock false, false
         uiStatus "Could not open " & pvSourceName(pSource) & ": " & pdfLastError(), "bad"
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
   uiStatus "Opened " & pvSourceName(pSource) & ": " & sPages & " page(s), PDF " & (pdfFileVersion(tDoc) / 10) & ".", "ok"
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
      if pWrong then
         put "That password did not open it. Try again:" into field "lock:msg"
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
   uiStatus "No page is numbered or labelled " & quote & pText & quote & ".", "warn"
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
   local tW, tH, tViewW, tViewH, tIW, tIH, tData, tStart, tCall
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      lock screen
      set the visible of image "view:page" to false
      set the visible of scrollbar "view:hs" to false
      set the visible of scrollbar "view:vs" to false
      set the visible of field "view:hint" to (sWaiting is empty)
      put empty into field "tb:zoom"
      put empty into sLastDraw
      pvPaintMarks
      unlock screen
      exit pvRender
   end if
   put kPvViewR - kPvViewL into tViewW
   put kPvViewB - kPvViewT into tViewH
   put pdfPageWidth(sDoc, sPage) into tW
   put pdfPageHeight(sDoc, sPage) into tH
   if tW <= 0 or tH <= 0 then
      uiStatus "Page " & sPage & " has no size: " & pdfLastError(), "bad"
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
   else
      put pdfRenderPageRegion(sDoc, sPage, sZoomW, sZoomH, sScrollX, sScrollY, tIW, tIH, sFlags) into tData
      put "pdfRenderPageRegion: a window of" && tIW && "x" && tIH && "pixels at" && sScrollX & comma & sScrollY \
            && "of the" && sZoomW && "x" && sZoomH && "page" into tCall
   end if
   put the milliseconds - tStart into tStart
   if tData is empty then
      set the visible of image "view:page" to false
      uiStatus "Page " & sPage & " could not be drawn: " & pdfLastError(), "bad"
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
   pvSyncBars
   pvPaintMarks
   unlock screen
end pvRender

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
      uiStatus "No text at that point of the page.", "muted"
      pvPaintMarks
      exit pvClickAt
   end if
   put pdfPageCharBox(sDoc, sPage, tIndex) into sCharRect
   put pvWordAt(tIndex) into tWord
   put "Clicked at" && pvNum(pX) & comma & pvNum(pY) && "points" into field "txt:hs"
   put "Character" && tIndex && "of" && pdfPageCharCount(sDoc, sPage) & ":" && quote & pdfPageTextRange(sDoc, sPage, tIndex, 1) & quote & return \
         & "its box (pdfPageCharBox):" && sCharRect & return & "the word it is in:" && tWord into field "txt:sel"
   uiStatus "Character" && tIndex && "is in the word" && quote & tWord & quote & ": the Text tab has the rest.", "ok"
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
      uiStatus "No text inside that box.", "muted"
   else
      put tText into field "txt:sel"
      uiStatus "Read" && the number of chars of tText && "characters from the box: the Text tab shows them.", "ok"
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
      uiStatus "A link inside the document: this is page" && tPage & pvLabelNote(tPage) & ".", "ok"
   else if tAddress is not empty then
      put tAddress into sAddress
      put "This link leads to" & return & tAddress into field "lnk:addr"
      pvShowTab "lnk"
      uiStatus "A web link: its address is in the Links tab. Nothing was opened.", "warn"
   end if
end pvFollow

command pvOpenAddress
   if sAddress begins with "https://" or sAddress begins with "http://" then
      launch url sAddress
      uiStatus "Asked the system to open" && sAddress & ".", "ok"
   else if sAddress is empty then
      uiStatus "Click a web link on the page first: its address shows here before anything opens.", "warn"
   else
      uiStatus "Only an http or https address is opened from here.", "warn"
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
      uiStatus "Outline: went to page" && tPage & pvLabelNote(tPage) & ".", "ok"
   else
      uiStatus "That entry leads outside this document: pdfOutline gives it page 0.", "warn"
   end if
end pvOutlineClick

-- ==========================================================================
-- Search.
-- ==========================================================================

command pvFind
   local tNeedle, tFlags, tPage, tHits, tLine, tCount, tPages, tList, tFrom, tContext, tLabel, tMore
   set the defaultStack to the short name of this stack
   if sDoc is 0 then
      uiStatus "Open a PDF first, then search it.", "warn"
      exit pvFind
   end if
   put field "find:text" into tNeedle
   if tNeedle is empty then
      uiStatus "Type a word to find.", "warn"
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
      uiStatus quote & tNeedle & quote && "is not in this document.", "warn"
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
   uiStatus "Match" && pIndex && "of" && the number of lines of sFinds & ", on page" && tPage & pvLabelNote(tPage) & ".", "ok"
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
   uiCopyFlash "txt:copy"
end pvCopy

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
   set the topLeft of image "draw:thumb" to "798,404"
   set the visible of image "draw:thumb" to (sTab is "draw")
end pvFillDraw

command pvAskSave
   local tPath
   if sDoc is 0 then
      uiStatus "Open a PDF first.", "warn"
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
      uiStatus "The page could not be drawn: " & pdfLastError(), "bad"
      exit pvSaveBMP
   end if
   put tBmp into URL ("binfile:" & pPath)
   if the result is not empty then
      uiStatus "Could not write " & pPath & ": " & the result, "bad"
      exit pvSaveBMP
   end if
   uiStatus "Saved page" && sPage && "as a" && trunc(tW * tScale) && "x" && trunc(tH * tScale) && "BMP:" && pPath, "ok"
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
      set the foregroundColor of field "chk:sum" to kUiOk
      uiStatus "Every check passed.", "ok"
   else
      put sCkPass && "passed," && sCkFail && "FAILED." into field "chk:sum"
      set the foregroundColor of field "chk:sum" to kUiBad
      uiStatus sCkFail && "check(s) failed: the failing lines begin with FAIL.", "bad"
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
