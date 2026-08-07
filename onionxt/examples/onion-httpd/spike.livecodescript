-- spike.livecodescript - share a folder of files over Tor, from OpenXTalk.
--
-- Pick a folder, and every file in it is served at a private <56>.onion address
-- with an auto-generated directory-listing page (names, sizes, download links,
-- browse into subfolders). Built entirely on OnionXT's accept loop via the
-- onion-httpd.livecodescript module (oxh*) - no engine-shipped HTTPD Library, so
-- it runs wherever OnionXT runs.
--
-- HOW TO RUN: make a new mainstack, set its stack script to this file, and put
-- BOTH src/onionxt.livecodescript AND src/onion-httpd.livecodescript in the
-- message path (start using them as libraries). Have a tor daemon with the
-- control port enabled (OnionXT README Troubleshooting). Click Start, then Share
-- Folder and pick a folder; wait for REACHABLE, then open the printed
-- http://<address>.onion/ in Tor Browser to browse and download the files.

constant kVirtualPort = 80       -- the onion's public port (URL needs no :port)
constant kLocalPort = 8090       -- loopback forward port (8080 is often reserved)
constant kControlPort = 9051     -- system tor control port (Tor Browser: 9151)
constant kSocksPort = 9050

local sSvcHandle
local sOnionAddress

on preOpenStack
   set the width of this stack to 660
   set the height of this stack to 440
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatus"
   oxhInit the long id of me
   demoBuildUI
   pass preOpenStack
end preOpenStack

on onStatus pKind, pInfo
   if pKind is "control" then
      if pInfo is "authenticated" then
         demoLog "control authenticated - now click 'Share Folder' and pick a folder"
      else if pInfo begins with "authfailed" or pInfo begins with "error" then
         demoLog "control error: " & pInfo
      else
         demoLog "control: " & pInfo
      end if
   else if pKind is "service" then
      put pInfo into sOnionAddress
      put "http://" & pInfo & "/" into field "demo:url"
      demoLog "onion address: " & pInfo
   else if pKind is "serviceReady" then
      demoLog "REACHABLE - open  http://" & sOnionAddress & "/  in Tor Browser to browse the files"
   end if
end onStatus

private command demoShareFolder
   local tFolder
   answer folder "Choose a folder to share over Tor"
   put it into tFolder
   if tFolder is empty then
      exit demoShareFolder       -- cancelled
   end if
   oxhServeFiles tFolder
   demoLog "sharing folder: " & tFolder
   if sSvcHandle is an integer then
      demoLog "(already published; the new folder is live at the same .onion)"
      exit demoShareFolder
   end if
   oxhServe kVirtualPort, kLocalPort
   put the result into sSvcHandle
   if sSvcHandle is an integer then
      demoLog "publishing the onion (port " & kVirtualPort & " -> 127.0.0.1:" & kLocalPort & ") ..."
   else
      demoLog "serve failed: " & sSvcHandle
   end if
end demoShareFolder

-- Minimal UI + lifecycle.
private command demoBuildUI
   create button "demo:start"
   set the rect of button "demo:start" to "24,20,150,52"
   set the label of button "demo:start" to "Start"
   create button "demo:share"
   set the rect of button "demo:share" to "162,20,318,52"
   set the label of button "demo:share" to "Share Folder"
   create button "demo:stop"
   set the rect of button "demo:stop" to "330,20,456,52"
   set the label of button "demo:stop" to "Stop"
   create field "demo:url"
   set the rect of field "demo:url" to "24,64,636,90"
   set the lockText of field "demo:url" to true
   set the opaque of field "demo:url" to true
   set the textFont of field "demo:url" to "Courier"
   set the dontWrap of field "demo:url" to true
   put "(the .onion URL will appear here once published)" into field "demo:url"
   create field "demo:out"
   set the rect of field "demo:out" to "24,102,636,416"
   set the lockText of field "demo:out" to true
   set the opaque of field "demo:out" to true
   set the textFont of field "demo:out" to "Courier"
   set the vScrollbar of field "demo:out" to true
   put empty into field "demo:out"
end demoBuildUI

on mouseUp
   local tName
   put the short name of the target into tName
   if tName is "demo:start" then
      demoStart
   else if tName is "demo:share" then
      demoShareFolder
   else if tName is "demo:stop" then
      demoStop
   end if
end mouseUp

private command demoStart
   local tErr
   put empty into field "demo:out"
   put empty into sOnionAddress
   demoLog "connecting to the tor control port 127.0.0.1:" & kControlPort & " ..."
   oxSetControlPort kControlPort
   oxSetSocksPort kSocksPort
   oxConnectControl
   put the result into tErr
   if tErr is not empty then
      demoLog "control connect error: " & tErr
   end if
end demoStart

private command demoStop
   if sSvcHandle is an integer then
      oxhStop sSvcHandle
      put empty into sSvcHandle
      demoLog "onion removed"
   end if
   oxDisconnectControl
end demoStop

on closeStack
   demoStop
   oxShutdown
   pass closeStack
end closeStack

private command demoLog pText
   put pText & return after field "demo:out"
   set the scroll of field "demo:out" to the formattedHeight of field "demo:out"
end demoLog
