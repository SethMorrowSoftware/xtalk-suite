script "coinSelfTest"

-- coin-selftest.livecodescript - a self-building RUNTIME harness that drives
-- the CoinXT public API in OXT and reports PASS / FAIL per handler. This is the
-- OXT-pass companion to tools/coin-kat.py: the KAT harness proves the SHIM
-- against public vectors headless, through ctypes; this proves the .lcb BINDING
-- (the foreign-decl signatures, the UIntSize returns, the Data marshalling, the
-- allocate-and-copy-back path) actually runs - the one layer CI cannot reach,
-- since OXT has no headless way to compile or run a .lcb.
--
-- WHY THIS FILE EXISTS. CoinXT was the only member with no self-building
-- harness. That is exactly why the 2026-08-08 suite pass could reach just 4 of
-- the 16 public cx* handlers: there was no paste-and-run way to drive the rest.
-- This file closes that. It calls ALL 16, by name, and checks every deterministic
-- output against the same published vector tools/coin-kat.py pins, so a green run
-- here and a green run there are the same claim at two different layers.
--
-- COVERAGE NOTE (honest): every public cx* handler is driven here -
-- cxCheckABI, the seven *Len accessors, cxKeccak256, cxSha3_256, cxSha256,
-- cxSha512, cxRipemd160, cxHmacSha256, cxHmacSha512, cxPbkdf2HmacSha512. The
-- vectors are Keccak-256 (Ethereum 0x01 padding), FIPS 180-4 SHA-2, the
-- RIPEMD-160 specification vectors, NIST SHA3-256, RFC 4231 HMAC cases 1 and 2,
-- and the BIP-39 abandon-about/TREZOR seed. THIS FILE HAS NOT ITSELF BEEN RUN ON
-- AN ENGINE YET, so it is verified statically; running it is what turns the 12
-- handlers the suite pass did not call into a runtime result.
--
-- WHAT IT DELIBERATELY DOES NOT PROVE: anything about the curve, HD wallets, or
-- address encodings. Those are phases 2 to 4 and do not exist yet. A green run
-- here says the phase-1 hash surface is correct through the binding, nothing more.
--
-- HOW TO USE: open OXT, make a one-card stack, paste THIS into the STACK script
-- (Object > Stack Script), then close+reopen. It builds its own UI, runs every
-- check synchronously, and shows a green/red list. Needs the installed
-- org.openxtalk.library.coin extension. Nothing here is asynchronous and nothing
-- holds state, so there is no teardown and no deadline: CoinXT is a calculator.
--
-- The LCS lessons this file was written under (the gotcha list carried in the
-- family CLAUDE.md files): no braces, no subscripted function results, binary
-- payloads built with numToByte (string literals have no escapes), byte-exact
-- compares under caseSensitive, and zero-argument calls BARE in statement
-- position - which is why cxCheckABI is invoked as a command and not as
-- cxCheckABI(). It is declared `returns nothing`, so `put cxCheckABI()` would
-- print a blank line and prove nothing; it THROWS on ABI skew, so silence is the
-- pass.

-- ---- the pinned vectors ------------------------------------------------------
-- Every one of these is a PUBLIC known answer, identical to the value pinned in
-- tools/coin-kat.py. Do not "fix" one to match an implementation: if a digest
-- here disagrees with the library, the library is what is wrong.

-- Keccak-256, Ethereum's 0x01-padded variant. NOT SHA3-256 (see kSha3Abc).
constant kKeccakEmpty = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
constant kKeccakAbc = "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"

-- NIST SHA3-256. The empty and "abc" answers differ from Keccak-256 above by
-- the padding byte alone, which is the entire reason both handlers exist.
constant kSha3Empty = "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
constant kSha3Abc = "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"
constant kSha3Fox = "69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04"

-- FIPS 180-4 worked examples.
constant kSha256Empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
constant kSha256Abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
constant kSha512Empty = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
constant kSha512Abc = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"

-- The RIPEMD-160 specification's own vectors. These stand alone: OpenSSL 3
-- moved RIPEMD-160 to the legacy provider, so Python's hashlib usually cannot
-- offer a second opinion, and coin-kat.py says so rather than skipping quietly.
constant kRipeEmpty = "9c1185a5c5e9fc54612808977ee8f548b2258d31"
constant kRipeA = "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"
constant kRipeAbc = "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
constant kRipeMsgDigest = "5d0689ef49d2fae572b881b123a85ffa21595f36"

