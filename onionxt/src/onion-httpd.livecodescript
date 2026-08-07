-- onion-httpd.livecodescript - a small, self-contained HTTP/1.1 server for Tor
-- onion services, built ENTIRELY on OnionXT's accept loop (oxCreateService).
--
-- WHY this instead of the engine's HTTPD Library: LiveCode's built-in HTTPD
-- Library is not present on every OpenXTalk engine (httpdStart raised "handler
-- not found" on-engine). This module needs nothing but OnionXT, which already
-- owns the socket, enforces loopback, and streams inbound bytes - the path the
-- main demo proved works. So it runs wherever OnionXT runs.
--
-- USAGE (in an app that has `start using` onionxt.livecodescript AND this file):
--   oxSetCallbackOwner the long id of me     -- your stack owns onStatus + routes
--   oxSetStatusCallback "onStatus"
--   oxhInit the long id of me                -- where your route handlers live
--   oxhSetRoot "/path/to/site"               -- optional: serve static files
--   oxhRoute "GET", "/hello", "myHello"      -- optional: a dynamic route
--   ... oxConnectControl, and when authenticated:
--   oxhServe 80, 8090                         -- publish an onion + serve HTTP on it
-- A route handler:  command myHello pStream, pRequest ; oxhReply pStream, 200, "hi",
--   "Content-Type: text/plain" ; end myHello
--
-- Public API: oxhInit / oxhServe / oxhSetRoot / oxhServeFiles / oxhRoute /
-- oxhUnroute / oxhReply / oxhStop.
-- It composes OnionXT (ox*); it adds no cryptography and owns no long-lived socket
-- of its own (OnionXT does). Public API `oxhCamelCase`, matching the family style.

constant kOxhCloseDelay = 500     -- ms to let the response flush before closing
constant kOxhMaxRequest = 262144  -- refuse a request head bigger than 256 KB (abuse guard)

local sOxhRoot        -- static-file root folder, or empty
local sOxhAutoIndex   -- true: auto-generate a directory-listing page for folders
local sOxhRoutes      -- array: (METHOD & space & path) -> handler name
local sOxhReq         -- array: stream handle -> accumulated request bytes
local sOxhServed      -- array: stream handle -> true once answered
local sOxhOwner       -- object whose script holds the route handlers

-- ==========================================================================
-- Public API
-- ==========================================================================

command oxhInit pOwner
   -- Remember where the app's route handlers live (default: the topStack).
   put pOwner into sOxhOwner
end oxhInit

command oxhServe pVirtualPort, pLocalPort
   -- Publish an onion and serve HTTP on it via OnionXT's accept loop (OnionXT owns
   -- the socket and rejects non-loopback peers - the proven path). Point OnionXT's
   -- peer callback at this module first, then create the service. Reports the
   -- service handle through `the result` (an integer on success).
   oxSetPeerCallback "oxhPeer"
   oxCreateService pVirtualPort, pLocalPort
   return the result
end oxhServe

command oxhSetRoot pFolder
   -- Static-site mode: serve files from pFolder ("/" maps to /index.html); a folder
   -- with no index.html is a 404 (no directory listing - the safe default for a
   -- site). Empty disables static serving.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put false into sOxhAutoIndex
end oxhSetRoot

command oxhServeFiles pFolder
   -- File-sharing mode: serve every file under pFolder by path AND auto-generate a
   -- directory-listing page (names, sizes, download links) for "/" and each
   -- subfolder, so a visitor can browse and download without you writing an index.
   -- A folder's own index.html, if present, still takes precedence over the listing.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put true into sOxhAutoIndex
end oxhServeFiles

command oxhRoute pMethod, pPath, pHandler
   -- Register a dynamic route (exact path match in v1). pHandler is a command in
   -- the owner's script, called as: pHandler pStream, pRequest.
   put pHandler into sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhRoute

command oxhUnroute pMethod, pPath
   -- Remove a route registered with oxhRoute. Lets an app switch what a path serves
   -- at runtime (e.g. drop the "/" route so a shared folder's listing shows there
   -- instead). Removing an unregistered route is a harmless no-op.
   delete variable sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhUnroute

