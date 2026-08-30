script "walletCore"

-- wallet-core.livecodescript - the CoinXT wallet engine: everything a
-- full-featured Bitcoin wallet computes, and nothing it does.
--
-- WHAT THIS IS. A pure calculator layer over CoinXT, in the same relationship
-- to examples/coin-wallet.livecodescript that coinxt.livecodescript is to
-- coinxt.lcb. CoinXT owns every hash and every curve operation; THIS file owns
-- the byte layout a wallet wraps around them - scripts, addresses, extended
-- keys, amounts, sizes, fees, coin selection, sighash dispatch, witness
-- shapes, PSBT, signed messages, payment URIs, output descriptors,
-- transaction decoding, JSON and QR. The APP owns state, key custody, the
-- window and the network.
--
-- It ships under examples/ rather than src/ for the reason
-- enetxt/examples/enet-helpers.livecodescript does: it is a library a demo
-- carries, not part of the extension's own published surface. Everything here
-- is composed from cx* calls; nothing is added to what CoinXT installs.
--
-- THREE PROPERTIES ARE DELIBERATE, AND EACH ONE BUYS SOMETHING.
--
-- 1. NO STATE. Not one script-level `local`. Every handler is a function of
--    its arguments, so there is nothing to initialise, nothing to tear down,
--    no order of calls to get wrong, and no way for one screen of the app to
--    leave another screen's answer stale. It also means the whole engine can
--    be driven headlessly (see 3).
--
-- 2. NO `item` AND NO `line` CHUNKS. Lists are ARRAYS, keyed 1..n with an "n"
--    count. `the itemDelimiter` and `the lineDelimiter` are global mutable
--    state in this engine family (templates/CLAUDE.md rule 5), and the
--    member's own CLAUDE.md records nine handlers that a hostile delimiter
--    turned into wrong ANSWERS rather than errors - a valid seed phrase
--    reported invalid, an address built from the wrong bytes. CoinXT answered
--    that with a save/set/use/restore wrapper around every affected handler.
--    Not reading those chunks at all is the stronger answer, and it is
--    available here because this layer was written after the lesson instead
--    of before it. Comma-joined strings are still BUILT here (that is CoinXT's
--    transaction API), which is safe: building a string never reads the
--    delimiter.
--
-- 3. NO UI AND NO I/O. No field, no control, no socket, no URL, no file. That
--    is what lets tools/check-wallet-vectors.py RUN this file - the actual
--    shipped bytes - through tools/lcs-interp.py against
--    tools/wallet_reference.py's independently derived answers, with the real
--    committed coinxt.so supplying the cryptography. The family's most
--    expensive recorded failure class is a shipped script that has never
--    executed; this layer is executable without an engine, so it does not join
--    that class.
--
-- HONESTY (the suite convention). Every handler here is verified statically
-- (tools/check-livecodescript.py) and by the vector gate above, which settles
-- LOGIC and not parser behaviour: an interpreter is an approximation of the
-- engine, never the engine. NOTHING HERE HAS RUN ON AN OXT ENGINE YET, and
-- that stays true until an engine pass is recorded in coinxt/CLAUDE.md. The
-- cryptography underneath it HAS - CoinXT's own passes of 2026-08-10 and
-- 2026-08-12 - so a failure here is most likely this file's arithmetic, not
-- the library's.
--
-- CUSTODY, said plainly, because this layer is one call away from a signature:
-- OXT script variables are not locked memory and can be paged to disk. A seed
-- typed into a stack on a general-purpose desktop is not hardware-wallet
-- isolation. This engine holds a private key only for the duration of the one
-- call that needs it and the app clears its own copies; that is the honest
-- limit, and it is the machine's trust boundary, not this file's.
--
-- The LCS rules this file is written under (the family lesson book): ASCII
-- only, no braces, no subscripted function results, literal constants before
-- first use, zero-argument statement calls BARE, no `throw` inside a `catch`,
-- no `repeat with ... step`, no `switch` (the interpreter above models none),
-- `byte` and never `char` on binary, and integer division through a helper
-- rather than `div`.

-- ---- version -----------------------------------------------------------------

constant kCwVersion = "1.0.0"

-- ---- opcodes -----------------------------------------------------------------
-- The handful of script opcodes a single-signature or simple-multisig wallet
-- ever writes. Spelled as numbers because that is what goes on the wire, and
-- named because 118 is not self-explanatory at the point of use.

constant kCwOpZero = 0
constant kCwOpDup = 118
constant kCwOpEqual = 135
constant kCwOpEqualVerify = 136
constant kCwOpHash160 = 169
constant kCwOpCheckSig = 172
constant kCwOpCheckMultisig = 174
constant kCwOpOne = 81

-- ---- network parameters ------------------------------------------------------
-- Four networks and the values that differ between them, as parallel comma
-- lists indexed by cwNetIndex. A table rather than a branch per lookup, so
-- adding a network is one entry per row and a WRONG lookup is a wrong row
-- rather than a silently shared value.
--
-- The base58 version bytes are Bitcoin Core's chainparams. The bech32 HRPs are
-- BIP-173 (bc, tb) with BIP-350's signet reuse of tb and Core's bcrt for
-- regtest. The extended-key versions are BIP-32's own pair (xpub/xprv,
-- tpub/tprv) plus SLIP-132's per-script-type pairs, which is what lets a bare
-- extended key say which script type it is for. Taproot has NO SLIP-132
-- assignment: BIP-86 keeps xpub deliberately, so the p2tr row repeats the
-- BIP-32 numbers rather than inventing any.

constant kCwNetworks = "mainnet,testnet,signet,regtest"
constant kCwHrps = "bc,tb,tb,bcrt"
constant kCwP2pkhVersions = "0,111,111,111"
constant kCwP2shVersions = "5,196,196,196"
constant kCwWifVersions = "128,239,239,239"
constant kCwCoinTypes = "0,1,1,1"

constant kCwXpubVersions = "76067358,70617039,70617039,70617039"
constant kCwXprvVersions = "76066276,70615956,70615956,70615956"
constant kCwYpubVersions = "77429938,71979618,71979618,71979618"
constant kCwYprvVersions = "77428856,71978536,71978536,71978536"
constant kCwZpubVersions = "78792518,73342198,73342198,73342198"
constant kCwZprvVersions = "78791436,73341116,73341116,73341116"
constant kCwYshPubVersions = "43365439,37915119,37915119,37915119"
constant kCwYshPrvVersions = "43364357,37914037,37914037,37914037"
constant kCwZshPubVersions = "44728019,39277699,39277699,39277699"
constant kCwZshPrvVersions = "44726937,39276616,39276616,39276616"

-- ---- script types ------------------------------------------------------------
-- The five standard output types this wallet builds and spends, with the BIP
-- that assigns each one a derivation purpose and the SLIP-132 stem its
-- extended keys carry. p2wsh is the multisig row and follows BIP-48, whose
-- account path carries a fifth hardened level naming the script type.

constant kCwScriptTypes = "p2pkh,p2sh-p2wpkh,p2wpkh,p2tr,p2wsh"
constant kCwPurposes = "44,49,84,86,48"
constant kCwStems = "x,y,z,x,Z"

-- ---- fees and sizes ----------------------------------------------------------
-- Worst case, always, because underestimating a transaction's size underpays
-- its fee and the result sits unconfirmed while the person watching it has no
-- idea why. A DER-encoded low-S ECDSA signature is 71 or 72 bytes and the
-- difference is one leading zero, so 72 is budgeted; BIP-340's is exactly 64.

constant kCwSigBytes = 72
constant kCwPubkeyBytes = 33
constant kCwSchnorrSigBytes = 64

-- Core's dust rule: an output is dust when spending it would cost more than a
-- third of its value at the 3000 sat/kvB dust relay fee. Core's spend-size
-- estimate branches on ONE question - is the scriptPubKey a witness program? -
-- and the distinction it does NOT draw is the tempting one: a P2SH-wrapped
-- SegWit output has a P2SH scriptPubKey, so it counts as legacy here even
-- though spending it really does use a witness.
constant kCwDustSpendLegacy = 148
constant kCwDustSpendWitness = 67

-- BIP-125 rule 3 / Core's default incremental relay fee, in sat/vB: a
-- replacement must pay at least this much more per virtual byte.
constant kCwIncrementalRelayFee = 1

-- The sequence numbers that decide replaceability. Anything below FFFFFFFE
-- signals opt-in RBF (BIP-125); FFFFFFFE keeps locktime active without it;
-- FFFFFFFF disables both.
constant kCwSeqRbf = 4294967293
constant kCwSeqFinal = 4294967295
constant kCwSeqNoRbf = 4294967294

-- ---- message signing ---------------------------------------------------------
-- The magic string Bitcoin Core has prefixed signed messages with since 2011.
-- It is length-prefixed as a varstr, which for 24 bytes is a single 0x18.
constant kCwMsgMagic = "Bitcoin Signed Message:"

-- ---- descriptors -------------------------------------------------------------
-- The checksum charset and the character-class input alphabet from Bitcoin
-- Core's descriptor.cpp. The generator constants are the five polynomial rows
-- of that same file.
constant kCwDescCharset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
-- The input alphabet is 95 characters and the last three are a double quote,
-- a backslash and a space - none of which can be written inside a
-- .livecodescript string literal without either an escape this dialect does
-- not have or a trailing backslash the parser reads as a line continuation.
-- So the constant carries the first 92 and cwDescCharPos appends the other
-- three by hand. The alternative (a constant built by concatenation) is not
-- available: constants must be literal here.
constant kCwDescInputHead = "0123456789()[],'/*abcdefgh@:$%{}IJKLMNOPQRSTUVWXYZ&+-.;<=>?!^_|~ijklmnopqrstuvwxyzABCDEFGH`#"
constant kCwDescGen0 = 1056006543753
constant kCwDescGen1 = 730107360018
constant kCwDescGen2 = 118834127661
constant kCwDescGen3 = 236335490938
constant kCwDescGen4 = 430795026429

-- ---- hex ---------------------------------------------------------------------
constant kCwHexDigits = "0123456789abcdef"

-- ==============================================================================
-- PRIMITIVES
--
-- The arithmetic and list helpers everything below is built from. They exist
-- because this dialect's spellings for these operations are traps: `div` and
-- `mod` are OPERATORS some OXT parsers reject inside a compound expression,
-- `^` is rejected outright in one, `bitXor` is an operator and not a function,
-- and `item` reads global mutable state. CoinXT's own script layer carries the
-- same four helpers for the same reasons; they are re-declared here rather
-- than borrowed because those are private to that file and this one has to
-- stand alone when it is loaded as a library rather than embedded.
-- ==============================================================================

private function cwIntDiv pA, pB
   -- Integer division, floor, for the non-negative operands every caller here
   -- uses. trunc() rather than `div`.
   return trunc(pA / pB)
end cwIntDiv

private function cwIntMod pA, pB
   return pA - pB * cwIntDiv(pA, pB)
end cwIntMod

private function cwMax pA, pB
   if pA > pB then
      return pA
   end if
   return pB
end cwMax

private function cwMin pA, pB
   if pA < pB then
      return pA
   end if
   return pB
end cwMin

private function cwAbs pA
   if pA < 0 then
      return 0 - pA
   end if
   return pA
end cwAbs

private function cwCeilDiv pA, pB
   -- Ceiling division for non-negative operands: the shape every weight ->
   -- vsize conversion needs, and the one a floor gets silently wrong by up to
   -- three quarters of a byte per transaction.
   return cwIntDiv(pA + pB - 1, pB)
end cwCeilDiv

private function cwPow2 pN
   local tResult, tI
   put 1 into tResult
   repeat with tI = 1 to pN
      multiply tResult by 2
   end repeat
   return tResult
end cwPow2

