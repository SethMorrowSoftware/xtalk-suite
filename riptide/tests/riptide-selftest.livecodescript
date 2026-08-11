script "RiptideSelfTest"
-- riptide-selftest.livecodescript - the offline self-test for the Riptide
-- phase-1 library (src/riptide.livecodescript).
--
-- HOW TO RUN: install the suite extensions (SodiumXT is required; coinxt and
-- onionxt light up two extra sections), put the riptide library in use (or
-- paste src/riptide.livecodescript into a stack script and this file into a
-- button), then call rsSelfTest() and read the report. Offline by design:
-- nothing here touches the network, a daemon, or a session - that is what
-- keeps it runnable anywhere, any time (the onionxt-tests convention).
--
-- STATUS (honesty convention): verified statically and against the oracle
-- (tools/riptide_reference.py, via tools/check-selftest-vectors.py, which
-- re-derives every golden constant below); needs an OXT pass.
--
-- The golden constants are copied from `python3 tools/riptide_reference.py`
-- and are the SAME bytes tests/riptide_golden_test.py pins in Python, so the
-- oracle, the Python golden test, and this harness hold one set of vectors.
-- Do not edit a constant by hand: regenerate from the oracle, and the vector
-- gate will fail loudly on any transcription slip.

-- inputs (chosen, not derived - the vector gate lists these with reasons)
constant kRsGoldMasterHex = "4242424242424242424242424242424242424242424242424242424242424242"
constant kRsGoldConfSeedHex = "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7"
constant kRsGoldRoomSalt = "golden-salt"
constant kRsGoldPost1Text = "hello, riptide"
constant kRsGoldPost2Text = "second post"
constant kRsGoldTs1 = "1754870400"
constant kRsGoldTs2 = "1754870460"
constant kRsGoldHeadSeq = "7"
constant kRsGoldHeadName = "Riptide"
constant kRsGoldPrekeyTarget = "abababababababababababababababababababab"
constant kRsGoldProfileTarget = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
constant kRsGoldMediaTarget = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

-- derived (every one re-derived by tools/check-selftest-vectors.py)
constant kRsGoldIdSeedHex = "9c7b6be59e0884a1923505cf1390a1d01b5b7a258c582d9518e722c07bd8650c"
constant kRsGoldDmSeedHex = "4dca52e87fa8919a5699fd35f79d6e4a417bdf0cf3e16d5c549aac6cd8c2b391"
constant kRsGoldLanKeyHex = "fb9441aca42ca2212b3b16ea0b615d70e6d8c5ab3f6ac9a90a5e648fd58ac85f"
constant kRsGoldAnon0Hex = "6940ca2dc794eb4c533feb196481c0547b1257d3837925affe35dae97682c68a"
constant kRsGoldHandle = "5a546e4fef5d1b76f94dc1b2eded75c44bffc900af7461a26d8427453a92f22d"
constant kRsGoldZeroSeedPub = "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29"
constant kRsGoldConfPub = "672e8e0b259627f15c772ec0d61f15cd786ce2bc7244549255f9d6cfaac300b2"
constant kRsGoldOnion = "ljkg4t7plunxn6knygzo33lvyrf77siav52gditnqqtukous6iwwe6yd.onion"
constant kRsGoldInboxId = "3cf4170b3e7253387f351af14eb1071224d0140e"
constant kRsGoldRoomId = "3a57d3ad644536e20a4486d31bde5ecb3902d3a5"
constant kRsGoldPost1Hex = "5253503100000000689932803030303030303030303030303030303030303030303030303030303030303030303030303030303044000e68656c6c6f2c20726970746964650084b56e15631b88e780a74e22241c00efc34b63e50fd645ba651bb27dc41cac5953396ae8f848ef9b81711b08baa5b764fc5746bfd02122f36ac5a17f87a88f01"
constant kRsGoldPost1Target = "a161e3add5a4d78080db9219583e6a988954705c"
constant kRsGoldPost2Hex = "5253503100000000689932bc6131363165336164643561346437383038306462393231393538336536613938383935343730356344000b7365636f6e6420706f737401656565656565656565656565656565656565656565656565656565656565656565656565656565654d29a287d8ac5360688b548ee342f7754287e3ddc604fe2a5160263ce1ef7a5526f9a750dc05d0edf2c317ea0b3dca062e745d0e2fb6c1b381225c7d19dba10f"
constant kRsGoldPost2Target = "21d0180855ef47084fd8a9825f4ec8516608161a"
constant kRsGoldHeadHex = "525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"