-- RFC 4231 test case 1: key = 0x0b repeated 20 times, message = "Hi There".
constant kHmac1Sha256 = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
constant kHmac1Sha512 = "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"

-- RFC 4231 test case 2: a SHORT ascii key, which exercises the pad path that a
-- 20-byte key does not.
constant kHmac2Sha256 = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
constant kHmac2Sha512 = "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"

-- The BIP-39 vector everyone knows. This pins the REAL call shape CoinXT will
-- use the KDF for in phase 4 (salt = "mnemonic" + passphrase, 2048 iterations,
-- a 64-byte seed), not merely the primitive in the abstract.
constant kBip39Mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
constant kBip39Salt = "mnemonicTREZOR"
constant kBip39Seed = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

constant kFox = "The quick brown fox jumps over the lazy dog"

-- ---- state -------------------------------------------------------------------
local sTotal, sPassed, sFailed
local sResultText       -- the accumulated PASS/FAIL/section lines
local sDone             -- "true" once the run has finished (drives the colour)

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack

on mouseUp
   if the short name of the target is "stRerun" then
      stRun
   else
      pass mouseUp
   end if
end mouseUp

-- ---- self-building UI (idempotent) -------------------------------------------
command stBuild
   if there is a field "stResults" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to 660
   set the height of this stack to 620
   set the backgroundColor of this card to "237,239,243"
   set the title of this stack to "coinxt - API Self-Test"
   stMakeLabel "stTitle", "  coinxt - API Self-Test", "0,0,660,30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38,520,66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stRerun", "Re-run", "566,38,644,64"
   stMakeList "stResults", "16,72,644,604"
   set the textFont of field "stResults" to "Courier"
   set the textSize of field "stResults" to 11
   unlock screen
end stBuild

command stMakeLabel pName, pText, pRect, pSize
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
end stMakeLabel

command stMakeButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end stMakeButton

command stMakeList pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the vScrollbar of field pName to true
end stMakeList

-- ---- assertion plumbing ------------------------------------------------------
command stAssert pName, pPass
   add 1 to sTotal
   if pPass then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

command stNote pText
   put "      " & pText & return after sResultText
end stNote

command stShow
   put sResultText into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sTotal & " total" into field "stSummary"
   if sDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "20,120,40"
      else
         set the foregroundColor of field "stSummary" to "170,30,30"
      end if
   end if
end stShow

-- Every section is contained. A section that throws - a mis-declared foreign
-- handler, a renamed export, an ABI skew - must cost EXACTLY ITSELF, so the rest
-- of the surface still gets measured and the maintainer reads a list instead of
-- an error dialog. This is the sibling harnesses' rule and it earns its keep
-- here: an ABI mismatch throws from EVERY handler, and seeing that as 40 failed
-- lines is far more diagnostic than one dialog on the first call.
command stSectionFailed pTitle, pError
   add 1 to sTotal
   add 1 to sFailed
   put "FAIL  " & pTitle & " threw: " & pError & return after sResultText
end stSectionFailed

-- ---- the run -----------------------------------------------------------------
command stRun
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put empty into sResultText
   put "false" into sDone
   -- Byte-exact compares, and hex strings that must not fold case.
   set the caseSensitive to true

   put "CoinXT API self-test" & return into sResultText
   put "Phase 1 hash surface: all 16 public cx* handlers." & return after sResultText

   stRunAbi
   stRunLengths
   stRunKeccak
   stRunSha3
   stRunSha2
   stRunRipemd
   stRunHmac
   stRunPbkdf2
   stRunEmptyInputs
   stRunIndependence
   stRunFailClosed

   stSection "summary"
   stNote "Vectors are identical to tools/coin-kat.py, so this run and the"
   stNote "headless KAT run are the same claim at two different layers."
   stNote "Nothing here covers the curve, HD wallets, or addresses (phases 2-4)."
   put "true" into sDone
   stShow
end stRun

-- The ABI guard, called BY NAME at last. cxCheckABI is `returns nothing` and
-- throws on skew, so silence is the pass; there is no value to inspect.
command stRunAbi
   local tOK
   stSection "load + ABI guard"
   try
      put "true" into tOK
      cxCheckABI
   catch tError
      put "false" into tOK
      stNote "cxCheckABI threw: " & tError
   end try
   stAssert "cxCheckABI passes against the shipped binary", tOK is "true"
   -- The probe that actually prints a value, and the first exercise of the
   -- UIntSize return type in this file.
   stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
