script "coinSelfTest"
-- STATUS: last run GREEN in the 2026-08-17 engine pass (Windows x86_64, NT 10.0, OXT 9.6.3) - 278/278, zero failures, folded
-- into tests/suite-selftest.livecodescript. Runs standalone too: this file
-- carries src/coinxt.livecodescript, so there is nothing to `start using`.

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
-- the 16 public cx* handlers that existed then: there was no paste-and-run way
-- to drive the rest. This file closes that. It names EVERY public cx* handler
-- (94 as of 2026-08-26: 43 in src/coinxt.lcb and 51 in
-- src/coinxt.livecodescript) and checks every deterministic output against the
-- same published vector tools/coin-kat.py pins, so a green run here and a green
-- run there are the same claim at two different layers. That count is measured,
-- not maintained by hand: tools/check-suite-coverage.py is what proves the
-- harness still reaches all of them, and it fails the build if one goes dark.
--
-- COVERAGE NOTE (honest): every public cx* handler is driven here, across all
-- FIVE built phases plus the ABI 6 BIP-340/BIP-341 surface. The per-phase lists
-- below were written when three phases existed and are kept as the phase 1-3
-- roll-call; phases 4 (BIP-39/32/44 HD wallets) and 5 (Bitcoin legacy + BIP-143
-- SegWit, Ethereum EIP-155 + EIP-1559 transactions) and the Schnorr/Taproot
-- sections are driven by their own sections further down this file. Phase 1
-- (the .lcb): cxCheckABI, the seven hash *Len
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
-- CORRECTED 2026-08-26. The three paragraphs that stood here said this file had
-- never run on an engine, that HD wallets and mnemonics "are phase 4 and do not
-- exist yet", and that Taproot key tweaking was unproven. All three were true
-- when written and none has been true for a while: the STATUS line at the top of
-- this file records a GREEN 278/278 engine run, and the file makes 92 calls into
-- the mnemonic and HD surface and 106 into the Schnorr/Taproot one. A STATUS
-- line was prepended above and the stale body underneath it was left standing,
-- so the header contradicted itself. What is actually true now:
--
-- RUN HISTORY: engine-passed. Phases 1-3 closed 2026-08-10 (207/207 on the
-- same-day re-run, after the engine surfaced one real fail-open in
-- cxHdDerivePath); phase 5 closed 2026-08-12 (Windows x64, 230/230); the ABI 6
-- Schnorr/Taproot surface ran green 2026-08-16 on the day it shipped; the last
-- full run was 278/278 on 2026-08-17. tools/check-script-vectors.py continues to
-- execute the real .livecodescript headlessly against the same vectors on every
-- push, so a regression between engine passes is caught by CI, not by the next
-- paste.
--
-- WHAT IT STILL DOES NOT PROVE: cxBtcAddressP2TR encodes an output key it is
-- GIVEN and does not derive one (see its comment) - the tweak itself is a
-- separate, and now shipped, ABI 6 handler. There is no BIP-341 sighash builder
-- anywhere in coinxt: it signs a sighash it is handed. And no transaction this
-- file builds has been broadcast to a live network.
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

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- coinxt/src/coinxt.livecodescript ----

-- coinxt.livecodescript - the CoinXT script layer (phase 3: encodings and
-- addresses; phase 4: BIP-39 mnemonics and BIP-32 HD derivation; phase 5:
-- transaction building; ABI 6: the BIP-341 Taproot tweak and the P2TR address
-- that applies it).
--
-- WHAT LIVES HERE AND WHY. Everything in this file is checksummed byte
-- shuffling with no secret-dependent branch, so it belongs in script where it
-- is diffable, reviewable and KAT-covered - exactly as OnionXT does base32
-- (CLAUDE.md, "The C-vs-script split"). Nothing here invents cryptography: every
-- hash is a cx* call into the audited native shim, and this file only moves
-- bits and verifies checksums.
--
-- The inverse rule matters just as much: nothing that touches a private key or
-- a curve point is implemented here. Those are src/coinxt.lcb over the two
-- vendored native libraries (trezor-crypto for the hashes, ECDSA, ECDH and the
-- BIP-32 curve steps; upstream libsecp256k1 for BIP-340 Schnorr and the
-- BIP-341 tweak - see SPEC.md section 2 for why there are now two). If you
-- find yourself reaching for modular arithmetic on a 256-bit number in this
-- file, stop; it is in the wrong layer.
--
-- ==========================================================================
-- STATUS: ENGINE-PASSED, twice. This block used to read "NEEDS AN OXT PASS";
-- the passes landed 2026-08-10 (the folded suite harness, coinxt section
-- 207/207) and 2026-08-12 (Windows x64, 230/230, phase 5 included), both
-- recorded in CLAUDE.md's as-built notes.
--
-- OXT cannot compile or run a .livecodescript headlessly, so historically a
-- file like this would ship never having run. Three things stood behind it
-- before the engine did - each still runs in CI, and it is worth being exact
-- about what each is worth:
--
--   * tools/coin_reference.py is an independent implementation of every
--     encoding here, and it reproduces the PUBLISHED vectors - BIP-173's valid
--     and invalid strings, BIP-173/350's SegWit addresses, EIP-55's own
--     examples, the RLP yellow-paper examples and a Base58Check worked example.
--     So the ANSWERS this file must produce are pinned by something
--     independently correct, not by this file agreeing with itself.
--     Phase 4 is pinned the same way, against the official BIP-39 english
--     vectors, BIP-32 test vectors 1 to 3 (including vector 3, which exists
--     solely because its master key has a leading zero byte), and the test
--     mnemonic every wallet ships with walked down BIP-44, BIP-84 and Ethereum
--     paths to their published addresses.
--   * tools/check-script-vectors.py RUNS THIS ACTUAL FILE against those vectors.
--     tools/lcs-interp.py interprets the LiveCodeScript subset used here, and
--     the cx* hash handlers are supplied by the REAL native library, so what
--     executes is this file's own logic over genuine crypto. That is an
--     approximation of the engine, NOT the engine: it settles logic, never
--     parser behaviour, and it promotes nothing out of "verified statically".
--     What it buys is that a wrong alphabet or an inverted checksum is caught
--     in CI rather than in a scarce engine session.
--   * tests/coin-selftest.livecodescript drives every handler below against the
--     same vectors, so ONE paste on a real engine settles the rest.
--
-- That engine run has happened (the two passes above), so the closing line
-- that stood here - "the LOGIC is observed, the ENGINE BEHAVIOUR is not" -
-- no longer holds: both are observed for this layer. What stays open is
-- narrower and is phase 5's alone: a live testnet broadcast is still owed
-- before any "broadcastable" claim (see the phase-5 STATUS block below).
-- ==========================================================================
--
-- THE THREE PORTABILITY DISCIPLINES this file follows, each paid for already
-- by OnionXT and recorded in templates/CLAUDE.md:
--
--   1. NO `^`, `div`, `mod`, `bitAnd`, `bitOr` OR `bitXor` ANYWHERE. Some xTalk
--      parsers reject `^` inside a compound expression, and bitAnd/bitOr/bitXor
--      are OPERATORS in this dialect rather than functions - so `bitXor(a, b)`
--      is a syntax error and `a bitXor b` is not portable across the parsers
--      this family has met. Every one of them is replaced by a small arithmetic
--      helper below (cxIntDiv, cxIntMod, cxPow2, cxBitXor). The bech32 checksum
--      needs 30-bit XOR and gets it from cxBitXor.
--   2. THE ACCUMULATOR IS MASKED EVERY STEP so it never approaches 2^53, where
--      an xTalk number stops being an exact integer. A 320-bit base58 payload
--      is NEVER held as one number: base58 conversion is long division over a
--      BYTE ARRAY (see cxBase58Encode), which is why this file has no bignum.
--   3. ALPHABET LOOKUP COMPARES BYTE VALUES, NOT CHARACTERS. `offset()` and
--      `is` honour `the caseSensitive`, which defaults to FALSE - and in Base58
--      `a` and `A` are DIFFERENT DIGITS, so a case-insensitive lookup silently
--      decodes the wrong number and hands back a valid-looking wrong key. Rather
--      than set a global property this library does not own, cxCharIndex
--      compares byteToNum values, which is exact whatever the caller's setting.
--      This is the single most dangerous line of this whole file; do not
--      "simplify" it to offset().
--   4. THIS FILE ASSUMES `the itemDelimiter` IS ITS DEFAULT COMMA, and that is
--      a REAL DEPENDENCY, not a note for tidiness. Twenty-six chunk expressions
--      here read comma-separated lists (bech32's 5-bit values, the 8-to-5
--      converters, the mnemonic word split, the path split), and every one of
--      them reads whatever the ENGINE's current item delimiter is. An app that
--      did `set the itemDelimiter to tab` and did not put it back would not get
--      an error from this file; it would get a silently wrong answer, which on
--      this surface means a wrong address.
--
--      THE FAMILY ALREADY SETTLED WHAT THIS PROPERTY IS, and this comment used
--      to say otherwise. templates/CLAUDE.md rule 5 states it plainly:
--      `itemDelimiter` / `lineDelimiter` are GLOBAL MUTABLE STATE - set them
--      immediately before the parse that needs them and RESTORE them afterward,
--      because other code assumes the defaults. OnionXT, which is the member
--      with the most on-engine hours, does exactly that at six sites (see
--      oxFieldAfter). So the remedy is NOT "set it at the top of every handler"
--      - that would leave the caller's delimiter changed, which is the very
--      thing the rule forbids - it is save, set, use, restore.
--
--      Applying that here is a deliberate change of its own, because a handler
--      that throws must restore on the way out too, and this file throws by
--      design on every malformed input. Until it is made, the dependency is
--      stated in docs/api-reference.md as a caller requirement.
--
-- FAIL CLOSED, EVERYWHERE. Every decoder verifies its checksum and throws
-- "CoinXT: <handler>: ..." on anything malformed. A corrupt address is never
-- coerced into a plausible one. That is not defensive style; on this surface a
-- wrong-but-plausible answer is a payment to a stranger.

-- ---- alphabets and constants -------------------------------------------------
-- Declared before first use: OXT resolves a constant by lexical position and a
-- forward reference silently evaluates to nothing.

-- Base58, Satoshi's ordering: the ASCII digits and letters MINUS 0, O, I and l,
-- the four that are confusable in print. Order is significant - it IS the digit
-- value mapping - so this string is checked against the reference by
-- tools/check-script-vectors.py.
constant kCxBase58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

-- Bech32 (BIP-173) data charset. Also order-significant, also gated.
constant kCxBech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

-- Lowercase hex digits, for cxHexEncode.
constant kCxHexDigits = "0123456789abcdef"

-- The bech32 checksum constant is 1; bech32m (BIP-350) uses this instead. The
-- ONLY difference between the two encodings is this number, and using the wrong
-- one is how a SegWit v1 address gets accepted as v0 (or the reverse).
constant kCxBech32mConst = 734539939

-- A bech32 string is capped at 90 characters by BIP-173.
constant kCxBech32MaxLen = 90

-- Mainnet P2PKH version byte (an address beginning "1").
constant kCxVersionP2PKH = 0

-- The human-readable part of a mainnet SegWit address.
constant kCxHrpMainnet = "bc"

-- ==============================================================================
-- Small arithmetic helpers. See discipline 1 in the header: these exist so that
-- no operator this family has seen a parser mishandle appears in the code below.
-- ==============================================================================

private function cxIntDiv pA, pB
   -- Integer division, floor, for the NON-NEGATIVE operands every caller here
   -- uses. trunc() rather than `div` (see the header).
   return trunc(pA / pB)
end cxIntDiv

private function cxIntMod pA, pB
   -- pA modulo pB, without the `mod` operator.
   return pA - pB * cxIntDiv(pA, pB)
end cxIntMod

private function cxPow2 pN
   -- 2 to the pN as an exact integer, without `^`. pN stays small here (0..30
   -- for the bech32 checksum, 0..8 for bit packing), so this is a few multiplies
   -- and never leaves exact-integer range.
   local tResult, tI
   put 1 into tResult
   repeat with tI = 1 to pN
      multiply tResult by 2
   end repeat
   return tResult
end cxPow2

private function cxBitXor pA, pB
   -- Bitwise exclusive-or over the low 31 bits, built from arithmetic because
   -- bitXor is an operator in this dialect and its portability across xTalk
   -- parsers is exactly the kind of thing this family has been bitten by.
   -- The bech32 checksum is a 30-bit value, so 31 bits is sufficient headroom
   -- and keeps every intermediate far below 2^53.
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to 31
      put cxIntMod(cxIntDiv(pA, tBit), 2) into tDigitA
      put cxIntMod(cxIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is not tDigitB then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end cxBitXor

private function cxCharIndex pChar, pAlphabet
   -- The 1-based position of pChar in pAlphabet, or 0 if absent, comparing BYTE
   -- VALUES so the answer does not depend on `the caseSensitive` (see discipline
   -- 3 in the header - this is the Base58 a-versus-A trap). Linear over a 58
   -- character alphabet, which is nothing next to the hashing these encoders
   -- already do.
   local tI, tCount, tWanted
   put byteToNum(pChar) into tWanted
   put the number of chars of pAlphabet into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of pAlphabet) is tWanted then
         return tI
      end if
   end repeat
   return 0
end cxCharIndex

private function cxCompareBytes pA, pB
   -- -1, 0 or 1 for pA before / equal to / after pB, comparing BYTE VALUES.
   -- Discipline 3 again: `<` on strings honours `the caseSensitive`, which
   -- defaults to FALSE, and a case-insensitive comparison would put the binary
   -- search below into the wrong half of a list that is sorted by byte value.
   local tI, tLenA, tLenB, tShort, tVa, tVb
   put the number of chars of pA into tLenA
   put the number of chars of pB into tLenB
   put tLenA into tShort
   if tLenB < tShort then
      put tLenB into tShort
   end if
   repeat with tI = 1 to tShort
      put byteToNum(char tI of pA) into tVa
      put byteToNum(char tI of pB) into tVb
      if tVa < tVb then
         return -1
      end if
      if tVa > tVb then
         return 1
      end if
   end repeat
   if tLenA < tLenB then
      return -1
   end if
   if tLenA > tLenB then
      return 1
   end if
   return 0
end cxCompareBytes

-- ==============================================================================
-- Hex. The one encoding with no checksum, so the only failure it can have is a
-- malformed input, and it says so rather than skipping the bad character.
-- ==============================================================================

-- Lowercase hex for arbitrary bytes. The inverse of cxHexDecode.
function cxHexEncode pData
   local tOut, tI, tCount, tByte
   put "" into tOut
   put the number of bytes of pData into tCount
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of pData) into tByte
      put char (cxIntDiv(tByte, 16) + 1) of kCxHexDigits after tOut
      put char (cxIntMod(tByte, 16) + 1) of kCxHexDigits after tOut
   end repeat
   return tOut
end cxHexEncode

-- Bytes from a hex string. Accepts upper, lower or mixed case; rejects an odd
-- length and any non-hex character rather than silently dropping it.
function cxHexDecode pHex
   local tOut, tI, tCount, tHi, tLo, tText
   put pHex into tText
   put the number of chars of tText into tCount
   if cxIntMod(tCount, 2) is not 0 then
      throw "CoinXT: cxHexDecode: a hex string must have an even number of characters."
   end if
   put "" into tOut
   -- WALK THE PAIRS WITH `repeat while` AND AN EXPLICIT `add 2`, NOT WITH
   -- `repeat with tI = 1 to tCount step 2`. This is the one line the first real
   -- OXT pass of the suite harness (2026-08-09) killed, and it is worth the
   -- paragraph because reading it tells you nothing.
   --
   -- The engine did not honour the increment: tI walked 1, 2, 3, ... so the
   -- final pass read `char (tCount + 1) of tText`, which is EMPTY. Empty is
   -- genuinely not a hex digit, so cxHexValue answered -1 and this handler's
   -- own fail-closed check threw "the input contains a character that is not a
   -- hex digit" - over a perfectly good lowercase literal. That is the worst
   -- shape a defect can take here: the library accused the CALLER'S DATA of
   -- being corrupt, in the exact words it uses for a real corruption, so the
   -- symptom pointed at the vector set rather than at the loop. Six harness
   -- sections (hex, Base58Check, RLP, BIP-39, BIP-32, the fail-open
   -- regressions) died on it; every section that never calls cxHexDecode
   -- passed, which is what identified this handler.
   --
   -- `step` was the only construct in this file with no other user anywhere in
   -- the six-member suite, and that is precisely why it was the one that broke:
   -- nothing else had ever put it in front of an engine. Every construct below
   -- ran green in that same session - cxEthAddressChecksum drives cxHexValue
   -- over `char tI of` eighty times per call, and `repeat while` with `add N
   -- to` is how cxBase58Encode and cxConvert8To5 loop. The even-length guard
   -- above is what makes `char (tI + 1)` safe here: tCount is even, so the last
   -- pair starts at tCount - 1 and never reads past the end.
   --
   -- Do not "tidy" this back into a step loop.
   put 1 into tI
   repeat while tI <= tCount
      put cxHexValue(char tI of tText) into tHi
      put cxHexValue(char (tI + 1) of tText) into tLo
      if tHi < 0 or tLo < 0 then
         throw "CoinXT: cxHexDecode: the input contains a character that is not a hex digit."
      end if
      put numToByte(tHi * 16 + tLo) after tOut
      add 2 to tI
   end repeat
   return tOut
end cxHexDecode

private function cxHexValue pChar
   -- 0..15, or -1 when pChar is not a hex digit. Case-insensitive BY VALUE: the
   -- upper and lower alphabets are checked explicitly rather than by folding
   -- case, so this does not depend on `the caseSensitive` either.
   local tCode
   put byteToNum(pChar) into tCode
   if tCode >= 48 and tCode <= 57 then
      return tCode - 48
   end if
   if tCode >= 97 and tCode <= 102 then
      return tCode - 87
   end if
   if tCode >= 65 and tCode <= 70 then
      return tCode - 55
   end if
   return -1
end cxHexValue

-- ==============================================================================
-- Composed hashes. Both are compositions of native calls, named because Bitcoin
-- names them and because writing them out at each call site is how one of them
-- ends up being SHA-256 twice where it should have been RIPEMD-160 of SHA-256.
-- ==============================================================================

-- HASH160 = RIPEMD-160(SHA-256(x)). What a P2PKH and a P2WPKH address commit to.
function cxHash160 pData
   return cxRipemd160(cxSha256(pData))
end cxHash160

-- HASH256 = SHA-256(SHA-256(x)). The Base58Check checksum and Bitcoin's txid.
function cxHash256 pData
   return cxSha256(cxSha256(pData))
end cxHash256

-- ==============================================================================
-- Base58 and Base58Check.
--
-- Base58 is a BASE CONVERSION, not a bit repacking: 58 is not a power of two, so
-- there is no bit-buffer trick and the whole payload is one number. A 25-byte
-- address payload is a 200-bit number, which no xTalk number can hold exactly,
-- so this converts by LONG DIVISION OVER THE BYTE ARRAY - the same way you would
-- do it on paper. Nothing here ever holds a value above 58 * 255.
-- ==============================================================================

private function cxBase58Encode pData
   -- Long division: repeatedly divide the big-endian byte array by 58, emitting
   -- the remainder as a digit, until the array is zero. Leading zero BYTES are
   -- not part of the number, so they are re-attached afterwards as leading "1"s,
   -- one for one, which is what makes a 0x00 version byte show up as the "1"
   -- every mainnet P2PKH address starts with.
   local tDigits, tOut, tI, tCount, tCarry, tValue, tQuotient, tStart, tZeros
   put the number of bytes of pData into tCount
   if tCount is 0 then
      return ""
   end if
   -- Copy the bytes into a numeric list we can divide in place.
   put empty into tDigits
   repeat with tI = 1 to tCount
      put byteToNum(byte tI of pData) into tDigits[tI]
   end repeat
   -- Count the leading zero bytes before they are consumed by the division.
   put 0 into tZeros
   repeat with tI = 1 to tCount
      if tDigits[tI] is not 0 then
         exit repeat
      end if
      add 1 to tZeros
   end repeat
   put "" into tOut
   put 1 into tStart
   repeat while tStart <= tCount
      put 0 into tCarry
      repeat with tI = tStart to tCount
         put tCarry * 256 + tDigits[tI] into tValue
         put cxIntDiv(tValue, 58) into tQuotient
         put tQuotient into tDigits[tI]
         put tValue - tQuotient * 58 into tCarry
      end repeat
      -- tCarry is now the next base58 digit, least significant first.
      put char (tCarry + 1) of kCxBase58Alphabet before tOut
      -- Skip over any leading zeros the division produced, so the next pass is
      -- shorter and the loop terminates.
      repeat while tStart <= tCount and tDigits[tStart] is 0
         add 1 to tStart
      end repeat
   end repeat
   repeat with tI = 1 to tZeros
      put char 1 of kCxBase58Alphabet before tOut
   end repeat
   return tOut
end cxBase58Encode

private function cxBase58Decode pText
   -- The inverse: multiply the byte array by 58 and add each digit. Returns
   -- empty on any character outside the alphabet, so the caller can fail closed.
   local tBytes, tI, tJ, tCount, tIndex, tCarry, tValue, tOut, tZeros, tLen
   put the number of chars of pText into tCount
   if tCount is 0 then
      return ""
   end if
   put 1 into tLen
   put 0 into tBytes[1]
   repeat with tI = 1 to tCount
      put cxCharIndex(char tI of pText, kCxBase58Alphabet) into tIndex
      if tIndex is 0 then
         return empty
      end if
      put tIndex - 1 into tCarry
      repeat with tJ = tLen down to 1
         put tBytes[tJ] * 58 + tCarry into tValue
         put cxIntMod(tValue, 256) into tBytes[tJ]
         put cxIntDiv(tValue, 256) into tCarry
      end repeat
      repeat while tCarry > 0
         add 1 to tLen
         repeat with tJ = tLen down to 2
            put tBytes[tJ - 1] into tBytes[tJ]
         end repeat
         put cxIntMod(tCarry, 256) into tBytes[1]
         put cxIntDiv(tCarry, 256) into tCarry
      end repeat
   end repeat
   -- Leading "1" characters are leading zero bytes, one for one.
   put 0 into tZeros
   repeat with tI = 1 to tCount
      if cxCharIndex(char tI of pText, kCxBase58Alphabet) is not 1 then
         exit repeat
      end if
      add 1 to tZeros
   end repeat
   put "" into tOut
   repeat with tI = 1 to tZeros
      put numToByte(0) after tOut
   end repeat
   -- Drop the single zero byte the accumulator starts with when the value is
   -- itself zero-length, but keep a genuine zero payload.
   repeat with tI = 1 to tLen
      if tI is 1 and tBytes[1] is 0 and tLen > 1 then
         next repeat
      end if
      put numToByte(tBytes[tI]) after tOut
   end repeat
   return tOut
end cxBase58Decode

-- Base58Check: the payload followed by the first 4 bytes of HASH256(payload).
-- This is how a mainnet address, a WIF key and an xprv are all framed.
function cxBase58CheckEncode pPayload
   local tChecksum
   put cxHash256(pPayload) into tChecksum
   return cxBase58Encode(pPayload & byte 1 to 4 of tChecksum)
end cxBase58CheckEncode

-- The inverse, and it VERIFIES. A bad checksum throws; it never returns the
-- payload it happened to decode. Four bytes of checksum means a corrupted
-- address gets through with probability 2^-32, and the whole point of the
-- encoding is that this check is not optional.
function cxBase58CheckDecode pText
   local tRaw, tBody, tChecksum, tCount
   put cxBase58Decode(pText) into tRaw
   if tRaw is empty then
      throw "CoinXT: cxBase58CheckDecode: the input contains a character that is not in the Base58 alphabet."
   end if
   put the number of bytes of tRaw into tCount
   if tCount < 5 then
      throw "CoinXT: cxBase58CheckDecode: the input is too short to carry a 4-byte checksum."
   end if
   put byte 1 to (tCount - 4) of tRaw into tBody
   put byte (tCount - 3) to tCount of tRaw into tChecksum
   -- BYTE COMPARISON, not `is`. Both operands here are 8-character hex strings,
   -- and `is` compares two operands that both LOOK numeric as NUMBERS - so
   -- whether "00001e00" and "00000001" are equal stops being a question about
   -- bytes and becomes a question about how the engine parses exponents. That
   -- has not been observed to collide on this surface, and it is not going to
   -- be left to chance either: this is the one comparison standing between a
   -- corrupt address and a caller's funds, and discipline 3 in the header
   -- already says a comparison whose answer depends on engine coercion does not
   -- belong on a checksum path.
   if cxCompareBytes(cxHexEncode(byte 1 to 4 of cxHash256(tBody)), cxHexEncode(tChecksum)) is not 0 then
      throw "CoinXT: cxBase58CheckDecode: the checksum does not match, so the input is corrupt."
   end if
   return tBody
end cxBase58CheckDecode

-- ==============================================================================
-- Bech32 and Bech32m (BIP-173, BIP-350).
--
-- The two differ ONLY in the constant the checksum is compared against, and the
-- rule that binds them to SegWit is: witness version 0 uses bech32, versions 1
-- to 16 use bech32m. Getting that pairing wrong is the whole reason BIP-350
-- exists, so cxSegwitAddressDecode enforces it explicitly rather than accepting
-- whichever checksum happens to verify.
-- ==============================================================================

private function cxBech32Polymod pValues
   -- BIP-173's checksum over a list of 5-bit values (pValues is a comma
   -- separated list of numbers). The generator constants are the BIP's, gated
   -- against the reference by tools/check-script-vectors.py.
   local tChk, tI, tCount, tTop, tValue, tGen
   put "996825010,642813549,513874426,1027748829,705979059" into tGen
   put 1 into tChk
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put cxIntDiv(tChk, 33554432) into tTop
      put cxBitXor(cxIntMod(tChk, 33554432) * 32, item tI of pValues) into tChk
      repeat with tValue = 1 to 5
         if cxIntMod(cxIntDiv(tTop, cxPow2(tValue - 1)), 2) is 1 then
            put cxBitXor(tChk, item tValue of tGen) into tChk
         end if
      end repeat
   end repeat
   return tChk
