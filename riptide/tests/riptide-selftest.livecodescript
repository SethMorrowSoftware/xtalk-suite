script "RiptideSelfTest"
-- riptide-selftest.livecodescript - the self-test for the Riptide phase 1-4
-- library (src/riptide.livecodescript).
--
-- HOW TO RUN: install the suite extensions (SodiumXT is required; coinxt and
-- onionxt light up two extra sections, torrentxt the live-feed and media
-- ones), put the riptide library in use (or paste src/riptide.livecodescript
-- into a stack script and this file into a button), then call rsSelfTest()
-- and read the report. No NETWORK is ever waited on: the phase 1-2 pure
-- layers run fully offline (the onionxt-tests convention), the live-feed
-- section drives BEP44 puts and lookups against a LOCAL torrent session -
-- stores return their verdict synchronously, lookups are fire-and-forget -
-- and the media section seeds a local temp file and reads its status back,
-- all skipping honestly when torrentxt is absent or a session cannot start.
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
constant kRsGoldChunk1Text = "chunked text, part one; "
constant kRsGoldChunk2Text = "part two closes the record."
constant kRsGoldTs1 = "1754870400"
constant kRsGoldTs2 = "1754870460"
constant kRsGoldTs3 = "1754870760"
constant kRsGoldDmTs = "1754870520"
constant kRsGoldMsgTs = "1754870580"
constant kRsGoldDmMsgText = "hello, dm"
constant kRsGoldLanNonce = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"
constant kRsGoldLanHostName = "laptop"
constant kRsGoldLanJoinName = "phone"
constant kRsGoldLanDraftText = "draft: hello mesh"
constant kRsGoldLanSeq = "5"
constant kRsGoldLanFeedSeq = "9"
constant kRsGoldLanReadTs = "1754870700"
constant kRsGoldLanTick = "3"
constant kRsGoldLanMediaSeq = "7"
constant kRsGoldLanFileName = "clip.mp4"
constant kRsGoldLanFileSize = "1048576"
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
constant kRsGoldChunk1Target = "b9122511adc47fd591ae37523f47a3b0ff8bb837"
constant kRsGoldChunk2Target = "6b30810b837c9d22db507c3c62988f70eac7fc92"
constant kRsGoldPostCHex = "5253503100000000689933e83231643031383038353565663437303834666438613938323566346563383531363630383136316143026239313232353131616463343766643539316165333735323366343761336230666638626238333736623330383130623833376339643232646235303763336336323938386637306561633766633932016565656565656565656565656565656565656565656565656565656565656565656565656565656596faa39d774097d62eea9ef9c06a04aecbabde8aac498055164a52fb1bc8a3f54ecae3058bf235eb5024e867f730321400d199072e35676554bfd186fb317508"
constant kRsGoldPostCTarget = "d7d0cb72bc85a5dd4f35523bb442a484ca108373"
constant kRsGoldHeadHex = "525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"
constant kRsGoldHeadBufHex = "343a73616c7431323a726970746964652d68656164333a736571693765313a763230333a525348310000000000000007075269707469646532316430313830383535656634373038346664386139383235663465633835313636303831363161616261626162616261626162616261626162616261626162616261626162616261626162616261623e6c6a6b67347437706c756e786e366b6e79677a6f33336c767972663737736961763532676469746e717174756b6f757336697777653679642e6f6e696f6e63646364636463646364636463646364636463646364636463646364636463646364636463646364"
constant kRsGoldHeadSigHex = "6d4560c6c20794dfbb71e4592679c242472d459728051a90bcedb123ec2404a544882525242888eda72dcd3c820a5538a80b9fb63e09d4c1bc3487db67730b0f"
constant kRsGoldDmKxPub = "d946190585386568c3123a6fa706f94f5140fdfe647ab51fdf76e3f6e5799d3c"
constant kRsGoldConfKxPub = "9cf14a375404bd5f3fc048647215af20b506717fdab3f6e7df50c64e837f2059"
constant kRsGoldSessionRx = "0cf0c702142da300ac5d769dff39a1b4aabe4842b617cdf4a624815290b4ba38"
constant kRsGoldSessionTx = "2f8bb162c5e2d4346eadcf2a47804458428840336303e629d1ac20e8375dfe83"
constant kRsGoldPrekeyRecHex = "52534b31643934363139303538353338363536386333313233613666613730366639346635313430666466653634376162353166646637366533663665353739396433634af78ee3dc74534030feac4a92bf540c17cd9fb992c8e3e0eeb9af2822c9d6c40df10e2880b8a395bfe1cf076d8a325c00d9fbb046987657c080faff77a98609"
constant kRsGoldPrekeyRecTarget = "5b92cd531aa0537e43def0f737e2a61c48673008"
constant kRsGoldIntroHex = "5253493135613534366534666566356431623736663934646331623265646564373563343462666663393030616637343631613236643834323734353361393266323264643934363139303538353338363536386333313233613666613730366639346635313430666466653634376162353166646637366533663665353739396433633637326538653062323539363237663135633737326563306436316631356364373836636532626337323434353439323535663964366366616163333030623200000000689932f89d0357d4159ca1bab0e329d9b1ef1bfe88dbf75970389251a855dc6237f43ede513265c5590c0b889be490c4b07f60e279f1405cca0d1c069f532f4fc9b61905"
constant kRsGoldDmMsgHex = "54000000006899333468656c6c6f2c20646d"
constant kRsGoldLanPub = "2008657949f2e06e9786315cde35ecf4aa419152787e4fa1670f189dc07285d9"
constant kRsGoldLanChallengeHex = "52534c3143066c6170746f705a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"
constant kRsGoldLanResponseHex = "52534c31520570686f6e658941d7087e125898cb16acdc61f814e91ea4cd861d133fdd5f38e611ea8416958b2e5a1a96540afdbe6f979f475abf77b235d8c1c06ca8306c3e04f0bec7ae08"
constant kRsGoldLanWelcomeHex = "52534c3157066c6170746f7006c1a710d7dd13ac6ade03ec0a853563c1c506923a042d38473d15abb29761c9699a013070c4f4a24527cafde5fb30ea0375d56ae85e53a1726f91612cf2b805"
constant kRsGoldLanDraftHex = "52534c31440570686f6e650000000000000005001164726166743a2068656c6c6f206d65736874cf0ede5c356853d97eb42b76b44ad279c5ac4622ef48738675ee26fd58cfa6fb672a60196700cda0ceabf81900d3b335ff85c1d0a8d318fef53ae05ec0bc0b"
constant kRsGoldLanFeedStateHex = "52534c31460570686f6e6500000000000000093561353436653466656635643162373666393464633162326564656437356334346266666339303061663734363161323664383432373435336139326632326400000000689933ac685240060b5fdf7539152e57b472e039f1b5c7eee3680cebfa94b43ae5209d81c45c83ae72ff10e355fc1cf1abcbc1c3664cd5d25e27efda7f169375b831ca09"
constant kRsGoldLanPresenceHex = "52534c31500570686f6e650100000000000000036c788687ae09387aa6195fd6132a06c72fc80a84d404feafe27d433cc4d12e153cb20ef814b592af8ec9ebb92ac70ae87d2aea6e71d9bf911ce2c4f60962ef0f"
constant kRsGoldLanHandoffHex = "52534c314d0570686f6e6500000000000000076565656565656565656565656565656565656565656565656565656565656565656565656565656508636c69702e6d70340000000000100000d769b6b0853772c7fd7a8050f12115c559ad663257ea5eb11bd8e808d4f9ef1e55ff92f63f690b30d598408fa6d2a48d93c92896d75f9418a1594e6af580e60b"
constant kRsGoldAnon0Handle = "e051209271559dbd241ae6d14d60cd8e6ffd84f682ee96129146e6209d0106e9"
constant kRsGoldAnon0Onion = "4bisbetrkwo32ja243iu2ygnrzx73bhwqlxjmeuri3tcbhiba3u2abyd.onion"
constant kRsGoldBtxoHeaderHex = "4254584f0100000a7365637265742e747874000000000000000b"
constant kRsGoldBtxoFrameHex = "0000000b68656c6c6f20776f726c64"
constant kRsGoldAnonDmKxPub = "d4e6c146e4c3b3a89562ed669c43f4bd7601a0e4361bdaa3304f4beeb410aa17"
constant kRsGoldAnonPageHex = "3c21646f63747970652068746d6c3e3c68746d6c3e3c686561643e3c6d65746120636861727365743d277574662d38273e3c7469746c653e526970746964653c2f7469746c653e3c2f686561643e3c626f64793e3c68313e526970746964653c2f68313e3c756c3e3c6c693e68656c6c6f2c20726970746964653c2f6c693e3c6c693e7365636f6e6420706f73743c2f6c693e3c2f756c3e3c703e5365616c656420444d733a20474554202f7072656b657920286d79207369676e65642052534b31207072656b6579207265636f72642c20686578292c207468656e20504f535420796f7572207365616c656420696e74726f2061732068657820746f202f646d2e3c2f703e3c2f626f64793e3c2f68746d6c3e"
constant kRsGoldAnonPrekeyBody = "52534b31643465366331343665346333623361383935363265643636396334336634626437363031613065343336316264616133333034663462656562343130616131375936364dfd99c3382a61d1630ea6f3229c661b67a455c850f80e1d07db832c055604386656d6354ac8802f618f4ce4cf97c6a972e7c0560190dfd2dd6c70ba04"

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
      rstSectionChunked tCaps
      rstSectionHelpers
      rstSectionBep44
      rstSectionIngest
      rstSectionDm tCaps
      rstSectionLan
      rstSectionLanSync
      rstSectionAnon tCaps
      rstSectionBtxoStream
      rstSectionLiveFeed tCaps
      rstSectionMedia tCaps
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