local sLog
local sPass
local sFail
local sSkip

--------------------------------------------------------------------------
-- entry point
--------------------------------------------------------------------------

function rsSelfTest
   local tCaps
   put empty into sLog
   put 0 into sPass
   put 0 into sFail
   put 0 into sSkip
   put rsProbeCapabilities() into tCaps
   rstSectionCapabilities tCaps
   if tCaps["canCrypto"] is true then
      rstSectionKdfTree
      rstSectionHandles
      rstSectionOnion tCaps
      rstSectionRendezvous
      rstSectionKeyFile
      rstSectionHead
      rstSectionPosts
      rstSectionHelpers
   else
      rstSkip "every crypto section: SodiumXT is not installed"
   end if
   return sPass && "passed," && sFail && "failed," && sSkip && \
         "skipped" & return & \
         "----------------------------------------" & return & sLog
end rsSelfTest

--------------------------------------------------------------------------
-- scaffolding (the onionxt-tests shape)
--------------------------------------------------------------------------

private command rstCheck pCondition, pLabel
   if pCondition is true then
      add 1 to sPass
      put "  ok  " && pLabel & return after sLog
   else
      add 1 to sFail
      put "  FAIL" && pLabel & return after sLog
   end if
end rstCheck

private command rstSection pTitle
   put return & "--" && pTitle & return after sLog
end rstSection

private command rstSkip pLabel
   add 1 to sSkip
   put "  skip" && pLabel & return after sLog
end rstSkip

private function rstBin pHex
   return sxHex2Bin(textEncode(pHex, "ASCII"))
end rstBin

private function rstHex pData
   return textDecode(sxBin2Hex(pData), "ASCII")
end rstHex

-- Flip one byte of a Data value (for tamper tests).
private function rstFlipByte pData, pIndex
   local tOut, tByte
   put byteToNum(byte pIndex of pData) into tByte
   put pData into tOut
   if tByte is 255 then
      put numToByte(0) into byte pIndex of tOut
   else
      put numToByte(tByte + 1) into byte pIndex of tOut
   end if
   return tOut
end rstFlipByte

--------------------------------------------------------------------------
-- sections
--------------------------------------------------------------------------

private command rstSectionCapabilities pCaps
   rstSection "capabilities + version"
   rstCheck (rsVersion() contains "Riptide"), "rsVersion names the library"
   rstCheck (pCaps["canCrypto"] is true or pCaps["canCrypto"] is false), \
         "probe reports canCrypto as a boolean"
   rstCheck (the number of lines in the keys of pCaps is 7), \
         "probe reports six extensions plus the derived hasSha3"
   put "      canCrypto=" & pCaps["canCrypto"] & \
         " hasTorrent=" & pCaps["hasTorrent"] & \
         " hasOnion=" & pCaps["hasOnion"] & return after sLog
   put "      hasDataChannel=" & pCaps["hasDataChannel"] & \
         " hasEnet=" & pCaps["hasEnet"] & \
         " hasCoin=" & pCaps["hasCoin"] & \
         " hasSha3=" & pCaps["hasSha3"] & return after sLog
end rstSectionCapabilities

private command rstSectionKdfTree
   local tMaster, tOut
   rstSection "the KDF subkey tree"
   put rstBin(kRsGoldMasterHex) into tMaster
   put rsIdentitySeed(tMaster) into tOut
   rstCheck (rstHex(tOut) is kRsGoldIdSeedHex), "identity seed matches golden"
   put rsDmSeed(tMaster) into tOut
   rstCheck (rstHex(tOut) is kRsGoldDmSeedHex), "DM seed matches golden"
   put rsLanKey(tMaster) into tOut
   rstCheck (rstHex(tOut) is kRsGoldLanKeyHex), "LAN key matches golden"
   put rsAnonSeed(tMaster, 0) into tOut
   rstCheck (rstHex(tOut) is kRsGoldAnon0Hex), "anon persona 0 matches golden"
   rstCheck (rsIdentitySeed(tMaster) is not rsDmSeed(tMaster)), \
         "identity and DM subkeys differ"
   rstCheck (rsAnonSeed(tMaster, 0) is not rsAnonSeed(tMaster, 1)), \
         "anon personas 0 and 1 differ"
   put rsIdentitySeed(byte 1 to 31 of tMaster) into tOut
   rstCheck (tOut is empty), "a 31-byte master is refused"
   rstCheck (rsLastError() is not empty), "and the refusal is explained"
   put rsAnonSeed(tMaster, -1) into tOut
   rstCheck (tOut is empty), "a negative persona index is refused"
