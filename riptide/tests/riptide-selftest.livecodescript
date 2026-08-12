script "RiptideSelfTest"
-- riptide-selftest.livecodescript - the self-test for the Riptide phase 1-2
-- library (src/riptide.livecodescript).
--
-- HOW TO RUN: install the suite extensions (SodiumXT is required; coinxt and
-- onionxt light up two extra sections, torrentxt the live-feed one), put the
-- riptide library in use (or paste src/riptide.livecodescript into a stack
-- script and this file into a button), then call rsSelfTest() and read the
-- report. No NETWORK is ever waited on: the phase 1-2 pure layers run fully
-- offline (the onionxt-tests convention), and the live-feed section drives
-- BEP44 puts and lookups against a LOCAL torrent session - stores return
-- their verdict synchronously, lookups are fire-and-forget - skipping
-- honestly when torrentxt is absent or a session cannot start.
--
-- STATUS (honesty convention): the phase-1 and phase-2 sections had their OXT
-- pass on 2026-08-12 (133/133 via the folded suite harness, no skips). The
-- oracle still independently pins the phase-2 vectors
-- (tools/riptide_reference.py, via tools/check-selftest-vectors.py, which
-- re-derives every golden constant below).
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
constant kRsGoldHeadBufHex = "343a73616c7431323a726970746964652d68656164333a736571693765313a763230333a525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"
constant kRsGoldHeadSigHex = "6d4560c6c20794dfbb71e4592679c242472d459728051a90bcedb123ec2404a544882525242888eda72dcd3c820a5538a80b9fb63e09d4c1bc3487db67730b0f"

local sLog
local sPass
local sFail
local sSkip
local sRsTestSession

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
      rstSectionBep44
      rstSectionIngest
      rstSectionLiveFeed tCaps
   else
      rstSkip "every crypto section: SodiumXT is not installed"
   end if
   -- The first line is EXACTLY two counts + passed/failed and nothing else:
   -- the suite core's stSummaryCounts treats any other word as prose, so the
   -- skip count gets its own line (the sodiumxt/onionxt returned-report shape).
   return sPass && "passed," && sFail && "failed" & return & \
         sSkip && "skipped (optional dependencies; see the log)" & return & \
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
   local tSeed, tSealed, tOpened, tGenA, tGenB
   rstSection "the RIPTKEY1 sealed key file"
   put rsGenerateMasterSeed() into tGenA
   put rsGenerateMasterSeed() into tGenB
   rstCheck (the number of bytes in tGenA is 32), \
         "a generated master seed is 32 bytes"
   rstCheck (rstHex(tGenA) is not rstHex(tGenB)), \
         "two generated seeds differ (the CSPRNG is live)"
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
   local tHead, tParsed, tRebuilt, tUpper
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
   -- A non-canonical (uppercase) hex target must be refused, not silently
   -- accepted: byte 61 is the first char of the prekey target ("ab"*20), so
   -- turning that 'a' (97) into 'A' (65) is a valid-length but non-lowercase
   -- target. `is in` would accept it (caseSensitive default false); the
   -- byte-value check refuses it.
   put tHead into tUpper
   put numToByte(65) into byte 61 of tUpper
   rstCheck (rsParseHead(tUpper) is empty), \
         "an uppercase (non-canonical) hex target is refused"
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

private command rstSectionBep44
   local tValue, tBuf, tSalt
   rstSection "phase 2 - the canonical BEP44 buffer + content addresses"
   -- the exact bytes the golden head's BEP44 signature covers, from the
   -- pure-script assembly (byte-identical to btDhtBep44SignBuf; the folded
   -- suite harness cross-checks the two implementations directly)
   put rsBencodeBytes(rstBin(kRsGoldHeadHex)) into tValue
   put rsBep44SignBuf(rsHeadSalt(), 7, tValue) into tBuf
   rstCheck (rstHex(tBuf) is kRsGoldHeadBufHex), \
         "the golden head's signing buffer matches golden"
   -- the cross-project anchor torrentxt/tests/bep44_golden_test.py pins
   put rsBep44SignBuf("rp-prekeys", 1, textEncode("2:hi", "ASCII")) into tBuf
   rstCheck (textDecode(tBuf, "ASCII") is \
         "4:salt10:rp-prekeys3:seqi1e1:v2:hi"), \
         "the salted anchor vector matches bep44_golden_test.py"
   put rsBep44SignBuf(empty, 7, textEncode("2:hi", "ASCII")) into tBuf
   rstCheck (textDecode(tBuf, "ASCII") is "3:seqi7e1:v2:hi"), \
         "an empty salt omits the salt segment"
   rstCheck (rsBep44SignBuf(rsHeadSalt(), -1, \
         textEncode("2:hi", "ASCII")) is empty), "a negative seq is refused"
   rstCheck (rsBep44SignBuf(rsHeadSalt(), 9007199254740992, \
         textEncode("2:hi", "ASCII")) is empty), \
         "a seq at 2^53 is refused (it would not round-trip)"
   rstCheck (rsBep44SignBuf(rsHeadSalt(), 7, \
         textEncode("hi", "ASCII")) is empty), \
         "a non-bencoded value is refused"
   rstCheck (rsBep44SignBuf(rsHeadSalt(), 7, \
         textEncode("3:hi", "ASCII")) is empty), \
         "a value whose length prefix lies is refused"
   put empty into tSalt
   repeat 65 times
      put "x" after tSalt
   end repeat
   rstCheck (rsBep44SignBuf(tSalt, 1, textEncode("2:hi", "ASCII")) is \
         empty), "a 65-byte salt is refused (the BEP44 cap)"
   -- the content address, through the library this time (the sha1Digest
   -- re-derivations in the posts section prove the same bytes engine-side)
   rstCheck (rsImmutableTarget(rstBin(kRsGoldPost1Hex)) is \
         kRsGoldPost1Target), "rsImmutableTarget re-derives post 1's target"
   rstCheck (rsImmutableTarget(rstBin(kRsGoldPost2Hex)) is \
         kRsGoldPost2Target), "rsImmutableTarget re-derives post 2's target"
   rstCheck (rsImmutableTarget(empty) is empty), \
         "an empty immutable value is refused"
