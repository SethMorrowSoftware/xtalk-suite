-- dial-example.livecodescript - dial a host through Tor's SOCKS5 proxy.
--
-- Example glue, NOT the library. It assumes onionxt.livecodescript is already in
-- the message path (for example: start using stack "onionxt") and that a field
-- named "response" exists to show the reply. See README.md.
--
-- OnionXT does not encrypt: the plain HTTP below is fine for a demo, but a real
-- protocol should seal its bytes with SodiumXT before oxWrite and open them
-- after the "data" event.

local sStream
local sHost

on onDialOnion
   -- DuckDuckGo's onion, a stable service that serves bytes over Tor.
   put "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion" into sHost
   startDial 9050
end onDialOnion

on onDialClearnet
   -- A clearnet name is resolved inside Tor too (ATYP=3), never locally.
   put "example.com" into sHost
   startDial 9050
end onDialClearnet

private command startDial pSocksPort
   put empty into field "response"
   oxSetSocksPort pSocksPort           -- 9050 system tor, 9150 Tor Browser
   oxSetCallbackOwner the long id of me
   oxDial sHost, 80
   put the result into sStream
   if sStream is not an integer then
      answer "Dial failed:" && sStream
      exit startDial
   end if
   oxSetStreamCallback sStream, "onStreamEvent"
end startDial

on onStreamEvent pStream, pEvent, pData
   if pEvent is "open" then
      -- The SOCKS tunnel is live. Send a minimal HTTP/1.0 request. Build CRLF as
      -- explicit bytes so the wire framing does not depend on the crlf constant,
      -- and textEncode the request so it is written as bytes, not engine UTF-16.
      local tEol, tRequest
      put numToChar(13) & numToChar(10) into tEol
      put "GET / HTTP/1.0" & tEol into tRequest
      put "Host:" && sHost & tEol after tRequest
      put "Connection: close" & tEol & tEol after tRequest
      oxWrite pStream, textEncode(tRequest, "UTF-8")
   else if pEvent is "data" then
      -- Raw inbound bytes; decode for display only (your protocol frames them).
      put textDecode(pData, "UTF-8") after field "response"
   else if pEvent is "closed" then
      put return & "-- connection closed --" after field "response"
   else if pEvent is "error" then
      answer "Stream error:" && pData
   end if
end onStreamEvent