end rstSectionKdfTree

private command rstSectionHandles
   local tSeed, tKeys, tOut
   rstSection "identity seed -> handle"
   put rstBin(kRsGoldIdSeedHex) into tSeed
   rstCheck (rsHandleFromSeed(tSeed) is kRsGoldHandle), \
         "the golden identity seed yields the golden handle"
   put rsIdentityKeys(tSeed) into tKeys
   rstCheck (the number of bytes in tKeys["publicKey"] is 32), \
         "public key is 32 bytes"
   rstCheck (the number of bytes in tKeys["secretKey"] is 64), \
         "secret key is 64 bytes (seed || pub)"
   rstCheck (tKeys["handle"] is kRsGoldHandle), \
         "rsIdentityKeys agrees with rsHandleFromSeed"
   rstCheck (rsHandleFromSeed(rstBin(kRsGoldConfSeedHex)) is \
         kRsGoldConfPub), "the cross-project conformance seed checks out"
   put numToByte(0) into tOut
   repeat 4 times
      put tOut & tOut into tOut
   end repeat
   rstCheck (rsHandleFromSeed(byte 1 to 16 of tOut & byte 1 to 16 of tOut) \
         is kRsGoldZeroSeedPub), "the zero seed matches the sodium C KAT"
   rstCheck (rsHandleFromSeed(byte 1 to 31 of tSeed) is empty), \
         "a 31-byte identity seed is refused"
end rstSectionHandles

private command rstSectionOnion pCaps
   local tPub, tOut
   rstSection "identity -> onion (offline)"
   put rstBin(kRsGoldHandle) into tPub
   if pCaps["hasSha3"] is true then
      rstCheck (rsOnionFromPublicKey(tPub) is kRsGoldOnion), \
            "the golden handle yields the golden onion"
      rstCheck (rsOnionFromHandle(kRsGoldHandle) is kRsGoldOnion), \
            "rsOnionFromHandle agrees"
      rstCheck (rsOnionFromPublicKey(byte 1 to 31 of tPub) is empty), \
            "a 31-byte public key is refused"
   else
      put rsOnionFromPublicKey(tPub) into tOut
      rstCheck (tOut is empty), \
            "without a SHA3 provider the self-computation refuses"
      rstCheck (rsLastError() contains "sxSha3_256"), \
            "and the refusal names both providers"
      rstSkip "offline onion self-computation: no SHA3 provider installed"
   end if
   if pCaps["hasOnion"] is true then
      rstCheck (rsVerifyOnionClaim(kRsGoldOnion, kRsGoldHandle) is true), \
            "the golden onion verifies against the golden handle"
      rstCheck (rsVerifyOnionClaim(kRsGoldOnion, kRsGoldConfPub) is \
            false), "the golden onion refuses a different handle"
      rstCheck (rsVerifyOnionClaim("not-an-onion", kRsGoldHandle) is \
            false), "a malformed onion address refuses"
   else
      rstSkip "onion claim verification: onionxt is not installed"
   end if
end rstSectionOnion

private command rstSectionRendezvous
   rstSection "rendezvous derivations"
   rstCheck (rsInboxId(kRsGoldHandle) is kRsGoldInboxId), \
         "inbox id matches golden"
   rstCheck (rsRoomId(kRsGoldHandle, kRsGoldConfPub, \
         textEncode(kRsGoldRoomSalt, "ASCII")) is kRsGoldRoomId), \
         "room id matches golden"
   rstCheck (rsRoomId(kRsGoldConfPub, kRsGoldHandle, \
         textEncode(kRsGoldRoomSalt, "ASCII")) is kRsGoldRoomId), \
         "room id is symmetric in its peers"
   rstCheck (rsInboxId("zz") is empty), "a malformed handle is refused"
   rstCheck (rsRoomId("zz", kRsGoldConfPub, empty) is empty), \
         "a malformed peer key is refused"
end rstSectionRendezvous