-- The kind-C chunked-post rail END TO END (backlog A2, 2026-08-23): the
-- wire format's golden pin (it was the last unpinned riptide format),
-- the producer split, the raw-blob ingest verifier, and the reassembling
-- verify. The live tail stores real chunks on the local session where
-- torrentxt is present; nothing waits on a network.
private command rstSectionChunked pCaps
   local tSeed, tPost, tParsed, tPartsIn, tText, tBig, tHuge, tPad
   local tSplit, tParts, tTargets, tI, tEvent, tSession, tTarget
   rstSection "phase 2b - the kind-C chunked-post rail"
   put rstBin(kRsGoldIdSeedHex) into tSeed
   -- the golden pin: chunk values are the chosen texts' UTF-8 bytes,
   -- their targets content addresses, the record byte-for-byte
   rstCheck (rsImmutableTarget(textEncode(kRsGoldChunk1Text, "UTF-8")) is \
         kRsGoldChunk1Target), "chunk 1's content address matches golden"
   rstCheck (rsImmutableTarget(textEncode(kRsGoldChunk2Text, "UTF-8")) is \
         kRsGoldChunk2Target), "chunk 2's content address matches golden"
   put rsBuildPostChunked(kRsGoldTs3, kRsGoldPost2Target, \
         kRsGoldChunk1Target & comma & kRsGoldChunk2Target, \
         kRsGoldMediaTarget, tSeed) into tPost
   rstCheck (rstHex(tPost) is kRsGoldPostCHex), \
         "the kind-C post bytes match golden (the wire format is pinned)"
   rstCheck (rstHex(sha1Digest(rsBencodeBytes(tPost))) is \
         kRsGoldPostCTarget), "its DHT target re-derives via SHA-1"
   rstCheck (rsVerifyPost(tPost, kRsGoldHandle) is true), \
         "the golden kind-C post verifies under the golden handle"
   put rsParsePost(tPost) into tParsed
   rstCheck (tParsed["mediaTargets"] is kRsGoldMediaTarget), \
         "the media attachment parses BEHIND the chunk list"
   -- the reassembling verify: parts keyed by target, each re-hashed
   -- before a byte is believed, the CONCATENATION decoded as one buffer
   put textEncode(kRsGoldChunk1Text, "UTF-8") into \
         tPartsIn[kRsGoldChunk1Target]
   put textEncode(kRsGoldChunk2Text, "UTF-8") into \
         tPartsIn[kRsGoldChunk2Target]
   put rsAssembleChunkText(tParsed["chunkTargets"], tPartsIn) into tText
   rstCheck (tText is kRsGoldChunk1Text & kRsGoldChunk2Text), \
         "the chunks reassemble to the full text in wire order"
   put rstFlipByte(tPartsIn[kRsGoldChunk2Target], 3) into \
         tPartsIn[kRsGoldChunk2Target]
   rstCheck (rsAssembleChunkText(tParsed["chunkTargets"], tPartsIn) is \
         empty), "a tampered chunk fails its own content address"
   delete variable tPartsIn[kRsGoldChunk2Target]
   rstCheck (rsAssembleChunkText(tParsed["chunkTargets"], tPartsIn) is \
         empty), "a missing chunk refuses (the honest-placeholder path)"
   rstCheck (rsLastError() contains kRsGoldChunk2Target), \
         "and the refusal names WHICH chunk is missing"
   -- the capacity arithmetic the app's D-or-C decision rides on
   rstCheck (rsPostTextCapacity(0) is 880), \
         "capacity with no media is 880 bytes"
   rstCheck (rsPostTextCapacity(8) is 560), \
         "each attachment costs its 40-hex spelling"
   rstCheck (rsPostTextCapacity(9) is empty), \
         "a media count over the cap is refused"
   put "x" into tHuge
   repeat 14 times
      put tHuge & tHuge into tHuge
   end repeat
   rstCheck (rsBuildPost(1, empty, char 1 to 880 of tHuge, empty, tSeed) \
         is not empty), "a direct post takes exactly the stated capacity"
   rstCheck (rsBuildPost(1, empty, char 1 to 881 of tHuge, empty, tSeed) \
         is empty), "and refuses one byte more"
   -- the producer split: full 1000-byte chunks, remainder last, by BYTE
   put empty into tBig
   repeat 250 times
      put "0123456789" after tBig
   end repeat
   put rsChunkPostText(tBig) into tParts
   rstCheck (the number of elements in tParts is 3), \
         "2500 bytes split into three chunks"
   rstCheck (the number of bytes in tParts[1] is 1000 and \
         the number of bytes in tParts[2] is 1000 and \
         the number of bytes in tParts[3] is 500), \
         "full chunks first, the remainder last"
   rstCheck (tParts[1] & tParts[2] & tParts[3] is \
         textEncode(tBig, "UTF-8")), "and nothing is lost or reordered"
   rstCheck (rsChunkPostText(empty) is empty), "empty text is refused"
   rstCheck (rsChunkPostText(tHuge) is empty), \
         "text over 16000 UTF-8 bytes is refused, never truncated"
   -- 16 is the wire's kRsMaxChunks; a library constant is not visible
   -- from this separate script, and the number here is the FORMAT's
   rstCheck ((the number of elements in \
         rsChunkPostText(char 1 to 16000 of tHuge)) is 16), \
         "exactly 16000 bytes takes exactly 16 chunks"
   -- a chunk boundary INSIDE a UTF-8 sequence: legal on the wire, and
   -- the reassembly (which validates the concatenation, never a part
   -- alone) must reproduce the text exactly
   put empty into tPad
   repeat 999 times
      put "a" after tPad
   end repeat
   put tPad & textDecode(rstBin("c3a9"), "UTF-8") into tSplit
   put rsChunkPostText(tSplit) into tParts
   rstCheck (the number of elements in tParts is 2 and \
         the number of bytes in tParts[2] is 1), \
         "a multi-byte character splits across the chunk boundary"
   put empty into tTargets
   put empty into tPartsIn
   repeat with tI = 1 to the number of elements in tParts
      if tTargets is not empty then put comma after tTargets
      put rsImmutableTarget(tParts[tI]) after tTargets
      put tParts[tI] into tPartsIn[rsImmutableTarget(tParts[tI])]
   end repeat
   rstCheck (rsAssembleChunkText(tTargets, tPartsIn) is tSplit), \
         "and reassembly reproduces the text across that boundary"
   -- the raw-blob ingest verifier (synthetic drained events, the
   -- rstSectionIngest convention)
   put kRsGoldChunk1Target into tEvent["target"]
   put textEncode(kRsGoldChunk1Text, "UTF-8") into tEvent["value"]
   rstCheck (rsIngestBlob(tEvent, kRsGoldChunk1Target) is \
         textEncode(kRsGoldChunk1Text, "UTF-8")), \
         "rsIngestBlob returns the verified chunk bytes"
   rstCheck (rsIngestBlob(tEvent, kRsGoldChunk2Target) is empty), \
         "an event for a different target is refused"
   put textEncode(kRsGoldChunk2Text, "UTF-8") into tEvent["value"]
   rstCheck (rsIngestBlob(tEvent, kRsGoldChunk1Target) is empty), \
         "a value that does not hash to its target is refused (lying node)"
   rstCheck (rsIngestBlob(tEvent, rsZeroTarget()) is empty), \
         "the zero target is refused"
   -- the producer's refusal paths run with no torrentxt at all
   rstCheck (rsPublishChunkedPost(0, kRsGoldTs3, empty, "hi", empty, \
         tSeed) is empty), \
         "rsPublishChunkedPost refuses a dead session handle"
   rstCheck (rsLastError() contains "session"), "and says why"
   rstCheck (rsPublishChunkedPost(0, kRsGoldTs3, empty, empty, empty, \
         tSeed) is empty), "and refuses empty text before the session"
   if pCaps["hasTorrent"] is not true then
      rstSkip "chunked-post store on a session: torrentxt is not installed"
      exit rstSectionChunked
   end if
   put rstAcquireSession() into tSession
   if tSession is 0 then
      rstSkip "chunked-post store on a session: could not start a session"
      exit rstSectionChunked
   end if
   -- deterministic inputs, so the stored target must equal the offline
   -- recomputation of the exact record the producer had to build
   put rsPublishChunkedPost(tSession, kRsGoldTs3, empty, tBig, empty, \
         tSeed) into tTarget
   put rsChunkPostText(tBig) into tParts
   put empty into tTargets
   repeat with tI = 1 to the number of elements in tParts
      if tTargets is not empty then put comma after tTargets
      put rsImmutableTarget(tParts[tI]) after tTargets
   end repeat
   put rsBuildPostChunked(kRsGoldTs3, empty, tTargets, empty, tSeed) \
         into tPost
   rstCheck (tTarget is rsImmutableTarget(tPost)), \
         "the stored kind-C target equals the offline recomputation"
end rstSectionChunked

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