end cxBech32Polymod

private function cxBech32HrpExpand pHrp
   -- The HRP contributes its high bits, then a zero, then its low bits.
   local tOut, tI, tCount, tCode
   put the number of chars of pHrp into tCount
   put "" into tOut
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      if tOut is not "" then
         put "," after tOut
      end if
      put cxIntDiv(tCode, 32) after tOut
   end repeat
   put ",0" after tOut
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      put "," & cxIntMod(tCode, 32) after tOut
   end repeat
   return tOut
end cxBech32HrpExpand

private function cxBech32Const pSpec
   -- "bech32" is 1; "bech32m" is the BIP-350 constant. Any other spelling is a
   -- programming error and is refused rather than defaulted.
   if pSpec is "bech32" then
      return 1
   end if
   if pSpec is "bech32m" then
      return kCxBech32mConst
   end if
   throw "CoinXT: the encoding must be either bech32 or bech32m."
end cxBech32Const

-- Encode 5-bit values (a comma separated list) under a human-readable part.
-- Most callers want cxSegwitAddressEncode instead; this is the layer beneath it.
-- ==============================================================================
-- THE ITEM-DELIMITER GUARDS.
--
-- Nine public handlers below read comma-separated lists (bech32's 5-bit values,
-- the 8-to-5 converters, the mnemonic word split, the path split) - ten since
-- ABI 6 added cxBtcAddressP2TRFromInternal, which reaches the bech32m encoder
-- the same way cxBtcAddressP2TR does - and an
-- `item` chunk reads whatever the ENGINE's delimiter currently is - which is
-- GLOBAL MUTABLE STATE in this family (templates/CLAUDE.md rule 5). An app that
-- did `set the itemDelimiter to tab` and did not put it back would get silently
-- wrong answers from this library: measured, a hostile delimiter makes
-- cxBtcAddressP2WPKH fail outright and cxMnemonicValidate answer FALSE to a
-- perfectly good twelve-word backup. Neither is an error the caller can see.
--
-- The remedy is the family's own, and OnionXT has used it at six sites for
-- years: SAVE, set, use, RESTORE. Not `set the itemDelimiter to comma` at the
-- top of the handler - that leaves the caller's delimiter changed, which is the
-- thing the rule exists to prevent.
--
-- It is done with a WRAPPER around each affected handler rather than by editing
-- the handlers themselves. The bodies are vector-verified against published
-- test vectors, and restructuring nine of them to thread a restore through
-- every return and every throw is exactly the kind of edit that introduces the
-- bug it was meant to prevent. The wrapper is eight identical lines; the logic
-- underneath is untouched, and the `Inner` handlers are private so nothing
-- outside this file can reach one without its guard.
--
-- The catch is not optional: this layer throws by design on malformed input, so
-- without it a caller who catches a "bad checksum" error would find its own
-- delimiter silently changed as a side effect.
--
-- BUT THE THROW MUST HAPPEN AFTER `end try`, NOT INSIDE THE CATCH BLOCK, and
-- that is not a style preference. These guards shipped re-throwing from inside
-- the catch, and the first real OXT pass (2026-08-09) showed the engine does
-- not deliver such an error to the caller. What was OBSERVED is exactly that
-- much: the Inner raised, and nothing reached the caller of the wrapper. That
-- the engine DISCARDS a throw issued inside a catch, and that the handler then
-- fell through to `return tResult` with tResult never assigned - returning
-- EMPTY where it owed an error - is the only reading consistent with the run,
-- but it was INFERRED, not watched. So the fix avoids the construct rather
-- than relying on the diagnosis, and the harness now measures the rule
-- directly.
--
-- THE CONTROL THAT NARROWS IT, and it is worth knowing because the next person
-- will wonder whether `catch` is broken generally: it is NOT. `return` from
-- inside a catch WORKS on this engine. onionxt's oxSodiumHasSha3 reaches false
-- only through `return false` in a catch (sxSha3_256 does not exist, docs/08
-- gap #2); that value becomes oxTransportInfo's "offlineAddress"; and the suite
-- harness asserts it IS false - which passed in the same run. Had the return
-- been discarded the handler would have returned empty, and `empty is false` is
-- false, so that line would have gone red. Only `throw` in a catch is affected.
-- This matters directly: cxMnemonicValidateInner reaches `return false` through
-- its own catch, and that path is only now reachable.
--
-- WHAT IT COST. Nine "is refused" assertions came back false, one per guarded
-- handler, while every unguarded handler refused correctly. Worse than the red
-- lines: cxMnemonicToEntropy returned empty instead of throwing, so
-- cxMnemonicValidateInner's catch never fired and cxMnemonicValidate answered
-- TRUE for a mistyped twelve-word backup. A fail-open in the one handler whose
-- entire job is to catch a typo before it becomes a lost wallet.
--
-- `throw` inside `catch` occurred at exactly these nine places in the whole
-- six-member suite and nowhere else, which is why it had never met an engine.
--
-- FOUR OF THE NINE GUARDS ARE LOAD-BEARING; FIVE ARE BELT AND BRACES, and it is
-- worth knowing which before you "clean one up". Only cxBech32EncodeValues,
-- cxSegwitAddressDecode, cxMnemonicToEntropy and cxHdDerivePath read an `item`
-- chunk in their OWN body. The other five reach one only through a handler that
-- is itself guarded, so removing their guard changes nothing observable today -
-- a mutation test confirms exactly that, and it is not a hole in the gate.
-- They stay anyway. This is a money library, every defect the phase-3 review
-- found was a check that was not being made, and a guard that is redundant today
-- stops being redundant the moment somebody adds an `item` to one of these
-- bodies. Uniformity also means a reader does not have to trace a call chain to
-- know whether a public handler is safe to call.
-- ==============================================================================

function cxBech32EncodeValues pHrp, pValues, pSpec
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBech32EncodeValuesInner(pHrp, pValues, pSpec) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBech32EncodeValues

private function cxBech32EncodeValuesInner pHrp, pValues, pSpec
   local tPolymod, tI, tOut, tIndex, tCombined, tCount, tCode
   -- FAIL CLOSED ON THE INPUTS, because both of these used to fail OPEN and a
   -- bech32 string that is subtly wrong is far worse than one that is refused.
   --
   -- The HRP: BIP-173 requires 1 to 83 characters in the range 33..126, and a
   -- bech32 string must be entirely one case. This handler lowercases nothing
   -- and used to concatenate whatever it was given, so an uppercase "BC" gave
   -- "BC1qqq...q42su7w" - a MIXED-case string that this file's own decoder
   -- rejects and no conformant decoder accepts. Refusing an uppercase HRP is
   -- the honest answer: a caller who wants the uppercase form should uppercase
   -- the whole finished string, which is what BIP-173 actually defines.
   put the number of chars of pHrp into tCount
   if tCount < 1 or tCount > 83 then
      throw "CoinXT: cxBech32EncodeValues: the human-readable part must be 1 to 83 characters."
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      if tCode < 33 or tCode > 126 then
         throw "CoinXT: cxBech32EncodeValues: the human-readable part must be printable ASCII."
      end if
      if tCode >= 65 and tCode <= 90 then
         throw "CoinXT: cxBech32EncodeValues: the human-readable part must be lowercase; uppercase the finished string instead."
      end if
   end repeat
   -- The data values: each indexes a 32-character charset, and `char (n) of` a
   -- short string returns EMPTY rather than failing. So a value of 32 used to
   -- emit NOTHING for that position - a string one character short, carrying a
   -- checksum computed over data it does not contain. It would decode to
   -- something, and that something would not be what the caller encoded.
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put item tI of pValues into tIndex
      if tIndex < 0 or tIndex > 31 or tIndex is not trunc(tIndex) then
         throw "CoinXT: cxBech32EncodeValues: every data value must be a whole number between 0 and 31."
      end if
   end repeat
   put cxBech32HrpExpand(pHrp) & "," & pValues & ",0,0,0,0,0,0" into tCombined
   put cxBitXor(cxBech32Polymod(tCombined), cxBech32Const(pSpec)) into tPolymod
   put pHrp & "1" into tOut
   put the number of items of pValues into tI
   repeat with tI = 1 to the number of items of pValues
      put item tI of pValues into tIndex
      put char (tIndex + 1) of kCxBech32Charset after tOut
   end repeat
   repeat with tI = 0 to 5
      put cxIntMod(cxIntDiv(tPolymod, cxPow2(5 * (5 - tI))), 32) into tIndex
      put char (tIndex + 1) of kCxBech32Charset after tOut
   end repeat
   -- The same 90-character cap the decoder enforces. An encoder that can emit a
   -- string its own decoder refuses is an encoder that will eventually be used
   -- to make one.
   if the number of chars of tOut > kCxBech32MaxLen then
      throw "CoinXT: cxBech32EncodeValues: the result would exceed the 90-character bech32 limit."
   end if
   return tOut
end cxBech32EncodeValuesInner

-- Decode a bech32 or bech32m string. Returns an array with keys "hrp", "spec"
-- and "values" (the data part as a comma separated list of 5-bit numbers, with
-- the six checksum characters removed). Throws on anything malformed.
function cxBech32DecodeValues pText
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBech32DecodeValuesInner(pText) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBech32DecodeValues

private function cxBech32DecodeValuesInner pText
   local tResult, tPos, tI, tCount, tCode, tHrp, tData, tIndex, tLower, tSpec
   put the number of chars of pText into tCount
   if tCount > kCxBech32MaxLen then
      throw "CoinXT: cxBech32DecodeValues: the string is longer than the 90 characters bech32 allows."
   end if
   -- Every character must be printable ASCII, and the string must not MIX case:
   -- a mixed-case bech32 string is invalid by specification, because the
   -- checksum is defined over one case only.
   put cxCaseKind(pText) into tLower
   if tLower is "mixed" then
      throw "CoinXT: cxBech32DecodeValues: the string mixes upper and lower case, which bech32 does not allow."
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode < 33 or tCode > 126 then
         throw "CoinXT: cxBech32DecodeValues: the string contains a character outside the printable ASCII range."
      end if
   end repeat
   put cxToLower(pText) into tData
   -- The separator is the LAST "1", because "1" is not in the data charset but
   -- may appear inside the human-readable part.
   put 0 into tPos
   repeat with tI = tCount down to 1
      if byteToNum(char tI of tData) is 49 then
         put tI into tPos
         exit repeat
      end if
   end repeat
   if tPos < 2 then
      throw "CoinXT: cxBech32DecodeValues: the string has no human-readable part before its separator."
   end if
   if tPos + 6 > tCount then
      throw "CoinXT: cxBech32DecodeValues: the string is too short to carry a 6-character checksum."
   end if
   put char 1 to (tPos - 1) of tData into tHrp
   put "" into tResult["values"]
   repeat with tI = (tPos + 1) to tCount
      put cxCharIndex(char tI of tData, kCxBech32Charset) into tIndex
      if tIndex is 0 then
         throw "CoinXT: cxBech32DecodeValues: the data part contains a character that is not in the bech32 charset."
      end if
      if tResult["values"] is not "" then
         put "," after tResult["values"]
      end if
      put (tIndex - 1) after tResult["values"]
   end repeat
   -- Try both constants and report WHICH verified, so the SegWit layer above can
   -- enforce the version-to-encoding pairing instead of guessing.
   put "" into tSpec
   if cxBech32Polymod(cxBech32HrpExpand(tHrp) & "," & tResult["values"]) is 1 then
      put "bech32" into tSpec
   end if
   if cxBech32Polymod(cxBech32HrpExpand(tHrp) & "," & tResult["values"]) is kCxBech32mConst then
      put "bech32m" into tSpec
   end if
   if tSpec is "" then
      throw "CoinXT: cxBech32DecodeValues: the checksum does not match, so the string is corrupt."
   end if
   put tHrp into tResult["hrp"]
   put tSpec into tResult["spec"]
   -- Drop the six checksum values; the caller wants the payload.
   put cxDropLastItems(tResult["values"], 6) into tResult["values"]
   return tResult
end cxBech32DecodeValuesInner

private function cxDropLastItems pList, pHowMany
   local tCount, tI, tOut
   put the number of items of pList into tCount
   put "" into tOut
   repeat with tI = 1 to (tCount - pHowMany)
      if tOut is not "" then
         put "," after tOut
      end if
      put item tI of pList after tOut
   end repeat
   return tOut
end cxDropLastItems

private function cxCaseKind pText
   -- "upper", "lower", "mixed" or "none", decided by BYTE VALUE so it does not
   -- depend on the caller's caseSensitive setting.
   local tI, tCount, tCode, tHasUpper, tHasLower
   put false into tHasUpper
   put false into tHasLower
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         put true into tHasUpper
      end if
      if tCode >= 97 and tCode <= 122 then
         put true into tHasLower
      end if
   end repeat
   if tHasUpper and tHasLower then
      return "mixed"
   end if
   if tHasUpper then
      return "upper"
   end if
   if tHasLower then
      return "lower"
   end if
   return "none"
end cxCaseKind

private function cxToLower pText
   -- ASCII lowercase by byte value (see cxCaseKind).
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
end cxToLower

-- ==============================================================================
-- Bit regrouping, 8 <-> 5. SegWit programs are bytes; bech32 carries 5-bit
-- groups. This is the only place in the file with a bit buffer, and it is masked
-- every step (discipline 2).
-- ==============================================================================

private function cxConvert8To5 pData
   local tOut, tI, tCount, tValue, tBits, tIndex
   put "" into tOut
   put 0 into tValue
   put 0 into tBits
   put the number of bytes of pData into tCount
   repeat with tI = 1 to tCount
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put cxIntMod(cxIntDiv(tValue, cxPow2(tBits)), 32) into tIndex
         if tOut is not "" then
            put "," after tOut
         end if
         put tIndex after tOut
      end repeat
      put cxIntMod(tValue, cxPow2(tBits)) into tValue
   end repeat
   if tBits > 0 then
      -- Pad the final group with zero bits, as SegWit encoding requires.
      put cxIntMod(tValue * cxPow2(5 - tBits), 32) into tIndex
      if tOut is not "" then
         put "," after tOut
      end if
      put tIndex after tOut
   end if
   return tOut
end cxConvert8To5

private function cxConvert5To8 pValues
   -- The inverse, and it is STRICTER than the forward direction on purpose: the
   -- padding must be fewer than 5 bits and must be zero. A decoder that accepts
   -- non-zero padding accepts several distinct strings for the same program,
   -- and BIP-173 rejects that explicitly.
   local tOut, tI, tCount, tValue, tBits, tByte, tResult
   put "" into tOut
   put 0 into tValue
   put 0 into tBits
   put the number of items of pValues into tCount
   repeat with tI = 1 to tCount
      put tValue * 32 + item tI of pValues into tValue
      add 5 to tBits
      repeat while tBits >= 8
         subtract 8 from tBits
         put cxIntMod(cxIntDiv(tValue, cxPow2(tBits)), 256) into tByte
         put numToByte(tByte) after tOut
      end repeat
      put cxIntMod(tValue, cxPow2(tBits)) into tValue
   end repeat
   -- THE STATUS IS OUT OF BAND, in a separate key, and it has to be. This
   -- returned the strings "ERROR: ..." in place of the bytes once, and the
   -- caller tested `char 1 to 5 of tProgram is "ERROR"` - which means a witness
   -- program whose first five bytes happen to be 45 52 52 4F 52 was read as a
   -- failure. That is a real address (bech32m v1 accepts any 2-to-40-byte
   -- program), and this file's own encoder produces it, so the library rejected
   -- an address it had just made. An in-band sentinel over arbitrary bytes is
   -- always wrong; there is no byte string that cannot occur.
   put tOut into tResult["bytes"]
   if tBits >= 5 then
      put false into tResult["ok"]
      put "there are too many padding bits" into tResult["why"]
   else if tValue is not 0 then
      put false into tResult["ok"]
      put "the padding bits are not zero" into tResult["why"]
   else
      put true into tResult["ok"]
      put "" into tResult["why"]
   end if
   return tResult
end cxConvert5To8

-- ==============================================================================
-- SegWit addresses (BIP-173 / BIP-350).
-- ==============================================================================

-- Build a SegWit address from a witness version (0..16) and its program bytes.
-- The encoding follows from the version, which is the BIP-350 rule.
function cxSegwitAddressEncode pHrp, pVersion, pProgram
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxSegwitAddressEncodeInner(pHrp, pVersion, pProgram) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxSegwitAddressEncode

private function cxSegwitAddressEncodeInner pHrp, pVersion, pProgram
   local tValues, tSpec, tLength
   if pVersion < 0 or pVersion > 16 then
      throw "CoinXT: cxSegwitAddressEncode: the witness version must be between 0 and 16."
   end if
   put the number of bytes of pProgram into tLength
   if tLength < 2 or tLength > 40 then
      throw "CoinXT: cxSegwitAddressEncode: a witness program must be between 2 and 40 bytes."
   end if
   if pVersion is 0 and tLength is not 20 and tLength is not 32 then
      throw "CoinXT: cxSegwitAddressEncode: a version 0 witness program must be exactly 20 or 32 bytes."
   end if
   if pVersion is 0 then
      put "bech32" into tSpec
   else
      put "bech32m" into tSpec
   end if
   put pVersion & "," & cxConvert8To5(pProgram) into tValues
   return cxBech32EncodeValues(pHrp, tValues, tSpec)
end cxSegwitAddressEncodeInner

-- Decode a SegWit address under an expected human-readable part. Returns an
-- array with keys "version" and "program". Throws on every invalidity BIP-173
-- and BIP-350 define, including the one that matters most: a version 0 address
-- carrying a bech32m checksum, or a version 1+ address carrying a bech32 one.
function cxSegwitAddressDecode pHrp, pAddress
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxSegwitAddressDecodeInner(pHrp, pAddress) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxSegwitAddressDecode

private function cxSegwitAddressDecodeInner pHrp, pAddress
   local tDecoded, tResult, tVersion, tProgram, tValues, tLength, tConverted
   put cxBech32DecodeValues(pAddress) into tDecoded
   if tDecoded["hrp"] is not cxToLower(pHrp) then
      throw "CoinXT: cxSegwitAddressDecode: the address is for a different network than the one requested."
   end if
   put tDecoded["values"] into tValues
   if (the number of items of tValues) < 1 then
      throw "CoinXT: cxSegwitAddressDecode: the address carries no witness version."
   end if
   put item 1 of tValues into tVersion
   if tVersion > 16 then
      throw "CoinXT: cxSegwitAddressDecode: the witness version is greater than 16."
   end if
   if tVersion is 0 and tDecoded["spec"] is not "bech32" then
      throw "CoinXT: cxSegwitAddressDecode: a version 0 address must use bech32, not bech32m."
   end if
   if tVersion > 0 and tDecoded["spec"] is not "bech32m" then
      throw "CoinXT: cxSegwitAddressDecode: a version 1 or later address must use bech32m, not bech32."
   end if
   put cxConvert5To8(cxDropFirstItem(tValues)) into tConverted
   if tConverted["ok"] is false then
      throw "CoinXT: cxSegwitAddressDecode: the address is not canonical because" && tConverted["why"] & "."
   end if
   put tConverted["bytes"] into tProgram
   put the number of bytes of tProgram into tLength
   if tLength < 2 or tLength > 40 then
      throw "CoinXT: cxSegwitAddressDecode: the witness program must be between 2 and 40 bytes."
   end if
   if tVersion is 0 and tLength is not 20 and tLength is not 32 then
      throw "CoinXT: cxSegwitAddressDecode: a version 0 witness program must be exactly 20 or 32 bytes."
   end if
   put tVersion into tResult["version"]
   put tProgram into tResult["program"]
   return tResult
end cxSegwitAddressDecodeInner

private function cxDropFirstItem pList
   local tCount, tI, tOut
   put the number of items of pList into tCount
   put "" into tOut
   repeat with tI = 2 to tCount
      if tOut is not "" then
         put "," after tOut
      end if
      put item tI of pList after tOut
   end repeat
   return tOut
end cxDropFirstItem

-- ==============================================================================
-- The address builders. Each takes a PUBLIC key (or, for Taproot, an output
-- key) and produces the string a user pastes into a wallet.
-- ==============================================================================

private function cxCheckPubkey pPubkey, pName, pCompressedOnly
   -- The length AND the prefix, together, exactly as the shim's cnx_pubkey_ok
   -- does - and for a related reason. There the danger is an overread; here it
   -- is worse in a quieter way: hash160 happily hashes ANY bytes, so without
   -- this an empty string, a 20-byte hash or a truncated key each produce a
   -- perfectly well-formed, checksummed mainnet address whose funds nobody can
   -- ever spend. Nothing downstream can catch that - the address is valid, it
   -- is simply not yours - so it has to be refused here.
   local tCount, tFirst
   put the number of bytes of pPubkey into tCount
   if tCount is not 33 and (pCompressedOnly is true or tCount is not 65) then
      if pCompressedOnly is true then
         throw "CoinXT:" && pName & ": this address type requires a 33-byte COMPRESSED public key."
      end if
      throw "CoinXT:" && pName & ": a public key must be 33 bytes (compressed) or 65 bytes (uncompressed)."
   end if
   put byteToNum(byte 1 of pPubkey) into tFirst
   if tCount is 33 and tFirst is not 2 and tFirst is not 3 then
      throw "CoinXT:" && pName & ": a 33-byte public key must begin with 0x02 or 0x03."
   end if
   if tCount is 65 and tFirst is not 4 then
      throw "CoinXT:" && pName & ": a 65-byte public key must begin with 0x04."
   end if
   return true
end cxCheckPubkey

-- Pay to public key hash: the original "1..." mainnet address.
function cxBtcAddressP2PKH pPubkey
   get cxCheckPubkey(pPubkey, "cxBtcAddressP2PKH", false)
   return cxBase58CheckEncode(numToByte(kCxVersionP2PKH) & cxHash160(pPubkey))
end cxBtcAddressP2PKH

-- Pay to witness public key hash: a native SegWit v0 "bc1q..." address. The key
-- MUST be compressed - an uncompressed key here produces an address whose funds
-- are unspendable by every modern wallet, so it is refused rather than encoded.
function cxBtcAddressP2WPKH pPubkey
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcAddressP2WPKHInner(pPubkey) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcAddressP2WPKH

private function cxBtcAddressP2WPKHInner pPubkey
   get cxCheckPubkey(pPubkey, "cxBtcAddressP2WPKH", true)
   return cxSegwitAddressEncode(kCxHrpMainnet, 0, cxHash160(pPubkey))
end cxBtcAddressP2WPKHInner

-- Pay to Taproot: a SegWit v1 "bc1p..." address over a 32-byte x-only OUTPUT
-- key.
--
-- READ THIS BEFORE USING IT. The argument is the TWEAKED output key, not an
-- internal key. BIP-341 defines the output key as
-- Q = P + int(hash_TapTweak(bytes(P) || merkle_root)) * G, and this handler
-- does the ENCODING HALF ONLY: it takes the Q you already have and spells it
-- as an address. Handing it a raw internal key P produces a valid-looking
-- address nobody can spend from.
--
-- WHAT CHANGED IN ABI 6, AND WHAT DID NOT. CoinXT can now compute that tweak
-- (cxTaprootTweak, below, over the BIP-341 surface added with libsecp256k1),
-- so the limitation this comment used to record - "computing that needs the
-- BIP-340 surface CoinXT has deferred" - is gone. THIS HANDLER'S MEANING IS
-- NOT CHANGED BY THAT, deliberately and permanently: it still encodes the key
-- it is given and still does not tweak. Making it tweak would silently turn
-- every existing correct call - an app that pre-tweaked its key elsewhere -
-- into a DOUBLE tweak, i.e. a different, valid-looking, permanently
-- unspendable address, with no way for the handler to tell the two cases apart
-- (both arguments are 32 bytes) and no way for the caller to notice. That is
-- exactly the wrong-but-plausible answer this library refuses to produce.
--
-- So: if you hold an internal key, call cxBtcAddressP2TRFromInternal. If you
-- hold an output key, call this. If you are not sure which you hold, you hold
-- an internal key.
function cxBtcAddressP2TR pOutputKey
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcAddressP2TRInner(pOutputKey) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcAddressP2TR

private function cxBtcAddressP2TRInner pOutputKey
   if the number of bytes of pOutputKey is not 32 then
      throw "CoinXT: cxBtcAddressP2TR: a Taproot address requires a 32-byte x-only output key."
   end if
   return cxSegwitAddressEncode(kCxHrpMainnet, 1, pOutputKey)
end cxBtcAddressP2TRInner

-- ==============================================================================
-- BIP-341 Taproot: the tweak, and the address builder that applies it.
--
-- STATUS: verified statically and executed headlessly against BIP-341's own
-- published wallet test vectors (tools/check-script-vectors.py drives the real
-- script through the real shim); needs an OXT pass. New in ABI 6.
-- ==============================================================================

-- Q = P + int(hash_TapTweak(bytes(P) || merkle_root)) * G, BIP-341's output
-- key, as a named array:
--
--   outputKey   the 32-byte x-only output key. This is the witness program of
--               the P2TR scriptPubKey and the payload of the bc1p... address.
--   parity      0 if the output point has an even Y coordinate, 1 if odd. A
--               key-path spend does not need it; a script-path spend puts it
--               in the low bit of its control block's first byte.
--
-- pMerkleRoot is EMPTY for a key-path-only output - the single-signature case,
-- and the one nearly every wallet wants - or the 32-byte root of a script
-- tree.
--
-- EMPTY IS NOT 32 ZERO BYTES, AND THE DIFFERENCE IS CONSENSUS. BIP-341 hashes
-- `bytes(P) || merkle_root` where merkle_root is the EMPTY BYTE STRING when
-- there is no script tree, so the key-path-only tweak hashes 32 bytes and a
-- rooted one hashes 64. Passing 32 zeros instead of empty computes a valid
-- tweak for a script tree whose root happens to be zero - a different output
-- key, a different address, and coins that only a script nobody has can move.
-- The two cases are carried by LENGTH all the way down to the C shim for
-- exactly this reason; there is no sentinel value to get wrong.
--
-- This handler needs no itemDelimiter guard: it is byte slicing over a fixed
-- 33-byte record and contains no `item` expression. cxBtcAddressP2TRFromInternal
-- below does need one, because the bech32m encoder it calls moves 5-bit groups
-- as a comma list.
function cxTaprootTweak pInternalKey, pMerkleRoot
   local tRecord, tResult, tKeyLen, tRootLen
   put the number of bytes of pInternalKey into tKeyLen
   if tKeyLen is not 32 then
      throw "CoinXT: cxTaprootTweak: the internal key must be a 32-byte x-only public key."
   end if
   put the number of bytes of pMerkleRoot into tRootLen
   if tRootLen is not 0 and tRootLen is not 32 then
      throw "CoinXT: cxTaprootTweak: the merkle root must be empty (a key-path-only output) or 32 bytes (a script-tree root)."
   end if
   -- The .lcb hands back one record so the parity travels with the key it
   -- belongs to; the slice widths come from the shim, never from a constant
   -- written down here (the same rule as every other length in this library).
   put cxTaprootTweakPubkey(pInternalKey, pMerkleRoot) into tRecord
   put cxXOnlyPubkeyLen() into tKeyLen
   put byte 1 to tKeyLen of tRecord into tResult["outputKey"]
   put byteToNum(byte (tKeyLen + 1) of tRecord) into tResult["parity"]
   return tResult
end cxTaprootTweak

-- The full BIP-341 address path: internal x-only key (plus an optional script
-- tree root) to a mainnet "bc1p..." address, tweak included.
--
-- This is the handler almost every caller wants, and it is a SEPARATE handler
-- from cxBtcAddressP2TR rather than a second argument to it. An absent
-- parameter in xTalk is indistinguishable from an empty one, so an optional
-- pMerkleRoot could not tell "encode this output key" from "tweak this
-- internal key with no script tree" - and those two readings of the same 32
-- bytes produce different addresses, one of which is unspendable. A separate
-- name is the only way to make the caller say which they meant.
function cxBtcAddressP2TRFromInternal pInternalKey, pMerkleRoot
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcAddressP2TRFromInternalInner(pInternalKey, pMerkleRoot) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcAddressP2TRFromInternal

private function cxBtcAddressP2TRFromInternalInner pInternalKey, pMerkleRoot
   local tTweak
   put cxTaprootTweak(pInternalKey, pMerkleRoot) into tTweak
   return cxSegwitAddressEncode(kCxHrpMainnet, 1, tTweak["outputKey"])
end cxBtcAddressP2TRFromInternalInner

-- The lowercase Ethereum address for a public key: the last 20 bytes of
-- Keccak-256 over the 64 bytes of the UNCOMPRESSED key, without its 0x04 prefix.
-- A compressed key is expanded first, so either form works.
function cxEthAddress pPubkey
   local tKey, tHash, tCount
   put the number of bytes of pPubkey into tCount
   if tCount is 33 then
      put cxPubkeyDecompress(pPubkey) into tKey
   else
      put pPubkey into tKey
   end if
   if the number of bytes of tKey is not 65 then
      throw "CoinXT: cxEthAddress: a public key must be 33 bytes (compressed) or 65 bytes (uncompressed)."
   end if
   put cxKeccak256(byte 2 to 65 of tKey) into tHash
   return "0x" & cxHexEncode(byte 13 to 32 of tHash)
end cxEthAddress

-- The EIP-55 mixed-case form, which is Ethereum's checksum: a hex digit is
-- upper-cased when the matching nibble of Keccak-256 over the LOWERCASE address
-- text is 8 or more. Accepts an address with or without the 0x prefix and with
-- any casing, because its whole job is to compute the correct casing.
function cxEthAddressChecksum pAddress
   local tPlain, tHash, tOut, tI, tCode, tNibble, tHex
   put pAddress into tPlain
   if char 1 to 2 of tPlain is "0x" then
      delete char 1 to 2 of tPlain
   end if
   if the number of chars of tPlain is not 40 then
      throw "CoinXT: cxEthAddressChecksum: an Ethereum address must be 40 hex characters."
   end if
   put cxToLower(tPlain) into tPlain
   repeat with tI = 1 to 40
      if cxHexValue(char tI of tPlain) < 0 then
         throw "CoinXT: cxEthAddressChecksum: the address contains a character that is not a hex digit."
      end if
   end repeat
   -- The hash is over the ASCII of the lowercase address, NOT over its bytes.
   put cxHexEncode(cxKeccak256(textEncode(tPlain, "UTF-8"))) into tHex
   put "0x" into tOut
   repeat with tI = 1 to 40
      put cxHexValue(char tI of tHex) into tNibble
      put byteToNum(char tI of tPlain) into tCode
      if tNibble >= 8 and tCode >= 97 and tCode <= 102 then
         put numToChar(tCode - 32) after tOut
      else
         put numToChar(tCode) after tOut
      end if
   end repeat
   return tOut
end cxEthAddressChecksum

-- Verify an address that already carries EIP-55 casing. An all-lowercase or
-- all-uppercase address has NO checksum by definition, so this reports that
-- rather than calling it valid: silently accepting an unchecked address is how
-- the checksum stops protecting anyone.
function cxEthAddressIsChecksummed pAddress
   local tPlain
   put pAddress into tPlain
   if char 1 to 2 of tPlain is "0x" then
      delete char 1 to 2 of tPlain
   end if
   if cxCaseKind(tPlain) is not "mixed" then
      return false
   end if
   -- COMPARE AGAINST THE CALLER'S ORIGINAL CASING, BY BYTE VALUE. Both halves
   -- of that sentence are load-bearing, and this handler shipped once getting
   -- both wrong - it read
   --    cxEthAddressChecksum(pAddress) is cxEthAddressChecksum(cxToLower(tPlain))
   -- which is a TAUTOLOGY: cxEthAddressChecksum lowercases its argument before
   -- it hashes or emits anything, so its result is a function of the lowercase
   -- form alone and both sides are the same string for every input. It answered
   -- "true" to every mixed-case address, including a corrupted one, which is
   -- precisely the failure EIP-55 exists to prevent.
   -- The second half matters too: `is` honours `the caseSensitive` (default
   -- FALSE), and this comparison is ENTIRELY about case, so `is` could not
   -- decide it even against the right operand. cxCompareBytes is exact whatever
   -- the caller has set - the same reasoning as discipline 3 in the header.
   return cxCompareBytes(cxEthAddressChecksum(tPlain), "0x" & tPlain) is 0
end cxEthAddressIsChecksummed

-- ==============================================================================
-- RLP (Ethereum's Recursive Length Prefix).
--
-- Ethereum encodes a transaction as an RLP list, so this is what stands between
-- cxSignRecoverable and a broadcastable transaction. The API is deliberately
-- built from PIECES rather than taking a nested structure: xTalk has no natural
-- nested-list literal, and a caller assembling a transaction already has its
-- fields one at a time.
-- ==============================================================================

-- Encode one byte string as an RLP item.
function cxRlpEncodeBytes pData
   local tCount
   put the number of bytes of pData into tCount
   if tCount is 1 and byteToNum(byte 1 of pData) < 128 then
      -- A single byte below 0x80 is its own encoding: it carries no prefix.
      return pData
   end if
   return cxRlpLengthPrefix(tCount, 128) & pData
end cxRlpEncodeBytes

-- Wrap already-encoded items as an RLP list. Build the payload by concatenating
-- cxRlpEncodeBytes / cxRlpEncodeList results, then pass it here.
function cxRlpEncodeList pEncodedItems
   return cxRlpLengthPrefix(the number of bytes of pEncodedItems, 192) & pEncodedItems
end cxRlpEncodeList

private function cxRlpLengthPrefix pLength, pOffset
   -- Short form below 56 bytes; otherwise a big-endian length whose OWN length
   -- goes in the prefix.
   local tBig, tOut
   if pLength < 56 then
      return numToByte(pOffset + pLength)
   end if
   put cxUIntToBytes(pLength) into tBig
   put numToByte(pOffset + 55 + the number of bytes of tBig) into tOut
   return tOut & tBig
end cxRlpLengthPrefix

private function cxUIntToBytes pValue
   -- Big-endian, no leading zero byte. Used for RLP length prefixes only, which
   -- stay far inside exact-integer range.
   local tOut, tRest
   put "" into tOut
   put pValue into tRest
   repeat while tRest > 0
      put numToByte(cxIntMod(tRest, 256)) before tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   if tOut is "" then
      put numToByte(0) into tOut
   end if
   return tOut
end cxUIntToBytes

-- Decode ONE RLP item from the front of pData. Returns an array with keys
-- "kind" ("bytes" or "list"), "payload" (the item's contents; for a list this is
-- the concatenated encodings of its elements, which you decode by looping) and
-- "rest" (whatever followed the item).
--
-- It rejects the non-canonical forms rather than accepting them, because RLP's
-- guarantee is that one value has exactly one encoding, and a decoder that
-- accepts two spellings of the same list breaks every hash computed over it.
function cxRlpDecode pData
   local tResult, tPrefix, tCount, tLength, tLengthLength, tI, tHeader
   put the number of bytes of pData into tCount
   if tCount is 0 then
      throw "CoinXT: cxRlpDecode: there is nothing to decode."
   end if
   put byteToNum(byte 1 of pData) into tPrefix
   if tPrefix < 128 then
      put "bytes" into tResult["kind"]
      put byte 1 of pData into tResult["payload"]
      put byte 2 to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 184 then
      put tPrefix - 128 into tLength
      if tCount < 1 + tLength then
         throw "CoinXT: cxRlpDecode: the item claims more bytes than the input holds."
      end if
      if tLength is 1 and byteToNum(byte 2 of pData) < 128 then
         throw "CoinXT: cxRlpDecode: a single byte below 0x80 must be encoded as itself, not with a length prefix."
      end if
      put "bytes" into tResult["kind"]
      put cxSlice(pData, 2, 1 + tLength) into tResult["payload"]
      put byte (2 + tLength) to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 192 then
      put tPrefix - 183 into tLengthLength
      put cxRlpLongLength(pData, tLengthLength, tCount) into tLength
      put 1 + tLengthLength into tHeader
      if tCount < tHeader + tLength then
         throw "CoinXT: cxRlpDecode: the item claims more bytes than the input holds."
      end if
      put "bytes" into tResult["kind"]
      put cxSlice(pData, tHeader + 1, tHeader + tLength) into tResult["payload"]
      put byte (tHeader + tLength + 1) to tCount of pData into tResult["rest"]
      return tResult
   end if
   if tPrefix < 248 then
      put tPrefix - 192 into tLength
      if tCount < 1 + tLength then
         throw "CoinXT: cxRlpDecode: the list claims more bytes than the input holds."
      end if
      put "list" into tResult["kind"]
      put cxSlice(pData, 2, 1 + tLength) into tResult["payload"]
      put byte (2 + tLength) to tCount of pData into tResult["rest"]
      return tResult
   end if
   put tPrefix - 247 into tLengthLength
   put cxRlpLongLength(pData, tLengthLength, tCount) into tLength
   put 1 + tLengthLength into tHeader
   if tCount < tHeader + tLength then
      throw "CoinXT: cxRlpDecode: the list claims more bytes than the input holds."
   end if
   put "list" into tResult["kind"]
   put cxSlice(pData, tHeader + 1, tHeader + tLength) into tResult["payload"]
   put byte (tHeader + tLength + 1) to tCount of pData into tResult["rest"]
   return tResult
end cxRlpDecode

private function cxRlpLongLength pData, pLengthLength, pCount
   -- The big-endian length that follows a long-form prefix, with both
   -- canonicality rules enforced: no leading zero byte, and the value must
   -- actually have needed the long form.
   local tI, tLength
   if pCount < 1 + pLengthLength then
      throw "CoinXT: cxRlpDecode: the length prefix is truncated."
   end if
   if byteToNum(byte 2 of pData) is 0 then
      throw "CoinXT: cxRlpDecode: the length has a leading zero byte, which is not canonical."
   end if
   put 0 into tLength
   repeat with tI = 1 to pLengthLength
      put tLength * 256 + byteToNum(byte (1 + tI) of pData) into tLength
   end repeat
   if tLength < 56 then
      throw "CoinXT: cxRlpDecode: a length below 56 must use the short form, so this is not canonical."
   end if
   return tLength
end cxRlpLongLength

private function cxSlice pData, pFrom, pTo
   -- byte x to y of, with the empty case made explicit: an empty RLP string has
   -- pFrom greater than pTo, and relying on the engine's behaviour there is the
   -- kind of assumption this family writes down rather than trusts.
   if pFrom > pTo then
      return ""
   end if
   return byte pFrom to pTo of pData
end cxSlice

-- ==============================================================================
-- PHASE 4 - HD WALLETS AND MNEMONICS (BIP-39, BIP-32, BIP-44).
--
-- Same split as everything above: the two operations that are curve arithmetic
-- (ki = IL + kpar mod n, and Ki = point(IL) + Kpar) are cxSeckeyTweakAdd and
-- cxPubkeyTweakAdd in the native module. Everything here is bit packing, a
-- checksum, a path parse and a serialization - no modular arithmetic on a
-- 256-bit number appears in this file, exactly as the header demands.
--
-- WHY THIS IS THE MOST INTEROPERABILITY-CRITICAL CODE IN COINXT. Every other
-- surface fails loudly when it is wrong: a bad signature does not verify, a bad
-- address fails its checksum. THIS one fails silently. A mnemonic that packs
-- its 11-bit groups in the wrong order still produces 12 valid-looking English
-- words and a seed that is perfectly self-consistent - and a wallet restored
-- from it in any other software finds an empty account and no way back. That is
-- why the official BIP-39 and BIP-32 vectors are re-derived end to end by
-- tools/check-script-vectors.py, against the REAL native library, on every push.
-- ==============================================================================

-- BIP-39 fixes the PBKDF2 work factor at 2048 rounds of HMAC-SHA512. It is not
-- a tuning knob: changing it changes the seed, and the wallet stops being a
-- BIP-39 wallet.
constant kCxBip39Rounds = 2048

-- The salt is the ASCII string "mnemonic" with the passphrase appended. The
-- passphrase is what BIP-39 calls the optional 25th word.
constant kCxBip39SaltPrefix = "mnemonic"

-- 2048 words, so every word carries exactly 11 bits.
constant kCxBip39WordCount = 2048
constant kCxBip39BitsPerWord = 11

-- BIP-32's HMAC key for the master node. ASCII, and normative - "Bitcoin seed"
-- is used verbatim by every BIP-32 wallet regardless of coin.
constant kCxBip32MasterKey = "Bitcoin seed"

-- Where the hardened half of the child-index space begins (2^31). An index at
-- or above this derives from the PRIVATE key, which is what makes a hardened
-- child underivable from an xpub.
constant kCxHardenedBase = 2147483648

-- The mainnet BIP-32 serialization version bytes, as integers: xprv is
-- 0x0488ADE4 and xpub is 0x0488B21E. Those two numbers are what make the
-- Base58Check text begin "xprv" and "xpub".
constant kCxVersionXprv = 76066276
constant kCxVersionXpub = 76067358

-- ==============================================================================
-- Bit plumbing. BIP-39 is a base conversion between 8-bit and 11-bit groups, and
-- these two do it a bit at a time rather than with a bignum - see discipline 2
-- in the header. Nothing here ever holds more than 11 bits, so no accumulator
-- comes within thirty orders of magnitude of 2^53.
-- ==============================================================================

private function cxBitAt pData, pBitIndex
   -- Bit pBitIndex (0-based, most significant bit of byte 1 first) of pData.
   local tByteIndex, tBitInByte, tByte
   put cxIntDiv(pBitIndex, 8) + 1 into tByteIndex
   put cxIntMod(pBitIndex, 8) into tBitInByte
   put byteToNum(byte tByteIndex of pData) into tByte
   return cxIntMod(cxIntDiv(tByte, cxPow2(7 - tBitInByte)), 2)
end cxBitAt

private function cxBitsToBytes pBits
   -- Pack a comma-separated list of 0/1 into bytes, most significant bit first,
   -- zero-padding the final partial byte. The padding is not a fudge: BIP-39's
   -- checksum is the FIRST few bits of a digest byte, so the zeros below a
   -- 4-bit checksum are exactly the zeros the comparison expects.
   local tOut, tAcc, tCount, tI, tBitCount
   put "" into tOut
   put 0 into tAcc
   put 0 into tBitCount
   put the number of items of pBits into tCount
   repeat with tI = 1 to tCount
      put tAcc * 2 + (item tI of pBits) into tAcc
      add 1 to tBitCount
      if tBitCount is 8 then
         put numToByte(tAcc) after tOut
         put 0 into tAcc
         put 0 into tBitCount
      end if
   end repeat
   if tBitCount > 0 then
      repeat with tI = tBitCount to 7
         put tAcc * 2 into tAcc
      end repeat
      put numToByte(tAcc) after tOut
   end if
   return tOut
end cxBitsToBytes

-- ==============================================================================
-- The BIP-39 wordlist. It arrives from the native module as 2048 fixed-width
-- 8-byte slots (see cxBip39Wordlist in src/coinxt.lcb), which is what makes
-- index -> word one chunk expression and word -> index a binary search over a
-- sorted table. It is fetched once per public handler and passed down, rather
-- than cached in a script-local: 16 KB is cheap next to 2048 rounds of PBKDF2,
-- and a cache would be one more piece of state to get wrong.
-- ==============================================================================

private function cxWordSlotLen pList
   -- The slot width, derived from the blob rather than written down again.
   return cxIntDiv(the number of bytes of pList, kCxBip39WordCount)
end cxWordSlotLen

private function cxWordAt pList, pIndex
   -- Word at pIndex (0-based), trailing pad removed.
   local tWidth, tStart, tSlot, tEnd
   put cxWordSlotLen(pList) into tWidth
   put pIndex * tWidth + 1 into tStart
   put byte tStart to (tStart + tWidth - 1) of pList into tSlot
   put tWidth into tEnd
   repeat while tEnd > 0
      if byteToNum(char tEnd of tSlot) is not 32 then
         exit repeat
      end if
      subtract 1 from tEnd
   end repeat
   return char 1 to tEnd of tSlot
end cxWordAt


private function cxWordIndex pList, pWord
   -- The 0-based index of pWord, or -1 if it is not a BIP-39 word. Binary
   -- search: the list is sorted by byte value (tools/coin-kat.py checks that,
   -- so this is a verified precondition and not an assumption).
   local tLow, tHigh, tMid, tCmp
   put 0 into tLow
   put kCxBip39WordCount - 1 into tHigh
   repeat while tLow <= tHigh
      put cxIntDiv(tLow + tHigh, 2) into tMid
      put cxCompareBytes(pWord, cxWordAt(pList, tMid)) into tCmp
      if tCmp is 0 then
         return tMid
      end if
      if tCmp < 0 then
         put tMid - 1 into tHigh
      else
         put tMid + 1 into tLow
      end if
   end repeat
   return -1
end cxWordIndex

-- ==============================================================================
-- BIP-39: entropy <-> mnemonic <-> seed.
-- ==============================================================================

-- Collapse a mnemonic to its canonical form: no leading or trailing whitespace,
-- exactly one space between words.
--
-- THIS IS NOT COSMETIC. BIP-39 derives the seed from the mnemonic STRING, so a
-- stray double space or a trailing newline from a paste would produce a
-- different seed from every other wallet holding the same words - silently, and
-- with no way to tell from the words themselves. Normalizing is what every
-- interoperable implementation does, so cxMnemonicValidate, cxMnemonicToEntropy
-- and cxMnemonicToSeed all run this first.
--
-- What it does NOT do is Unicode NFKD. For the English wordlist that is a
-- no-op, because every word is ASCII. A NON-ASCII PASSPHRASE IS THE CALLER'S
-- PROBLEM: normalize it to NFKD before calling cxMnemonicToSeed, or the seed
-- will not match a wallet that did.
function cxMnemonicNormalize pText
   local tOut, tI, tCount, tChar, tCode, tPending
   put "" into tOut
   put false into tPending
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put char tI of pText into tChar
      put byteToNum(tChar) into tCode
      if tCode is 32 or tCode is 9 or tCode is 10 or tCode is 13 then
         if tOut is not "" then
            put true into tPending
         end if
      else
         if tPending is true then
            put " " after tOut
            put false into tPending
         end if
         put tChar after tOut
      end if
   end repeat
   return tOut
end cxMnemonicNormalize

private function cxSplitWords pMnemonic
   -- The words of an already-normalized mnemonic, comma separated. Safe as a
   -- comma list because every BIP-39 English word is lowercase a-z; a word
   -- containing a comma could not be in the list and is rejected by
   -- cxWordIndex before it can be misread.
   local tOut, tI, tCount, tChar
   put "" into tOut
   put the number of chars of pMnemonic into tCount
   repeat with tI = 1 to tCount
      put char tI of pMnemonic into tChar
      if byteToNum(tChar) is 32 then
         put "," after tOut
      else
         put tChar after tOut
      end if
   end repeat
   return tOut
end cxSplitWords

-- The mnemonic for pEntropy, which must be 16, 20, 24, 28 or 32 bytes (128 to
-- 256 bits in 32-bit steps) and gives 12, 15, 18, 21 or 24 words.
--
-- COINXT DOES NOT GENERATE THE ENTROPY. It is the caller's, from a source the
-- caller trusts (SodiumXT's sxRandomBytes is the intended one), for the same
-- reason cxNewSeckey takes bytes rather than making them: a wallet's entire
-- security is this input, and a library that quietly supplied it would be
-- asking to be trusted about the one thing nobody should take on faith.
function cxMnemonicFromEntropy pEntropy
   local tLen, tChecksumBits, tTotalBits, tWordCount, tSource, tList
   local tI, tB, tValue, tOut, tBitIndex
   put the number of bytes of pEntropy into tLen
   if tLen is not 16 and tLen is not 20 and tLen is not 24 and tLen is not 28 and tLen is not 32 then
      throw "CoinXT: cxMnemonicFromEntropy: entropy must be 16, 20, 24, 28 or 32 bytes."
   end if
   -- One checksum bit per 32 bits of entropy, taken from the FRONT of the
   -- SHA-256 of the entropy. That is at most 8 bits, so appending the first
   -- digest byte supplies every bit the packing below will read.
   put cxIntDiv(tLen, 4) into tChecksumBits
   put tLen * 8 + tChecksumBits into tTotalBits
   put cxIntDiv(tTotalBits, kCxBip39BitsPerWord) into tWordCount
   put pEntropy & (byte 1 of cxSha256(pEntropy)) into tSource
   put cxBip39Wordlist() into tList
   put "" into tOut
   repeat with tI = 0 to (tWordCount - 1)
      put 0 into tValue
      repeat with tB = 0 to (kCxBip39BitsPerWord - 1)
         put tI * kCxBip39BitsPerWord + tB into tBitIndex
         put tValue * 2 + cxBitAt(tSource, tBitIndex) into tValue
      end repeat
      if tOut is not "" then
         put " " after tOut
      end if
      put cxWordAt(tList, tValue) after tOut
   end repeat
   return tOut
end cxMnemonicFromEntropy

-- The entropy a mnemonic encodes, verifying its checksum. Throws on any word
-- that is not in the list, on a word count BIP-39 does not define, and on a
-- checksum mismatch - which is the whole point of the checksum, so a single
-- mistyped word is caught here rather than becoming an empty wallet.
function cxMnemonicToEntropy pMnemonic
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxMnemonicToEntropyInner(pMnemonic) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxMnemonicToEntropy

private function cxMnemonicToEntropyInner pMnemonic
   local tWords, tCount, tList, tBits, tI, tIndex, tB
   local tEntBytes, tChecksumBits, tPacked, tEntropy, tGot, tWant
   put cxSplitWords(cxMnemonicNormalize(pMnemonic)) into tWords
   put the number of items of tWords into tCount
   if tCount is not 12 and tCount is not 15 and tCount is not 18 and tCount is not 21 and tCount is not 24 then
      throw "CoinXT: cxMnemonicToEntropy: a mnemonic must be 12, 15, 18, 21 or 24 words."
   end if
   put cxBip39Wordlist() into tList
   put "" into tBits
   repeat with tI = 1 to tCount
      put cxWordIndex(tList, item tI of tWords) into tIndex
      if tIndex < 0 then
         throw "CoinXT: cxMnemonicToEntropy: word" && tI && "is not in the BIP-39 English wordlist."
      end if
      -- Most significant bit of the 11 first, which is the order
      -- cxMnemonicFromEntropy wrote them in.
      repeat with tB = (kCxBip39BitsPerWord - 1) down to 0
         if tBits is not "" then
            put "," after tBits
         end if
         put cxIntMod(cxIntDiv(tIndex, cxPow2(tB)), 2) after tBits
      end repeat
   end repeat
   -- 32 bits of entropy per 3 words, and one checksum bit per 32 bits of it.
   put cxIntDiv(tCount * 4, 3) into tEntBytes
   put cxIntDiv(tEntBytes, 4) into tChecksumBits
   put cxBitsToBytes(tBits) into tPacked
   put byte 1 to tEntBytes of tPacked into tEntropy
   -- Compare the checksum bits as a NUMBER rather than as bytes, because when
   -- there are fewer than 8 of them the byte around them is padding on both
   -- sides and only the top tChecksumBits are meaningful.
   put cxIntDiv(byteToNum(byte (tEntBytes + 1) of tPacked), cxPow2(8 - tChecksumBits)) into tGot
   put cxIntDiv(byteToNum(byte 1 of cxSha256(tEntropy)), cxPow2(8 - tChecksumBits)) into tWant
   if tGot is not tWant then
      throw "CoinXT: cxMnemonicToEntropy: the checksum does not match, so at least one word is wrong or out of order."
   end if
   return tEntropy
end cxMnemonicToEntropyInner

-- True when pMnemonic is a well-formed BIP-39 mnemonic with a correct checksum.
--
-- Boolean, not a throw, because "is this what the user typed a valid mnemonic?"
-- is a QUESTION a restore screen asks on every keystroke, and an exception is
-- the wrong shape for an answer that is routinely no. The handlers that DO the
-- work (cxMnemonicToEntropy) still throw, so a caller never acts on a bad
-- mnemonic by accident.
function cxMnemonicValidate pMnemonic
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxMnemonicValidateInner(pMnemonic) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxMnemonicValidate

private function cxMnemonicValidateInner pMnemonic
   local tEntropy
   try
      put cxMnemonicToEntropy(pMnemonic) into tEntropy
   catch tError
      return false
   end try
   return true
end cxMnemonicValidateInner

-- The 64-byte BIP-39 seed: PBKDF2-HMAC-SHA512 over the mnemonic, salted with
-- "mnemonic" plus the passphrase, 2048 rounds.
--
-- NOTE WHAT IS NOT CHECKED: this does NOT verify the checksum. That is BIP-39's
-- design, not an omission - the seed is defined for any string, which is what
-- lets other schemes reuse the KDF - but it means a mnemonic with a typo yields
-- a perfectly good seed for the wrong wallet. Call cxMnemonicValidate first on
-- anything a human typed.
--
-- The passphrase must be ASCII, or already NFKD-normalized; see
-- cxMnemonicNormalize.
function cxMnemonicToSeed pMnemonic, pPassphrase
   return cxPbkdf2HmacSha512(cxMnemonicNormalize(pMnemonic), \
         kCxBip39SaltPrefix & pPassphrase, kCxBip39Rounds, 64)
end cxMnemonicToSeed

-- ==============================================================================
-- BIP-32: hierarchical deterministic derivation.
--
-- A node is an array, so a caller reads it by name rather than by position:
--
--   ["seckey"]     32 bytes, or empty for a watch-only (public) node
--   ["pubkey"]     33 bytes, compressed, always present
--   ["chaincode"]  32 bytes
--   ["depth"]      0 for the master node
--   ["index"]      this node's child number (0 for the master node)
--   ["parentfp"]   4 bytes, the parent's fingerprint (zero for the master node)
--
-- Every field is exactly what BIP-32 serializes, in the order it serializes it,
-- so cxXprv is a concatenation and not a translation.
-- ==============================================================================

private function cxUInt32ToBytes pValue
   -- Four bytes, big endian, FIXED WIDTH. Deliberately not cxUIntToBytes: that
   -- one is RLP's minimal-length encoding, and using it here would silently
   -- drop the leading zeros of a small child index and corrupt every
   -- serialization and every HMAC that covers one.
   local tOut, tI, tRest
   put "" into tOut
   put pValue into tRest
   repeat with tI = 1 to 4
      put numToByte(cxIntMod(tRest, 256)) before tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   return tOut
end cxUInt32ToBytes

private function cxFingerprint pPubkey
   -- The first 4 bytes of hash160(compressed public key). BIP-32 uses it only
   -- as a hint for locating a parent; it is NOT a checksum and collisions are
   -- expected, so nothing in this file treats a match as proof of anything.
   return byte 1 to 4 of cxHash160(pPubkey)
end cxFingerprint

-- The master node for a seed - normally the 64 bytes cxMnemonicToSeed returned,
-- though BIP-32 allows 16 to 64.
function cxHdFromSeed pSeed
   local tLen, tI, tNode
   put the number of bytes of pSeed into tLen
   if tLen < 16 or tLen > 64 then
      throw "CoinXT: cxHdFromSeed: a BIP-32 seed must be between 16 and 64 bytes."
   end if
   put cxHmacSha512(kCxBip32MasterKey, pSeed) into tI
   put byte 1 to 32 of tI into tNode["seckey"]
   put byte 33 to 64 of tI into tNode["chaincode"]
   -- Throws if IL is zero or >= n, which is BIP-32's "this seed is invalid" and
   -- happens with probability about 2^-127. Deriving the public key is what
   -- performs the check, so it is not restated here.
   put cxPublicKey(tNode["seckey"], true) into tNode["pubkey"]
   put 0 into tNode["depth"]
   put 0 into tNode["index"]
   put cxUInt32ToBytes(0) into tNode["parentfp"]
   return tNode
end cxHdFromSeed

-- The watch-only form of a node: same public key and chain code, no private
-- key. This is the xpub half of a wallet, and everything it can still do
-- (derive non-hardened children, and therefore receive addresses) is exactly
-- what makes an xpub both useful and a privacy liability if it leaks.
function cxHdNeuter pNode
   local tNode
   put pNode into tNode
   put "" into tNode["seckey"]
   return tNode
end cxHdNeuter

-- One derivation step. pIndex is the full child number, so a hardened child is
-- kCxHardenedBase plus its number (cxHdDerivePath does that for you when it
-- sees a ' marker).
function cxHdDeriveChild pNode, pIndex
   local tData, tI, tChild, tHasPrivate
   if pIndex < 0 or pIndex > 4294967295 then
      throw "CoinXT: cxHdDeriveChild: a child index must be between 0 and 2^32-1."
   end if
   put (pNode["seckey"] is not "") into tHasPrivate
   if pIndex >= kCxHardenedBase then
      if tHasPrivate is false then
         throw "CoinXT: cxHdDeriveChild: a hardened child cannot be derived from a public-only node, because BIP-32 hashes the private key to make one."
      end if
      -- The 0x00 pad makes the private key 33 bytes, the same width as the
      -- compressed public key the non-hardened branch uses, so both hash the
      -- same amount of data. BIP-32 is explicit about it.
      put numToByte(0) & pNode["seckey"] & cxUInt32ToBytes(pIndex) into tData
   else
      put pNode["pubkey"] & cxUInt32ToBytes(pIndex) into tData
   end if
   put cxHmacSha512(pNode["chaincode"], tData) into tI
   put byte 33 to 64 of tI into tChild["chaincode"]
   if tHasPrivate is true then
      -- Throws when IL >= n or the child key is zero. BIP-32's remedy is to
      -- use the next index; it is surfaced rather than retried here, because
      -- silently returning a DIFFERENT child than the one asked for is how two
      -- wallets end up disagreeing about what m/44'/0'/0'/0/0 means.
      put cxSeckeyTweakAdd(pNode["seckey"], byte 1 to 32 of tI) into tChild["seckey"]
      put cxPublicKey(tChild["seckey"], true) into tChild["pubkey"]
   else
      put "" into tChild["seckey"]
      put cxPubkeyTweakAdd(pNode["pubkey"], byte 1 to 32 of tI) into tChild["pubkey"]
   end if
   put pNode["depth"] + 1 into tChild["depth"]
   put pIndex into tChild["index"]
   put cxFingerprint(pNode["pubkey"]) into tChild["parentfp"]
   return tChild
end cxHdDeriveChild

-- Walk a path such as "m/44'/0'/0'/0/0" from pNode. A trailing ' or h marks a
-- hardened level. "m" alone returns pNode unchanged.
--
-- The leading "m" is accepted but NOT checked against pNode being a master
-- node, because it cannot be: a node does not record whether it is one, and
-- BIP-32 paths are routinely written relative to an account node. What IS
-- checked is that every level is a number in range and that the separators are
-- what they claim to be.
function cxHdDerivePath pNode, pPath
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxHdDerivePathInner(pNode, pPath) into tResult
   catch tError
      -- CAPTURE, DO NOT RE-THROW HERE. See the note above cxBech32EncodeValues:
      -- a throw issued INSIDE a catch block does not reach the caller on OXT.
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxHdDerivePath

private function cxHdDerivePathInner pNode, pPath
   local tPath, tNode, tCount, tI, tPart, tLast, tHardened, tIndex, tJ, tCode, tPartLen, tPathLen
   put pPath into tPath
   -- A trailing separator must be refused HERE, while the "/" is still
   -- visible: the engine ignores one trailing delimiter when it counts
   -- items, so after the replace below "m/" counts as ONE item, the level
   -- loop never runs, and the empty-level check inside it can never fire.
   -- The 2026-08-10 engine pass caught exactly that failing OPEN: "m/"
   -- walked zero levels and handed back the node unchanged.
   put the number of chars of tPath into tPathLen
   if tPathLen > 0 and char tPathLen of tPath is "/" then
      throw "CoinXT: cxHdDerivePath: the path has an empty level."
   end if
   replace "/" with comma in tPath
   put pNode into tNode
   put the number of items of tPath into tCount
   if tCount < 1 then
      throw "CoinXT: cxHdDerivePath: the path is empty."
   end if
   if item 1 of tPath is not "m" and item 1 of tPath is not "M" then
      throw "CoinXT: cxHdDerivePath: a path must begin with m."
   end if
   repeat with tI = 2 to tCount
      put item tI of tPath into tPart
      if tPart is "" then
         throw "CoinXT: cxHdDerivePath: the path has an empty level."
      end if
      put false into tHardened
      put the number of chars of tPart into tPartLen
      put char tPartLen of tPart into tLast
      if tLast is "'" or tLast is "h" or tLast is "H" then
         put true into tHardened
         delete char tPartLen to tPartLen of tPart
      end if
      if tPart is "" then
         throw "CoinXT: cxHdDerivePath: a hardened marker with no index before it."
      end if
      -- Digits only, checked by byte value: `is a number` would accept "1e3",
      -- " 5" and "5.0", and a path level that quietly became 5000 or 5 would be
      -- a different wallet with no error anywhere.
      repeat with tJ = 1 to the number of chars of tPart
         put byteToNum(char tJ of tPart) into tCode
         if tCode < 48 or tCode > 57 then
            throw "CoinXT: cxHdDerivePath: a path level must be digits, optionally followed by a hardened marker."
         end if
      end repeat
      put tPart + 0 into tIndex
      if tIndex >= kCxHardenedBase then
         throw "CoinXT: cxHdDerivePath: a path level must be below 2^31; use the ' marker for a hardened level."
      end if
      if tHardened is true then
         add kCxHardenedBase to tIndex
      end if
      put cxHdDeriveChild(tNode, tIndex) into tNode
   end repeat
   return tNode
end cxHdDerivePathInner

private function cxHdSerialize pNode, pVersion, pPrivate
   -- The 78 bytes BIP-32 defines, in order: version, depth, parent
   -- fingerprint, child number, chain code, then 33 key bytes - a private key
   -- padded to 33 with a leading 0x00, or the compressed public key as is.
   local tOut
   put cxUInt32ToBytes(pVersion) into tOut
   put numToByte(pNode["depth"]) after tOut
   put pNode["parentfp"] after tOut
   put cxUInt32ToBytes(pNode["index"]) after tOut
   put pNode["chaincode"] after tOut
   if pPrivate is true then
      put numToByte(0) & pNode["seckey"] after tOut
   else
      put pNode["pubkey"] after tOut
   end if
   return tOut
end cxHdSerialize

-- The node as an "xprv..." string. Mainnet only for now; a testnet or altcoin
-- prefix is a different version number and nothing else, but CoinXT does not
-- ship one it has not pinned to a vector.
function cxXprv pNode
   if pNode["seckey"] is "" then
      throw "CoinXT: cxXprv: this node has no private key, so it can only be serialized as an xpub."
   end if
   if pNode["depth"] > 255 then
      throw "CoinXT: cxXprv: BIP-32 stores the depth in one byte, so it cannot exceed 255."
   end if
   return cxBase58CheckEncode(cxHdSerialize(pNode, kCxVersionXprv, true))
end cxXprv

-- The node as an "xpub..." string. Safe to hand out in the sense that it holds
-- no private key, and unsafe in the sense that it reveals every address the
-- wallet will ever use on that branch.
function cxXpub pNode
   if pNode["depth"] > 255 then
      throw "CoinXT: cxXpub: BIP-32 stores the depth in one byte, so it cannot exceed 255."
   end if
   return cxBase58CheckEncode(cxHdSerialize(pNode, kCxVersionXpub, false))
end cxXpub


-- ==============================================================================
-- WIF (Wallet Import Format): Base58Check over
--   version || 32-byte private key || optional 0x01 compressed marker
-- the last of the Base58Check framings SPEC.md lists beside addresses and
-- xprv/xpub. The version byte is the network (0x80 mainnet, 0xEF testnet), and
-- the marker records which FORM of the public key the wallet should derive -
-- compressed and uncompressed keys hash to different addresses, so losing the
-- flag silently moves the funds to a different address, which is why it is
-- surfaced explicitly in both directions rather than defaulted.
--
-- THE KEY CROSSES AS HEX TEXT in both directions, unlike the Data keys of the
-- handlers above, and that follows from what WIF is FOR: it is the paste-in /
-- paste-out format, so the key arrives as pasted text and leaves as pasteable
-- text, the same reasoning that has phase 5 moving txids and scripts as hex.
-- A caller who needs the bytes (cxSign, cxPublicKey) runs cxHexDecode over
-- the decoded "seckey".
--
-- STATUS: verified statically; needs an OXT pass. The logic is executed
-- headlessly by tools/check-script-vectors.py against oracle-derived vectors
-- anchored to the Bitcoin wiki's published worked example, both directions
-- plus the refusals - the same net every earlier phase carries - but no
-- engine has run these two handlers yet.
-- ==============================================================================

-- The WIF network version bytes, the same role kCxVersionP2PKH plays for an
-- address payload. 128 is 0x80 (mainnet), 239 is 0xEF (testnet); they are what
-- make a mainnet WIF start with 5 (uncompressed) or K/L (compressed). Checked
-- against the reference by tools/check-script-vectors.py like every other
-- transcribed constant.
constant kCxWifVersionMainnet = 128
constant kCxWifVersionTestnet = 239

-- A private key as WIF text. pSeckeyHex is the key as 64 hex characters;
-- pNetwork is "mainnet" or "testnet" (any other spelling is refused, the
-- cxBech32Const rule: a wrong network is a programming error, never a
-- default); pCompressed must be literally true or false, because it changes
-- which address the key unlocks and there is no safe side to guess.
function cxWifEncode pSeckeyHex, pNetwork, pCompressed
   local tKey, tVersion, tPayload, tOut
   -- The argument checks run before the key is decoded, so no throw below
   -- them leaves key bytes in a local this handler did not get to clear.
   if pNetwork is "mainnet" then
      put kCxWifVersionMainnet into tVersion
   else if pNetwork is "testnet" then
      put kCxWifVersionTestnet into tVersion
   else
      throw "CoinXT: cxWifEncode: the network must be either mainnet or testnet."
   end if
   if pCompressed is not true and pCompressed is not false then
      throw "CoinXT: cxWifEncode: the compressed flag must be true or false."
   end if
   put cxHexDecode(pSeckeyHex) into tKey
   if the number of bytes of tKey is not 32 then
      put empty into tKey
      throw "CoinXT: cxWifEncode: a private key is 32 bytes (64 hex characters)."
   end if
   -- Range-check through the shim rather than framing blind: the encoding
   -- itself would happily wrap zero or a value at or above the group order
   -- into a checksummed, valid-looking WIF of a key no wallet can spend from
   -- - the wrong-but-plausible answer rule 4 exists to forbid. This is the
   -- exact question cxSeckeyIsValid was built to answer for an imported key.
   if cxSeckeyIsValid(tKey) is false then
      put empty into tKey
      throw "CoinXT: cxWifEncode: the key is zero or not below the secp256k1 group order, so it is not a usable private key."
   end if
   put numToByte(tVersion) & tKey into tPayload
   if pCompressed is true then
      put numToByte(1) after tPayload
   end if
   put cxBase58CheckEncode(tPayload) into tOut
   -- The secret-hygiene rule: clear the key copies the moment they are done
   -- with. Script variables are not locked memory (the documented limit), but
   -- a wallet's key should not linger in a library's locals either.
   put empty into tKey
   put empty into tPayload
   return tOut
end cxWifEncode

-- The inverse. Returns an array read by name, the cxSegwitAddressDecode
-- convention: "seckey" (64 lowercase hex characters), "network" ("mainnet" or
-- "testnet") and "compressed" (true or false). It FAILS CLOSED on everything
-- malformed: a bad character or checksum throws inside cxBase58CheckDecode
-- (the layer that found the corruption reports it, as the SegWit decoder lets
-- the bech32 layer's messages stand), and the wrong payload length, an
-- unknown version byte, a trailing byte that is not the 0x01 marker, and an
-- out-of-range key each throw here. A typo in a pasted key must never decode
-- to a plausible neighbouring wallet.
function cxWifDecode pWif
   local tBody, tCount, tVersion, tKey, tResult
   put cxBase58CheckDecode(pWif) into tBody
   put the number of bytes of tBody into tCount
   if tCount is not 33 and tCount is not 34 then
      throw "CoinXT: cxWifDecode: the payload must be 33 bytes (version and key) or 34 (with the compressed marker), so this is not a WIF key."
   end if
   put byteToNum(byte 1 of tBody) into tVersion
   if tVersion is kCxWifVersionMainnet then
      put "mainnet" into tResult["network"]
   else if tVersion is kCxWifVersionTestnet then
      put "testnet" into tResult["network"]
   else
      throw "CoinXT: cxWifDecode: the version byte is neither mainnet (0x80) nor testnet (0xEF)."
   end if
   -- A 34-byte payload whose trailing byte is anything but 0x01 is refused
   -- rather than read as uncompressed: it is not a shape any encoder emits,
   -- and guessing a flag guesses an address.
   if tCount is 34 then
      if byteToNum(byte 34 of tBody) is not 1 then
         throw "CoinXT: cxWifDecode: the trailing byte is not the 0x01 compressed marker."
      end if
      put true into tResult["compressed"]
   else
      put false into tResult["compressed"]
   end if
   put byte 2 to 33 of tBody into tKey
   -- The same range check as the encoder, for the same reason: a WIF that
   -- frames an unusable scalar is corrupt even with a valid checksum.
   if cxSeckeyIsValid(tKey) is false then
      throw "CoinXT: cxWifDecode: the decoded key is zero or not below the secp256k1 group order, so it is not a usable private key."
   end if
   put cxHexEncode(tKey) into tResult["seckey"]
   put empty into tKey
   put empty into tBody
   return tResult
end cxWifDecode


-- ==============================================================================
-- Phase 5 - transaction building and signing.
--
-- STATUS: verified statically and against tools/coin_reference.py (which
-- reproduces the BIP-143 native-P2WPKH worked example, the EIP-155 spec
-- example and a self-consistent EIP-1559 typed transaction). This block
-- used to demand "an OXT pass + independent-decoder acceptance" before any
-- "broadcastable" claim; both bars are met and recorded in CLAUDE.md's
-- as-built notes: ENGINE-PASSED 2026-08-12 (Windows x64, 230/230, this
-- phase included), and INDEPENDENTLY ACCEPTED 2026-08-12, extended to all
-- four transaction families 2026-08-13 - fresh transactions built end to
-- end through THIS file and accepted by python-bitcointx / eth-account
-- (tools/verify-independent-decoder.py). The one bar left: a live testnet
-- broadcast is still owed, so "broadcastable" stays unclaimed until then.
--
-- This is still the SCRIPT layer, so it composes the primitives and NEVER
-- touches a private key or a curve point: signing is the app calling cxSign /
-- cxSignRecoverable on a 32-byte digest THIS layer produced. A blind signer is
-- a footgun (coinxt/CLAUDE.md rule 3), so the app confirms the decoded human
-- intent before it signs.
--
-- THE STRUCTURED-INPUT CONVENTION mirrors the RLP layer's: xTalk has no nested
-- list literal, so a transaction's repeated fields cross as COMMA-SEPARATED
-- LISTS OF HEX (one item per input or per output), exactly like the comma list
-- of 5-bit values cxBech32EncodeValues already takes. Every handler that reads
-- one saves, sets and restores the itemDelimiter.
--
-- INTEGER WIDTHS. Bitcoin counts (version, sequence, locktime, vout) and
-- satoshi amounts stay inside exact-integer range (21e6 BTC is 2.1e15 sat, well
-- under 2^53) and cross as integers. Ethereum wei-scale fields (value,
-- gasPrice, the 1559 fee caps) routinely exceed 2^53, so they cross as MINIMAL
-- big-endian HEX and are RLP-encoded as byte strings; only the small counters
-- (nonce, gas, chainId, recid) cross as integers.

-- Fixed-width little-endian encoder. Bitcoin serialization is little-endian
-- throughout, which nothing in phases 1-4 needed (their integers were all
-- big-endian). pWidth bytes, least significant first; pValue must be
-- non-negative and fit in pWidth bytes.
private function cxUIntToBytesLE pValue, pWidth
   local tOut, tRest, tI
   if pValue < 0 then
      throw "CoinXT: cxUIntToBytesLE: the value must not be negative."
   end if
   put "" into tOut
   put pValue into tRest
   repeat with tI = 1 to pWidth
      put numToByte(cxIntMod(tRest, 256)) after tOut
      put cxIntDiv(tRest, 256) into tRest
   end repeat
   if tRest is not 0 then
      throw "CoinXT: cxUIntToBytesLE: the value does not fit in the requested width."
   end if
   return tOut
end cxUIntToBytesLE

-- Bitcoin CompactSize (varint): 1, 3, 5 or 9 bytes by magnitude.
function cxVarInt pN
   if pN < 0 then
      throw "CoinXT: cxVarInt: the count must not be negative."
   end if
   if pN < 253 then
      return numToByte(pN)
   end if
   if pN <= 65535 then
      return numToByte(253) & cxUIntToBytesLE(pN, 2)
   end if
   if pN <= 4294967295 then
      return numToByte(254) & cxUIntToBytesLE(pN, 4)
   end if
   return numToByte(255) & cxUIntToBytesLE(pN, 8)
end cxVarInt

-- Strip leading zero BYTES, so a hex uint field becomes its canonical minimal
-- big-endian form before RLP. RLP requires one encoding per value; a leading
-- zero byte would be a second spelling and break every hash over it.
private function cxStripLeadingZeroBytes pData
   local tCount, tStart
   put the number of bytes of pData into tCount
   put 1 into tStart
   repeat while tStart <= tCount and byteToNum(byte tStart of pData) is 0
      add 1 to tStart
   end repeat
   if tStart > tCount then
      return ""
   end if
   return byte tStart to tCount of pData
end cxStripLeadingZeroBytes

-- RLP of a non-negative integer given as minimal-or-padded big-endian hex:
-- strip leading zero bytes to canonical form, then encode as a byte string
-- (zero becomes the empty string, RLP 0x80).
private function cxRlpUintFromHex pHex
   return cxRlpEncodeBytes(cxStripLeadingZeroBytes(cxHexDecode(pHex)))
end cxRlpUintFromHex

-- Compact 64-byte r||s (the cxSign shape) to a DER-encoded signature, which is
-- what a Bitcoin scriptSig carries. cxSign already enforces low-s, so no
-- normalization is needed here; this is pure structure. The SIGHASH type byte
-- is the caller's to append.
function cxDerEncode pCompactSig
   local tR, tS, tBody
   if the number of bytes of pCompactSig is not 64 then
      throw "CoinXT: cxDerEncode: a compact signature is 64 bytes (r || s)."
   end if
   put cxDerInteger(byte 1 to 32 of pCompactSig) into tR
   put cxDerInteger(byte 33 to 64 of pCompactSig) into tS
   put tR & tS into tBody
   return numToByte(48) & numToByte(the number of bytes of tBody) & tBody
end cxDerEncode

private function cxDerInteger pValue
   local tTrimmed, tLen
   put cxStripLeadingZeroBytes(pValue) into tTrimmed
   if tTrimmed is "" then
      put numToByte(0) into tTrimmed
   end if
   -- DER integers are signed: a leading byte >= 0x80 needs a 0x00 sign pad so
   -- the value is not read as negative.
   if byteToNum(byte 1 of tTrimmed) >= 128 then
      put numToByte(0) & tTrimmed into tTrimmed
   end if
   put the number of bytes of tTrimmed into tLen
   return numToByte(2) & numToByte(tLen) & tTrimmed
end cxDerInteger

-- A 36-byte outpoint from a display-order (big-endian) txid hex and a vout. The
-- txid serializes little-endian (byte-reversed), then the 4-byte LE index.
function cxBtcOutpoint pTxidHex, pVout
   local tTxid
   put cxHexDecode(pTxidHex) into tTxid
   if the number of bytes of tTxid is not 32 then
      throw "CoinXT: cxBtcOutpoint: a txid is 32 bytes (64 hex chars)."
   end if
   return cxReverseBytes(tTxid) & cxUIntToBytesLE(pVout, 4)
end cxBtcOutpoint

private function cxReverseBytes pData
   local tOut, tI, tCount
   put the number of bytes of pData into tCount
   put "" into tOut
   repeat with tI = 1 to tCount
      put byte tI of pData before tOut
   end repeat
   return tOut
end cxReverseBytes

-- A serialized transaction output: 8-byte LE amount, then the scriptPubKey with
-- its CompactSize length. pScriptHex is the scriptPubKey as hex.
function cxBtcOutput pAmountSat, pScriptHex
   local tScript
   put cxHexDecode(pScriptHex) into tScript
   return cxUIntToBytesLE(pAmountSat, 8) & cxVarInt(the number of bytes of tScript) & tScript
end cxBtcOutput

-- The pre-SegWit SIGHASH_ALL preimage digest for input pIndex. pOutpoints and
-- pSequences are parallel comma lists (36-byte outpoint hex; a sequence
-- integer each); pOutputs is a comma list of serialized-output hex (from
-- cxBtcOutput). pScriptCodeHex is the BARE scriptPubKey of the input being
-- signed (this layer adds its length prefix); every other input's script slot
-- is empty. Returns a 32-byte digest to hand to cxSign.
function cxBtcSighashLegacy pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashLegacyInner(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcSighashLegacy

private function cxBtcSighashLegacyInner pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pOutputs, pLocktime, pSighashType
   local tCount, tI, tBuf, tScript, tOutBytes, tOutCount
   -- SIGHASH_ALL ONLY, AND IT IS REFUSED RATHER THAN APPROXIMATED.
   -- Neither preimage builder below branches on pSighashType: both always
   -- commit to every prevout, every sequence and every output, which IS the
   -- SIGHASH_ALL algorithm. The other types change WHICH of those the digest
   -- covers - SIGHASH_NONE drops the outputs, SINGLE keeps only the output at
   -- this index, ANYONECANPAY (0x80) drops the other inputs. The type byte was
   -- nonetheless appended verbatim to the preimage, so asking for type 3 got a
   -- digest that says "3" over data hashed as if it were 1: a signature that
   -- looks right, verifies nowhere, and commits to outputs the signer believed
   -- it had excluded. Silent, and in a signing path.
   --
   -- Refusing is the whole fix HERE. Implementing the variants is a separate,
   -- larger change with its own published vectors; until it lands, a caller
   -- that wants them must know they do not exist rather than discover it from
   -- a rejected transaction. (docs/api-reference.md already scopes both
   -- handlers to SIGHASH_ALL - the parameter simply never enforced it.)
   if pSighashType is not 1 then
      throw "CoinXT: " & "cxBtcSighashLegacy" & ": only SIGHASH_ALL (1) is implemented; got " & \
            pSighashType & ". SIGHASH_NONE/SINGLE/ANYONECANPAY change which " & \
            "inputs and outputs the digest covers, and this builder does not."
   end if
   put the number of items of pOutpoints into tCount
   if tCount is 0 or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcSighashLegacy: the outpoint and sequence lists must be parallel and non-empty."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashLegacy: the input index is out of range (it is 1-based)."
   end if
   put cxHexDecode(pScriptCodeHex) into tScript
   put cxUIntToBytesLE(pVersion, 4) & cxVarInt(tCount) into tBuf
   repeat with tI = 1 to tCount
      put tBuf & cxHexDecode(item tI of pOutpoints) into tBuf
      if tI is pIndex then
         put tBuf & cxVarInt(the number of bytes of tScript) & tScript into tBuf
      else
         put tBuf & cxVarInt(0) into tBuf
      end if
      put tBuf & cxUIntToBytesLE(item tI of pSequences, 4) into tBuf
   end repeat
   put the number of items of pOutputs into tOutCount
   put "" into tOutBytes
   repeat with tI = 1 to tOutCount
      put tOutBytes & cxHexDecode(item tI of pOutputs) into tOutBytes
   end repeat
   put tBuf & cxVarInt(tOutCount) & tOutBytes into tBuf
   put tBuf & cxUIntToBytesLE(pLocktime, 4) & cxUIntToBytesLE(pSighashType, 4) into tBuf
   return cxHash256(tBuf)
end cxBtcSighashLegacyInner

-- The BIP-143 (SegWit) preimage digest for input pIndex. Same parallel lists as
-- the legacy form (pOutpoints, pSequences, pOutputs), plus the input's amount in
-- satoshi (BIP-143 commits to it). pScriptCodeHex is the BARE scriptCode (for
-- P2WPKH the app passes the 25-byte P2PKH script 76a914{hash}88ac; this layer
-- adds the length prefix). pOutputs is REQUIRED: hashOutputs is the commitment
-- that binds the signature to WHERE the coins go, so a preimage without it would
-- authorize a payment to anywhere (the review caught exactly this).
function cxBtcSighashSegwit pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashSegwitInner(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcSighashSegwit

private function cxBtcSighashSegwitInner pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pOutputs, pLocktime, pSighashType
   local tCount, tI, tPrevouts, tSequencesRaw, tOutputsRaw, tScript, tBuf, tOutCount
   -- SIGHASH_ALL ONLY, AND IT IS REFUSED RATHER THAN APPROXIMATED.
   -- Neither preimage builder below branches on pSighashType: both always
   -- commit to every prevout, every sequence and every output, which IS the
   -- SIGHASH_ALL algorithm. The other types change WHICH of those the digest
   -- covers - SIGHASH_NONE drops the outputs, SINGLE keeps only the output at
   -- this index, ANYONECANPAY (0x80) drops the other inputs. The type byte was
   -- nonetheless appended verbatim to the preimage, so asking for type 3 got a
   -- digest that says "3" over data hashed as if it were 1: a signature that
   -- looks right, verifies nowhere, and commits to outputs the signer believed
   -- it had excluded. Silent, and in a signing path.
   --
   -- Refusing is the whole fix HERE. Implementing the variants is a separate,
   -- larger change with its own published vectors; until it lands, a caller
   -- that wants them must know they do not exist rather than discover it from
   -- a rejected transaction. (docs/api-reference.md already scopes both
   -- handlers to SIGHASH_ALL - the parameter simply never enforced it.)
   if pSighashType is not 1 then
      throw "CoinXT: " & "cxBtcSighashSegwit" & ": only SIGHASH_ALL (1) is implemented; got " & \
            pSighashType & ". SIGHASH_NONE/SINGLE/ANYONECANPAY change which " & \
            "inputs and outputs the digest covers, and this builder does not."
   end if
   put the number of items of pOutpoints into tCount
   if tCount is 0 or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcSighashSegwit: the outpoint and sequence lists must be parallel and non-empty."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashSegwit: the input index is out of range (it is 1-based)."
   end if
   if pOutputs is "" then
      throw "CoinXT: cxBtcSighashSegwit: the outputs list is required (BIP-143 commits to hashOutputs)."
   end if
   put "" into tPrevouts
   put "" into tSequencesRaw
   repeat with tI = 1 to tCount
      put tPrevouts & cxHexDecode(item tI of pOutpoints) into tPrevouts
      put tSequencesRaw & cxUIntToBytesLE(item tI of pSequences, 4) into tSequencesRaw
   end repeat
   put the number of items of pOutputs into tOutCount
   put "" into tOutputsRaw
   repeat with tI = 1 to tOutCount
      put tOutputsRaw & cxHexDecode(item tI of pOutputs) into tOutputsRaw
   end repeat
   put cxHexDecode(pScriptCodeHex) into tScript
   put cxUIntToBytesLE(pVersion, 4) into tBuf
   put tBuf & cxHash256(tPrevouts) & cxHash256(tSequencesRaw) into tBuf
   put tBuf & cxHexDecode(item pIndex of pOutpoints) into tBuf
   put tBuf & cxVarInt(the number of bytes of tScript) & tScript into tBuf
   put tBuf & cxUIntToBytesLE(pAmountSat, 8) & cxUIntToBytesLE(item pIndex of pSequences, 4) into tBuf
   put tBuf & cxHash256(tOutputsRaw) & cxUIntToBytesLE(pLocktime, 4) & cxUIntToBytesLE(pSighashType, 4) into tBuf
   return cxHash256(tBuf)
end cxBtcSighashSegwitInner

-- --------------------------------------------------------------------------
-- BIP-341: the Taproot signature hash and the script-path tree (2026-08-23).
-- The SPEC.md gap this closes read "there is NO BIP-341 sighash builder;
-- coinxt signs a sighash it is handed and cannot compute one" - additive
-- script-layer work over the ABI-6 surface, no shim change, exactly as that
-- sentence promised. Every value below is pinned to bitcoin/bips'
-- wallet-test-vectors.json (all 7 keyPathSpending inputs - the full sighash
-- type set 0/1/2/3/0x81/0x82/0x83 - all 6 script trees' leaf hashes and
-- merkle roots, and all 12 published control blocks), derived by
-- tools/coin_reference.py and EXECUTED through this file by
-- tools/check-script-vectors.py. Rule 3 stands: these build DIGESTS and
-- byte structures; the app still confirms intent and calls the signer.
-- --------------------------------------------------------------------------

private function cxTapTagged pTag, pData
   -- BIP-340/341 tagged hash: sha256(sha256(tag) || sha256(tag) || data).
   -- The tag doubling is the domain separation; do not "optimise" it away.
   local tTagHash
   put cxSha256(pTag) into tTagHash
   return cxSha256(tTagHash & tTagHash & pData)
end cxTapTagged

-- The BIP-341 leaf hash: tagged TapLeaf over version || compact_size(script)
-- || script. pLeafVersion is the EVEN byte from the control block (0xc0 for
-- tapscript); scripts here stay under 253 bytes, so a longer one is refused
-- rather than given a wrong one-byte size prefix.
function cxTapLeafHash pLeafVersion, pScriptHex
   local tScript
   if pLeafVersion < 0 or pLeafVersion > 254 or cxIntMod(pLeafVersion, 2) is not 0 then
      throw "CoinXT: cxTapLeafHash: the leaf version must be an even byte (0xc0 for tapscript)."
   end if
   -- 0x50 is even but RESERVED: BIP-341 excludes it because a control block
   -- starting 0x50 would be ambiguous with the annex marker.
   if pLeafVersion is 80 then
      throw "CoinXT: cxTapLeafHash: leaf version 0x50 is reserved (ambiguous with the annex)."
   end if
   put cxHexDecode(pScriptHex) into tScript
   if the number of bytes of tScript >= 253 then
      throw "CoinXT: cxTapLeafHash: scripts of 253+ bytes are not supported (compact size)."
   end if
   return cxHexEncode(cxTapTagged("TapLeaf", numToByte(pLeafVersion) & \
         numToByte(the number of bytes of tScript) & tScript))
end cxTapLeafHash

-- A BIP-341 inner node: tagged TapBranch over the two child hashes in
-- LEXICOGRAPHIC byte order. The sort is the CONSENSUS rule - an unsorted
-- branch is a different root and a different address - and it compares BYTE
-- VALUES through cxCompareBytes, never `<` (two hex strings that both look
-- numeric would compare as numbers; discipline 3).
function cxTapBranchHash pAHex, pBHex
   local tA, tB
   put cxHexDecode(pAHex) into tA
   put cxHexDecode(pBHex) into tB
   if the number of bytes of tA is not 32 or the number of bytes of tB is not 32 then
      throw "CoinXT: cxTapBranchHash: each child must be 32 bytes of hex."
   end if
   if cxCompareBytes(tA, tB) > 0 then
      return cxHexEncode(cxTapTagged("TapBranch", tB & tA))
   end if
   return cxHexEncode(cxTapTagged("TapBranch", tA & tB))
end cxTapBranchHash

-- The script-path control block: (leafVersion | parity) || internal x-only
-- key || the merkle path (the SIBLING hashes from the leaf to the root, in
-- leaf-to-root order, as a comma list of 64-hex; empty for a single-leaf
-- tree). pParity is the 0/1 the tweak reported (cxTaprootTweak's "parity").
function cxTapControlBlock pLeafVersion, pParity, pInternalKeyHex, pPathHex
   local tError
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxTapControlBlockInner(pLeafVersion, pParity, pInternalKeyHex, pPathHex) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxTapControlBlock

private function cxTapControlBlockInner pLeafVersion, pParity, pInternalKeyHex, pPathHex
   local tKey, tBuf, tI, tNode
   if pLeafVersion < 0 or pLeafVersion > 254 or cxIntMod(pLeafVersion, 2) is not 0 then
      throw "CoinXT: cxTapControlBlock: the leaf version must be an even byte."
   end if
   -- the 0x50 refusal is not pedantry here: a control block whose FIRST BYTE
   -- is 0x50 is exactly what BIP-341 reserves the value to avoid, because a
   -- witness element starting 0x50 is read as the annex.
   if pLeafVersion is 80 then
      throw "CoinXT: cxTapControlBlock: leaf version 0x50 is reserved (ambiguous with the annex)."
   end if
   if pParity is not 0 and pParity is not 1 then
      throw "CoinXT: cxTapControlBlock: the parity must be 0 or 1 (the tweak's own report)."
   end if
   put cxHexDecode(pInternalKeyHex) into tKey
   if the number of bytes of tKey is not 32 then
      throw "CoinXT: cxTapControlBlock: the internal key must be 32 bytes of hex (x-only)."
   end if
   put numToByte(pLeafVersion + pParity) & tKey into tBuf
   if pPathHex is not "" then
      -- BIP-341 caps a control block at 33 + 32*128 bytes; a longer path is
      -- not a bigger tree, it is an invalid witness element.
      if the number of items of pPathHex > 128 then
         throw "CoinXT: cxTapControlBlock: a merkle path is at most 128 nodes (BIP-341)."
      end if
      repeat with tI = 1 to the number of items of pPathHex
         put cxHexDecode(item tI of pPathHex) into tNode
         if the number of bytes of tNode is not 32 then
            throw "CoinXT: cxTapControlBlock: every path element must be 32 bytes of hex."
         end if
         put tBuf & tNode into tBuf
      end repeat
   end if
   return cxHexEncode(tBuf)
end cxTapControlBlockInner

-- The BIP-341 signature hash. Unlike BIP-143 it commits to EVERY spent
-- output, so beside the outpoint and sequence lists it takes the PER-INPUT
-- amounts and scriptPubKeys of everything the transaction spends (parallel
-- comma lists, one item per input, none of them optional). pOutputs is the
-- serialized outputs as in the segwit form. pTapleafHex chooses the path:
-- empty for key-path, the 64-hex cxTapLeafHash for script-path spending
-- (key_version 0, no OP_CODESEPARATOR - codesep position 0xffffffff - the
-- common tapscript case; a script using OP_CODESEPARATOR needs a builder
-- this layer does not have, and says so rather than guessing). No annex.
-- The full type set IS implemented here - 0 (default), 1, 2, 3 and their
-- ANYONECANPAY forms - each pinned to a published keyPathSpending vector,
-- which is what the segwit builder's SIGHASH_ALL-only refusal said the
-- variants would need before they could exist.
function cxBtcSighashTaproot pVersion, pOutpoints, pSequences, pAmountsSat, pScriptPubkeys, pOutputs, pIndex, pLocktime, pSighashType, pTapleafHex
   local tError
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashTaprootInner(pVersion, pOutpoints, pSequences, pAmountsSat, \
            pScriptPubkeys, pOutputs, pIndex, pLocktime, pSighashType, pTapleafHex) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcSighashTaproot

private function cxBtcSighashTaprootInner pVersion, pOutpoints, pSequences, pAmountsSat, pScriptPubkeys, pOutputs, pIndex, pLocktime, pSighashType, pTapleafHex
   local tCount, tI, tAnyoneCanPay, tBase, tBuf, tRaw, tSpk, tLeaf, tOutCount
   -- the valid type set is BIP-341's own: 0x80 alone is NOT a type.
   if pSighashType is not 0 and pSighashType is not 1 and pSighashType is not 2 \
         and pSighashType is not 3 and pSighashType is not 129 \
         and pSighashType is not 130 and pSighashType is not 131 then
      throw "CoinXT: cxBtcSighashTaproot: invalid sighash type (0, 1, 2, 3, 0x81, 0x82 or 0x83)."
   end if
   put the number of items of pOutpoints into tCount
   if tCount is 0 then
      throw "CoinXT: cxBtcSighashTaproot: the outpoint list is empty."
   end if
   -- BIP-341 commits to every spent output, so all four per-input lists must
   -- be parallel. No item may be empty (every input HAS an amount and a
   -- scriptPubKey), so a trailing-empty item - which the engine's chunk rule
   -- would count short - is malformed here and the strict count guard is the
   -- right one, unlike the tx encoder's deliberately-loose scriptSig list.
   if the number of items of pSequences is not tCount \
         or the number of items of pAmountsSat is not tCount \
         or the number of items of pScriptPubkeys is not tCount then
      throw "CoinXT: cxBtcSighashTaproot: the outpoint, sequence, amount and scriptPubKey lists must be parallel."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashTaproot: the input index is out of range (it is 1-based)."
   end if
   put 0 into tAnyoneCanPay
   put pSighashType into tBase
   if pSighashType >= 129 then
      put 1 into tAnyoneCanPay
      put pSighashType - 128 into tBase
   end if
   if tBase is 3 and pIndex > the number of items of pOutputs then
      throw "CoinXT: cxBtcSighashTaproot: SIGHASH_SINGLE with no matching output is invalid under BIP-341."
   end if
   -- epoch 0x00, then the type, version and locktime.
   put numToByte(0) & numToByte(pSighashType) into tBuf
   put tBuf & cxUIntToBytesLE(pVersion, 4) & cxUIntToBytesLE(pLocktime, 4) into tBuf
   if tAnyoneCanPay is 0 then
      put "" into tRaw
      repeat with tI = 1 to tCount
         put tRaw & cxHexDecode(item tI of pOutpoints) into tRaw
      end repeat
      put tBuf & cxSha256(tRaw) into tBuf
      put "" into tRaw
      repeat with tI = 1 to tCount
         put tRaw & cxUIntToBytesLE(item tI of pAmountsSat, 8) into tRaw
      end repeat
      put tBuf & cxSha256(tRaw) into tBuf
      put "" into tRaw
      repeat with tI = 1 to tCount
         put cxHexDecode(item tI of pScriptPubkeys) into tSpk
         put tRaw & cxVarInt(the number of bytes of tSpk) & tSpk into tRaw
      end repeat
      put tBuf & cxSha256(tRaw) into tBuf
      put "" into tRaw
      repeat with tI = 1 to tCount
         put tRaw & cxUIntToBytesLE(item tI of pSequences, 4) into tRaw
      end repeat
      put tBuf & cxSha256(tRaw) into tBuf
   end if
   if tBase is not 2 and tBase is not 3 then
      put "" into tRaw
      put the number of items of pOutputs into tOutCount
      repeat with tI = 1 to tOutCount
         put tRaw & cxHexDecode(item tI of pOutputs) into tRaw
      end repeat
      put tBuf & cxSha256(tRaw) into tBuf
   end if
   -- spend_type: ext_flag (1 for script path) * 2 + annex_present (never).
   if pTapleafHex is "" then
      put tBuf & numToByte(0) into tBuf
   else
      put tBuf & numToByte(2) into tBuf
   end if
   if tAnyoneCanPay is 1 then
      put cxHexDecode(item pIndex of pScriptPubkeys) into tSpk
      put tBuf & cxHexDecode(item pIndex of pOutpoints) into tBuf
      put tBuf & cxUIntToBytesLE(item pIndex of pAmountsSat, 8) into tBuf
      put tBuf & cxVarInt(the number of bytes of tSpk) & tSpk into tBuf
      put tBuf & cxUIntToBytesLE(item pIndex of pSequences, 4) into tBuf
   else
      put tBuf & cxUIntToBytesLE(pIndex - 1, 4) into tBuf
   end if
   if tBase is 3 then
      put tBuf & cxSha256(cxHexDecode(item pIndex of pOutputs)) into tBuf
   end if
   if pTapleafHex is not "" then
      put cxHexDecode(pTapleafHex) into tLeaf
      if the number of bytes of tLeaf is not 32 then
         throw "CoinXT: cxBtcSighashTaproot: the tapleaf hash must be 32 bytes of hex (cxTapLeafHash)."
      end if
      put tBuf & tLeaf & numToByte(0) into tBuf
      put tBuf & numToByte(255) & numToByte(255) & numToByte(255) & numToByte(255) into tBuf
   end if
   return cxTapTagged("TapSighash", tBuf)
end cxBtcSighashTaprootInner

-- A serialized SegWit witness stack for one input: the CompactSize item count,
-- then each item as CompactSize-length + bytes. pItems is a comma list of item
-- hex (empty string for an input with no witness).
function cxBtcWitness pItems
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcWitnessInner(pItems) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcWitness

private function cxBtcWitnessInner pItems
   local tCount, tI, tOut, tItem
   if pItems is "" then
      return cxVarInt(0)
   end if
   put the number of items of pItems into tCount
   put cxVarInt(tCount) into tOut
   repeat with tI = 1 to tCount
      put cxHexDecode(item tI of pItems) into tItem
      put tOut & cxVarInt(the number of bytes of tItem) & tItem into tOut
   end repeat
   return tOut
end cxBtcWitnessInner

-- Serialize a full transaction. pOutpoints / pScriptSigs / pSequences /
-- pWitnesses are parallel comma lists (outpoint hex; scriptSig hex, "" for
-- none; sequence integer; a pre-serialized witness stack hex from cxBtcWitness,
-- "" for none). pOutputs is a comma list of serialized-output hex. If any
-- witness is non-empty the BIP-141 marker+flag and witness section are emitted.
-- Returns the raw transaction as Data.
function cxBtcTxEncode pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcTxEncodeInner(pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcTxEncode

private function cxBtcTxEncodeInner pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses, pOutputs, pLocktime
   local tCount, tI, tBuf, tHasWitness, tSig, tWitBytes
   put the number of items of pOutpoints into tCount
   if tCount is 0 then
      throw "CoinXT: cxBtcTxEncode: a transaction needs at least one input."
   end if
   -- Every list is read BY INDEX below (item 1..tCount), so a missing entry
   -- reads as empty: for a scriptSig that means "no scriptSig", for a witness
   -- "no witness" - the correct meaning, not an error. That read-by-index is
   -- FORCED by the engine's chunk rule, and getting it wrong was a real bug the
   -- headless gate caught before the engine did: the engine ignores ONE trailing
   -- delimiter when it counts items, so a list whose LAST input is empty
   -- ("<sig>," for [sig, ""], the common legacy-then-segwit shape) counts as
   -- tCount-1 and is INDISTINGUISHABLE from a genuinely short list. A strict
   -- "items == tCount" check therefore REFUSED the BIP-143 reference transaction
   -- outright. The count can only catch a list that is too LONG (extra entries
   -- serialization would silently drop); a short one is read as trailing empties.
   -- Sequences are the exception and stay strict: an input always carries one and
   -- it is never empty, so that list is a reliable one-per-input cross-check.
   if the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcTxEncode: the sequence list must have one entry per input."
   end if
   if the number of items of pScriptSigs > tCount then
      throw "CoinXT: cxBtcTxEncode: the scriptSig list has more entries than there are inputs."
   end if
   if pWitnesses is not "" and the number of items of pWitnesses > tCount then
      throw "CoinXT: cxBtcTxEncode: the witness list has more entries than there are inputs."
   end if
   put false into tHasWitness
   if pWitnesses is not "" then
      repeat with tI = 1 to tCount
         if item tI of pWitnesses is not "" then
            put true into tHasWitness
         end if
      end repeat
   end if
   put cxBtcTxBody(pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, tHasWitness) into tBuf
   if tHasWitness then
      repeat with tI = 1 to tCount
         put item tI of pWitnesses into tWitBytes
         if tWitBytes is "" then
            put tBuf & cxVarInt(0) into tBuf
         else
            put tBuf & cxHexDecode(tWitBytes) into tBuf
         end if
      end repeat
      -- The witness section sits before nLockTime, so append the locktime last.
      put tBuf & cxUIntToBytesLE(pLocktime, 4) into tBuf
   end if
   return tBuf
end cxBtcTxEncodeInner

-- The transaction body WITHOUT the witness section and (when pWithMarker)
-- without the trailing locktime, since a SegWit serialization inserts the
-- witnesses between the outputs and the locktime. This is also exactly the
-- preimage a txid hashes (marker off, locktime included), so cxBtcTxid reuses
-- it. Assumes the itemDelimiter is already comma (its callers set it).
private function cxBtcTxBody pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, pWithMarker
   local tCount, tI, tBuf, tSig, tOutBytes
   put the number of items of pOutpoints into tCount
   put cxUIntToBytesLE(pVersion, 4) into tBuf
   if pWithMarker then
      put tBuf & numToByte(0) & numToByte(1) into tBuf
   end if
   put tBuf & cxVarInt(tCount) into tBuf
   repeat with tI = 1 to tCount
      put tBuf & cxHexDecode(item tI of pOutpoints) into tBuf
      if item tI of pScriptSigs is "" then
         put tBuf & cxVarInt(0) into tBuf
      else
         put cxHexDecode(item tI of pScriptSigs) into tSig
         put tBuf & cxVarInt(the number of bytes of tSig) & tSig into tBuf
      end if
      put tBuf & cxUIntToBytesLE(item tI of pSequences, 4) into tBuf
   end repeat
   put "" into tOutBytes
   repeat with tI = 1 to the number of items of pOutputs
      put tOutBytes & cxHexDecode(item tI of pOutputs) into tOutBytes
   end repeat
   put tBuf & cxVarInt(the number of items of pOutputs) & tOutBytes into tBuf
   if not pWithMarker then
      put tBuf & cxUIntToBytesLE(pLocktime, 4) into tBuf
   end if
   return tBuf
end cxBtcTxBody

-- The transaction id as display-order (big-endian) hex: hash256 of the
-- non-witness serialization (BIP-141), byte-reversed for display. Same input
-- lists as cxBtcTxEncode minus the witnesses.
function cxBtcTxid pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxHexEncode(cxReverseBytes(cxHash256(cxBtcTxBody(pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime, false)))) into tResult
   catch tError
      put true into tFailed
      put tError into tFailure
   end try
   set the itemDelimiter to tSavedDelim
   if tFailed then
      throw tFailure
   end if
   return tResult
end cxBtcTxid

-- ---- Ethereum ----------------------------------------------------------------
--
-- Wei-scale fields (pGasPriceHex, pValueHex, pMaxPriorityHex, pMaxFeeHex) cross
-- as minimal-or-padded big-endian HEX; the small counters (pNonce, pGas,
-- pChainId, pRecid) cross as integers. pToHex is the 20-byte recipient as hex
-- ("" for a contract creation); pDataHex is the calldata as hex.

-- The EIP-155 legacy signing digest: keccak(rlp([nonce, gasPrice, gas, to,
-- value, data, chainId, 0, 0])). Hand the result to cxSignRecoverable.
function cxEthLegacySighash pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex, pChainId
   local tBody
   put cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pGasPriceHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pChainId)) into tBody
   put tBody & cxRlpEncodeBytes("") & cxRlpEncodeBytes("") into tBody
   return cxKeccak256(cxRlpEncodeList(tBody))
end cxEthLegacySighash

-- Assemble the signed EIP-155 legacy transaction from the recovery id and the
-- compact (r, s) cxSignRecoverable produced (pass its first 32 bytes as pRHex
-- and next 32 as pSHex, or the whole 64 via cxDerEncode's inputs). v is
-- pRecid + 2*pChainId + 35. Returns an array: ["raw"] the signed tx hex,
-- ["txhash"] the keccak transaction hash hex.
function cxEthLegacyEncode pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex, pChainId, pRecid, pRHex, pSHex
   local tBody, tRaw, tResult, tV
   put pRecid + 2 * pChainId + 35 into tV
   put cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pGasPriceHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(tV)) into tBody
   put tBody & cxRlpUintFromHex(pRHex) & cxRlpUintFromHex(pSHex) into tBody
   put cxRlpEncodeList(tBody) into tRaw
   put cxHexEncode(tRaw) into tResult["raw"]
   put cxHexEncode(cxKeccak256(tRaw)) into tResult["txhash"]
   return tResult
end cxEthLegacyEncode

-- The EIP-1559 (type 0x02) signing digest: keccak(0x02 || rlp([chainId, nonce,
-- maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList])).
-- The access list is the empty list in this build.
function cxEth1559Sighash pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex
   local tBody
   put cxEth1559Body(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex) into tBody
   return cxKeccak256(numToByte(2) & cxRlpEncodeList(tBody))
end cxEth1559Sighash

private function cxEth1559Body pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex
   local tBody
   put cxRlpUintFromHex(cxHexOfInt(pChainId)) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pNonce)) into tBody
   put tBody & cxRlpUintFromHex(pMaxPriorityHex) into tBody
   put tBody & cxRlpUintFromHex(pMaxFeeHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pGas)) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pToHex)) into tBody
   put tBody & cxRlpUintFromHex(pValueHex) into tBody
   put tBody & cxRlpEncodeBytes(cxHexDecode(pDataHex)) into tBody
   -- The access list is an empty RLP list.
   put tBody & cxRlpEncodeList("") into tBody
   return tBody
end cxEth1559Body

-- Assemble the signed EIP-1559 transaction. pRecid is the y-parity (0 or 1), the
-- 1559 signature's v; pRHex / pSHex are the compact r and s. Returns an array:
-- ["raw"] the 0x02-prefixed tx hex, ["txhash"] the keccak transaction hash hex.
function cxEth1559Encode pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex, pRecid, pRHex, pSHex
   local tBody, tRaw, tResult
   put cxEth1559Body(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex, pValueHex, pDataHex) into tBody
   put tBody & cxRlpUintFromHex(cxHexOfInt(pRecid)) into tBody
   put tBody & cxRlpUintFromHex(pRHex) & cxRlpUintFromHex(pSHex) into tBody
   put numToByte(2) & cxRlpEncodeList(tBody) into tRaw
   put cxHexEncode(tRaw) into tResult["raw"]
   put cxHexEncode(cxKeccak256(tRaw)) into tResult["txhash"]
   return tResult
end cxEth1559Encode

-- A small non-negative integer to big-endian hex (an even number of hex chars),
-- for feeding an integer counter through the hex-uint RLP path. Stays inside
-- exact-integer range by construction (its callers pass nonce/gas/chainId/v).
private function cxHexOfInt pValue
   local tHex
   if pValue < 0 then
      throw "CoinXT: cxHexOfInt: the value must not be negative."
   end if
   if pValue is 0 then
      return ""
   end if
   put cxHexEncode(cxUIntToBytes(pValue)) into tHex
   return tHex
end cxHexOfInt

-- <<< END EMBEDDED LIBRARIES <<<

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
-- 2G, for the same reason: it is the curve's own second point, so the two tweak
-- entry points can be pinned to a published answer rather than only to each
-- other. 1 + 1 = 2 is the smallest case of the homomorphism BIP-32 rests on.
constant kPubTwoCompressed = "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

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
-- SHA-256(SHA-256("abc")). hash256 is the function Base58Check's four-byte tail
-- IS, so pinning it directly turns "the address round-trips" into "the address
-- round-trips AND the checksum is the one Bitcoin specifies", which a
-- self-consistent encoder/decoder pair cannot tell you on its own.
constant kHash256Abc = "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358"
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

-- ---- WIF (wallet import format) ----------------------------------------------
-- The Bitcoin wiki's worked-example private key, the same page the Base58Check
-- worked example above comes from. It is a published, burned test key, safe to
-- commit (the KAT rule: public test-vector keys only). The mainnet/uncompressed
-- string is the wiki's own; the compressed and testnet forms are derived by
-- tools/coin_reference.py, whose import self-check anchors the derivation to
-- the published string - all three are re-derived by check-selftest-vectors.py.
constant kWifSeckey = "0c28fca386c7a227600b2fe50b7cae11ec86d3bf1fbe471be89827e19d72aa1d"
constant kWifUncompressed = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
constant kWifCompressed = "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"
constant kWifTestnet = "cMzLdeGd5vEqxB8B6VFQoRopQ3sLAAvEzDAoQgvX54xwofSWj1fx"
-- kWifUncompressed with its final character changed, so the checksum must
-- refuse it (checked genuinely corrupt by the gate, the kBase58Corrupt rule).
constant kWifBadChecksum = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTk"

-- ---- the fail-closed regression set ------------------------------------------
-- One constant per defect an adversarial review found in the shipped script
-- layer. Every one of them FAILED OPEN - a wrong answer that looked like a right
-- one - and every one of them slipped past a vector set that only ever fed the
-- handlers well-formed input. That is the lesson worth carrying: a positive
-- vector cannot catch a check that is not being made.

-- kEip55A with one letter's case corrupted, and with every letter's case
-- flipped. cxEthAddressIsChecksummed used to answer true to both, because it
-- compared a value against itself.
constant kEip55Corrupt = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"
constant kEip55Flipped = "0x5AaEB6053f3e94c9B9a09F33669435e7eF1bEaEd"
-- A REAL bech32m v1 address whose 32-byte witness program begins with the bytes
-- 45 52 52 4F 52. The decoder used to signal its own failure with the string
-- "ERROR" in place of the bytes, so it rejected this address as malformed - an
-- address this very file's encoder produces.
constant kSegwitErrorProgram = "4552524f52000102030405060708090a0b0c0d0e0f101112131415161718191a"
constant kSegwitErrorAddress = "bc1pg4f9yn6jqqqsyqcyq5rqwzqfpg9scrgwpugpzysnzs23v9ccrydqqwyhrw"

-- ---- HD wallets and mnemonics (phase 4) --------------------------------------
-- Every value below is PUBLISHED. That matters more here than anywhere else in
-- this file, because phase 4 is the only surface that can be wrong WITHOUT
-- FAILING: a mis-packed mnemonic is still twelve English words and a
-- mis-derived path is still a valid address. Nothing tells the user until the
-- funds are somewhere they cannot reach.

-- The all-zero entropy vector, and the 24-word all-ones one, from BIP-39's own
-- english test set. kBip39Mnemonic above is the 12-word one.
constant kBip39Entropy12 = "00000000000000000000000000000000"
constant kBip39Entropy24 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
constant kBip39Mnemonic24 = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
-- The same 12 words with NO passphrase. kBip39Seed above is the same mnemonic
-- with "TREZOR", so the pair also proves the passphrase reaches the KDF.
constant kBip39SeedNoPass = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
-- The same mnemonic with one word replaced, so the checksum must reject it.
constant kBip39Mnemonic12Bad = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon"

-- BIP-32 test vector 1: seed 000102...0f, and three levels of its published
-- chain. The last one is five levels deep and mixes hardened with normal.
constant kBip32Seed1 = "000102030405060708090a0b0c0d0e0f"
constant kBip32V1Xprv = "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
constant kBip32V1Xpub = "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
constant kBip32V1H0Xprv = "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7"
constant kBip32V1H0Xpub = "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
constant kBip32V1DeepPath = "m/0'/1/2'/2/1000000000"
constant kBip32V1DeepXprv = "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76"
-- BIP-32 test vector 3 exists SOLELY because its master private key has a
-- leading zero byte, the case a "strip leading zeros" bignum bug gets wrong.
constant kBip32Seed3 = "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
constant kBip32V3Xprv = "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6"

-- The end-to-end claim: the test mnemonic every wallet ships with, walked down
-- BIP-44 and BIP-84 paths to the addresses those wallets show.
constant kAbandonXprv = "xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu"
constant kAbandonBip44 = "m/44'/0'/0'/0/0"
constant kAbandonP2pkh = "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
constant kAbandonBip84 = "m/84'/0'/0'/0/0"
constant kAbandonP2wpkh = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
constant kAbandonBip84Account = "m/84'/0'/0'"
constant kAbandonBip84Xpub = "xpub6CatWdiZiodmUeTDp8LT5or8nmbKNcuyvz7WyksVFkKB4RHwCD3XyuvPEbvqAQY3rAPshWcMLoP2fMFMKHPJ4ZeZXYVUhLv1VMrjPC7PW6V"
constant kAbandonEthPath = "m/44'/60'/0'/0/0"
constant kAbandonEth = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"

-- Phase 5. Transaction building and signing. The Bitcoin case IS the BIP-143
-- native-P2WPKH worked example: a two-input transaction that exercises BOTH a
-- legacy SIGHASH_ALL preimage (input 0, a P2PK spend) and a BIP-143 segwit
-- preimage (input 1, P2WPKH), reproduced byte-for-byte including its witness.
-- The Ethereum cases are the EIP-155 specification's own example and a
-- self-consistent EIP-1559 typed transaction. All the "expected" constants are
-- re-derived from tools/coin_reference.py by check-selftest-vectors.py; the
-- inputs are the published fixtures.
constant kTxSeckey0 = "bbc27228ddcb9209d7fd6f36b02f7dfa6252af40bb2f1cbc7a557da8027ff866"
constant kTxSeckey1 = "619c335025c7f4012e556c2a58b2506e30b8511b53ade95ea316fd8c3286feb9"
constant kTxPubkey1 = "025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant kTxid0 = "9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff"
constant kTxid1 = "8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef"
constant kTxScriptCode0 = "2103c9f4836b9a4f77fc0d81f7bcb01b7f1b35916864b9476c241ce9fc198bd25432ac"
constant kTxScriptCode1 = "76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac"
constant kTxOutScript0 = "76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant kTxOutScript1 = "76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant kTxOutpoint0 = "fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000"
constant kTxOutpoint1 = "ef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a01000000"
constant kTxOut0 = "202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac"
constant kTxOut1 = "9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac"
constant kTxLegacySighash = "63cec688ee06a91e913875356dd4dea2f8e0f2a2659885372da2a37e32c7532e"
constant kTxSegwitSighash = "c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670"
constant kTxScriptSig0 = "4830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01"
constant kTxWitness1 = "0247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee6357"
constant kTxSignedRaw = "01000000000102fff7f7881a8099afa6940d42d1e7f6362bec38171ea3edf433541db4e4ad969f00000000494830450221008b9d1dc26ba6a9cb62127b02742fa9d754cd3bebf337f7a55d114c8e5cdd30be022040529b194ba3f9281a99f2b1c0a19c0489bc22ede944ccf4ecbab4cc618ef3ed01eeffffffef51e1b804cc89d182d279655c3aa89e815b1b309fe287d9b2b55d57b90ec68a0100000000ffffffff02202cb206000000001976a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac9093510d000000001976a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac000247304402203609e17b84f6a7d30c80bfa610b5b4542f32a8a0d5447a12fb1366d7f01cc44a0220573a954c4518331561406f90300e8f3358f51928d43c212a8caed02de67eebee0121025476c2e83188368da1ff3e292e7acafcdb3566bb0ad253f62fc70f07aeee635711000000"
constant kTxTxid = "e8151a2af31c368a35053ddd4bdb285a8595c769a3ad83e0fa02314a602d4609"

-- BIP-341 (2026-08-23). The tree pieces are the PUBLISHED wallet-test-vectors
-- values (scriptPubKey vector with the two-leaf tree; the 0xfa leaf version is
-- the vectors' own unusual-but-legal case); the two sighashes are DERIVED by
-- tools/coin_reference.py over a one-input transaction reusing kTxid0/kTxOut0,
-- because the published keyPathSpending tx is nine inputs of fixture - the
-- FULL published sweep (all 7 inputs, all 6 trees, all 12 control blocks) is
-- executed on every build by tools/check-script-vectors.py, and this section
-- pins one engine-checkable case per handler on top of it.
constant kTapInternal = "ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592"
constant kTapLeafScript0 = "20387671353e273264c495656e27e39ba899ea8fee3bb69fb2a680e22093447d48ac"
constant kTapLeafScript1 = "06424950333431"
constant kTapLeafHash0 = "8ad69ec7cf41c2a4001fd1f738bf1e505ce2277acdcaa63fe4765192497f47a7"
constant kTapLeafHash1 = "f224a923cd0021ab202ab139cc56802ddb92dcfc172b9212261a539df79a112a"
constant kTapMerkleRoot = "6c2dc106ab816b73f9d07e3cd1ef2c8c1256f519748e0813e4edd2405d277bef"
constant kTapControlBlock0 = "c0ee4fe085983462a184015d1f782d6a5f8b9c2b60130aff050ce221ecf3786592f224a923cd0021ab202ab139cc56802ddb92dcfc172b9212261a539df79a112a"
constant kTapSpk = "5120712447206d7a5238acc7ff53fbe94a3b64539ad291c7cdbc490b7577e4b17df5"
constant kTapSighashKeyPath = "b381cd222933416aa1b7b8854446926452ee7f2407f9d0a9fba0c924a8e0f3ac"
constant kTapSighashScriptPath = "51f1c8afa1e5ad26f0f97c23ada20a4dfd88afaa75ba4b0e478fe9424837a4fb"
constant kEthSeckey = "4646464646464646464646464646464646464646464646464646464646464646"
constant kEthTo = "3535353535353535353535353535353535353535"
constant kEthGasPrice = "04a817c800"
constant kEthValue = "0de0b6b3a7640000"
constant kEthLegacySighash = "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53"
constant kEthLegacyRaw = "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
constant kEthLegacyTxhash = "33469b22e9f636356c4160a87eb19df52b7412e8eac32a4a55ffe88ea8350788"
constant kEth1559MaxPrio = "3b9aca00"
constant kEth1559MaxFee = "04a817c800"
constant kEth1559Value = "016345785d8a0000"
constant kEth1559Sighash = "bf4c3dfa4164868c98534322ecbbce3c022d6d0dee3580b1504da0a28fff9199"
constant kEth1559Raw = "02f8730180843b9aca008504a817c80082520894353535353535353535353535353535353535353588016345785d8a000080c001a0180a63d9ea767ab51941f4cb5d3f4f1113ae08861b4a660eb72770967ddc8987a04a41c8877f4e53a06c3a7d6f2787f113d9700bd112168f6714ff3b8957f1b123"
constant kEth1559Txhash = "1d723f02967119095427907564da7762bd6d3a5d8edb1291db53b97191749e7f"

-- ---- BIP-340 Schnorr and BIP-341 Taproot (ABI 6) -----------------------------
-- Every value here is PUBLISHED, and both specifications publish the negatives
-- as well as the positives - which is the whole reason a Schnorr vector file
-- exists. An implementation that only ever meets good signatures passes every
-- positive case while happily accepting a forged one.
--   BIP-340: https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
--   BIP-341: https://github.com/bitcoin/bips/blob/master/bip-0341/wallet-test-vectors.json
-- The full 19-case BIP-340 set and the full 14-case BIP-341 set run headlessly
-- in tools/coin-kat.py; this file carries the subset that a human pasting one
-- stack into OXT should see, chosen so every new handler is called by name and
-- both a positive and a negative reach each one.

-- BIP-340 test vector 1 (a nonzero key, message and aux, so no field is
-- accidentally right because it was zero).
constant kSchnorrSk1 = "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef"
constant kSchnorrPub1 = "dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659"
constant kSchnorrAux1 = "0000000000000000000000000000000000000000000000000000000000000001"
constant kSchnorrMsg1 = "243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89"
constant kSchnorrSig1 = "6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de33418906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a"
-- BIP-340 vector 5's public key: 32 bytes that are NOT the X coordinate of any
-- point on the curve. Its expected verification result is FALSE, not an error,
-- and that distinction is the reason this constant is here.
constant kSchnorrPubOffCurve = "eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34"
-- BIP-340 vector 6's signature: well formed, over the right message and key,
-- and invalid because has_even_y(R) is false. A verifier that skipped that one
-- rule would accept it.
constant kSchnorrSigOddR = "fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a14602975563cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2"

-- BIP-341 scriptPubKey vector 0 and keyPathSpending input 0: the KEY-PATH-ONLY
-- case, where the merkle root is the specification's EMPTY BYTE STRING. This is
-- the shape a single-signature wallet actually uses, and the one that separates
-- a correct implementation from one that hashes 32 zero bytes instead.
constant kTapSeckey0 = "6b973d88838f27366ed61c9ad6367663045cb456e28335c109e30717ae0c6baa"
constant kTapInternal0 = "d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d"
constant kTapOutput0 = "53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343"
constant kTapTweaked0 = "2405b971772ad26915c8dcdf10f238753a9b837e5f8e6a86fd7c0cce5b7296d9"
constant kTapAddress0 = "bc1p2wsldez5mud2yam29q22wgfh9439spgduvct83k3pm50fcxa5dps59h4z5"
-- BIP-341 scriptPubKey vector 1: the same operation WITH a script-tree root, so
-- the two branches of the tagged hash (32 bytes of input versus 64) are both
-- exercised by a published answer.
constant kTapInternal1 = "187791b6f712a8ea41c8ecdd0ee77fab3e85263b37e1ec18a3651926b3a6cf27"
constant kTapRoot1 = "5b75adecf53548f3ec6ad7d78383bf84cc57b55a3127c72b9a2481752dd88b21"
constant kTapOutput1 = "147c9c57132f6e7ecddba9800bb0c4449251c92a1e60371ee77557b6620f3ea3"
constant kTapAddress1 = "bc1pz37fc4cn9ah8anwm4xqqhvxygjf9rjf2resrw8h8w4tmvcs0863sa2e586"

constant kStTitle = "coinxt - API Self-Test"
constant kStWidth = 660
constant kStHeight = 620

-- ---- state -------------------------------------------------------------------

-- ---- the scaffolding (carried) ----------------------------------------------
-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: tools/harness-scaffold.livecodescript; gate: tools/check-harness-scaffold-drift.py) ====
-- The harness scaffolding as one carried block: counters, the window, the
-- assertion plumbing, the report surface. The adopting harness declares
-- kStTitle/kStWidth/kStHeight above this block, owns openStack/stRun/
-- stCleanup, calls stResetCounters first in stRun and stReportDone when
-- the run completes. Do not edit this block in place: change the master
-- and re-carry it.
local sTotal, sPassed, sFailed, sSkipped
local sResultText          -- the accumulated PASS/FAIL/SKIP/section lines
local sStRunDone           -- "true" once the run finished (drives the color)

-- The platform's own terminal face (the demo kit's uiMonoFont, by value).
function stMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end stMonoFont

-- ---- the window (idempotent; the fold drops this half) -----------------------
command stBuild
   -- the guard is on a control this VERSION of the scaffold adds, so a stack
   -- built by an older scaffold rebuilds once and picks up the new layout
   -- (the builders re-rect existing controls by name; nothing needs deleting)
   if there is a button "stCopy" then
      exit stBuild
   end if
   lock screen
   set the width of this stack to kStWidth
   set the height of this stack to kStHeight
   set the backgroundColor of this card to "240,242,246"
   set the title of this stack to kStTitle
   stMakeLabel "stTitle", "  " & kStTitle, "0,0," & kStWidth & ",30", 15
   set the opaque of field "stTitle" to true
   set the backgroundColor of field "stTitle" to "44,90,160"
   set the foregroundColor of field "stTitle" to "255,255,255"
   set the textStyle of field "stTitle" to "bold"
   stMakeLabel "stSummary", "Running...", "16,38," & (kStWidth - 200) & ",66", 13
   set the textStyle of field "stSummary" to "bold"
   stMakeButton "stCopy", "Copy results", (kStWidth - 184) & ",38," & (kStWidth - 100) & ",64"
   stMakeButton "stRerun", "Re-run", (kStWidth - 94) & ",38," & (kStWidth - 16) & ",64"
   stMakeList "stResults", "16,72," & (kStWidth - 16) & "," & (kStHeight - 16)
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
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to "225,229,236"
   set the opaque of field pName to true
   set the backgroundColor of field pName to "255,255,255"
   set the textSize of field pName to 11
   set the textFont of field pName to stMonoFont()
end stMakeList

-- ---- assertion plumbing (this half folds into the suite harness) -------------
command stResetCounters
   put 0 into sTotal
   put 0 into sPassed
   put 0 into sFailed
   put 0 into sSkipped
   put empty into sResultText
   put empty into sStRunDone
end stResetCounters

command stAssert pName, pOk
   add 1 to sTotal
   if pOk then
      add 1 to sPassed
      put "PASS  " & pName & return after sResultText
   else
      add 1 to sFailed
      put "FAIL  " & pName & return after sResultText
   end if
end stAssert

-- A SKIP is a first-class outcome, not a silent gap: it counts, it names
-- itself, and it says what would make it run.
command stSkip pName, pReason
   add 1 to sTotal
   add 1 to sSkipped
   put "SKIP  " & pName & "  (" & pReason & ")" & return after sResultText
end stSkip

command stSection pTitle
   put return & "== " & pTitle & " ==" & return after sResultText
end stSection

-- A section that threw is a FAIL, never a skip: a skip means "this piece is
-- not here", and something that blew up very much is.
command stSectionFailed pWhich, pError
   stAssert pWhich & " section ran to completion", false
   stNote "it raised:" && pError
   stNote "the other sections still ran; this one is a defect to report"
end stSectionFailed

command stNote pText
   put "      " & pText & return after sResultText
end stNote

-- THE REPORT IS A LIVE SURFACE, so its text is ambiguous by construction:
-- sResultText grows as the run goes, the async harnesses re-render it every
-- tick, and an unfinished report simply STOPS - with no marker, at whatever
-- section the pump had reached. That reads exactly like a hang. It cost a
-- round trip on the 2026-08-19 suite pass: a fully green run came back ending
-- mid-CROSS-section, and nothing in the pasted text could tell an early Copy
-- from a stalled pump. The async deadline is FORTY SECONDS (kStDeadlineMs in
-- the suite core), and the list stops visibly growing long before it expires,
-- so "it looks finished" is the normal state of a run that is not. Every
-- render of the report goes through here, so that state can never be silent
-- again - on screen or on the clipboard.
function stReportText
   if sStRunDone is "true" then
      return sResultText
   end if
   return sResultText \
         & "      ----------------------------------------------------" & return \
         & "      RUN NOT FINISHED - this is NOT the end of the report." & return \
         & "      An async section is still running. Wait for the SUMMARY" & return \
         & "      section at the bottom, then Copy." & return
end stReportText

command stShow
   -- PIN THE STACK, AND FAIL CLOSED IF THE WINDOW IS NOT THERE. An unqualified
   -- `field "stResults"` resolves against THE DEFAULTSTACK, not against the
   -- stack whose script is running (OXT-ENGINE-NOTES 5.3). Inside openStack
   -- those are the same object, which is why the synchronous half of every run
   -- has always rendered. This handler is ALSO called from an async pump, on a
   -- `send ... in` tick, where they are not: with another window in front the
   -- write would throw "Chunk: error in object expression", and in the suite
   -- core that throw lands in stPump, which is where the timer re-arms.
   -- PRECAUTIONARY, NOT DIAGNOSED. It was written on 2026-08-20 while chasing
   -- two engine reports that ended mid-CROSS-section, and that was the wrong
   -- cause: the third run, same build, completed 1981/0/1 through both
   -- loopbacks and the summary. Those two were early Copies, which is what the
   -- trailer in stReportText now says out loud. What stands on its own is the
   -- hazard class - engine-observed in enet-lan-chat's ecDashOnce on
   -- 2026-08-18 - and the fact that this is the same fault, and the same fix,
   -- as the ui-kit's uiStatus, one carried block over.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stShow
   put stReportText() into field "stResults"
   put sPassed & " passed, " & sFailed & " failed, " & sSkipped & " skipped, " \
         & sTotal & " total" into field "stSummary"
   if sStRunDone is "true" then
      if sFailed is 0 then
         set the foregroundColor of field "stSummary" to "23,128,63"
      else
         set the foregroundColor of field "stSummary" to "176,58,46"
      end if
   end if
end stShow

-- paint the results list: red FAIL, green PASS, amber SKIP, muted the rest
command stPaint
   local tN, tI, tLine, tErr
   -- Pinned for the reason stShow above is: stReportDone calls this one too,
   -- and an async harness reaches stReportDone from a timer tick.
   set the defaultStack to the short name of this stack
   if there is no field "stResults" then exit stPaint
   put the number of lines of field "stResults" into tN
   lock screen
   try
      repeat with tI = 1 to tN
         put line tI of field "stResults" into tLine
         if tLine begins with "FAIL" then
            set the foregroundColor of line tI of field "stResults" to "176,58,46"
         else if tLine begins with "PASS" then
            set the foregroundColor of line tI of field "stResults" to "23,128,63"
         else if tLine begins with "SKIP" then
            set the foregroundColor of line tI of field "stResults" to "150,110,40"
         else
            set the foregroundColor of line tI of field "stResults" to "138,146,158"
         end if
      end repeat
   catch tErr
   end try
   set the vScroll of field "stResults" to 0
   unlock screen
end stPaint

-- The run's one epilogue: mark done, render, paint. Synchronous harnesses
-- call this at the end of stRun; async ones from the tick that ends the run.
command stReportDone
   put "true" into sStRunDone
   stShow
   stPaint
end stReportDone

command stCopyResults
   -- The whole point of the button: the maintainer pastes the run back
   -- verbatim into the OXT-pass record, so nobody has to retype a result.
   -- It copies stReportText(), not sResultText, so an early copy carries its
   -- own "not finished" trailer into the record - and says so here too,
   -- because the one moment a maintainer is looking at this window is the
   -- moment the dialog appears.
   --
   -- The COUNTS ride along, ahead of the lines. They live in their own field
   -- (stSummary) and used to be left behind, so the runbook taught a message
   -- box incantation to fetch them by hand - one more step between a finished
   -- run and a recorded one, at the exact moment the operator is done. A
   -- report with no totals cannot be checked against the next run's.
   local tError
   try
      set the clipboardData["text"] to sPassed & " passed, " & sFailed \
            & " failed, " & sSkipped & " skipped, " & sTotal & " total" \
            & return & return & stReportText()
      if sStRunDone is "true" then
         answer "Results copied to the clipboard."
      else
         answer "Copied - but the run has NOT finished. An async section is" \
               && "still going; wait for the SUMMARY section, then copy again."
      end if
   catch tError
      answer "Could not reach the clipboard:" && tError
   end try
end stCopyResults

on closeStack
   stCleanup
end closeStack

on mouseUp
   if the short name of the target is "stRerun" then
      stCleanup
      stRun
   else if the short name of the target is "stCopy" then
      stCopyResults
   else
      pass mouseUp
   end if
end mouseUp
-- ==== SUITE HARNESS SCAFFOLD v1 END ====

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   stBuild
   stRun
end openStack











-- Nothing to release: coinxt is stateless (no sessions, no sockets, no
-- handles). The scaffold's Re-run button and closeStack call this all the
-- same, so it exists and says why it is empty.
command stCleanup
end stCleanup

-- ---- the run -----------------------------------------------------------------
command stRun
   stResetCounters
   -- Byte-exact compares, and hex strings that must not fold case.
   set the caseSensitive to true

   put "CoinXT API self-test" & return into sResultText
   put "Phases 1-5: the .lcb module and the script layer, end to end." & return after sResultText

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
   stRunWif
   stRunBip39
   stRunBip32
   stRunBip44
   stRunTransactions
   stRunTaproot341
   stRunSchnorr
   stRunTaproot
   stRunFailOpen

   stSection "summary"
   stNote "Vectors are identical to tools/coin-kat.py, so this run and the"
   stNote "headless KAT run are the same claim at two different layers."
   stNote "Phase 4 is the section to read first if anything failed: it is the"
   stNote "only surface where a wrong answer still looks like a right one."
   stReportDone
end stRun

-- The ABI guard, called BY NAME at last. cxCheckABI is `returns nothing` and
-- throws on skew, so silence is the pass; there is no value to inspect.
command stRunAbi
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tPubC, tPubU, tTweaked
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
      -- The two ABI-4 tweak entry points. BIP-32 non-hardened derivation is
      -- built on the claim that tweaking the PRIVATE key and tweaking the
      -- PUBLIC key land on the same point; if they ever disagreed, an xpub
      -- watch-only wallet would generate addresses the xprv cannot spend, and
      -- nothing above this line would notice. 1 + 1 = 2 pins both to the
      -- curve's own second point rather than only to each other.
      put cxSeckeyTweakAdd(tSk, tSk) into tTweaked
      stAssert "cxSeckeyTweakAdd of 1 by 1 is the scalar 2", stHex(tTweaked) is stHex(stRepeatByte(0, 31) & numToByte(2))
      stAssert "and its public key is 2G", stHex(cxPublicKey(tTweaked, true)) is kPubTwoCompressed
      stAssert "cxPubkeyTweakAdd of G by 1 is also 2G", stHex(cxPubkeyTweakAdd(tPubC, tSk)) is kPubTwoCompressed
      stAssert "so private and public tweaking agree", stHex(cxPubkeyTweakAdd(tPubC, tSk)) is stHex(cxPublicKey(cxSeckeyTweakAdd(tSk, tSk), true))
      -- Both refuse a ZERO tweak, where upstream's public entry point accepts
      -- it. Accepting on one path and refusing on the other is the
      -- interoperability bug this member exists to prevent, so the symmetry is
      -- asserted rather than assumed.
      stAssert "a zero tweak is refused on the private path", stThrows2("cxSeckeyTweakAdd", tSk, stRepeatByte(0, 32))
      stAssert "a zero tweak is refused on the public path", stThrows2("cxPubkeyTweakAdd", tPubC, stRepeatByte(0, 32))
      stAssert "a wrong-length tweak is refused", stThrows2("cxSeckeyTweakAdd", tSk, stRepeatByte(1, 31))
   catch tError
      stSectionFailed "secp256k1 keys", tError
   end try
end stRunCurveKeys

command stRunCurveSign
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tPayload, tI, tPadded
   stSection "Base58Check"
   try
      put cxHexDecode(kBase58Payload) into tPayload
      -- hash256 first, on its own. It is the checksum function this encoding is
      -- defined in terms of, and an encoder/decoder pair that agreed with each
      -- other while both used the wrong hash would pass every round-trip below.
      stAssert "cxHash256 of abc is the published double-SHA-256", stHex(cxHash256(stText("abc"))) is kHash256Abc
      stAssert "cxHash256 is 32 bytes", the number of bytes of cxHash256(stText("")) is 32
      stAssert "and it is genuinely SHA-256 applied twice", stHex(cxHash256(stText("abc"))) is stHex(cxSha256(cxSha256(stText("abc"))))
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
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

command stRunWif
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   -- tThrew went with the two hand-rolled try blocks the refusals below used
   -- to need; stThrowsText3 carries that state now.
   local tDecoded
   stSection "WIF (wallet import format)"
   try
      -- The mainnet/uncompressed answer IS the Bitcoin wiki's published worked
      -- example; the other forms are oracle-derived (see the constants block).
      stAssert "encodes the wiki worked example (mainnet, uncompressed)", cxWifEncode(kWifSeckey, "mainnet", false) is kWifUncompressed
      stAssert "the compressed form is the same key with the 0x01 marker", cxWifEncode(kWifSeckey, "mainnet", true) is kWifCompressed
      stAssert "the testnet form differs only in its version byte", cxWifEncode(kWifSeckey, "testnet", true) is kWifTestnet
      -- The three encodings must be three different strings, or the network
      -- and the flag are not reaching the payload at all.
      stAssert "compressed and uncompressed forms are distinct", kWifCompressed is not kWifUncompressed
      stAssert "mainnet and testnet forms are distinct", kWifTestnet is not kWifCompressed
      put cxWifDecode(kWifCompressed) into tDecoded
      stAssert "decodes back to the same key", tDecoded["seckey"] is kWifSeckey
      stAssert "and reports mainnet", tDecoded["network"] is "mainnet"
      stAssert "and reports the compressed flag", tDecoded["compressed"] is true
      put cxWifDecode(kWifUncompressed) into tDecoded
      stAssert "the uncompressed form reports compressed false", tDecoded["compressed"] is false
      put cxWifDecode(kWifTestnet) into tDecoded
      stAssert "the testnet form reports testnet", tDecoded["network"] is "testnet"
      -- The refusals. A typo in a pasted key must never decode to a plausible
      -- neighbouring wallet, so a refusal is the assertion - but WHICH refusal
      -- is the assertion that has content here, because WIF is four guards
      -- stacked on a Base58Check frame and every one of them throws. Each line
      -- names the handler the message must come from and a phrase unique to
      -- that guard's sentence (see stRefusalNames).
      --
      -- The corrupt-checksum case is the instructive one: it is refused by
      -- cxBase58CheckDecode, one layer BELOW cxWifDecode, which never sees the
      -- string. Naming cxWifDecode here would have been wrong, and the reason
      -- to pin it is the _wrong_spec lesson the Python gate already carries - a
      -- bad checksum masks every later check, so the four WIF-specific guards
      -- can only be reached through payloads whose checksum is VALID. If this
      -- line ever started naming cxWifDecode, the checksum would have stopped
      -- being verified before the payload was read.
      stAssertRefusal "a corrupt checksum is refused, by the Base58Check frame below cxWifDecode", stThrowsText("cxWifDecode", kWifBadChecksum), "cxBase58CheckDecode", "checksum"
      stAssertRefusal "an xprv is refused, on its payload LENGTH and not on its version byte", stThrowsText("cxWifDecode", kBip32V1Xprv), "cxWifDecode", "payload"
      -- These two were hand-rolled try blocks with an undeclared catch
      -- variable each. stThrowsText3 is the same shape as the rest of the
      -- harness, declares its catch variable (checker check 15), and reads the
      -- message, so the three-argument encoder's two distinct refusals can no
      -- longer be satisfied by each other.
      stAssertRefusal "an unknown network is refused, naming the network", stThrowsText3("cxWifEncode", kWifSeckey, "regtest", true), "cxWifEncode", "network"
      stAssertRefusal "a short key is refused, naming the key length", stThrowsText3("cxWifEncode", "deadbeef", "mainnet", true), "cxWifEncode", "64 hex characters"
   catch tError
      stSectionFailed "WIF", tError
   end try
end stRunWif

-- ==============================================================================
-- ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak.
--
-- NEW SURFACE, NO ENGINE PASS YET. These handlers postdate the 2026-08-10 and
-- 2026-08-12 runs. What they owe an engine, specifically: that cxSchnorrSign's
-- THREE-argument shape marshals, that an EMPTY Data in the aux and merkle-root
-- slots reaches the shim as a length of 0 (this is the family's proven "absent"
-- spelling - cxKeccak256("") settled it on 2026-08-08 - but it has never been
-- used for an OPTIONAL argument before), that cxSchnorrVerify's Boolean answers
-- both ways, and that cxTaprootTweak's array return reads back by name.
-- ==============================================================================

command stRunSchnorr
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tSk, tPub, tMsg, tAux, tSig, tFreshA, tFreshB
   stSection "BIP-340 Schnorr (published vectors, positive and negative)"
   try
      put cxHexDecode(kSchnorrSk1) into tSk
      put cxHexDecode(kSchnorrMsg1) into tMsg
      put cxHexDecode(kSchnorrAux1) into tAux
      put cxXOnlyPubkey(tSk) into tPub
      stAssert "cxXOnlyPubkey reproduces BIP-340 vector 1's x-only key", stSameHex(cxHexEncode(tPub), kSchnorrPub1)
      put cxSchnorrSign(tSk, tMsg, tAux) into tSig
      stAssert "cxSchnorrSign reproduces vector 1 byte for byte", stSameHex(cxHexEncode(tSig), kSchnorrSig1)
      stAssert "cxSchnorrVerify accepts it", cxSchnorrVerify(tPub, tMsg, tSig) is true
      -- The negatives. A Schnorr verifier that only ever meets good signatures
      -- passes every positive case above while accepting a forgery.
      stAssert "cxSchnorrVerify rejects a tampered signature", cxSchnorrVerify(tPub, tMsg, stFlipByte(tSig, 40)) is false
      stAssert "cxSchnorrVerify rejects the wrong message", cxSchnorrVerify(tPub, tSk, tSig) is false
      stAssert "cxSchnorrVerify rejects the wrong key", cxSchnorrVerify(cxHexDecode(kTapInternal0), tMsg, tSig) is false
      -- BIP-340 case 5. The expected result is FALSE, not an error: a verifier
      -- that threw here would be unusable on a third party's signature.
      stAssert "a public key that is not on the curve answers false, not an error", cxSchnorrVerify(cxHexDecode(kSchnorrPubOffCurve), tMsg, tSig) is false
      -- BIP-340 case 6: has_even_y(R) is false.
      stAssert "a signature whose R has an odd Y is rejected", cxSchnorrVerify(tPub, tMsg, cxHexDecode(kSchnorrSigOddR)) is false
      -- An ABSENT aux means FRESH randomness, never an all-zero aux. Two calls
      -- must differ, both must verify, and neither may be the pinned vector -
      -- which is what would come back if empty were passed through as a null
      -- and upstream read it as zeros.
      put cxSchnorrSign(tSk, tMsg, empty) into tFreshA
      put cxSchnorrSign(tSk, tMsg, empty) into tFreshB
      stAssert "an absent aux gives two DIFFERENT signatures", not stSameHex(cxHexEncode(tFreshA), cxHexEncode(tFreshB))
      stAssert "and neither one is the zero-aux signature", not stSameHex(cxHexEncode(tFreshA), kSchnorrSig1)
      stAssert "both signatures still verify", cxSchnorrVerify(tPub, tMsg, tFreshA) is true and cxSchnorrVerify(tPub, tMsg, tFreshB) is true
      -- The three new length accessors, called by name.
      stAssert "cxSchnorrSignatureLen is 64", cxSchnorrSignatureLen() is 64
      stAssert "cxXOnlyPubkeyLen is 32", cxXOnlyPubkeyLen() is 32
      stAssert "cxTaprootOutputLen is 33 (key plus a parity byte)", cxTaprootOutputLen() is 33
      -- Fail closed, and in whose words (see stRefusalNames). Neither of these
      -- has a script-layer guard above it, so the message is the .lcb's
      -- sFinish text and the reason it can carry is the shim's generic status
      -- sentence rather than an argument name. That is still the assertion
      -- worth making, because the STATUS is what discriminates: cxSchnorrVerify
      -- is the one handler in the library where a bad SIGNATURE is an answer
      -- (false) and a bad LENGTH is an error, so "it threw" cannot tell a
      -- correct length refusal from the shim having decided the 33 bytes were
      -- an unparseable KEY. The message can, and does.
      stAssertRefusal "cxXOnlyPubkey refuses a 33-byte public key", stThrowsText("cxXOnlyPubkey", cxHexDecode(kPubOneCompressed)), "cxXOnlyPubkey", "a buffer had the wrong length"
      stAssertRefusal "cxSchnorrVerify refuses a 33-byte key as a LENGTH error (a length is a caller bug, not a verdict)", stThrowsText3("cxSchnorrVerify", cxHexDecode(kPubOneCompressed), tMsg, tSig), "cxSchnorrVerify", "a buffer had the wrong length"
   catch tError
      stSectionFailed "BIP-340 Schnorr", tError
   end try
end stRunSchnorr

command stRunTaproot
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tInternal, tTweak, tZeroTweak, tSeckey, tTweaked, tOutKey, tSig, tMsg, tRecord
   stSection "BIP-341 Taproot (published wallet vectors)"
   try
      put cxHexDecode(kTapInternal0) into tInternal
      put cxTaprootTweak(tInternal, empty) into tTweak
      put tTweak["outputKey"] into tOutKey
      stAssert "the key-path-only output key matches BIP-341 vector 0", stSameHex(cxHexEncode(tOutKey), kTapOutput0)
      stAssert "the parity byte is 0 or 1", tTweak["parity"] is 0 or tTweak["parity"] is 1
      -- cxTaprootTweakPubkey is the .lcb handler cxTaprootTweak is a thin
      -- slicer over, and it is public API in its own right. Pin it to the
      -- PUBLISHED key first and only then assert the two agree - the
      -- cxHdDeriveChild lesson: testing only the wrapper cannot separate "the
      -- record is right" from "the record and the slicing are wrong in the
      -- same direction". This also pins the 33-byte layout: 32 bytes of key
      -- then one parity byte, in that order.
      put cxTaprootTweakPubkey(tInternal, empty) into tRecord
      stAssert "cxTaprootTweakPubkey returns a 33-byte record", the number of bytes of tRecord is cxTaprootOutputLen()
      stAssert "its first 32 bytes are the published output key", stSameHex(cxHexEncode(byte 1 to 32 of tRecord), kTapOutput0)
      stAssert "and its last byte is the parity cxTaprootTweak reports", byteToNum(byte 33 of tRecord) is tTweak["parity"]
      stAssert "and the address is BIP-341's published bc1p string", cxBtcAddressP2TRFromInternal(tInternal, empty) is kTapAddress0
      -- The same operation WITH a script tree, so both lengths of tagged-hash
      -- input (32 bytes and 64) have a published answer behind them.
      put cxTaprootTweak(cxHexDecode(kTapInternal1), cxHexDecode(kTapRoot1)) into tTweak
      stAssert "a script-tree root gives vector 1's output key", stSameHex(cxHexEncode(tTweak["outputKey"]), kTapOutput1)
      stAssert "and vector 1's published address", cxBtcAddressP2TRFromInternal(cxHexDecode(kTapInternal1), cxHexDecode(kTapRoot1)) is kTapAddress1
      -- THE CONSENSUS DISTINCTION. An EMPTY merkle root is the specification's
      -- empty byte string; 32 ZERO BYTES is a script commitment to a zero root.
      -- They hash different lengths and must give different output keys. If
      -- these ever agreed, every key-path-only address this library produced
      -- would be wrong, and it would still look like an address.
      put cxTaprootTweak(tInternal, stRepeatByte(0, 32)) into tZeroTweak
      stAssert "an EMPTY merkle root is not a 32-zero root", not stSameHex(cxHexEncode(tZeroTweak["outputKey"]), kTapOutput0)
      -- The private half, and then the loop closed: the tweaked PRIVATE key
      -- must sign for the output key the PUBLIC path derived on its own.
      put cxHexDecode(kTapSeckey0) into tSeckey
      stAssert "the internal key is the x-only key of its private key", stSameHex(cxHexEncode(cxXOnlyPubkey(tSeckey)), kTapInternal0)
      put cxTaprootTweakSeckey(tSeckey, empty) into tTweaked
      stAssert "the tweaked private key matches BIP-341's published value", stSameHex(cxHexEncode(tTweaked), kTapTweaked0)
      put cxHexDecode(kSchnorrMsg1) into tMsg
      put cxSchnorrSign(tTweaked, tMsg, cxHexDecode(kSchnorrAux1)) into tSig
      stAssert "the tweaked private key signs for the tweaked public key", cxSchnorrVerify(tOutKey, tMsg, tSig) is true
      -- cxBtcAddressP2TR is UNCHANGED and must stay so: it encodes the output
      -- key it is given and never tweaks. If a future edit made it tweak, every
      -- existing correct call would silently become a DOUBLE tweak - a
      -- valid-looking address nobody can spend from - so the two handlers
      -- disagreeing on the same 32 bytes is the assertion.
      stAssert "cxBtcAddressP2TR still does NOT tweak", cxBtcAddressP2TR(tInternal) is not kTapAddress0
      -- Fail closed, AND IN WHOSE WORDS. These five used to assert only that
      -- something threw, which on this surface is close to asserting nothing:
      -- the shim re-checks every length the script guards, so the guard can be
      -- deleted and the throw survives. That mutation was run and it SURVIVED
      -- on the headless side until check-script-vectors.py started reading the
      -- message (2026-08-16). Each check below now names the handler the
      -- message must come from and a phrase from the reason, which is the only
      -- thing that separates "the guard under test refused" from "something
      -- below it did". See stRefusalNames for why the handler is matched with
      -- its colons.
      stAssertRefusal "a 33-byte internal key is refused, by cxTaprootTweak's own guard", stThrowsText2("cxTaprootTweak", cxHexDecode(kPubOneCompressed), empty), "cxTaprootTweak", "internal key"
      -- The off-curve key is the one that must NOT come from the script: 32
      -- bytes passes both length guards, so only the curve can say no, and the
      -- message therefore names cxTaprootTweakPubkey - the .lcb handler one
      -- call down. Asserting that is asserting the layering: if this ever
      -- started naming cxTaprootTweak, a script-side check would have grown
      -- that is deciding curve membership, which nothing in this layer may do.
      stAssertRefusal "an internal key that is not on the curve is refused, by the CURVE and not by a length check", stThrowsText2("cxTaprootTweak", cxHexDecode(kSchnorrPubOffCurve), empty), "cxTaprootTweakPubkey", "not a valid secp256k1 key"
      stAssertRefusal "a 31-byte merkle root is refused, naming the merkle root", stThrowsText2("cxTaprootTweak", tInternal, stRepeatByte(0, 31)), "cxTaprootTweak", "merkle root"
      -- cxBtcAddressP2TRFromInternal re-throws the INNER message, so this line
      -- expects cxTaprootTweak's words and not its own. That is worth pinning
      -- rather than working around: the handler wraps its body in a
      -- capture-set-the-itemDelimiter-back-then-throw-after-end-try dance,
      -- because a throw issued INSIDE a catch does not reach the caller on OXT
      -- (2026-08-09, the fail-open that made cxMnemonicValidate answer true to
      -- a mistyped backup). If that capture ever broke, the caller would get
      -- empty or a bare engine error, and this is the check that would say so.
      stAssertRefusal "cxBtcAddressP2TRFromInternal refuses a 33-byte key, re-throwing the inner message intact", stThrowsText2("cxBtcAddressP2TRFromInternal", cxHexDecode(kPubOneCompressed), empty), "cxTaprootTweak", "internal key"
      stAssertRefusal "cxTaprootTweakSeckey refuses a 31-byte key", stThrowsText2("cxTaprootTweakSeckey", stRepeatByte(0, 31), empty), "cxTaprootTweakSeckey", "a buffer had the wrong length"
   catch tError
      stSectionFailed "BIP-341 Taproot", tError
   end try
end stRunTaproot

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

-- The three-argument form (cxSchnorrVerify takes a key, a message and a
-- signature).
function stThrows3 pHandler, pArgA, pArgB, pArgC
   local tThrew
   put "false" into tThrew
   try
      do "get" && pHandler & "(pArgA, pArgB, pArgC)"
   catch tError
      put "true" into tThrew
   end try
   return tThrew is "true"
end stThrows3

-- ---- the same three, but returning the MESSAGE ------------------------------
--
-- WHY A SECOND FAMILY EXISTS, AND WHY "IT THREW" IS THE WEAK ASSERTION HERE.
-- Every refusal in this library can come from either of TWO layers: a guard in
-- src/coinxt.livecodescript, and, one call below it, the C shim checking the
-- same thing again through the .lcb. Where both refuse the same input, a
-- Boolean "it threw" tests the layer BELOW the one under test, and the upper
-- guard is untested by construction.
--
-- That is not a theoretical worry, it is a measured one. On 2026-08-16 four
-- defects were reconstructed in the shipped Taproot script and driven through
-- tools/check-script-vectors.py; three were caught and one SURVIVED - deleting
-- cxTaprootTweak's merkle-root length guard - because the shim refuses a
-- 31-byte root too, with CNX_ERR_BADLEN, so the handler threw either way. The
-- headless gate was upgraded that day (its `throw_text`, and the mutation is
-- caught now). These helpers are the same upgrade on the ENGINE side, so the
-- two gates assert the same property instead of one of them settling for the
-- weaker half.
--
-- What the upper guard actually buys is a MESSAGE that names the handler and
-- the argument, instead of the shim's generic "a buffer had the wrong length"
-- - so that is what has to be asserted.
--
-- tError IS DECLARED in all three of these and is NOT declared in the Boolean
-- forms above, and the difference is load-bearing rather than tidiness: these
-- bodies REFERENCE the caught error. On strict OXT a reference to an undeclared
-- catch variable throws a SECOND error at the moment the catch fires, masking
-- the real failure as an opaque "error in function handler" - which is
-- invisible on a read, because the catch only misbehaves when it actually
-- fires (holde-em gotcha H8; check-livecodescript.py check 15). The Boolean
-- forms never read theirs, which is the binding-only case the checker
-- deliberately allows and onionxt's capability probes have proven on engines.
--
-- The no-throw answer is a SENTINEL rather than empty: empty would read as "it
-- threw, with an empty message" in a failure line, and the sentinel text
-- contains none of the words any caller asserts on, so stRefusalNames says no
-- to it for the right reason.
function stThrowsText pHandler, pArg
   local tError, tMessage
   put "(did not throw)" into tMessage
   try
      do "get" && pHandler & "(pArg)"
   catch tError
      put tError into tMessage
   end try
   return tMessage
end stThrowsText

function stThrowsText2 pHandler, pArgA, pArgB
   local tError, tMessage
   put "(did not throw)" into tMessage
   try
      do "get" && pHandler & "(pArgA, pArgB)"
   catch tError
      put tError into tMessage
   end try
   return tMessage
end stThrowsText2

function stThrowsText3 pHandler, pArgA, pArgB, pArgC
   local tError, tMessage
   put "(did not throw)" into tMessage
   try
      do "get" && pHandler & "(pArgA, pArgB, pArgC)"
   catch tError
      put tError into tMessage
   end try
   return tMessage
end stThrowsText3

-- Did a refusal say WHICH handler refused, and WHY, in its own words?
--
-- Every error this library raises is framed "CoinXT: <handler>: <reason>" -
-- the script layer writes that literally, and the .lcb builds the same shape
-- in sFinish ("CoinXT:" && pName & ":" && sStatusText(...)). So the handler is
-- matched WITH ITS COLONS and not as a bare name, which matters more than it
-- looks: "cxTaprootTweak" is a PREFIX of both cxTaprootTweakPubkey and
-- cxTaprootTweakSeckey, three handlers that refuse three different things and
-- sit one call apart. A bare-name match would let the wrong layer's refusal
-- satisfy the check, which is the exact confusion these helpers exist to
-- remove.
--
-- pReason is matched as a plain substring, and stRun sets `the caseSensitive`
-- true, so it is byte for byte. It is deliberately a PHRASE from the message
-- rather than the whole sentence: the .lcb appends a wipe note on the (never
-- yet seen) path where memzero refuses, and a whole-string comparison would go
-- red for a reason that is not a defect in the handler under test.
-- The two tests are written as two STATEMENTS rather than joined with `and`,
-- deliberately. `A is in B and C is in D` almost certainly parses the way it
-- reads, but "almost certainly" about operator precedence is exactly the kind
-- of bet this harness exists to settle rather than to place, and there is no
-- engine-passed precedent for that shape in this file (every `and` here is in
-- an ABI-6 section that has never run). Two ifs cost nothing and ask nothing.
function stRefusalNames pMessage, pHandler, pReason
   local tFramed
   put "CoinXT: " & pHandler & ":" into tFramed
   if tFramed is in pMessage then
      return pReason is in pMessage
   end if
   return false
end stRefusalNames

-- Assert a refusal MESSAGE, putting the message itself on the result line when
-- it does not match. A bare "FAIL a 31-byte merkle root is refused" tells the
-- person doing the engine pass nothing about what came back, and the whole
-- reason for reading the message is that the wrong layer's refusal looks
-- exactly like the right one from a distance. On a PASS the label stays short,
-- so the results window does not grow a full error sentence per green line.
command stAssertRefusal pName, pMessage, pHandler, pReason
   if stRefusalNames(pMessage, pHandler, pReason) then
      stAssert pName, true
   else
      stAssert pName & "  [got: " & pMessage & "]", false
   end if
end stAssertRefusal

-- Byte-exact equality for two HEX STRINGS, which `is` alone cannot promise.
-- `is` compares two operands that both LOOK numeric as NUMBERS, and a hex
-- string can be all decimal digits - rarely for a 64-byte signature, but this
-- library's whole discipline is that "rarely" is not "never", and the
-- Base58Check checksum path already had to be moved off `is` for exactly this
-- reason. Prefixing a letter forces the string comparison, which with `the
-- caseSensitive` set true (stRun does) is byte for byte.
function stSameHex pA, pB
   return ("h" & pA) is ("h" & pB)
end stSameHex

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

-- ==============================================================================
-- Phase 4. The most consequential sections in this file: see the note above the
-- phase-4 constants for why a wrong answer here does not announce itself.
-- ==============================================================================

command stRunBip39
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tEnt, tMnemonic
   stSection "BIP-39 mnemonics"
   try
      put cxHexDecode(kBip39Entropy12) into tEnt
      stAssert "12 words from all-zero entropy", cxMnemonicFromEntropy(tEnt) is kBip39Mnemonic
      stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(kBip39Mnemonic)) is kBip39Entropy12
      put cxHexDecode(kBip39Entropy24) into tEnt
      stAssert "24 words from all-ones entropy", cxMnemonicFromEntropy(tEnt) is kBip39Mnemonic24
      stAssert "and back to the entropy", cxHexEncode(cxMnemonicToEntropy(kBip39Mnemonic24)) is kBip39Entropy24
      stAssert "cxMnemonicValidate accepts it", cxMnemonicValidate(kBip39Mnemonic) is true
      -- The checksum is the whole reason a mnemonic is 12 words and not 11: it
      -- is what catches a single mistyped word before it becomes a lost wallet.
      stAssert "one wrong word fails the checksum", cxMnemonicValidate(kBip39Mnemonic12Bad) is false
      stAssert "a word outside the list is refused", cxMnemonicValidate("zzzz" && kBip39Mnemonic) is false
      -- Whitespace is normalized because BIP-39 derives the seed from the
      -- STRING; a pasted trailing newline must not change the wallet.
      put "  " & kBip39Mnemonic & "  " into tMnemonic
      stAssert "surrounding whitespace is normalized away", cxMnemonicValidate(tMnemonic) is true
      -- cxMnemonicNormalize on its own, because it is public API and because
      -- every other BIP-39 handler runs it first: if it were wrong, validate
      -- and to-seed would be wrong together and agree with each other.
      stAssert "cxMnemonicNormalize strips the padding", cxMnemonicNormalize(tMnemonic) is kBip39Mnemonic
      stAssert "an already-clean mnemonic is returned unchanged", cxMnemonicNormalize(kBip39Mnemonic) is kBip39Mnemonic
      stAssert "it is idempotent", cxMnemonicNormalize(cxMnemonicNormalize(tMnemonic)) is kBip39Mnemonic
      -- Tabs, newlines and runs of spaces are what a pasted backup actually
      -- contains, and BIP-39 derives the seed from the STRING, so collapsing
      -- them is the difference between restoring a wallet and missing it.
      stAssert "tabs and newlines collapse to single spaces", cxMnemonicNormalize("abandon" & tab & "abandon" & return & "  abandon ") is "abandon abandon abandon"
      stAssert "an empty string normalizes to empty", cxMnemonicNormalize("   ") is ""
      stAssert "the seed with no passphrase", cxHexEncode(cxMnemonicToSeed(kBip39Mnemonic, "")) is kBip39SeedNoPass
      stAssert "the seed with the TREZOR passphrase", cxHexEncode(cxMnemonicToSeed(kBip39Mnemonic, "TREZOR")) is kBip39Seed
      stAssert "a normalized mnemonic gives the same seed", cxHexEncode(cxMnemonicToSeed(tMnemonic, "")) is kBip39SeedNoPass
      stAssert "an entropy length BIP-39 does not define is refused", stThrows("cxMnemonicFromEntropy", stRepeatByte(0, 17))
      -- The wordlist crosses from the shim; if it were the wrong list or in the
      -- wrong order, everything above would still be self-consistent.
      stAssert "the wordlist is 2048 slots of 8 bytes", the number of bytes of cxBip39Wordlist() is 16384
      stAssert "cxBip39WordlistLen agrees", cxBip39WordlistLen() is 16384
      stAssert "the first word is abandon", byte 1 to 7 of cxBip39Wordlist() is "abandon"
   catch tError
      stSectionFailed "BIP-39", tError
   end try
