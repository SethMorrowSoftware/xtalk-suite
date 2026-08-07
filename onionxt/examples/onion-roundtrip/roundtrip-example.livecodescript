-- roundtrip-example.livecodescript - two-instance onion round trip.
--
-- Example glue, NOT the library. Load onionxt.livecodescript AND sodiumxt into
-- the message path first. Run startServiceA in one instance and dialServiceB in
-- another (see README.md). The sx* calls are SodiumXT and are illustrative:
-- OnionXT adds no crypto, it only transports the sealed bytes.
--
-- sSharedKey stands in for a key both sides hold (from key agreement or a pinned
-- contact in a real app, never a hardcode). The exact sx* API is SodiumXT's.

local sService
local sStream
local sSharedKey

-- ===================== Role A: publish and accept ==========================

on startServiceA
   put demoSharedKey() into sSharedKey
   oxSetControlPort 9051                 -- 9151 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxSetStatusCallback "onStatusA"
   oxSetPeerCallback "onPeerA"
   oxConnectControl                      -- completes asynchronously via onStatusA
end startServiceA

on onStatusA pKind, pInfo
   if pKind is "control" and pInfo is "authenticated" then
      -- Publish an ephemeral onion mapping virtual port 80 -> loopback 8080.
      oxCreateService 80, 8080
      put the result into sService
   else if pKind is "service" then
      put pInfo into field "myAddress"    -- our <56>.onion; share it with B
   else if pKind is "serviceReady" then
      put "reachable" into field "state"  -- descriptor uploaded; safe to dial now
   else if pKind is "bootstrap" then
      set the label of this stack to "Tor" && pInfo & "%"
   else if pKind is "control" and pInfo begins with "authfailed" then
      answer "Control auth failed:" && pInfo
   end if
end onStatusA

on onPeerA pStream, pService, pPeerAddr
   -- A peer reached our onion. The inbound stream behaves like a dialed one.
   oxSetStreamCallback pStream, "onServerStream"
end onPeerA

on onServerStream pStream, pEvent, pData
   if pEvent is "data" then
      -- pData is a SodiumXT-sealed request from B. Open it, act, seal the reply.
      local tPlain, tReply
      put sxSecretBoxOpen(pData, sSharedKey) into tPlain
      put sxSecretBox("pong:" & tPlain, sSharedKey) into tReply
      oxWrite pStream, tReply
   else if pEvent is "error" then
      answer "Inbound stream error:" && pData
   end if
end onServerStream

-- ===================== Role B: dial the service ============================

on dialServiceB pOnionAddress
   put demoSharedKey() into sSharedKey
   oxSetSocksPort 9050                   -- 9150 for Tor Browser
   oxSetCallbackOwner the long id of me
   oxDial pOnionAddress, 80
   put the result into sStream
   if sStream is not an integer then
      answer "Dial failed:" && sStream
      exit dialServiceB
   end if
   oxSetStreamCallback sStream, "onClientStream"
end dialServiceB

on onClientStream pStream, pEvent, pData
   if pEvent is "open" then
      -- The tunnel is live. Seal a message with SodiumXT and send it.
      oxWrite pStream, sxSecretBox("ping", sSharedKey)
   else if pEvent is "data" then
      answer "Reply from the onion:" && sxSecretBoxOpen(pData, sSharedKey)
   else if pEvent is "error" then
      answer "Stream error:" && pData
   end if
end onClientStream

-- ===================== shared demo helper ==================================

private function demoSharedKey
   -- A placeholder shared key. In a real app derive this from a key agreement or
   -- load a pinned contact key; do not hardcode a secret.
   return sxHashKey("onionxt-roundtrip-demo")
end demoSharedKey
