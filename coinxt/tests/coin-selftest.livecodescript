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
-- COVERAGE NOTE (honest): every public cx* handler is driven here, across all
-- three built phases. Phase 1 (the .lcb): cxCheckABI, the seven hash *Len
-- accessors, cxKeccak256, cxSha3_256, cxSha256, cxSha512, cxRipemd160,
-- cxHmacSha256, cxHmacSha512, cxPbkdf2HmacSha512. Phase 2 (the .lcb):
-- cxNewSeckey, cxSeckeyIsValid, cxPublicKey, cxPubkeyDecompress, cxSign,
-- cxVerify, cxSignRecoverable, cxRecover, cxEcdh and their six length
-- accessors. Phase 3 (src/coinxt.livecodescript): the hex, Base58Check,
-- bech32/bech32m and RLP encoders, cxHash160/cxHash256, and the four address
-- builders. The vectors are Keccak-256 (Ethereum 0x01 padding), FIPS 180-4
-- SHA-2, the RIPEMD-160 specification vectors, NIST SHA3-256, RFC 4231 HMAC
-- cases 1 and 2, the BIP-39 abandon-about/TREZOR seed, the secp256k1 generator
-- G, the published RFC 6979 signature of sha256("Satoshi Nakamoto") under the
-- private key 1, and for phase 3 the BIP-173/BIP-350 addresses, the EIP-55
-- examples and the RLP yellow-paper examples.
--
-- TWO DIFFERENT LOADS ARE BEING TESTED HERE, and it is worth knowing which is
-- which when something fails. Phases 1 and 2 are the .lcb extension. Phase 3 is
-- a SCRIPT that must be in the message path (`start using stack "coinxt"`), the
-- way OnionXT ships its ox* surface. If every phase-3 section fails with
-- "handler not found" while the earlier ones pass, the extension loaded and the
-- script did not - that is a setup problem, not a defect.
--
-- THIS FILE HAS NOT ITSELF BEEN RUN ON AN ENGINE YET, so it is verified
-- statically. Running it is what turns the 12 phase-1 handlers the 2026-08-08
-- suite pass could not reach, all 15 phase-2 handlers, and the whole phase-3
-- surface into runtime results. Phase 3's LOGIC has been executed headlessly by
-- tools/check-script-vectors.py against these same vectors; what is still
-- unobserved for it is engine PARSER behaviour, which only a real engine
-- settles.
--
-- WHAT IT DELIBERATELY DOES NOT PROVE: anything about HD wallets or mnemonics.
-- Those are phase 4 and do not exist yet. Nor Taproot key tweaking: cxBtcAddressP2TR
-- encodes an output key it is GIVEN and does not derive one (see its comment).
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

-- ---- secp256k1 (phase 2) -----------------------------------------------------
-- The private key 1 is the curve's generator G, so its public key needs no
-- vector table: it IS the published definition of secp256k1. That is why the
-- curve sections below use it rather than a random-looking test key.
constant kPubOneCompressed = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
constant kPubOneUncompressed = "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"

-- The RFC 6979 deterministic signature of sha256("Satoshi Nakamoto") under that
-- same key: the most-republished vector for secp256k1 + SHA-256, and identical
-- to the one pinned in tools/coin-kat.py. Low-s, as both Bitcoin relay policy
-- and Ethereum consensus require.
constant kSigSatoshi = "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d82442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"