end stRunBip39

command stRunBip32
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tNode, tDeep, tWatch, tChild, tStep
   stSection "BIP-32 derivation"
   try
      put cxHdFromSeed(cxHexDecode(kBip32Seed1)) into tNode
      stAssert "vector 1 master xprv", cxXprv(tNode) is kBip32V1Xprv
      stAssert "vector 1 master xpub", cxXpub(tNode) is kBip32V1Xpub
      stAssert "the master node is at depth 0", tNode["depth"] is 0
      put cxHdDerivePath(tNode, "m/0'") into tChild
      stAssert "vector 1 m/0' xprv", cxXprv(tChild) is kBip32V1H0Xprv
      stAssert "vector 1 m/0' xpub", cxXpub(tChild) is kBip32V1H0Xpub
      stAssert "h is accepted as a hardened marker", cxXprv(cxHdDerivePath(tNode, "m/0h")) is kBip32V1H0Xprv
      -- cxHdDeriveChild is the single CKD step cxHdDerivePath is a loop over,
      -- and it is public API in its own right. Pin it to the SAME published
      -- vector rather than only to the path walker: a shared defect in the
      -- step would make the two agree while both were wrong, so the first
      -- assertion here is against BIP-32's own number and the second is the
      -- agreement check on top of it.
      stAssert "cxHdDeriveChild reaches m/0' as one hardened step", cxXprv(cxHdDeriveChild(tNode, 2147483648)) is kBip32V1H0Xprv
      stAssert "and a normal step agrees with the path walker", cxXprv(cxHdDeriveChild(tChild, 1)) is cxXprv(cxHdDerivePath(tNode, "m/0'/1"))
      stAssert "index 0 is not treated as hardened", cxXprv(cxHdDeriveChild(tNode, 0)) is cxXprv(cxHdDerivePath(tNode, "m/0"))
      put cxHdDeriveChild(tChild, 1) into tStep
      stAssert "each step advances the depth by one", tStep["depth"] is 2
      stAssert "a child index at or above 2^32 is refused", stThrows2("cxHdDeriveChild", tNode, 4294967296)
      stAssert "a negative child index is refused", stThrows2("cxHdDeriveChild", tNode, -1)
      put cxHdDerivePath(tNode, kBip32V1DeepPath) into tDeep
      stAssert "vector 1 five levels deep", cxXprv(tDeep) is kBip32V1DeepXprv
      stAssert "and it is at depth 5", tDeep["depth"] is 5
      -- Vector 3 is in the BIP for one reason: a leading zero in the master key.
      stAssert "vector 3 (leading-zero master key)", cxXprv(cxHdFromSeed(cxHexDecode(kBip32Seed3))) is kBip32V3Xprv
      -- A watch-only node is the whole point of an xpub, and its limits are the
      -- whole point of hardened derivation.
      put cxHdNeuter(tChild) into tWatch
      stAssert "neuter leaves the source node's key alone", tChild["seckey"] is not ""
      stAssert "a watch-only node has no private key", tWatch["seckey"] is ""
      stAssert "and still derives the same normal child", cxXpub(cxHdDerivePath(tWatch, "m/1")) is cxXpub(cxHdDerivePath(tChild, "m/1"))
      stAssert "but cannot make an xprv", stThrows("cxXprv", tWatch)
      stAssert "and cannot derive a hardened child", stThrows2("cxHdDerivePath", tWatch, "m/0'")
      -- A path that parses loosely is a path that silently derives the wrong
      -- wallet, so each of these must throw rather than be interpreted.
      stAssert "a path without a leading m is refused", stThrows2("cxHdDerivePath", tNode, "0/1")
      stAssert "an empty level is refused", stThrows2("cxHdDerivePath", tNode, "m/")
      -- "m/" and "m/0'/" are the trailing-separator cases the 2026-08-10
      -- engine pass caught failing OPEN: a trailing delimiter is invisible
      -- to `the number of items`, so the walker returned the node unchanged
      -- instead of throwing. The second spelling pins the fix at depth too.
      stAssert "a trailing separator is refused", stThrows2("cxHdDerivePath", tNode, "m/0'/")
      stAssert "a non-digit level is refused", stThrows2("cxHdDerivePath", tNode, "m/1e3")
      stAssert "a level at or above 2^31 is refused", stThrows2("cxHdDerivePath", tNode, "m/2147483648")
      stAssert "a too-short seed is refused", stThrows("cxHdFromSeed", stRepeatByte(0, 15))
   catch tError
      stSectionFailed "BIP-32", tError
   end try