command oxhStop pService
   -- Tear down one served onion (DEL_ONION + stop OnionXT's listener).
   oxRemoveService pService
end oxhStop

command oxhReply pStream, pCode, pBodyText, pHeaders
   -- Send a text response (HTML, JSON, plain) from a route handler. pBodyText is
   -- TEXT; it is UTF-8 encoded and its exact byte length becomes Content-Length.
   oxhSendBytes pStream, pCode, textEncode(pBodyText, "UTF-8"), pHeaders
end oxhReply

-- ==========================================================================
-- OnionXT callbacks (public: reached through the message path). OnionXT has
-- already enforced loopback before oxhPeer fires.
-- ==========================================================================

command oxhPeer pStream, pService, pPeerAddr
   oxSetStreamCallback pStream, "oxhStream"
   put empty into sOxhReq[pStream]
   put false into sOxhServed[pStream]
end oxhPeer

command oxhStream pStream, pEvent, pData
   if pEvent is "data" then
      if sOxhServed[pStream] is true then
         exit oxhStream           -- already answered; ignore the rest of the request
      end if
      put pData after sOxhReq[pStream]
      if the number of bytes of sOxhReq[pStream] > kOxhMaxRequest then
         put true into sOxhServed[pStream]
         delete variable sOxhReq[pStream]     -- free the buffer now; do not hold it
         oxhSendBytes pStream, 413, textEncode("Request too large", "UTF-8"), "Content-Type: text/plain"
         exit oxhStream
      end if
      if oxhRequestComplete(sOxhReq[pStream]) then
         put true into sOxhServed[pStream]
         oxhHandle pStream, sOxhReq[pStream]
         delete variable sOxhReq[pStream]
      end if
   else if pEvent is "closed" or pEvent is "error" then
      delete variable sOxhReq[pStream]
      delete variable sOxhServed[pStream]
   end if
end oxhStream

-- ==========================================================================
-- Request framing and parsing. Byte discipline on the raw request; text ops only
-- on the decoded (ASCII) header block.
-- ==========================================================================

private function oxhHeaderEnd pData
   -- 1-indexed byte position of the first CR of the CRLFCRLF that ends the header
   -- block, or 0 if not present yet. No char/line on binary (gotcha): scan bytes.
   -- Bytes go into locals so the match is a single-line `if` (the static gate does
   -- not join `\` continuations, and a long condition would look unbalanced).
   local tN, tI, tB1, tB2, tB3, tB4
   put the number of bytes of pData into tN
   if tN < 4 then
      return 0
   end if
   repeat with tI = 1 to tN - 3
      put byteToNum(byte tI of pData) into tB1
      if tB1 is 13 then
         put byteToNum(byte (tI + 1) of pData) into tB2
         put byteToNum(byte (tI + 2) of pData) into tB3
         put byteToNum(byte (tI + 3) of pData) into tB4
         if tB2 is 10 and tB3 is 13 and tB4 is 10 then
            return tI
         end if
      end if
   end repeat
   return 0
end oxhHeaderEnd

private function oxhRequestComplete pData
   local tHeadEnd, tHeaders, tContentLen, tBodyStart, tHave
   put oxhHeaderEnd(pData) into tHeadEnd
   if tHeadEnd is 0 then
      return false             -- headers not fully received yet
   end if
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   put tHeaders["content-length"] into tContentLen
   if tContentLen is empty or tContentLen is not an integer then
      return true              -- no declared body (typical GET)
   end if
   put tHeadEnd + 4 into tBodyStart
   put (the number of bytes of pData) - tBodyStart + 1 into tHave
   return (tHave >= tContentLen)
end oxhRequestComplete

private function oxhParseHeaders pHeaderBytes
   -- pHeaderBytes is the ASCII header block (request line + header lines, no body).
   -- Returns an array: lowercased header names -> values, plus __method / __path /
   -- __query / __resource from the request line. Save and restore the delimiters.
   local tText, tSavedLD, tSavedID, tReqLine, tRes, tI, tLine, tColon, tName, tValue, tOut
   put textDecode(pHeaderBytes, "UTF-8") into tText     -- headers are ASCII
   put the lineDelimiter into tSavedLD
   put the itemDelimiter into tSavedID
   set the lineDelimiter to (numToChar(13) & numToChar(10))
   put line 1 of tText into tReqLine
   put word 1 of tReqLine into tOut["__method"]
   put word 2 of tReqLine into tOut["__resource"]
   set the itemDelimiter to "?"
   put item 1 of tOut["__resource"] into tOut["__path"]
   if the number of items of tOut["__resource"] > 1 then
      put item 2 to -1 of tOut["__resource"] into tOut["__query"]
   end if
   repeat with tI = 2 to the number of lines of tText
      put line tI of tText into tLine
      if tLine is empty then
         next repeat
      end if
      put offset(":", tLine) into tColon
      if tColon > 1 then
         put toLower(oxhTrim(char 1 to (tColon - 1) of tLine)) into tName
         put oxhTrim(char (tColon + 1) to -1 of tLine) into tValue
         put tValue into tOut[tName]
      end if
   end repeat
   set the lineDelimiter to tSavedLD
   set the itemDelimiter to tSavedID
   return tOut
end oxhParseHeaders

-- ==========================================================================
-- Routing: a registered route, else a static file, else 404.
-- ==========================================================================

private command oxhHandle pStream, pData
   local tHeadEnd, tHeaders, tKey, tBodyStart, tContentLen, tBodyEnd
   put oxhHeaderEnd(pData) into tHeadEnd
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   -- Attach the raw body bytes for a POST handler, CAPPED to the declared
   -- Content-Length. Without the cap, trailing or pipelined bytes in the same read
   -- would bleed into __body and a form/upload route would parse the next request
   -- as part of this body.
   put tHeadEnd + 4 into tBodyStart
   put tHeaders["content-length"] into tContentLen
   if tContentLen is an integer and tContentLen > 0 and (the number of bytes of pData) >= tBodyStart then
      put tBodyStart + tContentLen - 1 into tBodyEnd
      if tBodyEnd > the number of bytes of pData then
         put the number of bytes of pData into tBodyEnd   -- defensive clamp
      end if
      put byte tBodyStart to tBodyEnd of pData into tHeaders["__body"]
   else
      put empty into tHeaders["__body"]
   end if
   put toUpper(tHeaders["__method"]) & space & tHeaders["__path"] into tKey
   if sOxhRoutes[tKey] is not empty then
      dispatch sOxhRoutes[tKey] to oxhOwnerObject() with pStream, tHeaders
      exit oxhHandle
   end if
   if sOxhRoot is not empty and tHeaders["__method"] is "GET" then
      oxhServeStatic pStream, tHeaders["__path"]
      exit oxhHandle
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhHandle

private command oxhServeStatic pStream, pRawPath
   local tPath, tFile, tIndex
   put urlDecode(pRawPath) into tPath        -- %20 etc. -> real chars for disk mapping
   if tPath is empty then
      put "/" into tPath
   end if
   -- Path-traversal guard AFTER decoding (catches %2e%2e), before touching disk.
   if ".." is in tPath then
      oxhSendBytes pStream, 403, textEncode("Forbidden", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhServeStatic
   end if
   put sOxhRoot & tPath into tFile
   if there is a folder tFile then
      -- A folder URL must end in "/" so relative links in the listing resolve;
      -- redirect if it does not (send the browser back with the slash added).
      if the last char of tPath is not "/" then
         oxhSendBytes pStream, 301, empty, "Location: " & pRawPath & "/"
         exit oxhServeStatic
      end if
      put tFile & "index.html" into tIndex    -- tFile ends with "/" here
      if there is a file tIndex then
         oxhSendFile pStream, tIndex, "index.html"
      else if sOxhAutoIndex is true then
         oxhSendBytes pStream, 200, textEncode(oxhListingHtml(tFile, tPath), "UTF-8"), "Content-Type: text/html; charset=utf-8"
      else
         oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      end if
      exit oxhServeStatic
   end if
   if there is a file tFile then
      oxhSendFile pStream, tFile, tPath
      exit oxhServeStatic
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhServeStatic

private command oxhSendFile pStream, pDiskPath, pForMime
   -- Read a file as bytes and serve it with a MIME type from pForMime's extension.
   local tContent
   put url ("binfile:" & pDiskPath) into tContent
   if the result is not empty then
      oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhSendFile
   end if
   oxhSendBytes pStream, 200, tContent, "Content-Type: " & oxhMimeType(pForMime)
end oxhSendFile

private function oxhListingHtml pDiskFolder, pUrlPath
   -- Build a directory-listing page for pDiskFolder (a disk path ending in "/"),
   -- served at pUrlPath (a URL path ending in "/"). Uses `the files` / `the folders`
   -- (portable; `the detailedFiles` is not recognized on every OXT engine and is a
   -- compile-time "bad factor" there). Names are HTML-escaped (a file named
   -- "<script>" cannot inject) and path-encoded for the hrefs; links are relative
   -- to pUrlPath, so a subfolder link browses in and ".." goes up.
   local tSaved, tFiles, tFolders, tName, tOut
   put the defaultFolder into tSaved
   set the defaultFolder to pDiskFolder
   put the files into tFiles
   put the folders into tFolders
   set the defaultFolder to tSaved
   put "<!doctype html><html><head><meta charset='utf-8'><title>Shared files</title>" into tOut
   put "<style>body{font-family:system-ui,sans-serif;max-width:44em;margin:2em auto;padding:0 1em}h1{font-size:1.2em}ul{list-style:none;padding:0}li{padding:.3em 0;border-bottom:1px solid #eee}a{text-decoration:none}</style>" after tOut
   put "</head><body><h1>Shared files: " & oxhHtmlEscape(pUrlPath) & "</h1><ul>" after tOut
   if pUrlPath is not "/" then
      put "<li><a href='../'>.. (up)</a></li>" after tOut
   end if
   repeat for each line tName in tFolders
      if tName is "." or tName is ".." then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "/'>" & oxhHtmlEscape(tName) & "/</a></li>" after tOut
   end repeat
   repeat for each line tName in tFiles
      if tName is empty then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "'>" & oxhHtmlEscape(tName) & "</a></li>" after tOut
   end repeat
   put "</ul></body></html>" after tOut
   return tOut
end oxhListingHtml

-- ==========================================================================
-- Response building. The proven demo pattern: exact BYTE Content-Length,
-- Connection: close, then a delayed close so the write flushes cleanly.
-- ==========================================================================

private command oxhSendBytes pStream, pCode, pBodyBytes, pHeaders
   local tCrlf, tResp
   put (numToChar(13) & numToChar(10)) into tCrlf
   put "HTTP/1.1 " & pCode & space & oxhReason(pCode) & tCrlf into tResp
   if pHeaders is not empty then
      put oxhNormalizeHeaders(pHeaders) after tResp
   end if
   put "Content-Length: " & (the number of bytes of pBodyBytes) & tCrlf after tResp
   put "Connection: close" & tCrlf after tResp
   put tCrlf after tResp
   oxWrite pStream, (textEncode(tResp, "UTF-8") & pBodyBytes)
   send ("oxhClose " & pStream) to me in kOxhCloseDelay milliseconds
end oxhSendBytes

command oxhClose pStream
   -- Deferred, idempotent close of a served connection (public: reached via send).
   -- Clear BOTH per-stream tables here as the catch-all: oxCloseStream removes the
   -- OnionXT stream, so no later socketClosed/"closed" event will arrive to clean
   -- the HTTP state, and every response path (200/404/413/301/...) routes through
   -- oxhSendBytes which schedules this. A double-delete on the normal path is a
   -- harmless no-op.
   oxCloseStream pStream
   delete variable sOxhReq[pStream]
   delete variable sOxhServed[pStream]
end oxhClose

private function oxhNormalizeHeaders pHeaders
   -- Turn caller headers ("Name: value", LF- or CRLF-separated) into CRLF lines,
   -- dropping any Content-Length / Connection (this module sets those).
   local tCrlf, tSaved, tI, tLine, tOut, tLow
   put (numToChar(13) & numToChar(10)) into tCrlf
   put the lineDelimiter into tSaved
   set the lineDelimiter to lf
   put empty into tOut
   repeat with tI = 1 to the number of lines of pHeaders
      put line tI of pHeaders into tLine
      if the last char of tLine is (numToChar(13)) then
         delete the last char of tLine   -- tolerate CRLF-separated input
      end if
      if tLine is empty then
         next repeat
      end if
      put toLower(tLine) into tLow
      if tLow begins with "content-length" or tLow begins with "connection" then
         next repeat
      end if
      put tLine & tCrlf after tOut
   end repeat
   set the lineDelimiter to tSaved
   return tOut
end oxhNormalizeHeaders

-- ==========================================================================
-- Small helpers.
-- ==========================================================================

private function oxhMimeType pPath
   local tSaved, tExtn
   put the itemDelimiter into tSaved
   set the itemDelimiter to "."
   put toLower(the last item of pPath) into tExtn
   set the itemDelimiter to tSaved
   if tExtn is "html" or tExtn is "htm" then
      return "text/html; charset=utf-8"
   else if tExtn is "css" then
      return "text/css; charset=utf-8"
   else if tExtn is "js" then
      return "application/javascript; charset=utf-8"
   else if tExtn is "json" then
      return "application/json; charset=utf-8"
   else if tExtn is "txt" then
      return "text/plain; charset=utf-8"
   else if tExtn is "png" then
      return "image/png"
   else if tExtn is "jpg" or tExtn is "jpeg" then
      return "image/jpeg"
   else if tExtn is "gif" then
      return "image/gif"
   else if tExtn is "svg" then
      return "image/svg+xml"
   else if tExtn is "ico" then
      return "image/x-icon"
   else if tExtn is "wasm" then
      return "application/wasm"
   else if tExtn is "pdf" then
      return "application/pdf"
   end if
   return "application/octet-stream"
end oxhMimeType

private function oxhReason pCode
   if pCode is 200 then
      return "OK"
   else if pCode is 204 then
      return "No Content"
   else if pCode is 301 then
      return "Moved Permanently"
   else if pCode is 302 then
      return "Found"
   else if pCode is 400 then
      return "Bad Request"
   else if pCode is 403 then
      return "Forbidden"
   else if pCode is 404 then
      return "Not Found"
   else if pCode is 405 then
      return "Method Not Allowed"
   else if pCode is 413 then
      return "Payload Too Large"
   else if pCode is 500 then
      return "Internal Server Error"
   end if
   return "OK"
end oxhReason

private function oxhTrim pText
   -- Strip leading/trailing spaces and tabs. Guard the empty-string-is-in trap.
   local tOut, tTab
   put pText into tOut
   put numToChar(9) into tTab
   repeat while tOut is not empty and (the first char of tOut is space or the first char of tOut is tTab)
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut is space or the last char of tOut is tTab)
      delete the last char of tOut
   end repeat
   return tOut
end oxhTrim

private function oxhOwnerObject
   if sOxhOwner is not empty then
      return sOxhOwner
   end if
   return the topStack
end oxhOwnerObject

private function oxhStripTrailingSlash pFolder
   local tOut
   put pFolder into tOut
   if tOut is not empty and (the last char of tOut is "/" or the last char of tOut is "\") then
      delete the last char of tOut
   end if
   return tOut
end oxhStripTrailingSlash

private function oxhPathEncode pName
   -- Encode a name for a URL PATH segment. urlEncode uses "+" for space (form
   -- style); a path wants "%20", so fix that up.
   local tEnc
   put urlEncode(pName) into tEnc
   replace "+" with "%20" in tEnc
   return tEnc
end oxhPathEncode

private function oxhHtmlEscape pText
   -- Escape a value for HTML text/attribute context so a crafted file name cannot
   -- inject markup. `&` first, then the rest.
   local tOut
   put pText into tOut
   replace "&" with "&amp;" in tOut
   replace "<" with "&lt;" in tOut
   replace ">" with "&gt;" in tOut
   replace quote with "&quot;" in tOut
   return tOut
end oxhHtmlEscape