private function cwBitXorN pA, pB, pBits
   -- Bitwise exclusive-or over the low pBits bits, from arithmetic. pBits is
   -- a parameter because the two callers want very different widths: the
   -- Reed-Solomon field is 8 bits and runs thousands of times, the descriptor
   -- checksum is 40 bits and runs hundreds, and paying 40 iterations for an
   -- 8-bit XOR would make a QR code take seconds to draw.
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to pBits
      put cwIntMod(cwIntDiv(pA, tBit), 2) into tDigitA
      put cwIntMod(cwIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is not tDigitB then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end cwBitXorN

private function cwBitAndN pA, pB, pBits
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to pBits
      put cwIntMod(cwIntDiv(pA, tBit), 2) into tDigitA
      put cwIntMod(cwIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is 1 and tDigitB is 1 then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end cwBitAndN

-- ---- comma lists, read without `the itemDelimiter` ---------------------------
-- The parameter tables above are comma lists and have to be indexed. `item N
-- of` would do it and would read a property any other script in the process
-- may have changed, so these two scan for the separator instead. They are the
-- ONLY place in this file that takes a delimited string apart.

private function cwListAt pList, pIndex
   -- The two-argument offset() only; the three-argument form that takes a
   -- start position is not modelled by the offline runner this file has to
   -- execute in, so the remainder is re-sliced each step instead.
   local tRest, tI, tPos
   put pList into tRest
   put 1 into tI
   repeat while tI < pIndex
      put offset(",", tRest) into tPos
      if tPos is 0 then
         return ""
      end if
      put char (tPos + 1) to -1 of tRest into tRest
      add 1 to tI
   end repeat
   put offset(",", tRest) into tPos
   if tPos is 0 then
      return tRest
   end if
   return char 1 to (tPos - 1) of tRest
end cwListAt

private function cwListIndex pList, pValue
   -- The 1-based position of pValue in pList, or 0. Compared exactly, because
   -- these are lookup keys and a case-folded match would quietly accept
   -- "MainNet" and then index the same row anyway - which is fine until the
   -- day a caller passes something that is nearly a network name.
   local tI, tGot
   put 1 into tI
   repeat while true
      put cwListAt(pList, tI) into tGot
      if tGot is "" then
         return 0
      end if
      if tGot is pValue then
         return tI
      end if
      add 1 to tI
      if tI > 64 then
         return 0
      end if
   end repeat
   return 0
end cwListIndex

-- ---- arrays as lists ---------------------------------------------------------
-- Every list this file passes around is an ARRAY: keys 1..n plus "n". These
-- three helpers are the whole convention, written once so no caller has to
-- remember to keep "n" in step with the elements.

function cwListNew
   local tList
   put 0 into tList["n"]
   return tList
end cwListNew

function cwListAdd pList, pValue
   -- Returns the list with pValue appended. A FUNCTION rather than a command
   -- taking a reference parameter, because xTalk arrays are values (a `put
   -- tA into tB` copies) and the by-reference spelling is not modelled by the
   -- offline runner. Copying a list per append is quadratic in principle and
   -- irrelevant in practice: the longest list this wallet builds is a few
   -- hundred UTXOs.
   local tList, tCount
   put pList into tList
   put tList["n"] + 0 into tCount
   add 1 to tCount
   put pValue into tList[tCount]
   put tCount into tList["n"]
   return tList
end cwListAdd

function cwListCount pList
   if pList["n"] is "" then
      return 0
   end if
   return pList["n"]
end cwListCount

-- ---- bytes and integers ------------------------------------------------------

function cwLeBytes pValue, pWidth
   -- pWidth little-endian bytes of a non-negative integer. Amounts reach 8
   -- bytes and satoshi values stay far below 2^53, so ordinary arithmetic is
   -- exact here; anything wider would need a hex path, and nothing here is.
   local tOut, tN, tI, tByte
   put "" into tOut
   put pValue into tN
   repeat with tI = 1 to pWidth
      put cwIntMod(tN, 256) into tByte
      put tOut & numToByte(tByte) into tOut
      put cwIntDiv(tN, 256) into tN
   end repeat
   if tN is not 0 then
      throw "wallet-core: cwLeBytes: " & pValue & " does not fit in " & pWidth & " bytes."
   end if
   return tOut
end cwLeBytes

function cwBeBytes pValue, pWidth
   local tOut, tN, tI, tByte
   put "" into tOut
   put pValue into tN
   repeat with tI = 1 to pWidth
      put cwIntMod(tN, 256) into tByte
      put numToByte(tByte) & tOut into tOut
      put cwIntDiv(tN, 256) into tN
   end repeat
   if tN is not 0 then
      throw "wallet-core: cwBeBytes: " & pValue & " does not fit in " & pWidth & " bytes."
   end if
   return tOut
end cwBeBytes

function cwLeRead pBytes
   -- A little-endian unsigned integer from however many bytes it is given.
   local tValue, tI, tCount
   put the number of bytes of pBytes into tCount
   put 0 into tValue
   repeat with tI = tCount down to 1
      put tValue * 256 + byteToNum(byte tI of pBytes) into tValue
   end repeat
   return tValue
end cwLeRead

function cwBeRead pBytes
   local tValue, tI, tCount
   put the number of bytes of pBytes into tCount
   put 0 into tValue
   repeat with tI = 1 to tCount
      put tValue * 256 + byteToNum(byte tI of pBytes) into tValue
   end repeat
   return tValue
end cwBeRead

function cwHexIsClean pHex
   -- True when pHex is an even-length run of hex digits, lower or upper case.
   -- Written as its own predicate because every entry point that takes hex
   -- needs to refuse bad input BEFORE it reaches anything that signs.
   local tCount, tI, tC
   put the number of chars of pHex into tCount
   if tCount is 0 then
      return false
   end if
   if cwIntMod(tCount, 2) is not 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      put char tI of pHex into tC
      if offset(tC, "0123456789abcdefABCDEF") is 0 then
         return false
      end if
   end repeat
   return true
end cwHexIsClean

function cwLower pText
   -- toLower is not in the subset the offline vector runner models, and this
   -- file has to be runnable there (see the header). ASCII only, which is all
   -- an address, a hex string or a bech32 HRP ever is.
   local tOut, tI, tCount, tC, tCode
   put "" into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put char tI of pText into tC
      put charToNum(tC) into tCode
      if tCode >= 65 and tCode <= 90 then
         put numToChar(tCode + 32) after tOut
      else
         put tC after tOut
      end if
   end repeat
   return tOut
end cwLower

function cwUpper pText
   local tOut, tI, tCount, tC, tCode
   put "" into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put char tI of pText into tC
      put charToNum(tC) into tCode
      if tCode >= 97 and tCode <= 122 then
         put numToChar(tCode - 32) after tOut
      else
         put tC after tOut
      end if
   end repeat
   return tOut
end cwUpper

function cwTrim pText
   -- Leading and trailing spaces, tabs, CR and LF. A pasted address arrives
   -- wearing at least one of them more often than not.
   local tStart, tEnd, tCount, tC
   put the number of chars of pText into tCount
   put 1 into tStart
   repeat while tStart <= tCount
      put char tStart of pText into tC
      if tC is not " " and charToNum(tC) is not 9 and charToNum(tC) is not 10 \
            and charToNum(tC) is not 13 then
         exit repeat
      end if
      add 1 to tStart
   end repeat
   put tCount into tEnd
   repeat while tEnd >= tStart
      put char tEnd of pText into tC
      if tC is not " " and charToNum(tC) is not 9 and charToNum(tC) is not 10 \
            and charToNum(tC) is not 13 then
         exit repeat
      end if
      subtract 1 from tEnd
   end repeat
   if tEnd < tStart then
      return ""
   end if
   return char tStart to tEnd of pText
end cwTrim

function cwVersion
   return "CoinXT Wallet core " & kCwVersion
end cwVersion

-- ==============================================================================
-- NETWORK PARAMETERS
--
-- Everything below takes a network NAME and refuses an unknown one rather than
-- defaulting to mainnet. That refusal is the whole safety property: a typo in
-- a network name must never silently produce a mainnet address, because the
-- mistake it hides is paying real coins to a key the sender generated for a
-- test.
-- ==============================================================================

private function cwNetIndex pNetwork
   local tIndex
   put cwListIndex(kCwNetworks, pNetwork) into tIndex
   if tIndex is 0 then
      throw "wallet-core: unknown network " & quote & pNetwork & quote & \
            ". Known: " & kCwNetworks & "."
   end if
   return tIndex
end cwNetIndex

function cwNetworks
   return kCwNetworks
end cwNetworks

function cwNetHrp pNetwork
   return cwListAt(kCwHrps, cwNetIndex(pNetwork))
end cwNetHrp

function cwNetP2pkhVersion pNetwork
   return cwListAt(kCwP2pkhVersions, cwNetIndex(pNetwork)) + 0
end cwNetP2pkhVersion

function cwNetP2shVersion pNetwork
   return cwListAt(kCwP2shVersions, cwNetIndex(pNetwork)) + 0
end cwNetP2shVersion

function cwNetWifVersion pNetwork
   return cwListAt(kCwWifVersions, cwNetIndex(pNetwork)) + 0
end cwNetWifVersion

function cwNetCoinType pNetwork
   return cwListAt(kCwCoinTypes, cwNetIndex(pNetwork)) + 0
end cwNetCoinType

function cwScriptTypes
   return kCwScriptTypes
end cwScriptTypes

private function cwTypeIndex pScriptType
   local tIndex
   put cwListIndex(kCwScriptTypes, pScriptType) into tIndex
   if tIndex is 0 then
      throw "wallet-core: unknown script type " & quote & pScriptType & quote & \
            ". Known: " & kCwScriptTypes & "."
   end if
   return tIndex
end cwTypeIndex

function cwTypePurpose pScriptType
   return cwListAt(kCwPurposes, cwTypeIndex(pScriptType)) + 0
end cwTypePurpose

function cwTypeStem pScriptType
   return cwListAt(kCwStems, cwTypeIndex(pScriptType))
end cwTypeStem

function cwXKeyVersion pNetwork, pScriptType, pPublic
   -- The 4-byte version an extended key of this script type carries on this
   -- network. SLIP-132 gives p2sh-p2wpkh and p2wpkh their own pairs so a bare
   -- ypub or zpub says what it is for; BIP-86 deliberately did NOT take one,
   -- so taproot answers with the plain BIP-32 xpub version and this is not an
   -- omission.
   local tNet, tStem, tRow
   put cwNetIndex(pNetwork) into tNet
   put cwTypeStem(pScriptType) into tStem
   if tStem is "x" then
      if pPublic is true then
         put kCwXpubVersions into tRow
      else
         put kCwXprvVersions into tRow
      end if
   else if tStem is "y" then
      if pPublic is true then
         put kCwYpubVersions into tRow
      else
         put kCwYprvVersions into tRow
      end if
   else if tStem is "z" then
      if pPublic is true then
         put kCwZpubVersions into tRow
      else
         put kCwZprvVersions into tRow
      end if
   else if tStem is "Y" then
      if pPublic is true then
         put kCwYshPubVersions into tRow
      else
         put kCwYshPrvVersions into tRow
      end if
   else
      if pPublic is true then
         put kCwZshPubVersions into tRow
      else
         put kCwZshPrvVersions into tRow
      end if
   end if
   return cwListAt(tRow, tNet) + 0
end cwXKeyVersion

-- ==============================================================================
-- SCRIPTS
--
-- Every scriptPubKey this wallet builds or reads, as HEX in and hex out. Hex
-- rather than raw bytes for the reason CoinXT's own phase-5 layer moves txids
-- and scripts as hex: these values are pasted, logged, compared and shown to
-- people, and a raw byte string that reaches a field is mojibake.
-- ==============================================================================

function cwPush pDataHex
   -- A minimal data push. The direct form covers 1..75 bytes, which is every
   -- push a single-key script makes; OP_PUSHDATA1 and 2 are here because a
   -- large multisig witness script reaches them and a script that silently
   -- mis-encodes its own length is unspendable.
   local tLen
   if pDataHex is "" then
      return "00"
   end if
   if cwHexIsClean(pDataHex) is not true then
      throw "wallet-core: cwPush: the payload is not hex."
   end if
   put cwIntDiv(the number of chars of pDataHex, 2) into tLen
   if tLen < 76 then
      return cxHexEncode(numToByte(tLen)) & pDataHex
   end if
   if tLen < 256 then
      return "4c" & cxHexEncode(numToByte(tLen)) & pDataHex
   end if
   if tLen < 65536 then
      return "4d" & cxHexEncode(cwLeBytes(tLen, 2)) & pDataHex
   end if
   throw "wallet-core: cwPush: a push of " & tLen & " bytes is beyond this wallet."
end cwPush

private function cwOpHex pOpcode
   return cxHexEncode(numToByte(pOpcode))
end cwOpHex

function cwScriptP2pkh pPubkeyHex
   local tHash
   put cxHexEncode(cxHash160(cxHexDecode(pPubkeyHex))) into tHash
   return cwOpHex(kCwOpDup) & cwOpHex(kCwOpHash160) & cwPush(tHash) & \
         cwOpHex(kCwOpEqualVerify) & cwOpHex(kCwOpCheckSig)
end cwScriptP2pkh

function cwScriptP2sh pScriptHashHex
   if the number of chars of pScriptHashHex is not 40 then
      throw "wallet-core: cwScriptP2sh: a script hash is 20 bytes."
   end if
   return cwOpHex(kCwOpHash160) & cwPush(pScriptHashHex) & cwOpHex(kCwOpEqual)
end cwScriptP2sh

function cwScriptP2wpkh pPubkeyHex
   local tHash
   put cxHexEncode(cxHash160(cxHexDecode(pPubkeyHex))) into tHash
   return cwOpHex(kCwOpZero) & cwPush(tHash)
end cwScriptP2wpkh

function cwScriptP2wsh pWitnessScriptHex
   local tHash
   put cxHexEncode(cxSha256(cxHexDecode(pWitnessScriptHex))) into tHash
   return cwOpHex(kCwOpZero) & cwPush(tHash)
end cwScriptP2wsh

function cwScriptP2tr pOutputKeyHex
   if the number of chars of pOutputKeyHex is not 64 then
      throw "wallet-core: cwScriptP2tr: a taproot output key is 32 bytes (x-only)."
   end if
   return cwOpHex(kCwOpOne) & cwPush(pOutputKeyHex)
end cwScriptP2tr

function cwRedeemP2shP2wpkh pPubkeyHex
   -- BIP-49's redeem script IS the P2WPKH scriptPubKey, wrapped in a P2SH.
   -- The wrapping is what let 2017-era wallets receive SegWit from software
   -- that had never heard of it.
   return cwScriptP2wpkh(pPubkeyHex)
end cwRedeemP2shP2wpkh

function cwScriptP2shP2wpkh pPubkeyHex
   local tRedeem, tHash
   put cwRedeemP2shP2wpkh(pPubkeyHex) into tRedeem
   put cxHexEncode(cxHash160(cxHexDecode(tRedeem))) into tHash
   return cwScriptP2sh(tHash)
end cwScriptP2shP2wpkh

function cwMultisigScript pM, pPubkeys, pSortBip67
   -- A bare m-of-n CHECKMULTISIG script: the witnessScript of a P2WSH
   -- multisig. BIP-67 ordering is the default because it makes the address a
   -- function of the KEY SET and not of the order somebody typed the keys in,
   -- which is what lets two cosigners independently derive the same address
   -- and discover they agree.
   local tKeys, tCount, tOut, tI, tKey
   put cwListCount(pPubkeys) into tCount
   if pM < 1 or tCount < pM or tCount > 15 then
      throw "wallet-core: cwMultisigScript: " & pM & "-of-" & tCount & \
            " is out of range (1..15, and m <= n)."
   end if
   put pPubkeys into tKeys
   if pSortBip67 is not false then
      put cwSortHexList(tKeys) into tKeys
   end if
   put cwOpHex(kCwOpOne + pM - 1) into tOut
   repeat with tI = 1 to tCount
      put tKeys[tI] into tKey
      if the number of chars of tKey is not 66 then
         throw "wallet-core: cwMultisigScript: multisig wants COMPRESSED keys " & \
               "(33 bytes); an uncompressed cosigner key changes the address."
      end if
      put cwPush(tKey) after tOut
   end repeat
   put cwOpHex(kCwOpOne + tCount - 1) & cwOpHex(kCwOpCheckMultisig) after tOut
   return tOut
end cwMultisigScript

function cwSortHexList pList
   -- Ascending lexicographic sort of a list of hex strings, by BYTE VALUE.
   -- An insertion sort, because BIP-67 lists are at most 15 long and because
   -- `sort lines of` would fold case - and these are hex strings whose case
   -- this file does not otherwise constrain, so a case-folding sort could put
   -- two cosigners' keys in different orders on different machines and give
   -- them different addresses for the same wallet.
   local tOut, tCount, tI, tJ, tValue
   put cwListCount(pList) into tCount
   put pList into tOut
   repeat with tI = 2 to tCount
      put tOut[tI] into tValue
      put tI - 1 into tJ
      repeat while tJ >= 1
         if cwHexCompare(tOut[tJ], tValue) <= 0 then
            exit repeat
         end if
         put tOut[tJ] into tOut[tJ + 1]
         subtract 1 from tJ
      end repeat
      put tValue into tOut[tJ + 1]
   end repeat
   return tOut
end cwSortHexList

function cwHexCompare pA, pB
   -- -1, 0 or 1 comparing two hex strings by the bytes they denote. Compared
   -- as NUMBERS per nibble rather than as text, so "AB" and "ab" order
   -- identically and neither `the caseSensitive` nor a locale can move them.
   local tA, tB, tCount, tI, tVa, tVb
   put cwLower(pA) into tA
   put cwLower(pB) into tB
   put cwMin(the number of chars of tA, the number of chars of tB) into tCount
   repeat with tI = 1 to tCount
      put offset(char tI of tA, kCwHexDigits) into tVa
      put offset(char tI of tB, kCwHexDigits) into tVb
      if tVa < tVb then
         return -1
      end if
      if tVa > tVb then
         return 1
      end if
   end repeat
   if the number of chars of tA < the number of chars of tB then
      return -1
   end if
   if the number of chars of tA > the number of chars of tB then
      return 1
   end if
   return 0
end cwHexCompare

-- ==============================================================================
-- ADDRESSES, both directions
--
-- The direction a SEND needs is address -> scriptPubKey, and it is the one
-- that must fail closed: a cross-network address, a bad checksum or a witness
-- program of the wrong length is a REFUSAL here, never a coercion. The
-- direction a HISTORY view needs is scriptPubKey -> address, and it must
-- answer for scripts this wallet did not create.
-- ==============================================================================

function cwAddressForScript pNetwork, pScriptHex
   local tHex, tLen, tHrp, tVer, tProgram, tOpcode, tLenProg
   put cwLower(pScriptHex) into tHex
   put the number of chars of tHex into tLen
   put cwNetHrp(pNetwork) into tHrp
   -- P2PKH: OP_DUP OP_HASH160 <20> OP_EQUALVERIFY OP_CHECKSIG
   if tLen is 50 and char 1 to 6 of tHex is "76a914" and char 47 to 50 of tHex is "88ac" then
      return cxBase58CheckEncode(numToByte(cwNetP2pkhVersion(pNetwork)) & \
            cxHexDecode(char 7 to 46 of tHex))
   end if
   -- P2SH: OP_HASH160 <20> OP_EQUAL
   if tLen is 46 and char 1 to 4 of tHex is "a914" and char 45 to 46 of tHex is "87" then
      return cxBase58CheckEncode(numToByte(cwNetP2shVersion(pNetwork)) & \
            cxHexDecode(char 5 to 44 of tHex))
   end if
   -- a witness program: a version opcode, then a single push of 2..40 bytes
   if tLen >= 8 then
      put char 1 to 2 of tHex into tOpcode
      put -1 into tVer
      if tOpcode is "00" then
         put 0 into tVer
      else if offset(tOpcode, "51,52,53,54,55,56,57,58,59,5a,5b,5c,5d,5e,5f,60") is not 0 then
         put cwBeRead(cxHexDecode(tOpcode)) - kCwOpOne + 1 into tVer
      end if
      if tVer >= 0 then
         put char 5 to -1 of tHex into tProgram
         put the number of chars of tProgram into tLenProg
         if cwBeRead(cxHexDecode(char 3 to 4 of tHex)) * 2 is tLenProg then
            if tVer is 0 and tLenProg is not 40 and tLenProg is not 64 then
               throw "wallet-core: a version-0 witness program is 20 or 32 bytes."
            end if
            return cxSegwitAddressEncode(tHrp, tVer, cxHexDecode(tProgram))
         end if
      end if
   end if
   throw "wallet-core: this scriptPubKey is not a standard wallet output: " & tHex
end cwAddressForScript

function cwScriptForAddress pNetwork, pAddress
   local tAddr, tHrp, tDecoded, tVer, tProgram, tPayload, tVersion, tHash, tCut
   put cwTrim(pAddress) into tAddr
   if tAddr is "" then
      throw "wallet-core: an empty address."
   end if
   put cwNetHrp(pNetwork) into tHrp
   -- the HRP plus its separator: computed into a local because
   -- `the number of chars of X + 1` binds the addition INTO the chunk
   -- target, which is a different (and silently wrong) expression
   put the number of chars of tHrp into tCut
   add 1 to tCut
   if cwLower(char 1 to tCut of tAddr) is (tHrp & "1") then
      put cxSegwitAddressDecode(tHrp, tAddr) into tDecoded
      put tDecoded["version"] into tVer
      put cxHexEncode(tDecoded["program"]) into tProgram
      if tVer is 0 then
         return "00" & cwPush(tProgram)
      end if
      return cwOpHex(kCwOpOne + tVer - 1) & cwPush(tProgram)
   end if
   put cxBase58CheckDecode(tAddr) into tPayload
   if the number of bytes of tPayload is not 21 then
      throw "wallet-core: " & tAddr & " is neither a valid bech32 nor a valid " & \
            "base58check address for " & pNetwork & "."
   end if
   put byteToNum(byte 1 of tPayload) into tVersion
   put cxHexEncode(byte 2 to 21 of tPayload) into tHash
   if tVersion is cwNetP2pkhVersion(pNetwork) then
      return cwOpHex(kCwOpDup) & cwOpHex(kCwOpHash160) & cwPush(tHash) & \
            cwOpHex(kCwOpEqualVerify) & cwOpHex(kCwOpCheckSig)
   end if
   if tVersion is cwNetP2shVersion(pNetwork) then
      return cwOpHex(kCwOpHash160) & cwPush(tHash) & cwOpHex(kCwOpEqual)
   end if
   throw "wallet-core: base58 version byte " & tVersion & " is not a " & \
         pNetwork & " address. Paying a " & pNetwork & " transaction to an " & \
         "address from another network sends the coins nowhere recoverable."
end cwScriptForAddress

function cwScriptKind pScriptHex
   -- The output type a scriptPubKey is, by shape alone, with no network in
   -- the question. "unknown" rather than a throw: a history view meets
   -- OP_RETURN and bare-multisig outputs in the wild and must be able to say
   -- so rather than refuse to render the transaction.
   local tHex, tLen
   put cwLower(pScriptHex) into tHex
   put the number of chars of tHex into tLen
   if tLen is 50 and char 1 to 6 of tHex is "76a914" and char 47 to 50 of tHex is "88ac" then
      return "p2pkh"
   end if
   if tLen is 46 and char 1 to 4 of tHex is "a914" and char 45 to 46 of tHex is "87" then
      return "p2sh"
   end if
   if tLen is 44 and char 1 to 4 of tHex is "0014" then
      return "p2wpkh"
   end if
   if tLen is 68 and char 1 to 4 of tHex is "0020" then
      return "p2wsh"
   end if
   if tLen is 68 and char 1 to 4 of tHex is "5120" then
      return "p2tr"
   end if
   if tLen >= 2 and char 1 to 2 of tHex is "6a" then
      return "nulldata"
   end if
   return "unknown"
end cwScriptKind

function cwAddressKind pNetwork, pAddress
   return cwScriptKind(cwScriptForAddress(pNetwork, pAddress))
end cwAddressKind

function cwAddressIsValid pNetwork, pAddress
   -- A predicate that never throws, because the Send screen asks this on every
   -- keystroke and an exception per character is not a validator.
   local tError, tOk
   put false into tOk
   try
      get cwScriptForAddress(pNetwork, pAddress)
      put true into tOk
   catch tError
      put false into tOk
   end try
   return tOk
end cwAddressIsValid

function cwAddressProblem pNetwork, pAddress
   -- Empty when the address is good, otherwise the reason. Separate from the
   -- predicate above because a Send screen wants to SAY what is wrong, and
   -- returning the message from the predicate would make every caller test a
   -- string for emptiness to learn a boolean.
   local tError, tWhy
   put "" into tWhy
   try
      get cwScriptForAddress(pNetwork, pAddress)
   catch tError
      put tError into tWhy
   end try
   return tWhy
end cwAddressProblem

function cwElectrumScripthash pScriptHex
   -- Electrum's scripthash: SHA-256 of the scriptPubKey, REVERSED, as hex.
   -- The reversal is the part everybody gets wrong once - the protocol shows
   -- the hash in the same little-endian display order as a txid - and getting
   -- it wrong means every address looks unused, which reads as an empty
   -- wallet rather than as a bug.
   return cxHexEncode(cwReverseBytes(cxSha256(cxHexDecode(pScriptHex))))
end cwElectrumScripthash

function cwReverseBytes pData
   local tOut, tI, tCount
   put "" into tOut
   put the number of bytes of pData into tCount
   repeat with tI = tCount down to 1
      put tOut & byte tI of pData into tOut
   end repeat
   return tOut
end cwReverseBytes

-- ==============================================================================
-- DERIVATION PATHS AND EXTENDED KEYS
--
-- CoinXT owns the BIP-32 arithmetic (cxHdFromSeed, cxHdDeriveChild,
-- cxHdDerivePath, cxHdNeuter) and serializes a node as xprv/xpub only. What is
-- added here is every OTHER version prefix - tpub for testnet, and SLIP-132's
-- ypub/zpub/upub/vpub and their capital-letter multisig forms - because a
-- wallet has to read the key a person pastes in, and people paste zpubs.
-- ==============================================================================

function cwParsePath pPath
   -- "m/84'/0'/0'/0/5" -> a list of child numbers, hardened levels carrying
   -- the 0x80000000 bit. Apostrophe, h and H are all accepted as the hardened
   -- marker because all three are in circulation and refusing one would reject
   -- a correct path a person copied from correct documentation.
   local tText, tOut, tLevel, tPos, tHard, tNumber, tCount, tI, tC
   put cwTrim(pPath) into tText
   put cwListNew() into tOut
   if tText is "m" or tText is "" then
      return tOut
   end if
   if char 1 to 2 of tText is "m/" then
      delete char 1 to 2 of tText
   else if char 1 of tText is "/" then
      delete char 1 of tText
   end if
   if tText is "" then
      throw "wallet-core: cwParsePath: " & quote & pPath & quote & \
            " ends with a separator and names no level."
   end if
   repeat while true
      put offset("/", tText) into tPos
      if tPos is 0 then
         put tText into tLevel
         put "" into tText
      else
         put char 1 to (tPos - 1) of tText into tLevel
         put char (tPos + 1) to -1 of tText into tText
      end if
      if tLevel is "" then
         throw "wallet-core: cwParsePath: an empty level in " & quote & pPath & quote & "."
      end if
      put false into tHard
      put char -1 of tLevel into tC
      put the number of chars of tLevel into tCount
      if tC is "'" or tC is "h" or tC is "H" then
         put true into tHard
         subtract 1 from tCount
         put char 1 to tCount of tLevel into tLevel
      end if
      if tCount is 0 then
         throw "wallet-core: cwParsePath: a level with no number in " & quote & pPath & quote & "."
      end if
      repeat with tI = 1 to tCount
         if offset(char tI of tLevel, "0123456789") is 0 then
            throw "wallet-core: cwParsePath: " & quote & tLevel & quote & \
                  " is not a child number."
         end if
      end repeat
      put tLevel + 0 into tNumber
      if tNumber > 2147483647 then
         throw "wallet-core: cwParsePath: level " & tNumber & " is out of range."
      end if
      if tHard is true then
         add 2147483648 to tNumber
      end if
      put cwListAdd(tOut, tNumber) into tOut
      if tText is "" then
         exit repeat
      end if
   end repeat
   return tOut
end cwParsePath

function cwFormatPath pLevels
   local tOut, tI, tCount, tN
   put "m" into tOut
   put cwListCount(pLevels) into tCount
   repeat with tI = 1 to tCount
      put pLevels[tI] + 0 into tN
      if tN >= 2147483648 then
         put "/" & (tN - 2147483648) & "'" after tOut
      else
         put "/" & tN after tOut
      end if
   end repeat
   return tOut
end cwFormatPath

function cwAccountPath pScriptType, pNetwork, pAccount
   -- The standard account path for a script type. BIP-48 gives multisig a
   -- fifth hardened level naming the script type, which is why the p2wsh row
   -- is one level deeper than the others rather than the same shape.
   local tPath
   put "m/" & cwTypePurpose(pScriptType) & "'/" & cwNetCoinType(pNetwork) & \
         "'/" & pAccount & "'" into tPath
   if pScriptType is "p2wsh" then
      put "/2'" after tPath
   end if
   return tPath
end cwAccountPath

function cwFingerprint pPubkeyHex
   return cxHexEncode(byte 1 to 4 of cxHash160(cxHexDecode(pPubkeyHex)))
end cwFingerprint

function cwXKeyEncode pNode, pVersion, pPrivate
   -- BIP-32's 78 bytes with a chosen version: version, depth, parent
   -- fingerprint, child number, chain code, then 33 key bytes - a private key
   -- padded to 33 by a leading zero, or the compressed public key as is.
   local tOut
   if pNode["depth"] > 255 then
      throw "wallet-core: cwXKeyEncode: BIP-32 stores the depth in one byte."
   end if
   if pPrivate is true and pNode["seckey"] is "" then
      throw "wallet-core: cwXKeyEncode: this node has no private key."
   end if
   put cwBeBytes(pVersion, 4) into tOut
   put numToByte(pNode["depth"]) after tOut
   put pNode["parentfp"] after tOut
   put cwBeBytes(pNode["index"], 4) after tOut
   put pNode["chaincode"] after tOut
   if pPrivate is true then
      put numToByte(0) & pNode["seckey"] after tOut
   else
      put pNode["pubkey"] after tOut
   end if
   return cxBase58CheckEncode(tOut)
end cwXKeyEncode

function cwXKeyDecode pText
   -- The inverse, plus the network and script type the version byte names.
   -- Refuses a version it does not know rather than guessing mainnet, because
   -- guessing here means deriving a mainnet address from a testnet key.
   local tRaw, tNode, tVersion, tBody, tNet, tStem, tI, tJ, tPub, tPrv
   put cxBase58CheckDecode(cwTrim(pText)) into tRaw
   if the number of bytes of tRaw is not 78 then
      throw "wallet-core: cwXKeyDecode: an extended key is 78 bytes; got " & \
            the number of bytes of tRaw & "."
   end if
   put cwBeRead(byte 1 to 4 of tRaw) into tVersion
   put tVersion into tNode["version"]
   put byteToNum(byte 5 of tRaw) into tNode["depth"]
   put byte 6 to 9 of tRaw into tNode["parentfp"]
   put cwBeRead(byte 10 to 13 of tRaw) into tNode["index"]
   put byte 14 to 45 of tRaw into tNode["chaincode"]
   put byte 46 to 78 of tRaw into tBody
   if byteToNum(byte 1 of tBody) is 0 then
      put byte 2 to 33 of tBody into tNode["seckey"]
      put cxPublicKey(tNode["seckey"], true) into tNode["pubkey"]
      put "private" into tNode["kind"]
   else
      if byteToNum(byte 1 of tBody) is not 2 and byteToNum(byte 1 of tBody) is not 3 then
         throw "wallet-core: cwXKeyDecode: the key is neither a padded private " & \
               "key nor a compressed public point."
      end if
      put tBody into tNode["pubkey"]
      put "" into tNode["seckey"]
      put "public" into tNode["kind"]
   end if
   put "" into tNode["network"]
   repeat with tI = 1 to 4
      put cwListAt(kCwNetworks, tI) into tNet
      repeat with tJ = 1 to 5
         put cwListAt(kCwScriptTypes, tJ) into tStem
         put cwXKeyVersion(tNet, tStem, true) into tPub
         put cwXKeyVersion(tNet, tStem, false) into tPrv
         if tVersion is tPub or tVersion is tPrv then
            put tNet into tNode["network"]
            put cwTypeStem(tStem) into tNode["stem"]
            put tStem into tNode["scripttype"]
            return tNode
         end if
      end repeat
   end repeat
   throw "wallet-core: cwXKeyDecode: extended key version " & tVersion & \
         " belongs to no network this wallet knows."
end cwXKeyDecode

function cwXKeyIsPrivate pText
   local tNode
   put cwXKeyDecode(pText) into tNode
   return tNode["kind"] is "private"
end cwXKeyIsPrivate

function cwAccountXKey pMaster, pScriptType, pNetwork, pAccount, pPrivate
   -- The account-level extended key a wallet exports: derive the account path
   -- from the master node and serialize it with the version its script type
   -- takes. This is the string a watch-only wallet is restored from, so it
   -- must be the exact string other wallets produce for the same seed.
   local tNode
   put cxHdDerivePath(pMaster, cwAccountPath(pScriptType, pNetwork, pAccount)) into tNode
   if pPrivate is not true then
      put cxHdNeuter(tNode) into tNode
   end if
   return cwXKeyEncode(tNode, cwXKeyVersion(pNetwork, pScriptType, pPrivate is not true), \
         pPrivate is true)
end cwAccountXKey

function cwChainNode pAccountNode, pChange, pIndex
   -- The two NON-hardened steps from an account node to one address key. Two
   -- steps and not a path string because this is the inner loop of a gap-limit
   -- scan - hundreds of calls - and because both steps must be non-hardened or
   -- a watch-only wallet holding only the account xpub could not follow them,
   -- which is the entire point of the account level being where it is.
   local tNode
   put cxHdDeriveChild(pAccountNode, pChange) into tNode
   return cxHdDeriveChild(tNode, pIndex)
end cwChainNode

function cwAddressAt pAccountNode, pScriptType, pNetwork, pChange, pIndex
   -- One derived address and everything the wallet needs to spend from it.
   local tNode, tOut, tPub, tTweak
   put cwChainNode(pAccountNode, pChange, pIndex) into tNode
   put cxHexEncode(tNode["pubkey"]) into tPub
   put tPub into tOut["pubkey"]
   put pIndex into tOut["index"]
   put pChange into tOut["change"]
   put pScriptType into tOut["scripttype"]
   put "/" & pChange & "/" & pIndex into tOut["suffix"]
   if pScriptType is "p2pkh" then
      put cwScriptP2pkh(tPub) into tOut["script"]
   else if pScriptType is "p2wpkh" then
      put cwScriptP2wpkh(tPub) into tOut["script"]
   else if pScriptType is "p2sh-p2wpkh" then
      put cwScriptP2shP2wpkh(tPub) into tOut["script"]
      put cwRedeemP2shP2wpkh(tPub) into tOut["redeem"]
   else if pScriptType is "p2tr" then
      -- BIP-86: the internal key is the x-only form of the derived key (the
      -- 33-byte compressed point with its parity byte dropped) and the output
      -- key is that key tweaked by an EMPTY merkle root - which is NOT the
      -- same as a root of 32 zero bytes, and confusing the two produces a
      -- different, unspendable address. cxTaprootTweak takes and returns
      -- BYTES, so the x-only key is sliced off the node's binary public key
      -- rather than off its hex.
      put cxTaprootTweak(byte 2 to 33 of tNode["pubkey"], "") into tTweak
      put cxHexEncode(tTweak["outputKey"]) into tOut["outputkey"]
      put tTweak["parity"] into tOut["parity"]
      put cxHexEncode(byte 2 to 33 of tNode["pubkey"]) into tOut["internalkey"]
      put cwScriptP2tr(tOut["outputkey"]) into tOut["script"]
   else
      throw "wallet-core: cwAddressAt: " & pScriptType & " is a multisig type; " & \
            "use cwMultisigAddressAt, which needs every cosigner's key."
   end if
   put cwAddressForScript(pNetwork, tOut["script"]) into tOut["address"]
   if tNode["seckey"] is not "" then
      put cxHexEncode(tNode["seckey"]) into tOut["seckey"]
   else
      put "" into tOut["seckey"]
   end if
   return tOut
end cwAddressAt

function cwMultisigAddressAt pAccountNodes, pM, pNetwork, pChange, pIndex, pSortBip67
   -- The m-of-n P2WSH address at one chain position: derive the same
   -- /change/index step under EVERY cosigner's account key, build the witness
   -- script from the derived keys, and hash it. Every cosigner doing this
   -- independently must land on the same address, which is what BIP-67
   -- ordering is for.
   local tKeys, tI, tCount, tNode, tOut, tScript
   put cwListCount(pAccountNodes) into tCount
   put cwListNew() into tKeys
   repeat with tI = 1 to tCount
      put cwChainNode(pAccountNodes[tI], pChange, pIndex) into tNode
      put cwListAdd(tKeys, cxHexEncode(tNode["pubkey"])) into tKeys
   end repeat
   put cwMultisigScript(pM, tKeys, pSortBip67) into tScript
   put tScript into tOut["witnessscript"]
   put cwScriptP2wsh(tScript) into tOut["script"]
   put cwAddressForScript(pNetwork, tOut["script"]) into tOut["address"]
   put pIndex into tOut["index"]
   put pChange into tOut["change"]
   put "p2wsh" into tOut["scripttype"]
   put pM into tOut["m"]
   put tCount into tOut["cosigners"]
   put tKeys into tOut["pubkeys"]
   return tOut
end cwMultisigAddressAt

-- ==============================================================================
-- AMOUNTS
--
-- Satoshi are integers; BTC is a DISPLAY form. Every conversion here is exact
-- integer and string arithmetic, and nothing rounds through a float. That is
-- not caution for its own sake: a double loses satoshi precision above about
-- 90 million BTC, and long before that "0.1 + 0.2" is the oldest bug in money
-- software. A wallet that shows a balance one satoshi off has lost the user's
-- trust in every other number on the screen.
-- ==============================================================================

function cwSatToBtc pSat
   local tSat, tSign, tWhole, tFrac, tText
   put pSat into tSat
   put "" into tSign
   if tSat < 0 then
      put "-" into tSign
      put 0 - tSat into tSat
   end if
   put cwIntDiv(tSat, 100000000) into tWhole
   put tSat - tWhole * 100000000 into tFrac
   put tFrac into tText
   repeat while the number of chars of tText < 8
      put "0" & tText into tText
   end repeat
   return tSign & tWhole & "." & tText
end cwSatToBtc

function cwBtcToSat pText
   local tText, tSign, tWhole, tFrac, tPos, tI, tCount
   put cwTrim(pText) into tText
   if tText is "" then
      throw "wallet-core: cwBtcToSat: an empty amount."
   end if
   put "" into tSign
   if char 1 of tText is "-" then
      put "-" into tSign
      put char 2 to -1 of tText into tText
   end if
   put offset(".", tText) into tPos
   if tPos is 0 then
      put tText into tWhole
      put "" into tFrac
   else
      put char 1 to (tPos - 1) of tText into tWhole
      put char (tPos + 1) to -1 of tText into tFrac
      if offset(".", tFrac) is not 0 then
         throw "wallet-core: cwBtcToSat: more than one decimal point."
      end if
   end if
   if tWhole is "" then
      put "0" into tWhole
   end if
   put the number of chars of tWhole into tCount
   repeat with tI = 1 to tCount
      if offset(char tI of tWhole, "0123456789") is 0 then
         throw "wallet-core: cwBtcToSat: " & quote & pText & quote & \
               " is not a decimal amount."
      end if
   end repeat
   put the number of chars of tFrac into tCount
   repeat with tI = 1 to tCount
      if offset(char tI of tFrac, "0123456789") is 0 then
         throw "wallet-core: cwBtcToSat: " & quote & pText & quote & \
               " is not a decimal amount."
      end if
   end repeat
   if tCount > 8 then
      throw "wallet-core: cwBtcToSat: a satoshi is the smallest unit, so an " & \
            "amount carries at most 8 decimals; " & quote & pText & quote & \
            " has " & tCount & "."
   end if
   repeat while the number of chars of tFrac < 8
      put tFrac & "0" into tFrac
   end repeat
   if tSign is "-" then
      return 0 - (tWhole * 100000000 + tFrac)
   end if
   return tWhole * 100000000 + tFrac
end cwBtcToSat

function cwFormatAmount pSat, pUnit
   -- The three units a wallet offers, and nothing between them: BTC with all
   -- eight decimals, mBTC with five, and raw satoshi. Trailing zeros are KEPT
   -- in BTC because a column of amounts that all end at the same place is
   -- readable and a ragged one is not.
   if pUnit is "sat" then
      return pSat & " sat"
   end if
   if pUnit is "mBTC" then
      return cwSatToBtc(pSat * 1000) & " mBTC"
   end if
   return cwSatToBtc(pSat) & " BTC"
end cwFormatAmount

function cwParseAmount pText, pUnit
   local tText
   put cwTrim(pText) into tText
   if pUnit is "sat" then
      if tText is not an integer then
         throw "wallet-core: cwParseAmount: satoshi are whole numbers."
      end if
      return tText + 0
   end if
   if pUnit is "mBTC" then
      return cwIntDiv(cwBtcToSat(tText), 1000)
   end if
   return cwBtcToSat(tText)
end cwParseAmount

-- ==============================================================================
-- SIZE, WEIGHT AND FEES
--
-- Every figure here is the WORST case, and worst case is the only safe
-- direction. Underestimating a transaction's virtual size underpays its fee,
-- and an underpaid transaction does not fail loudly: it sits in nobody's
-- mempool while the person who sent it watches an explorer and wonders. A
-- DER-encoded low-S ECDSA signature is 71 or 72 bytes depending on one leading
-- zero, so 72 is budgeted; BIP-340's Schnorr signature is exactly 64.
-- ==============================================================================

function cwVarIntLen pN
   if pN < 253 then
      return 1
   end if
   if pN < 65536 then
      return 3
   end if
   if pN < 4294967296 then
      return 5
   end if
   return 9
end cwVarIntLen

function cwInputBaseBytes pType, pM, pCosigners
   -- The non-witness bytes one input contributes: outpoint, the scriptSig
   -- length prefix, the scriptSig itself and the sequence.
   local tSig
   if pType is "p2pkh" then
      put 1 + kCwSigBytes + 1 + kCwPubkeyBytes into tSig
   else if pType is "p2sh-p2wpkh" then
      put 1 + 1 + 1 + 20 into tSig
   else
      put 0 into tSig
   end if
   return 32 + 4 + cwVarIntLen(tSig) + tSig + 4
end cwInputBaseBytes

function cwInputWitnessBytes pType, pM, pCosigners
   -- The witness bytes one input contributes, INCLUDING the item count. A
   -- non-witness input still contributes one byte (an empty stack) whenever
   -- any other input in the transaction is a witness input, which is the part
   -- a naive estimator forgets and then underpays a mixed-input spend.
   local tScript
   if pType is "p2wpkh" or pType is "p2sh-p2wpkh" then
      return 1 + 1 + kCwSigBytes + 1 + kCwPubkeyBytes
   end if
   if pType is "p2tr" then
      return 1 + 1 + kCwSchnorrSigBytes
   end if
   if pType is "p2wsh" then
      put 1 + pCosigners * 34 + 2 into tScript
      return 1 + 1 + pM * (1 + kCwSigBytes) + cwVarIntLen(tScript) + tScript
   end if
   return 0
end cwInputWitnessBytes

function cwOutputBytes pType
   if pType is "p2pkh" then
      return 8 + 1 + 25
   end if
   if pType is "p2sh" or pType is "p2sh-p2wpkh" then
      return 8 + 1 + 23
   end if
   if pType is "p2wpkh" then
      return 8 + 1 + 22
   end if
   if pType is "p2wsh" or pType is "p2tr" then
      return 8 + 1 + 34
   end if
   throw "wallet-core: cwOutputBytes: unknown output type " & pType & "."
end cwOutputBytes

function cwEstimateVsize pInputs, pOutputs
   -- pInputs is a list of arrays with "type" and, for p2wsh, "m" and
   -- "cosigners". pOutputs is a list of type names. Returns virtual bytes,
   -- rounded UP: the network charges by weight and gives nobody the fraction.
   local tBase, tWit, tI, tCount, tSpec, tType, tAnyWitness, tWeight
   put cwListCount(pInputs) into tCount
   put 4 + 4 into tBase
   add cwVarIntLen(tCount) to tBase
   add cwVarIntLen(cwListCount(pOutputs)) to tBase
   put 0 into tWit
   put false into tAnyWitness
   repeat with tI = 1 to tCount
      put pInputs[tI] into tSpec
      put tSpec["type"] into tType
      add cwInputBaseBytes(tType, tSpec["m"], tSpec["cosigners"]) to tBase
      add cwInputWitnessBytes(tType, tSpec["m"], tSpec["cosigners"]) to tWit
      if tType is not "p2pkh" then
         put true into tAnyWitness
      end if
   end repeat
   put cwListCount(pOutputs) into tCount
   repeat with tI = 1 to tCount
      add cwOutputBytes(pOutputs[tI]) to tBase
   end repeat
   if tAnyWitness is true then
      add 2 to tWit
      put cwListCount(pInputs) into tCount
      repeat with tI = 1 to tCount
         put pInputs[tI] into tSpec
         if tSpec["type"] is "p2pkh" then
            add 1 to tWit
         end if
      end repeat
   end if
   put tBase * 4 + tWit into tWeight
   return cwCeilDiv(tWeight, 4)
end cwEstimateVsize

function cwSimpleInputs pType, pCount, pM, pCosigners
   -- The common shape: pCount inputs all of one type. Written once because
   -- every caller that wanted it was building the same three-line loop.
   local tList, tI, tSpec
   put cwListNew() into tList
   put pType into tSpec["type"]
   put pM into tSpec["m"]
   put pCosigners into tSpec["cosigners"]
   repeat with tI = 1 to pCount
      put cwListAdd(tList, tSpec) into tList
   end repeat
   return tList
end cwSimpleInputs

function cwFeeFor pVsize, pSatPerVb
   -- The fee at a rate given in sat/vB, which may be fractional (1.5 sat/vB
   -- is an ordinary setting). Multiplied out in thousandths and divided with
   -- a CEILING, because a fee rounded down is a rate below the one the user
   -- chose and relay rules are a floor, not a target.
   return cwCeilDiv(trunc(pVsize * pSatPerVb * 1000 + 0.5), 1000)
end cwFeeFor

function cwDustThreshold pType
   -- Bitcoin Core's rule: an output is dust when spending it would cost more
   -- than a third of its value at the 3000 sat/kvB dust relay fee. The
   -- familiar 546 (P2PKH), 540 (P2SH), 330 (P2WSH and P2TR) and 294 (P2WPKH)
   -- all fall out of this, so the numbers are DERIVED here rather than
   -- written down.
   local tSpend, tSize
   if pType is "p2wpkh" or pType is "p2wsh" or pType is "p2tr" then
      put kCwDustSpendWitness into tSpend
   else
      put kCwDustSpendLegacy into tSpend
   end if
   put cwOutputBytes(pType) into tSize
   return (tSize + tSpend) * 3
end cwDustThreshold

function cwRbfMinFee pOldFee, pNewVsize
   -- BIP-125 rule 3 and 4: a replacement must pay the whole fee the
   -- transactions it evicts paid, PLUS the incremental relay fee over its own
   -- size. Returned as a floor for the Send screen to enforce, because a
   -- replacement rejected for underpaying looks to the user exactly like a
   -- replacement that vanished.
   return pOldFee + pNewVsize * kCwIncrementalRelayFee
end cwRbfMinFee

-- ==============================================================================
-- COIN SELECTION
--
-- Four strategies, because they trade different things and no one of them is
-- right for every spend.
--
--   bnb       branch and bound (Murch's algorithm, what Bitcoin Core reaches
--             for first): look for a subset that pays the amount and the fee
--             with a remainder too small to be worth an output, and make NO
--             CHANGE AT ALL. An output the wallet never creates is an output
--             nobody can link to it, so this is the privacy-preserving answer
--             as well as the cheap one. Falls back to largest-first when no
--             such subset exists, which is most of the time.
--   largest   fewest inputs, smallest transaction, lowest fee.
--   smallest  consolidate dust while fees are low.
--   oldest    spend the most-confirmed coins first.
--   manual    exactly the coins the user ticked in the Coins screen, and a
--             clean refusal if they do not cover the spend.
--
-- ALL OF THEM ARE DETERMINISTIC. No shuffling, no randomness anywhere: the
-- same wallet state and the same request produce the same transaction, which
-- is what lets a vector gate pin this and what lets a person compare two runs
-- and believe the difference means something.
--
-- THE INVARIANT EVERY BRANCH HOLDS, and the one a hand-rolled selector
-- usually breaks:
--
--     total_in == target + fee + change,   with change 0 or >= dust
--
-- A selector that returns a change output below the dust threshold has built
-- a transaction the network will not relay, and the failure arrives as a
-- rejection with no explanation. Where the remainder is under dust this code
-- BURNS IT INTO THE FEE rather than creating the output - which is what
-- every other wallet does, and is worth saying out loud because it means the
-- user pays a fee slightly above the rate they asked for.
-- ==============================================================================

private function cwInputCost pInputType, pFeeRate, pM, pCosigners
   -- What one more input of this type costs in fee at this rate: the
   -- difference the input makes to the transaction's virtual size, priced.
   local tOne, tNone, tSpec, tListOne, tListNone
   put cwSimpleInputs(pInputType, 1, pM, pCosigners) into tListOne
   put cwListNew() into tListNone
   put cwEstimateVsize(tListOne, cwListNew()) into tOne
   put cwEstimateVsize(tListNone, cwListNew()) into tNone
   return cwFeeFor(cwMax(tOne - tNone, 1), pFeeRate)
end cwInputCost

function cwSelectCoins pUtxos, pTargetSat, pFeeRate, pInputType, pOutputTypes, pChangeType, pStrategy, pM, pCosigners
   -- pUtxos: a list of arrays with "value" (satoshi) and optionally "frozen",
   -- "selected", "confirmations", "txid", "vout". Returns an array carrying
   -- "ok", "why", "selected" (a list), "fee", "change", "totalin", "vsize"
   -- and "strategy".
   local tPool, tI, tCount, tCoin, tResult, tStrategy, tDust, tSel, tOut
   local tVsize, tFee, tTotal, tChange, tSurplus, tOuts, tIns
   put pStrategy into tStrategy
   if tStrategy is "" then
      put "bnb" into tStrategy
   end if
   put cwListNew() into tPool
   put cwListCount(pUtxos) into tCount
   repeat with tI = 1 to tCount
      put pUtxos[tI] into tCoin
      if tStrategy is "manual" then
         if tCoin["selected"] is true then
            put cwListAdd(tPool, tCoin) into tPool
         end if
      else if tCoin["frozen"] is not true then
         put cwListAdd(tPool, tCoin) into tPool
      end if
   end repeat
   if cwListCount(tPool) is 0 then
      put false into tOut["ok"]
      if tStrategy is "manual" then
         put "no coins are selected" into tOut["why"]
      else
         put "no spendable coins (every coin is frozen, or the wallet is empty)" into tOut["why"]
      end if
      put cwListNew() into tOut["selected"]
      put 0 into tOut["fee"]
      put 0 into tOut["change"]
      put 0 into tOut["totalin"]
      put 0 into tOut["vsize"]
      put tStrategy into tOut["strategy"]
      return tOut
   end if
   put cwDustThreshold(pChangeType) into tDust
   if tStrategy is "bnb" then
      put cwBranchAndBound(tPool, pTargetSat, pFeeRate, pInputType, pOutputTypes, \
            pChangeType, pM, pCosigners) into tResult
      if tResult["ok"] is true then
         return tResult
      end if
      put "largest" into tStrategy
   end if
   put cwSortCoins(tPool, tStrategy) into tPool
   put cwListNew() into tSel
   put cwListCount(tPool) into tCount
   repeat with tI = 1 to tCount
      put cwListAdd(tSel, tPool[tI]) into tSel
      put cwSelectionResult(tSel, pTargetSat, pFeeRate, pInputType, pOutputTypes, \
            pChangeType, true, pM, pCosigners) into tResult
      if tResult["change"] >= tDust then
         put true into tResult["ok"]
         put "with change" into tResult["why"]
         put tStrategy into tResult["strategy"]
         return tResult
      end if
      put cwSelectionResult(tSel, pTargetSat, pFeeRate, pInputType, pOutputTypes, \
            pChangeType, false, pM, pCosigners) into tResult
      put tResult["totalin"] - pTargetSat - tResult["fee"] into tSurplus
      if tSurplus >= 0 and tSurplus < tDust then
         put tResult["totalin"] - pTargetSat into tResult["fee"]
         put 0 into tResult["change"]
         put true into tResult["ok"]
         put "changeless: the remainder is below the dust threshold and goes to the miner" \
               into tResult["why"]
         put tStrategy into tResult["strategy"]
         return tResult
      end if
   end repeat
   put cwSelectionResult(tPool, pTargetSat, pFeeRate, pInputType, pOutputTypes, \
         pChangeType, true, pM, pCosigners) into tResult
   put false into tResult["ok"]
   if tStrategy is "manual" then
      put "the coins you picked do not cover the amount plus the fee" into tResult["why"]
   else
      put "insufficient funds" into tResult["why"]
   end if
   put tStrategy into tResult["strategy"]
   return tResult
end cwSelectCoins

private function cwSelectionResult pSel, pTargetSat, pFeeRate, pInputType, pOutputTypes, pChangeType, pWithChange, pM, pCosigners
   local tOuts, tIns, tI, tCount, tVsize, tFee, tTotal, tOut
   put pOutputTypes into tOuts
   if pWithChange is true then
      put cwListAdd(tOuts, pChangeType) into tOuts
   end if
   put cwListCount(pSel) into tCount
   put cwSimpleInputs(pInputType, tCount, pM, pCosigners) into tIns
   put cwEstimateVsize(tIns, tOuts) into tVsize
   put cwFeeFor(tVsize, pFeeRate) into tFee
   put 0 into tTotal
   repeat with tI = 1 to tCount
      put pSel[tI] into tOut
      add tOut["value"] to tTotal
   end repeat
   put pSel into tOut["selected"]
   put tFee into tOut["fee"]
   put tTotal into tOut["totalin"]
   put tVsize into tOut["vsize"]
   if pWithChange is true then
      put tTotal - pTargetSat - tFee into tOut["change"]
   else
      put 0 into tOut["change"]
   end if
   return tOut
end cwSelectionResult

private function cwSortCoins pPool, pStrategy
   -- Insertion sort with an explicit tie-break on txid and vout, so two coins
   -- of the same value always order the same way and the selector is
   -- reproducible across runs and machines.
   local tOut, tCount, tI, tJ, tValue
   put pPool into tOut
   put cwListCount(pPool) into tCount
   repeat with tI = 2 to tCount
      put tOut[tI] into tValue
      put tI - 1 into tJ
      repeat while tJ >= 1
         if cwCoinBefore(tOut[tJ], tValue, pStrategy) is true then
            exit repeat
         end if
         put tOut[tJ] into tOut[tJ + 1]
         subtract 1 from tJ
      end repeat
      put tValue into tOut[tJ + 1]
   end repeat
   return tOut
end cwSortCoins

private function cwCoinBefore pA, pB, pStrategy
   local tKa, tKb
   if pStrategy is "smallest" then
      put pA["value"] into tKa
      put pB["value"] into tKb
   else if pStrategy is "oldest" then
      put 0 - pA["confirmations"] into tKa
      put 0 - pB["confirmations"] into tKb
   else if pStrategy is "manual" then
      -- manual keeps the order the caller gave, so nothing sorts before
      -- anything: the comparison always says "already in place"
      return true
   else
      put 0 - pA["value"] into tKa
      put 0 - pB["value"] into tKb
   end if
   if tKa < tKb then
      return true
   end if
   if tKa > tKb then
      return false
   end if
   if pA["txid"] < pB["txid"] then
      return true
   end if
   if pA["txid"] > pB["txid"] then
      return false
   end if
   return (pA["vout"] + 0) <= (pB["vout"] + 0)
end cwCoinBefore

private function cwBranchAndBound pPool, pTargetSat, pFeeRate, pInputType, pOutputTypes, pChangeType, pM, pCosigners
   -- Murch's branch and bound, ITERATIVE.
   --
   -- The recursive spelling is shorter and this is not it, deliberately: the
   -- search depth is the number of spendable coins, a wallet that has been
   -- receiving for years has hundreds, and a script that recurses hundreds
   -- deep is a stack the engine may or may not have. An explicit state array
   -- costs a dozen lines and cannot overflow anything.
   --
   -- The search is over EFFECTIVE values - each coin's value minus what
   -- spending it costs in fee at this rate - because that is what the coin is
   -- actually worth to this transaction. Coins whose effective value is zero
   -- or negative are dropped: including one makes the transaction strictly
   -- worse.
   --
   -- The window is [target + base fee, that + cost of change]. A total inside
   -- it means the remainder is smaller than a change output would cost to make
   -- and later to spend, so there is no change output and the remainder goes
   -- to the miner.
   local tSorted, tCount, tI, tCoin, tEff, tValues, tCoins, tRemain, tSum
   local tCost, tBaseFee, tLo, tHi, tCostOfChange, tState, tDepth, tValue
   local tTries, tBack, tOut, tSel, tResult, tChangeCost, tEmpty
   put cwSortCoins(pPool, "largest") into tSorted
   put cwListCount(tSorted) into tCount
   put cwInputCost(pInputType, pFeeRate, pM, pCosigners) into tCost
   put cwListNew() into tValues
   put cwListNew() into tCoins
   repeat with tI = 1 to tCount
      put tSorted[tI] into tCoin
      put tCoin["value"] - tCost into tEff
      if tEff > 0 then
         put cwListAdd(tValues, tEff) into tValues
         put cwListAdd(tCoins, tCoin) into tCoins
      end if
   end repeat
   put cwListCount(tValues) into tCount
   put cwListNew() into tEmpty
   put cwEstimateVsize(cwListNew(), pOutputTypes) into tBaseFee
   put cwFeeFor(tBaseFee, pFeeRate) into tBaseFee
   put pTargetSat + tBaseFee into tLo
   put cwFeeFor(cwOutputBytes(pChangeType), pFeeRate) into tChangeCost
   put tCost + tChangeCost into tCostOfChange
   put tLo + tCostOfChange into tHi
   -- the suffix sums: what is still reachable from each position on
   put 0 into tRemain[tCount + 1]
   repeat with tI = tCount down to 1
      put tRemain[tI + 1] + tValues[tI] into tRemain[tI]
   end repeat
   put 0 into tValue
   put 1 into tDepth
   put 100000 into tTries
   repeat while tTries > 0
      subtract 1 from tTries
      put false into tBack
      if tValue > tHi then
         put true into tBack
      else if tValue >= tLo then
         -- a solution: take the first one found, which with the
         -- largest-first ordering and include-before-exclude walk is the
         -- one using the fewest, biggest coins
         put cwListNew() into tSel
         repeat with tI = 1 to (tDepth - 1)
            if tState[tI] is 1 then
               put cwListAdd(tSel, tCoins[tI]) into tSel
            end if
         end repeat
         put cwSelectionResult(tSel, pTargetSat, pFeeRate, pInputType, pOutputTypes, \
               pChangeType, false, pM, pCosigners) into tResult
         put tResult["totalin"] - pTargetSat into tResult["fee"]
         put 0 into tResult["change"]
         put true into tResult["ok"]
         put "branch and bound: an exact-enough match, so there is no change output" \
               into tResult["why"]
         put "bnb" into tResult["strategy"]
         return tResult
      else if tDepth > tCount then
         put true into tBack
      else if tValue + tRemain[tDepth] < tLo then
         put true into tBack
      end if
      if tBack is true then
         -- walk back to the most recent INCLUDED coin, drop it, and take the
         -- exclude branch there instead
         repeat while tDepth > 1
            subtract 1 from tDepth
            if tState[tDepth] is 1 then
               subtract tValues[tDepth] from tValue
               put 2 into tState[tDepth]
               add 1 to tDepth
               exit repeat
            end if
            put 0 into tState[tDepth]
         end repeat
         if tDepth is 1 and tState[1] is not 2 then
            exit repeat
         end if
      else
         put 1 into tState[tDepth]
         add tValues[tDepth] to tValue
         add 1 to tDepth
      end if
   end repeat
   put false into tOut["ok"]
   put "no changeless combination exists" into tOut["why"]
   return tOut
end cwBranchAndBound

-- ==============================================================================
-- TRANSACTIONS
--
-- CoinXT owns the three signature-hash preimages (cxBtcSighashLegacy,
-- cxBtcSighashSegwit, cxBtcSighashTaproot) and a transaction encoder. What is
-- added here is what a WALLET does around them: the per-type scriptCode rules,
-- the scriptSig and witness shapes, and a DECODER, which no signer needs and
-- every reviewer does.
--
-- THE SCRIPTCODE RULES ARE WHERE THIS GOES WRONG, so they are stated once:
--   p2pkh          the scriptCode is the P2PKH script itself (legacy preimage)
--   p2wpkh         BIP-143's scriptCode is the P2PKH script OF THE SAME KEY,
--                  not the witness program
--   p2sh-p2wpkh    identical to p2wpkh; the P2SH wrapping is invisible to the
--                  preimage and shows up only in the scriptSig
--   p2wsh          the scriptCode is the WITNESS SCRIPT itself
--   p2tr           there is no scriptCode at all: BIP-341 commits to every
--                  input's scriptPubKey and amount, which is why the taproot
--                  path needs the whole prevout set and the others do not
-- ==============================================================================

function cwTxInput pTxidHex, pVout, pSequence
   local tIn
   if cwHexIsClean(pTxidHex) is not true or the number of chars of pTxidHex is not 64 then
      throw "wallet-core: cwTxInput: a txid is 32 bytes of hex."
   end if
   put cwLower(pTxidHex) into tIn["txid"]
   put pVout + 0 into tIn["vout"]
   if pSequence is "" then
      put kCwSeqRbf into tIn["sequence"]
   else
      put pSequence + 0 into tIn["sequence"]
   end if
   return tIn
end cwTxInput

function cwTxOutput pAmountSat, pScriptHex
   local tOut
   put pAmountSat + 0 into tOut["value"]
   put cwLower(pScriptHex) into tOut["script"]
   return tOut
end cwTxOutput

function cwOutpointsHex pInputs
   -- CoinXT's transaction API takes parallel COMMA lists of hex, so this is
   -- where the array convention meets it. Building a comma-joined string is
   -- safe whatever the engine's itemDelimiter is; only READING one is not.
   local tOut, tI, tCount, tIn
   put "" into tOut
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      put pInputs[tI] into tIn
      if tI > 1 then
         put "," after tOut
      end if
      put cxHexEncode(cxBtcOutpoint(tIn["txid"], tIn["vout"])) after tOut
   end repeat
   return tOut
end cwOutpointsHex

function cwSequencesList pInputs
   local tOut, tI, tCount, tIn
   put "" into tOut
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      put pInputs[tI] into tIn
      if tI > 1 then
         put "," after tOut
      end if
      put tIn["sequence"] after tOut
   end repeat
   return tOut
end cwSequencesList

function cwOutputsHex pOutputs
   local tOut, tI, tCount, tRec
   put "" into tOut
   put cwListCount(pOutputs) into tCount
   repeat with tI = 1 to tCount
      put pOutputs[tI] into tRec
      if tI > 1 then
         put "," after tOut
      end if
      put cxHexEncode(cxBtcOutput(tRec["value"], tRec["script"])) after tOut
   end repeat
   return tOut
end cwOutputsHex

function cwSighash pScriptType, pVersion, pInputs, pOutputs, pIndex, pLocktime, pPubkeyHex, pAmountSat, pWitnessScriptHex, pPrevScripts, pPrevAmounts
   -- The digest to sign for input pIndex (1-based, as CoinXT counts).
   local tOutpoints, tSeqs, tOuts, tCode, tI, tCount, tSpks, tAmts, tRec
   put cwOutpointsHex(pInputs) into tOutpoints
   put cwSequencesList(pInputs) into tSeqs
   put cwOutputsHex(pOutputs) into tOuts
   if pScriptType is "p2pkh" then
      put cwScriptP2pkh(pPubkeyHex) into tCode
      return cxHexEncode(cxBtcSighashLegacy(pVersion, tOutpoints, tSeqs, pIndex, \
            tCode, tOuts, pLocktime, 1))
   end if
   if pScriptType is "p2wpkh" or pScriptType is "p2sh-p2wpkh" then
      put cwScriptP2pkh(pPubkeyHex) into tCode
      return cxHexEncode(cxBtcSighashSegwit(pVersion, tOutpoints, tSeqs, pIndex, \
            tCode, pAmountSat, tOuts, pLocktime, 1))
   end if
   if pScriptType is "p2wsh" then
      return cxHexEncode(cxBtcSighashSegwit(pVersion, tOutpoints, tSeqs, pIndex, \
            pWitnessScriptHex, pAmountSat, tOuts, pLocktime, 1))
   end if
   if pScriptType is "p2tr" then
      put "" into tSpks
      put "" into tAmts
      put cwListCount(pPrevScripts) into tCount
      repeat with tI = 1 to tCount
         if tI > 1 then
            put "," after tSpks
            put "," after tAmts
         end if
         put pPrevScripts[tI] after tSpks
         put pPrevAmounts[tI] after tAmts
      end repeat
      -- BIP-341's DEFAULT sighash type is 0, which is not SIGHASH_ALL's 1 and
      -- does not appear in the signature at all. Passing 1 here would produce
      -- a valid but longer 65-byte signature; 0 is what a key-path spend
      -- normally uses.
      return cxHexEncode(cxBtcSighashTaproot(pVersion, tOutpoints, tSeqs, tAmts, \
            tSpks, tOuts, pIndex, pLocktime, 0, ""))
   end if
   throw "wallet-core: cwSighash: unknown script type " & pScriptType & "."
end cwSighash

function cwSignInput pScriptType, pSeckeyHex, pDigestHex, pPubkeyHex
   -- Returns an array with "scriptsig" (hex) and "witness" (a list of hex
   -- items). The sighash byte appended to the DER signature is 1 (SIGHASH_ALL)
   -- for every non-taproot type, and taproot's key-path signature carries no
   -- type byte at all when the type is the default 0.
   local tSig, tOut, tWit
   put cwListNew() into tWit
   if pScriptType is "p2tr" then
      throw "wallet-core: cwSignInput: taproot signs with cwSignTaproot, which " & \
            "must tweak the private key first."
   end if
   put cxHexEncode(cxDerEncode(cxSign(cxHexDecode(pSeckeyHex), cxHexDecode(pDigestHex)))) \
         & "01" into tSig
   if pScriptType is "p2pkh" then
      put cwPush(tSig) & cwPush(pPubkeyHex) into tOut["scriptsig"]
      put tWit into tOut["witness"]
      return tOut
   end if
   put cwListAdd(tWit, tSig) into tWit
   put cwListAdd(tWit, pPubkeyHex) into tWit
   put tWit into tOut["witness"]
   if pScriptType is "p2sh-p2wpkh" then
      put cwPush(cwRedeemP2shP2wpkh(pPubkeyHex)) into tOut["scriptsig"]
   else
      put "" into tOut["scriptsig"]
   end if
   return tOut
end cwSignInput

function cwSignTaproot pSeckeyHex, pDigestHex, pMerkleRootHex
   -- A BIP-341 key-path spend. The private key is TWEAKED first: the key that
   -- signs is not the derived key but that key plus the taproot tweak, and a
   -- signature from the untweaked key verifies against nothing.
   --
   -- The aux randomness is 32 zero bytes. BIP-340 allows it, and the reason to
   -- choose it here is that a wallet whose signatures cannot be reproduced
   -- cannot be tested by anybody, including its own vector gate; the security
   -- argument for aux randomness is about fault attacks on hardware, which is
   -- not the threat model of a script wallet on a general-purpose desktop.
   local tTweaked, tSig, tOut, tWit
   put cxTaprootTweakSeckey(cxHexDecode(pSeckeyHex), cxHexDecode(pMerkleRootHex)) into tTweaked
   put cxHexEncode(cxSchnorrSign(tTweaked, cxHexDecode(pDigestHex), \
         cxHexDecode("0000000000000000000000000000000000000000000000000000000000000000"))) into tSig
   put "" into tTweaked
   put cwListNew() into tWit
   put cwListAdd(tWit, tSig) into tWit
   put "" into tOut["scriptsig"]
   put tWit into tOut["witness"]
   return tOut
end cwSignTaproot

function cwSignMultisig pSeckeys, pDigestHex, pWitnessScriptHex
   -- The P2WSH m-of-n witness: an empty element for CHECKMULTISIG's
   -- off-by-one, then one signature per cosigner IN WITNESS-SCRIPT KEY ORDER,
   -- then the witness script itself. Signatures out of key order are a SCRIPT
   -- FAILURE, not a policy warning - the interpreter walks both lists once and
   -- never backtracks - so the order is taken from the script rather than from
   -- the order the keys were handed in.
   local tKeys, tI, tJ, tCount, tKeyCount, tWit, tOut, tSig, tSk, tPub
   put cwMultisigKeys(pWitnessScriptHex) into tKeys
   put cwListCount(tKeys) into tKeyCount
   put cwListCount(pSeckeys) into tCount
   put cwListNew() into tWit
   put cwListAdd(tWit, "") into tWit
   repeat with tI = 1 to tKeyCount
      repeat with tJ = 1 to tCount
         put pSeckeys[tJ] into tSk
         put cxHexEncode(cxPublicKey(cxHexDecode(tSk), true)) into tPub
         if tPub is tKeys[tI] then
            put cxHexEncode(cxDerEncode(cxSign(cxHexDecode(tSk), cxHexDecode(pDigestHex)))) \
                  & "01" into tSig
            put cwListAdd(tWit, tSig) into tWit
            exit repeat
         end if
      end repeat
   end repeat
   put cwListAdd(tWit, pWitnessScriptHex) into tWit
   put "" into tOut["scriptsig"]
   put tWit into tOut["witness"]
   return tOut
end cwSignMultisig

function cwMultisigKeys pWitnessScriptHex
   -- The public keys a bare CHECKMULTISIG script pushes, in script order.
   local tHex, tPos, tLen, tKeys, tEnd
   put cwLower(pWitnessScriptHex) into tHex
   put cwListNew() into tKeys
   put 3 into tPos
   put the number of chars of tHex into tEnd
   repeat while tPos < (tEnd - 3)
      put cwBeRead(cxHexDecode(char tPos to (tPos + 1) of tHex)) into tLen
      if tLen < 1 or tLen > 65 then
         exit repeat
      end if
      put cwListAdd(tKeys, char (tPos + 2) to (tPos + 1 + tLen * 2) of tHex) into tKeys
      put tPos + 2 + tLen * 2 into tPos
   end repeat
   return tKeys
end cwMultisigKeys

function cwTxSerialize pVersion, pInputs, pOutputs, pLocktime, pScriptSigs, pWitnesses
   -- The signed transaction, as hex. pScriptSigs is a list of hex scriptSigs
   -- (one per input, possibly empty); pWitnesses is a list of witness lists,
   -- or an empty list for a wholly non-witness transaction.
   local tSigs, tWits, tI, tJ, tCount, tItems, tOne, tHasWitness
   put "" into tSigs
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      if tI > 1 then
         put "," after tSigs
      end if
      put pScriptSigs[tI] after tSigs
   end repeat
   put false into tHasWitness
   put "" into tWits
   if cwListCount(pWitnesses) > 0 then
      repeat with tI = 1 to tCount
         put pWitnesses[tI] into tItems
         if cwListCount(tItems) > 0 then
            put true into tHasWitness
         end if
      end repeat
   end if
   if tHasWitness is true then
      repeat with tI = 1 to tCount
         if tI > 1 then
            put "," after tWits
         end if
         put pWitnesses[tI] into tItems
         put "" into tOne
         repeat with tJ = 1 to cwListCount(tItems)
            if tJ > 1 then
               put "," after tOne
            end if
            put tItems[tJ] after tOne
         end repeat
         put cxHexEncode(cxBtcWitness(tOne)) after tWits
      end repeat
   end if
   return cxHexEncode(cxBtcTxEncode(pVersion, cwOutpointsHex(pInputs), tSigs, \
         cwSequencesList(pInputs), tWits, cwOutputsHex(pOutputs), pLocktime))
end cwTxSerialize

function cwTxid pVersion, pInputs, pOutputs, pLocktime, pScriptSigs
   local tSigs, tI, tCount
   put "" into tSigs
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      if tI > 1 then
         put "," after tSigs
      end if
      put pScriptSigs[tI] after tSigs
   end repeat
   return cxBtcTxid(pVersion, cwOutpointsHex(pInputs), tSigs, \
         cwSequencesList(pInputs), cwOutputsHex(pOutputs), pLocktime)
end cwTxid

-- ==============================================================================
-- TRANSACTION DECODING
--
-- No signer needs this and every reviewer does. A wallet that can only BUILD a
-- transaction asks the person in front of it to trust its own summary of what
-- it built; one that can read a raw transaction back can show them the bytes
-- decoded independently of the code that made them, and can tell them what a
-- transaction somebody else handed them actually does.
-- ==============================================================================

private function cwReadVarInt pHex, pPos
   -- Returns an array with "value" and "next" (the 1-based hex character
   -- position after the field).
   local tFirst, tOut, tLen
   put cwBeRead(cxHexDecode(char pPos to (pPos + 1) of pHex)) into tFirst
   if tFirst < 253 then
      put tFirst into tOut["value"]
      put pPos + 2 into tOut["next"]
      return tOut
   end if
   if tFirst is 253 then
      put 2 into tLen
   else if tFirst is 254 then
      put 4 into tLen
   else
      put 8 into tLen
   end if
   put cwLeRead(cxHexDecode(char (pPos + 2) to (pPos + 1 + tLen * 2) of pHex)) into tOut["value"]
   put pPos + 2 + tLen * 2 into tOut["next"]
   return tOut
end cwReadVarInt

function cwTxDecode pRawHex
   local tHex, tPos, tOut, tVer, tSegwit, tCount, tI, tJ, tRec, tIn, tOutRec
   local tIns, tOuts, tLen, tWit, tItems, tStripped, tWeight, tRbf, tTotal, tEnd
   put cwLower(cwTrim(pRawHex)) into tHex
   if cwHexIsClean(tHex) is not true then
      throw "wallet-core: cwTxDecode: that is not hex."
   end if
   put 1 into tPos
   put cwLeRead(cxHexDecode(char 1 to 8 of tHex)) into tVer
   put 9 into tPos
   put false into tSegwit
   if char 9 to 12 of tHex is "0001" then
      put true into tSegwit
      put 13 into tPos
   end if
   put cwReadVarInt(tHex, tPos) into tRec
   put tRec["value"] into tCount
   put tRec["next"] into tPos
   put cwListNew() into tIns
   repeat with tI = 1 to tCount
      -- the outpoint's txid is stored LITTLE-endian and displayed big-endian;
      -- the reversal is the difference between a txid a person recognises and
      -- one that matches nothing on any explorer
      put "" into tIn
      put cxHexEncode(cwReverseBytes(cxHexDecode(char tPos to (tPos + 63) of tHex))) into tIn["txid"]
      put tPos + 64 into tPos
      put cwLeRead(cxHexDecode(char tPos to (tPos + 7) of tHex)) into tIn["vout"]
      put tPos + 8 into tPos
      put cwReadVarInt(tHex, tPos) into tRec
      put tRec["value"] into tLen
      put tRec["next"] into tPos
      put char tPos to (tPos + tLen * 2 - 1) of tHex into tIn["scriptsig"]
      put tPos + tLen * 2 into tPos
      put cwLeRead(cxHexDecode(char tPos to (tPos + 7) of tHex)) into tIn["sequence"]
      put tPos + 8 into tPos
      put cwListNew() into tIn["witness"]
      put cwListAdd(tIns, tIn) into tIns
   end repeat
   put cwReadVarInt(tHex, tPos) into tRec
   put tRec["value"] into tCount
   put tRec["next"] into tPos
   put cwListNew() into tOuts
   put 0 into tTotal
   repeat with tI = 1 to tCount
      put cwLeRead(cxHexDecode(char tPos to (tPos + 15) of tHex)) into tOutRec["value"]
      add tOutRec["value"] to tTotal
      put tPos + 16 into tPos
      put cwReadVarInt(tHex, tPos) into tRec
      put tRec["value"] into tLen
      put tRec["next"] into tPos
      put char tPos to (tPos + tLen * 2 - 1) of tHex into tOutRec["script"]
      put tPos + tLen * 2 into tPos
      put cwScriptKind(tOutRec["script"]) into tOutRec["kind"]
      put cwListAdd(tOuts, tOutRec) into tOuts
   end repeat
   if tSegwit is true then
      put cwListCount(tIns) into tCount
      repeat with tI = 1 to tCount
         put cwReadVarInt(tHex, tPos) into tRec
         put tRec["next"] into tPos
         put cwListNew() into tItems
         repeat with tJ = 1 to tRec["value"]
            put cwReadVarInt(tHex, tPos) into tWit
            put tWit["next"] into tPos
            put cwListAdd(tItems, char tPos to (tPos + tWit["value"] * 2 - 1) of tHex) into tItems
            put tPos + tWit["value"] * 2 into tPos
         end repeat
         put tIns[tI] into tIn
         put tItems into tIn["witness"]
         put tIn into tIns[tI]
      end repeat
   end if
   put cwLeRead(cxHexDecode(char tPos to (tPos + 7) of tHex)) into tOut["locktime"]
   put tPos + 8 into tPos
   -- the end position, taken into a local FIRST: `the number of chars of tHex
   -- + 1` binds the addition into the chunk target, so the engine is asked
   -- for the character count of tHex+1 rather than for one past the end
   put the number of chars of tHex into tEnd
   add 1 to tEnd
   if tPos is not tEnd then
      throw "wallet-core: cwTxDecode: " & cwIntDiv(tEnd - tPos, 2) & \
            " trailing bytes after the transaction."
   end if
   put tVer into tOut["version"]
   put tSegwit into tOut["segwit"]
   put tIns into tOut["inputs"]
   put tOuts into tOut["outputs"]
   put tTotal into tOut["outputtotal"]
   -- the txid is over the serialization WITHOUT the witness (BIP-141), which
   -- is what makes a signature over the inputs not commit to itself
   put cwStripWitness(tOut) into tStripped
   put cxHexEncode(cwReverseBytes(cxHash256(cxHexDecode(tStripped)))) into tOut["txid"]
   put cxHexEncode(cwReverseBytes(cxHash256(cxHexDecode(tHex)))) into tOut["wtxid"]
   put cwIntDiv(the number of chars of tHex, 2) into tOut["size"]
   put cwIntDiv(the number of chars of tStripped, 2) * 3 + tOut["size"] into tWeight
   put tWeight into tOut["weight"]
   put cwCeilDiv(tWeight, 4) into tOut["vsize"]
   put false into tRbf
   put cwListCount(tIns) into tCount
   repeat with tI = 1 to tCount
      put tIns[tI] into tIn
      if tIn["sequence"] < kCwSeqNoRbf then
         put true into tRbf
      end if
   end repeat
   put tRbf into tOut["rbf"]
   return tOut
end cwTxDecode

private function cwStripWitness pTx
   local tIns, tOuts, tSigs, tI, tCount, tIn
   put pTx["inputs"] into tIns
   put pTx["outputs"] into tOuts
   put cwListNew() into tSigs
   put cwListCount(tIns) into tCount
   repeat with tI = 1 to tCount
      put tIns[tI] into tIn
      put cwListAdd(tSigs, tIn["scriptsig"]) into tSigs
   end repeat
   return cxHexEncode(cxBtcTxEncode(pTx["version"], cwOutpointsHex(tIns), \
         cwSigsList(tSigs), cwSequencesList(tIns), "", cwOutputsHex(tOuts), \
         pTx["locktime"]))
end cwStripWitness

function cwSigsList pScriptSigs
   local tOut, tI, tCount
   put "" into tOut
   put cwListCount(pScriptSigs) into tCount
   repeat with tI = 1 to tCount
      if tI > 1 then
         put "," after tOut
      end if
      put pScriptSigs[tI] after tOut
   end repeat
   return tOut
end cwSigsList

function cwScriptAsm pScriptHex
   -- A script rendered as opcodes and pushes, for the transaction inspector.
   -- Only the opcodes a wallet script uses are named; anything else prints as
   -- OP_<n>, which is honest about what this decoder is and is not.
   local tHex, tPos, tEnd, tOut, tByte, tLen, tRec
   put cwLower(pScriptHex) into tHex
   put 1 into tPos
   put the number of chars of tHex into tEnd
   put "" into tOut
   repeat while tPos <= tEnd
      put cwBeRead(cxHexDecode(char tPos to (tPos + 1) of tHex)) into tByte
      add 2 to tPos
      if tByte >= 1 and tByte <= 75 then
         put "PUSH(" & tByte & ") " & char tPos to (tPos + tByte * 2 - 1) of tHex & " " after tOut
         add tByte * 2 to tPos
      else if tByte is 76 then
         put cwBeRead(cxHexDecode(char tPos to (tPos + 1) of tHex)) into tLen
         add 2 to tPos
         put "PUSHDATA1(" & tLen & ") " & char tPos to (tPos + tLen * 2 - 1) of tHex & " " after tOut
         add tLen * 2 to tPos
      else if tByte is 0 then
         put "OP_0 " after tOut
      else if tByte is 81 then
         put "OP_1 " after tOut
      else if tByte >= 82 and tByte <= 96 then
         put "OP_" & (tByte - 80) & " " after tOut
      else if tByte is 106 then
         put "OP_RETURN " after tOut
      else if tByte is 118 then
         put "OP_DUP " after tOut
      else if tByte is 135 then
         put "OP_EQUAL " after tOut
      else if tByte is 136 then
         put "OP_EQUALVERIFY " after tOut
      else if tByte is 169 then
         put "OP_HASH160 " after tOut
      else if tByte is 172 then
         put "OP_CHECKSIG " after tOut
      else if tByte is 174 then
         put "OP_CHECKMULTISIG " after tOut
      else
         put "OP_" & tByte & " " after tOut
      end if
   end repeat
   return cwTrim(tOut)
end cwScriptAsm

-- ==============================================================================
-- PSBT (BIP-174 version 0, with BIP-371's taproot fields)
--
-- The format is three runs of key/value maps - one global, one per input, one
-- per output - each terminated by a zero-length key. A key is
-- <compact_size keylen><keytype><keydata>; a value is <compact_size len><data>.
--
-- Nothing about it is clever, and that is exactly why it is dangerous: every
-- field is a length prefix around a blob, so a wrong length does not fail, it
-- produces a file another wallet parses into DIFFERENT MONEY. It is here
-- because PSBT is how a wallet talks to anything that is not itself - a
-- hardware signer, a cosigner, a coordinator, Bitcoin Core - and a wallet
-- that can only sign its own transactions is a wallet that can only ever be
-- used alone.
-- ==============================================================================

constant kCwPsbtMagic = "70736274ff"

constant kCwPsbtGlobalUnsignedTx = 0
constant kCwPsbtGlobalXpub = 1
constant kCwPsbtGlobalVersion = 251

constant kCwPsbtInNonWitnessUtxo = 0
constant kCwPsbtInWitnessUtxo = 1
constant kCwPsbtInPartialSig = 2
constant kCwPsbtInSighashType = 3
constant kCwPsbtInRedeemScript = 4
constant kCwPsbtInWitnessScript = 5
constant kCwPsbtInBip32 = 6
constant kCwPsbtInFinalScriptSig = 7
constant kCwPsbtInFinalScriptWitness = 8
constant kCwPsbtInTapKeySig = 19
constant kCwPsbtInTapBip32 = 22
constant kCwPsbtInTapInternalKey = 23
constant kCwPsbtInTapMerkleRoot = 24

constant kCwPsbtOutRedeemScript = 0
constant kCwPsbtOutWitnessScript = 1
constant kCwPsbtOutBip32 = 2
constant kCwPsbtOutTapInternalKey = 5
constant kCwPsbtOutTapBip32 = 7

function cwVarIntHex pN
   return cxHexEncode(cxVarInt(pN))
end cwVarIntHex

private function cwPsbtEntry pType, pKeyDataHex, pValueHex
   local tEntry
   put pType into tEntry["type"]
   put pKeyDataHex into tEntry["key"]
   put pValueHex into tEntry["value"]
   return tEntry
end cwPsbtEntry

private function cwPsbtEmitMap pEntries
   -- Entries go out in ascending (type, keydata) order. BIP-174 does not
   -- require it; a vector gate does, and so does anybody diffing two PSBTs
   -- to see what a cosigner changed.
   local tSorted, tOut, tI, tCount, tEntry, tKey
   put cwPsbtSortEntries(pEntries) into tSorted
   put "" into tOut
   put cwListCount(tSorted) into tCount
   repeat with tI = 1 to tCount
      put tSorted[tI] into tEntry
      put cxHexEncode(numToByte(tEntry["type"])) & tEntry["key"] into tKey
      put cwVarIntHex(cwIntDiv(the number of chars of tKey, 2)) & tKey after tOut
      put cwVarIntHex(cwIntDiv(the number of chars of tEntry["value"], 2)) & \
            tEntry["value"] after tOut
   end repeat
   return tOut & "00"
end cwPsbtEmitMap

private function cwPsbtSortEntries pEntries
   local tOut, tCount, tI, tJ, tValue, tA, tB
   put pEntries into tOut
   put cwListCount(pEntries) into tCount
   repeat with tI = 2 to tCount
      put tOut[tI] into tValue
      put tI - 1 into tJ
      repeat while tJ >= 1
         put tOut[tJ] into tA
         if tA["type"] < tValue["type"] then
            exit repeat
         end if
         if tA["type"] is tValue["type"] and cwHexCompare(tA["key"], tValue["key"]) <= 0 then
            exit repeat
         end if
         put tOut[tJ] into tOut[tJ + 1]
         subtract 1 from tJ
      end repeat
      put tValue into tOut[tJ + 1]
   end repeat
   return tOut
end cwPsbtSortEntries

function cwPathBytes pPath
   -- A BIP-32 path as PSBT stores it: each level a 4-byte LITTLE-endian
   -- unsigned integer. Note the endianness. Every OTHER place BIP-32 writes a
   -- child number it is big-endian, and this one place it is not, which is
   -- exactly the kind of detail that produces a file that parses cleanly and
   -- claims the wrong derivation.
   local tLevels, tI, tCount, tOut
   put cwParsePath(pPath) into tLevels
   put cwListCount(tLevels) into tCount
   put "" into tOut
   repeat with tI = 1 to tCount
      put cxHexEncode(cwLeBytes(tLevels[tI], 4)) after tOut
   end repeat
   return tOut
end cwPathBytes

function cwPathFromBytes pHex
   local tCount, tI, tLevels, tN
   put cwIntDiv(the number of chars of pHex, 8) into tCount
   put cwListNew() into tLevels
   repeat with tI = 1 to tCount
      put cwLeRead(cxHexDecode(char (tI * 8 - 7) to (tI * 8) of pHex)) into tN
      put cwListAdd(tLevels, tN) into tLevels
   end repeat
   return cwFormatPath(tLevels)
end cwPathFromBytes

function cwPsbtUnsignedTx pVersion, pInputs, pOutputs, pLocktime
   -- The PSBT unsigned transaction: every scriptSig empty, no witness at all.
   local tSigs, tI, tCount
   put cwListNew() into tSigs
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      put cwListAdd(tSigs, "") into tSigs
   end repeat
   return cwTxSerialize(pVersion, pInputs, pOutputs, pLocktime, tSigs, cwListNew())
end cwPsbtUnsignedTx

function cwPsbtCreate pVersion, pInputs, pOutputs, pLocktime, pInMeta, pOutMeta
   -- pInMeta[i] and pOutMeta[i] are arrays of optional per-map fields; see
   -- cwPsbtInputEntries below for the key names they may carry.
   local tOut, tGlobal, tI, tCount
   put cwListNew() into tGlobal
   put cwListAdd(tGlobal, cwPsbtEntry(kCwPsbtGlobalUnsignedTx, "", \
         cwPsbtUnsignedTx(pVersion, pInputs, pOutputs, pLocktime))) into tGlobal
   put kCwPsbtMagic & cwPsbtEmitMap(tGlobal) into tOut
   put cwListCount(pInputs) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtEmitMap(cwPsbtInputEntries(pInMeta[tI])) after tOut
   end repeat
   put cwListCount(pOutputs) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtEmitMap(cwPsbtOutputEntries(pOutMeta[tI])) after tOut
   end repeat
   return cwB64Encode(tOut)
end cwPsbtCreate

private function cwPsbtInputEntries pMeta
   local tOut, tKeys, tI, tCount, tKey, tRec
   put cwListNew() into tOut
   if pMeta["nonwitnessutxo"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInNonWitnessUtxo, "", \
            pMeta["nonwitnessutxo"])) into tOut
   end if
   if pMeta["witnessutxoscript"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInWitnessUtxo, "", \
            cxHexEncode(cwLeBytes(pMeta["witnessutxovalue"], 8)) & \
            cwVarIntHex(cwIntDiv(the number of chars of pMeta["witnessutxoscript"], 2)) & \
            pMeta["witnessutxoscript"])) into tOut
   end if
   if pMeta["sighash"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInSighashType, "", \
            cxHexEncode(cwLeBytes(pMeta["sighash"], 4)))) into tOut
   end if
   if pMeta["redeemscript"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInRedeemScript, "", \
            pMeta["redeemscript"])) into tOut
   end if
   if pMeta["witnessscript"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInWitnessScript, "", \
            pMeta["witnessscript"])) into tOut
   end if
   if pMeta["tapinternalkey"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInTapInternalKey, "", \
            pMeta["tapinternalkey"])) into tOut
   end if
   put pMeta["bip32"] into tRec
   put cwListCount(tRec) into tCount
   repeat with tI = 1 to tCount
      put tRec[tI] into tKey
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInBip32, tKey["pubkey"], \
            tKey["fingerprint"] & cwPathBytes(tKey["path"]))) into tOut
   end repeat
   put pMeta["tapbip32"] into tRec
   put cwListCount(tRec) into tCount
   repeat with tI = 1 to tCount
      put tRec[tI] into tKey
      -- a leading compact-size 0: this key is used by NO tap leaf, i.e. it is
      -- the internal key of a key-path spend
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInTapBip32, tKey["pubkey"], \
            "00" & tKey["fingerprint"] & cwPathBytes(tKey["path"]))) into tOut
   end repeat
   put pMeta["partialsigs"] into tRec
   put cwListCount(tRec) into tCount
   repeat with tI = 1 to tCount
      put tRec[tI] into tKey
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInPartialSig, tKey["pubkey"], \
            tKey["sig"])) into tOut
   end repeat
   if pMeta["tapkeysig"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInTapKeySig, "", pMeta["tapkeysig"])) into tOut
   end if
   if pMeta["finalscriptsig"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInFinalScriptSig, "", \
            pMeta["finalscriptsig"])) into tOut
   end if
   if pMeta["finalscriptwitness"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtInFinalScriptWitness, "", \
            pMeta["finalscriptwitness"])) into tOut
   end if
   return tOut