-- ---- phase 3: encodings and addresses ----------------------------------------
-- Every one of these is a PUBLISHED vector, identical to the values
-- tools/coin_reference.py pins and tools/check-script-vectors.py runs the real
-- script against. Two of them are worth pointing at, because they make this
-- harness stronger than it looks: hash160 of the compressed generator G is
-- 751e76e8...33bd6, which is EXACTLY the witness program in BIP-173's own
-- example address, and the x-only G is the program in BIP-350's. So deriving an
-- address from the private key 1 lands on a published answer at both witness
-- versions - no CoinXT-invented expectations anywhere in this section.
constant kBase58Payload = "00010966776006953D5567439E5E39F86A0D273BEE"
constant kBase58Address = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM"
constant kBase58Corrupt = "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvN"
constant kP2wpkhOfG = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
constant kP2trOfG = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"
constant kP2pkhOfG = "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH"
constant kEthOfG = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"
constant kEip55A = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
constant kEip55B = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
constant kBech32Valid = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
constant kSegwitTestnet = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"
constant kSegwitTestnetProgram = "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262"
-- BIP-350's invalid list: a version 0 address carrying a bech32m checksum. This
-- is the single most important rejection in the whole encoding surface.
constant kSegwitV0WithBech32m = "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T5"

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
   put "Phases 1 and 2: all 31 public cx* handlers." & return after sResultText

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
   stRunCurveKeys
   stRunCurveSign
   stRunCurveVerify
   stRunCurveRecover
   stRunCurveEcdh
   stRunCurveFailClosed
   stRunHex
   stRunBase58
   stRunBech32
   stRunAddresses
   stRunEip55
   stRunRlp

   stSection "summary"
   stNote "Vectors are identical to tools/coin-kat.py, so this run and the"
   stNote "headless KAT run are the same claim at two different layers."
   stNote "Nothing here covers HD wallets or addresses (phases 3-4)."
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
      stAssert "cxSeckeyLen() is 32", cxSeckeyLen() is 32
      stAssert "cxPubkeyLenCompressed() is 33", cxPubkeyLenCompressed() is 33
      stAssert "cxPubkeyLenUncompressed() is 65", cxPubkeyLenUncompressed() is 65
      stAssert "cxSignatureLen() is 64", cxSignatureLen() is 64
      stAssert "cxRecoverableSignatureLen() is 65", cxRecoverableSignatureLen() is 65
      stAssert "cxEcdhLen() is 65", cxEcdhLen() is 65
      stAssert "a recoverable signature is one byte longer than a plain one", cxRecoverableSignatureLen() is cxSignatureLen() + 1
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

-- ---- the secp256k1 curve (phase 2) -------------------------------------------
-- These sections are the reason phase 2 needs an engine pass at all. The shim
-- itself is already proven headless by tools/coin-kat.py against the same
-- vectors; what only an engine can answer is whether the BINDING carries them.
-- Two shapes below are new to coinxt.lcb and are the ones to watch if this run
-- goes red: cxPublicKey passes a boolean through a C int flag, and cxVerify and
-- cxSeckeyIsValid RETURN Boolean where every phase-1 handler returned Data.

command stRunCurveKeys
   local tSk, tPubC, tPubU
   stSection "secp256k1 keys"
   try
      put stSeckeyOne() into tSk
      -- cxNewSeckey validates caller entropy and hands it back unchanged. The
      -- private key 1 is the generator G, which is why no vector table is
      -- needed here: this public key is the curve's own definition.
      stAssert "cxNewSeckey accepts a valid key", stHex(cxNewSeckey(tSk)) is stHex(tSk)
      stAssert "cxSeckeyIsValid says true for a valid key", cxSeckeyIsValid(tSk) is true
      put cxPublicKey(tSk, true) into tPubC
      put cxPublicKey(tSk, false) into tPubU
      stAssert "cxPublicKey compressed is G", stHex(tPubC) is kPubOneCompressed
      stAssert "cxPublicKey uncompressed is G", stHex(tPubU) is kPubOneUncompressed
      -- The boolean flag is the new marshalling shape (an LCB Boolean into a C
      -- int). If it were dropped, both calls would return the same length.
      stAssert "the compressed key is 33 bytes", the number of bytes of tPubC is 33
      stAssert "the uncompressed key is 65 bytes", the number of bytes of tPubU is 65
      stAssert "cxPubkeyDecompress rebuilds the uncompressed key", stHex(cxPubkeyDecompress(tPubC)) is stHex(tPubU)
      stAssert "cxPubkeyDecompress of an uncompressed key is a no-op", stHex(cxPubkeyDecompress(tPubU)) is stHex(tPubU)
   catch tError
      stSectionFailed "secp256k1 keys", tError
   end try
end stRunCurveKeys

