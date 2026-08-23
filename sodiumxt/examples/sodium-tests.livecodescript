-- sodium-tests.livecodescript - an xTalk self-test harness for SodiumXT.
--
-- Exercises every public sx* capability with round-trips, known-answer vectors,
-- and tamper / wrong-key checks (the negative paths use try/catch, because the
-- sx* handlers throw on an authentication failure rather than return garbage).
--
-- How to run, once the SodiumXT extension is installed (so org.openxtalk.library
-- .sodium is loaded): put this script where its handlers are in scope (e.g. set
-- it as a stack script, or `start using` this script-only stack), then from the
-- message box:
--     put sxSelfTest()
-- It returns a per-check report and a PASSED/FAILED summary.
--
-- NOTE on the Data-based API: hex/base64 and the pwhash string cross as Data
-- (the ASCII bytes); textDecode them here when a String is wanted. A passphrase
-- is textEncoded to UTF-8 before it crosses.
--
-- Engine-verified through ABI 9: the "run it in OXT to confirm" label that
-- stood here is retired by recorded passes - the complete harness ran green
-- on-engine 2026-08-10 (68 checks, zero failures, twice in one day), again
-- 2026-08-12 on Windows x64 (71 checks, adding the ABI-7 sxSha3_256 / FIPS 202
-- vectors), and testRistretto (the ABI 8 group surface plus the ABI 9
-- DLEQ/batch follow-ons behind their own probe, so an ABI-8 package still
-- runs the ABI-8 half) ran green on-engine 2026-08-17 (Windows) and
-- 2026-08-18 (Linux) - the "not yet run on an engine" claim that stood here
-- about it was corrected 2026-08-23, the third stale copy of that sentence
-- fixed that day (docs/api-reference.md corrected its own 2026-08-19,
-- src/sodium.lcb's the same day as this one). The ONE section with no engine
-- run today is testChaCha20 (the ABI 10 raw stream xor added 2026-08-23):
-- verified statically (tools/check-livecodescript.py), vectors pinned against
-- the C KATs and the independent RFC 8439 reference, still waiting on an OXT
-- pass.

local sLog
local sPass
local sFail

function sxSelfTest
   put "SodiumXT self-test" & return into sLog
   put 0 into sPass
   put 0 into sFail

   testVersion
   testRandomBytes
   testEncoding
   testHashing
   testMemEqual
   testSecretBox
   testAead
   testPwHash
   testKdf
   testSecretStream
   testStreamRekey
   testFileHelpers
   testSign
   testBox
   testSeal
   testKeyExchange
   testSeededKeypairs
   testOnionPrimitives
   testPadding
   testHashExtras
   testRistretto
   testChaCha20
   testDiagnostics

   put return & "----" & return after sLog
   put "PASSED:" && sPass & "   FAILED:" && sFail after sLog
   return sLog
end sxSelfTest

-- record one assertion
on sxCheck pCondition, pLabel
   if pCondition then
      add 1 to sPass
      put "  ok   " & pLabel & return after sLog
   else
      add 1 to sFail
      put "  FAIL " & pLabel & return after sLog
   end if
end sxCheck

private command sxSection pTitle
   put pTitle & ":" & return after sLog
end sxSection

-- convenience: hex string (decoded from the Data sxBin2Hex returns)
private function sxHexOf pData
   return textDecode(sxBin2Hex(pData), "ascii")
end sxHexOf

private function sxUtf8 pText
   return textEncode(pText, "utf-8")
end sxUtf8

on testVersion
   local tVer
   sxSection "version"
   put sxVersion() into tVer
   sxCheck (tVer is not empty), "sxVersion returns a non-empty string"
   sxCheck ("libsodium" is in tVer), "version names libsodium"
end testVersion

on testRandomBytes
   local tA
   local tB
   sxSection "randombytes"
   put sxRandomBytes(32) into tA
   put sxRandomBytes(32) into tB
   sxCheck (the number of bytes in tA is 32), "sxRandomBytes(32) returns 32 bytes"
   sxCheck (tA is not tB), "two draws differ (entropy is flowing)"
end testRandomBytes

on testEncoding
   local tBin
   local tHex
   local tRound
   local tTriplet
   local tEmpty
   sxSection "encoding"
   put sxHex2Bin(textEncode("deadbeef", "ascii")) into tBin
   put sxHexOf(tBin) into tHex
   sxCheck (tHex is "deadbeef"), "hex round trip (deadbeef)"
   put sxBase642Bin(sxBin2Base64(sxUtf8("Hello, xTalk!"))) into tRound
   sxCheck (textDecode(tRound, "utf-8") is "Hello, xTalk!"), "base64 round trip"
   -- Regression (short payloads): a 3-byte value encodes to a 4-char base64
   -- group, the smallest whole group and the exact size the decode out buffer
   -- must fit. This round trip used to throw (the wrapper allocated one byte too
   -- few), so keep a 3-byte and an empty case pinned here on-engine.
   put sxBase642Bin(sxBin2Base64(textEncode("abc", "ascii"))) into tTriplet
   sxCheck (textDecode(tTriplet, "ascii") is "abc"), "base64 round trip of a 3-byte value"
   put sxBase642Bin(sxBin2Base64(textEncode("", "ascii"))) into tEmpty
   sxCheck (the number of bytes in tEmpty is 0), "base64 round trip of an empty value"
end testEncoding

on testHashing
   sxSection "hashing (BLAKE2b + SHA3-256)"
   -- published BLAKE2b-256 known-answer vector for "abc"
   sxCheck (sxHexOf(sxHash(sxUtf8("abc"), 32)) is \
      "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"), \
      "BLAKE2b-256(abc) matches the published vector"
   -- a keyed hash differs from the unkeyed hash
   sxCheck (sxHash(sxUtf8("abc"), 32) is not \
      sxHashKeyed(sxUtf8("abc"), sxRandomBytes(32), 32)), \
      "keyed hash differs from unkeyed"
   -- SHA3-256 (ABI 7, the vendored FIPS 202 primitive for the offline v3
   -- onion checksum). The abc vector pins the DOMAIN PADDING: Keccak-256 of
   -- "abc" starts 4e03657a, SHA3-256 starts 3a985da7 - a wrong variant
   -- cannot pass. Same vectors as sodium_smoke_test.c test_sha3.
   sxCheck (sxHexOf(sxSha3_256(sxUtf8("abc"))) is \
      "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"), \
      "SHA3-256(abc) matches the FIPS 202 vector"
   sxCheck (sxHexOf(sxSha3_256(sxUtf8(""))) is \
      "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"), \
      "SHA3-256 of empty input matches the FIPS 202 vector"
   sxCheck (sxSha3_256(sxUtf8("abc")) is not sxHash(sxUtf8("abc"), 32)), \
      "SHA3-256 and BLAKE2b-256 are different functions"
end testHashing

on testMemEqual
   local tX
   sxSection "constant-time compare"
   put sxRandomBytes(32) into tX
   sxCheck (sxMemEqual(tX, tX) is true), "equal buffers compare equal"
   sxCheck (sxMemEqual(tX, sxRandomBytes(32)) is false), "different buffers compare unequal"
end testMemEqual

on testSecretBox
   local tKey
   local tBox
   local tPlain
   local tOk
   sxSection "secretbox"
   put sxRandomBytes(32) into tKey
   put sxSecretBox(sxUtf8("Attack at dawn"), tKey) into tBox
   put sxSecretBoxOpen(tBox, tKey) into tPlain
   sxCheck (textDecode(tPlain, "utf-8") is "Attack at dawn"), "round trip recovers the plaintext"
   -- tamper a byte: open must fail
   put false into tOk
   put numToByte(byteToNum(byte 30 of tBox) bitXor 1) into byte 30 of tBox
   try
      get sxSecretBoxOpen(tBox, tKey)
   catch tErr
      put true into tOk
   end try
   sxCheck tOk, "a tampered ciphertext is rejected"
end testSecretBox

on testAead
   local tKey
   local tAd
   local tBox
   local tOk
   sxSection "aead (XChaCha20-Poly1305)"
   put sxRandomBytes(32) into tKey
   put sxUtf8("v1;application/json") into tAd
   put sxAeadEncrypt(sxUtf8("{ok:true}"), tAd, tKey) into tBox
   sxCheck (textDecode(sxAeadDecrypt(tBox, tAd, tKey), "utf-8") is "{ok:true}"), \
      "round trip with associated data"
   -- wrong associated data must fail
   put false into tOk
   try
      get sxAeadDecrypt(tBox, sxUtf8("v2;application/json"), tKey)
   catch tErr
      put true into tOk
   end try
   sxCheck tOk, "wrong associated data is rejected"
end testAead

on testPwHash
   local tSalt
   local tKey
   local tHash
   sxSection "Argon2id (pwhash)"
   -- deterministic known-answer: pass "password", salt = 16 x 'A', ops 2, mem 1 MiB
   put sxUtf8("AAAAAAAAAAAAAAAA") into tSalt
   -- The accessor is what a caller sizes its salt from, so tie it to the salt
   -- this vector actually uses rather than checking it in isolation: if the two
   -- ever disagreed, the KAT below would still pass while every caller that
   -- trusted sxPwSaltBytes built a salt libsodium rejects.
   sxCheck (sxPwSaltBytes() is 16), "sxPwSaltBytes reports the Argon2id salt length"
   sxCheck (the number of bytes of tSalt is sxPwSaltBytes()), \
      "the vector's salt is exactly that length"
   put sxPwHash(sxUtf8("password"), tSalt, 32, "2", "1048576") into tKey
   sxCheck (sxHexOf(tKey) is \
      "7216b4357104ed7f8a4e900e9cc7a63a0786855abe0b59340053ee43f841228a"), \
      "Argon2id derivation matches the known-answer vector"
   -- password-string storage + verify
   put sxPwHashStr(sxUtf8("hunter2"), "2", "1048576") into tHash
   sxCheck (sxPwHashStrVerify(textDecode(tHash, "ascii"), sxUtf8("hunter2")) is true), \
      "pwhash_str verify accepts the right passphrase"
   sxCheck (sxPwHashStrVerify(textDecode(tHash, "ascii"), sxUtf8("nope")) is false), \
      "pwhash_str verify rejects the wrong passphrase"
end testPwHash

on testKdf
   local tMaster
   local tCtx
   local tA
   local tB
   sxSection "kdf"
   put sxRandomBytes(32) into tMaster
   put sxUtf8("SXTctx00") into tCtx
   put sxKdfDerive(tMaster, "1", tCtx, 32) into tA
   put sxKdfDerive(tMaster, "2", tCtx, 32) into tB
   sxCheck (the number of bytes in tA is 32), "kdf derives a 32-byte subkey"
   sxCheck (tA is not tB), "different subkey ids give different subkeys"
end testKdf

on testSecretStream
   local tKey
   local tHeader
   local tPushH
   local tPullH
   local tNoAd
   local tC1
   local tC2
   local tTag1
   local tTag2
   local tP1
   local tP2
   sxSection "secretstream"
   put sxRandomBytes(32) into tKey
   put sxUtf8("") into tNoAd
   put sxSecretStreamInitPush(tKey, tHeader) into tPushH
   put sxSecretStreamPush(tPushH, sxUtf8("chunk one "), tNoAd, false) into tC1
   put sxSecretStreamPush(tPushH, sxUtf8("and final"), tNoAd, true) into tC2
   sxFreeStream tPushH
   put sxSecretStreamInitPull(tKey, tHeader) into tPullH
   put sxSecretStreamPull(tPullH, tC1, tNoAd, tTag1) into tP1
   put sxSecretStreamPull(tPullH, tC2, tNoAd, tTag2) into tP2
   sxFreeStream tPullH
   sxCheck (textDecode(tP1, "utf-8") is "chunk one "), "first chunk decrypts"
   sxCheck (textDecode(tP2, "utf-8") is "and final"), "final chunk decrypts"
   sxCheck (sxIsFinalTag(tTag2) is true), "final chunk carries the FINAL tag"
end testSecretStream

on testStreamRekey
   local tKey
   local tHeader
   local tNoAd
   local tPushH
   local tPullH
   local tC1
   local tC2
   local tTag
   local tP1
   local tP2
   local tOk
   sxSection "secretstream rekey (in-session forward secrecy)"
   put sxRandomBytes(32) into tKey
   put sxUtf8("") into tNoAd
   -- push a chunk, rekey the push side, push another chunk
   put sxSecretStreamInitPush(tKey, tHeader) into tPushH
   put sxSecretStreamPush(tPushH, sxUtf8("before"), tNoAd, false) into tC1
   sxSecretStreamRekey tPushH
   put sxSecretStreamPush(tPushH, sxUtf8("after"), tNoAd, true) into tC2
   sxFreeStream tPushH
   -- matched rekey: the pull side rekeys at the same point, both chunks decrypt
   put sxSecretStreamInitPull(tKey, tHeader) into tPullH
   put sxSecretStreamPull(tPullH, tC1, tNoAd, tTag) into tP1
   sxSecretStreamRekey tPullH
   put sxSecretStreamPull(tPullH, tC2, tNoAd, tTag) into tP2
   sxFreeStream tPullH
   sxCheck (textDecode(tP1, "utf-8") is "before"), "chunk before the rekey decrypts"
   sxCheck (textDecode(tP2, "utf-8") is "after"), "chunk after a matched rekey decrypts"
   -- one-sided rekey desyncs: pulling the second chunk without rekeying must fail
   put false into tOk
   put sxSecretStreamInitPull(tKey, tHeader) into tPullH
   get sxSecretStreamPull(tPullH, tC1, tNoAd, tTag)
   try
      get sxSecretStreamPull(tPullH, tC2, tNoAd, tTag)
   catch tErr
      put true into tOk
   end try
   sxFreeStream tPullH
   sxCheck tOk, "an unmatched rekey makes the next chunk fail to open"
end testStreamRekey

on testFileHelpers
   local tKey
   local tSrc
   local tEnc
   local tDec
   local tData
   sxSection "file helpers"
   put sxRandomBytes(32) into tKey
   put specialFolderPath("temporary") & "/sxt_demo_plain.bin" into tSrc
   put specialFolderPath("temporary") & "/sxt_demo.enc" into tEnc
   put specialFolderPath("temporary") & "/sxt_demo_dec.bin" into tDec
   put sxRandomBytes(50000) into tData
   put tData into url ("binfile:" & tSrc)
   sxEncryptFile tSrc, tEnc, tKey
   sxDecryptFile tEnc, tDec, tKey
   sxCheck (url ("binfile:" & tDec) is tData), "file encrypt/decrypt round trip (50 KB)"
   delete file tSrc
   delete file tEnc
   delete file tDec
end testFileHelpers

on testSign
   local tPk
   local tSk
   local tSig
   local tOk
   local tSigned
   local tOpened
   local tErr
   local tSeed
   local tPk2, tSk2, tPk3, tSk3
   sxSection "ed25519 sign/verify"
   sxSignKeypair tPk, tSk
   put sxSignDetached(sxUtf8("release v1.0"), tSk) into tSig
   sxCheck (sxSignVerifyDetached(tSig, sxUtf8("release v1.0"), tPk) is true), \
      "a valid signature verifies"
   sxCheck (sxSignVerifyDetached(tSig, sxUtf8("release v1.1"), tPk) is false), \
      "a modified message fails verification"
   -- The ATTACHED form (signature prepended to the message). sxSign/sxSignOpen
   -- are a different libsodium call pair from the detached one above, so they
   -- need their own round trip, their own tamper check, and their own
   -- wrong-key check - a verifier that ignores the key would pass the first
   -- two on their own.
   put sxSign(sxUtf8("attached payload"), tSk) into tSigned
   sxCheck (textDecode(sxSignOpen(tSigned, tPk), "utf-8") is "attached payload"), \
      "sxSign / sxSignOpen round-trips the message"
   sxCheck (the length of tSigned > the length of sxUtf8("attached payload")), \
      "the attached form carries its signature with the message"
   put empty into tOpened
   try
      put sxSignOpen(sxFlipLastByte(tSigned), tPk) into tOpened
   catch tErr
      put "threw" into tOpened
   end try
   sxCheck (tOpened is "threw" or tOpened is empty), \
      "a tampered attached message does not open"
   -- Deterministic keypair-from-seed: the same seed must yield the same pair,
   -- which is what makes a seed a backup (and what OnionXT relies on for a
   -- reproducible .onion).
   put sxRandomBytes(32) into tSeed
   sxSignKeypairFromSeed tSeed, tPk2, tSk2
   sxSignKeypairFromSeed tSeed, tPk3, tSk3
   sxCheck (tPk2 is tPk3 and tSk2 is tSk3), \
      "sxSignKeypairFromSeed is deterministic for one seed"
   sxCheck (tPk2 is not tPk), "a different seed yields a different key"
   put sxSignDetached(sxUtf8("seeded"), tSk2) into tSig
   sxCheck (sxSignVerifyDetached(tSig, sxUtf8("seeded"), tPk2) is true), \
      "a seed-derived key signs and verifies"
end testSign

-- Flip the last byte of a Data, for tamper checks. Byte discipline: LCS string
-- literals have no escape syntax, so a byte is built with numToByte and the
-- data is indexed with `byte x to y of`, never char/line/word.
function sxFlipLastByte pData
   local tLast
   local tLen
   put the number of bytes of pData into tLen
   if tLen is 0 then
      return pData
   end if
   put byteToNum(byte tLen of pData) into tLast
   put (tLast + 1) mod 256 into tLast
   return (byte 1 to (tLen - 1) of pData) & numToByte(tLast)
end sxFlipLastByte

on testBox
   local tApk
   local tAsk
   local tBpk
   local tBsk
   local tBox
   local tOk
   sxSection "public-key box (X25519)"
   sxBoxKeypair tApk, tAsk
   sxBoxKeypair tBpk, tBsk
   put sxBox(sxUtf8("for your eyes only"), tBpk, tAsk) into tBox
   sxCheck (textDecode(sxBoxOpen(tBox, tApk, tBsk), "utf-8") is "for your eyes only"), \
      "A->B box round trip"
   put false into tOk
   try
      get sxBoxOpen(tBox, tApk, tAsk)
   catch tErr
      put true into tOk
   end try
   sxCheck tOk, "a third party cannot open the box"
end testBox

on testSeal
   local tPk
   local tSk
   local tSealed
   sxSection "sealed box (anonymous sender)"
   sxBoxKeypair tPk, tSk
   put sxSeal(sxUtf8("anonymous tip"), tPk) into tSealed
   sxCheck (textDecode(sxSealOpen(tSealed, tPk, tSk), "utf-8") is "anonymous tip"), \
      "seal round trip to the recipient"
end testSeal

on testKeyExchange
   local tCpk
   local tCsk
   local tSpk
   local tSsk
   local tCrx
   local tCtx
   local tSrx
   local tStx
   sxSection "key exchange (kx)"
   sxKeyExchangeKeypair tCpk, tCsk
   sxKeyExchangeKeypair tSpk, tSsk
   sxKeyExchangeClient tCpk, tCsk, tSpk, tCrx, tCtx
   sxKeyExchangeServer tSpk, tSsk, tCpk, tSrx, tStx
   sxCheck (sxMemEqual(tCrx, tStx) is true), "client rx equals server tx"
   sxCheck (sxMemEqual(tCtx, tSrx) is true), "client tx equals server rx"
end testKeyExchange

on testSeededKeypairs
   local tSeed
   local tPk1
   local tSk1
   local tPk2
   local tSk2
   local tSealed
   local tKpk
   local tKsk
   local tRpk
   local tRsk
   local tCrx
   local tCtx
   local tSrx
   local tStx
   sxSection "seeded keypairs (deterministic one-seed identity)"
   -- a fixed 32-byte seed: "B" is 0x42, so this is 0x42 repeated 32 times, the
   -- same seed the native known-answer test uses.
   put textEncode("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "ascii") into tSeed

   -- box keypair: deterministic, and the pubkey matches the known-answer vector
   sxBoxKeypairFromSeed tSeed, tPk1, tSk1
   sxBoxKeypairFromSeed tSeed, tPk2, tSk2
   sxCheck (sxMemEqual(tPk1, tPk2) is true and sxMemEqual(tSk1, tSk2) is true), \
      "sxBoxKeypairFromSeed is deterministic"
   sxCheck (sxHexOf(tPk1) is \
      "cc4f2cdb695dd766f34118eb67b98652fed1d8bc49c330b119bbfa8a64989378"), \
      "seeded box pubkey matches the known-answer vector"
   -- functional: a sealed box to the derived pubkey opens with the derived keypair
   put sxSeal(sxUtf8("seeded identity"), tPk1) into tSealed
   sxCheck (textDecode(sxSealOpen(tSealed, tPk1, tSk1), "utf-8") is "seeded identity"), \
      "the seeded box keypair opens its own sealed box"

   -- kx keypair: deterministic pubkey (KAT) + a working agreement with a peer
   sxKeyExchangeKeypairFromSeed tSeed, tKpk, tKsk
   sxCheck (sxHexOf(tKpk) is \
      "191957342799412f1a3cbeae3d3af8cf5441f2fb51d88a8c2a56175f1fae3f3a"), \
      "seeded kx pubkey matches the known-answer vector"
   sxKeyExchangeKeypair tRpk, tRsk
   sxKeyExchangeClient tKpk, tKsk, tRpk, tCrx, tCtx
   sxKeyExchangeServer tRpk, tRsk, tKpk, tSrx, tStx
   sxCheck (sxMemEqual(tCrx, tStx) is true), "a seeded kx keypair agrees a session key"
end testSeededKeypairs

on testOnionPrimitives
   local tSeed
   local tExpanded
   local tExpanded2
   local tMac
   sxSection "onion-support primitives (ed25519 expanded key + HMAC-SHA256)"
   -- 0x42 x 32, the same seed the native known-answer test uses (B is 0x42).
   put textEncode("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", "ascii") into tSeed
   -- seed -> the 64-byte expanded ed25519 key (SHA-512(seed), clamped): the form
   -- a Tor v3 onion service consumes, so one seed fixes a reproducible address.
   put sxSignSeedToExpandedKey(tSeed) into tExpanded
   sxCheck (the number of bytes in tExpanded is 64), "expanded ed25519 key is 64 bytes"
   sxCheck (sxHexOf(tExpanded) is \
      "90e7595fc89e52fdfddce9c6a43d74dbf6047025ee0462d2d172e8b6a2841d6eeda66ce2983f7ff7e47c49615220e78c25c775a040957316b7bafd5985450f90"), \
      "seed -> expanded key matches the known-answer vector"
   put sxSignSeedToExpandedKey(tSeed) into tExpanded2
   sxCheck (sxMemEqual(tExpanded, tExpanded2) is true), "seed -> expanded key is deterministic"
   -- HMAC-SHA256 over an arbitrary-length key: RFC 4231 Test Case 2.
   put sxHmacSha256(textEncode("Jefe", "ascii"), textEncode("what do ya want for nothing?", "ascii")) into tMac
   sxCheck (sxHexOf(tMac) is \
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"), \
      "HMAC-SHA256 matches RFC 4231 Test Case 2"
end testOnionPrimitives

on testPadding
   local tPadded
   sxSection "padding"
   put sxPad(sxUtf8("hello"), 16) into tPadded
   sxCheck (the number of bytes in tPadded is 16), "pad rounds 5 bytes up to 16"
   sxCheck (textDecode(sxUnpad(tPadded, 16), "utf-8") is "hello"), "unpad recovers the original"
end testPadding

on testHashExtras
   local tInRange
   local tR
   local tH
   local tStream
   local tPath
   local tContent
   local tKey
   local tHK
   local tKeyed
   local tAbandoned
   sxSection "phase 6 (uniform random, multipart hash, file hash)"
   -- uniform random stays in range
   put true into tInRange
   repeat 200 times
      put sxRandomUniform(6) into tR
      if tR < 0 or tR >= 6 then
         put false into tInRange
      end if
   end repeat
   sxCheck tInRange, "sxRandomUniform(6) stays in [0,6)"
   -- multipart "a" + "b" + "c" equals the one-shot BLAKE2b-256("abc") vector
   put sxHashInit(32) into tH
   sxHashUpdate tH, sxUtf8("a")
   sxHashUpdate tH, sxUtf8("b")
   sxHashUpdate tH, sxUtf8("c")
   put sxHashFinal(tH, 32) into tStream
   sxCheck (sxHexOf(tStream) is \
      "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"), \
      "multipart hash of a|b|c matches BLAKE2b-256(abc)"
   -- a file hash equals the one-shot hash of the same bytes
   put specialFolderPath("temporary") & "/sxt_hashfile.bin" into tPath
   put sxRandomBytes(40000) into tContent
   put tContent into url ("binfile:" & tPath)
   sxCheck (sxHashFile(tPath, 32) is sxHash(tContent, 32)), \
      "sxHashFile matches the one-shot hash of the same bytes"
   -- KEYED hashing (BLAKE2b as a MAC). The keyed multipart state and the keyed
   -- file helper are separate entry points from the unkeyed ones above, and the
   -- property that matters is that the key actually participates: same bytes +
   -- different key must NOT collide.
   put sxRandomBytes(32) into tKey
   put sxHashInitKeyed(tKey, 32) into tHK
   sxHashUpdate tHK, sxUtf8("a")
   sxHashUpdate tHK, sxUtf8("bc")
   put sxHashFinal(tHK, 32) into tKeyed
   sxCheck (tKeyed is sxHashKeyed(sxUtf8("abc"), tKey, 32)), \
      "keyed multipart hash matches the one-shot keyed hash"
   sxCheck (tKeyed is not sxHash(sxUtf8("abc"), 32)), \
      "the key changes the digest (it is not an unkeyed hash)"
   sxCheck (sxHashFileKeyed(tPath, tKey, 32) is sxHashKeyed(tContent, tKey, 32)), \
      "sxHashFileKeyed matches the one-shot keyed hash of the same bytes"
   -- sxFreeHash: an explicitly abandoned state frees cleanly, and freeing is
   -- idempotent (there is no deterministic LCB unload hook, so the app frees
   -- what it opens and a double free must be a harmless no-op, never a crash).
   put sxHashInit(32) into tAbandoned
   sxHashUpdate tAbandoned, sxUtf8("never finalised")
   sxFreeHash tAbandoned
   sxFreeHash tAbandoned
   sxCheck true, "sxFreeHash is idempotent on an abandoned state"
   delete file tPath
end testHashExtras

on testRistretto
   -- ABI 8 (holde-em Workstream U): the ristretto255 group surface. The
   -- point/scalar vectors are pinned twice over: generated from the pinned
   -- libsodium AND re-derived by the independent pure-Python RFC 9496
   -- reference in holde-em/tools/protocol-kat.py - both agree on every value
   -- here, so a transcription slip cannot pass. The same vectors are pinned
   -- in the C smoke test, so a green run here plus a green ctest pins the
   -- whole path: script -> LCB -> shim -> libsodium.
   local tGen
   local tP0
   local tP1
   local tP51
   local tK7
   local tKp
   local tKinv
   local tBack
   local tR1
   local tR2
   local tBad
   local tZero
   local tProbe
   local tErr
   local tCaught
   local tBase
   local tSum
   local tDiff
   local tConcat
   local tBatch
   local tLm2
   local tInv7
   local tScalar
   sxSection "ristretto255 (ABI 8)"
   put sxHex2Bin(textEncode("e2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76", "ascii")) into tGen
   -- SKIP cleanly on a pre-ABI-8 package: the probe call throws (handler not
   -- found on an older .lcb, or the ABI-mismatch guard on a mixed package)
   -- instead of answering, and this section must not take the whole run down
   -- with it (the suite's stMergeCounted lesson: one uncaught engine error
   -- loses every section's results).
   try
      put sxRistrettoPointValid(tGen) into tProbe
   catch tErr
      sxCheck true, "SKIP: this SodiumXT package predates ristretto255 (ABI 8)"
      exit testRistretto
   end try
   sxCheck tProbe, "the RFC 9496 generator encoding is a valid point"
   -- hash-to-group, the deal's card-point derivation: BLAKE2b-512 of a
   -- domain-separated label into from_hash (sxHash(tData, 64) IS the 64-byte
   -- hash the plan's conditional "sxHash512" asked about)
   put sxRistrettoFromHash(sxHash(sxUtf8("HOLDEM-RISTRETTO-KAT-v1|card-00"), 64)) into tP0
   sxCheck (sxHexOf(tP0) is "d4976d032129eb3cc15bb2e700e0f303c46bdb8a4874d009dc03405c3fdedd4d"), \
         "from_hash(card-00) matches the cross-checked vector"
   put sxRistrettoFromHash(sxHash(sxUtf8("HOLDEM-RISTRETTO-KAT-v1|card-01"), 64)) into tP1
   sxCheck (sxHexOf(tP1) is "48a187d5d40ac12e4b95efe4d1c50e099efd7d5b1c3f9d881c32a51a6df6e70d"), \
         "from_hash(card-01) matches the cross-checked vector"
   sxCheck (sxRistrettoPointValid(tP0) and sxRistrettoPointValid(tP1)), \
         "from_hash outputs are valid encodings"
   -- mask/unmask, the deal's core algebra: k*P, k^-1, k^-1*(k*P) == P
   put sxHex2Bin(textEncode("0700000000000000000000000000000000000000000000000000000000000000", "ascii")) into tK7
   put sxRistrettoScalarMultPoint(tK7, tP0) into tKp
   sxCheck (sxHexOf(tKp) is "e4efdd42fce9e2cc212ccf6aa307b6bba55ba8f9d2b33103721be7fead96964c"), \
         "7 * from_hash(card-00) matches the cross-checked vector"
   put sxRistrettoScalarInvert(tK7) into tKinv
   sxCheck (sxHexOf(tKinv) is "22d5909fba32273143cdfe848dda1f4c92244992244992244992244992244902"), \
         "invert(7) matches 7^-1 mod L (independently pow(7, L-2, L))"
   put sxRistrettoScalarMultPoint(tKinv, tKp) into tBack
   sxCheck (tBack is tP0), "the mask/unmask roundtrip returns exactly P"
   -- random masking scalars: right length, and two draws differ
   put sxRistrettoScalarRandom() into tR1
   put sxRistrettoScalarRandom() into tR2
   sxCheck (the number of bytes in tR1 is 32), "sxRistrettoScalarRandom returns 32 bytes"
   sxCheck (tR1 is not tR2), "two random scalars differ"
   -- the predicate refuses garbage without throwing
   put sxHex2Bin(textEncode("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "ascii")) into tBad
   sxCheck (not sxRistrettoPointValid(tBad)), "all-FF is not a valid encoding"
   sxCheck (not sxRistrettoPointValid(sxRandomBytes(31))), "a 31-byte blob is not a valid point"
   -- the failure paths THROW (H4: the catch path is the detection path)
   put sxHex2Bin(textEncode("0000000000000000000000000000000000000000000000000000000000000000", "ascii")) into tZero
   put false into tCaught
   try
      put sxRistrettoScalarInvert(tZero) into tKinv
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "a zero scalar has no inverse (throws)"
   put false into tCaught
   try
      put sxRistrettoScalarMultPoint(tZero, tP0) into tKp
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "a zero scalar refuses to multiply (identity result, throws)"
   put false into tCaught
   try
      put sxRistrettoScalarMultPoint(tK7, tBad) into tKp
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "an invalid point encoding refuses to multiply (throws)"
   -- ABI 9 (holde-em Phase 5, added 2026-08-15): the DLEQ/batch follow-ons.
   -- A SECOND probe, so an ABI-8 package (where everything above just ran)
   -- SKIPs only these newer checks cleanly instead of dying on the first
   -- handler it does not have.
   sxSection "ristretto255 (ABI 9: DLEQ/batch follow-ons)"
   try
      put sxRistrettoScalarMultBase(tK7) into tBase
   catch tErr
      sxCheck true, "SKIP: this SodiumXT package predates the DLEQ/batch surface (ABI 9)"
      exit testRistretto
   end try
   -- base-mult: the pinned vector (== RFC 9496's small-multiples entry B[7],
   -- a third independent witness) AND agreement with the general scalarmult
   -- of the generator encoding - both legs, so a wrong base cannot pass.
   sxCheck (sxHexOf(tBase) is "44f53520926ec81fbd5a387845beb7df85a96a24ece18738bdcfa6a7822a176d"), \
         "7 * B matches the cross-checked vector (RFC 9496 B[7])"
   sxCheck (tBase is sxRistrettoScalarMultPoint(tK7, tGen)), \
         "sxRistrettoScalarMultBase agrees with scalarmult(generator)"
   -- add/sub: the pinned sum and the roundtrip (P+Q)-Q == P
   put sxRistrettoAdd(tP0, tP1) into tSum
   sxCheck (sxHexOf(tSum) is "34722b333ab7982fe4d5e2be2913c316db8f8675de2394a5cfb704abab7c8b4c"), \
         "card00 + card01 matches the cross-checked vector"
   put sxRistrettoSub(tSum, tP1) into tDiff
   sxCheck (tDiff is tP0), "the add/sub roundtrip (P+Q)-Q returns exactly P"
   -- the batch call: one FFI crossing over three concatenated card points,
   -- element-for-element equal to the loop of single multiplications
   put sxRistrettoFromHash(sxHash(sxUtf8("HOLDEM-RISTRETTO-KAT-v1|card-51"), 64)) into tP51
   put tP0 & tP1 & tP51 into tConcat
   put sxRistrettoScalarMultBatch(tK7, tConcat) into tBatch
   sxCheck (the number of bytes in tBatch is 96), \
         "the batch over 3 points returns 96 concatenated bytes"
   sxCheck (byte 1 to 32 of tBatch is sxRistrettoScalarMultPoint(tK7, tP0)), \
         "batch element 1 equals the single-call multiplication"
   sxCheck (byte 33 to 64 of tBatch is sxRistrettoScalarMultPoint(tK7, tP1)), \
         "batch element 2 equals the single-call multiplication"
   sxCheck (byte 65 to 96 of tBatch is sxRistrettoScalarMultPoint(tK7, tP51)), \
         "batch element 3 equals the single-call multiplication"
   -- the DLEQ-shaped identity the whole surface exists for
   sxCheck (sxRistrettoScalarMultPoint(tK7, tSum) is \
         sxRistrettoAdd(byte 1 to 32 of tBatch, byte 33 to 64 of tBatch)), \
         "k*(P+Q) equals k*P + k*Q (the DLEQ-shaped identity)"
   -- scalar arithmetic mod L: 7 + (L-2) wraps to 5, and 7 * 7^-1 is 1
   put sxHex2Bin(textEncode("ebd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010", "ascii")) into tLm2
   put sxRistrettoScalarAdd(tK7, tLm2) into tScalar
   sxCheck (sxHexOf(tScalar) is "0500000000000000000000000000000000000000000000000000000000000000"), \
         "7 + (L-2) wraps to 5 mod L (reduce semantics)"
   put sxRistrettoScalarInvert(tK7) into tInv7
   put sxRistrettoScalarMul(tK7, tInv7) into tScalar
   sxCheck (sxHexOf(tScalar) is "0100000000000000000000000000000000000000000000000000000000000000"), \
         "7 * 7^-1 is 1 mod L"
   -- failure paths: one bad point voids the WHOLE batch, and the thrown
   -- message carries the 1-based failing index (the atomic-void contract)
   put false into tCaught
   put empty into tErr
   try
      put sxRistrettoScalarMultBatch(tK7, tP0 & tBad & tP51) into tBatch
   catch tErr
      put true into tCaught
   end try
   sxCheck (tCaught and ("point 2 of 3" is in tErr)), \
         "one bad point fails the whole batch, naming index 2 of 3"
   put false into tCaught
   try
      put sxRistrettoScalarMultBase(tZero) into tBase
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "a zero scalar refuses base multiplication (identity result, throws)"
   put false into tCaught
   try
      put sxRistrettoAdd(tP0, tBad) into tSum
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "an invalid operand encoding refuses to add (throws)"
end testRistretto

on testChaCha20
   local tProbe
   local tErr
   local tCaught
   local tKey
   local tNonce
   local tZeros
   local tOut
   local tPlain
   local tCipher
   local tBack
   sxSection "raw IETF ChaCha20 stream xor (ABI 10)"
   -- SKIP cleanly on a pre-ABI-10 package: the probe call throws (handler not
   -- found on an older .lcb, or the ABI-mismatch guard on a mixed package)
   -- instead of answering, and this section must not take the whole run down
   -- with it (the suite's stMergeCounted lesson).
   put sxHex2Bin(textEncode("0000000000000000000000000000000000000000000000000000000000000000", "ascii")) into tKey
   put sxHex2Bin(textEncode("000000000000000000000000", "ascii")) into tNonce
   try
      put sxChaCha20IetfXor(tKey, tNonce, numToByte(0)) into tProbe
   catch tErr
      sxCheck true, "SKIP: this SodiumXT package predates the raw ChaCha20 surface (ABI 10)"
      exit testChaCha20
   end try
   -- RFC 8439 Appendix A.2 #1: all-zero key and nonce at counter 0 over 64
   -- zero bytes is the raw keystream. The same bytes are pinned in the C
   -- smoke test and cross-derived from nostrxt's independent RFC 8439
   -- reference, so this compares THREE implementations, not one.
   put sxHex2Bin(textEncode("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "ascii")) into tZeros
   put sxChaCha20IetfXor(tKey, tNonce, tZeros) into tOut
   sxCheck (sxHexOf(tOut) is "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7" \
         & "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586"), \
         "counter-0 keystream matches RFC 8439 A.2 #1"
   sxCheck (the number of bytes in tOut is the number of bytes in tZeros), \
         "the output length equals the input length"
   -- the section 2.4.2 sunscreen plaintext under that section's key and nonce
   -- but at COUNTER 0 (the raw-xor configuration this handler fixes; 2.4.2
   -- itself starts at counter 1, so its published ciphertext does not apply).
   -- Expected bytes derived from nostrxt's independent RFC 8439 reference and
   -- pinned identically in the C smoke test.
   put sxHex2Bin(textEncode("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", "ascii")) into tKey
   put sxHex2Bin(textEncode("000000000000004a00000000", "ascii")) into tNonce
   put sxUtf8("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.") into tPlain
   put sxChaCha20IetfXor(tKey, tNonce, tPlain) into tCipher
   sxCheck (sxHexOf(tCipher) is "e3647a29ded31528ef56bac70f7a7ac3b735c7444da42d99823ef9938c8ebfdc" \
         & "f05bb71a822c62981aa1ea608f47933f2ed755b62d9312ae72037674f3e93e24" \
         & "4c2328d32f75bcc15bb7574fde0c6fcdf87b7aa25b5972970c2ae6cced86a10b" \
         & "e9496fc61c407dfdc01510ed8f4eb35d0d62"), \
         "counter-0 sunscreen ciphertext matches the independent reference"
   -- the call is its own inverse: the same handler decrypts. Compared as hex
   -- (both sides through sxHexOf), because `is` on the raw bytes folds case
   -- and would call "Ladies" and "lADIES" the same plaintext.
   put sxChaCha20IetfXor(tKey, tNonce, tCipher) into tBack
   sxCheck (sxHexOf(tBack) is sxHexOf(tPlain)), "xor twice with the same key and nonce is the identity"
   -- an empty input is legal and returns empty.
   put sxChaCha20IetfXor(tKey, tNonce, textEncode("", "ascii")) into tOut
   sxCheck (the number of bytes in tOut is 0), "an empty input returns empty"
   -- firewall: the shim refuses any other key or nonce length, and the
   -- refusal arrives as a throw (the .lcb error convention), never as
   -- truncated or garbage output.
   put false into tCaught
   try
      put sxChaCha20IetfXor(sxHex2Bin(textEncode("00", "ascii")), tNonce, tPlain) into tOut
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "a 1-byte key is refused"
   put false into tCaught
   try
      put sxChaCha20IetfXor(tKey, sxHex2Bin(textEncode("0000", "ascii")), tPlain) into tOut
   catch tErr
      put true into tCaught
   end try
   sxCheck tCaught, "a 2-byte nonce is refused"
end testChaCha20

on testDiagnostics
   local tErr
   sxSection "init, presets, and last-error"
   -- sxInit is safe to call again at any time (it is guarded internally); the
   -- library has already initialised itself by now, so this asserts the
   -- re-entry is harmless rather than that it did the first-time work.
   sxInit
   sxCheck true, "sxInit is safe to call again"
   -- The Argon2id memlimit presets are PROBED FOR THEIR VALUE, never used to
   -- run a hash here: at the sensitive preset a single sxPwHash can occupy the
   -- one interpreter thread for a long, UI-freezing beat, which is a cost this
   -- harness should describe rather than pay.
   sxCheck (sxPwMemInteractive() is not empty), "sxPwMemInteractive returns a value"
   sxCheck (sxPwMemModerate() is not empty), "sxPwMemModerate returns a value"
   sxCheck (sxPwMemSensitive() is not empty), "sxPwMemSensitive returns a value"
   sxCheck (sxPwMemModerate() is not sxPwMemInteractive()), \
      "moderate is a different cost from interactive"
   sxCheck (sxPwMemSensitive() is not sxPwMemModerate()), \
      "sensitive is a different cost from moderate"
   -- sxLastError reports the most recent failure. Force one, then confirm the
   -- message is there to be read.
   put empty into tErr
   try
      get sxSecretBoxOpen(sxUtf8("not a real ciphertext"), sxRandomBytes(32))
   catch tErr
   end try
   sxCheck (tErr is not empty or sxLastError() is not empty), \
      "a failed call surfaces an error (thrown or via sxLastError)"
end testDiagnostics
