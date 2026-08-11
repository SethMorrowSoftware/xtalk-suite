script "coinxt"

-- coinxt.livecodescript - the CoinXT script layer (phase 3: encodings and
-- addresses; phase 4: BIP-39 mnemonics and BIP-32 HD derivation).
--
-- WHAT LIVES HERE AND WHY. Everything in this file is checksummed byte
-- shuffling with no secret-dependent branch, so it belongs in script where it
-- is diffable, reviewable and KAT-covered - exactly as OnionXT does base32
-- (CLAUDE.md, "The C-vs-script split"). Nothing here invents cryptography: every
-- hash is a cx* call into the audited native shim, and this file only moves
-- bits and verifies checksums.
--
-- The inverse rule matters just as much: nothing that touches a private key or
-- a curve point is implemented here. Those are src/coinxt.lcb over
-- trezor-crypto. If you find yourself reaching for modular arithmetic on a
-- 256-bit number in this file, stop; it is in the wrong layer.
--
-- ==========================================================================
-- STATUS: NEEDS AN OXT PASS - but this file HAS been executed, which is new.
--
-- OXT cannot compile or run a .livecodescript headlessly, so historically a
-- file like this would ship never having run. Three things stand behind it
-- instead, and it is worth being exact about what each is worth:
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
-- Until that engine run: the LOGIC is observed, the ENGINE BEHAVIOUR is not.
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
-- the 8-to-5 converters, the mnemonic word split, the path split), and an
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
-- internal key: BIP-341 defines the output key as Q = P + int(tagged_hash(P ||
-- merkle_root)) * G, and computing that needs the BIP-340 surface CoinXT has
-- deferred with Taproot (see CLAUDE.md). This handler does the encoding half
-- only. Handing it a raw internal key produces a VALID-LOOKING address that
-- nobody can spend from, so if you do not already know your key is tweaked,
-- it is not.
function cxBtcAddressP2TR pOutputKey
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
-- Phase 5 - transaction building and signing.
--
-- STATUS: verified statically and against tools/coin_reference.py (which
-- reproduces the BIP-143 native-P2WPKH worked example, the EIP-155 spec
-- example and a self-consistent EIP-1559 typed transaction); NEEDS AN OXT
-- PASS + independent-decoder acceptance before any "broadcastable" claim.
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
-- the legacy form, plus the input's amount in satoshi (BIP-143 commits to it).
-- pScriptCodeHex is the BARE scriptCode (for P2WPKH the app passes the
-- 25-byte P2PKH script 76a914{hash}88ac; this layer adds the length prefix).
function cxBtcSighashSegwit pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pLocktime, pSighashType
   local tSavedDelim, tResult, tFailed, tFailure
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to comma
   put false into tFailed
   try
      put cxBtcSighashSegwitInner(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pLocktime, pSighashType) into tResult
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

private function cxBtcSighashSegwitInner pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex, pAmountSat, pLocktime, pSighashType
   local tCount, tI, tPrevouts, tSequencesRaw, tOutputsRaw, tScript, tBuf, tOutCount
   put the number of items of pOutpoints into tCount
   if tCount is 0 or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcSighashSegwit: the outpoint and sequence lists must be parallel and non-empty."
   end if
   if pIndex < 1 or pIndex > tCount then
      throw "CoinXT: cxBtcSighashSegwit: the input index is out of range (it is 1-based)."
   end if
   put "" into tPrevouts
   put "" into tSequencesRaw
   repeat with tI = 1 to tCount
      put tPrevouts & cxHexDecode(item tI of pOutpoints) into tPrevouts
      put tSequencesRaw & cxUIntToBytesLE(item tI of pSequences, 4) into tSequencesRaw
   end repeat
   put the number of items of pOutputs into tOutCount
   put "" into tOutputsRaw
   repeat with tI = 1 to the number of items of pOutputs
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

-- A serialized SegWit witness stack for one input: the CompactSize item count,
-- then each item as CompactSize-length + bytes. pItems is a comma list of item
-- hex (empty string for an input with no witness).
function cxBtcWitness pItems
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
   if the number of items of pScriptSigs is not tCount or the number of items of pSequences is not tCount then
      throw "CoinXT: cxBtcTxEncode: the input lists must be parallel."
   end if
   put false into tHasWitness
   if pWitnesses is not "" then
      repeat with tI = 1 to the number of items of pWitnesses
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