command stRunCurveSign
   local tSk, tDigest, tSig, tAgain
   stSection "ECDSA signing (RFC 6979, published vector)"
   try
      put stSeckeyOne() into tSk
      -- The digest is built with cxSha256, which this same run already checked
      -- against FIPS 180-4, so a failure here cannot be a hashing failure.
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSign(tSk, tDigest) into tSig
      stAssert "cxSign reproduces the published RFC 6979 signature", stHex(tSig) is kSigSatoshi
      stAssert "the signature is 64 bytes", the number of bytes of tSig is cxSignatureLen()
      -- Determinism is the property the whole vector table rests on. The native
      -- code draws fresh OS entropy for side-channel blinding on every call;
      -- that blinding cancels, and this is the check that says so from script.
      put cxSign(tSk, tDigest) into tAgain
      stAssert "signing twice gives the same signature", stHex(tAgain) is stHex(tSig)
   catch tError
      stSectionFailed "ECDSA signing", tError
   end try
end stRunCurveSign

command stRunCurveVerify
   local tSk, tDigest, tSig, tPubC, tPubU, tBad, tOtherPub
   stSection "ECDSA verification (true, and false)"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSign(tSk, tDigest) into tSig
      put cxPublicKey(tSk, true) into tPubC
      put cxPublicKey(tSk, false) into tPubU
      -- cxVerify RETURNS Boolean rather than throwing, which is the second new
      -- shape in this file. A binding that mismarshalled it would most likely
      -- throw or return empty, so assert the true case explicitly.
      stAssert "cxVerify accepts a good signature (compressed key)", cxVerify(tPubC, tDigest, tSig) is true
      stAssert "cxVerify accepts a good signature (uncompressed key)", cxVerify(tPubU, tDigest, tSig) is true
      put stFlipByte(tSig, 6) into tBad
      stAssert "cxVerify rejects a tampered signature", cxVerify(tPubC, tDigest, tBad) is false
      stAssert "cxVerify rejects a wrong digest", cxVerify(tPubC, cxSha256(stText("not the message")), tSig) is false
      put cxPublicKey(stSeckeyTwo(), true) into tOtherPub
      stAssert "cxVerify rejects the wrong public key", cxVerify(tOtherPub, tDigest, tSig) is false
   catch tError
      stSectionFailed "ECDSA verification", tError
   end try
end stRunCurveVerify

command stRunCurveRecover
   local tSk, tDigest, tSig, tRec, tPubU
   stSection "recoverable signing and ecrecover"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("Satoshi Nakamoto")) into tDigest
      put cxSignRecoverable(tSk, tDigest) into tSig
      put cxPublicKey(tSk, false) into tPubU
      stAssert "a recoverable signature is 65 bytes", the number of bytes of tSig is cxRecoverableSignatureLen()
      stAssert "its first 64 bytes are the plain signature", stHex(byte 1 to 64 of tSig) is kSigSatoshi
      stAssert "the recovery id is 0..3", byteToNum(byte 65 of tSig) >= 0 and byteToNum(byte 65 of tSig) <= 3
      put cxRecover(tSig, tDigest) into tRec
      -- The whole point of recovery: get the signer back from the signature
      -- alone. Recovery ALSO succeeds for a wrong id and returns some other
      -- key, so comparing against the expected key is the real check.
      stAssert "cxRecover returns the signing public key", stHex(tRec) is stHex(tPubU)
      stAssert "and that key is the published G", stHex(tRec) is kPubOneUncompressed
   catch tError
      stSectionFailed "ecrecover", tError
   end try
end stRunCurveRecover

command stRunCurveEcdh
   local tA, tB, tPubA, tPubB, tShared1, tShared2
   stSection "ECDH"
   try
      put stSeckeyOne() into tA
      put stSeckeyTwo() into tB
      put cxPublicKey(tA, true) into tPubA
      put cxPublicKey(tB, true) into tPubB
      put cxEcdh(tA, tPubB) into tShared1
      put cxEcdh(tB, tPubA) into tShared2
      stAssert "both sides derive the same point", stHex(tShared1) is stHex(tShared2)
      stAssert "the shared point is 65 bytes", the number of bytes of tShared1 is cxEcdhLen()
      stAssert "the shared point is in uncompressed form", byteToNum(byte 1 of tShared1) is 4
      -- 1 * (2G) == 2G, so with these two keys the shared point is just the
      -- public key of the other side. That makes this leg checkable against a
      -- value already pinned above rather than against a new magic constant.
      stAssert "1 * 2G is 2G", stHex(tShared1) is stHex(cxPublicKey(tB, false))
   catch tError
      stSectionFailed "ECDH", tError
   end try
end stRunCurveEcdh

