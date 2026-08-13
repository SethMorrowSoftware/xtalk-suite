script "riptideSocial"

-- riptide-social.livecodescript - the Riptide Social flagship stack, phases
-- 1-2: one identity, one public feed, one follow, on one self-building card.
--
-- WHAT IT WALKS (RIPTIDE-SOCIAL-SPEC.md sections 10.3 phases 1-2): create or
-- unlock the Argon2id-sealed master seed (RIPTKEY1, a 97-byte file the APP
-- owns - the library does no file I/O), derive the identity, show the same
-- key as its two spellings (the 64-hex handle the feed publishes under, and
-- the .onion address), then publish signed posts + a signed BEP44 head over
-- the real DHT, and follow another author: fetch their head, walk the post
-- chain back to the zero target, and show every authorSig verdict.
--
-- HONESTY (the suite convention): this stack is verified statically and
-- NEEDS an OXT pass. The library underneath is engine-passed (2026-08-12,
-- 133/133) and its publish/lookup calls ran against a real session there -
-- but the EVENT half (btPoll delivering dhtMutableItem/dhtImmutableItem into
-- the ingest verifiers) has only ever run against synthetic events, so this
-- stack is the first thing that can close that loop. And a ONE-machine run
-- does not prove propagation: phase 2's done-criterion is a SECOND machine
-- walking the chain and verifying every authorSig (runbook item 6). Running
-- publisher and follower on one machine is the honest half-result.
--
-- SETUP: install sodiumxt (REQUIRED - identity cannot exist without it) and
-- torrentxt (required for publish/fetch; identity still works without), then
-- put the riptide script library in the message path before opening:
--
--    start using stack "riptide"
--
-- ONE SESSION PER PROCESS (torrentxt's rule, runbook trap 5.1): this stack
-- takes THE TorrentXT session. Close every other torrent-flavoured stack
-- first, and restart OXT before re-pasting this script - a recompile orphans
-- the session for the rest of the engine launch.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; tools/check-ui-kit-drift.py holds
-- every copy byte-identical). Change the look in the master, never here.
--
-- SCOPE, said loudly: phases 3-7 are NOT here - no media torrents, no DMs
-- (rsInboxId / rsRoomId / rsDmSeed exist but are phase-4 fuel), no live
-- sessions, no LAN sync, no anonymous persona. Prekey and profile-meta head
-- fields are published EMPTY (phase-4 material). Public feeds are PUBLIC:
-- the DHT keeps records until expiry, there is no deletion, and nothing
-- here is anonymity (spec section 9).
--
-- KEYRING honesty: while unlocked, the identity seed lives in a script
-- local (the spec's one-keyring pattern) and OXT script memory is not
-- locked or reliably zeroed. Lock when done; never use a passphrase that
-- guards anything real in a demo.

-- ---- constants ---------------------------------------------------------------
constant kPollMs is 250
constant kDhtWaitMs is 25000
constant kWalkMax is 12
constant kNameMax is 64

-- ==== SUITE UI KIT v1 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg is "237,239,243"
constant kUiAccent is "44,90,160"
constant kUiAccentText is "255,255,255"
constant kUiOk is "20,120,40"
constant kUiWarn is "160,90,10"
constant kUiBad is "170,30,30"
constant kUiMuted is "90,96,110"
constant kUiMono is "Courier"

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

-- ---- state -------------------------------------------------------------------
local sCaps            -- rsProbeCapabilities() array, probed once at open
local sHaveLib         -- "true" once the riptide library answered at all
local sSession         -- THE TorrentXT session handle; this app owns it
local sIdSeed          -- identity seed Data(32) while unlocked (the keyring)
local sHandle          -- the identity's 64-hex public key
local sOnion           -- the identity as .onion (empty without a SHA3 provider)
local sSeq             -- monotonic head sequence (recovered from our own head)
local sMyLatest        -- our latest post's 40-hex target, or empty
local sPolling         -- "true" while the pump chain is armed
local sAwaitOwn        -- "true" while our own head lookup is in flight
local sFollowHandle    -- the author a fetch is walking
local sAwaitHead       -- "true" while their head lookup is in flight
local sWalkNext        -- the post target the walk is waiting on, or empty
local sWalkCount       -- posts verified so far in this walk
local sWaitUntil       -- ms deadline for the outstanding DHT request

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   raBuild
   raProbe
end openStack

on closeStack
   local tErr
   put empty into sPolling
   if sSession is an integer and sSession > 0 then
      try
         btStopSession sSession
      catch tErr
         -- extension gone or session already dead; nothing to release
      end try
   end if
   put empty into sSession
   raClearKeys
end closeStack

on mouseUp
   switch the short name of the target
      case "raCreate"
         raCreate
         break
      case "raUnlock"
         raUnlock
         break
      case "raLock"
         raLock
         break
      case "raPost"
         raPost
         break
      case "raFetch"
         raFetch
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; the kit owns the look) --------------------
command raBuild
   if there is a field "uiTitle" then
      exit raBuild
   end if
   lock screen
   uiChrome "Riptide Social - identity + public feed (phases 1-2)", 780, 940

   -- 1. identity
   uiSection "raSec1", "1. Identity: one sealed seed, two spellings of one key", "16,58,764,76"
   uiLabel "raIdL1", "key file:", "16,80,90,98", 11
   uiInput "raKeyFile", "94,80,560,100"
   put raKeyPath() into field "raKeyFile"
   uiButton "raCreate", "Create", "612,80,764,104"
   uiLabel "raIdL2", "passphrase:", "16,104,90,122", 11
   uiInput "raPassphrase", "94,104,560,124"
   uiButton "raUnlock", "Unlock", "612,108,684,132"
   uiButton "raLock", "Lock", "692,108,764,132"
   uiArea "raIdOut", "16,130,764,240"

   -- 2. my feed
   uiSection "raSec2", "2. My feed: post, then the signed head republishes", "16,246,764,264"
   uiLabel "raNameL", "display name:", "16,268,110,286", 11
   uiInput "raName", "114,268,340,288"
   put "riptide user" into field "raName"
   uiInput "raCompose", "16,292,600,340"
   uiButton "raPost", "Post", "612,292,764,316"
   uiArea "raMyFeed", "16,346,764,480"

   -- 3. follow
   uiSection "raSec3", "3. Follow: fetch a head, walk the chain, verify every signature", "16,486,764,504"
   uiLabel "raHandleL", "author handle (64 hex):", "16,508,180,526", 11
   uiInput "raHandle", "184,508,600,528"
   uiButton "raFetch", "Fetch feed", "612,508,764,532"
   uiArea "raTheirFeed", "16,538,764,830"

   uiFooter \
         "Phases 1-2 only: public feeds are public, the DHT keeps records" \
         & " until expiry, nothing here is deletion or anonymity. While" \
         & " unlocked, the identity seed lives in unlocked engine memory:" \
         & " Lock when done, and never reuse a real passphrase in a demo." \
         & " A one-machine run does not prove propagation - phase 2 is done" \
         & " when a SECOND machine walks this chain and verifies every" \
         & " authorSig.", \
         "16,838,764,926"
   unlock screen