end stRunBip32

command stRunBip44
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tMaster, tNode
   stSection "BIP-44 / BIP-84 end to end"
   try
      -- The claim this section makes is the one that matters to a user: the
      -- same twelve words that restore a wallet anywhere else restore THIS one
      -- to the same addresses.
      put cxHdFromSeed(cxMnemonicToSeed(kBip39Mnemonic, "")) into tMaster
      stAssert "the test mnemonic's root xprv", cxXprv(tMaster) is kAbandonXprv
      put cxHdDerivePath(tMaster, kAbandonBip44) into tNode
      stAssert "m/44'/0'/0'/0/0 is the published P2PKH address", cxBtcAddressP2PKH(tNode["pubkey"]) is kAbandonP2pkh
      put cxHdDerivePath(tMaster, kAbandonBip84) into tNode
      stAssert "m/84'/0'/0'/0/0 is the BIP-84 vector", cxBtcAddressP2WPKH(tNode["pubkey"]) is kAbandonP2wpkh
      stAssert "the BIP-84 account xpub", cxXpub(cxHdDerivePath(tMaster, kAbandonBip84Account)) is kAbandonBip84Xpub
      put cxHdDerivePath(tMaster, kAbandonEthPath) into tNode
      stAssert "m/44'/60'/0'/0/0 is the published Ethereum address", cxEthAddressChecksum(cxEthAddress(tNode["pubkey"])) is kAbandonEth
   catch tError
      stSectionFailed "BIP-44", tError
   end try