command stRunCurveFailClosed
   local tThrew, tSk, tDigest
   stSection "the curve fails closed"
   try
      put stSeckeyOne() into tSk
      put cxSha256(stText("abc")) into tDigest

      -- A key of zero is not on the curve. cxSeckeyIsValid answers false (an
      -- ordinary answer for an imported key), while cxNewSeckey THROWS (fresh
      -- entropy that fails validation is a bug in the caller's RNG, not a
      -- routine outcome). Both halves of that split are checked.
      stAssert "cxSeckeyIsValid says false for an all-zero key", cxSeckeyIsValid(stRepeatByte(0, 32)) is false
      stAssert "cxSeckeyIsValid says false for a short key", cxSeckeyIsValid(stRepeatByte(1, 31)) is false

      put "false" into tThrew
      try
         get cxNewSeckey(stRepeatByte(0, 32))
      catch tInner
         put "true" into tThrew
      end try
      stAssert "cxNewSeckey refuses an all-zero key", tThrew is "true"

      put "false" into tThrew
      try
         get cxNewSeckey(stRepeatByte(7, 31))
      catch tInner2
         put "true" into tThrew
      end try
      stAssert "cxNewSeckey refuses 31 bytes of entropy", tThrew is "true"

      put "false" into tThrew
      try
         get cxSign(stRepeatByte(0, 32), tDigest)
      catch tInner3
         put "true" into tThrew
      end try
      stAssert "cxSign refuses an invalid private key", tThrew is "true"

      -- An all-zero digest is refused because a signature over it can be forged
      -- for ANY public key.
      put "false" into tThrew
      try
         get cxSign(tSk, stRepeatByte(0, 32))
      catch tInner4
         put "true" into tThrew
      end try
      stAssert "cxSign refuses an all-zero digest", tThrew is "true"

      -- A malformed public key must THROW, not answer false: it is a bug in the
      -- caller, and hiding it behind a security-shaped `false` is how a broken
      -- verify path goes unnoticed.
      put "false" into tThrew
      try
         get cxVerify(stRepeatByte(9, 20), tDigest, cxSign(tSk, tDigest))
      catch tInner5
         put "true" into tThrew
      end try
      stAssert "cxVerify throws on a malformed public key (it does not answer false)", tThrew is "true"
   catch tError
      stSectionFailed "the curve fails closed", tError
   end try
end stRunCurveFailClosed


-- ---- phase 3: the pure-script encodings --------------------------------------
-- These handlers live in src/coinxt.livecodescript, NOT in the .lcb module, so
-- they only resolve once that script is in the message path (`start using stack
-- "coinxt"`, the same way OnionXT ships its ox* surface). A "handler not found"
-- in this whole block means the script layer was not loaded, which is a setup
-- problem and not a phase-3 defect - check that first before reading further.

command stRunHex
   stSection "hex"
   try
      stAssert "cxHexEncode of 00ff10ab", cxHexEncode(cxHexDecode("00ff10ab")) is "00ff10ab"
      stAssert "cxHexDecode accepts upper case", cxHexEncode(cxHexDecode("00FF10AB")) is "00ff10ab"
      stAssert "cxHexEncode of the empty input", cxHexEncode(cxHexDecode("")) is ""
      stAssert "an odd-length hex string is refused", stThrows("cxHexDecode", "abc")
      stAssert "a non-hex character is refused", stThrows("cxHexDecode", "zz")
   catch tError
      stSectionFailed "hex", tError
   end try
end stRunHex