end stRunAbi

-- The seven length accessors. These are the whole UIntSize-as-a-foreign-RETURN
-- surface: our lengths are C size_t, so they marshal as UIntSize, not CUInt.
-- Each is checked twice over - against its known digest size, and against the
-- length of a digest the library actually produced - because a length that is
-- self-consistently wrong would still size every buffer wrong.
command stRunLengths
   stSection "length accessors (UIntSize as a foreign RETURN type)"
   try
      stAssert "cxKeccak256Len() is 32", cxKeccak256Len() is 32
      stAssert "cxSha3_256Len() is 32", cxSha3_256Len() is 32
      stAssert "cxSha256Len() is 32", cxSha256Len() is 32
      stAssert "cxSha512Len() is 64", cxSha512Len() is 64
      stAssert "cxRipemd160Len() is 20", cxRipemd160Len() is 20
      stAssert "cxHmacSha256Len() is 32", cxHmacSha256Len() is 32
      stAssert "cxHmacSha512Len() is 64", cxHmacSha512Len() is 64
      stAssert "keccak digest length matches its accessor", the number of bytes of cxKeccak256(stText("abc")) is cxKeccak256Len()
      stAssert "sha512 digest length matches its accessor", the number of bytes of cxSha512(stText("abc")) is cxSha512Len()
      stAssert "ripemd digest length matches its accessor", the number of bytes of cxRipemd160(stText("abc")) is cxRipemd160Len()
   catch tError
      stSectionFailed "length accessors", tError
   end try
end stRunLengths

command stRunKeccak
   stSection "Keccak-256 (published Ethereum vectors)"
   try
      -- The empty input FIRST, on purpose. It is the MCDataGetBytePtr-on-empty
      -- marshalling question: if the engine imported a null byte pointer as
      -- `nothing`, the plain Pointer slot would reject it and this would THROW
      -- rather than return a digest. A throw here is a marshalling failure, not
      -- a hashing failure - do not go looking in the vectors.
      stAssert "cxKeccak256 of the empty input", stHex(cxKeccak256(stText(""))) is kKeccakEmpty
      stAssert "cxKeccak256 of abc", stHex(cxKeccak256(stText("abc"))) is kKeccakAbc
      stAssert "cxKeccak256 is deterministic", stHex(cxKeccak256(stText("abc"))) is stHex(cxKeccak256(stText("abc")))
   catch tError
      stSectionFailed "Keccak-256", tError
   end try
end stRunKeccak

command stRunSha3
   stSection "SHA3-256 (NIST) and the aliasing trap"
   try
      stAssert "cxSha3_256 of the empty input", stHex(cxSha3_256(stText(""))) is kSha3Empty
      stAssert "cxSha3_256 of abc", stHex(cxSha3_256(stText("abc"))) is kSha3Abc
      stAssert "cxSha3_256 of the fox sentence", stHex(cxSha3_256(stText(kFox))) is kSha3Fox
      -- The trap this pair of handlers exists to avoid. Keccak-256 and SHA3-256
      -- differ ONLY in a padding byte, so a shim that wires one to the other is
      -- a silent, plausible, totally wrong answer - and on Ethereum, a wrong
      -- address. Assert the difference explicitly, in both directions.
      stAssert "cxSha3_256 is NOT aliased to cxKeccak256", stHex(cxSha3_256(stText("abc"))) is not stHex(cxKeccak256(stText("abc")))
      stAssert "cxKeccak256 is NOT aliased to cxSha3_256", stHex(cxKeccak256(stText(""))) is not stHex(cxSha3_256(stText("")))
   catch tError
      stSectionFailed "SHA3-256", tError
   end try
end stRunSha3

command stRunSha2
   stSection "SHA-256 and SHA-512 (FIPS 180-4)"
   try
      stAssert "cxSha256 of the empty input", stHex(cxSha256(stText(""))) is kSha256Empty
      stAssert "cxSha256 of abc", stHex(cxSha256(stText("abc"))) is kSha256Abc
      stAssert "cxSha512 of the empty input", stHex(cxSha512(stText(""))) is kSha512Empty
      stAssert "cxSha512 of abc", stHex(cxSha512(stText("abc"))) is kSha512Abc
   catch tError
      stSectionFailed "SHA-2", tError
   end try