-- The phase-7 anon persona layer. The derivations (handle, onion) and the
-- BTXO framing are pure and golden-pinned; the deanonymization GUARD is
-- pure policy and gets its full truth table here (it is the app's
-- highest-severity invariant, so it is asserted every way it can fail);
-- the onion-service wrapper's refusal paths run offline, and its live
-- create needs a tor daemon (SKIP without onionxt, like the other live
-- sections skip without their transport).
private command rstSectionAnon pCaps
   local tHeader, tFrame, tParsed, tHandle, tPage, tPageText, tPkBody, tHex
   rstSection "phase 7 - the anon persona, the guard, and BTXO framing"
   -- derivations: the anon persona is a real, distinct identity
   rstCheck (rsAnonHandle(rstBin(kRsGoldMasterHex), 0) is kRsGoldAnon0Handle), \
         "anon persona 0's handle matches golden"
   rstCheck (rsAnonHandle(rstBin(kRsGoldMasterHex), 0) is not \
         rsAnonHandle(rstBin(kRsGoldMasterHex), 1)), \
         "distinct personas are distinct identities"
   rstCheck (rsAnonHandle(rstBin(kRsGoldMasterHex), 0) is not kRsGoldHandle), \
         "and an anon persona is not the public identity"
   if pCaps["hasSha3"] is true then
      rstCheck (rsAnonOnion(rstBin(kRsGoldMasterHex), 0) is \
            kRsGoldAnon0Onion), "anon persona 0's onion matches golden"
      rstCheck (rsVerifyOnionClaim(kRsGoldAnon0Onion, kRsGoldAnon0Handle) is \
            true or pCaps["hasOnion"] is not true), \
            "the anon onion self-authenticates to the anon handle"
   else
      rstCheck (rsAnonOnion(rstBin(kRsGoldMasterHex), 0) is empty), \
            "without a SHA3 provider the anon onion refuses"
      rstSkip "anon onion self-computation: no SHA3 provider installed"
   end if
   -- THE GUARD (spec 9.3): the full truth table, because a hole here is a
   -- deanonymization bug. An anon persona may use ONLY the onion.
   rstCheck (rsPersonaAllows(true, "onion") is true), \
         "anon persona: onion is allowed"
   rstCheck (rsPersonaAllows(true, "dht") is false), \
         "anon persona: the DHT is REFUSED"
   rstCheck (rsPersonaAllows(true, "torrent") is false), \
         "anon persona: torrents are REFUSED"
   rstCheck (rsPersonaAllows(true, "rp1") is false), \
         "anon persona: rp1 is REFUSED"
   rstCheck (rsPersonaAllows(true, "enet") is false), \
         "anon persona: enet is REFUSED"
   rstCheck (rsPersonaAllows(true, "dc") is false), \
         "anon persona: dataChannel is REFUSED"
   -- a public persona may use anything EXCEPT the anon onion route
   rstCheck (rsPersonaAllows(false, "dht") is true), \
         "public persona: the DHT is allowed"
   rstCheck (rsPersonaAllows(false, "torrent") is true), \
         "public persona: torrents are allowed"
   rstCheck (rsPersonaAllows(false, "rp1") is true), \
         "public persona: rp1 is allowed"
   rstCheck (rsPersonaAllows(false, "enet") is true), \
         "public persona: enet is allowed"
   rstCheck (rsPersonaAllows(false, "dc") is true), \
         "public persona: dataChannel is allowed"
   rstCheck (rsPersonaAllows(false, "onion") is false), \
         "public persona: the anon onion route is REFUSED"
   -- feed and media are in the guard's own known-transport list, so the
   -- "full truth table" must assert them too - an anon persona reaching
   -- either is the exact DHT/torrent-under-the-anon-key leak the guard
   -- exists to prevent, and a hole here would be a silent deanonymization
   rstCheck (rsPersonaAllows(true, "feed") is false), \
         "anon persona: the public feed is REFUSED"
   rstCheck (rsPersonaAllows(true, "media") is false), \
         "anon persona: torrent media is REFUSED"
   rstCheck (rsPersonaAllows(false, "feed") is true), \
         "public persona: the feed is allowed"
   rstCheck (rsPersonaAllows(false, "media") is true), \
         "public persona: media is allowed"
   -- fail-closed: an unknown transport is refused for BOTH personas
   rstCheck (rsPersonaAllows(true, "smoke-signal") is false), \
         "an unknown transport is refused for an anon persona"
   rstCheck (rsPersonaAllows(false, "smoke-signal") is false), \
         "and refused for a public persona (fail-closed)"
   -- BTXO framing
   put rsBtxoHeader("secret.txt", 11, 0) into tHeader
   rstCheck (rstHex(tHeader) is kRsGoldBtxoHeaderHex), \
         "the BTXO header bytes match golden"
   put rsBtxoParseHeader(tHeader) into tParsed
   rstCheck (tParsed["name"] is "secret.txt"), "the header name round-trips"
   rstCheck (tParsed["total"] is 11), "the header total round-trips"
   rstCheck (tParsed["flags"] is 0), "the header flags round-trip"
   put rsBtxoDataFrame(textEncode("hello world", "ASCII")) into tFrame
   rstCheck (rstHex(tFrame) is kRsGoldBtxoFrameHex), \
         "a BTXO data frame matches golden"
   rstCheck (the number of bytes in rsBtxoTerminator() is 4), \
         "the terminator is a 4-byte zero length"
   rstCheck (rsBtxoDataFrame(empty) is empty), \
         "an empty data frame is refused (use the terminator)"
   rstCheck (rsBtxoParseHeader(byte 1 to 5 of tHeader) is empty), \
         "a truncated BTXO header is refused"
   rstCheck (rsBtxoHeader("x", -1, 0) is empty), \
         "a negative total size is refused"
   -- a header whose name field is invalid UTF-8 (0xFF) passes the exact
   -- length gate but must be REFUSED, not thrown (the never-throw contract)
   rstCheck (rsBtxoParseHeader(rstBin("4254584f0100" & "0001" & "ff" & \
         "000000000000000b")) is empty), \
         "a non-UTF-8 file name in a BTXO header is refused, not thrown"
   -- the onion-service wrapper: refusals run offline
   -- 8.3: sealed DMs TO the anon persona - the phase-4 machinery composed
   -- with the anon subkeys, end to end: the persona's prekey (signed by
   -- its ANON identity), an intro from the PUBLIC identity addressed to
   -- the anon handle, sealed to the anon prekey, opened with the anon DM
   -- seed. The sender proves itself; only the persona can read it.
   put rsDmKeys(rsAnonDmSeed(rstBin(kRsGoldMasterHex), 0)) into tParsed
   rstCheck (tParsed["publicKeyHex"] is kRsGoldAnonDmKxPub), \
         "the anon DM subkey (200+n) yields the golden kx public"
   rstCheck (rsAnonDmSeed(rstBin(kRsGoldMasterHex), 0) is not \
         rsAnonSeed(rstBin(kRsGoldMasterHex), 0)), \
         "and it is a DIFFERENT subkey from the persona identity"
   rstCheck (rsAnonDmSeed(rstBin(kRsGoldMasterHex), -1) is empty), \
         "a negative persona index is refused"
   put rsBuildPrekey(kRsGoldAnonDmKxPub, \
         rsAnonSeed(rstBin(kRsGoldMasterHex), 0)) into tHeader
   rstCheck (rsVerifyPrekey(tHeader, kRsGoldAnon0Handle) is not empty), \
         "the persona's prekey verifies under its ANON handle"
   rstCheck (rsVerifyPrekey(tHeader, kRsGoldHandle) is empty), \
         "and refuses the PUBLIC handle (the personas stay unlinked)"
   put rsBuildIntro(kRsGoldMsgTs, kRsGoldAnon0Handle, kRsGoldDmKxPub, \
         rstBin(kRsGoldIdSeedHex)) into tFrame
   put rsDmSealIntro(tFrame, kRsGoldAnonDmKxPub) into tFrame
   rstCheck (tFrame is not empty), "an intro seals to the anon prekey"
   put rsDmOpenIntro(tFrame, kRsGoldAnon0Handle, \
         rsAnonDmSeed(rstBin(kRsGoldMasterHex), 0)) into tParsed
   rstCheck (tParsed is not empty), \
         "the persona opens it with its anon DM seed"
   rstCheck (tParsed["senderHandle"] is kRsGoldHandle), \
         "learning the (proven) sender"
   rstCheck (rsDmOpenIntro(tFrame, kRsGoldHandle, \
         rstBin(kRsGoldDmSeedHex)) is empty), \
         "the PUBLIC identity cannot open the persona's mail"
   -- 8.2/8.3 SERVING SEAMS: the payloads the persona's onion serves and
   -- the POST /dm acceptance. All pure, so they run right here; only the
   -- oxh* wiring and the live onion need tor (the skips below).
   put rsAnonFeedPage(kRsGoldHeadName, kRsGoldPost1Text & return & \
         kRsGoldPost2Text) into tPage
   rstCheck (rstHex(tPage) is kRsGoldAnonPageHex), \
         "the anon feed page bytes match golden"
   put textDecode(rsAnonFeedPage(kRsGoldHeadName, \
         "an <i>entry</i> & " & quote & "q" & quote), "UTF-8") into tPageText
   rstCheck (offset("<i>", tPageText) is 0 and \
         offset("&lt;i&gt;entry&lt;/i&gt; &amp; &quot;q&quot;", \
         tPageText) > 0), \
         "entries are HTML-escaped (no markup injection into the page)"
   rstCheck (rsAnonFeedPage("", "x") is empty), \
         "an empty page title is refused"
   rstCheck (rsAnonFeedPage(kRsGoldHeadName, empty) is not empty), \
         "an empty feed still serves a (bare) page"
   put rsAnonPrekeyBody(rstBin(kRsGoldMasterHex), 0) into tPkBody
   rstCheck (tPkBody is kRsGoldAnonPrekeyBody), \
         "the GET /prekey body matches golden"
   rstCheck (rsVerifyPrekey(rstBin(tPkBody), kRsGoldAnon0Handle) is not \
         empty), "and decodes to a prekey verifying under the ANON handle"
   rstCheck (rsAnonPrekeyBody(rstBin(kRsGoldMasterHex), -1) is empty), \
         "a negative persona index refuses a prekey body"
   -- the POST /dm ACCEPTANCE, against a sealed blob built with the
   -- existing 8.3 crypto (tFrame still holds the sealed intro from the
   -- open checks above) - accept the good body, refuse before decode
   -- everything else
   put rstHex(tFrame) into tHex
   put rsAnonAcceptDm(tHex, rstBin(kRsGoldMasterHex), 0) into tParsed
   rstCheck (tParsed is not empty), \
         "rsAnonAcceptDm accepts the hex-posted sealed intro"
   rstCheck (tParsed["senderHandle"] is kRsGoldHandle), \
         "and reports the proven sender"
   rstCheck (rsAnonAcceptDm(char 1 to 630 of tHex, \
         rstBin(kRsGoldMasterHex), 0) is empty), \
         "a short body is refused before any decode"
   rstCheck (rsAnonAcceptDm(tHex & "00", rstBin(kRsGoldMasterHex), 0) \
         is empty), "a long body is refused before any decode"
   rstCheck (rsAnonAcceptDm(toUpper(tHex), rstBin(kRsGoldMasterHex), 0) \
         is empty), "a non-canonical (uppercase) body is refused"
   rstCheck (rsAnonAcceptDm("zz" & char 3 to -1 of tHex, \
         rstBin(kRsGoldMasterHex), 0) is empty), \
         "a non-hex body of the right length is refused before decode"
   rstCheck (rsAnonAcceptDm(rstHex(rstFlipByte(tFrame, 20)), \
         rstBin(kRsGoldMasterHex), 0) is empty), \
         "a tampered sealed blob is refused by the seal itself"
   rstCheck (rsAnonCreateService(rstBin(kRsGoldMasterHex), 0, 0, 8080) is \
         empty), "rsAnonCreateService refuses a bad virtual port"
   rstCheck (rsAnonCreateService(rstBin(kRsGoldMasterHex), 0, 80, 70000) is \
         empty), "rsAnonCreateService refuses a bad local port"
   if pCaps["hasOnion"] is not true then
      rstSkip "anon onion service create: onionxt is not installed"
   else
      rstSkip "anon onion service create: needs a live tor daemon"
   end if
   rstSkip "anon onion SERVING (the / page, /prekey, POST /dm as routes):" && \
         "needs onion-httpd + a live tor daemon"