end cwPsbtInputEntries

private function cwPsbtOutputEntries pMeta
   local tOut, tRec, tI, tCount, tKey
   put cwListNew() into tOut
   if pMeta["redeemscript"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtOutRedeemScript, "", \
            pMeta["redeemscript"])) into tOut
   end if
   if pMeta["witnessscript"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtOutWitnessScript, "", \
            pMeta["witnessscript"])) into tOut
   end if
   if pMeta["tapinternalkey"] is not "" then
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtOutTapInternalKey, "", \
            pMeta["tapinternalkey"])) into tOut
   end if
   put pMeta["bip32"] into tRec
   put cwListCount(tRec) into tCount
   repeat with tI = 1 to tCount
      put tRec[tI] into tKey
      put cwListAdd(tOut, cwPsbtEntry(kCwPsbtOutBip32, tKey["pubkey"], \
            tKey["fingerprint"] & cwPathBytes(tKey["path"]))) into tOut
   end repeat
   return tOut
end cwPsbtOutputEntries

function cwB64Encode pHex
   -- The engine's base64Encode wraps its output at a width nobody in this
   -- family has measured, so every line break is stripped: a PSBT is pasted
   -- into fields and URLs where a stray newline is a corrupt file.
   return cwStripWhitespace(base64Encode(cxHexDecode(pHex)))