end rstSectionBep44

private command rstSectionIngest
   local tEvent, tBad, tPostEvent, tHead, tPost, tSig
   rstSection "phase 2 - ingest verifiers (synthetic drained events)"
   -- a synthetic dhtMutableItem event, key-for-key what btPoll drains for
   -- the golden head. The oracle pre-derived the BEP44 signature, so this
   -- is fully deterministic - nothing is signed at run time.
   put kRsGoldHandle into tEvent["publicKey"]
   put rsHeadSalt() into tEvent["salt"]
   put 7 into tEvent["seq"]
   put rstBin(kRsGoldHeadHex) into tEvent["value"]
   put kRsGoldHeadSigHex into tEvent["signature"]
   put rsIngestHead(tEvent, kRsGoldHandle) into tHead
   rstCheck (tHead is not empty), "the golden head event ingests"
   rstCheck (tHead["displayName"] is kRsGoldHeadName), \
         "and hands back the parsed head"
   rstCheck (tHead["latestPostTarget"] is kRsGoldPost2Target), \
         "naming post 2 as latest"
   rstCheck (rsIngestHead(tEvent, kRsGoldConfPub) is empty), \
         "an event for another handle is refused"
   put tEvent into tBad
   put "riptide-lies" into tBad["salt"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a wrong salt is refused"
   put tEvent into tBad
   put 8 into tBad["seq"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a seq disagreeing with the head's embedded seq is refused"
   put tEvent into tBad
   put rstFlipByte(tBad["value"], 2) into tBad["value"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a value that is not an RSH1 record is refused"
   put tEvent into tBad
   -- byte 20 is the last display-name char: the record still PARSES, so
   -- this refusal is the signature's, not the parser's
   put rstFlipByte(tBad["value"], 20) into tBad["value"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a tampered-but-parseable value fails the BEP44 signature"
   put tEvent into tBad
   put tBad["signature"] into tSig
   if char 1 of tSig is "6" then
      put "7" into char 1 of tSig
   else
      put "6" into char 1 of tSig
   end if
   put tSig into tBad["signature"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a forged signature is refused"
   put tEvent into tBad
   put char 1 to 127 of tBad["signature"] into tBad["signature"]
   rstCheck (rsIngestHead(tBad, kRsGoldHandle) is empty), \
         "a truncated signature is refused"
   -- the post walk, on synthetic dhtImmutableItem events: head names post 2,
   -- post 2's prev names post 1, post 1's prev is the zero target - the end
   put kRsGoldPost2Target into tPostEvent["target"]
   put rstBin(kRsGoldPost2Hex) into tPostEvent["value"]
   put rsIngestPost(tPostEvent, tHead["latestPostTarget"], kRsGoldHandle) \
         into tPost
   rstCheck (tPost is not empty), "the head's latest target ingests post 2"
   rstCheck (tPost["text"] is kRsGoldPost2Text), "with its text intact"
   put kRsGoldPost1Target into tPostEvent["target"]
   put rstBin(kRsGoldPost1Hex) into tPostEvent["value"]
   put rsIngestPost(tPostEvent, tPost["prevPostTarget"], kRsGoldHandle) \
         into tPost
   rstCheck (tPost is not empty), "walking the chain link ingests post 1"
   rstCheck (tPost["prevPostTarget"] is rsZeroTarget()), \
         "whose prev is the zero target - the chain ends"
   rstCheck (rsIngestPost(tPostEvent, kRsGoldPost2Target, kRsGoldHandle) \
         is empty), "an event answering a different target is refused"
   put rstFlipByte(rstBin(kRsGoldPost1Hex), 60) into tPostEvent["value"]
   rstCheck (rsIngestPost(tPostEvent, kRsGoldPost1Target, kRsGoldHandle) \
         is empty), "a value that does not hash to its target is refused"
   put rstBin(kRsGoldPost1Hex) into tPostEvent["value"]
   rstCheck (rsIngestPost(tPostEvent, kRsGoldPost1Target, kRsGoldConfPub) \
         is empty), "a different claimed author is refused"
   rstCheck (rsIngestPost(tPostEvent, rsZeroTarget(), kRsGoldHandle) is \
         empty), "ingesting against the zero target is refused"
end rstSectionIngest

-- Acquire the ONE torrent session the live-layer checks share. TorrentXT
-- allows a single session per process, so: reuse the handle a previous run
-- of this harness left live (a re-run in the same engine), else START INTO
-- A TEMPORARY and commit only on success - the torrent-selftest lesson: a
-- refusal must never overwrite a still-live handle with 0, which would
-- orphan the only session this process can ever have. The session is
-- deliberately left running at the end: stopping it would tear the
-- transport out from under any host still using it (the suite fold's
-- bt1stCleanup rule, applied from birth).
private function rstAcquireSession
   local tNew, tErr
   if sRsTestSession is not empty and sRsTestSession > 0 then
      return sRsTestSession
   end if
   try
      put btStartSession() into tNew
   catch tErr
      put 0 into tNew
   end try
   if tNew is not empty and tNew > 0 then
      put tNew into sRsTestSession
   end if
   if sRsTestSession is empty or sRsTestSession <= 0 then return 0
   return sRsTestSession
end rstAcquireSession

private command rstSectionLiveFeed pCaps
   local tSession, tSeed, tTarget
   rstSection "phase 2 - the live layer against a real session"
   -- The refusal paths run EVERYWHERE: every input is validated before the
   -- session handle is touched, so proving them needs no torrentxt at all.
   put rstBin(kRsGoldIdSeedHex) into tSeed
   rstCheck (rsPublishHead(0, rstBin(kRsGoldHeadHex), tSeed) is false), \
         "rsPublishHead refuses a dead session handle"
   rstCheck (rsLastError() contains "session"), "and says why"
   rstCheck (rsPublishHead(0, textEncode("junk", "ASCII"), tSeed) is \
         false), "rsPublishHead refuses a non-RSH1 record first"
   rstCheck (rsLastError() contains "RSH1"), "and names the parse"
   rstCheck (rsPublishPost(0, textEncode("junk", "ASCII")) is empty), \
         "rsPublishPost refuses a non-RSP1 record"
   rstCheck (rsPublishImmutable(0, rstBin(kRsGoldPost1Hex)) is empty), \
         "rsPublishImmutable refuses a dead session handle"
   rstCheck (rsRequestHead(0, kRsGoldHandle) is false), \
         "rsRequestHead refuses a dead session handle"
   rstCheck (rsRequestHead(0, "zz") is false), \
         "rsRequestHead refuses a malformed handle"
   rstCheck (rsRequestImmutable(0, rsZeroTarget()) is false), \
         "rsRequestImmutable refuses the zero target"
   rstCheck (rsRequestImmutable(0, kRsGoldPost1Target) is false), \
         "rsRequestImmutable refuses a dead session handle"
   if pCaps["hasTorrent"] is not true then
      rstSkip "live feed puts and lookups: torrentxt is not installed"
      exit rstSectionLiveFeed
   end if
   put rstAcquireSession() into tSession
   if tSession is 0 then
      rstSkip "live feed puts and lookups: could not start a torrent session"
      exit rstSectionLiveFeed
   end if
   -- The stores answer synchronously (the async dhtPut confirm is not
   -- waited on), so nothing here needs a network. The target comparisons
   -- are REAL cross-implementation checks: libtorrent's SHA-1 over its own
   -- bencoding against the oracle's pinned bytes.
   put rsPublishImmutable(tSession, rstBin(kRsGoldPost1Hex)) into tTarget
   rstCheck (tTarget is kRsGoldPost1Target), \
         "rsPublishImmutable stores post 1 at the golden target"
   put rsPublishPost(tSession, rstBin(kRsGoldPost2Hex)) into tTarget
   rstCheck (tTarget is kRsGoldPost2Target), \
         "rsPublishPost stores post 2 at the golden target"
   -- The whole external-signing seam in one boolean: script-assembled
   -- canonical buffer, SodiumXT signature, and libtorrent VERIFIES it
   -- before queueing - true means two independent ed25519 implementations
   -- and two independent BEP44 buffer assemblies agreed byte-for-byte.
   rstCheck (rsPublishHead(tSession, rstBin(kRsGoldHeadHex), tSeed) is \
         true), "rsPublishHead's signature satisfies libtorrent's verifier"
   rstCheck (rsRequestHead(tSession, kRsGoldHandle) is true), \
         "rsRequestHead's lookup is accepted (async; value not awaited)"
   rstCheck (rsRequestImmutable(tSession, kRsGoldPost1Target) is true), \
         "rsRequestImmutable's lookup is accepted (async; value not awaited)"
end rstSectionLiveFeed