end raBuild

-- ---- probes (fail closed, name the missing piece) ----------------------------
command raProbe
   local tErr
   put empty into sHaveLib
   try
      put rsProbeCapabilities() into sCaps
      put "true" into sHaveLib
   catch tErr
      -- library absent; reported below
   end try
   if sHaveLib is not "true" then
      uiStatus "Riptide library NOT in the message path: start using stack" && quote & "riptide" & quote & ".", "bad"
   else if sCaps["canCrypto"] is not true then
      uiStatus "SodiumXT missing, and identity cannot exist without it: install org.openxtalk.library.sodium.", "bad"
   else if sCaps["hasTorrent"] is not true then
      uiStatus "Offline mode (TorrentXT absent): identity works; publish and fetch are disabled.", "warn"
   else if sCaps["hasSha3"] is not true then
      uiStatus "Ready, minus the .onion spelling: no SHA3 provider is loaded (SodiumXT ABI 7 serves sxSha3_256; CoinXT's cxSha3_256 is the fallback).", "warn"
   else
      uiStatus "Ready: SodiumXT + TorrentXT + SHA3 all present.", "ok"
   end if
end raProbe

-- ---- 1. identity -------------------------------------------------------------
command raCreate
   local tPass, tPath, tFolder, tSeed, tSealed, tSaved, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot create an identity without the library and SodiumXT (see above).", "bad"
      exit raCreate
   end if
   put field "raPassphrase" into tPass
   if the number of chars of tPass < 8 then
      put "REFUSED: use a passphrase of at least 8 characters." & return into field "raIdOut"
      exit raCreate
   end if
   put field "raKeyFile" into tPath
   if there is a file tPath then
      put "REFUSED: a key file already exists at" && tPath & return \
            & "Unlock it, or point the key-file field somewhere new." & return into field "raIdOut"
      exit raCreate
   end if
   put false into tFailed
   try
      put rsGenerateMasterSeed() into tSeed
      if tSeed is empty then
         throw "rsGenerateMasterSeed:" && rsLastError()
      end if
      put rsSealMasterSeed(tSeed, tPass) into tSealed
      if tSealed is empty then
         throw "rsSealMasterSeed:" && rsLastError()
      end if
      -- the folder half of the write, itemDelimiter guarded (global state)
      put the itemDelimiter into tSaved
      set the itemDelimiter to "/"
      put item 1 to -2 of tPath into tFolder
      set the itemDelimiter to tSaved
      if tFolder is not empty and there is no folder tFolder then
         create folder tFolder
      end if
      put tSealed into url ("binfile:" & tPath)
      if there is no file tPath then
         throw "the key file did not write; check the path and permissions"
      end if
      put rsIdentitySeed(tSeed) into sIdSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tSeed
   put empty into tSealed
   if tFailed then
      put "Create failed:" && tErr & return into field "raIdOut"
      exit raCreate
   end if
   put "Identity CREATED and sealed (RIPTKEY1, Argon2id) at:" && tPath & return into field "raIdOut"
   put "Write the passphrase down; the seed cannot be recovered without it." & return after field "raIdOut"
   raIdentityReady