end cwB64Encode

function cwB64Decode pText
   return cxHexEncode(base64Decode(cwStripWhitespace(pText)))
end cwB64Decode

function cwStripWhitespace pText
   local tOut, tI, tCount, tC, tCode
   put "" into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put char tI of pText into tC
      put charToNum(tC) into tCode
      if tCode > 32 then
         put tC after tOut
      end if
   end repeat
   return tOut
end cwStripWhitespace

private function cwPsbtParseMap pHex, pPos
   -- Returns an array with "entries" (a list) and "next". Refuses a map that
   -- runs off the end rather than returning what it managed to read: a
   -- truncated PSBT that parses into a shorter one is the failure mode this
   -- format makes easiest and the most expensive to notice.
   local tEntries, tPos, tRec, tKeyLen, tKey, tValLen, tEntry, tEnd
   put cwListNew() into tEntries
   put pPos into tPos
   put the number of chars of pHex into tEnd
   repeat while true
      if tPos > tEnd then
         throw "wallet-core: cwPsbtParse: a map ran off the end with no separator."
      end if
      put cwReadVarInt(pHex, tPos) into tRec
      put tRec["value"] into tKeyLen
      put tRec["next"] into tPos
      if tKeyLen is 0 then
         put tEntries into tEntry["entries"]
         put tPos into tEntry["next"]
         return tEntry
      end if
      if (tPos + tKeyLen * 2 - 1) > tEnd then
         throw "wallet-core: cwPsbtParse: a key length overruns the file."
      end if
      put char tPos to (tPos + tKeyLen * 2 - 1) of pHex into tKey
      put tPos + tKeyLen * 2 into tPos
      put cwReadVarInt(pHex, tPos) into tRec
      put tRec["value"] into tValLen
      put tRec["next"] into tPos
      if (tPos + tValLen * 2 - 1) > tEnd then
         throw "wallet-core: cwPsbtParse: a value length overruns the file."
      end if
      put "" into tEntry
      put cwBeRead(cxHexDecode(char 1 to 2 of tKey)) into tEntry["type"]
      put char 3 to -1 of tKey into tEntry["key"]
      put char tPos to (tPos + tValLen * 2 - 1) of pHex into tEntry["value"]
      put tPos + tValLen * 2 into tPos
      put cwListAdd(tEntries, tEntry) into tEntries
   end repeat
   return tEntry