end stRunSha2

command stRunRipemd
   stSection "RIPEMD-160 (specification vectors)"
   try
      stAssert "cxRipemd160 of the empty input", stHex(cxRipemd160(stText(""))) is kRipeEmpty
      stAssert "cxRipemd160 of a", stHex(cxRipemd160(stText("a"))) is kRipeA
      stAssert "cxRipemd160 of abc", stHex(cxRipemd160(stText("abc"))) is kRipeAbc
      stAssert "cxRipemd160 of message digest", stHex(cxRipemd160(stText("message digest"))) is kRipeMsgDigest
      stNote "No second opinion exists for these: OpenSSL 3 moved RIPEMD-160 to"
      stNote "the legacy provider, so the published vectors stand alone."
   catch tError
      stSectionFailed "RIPEMD-160", tError
   end try
end stRunRipemd

command stRunHmac
   local tKey1, tKey2, tMsg1, tMsg2
   stSection "HMAC-SHA256 / HMAC-SHA512 (RFC 4231 cases 1 and 2)"
   try
      -- Case 1's key is twenty 0x0b bytes. Built with numToByte because a
      -- LiveCodeScript string literal has no escape syntax: "\x0b" is four
      -- characters, not one byte.
      put stRepeatByte(11, 20) into tKey1
      put stText("Hi There") into tMsg1
      stAssert "HMAC-SHA256 case 1", stHex(cxHmacSha256(tKey1, tMsg1)) is kHmac1Sha256
      stAssert "HMAC-SHA512 case 1", stHex(cxHmacSha512(tKey1, tMsg1)) is kHmac1Sha512
      -- Case 2's key is shorter than the block size and ascii, which walks a
      -- different pad path than case 1's.
      put stText("Jefe") into tKey2
      put stText("what do ya want for nothing?") into tMsg2
      stAssert "HMAC-SHA256 case 2", stHex(cxHmacSha256(tKey2, tMsg2)) is kHmac2Sha256
      stAssert "HMAC-SHA512 case 2", stHex(cxHmacSha512(tKey2, tMsg2)) is kHmac2Sha512
      -- A MAC must depend on its key. Same message, different key, different tag.
      stAssert "HMAC-SHA256 depends on the key", stHex(cxHmacSha256(tKey1, tMsg1)) is not stHex(cxHmacSha256(tKey2, tMsg1))
   catch tError
      stSectionFailed "HMAC", tError
   end try
end stRunHmac

command stRunPbkdf2
   local tSeed, tShort
   stSection "PBKDF2-HMAC-SHA512 (the BIP-39 seed vector)"
   try
      put cxPbkdf2HmacSha512(stText(kBip39Mnemonic), stText(kBip39Salt), 2048, 64) into tSeed
      stAssert "BIP-39 abandon-about with TREZOR", stHex(tSeed) is kBip39Seed
      stAssert "the seed is exactly 64 bytes", the number of bytes of tSeed is 64
      -- This is the one handler whose output length the CALLER chooses, so the
      -- shim writes exactly what was asked for rather than a size it reports.
      -- A non-block-multiple length exercises the partial final block.
      put cxPbkdf2HmacSha512(stText(kBip39Mnemonic), stText(kBip39Salt), 2048, 20) into tShort
      stAssert "a 20-byte request returns 20 bytes", the number of bytes of tShort is 20
      stAssert "the short output prefixes the long one", stHex(tShort) is char 1 to 40 of kBip39Seed
   catch tError
      stSectionFailed "PBKDF2", tError
   end try
end stRunPbkdf2