end raCreate

command raUnlock
   local tPass, tPath, tRaw, tMaster, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot unlock without the library and SodiumXT (see above).", "bad"
      exit raUnlock
   end if
   put field "raPassphrase" into tPass
   put field "raKeyFile" into tPath
   if there is no file tPath then
      put "REFUSED: no key file at" && tPath & return into field "raIdOut"
      exit raUnlock
   end if
   put false into tFailed
   try
      put url ("binfile:" & tPath) into tRaw
      put rsOpenMasterSeed(tRaw, tPass) into tMaster
      if tMaster is empty then
         throw rsLastError()
      end if
      put rsIdentitySeed(tMaster) into sIdSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tMaster
   put empty into tRaw
   if tFailed then
      put "Unlock failed:" && tErr & return into field "raIdOut"
      exit raUnlock
   end if
   put "Identity UNLOCKED from" && tPath & return into field "raIdOut"
   raIdentityReady
end raUnlock

-- The shared tail of create and unlock: derive the public spellings, start
-- the session, and recover our head sequence from the DHT rather than from
-- local guesswork (republishing under a LOWER seq than the network holds is
-- refused by BEP44, so the network's number is the truthful one).
command raIdentityReady
   local tOk
   put rsHandleFromSeed(sIdSeed) into sHandle
   put rsOnionFromHandle(sHandle) into sOnion
   put "handle (the key your feed publishes under):" & return & "  " & sHandle & return after field "raIdOut"
   if sOnion is empty then
      put "onion spelling: unavailable (no SHA3 provider; identity still works)" & return after field "raIdOut"
   else
      put "the SAME key as an onion identity:" & return & "  " & sOnion & return after field "raIdOut"
   end if
   put 0 into sSeq
   put empty into sMyLatest
   raStartSession
   if sSession is an integer and sSession > 0 then
      put rsRequestHead(sSession, sHandle) into tOk
      if tOk is true then
         put "true" into sAwaitOwn
         put the milliseconds + kDhtWaitMs into sWaitUntil
         put "recovering your head from the DHT (fresh identities start at seq 0)..." & return after field "raIdOut"
      end if
   else
      put "no session: posts stay disabled until TorrentXT is available." & return after field "raIdOut"
   end if
end raIdentityReady

command raLock
   raClearKeys
   put "LOCKED: the identity seed left memory. Unlock to publish again." & return into field "raIdOut"
end raLock

command raClearKeys
   put empty into sIdSeed
   put empty into sHandle
   put empty into sOnion
   put 0 into sSeq
   put empty into sMyLatest
   put empty into sAwaitOwn
end raClearKeys

-- ---- the session + the pump --------------------------------------------------
-- The app owns THE one TorrentXT session (the library never does), pumps
-- btPoll on one standing timer chain, and hands DHT events to the ingest
-- verifiers. Each drain rides a try: a throw out of the pump would break
-- the chain and orphan the session (runbook trap 5.1.1).
command raStartSession
   local tSession, tErr
   if sSession is an integer and sSession > 0 then
      exit raStartSession
   end if
   if sHaveLib is not "true" or sCaps["hasTorrent"] is not true then
      exit raStartSession
   end if
   try
      put btStartSession() into tSession
      if tSession > 0 then
         put tSession into sSession
         btSetBool sSession, "enable_dht", true
         btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
         btDhtAddBootstrap sSession, "router.utorrent.com", 6881
         btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
      end if
   catch tErr
      uiStatus "TorrentXT session failed:" && tErr, "bad"
   end try
   if sSession is an integer and sSession > 0 and sPolling is not "true" then
      put "true" into sPolling
      send "raPoll" to me in kPollMs milliseconds
   end if
end raStartSession

command raPoll
   local tEvents, tEvent, tErr
   if sPolling is not "true" then
      exit raPoll
   end if
   if sSession is an integer and sSession > 0 then
      try
         put btPoll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            raHandleEvent tEvent
         end repeat
      catch tErr
         -- one bad drain must not kill the chain; the next tick retries
      end try
   end if
   raExpire
   send "raPoll" to me in kPollMs milliseconds
end raPoll

-- The deadline half: the walk keys every request by the exact target it
-- awaits, so a DHT that never answers expires visibly instead of hanging.
command raExpire
   if the milliseconds <= sWaitUntil then
      exit raExpire
   end if
   if sAwaitOwn is "true" then
      put empty into sAwaitOwn
      put "no head found for your key (fresh identity, or not yet propagated); starting at seq 0." & return after field "raIdOut"
   end if
   if sAwaitHead is "true" then
      put empty into sAwaitHead
      put "the DHT did not answer for that head in time; try again in a minute (bootstrap takes a moment)." & return after field "raTheirFeed"
   end if
   if sWalkNext is not empty then
      put "the DHT did not answer for post target" && sWalkNext && "in time; walk abandoned." & return after field "raTheirFeed"
      put empty into sWalkNext
   end if
end raExpire

command raHandleEvent pEvent
   local tHead, tPost, tNext, tOk, tKeyCount
   switch pEvent["name"]
      case "dhtMutableItem"
         if sAwaitOwn is "true" then
            put rsIngestHead(pEvent, sHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitOwn
               put tHead["seq"] into sSeq
               if tHead["latestPostTarget"] is not rsZeroTarget() then
                  put tHead["latestPostTarget"] into sMyLatest
               end if
               put "recovered your head: seq" && sSeq & comma && "latest post" && tHead["latestPostTarget"] & return after field "raIdOut"
            end if
         end if
         if sAwaitHead is "true" then
            put rsIngestHead(pEvent, sFollowHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitHead
               put "head VERIFIED for" && tHead["displayName"] && "(seq" && tHead["seq"] & ")" & return after field "raTheirFeed"
               if tHead["latestPostTarget"] is rsZeroTarget() then
                  put "no posts yet." & return after field "raTheirFeed"
               else
                  put tHead["latestPostTarget"] into sWalkNext
                  put 0 into sWalkCount
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     put "lookup refused:" && rsLastError() & return after field "raTheirFeed"
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtImmutableItem"
         if sWalkNext is not empty and pEvent["target"] is sWalkNext then
            put rsIngestPost(pEvent, sWalkNext, sFollowHandle) into tPost
            put the number of lines of the keys of tPost into tKeyCount
            if tKeyCount is 0 then
               put "post REFUSED (tamper or wrong author):" && rsLastError() & return after field "raTheirFeed"
               put empty into sWalkNext
            else
               add 1 to sWalkCount
               put "post" && sWalkCount && "[t=" & tPost["timestamp"] & "] authorSig VERIFIED:" && tPost["text"] & return after field "raTheirFeed"
               put tPost["prevPostTarget"] into tNext
               if tNext is rsZeroTarget() then
                  put "chain COMPLETE:" && sWalkCount && "post(s), every authorSig verified." & return after field "raTheirFeed"
                  put empty into sWalkNext
               else if sWalkCount >= kWalkMax then
                  put "stopped at the" && kWalkMax & "-post demo cap; the chain continues at" && tNext & return after field "raTheirFeed"
                  put empty into sWalkNext
               else
                  put tNext into sWalkNext
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     put "lookup refused:" && rsLastError() & return after field "raTheirFeed"
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtPut"
         -- store confirmations arrive here; the publish calls already
         -- validated synchronously, so these stay quiet in the demo
         break
   end switch
end raHandleEvent

-- ---- 2. my feed --------------------------------------------------------------
command raPost
   local tText, tName, tPost, tTarget, tHead, tOk
   if sIdSeed is empty then
      uiStatus "Unlock (or create) your identity before posting.", "warn"
      exit raPost
   end if
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot publish.", "bad"
      exit raPost
   end if
   put field "raCompose" into tText
   if tText is empty then
      uiStatus "Nothing to post: the compose field is empty.", "warn"
      exit raPost
   end if
   put field "raName" into tName
   if the number of chars of tName > kNameMax then
      uiStatus "The display name is over the 64-byte head budget; shorten it.", "warn"
      exit raPost
   end if
   put rsBuildPost(the seconds, sMyLatest, tText, empty, sIdSeed) into tPost
   if tPost is empty then
      uiStatus "rsBuildPost refused:" && rsLastError(), "bad"
      exit raPost
   end if
   put rsPublishPost(sSession, tPost) into tTarget
   if tTarget is empty then
      uiStatus "rsPublishPost failed:" && rsLastError(), "bad"
      exit raPost
   end if
   add 1 to sSeq
   put rsBuildHead(sSeq, tName, tTarget, empty, sOnion, empty) into tHead
   if tHead is empty then
      subtract 1 from sSeq
      uiStatus "rsBuildHead refused:" && rsLastError(), "bad"
      exit raPost
   end if
   put rsPublishHead(sSession, tHead, sIdSeed) into tOk
   if tOk is not true then
      subtract 1 from sSeq
      uiStatus "rsPublishHead failed:" && rsLastError(), "bad"
      exit raPost
   end if
   put tTarget into sMyLatest
   put "seq" && sSeq & ":" && tText & return & "  ->" && tTarget & return before field "raMyFeed"
   put empty into field "raCompose"
   uiStatus "Posted, and the signed head republished at seq" && sSeq & ".", "ok"
end raPost

-- ---- 3. follow ---------------------------------------------------------------
command raFetch
   local tHandle, tOk
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot fetch.", "bad"
      exit raFetch
   end if
   put toLower(word 1 of field "raHandle") into tHandle
   if the number of chars of tHandle is not 64 then
      uiStatus "A handle is 64 hex characters (the author's public key).", "warn"
      exit raFetch
   end if
   put tHandle into sFollowHandle
   put empty into sWalkNext
   put 0 into sWalkCount
   put "true" into sAwaitHead
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put empty into field "raTheirFeed"
   put rsRequestHead(sSession, sFollowHandle) into tOk
   if tOk is not true then
      put empty into sAwaitHead
      uiStatus "rsRequestHead refused:" && rsLastError(), "bad"
      exit raFetch
   end if
   uiStatus "Asking the DHT for" && sFollowHandle & "...", empty
end raFetch

-- ---- helpers -----------------------------------------------------------------
-- The default key-file location, the family preferences idiom (fall back
-- rather than fail on a platform with no preferences folder). The field is
-- editable, so this is only the starting suggestion.
function raKeyPath
   local tBase
   put specialFolderPath("preferences") into tBase
   if tBase is empty then
      put specialFolderPath("application data") into tBase
   end if
   if tBase is empty then
      put specialFolderPath("documents") into tBase
   end if
   return tBase & "/Riptide/identity.riptkey"
end raKeyPath