end cwPsbtParseMap

function cwPsbtParse pB64
   local tHex, tPos, tRec, tOut, tTx, tDecoded, tI, tCount, tMaps, tEnd
   put cwB64Decode(pB64) into tHex
   if char 1 to 10 of tHex is not kCwPsbtMagic then
      throw "wallet-core: cwPsbtParse: that is not a PSBT (the magic bytes are wrong)."
   end if
   put 11 into tPos
   put cwPsbtParseMap(tHex, tPos) into tRec
   put tRec["entries"] into tOut["global"]
   put tRec["next"] into tPos
   put cwPsbtFind(tOut["global"], kCwPsbtGlobalUnsignedTx, "") into tTx
   if tTx is "" then
      throw "wallet-core: cwPsbtParse: this PSBT carries no unsigned transaction."
   end if
   put tTx into tOut["unsignedtx"]
   put cwTxDecode(tTx) into tDecoded
   put tDecoded into tOut["tx"]
   put cwListNew() into tMaps
   put cwListCount(tDecoded["inputs"]) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtParseMap(tHex, tPos) into tRec
      put cwListAdd(tMaps, tRec["entries"]) into tMaps
      put tRec["next"] into tPos
   end repeat
   put tMaps into tOut["inputs"]
   put cwListNew() into tMaps
   put cwListCount(tDecoded["outputs"]) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtParseMap(tHex, tPos) into tRec
      put cwListAdd(tMaps, tRec["entries"]) into tMaps
      put tRec["next"] into tPos
   end repeat
   put tMaps into tOut["outputs"]
   put the number of chars of tHex into tEnd
   add 1 to tEnd
   if tPos is not tEnd then
      throw "wallet-core: cwPsbtParse: " & cwIntDiv(tEnd - tPos, 2) & \
            " trailing bytes after the output maps."
   end if
   return tOut