end rstSectionAnon

-- The BTXO RECEIVE path (backlog A3, 2026-08-23): rsBtxoStreamStep, the
-- pure length-prefix stream state machine. Entirely offline: the whole
-- point is that boundary-finding, caps, and refusal shapes are provable
-- without a Tor stream, so the scarce live-Tor slot spends its minutes on
-- reachability instead of parser bugs. The caps are nocloud's, ported.
private command rstSectionBtxoStream
   local tStream, tBuf, tStep, tPhase, tGotName, tGotTotal, tPayloads
   local tSawEnd, tRefused, tI, tHostile
   rstSection "phase 7b - the BTXO receive path (stream reassembly)"
   -- a full golden stream: header + one data frame + the terminator
   put rstBin(kRsGoldBtxoHeaderHex) & rstBin(kRsGoldBtxoFrameHex) & \
         rsBtxoTerminator() into tStream
   -- (1) whole-buffer: three steps, exact consumption, nothing left over
   put tStream into tBuf
   put rsBtxoStreamStep(tBuf, "header") into tStep
   rstCheck (tStep["status"] is "header" and tStep["name"] is \
         "secret.txt" and tStep["total"] is 11 and tStep["flags"] is 0), \
         "step 1 consumes the header and reports name/total/flags"
   rstCheck (tStep["used"] is the number of bytes in \
         rstBin(kRsGoldBtxoHeaderHex)), \
         "and used names exactly the header's bytes"
   delete byte 1 to tStep["used"] of tBuf
   put rsBtxoStreamStep(tBuf, "body") into tStep
   rstCheck (tStep["status"] is "frame" and tStep["payload"] is \
         textEncode("hello world", "ASCII")), \
         "step 2 extracts exactly one data frame"
   delete byte 1 to tStep["used"] of tBuf
   put rsBtxoStreamStep(tBuf, "body") into tStep
   rstCheck (tStep["status"] is "end" and tStep["used"] is 4), \
         "step 3 sees the zero-length terminator"
   delete byte 1 to tStep["used"] of tBuf
   rstCheck (the number of bytes in tBuf is 0), \
         "nothing is left over after the terminator"
   -- (2) EVERY byte boundary: feed the same stream one byte at a time
   -- and require the identical header, payload, and end - the arrival
   -- pattern must never change the answer
   put empty into tBuf
   put "header" into tPhase
   put empty into tGotName
   put empty into tPayloads
   put false into tSawEnd
   put false into tRefused
   repeat with tI = 1 to the number of bytes in tStream
      put byte tI of tStream after tBuf
      repeat forever
         put rsBtxoStreamStep(tBuf, tPhase) into tStep
         if tStep["status"] is "need" then
            exit repeat
         end if
         if tStep["status"] is "refused" then
            put true into tRefused
            exit repeat
         end if
         if tStep["status"] is "header" then
            put tStep["name"] into tGotName
            put tStep["total"] into tGotTotal
            put "body" into tPhase
         else if tStep["status"] is "frame" then
            put tStep["payload"] after tPayloads
         else if tStep["status"] is "end" then
            put true into tSawEnd
         end if
         delete byte 1 to tStep["used"] of tBuf
      end repeat
   end repeat
   rstCheck (tGotName is "secret.txt" and tGotTotal is 11), \
         "byte-at-a-time arrival yields the same header"
   rstCheck (tPayloads is textEncode("hello world", "ASCII")), \
         "and the same reassembled payload"
   rstCheck (tSawEnd is true and tRefused is false and \
         the number of bytes in tBuf is 0), \
         "and the same clean end, with nothing refused or left over"
   -- (3) concatenated frames: one call extracts exactly one frame and
   -- keeps the remainder
   put rstBin(kRsGoldBtxoFrameHex) & rstBin(kRsGoldBtxoFrameHex) into tBuf
   put rsBtxoStreamStep(tBuf, "body") into tStep
   rstCheck (tStep["status"] is "frame" and tStep["used"] is \
         (the number of bytes in tBuf) div 2), \
         "two concatenated frames: the first extracts alone"
   delete byte 1 to tStep["used"] of tBuf
   put rsBtxoStreamStep(tBuf, "body") into tStep
   rstCheck (tStep["status"] is "frame" and tStep["payload"] is \
         textEncode("hello world", "ASCII")), \
         "and the remainder is exactly the second frame"
   -- (4) the fail-closed refusals, each with used 0 (never consume
   -- toward a hostile boundary)
   put binaryEncode("N", 65537) & textEncode("x", "ASCII") into tHostile
   put rsBtxoStreamStep(tHostile, "body") into tStep
   rstCheck (tStep["status"] is "refused" and tStep["used"] is 0), \
         "a frame length over the 65536 cap is refused (hostile length)"
   -- a hostile nameLen refuses on the FIRST 8 BYTES, before the name
   -- would ever be buffered (the anti-DoS half of the cap)
   put textEncode("BTXO", "ASCII") & numToByte(1) & numToByte(0) & \
         binaryEncode("n", 2000) into tHostile
   put rsBtxoStreamStep(tHostile, "header") into tStep
   rstCheck (tStep["status"] is "refused"), \
         "a name length over 1024 is refused before the name arrives"
   -- a total over the 8 GiB ceiling (hi u32 = 2, lo u32 = 1)
   put textEncode("BTXO", "ASCII") & numToByte(1) & numToByte(0) & \
         binaryEncode("n", 1) & textEncode("a", "ASCII") & \
         binaryEncode("NN", 2, 1) into tHostile
   put rsBtxoStreamStep(tHostile, "header") into tStep
   rstCheck (tStep["status"] is "refused"), \
         "a total over the 8 GiB transfer ceiling is refused"
   put textEncode("XXXXXXXX", "ASCII") into tHostile
   put rsBtxoStreamStep(tHostile, "header") into tStep
   rstCheck (tStep["status"] is "refused"), "a bad magic is refused"
   put textEncode("BTXO", "ASCII") & numToByte(9) & numToByte(0) & \
         binaryEncode("n", 1) into tHostile
   put rsBtxoStreamStep(tHostile, "header") into tStep
   rstCheck (tStep["status"] is "refused"), \
         "an unsupported version is refused"
   -- a header whose name bytes are invalid UTF-8 reaches the strict
   -- parse and is refused, not thrown (the never-throw contract, reused)
   put rstBin("4254584f01000001ff000000000000000b") into tHostile
   put rsBtxoStreamStep(tHostile, "header") into tStep
   rstCheck (tStep["status"] is "refused"), \
         "a non-UTF-8 name is refused through the strict parse"
   -- incompleteness is "need", never a guess
   put rsBtxoStreamStep(byte 1 to 3 of tStream, "header") into tStep
   rstCheck (tStep["status"] is "need"), \
         "three bytes of header is need, not a verdict"
   put binaryEncode("N", 5) & textEncode("ab", "ASCII") into tHostile
   put rsBtxoStreamStep(tHostile, "body") into tStep
   rstCheck (tStep["status"] is "need"), \
         "a frame missing payload bytes is need, not a verdict"
   -- the one caller bug: a phase this machine does not have
   rstCheck (rsBtxoStreamStep(tStream, "junk") is empty), \
         "an unknown phase is a caller bug (empty, rsLastError says why)"