private command rstSectionKeyFile
   local tSeed, tSealed, tOpened
   rstSection "the RIPTKEY1 sealed key file"
   put rstBin(kRsGoldMasterHex) into tSeed
   put rsSealMasterSeed(tSeed, "correct horse") into tSealed
   rstCheck (tSealed is not empty), "sealing succeeds"
   rstCheck (textDecode(byte 1 to 9 of tSealed, "ASCII") is "RIPTKEY1E"), \
         "the file leads with the magic and mode"
   rstCheck (the number of bytes in tSealed is 97), \
         "the sealed file is exactly 97 bytes"
   put rsOpenMasterSeed(tSealed, "correct horse") into tOpened
   rstCheck (rstHex(tOpened) is kRsGoldMasterHex), \
         "the right passphrase recovers the seed"
   put rsOpenMasterSeed(tSealed, "wrong horse") into tOpened
   rstCheck (tOpened is empty), "a wrong passphrase is refused"
   rstCheck (rsLastError() contains "passphrase"), \
         "and the refusal says why"
   put rsOpenMasterSeed(rstFlipByte(tSealed, 40), "correct horse") \
         into tOpened
   rstCheck (tOpened is empty), "a tampered file is refused"
   put rsOpenMasterSeed(byte 1 to 60 of tSealed, "correct horse") \
         into tOpened
   rstCheck (tOpened is empty), "a truncated file is refused"
   rstCheck (rsSealMasterSeed(tSeed, empty) is empty), \
         "an empty passphrase is refused at seal time"
   rstCheck (rsSealMasterSeed(byte 1 to 16 of tSeed, "x") is empty), \
         "a 16-byte seed is refused at seal time"
   rstCheck (rsSealMasterSeed(tSeed, "a") is not rsSealMasterSeed(tSeed, \
         "a")), "two seals of one seed differ (fresh salt and nonce)"
end rstSectionKeyFile

private command rstSectionHead
   local tHead, tParsed, tRebuilt
   rstSection "RSH1 - the feed head"
   put rsBuildHead(kRsGoldHeadSeq, kRsGoldHeadName, kRsGoldPost2Target, \
         kRsGoldPrekeyTarget, kRsGoldOnion, kRsGoldProfileTarget) into tHead
   rstCheck (rstHex(tHead) is kRsGoldHeadHex), "head bytes match golden"
   put rsParseHead(tHead) into tParsed
   rstCheck (tParsed is not empty), "the golden head parses"
   rstCheck (tParsed["seq"] is 7), "seq round-trips"
   rstCheck (tParsed["displayName"] is kRsGoldHeadName), \
         "display name round-trips"
   rstCheck (tParsed["latestPostTarget"] is kRsGoldPost2Target), \
         "latest-post target round-trips"
   rstCheck (tParsed["prekeyTarget"] is kRsGoldPrekeyTarget), \
         "prekey target round-trips"
   rstCheck (tParsed["onionAddr"] is kRsGoldOnion), \
         "onion address round-trips"
   rstCheck (tParsed["profileMetaTarget"] is kRsGoldProfileTarget), \
         "profile-meta target round-trips"
   put rsBuildHead(0, "n", empty, empty, empty, empty) into tRebuilt
   put rsParseHead(tRebuilt) into tParsed
   rstCheck (tParsed["latestPostTarget"] is rsZeroTarget()), \
         "an empty target normalizes to the zero target"
   rstCheck (tParsed["onionAddr"] is empty), \
         "an empty onion address round-trips as empty"
   rstCheck (rsParseHead(rstFlipByte(tHead, 2)) is empty), \
         "a wrong magic is refused"
   rstCheck (rsParseHead(byte 1 to 30 of tHead) is empty), \
         "a truncated head is refused"
   rstCheck (rsParseHead(tHead & numToByte(0)) is empty), \
         "trailing bytes are refused"
   rstCheck (rsBuildHead(1, \
         "0123456789012345678901234567890123456789012345678901234567890123x", \
         empty, empty, empty, empty) is empty), \
         "a 65-byte display name is refused"
   rstCheck (rsBuildHead(1, "n", "zz", empty, empty, empty) is empty), \
         "a malformed target is refused"
   rstCheck (rsBuildHead(1, "n", empty, empty, "short.onion", empty) is \
         empty), "a short onion address is refused"
   rstCheck (rsBuildHead(-1, "n", empty, empty, empty, empty) is empty), \
         "a negative seq is refused"
end rstSectionHead