end cwPsbtParse

function cwPsbtFind pEntries, pType, pKeyHex
   -- The value of the first entry of this type and key data, or empty.
   local tI, tCount, tEntry
   put cwListCount(pEntries) into tCount
   repeat with tI = 1 to tCount
      put pEntries[tI] into tEntry
      if tEntry["type"] is pType and tEntry["key"] is pKeyHex then
         return tEntry["value"]
      end if
   end repeat
   return ""
end cwPsbtFind

function cwPsbtFindAll pEntries, pType
   local tI, tCount, tEntry, tOut
   put cwListNew() into tOut
   put cwListCount(pEntries) into tCount
   repeat with tI = 1 to tCount
      put pEntries[tI] into tEntry
      if tEntry["type"] is pType then
         put cwListAdd(tOut, tEntry) into tOut
      end if
   end repeat
   return tOut
end cwPsbtFindAll

function cwPsbtInputAmount pInputMap
   -- The amount an input is spending, from whichever UTXO field the PSBT
   -- carries. A signer that cannot find it must REFUSE rather than assume:
   -- BIP-143 commits to the amount, so a wrong one produces a signature that
   -- verifies nowhere, and a signer that guesses has quietly wasted the
   -- signing device's one chance to be correct.
   local tWit, tRec
   put cwPsbtFind(pInputMap, kCwPsbtInWitnessUtxo, "") into tWit
   if tWit is not "" then
      return cwLeRead(cxHexDecode(char 1 to 16 of tWit))
   end if
   return -1