end stRunBip44

command stRunTransactions
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tOutpoints, tSequences, tOutputs, tD0, tD1, tSig0, tDer0, tScriptSig0
   local tSig1, tDer1, tPub1, tWit1, tScriptSigs, tWitnesses, tRaw
   local tRecov, tRecid, tRHex, tSHex, tEth, tThrew, tErr2
   stSection "phase 5: transactions (BIP-143, EIP-155, EIP-1559)"
   try
      -- --- Bitcoin: the BIP-143 native-P2WPKH worked example, rebuilt whole.
      -- The pieces first, so a mismatch localizes.
      stAssert "input 0 outpoint serializes (txid reversed + LE vout)", \
            cxHexEncode(cxBtcOutpoint(kTxid0, 0)) is kTxOutpoint0
      stAssert "input 1 outpoint serializes", \
            cxHexEncode(cxBtcOutpoint(kTxid1, 1)) is kTxOutpoint1
      stAssert "output 0 serializes (LE amount + script)", \
            cxHexEncode(cxBtcOutput(112340000, kTxOutScript0)) is kTxOut0
      stAssert "output 1 serializes", \
            cxHexEncode(cxBtcOutput(223450000, kTxOutScript1)) is kTxOut1
      put kTxOutpoint0 & comma & kTxOutpoint1 into tOutpoints
      put "4294967278,4294967295" into tSequences
      put kTxOut0 & comma & kTxOut1 into tOutputs
      -- The two sighashes: input 0 legacy SIGHASH_ALL, input 1 BIP-143.
      put cxBtcSighashLegacy(1, tOutpoints, tSequences, 1, kTxScriptCode0, tOutputs, 17, 1) into tD0
      stAssert "input 0 legacy sighash matches", cxHexEncode(tD0) is kTxLegacySighash
      put cxBtcSighashSegwit(1, tOutpoints, tSequences, 2, kTxScriptCode1, 600000000, tOutputs, 17, 1) into tD1
      stAssert "input 1 BIP-143 sighash matches the BIP", cxHexEncode(tD1) is kTxSegwitSighash
      -- Sign each (RFC 6979, so deterministic), DER-encode, append SIGHASH_ALL.
      put cxSign(cxHexDecode(kTxSeckey0), tD0) into tSig0
      put cxDerEncode(tSig0) & numToByte(1) into tDer0
      put numToByte(the number of bytes of tDer0) & tDer0 into tScriptSig0
      stAssert "input 0 scriptSig (push + DER sig + hashtype)", \
            cxHexEncode(tScriptSig0) is kTxScriptSig0
      put cxSign(cxHexDecode(kTxSeckey1), tD1) into tSig1
      put cxDerEncode(tSig1) & numToByte(1) into tDer1
      put cxPublicKey(cxHexDecode(kTxSeckey1), true) into tPub1
      stAssert "input 1's pubkey is the BIP's compressed key", \
            cxHexEncode(tPub1) is kTxPubkey1
      put cxBtcWitness(cxHexEncode(tDer1) & comma & cxHexEncode(tPub1)) into tWit1
      stAssert "input 1 witness stack (count + sig + pubkey)", \
            cxHexEncode(tWit1) is kTxWitness1
      -- Assemble: input 0 has the scriptSig and no witness, input 1 the reverse.
      put cxHexEncode(tScriptSig0) & comma into tScriptSigs
      put comma & cxHexEncode(tWit1) into tWitnesses
      put cxBtcTxEncode(1, tOutpoints, tScriptSigs, tSequences, tWitnesses, tOutputs, 17) into tRaw
      stAssert "the whole signed transaction matches BIP-143 byte for byte", \
            cxHexEncode(tRaw) is kTxSignedRaw
      stAssert "the txid (non-witness serialization, reversed)", \
            cxBtcTxid(1, tOutpoints, tScriptSigs, tSequences, tOutputs, 17) is kTxTxid
      -- varint boundaries.
      stAssert "varint 252 is one byte", cxHexEncode(cxVarInt(252)) is "fc"
      stAssert "varint 253 is fd + LE u16", cxHexEncode(cxVarInt(253)) is "fdfd00"
      stAssert "varint 65536 is fe + LE u32", cxHexEncode(cxVarInt(65536)) is "fe00000100"

      -- --- Ethereum EIP-155 legacy: the specification's own example.
      stAssert "the EIP-155 signing hash matches the spec", \
            cxHexEncode(cxEthLegacySighash(9, kEthGasPrice, 21000, kEthTo, kEthValue, "", 1)) is kEthLegacySighash
      put cxSignRecoverable(cxHexDecode(kEthSeckey), cxHexDecode(kEthLegacySighash)) into tRecov
      put byteToNum(byte 65 of tRecov) into tRecid
      put cxHexEncode(byte 1 to 32 of tRecov) into tRHex
      put cxHexEncode(byte 33 to 64 of tRecov) into tSHex
      put cxEthLegacyEncode(9, kEthGasPrice, 21000, kEthTo, kEthValue, "", 1, tRecid, tRHex, tSHex) into tEth
      stAssert "the signed EIP-155 transaction matches the spec (v=37)", \
            tEth["raw"] is kEthLegacyRaw
      stAssert "the EIP-155 transaction hash", tEth["txhash"] is kEthLegacyTxhash

      -- --- Ethereum EIP-1559 typed (0x02): self-consistent, deterministic.
      stAssert "the EIP-1559 signing hash", \
            cxHexEncode(cxEth1559Sighash(1, 0, kEth1559MaxPrio, kEth1559MaxFee, 21000, kEthTo, kEth1559Value, "")) is kEth1559Sighash
      put cxSignRecoverable(cxHexDecode(kEthSeckey), cxHexDecode(kEth1559Sighash)) into tRecov
      put byteToNum(byte 65 of tRecov) into tRecid
      put cxHexEncode(byte 1 to 32 of tRecov) into tRHex
      put cxHexEncode(byte 33 to 64 of tRecov) into tSHex
      put cxEth1559Encode(1, 0, kEth1559MaxPrio, kEth1559MaxFee, 21000, kEthTo, kEth1559Value, "", tRecid, tRHex, tSHex) into tEth
      stAssert "the signed EIP-1559 transaction (0x02 envelope)", \
            tEth["raw"] is kEth1559Raw
      stAssert "the EIP-1559 transaction hash", tEth["txhash"] is kEth1559Txhash

      -- Fail closed: a compact signature must be exactly 64 bytes.
      stAssert "cxDerEncode refuses a short signature", \
            stThrows("cxDerEncode", byte 1 to 40 of tSig1)
      -- Fail closed: the BIP-143 sighash MUST commit to the outputs. An empty
      -- outputs list is refused - a preimage without hashOutputs would sign a
      -- payment to anywhere (the review's CRITICAL finding, guarded here).
      put false into tThrew
      try
         get cxBtcSighashSegwit(1, tOutpoints, tSequences, 2, kTxScriptCode1, 600000000, "", 17, 1)
      catch tErr2
         put true into tThrew
      end try
      stAssert "cxBtcSighashSegwit refuses an empty outputs list (hashOutputs is mandatory)", tThrew
      -- Fail closed: a witness list may not carry MORE entries than there are
      -- inputs (the extras would be silently dropped). A SHORT list cannot be
      -- rejected here - the engine ignores one trailing delimiter, so [wit, ""]
      -- and [wit] are the same string, and a missing trailing witness reads as
      -- an empty stack, which is its correct meaning. tWitnesses already has one
      -- entry per input; a third makes it over-long for this two-input tx.
      put false into tThrew
      try
         get cxBtcTxEncode(1, tOutpoints, tScriptSigs, tSequences, tWitnesses & comma & cxHexEncode(tWit1), tOutputs, 17)
      catch tErr2
         put true into tThrew
      end try
      stAssert "cxBtcTxEncode refuses a witness list longer than the input count", tThrew
   catch tError
      stSectionFailed "transactions", tError
   end try
end stRunTransactions

command stRunTaproot341
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tOutpoint, tLeaf0, tLeaf1, tRoot, tD0, tD1
   stSection "BIP-341: taproot sighash + script tree"
   try
      -- the published two-leaf tree: leaf hashes (the 0xfa version included),
      -- the sorted branch fold, and the published control block byte for byte.
      put cxTapLeafHash(192, kTapLeafScript0) into tLeaf0
      stAssert "leaf 0 hashes to the published TapLeaf value", tLeaf0 is kTapLeafHash0
      put cxTapLeafHash(250, kTapLeafScript1) into tLeaf1
      stAssert "leaf 1 (version 0xfa) hashes to the published value", tLeaf1 is kTapLeafHash1
      stAssert "the branch folds to the published merkle root (sorted)", \
            cxTapBranchHash(tLeaf0, tLeaf1) is kTapMerkleRoot
      stAssert "the argument order cannot change the root (the sort is inside)", \
            cxTapBranchHash(tLeaf1, tLeaf0) is kTapMerkleRoot
      stAssert "the control block assembles to the published bytes", \
            cxTapControlBlock(192, 0, kTapInternal, kTapLeafHash1) is kTapControlBlock0
      -- the sighash builder, one derived case per path over kTxid0/kTxOut0.
      put cxHexEncode(cxBtcOutpoint(kTxid0, 0)) into tOutpoint
      put cxBtcSighashTaproot(2, tOutpoint, "4294967294", "50000", kTapSpk, kTxOut0, 1, 0, 0, "") into tD0
      stAssert "the key-path sighash matches the derived vector", cxHexEncode(tD0) is kTapSighashKeyPath
      put cxBtcSighashTaproot(2, tOutpoint, "4294967294", "50000", kTapSpk, kTxOut0, 1, 0, 0, tLeaf0) into tD1
      stAssert "the script-path sighash matches (tapleaf extension)", cxHexEncode(tD1) is kTapSighashScriptPath
      stAssert "and the two paths genuinely differ", cxHexEncode(tD0) is not cxHexEncode(tD1)
      -- the refusals that make the builder safe to hold.
      stAssert "0x80 alone is refused (not a BIP-341 type)", \
            stThrowsTaproot(tOutpoint, 1, 128, "")
      stAssert "SIGHASH_SINGLE past the last output is refused", \
            stThrowsTaproot(tOutpoint, 1, 3, "single-past-end")
      stAssert "an odd leaf version is refused", stThrows2("cxTapLeafHash", 193, "51")
      stAssert "leaf version 0x50 is refused (annex ambiguity)", \
            stThrows2("cxTapLeafHash", 80, "51")
   catch tError
      stSectionFailed "BIP-341", tError
   end try
end stRunTaproot341

-- The taproot refusal probe: builds the argument list the two negatives need.
-- The SINGLE-past-the-end case uses an EMPTY outputs list with index 1 + type
-- 3, so there is no output for the signed input - the invalid-under-BIP-341
-- shape (pre-taproot it silently signed the number 1).
private function stThrowsTaproot pOutpoint, pIndex, pType, pMode
   local tError, tOutputs
   put kTxOut0 into tOutputs
   if pMode is "single-past-end" then
      put "" into tOutputs
   end if
   try
      get cxBtcSighashTaproot(2, pOutpoint, "4294967294", "50000", kTapSpk, tOutputs, pIndex, 0, pType, "")
   catch tError
      return true
   end try
   return false
end stThrowsTaproot

-- ==============================================================================
-- The fail-closed regression set. Read the note above its constants: each of
-- these is a case where the library used to give a WRONG ANSWER THAT LOOKED
-- RIGHT, which is the only failure mode that matters on a surface that moves
-- money. They are also the cases most likely to behave differently on a real
-- engine than in the headless interpreter, because three of them turn on `is`
-- and on `the caseSensitive`.
-- ==============================================================================

command stRunFailOpen
   local tError -- a REFERENCED catch variable must be declared: undeclared, strict OXT throws a second error that masks the real one (checker check 15)
   local tProgram, tDecoded, tKey
   stSection "fail-closed regressions"
   try
      -- EIP-55 verification must depend on the CALLER'S casing. If these come
      -- back true on the engine while they are false headlessly, the cause is
      -- `the caseSensitive` reaching a comparison it should not - look at
      -- cxCompareBytes first.
      stAssert "a correctly checksummed address still verifies", cxEthAddressIsChecksummed(kEip55A) is true
      stAssert "one corrupted letter is caught", cxEthAddressIsChecksummed(kEip55Corrupt) is false
      stAssert "a fully case-flipped address is caught", cxEthAddressIsChecksummed(kEip55Flipped) is false
      -- An in-band error sentinel over arbitrary bytes is always wrong.
      put cxHexDecode(kSegwitErrorProgram) into tProgram
      stAssert "an address whose program spells ERROR encodes", cxSegwitAddressEncode("bc", 1, tProgram) is kSegwitErrorAddress
      put cxSegwitAddressDecode("bc", kSegwitErrorAddress) into tDecoded
      stAssert "and decodes back to the same program", cxHexEncode(tDecoded["program"]) is kSegwitErrorProgram
      stAssert "at witness version 1", tDecoded["version"] is 1
      -- hash160 hashes anything, so an unchecked key gives a well-formed,
      -- checksummed, permanently unspendable address.
      stAssert "P2PKH refuses an empty key", stThrows("cxBtcAddressP2PKH", "")
      stAssert "P2PKH refuses a 20-byte hash", stThrows("cxBtcAddressP2PKH", stRepeatByte(0, 20))
      put numToByte(4) & stRepeatByte(0, 32) into tKey
      stAssert "P2PKH refuses 33 bytes tagged 0x04", stThrows("cxBtcAddressP2PKH", tKey)
      -- char (n) of a 32-character charset returns EMPTY past the end, so an
      -- out-of-range value used to emit nothing and shorten the string.
      stAssert "bech32 refuses a data value of 32", stThrows2("cxBech32EncodeValues", "bc", "0,32,1")
      stAssert "bech32 refuses a negative data value", stThrows2("cxBech32EncodeValues", "bc", "0,-1")
      -- An uppercase HRP used to produce a MIXED-case string, which BIP-173
      -- forbids and which this library's own decoder rejects.
      stAssert "an uppercase HRP is refused", stThrows2("cxBech32EncodeValues", "BC", "0")
   catch tError
      stSectionFailed "fail-closed regressions", tError
   end try
end stRunFailOpen