private command rstSectionPosts
   local tSeed, tPost1, tPost2, tParsed, tChunked, tMangled
   rstSection "RSP1 - posts and the chain"
   put rstBin(kRsGoldIdSeedHex) into tSeed
   put rsBuildPost(kRsGoldTs1, empty, kRsGoldPost1Text, empty, tSeed) \
         into tPost1
   rstCheck (rstHex(tPost1) is kRsGoldPost1Hex), \
         "post 1 bytes match golden (deterministic signature)"
   rstCheck (rstHex(sha1Digest(rsBencodeBytes(tPost1))) is \
         kRsGoldPost1Target), "post 1's DHT target re-derives via SHA-1"
   put rsBuildPost(kRsGoldTs2, kRsGoldPost1Target, kRsGoldPost2Text, \
         kRsGoldMediaTarget, tSeed) into tPost2
   rstCheck (rstHex(tPost2) is kRsGoldPost2Hex), "post 2 bytes match golden"
   rstCheck (rstHex(sha1Digest(rsBencodeBytes(tPost2))) is \
         kRsGoldPost2Target), "post 2's DHT target re-derives via SHA-1"
   put rsParsePost(tPost2) into tParsed
   rstCheck (tParsed is not empty), "post 2 parses"
   rstCheck (tParsed["timestamp"] is 1754870460), "timestamp round-trips"
   rstCheck (tParsed["prevPostTarget"] is kRsGoldPost1Target), \
         "the chain link names post 1"
   rstCheck (tParsed["kind"] is "D"), "kind round-trips"
   rstCheck (tParsed["text"] is kRsGoldPost2Text), "text round-trips"
   rstCheck (tParsed["mediaTargets"] is kRsGoldMediaTarget), \
         "media info-hash round-trips"
   rstCheck (rsVerifyPost(tPost1, kRsGoldHandle) is true), \
         "post 1 verifies under the golden handle"
   rstCheck (rsVerifyPost(tPost2, kRsGoldHandle) is true), \
         "post 2 verifies under the golden handle"
   rstCheck (rsVerifyPost(tPost2, kRsGoldConfPub) is false), \
         "post 2 refuses a different author"
   put rstFlipByte(tPost2, 60) into tMangled
   rstCheck (rsVerifyPost(tMangled, kRsGoldHandle) is false), \
         "one flipped text byte breaks the signature"
   put rstFlipByte(tPost2, 1) into tMangled
   rstCheck (rsVerifyPost(tMangled, kRsGoldHandle) is false), \
         "a wrong magic is refused before any crypto"
   rstCheck (rsVerifyPost(byte 1 to 100 of tPost2, kRsGoldHandle) is \
         false), "a truncated post is refused"
   put rsBuildPostChunked(kRsGoldTs2, kRsGoldPost2Target, \
         kRsGoldPrekeyTarget & comma & kRsGoldProfileTarget, empty, tSeed) \
         into tChunked
   rstCheck (tChunked is not empty), "a chunked post builds"
   put rsParsePost(tChunked) into tParsed
   rstCheck (tParsed["kind"] is "C"), "chunked kind round-trips"
   rstCheck (tParsed["chunkTargets"] is \
         (kRsGoldPrekeyTarget & comma & kRsGoldProfileTarget)), \
         "the chunk list round-trips in order"
   rstCheck (rsVerifyPost(tChunked, kRsGoldHandle) is true), \
         "the chunked post verifies"
   rstCheck (rsBuildPostChunked(1, empty, empty, empty, tSeed) is empty), \
         "an empty chunk list is refused"
   rstCheck (rsBuildPost(1, empty, "x", \
         kRsGoldMediaTarget & comma & kRsGoldMediaTarget & comma & \
         kRsGoldMediaTarget & comma & kRsGoldMediaTarget & comma & \
         kRsGoldMediaTarget & comma & kRsGoldMediaTarget & comma & \
         kRsGoldMediaTarget & comma & kRsGoldMediaTarget & comma & \
         kRsGoldMediaTarget, tSeed) is empty), \
         "nine media attachments are refused"
   rstCheck (rsBuildPost(-5, empty, "x", empty, tSeed) is empty), \
         "a negative timestamp is refused"
end rstSectionPosts

private command rstSectionHelpers
   local tValue
   rstSection "helpers"
   rstCheck (textDecode(rsBencodeBytes(empty), "ASCII") is "0:"), \
         "bencode of empty is 0:"
   rstCheck (textDecode(rsBencodeBytes(textEncode("hi", "ASCII")), \
         "ASCII") is "2:hi"), "bencode of a short string"
   put rsBencodeBytes(rstBin(kRsGoldHeadHex)) into tValue
   rstCheck (textDecode(byte 1 to 4 of tValue, "ASCII") is "203:"), \
         "the golden head bencodes at 203 bytes"
   rstCheck (rsHeadSalt() is "riptide-head"), "the head salt is published"
   rstCheck (the number of chars in rsZeroTarget() is 40), \
         "the zero target is 40 chars"
end rstSectionHelpers