end cwPsbtInputAmount

function cwPsbtInputScript pInputMap
   local tWit, tRec, tLen
   put cwPsbtFind(pInputMap, kCwPsbtInWitnessUtxo, "") into tWit
   if tWit is "" then
      return ""
   end if
   put cwReadVarInt(tWit, 17) into tRec
   put tRec["value"] into tLen
   return char tRec["next"] to (tRec["next"] + tLen * 2 - 1) of tWit
end cwPsbtInputScript

function cwPsbtInputType pInputMap
   -- What kind of input this is, from the fields the PSBT carries. The order
   -- matters: a witness script means P2WSH whatever else is present, and a
   -- redeem script that IS a witness program means the P2SH-wrapped form.
   local tSpk, tKind, tRedeem
   put cwPsbtInputScript(pInputMap) into tSpk
   put cwScriptKind(tSpk) into tKind
   if tKind is "p2sh" then
      put cwPsbtFind(pInputMap, kCwPsbtInRedeemScript, "") into tRedeem
      if cwScriptKind(tRedeem) is "p2wpkh" then
         return "p2sh-p2wpkh"
      end if
      return "p2sh"
   end if
   return tKind
end cwPsbtInputType

function cwPsbtEmit pParsed
   -- Re-emit a parsed PSBT. Everything that MODIFIES a PSBT here goes
   -- parse -> edit the entry lists -> emit, rather than splicing bytes into
   -- the original: a byte splice has to get every surrounding length right
   -- and gets no second chance, and this way the emitter is the same one code
   -- path that cwPsbtCreate uses and is pinned by the same vectors.
   local tOut, tI, tCount, tMaps
   put kCwPsbtMagic & cwPsbtEmitMap(pParsed["global"]) into tOut
   put pParsed["inputs"] into tMaps
   put cwListCount(tMaps) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtEmitMap(tMaps[tI]) after tOut
   end repeat
   put pParsed["outputs"] into tMaps
   put cwListCount(tMaps) into tCount
   repeat with tI = 1 to tCount
      put cwPsbtEmitMap(tMaps[tI]) after tOut
   end repeat
   return cwB64Encode(tOut)
end cwPsbtEmit

private function cwPsbtSetEntry pEntries, pType, pKeyHex, pValueHex
   -- Replace an entry of this (type, key) or append it. BIP-174 requires keys
   -- to be unique within a map, so this is the only correct way to add one.
   local tOut, tI, tCount, tEntry
   put pEntries into tOut
   put cwListCount(pEntries) into tCount
   repeat with tI = 1 to tCount
      put tOut[tI] into tEntry
      if tEntry["type"] is pType and tEntry["key"] is pKeyHex then
         put pValueHex into tEntry["value"]
         put tEntry into tOut[tI]
         return tOut
      end if
   end repeat
   return cwListAdd(tOut, cwPsbtEntry(pType, pKeyHex, pValueHex))