command stRunBase58
   local tPayload, tI, tPadded
   stSection "Base58Check"
   try
      put cxHexDecode(kBase58Payload) into tPayload
      stAssert "encodes the worked example", cxBase58CheckEncode(tPayload) is kBase58Address
      stAssert "decodes it back", cxHexEncode(cxBase58CheckDecode(kBase58Address)) is stToLowerText(kBase58Payload)
      -- The checksum is the entire point of the encoding: one flipped character
      -- must be refused, never coerced into a nearby valid-looking payload.
      stAssert "a corrupt checksum is refused", stThrows("cxBase58CheckDecode", kBase58Corrupt)
      stAssert "a character outside the alphabet is refused", stThrows("cxBase58CheckDecode", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtj0O")
      -- Leading zero bytes must survive as leading "1"s, one for one. That is
      -- what makes a mainnet P2PKH address start with a 1 at all.
      put numToByte(0) & numToByte(0) & cxHexDecode("deadbeef") into tPadded
      stAssert "two leading zero bytes give two leading ones", char 1 to 2 of cxBase58CheckEncode(tPadded) is "11"
      stAssert "the round trip preserves them", cxHexEncode(cxBase58CheckDecode(cxBase58CheckEncode(tPadded))) is "0000deadbeef"
   catch tError
      stSectionFailed "Base58Check", tError
   end try
end stRunBase58

command stRunBech32
   local tDecoded
   stSection "bech32 and bech32m"
   try
      put cxBech32DecodeValues(kBech32Valid) into tDecoded
      stAssert "a published bech32 string decodes", tDecoded["hrp"] is "abcdef"
      stAssert "and reports the bech32 encoding", tDecoded["spec"] is "bech32"
      stAssert "a mixed-case string is refused", stThrows("cxBech32DecodeValues", "A1G7SGD8x")
      stAssert "a string with no separator is refused", stThrows("cxBech32DecodeValues", "pzry9x0s0muk")
      stAssert "an empty human-readable part is refused", stThrows("cxBech32DecodeValues", "1pzry9x0s0muk")
      stAssert "a checksum computed over an uppercase HRP is refused", stThrows("cxBech32DecodeValues", "A1G7SGD8")
      stAssert "a data character outside the charset is refused", stThrows("cxBech32DecodeValues", "x1b4n0q5v")
   catch tError
      stSectionFailed "bech32", tError
   end try
end stRunBech32

command stRunAddresses
   local tPubC, tPubU, tSeckey, tDecoded
   stSection "addresses from the generator G"
   try
      put stRepeatByte(0, 31) & numToByte(1) into tSeckey
      put cxPublicKey(tSeckey, true) into tPubC
      put cxPublicKey(tSeckey, false) into tPubU
      -- Each of these is a PUBLISHED answer, not a CoinXT expectation.
      stAssert "cxBtcAddressP2PKH of G", cxBtcAddressP2PKH(tPubC) is kP2pkhOfG
      stAssert "cxBtcAddressP2WPKH of G is the BIP-173 vector", cxBtcAddressP2WPKH(tPubC) is kP2wpkhOfG
      stAssert "cxBtcAddressP2TR of x-only G is the BIP-350 vector", cxBtcAddressP2TR(byte 2 to 33 of tPubU) is kP2trOfG
      stAssert "cxEthAddress of G (from the compressed key)", cxEthAddressChecksum(cxEthAddress(tPubC)) is kEthOfG
      stAssert "cxEthAddress agrees from the uncompressed key", cxEthAddress(tPubU) is cxEthAddress(tPubC)
      -- An uncompressed key in a v0 SegWit address makes funds unspendable by
      -- every modern wallet, so it must be refused rather than encoded.
      stAssert "P2WPKH refuses an uncompressed key", stThrows("cxBtcAddressP2WPKH", tPubU)
      stAssert "P2TR refuses a 33-byte key", stThrows("cxBtcAddressP2TR", tPubC)
      -- Round-trip through the SegWit decoder, including the network check.
      put cxSegwitAddressDecode("bc", kP2wpkhOfG) into tDecoded
      stAssert "the decoded witness version is 0", tDecoded["version"] is 0
      stAssert "the decoded program is hash160 of G", cxHexEncode(tDecoded["program"]) is cxHexEncode(cxHash160(tPubC))
      put cxSegwitAddressDecode("tb", kSegwitTestnet) into tDecoded
      stAssert "a testnet v0 script address decodes", cxHexEncode(tDecoded["program"]) is kSegwitTestnetProgram
      stAssert "a mainnet address is refused under the testnet HRP", stThrows2("cxSegwitAddressDecode", "tb", kP2wpkhOfG)
      -- THE rule BIP-350 exists for.
      stAssert "a version 0 address with a bech32m checksum is refused", stThrows2("cxSegwitAddressDecode", "bc", kSegwitV0WithBech32m)
   catch tError
      stSectionFailed "addresses", tError
   end try
end stRunAddresses

command stRunEip55
   stSection "EIP-55 checksummed Ethereum addresses"
   try
      stAssert "checksums the first specification example", cxEthAddressChecksum(stToLowerText(kEip55A)) is kEip55A
      stAssert "checksums the second", cxEthAddressChecksum(stToLowerText(kEip55B)) is kEip55B
      stAssert "recognises a correctly checksummed address", cxEthAddressIsChecksummed(kEip55A) is true
      -- An all-lowercase address carries NO checksum, so reporting it as valid
      -- would quietly retire the protection EIP-55 exists to give.
      stAssert "an all-lowercase address is NOT reported as checksummed", cxEthAddressIsChecksummed(stToLowerText(kEip55A)) is false
      stAssert "a wrong-length address is refused", stThrows("cxEthAddressChecksum", "0xdeadbeef")
   catch tError
      stSectionFailed "EIP-55", tError
   end try
end stRunEip55

command stRunRlp
   local tCatDog, tDecoded
   stSection "RLP"
   try
      stAssert "encodes the string dog", cxHexEncode(cxRlpEncodeBytes(stText("dog"))) is "83646f67"
      stAssert "encodes the empty string", cxHexEncode(cxRlpEncodeBytes("")) is "80"
      stAssert "encodes a single byte below 0x80 as itself", cxHexEncode(cxRlpEncodeBytes(numToByte(15))) is "0f"
      stAssert "encodes the empty list", cxHexEncode(cxRlpEncodeList("")) is "c0"
      put cxRlpEncodeBytes(stText("cat")) & cxRlpEncodeBytes(stText("dog")) into tCatDog
      stAssert "encodes the list of cat and dog", cxHexEncode(cxRlpEncodeList(tCatDog)) is "c88363617483646f67"
      put cxRlpDecode(cxHexDecode("83646f67")) into tDecoded
      stAssert "decodes a string item", tDecoded["kind"] is "bytes"
      stAssert "and its payload", cxHexEncode(tDecoded["payload"]) is "646f67"
      put cxRlpDecode(cxHexDecode("c88363617483646f67")) into tDecoded
      stAssert "decodes a list item", tDecoded["kind"] is "list"
      -- RLP's guarantee is one value, one encoding. A decoder that accepts a
      -- second spelling breaks every hash computed over the result.
      stAssert "a single byte wrapped in a length prefix is refused", stThrows("cxRlpDecode", cxHexDecode("8100"))
   catch tError
      stSectionFailed "RLP", tError
   end try
end stRunRlp

-- ---- small helpers -----------------------------------------------------------
-- Did calling pHandler with one argument throw? The encoders fail closed by
-- throwing, and "it threw" is the assertion, so this keeps each check to one
-- readable line instead of a nested try per case.
function stThrows pHandler, pArg
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArg)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows

-- The two-argument form (cxSegwitAddressDecode takes an HRP and an address).
function stThrows2 pHandler, pArgA, pArgB
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArgA, pArgB)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows2

-- ASCII lowercase, by byte value, so it does not depend on the caseSensitive.
function stToLowerText pText
   local tI, tCount, tCode, tOut
   put "" into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         add 32 to tCode
      end if
      put numToChar(tCode) after tOut
   end repeat
   return tOut
end stToLowerText


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

-- The private key 1: 31 zero bytes then a 1. Built rather than written as a hex
-- literal because this file has no hex DECODER (cxHexDecode is a phase-3
-- script-layer encoding that does not exist yet), and a harness must not depend
-- on the layer it is testing for its own inputs.
function stSeckeyOne
   return stRepeatByte(0, 31) & numToByte(1)
end stSeckeyOne

-- The private key 2, whose public key is 2G.
function stSeckeyTwo
   return stRepeatByte(0, 31) & numToByte(2)
end stSeckeyTwo

-- Return pData with byte pIndex changed to a different value, for the "must be
-- rejected" checks. Addition mod 256 rather than bitXor: the family gotcha list
-- warns that bitAnd/bitOr/bitXor are OPERATORS, not functions, and this file
-- avoids the whole question.
function stFlipByte pData, pIndex
   local tByte
   put (byteToNum(byte pIndex of pData) + 1) mod 256 into tByte
   return byte 1 to (pIndex - 1) of pData & numToByte(tByte) & \
      byte (pIndex + 1) to (the number of bytes of pData) of pData
end stFlipByte

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