-- The empty input, generalised. The suite pass settled this for cxKeccak256
-- only; every one-shot digest marshals its IN buffer the same way, so each one
-- should return a full-length digest rather than throw.
command stRunEmptyInputs
   stSection "empty input marshals for every one-shot digest"
   try
      stAssert "cxKeccak256 empty returns 32 bytes", the number of bytes of cxKeccak256(stText("")) is 32
      stAssert "cxSha3_256 empty returns 32 bytes", the number of bytes of cxSha3_256(stText("")) is 32
      stAssert "cxSha256 empty returns 32 bytes", the number of bytes of cxSha256(stText("")) is 32
      stAssert "cxSha512 empty returns 64 bytes", the number of bytes of cxSha512(stText("")) is 64
      stAssert "cxRipemd160 empty returns 20 bytes", the number of bytes of cxRipemd160(stText("")) is 20
      -- An empty KEY and an empty MESSAGE are separate marshalling slots.
      stAssert "cxHmacSha256 with an empty key", the number of bytes of cxHmacSha256(stText(""), stText("abc")) is 32
      stAssert "cxHmacSha256 with an empty message", the number of bytes of cxHmacSha256(stText("abc"), stText("")) is 32
   catch tError
      stSectionFailed "empty inputs", tError
   end try
end stRunEmptyInputs

-- Four digests of the same input must be four DIFFERENT answers. If any two
-- agree, a wire has been crossed somewhere in the binding.
command stRunIndependence
   local tK, tS3, tS2, tR
   stSection "the digests are independent of each other"
   try
      put stHex(cxKeccak256(stText("abc"))) into tK
      put stHex(cxSha3_256(stText("abc"))) into tS3
      put stHex(cxSha256(stText("abc"))) into tS2
      put stHex(cxRipemd160(stText("abc"))) into tR
      stAssert "keccak differs from sha3", tK is not tS3
      stAssert "keccak differs from sha256", tK is not tS2
      stAssert "sha3 differs from sha256", tS3 is not tS2
      stAssert "ripemd differs from them all", tR is not tK and tR is not tS3 and tR is not tS2
      -- One flipped input bit must change the digest. A binding that hashed a
      -- stale or empty buffer would pass every fixed vector above by accident
      -- only if the vector were wrong too, but this catches a buffer that never
      -- gets the caller's bytes at all.
      stAssert "one changed input byte changes the digest", stHex(cxKeccak256(stText("abc"))) is not stHex(cxKeccak256(stText("abd")))
   catch tError
      stSectionFailed "independence", tError
   end try
end stRunIndependence

-- CoinXT handles money, so a malformed input must produce a clean error, never
-- a wrong-but-plausible answer. Both of these are guards in the shim
-- (CNX_ERR_RANGE and CNX_ERR_BADLEN), surfaced by the .lcb as a throw.
command stRunFailClosed
   local tThrew
   stSection "fail closed on malformed input"
   try
      put "false" into tThrew
      try
         get cxPbkdf2HmacSha512(stText("pw"), stText("salt"), 0, 64)
      catch tInner
         put "true" into tThrew
      end try
      stAssert "zero iterations is refused", tThrew is "true"

      put "false" into tThrew
      try
         get cxPbkdf2HmacSha512(stText("pw"), stText("salt"), 1, 0)
      catch tInner2
         put "true" into tThrew
      end try
      stAssert "a zero-length output request is refused", tThrew is "true"
   catch tError
      stSectionFailed "fail closed", tError
   end try
end stRunFailClosed

-- ---- small helpers -----------------------------------------------------------
-- Text to Data. Every cx* input is a Data; a bare literal would be text, and the
-- engine would be free to re-encode it.
function stText pString
   return textEncode(pString, "utf-8")
end stText

-- Lowercase hex, encoded here rather than borrowed. CoinXT's own hex encoder is
-- a phase-2 script-layer encoding that does not exist yet, and reaching for
-- SodiumXT's sxBin2Hex would make a CoinXT check fail whenever SodiumXT is the
-- absent member. A harness must not need one member present to test another.
function stHex pData
   local tOut, tI, tByte, tDigits
   put "0123456789abcdef" into tDigits
   put empty into tOut
   repeat with tI = 1 to the number of bytes of pData
      put byteToNum(byte tI of pData) into tByte
      put char (tByte div 16 + 1) of tDigits after tOut
      put char (tByte mod 16 + 1) of tDigits after tOut
   end repeat
   return tOut
end stHex

-- pCount copies of byte pCode, built without string-escape folklore.
function stRepeatByte pCode, pCount
   local tOne, tOut
   put numToByte(pCode) into tOne
   put tOne into tOut
   -- double up to size, then trim: O(log n) concatenations
   repeat while the number of bytes in tOut < pCount
      put tOut & tOut into tOut
   end repeat
   return byte 1 to pCount of tOut
end stRepeatByte