end cwPsbtSetEntry

function cwPsbtSign pB64, pKeys, pNetwork
   -- Sign every input this key set can sign, and leave the rest alone. pKeys
   -- is a list of arrays with "seckey" (hex). Returns an array with "psbt"
   -- (the updated base64), "signed" (how many inputs gained a signature) and
   -- "why" (a line per input that could not be signed, so a person can see
   -- WHICH input is missing WHAT rather than being told the file failed).
   local tP, tTx, tIns, tOuts, tCount, tI, tJ, tKeyCount, tMap, tType, tAmount
   local tSpk, tDigest, tKey, tPub, tSig, tSigned, tWhy, tOut, tInternal
   local tWitScript, tRedeem, tTweaked, tTapKey, tKeys, tTxIns, tTxOuts, tFound
   put cwPsbtParse(pB64) into tP
   put tP["tx"] into tTx
   put tTx["inputs"] into tTxIns
   put tTx["outputs"] into tTxOuts
   put tP["inputs"] into tIns
   put cwListCount(tIns) into tCount
   put cwListCount(pKeys) into tKeyCount
   put 0 into tSigned
   put "" into tWhy
   repeat with tI = 1 to tCount
      put tIns[tI] into tMap
      if cwPsbtFind(tMap, kCwPsbtInFinalScriptSig, "") is not "" \
            or cwPsbtFind(tMap, kCwPsbtInFinalScriptWitness, "") is not "" then
         put tWhy & "input " & tI & ": already finalized" & return into tWhy
         next repeat
      end if
      put cwPsbtInputType(tMap) into tType
      put cwPsbtInputAmount(tMap) into tAmount
      put cwPsbtInputScript(tMap) into tSpk
      if tAmount < 0 then
         put tWhy & "input " & tI & ": no witness UTXO, so the amount BIP-143 " & \
               "commits to is unknown - refusing to guess it" & return into tWhy
         next repeat
      end if
      put cwPsbtFind(tMap, kCwPsbtInWitnessScript, "") into tWitScript
      put false into tFound
      if tType is "p2tr" then
         put cwPsbtFind(tMap, kCwPsbtInTapInternalKey, "") into tInternal
         if tInternal is "" then
            put tWhy & "input " & tI & ": a taproot input with no internal key" & \
                  return into tWhy
            next repeat
         end if
         put cwPsbtTaprootPrevouts(tP) into tOut
         put cwSighash("p2tr", tTx["version"], tTxIns, tTxOuts, tI, tTx["locktime"], \
               "", 0, "", tOut["scripts"], tOut["amounts"]) into tDigest
         repeat with tJ = 1 to tKeyCount
            put pKeys[tJ] into tKey
            put cxHexEncode(cxXOnlyPubkey(cxHexDecode(tKey["seckey"]))) into tPub
            if tPub is tInternal then
               put cwSignTaproot(tKey["seckey"], tDigest, "") into tSig
               put tSig["witness"] into tOut
               put cwPsbtSetEntry(tMap, kCwPsbtInTapKeySig, "", tOut[1]) into tMap
               put tMap into tIns[tI]
               add 1 to tSigned
               put true into tFound
               exit repeat
            end if
         end repeat
         if tFound is not true then
            put tWhy & "input " & tI & ": no key here matches its taproot internal key" \
                  & return into tWhy
         end if
         next repeat
      end if
      repeat with tJ = 1 to tKeyCount
         put pKeys[tJ] into tKey
         put cxHexEncode(cxPublicKey(cxHexDecode(tKey["seckey"]), true)) into tPub
         if tType is "p2wsh" then
            if tWitScript is "" then
               next repeat
            end if
            if cwHexListHas(cwMultisigKeys(tWitScript), tPub) is not true then
               next repeat
            end if
            put cwSighash("p2wsh", tTx["version"], tTxIns, tTxOuts, tI, \
                  tTx["locktime"], "", tAmount, tWitScript, cwListNew(), cwListNew()) into tDigest
         else
            if cwScriptForPubkey(tType, tPub) is not tSpk then
               next repeat
            end if
            put cwSighash(tType, tTx["version"], tTxIns, tTxOuts, tI, \
                  tTx["locktime"], tPub, tAmount, "", cwListNew(), cwListNew()) into tDigest
         end if
         put cxHexEncode(cxDerEncode(cxSign(cxHexDecode(tKey["seckey"]), \
               cxHexDecode(tDigest)))) & "01" into tSig
         put cwPsbtSetEntry(tMap, kCwPsbtInPartialSig, tPub, tSig) into tMap
         put tMap into tIns[tI]
         add 1 to tSigned
         put true into tFound
      end repeat
      if tFound is not true then
         put tWhy & "input " & tI & ": no key here unlocks it (" & tType & ")" & \
               return into tWhy
      end if
   end repeat
   put tIns into tP["inputs"]
   put "" into tOut
   put cwPsbtEmit(tP) into tOut["psbt"]
   put tSigned into tOut["signed"]
   put tWhy into tOut["why"]
   return tOut
end cwPsbtSign

private function cwScriptForPubkey pType, pPubkeyHex
   if pType is "p2pkh" then
      return cwScriptP2pkh(pPubkeyHex)
   end if
   if pType is "p2wpkh" then
      return cwScriptP2wpkh(pPubkeyHex)
   end if
   if pType is "p2sh-p2wpkh" then
      return cwScriptP2shP2wpkh(pPubkeyHex)
   end if
   return ""
end cwScriptForPubkey

function cwHexListHas pList, pValue
   local tI, tCount
   put cwListCount(pList) into tCount
   repeat with tI = 1 to tCount
      if pList[tI] is pValue then
         return true
      end if
   end repeat
   return false
end cwHexListHas

private function cwPsbtTaprootPrevouts pParsed
   -- BIP-341 commits to EVERY input's scriptPubKey and amount, so a taproot
   -- signature cannot be produced from one input's fields alone. A PSBT that
   -- omits any input's witness UTXO cannot be taproot-signed, and this is
   -- where that becomes visible rather than becoming a wrong signature.
   local tIns, tI, tCount, tMap, tScripts, tAmounts, tOut, tAmount
   put pParsed["inputs"] into tIns
   put cwListCount(tIns) into tCount
   put cwListNew() into tScripts
   put cwListNew() into tAmounts
   repeat with tI = 1 to tCount
      put tIns[tI] into tMap
      put cwPsbtInputAmount(tMap) into tAmount
      if tAmount < 0 then
         throw "wallet-core: a taproot input cannot be signed unless EVERY input " & \
               "in the transaction carries its witness UTXO: BIP-341 commits to " & \
               "all of them. Input " & tI & " has none."
      end if
      put cwListAdd(tScripts, cwPsbtInputScript(tMap)) into tScripts
      put cwListAdd(tAmounts, tAmount) into tAmounts
   end repeat
   put tScripts into tOut["scripts"]
   put tAmounts into tOut["amounts"]
   return tOut
end cwPsbtTaprootPrevouts

function cwPsbtFinalize pB64
   -- Turn the partial signatures into the final scriptSig and witness for
   -- every input that has enough of them, and return the network-ready raw
   -- transaction. Returns an array with "raw", "txid", "complete" and "why".
   local tP, tTx, tIns, tCount, tI, tMap, tType, tSigs, tKeys, tWitScript
   local tOut, tScriptSigs, tWitnesses, tItems, tComplete, tWhy, tPub, tSig
   local tJ, tM, tKeyCount, tTapSig, tTxIns, tTxOuts, tHave, tRedeem
   put cwPsbtParse(pB64) into tP
   put tP["tx"] into tTx
   put tP["inputs"] into tIns
   put cwListCount(tIns) into tCount
   put cwListNew() into tScriptSigs
   put cwListNew() into tWitnesses
   put true into tComplete
   put "" into tWhy
   repeat with tI = 1 to tCount
      put tIns[tI] into tMap
      put cwPsbtInputType(tMap) into tType
      put cwListNew() into tItems
      put "" into tSig
      if tType is "p2tr" then
         put cwPsbtFind(tMap, kCwPsbtInTapKeySig, "") into tTapSig
         if tTapSig is "" then
            put false into tComplete
            put tWhy & "input " & tI & ": unsigned (taproot)" & return into tWhy
         else
            put cwListAdd(tItems, tTapSig) into tItems
         end if
         put cwListAdd(tScriptSigs, "") into tScriptSigs
         put cwListAdd(tWitnesses, tItems) into tWitnesses
         next repeat
      end if
      put cwPsbtFindAll(tMap, kCwPsbtInPartialSig) into tSigs
      if tType is "p2wsh" then
         put cwPsbtFind(tMap, kCwPsbtInWitnessScript, "") into tWitScript
         put cwMultisigKeys(tWitScript) into tKeys
         put cwBeRead(cxHexDecode(char 1 to 2 of tWitScript)) - kCwOpOne + 1 into tM
         put cwListAdd(tItems, "") into tItems
         put 0 into tHave
         put cwListCount(tKeys) into tKeyCount
         repeat with tJ = 1 to tKeyCount
            put cwPsbtFind(tMap, kCwPsbtInPartialSig, tKeys[tJ]) into tSig
            if tSig is not "" and tHave < tM then
               put cwListAdd(tItems, tSig) into tItems
               add 1 to tHave
            end if
         end repeat
         put cwListAdd(tItems, tWitScript) into tItems
         if tHave < tM then
            put false into tComplete
            put tWhy & "input " & tI & ": " & tHave & " of " & tM & \
                  " signatures" & return into tWhy
         end if
         put cwListAdd(tScriptSigs, "") into tScriptSigs
         put cwListAdd(tWitnesses, tItems) into tWitnesses
         next repeat
      end if
      if cwListCount(tSigs) is 0 then
         put false into tComplete
         put tWhy & "input " & tI & ": unsigned" & return into tWhy
         put cwListAdd(tScriptSigs, "") into tScriptSigs
         put cwListAdd(tWitnesses, tItems) into tWitnesses
         next repeat
      end if
      put tSigs[1] into tOut
      put tOut["key"] into tPub
      put tOut["value"] into tSig
      if tType is "p2pkh" then
         put cwListAdd(tScriptSigs, cwPush(tSig) & cwPush(tPub)) into tScriptSigs
         put cwListAdd(tWitnesses, tItems) into tWitnesses
         next repeat
      end if
      put cwListAdd(tItems, tSig) into tItems
      put cwListAdd(tItems, tPub) into tItems
      if tType is "p2sh-p2wpkh" then
         put cwPsbtFind(tMap, kCwPsbtInRedeemScript, "") into tRedeem
         if tRedeem is "" then
            put cwRedeemP2shP2wpkh(tPub) into tRedeem
         end if
         put cwListAdd(tScriptSigs, cwPush(tRedeem)) into tScriptSigs
      else
         put cwListAdd(tScriptSigs, "") into tScriptSigs
      end if
      put cwListAdd(tWitnesses, tItems) into tWitnesses
   end repeat
   put tTx["inputs"] into tTxIns
   put tTx["outputs"] into tTxOuts
   put "" into tOut
   put cwTxSerialize(tTx["version"], tTxIns, tTxOuts, tTx["locktime"], \
         tScriptSigs, tWitnesses) into tOut["raw"]
   put cwTxid(tTx["version"], tTxIns, tTxOuts, tTx["locktime"], tScriptSigs) into tOut["txid"]
   put tComplete into tOut["complete"]
   put tWhy into tOut["why"]
   return tOut
end cwPsbtFinalize

function cwPsbtCombine pA, pB
   -- Merge two PSBTs of the SAME transaction: the cosigner workflow. The
   -- unsigned transactions must be identical, and if they are not this
   -- REFUSES rather than picking one - two cosigners holding different
   -- transactions is the exact situation where quietly choosing is worst.
   local tA, tB, tI, tCount, tJ, tN, tMapA, tMapB, tEntry, tOut
   put cwPsbtParse(pA) into tA
   put cwPsbtParse(pB) into tB
   if tA["unsignedtx"] is not tB["unsignedtx"] then
      throw "wallet-core: cwPsbtCombine: these two PSBTs are for DIFFERENT " & \
            "transactions and cannot be merged."
   end if
   put tA["inputs"] into tMapA
   put tB["inputs"] into tMapB
   put cwListCount(tMapA) into tCount
   repeat with tI = 1 to tCount
      put tMapA[tI] into tOut
      put tMapB[tI] into tEntry
      put cwPsbtMergeMap(tOut, tEntry) into tMapA[tI]
   end repeat
   put tMapA into tA["inputs"]
   put tA["outputs"] into tMapA
   put tB["outputs"] into tMapB
   put cwListCount(tMapA) into tCount
   repeat with tI = 1 to tCount
      put tMapA[tI] into tOut
      put tMapB[tI] into tEntry
      put cwPsbtMergeMap(tOut, tEntry) into tMapA[tI]
   end repeat
   put tMapA into tA["outputs"]
   put cwPsbtMergeMap(tA["global"], tB["global"]) into tA["global"]
   return cwPsbtEmit(tA)
end cwPsbtCombine

private function cwPsbtMergeMap pInto, pFrom
   -- Entries from pFrom that pInto does not already have. First writer wins
   -- on a conflict, which is BIP-174's own rule.
   local tOut, tI, tCount, tEntry
   put pInto into tOut
   put cwListCount(pFrom) into tCount
   repeat with tI = 1 to tCount
      put pFrom[tI] into tEntry
      if cwPsbtFind(tOut, tEntry["type"], tEntry["key"]) is "" then
         put cwListAdd(tOut, tEntry) into tOut
      end if
   end repeat
   return tOut
end cwPsbtMergeMap

function cwPsbtSummary pB64, pNetwork
   -- What this PSBT actually does, in words, for the screen a person reads
   -- before they authorise anything. Every wallet that shows only a fee and a
   -- total is asking to be trusted about the part it is not showing.
   local tP, tTx, tOut, tI, tCount, tIn, tOutRec, tTotalIn, tTotalOut, tMap
   local tAmount, tKind, tSigs, tAddr, tError
   put cwPsbtParse(pB64) into tP
   put tP["tx"] into tTx
   put "PSBT: " & cwListCount(tTx["inputs"]) & " input(s), " & \
         cwListCount(tTx["outputs"]) & " output(s), version " & tTx["version"] & \
         ", locktime " & tTx["locktime"] & return into tOut
   put 0 into tTotalIn
   put cwListCount(tTx["inputs"]) into tCount
   put tP["inputs"] into tMap
   repeat with tI = 1 to tCount
      put tTx["inputs"] into tIn
      put tIn[tI] into tIn
      put cwPsbtInputAmount(tMap[tI]) into tAmount
      put cwPsbtFindAll(tMap[tI], kCwPsbtInPartialSig) into tSigs
      put tOut & "  in  " & tI & ": " & char 1 to 16 of tIn["txid"] & "..:" & \
            tIn["vout"] & "  " into tOut
      if tAmount < 0 then
         put "amount UNKNOWN" after tOut
      else
         put cwSatToBtc(tAmount) && "BTC" after tOut
         add tAmount to tTotalIn
      end if
      put "  " & cwPsbtInputType(tMap[tI]) & ", " & cwListCount(tSigs) & \
            " signature(s)" & return after tOut
   end repeat
   put 0 into tTotalOut
   put cwListCount(tTx["outputs"]) into tCount
   repeat with tI = 1 to tCount
      put tTx["outputs"] into tOutRec
      put tOutRec[tI] into tOutRec
      add tOutRec["value"] to tTotalOut
      put "unrecognised script" into tAddr
      try
         put cwAddressForScript(pNetwork, tOutRec["script"]) into tAddr
      catch tError
         put "unrecognised script" into tAddr
      end try
      put tOut & "  out " & tI & ": " & cwSatToBtc(tOutRec["value"]) && "BTC  ->  " & \
            tAddr & return into tOut
   end repeat
   if tTotalIn > 0 then
      put tOut & "  fee: " & cwSatToBtc(tTotalIn - tTotalOut) && "BTC (" & \
            (tTotalIn - tTotalOut) && "sat)" & return into tOut
   else
      put tOut & "  fee: unknown (no input amounts in this PSBT)" & return into tOut
   end if
   return tOut
end cwPsbtSummary