end rstSectionBtxoStream

-- The phase-6 LAN admission layer. Entirely pure crypto (no transport),
-- so it runs on SodiumXT alone - which is right: the admission proof is
-- what MUST hold before any enet peer is trusted, and it is provable
-- without a network. The golden challenge/response use a FIXED nonce; a
-- real host uses sxRandomBytes, and the "fresh nonce refuses a stale
-- response" property is checked with a second, different nonce.
private command rstSectionLan
   local tKeys, tChallenge, tResponse, tNonce2, tChallenge2, tName, tBadName
   local tBadUtf, tWelcome
   rstSection "phase 6 - LAN mesh admission"
   put rsLanKeys(rstBin(kRsGoldMasterHex)) into tKeys
   rstCheck (rstHex(tKeys["publicKey"]) is kRsGoldLanPub), \
         "the LAN subkey yields the golden mesh public"
   rstCheck (the number of bytes in tKeys["secretKey"] is 64), \
         "and a 64-byte signing secret"
   put rsLanBuildChallenge(kRsGoldLanHostName, rstBin(kRsGoldLanNonce)) \
         into tChallenge
   rstCheck (rstHex(tChallenge) is kRsGoldLanChallengeHex), \
         "the challenge bytes match golden"
   put rsLanParseChallenge(tChallenge) into tName
   rstCheck (tName["name"] is kRsGoldLanHostName), \
         "the host name round-trips out of the challenge"
   rstCheck (rstHex(tName["nonce"]) is kRsGoldLanNonce), \
         "the nonce round-trips out of the challenge"
   put rsLanBuildResponse(tChallenge, kRsGoldLanJoinName, \
         rstBin(kRsGoldMasterHex)) into tResponse
   rstCheck (rstHex(tResponse) is kRsGoldLanResponseHex), \
         "the response bytes match golden"
   put rsLanParseResponse(tResponse) into tName
   rstCheck (tName["name"] is kRsGoldLanJoinName), \
         "the joiner name round-trips out of the response"
   -- the host's verdict: this response proves the shared master
   put rsLanVerifyResponse(tResponse, tChallenge, rstBin(kRsGoldMasterHex)) \
         into tName
   rstCheck (tName is kRsGoldLanJoinName), \
         "the host admits a joiner who shares the master, learning its name"
   -- a STRANGER: a response built under a different master must be refused
   -- by a host holding the golden master
   put rsLanBuildResponse(tChallenge, kRsGoldLanJoinName, \
         rstBin(kRsGoldConfSeedHex)) into tBadName
   rstCheck (rsLanVerifyResponse(tBadName, tChallenge, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a joiner who does NOT share the master is refused"
   -- freshness: the same response against a DIFFERENT challenge nonce fails
   -- (this is why the nonce must never be reused)
   put rstBin(kRsGoldMasterHex) into tNonce2
   put rsLanBuildChallenge(kRsGoldLanHostName, \
         byte 1 to 32 of (tNonce2 & tNonce2)) into tChallenge2
   rstCheck (rsLanVerifyResponse(tResponse, tChallenge2, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a response replayed against a fresh nonce is refused"
   -- tamper and cap refusals
   rstCheck (rsLanVerifyResponse(rstFlipByte(tResponse, 60), tChallenge, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a tampered response is refused"
   rstCheck (rsLanParseChallenge(byte 1 to 20 of tChallenge) is empty), \
         "a truncated challenge is refused"
   rstCheck (rsLanBuildChallenge("laptop", byte 1 to 31 of \
         rstBin(kRsGoldLanNonce)) is empty), \
         "a 31-byte nonce is refused"
   rstCheck (rsLanBuildChallenge("", rstBin(kRsGoldLanNonce)) is empty), \
         "an empty device name is refused"
   -- a name field of INVALID UTF-8 (0xFF 0xFE) passes the exact-length gate
   -- but must be REFUSED, not thrown, out of the parser (the never-throw
   -- contract; a LAN peer could otherwise crash the admission drain)
   put rstBin("52534c314302fffe") & rstBin(kRsGoldLanNonce) into tBadUtf
   rstCheck (rsLanParseChallenge(tBadUtf) is empty), \
         "a non-UTF-8 device name in a challenge is refused, not thrown"
   put rstBin("52534c31520180") & (byte -64 to -1 of tResponse) into tBadUtf
   rstCheck (rsLanParseResponse(tBadUtf) is empty), \
         "a non-UTF-8 device name in a response is refused, not thrown"
   -- the W welcome: mutual auth back to the joiner, bound to THIS handshake
   put rsLanBuildWelcome(tResponse, kRsGoldLanHostName, \
         rstBin(kRsGoldMasterHex)) into tWelcome
   rstCheck (rstHex(tWelcome) is kRsGoldLanWelcomeHex), \
         "the welcome bytes match golden"
   put rsLanParseWelcome(tWelcome) into tName
   rstCheck (tName["name"] is kRsGoldLanHostName), \
         "the host name round-trips out of the welcome"
   put rsLanVerifyWelcome(tWelcome, tResponse, rstBin(kRsGoldMasterHex)) \
         into tName
   rstCheck (tName is kRsGoldLanHostName), \
         "the joiner verifies the host shares the master, learning ITS name"
   -- a rogue host: a welcome built under a different master is refused
   put rsLanBuildWelcome(tResponse, kRsGoldLanHostName, \
         rstBin(kRsGoldConfSeedHex)) into tBadName
   rstCheck (rsLanVerifyWelcome(tBadName, tResponse, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a welcome from a host that does NOT share the master is refused"
   -- handshake binding: the welcome must not verify against a DIFFERENT
   -- response (a captured welcome cannot admit a later session)
   put rsLanBuildResponse(tChallenge2, kRsGoldLanJoinName, \
         rstBin(kRsGoldMasterHex)) into tBadName
   rstCheck (rsLanVerifyWelcome(tWelcome, tBadName, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a welcome replayed against another handshake is refused"
   rstCheck (rsLanVerifyWelcome(rstFlipByte(tWelcome, 70), tResponse, \
         rstBin(kRsGoldMasterHex)) is empty), \
         "a tampered welcome is refused"
   rstCheck (rsLanParseWelcome(byte 1 to 30 of tWelcome) is empty), \
         "a truncated welcome is refused"
   put rstBin("52534c31570180") & (byte -64 to -1 of tWelcome) into tBadUtf
   rstCheck (rsLanParseWelcome(tBadUtf) is empty), \
         "a non-UTF-8 host name in a welcome is refused, not thrown"
end rstSectionLan

-- The phase-6 SYNC records over the admitted mesh: pure crypto again (no
-- transport), signed under the same shared LAN key as the admission with
-- the distinct "riptide-lan-s" domain over the whole body. Build + verify
-- + a distinct refusal per record kind, the stranger/tamper refusals, and
-- the two hand-signed forgeries the builders cannot produce (a valid
-- signature over a non-UTF-8 name; a valid signature over unknown flag
-- bits) so the post-verification refusal paths run too.
private command rstSectionLanSync
   local tMaster, tKeys, tRec, tOut, tBytes, tBody
   rstSection "phase 6 - LAN sync records (drafts, feed state, presence)"
   put rstBin(kRsGoldMasterHex) into tMaster
   put rsLanKeys(tMaster) into tKeys
   -- the draft record (channel 0, reliable)
   put rsLanBuildDraft(kRsGoldLanJoinName, kRsGoldLanSeq, \
         kRsGoldLanDraftText, tMaster) into tRec
   rstCheck (rstHex(tRec) is kRsGoldLanDraftHex), \
         "the draft record bytes match golden"
   put rsLanVerifyDraft(tRec, tMaster) into tOut
   rstCheck (tOut["name"] is kRsGoldLanJoinName), \
         "the draft's device name verifies and round-trips"
   rstCheck (tOut["seq"] is kRsGoldLanSeq + 0), \
         "the draft's per-device seq round-trips"
   rstCheck (tOut["draft"] is kRsGoldLanDraftText), \
         "the draft text round-trips"
   -- absolute state: an EMPTY draft is legal and means cleared
   put rsLanBuildDraft(kRsGoldLanJoinName, 6, empty, tMaster) into tBytes
   put rsLanVerifyDraft(tBytes, tMaster) into tOut
   rstCheck (tOut is not empty and tOut["draft"] is empty), \
         "an empty draft builds and verifies (cleared state)"
   -- the stranger: a record signed under a DIFFERENT master is refused
   put rsLanBuildDraft(kRsGoldLanJoinName, kRsGoldLanSeq, \
         kRsGoldLanDraftText, rstBin(kRsGoldConfSeedHex)) into tBytes
   rstCheck (rsLanVerifyDraft(tBytes, tMaster) is empty), \
         "a stranger's draft record is refused"
   rstCheck (rsLanVerifyDraft(rstFlipByte(tRec, 30), tMaster) is empty), \
         "a tampered draft record is refused"
   rstCheck (rsLanVerifyDraft(byte 1 to 40 of tRec, tMaster) is empty), \
         "a truncated draft record is refused"
   rstCheck (rsLanBuildDraft(kRsGoldLanJoinName, -1, "x", tMaster) \
         is empty), "a negative draft seq is refused"
   -- a hand-signed record with a non-UTF-8 name: the signature is VALID
   -- (only a master-holder could make it), so this exercises the
   -- refusal AFTER the proof - refused clean, never thrown, never mangled
   put rstBin("52534c3144") & numToByte(2) & rstBin("fffe") & \
         rstBin("0000000000000001") & rstBin("0000") into tBody
   put tBody & sxSignDetached(textEncode("riptide-lan-s", "ASCII") & \
         tBody, tKeys["secretKey"]) into tBytes
   rstCheck (rsLanVerifyDraft(tBytes, tMaster) is empty), \
         "a validly signed draft with a non-UTF-8 name is refused, not thrown"
   -- the feed-state record (channel 0): feedSeq + an optional read receipt
   put rsLanBuildFeedState(kRsGoldLanJoinName, kRsGoldLanFeedSeq, \
         kRsGoldHandle, kRsGoldLanReadTs, tMaster) into tRec
   rstCheck (rstHex(tRec) is kRsGoldLanFeedStateHex), \
         "the feed-state record bytes match golden"
   put rsLanVerifyFeedState(tRec, tMaster) into tOut
   rstCheck (tOut["feedSeq"] is kRsGoldLanFeedSeq + 0), \
         "the feed seq verifies and round-trips"
   rstCheck (tOut["readPeer"] is kRsGoldHandle), \
         "the read-receipt peer round-trips"
   rstCheck (tOut["readUpTo"] is kRsGoldLanReadTs + 0), \
         "the read-up-to timestamp round-trips"
   -- an empty peer travels as the all-zeros handle and parses back EMPTY
   put rsLanBuildFeedState(kRsGoldLanJoinName, 1, empty, 0, tMaster) \
         into tBytes
   put rsLanVerifyFeedState(tBytes, tMaster) into tOut
   rstCheck (tOut is not empty and tOut["readPeer"] is empty), \
         "a pure feed-seq claim (no receipt) round-trips the none spelling"
   put rsLanBuildFeedState(kRsGoldLanJoinName, 1, empty, 0, \
         rstBin(kRsGoldConfSeedHex)) into tBytes
   rstCheck (rsLanVerifyFeedState(tBytes, tMaster) is empty), \
         "a stranger's feed-state record is refused"
   rstCheck (rsLanBuildFeedState(kRsGoldLanJoinName, 1, "zz", 0, tMaster) \
         is empty), "a malformed read-receipt peer is refused at build"
   -- the presence record (channel 1, unreliable-unsequenced)
   put rsLanBuildPresence(kRsGoldLanJoinName, true, kRsGoldLanTick, \
         tMaster) into tRec
   rstCheck (rstHex(tRec) is kRsGoldLanPresenceHex), \
         "the presence record bytes match golden"
   put rsLanVerifyPresence(tRec, tMaster) into tOut
   rstCheck (tOut["typing"] is true and tOut["tick"] is kRsGoldLanTick + 0), \
         "typing state and tick verify and round-trip"
   put rsLanBuildPresence(kRsGoldLanJoinName, false, 4, tMaster) into tBytes
   put rsLanVerifyPresence(tBytes, tMaster) into tOut
   rstCheck (tOut is not empty and tOut["typing"] is false), \
         "the not-typing absolute state round-trips"
   put rsLanBuildPresence(kRsGoldLanJoinName, true, 1, \
         rstBin(kRsGoldConfSeedHex)) into tBytes
   rstCheck (rsLanVerifyPresence(tBytes, tMaster) is empty), \
         "a stranger's presence record is refused"
   -- a hand-signed record with UNKNOWN flag bits (2): a valid signature,
   -- refused fail-closed - a newer format must never half-parse
   put rstBin("52534c3150") & numToByte(5) & \
         textEncode(kRsGoldLanJoinName, "UTF-8") & numToByte(2) & \
         rstBin("0000000000000001") into tBody
   put tBody & sxSignDetached(textEncode("riptide-lan-s", "ASCII") & \
         tBody, tKeys["secretKey"]) into tBytes
   rstCheck (rsLanVerifyPresence(tBytes, tMaster) is empty), \
         "a validly signed presence record with unknown flags is refused"
   -- no cross-kind reads: one record kind can never verify as another
   rstCheck (rsLanVerifyDraft(tRec, tMaster) is empty), \
         "a presence record fed to the draft verifier is refused"
   -- the media-handoff record (channel 0: the channel-2 decision - a
   -- signed POINTER at the phase-3 torrent path; the pointed-at hash is
   -- the same placeholder info-hash the golden post-2 media list names)
   put rsLanBuildHandoff(kRsGoldLanJoinName, kRsGoldLanMediaSeq, \
         kRsGoldMediaTarget, kRsGoldLanFileName, kRsGoldLanFileSize, \
         tMaster) into tRec
   rstCheck (rstHex(tRec) is kRsGoldLanHandoffHex), \
         "the media-handoff record bytes match golden"
   put rsLanVerifyHandoff(tRec, tMaster) into tOut
   rstCheck (tOut["name"] is kRsGoldLanJoinName), \
         "the handoff's device name verifies and round-trips"
   rstCheck (tOut["seq"] is kRsGoldLanMediaSeq + 0), \
         "the handoff's per-device seq round-trips"
   rstCheck (tOut["infoHash"] is kRsGoldMediaTarget), \
         "the handoff's info-hash round-trips"
   rstCheck (tOut["fileName"] is kRsGoldLanFileName), \
         "the handoff's file name round-trips"
   rstCheck (tOut["fileSize"] is kRsGoldLanFileSize + 0), \
         "the handoff's file size round-trips"
   -- the build normalizes hash case; the WIRE stays strict lowercase.
   -- Compared as HEX against the golden, not with `is` on the Data -
   -- `is` folds case, so a non-normalizing build could pass a bytes
   -- compare (the vacuous-check trap)
   put rsLanBuildHandoff(kRsGoldLanJoinName, kRsGoldLanMediaSeq, \
         toUpper(kRsGoldMediaTarget), kRsGoldLanFileName, \
         kRsGoldLanFileSize, tMaster) into tBytes
   rstCheck (rstHex(tBytes) is kRsGoldLanHandoffHex), \
         "an uppercase info-hash normalizes to the same handoff bytes"
   rstCheck (rsLanBuildHandoff(kRsGoldLanJoinName, 1, \
         rsZeroTarget(), "f", 1, tMaster) is empty), \
         "the all-zeros info-hash is refused at build (no empty handoff)"
   rstCheck (rsLanBuildHandoff(kRsGoldLanJoinName, 1, "zz", "f", 1, \
         tMaster) is empty), "a malformed info-hash is refused at build"
   rstCheck (rsLanBuildHandoff(kRsGoldLanJoinName, 1, \
         kRsGoldMediaTarget, empty, 1, tMaster) is empty), \
         "an empty file name is refused at build"
   put rsLanBuildHandoff(kRsGoldLanJoinName, kRsGoldLanMediaSeq, \
         kRsGoldMediaTarget, kRsGoldLanFileName, kRsGoldLanFileSize, \
         rstBin(kRsGoldConfSeedHex)) into tBytes
   rstCheck (rsLanVerifyHandoff(tBytes, tMaster) is empty), \
         "a stranger's handoff record is refused"
   rstCheck (rsLanVerifyHandoff(rstFlipByte(tRec, 25), tMaster) is empty), \
         "a tampered handoff record is refused"
   rstCheck (rsLanVerifyHandoff(byte 1 to 60 of tRec, tMaster) is empty), \
         "a truncated handoff record is refused"
   -- a hand-signed record with a non-UTF-8 FILE name: the signature is
   -- VALID, so this exercises the refusal AFTER the proof (the draft
   -- forgery's discipline, on the handoff's second text field)
   put rstBin("52534c314d") & numToByte(5) & \
         textEncode(kRsGoldLanJoinName, "UTF-8") & \
         rstBin("0000000000000001") & \
         textEncode(kRsGoldMediaTarget, "ASCII") & numToByte(2) & \
         rstBin("fffe") & rstBin("0000000000000001") into tBody
   put tBody & sxSignDetached(textEncode("riptide-lan-s", "ASCII") & \
         tBody, tKeys["secretKey"]) into tBytes
   rstCheck (rsLanVerifyHandoff(tBytes, tMaster) is empty), \
         "a validly signed handoff with a non-UTF-8 file name is refused"
   -- a hand-signed record with an UPPERCASE hash on the wire: valid
   -- signature, non-canonical spelling - refused (the coinxt lesson)
   put rstBin("52534c314d") & numToByte(5) & \
         textEncode(kRsGoldLanJoinName, "UTF-8") & \
         rstBin("0000000000000001") & \
         textEncode(toUpper(kRsGoldMediaTarget), "ASCII") & \
         numToByte(1) & textEncode("f", "UTF-8") & \
         rstBin("0000000000000001") into tBody
   put tBody & sxSignDetached(textEncode("riptide-lan-s", "ASCII") & \
         tBody, tKeys["secretKey"]) into tBytes
   rstCheck (rsLanVerifyHandoff(tBytes, tMaster) is empty), \
         "a validly signed handoff with an uppercase hash is refused"
   -- cross-kind, both directions for the new kind
   rstCheck (rsLanVerifyDraft(tRec, tMaster) is empty), \
         "a handoff record fed to the draft verifier is refused"
   put rsLanBuildDraft(kRsGoldLanJoinName, kRsGoldLanSeq, \
         kRsGoldLanDraftText, tMaster) into tBytes
   rstCheck (rsLanVerifyHandoff(tBytes, tMaster) is empty), \
         "a draft record fed to the handoff verifier is refused"
end rstSectionLanSync

-- The phase-4 DM layer. The pure half (keys, records, session derivation,
-- seal round trip, the message-through-a-secretstream path) runs on
-- SodiumXT alone; the live half (inbox join, framed send) mirrors the
-- other live sections: refusals everywhere, real calls behind hasTorrent.
-- Both sides of every pair are derived HERE, so the cross-match claims
-- (my tx is your rx; the seal opens only for its recipient) are engine
-- results, not assumptions.
private command rstSectionDm pCaps
   local tSeed, tMyKeys, tConfKeys, tSess, tSessB, tPrekey, tIntro
   local tSealed, tOpened, tFrame, tParsed, tMsg, tBig, tDir, tErr
   local tHeader, tPush, tPull, tCipher, tCipher2, tPlain, tTag, tSession, tH
   rstSection "phase 4 - DM keys, records, and the sealed first contact"
   put rstBin(kRsGoldIdSeedHex) into tSeed
   -- keys: the kx pair from the DM subkey, pinned against real libsodium
   put rsDmKeys(rstBin(kRsGoldDmSeedHex)) into tMyKeys
   rstCheck (tMyKeys["publicKeyHex"] is kRsGoldDmKxPub), \
         "the DM subkey yields the golden kx public"
   rstCheck (the number of bytes in tMyKeys["secretKey"] is 32), \
         "and a 32-byte kx secret"
   put rsDmKeys(rstBin(kRsGoldConfSeedHex)) into tConfKeys
   rstCheck (tConfKeys["publicKeyHex"] is kRsGoldConfKxPub), \
         "the conformance seed yields its golden kx public"
   rstCheck (rsDmKeys(byte 1 to 31 of tSeed) is empty), \
         "a 31-byte DM seed is refused"
   -- one session, two roles, derived from BOTH ends: the golden handle
   -- sorts below the conformance pub, so the golden side is the client
   put rsDmSessionKeys(kRsGoldHandle, tMyKeys, kRsGoldConfPub, \
         kRsGoldConfKxPub) into tSess
   rstCheck (tSess["role"] is "client"), \
         "the lexically smaller handle takes the client role"
   rstCheck (rstHex(tSess["rx"]) is kRsGoldSessionRx), \
         "client rx matches the libsodium-anchored golden"
   rstCheck (rstHex(tSess["tx"]) is kRsGoldSessionTx), \
         "client tx matches the libsodium-anchored golden"
   put rsDmSessionKeys(kRsGoldConfPub, tConfKeys, kRsGoldHandle, \
         kRsGoldDmKxPub) into tSessB
   rstCheck (tSessB["role"] is "server"), "the peer takes the server role"
   rstCheck (rstHex(tSessB["rx"]) is kRsGoldSessionTx), \
         "my tx is the peer's rx"
   rstCheck (rstHex(tSessB["tx"]) is kRsGoldSessionRx), \
         "and my rx is the peer's tx"
   rstCheck (rsDmSessionKeys(kRsGoldHandle, tMyKeys, kRsGoldHandle, \
         kRsGoldConfKxPub) is empty), \
         "a session with myself is refused"
   rstCheck (rsDmSessionKeys("zz", tMyKeys, kRsGoldConfPub, \
         kRsGoldConfKxPub) is empty), "a malformed handle is refused"
   -- RSK1: the signed prekey record
   put rsBuildPrekey(kRsGoldDmKxPub, tSeed) into tPrekey
   rstCheck (rstHex(tPrekey) is kRsGoldPrekeyRecHex), \
         "prekey record bytes match golden"
   rstCheck (rsImmutableTarget(tPrekey) is kRsGoldPrekeyRecTarget), \
         "and its DHT target re-derives"
   put rsParsePrekey(tPrekey) into tParsed
   rstCheck (tParsed["kxPub"] is kRsGoldDmKxPub), "prekey kx round-trips"
   put rsVerifyPrekey(tPrekey, kRsGoldHandle) into tParsed
   rstCheck (tParsed is not empty), "the prekey verifies under its author"
   rstCheck (rsVerifyPrekey(tPrekey, kRsGoldConfPub) is empty), \
         "and refuses a different author"
   rstCheck (rsVerifyPrekey(rstFlipByte(tPrekey, 10), kRsGoldHandle) is \
         empty), "a tampered prekey is refused"
   rstCheck (rsParsePrekey(byte 1 to 131 of tPrekey) is empty), \
         "a truncated prekey is refused"
   rstCheck (rsBuildPrekey("zz", tSeed) is empty), \
         "a malformed kx public is refused at build"
   -- RSI1: the intro, built by the golden identity FOR the conformance
   -- identity; the sender handle comes from the signing seed, never an arg
   put rsBuildIntro(kRsGoldDmTs, kRsGoldConfPub, kRsGoldDmKxPub, tSeed) \
         into tIntro
   rstCheck (rstHex(tIntro) is kRsGoldIntroHex), \
         "intro record bytes match golden"
   put rsParseIntro(tIntro) into tParsed
   rstCheck (tParsed["senderHandle"] is kRsGoldHandle), \
         "the sender handle round-trips"
   rstCheck (tParsed["senderKxPub"] is kRsGoldDmKxPub), \
         "the sender kx public round-trips"
   rstCheck (tParsed["recipientHandle"] is kRsGoldConfPub), \
         "the recipient handle round-trips"
   rstCheck (tParsed["timestamp"] is 1754870520), "the timestamp round-trips"
   put rsVerifyIntro(tIntro, kRsGoldConfPub) into tParsed
   rstCheck (tParsed is not empty), "the intro verifies for its recipient"
   rstCheck (rsVerifyIntro(tIntro, kRsGoldHandle) is empty), \
         "and refuses a recipient it is not addressed to"
   rstCheck (rsVerifyIntro(rstFlipByte(tIntro, 200), kRsGoldConfPub) is \
         empty), "a tampered intro fails its signature"
   rstCheck (rsParseIntro(tIntro & numToByte(0)) is empty), \
         "trailing bytes are refused"
   -- the seal: to the recipient's kx prekey; only the recipient opens it
   put rsDmSealIntro(tIntro, kRsGoldConfKxPub) into tSealed
   rstCheck (tSealed is not empty), "the intro seals to the recipient prekey"
   rstCheck (the number of bytes in tSealed is 268 + 48), \
         "the sealed intro carries the 48-byte seal overhead"
   put rsDmOpenIntro(tSealed, kRsGoldConfPub, rstBin(kRsGoldConfSeedHex)) \
         into tOpened
   rstCheck (tOpened is not empty), "the recipient opens and verifies it"
   rstCheck (tOpened["senderHandle"] is kRsGoldHandle), \
         "learning who is calling"
   rstCheck (tOpened["senderKxPub"] is kRsGoldDmKxPub), \
         "and the key to answer on"
   rstCheck (rsDmOpenIntro(tSealed, kRsGoldHandle, \
         rstBin(kRsGoldDmSeedHex)) is empty), \
         "a NON-recipient cannot open the seal"
   rstCheck (rsDmOpenIntro(rstFlipByte(tSealed, 40), kRsGoldConfPub, \
         rstBin(kRsGoldConfSeedHex)) is empty), \
         "a tampered seal is refused"
   -- RSM1 frames: canonical kinds by byte value, strict parse
   put rsDmFrame("I", tSealed) into tFrame
   rstCheck (tFrame is not empty), "an intro frame builds"
   put rsDmParseFrame(tFrame) into tParsed
   rstCheck (tParsed["kind"] is "I"), "the frame kind round-trips"
   rstCheck (tParsed["payload"] is tSealed), "the frame payload round-trips"
   rstCheck (rsDmFrame("X", tSealed) is empty), \
         "an unknown frame kind is refused"
   rstCheck (rsDmFrame("i", tSealed) is empty), \
         "a lowercase kind is refused (canonical bytes, not folded case)"
   rstCheck (rsDmFrame("M", empty) is empty), \
         "an empty frame payload is refused"
   put "x" into tBig
   repeat 16 times
      put tBig & tBig into tBig
   end repeat
   rstCheck (rsDmFrame("M", textEncode(tBig, "ASCII")) is empty), \
         "a frame over the rp1 cap is refused"
   rstCheck (rsDmParseFrame(byte 1 to 5 of tFrame) is empty), \
         "a payload-less frame is refused"
   -- the message record, and the whole DM message path through a REAL
   -- secretstream: build -> push (my tx) -> pull (peer rx = same key)
   -- -> parse. The stream handles are freed even though the section is
   -- pure - sodiumxt has no unload hook (its own rule).
   put rsDmMessageBody("T", kRsGoldMsgTs, kRsGoldDmMsgText) into tMsg
   rstCheck (rstHex(tMsg) is kRsGoldDmMsgHex), \
         "message record bytes match golden"
   put rsDmParseMessage(tMsg) into tParsed
   rstCheck (tParsed["kind"] is "T"), "message kind round-trips"
   rstCheck (tParsed["timestamp"] is 1754870580), \
         "message timestamp round-trips"
   rstCheck (tParsed["text"] is kRsGoldDmMsgText), "message text round-trips"
   rstCheck (rsDmMessageBody("X", 1, "hi") is empty), \
         "an unknown message kind is refused"
   rstCheck (rsDmMessageBody("T", 1, empty) is empty), \
         "an empty message body is refused"
   rstCheck (rsDmParseMessage(byte 1 to 9 of tMsg) is empty), \
         "a truncated message record is refused"
   put sxSecretStreamInitPush(tSess["tx"], tHeader) into tPush
   put sxSecretStreamPush(tPush, tMsg, empty, false) into tCipher
   rstCheck (the number of bytes in tCipher > the number of bytes in tMsg), \
         "the stream ciphertext carries its auth overhead"
   put sxSecretStreamInitPull(tSessB["rx"], tHeader) into tPull
   put sxSecretStreamPull(tPull, tCipher, empty, tTag) into tPlain
   rstCheck (tPlain is tMsg), \
         "the peer's rx key decrypts what my tx key sent"
   rstCheck (sxIsFinalTag(tTag) is false), "mid-stream is not final"
   put sxSecretStreamPush(tPush, tMsg, empty, true) into tCipher2
   put sxSecretStreamPull(tPull, tCipher2, empty, tTag) into tPlain
   rstCheck (sxIsFinalTag(tTag) is true), \
         "the final tag survives the stream"
   sxFreeStream tPush
   sxFreeStream tPull
   -- the live half: refusals run everywhere, the join runs on a session
   rstCheck (rsDmJoinInbox(0, "zz", "/") is empty), \
         "rsDmJoinInbox refuses a malformed handle first"
   rstCheck (rsDmSend(0, 1, textEncode("junk", "ASCII")) is false), \
         "rsDmSend refuses a non-RSM1 frame"
   rstCheck (rsDmSend(0, 1, tFrame) is false), \
         "rsDmSend refuses a dead session handle"
   rstCheck (rsDmSend(0, 0, tFrame) is false), \
         "rsDmSend refuses a bad peer id"
   if pCaps["hasTorrent"] is not true then
      rstSkip "DM inbox join + framed send: torrentxt is not installed"
      exit rstSectionDm
   end if
   put rstAcquireSession() into tSession
   if tSession is 0 then
      rstSkip "DM inbox join + framed send: could not start a session"
      exit rstSectionDm
   end if
   put specialFolderPath("temporary") into tDir
   if tDir is empty then put specialFolderPath("documents") into tDir
   if the last char of tDir is "/" then delete the last char of tDir
   rstCheck (rsDmJoinInbox(tSession, kRsGoldHandle, \
         tDir & "/riptide-no-such-folder") is empty), \
         "rsDmJoinInbox refuses a missing save path"
   put rsDmJoinInbox(tSession, kRsGoldHandle, tDir) into tH
   rstCheck (tH is not empty and tH > 0), \
         "joining the inbox swarm returns its live handle"
   rstCheck (rsDmSend(tSession, 999999999, tFrame) is false), \
         "rsDmSend to an unknown peer is refused by the binding"
   -- tidy: drop the phantom swarm so a re-run starts clean
   if tH is not empty and tH > 0 then
      try
         btRemoveTorrent tSession, tH, false
      catch tErr
         -- best effort; the harness rule keeps the session itself alive
      end try
   end if
end rstSectionDm

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

-- The phase-3 media layer. The refusal paths run EVERYWHERE (every input
-- is validated before any bt* handler is touched); the live half creates a
-- real torrent over a temp file, seeds it in place, resolves it back
-- through rsMediaFetch's find path, and reads it through rsMediaStatus -
-- all local to this machine, so nothing waits on a network. The swarm half
-- (a second machine fetching by hash and playing mid-download) is the
-- phase-3 done-criterion and needs the two-machine pass. The payload is
-- salted with the clock so a crashed run's leftover torrent (same file,
-- different bytes) can never collide with this run's add.
private command rstSectionMedia pCaps
   local tSession, tDir, tPath, tHash, tH, tFound, tS, tCode, tErr
   rstSection "phase 3 - media create/seed/fetch/status"
   rstCheck (rsMediaCreate(0, empty) is empty), \
         "rsMediaCreate refuses an empty path"
   rstCheck (rsLastError() contains "file"), "and says why"
   put specialFolderPath("temporary") into tDir
   if tDir is empty then put specialFolderPath("documents") into tDir
   if the last char of tDir is "/" then delete the last char of tDir
   put tDir & "/riptide-media-selftest.bin" into tPath
   put "riptide media selftest payload," && the milliseconds \
         into url ("binfile:" & tPath)
   rstCheck (rsMediaCreate(0, tPath) is empty), \
         "rsMediaCreate refuses a dead session handle"
   rstCheck (rsLastError() contains "session"), "and says why"
   rstCheck (rsMediaFetch(0, "zz", tDir, false) is empty), \
         "rsMediaFetch refuses a malformed info-hash"
   rstCheck (rsMediaFetch(0, rsZeroTarget(), tDir, false) is empty), \
         "rsMediaFetch refuses the zero info-hash"
   rstCheck (rsMediaFetch(0, kRsGoldMediaTarget, \
         tDir & "/riptide-no-such-folder", false) is empty), \
         "rsMediaFetch refuses a missing save folder"
   rstCheck (rsMediaFetch(0, kRsGoldMediaTarget, tDir, false) is empty), \
         "rsMediaFetch refuses a dead session handle"
   rstCheck (rsMediaStatus(0) is empty), \
         "rsMediaStatus refuses a dead torrent handle"
   -- B7: the streaming plan's refusal paths run everywhere too - the
   -- handle gate needs no torrentxt, and a bogus handle refuses either
   -- way (bad handle with torrentxt, needs-torrentxt without)
   rstCheck (rsMediaStreamPlan(0) is empty), \
         "rsMediaStreamPlan refuses a dead torrent handle"
   rstCheck (rsMediaStreamPlan(999999999) is empty), \
         "rsMediaStreamPlan refuses a bogus handle"
   if pCaps["hasTorrent"] is not true then
      rstSkip "media create/seed/fetch/status: torrentxt is not installed"
      exit rstSectionMedia
   end if
   put rstAcquireSession() into tSession
   if tSession is 0 then
      rstSkip "media create/seed/fetch/status: could not start a session"
      exit rstSectionMedia
   end if
   put rsMediaCreate(tSession, tPath) into tHash
   rstCheck (the number of chars in tHash is 40), \
         "rsMediaCreate returns a 40-hex info-hash"
   if the number of chars in tHash is not 40 then
      put "      rsMediaCreate said:" && rsLastError() & return after sLog
      exit rstSectionMedia
   end if
   -- We are this hash's seeder, so the fetch lands on its find path: the
   -- live handle comes back (no duplicate-add error) with the sequential
   -- flag applied - the idempotency a re-click or a restart depends on.
   put rsMediaFetch(tSession, tHash, tDir, true) into tH
   rstCheck (tH is not empty and tH > 0), \
         "rsMediaFetch on a seeding hash returns its live handle"
   try
      put btFindTorrent(tSession, tHash) into tFound
   catch tErr
      put 0 into tFound
   end try
   rstCheck (tFound is tH), "and it is the handle btFindTorrent names"
   put rsMediaStatus(tH) into tS
   rstCheck (tS is an array), "rsMediaStatus returns a snapshot"
   rstCheck (toLower(tS["infoHashV1"]) is tHash), \
         "whose info-hash is the created one"
   rstCheck (tS["name"] contains "riptide-media-selftest"), \
         "whose name is the attached file's"
   rstCheck (tS["filePath"] is not empty), \
         "with the player path resolved (metadata is local)"
   rstCheck (there is a file tS["filePath"]), \
         "and the player path names the on-disk file"
   rstCheck (tS["fileSize"] > 0), "with the file's size beside it"
   rstCheck (tS["progress"] >= 0 and tS["progress"] <= 1), \
         "progress is a 0..1 fraction"
   rstCheck (rsMediaStatus(999999999) is empty), \
         "rsMediaStatus refuses a bogus handle"
   -- B7 live: the local seed HAS metadata (its piece table exists), so
   -- the plan applies right here; on a real magnet fetch the app calls
   -- this from its metadataReceived event. The payload is tiny, so the
   -- plan covers 1..8 front pieces.
   put rsMediaStreamPlan(tH) into tCode
   rstCheck (tCode is not empty and tCode >= 1 and \
         tCode <= 8), "rsMediaStreamPlan sets deadlines on the front pieces"
   -- tidy: drop the seed we added so a re-run starts clean; the payload
   -- file stays (temp folder) and the session stays live (the harness rule)
   try
      btRemoveTorrent tSession, tH, false
      put the result into tCode
   catch tErr
      put -1 into tCode
   end try
   rstCheck (tCode is 0), "cleanup: the media torrent removes"
end rstSectionMedia
