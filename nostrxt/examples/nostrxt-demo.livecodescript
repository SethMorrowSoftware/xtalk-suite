script "NostrDemo"
-- nostrxt-demo.livecodescript - the NostrXT showcase, one paste-and-run file.
--
-- WHAT THIS IS. A single stack that exercises the whole member the way an
-- app would: generate or import an identity and see its npub, compose and
-- sign a text note (and watch it verify), decode any NIP-19 entity, connect
-- to a relay over ws:// or wss://, subscribe to recent notes, publish, and
-- run the member's full offline self-test into the log. It CARRIES the
-- nostrxt core, the relay layer and the member harness verbatim between the
-- embed sentinels below (tools/sync-demo-embeds.py owns that region), so
-- there is nothing to `start using` first. The CoinXT and SodiumXT
-- EXTENSIONS must be installed for signing and key generation; without them
-- the demo still opens and says exactly what is missing (fail closed, with
-- names).
--
-- WHAT TO LOOK AT AS A TEMPLATE. The callback handler onRelay is the whole
-- relay contract in one switch; ndDoSign is build -> sign -> verify -> show;
-- the self-check block at the bottom is the boot record every suite demo
-- prints.
--
-- HOW TO USE. Paste into a new stack script, then close and reopen the
-- stack. The window builds itself. Opening this file directly does not build
-- it (docs/OXT-ENGINE-NOTES.md 5.5). Point the relay url at a relay you
-- trust; wss:// is the form this stack has actually run on an engine, and
-- ws:// is the one that has not (see the honesty label below - that
-- ordering is the opposite of what this comment used to say, and the merge
-- resolving engine-notes 5.5 into this header kept the ENGINE-EVIDENCE
-- ordering: the incoming side had the stale claim).
--
-- HONESTY (the suite convention): this stack HAS run on a real engine, on
-- 2026-08-24 (Windows x86_64, OXT 9.6.3). Its boot self-check came back 9/9
-- green, and its live legs went to wss://nos.lol: the relay opened, an
-- identity was derived, a kind-1 note was signed, verified, published, and
-- the relay's ok-true came back for its id. What is STILL unrun, and still
-- the runbook's to close: the receive side (subscribe, the EVENT/EOSE/
-- CLOSED/NOTICE callbacks), NIP-42 auth, every ws:// path, and the TLS
-- question the successful run could not answer - it met a VALID certificate,
-- so whether a bad one would be refused is unmeasured in both directions
-- (root docs/OXT-ENGINE-NOTES.md 6.8). The pure-compute answers it shows are
-- pinned by tools/nostr-kat.py.
--
-- THE LOOK. This stack adopts the suite UI kit v2 verbatim (the marked
-- block below); the kit block is never edited here - a look change edits
-- tools/ui-kit.livecodescript and re-carries.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- nostrxt/src/nostrxt.livecodescript ----
-- nostrxt.livecodescript - the NostrXT core library.
--
-- NostrXT is a Nostr protocol layer for OpenXTalk / the xTalk family: NIP-01
-- events (canonical serialization, ids, BIP-340 signatures), NIP-19 bech32
-- entities, NIP-44 v2 encrypted payloads, NIP-01 filters and relay messages,
-- and the pure-compute half of an RFC 6455 websocket client. It adds no
-- cryptography of its own: SHA-256, Schnorr sign/verify, x-only keys and ECDH
-- are CoinXT calls (cx*, ABI >= 6); randomness and constant-time compare are
-- SodiumXT calls (sx*). What this file owns in pure script is exactly the
-- checksummed byte shuffling family law allows there: JSON bytes, bech32 bit
-- packing, the NIP-44 key schedule and padding, websocket framing math.
--
-- THIS FILE DOES NO I/O AND HOLDS NO CONNECTION STATE. The relay client (the
-- stateful websocket state machine over engine sockets) is the separate layer
-- src/nostr-relay.livecodescript (public nxr*), which composes this one - the
-- riptide shape: the compute library stays offline-testable, the transport
-- owns the sockets. That split is also load-bearing for the suite paste,
-- which embeds this file verbatim and must not carry a second definition of
-- the engine's socketError / socketClosed / socketTimeout handlers.
--
-- STATUS: ENGINE-PROVEN 2026-08-24 (Windows x86_64, OXT 9.6.3). This file
-- folded into the suite paste at 274 passed, 0 failed, 2 deliberate skips:
-- the whole nx* surface, the NIP-44 official vectors through the real
-- sodiumxt ABI-10 cipher, and every engine-semantics pin the headless
-- interpreter models. The nxr* relay layer keeps its own, stricter label -
-- see src/nostr-relay.livecodescript, where only the connect/handshake/
-- publish half is live-proven. The pure-compute answers are pinned by
-- tools/nostr-kat.py against the published BIP-340, NIP-44, BIP-173 and
-- NIP-19 vector sets, and tools/check-selftest-vectors.py re-derives every
-- constant the member harness pins.
--
-- Conventions (see CLAUDE.md): public API nxPascalCase; locals t..., params
-- p..., script-locals s..., constants k... ERROR CONVENTION (the riptide
-- shape): no handler in this file ever throws. Functions return empty (or
-- false) on failure and record the reason; nxLastError() returns it. cx*/sx*
-- failures throw, so every foreign call in here sits inside a try. Binary is
-- byte discipline (numToByte / byteToNum / byte chunks), never char/line/word
-- on bytes; itemDelimiter and lineDelimiter are global mutable state and are
-- saved, set, used and restored around every chunk read.
--
-- EVENT SHAPE (the one record this library passes around): an event is an
-- xTalk array with keys "id", "pubkey", "created_at", "kind", "content",
-- "sig" (strings / integers) and "tags" (a 1-based nested array:
-- tEvent["tags"][1][1] = "e", tEvent["tags"][1][2] = <event id>, ...; empty
-- when there are no tags). Ids, pubkeys, seckeys and sigs cross this API as
-- LOWERCASE HEX STRINGS; binary stays internal.
--
-- WIRE FORMATS pinned byte for byte (tools/nostr-kat.py, the member harness):
--   NIP-01 canonical serialization: [0,pubkey,created_at,kind,tags,content],
--     UTF-8, no whitespace, and EXACTLY seven escapes in strings - \" \\ \n
--     \r \t \b \f; every other byte verbatim (json.dumps would \u-escape
--     other controls, which is why the serializer is owned, not borrowed).
--   NIP-19: bech32 (not m) with the BIP-173 90-char cap WAIVED (NIP-19 waives
--     it for TLV entities; the SHOULD cap is 5000 chars).
--   NIP-44 v2: ECDH-x -> HKDF-extract(salt "nip44-v2") conversation key;
--     HKDF-expand(nonce, 76) message keys; u16-prefixed power-of-two padding
--     (plaintext 1..65535 bytes - the published vectors pin the u16 path
--     only, so longer refuses, fail closed); ChaCha20; HMAC-SHA256 over
--     nonce||ciphertext; standard base64.
--
-- EXTENSION DEPENDENCIES, probed, never assumed (nxProbeCapabilities):
--   CoinXT (HARD for signing/encryption): cxSha256, cxSchnorrSign,
--     cxSchnorrVerify, cxXOnlyPubkey, cxEcdh, cxHmacSha256, cxSeckeyIsValid.
--   SodiumXT (soft): sxRandomBytes (key/nonce generation), sxMemEqual
--     (constant-time compare; a masked accumulate-loop stands in when absent).
--   SodiumXT sxChaCha20IetfXor (SHIPPED upstream in SodiumXT ABI 10,
--     2026-08-23; docs/07): the NIP-44 cipher. On an installed SodiumXT
--     older than ABI 10 nxNip44Encrypt/Decrypt still fail closed with a
--     clear capability error, by design; with ABI 10+ the full construction
--     runs and is vector-pinned headlessly (it still needs an OXT pass).

-- ==========================================================================
-- Constants. Declared before first use (OXT resolves a constant by lexical
-- position; a forward reference silently evaluates to nothing).
-- ==========================================================================

constant kNxVersion = "0.1.0"
constant kNxHexAlphabet = "0123456789abcdef"
-- BIP-173's data charset and the bech32m constant (0x2bc830a3), gated against
-- the reference by tools/nostr-kat.py.
constant kNxBech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
constant kNxBech32mConst = 734539939
-- NIP-19 waives BIP-173's 90-char cap for TLV entities and says strings
-- SHOULD stay under 5000 characters; that SHOULD is enforced, fail closed.
constant kNxBech32MaxLen = 5000
-- NIP-44 v2: the HKDF-extract salt and the plaintext byte cap the published
-- vectors pin (65536+ is an invalid length there; see the header).
constant kNxNip44Salt = "nip44-v2"
constant kNxNip44MaxPlain = 65535
-- RFC 6455: the handshake GUID (anchored to the python-websockets reference
-- implementation; see tools/nostr-kat.py), the protocol version, and a frame
-- cap so a hostile length prefix cannot balloon memory (fail closed).
constant kNxWsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
constant kNxWsVersion = "13"
constant kNxWsMaxFrame = 8388608
-- JSON parser guards: nesting depth (fail closed on hostile input) and the
-- NIP-01 subscription-id length cap.
constant kNxJsonMaxDepth = 64
constant kNxSubIdMax = 64

-- ==========================================================================
-- Script-local state. This file is stateless by design bar the error surface,
-- the cached capability probe, and the JSON parser's cursor (single-threaded
-- scratch state: the parser never calls app code, so it cannot re-enter).
-- ==========================================================================

local sNxLastError           -- the reason the last failing nx* call recorded
local sNxCaps                -- cached capability array (nxProbeCapabilities)
local sNxCapsProbed          -- "true" once the probe has run

-- JSON parser scratch (input bytes, 1-based cursor, error, depth counter).
local sNxJsonBytes
local sNxJsonPos
local sNxJsonLen
local sNxJsonErr
local sNxJsonDepth

-- ==========================================================================
-- Version, errors, capabilities.
-- ==========================================================================

function nxVersion
   return "NostrXT" && kNxVersion
end nxVersion

function nxLastError
   return sNxLastError
end nxLastError

private command nxSetError pMessage
   put pMessage into sNxLastError
end nxSetError

function nxProbeCapabilities
   -- Probe ONCE into a cached array, each extension in its own try, each
   -- probe a REAL round-trip rather than a version sniff (the riptide
   -- rsProbeCapabilities shape). Fail closed: a missing extension disables
   -- exactly its feature and never another.
   local tCaps, tError, tHash, tRand, tOut
   if sNxCapsProbed is "true" then
      return sNxCaps
   end if
   put false into tCaps["hasCoin"]
   put false into tCaps["hasSodium"]
   put false into tCaps["canSign"]
   put false into tCaps["canNip44Cipher"]
   put kNxVersion into tCaps["version"]
   try
      -- SHA-256 of empty is the one answer every correct build agrees on.
      put cxSha256(empty) into tHash
      if nxHexEncode(tHash) is "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" then
         put true into tCaps["hasCoin"]
         put true into tCaps["canSign"]
      end if
   catch tError
      put false into tCaps["hasCoin"]
   end try
   try
      put sxRandomBytes(1) into tRand
      if the number of bytes of tRand is 1 then
         put true into tCaps["hasSodium"]
      end if
   catch tError
      put false into tCaps["hasSodium"]
   end try
   try
      -- The upstream NIP-44 cipher (docs/07; shipped in SodiumXT ABI 10,
      -- 2026-08-23). Probe with a 1-byte xor; false only when the INSTALLED
      -- SodiumXT predates ABI 10 - the probe is the seam, not a promise.
      put sxChaCha20IetfXor(nxHexDecode("0000000000000000000000000000000000000000000000000000000000000000"), nxHexDecode("000000000000000000000000"), numToByte(0)) into tOut
      if the number of bytes of tOut is 1 then
         put true into tCaps["canNip44Cipher"]
      end if
   catch tError
      put false into tCaps["canNip44Cipher"]
   end try
   put tCaps into sNxCaps
   put "true" into sNxCapsProbed
   return sNxCaps
end nxProbeCapabilities

-- ==========================================================================
-- Small pure helpers. The arithmetic bit ops exist because ^ / div / mod can
-- misparse in compound expressions on some xTalk parsers, and bitXor's
-- portability is exactly the kind of thing this family has been bitten by
-- (the coinxt cxBitXor precedent). Accumulators stay far below 2^53.
-- ==========================================================================

private function nxIntDiv pA, pB
   return trunc(pA / pB)
end nxIntDiv

private function nxIntMod pA, pB
   return pA - pB * nxIntDiv(pA, pB)
end nxIntMod

private function nxPow2 pN
   -- 2 to the pN as an exact integer; pN <= 52 keeps it exact.
   local tR, tI
   put 1 into tR
   repeat with tI = 1 to pN
      multiply tR by 2
   end repeat
   return tR
end nxPow2

private function nxBitXor31 pA, pB
   -- Bitwise xor over the low 31 bits, built from arithmetic (see the section
   -- header). The bech32 checksum is 30 bits, so 31 is sufficient headroom.
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to 31
      put nxIntMod(nxIntDiv(pA, tBit), 2) into tDigitA
      put nxIntMod(nxIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is not tDigitB then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end nxBitXor31

private function nxCharIndex pChar, pAlphabet
   -- 1-based position of pChar in pAlphabet comparing BYTE VALUES, so the
   -- answer does not depend on `the caseSensitive` (the coinxt cxCharIndex
   -- discipline). Returns 0 if absent.
   local tI, tCount, tWanted
   put byteToNum(pChar) into tWanted
   put the number of chars of pAlphabet into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of pAlphabet) is tWanted then
         return tI
      end if
   end repeat
   return 0
end nxCharIndex

private function nxSeqCount pArray
   -- How many 1-based sequential keys pArray carries (the tag-list shape).
   -- `is among the keys of` involves no delimiter, so this needs no guard.
   local tN
   put 0 into tN
   repeat forever
      if (tN + 1) is among the keys of pArray then
         add 1 to tN
      else
         exit repeat
      end if
   end repeat
   return tN
end nxSeqCount

private function nxLinesToSeq pText
   -- Return-delimited text -> 1-based sequential array, skipping empty lines.
   -- The lineDelimiter is global mutable state: save, set, use, restore.
   local tSavedDelim, tOut, tI, tCount, tLine, tN
   put the lineDelimiter into tSavedDelim
   set the lineDelimiter to return
   put 0 into tN
   put the number of lines of pText into tCount
   repeat with tI = 1 to tCount
      put line tI of pText into tLine
      if tLine is not empty then
         add 1 to tN
         put tLine into tOut[tN]
      end if
   end repeat
   set the lineDelimiter to tSavedDelim
   return tOut
end nxLinesToSeq

private function nxSeqToLines pArray
   -- Inverse of nxLinesToSeq; builds with the `return` constant directly, so
   -- no delimiter guard is needed.
   local tOut, tI, tCount
   put empty into tOut
   put nxSeqCount(pArray) into tCount
   repeat with tI = 1 to tCount
      if tOut is not empty then
         put return after tOut
      end if
      put pArray[tI] after tOut
   end repeat
   return tOut
end nxSeqToLines

function nxB64Encode pData
   -- The engine's base64Encode wraps its output with line breaks; the wire
   -- formats here (NIP-44 payloads, Sec-WebSocket-Key) are single-line, so
   -- strip both break bytes. VERIFY (on-engine): the exact wrap behaviour.
   local tOut
   put base64Encode(pData) into tOut
   replace numToChar(13) with empty in tOut
   replace numToChar(10) with empty in tOut
   return tOut
end nxB64Encode

function nxB64Decode pText
   -- Standard base64 with padding. The engine's decoder tolerates whitespace;
   -- refuse characters outside the alphabet FIRST so a malformed payload is
   -- an error, not a silent partial decode (fail closed).
   local tI, tCount, tCode, tPadFrom, tCh
   put the number of chars of pText into tCount
   if tCount is 0 then
      return empty
   end if
   put 0 into tPadFrom
   repeat with tI = 1 to tCount
      put char tI of pText into tCh
      put byteToNum(tCh) into tCode
      if tCh is "=" then
         if tPadFrom is 0 then
            put tI into tPadFrom
         end if
         next repeat
      end if
      if tPadFrom is not 0 then
         -- data after padding
         return empty
      end if
      if nxCharIndex(tCh, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/") is 0 then
         return empty
      end if
   end repeat
   if nxIntMod(tCount, 4) is not 0 then
      return empty
   end if
   if tPadFrom is not 0 then
      -- At most two pads, only at the very end, and the final group must
      -- carry a legal data residue: pads + (data mod 4) is exactly 4.
      -- Without this, strings every conforming decoder refuses (extra or
      -- misplaced '=', a one-data-char final group) reached the engine's
      -- LENIENT decoder and could round to a valid payload.
      if tCount - tPadFrom + 1 > 2 then
         return empty
      end if
      if nxIntMod(tPadFrom - 1, 4) + (tCount - tPadFrom + 1) is not 4 then
         return empty
      end if
   end if
   return base64Decode(pText)
end nxB64Decode

function nxUnixNow
   -- The unix timestamp (seconds) events stamp created_at with.
   return the seconds
end nxUnixNow

-- ==========================================================================
-- Hex. Lowercase out; mixed case in (0-9 a-f A-F); anything else refuses.
-- ==========================================================================

function nxHexEncode pData
   local tOut, tI, tN, tByte
   put empty into tOut
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put byteToNum(byte tI of pData) into tByte
      put char (nxIntDiv(tByte, 16) + 1) of kNxHexAlphabet after tOut
      put char (nxIntMod(tByte, 16) + 1) of kNxHexAlphabet after tOut
   end repeat
   return tOut
end nxHexEncode

function nxHexDecode pHex
   -- Bytes for a hex string, or empty (with the reason recorded) on odd
   -- length or a non-hex character. Walks with `repeat while` + `add 2`: the
   -- engine does not honour `repeat with ... step` (family law, checker-held).
   local tOut, tI, tCount, tHi, tLo
   put the number of chars of pHex into tCount
   if nxIntMod(tCount, 2) is not 0 then
      nxSetError "nxHexDecode: hex text has odd length"
      return empty
   end if
   put empty into tOut
   put 1 into tI
   repeat while tI < tCount
      put nxHexNibble(char tI of pHex) into tHi
      put nxHexNibble(char (tI + 1) of pHex) into tLo
      if tHi < 0 or tLo < 0 then
         nxSetError "nxHexDecode: not a hex character"
         return empty
      end if
      put numToByte(tHi * 16 + tLo) after tOut
      add 2 to tI
   end repeat
   return tOut
end nxHexDecode

private function nxHexNibble pChar
   -- 0..15 for a hex digit of either case, -1 otherwise (byte-value compare).
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
end nxHexNibble

function nxIsHex pText, pLen
   -- True when pText is entirely hex digits, and (when pLen is not empty) is
   -- exactly pLen characters. The id/pubkey/sig validation everything uses.
   local tI, tCount
   put the number of chars of pText into tCount
   if pLen is not empty and tCount is not pLen then
      return false
   end if
   if tCount is 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      if nxHexNibble(char tI of pText) < 0 then
         return false
      end if
   end repeat
   return true
end nxIsHex

function nxCtEqualHex pAHex, pBHex
   -- Constant-time-ish equality for hex strings (MACs, ids). Prefers
   -- SodiumXT's sxMemEqual (real constant-time compare over the decoded
   -- bytes); without SodiumXT, an accumulate-loop over every character that
   -- never exits early stands in. The honest limit either way: an
   -- interpreter's timing is noisy, and this guards against the gross
   -- early-exit leak, not a lab-grade side channel (the onionxt
   -- oxConstantTimeEqual acceptability argument).
   local tError, tA, tB, tDiff, tI, tCount, tLowA, tLowB
   if the number of chars of pAHex is not the number of chars of pBHex then
      return false
   end if
   -- ONE predicate on both paths: normalize case first, so the verdict
   -- cannot depend on whether SodiumXT happens to be installed (the
   -- sxMemEqual path compared decoded bytes, case-blind; the fallback
   -- compared hex TEXT, case-sensitive - same input, opposite answers).
   put nxToLowerAscii(pAHex) into tLowA
   put nxToLowerAscii(pBHex) into tLowB
   try
      put nxHexDecode(tLowA) into tA
      put nxHexDecode(tLowB) into tB
      if tA is not empty and tB is not empty then
         return sxMemEqual(tA, tB)
      end if
   catch tError
      -- fall through to the pure-script loop
   end try
   put 0 into tDiff
   put the number of chars of tLowA into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of tLowA) is not byteToNum(char tI of tLowB) then
         add 1 to tDiff
      end if
   end repeat
   return tDiff is 0
end nxCtEqualHex

-- ==========================================================================
-- JSON. Owned, because NIP-01's canonical form and JSON disagree about
-- control characters, and because nothing in the suite encodes JSON at all.
-- The parser walks UTF-8 BYTES (structure is ASCII; multi-byte sequences
-- only ever occur inside strings), builds nested arrays of typed nodes, and
-- records byte spans so a message parser can slice VERBATIM sub-documents
-- (an event arriving from a relay is re-serialized canonically for id
-- checking, never trusted to be canonical on the wire).
--
-- Node shape (internal): tNode["t"] is one of "o" (object), "a" (array),
-- "s" (string), "n" (number), "b" (boolean), "z" (null); tNode["v"] is the
-- scalar value; tNode["k"][i] / tNode["c"][i] are 1-based key and child
-- lists; tNode["b1"] / tNode["b2"] are the value's first and last byte
-- positions in the input.
-- ==========================================================================

function nxJsonEscape pText
   -- The NIP-01 escape set, exactly: \" \\ \n \r \t \b \f, everything else
   -- verbatim (including control bytes outside the seven - that is the rule
   -- that makes a borrowed JSON encoder produce WRONG event ids). Works on
   -- UTF-8 bytes; multi-byte sequences pass through untouched.
   local tBytes, tOut, tI, tN, tByte
   put textEncode(pText, "UTF-8") into tBytes
   put empty into tOut
   put the number of bytes of tBytes into tN
   repeat with tI = 1 to tN
      put byteToNum(byte tI of tBytes) into tByte
      if tByte is 34 then
         put numToByte(92) & numToByte(34) after tOut
      else if tByte is 92 then
         put numToByte(92) & numToByte(92) after tOut
      else if tByte is 10 then
         put numToByte(92) & numToByte(110) after tOut
      else if tByte is 13 then
         put numToByte(92) & numToByte(114) after tOut
      else if tByte is 9 then
         put numToByte(92) & numToByte(116) after tOut
      else if tByte is 8 then
         put numToByte(92) & numToByte(98) after tOut
      else if tByte is 12 then
         put numToByte(92) & numToByte(102) after tOut
      else
         put byte tI of tBytes after tOut
      end if
   end repeat
   return textDecode(tOut, "UTF-8")
end nxJsonEscape

private function nxJsonParseText pJson
   -- Parse a whole JSON document; returns the root node array or empty (with
   -- the reason in sNxJsonErr). Resets the module-local cursor state.
   local tRoot
   put textEncode(pJson, "UTF-8") into sNxJsonBytes
   put 1 into sNxJsonPos
   put the number of bytes of sNxJsonBytes into sNxJsonLen
   put empty into sNxJsonErr
   put 0 into sNxJsonDepth
   put nxJsonParseValue() into tRoot
   if sNxJsonErr is not empty then
      return empty
   end if
   nxJsonSkipWs
   if sNxJsonPos <= sNxJsonLen then
      put "trailing bytes after the document" into sNxJsonErr
      return empty
   end if
   return tRoot
end nxJsonParseText

private command nxJsonSkipWs
   local tByte
   repeat while sNxJsonPos <= sNxJsonLen
      put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
      if tByte is 32 or tByte is 9 or tByte is 10 or tByte is 13 then
         add 1 to sNxJsonPos
      else
         exit repeat
      end if
   end repeat
end nxJsonSkipWs

private function nxJsonParseValue
   local tNode, tByte, tStart
   nxJsonSkipWs
   if sNxJsonPos > sNxJsonLen then
      put "unexpected end of document" into sNxJsonErr
      return empty
   end if
   add 1 to sNxJsonDepth
   if sNxJsonDepth > kNxJsonMaxDepth then
      put "nesting deeper than" && kNxJsonMaxDepth into sNxJsonErr
      return empty
   end if
   put sNxJsonPos into tStart
   put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
   if tByte is 123 then
      put nxJsonParseObject() into tNode
   else if tByte is 91 then
      put nxJsonParseArray() into tNode
   else if tByte is 34 then
      put nxJsonParseString() into tNode
   else if tByte is 116 or tByte is 102 then
      put nxJsonParseWord() into tNode
   else if tByte is 110 then
      put nxJsonParseWord() into tNode
   else
      put nxJsonParseNumber() into tNode
   end if
   subtract 1 from sNxJsonDepth
   if sNxJsonErr is not empty then
      return empty
   end if
   put tStart into tNode["b1"]
   put sNxJsonPos - 1 into tNode["b2"]
   return tNode
end nxJsonParseValue

private function nxJsonParseObject
   -- Opening byte 123 confirmed by the caller. Builds parallel 1-based key
   -- and child lists so key order survives (xTalk array keys do not).
   local tNode, tByte, tN, tKeyNode, tChild, tDup
   put "o" into tNode["t"]
   put 0 into tN
   add 1 to sNxJsonPos
   nxJsonSkipWs
   if sNxJsonPos <= sNxJsonLen and byteToNum(byte sNxJsonPos of sNxJsonBytes) is 125 then
      add 1 to sNxJsonPos
      return tNode
   end if
   repeat forever
      nxJsonSkipWs
      if sNxJsonPos > sNxJsonLen or byteToNum(byte sNxJsonPos of sNxJsonBytes) is not 34 then
         put "object member is not a string key" into sNxJsonErr
         return empty
      end if
      put nxJsonParseString() into tKeyNode
      if sNxJsonErr is not empty then
         return empty
      end if
      nxJsonSkipWs
      if sNxJsonPos > sNxJsonLen or byteToNum(byte sNxJsonPos of sNxJsonBytes) is not 58 then
         put "missing colon after object key" into sNxJsonErr
         return empty
      end if
      add 1 to sNxJsonPos
      put nxJsonParseValue() into tChild
      if sNxJsonErr is not empty then
         return empty
      end if
      -- Refuse duplicate member names, fail closed: first-wins readers and
      -- last-wins readers of the same document otherwise disagree about
      -- what it says - the classic duplicate-key desync a relay could use
      -- to show a verifier one content and a reader another.
      repeat with tDup = 1 to tN
         if nxStrEqExact(tNode["k"][tDup], tKeyNode["v"]) then
            put "duplicate object key" into sNxJsonErr
            return empty
         end if
      end repeat
      add 1 to tN
      put tKeyNode["v"] into tNode["k"][tN]
      put tChild into tNode["c"][tN]
      nxJsonSkipWs
      if sNxJsonPos > sNxJsonLen then
         put "unterminated object" into sNxJsonErr
         return empty
      end if
      put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
      add 1 to sNxJsonPos
      if tByte is 125 then
         exit repeat
      end if
      if tByte is not 44 then
         put "expected comma or closing brace in object" into sNxJsonErr
         return empty
      end if
   end repeat
   return tNode
end nxJsonParseObject

private function nxJsonParseArray
   local tNode, tByte, tN, tChild
   put "a" into tNode["t"]
   put 0 into tN
   add 1 to sNxJsonPos
   nxJsonSkipWs
   if sNxJsonPos <= sNxJsonLen and byteToNum(byte sNxJsonPos of sNxJsonBytes) is 93 then
      add 1 to sNxJsonPos
      return tNode
   end if
   repeat forever
      put nxJsonParseValue() into tChild
      if sNxJsonErr is not empty then
         return empty
      end if
      add 1 to tN
      put tChild into tNode["c"][tN]
      nxJsonSkipWs
      if sNxJsonPos > sNxJsonLen then
         put "unterminated array" into sNxJsonErr
         return empty
      end if
      put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
      add 1 to sNxJsonPos
      if tByte is 93 then
         exit repeat
      end if
      if tByte is not 44 then
         put "expected comma or closing bracket in array" into sNxJsonErr
         return empty
      end if
   end repeat
   return tNode
end nxJsonParseArray

private function nxJsonParseString
   -- Opening quote confirmed by the caller. Collects raw bytes, decodes the
   -- backslash escapes (including \uXXXX with surrogate pairs), and hands the
   -- collected bytes to textDecode once, at the end.
   local tNode, tOut, tByte, tEsc, tCode, tCodeTwo, tI, tNib
   put "s" into tNode["t"]
   put empty into tOut
   add 1 to sNxJsonPos
   repeat forever
      if sNxJsonPos > sNxJsonLen then
         put "unterminated string" into sNxJsonErr
         return empty
      end if
      put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
      add 1 to sNxJsonPos
      if tByte is 34 then
         exit repeat
      end if
      if tByte is not 92 then
         put numToByte(tByte) after tOut
         next repeat
      end if
      if sNxJsonPos > sNxJsonLen then
         put "unterminated escape" into sNxJsonErr
         return empty
      end if
      put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tEsc
      add 1 to sNxJsonPos
      if tEsc is 34 then
         put numToByte(34) after tOut
      else if tEsc is 92 then
         put numToByte(92) after tOut
      else if tEsc is 47 then
         put numToByte(47) after tOut
      else if tEsc is 110 then
         put numToByte(10) after tOut
      else if tEsc is 114 then
         put numToByte(13) after tOut
      else if tEsc is 116 then
         put numToByte(9) after tOut
      else if tEsc is 98 then
         put numToByte(8) after tOut
      else if tEsc is 102 then
         put numToByte(12) after tOut
      else if tEsc is 117 then
         put nxJsonHex4() into tCode
         if tCode < 0 then
            return empty
         end if
         if tCode >= 55296 and tCode <= 56319 then
            -- A high surrogate must pair with \uDC00..\uDFFF.
            if sNxJsonPos + 5 > sNxJsonLen then
               put "truncated surrogate pair" into sNxJsonErr
               return empty
            end if
            if byteToNum(byte sNxJsonPos of sNxJsonBytes) is not 92 or byteToNum(byte (sNxJsonPos + 1) of sNxJsonBytes) is not 117 then
               put "high surrogate not followed by an escape" into sNxJsonErr
               return empty
            end if
            add 2 to sNxJsonPos
            put nxJsonHex4() into tCodeTwo
            if tCodeTwo < 56320 or tCodeTwo > 57343 then
               put "high surrogate not followed by a low surrogate" into sNxJsonErr
               return empty
            end if
            put 65536 + (tCode - 55296) * 1024 + (tCodeTwo - 56320) into tCode
         else if tCode >= 56320 and tCode <= 57343 then
            put "lone low surrogate" into sNxJsonErr
            return empty
         end if
         put nxCodepointToUtf8(tCode) after tOut
      else
         put "unknown escape character" into sNxJsonErr
         return empty
      end if
   end repeat
   put textDecode(tOut, "UTF-8") into tNode["v"]
   return tNode
end nxJsonParseString

private function nxJsonHex4
   -- Four hex digits at the cursor -> 0..65535, or -1 (error recorded).
   local tCode, tI, tNib
   put 0 into tCode
   repeat with tI = 1 to 4
      if sNxJsonPos > sNxJsonLen then
         put "truncated unicode escape" into sNxJsonErr
         return -1
      end if
      put nxHexNibble(byte sNxJsonPos of sNxJsonBytes) into tNib
      if tNib < 0 then
         put "bad unicode escape digit" into sNxJsonErr
         return -1
      end if
      put tCode * 16 + tNib into tCode
      add 1 to sNxJsonPos
   end repeat
   return tCode
end nxJsonHex4

private function nxCodepointToUtf8 pCode
   -- Encode one codepoint as UTF-8 bytes, by arithmetic (no engine unicode
   -- surface is trusted with this; the byte layout is the contract).
   local tOut
   if pCode < 128 then
      return numToByte(pCode)
   end if
   if pCode < 2048 then
      put numToByte(192 + nxIntDiv(pCode, 64)) into tOut
      put numToByte(128 + nxIntMod(pCode, 64)) after tOut
      return tOut
   end if
   if pCode < 65536 then
      put numToByte(224 + nxIntDiv(pCode, 4096)) into tOut
      put numToByte(128 + nxIntMod(nxIntDiv(pCode, 64), 64)) after tOut
      put numToByte(128 + nxIntMod(pCode, 64)) after tOut
      return tOut
   end if
   put numToByte(240 + nxIntDiv(pCode, 262144)) into tOut
   put numToByte(128 + nxIntMod(nxIntDiv(pCode, 4096), 64)) after tOut
   put numToByte(128 + nxIntMod(nxIntDiv(pCode, 64), 64)) after tOut
   put numToByte(128 + nxIntMod(pCode, 64)) after tOut
   return tOut
end nxCodepointToUtf8

private function nxJsonParseWord
   -- true / false / null, matched by BYTE VALUE: `is` folds case in this
   -- dialect, and JSON's bare words are lowercase-only, so "tRUE" must refuse.
   local tNode
   if nxJsonWordAt("true") then
      put "b" into tNode["t"]
      put "true" into tNode["v"]
      add 4 to sNxJsonPos
      return tNode
   end if
   if nxJsonWordAt("false") then
      put "b" into tNode["t"]
      put "false" into tNode["v"]
      add 5 to sNxJsonPos
      return tNode
   end if
   if nxJsonWordAt("null") then
      put "z" into tNode["t"]
      put empty into tNode["v"]
      add 4 to sNxJsonPos
      return tNode
   end if
   put "unrecognized bare word" into sNxJsonErr
   return empty
end nxJsonParseWord

private function nxJsonWordAt pWord
   -- True when the exact ASCII bytes of pWord sit at the parser cursor.
   local tI, tCount
   put the number of chars of pWord into tCount
   if sNxJsonPos + tCount - 1 > sNxJsonLen then
      return false
   end if
   repeat with tI = 1 to tCount
      if byteToNum(byte (sNxJsonPos + tI - 1) of sNxJsonBytes) is not byteToNum(char tI of pWord) then
         return false
      end if
   end repeat
   return true
end nxJsonWordAt

private function nxJsonParseNumber
   -- The RFC 8259 number grammar, enforced: -?(0|[1-9][0-9]*)(.[0-9]+)?
   -- ([eE][+-]?[0-9]+)?. The first cut of this collected any run of
   -- number-ish bytes, which accepted "07", "1e", "1-2" and "+5" - and a
   -- "number" like "1e" reaching `+ 0` downstream is a hard engine error
   -- from a never-throw library (the adversarial review's trace). Collected
   -- as TEXT so integer spellings survive verbatim.
   local tNode, tOut, tByte
   put "n" into tNode["t"]
   put empty into tOut
   if sNxJsonPos <= sNxJsonLen and byteToNum(byte sNxJsonPos of sNxJsonBytes) is 45 then
      put "-" after tOut
      add 1 to sNxJsonPos
   end if
   -- int part: one zero, or a nonzero digit then any digits
   if sNxJsonPos > sNxJsonLen then
      put "not a number" into sNxJsonErr
      return empty
   end if
   put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
   if tByte is 48 then
      put "0" after tOut
      add 1 to sNxJsonPos
   else if tByte >= 49 and tByte <= 57 then
      repeat while sNxJsonPos <= sNxJsonLen
         put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
         if tByte >= 48 and tByte <= 57 then
            put numToChar(tByte) after tOut
            add 1 to sNxJsonPos
         else
            exit repeat
         end if
      end repeat
   else
      put "not a number" into sNxJsonErr
      return empty
   end if
   -- optional fraction: "." then at least one digit
   if sNxJsonPos <= sNxJsonLen and byteToNum(byte sNxJsonPos of sNxJsonBytes) is 46 then
      put "." after tOut
      add 1 to sNxJsonPos
      if sNxJsonPos > sNxJsonLen or byteToNum(byte sNxJsonPos of sNxJsonBytes) < 48 or byteToNum(byte sNxJsonPos of sNxJsonBytes) > 57 then
         put "a fraction needs at least one digit" into sNxJsonErr
         return empty
      end if
      repeat while sNxJsonPos <= sNxJsonLen
         put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
         if tByte >= 48 and tByte <= 57 then
            put numToChar(tByte) after tOut
            add 1 to sNxJsonPos
         else
            exit repeat
         end if
      end repeat
   end if
   -- optional exponent: e/E, optional sign, at least one digit
   if sNxJsonPos <= sNxJsonLen and (byteToNum(byte sNxJsonPos of sNxJsonBytes) is 101 or byteToNum(byte sNxJsonPos of sNxJsonBytes) is 69) then
      put numToChar(byteToNum(byte sNxJsonPos of sNxJsonBytes)) after tOut
      add 1 to sNxJsonPos
      if sNxJsonPos <= sNxJsonLen and (byteToNum(byte sNxJsonPos of sNxJsonBytes) is 43 or byteToNum(byte sNxJsonPos of sNxJsonBytes) is 45) then
         put numToChar(byteToNum(byte sNxJsonPos of sNxJsonBytes)) after tOut
         add 1 to sNxJsonPos
      end if
      if sNxJsonPos > sNxJsonLen or byteToNum(byte sNxJsonPos of sNxJsonBytes) < 48 or byteToNum(byte sNxJsonPos of sNxJsonBytes) > 57 then
         put "an exponent needs at least one digit" into sNxJsonErr
         return empty
      end if
      repeat while sNxJsonPos <= sNxJsonLen
         put byteToNum(byte sNxJsonPos of sNxJsonBytes) into tByte
         if tByte >= 48 and tByte <= 57 then
            put numToChar(tByte) after tOut
            add 1 to sNxJsonPos
         else
            exit repeat
         end if
      end repeat
   end if
   put tOut into tNode["v"]
   return tNode
end nxJsonParseNumber

private function nxJsonPathNode pJson, pPath
   -- Walk pPath ("/"-separated: object keys by name, array elements by
   -- 1-based index; empty path = the root) down the parsed document. Returns
   -- the node, or empty with the reason recorded. Keys containing "/" are
   -- not addressable through this convenience (documented limit).
   local tSavedDelim, tRoot, tNode, tI, tCount, tStep, tJ, tKidCount, tFound
   put nxJsonParseText(pJson) into tRoot
   if sNxJsonErr is not empty then
      nxSetError "nxJson: " & sNxJsonErr
      return empty
   end if
   put tRoot into tNode
   if pPath is empty then
      return tNode
   end if
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "/"
   put the number of items of pPath into tCount
   repeat with tI = 1 to tCount
      put item tI of pPath into tStep
      if tNode["t"] is "o" then
         put 0 into tFound
         put nxSeqCount(tNode["k"]) into tKidCount
         repeat with tJ = 1 to tKidCount
            -- BYTE-EXACT, not `is`: `is` folds case AND compares numerically,
            -- so "NAME" would match "name" and "1000" would match "1e3" -
            -- the adversarial review's headline find (it broke every
            -- single-letter tag filter through the #e/#E probe loop).
            if nxStrEqExact(tNode["k"][tJ], tStep) then
               put tJ into tFound
               exit repeat
            end if
         end repeat
         if tFound is 0 then
            set the itemDelimiter to tSavedDelim
            nxSetError "nxJson: no key" && tStep
            return empty
         end if
         put tNode["c"][tFound] into tNode
      else if tNode["t"] is "a" then
         -- Digit runs only: "2.0" and "03" pass `is an integer` by numeric
         -- fold, then miss the STRING-keyed child table silently.
         if not nxIsDigits(tStep) or tStep + 0 < 1 or tStep + 0 > nxSeqCount(tNode["c"]) then
            set the itemDelimiter to tSavedDelim
            nxSetError "nxJson: no element" && tStep
            return empty
         end if
         put tNode["c"][tStep] into tNode
      else
         set the itemDelimiter to tSavedDelim
         nxSetError "nxJson: path descends into a scalar"
         return empty
      end if
   end repeat
   set the itemDelimiter to tSavedDelim
   return tNode
end nxJsonPathNode

function nxJsonGet pJson, pPath
   -- The scalar value at pPath: strings decoded, numbers as text, booleans
   -- "true"/"false", null empty. An object or array at the path returns its
   -- VERBATIM source slice, so a caller can hand a sub-document onward.
   local tNode
   put nxJsonPathNode(pJson, pPath) into tNode
   if tNode is empty then
      return empty
   end if
   if tNode["t"] is "o" or tNode["t"] is "a" then
      return textDecode(byte tNode["b1"] to tNode["b2"] of sNxJsonBytes, "UTF-8")
   end if
   return tNode["v"]
end nxJsonGet

function nxJsonCount pJson, pPath
   -- Element count of the array (or member count of the object) at pPath;
   -- empty on error, 0 for an empty container, and empty (with the reason)
   -- for a scalar.
   local tNode
   put nxJsonPathNode(pJson, pPath) into tNode
   if tNode is empty then
      return empty
   end if
   if tNode["t"] is "a" then
      return nxSeqCount(tNode["c"])
   end if
   if tNode["t"] is "o" then
      return nxSeqCount(tNode["k"])
   end if
   nxSetError "nxJsonCount: not a container at that path"
   return empty
end nxJsonCount

function nxJsonType pJson, pPath
   -- "object" / "array" / "string" / "number" / "boolean" / "null", or
   -- "missing" when the path does not resolve (parse errors record why).
   local tNode, tKind
   put nxJsonPathNode(pJson, pPath) into tNode
   if tNode is empty then
      return "missing"
   end if
   put tNode["t"] into tKind
   if tKind is "o" then
      return "object"
   end if
   if tKind is "a" then
      return "array"
   end if
   if tKind is "s" then
      return "string"
   end if
   if tKind is "n" then
      return "number"
   end if
   if tKind is "b" then
      return "boolean"
   end if
   return "null"
end nxJsonType

-- ==========================================================================
-- Byte-exact string equality. `is` folds case in this dialect, and Nostr tag
-- names are case-sensitive ("p" and "P" are different tags), so every name
-- comparison in this file goes through here.
-- ==========================================================================

private function nxIsDigits pText
   -- True for one or more ASCII digits and nothing else.
   local tI, tCount, tCode
   put the number of chars of pText into tCount
   if tCount is 0 then
      return false
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode < 48 or tCode > 57 then
         return false
      end if
   end repeat
   return true
end nxIsDigits

private function nxIsCanonInt pText
   -- The canonical integer spelling the id preimage may carry: a digit run
   -- with no leading zero (a lone "0" is fine). "07", "1e3" and "5.0" all
   -- coerce to integers in this dialect, and a non-canonical spelling that
   -- reaches the serializer signs an event no conforming client recomputes.
   local tCount
   if not nxIsDigits(pText) then
      return false
   end if
   put the number of chars of pText into tCount
   if tCount > 1 and byteToNum(char 1 of pText) is 48 then
      return false
   end if
   return true
end nxIsCanonInt

private function nxIsLowerHex pText, pLen
   -- nxIsHex plus the wire rule: NIP-01 ids, pubkeys and sigs are
   -- LOWERCASE hex on the wire, and this member refuses rather than
   -- normalizing what it did not produce (fail closed).
   local tI, tCount, tCode
   if not nxIsHex(pText, pLen) then
      return false
   end if
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 70 then
         return false
      end if
   end repeat
   return true
end nxIsLowerHex

private function nxKeyCount pArray
   -- How many keys pArray carries IN TOTAL (nxSeqCount stops at the first
   -- gap, so the two disagreeing is how a gapped table is detected). The
   -- keys join with the return constant; the lineDelimiter is global
   -- mutable state, so guard the read.
   local tSavedLineDelim, tCount
   if pArray is not an array then
      return 0
   end if
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the number of lines of the keys of pArray into tCount
   set the lineDelimiter to tSavedLineDelim
   return tCount
end nxKeyCount

private function nxStrEqExact pA, pB
   local tA, tB, tI, tN
   put textEncode(pA, "UTF-8") into tA
   put textEncode(pB, "UTF-8") into tB
   put the number of bytes of tA into tN
   if tN is not the number of bytes of tB then
      return false
   end if
   repeat with tI = 1 to tN
      if byteToNum(byte tI of tA) is not byteToNum(byte tI of tB) then
         return false
      end if
   end repeat
   return true
end nxStrEqExact

-- ==========================================================================
-- Keys. Generation composes SodiumXT randomness and CoinXT validation; this
-- file mints no randomness and validates no scalar itself (rule 1).
-- ==========================================================================

function nxKeyGenerate
   -- A fresh secret key as 64 lowercase hex, or empty (reason recorded).
   -- Rejection-samples: an out-of-range 32-byte draw is astronomically rare
   -- but checked anyway, because "cannot happen" is not a validation.
   local tError, tTry, tSeckey, tOk
   repeat with tTry = 1 to 10
      try
         put sxRandomBytes(32) into tSeckey
      catch tError
         nxSetError "nxKeyGenerate needs SodiumXT sxRandomBytes"
         return empty
      end try
      put false into tOk
      try
         put cxSeckeyIsValid(tSeckey) into tOk
      catch tError
         nxSetError "nxKeyGenerate needs CoinXT cxSeckeyIsValid"
         return empty
      end try
      if tOk is true then
         return nxHexEncode(tSeckey)
      end if
   end repeat
   nxSetError "nxKeyGenerate: ten random draws in a row were invalid scalars, which points at a broken randomness source"
   return empty
end nxKeyGenerate

function nxKeyPublic pSeckeyHex
   -- The 64-hex x-only public key (the Nostr pubkey) for a secret key.
   local tError, tPub
   if not nxIsHex(pSeckeyHex, 64) then
      nxSetError "nxKeyPublic: the secret key must be 64 hex characters"
      return empty
   end if
   try
      put cxXOnlyPubkey(nxHexDecode(pSeckeyHex)) into tPub
   catch tError
      nxSetError "nxKeyPublic needs CoinXT cxXOnlyPubkey:" && tError
      return empty
   end try
   return nxHexEncode(tPub)
end nxKeyPublic

function nxKeyIsValid pSeckeyHex
   local tError, tOk
   if not nxIsHex(pSeckeyHex, 64) then
      return false
   end if
   try
      put cxSeckeyIsValid(nxHexDecode(pSeckeyHex)) into tOk
   catch tError
      nxSetError "nxKeyIsValid needs CoinXT cxSeckeyIsValid"
      return false
   end try
   return tOk is true
end nxKeyIsValid

-- ==========================================================================
-- Events: build, canonical serialization, id, sign, verify, JSON in and out.
-- The canonical bytes are the contract (header WIRE FORMATS): change nothing
-- here without re-running tools/nostr-kat.py and the member harness.
-- ==========================================================================

function nxEventBuild pKind, pContent, pTags, pCreatedAt
   -- An unsigned event array. pTags is a nested tag array (nxTagsFromText
   -- converts text) or empty; pCreatedAt empty means now.
   local tEvent, tStamp
   if pKind is not an integer or pKind < 0 or pKind > 65535 or not nxIsCanonInt(pKind) then
      nxSetError "nxEventBuild: kind must be a plain integer between 0 and 65535"
      return empty
   end if
   if pCreatedAt is empty then
      put nxUnixNow() into tStamp
   else
      -- nxIsCanonInt as well as the range: "1e3" and "1700000000 " pass
      -- `is an integer` by coercion, get stored VERBATIM, and would be
      -- signed into a preimage no conforming client recomputes.
      if pCreatedAt is not an integer or pCreatedAt < 0 or not nxIsCanonInt(pCreatedAt) then
         nxSetError "nxEventBuild: created_at must be a plain non-negative integer"
         return empty
      end if
      put pCreatedAt into tStamp
   end if
   put pKind into tEvent["kind"]
   put tStamp into tEvent["created_at"]
   put pContent into tEvent["content"]
   put pTags into tEvent["tags"]
   put empty into tEvent["id"]
   put empty into tEvent["pubkey"]
   put empty into tEvent["sig"]
   if not nxEventHasValidShape(tEvent) then
      -- nxEventHasValidShape recorded the specific reason.
      return empty
   end if
   return tEvent
end nxEventBuild

private function nxTagsSerialize pTags
   -- The tags half of the canonical form: an array of arrays of strings,
   -- every string escaped by the NIP-01 rules.
   local tOut, tI, tJ, tTagCount, tItemCount
   put "[" into tOut
   put nxSeqCount(pTags) into tTagCount
   repeat with tI = 1 to tTagCount
      if tI > 1 then
         put "," after tOut
      end if
      put "[" after tOut
      put nxSeqCount(pTags[tI]) into tItemCount
      repeat with tJ = 1 to tItemCount
         if tJ > 1 then
            put "," after tOut
         end if
         put quote & nxJsonEscape(pTags[tI][tJ]) & quote after tOut
      end repeat
      put "]" after tOut
   end repeat
   put "]" after tOut
   return tOut
end nxTagsSerialize

function nxEventSerialize pEvent
   -- The canonical [0,pubkey,created_at,kind,tags,content] string NIP-01
   -- hashes. Refuses an event whose pubkey is not yet filled in: serializing
   -- a half-built event would produce a well-formed WRONG preimage.
   local tOut
   if not nxIsLowerHex(pEvent["pubkey"], 64) then
      nxSetError "nxEventSerialize: the event needs a 64-hex LOWERCASE pubkey (the canonical form; sign fills it in)"
      return empty
   end if
   if not nxEventHasValidShape(pEvent) then
      return empty
   end if
   put "[0," & quote & pEvent["pubkey"] & quote & "," into tOut
   put pEvent["created_at"] & "," & pEvent["kind"] & "," after tOut
   put nxTagsSerialize(pEvent["tags"]) after tOut
   put "," & quote & nxJsonEscape(pEvent["content"]) & quote & "]" after tOut
   return tOut
end nxEventSerialize

function nxEventId pEvent
   -- 64-hex sha256 of the canonical serialization's UTF-8 bytes.
   local tError, tSerialized, tHash
   put nxEventSerialize(pEvent) into tSerialized
   if tSerialized is empty then
      return empty
   end if
   try
      put cxSha256(textEncode(tSerialized, "UTF-8")) into tHash
   catch tError
      nxSetError "nxEventId needs CoinXT cxSha256:" && tError
      return empty
   end try
   return nxHexEncode(tHash)
end nxEventId

function nxEventSign pEvent, pSeckeyHex, pAuxHex
   -- Fill pubkey, id and sig; returns the completed event array or empty.
   -- pAuxHex empty draws fresh BIP-340 auxiliary randomness inside CoinXT's
   -- shim; a 64-hex pAuxHex makes the signature deterministic (KAT-pinnable).
   local tError, tEvent, tAux, tEventId, tSig
   if not nxIsHex(pSeckeyHex, 64) then
      nxSetError "nxEventSign: the secret key must be 64 hex characters"
      return empty
   end if
   if pAuxHex is empty then
      put empty into tAux
   else
      if not nxIsHex(pAuxHex, 64) then
         nxSetError "nxEventSign: aux randomness must be empty or 64 hex characters"
         return empty
      end if
      put nxHexDecode(pAuxHex) into tAux
   end if
   put pEvent into tEvent
   put nxKeyPublic(pSeckeyHex) into tEvent["pubkey"]
   if tEvent["pubkey"] is empty then
      return empty
   end if
   put nxEventId(tEvent) into tEventId
   if tEventId is empty then
      return empty
   end if
   put tEventId into tEvent["id"]
   try
      put cxSchnorrSign(nxHexDecode(pSeckeyHex), nxHexDecode(tEventId), tAux) into tSig
   catch tError
      nxSetError "nxEventSign needs CoinXT cxSchnorrSign:" && tError
      return empty
   end try
   put nxHexEncode(tSig) into tEvent["sig"]
   return tEvent
end nxEventSign

function nxEventVerify pEvent
   -- True only when the id recomputes from the fields AND the signature
   -- verifies over it. Everything else is false with the reason recorded -
   -- an inbound event is untrusted until this says otherwise (rule 2).
   local tError, tEventId, tOk
   if not nxIsHex(pEvent["id"], 64) or not nxIsHex(pEvent["pubkey"], 64) or not nxIsHex(pEvent["sig"], 128) then
      nxSetError "nxEventVerify: id, pubkey or sig missing or malformed"
      return false
   end if
   put nxEventId(pEvent) into tEventId
   if tEventId is empty then
      return false
   end if
   if not nxCtEqualHex(tEventId, pEvent["id"]) then
      nxSetError "nxEventVerify: the id does not match the serialized fields"
      return false
   end if
   put false into tOk
   try
      put cxSchnorrVerify(nxHexDecode(pEvent["pubkey"]), nxHexDecode(tEventId), nxHexDecode(pEvent["sig"])) into tOk
   catch tError
      nxSetError "nxEventVerify needs CoinXT cxSchnorrVerify:" && tError
      return false
   end try
   if tOk is not true then
      nxSetError "nxEventVerify: the signature does not verify"
      return false
   end if
   return true
end nxEventVerify

function nxEventHasValidShape pEvent
   -- Structural validation, with the reason recorded: integers in range,
   -- hex fields (when present) the right length, tags an array of arrays of
   -- strings whose first item is non-empty.
   local tI, tJ, tTagCount, tItemCount
   if pEvent["kind"] is not an integer or pEvent["kind"] < 0 or pEvent["kind"] > 65535 or not nxIsCanonInt(pEvent["kind"]) then
      nxSetError "event shape: kind must be a plain integer between 0 and 65535"
      return false
   end if
   if pEvent["created_at"] is not an integer or pEvent["created_at"] < 0 or not nxIsCanonInt(pEvent["created_at"]) then
      nxSetError "event shape: created_at must be a plain non-negative integer"
      return false
   end if
   if pEvent["id"] is not empty and not nxIsHex(pEvent["id"], 64) then
      nxSetError "event shape: id must be 64 hex characters"
      return false
   end if
   if pEvent["pubkey"] is not empty and not nxIsHex(pEvent["pubkey"], 64) then
      nxSetError "event shape: pubkey must be 64 hex characters"
      return false
   end if
   if pEvent["sig"] is not empty and not nxIsHex(pEvent["sig"], 128) then
      nxSetError "event shape: sig must be 128 hex characters"
      return false
   end if
   if pEvent["content"] is an array then
      nxSetError "event shape: content must be a string"
      return false
   end if
   if pEvent["tags"] is not empty then
      if pEvent["tags"] is not an array then
         nxSetError "event shape: tags must be an array of arrays"
         return false
      end if
      put nxSeqCount(pEvent["tags"]) into tTagCount
      -- DENSE 1-based keys or refuse: nxSeqCount stops at the first gap, so
      -- a 0-based or gapped caller table would sign an event with the
      -- unreachable tags silently DROPPED (fail-open data loss).
      if nxKeyCount(pEvent["tags"]) is not tTagCount then
         nxSetError "event shape: tags keys must be 1-based and dense"
         return false
      end if
      repeat with tI = 1 to tTagCount
         if pEvent["tags"][tI] is not an array then
            nxSetError "event shape: tag" && tI && "is not an array"
            return false
         end if
         put nxSeqCount(pEvent["tags"][tI]) into tItemCount
         if nxKeyCount(pEvent["tags"][tI]) is not tItemCount then
            nxSetError "event shape: tag" && tI && "keys must be 1-based and dense"
            return false
         end if
         if tItemCount < 1 or pEvent["tags"][tI][1] is empty then
            nxSetError "event shape: tag" && tI && "has no name"
            return false
         end if
         repeat with tJ = 1 to tItemCount
            if pEvent["tags"][tI][tJ] is an array then
               nxSetError "event shape: tag" && tI && "item" && tJ && "is not a string"
               return false
            end if
         end repeat
      end repeat
   end if
   return true
end nxEventHasValidShape

function nxEventToJson pEvent
   -- The full wire-format event object (for ["EVENT", ...] and storage).
   -- Field order is fixed for readability; the wire does not care, and the
   -- id never depends on this form (only on nxEventSerialize's).
   local tOut
   if not nxEventHasValidShape(pEvent) then
      return empty
   end if
   put "{" & quote & "id" & quote & ":" & quote & pEvent["id"] & quote into tOut
   put "," & quote & "pubkey" & quote & ":" & quote & pEvent["pubkey"] & quote after tOut
   put "," & quote & "created_at" & quote & ":" & pEvent["created_at"] after tOut
   put "," & quote & "kind" & quote & ":" & pEvent["kind"] after tOut
   put "," & quote & "tags" & quote & ":" & nxTagsSerialize(pEvent["tags"]) after tOut
   put "," & quote & "content" & quote & ":" & quote & nxJsonEscape(pEvent["content"]) & quote after tOut
   put "," & quote & "sig" & quote & ":" & quote & pEvent["sig"] & quote & "}" after tOut
   return tOut
end nxEventToJson

function nxEventFromJson pJson
   -- Parse a wire-format event object into the event array shape. Verifies
   -- STRUCTURE only; call nxEventVerify before trusting the result (rule 2).
   local tRoot, tEvent, tI, tJ, tKidCount, tKeyText, tNode, tTagNode, tTagCount, tItemCount, tN
   put nxJsonParseText(pJson) into tRoot
   if sNxJsonErr is not empty then
      nxSetError "nxEventFromJson:" && sNxJsonErr
      return empty
   end if
   if tRoot["t"] is not "o" then
      nxSetError "nxEventFromJson: not a JSON object"
      return empty
   end if
   put empty into tEvent["id"]
   put empty into tEvent["pubkey"]
   put empty into tEvent["sig"]
   put empty into tEvent["content"]
   put empty into tEvent["tags"]
   put nxSeqCount(tRoot["k"]) into tKidCount
   repeat with tI = 1 to tKidCount
      put tRoot["k"][tI] into tKeyText
      put tRoot["c"][tI] into tNode
      if nxStrEqExact(tKeyText, "id") and tNode["t"] is "s" then
         -- NIP-01: hex fields are lowercase on the wire; refuse rather
         -- than normalize what this library did not produce.
         if not nxIsLowerHex(tNode["v"], 64) then
            nxSetError "nxEventFromJson: id must be 64 lowercase hex characters"
            return empty
         end if
         put tNode["v"] into tEvent["id"]
      else if nxStrEqExact(tKeyText, "pubkey") and tNode["t"] is "s" then
         if not nxIsLowerHex(tNode["v"], 64) then
            nxSetError "nxEventFromJson: pubkey must be 64 lowercase hex characters"
            return empty
         end if
         put tNode["v"] into tEvent["pubkey"]
      else if nxStrEqExact(tKeyText, "sig") and tNode["t"] is "s" then
         if not nxIsLowerHex(tNode["v"], 128) then
            nxSetError "nxEventFromJson: sig must be 128 lowercase hex characters"
            return empty
         end if
         put tNode["v"] into tEvent["sig"]
      else if nxStrEqExact(tKeyText, "content") and tNode["t"] is "s" then
         put tNode["v"] into tEvent["content"]
      else if nxStrEqExact(tKeyText, "created_at") and tNode["t"] is "n" then
         -- Canonical digits only: "1e3", "1.5" and "07" coerce to integers
         -- in this dialect, but a non-canonical number spelling must never
         -- reach the serializer, where it would silently change the id
         -- preimage. (The JSON grammar already refuses "07"; the check
         -- stays here so the invariant does not depend on the parser.)
         if not nxIsCanonInt(tNode["v"]) then
            nxSetError "nxEventFromJson: created_at is not a plain integer"
            return empty
         end if
         put tNode["v"] into tEvent["created_at"]
      else if nxStrEqExact(tKeyText, "kind") and tNode["t"] is "n" then
         if not nxIsCanonInt(tNode["v"]) then
            nxSetError "nxEventFromJson: kind is not a plain integer"
            return empty
         end if
         put tNode["v"] into tEvent["kind"]
      else if nxStrEqExact(tKeyText, "tags") and tNode["t"] is "a" then
         put tNode into tTagNode
         put nxSeqCount(tTagNode["c"]) into tTagCount
         repeat with tJ = 1 to tTagCount
            if tTagNode["c"][tJ]["t"] is not "a" then
               nxSetError "nxEventFromJson: tag" && tJ && "is not an array"
               return empty
            end if
            put nxSeqCount(tTagNode["c"][tJ]["c"]) into tItemCount
            if tItemCount is 0 then
               -- An empty inner tag would leave a GAP in the rebuilt keys,
               -- hiding every later tag from nxSeqCount consumers.
               nxSetError "nxEventFromJson: tag" && tJ && "has no name"
               return empty
            end if
            repeat with tN = 1 to tItemCount
               if tTagNode["c"][tJ]["c"][tN]["t"] is not "s" then
                  nxSetError "nxEventFromJson: tag" && tJ && "item" && tN && "is not a string"
                  return empty
               end if
               put tTagNode["c"][tJ]["c"][tN]["v"] into tEvent["tags"][tJ][tN]
            end repeat
         end repeat
      end if
   end repeat
   if tEvent["created_at"] is not an integer or tEvent["kind"] is not an integer then
      nxSetError "nxEventFromJson: created_at or kind missing or not an integer"
      return empty
   end if
   if not nxEventHasValidShape(tEvent) then
      return empty
   end if
   return tEvent
end nxEventFromJson

-- ==========================================================================
-- Tags: text form (one tag per line, items tab-separated), lookups.
-- ==========================================================================

function nxTagsFromText pText
   -- One tag per line, items tab-separated. Empty lines skip; a line with an
   -- empty first item refuses (a tag must have a name).
   local tSavedLineDelim, tSavedItemDelim, tOut, tI, tJ, tLineCount, tItemCount, tLine, tN
   put the lineDelimiter into tSavedLineDelim
   put the itemDelimiter into tSavedItemDelim
   set the lineDelimiter to return
   set the itemDelimiter to tab
   put 0 into tN
   put the number of lines of pText into tLineCount
   repeat with tI = 1 to tLineCount
      put line tI of pText into tLine
      if tLine is empty then
         next repeat
      end if
      if item 1 of tLine is empty then
         set the lineDelimiter to tSavedLineDelim
         set the itemDelimiter to tSavedItemDelim
         nxSetError "nxTagsFromText: line" && tI && "has an empty tag name"
         return empty
      end if
      add 1 to tN
      put the number of items of tLine into tItemCount
      repeat with tJ = 1 to tItemCount
         put item tJ of tLine into tOut[tN][tJ]
      end repeat
   end repeat
   set the lineDelimiter to tSavedLineDelim
   set the itemDelimiter to tSavedItemDelim
   return tOut
end nxTagsFromText

function nxTagsToText pTags
   -- Inverse of nxTagsFromText. A tag item containing a tab or a line break
   -- cannot round-trip through the text form, so it refuses rather than
   -- silently corrupting (use the array form for such tags).
   local tOut, tI, tJ, tTagCount, tItemCount, tItemText
   put empty into tOut
   put nxSeqCount(pTags) into tTagCount
   repeat with tI = 1 to tTagCount
      if tI > 1 then
         put return after tOut
      end if
      put nxSeqCount(pTags[tI]) into tItemCount
      repeat with tJ = 1 to tItemCount
         put pTags[tI][tJ] into tItemText
         if tItemText contains tab or tItemText contains numToChar(10) or tItemText contains numToChar(13) then
            nxSetError "nxTagsToText: tag" && tI && "item" && tJ && "contains a tab or line break; use the array form"
            return empty
         end if
         if tJ is tItemCount and tItemText is empty then
            -- The engine ignores one trailing delimiter when counting
            -- items (engine notes 2.2), so a trailing empty item cannot
            -- round-trip through the text form: refuse, never corrupt.
            nxSetError "nxTagsToText: tag" && tI && "ends with an empty item, which the text form cannot round-trip; use the array form"
            return empty
         end if
         if tJ > 1 then
            put tab after tOut
         end if
         put tItemText after tOut
      end repeat
   end repeat
   return tOut
end nxTagsToText

function nxTagCount pEvent
   return nxSeqCount(pEvent["tags"])
end nxTagCount

function nxTagItem pEvent, pIndex
   -- Tag number pIndex (1-based) as tab-joined text, or empty.
   local tOut, tJ, tItemCount
   if pIndex is not an integer or pIndex < 1 or pIndex > nxSeqCount(pEvent["tags"]) then
      nxSetError "nxTagItem: no tag" && pIndex
      return empty
   end if
   put empty into tOut
   put nxSeqCount(pEvent["tags"][pIndex]) into tItemCount
   repeat with tJ = 1 to tItemCount
      if tJ > 1 then
         put tab after tOut
      end if
      put pEvent["tags"][pIndex][tJ] after tOut
   end repeat
   return tOut
end nxTagItem

function nxTagFirst pEvent, pTagName
   -- The VALUE (second item) of the first tag named pTagName, or empty.
   -- Byte-exact name compare: "p" and "P" are different tags.
   local tI, tTagCount
   put nxSeqCount(pEvent["tags"]) into tTagCount
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pEvent["tags"][tI][1], pTagName) then
         if 2 is among the keys of pEvent["tags"][tI] then
            return pEvent["tags"][tI][2]
         end if
         return empty
      end if
   end repeat
   return empty
end nxTagFirst

function nxTagValues pEvent, pTagName
   -- Every value of every tag named pTagName, one per line.
   local tOut, tI, tTagCount
   put empty into tOut
   put nxSeqCount(pEvent["tags"]) into tTagCount
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pEvent["tags"][tI][1], pTagName) and 2 is among the keys of pEvent["tags"][tI] then
         if tOut is not empty then
            put return after tOut
         end if
         put pEvent["tags"][tI][2] after tOut
      end if
   end repeat
   return tOut
end nxTagValues

-- ==========================================================================
-- Convenience builders for the core kinds. Every one returns an UNSIGNED
-- event array (nxEventSign completes it), so key material never threads
-- through builders that do not need it.
-- ==========================================================================

function nxMetadataBuild pName, pAbout, pPicture, pCreatedAt
   -- kind 0 user metadata; the content is the stringified JSON object.
   local tContent
   put "{" & quote & "name" & quote & ":" & quote & nxJsonEscape(pName) & quote into tContent
   put "," & quote & "about" & quote & ":" & quote & nxJsonEscape(pAbout) & quote after tContent
   put "," & quote & "picture" & quote & ":" & quote & nxJsonEscape(pPicture) & quote & "}" after tContent
   return nxEventBuild(0, tContent, empty, pCreatedAt)
end nxMetadataBuild

function nxMetadataParse pEvent
   -- The common kind-0 content fields as an array; absent fields are empty.
   local tContent, tOut, tField, tSavedItemDelim
   if pEvent["kind"] is not 0 then
      nxSetError "nxMetadataParse: not a kind 0 event"
      return empty
   end if
   put pEvent["content"] into tContent
   -- `repeat for each item` reads the CURRENT itemDelimiter: guard it.
   put the itemDelimiter into tSavedItemDelim
   set the itemDelimiter to comma
   repeat for each item tField in "name,about,picture,display_name,nip05,website,banner,lud16"
      if nxJsonType(tContent, tField) is "string" then
         put nxJsonGet(tContent, tField) into tOut[tField]
      else
         put empty into tOut[tField]
      end if
   end repeat
   set the itemDelimiter to tSavedItemDelim
   return tOut
end nxMetadataParse

function nxReplyBuild pParentEvent, pContent, pCreatedAt
   -- A kind-1 reply with NIP-10 marked tags: the thread root (the parent's
   -- own "root" e tag, or the parent itself when it has none), a "reply"
   -- marker on the parent, and p tags for the people in the thread.
   local tTags, tRootId, tI, tN, tTagCount, tSeen, tValueText
   if not nxIsHex(pParentEvent["id"], 64) or not nxIsHex(pParentEvent["pubkey"], 64) then
      nxSetError "nxReplyBuild: the parent event has no id or pubkey"
      return empty
   end if
   put empty into tRootId
   put nxSeqCount(pParentEvent["tags"]) into tTagCount
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pParentEvent["tags"][tI][1], "e") and 4 is among the keys of pParentEvent["tags"][tI] then
         if nxStrEqExact(pParentEvent["tags"][tI][4], "root") then
            put pParentEvent["tags"][tI][2] into tRootId
            exit repeat
         end if
      end if
   end repeat
   put 0 into tN
   if tRootId is empty then
      -- The parent IS the thread root: one marked e tag (NIP-10's direct
      -- reply shape).
      add 1 to tN
      put "e" into tTags[tN][1]
      put pParentEvent["id"] into tTags[tN][2]
      put empty into tTags[tN][3]
      put "root" into tTags[tN][4]
   else
      add 1 to tN
      put "e" into tTags[tN][1]
      put tRootId into tTags[tN][2]
      put empty into tTags[tN][3]
      put "root" into tTags[tN][4]
      add 1 to tN
      put "e" into tTags[tN][1]
      put pParentEvent["id"] into tTags[tN][2]
      put empty into tTags[tN][3]
      put "reply" into tTags[tN][4]
   end if
   -- The parent's author, then the parent's own p tags, deduplicated.
   add 1 to tN
   put "p" into tTags[tN][1]
   put pParentEvent["pubkey"] into tTags[tN][2]
   put pParentEvent["pubkey"] into tSeen[pParentEvent["pubkey"]]
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pParentEvent["tags"][tI][1], "p") and 2 is among the keys of pParentEvent["tags"][tI] then
         put pParentEvent["tags"][tI][2] into tValueText
         if nxIsHex(tValueText, 64) and tValueText is not among the keys of tSeen then
            add 1 to tN
            put "p" into tTags[tN][1]
            put tValueText into tTags[tN][2]
            put tValueText into tSeen[tValueText]
         end if
      end if
   end repeat
   return nxEventBuild(1, pContent, tTags, pCreatedAt)
end nxReplyBuild

function nxReactionBuild pTargetEvent, pContent, pCreatedAt
   -- kind 7 reaction (NIP-25); empty content means the conventional "+".
   local tTags, tContent
   if not nxIsHex(pTargetEvent["id"], 64) or not nxIsHex(pTargetEvent["pubkey"], 64) then
      nxSetError "nxReactionBuild: the target event has no id or pubkey"
      return empty
   end if
   put "e" into tTags[1][1]
   put pTargetEvent["id"] into tTags[1][2]
   put "p" into tTags[2][1]
   put pTargetEvent["pubkey"] into tTags[2][2]
   put "k" into tTags[3][1]
   put pTargetEvent["kind"] into tTags[3][2]
   if pContent is empty then
      put "+" into tContent
   else
      put pContent into tContent
   end if
   return nxEventBuild(7, tContent, tTags, pCreatedAt)
end nxReactionBuild

function nxDeleteBuild pIdLines, pReason, pCreatedAt
   -- kind 5 deletion request (NIP-09): one e tag per event id line.
   local tTags, tIdSeq, tI, tCount
   put nxLinesToSeq(pIdLines) into tIdSeq
   put nxSeqCount(tIdSeq) into tCount
   if tCount is 0 then
      nxSetError "nxDeleteBuild: no event ids given"
      return empty
   end if
   repeat with tI = 1 to tCount
      if not nxIsHex(tIdSeq[tI], 64) then
         nxSetError "nxDeleteBuild: line" && tI && "is not a 64-hex event id"
         return empty
      end if
      put "e" into tTags[tI][1]
      put tIdSeq[tI] into tTags[tI][2]
   end repeat
   return nxEventBuild(5, pReason, tTags, pCreatedAt)
end nxDeleteBuild

function nxContactsBuild pPubkeyLines, pCreatedAt
   -- kind 3 contact list: one p tag per followed pubkey line.
   local tTags, tSeq, tI, tCount
   put nxLinesToSeq(pPubkeyLines) into tSeq
   put nxSeqCount(tSeq) into tCount
   repeat with tI = 1 to tCount
      if not nxIsHex(tSeq[tI], 64) then
         nxSetError "nxContactsBuild: line" && tI && "is not a 64-hex pubkey"
         return empty
      end if
      put "p" into tTags[tI][1]
      put tSeq[tI] into tTags[tI][2]
   end repeat
   return nxEventBuild(3, empty, tTags, pCreatedAt)
end nxContactsBuild

function nxContactsParse pEvent
   -- The followed pubkeys of a kind 3 event, one per line.
   if pEvent["kind"] is not 3 then
      nxSetError "nxContactsParse: not a kind 3 event"
      return empty
   end if
   return nxTagValues(pEvent, "p")
end nxContactsParse

function nxRelayListBuild pRelayLines, pCreatedAt
   -- kind 10002 relay list (NIP-65): each line "url" (read and write) or
   -- "url<tab>read" / "url<tab>write".
   local tSavedItemDelim, tTags, tSeq, tI, tCount, tMarker, tUrl
   put nxLinesToSeq(pRelayLines) into tSeq
   put nxSeqCount(tSeq) into tCount
   if tCount is 0 then
      nxSetError "nxRelayListBuild: no relays given"
      return empty
   end if
   put the itemDelimiter into tSavedItemDelim
   set the itemDelimiter to tab
   repeat with tI = 1 to tCount
      put item 1 of tSeq[tI] into tUrl
      put item 2 of tSeq[tI] into tMarker
      if tUrl is empty then
         set the itemDelimiter to tSavedItemDelim
         nxSetError "nxRelayListBuild: line" && tI && "has no url"
         return empty
      end if
      if tMarker is not empty and not nxStrEqExact(tMarker, "read") and not nxStrEqExact(tMarker, "write") then
         set the itemDelimiter to tSavedItemDelim
         nxSetError "nxRelayListBuild: line" && tI && "marker must be read or write"
         return empty
      end if
      put "r" into tTags[tI][1]
      put tUrl into tTags[tI][2]
      if tMarker is not empty then
         put tMarker into tTags[tI][3]
      end if
   end repeat
   set the itemDelimiter to tSavedItemDelim
   return nxEventBuild(10002, empty, tTags, pCreatedAt)
end nxRelayListBuild

function nxRelayListParse pEvent
   -- The r tags of a kind 10002 event, one relay per line: "url" or
   -- "url<tab>marker".
   local tOut, tI, tTagCount
   if pEvent["kind"] is not 10002 then
      nxSetError "nxRelayListParse: not a kind 10002 event"
      return empty
   end if
   put empty into tOut
   put nxSeqCount(pEvent["tags"]) into tTagCount
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pEvent["tags"][tI][1], "r") and 2 is among the keys of pEvent["tags"][tI] then
         if tOut is not empty then
            put return after tOut
         end if
         put pEvent["tags"][tI][2] after tOut
         if 3 is among the keys of pEvent["tags"][tI] then
            put tab & pEvent["tags"][tI][3] after tOut
         end if
      end if
   end repeat
   return tOut
end nxRelayListParse

function nxAuthBuild pRelayUrl, pChallenge, pCreatedAt
   -- kind 22242 NIP-42 authentication event (sign it, then nxClientAuth).
   local tTags
   if pRelayUrl is empty or pChallenge is empty then
      nxSetError "nxAuthBuild: the relay url and the challenge are both required"
      return empty
   end if
   put "relay" into tTags[1][1]
   put pRelayUrl into tTags[1][2]
   put "challenge" into tTags[2][1]
   put pChallenge into tTags[2][2]
   return nxEventBuild(22242, empty, tTags, pCreatedAt)
end nxAuthBuild

-- ==========================================================================
-- bech32 (BIP-173) and the NIP-19 entities. The 5-bit value lists flow as
-- 1-based sequential ARRAYS, never as delimited text, so no delimiter state
-- is touched anywhere in this section. The 90-character BIP-173 cap is
-- deliberately WAIVED (NIP-19 waives it for TLV entities); the NIP-19
-- SHOULD cap of 5000 characters is enforced instead, both directions.
-- ==========================================================================

private function nxConvert8To5 pData
   -- Bytes -> 5-bit values (zero-padded tail), as a sequential array. The
   -- accumulator is masked to its pending bits each step (exact-integer
   -- discipline: a long buffer must never build a big integer).
   local tOut, tBits, tValue, tI, tN, tCount
   put 0 into tBits
   put 0 into tValue
   put 0 into tCount
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         add 1 to tCount
         put nxIntMod(nxIntDiv(tValue, nxPow2(tBits)), 32) into tOut[tCount]
      end repeat
      put nxIntMod(tValue, nxPow2(tBits)) into tValue
   end repeat
   if tBits > 0 then
      add 1 to tCount
      put nxIntMod(tValue * nxPow2(5 - tBits), 32) into tOut[tCount]
   end if
   return tOut
end nxConvert8To5

private function nxConvert5To8 pValues
   -- 5-bit values -> bytes, STRICT (BIP-173 decode rules): more than four
   -- leftover bits, or non-zero padding bits, refuse. Returns an array with
   -- keys "bytes" and "ok" plus "why" on refusal.
   local tOut, tResult, tBits, tValue, tI, tN
   put 0 into tBits
   put 0 into tValue
   put empty into tOut
   put nxSeqCount(pValues) into tN
   repeat with tI = 1 to tN
      put tValue * 32 + pValues[tI] into tValue
      add 5 to tBits
      if tBits >= 8 then
         subtract 8 from tBits
         put numToByte(nxIntMod(nxIntDiv(tValue, nxPow2(tBits)), 256)) after tOut
         put nxIntMod(tValue, nxPow2(tBits)) into tValue
      end if
   end repeat
   if tBits >= 5 then
      put false into tResult["ok"]
      put "too many padding bits" into tResult["why"]
      return tResult
   end if
   if tValue is not 0 then
      put false into tResult["ok"]
      put "non-zero padding bits" into tResult["why"]
      return tResult
   end if
   put true into tResult["ok"]
   put tOut into tResult["bytes"]
   return tResult
end nxConvert5To8

private function nxBech32Polymod pValues
   -- BIP-173's checksum over a sequential array of 5-bit values. The
   -- generator constants are the BIP's (decimal spellings of the published
   -- hex), gated against the reference by tools/nostr-kat.py.
   local tChk, tI, tCount, tTop, tBit, tGen
   put 996825010 into tGen[1]
   put 642813549 into tGen[2]
   put 513874426 into tGen[3]
   put 1027748829 into tGen[4]
   put 705979059 into tGen[5]
   put 1 into tChk
   put nxSeqCount(pValues) into tCount
   repeat with tI = 1 to tCount
      put nxIntDiv(tChk, 33554432) into tTop
      put nxBitXor31(nxIntMod(tChk, 33554432) * 32, pValues[tI]) into tChk
      repeat with tBit = 1 to 5
         if nxIntMod(nxIntDiv(tTop, nxPow2(tBit - 1)), 2) is 1 then
            put nxBitXor31(tChk, tGen[tBit]) into tChk
         end if
      end repeat
   end repeat
   return tChk
end nxBech32Polymod

private function nxBech32HrpExpand pHrp
   -- The HRP contributes its high bits, a zero, then its low bits.
   local tOut, tI, tCount, tCode, tN
   put the number of chars of pHrp into tCount
   put 0 into tN
   repeat with tI = 1 to tCount
      add 1 to tN
      put nxIntDiv(byteToNum(char tI of pHrp), 32) into tOut[tN]
   end repeat
   add 1 to tN
   put 0 into tOut[tN]
   repeat with tI = 1 to tCount
      add 1 to tN
      put nxIntMod(byteToNum(char tI of pHrp), 32) into tOut[tN]
   end repeat
   return tOut
end nxBech32HrpExpand

private function nxBech32SpecConst pSpec
   if pSpec is "bech32m" then
      return kNxBech32mConst
   end if
   return 1
end nxBech32SpecConst

private function nxCaseKind pText
   -- "lower", "upper", "mixed" or "none" over the ASCII letters of pText.
   local tI, tCount, tCode, tHasLower, tHasUpper
   put false into tHasLower
   put false into tHasUpper
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 97 and tCode <= 122 then
         put true into tHasLower
      end if
      if tCode >= 65 and tCode <= 90 then
         put true into tHasUpper
      end if
   end repeat
   if tHasLower and tHasUpper then
      return "mixed"
   end if
   if tHasLower then
      return "lower"
   end if
   if tHasUpper then
      return "upper"
   end if
   return "none"
end nxCaseKind

private function nxToLowerAscii pText
   -- ASCII-only lowercasing by byte value (`toLower`'s locale behaviour is
   -- nothing this wire format wants to depend on).
   local tOut, tI, tCount, tCode
   put empty into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         put numToChar(tCode + 32) after tOut
      else
         put numToChar(tCode) after tOut
      end if
   end repeat
   return tOut
end nxToLowerAscii

function nxBech32Encode pHrp, pHex, pSpec
   -- Encode bytes (as hex) under pHrp; pSpec "bech32" (default, NIP-19) or
   -- "bech32m". Lowercase out; an uppercase HRP refuses (uppercase the
   -- finished string instead, which is what BIP-173 defines).
   local tData, tValues, tCombined, tPolymod, tOut, tI, tCount, tCode, tN, tIndex
   put the number of chars of pHrp into tCount
   if tCount < 1 or tCount > 83 then
      nxSetError "nxBech32Encode: the human-readable part must be 1 to 83 characters"
      return empty
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pHrp) into tCode
      if tCode < 33 or tCode > 126 then
         nxSetError "nxBech32Encode: the human-readable part must be printable ASCII"
         return empty
      end if
      if tCode >= 65 and tCode <= 90 then
         nxSetError "nxBech32Encode: the human-readable part must be lowercase; uppercase the finished string instead"
         return empty
      end if
   end repeat
   if pSpec is not empty and pSpec is not "bech32" and pSpec is not "bech32m" then
      nxSetError "nxBech32Encode: spec must be bech32 or bech32m"
      return empty
   end if
   put nxHexDecode(pHex) into tData
   if tData is empty and pHex is not empty then
      return empty
   end if
   put nxConvert8To5(tData) into tValues
   -- checksum input: hrp expansion, data, six zeros
   put nxBech32HrpExpand(pHrp) into tCombined
   put nxSeqCount(tCombined) into tN
   put nxSeqCount(tValues) into tCount
   repeat with tI = 1 to tCount
      add 1 to tN
      put tValues[tI] into tCombined[tN]
   end repeat
   repeat with tI = 1 to 6
      add 1 to tN
      put 0 into tCombined[tN]
   end repeat
   put nxBitXor31(nxBech32Polymod(tCombined), nxBech32SpecConst(pSpec)) into tPolymod
   put pHrp & "1" into tOut
   put nxSeqCount(tValues) into tCount
   repeat with tI = 1 to tCount
      put char (tValues[tI] + 1) of kNxBech32Charset after tOut
   end repeat
   repeat with tI = 0 to 5
      put nxIntMod(nxIntDiv(tPolymod, nxPow2(5 * (5 - tI))), 32) into tIndex
      put char (tIndex + 1) of kNxBech32Charset after tOut
   end repeat
   if the number of chars of tOut > kNxBech32MaxLen then
      nxSetError "nxBech32Encode: the result would exceed the" && kNxBech32MaxLen & "-character NIP-19 cap"
      return empty
   end if
   return tOut
end nxBech32Encode

function nxBech32Decode pText
   -- Decode either spec. Returns an array with keys "hrp", "spec" and "hex"
   -- (the data bytes, checksum stripped, as lowercase hex), or empty with
   -- the reason recorded. Mixed case refuses; padding is strict.
   local tResult, tLower, tCount, tI, tCode, tPos, tHrp, tDataText, tValues, tIndex, tCheck, tPayload, tN, tCase
   put the number of chars of pText into tCount
   if tCount > kNxBech32MaxLen then
      nxSetError "nxBech32Decode: longer than the" && kNxBech32MaxLen & "-character NIP-19 cap"
      return empty
   end if
   put nxCaseKind(pText) into tCase
   if tCase is "mixed" then
      nxSetError "nxBech32Decode: mixed case is not allowed"
      return empty
   end if
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode < 33 or tCode > 126 then
         nxSetError "nxBech32Decode: character outside printable ASCII"
         return empty
      end if
   end repeat
   put nxToLowerAscii(pText) into tLower
   -- The separator is the LAST "1" ("1" may appear inside the HRP).
   put 0 into tPos
   repeat with tI = tCount down to 1
      if byteToNum(char tI of tLower) is 49 then
         put tI into tPos
         exit repeat
      end if
   end repeat
   -- The data part must be at least the 6 checksum characters: tPos + 6,
   -- not + 7 (the reference's 0-based pos+7 bound, re-based). The first
   -- cut carried the 0-based spelling and refused every valid empty-
   -- payload string, including BIP-173's own "A12UEL5L" vector.
   if tPos < 2 or tPos + 6 > tCount then
      nxSetError "nxBech32Decode: bad separator position"
      return empty
   end if
   put char 1 to (tPos - 1) of tLower into tHrp
   put char (tPos + 1) to tCount of tLower into tDataText
   put the number of chars of tDataText into tN
   repeat with tI = 1 to tN
      put nxCharIndex(char tI of tDataText, kNxBech32Charset) into tIndex
      if tIndex is 0 then
         nxSetError "nxBech32Decode: character outside the bech32 charset"
         return empty
      end if
      put tIndex - 1 into tValues[tI]
   end repeat
   -- Verify: polymod(hrpExpand + data incl checksum) is the spec constant.
   local tCombined, tJ
   put nxBech32HrpExpand(tHrp) into tCombined
   put nxSeqCount(tCombined) into tJ
   repeat with tI = 1 to tN
      add 1 to tJ
      put tValues[tI] into tCombined[tJ]
   end repeat
   put nxBech32Polymod(tCombined) into tCheck
   if tCheck is 1 then
      put "bech32" into tResult["spec"]
   else if tCheck is kNxBech32mConst then
      put "bech32m" into tResult["spec"]
   else
      nxSetError "nxBech32Decode: bad checksum"
      return empty
   end if
   -- Strip the six checksum values, repack 5 -> 8 strictly.
   local tDataValues, tConverted
   repeat with tI = 1 to tN - 6
      put tValues[tI] into tDataValues[tI]
   end repeat
   put nxConvert5To8(tDataValues) into tConverted
   if tConverted["ok"] is not true then
      nxSetError "nxBech32Decode:" && tConverted["why"]
      return empty
   end if
   put tHrp into tResult["hrp"]
   put nxHexEncode(tConverted["bytes"]) into tResult["hex"]
   return tResult
end nxBech32Decode

private function nxBareEncode pHrp, pHex
   -- npub / nsec / note share one shape: exactly 32 bytes, bech32 (not m).
   if not nxIsHex(pHex, 64) then
      nxSetError "nx" & pHrp & "Encode: the payload must be 64 hex characters"
      return empty
   end if
   return nxBech32Encode(pHrp, pHex, "bech32")
end nxBareEncode

private function nxBareDecode pText, pHrp
   -- Decode a bare entity; enforce the hrp, the spec and the 32-byte payload.
   local tDecoded
   put nxBech32Decode(pText) into tDecoded
   if tDecoded is empty then
      return empty
   end if
   if not nxStrEqExact(tDecoded["hrp"], pHrp) then
      nxSetError "expected a" && pHrp && "entity, got" && tDecoded["hrp"]
      return empty
   end if
   if tDecoded["spec"] is not "bech32" then
      nxSetError pHrp && "entities are bech32, not bech32m"
      return empty
   end if
   if the number of chars of tDecoded["hex"] is not 64 then
      nxSetError pHrp && "payload is not 32 bytes"
      return empty
   end if
   return tDecoded["hex"]
end nxBareDecode

function nxNpubEncode pPubkeyHex
   return nxBareEncode("npub", pPubkeyHex)
end nxNpubEncode

function nxNpubDecode pText
   return nxBareDecode(pText, "npub")
end nxNpubDecode

function nxNsecEncode pSeckeyHex
   return nxBareEncode("nsec", pSeckeyHex)
end nxNsecEncode

function nxNsecDecode pText
   return nxBareDecode(pText, "nsec")
end nxNsecDecode

function nxNoteEncode pIdHex
   return nxBareEncode("note", pIdHex)
end nxNoteEncode

function nxNoteDecode pText
   return nxBareDecode(pText, "note")
end nxNoteDecode

private function nxTlvAppend pPayload, pTagByte, pValueData
   -- One TLV item (type, length, value); value must fit one length byte.
   if the number of bytes of pValueData > 255 then
      nxSetError "NIP-19 TLV value longer than 255 bytes"
      return empty
   end if
   return pPayload & numToByte(pTagByte) & numToByte(the number of bytes of pValueData) & pValueData
end nxTlvAppend

private function nxTlvRelays pPayload, pRelayLines
   -- Append a type-1 TLV per relay line (ascii); refuses a non-ascii url.
   local tSeq, tI, tCount, tBytes, tOut
   put pPayload into tOut
   put nxLinesToSeq(pRelayLines) into tSeq
   put nxSeqCount(tSeq) into tCount
   repeat with tI = 1 to tCount
      put textEncode(tSeq[tI], "UTF-8") into tBytes
      if the number of bytes of tBytes is not the number of chars of tSeq[tI] then
         nxSetError "NIP-19 relay urls must be ascii"
         return empty
      end if
      put nxTlvAppend(tOut, 1, tBytes) into tOut
      if tOut is empty then
         return empty
      end if
   end repeat
   return tOut
end nxTlvRelays

private function nxKindToU32 pKind
   -- A kind as 4 big-endian bytes (the NIP-19 TLV type 3 encoding).
   local tOut
   put numToByte(nxIntMod(nxIntDiv(pKind, 16777216), 256)) into tOut
   put numToByte(nxIntMod(nxIntDiv(pKind, 65536), 256)) after tOut
   put numToByte(nxIntMod(nxIntDiv(pKind, 256), 256)) after tOut
   put numToByte(nxIntMod(pKind, 256)) after tOut
   return tOut
end nxKindToU32

function nxNprofileEncode pPubkeyHex, pRelayLines
   local tPayload
   if not nxIsHex(pPubkeyHex, 64) then
      nxSetError "nxNprofileEncode: the pubkey must be 64 hex characters"
      return empty
   end if
   put nxTlvAppend(empty, 0, nxHexDecode(pPubkeyHex)) into tPayload
   put nxTlvRelays(tPayload, pRelayLines) into tPayload
   if tPayload is empty then
      return empty
   end if
   return nxBech32Encode("nprofile", nxHexEncode(tPayload), "bech32")
end nxNprofileEncode

function nxNprofileDecode pText
   -- Returns an array with keys "pubkey" and "relays" (one per line).
   local tFields
   put nxEntityDecode(pText) into tFields
   if tFields is empty then
      return empty
   end if
   if not nxStrEqExact(tFields["type"], "nprofile") then
      nxSetError "expected an nprofile entity, got" && tFields["type"]
      return empty
   end if
   return tFields
end nxNprofileDecode

function nxNeventEncode pIdHex, pRelayLines, pAuthorHex, pKind
   local tPayload
   if not nxIsHex(pIdHex, 64) then
      nxSetError "nxNeventEncode: the event id must be 64 hex characters"
      return empty
   end if
   put nxTlvAppend(empty, 0, nxHexDecode(pIdHex)) into tPayload
   put nxTlvRelays(tPayload, pRelayLines) into tPayload
   if tPayload is empty then
      return empty
   end if
   if pAuthorHex is not empty then
      if not nxIsHex(pAuthorHex, 64) then
         nxSetError "nxNeventEncode: the author must be 64 hex characters"
         return empty
      end if
      put nxTlvAppend(tPayload, 2, nxHexDecode(pAuthorHex)) into tPayload
   end if
   if pKind is not empty then
      if pKind is not an integer or pKind < 0 or pKind > 65535 then
         nxSetError "nxNeventEncode: kind must be an integer between 0 and 65535"
         return empty
      end if
      put nxTlvAppend(tPayload, 3, nxKindToU32(pKind)) into tPayload
   end if
   return nxBech32Encode("nevent", nxHexEncode(tPayload), "bech32")
end nxNeventEncode

function nxNeventDecode pText
   local tFields
   put nxEntityDecode(pText) into tFields
   if tFields is empty then
      return empty
   end if
   if not nxStrEqExact(tFields["type"], "nevent") then
      nxSetError "expected an nevent entity, got" && tFields["type"]
      return empty
   end if
   return tFields
end nxNeventDecode

function nxNaddrEncode pIdentifier, pPubkeyHex, pKind, pRelayLines
   -- The addressable-event coordinate: identifier (the d tag; may be empty
   -- for normal replaceable events), author pubkey and kind are REQUIRED.
   local tPayload
   if not nxIsHex(pPubkeyHex, 64) then
      nxSetError "nxNaddrEncode: the pubkey must be 64 hex characters"
      return empty
   end if
   if pKind is not an integer or pKind < 0 or pKind > 65535 then
      nxSetError "nxNaddrEncode: kind must be an integer between 0 and 65535"
      return empty
   end if
   put nxTlvAppend(empty, 0, textEncode(pIdentifier, "UTF-8")) into tPayload
   if tPayload is empty then
      -- Checked HERE, before the relay TLVs could refill the payload and
      -- mask the refusal: an over-255-byte identifier would otherwise be
      -- silently DROPPED from a checksum-valid naddr naming the wrong
      -- coordinate. (An empty identifier still yields its 2-byte header,
      -- so this guard cannot false-positive.)
      return empty
   end if
   put nxTlvRelays(tPayload, pRelayLines) into tPayload
   if tPayload is empty then
      return empty
   end if
   put nxTlvAppend(tPayload, 2, nxHexDecode(pPubkeyHex)) into tPayload
   put nxTlvAppend(tPayload, 3, nxKindToU32(pKind)) into tPayload
   return nxBech32Encode("naddr", nxHexEncode(tPayload), "bech32")
end nxNaddrEncode

function nxNaddrDecode pText
   local tFields
   put nxEntityDecode(pText) into tFields
   if tFields is empty then
      return empty
   end if
   if not nxStrEqExact(tFields["type"], "naddr") then
      nxSetError "expected an naddr entity, got" && tFields["type"]
      return empty
   end if
   return tFields
end nxNaddrDecode

function nxEntityDecode pText
   -- The generic decoder every entity handler shares: accepts any NIP-19
   -- entity (a nostr: URI prefix is stripped first) and returns an array
   -- keyed by "type" plus the fields that entity carries. Unknown TLV types
   -- are IGNORED, as NIP-19 requires.
   local tText, tDecoded, tPayload, tFields, tPos, tLen, tTagByte, tValueData, tByteCount, tRelayCount, tKindValue, tI
   put pText into tText
   if char 1 to 6 of tText is "nostr:" then
      put char 7 to (the number of chars of tText) of tText into tText
   end if
   put nxBech32Decode(tText) into tDecoded
   if tDecoded is empty then
      return empty
   end if
   if tDecoded["spec"] is not "bech32" then
      nxSetError "NIP-19 entities are bech32, not bech32m"
      return empty
   end if
   put tDecoded["hrp"] into tFields["type"]
   -- Bare entities: a fixed 32-byte payload.
   if tFields["type"] is "npub" or tFields["type"] is "nsec" or tFields["type"] is "note" then
      if the number of chars of tDecoded["hex"] is not 64 then
         nxSetError tFields["type"] && "payload is not 32 bytes"
         return empty
      end if
      if tFields["type"] is "npub" then
         put tDecoded["hex"] into tFields["pubkey"]
      else if tFields["type"] is "nsec" then
         put tDecoded["hex"] into tFields["seckey"]
      else
         put tDecoded["hex"] into tFields["id"]
      end if
      return tFields
   end if
   if tFields["type"] is not "nprofile" and tFields["type"] is not "nevent" and tFields["type"] is not "naddr" then
      nxSetError "nxEntityDecode: unknown entity type" && tFields["type"]
      return empty
   end if
   -- TLV entities.
   put nxHexDecode(tDecoded["hex"]) into tPayload
   put empty into tFields["relays"]
   put empty into tFields["pubkey"]
   put empty into tFields["id"]
   put empty into tFields["identifier"]
   put empty into tFields["kind"]
   put 0 into tRelayCount
   put 1 into tPos
   put the number of bytes of tPayload into tByteCount
   repeat while tPos <= tByteCount
      if tPos + 1 > tByteCount then
         nxSetError "nxEntityDecode: truncated TLV header"
         return empty
      end if
      put byteToNum(byte tPos of tPayload) into tTagByte
      put byteToNum(byte (tPos + 1) of tPayload) into tLen
      if tPos + 1 + tLen > tByteCount then
         nxSetError "nxEntityDecode: truncated TLV value"
         return empty
      end if
      if tLen is 0 then
         put empty into tValueData
      else
         put byte (tPos + 2) to (tPos + 1 + tLen) of tPayload into tValueData
      end if
      add 2 + tLen to tPos
      if tTagByte is 0 then
         if tFields["type"] is "naddr" then
            put textDecode(tValueData, "UTF-8") into tFields["identifier"]
         else
            if tLen is not 32 then
               nxSetError "nxEntityDecode: the special TLV must be 32 bytes"
               return empty
            end if
            if tFields["type"] is "nprofile" then
               put nxHexEncode(tValueData) into tFields["pubkey"]
            else
               put nxHexEncode(tValueData) into tFields["id"]
            end if
         end if
      else if tTagByte is 1 then
         add 1 to tRelayCount
         if tFields["relays"] is not empty then
            put return after tFields["relays"]
         end if
         put textDecode(tValueData, "UTF-8") after tFields["relays"]
      else if tTagByte is 2 then
         if tLen is not 32 then
            nxSetError "nxEntityDecode: the author TLV must be 32 bytes"
            return empty
         end if
         put nxHexEncode(tValueData) into tFields["pubkey"]
      else if tTagByte is 3 then
         if tLen is not 4 then
            nxSetError "nxEntityDecode: the kind TLV must be 4 bytes"
            return empty
         end if
         put byteToNum(byte 1 of tValueData) * 16777216 into tKindValue
         add byteToNum(byte 2 of tValueData) * 65536 to tKindValue
         add byteToNum(byte 3 of tValueData) * 256 to tKindValue
         add byteToNum(byte 4 of tValueData) to tKindValue
         put tKindValue into tFields["kind"]
      end if
      -- Unknown TLV types fall through untouched: NIP-19 says ignore them.
   end repeat
   -- The required field per type.
   if tFields["type"] is "nprofile" and tFields["pubkey"] is empty then
      nxSetError "nxEntityDecode: nprofile carries no pubkey"
      return empty
   end if
   if tFields["type"] is "nevent" and tFields["id"] is empty then
      nxSetError "nxEntityDecode: nevent carries no id"
      return empty
   end if
   if tFields["type"] is "naddr" and (tFields["pubkey"] is empty or tFields["kind"] is empty) then
      nxSetError "nxEntityDecode: naddr needs an author and a kind"
      return empty
   end if
   return tFields
end nxEntityDecode

function nxUriEncode pEntity
   -- A NIP-21 nostr: URI for a shareable entity (never nsec, by refusal:
   -- putting a secret key in a URI is how secret keys end up in chat logs).
   local tFields
   put nxEntityDecode(pEntity) into tFields
   if tFields is empty then
      return empty
   end if
   if nxStrEqExact(tFields["type"], "nsec") then
      nxSetError "nxUriEncode: refusing to build a URI around a secret key"
      return empty
   end if
   if char 1 to 6 of pEntity is "nostr:" then
      -- Idempotent: the decoder above accepts a prefixed input, so without
      -- this an existing URI would come back double-prefixed.
      return pEntity
   end if
   return "nostr:" & pEntity
end nxUriEncode

function nxUriDecode pUri
   -- The entity fields of a nostr: URI (nxEntityDecode already accepts the
   -- prefix; this spelling exists so intent reads at the call site).
   local tFields
   if char 1 to 6 of pUri is not "nostr:" then
      nxSetError "nxUriDecode: not a nostr: URI"
      return empty
   end if
   put nxEntityDecode(pUri) into tFields
   if tFields is empty then
      return empty
   end if
   if nxStrEqExact(tFields["type"], "nsec") then
      -- NIP-21 defines the scheme for the SHAREABLE entities; a secret key
      -- arriving through a clicked link must refuse, the same hygiene
      -- nxUriEncode enforces outbound.
      nxSetError "nxUriDecode: refusing a URI that carries a secret key"
      return empty
   end if
   return tFields
end nxUriDecode

-- ==========================================================================
-- NIP-44 v2 encrypted payloads. Every step here is vector-pinned
-- (tools/nostr-kat.py sweeps the full official set), INCLUDING the cipher
-- since 2026-08-23: family law said the missing primitive was an UPSTREAM
-- feature request, never a hand-rolled cipher here, and that request
-- shipped as SodiumXT ABI 10's sxChaCha20IetfXor (docs/07). On an installed
-- SodiumXT older than ABI 10, nxNip44Encrypt/Decrypt still fail closed with
-- a clear capability error; the key schedule, padding and MAC work either
-- way. The complete path is engine-unproven (needs an OXT pass).
-- ==========================================================================

function nxNip44ConversationKey pSeckeyHex, pPubkeyHex
   -- HKDF-extract(salt "nip44-v2", ECDH shared x) as 64 hex. The peer's
   -- x-only key lifts even-y: prefix byte 0x02 onto it for cxEcdh, which
   -- wants a full compressed point. cxEcdh returns the RAW 65-byte
   -- 0x04||X||Y point; the shared x is bytes 2..33 (unhashed, as NIP-44
   -- specifies - some libraries sha256 it, which would be wrong here).
   local tError, tShared, tSharedX, tConv
   if not nxIsHex(pSeckeyHex, 64) or not nxIsHex(pPubkeyHex, 64) then
      nxSetError "nxNip44ConversationKey: keys must be 64 hex characters"
      return empty
   end if
   try
      put cxEcdh(nxHexDecode(pSeckeyHex), numToByte(2) & nxHexDecode(pPubkeyHex)) into tShared
   catch tError
      nxSetError "nxNip44ConversationKey needs CoinXT cxEcdh:" && tError
      return empty
   end try
   if the number of bytes of tShared is not 65 then
      nxSetError "nxNip44ConversationKey: cxEcdh returned an unexpected length"
      return empty
   end if
   put byte 2 to 33 of tShared into tSharedX
   try
      put cxHmacSha256(textEncode(kNxNip44Salt, "UTF-8"), tSharedX) into tConv
   catch tError
      nxSetError "nxNip44ConversationKey needs CoinXT cxHmacSha256:" && tError
      return empty
   end try
   return nxHexEncode(tConv)
end nxNip44ConversationKey

function nxNip44MessageKeys pConvKeyHex, pNonceHex
   -- HKDF-expand(PRK conversation key, info nonce, L 76) sliced into the
   -- three message keys; returned as an array with keys "chachaKey" (32B),
   -- "chachaNonce" (12B) and "hmacKey" (32B), all hex.
   local tError, tConv, tNonce, tBlockOne, tBlockTwo, tBlockThree, tOkm, tOut
   if not nxIsHex(pConvKeyHex, 64) or not nxIsHex(pNonceHex, 64) then
      nxSetError "nxNip44MessageKeys: the conversation key and nonce must be 64 hex characters"
      return empty
   end if
   put nxHexDecode(pConvKeyHex) into tConv
   put nxHexDecode(pNonceHex) into tNonce
   try
      put cxHmacSha256(tConv, tNonce & numToByte(1)) into tBlockOne
      put cxHmacSha256(tConv, tBlockOne & tNonce & numToByte(2)) into tBlockTwo
      put cxHmacSha256(tConv, tBlockTwo & tNonce & numToByte(3)) into tBlockThree
   catch tError
      nxSetError "nxNip44MessageKeys needs CoinXT cxHmacSha256:" && tError
      return empty
   end try
   put tBlockOne & tBlockTwo & tBlockThree into tOkm
   put nxHexEncode(byte 1 to 32 of tOkm) into tOut["chachaKey"]
   put nxHexEncode(byte 33 to 44 of tOkm) into tOut["chachaNonce"]
   put nxHexEncode(byte 45 to 76 of tOkm) into tOut["hmacKey"]
   return tOut
end nxNip44MessageKeys

function nxNip44PaddedLen pLen
   -- The padded length of a pLen-byte plaintext (the vectors' 24 pairs pin
   -- this). Pure arithmetic; the 1..65535 REFUSAL lives in the pad step.
   local tPower, tChunk
   if pLen is not an integer or pLen < 1 then
      nxSetError "nxNip44PaddedLen: the length must be a positive integer"
      return empty
   end if
   if pLen <= 32 then
      return 32
   end if
   put 1 into tPower
   repeat while tPower < pLen
      multiply tPower by 2
   end repeat
   if tPower <= 256 then
      put 32 into tChunk
   else
      put nxIntDiv(tPower, 8) into tChunk
   end if
   return tChunk * (nxIntDiv(pLen - 1, tChunk) + 1)
end nxNip44PaddedLen

private function nxNip44Pad pPlaintext
   -- [len u16 BE][utf8 plaintext][zeros]; plaintext 1..65535 bytes (the
   -- published vectors pin the u16 prefix only; longer refuses, fail
   -- closed - see the header).
   local tBytes, tLen, tOut, tI, tPadTo
   put textEncode(pPlaintext, "UTF-8") into tBytes
   put the number of bytes of tBytes into tLen
   if tLen < 1 or tLen > kNxNip44MaxPlain then
      nxSetError "nxNip44: the plaintext must be 1 to" && kNxNip44MaxPlain && "bytes"
      return empty
   end if
   put numToByte(nxIntDiv(tLen, 256)) & numToByte(nxIntMod(tLen, 256)) into tOut
   put tBytes after tOut
   put nxNip44PaddedLen(tLen) into tPadTo
   repeat with tI = tLen + 1 to tPadTo
      put numToByte(0) after tOut
   end repeat
   return tOut
end nxNip44Pad

private function nxNip44Unpad pPadded
   -- Inverse of nxNip44Pad, strict: the declared length, the slice and the
   -- computed padded length must all agree or the payload refuses.
   local tLen, tBytes, tTotal
   put the number of bytes of pPadded into tTotal
   if tTotal < 3 then
      nxSetError "nxNip44: padded data too short"
      return empty
   end if
   put byteToNum(byte 1 of pPadded) * 256 + byteToNum(byte 2 of pPadded) into tLen
   if tLen < 1 or tLen > kNxNip44MaxPlain then
      nxSetError "nxNip44: invalid padding (declared length out of range)"
      return empty
   end if
   if 2 + tLen > tTotal then
      nxSetError "nxNip44: invalid padding (declared length exceeds the data)"
      return empty
   end if
   if tTotal is not 2 + nxNip44PaddedLen(tLen) then
      nxSetError "nxNip44: invalid padding (padded length mismatch)"
      return empty
   end if
   put byte 3 to (2 + tLen) of pPadded into tBytes
   -- UTF-8 validity by ROUND TRIP: textDecode is lossy and never throws
   -- (the riptide rsBytesAreUtf8 lesson), so decode, re-encode, and
   -- require byte equality - a key-holding peer sending non-UTF-8 padded
   -- bytes gets a refusal, as every conforming implementation gives.
   local tText
   put textDecode(tBytes, "UTF-8") into tText
   if textEncode(tText, "UTF-8") is not tBytes then
      nxSetError "nxNip44: the plaintext is not valid UTF-8"
      return empty
   end if
   return tText
end nxNip44Unpad

private function nxChaCha20 pKeyData, pNonceData, pData
   -- THE CIPHER SEAM (docs/07): composes SodiumXT's sxChaCha20IetfXor
   -- (RFC 8439 ChaCha20, 12-byte nonce, counter 0; shipped upstream in
   -- SodiumXT ABI 10, 2026-08-23). On an installed SodiumXT older than that
   -- the call raises and this returns empty with the capability error
   -- recorded - the fail-closed branch is the old-install path, not dead
   -- code. Family law forbids hand-rolling the cipher here (rule 1).
   local tError, tOut
   try
      put sxChaCha20IetfXor(pKeyData, pNonceData, pData) into tOut
   catch tError
      nxSetError "nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT ABI 10; the installed SodiumXT predates it - docs/07-capabilities-required.md)"
      return empty
   end try
   if the number of bytes of tOut is not the number of bytes of pData then
      nxSetError "nxNip44: the cipher returned an unexpected length"
      return empty
   end if
   return tOut
end nxChaCha20

function nxNip44HasCipher
   -- A live probe of the cipher seam, so an upgraded SodiumXT is noticed
   -- without restarting (unlike the cached nxProbeCapabilities row).
   local tError, tOut
   try
      put sxChaCha20IetfXor(nxHexDecode("0000000000000000000000000000000000000000000000000000000000000000"), nxHexDecode("000000000000000000000000"), numToByte(0)) into tOut
   catch tError
      return false
   end try
   return the number of bytes of tOut is 1
end nxNip44HasCipher

function nxNip44Encrypt pSeckeyHex, pPubkeyHex, pPlaintext, pNonceHex
   -- The full NIP-44 v2 payload (standard base64), or empty with the reason.
   -- pNonceHex empty draws 32 fresh SodiumXT bytes; a 64-hex nonce makes the
   -- payload deterministic (KAT use ONLY - never reuse a nonce in anger).
   local tError, tConvHex, tNonce, tKeys, tPadded, tCipher, tMac
   put nxNip44ConversationKey(pSeckeyHex, pPubkeyHex) into tConvHex
   if tConvHex is empty then
      return empty
   end if
   if pNonceHex is empty then
      try
         put sxRandomBytes(32) into tNonce
      catch tError
         nxSetError "nxNip44Encrypt needs SodiumXT sxRandomBytes for the nonce"
         return empty
      end try
   else
      if not nxIsHex(pNonceHex, 64) then
         nxSetError "nxNip44Encrypt: the nonce must be empty or 64 hex characters"
         return empty
      end if
      put nxHexDecode(pNonceHex) into tNonce
   end if
   put nxNip44MessageKeys(tConvHex, nxHexEncode(tNonce)) into tKeys
   if tKeys is empty then
      return empty
   end if
   put nxNip44Pad(pPlaintext) into tPadded
   if tPadded is empty then
      return empty
   end if
   put nxChaCha20(nxHexDecode(tKeys["chachaKey"]), nxHexDecode(tKeys["chachaNonce"]), tPadded) into tCipher
   if tCipher is empty then
      return empty
   end if
   try
      put cxHmacSha256(nxHexDecode(tKeys["hmacKey"]), tNonce & tCipher) into tMac
   catch tError
      nxSetError "nxNip44Encrypt needs CoinXT cxHmacSha256:" && tError
      return empty
   end try
   return nxB64Encode(numToByte(2) & tNonce & tCipher & tMac)
end nxNip44Encrypt

function nxNip44Decrypt pSeckeyHex, pPubkeyHex, pPayload
   -- Decrypt and unpad, or empty with the reason. The MAC verifies BEFORE
   -- the cipher runs, over nonce||ciphertext, compared constant-time.
   local tError, tConvHex, tRaw, tTotal, tNonce, tCipher, tMac, tKeys, tExpected, tPadded
   if pPayload is empty then
      nxSetError "nxNip44Decrypt: empty payload"
      return empty
   end if
   if char 1 of pPayload is "#" then
      nxSetError "nxNip44Decrypt: unsupported encryption version (future-format flag)"
      return empty
   end if
   if the number of chars of pPayload < 132 then
      nxSetError "nxNip44Decrypt: payload shorter than the 132-character floor"
      return empty
   end if
   put nxB64Decode(pPayload) into tRaw
   if tRaw is empty then
      nxSetError "nxNip44Decrypt: not valid standard base64"
      return empty
   end if
   put the number of bytes of tRaw into tTotal
   if tTotal < 99 then
      nxSetError "nxNip44Decrypt: decoded payload shorter than the 99-byte floor"
      return empty
   end if
   if byteToNum(byte 1 of tRaw) is not 2 then
      nxSetError "nxNip44Decrypt: unsupported encryption version"
      return empty
   end if
   put byte 2 to 33 of tRaw into tNonce
   put byte 34 to (tTotal - 32) of tRaw into tCipher
   put byte (tTotal - 31) to tTotal of tRaw into tMac
   put nxNip44ConversationKey(pSeckeyHex, pPubkeyHex) into tConvHex
   if tConvHex is empty then
      return empty
   end if
   put nxNip44MessageKeys(tConvHex, nxHexEncode(tNonce)) into tKeys
   if tKeys is empty then
      return empty
   end if
   try
      put cxHmacSha256(nxHexDecode(tKeys["hmacKey"]), tNonce & tCipher) into tExpected
   catch tError
      nxSetError "nxNip44Decrypt needs CoinXT cxHmacSha256:" && tError
      return empty
   end try
   if not nxCtEqualHex(nxHexEncode(tExpected), nxHexEncode(tMac)) then
      nxSetError "nxNip44Decrypt: the MAC does not verify (wrong key or tampered payload)"
      return empty
   end if
   put nxChaCha20(nxHexDecode(tKeys["chachaKey"]), nxHexDecode(tKeys["chachaNonce"]), tCipher) into tPadded
   if tPadded is empty then
      return empty
   end if
   return nxNip44Unpad(tPadded)
end nxNip44Decrypt

-- ==========================================================================
-- NIP-01 filters and the client/relay wire messages.
-- ==========================================================================

private function nxHexListToJson pLines, pLabel
   -- A return-delimited list of 64-hex values as a JSON string array, or
   -- empty (reason recorded) when a line is not 64-hex.
   local tSeq, tI, tCount, tOut
   put nxLinesToSeq(pLines) into tSeq
   put nxSeqCount(tSeq) into tCount
   put "[" into tOut
   repeat with tI = 1 to tCount
      if not nxIsHex(tSeq[tI], 64) then
         nxSetError "nxFilterBuild:" && pLabel && "line" && tI && "is not 64 hex characters"
         return empty
      end if
      if tI > 1 then
         put "," after tOut
      end if
      put quote & tSeq[tI] & quote after tOut
   end repeat
   put "]" after tOut
   return tOut
end nxHexListToJson

function nxFilterBuild pFilter
   -- A NIP-01 filter object from an array: keys "ids" / "authors" (lines of
   -- 64-hex), "kinds" (comma list of integers), "since" / "until" / "limit"
   -- (integers), "search" (string), and any number of single-letter tag
   -- filters keyed "#e", "#p", ... (lines of values). Emits a fixed field
   -- order so output is deterministic.
   local tSavedItemDelim, tSavedLineDelim, tOut, tPiece, tFirst, tKeyList, tI, tJ, tCount, tKeyText, tSeq, tValCount, tKindText
   put "{" into tOut
   put true into tFirst
   if pFilter["ids"] is not empty then
      put nxHexListToJson(pFilter["ids"], "ids") into tPiece
      if tPiece is empty then
         return empty
      end if
      put quote & "ids" & quote & ":" & tPiece after tOut
      put false into tFirst
   end if
   if pFilter["authors"] is not empty then
      put nxHexListToJson(pFilter["authors"], "authors") into tPiece
      if tPiece is empty then
         return empty
      end if
      if not tFirst then
         put "," after tOut
      end if
      put quote & "authors" & quote & ":" & tPiece after tOut
      put false into tFirst
   end if
   if pFilter["kinds"] is not empty then
      put the itemDelimiter into tSavedItemDelim
      set the itemDelimiter to comma
      put "[" into tPiece
      put the number of items of pFilter["kinds"] into tCount
      repeat with tI = 1 to tCount
         put item tI of pFilter["kinds"] into tKindText
         if tKindText is not an integer or tKindText < 0 or tKindText > 65535 then
            set the itemDelimiter to tSavedItemDelim
            nxSetError "nxFilterBuild: kinds entry" && tI && "is not a kind number"
            return empty
         end if
         if tI > 1 then
            put "," after tPiece
         end if
         put tKindText + 0 after tPiece
      end repeat
      set the itemDelimiter to tSavedItemDelim
      put "]" after tPiece
      if not tFirst then
         put "," after tOut
      end if
      put quote & "kinds" & quote & ":" & tPiece after tOut
      put false into tFirst
   end if
   -- Tag filters, in sorted key order for determinism.
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of pFilter into tKeyList
   sort lines of tKeyList
   put the number of lines of tKeyList into tCount
   repeat with tI = 1 to tCount
      put line tI of tKeyList into tKeyText
      if char 1 of tKeyText is not "#" or the number of chars of tKeyText is not 2 then
         next repeat
      end if
      put nxLinesToSeq(pFilter[tKeyText]) into tSeq
      put nxSeqCount(tSeq) into tValCount
      if tValCount is 0 then
         next repeat
      end if
      put "[" into tPiece
      repeat with tJ = 1 to tValCount
         if tJ > 1 then
            put "," after tPiece
         end if
         put quote & nxJsonEscape(tSeq[tJ]) & quote after tPiece
      end repeat
      put "]" after tPiece
      if not tFirst then
         put "," after tOut
      end if
      put quote & tKeyText & quote & ":" & tPiece after tOut
      put false into tFirst
   end repeat
   set the lineDelimiter to tSavedLineDelim
   -- The scalar fields, spelled out (no delimited list to read, so no guard).
   if pFilter["since"] is not empty then
      if pFilter["since"] is not an integer or pFilter["since"] < 0 then
         nxSetError "nxFilterBuild: since must be a non-negative integer"
         return empty
      end if
      if not tFirst then
         put "," after tOut
      end if
      put quote & "since" & quote & ":" & (pFilter["since"] + 0) after tOut
      put false into tFirst
   end if
   if pFilter["until"] is not empty then
      if pFilter["until"] is not an integer or pFilter["until"] < 0 then
         nxSetError "nxFilterBuild: until must be a non-negative integer"
         return empty
      end if
      if not tFirst then
         put "," after tOut
      end if
      put quote & "until" & quote & ":" & (pFilter["until"] + 0) after tOut
      put false into tFirst
   end if
   if pFilter["limit"] is not empty then
      if pFilter["limit"] is not an integer or pFilter["limit"] < 0 then
         nxSetError "nxFilterBuild: limit must be a non-negative integer"
         return empty
      end if
      if not tFirst then
         put "," after tOut
      end if
      put quote & "limit" & quote & ":" & (pFilter["limit"] + 0) after tOut
      put false into tFirst
   end if
   if pFilter["search"] is not empty then
      if not tFirst then
         put "," after tOut
      end if
      put quote & "search" & quote & ":" & quote & nxJsonEscape(pFilter["search"]) & quote after tOut
      put false into tFirst
   end if
   put "}" after tOut
   return tOut
end nxFilterBuild

function nxFilterMatches pFilterJson, pEvent
   -- Client-side NIP-01 matching: every present condition must hold (AND);
   -- list conditions need one exact member match. False on any doubt.
   local tCount, tI, tListValue, tOk, tKeyText, tJ, tValCount, tSavedLineDelim, tEventValues, tLineNo, tLineCount
   if nxJsonType(pFilterJson, empty) is not "object" then
      nxSetError "nxFilterMatches: the filter is not a JSON object"
      return false
   end if
   if not nxEventHasValidShape(pEvent) then
      return false
   end if
   -- ids
   if nxJsonType(pFilterJson, "ids") is "array" then
      put nxJsonCount(pFilterJson, "ids") into tCount
      put false into tOk
      repeat with tI = 1 to tCount
         put nxJsonGet(pFilterJson, "ids/" & tI) into tListValue
         if nxStrEqExact(tListValue, pEvent["id"]) then
            put true into tOk
            exit repeat
         end if
      end repeat
      if not tOk then
         return false
      end if
   end if
   -- authors
   if nxJsonType(pFilterJson, "authors") is "array" then
      put nxJsonCount(pFilterJson, "authors") into tCount
      put false into tOk
      repeat with tI = 1 to tCount
         put nxJsonGet(pFilterJson, "authors/" & tI) into tListValue
         if nxStrEqExact(tListValue, pEvent["pubkey"]) then
            put true into tOk
            exit repeat
         end if
      end repeat
      if not tOk then
         return false
      end if
   end if
   -- kinds
   if nxJsonType(pFilterJson, "kinds") is "array" then
      put nxJsonCount(pFilterJson, "kinds") into tCount
      put false into tOk
      repeat with tI = 1 to tCount
         put nxJsonGet(pFilterJson, "kinds/" & tI) into tListValue
         if tListValue is an integer and tListValue + 0 is pEvent["kind"] + 0 then
            put true into tOk
            exit repeat
         end if
      end repeat
      if not tOk then
         return false
      end if
   end if
   -- since / until
   if nxJsonType(pFilterJson, "since") is "number" then
      if pEvent["created_at"] + 0 < nxJsonGet(pFilterJson, "since") + 0 then
         return false
      end if
   end if
   if nxJsonType(pFilterJson, "until") is "number" then
      if pEvent["created_at"] + 0 > nxJsonGet(pFilterJson, "until") + 0 then
         return false
      end if
   end if
   -- tag filters: every "#x" key needs an intersection with the event's x
   -- tag values.
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   -- Type each candidate single-letter tag key directly (a-z then A-Z).
   repeat with tI = 1 to 52
      if tI <= 26 then
         put "#" & numToChar(96 + tI) into tKeyText
      else
         put "#" & numToChar(64 + tI - 26) into tKeyText
      end if
      if nxJsonType(pFilterJson, tKeyText) is not "array" then
         next repeat
      end if
      put nxTagValues(pEvent, char 2 of tKeyText) into tEventValues
      put nxJsonCount(pFilterJson, tKeyText) into tValCount
      put false into tOk
      repeat with tJ = 1 to tValCount
         put nxJsonGet(pFilterJson, tKeyText & "/" & tJ) into tListValue
         put the number of lines of tEventValues into tLineCount
         repeat with tLineNo = 1 to tLineCount
            if nxStrEqExact(line tLineNo of tEventValues, tListValue) then
               put true into tOk
               exit repeat
            end if
         end repeat
         if tOk then
            exit repeat
         end if
      end repeat
      if not tOk then
         set the lineDelimiter to tSavedLineDelim
         return false
      end if
   end repeat
   set the lineDelimiter to tSavedLineDelim
   return true
end nxFilterMatches

function nxClientReq pSubId, pFiltersJson
   -- ["REQ", subid, filter, ...]: pFiltersJson is one filter object per
   -- line (nxFilterBuild emits single-line objects). At least one filter.
   local tSeq, tI, tCount, tOut
   if pSubId is empty or the number of chars of pSubId > kNxSubIdMax then
      nxSetError "nxClientReq: the subscription id must be 1 to" && kNxSubIdMax && "characters"
      return empty
   end if
   put nxLinesToSeq(pFiltersJson) into tSeq
   put nxSeqCount(tSeq) into tCount
   if tCount is 0 then
      nxSetError "nxClientReq: at least one filter is required"
      return empty
   end if
   put "[" & quote & "REQ" & quote & "," & quote & nxJsonEscape(pSubId) & quote into tOut
   repeat with tI = 1 to tCount
      if nxJsonType(tSeq[tI], empty) is not "object" then
         nxSetError "nxClientReq: filter" && tI && "is not a JSON object"
         return empty
      end if
      put "," & tSeq[tI] after tOut
   end repeat
   put "]" after tOut
   return tOut
end nxClientReq

function nxClientClose pSubId
   if pSubId is empty or the number of chars of pSubId > kNxSubIdMax then
      nxSetError "nxClientClose: the subscription id must be 1 to" && kNxSubIdMax && "characters"
      return empty
   end if
   return "[" & quote & "CLOSE" & quote & "," & quote & nxJsonEscape(pSubId) & quote & "]"
end nxClientClose

function nxClientEvent pEvent
   -- ["EVENT", {...}]: the event must be COMPLETE (id and sig filled in).
   local tJson
   if not nxIsHex(pEvent["id"], 64) or not nxIsHex(pEvent["sig"], 128) then
      nxSetError "nxClientEvent: the event is not signed yet (nxEventSign first)"
      return empty
   end if
   put nxEventToJson(pEvent) into tJson
   if tJson is empty then
      return empty
   end if
   return "[" & quote & "EVENT" & quote & "," & tJson & "]"
end nxClientEvent

function nxClientAuth pEvent
   -- ["AUTH", {...}]: a SIGNED kind-22242 event (nxAuthBuild + nxEventSign).
   local tJson
   if pEvent["kind"] is not 22242 then
      nxSetError "nxClientAuth: not a kind 22242 authentication event"
      return empty
   end if
   if not nxIsHex(pEvent["id"], 64) or not nxIsHex(pEvent["sig"], 128) then
      nxSetError "nxClientAuth: the auth event is not signed yet"
      return empty
   end if
   put nxEventToJson(pEvent) into tJson
   if tJson is empty then
      return empty
   end if
   return "[" & quote & "AUTH" & quote & "," & tJson & "]"
end nxClientAuth

function nxRelayParse pWire
   -- One relay-to-client message -> an array keyed by "type" plus fields:
   --   "EVENT"  subId, eventJson (the VERBATIM object slice - parse it with
   --            nxEventFromJson and verify with nxEventVerify before trust)
   --   "OK"     eventId, accepted ("true"/"false"), reason
   --   "EOSE"   subId
   --   "CLOSED" subId, reason
   --   "NOTICE" notice
   --   "AUTH"   challenge
   -- Anything else parses to type "unknown" with "raw" carrying the text.
   -- Message types compare byte-exact: a relay saying "event" is NOT
   -- speaking NIP-01 and is not treated as if it were.
   local tRoot, tOut, tTypeText, tN, tNode
   put nxJsonParseText(pWire) into tRoot
   if sNxJsonErr is not empty then
      nxSetError "nxRelayParse:" && sNxJsonErr
      return empty
   end if
   if tRoot["t"] is not "a" then
      nxSetError "nxRelayParse: a relay message must be a JSON array"
      return empty
   end if
   put nxSeqCount(tRoot["c"]) into tN
   if tN < 1 or tRoot["c"][1]["t"] is not "s" then
      nxSetError "nxRelayParse: the first element must be the message type string"
      return empty
   end if
   put tRoot["c"][1]["v"] into tTypeText
   if nxStrEqExact(tTypeText, "EVENT") then
      if tN < 3 or tRoot["c"][2]["t"] is not "s" or tRoot["c"][3]["t"] is not "o" then
         nxSetError "nxRelayParse: EVENT needs a subscription id and an event object"
         return empty
      end if
      put "EVENT" into tOut["type"]
      put tRoot["c"][2]["v"] into tOut["subId"]
      -- Slice the event object VERBATIM before anything re-parses (the
      -- parser scratch is module state).
      put tRoot["c"][3] into tNode
      put textDecode(byte tNode["b1"] to tNode["b2"] of sNxJsonBytes, "UTF-8") into tOut["eventJson"]
      return tOut
   end if
   if nxStrEqExact(tTypeText, "OK") then
      if tN < 4 or tRoot["c"][2]["t"] is not "s" or tRoot["c"][3]["t"] is not "b" then
         nxSetError "nxRelayParse: OK needs an id, a boolean and a message"
         return empty
      end if
      put "OK" into tOut["type"]
      put tRoot["c"][2]["v"] into tOut["eventId"]
      put tRoot["c"][3]["v"] into tOut["accepted"]
      if tN >= 4 and tRoot["c"][4]["t"] is "s" then
         put tRoot["c"][4]["v"] into tOut["reason"]
      else
         put empty into tOut["reason"]
      end if
      return tOut
   end if
   if nxStrEqExact(tTypeText, "EOSE") then
      if tN < 2 or tRoot["c"][2]["t"] is not "s" then
         nxSetError "nxRelayParse: EOSE needs a subscription id"
         return empty
      end if
      put "EOSE" into tOut["type"]
      put tRoot["c"][2]["v"] into tOut["subId"]
      return tOut
   end if
   if nxStrEqExact(tTypeText, "CLOSED") then
      if tN < 2 or tRoot["c"][2]["t"] is not "s" then
         nxSetError "nxRelayParse: CLOSED needs a subscription id"
         return empty
      end if
      put "CLOSED" into tOut["type"]
      put tRoot["c"][2]["v"] into tOut["subId"]
      if tN >= 3 and tRoot["c"][3]["t"] is "s" then
         put tRoot["c"][3]["v"] into tOut["reason"]
      else
         put empty into tOut["reason"]
      end if
      return tOut
   end if
   if nxStrEqExact(tTypeText, "NOTICE") then
      put "NOTICE" into tOut["type"]
      if tN >= 2 and tRoot["c"][2]["t"] is "s" then
         put tRoot["c"][2]["v"] into tOut["notice"]
      else
         put empty into tOut["notice"]
      end if
      return tOut
   end if
   if nxStrEqExact(tTypeText, "AUTH") then
      if tN < 2 or tRoot["c"][2]["t"] is not "s" then
         nxSetError "nxRelayParse: AUTH needs a challenge string"
         return empty
      end if
      put "AUTH" into tOut["type"]
      put tRoot["c"][2]["v"] into tOut["challenge"]
      return tOut
   end if
   put "unknown" into tOut["type"]
   put pWire into tOut["raw"]
   return tOut
end nxRelayParse

-- ==========================================================================
-- RFC 6455, the pure half: url parsing, the handshake request and accept
-- derivation, and frame encode/decode. The stateful socket machine lives in
-- src/nostr-relay.livecodescript and composes these.
-- ==========================================================================

function nxWsUrlParse pUrl
   -- ws:// or wss:// -> an array with keys "scheme", "secure", "host",
   -- "port", "path". IPv6 bracket literals refuse (documented limit); a
   -- missing port defaults to 80 / 443.
   local tOut, tRest, tSlashPos, tHostPort, tColonPos, tI, tCount, tPortText
   if pUrl contains " " or pUrl contains tab or pUrl contains numToChar(10) or pUrl contains numToChar(13) then
      nxSetError "nxWsUrlParse: the url contains whitespace"
      return empty
   end if
   if char 1 to 5 of pUrl is "ws://" then
      put "ws" into tOut["scheme"]
      put false into tOut["secure"]
      put 80 into tOut["port"]
      put char 6 to (the number of chars of pUrl) of pUrl into tRest
   else if char 1 to 6 of pUrl is "wss://" then
      put "wss" into tOut["scheme"]
      put true into tOut["secure"]
      put 443 into tOut["port"]
      put char 7 to (the number of chars of pUrl) of pUrl into tRest
   else
      nxSetError "nxWsUrlParse: the url must start ws:// or wss://"
      return empty
   end if
   if tRest is empty then
      nxSetError "nxWsUrlParse: no host"
      return empty
   end if
   if tRest contains "[" then
      nxSetError "nxWsUrlParse: IPv6 bracket literals are not supported"
      return empty
   end if
   put 0 into tSlashPos
   put the number of chars of tRest into tCount
   repeat with tI = 1 to tCount
      if byteToNum(char tI of tRest) is 47 then
         put tI into tSlashPos
         exit repeat
      end if
   end repeat
   if tSlashPos is 0 then
      put tRest into tHostPort
      put "/" into tOut["path"]
   else
      put char 1 to (tSlashPos - 1) of tRest into tHostPort
      put char tSlashPos to tCount of tRest into tOut["path"]
   end if
   put 0 into tColonPos
   put the number of chars of tHostPort into tCount
   repeat with tI = tCount down to 1
      if byteToNum(char tI of tHostPort) is 58 then
         put tI into tColonPos
         exit repeat
      end if
   end repeat
   if tColonPos is 0 then
      put tHostPort into tOut["host"]
   else
      put char 1 to (tColonPos - 1) of tHostPort into tOut["host"]
      put char (tColonPos + 1) to tCount of tHostPort into tPortText
      if not nxIsDigits(tPortText) or tPortText + 0 < 1 or tPortText + 0 > 65535 then
         nxSetError "nxWsUrlParse: the port must be 1 to 65535"
         return empty
      end if
      put tPortText + 0 into tOut["port"]
   end if
   if tOut["host"] is empty then
      nxSetError "nxWsUrlParse: no host"
      return empty
   end if
   return tOut
end nxWsUrlParse

function nxWsHandshakeRequest pHost, pPort, pPath, pKeyB64, pSecure
   -- The client upgrade request, CRLF line endings, blank line terminated.
   -- The Host header omits the port only at the SCHEME'S default (80 for
   -- ws, 443 for wss - RFC 6455 section 4.1 defines them per scheme, so a
   -- cross-scheme port like ws://host:443 must stay in the header or a
   -- name-routing proxy serves the wrong vhost). pSecure true means wss.
   local tOut, tCrlf, tHostHeader, tDefaultPort
   if pHost is empty or pPath is empty or pKeyB64 is empty then
      nxSetError "nxWsHandshakeRequest: host, path and key are all required"
      return empty
   end if
   put numToChar(13) & numToChar(10) into tCrlf
   if pSecure is true then
      put 443 into tDefaultPort
   else
      put 80 into tDefaultPort
   end if
   put pHost into tHostHeader
   if pPort is not empty and pPort is not tDefaultPort then
      put ":" & pPort after tHostHeader
   end if
   put "GET " & pPath & " HTTP/1.1" & tCrlf into tOut
   put "Host: " & tHostHeader & tCrlf after tOut
   put "Upgrade: websocket" & tCrlf after tOut
   put "Connection: Upgrade" & tCrlf after tOut
   put "Sec-WebSocket-Key: " & pKeyB64 & tCrlf after tOut
   put "Sec-WebSocket-Version: " & kNxWsVersion & tCrlf after tOut
   put tCrlf after tOut
   return tOut
end nxWsHandshakeRequest

function nxWsAcceptFor pKeyB64
   -- The Sec-WebSocket-Accept a compliant server must answer with:
   -- base64(SHA-1(key || GUID)). sha1Digest is the engine's own digest
   -- (the one engine-proven builtin hash in this tree; riptide relies on it).
   return nxB64Encode(sha1Digest(pKeyB64 & kNxWsGuid))
end nxWsAcceptFor

private function nxByteXor pA, pB
   -- One-byte xor by arithmetic (see nxBitXor31's rationale).
   local tResult, tBit, tI, tDigitA, tDigitB
   put 0 into tResult
   put 1 into tBit
   repeat with tI = 1 to 8
      put nxIntMod(nxIntDiv(pA, tBit), 2) into tDigitA
      put nxIntMod(nxIntDiv(pB, tBit), 2) into tDigitB
      if tDigitA is not tDigitB then
         add tBit to tResult
      end if
      multiply tBit by 2
   end repeat
   return tResult
end nxByteXor

private function nxWsMask pPayload, pMaskData
   -- XOR pPayload with the repeating 4-byte mask (its own inverse).
   local tOut, tI, tN, tMaskByte
   put empty into tOut
   put the number of bytes of pPayload into tN
   repeat with tI = 1 to tN
      put byteToNum(byte (nxIntMod(tI - 1, 4) + 1) of pMaskData) into tMaskByte
      put numToByte(nxByteXor(byteToNum(byte tI of pPayload), tMaskByte)) after tOut
   end repeat
   return tOut
end nxWsMask

function nxWsFrameEncode pOpcode, pPayload, pMaskHex
   -- A single client frame: FIN set, MASKED (RFC 6455 requires a client to
   -- mask every frame), no fragmentation. pMaskHex is exactly 8 hex chars
   -- (the relay layer draws it fresh per frame; a fixed mask is for KATs).
   local tMask, tOut, tLen
   if pOpcode is not an integer or pOpcode < 0 or pOpcode > 15 then
      nxSetError "nxWsFrameEncode: the opcode must be 0 to 15"
      return empty
   end if
   if not nxIsHex(pMaskHex, 8) then
      nxSetError "nxWsFrameEncode: the mask must be 8 hex characters"
      return empty
   end if
   put the number of bytes of pPayload into tLen
   if tLen > kNxWsMaxFrame then
      nxSetError "nxWsFrameEncode: the payload exceeds the" && kNxWsMaxFrame & "-byte frame cap"
      return empty
   end if
   if pOpcode >= 8 and tLen > 125 then
      nxSetError "nxWsFrameEncode: a control frame's payload must be 125 bytes or fewer"
      return empty
   end if
   put nxHexDecode(pMaskHex) into tMask
   put numToByte(128 + pOpcode) into tOut
   if tLen < 126 then
      put numToByte(128 + tLen) after tOut
   else if tLen <= 65535 then
      put numToByte(128 + 126) after tOut
      put numToByte(nxIntDiv(tLen, 256)) after tOut
      put numToByte(nxIntMod(tLen, 256)) after tOut
   else
      put numToByte(128 + 127) after tOut
      put numToByte(0) & numToByte(0) & numToByte(0) & numToByte(0) after tOut
      put numToByte(nxIntMod(nxIntDiv(tLen, 16777216), 256)) after tOut
      put numToByte(nxIntMod(nxIntDiv(tLen, 65536), 256)) after tOut
      put numToByte(nxIntMod(nxIntDiv(tLen, 256), 256)) after tOut
      put numToByte(nxIntMod(tLen, 256)) after tOut
   end if
   put tMask after tOut
   put nxWsMask(pPayload, tMask) after tOut
   return tOut
end nxWsFrameEncode

function nxWsFrameDecode pBuffer
   -- Parse ONE frame at the head of pBuffer. Returns an array:
   --   "complete" true/false; when false, "needMore" says how many bytes
   --   are known to be missing (0 = unknown, read more), and nothing else
   --   is meaningful.
   --   when true: "fin", "opcode", "masked", "payload" (unmasked Data) and
   --   "consumed" (bytes to drop from the buffer).
   --   "error" non-empty means the stream is unrecoverable: fail closed and
   --   close the socket (hostile length, reserved bits, oversized control).
   local tOut, tTotal, tByteOne, tByteTwo, tOpcode, tFin, tMasked, tLen, tPos, tHigh, tLow, tMask, tRsv
   put false into tOut["complete"]
   put 0 into tOut["needMore"]
   put empty into tOut["error"]
   put the number of bytes of pBuffer into tTotal
   if tTotal < 2 then
      return tOut
   end if
   put byteToNum(byte 1 of pBuffer) into tByteOne
   put byteToNum(byte 2 of pBuffer) into tByteTwo
   put (tByteOne >= 128) into tFin
   put nxIntMod(nxIntDiv(tByteOne, 16), 8) into tRsv
   if tRsv is not 0 then
      put "reserved bits set (no extension was negotiated)" into tOut["error"]
      return tOut
   end if
   put nxIntMod(tByteOne, 16) into tOpcode
   put (tByteTwo >= 128) into tMasked
   put nxIntMod(tByteTwo, 128) into tLen
   put 3 into tPos
   if tLen is 126 then
      if tTotal < 4 then
         return tOut
      end if
      put byteToNum(byte 3 of pBuffer) * 256 + byteToNum(byte 4 of pBuffer) into tLen
      put 5 into tPos
   else if tLen is 127 then
      if tTotal < 10 then
         return tOut
      end if
      put byteToNum(byte 3 of pBuffer) * 16777216 + byteToNum(byte 4 of pBuffer) * 65536 + byteToNum(byte 5 of pBuffer) * 256 + byteToNum(byte 6 of pBuffer) into tHigh
      put byteToNum(byte 7 of pBuffer) * 16777216 + byteToNum(byte 8 of pBuffer) * 65536 + byteToNum(byte 9 of pBuffer) * 256 + byteToNum(byte 10 of pBuffer) into tLow
      if tHigh is not 0 or tLow > kNxWsMaxFrame then
         put "frame length exceeds the" && kNxWsMaxFrame & "-byte cap" into tOut["error"]
         return tOut
      end if
      put tLow into tLen
      put 11 into tPos
   end if
   if tLen > kNxWsMaxFrame then
      put "frame length exceeds the" && kNxWsMaxFrame & "-byte cap" into tOut["error"]
      return tOut
   end if
   if tOpcode >= 8 then
      if tLen > 125 then
         put "control frame longer than 125 bytes" into tOut["error"]
         return tOut
      end if
      if tFin is not true then
         put "fragmented control frame" into tOut["error"]
         return tOut
      end if
   end if
   if tMasked then
      if tTotal < tPos + 3 then
         return tOut
      end if
      put byte tPos to (tPos + 3) of pBuffer into tMask
      add 4 to tPos
   end if
   if tTotal < tPos + tLen - 1 then
      put (tPos + tLen - 1) - tTotal into tOut["needMore"]
      return tOut
   end if
   if tLen is 0 then
      put empty into tOut["payload"]
   else
      put byte tPos to (tPos + tLen - 1) of pBuffer into tOut["payload"]
   end if
   if tMasked then
      put nxWsMask(tOut["payload"], tMask) into tOut["payload"]
   end if
   put true into tOut["complete"]
   put tFin into tOut["fin"]
   put tOpcode into tOut["opcode"]
   put tMasked into tOut["masked"]
   put tPos + tLen - 1 into tOut["consumed"]
   return tOut
end nxWsFrameDecode

-- ==========================================================================
-- NIP-13 proof of work, NIP-05 identifiers, NIP-11 relay information.
-- ==========================================================================

function nxPowDifficulty pIdHex
   -- Leading zero BITS of an event id (NIP-13's definition). Counts by hex
   -- digit; remember digits 1..7 still contribute leading zero bits.
   local tBits, tI, tDigit
   if not nxIsHex(pIdHex, 64) then
      nxSetError "nxPowDifficulty: not a 64-hex event id"
      return empty
   end if
   put 0 into tBits
   repeat with tI = 1 to 64
      put nxHexNibble(char tI of pIdHex) into tDigit
      if tDigit is 0 then
         add 4 to tBits
         next repeat
      end if
      if tDigit is 1 then
         add 3 to tBits
      else if tDigit <= 3 then
         add 2 to tBits
      else if tDigit <= 7 then
         add 1 to tBits
      end if
      exit repeat
   end repeat
   return tBits
end nxPowDifficulty

function nxPowCheck pEvent, pMinBits
   -- True when the event's id meets pMinBits AND any committed target (the
   -- third entry of its nonce tag) is itself at least pMinBits - NIP-13
   -- says a lucky low-target mine must be rejected against a higher bar.
   local tBits, tI, tTagCount, tTarget
   if pMinBits is not an integer or pMinBits < 0 or pMinBits > 256 then
      nxSetError "nxPowCheck: pMinBits must be an integer between 0 and 256"
      return false
   end if
   put nxPowDifficulty(pEvent["id"]) into tBits
   if tBits is empty then
      return false
   end if
   if tBits < pMinBits then
      nxSetError "nxPowCheck: difficulty" && tBits && "is below" && pMinBits
      return false
   end if
   put nxSeqCount(pEvent["tags"]) into tTagCount
   repeat with tI = 1 to tTagCount
      if nxStrEqExact(pEvent["tags"][tI][1], "nonce") and 3 is among the keys of pEvent["tags"][tI] then
         put pEvent["tags"][tI][3] into tTarget
         if not nxIsDigits(tTarget) or tTarget + 0 < pMinBits then
            nxSetError "nxPowCheck: the committed target" && tTarget && "is below" && pMinBits
            return false
         end if
      end if
   end repeat
   return true
end nxPowCheck

function nxNip05Url pIdentifier
   -- The .well-known url for a NIP-05 identifier ("name@domain", or a bare
   -- domain meaning "_@domain"). The FETCH is the app's (libURL or a proxy
   -- of its choosing); this file does no I/O.
   local tAtPos, tI, tCount, tLocalPart, tDomain
   if pIdentifier is empty then
      nxSetError "nxNip05Url: empty identifier"
      return empty
   end if
   put 0 into tAtPos
   put the number of chars of pIdentifier into tCount
   repeat with tI = tCount down to 1
      if byteToNum(char tI of pIdentifier) is 64 then
         put tI into tAtPos
         exit repeat
      end if
   end repeat
   if tAtPos is 0 then
      put "_" into tLocalPart
      put pIdentifier into tDomain
   else
      put char 1 to (tAtPos - 1) of pIdentifier into tLocalPart
      put char (tAtPos + 1) to tCount of pIdentifier into tDomain
   end if
   if tLocalPart is empty or tDomain is empty then
      nxSetError "nxNip05Url: malformed identifier"
      return empty
   end if
   if tDomain contains "/" or tDomain contains "?" or tDomain contains "#" or tDomain contains "@" then
      nxSetError "nxNip05Url: the domain contains a url delimiter"
      return empty
   end if
   return "https://" & tDomain & "/.well-known/nostr.json?name=" & tLocalPart
end nxNip05Url

function nxNip05Verify pJsonBody, pUserName, pPubkeyHex
   -- True when the fetched nostr.json maps pUserName to pPubkeyHex. A name
   -- containing "/" cannot be addressed through the path walk (documented
   -- limit; NIP-05 local parts are a-z0-9-_. anyway).
   local tFound
   if pUserName contains "/" then
      nxSetError "nxNip05Verify: names containing / are not supported"
      return false
   end if
   if not nxIsHex(pPubkeyHex, 64) then
      nxSetError "nxNip05Verify: the pubkey must be 64 hex characters"
      return false
   end if
   if nxJsonType(pJsonBody, "names/" & pUserName) is not "string" then
      nxSetError "nxNip05Verify: no such name in the document"
      return false
   end if
   put nxJsonGet(pJsonBody, "names/" & pUserName) into tFound
   return nxStrEqExact(nxToLowerAscii(tFound), nxToLowerAscii(pPubkeyHex))
end nxNip05Verify

function nxRelayInfoParse pJsonBody
   -- The common NIP-11 relay-information fields as an array; absent fields
   -- are empty; "supportedNips" is a comma list.
   local tOut, tField, tCount, tI, tSavedItemDelim
   if nxJsonType(pJsonBody, empty) is not "object" then
      nxSetError "nxRelayInfoParse: not a JSON object"
      return empty
   end if
   put the itemDelimiter into tSavedItemDelim
   set the itemDelimiter to comma
   repeat for each item tField in "name,description,pubkey,contact,software,version"
      if nxJsonType(pJsonBody, tField) is "string" then
         put nxJsonGet(pJsonBody, tField) into tOut[tField]
      else
         put empty into tOut[tField]
      end if
   end repeat
   set the itemDelimiter to tSavedItemDelim
   put empty into tOut["supportedNips"]
   if nxJsonType(pJsonBody, "supported_nips") is "array" then
      put nxJsonCount(pJsonBody, "supported_nips") into tCount
      repeat with tI = 1 to tCount
         if tOut["supportedNips"] is not empty then
            put "," after tOut["supportedNips"]
         end if
         put nxJsonGet(pJsonBody, "supported_nips/" & tI) after tOut["supportedNips"]
      end repeat
   end if
   return tOut
end nxRelayInfoParse

-- ---- nostrxt/src/nostr-relay.livecodescript ----
-- nostr-relay.livecodescript - the NostrXT relay client (public nxr*).
--
-- The stateful half of NostrXT: a websocket (RFC 6455) client over engine
-- sockets that speaks the NIP-01 relay protocol - REQ / CLOSE / EVENT out,
-- EVENT / OK / EOSE / CLOSED / NOTICE / AUTH in. It COMPOSES the pure-compute
-- core (src/nostrxt.livecodescript, nx*): url parsing, handshake and accept
-- derivation, frame encode/decode, message build/parse, event verification.
-- Load the core first; this file owns only sockets, buffers and handles.
--
-- THIS FILE IS DELIBERATELY NOT EMBEDDED IN THE SUITE PASTE: it defines the
-- engine's socketError / socketClosed / socketTimeout handlers, which the
-- embedded onionxt layer also defines, and the suite generator refuses (as
-- it must) an assembly that defines one handler twice. It ships in the demo
-- embed instead (the onion-httpd precedent), and its offline paths are
-- exercised by probe-guarded harness sections that SKIP in the paste.
--
-- STATUS, and it is SPLIT - read both halves before quoting either.
-- LIVE-PROVEN 2026-08-24 (Windows x86_64, OXT 9.6.3, wss://nos.lol): connect,
-- the websocket handshake, publish, and the relay's ok-true verdict arriving
-- back through the app callback. That run went over TLS, so it is also this
-- suite's FIRST exercised `open secure socket` - the wss:// path is no longer
-- the doubly-flagged unknown this banner used to describe, and
-- docs/OXT-ENGINE-NOTES.md 6.8 records exactly what the one run measured.
-- STILL UNPROVEN, and keeping "verified statically; needs a live-relay pass":
-- the whole RECEIVE leg - REQ/subscribe, the EVENT and EOSE callbacks,
-- CLOSED, NOTICE - and the NIP-42 auth exchange. So is every ws:// path: the
-- proven run was secure, and the plain form here still rests on onionxt's
-- engine-proven SOCKS idioms rather than on a run of its own.
--
-- Conventions (see CLAUDE.md): public API nxrPascalCase; commands report
-- through `the result` (empty on success, a "NostrXT relay: ..." string on
-- refusal; handle-yielding commands return the integer handle, so callers
-- test `the result is an integer`) - the onionxt shape for a stateful
-- layer. Async outcomes arrive through the app callback, never a blocking
-- return. Every wire error fails closed and tears the connection down;
-- every teardown is idempotent; the app frees what it opens (closeStack).
--
-- CALLBACK CONTRACT: nxrSetCallback registers <handler> per relay; it is
-- dispatched (try-guarded; a missing handler is a clean no-op) to the owner
-- set by nxrInit (default: the topStack) as:
--   <handler> pRelay, pKind, pArgOne, pArgTwo
--     pKind = "open"          handshake complete; the relay is usable
--     pKind = "event"         pArgOne = subscription id, pArgTwo = the raw
--                             event JSON. VERIFIED (id + signature) before
--                             delivery unless nxrSetVerify turned that off.
--     pKind = "invalid"       pArgOne = subscription id, pArgTwo = why the
--                             event was refused (failed verify, or CoinXT
--                             absent while verification is on - fail closed)
--     pKind = "eose"          pArgOne = subscription id
--     pKind = "ok"            pArgOne = event id, pArgTwo = "true" or
--                             "false", then a tab, then the relay's reason
--     pKind = "closed"        pArgOne = subscription id, pArgTwo = reason
--     pKind = "notice"        pArgOne = the notice text
--     pKind = "auth"          pArgOne = the NIP-42 challenge (also kept for
--                             nxrChallenge; answer with nxAuthBuild +
--                             nxEventSign + nxrAuth)
--     pKind = "error"         pArgOne = the failure; the relay is torn down
--     pKind = "disconnected"  pArgOne = the reason; the relay is gone

-- ==========================================================================
-- Constants.
-- ==========================================================================

constant kNxrHandshakeTimeout = 20000     -- milliseconds
-- The receive buffer cap: a peer that streams bytes without ever completing
-- a frame must hit a wall, not exhaust memory (fail closed).
constant kNxrMaxBuffer = 16777216

-- ==========================================================================
-- Script-local state. Handle tables keyed by integer handle and by engine
-- socket id; a stale id is a clean no-op (family rule 4's spirit).
-- ==========================================================================

local sNxrRelays             -- keyed by handle: socketID, state, url, host,
                             -- port, path, secure, wsKey, buffer, callback,
                             -- verify, challenge, fragOp, fragData, subs
local sNxrSockToRelay        -- socket id -> handle
local sNxrNextHandle         -- monotonic; 0 never valid
local sNxrOwner              -- long id the callbacks dispatch to

-- ==========================================================================
-- Wiring.
-- ==========================================================================

function nxrVersion
   return "NostrXT relay" && nxVersion()
end nxrVersion

command nxrInit pOwner
   -- Set the object whose script receives the callbacks (the demo passes
   -- `the long id of me` in preOpenStack). Idempotent.
   put pOwner into sNxrOwner
   return empty
end nxrInit

private function nxrCallbackTarget
   if sNxrOwner is not empty then
      return sNxrOwner
   end if
   return the topStack
end nxrCallbackTarget

private command nxrDispatch pRelay, pKind, pArgOne, pArgTwo
   -- Deliver one callback, try-guarded: a throwing app handler must not
   -- break the socket state machine, and a missing handler is a clean miss
   -- (the onionxt oxDispatch shape).
   local tError, tHandler
   put sNxrRelays[pRelay]["callback"] into tHandler
   if tHandler is empty then
      exit nxrDispatch
   end if
   try
      dispatch tHandler to nxrCallbackTarget() with pRelay, pKind, pArgOne, pArgTwo
   catch tError
      -- Swallowed on purpose: the app broke, the transport must not.
   end try
end nxrDispatch

private function nxrAllocHandle
   if sNxrNextHandle is empty then
      put 0 into sNxrNextHandle
   end if
   add 1 to sNxrNextHandle
   return sNxrNextHandle
end nxrAllocHandle

private function nxrRandomHex pByteCount
   -- Hex for pByteCount random bytes. Prefers SodiumXT; falls back to the
   -- engine's random(). ACCEPTABILITY: these bytes are websocket MASKS and
   -- handshake nonces - RFC 6455's masking defends proxy caches, not
   -- confidentiality - so a non-cryptographic fallback is honest here. Key
   -- material NEVER comes through this function (nxKeyGenerate refuses
   -- outright without SodiumXT).
   local tError, tData, tI
   try
      put sxRandomBytes(pByteCount) into tData
      if the number of bytes of tData is pByteCount then
         return nxHexEncode(tData)
      end if
   catch tError
      put empty into tData
   end try
   put empty into tData
   repeat with tI = 1 to pByteCount
      put numToByte(random(256) - 1) after tData
   end repeat
   return nxHexEncode(tData)
end nxrRandomHex

-- ==========================================================================
-- Connect and the handshake state machine.
-- ==========================================================================

command nxrConnect pUrl
   -- Returns an integer relay handle through `the result` immediately; the
   -- handshake completes asynchronously and the callback receives "open" or
   -- "error". States: connecting -> handshake -> open -> closing/gone.
   local tParsed, tHandle, tSocketID, tKeyHex
   put nxWsUrlParse(pUrl) into tParsed
   if tParsed is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   put nxrAllocHandle() into tHandle
   -- A named socket id so several relays at one host:port stay distinct
   -- (the onionxt |name discipline; store the engine's id verbatim).
   put tParsed["host"] & ":" & tParsed["port"] & "|nxr" & tHandle into tSocketID
   put tSocketID into sNxrRelays[tHandle]["socketID"]
   put "connecting" into sNxrRelays[tHandle]["state"]
   put pUrl into sNxrRelays[tHandle]["url"]
   put tParsed["host"] into sNxrRelays[tHandle]["host"]
   put tParsed["port"] into sNxrRelays[tHandle]["port"]
   put tParsed["path"] into sNxrRelays[tHandle]["path"]
   put tParsed["secure"] into sNxrRelays[tHandle]["secure"]
   put empty into sNxrRelays[tHandle]["buffer"]
   put empty into sNxrRelays[tHandle]["callback"]
   put true into sNxrRelays[tHandle]["verify"]
   put empty into sNxrRelays[tHandle]["challenge"]
   put empty into sNxrRelays[tHandle]["fragOp"]
   put empty into sNxrRelays[tHandle]["fragData"]
   -- The Sec-WebSocket-Key: 16 random bytes, base64.
   put nxrRandomHex(16) into tKeyHex
   put nxB64Encode(nxHexDecode(tKeyHex)) into sNxrRelays[tHandle]["wsKey"]
   put tHandle into sNxrSockToRelay[tSocketID]
   set the socketTimeoutInterval to kNxrHandshakeTimeout
   if tParsed["secure"] is true then
      -- ENGINE-ARMED 2026-08-24: this line is the suite's first and so far
      -- only exercised `open secure socket`, and it reached an ordinary
      -- public relay - so the form exists on OXT 9.6.3, connects, and carries
      -- the handshake and the framing below.
      -- VERIFY (on-engine), because "it connected" is not "it verifies": a
      -- REJECTED certificate was never tried, so whether an invalid one is
      -- refused or silently accepted is still unmeasured, as are the TLS
      -- versions offered and how a TLS failure is delivered (expected: a
      -- socketError message, as with the plain form). docs/07 gap #2 carries
      -- that remainder; engine notes 6.8 carries what the run did settle.
      open secure socket to tSocketID with message "nxrWsOpened"
   else
      open socket to tSocketID with message "nxrWsOpened"
   end if
   send ("nxrDeadline " & tHandle) to me in kNxrHandshakeTimeout milliseconds
   return tHandle
end nxrConnect

command nxrWsOpened pSocketID
   -- ENGINE-ARMED: TCP (or TLS) is up; send the upgrade request and start
   -- the one persistent read. A stale id is a clean no-op.
   local tHandle, tRequest
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is empty then
      exit nxrWsOpened
   end if
   put "handshake" into sNxrRelays[tHandle]["state"]
   put nxWsHandshakeRequest(sNxrRelays[tHandle]["host"], sNxrRelays[tHandle]["port"], sNxrRelays[tHandle]["path"], sNxrRelays[tHandle]["wsKey"], sNxrRelays[tHandle]["secure"]) into tRequest
   if tRequest is empty then
      nxrFail tHandle, "could not build the handshake request:" && nxLastError()
      exit nxrWsOpened
   end if
   write textEncode(tRequest, "UTF-8") to socket pSocketID
   read from socket pSocketID with message "nxrWsData"
end nxrWsOpened

command nxrWsData pSocketID, pData
   -- ENGINE-ARMED: the persistent read delivers whatever bytes arrived;
   -- append to the relay's buffer, run the state machine, and re-arm ONLY
   -- if the relay still exists (the callback may have torn it down - the
   -- onionxt oxStreamData discipline).
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is empty then
      exit nxrWsData
   end if
   put pData after sNxrRelays[tHandle]["buffer"]
   if the number of bytes of sNxrRelays[tHandle]["buffer"] > kNxrMaxBuffer then
      nxrFail tHandle, "receive buffer exceeded" && kNxrMaxBuffer && "bytes"
      exit nxrWsData
   end if
   nxrProcessBuffer tHandle
   if sNxrSockToRelay[pSocketID] is not empty then
      read from socket pSocketID with message "nxrWsData"
   end if
end nxrWsData

command nxrDeadline pRelay
   -- Self-sent watchdog: a handshake that has not reached "open" by the
   -- deadline fails closed (a bootstrapping or stalled peer accepts TCP and
   -- then hangs; rule: timeouts are mandatory).
   if sNxrRelays[pRelay]["socketID"] is empty then
      exit nxrDeadline
   end if
   if sNxrRelays[pRelay]["state"] is "connecting" or sNxrRelays[pRelay]["state"] is "handshake" then
      nxrFail pRelay, "the websocket handshake timed out"
   end if
end nxrDeadline

private command nxrProcessBuffer pRelay
   -- Drive whichever phase the connection is in. The handshake phase eats
   -- the HTTP response; anything after it falls through to the frame phase.
   if sNxrRelays[pRelay]["state"] is "handshake" then
      nxrProcessHandshake pRelay
   end if
   if sNxrRelays[pRelay]["state"] is "open" or sNxrRelays[pRelay]["state"] is "closing" then
      nxrProcessFrames pRelay
   end if
end nxrProcessBuffer

private function nxrHeaderEnd pBuffer
   -- The byte position just PAST the CRLFCRLF terminator, or 0.
   local tI, tN
   put the number of bytes of pBuffer into tN
   repeat with tI = 1 to tN - 3
      if byteToNum(byte tI of pBuffer) is 13 and byteToNum(byte (tI + 1) of pBuffer) is 10 and byteToNum(byte (tI + 2) of pBuffer) is 13 and byteToNum(byte (tI + 3) of pBuffer) is 10 then
         return tI + 4
      end if
   end repeat
   return 0
end nxrHeaderEnd

private command nxrProcessHandshake pRelay
   -- Validate the 101 upgrade response: status code and the accept echo.
   -- Fail closed on anything else - a relay that answers 200 is a web page,
   -- not a websocket.
   local tEnd, tHeaderText, tSavedLineDelim, tStatusLine, tAcceptValue, tLineCount, tI, tLineText, tColonPos, tHeaderName
   put nxrHeaderEnd(sNxrRelays[pRelay]["buffer"]) into tEnd
   if tEnd is 0 then
      exit nxrProcessHandshake        -- headers not complete yet
   end if
   put textDecode(byte 1 to (tEnd - 1) of sNxrRelays[pRelay]["buffer"], "UTF-8") into tHeaderText
   -- Consume the header bytes; whatever follows is already frame data.
   if tEnd > the number of bytes of sNxrRelays[pRelay]["buffer"] then
      put empty into sNxrRelays[pRelay]["buffer"]
   else
      put byte tEnd to (the number of bytes of sNxrRelays[pRelay]["buffer"]) of sNxrRelays[pRelay]["buffer"] into sNxrRelays[pRelay]["buffer"]
   end if
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to numToChar(13) & numToChar(10)
   put line 1 of tHeaderText into tStatusLine
   put empty into tAcceptValue
   put the number of lines of tHeaderText into tLineCount
   repeat with tI = 2 to tLineCount
      put line tI of tHeaderText into tLineText
      put offset(":", tLineText) into tColonPos
      if tColonPos < 2 then
         next repeat
      end if
      put char 1 to (tColonPos - 1) of tLineText into tHeaderName
      -- Header names are case-insensitive by HTTP's own rule, so the folded
      -- compare `is` gives here is the CORRECT one for once.
      if nxrToLowerAscii(tHeaderName) is "sec-websocket-accept" then
         put char (tColonPos + 1) to (the number of chars of tLineText) of tLineText into tAcceptValue
         repeat while char 1 of tAcceptValue is " "
            delete char 1 of tAcceptValue
         end repeat
         repeat while char (the number of chars of tAcceptValue) of tAcceptValue is " "
            delete char (the number of chars of tAcceptValue) of tAcceptValue
         end repeat
      end if
   end repeat
   set the lineDelimiter to tSavedLineDelim
   if not (tStatusLine contains " 101 ") then
      nxrFail pRelay, "the server did not upgrade (status line: " & tStatusLine & ")"
      exit nxrProcessHandshake
   end if
   if not nxrStrEq(tAcceptValue, nxWsAcceptFor(sNxrRelays[pRelay]["wsKey"])) then
      nxrFail pRelay, "Sec-WebSocket-Accept mismatch (not a compliant websocket server)"
      exit nxrProcessHandshake
   end if
   put "open" into sNxrRelays[pRelay]["state"]
   nxrDispatch pRelay, "open", empty, empty
end nxrProcessHandshake

private function nxrToLowerAscii pText
   -- ASCII lowercase by byte value. Local copy for the same reason as
   -- nxrStrEq below: the core's nxToLowerAscii is PRIVATE to its own
   -- script when the two files load as separate stacks, and a private
   -- handler called cross-script is an execution error at the first
   -- handshake (the adversarial review traced exactly that).
   local tOut, tI, tCount, tCode
   put empty into tOut
   put the number of chars of pText into tCount
   repeat with tI = 1 to tCount
      put byteToNum(char tI of pText) into tCode
      if tCode >= 65 and tCode <= 90 then
         put numToChar(tCode + 32) after tOut
      else
         put numToChar(tCode) after tOut
      end if
   end repeat
   return tOut
end nxrToLowerAscii

private function nxrStrEq pA, pB
   -- Byte-exact equality (the accept value is base64: case matters and `is`
   -- folds case). Local copy: the core's nxStrEqExact is private to its own
   -- script when the two files load as separate stacks.
   local tA, tB, tI, tN
   put textEncode(pA, "UTF-8") into tA
   put textEncode(pB, "UTF-8") into tB
   put the number of bytes of tA into tN
   if tN is not the number of bytes of tB then
      return false
   end if
   repeat with tI = 1 to tN
      if byteToNum(byte tI of tA) is not byteToNum(byte tI of tB) then
         return false
      end if
   end repeat
   return true
end nxrStrEq

private command nxrProcessFrames pRelay
   -- Drain complete frames from the buffer. Client-bound frames from a
   -- server are unmasked; nxWsFrameDecode handles either. Fragmented text
   -- reassembles across continuation frames; control frames interleave.
   local tFrame, tRemaining, tTotal
   repeat forever
      if sNxrRelays[pRelay]["socketID"] is empty then
         exit repeat        -- torn down mid-drain
      end if
      put nxWsFrameDecode(sNxrRelays[pRelay]["buffer"]) into tFrame
      if tFrame["error"] is not empty then
         nxrFail pRelay, "websocket framing:" && tFrame["error"]
         exit repeat
      end if
      if tFrame["complete"] is not true then
         exit repeat
      end if
      put the number of bytes of sNxrRelays[pRelay]["buffer"] into tTotal
      if tFrame["consumed"] >= tTotal then
         put empty into sNxrRelays[pRelay]["buffer"]
      else
         put byte (tFrame["consumed"] + 1) to tTotal of sNxrRelays[pRelay]["buffer"] into sNxrRelays[pRelay]["buffer"]
      end if
      if tFrame["opcode"] >= 8 then
         nxrHandleControlFrame pRelay, tFrame["opcode"], tFrame["payload"]
      else
         nxrHandleDataFrame pRelay, tFrame["opcode"], tFrame["fin"], tFrame["payload"]
      end if
   end repeat
end nxrProcessFrames

private command nxrHandleControlFrame pRelay, pOpcode, pPayload
   local tMask, tFrame
   if pOpcode is 8 then
      -- Close: echo one close back (best effort), then tear down.
      if sNxrRelays[pRelay]["state"] is "open" then
         put "closing" into sNxrRelays[pRelay]["state"]
         put nxrRandomHex(4) into tMask
         put nxWsFrameEncode(8, pPayload, tMask) into tFrame
         if tFrame is not empty then
            write tFrame to socket sNxrRelays[pRelay]["socketID"]
         end if
      end if
      nxrTeardown pRelay, "the relay closed the connection"
   else if pOpcode is 9 then
      -- Ping: answer with a pong carrying the same payload.
      put nxrRandomHex(4) into tMask
      put nxWsFrameEncode(10, pPayload, tMask) into tFrame
      if tFrame is not empty then
         write tFrame to socket sNxrRelays[pRelay]["socketID"]
      end if
   end if
   -- Pong (10) and unknown control opcodes are ignored on purpose.
end nxrHandleControlFrame

private command nxrHandleDataFrame pRelay, pOpcode, pFin, pPayload
   -- Text (1) and continuation (0) frames carry the relay protocol; binary
   -- (2) is not part of NIP-01 and is ignored with a notice-level callback.
   local tMessage
   if pOpcode is 2 then
      nxrDispatch pRelay, "notice", "ignored a binary websocket frame", empty
      exit nxrHandleDataFrame
   end if
   if pOpcode is 1 then
      if pFin is true then
         nxrHandleMessage pRelay, pPayload
         exit nxrHandleDataFrame
      end if
      put 1 into sNxrRelays[pRelay]["fragOp"]
      put pPayload into sNxrRelays[pRelay]["fragData"]
      exit nxrHandleDataFrame
   end if
   if pOpcode is 0 then
      if sNxrRelays[pRelay]["fragOp"] is empty then
         nxrFail pRelay, "continuation frame with nothing to continue"
         exit nxrHandleDataFrame
      end if
      put pPayload after sNxrRelays[pRelay]["fragData"]
      if the number of bytes of sNxrRelays[pRelay]["fragData"] > kNxrMaxBuffer then
         nxrFail pRelay, "fragmented message exceeded" && kNxrMaxBuffer && "bytes"
         exit nxrHandleDataFrame
      end if
      if pFin is true then
         put sNxrRelays[pRelay]["fragData"] into tMessage
         put empty into sNxrRelays[pRelay]["fragOp"]
         put empty into sNxrRelays[pRelay]["fragData"]
         nxrHandleMessage pRelay, tMessage
      end if
   end if
end nxrHandleDataFrame

private command nxrHandleMessage pRelay, pPayloadData
   -- One complete text message: parse the relay protocol and dispatch. An
   -- unparseable message is surfaced, never silently dropped (fail closed
   -- in the visible sense: the app learns its relay is misbehaving).
   local tParsed, tEvent, tReason
   put nxRelayParse(textDecode(pPayloadData, "UTF-8")) into tParsed
   if tParsed is empty then
      nxrDispatch pRelay, "notice", "unparseable relay message:" && nxLastError(), empty
      exit nxrHandleMessage
   end if
   if tParsed["type"] is "EVENT" then
      if sNxrRelays[pRelay]["verify"] is true then
         put nxEventFromJson(tParsed["eventJson"]) into tEvent
         if tEvent is empty then
            nxrDispatch pRelay, "invalid", tParsed["subId"], "unparseable event:" && nxLastError()
            exit nxrHandleMessage
         end if
         if nxEventVerify(tEvent) is not true then
            put nxLastError() into tReason
            nxrDispatch pRelay, "invalid", tParsed["subId"], tReason
            exit nxrHandleMessage
         end if
      end if
      nxrDispatch pRelay, "event", tParsed["subId"], tParsed["eventJson"]
   else if tParsed["type"] is "OK" then
      nxrDispatch pRelay, "ok", tParsed["eventId"], tParsed["accepted"] & tab & tParsed["reason"]
   else if tParsed["type"] is "EOSE" then
      nxrDispatch pRelay, "eose", tParsed["subId"], empty
   else if tParsed["type"] is "CLOSED" then
      nxrDispatch pRelay, "closed", tParsed["subId"], tParsed["reason"]
   else if tParsed["type"] is "NOTICE" then
      nxrDispatch pRelay, "notice", tParsed["notice"], empty
   else if tParsed["type"] is "AUTH" then
      put tParsed["challenge"] into sNxrRelays[pRelay]["challenge"]
      nxrDispatch pRelay, "auth", tParsed["challenge"], empty
   else
      nxrDispatch pRelay, "notice", "unknown relay message type", empty
   end if
end nxrHandleMessage

-- ==========================================================================
-- The client verbs.
-- ==========================================================================

private command nxrSendText pRelay, pText
   -- Frame and send one text message; reports via `the result`.
   local tFrame
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if sNxrRelays[pRelay]["state"] is not "open" then
      return "NostrXT relay: relay" && pRelay && "is not open (state:" && sNxrRelays[pRelay]["state"] & ")"
   end if
   put nxWsFrameEncode(1, textEncode(pText, "UTF-8"), nxrRandomHex(4)) into tFrame
   if tFrame is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrSendText

command nxrSetCallback pRelay, pHandlerName
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   put pHandlerName into sNxrRelays[pRelay]["callback"]
   return empty
end nxrSetCallback

command nxrSetVerify pRelay, pVerify
   -- Event verification is ON by default and fails closed (no CoinXT means
   -- events arrive as "invalid", never as unverified "event"s). An app that
   -- explicitly wants raw delivery turns it off per relay, eyes open.
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if pVerify is not true and pVerify is not false then
      return "NostrXT relay: nxrSetVerify takes true or false"
   end if
   put pVerify into sNxrRelays[pRelay]["verify"]
   return empty
end nxrSetVerify

command nxrSubscribe pRelay, pSubId, pFiltersJson
   local tWire
   put nxClientReq(pSubId, pFiltersJson) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   if the result is not empty then
      return the result
   end if
   put pFiltersJson into sNxrRelays[pRelay]["subs"][pSubId]
   return empty
end nxrSubscribe

command nxrUnsubscribe pRelay, pSubId
   local tWire
   put nxClientClose(pSubId) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   if the result is not empty then
      return the result
   end if
   delete variable sNxrRelays[pRelay]["subs"][pSubId]
   return empty
end nxrUnsubscribe

command nxrPublish pRelay, pEvent
   -- Send a SIGNED event; the relay's verdict arrives as the "ok" callback
   -- keyed by the event id.
   local tWire
   put nxClientEvent(pEvent) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   return the result
end nxrPublish

command nxrAuth pRelay, pSignedEvent
   -- Answer a NIP-42 challenge (nxAuthBuild + nxEventSign built it).
   local tWire
   put nxClientAuth(pSignedEvent) into tWire
   if tWire is empty then
      return "NostrXT relay: " & nxLastError()
   end if
   nxrSendText pRelay, tWire
   return the result
end nxrAuth

command nxrSendRaw pRelay, pText
   -- The escape hatch for NIPs this layer does not speak yet: one text
   -- frame, verbatim. The caller owns the JSON.
   nxrSendText pRelay, pText
   return the result
end nxrSendRaw

command nxrPing pRelay
   -- An RFC 6455 ping (liveness probe); a compliant peer answers with a
   -- pong, which this layer ignores on arrival.
   local tFrame
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "NostrXT relay: unknown relay handle" && pRelay
   end if
   if sNxrRelays[pRelay]["state"] is not "open" then
      return "NostrXT relay: relay" && pRelay && "is not open"
   end if
   put nxWsFrameEncode(9, textEncode("nxr", "UTF-8"), nxrRandomHex(4)) into tFrame
   write tFrame to socket sNxrRelays[pRelay]["socketID"]
   return empty
end nxrPing

function nxrState pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return "unknown"
   end if
   return sNxrRelays[pRelay]["state"]
end nxrState

function nxrUrl pRelay
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["url"]
end nxrUrl

function nxrChallenge pRelay
   -- The most recent NIP-42 challenge this relay sent, or empty.
   if sNxrRelays[pRelay]["socketID"] is empty then
      return empty
   end if
   return sNxrRelays[pRelay]["challenge"]
end nxrChallenge

function nxrOpenRelays
   -- Every live relay handle, one per line (delimiter-guarded read of the
   -- handle table's keys).
   local tSavedLineDelim, tOut, tKeyList, tI, tCount
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of sNxrRelays into tKeyList
   sort lines of tKeyList numeric
   put empty into tOut
   put the number of lines of tKeyList into tCount
   repeat with tI = 1 to tCount
      if tOut is not empty then
         put return after tOut
      end if
      put line tI of tKeyList after tOut
   end repeat
   set the lineDelimiter to tSavedLineDelim
   return tOut
end nxrOpenRelays

-- ==========================================================================
-- Teardown: idempotent, fail closed, own the lifecycle.
-- ==========================================================================

private command nxrSafeCloseSocket pSocketID
   -- Close only a socket the engine still lists (the onionxt idempotent-
   -- close shape; delimiter-guarded read of the openSockets).
   local tSavedLineDelim, tIsOpen
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put (pSocketID is among the lines of the openSockets) into tIsOpen
   set the lineDelimiter to tSavedLineDelim
   if tIsOpen then
      close socket pSocketID
   end if
end nxrSafeCloseSocket

private command nxrDispatchTo pHandler, pRelay, pKind, pArgOne, pArgTwo
   -- nxrDispatch by EXPLICIT handler name, for callbacks delivered after
   -- the relay's table entry is already gone (teardown saves the name
   -- first). Same try guard, same clean-miss contract.
   local tError
   if pHandler is empty then
      exit nxrDispatchTo
   end if
   try
      dispatch pHandler to nxrCallbackTarget() with pRelay, pKind, pArgOne, pArgTwo
   catch tError
      -- Swallowed on purpose: the app broke, the transport must not.
   end try
end nxrDispatchTo

private command nxrTeardown pRelay, pReason
   -- Close and FORGET FIRST, tell the app once AFTER: the callback runs
   -- app code synchronously, and an app that answers "disconnected" by
   -- calling nxrDisconnect on the same handle must find the clean no-op
   -- the contract promises - dispatching while the tables were still
   -- populated re-entered a relay that looked fully open (a second close
   -- frame on the wire, a second callback, unbounded recursion; the
   -- adversarial review traced the loop). Safe to call twice.
   local tSocketID, tCallback
   put sNxrRelays[pRelay]["socketID"] into tSocketID
   if tSocketID is empty then
      exit nxrTeardown
   end if
   put sNxrRelays[pRelay]["callback"] into tCallback
   nxrSafeCloseSocket tSocketID
   delete variable sNxrSockToRelay[tSocketID]
   delete variable sNxrRelays[pRelay]
   nxrDispatchTo tCallback, pRelay, "disconnected", pReason, empty
end nxrTeardown

private command nxrFail pRelay, pReason
   -- A wire error: tear down FIRST (the reentrancy rule above), then
   -- surface "error" and "disconnected" from the saved callback name.
   local tSocketID, tCallback
   put sNxrRelays[pRelay]["socketID"] into tSocketID
   if tSocketID is empty then
      exit nxrFail
   end if
   put sNxrRelays[pRelay]["callback"] into tCallback
   nxrSafeCloseSocket tSocketID
   delete variable sNxrSockToRelay[tSocketID]
   delete variable sNxrRelays[pRelay]
   nxrDispatchTo tCallback, pRelay, "error", pReason, empty
   nxrDispatchTo tCallback, pRelay, "disconnected", pReason, empty
end nxrFail

command nxrDisconnect pRelay
   -- App-initiated close: send a close frame when the link is up, then
   -- tear down. Idempotent; a stale handle is a clean no-op.
   local tMask
   if sNxrRelays[pRelay]["socketID"] is empty then
      exit nxrDisconnect
   end if
   if sNxrRelays[pRelay]["state"] is "open" then
      put nxrRandomHex(4) into tMask
      write nxWsFrameEncode(8, numToByte(3) & numToByte(232), tMask) to socket sNxrRelays[pRelay]["socketID"]
   end if
   nxrTeardown pRelay, "disconnected by the app"
end nxrDisconnect

command nxrShutdown
   -- Close every relay (closeStack calls this; there is no deterministic
   -- unload hook in OXT, so the app frees what it opens).
   local tSavedLineDelim, tKeyList, tI, tCount
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of sNxrRelays into tKeyList
   put the number of lines of tKeyList into tCount
   set the lineDelimiter to tSavedLineDelim
   repeat with tI = 1 to tCount
      -- Re-read the key list line by line under a fresh guard each pass:
      -- nxrDisconnect mutates the table while this walks a SNAPSHOT.
      put the lineDelimiter into tSavedLineDelim
      set the lineDelimiter to return
      nxrDisconnect (line tI of tKeyList)
      set the lineDelimiter to tSavedLineDelim
   end repeat
end nxrShutdown

-- ==========================================================================
-- The engine's socket messages. Act ONLY on our own socket ids and PASS the
-- rest: these three names are shared by every socket user in a stack, and
-- swallowing another library's message is a silent HANG no gate can see
-- (the family's socketError rule; two shipping apps re-derived it).
-- ==========================================================================

-- THE ENGINE'S THREE SOCKET MESSAGES, SPLIT IN TWO (2026-08-24), the same
-- way onionxt splits them and for the same reason: these names belong to the
-- ENGINE, so every socket library in the message path declares them, and one
-- script cannot define a name twice - which is what embedding a library into
-- an app's stack script does (tools/sync-demo-embeds.py). The LOGIC lives in
-- nxrSocketError / nxrSocketClosed / nxrSocketTimeout, which answer one
-- question: was that socket MINE, and did I handle it? The `on socket*`
-- handlers are pure dispatch. An embedder drops the three thin wrappers and
-- calls the named function from its own handler, so this logic is never
-- copied and cannot go stale.

-- Was pSocketID one of OUR relay sockets, and did we handle the error?
function nxrSocketError pSocketID, pError
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      nxrFail tHandle, "socket error:" && pError
      return "true"
   end if
   return "false"
end nxrSocketError

on socketError pSocketID, pError
   if nxrSocketError(pSocketID, pError) then
      exit socketError
   end if
   pass socketError
end socketError

-- Was pSocketID one of OUR relay sockets, and did we handle the close?
function nxrSocketClosed pSocketID
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      nxrTeardown tHandle, "the connection closed"
      return "true"
   end if
   return "false"
end nxrSocketClosed

on socketClosed pSocketID
   if nxrSocketClosed(pSocketID) then
      exit socketClosed
   end if
   pass socketClosed
end socketClosed

-- Was pSocketID one of OUR relay sockets, and did we handle the timeout?
function nxrSocketTimeout pSocketID
   -- socketTimeout REPEATS while a read is pending, so it is fatal only
   -- during the handshake; on an open relay an idle read is normal.
   local tHandle
   put sNxrSockToRelay[pSocketID] into tHandle
   if tHandle is not empty then
      if sNxrRelays[tHandle]["state"] is not "open" then
         nxrFail tHandle, "the websocket handshake timed out (socket timeout)"
      end if
      return "true"
   end if
   return "false"
end nxrSocketTimeout

on socketTimeout pSocketID
   if nxrSocketTimeout(pSocketID) then
      exit socketTimeout
   end if
   pass socketTimeout
end socketTimeout

-- ---- nostrxt/examples/nostrxt-tests.livecodescript ----
-- nostrxt-tests.livecodescript - the NostrXT member self-test.
--
-- One OFFLINE, deterministic harness for the whole nx* surface plus the
-- offline (fail-closed / clean-miss) paths of the nxr* relay layer. It runs
-- three ways, and behaves identically in each: standalone beside the
-- libraries (`start using` both stacks), embedded in the demo (which
-- carries libraries and harness between sync-demo-embeds sentinels), and
-- folded into the suite paste (tests/suite-selftest.livecodescript, prefix
-- nx1), where the nxr* sections SKIP because the relay layer is
-- deliberately not embedded there (it defines the engine's socket
-- messages; see src/nostr-relay.livecodescript's header).
--
-- STATUS: verified statically; needs an OXT pass. Every pinned constant
-- below is DERIVED by tools/nostr-kat.py from the published BIP-340,
-- NIP-44, BIP-173 and NIP-19 vector sets or from the member's own oracle
-- fixtures, and tools/check-selftest-vectors.py re-derives each one BY
-- NAME on every build - never hand-edit a vector here; edit the fixture in
-- the KAT and re-paste.
--
-- Entry point: nxSelfTest() - a FUNCTION returning the report. The first
-- line honours the suite's summary-line contract, "N passed, M failed, K
-- skipped" (every word a number or passed/failed/skipped, exactly one such
-- line per report); the suite core parses it via stMergeReturned.
--
-- SKIP is a counted outcome, used when: CoinXT is absent (signing, ids,
-- NIP-44 key schedule), SodiumXT is absent (key generation), or the nxr*
-- relay layer is not loaded (the suite paste). Deliberately NO live
-- network anywhere: a synchronous harness cannot await an async callback
-- without blocking the interpreter thread; the live-relay legs live in the
-- demo and the runbook.
--
-- CAUTION (the onionxt precedent, documented not hidden): the relay
-- section REALLY calls nxrShutdown twice to prove teardown is idempotent.
-- Inside the demo that closes any relay the demo has open.

-- ==========================================================================
-- Pinned vectors - GENERATED by `python3 tools/nostr-kat.py`, re-derived by
-- name by tools/check-selftest-vectors.py. Sources are named in the KAT.
-- ==========================================================================

constant kNxVecSeckey = "0000000000000000000000000000000000000000000000000000000000000003"
constant kNxVecTagEventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
constant kNxVecTagPubkey = "f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca"
constant kNxVecPubkey = "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
constant kNxVecSerializedAHex = "5b302c2266393330386130313932353863333130343933343466383566383964353232396235333163383435383336663939623038363031663131336263653033366639222c313730303030303030302c312c5b5b2265222c2235633833646137376166316465633664373238393833343939386164376161666264396532313931333936643735656333636332376635613737323236663336222c227773733a2f2f6e6f7374722e6578616d706c652e636f6d225d2c5b2270222c2266373233346264346331333934646461343664303966333562643338346464333063633535326164353534313939306639383834346662303636373665396361225d5d2c224e6f737472205c2271756f7465645c22206261636b5c5c736c6173685c6e6c696e655c727265745c747461625c6262735c66666620656e64225d"
constant kNxVecIdA = "69e9622dbf685f4e08c785a9340852ff9d8ba99e43bc26cece70c2e408eac706"
constant kNxVecSigA = "24c9892b29badc15f136f7e850a9fcb3dc4bd4a5997d53b385ff470d80bca86158b9de59f8cd8bd65738d379d1c2e39092f34f03136abb040498e6f2268fc708"
constant kNxVecSerializedBHex = "5b302c2266393330386130313932353863333130343933343466383566383964353232396235333163383435383336663939623038363031663131336263653033366639222c313730303030303030312c302c5b5d2c22225d"
constant kNxVecIdB = "6ea6c7b5b5373cc1881df20c8f80bb5f5577f3ac4c41747a55aca40382436d46"
constant kNxVecContentCHex = "e282ac20f09f929c"
constant kNxVecIdC = "d69bea93a4401bd3bcb2b0eb5687909cf528bd55f32289141228dc753d392c1e"
constant kNxVecNpubHex = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
constant kNxVecNpub = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
constant kNxVecNsecHex = "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa"
constant kNxVecNsec = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"
constant kNxVecNote = "note1d85kytdldp05uzx8sk5ngzzjl7wch2v7gw7zdnkwwrpwgz82curq7275p8"
constant kNxVecNprofile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
constant kNxVecNprofileHex = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
constant kNxVecNevent = "nevent1qqsxn6tz9klksh6wprrct2f5ppf0l8vt4x0y80pxem88pshypr4vwpspzamhxue69uhkummnw3ezuetcv9khqmr99e3k7mgzyrunpzspjfvvxyzfx38ct7ya2g5m2vwggkpklxdsscqlzyauuqm0jqcyqqqqqqg4xh26x"
constant kNxVecNaddr = "naddr1qqrkummnw3e8saqzyrunpzspjfvvxyzfx38ct7ya2g5m2vwggkpklxdsscqlzyauuqm0jqcyqqq823c2e6523"
constant kNxVecN44Sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
constant kNxVecN44Sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
constant kNxVecN44Pub2 = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
constant kNxVecN44Conv = "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d"
constant kNxVecN44Nonce = "0000000000000000000000000000000000000000000000000000000000000001"
constant kNxVecN44Payload = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"
constant kNxVecN44MkConv = "a1a3d60f3470a8612633924e91febf96dc5366ce130f658b1f0fc652c20b3b54"
constant kNxVecN44MkNonce = "e1e6f880560d6d149ed83dcc7e5861ee62a5ee051f7fde9975fe5d25d2a02d72"
constant kNxVecN44MkChaKey = "f145f3bed47cb70dbeaac07f3a3fe683e822b3715edb7c4fe310829014ce7d76"
constant kNxVecN44MkChaNonce = "c4ad129bb01180c0933a160c"
constant kNxVecN44MkHmacKey = "027c1db445f05e2eee864a0975b0ddef5b7110583c8c192de3732571ca5838c4"
constant kNxVecN44PadIns = "16,32,33,37,45,49,64,65,100,111,200,250,320,383,384,400,500,512,515,700,800,900,1020,65536"
constant kNxVecN44PadOuts = "32,32,64,64,64,64,64,96,128,128,224,256,320,384,384,448,512,512,640,768,896,1024,1024,65536"
constant kNxVecWsKey = "dGhlIHNhbXBsZSBub25jZQ=="
constant kNxVecWsAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
constant kNxVecWsMask = "37fa213d"
constant kNxVecWsFrameHello = "818537fa213d7f9f4d5158"
constant kNxVecPowId = "000000000e9d97a1ab09fc381030b346cdd7a142ad57e6df0b46dc9bef6c7e2d"

-- ==========================================================================
-- Counters and per-run state.
-- ==========================================================================

local sNxtLog
local sNxtPass
local sNxtFail
local sNxtSkip
local sNxtHasCoin            -- true when the CoinXT probe round-tripped
local sNxtHasSodium          -- true when the SodiumXT probe round-tripped

-- ==========================================================================
-- Entry point and plumbing.
-- ==========================================================================

function nxSelfTest
   local tCaps, tSummary
   put empty into sNxtLog
   put 0 into sNxtPass
   put 0 into sNxtFail
   put 0 into sNxtSkip
   put nxProbeCapabilities() into tCaps
   put tCaps["hasCoin"] into sNxtHasCoin
   put tCaps["hasSodium"] into sNxtHasSodium
   nxtTestVersionAndCapabilities
   nxtTestHexAndHelpers
   nxtTestJsonEscape
   nxtTestJsonParse
   nxtTestEventShape
   nxtTestEventIdAndSign
   nxtTestNip19Bare
   nxtTestNip19Tlv
   nxtTestNip44Schedule
   nxtTestNip44Padding
   nxtTestNip44Seam
   nxtTestFilters
   nxtTestRelayMessages
   nxtTestWsPure
   nxtTestBuilders
   nxtTestPowAndDiscovery
   nxtTestRelayLayerOffline
   put sNxtPass & " passed, " & sNxtFail & " failed, " & sNxtSkip & " skipped" into tSummary
   return tSummary & return & "----------------------------------------" & return & sNxtLog
end nxSelfTest

private command nxtCheck pCondition, pLabel
   if pCondition is true then
      add 1 to sNxtPass
      put "  ok   " & pLabel & return after sNxtLog
   else
      add 1 to sNxtFail
      put "  FAIL " & pLabel & return after sNxtLog
   end if
end nxtCheck

private command nxtSection pTitle
   put "-- " & pTitle & " --" & return after sNxtLog
end nxtSection

private command nxtSkip pReason
   add 1 to sNxtSkip
   put "  --   (skipped: " & pReason & ")" & return after sNxtLog
end nxtSkip

private function nxtBytesHex pText
   -- The UTF-8 bytes of a string, as hex: the byte-exact comparison every
   -- canonical-form check uses.
   return nxHexEncode(textEncode(pText, "UTF-8"))
end nxtBytesHex

private function nxtEventA
   -- The escape-set fixture event (tools/nostr-kat.py EVENT_A), pubkey
   -- filled in so the serialization checks run without CoinXT.
   local tTags, tContent, tEvent
   put "e" into tTags[1][1]
   put kNxVecTagEventId into tTags[1][2]
   put "wss://nostr.example.com" into tTags[1][3]
   put "p" into tTags[2][1]
   put kNxVecTagPubkey into tTags[2][2]
   put "Nostr " & quote & "quoted" & quote & " back\slash" into tContent
   put numToChar(10) & "line" & numToChar(13) & "ret" & tab & "tab" after tContent
   put numToChar(8) & "bs" & numToChar(12) & "ff end" after tContent
   put nxEventBuild(1, tContent, tTags, 1700000000) into tEvent
   put kNxVecPubkey into tEvent["pubkey"]
   return tEvent
end nxtEventA

private function nxtEventB
   -- The empty-tags, empty-content fixture (tools/nostr-kat.py EVENT_B).
   local tEvent
   put nxEventBuild(0, empty, empty, 1700000001) into tEvent
   put kNxVecPubkey into tEvent["pubkey"]
   return tEvent
end nxtEventB

-- ==========================================================================
-- 1. Version and capabilities.
-- ==========================================================================

private command nxtTestVersionAndCapabilities
   local tCaps, tVersionText
   nxtSection "version and capabilities"
   put nxVersion() into tVersionText
   nxtCheck tVersionText begins with "NostrXT", "nxVersion reports the member name"
   put nxProbeCapabilities() into tCaps
   nxtCheck tCaps is an array, "nxProbeCapabilities returns an array"
   nxtCheck tCaps["hasCoin"] is true or tCaps["hasCoin"] is false, "hasCoin is a boolean"
   nxtCheck tCaps["hasSodium"] is true or tCaps["hasSodium"] is false, "hasSodium is a boolean"
   nxtCheck tCaps["canNip44Cipher"] is true or tCaps["canNip44Cipher"] is false, "canNip44Cipher is a boolean"
   -- The error surface: a failing call records a readable reason.
   get nxHexDecode("abc")
   nxtCheck nxLastError() contains "odd length", "nxLastError carries the last refusal"
end nxtTestVersionAndCapabilities

-- ==========================================================================
-- 2. Hex, base64, comparison, time.
-- ==========================================================================

private command nxtTestHexAndHelpers
   local tData, tHexText, tB64Text
   nxtSection "hex, base64, compare, time"
   put nxHexDecode("00ff10") into tData
   nxtCheck the number of bytes of tData is 3, "nxHexDecode yields bytes"
   nxtCheck byteToNum(byte 2 of tData) is 255, "nxHexDecode byte values are right"
   nxtCheck nxHexEncode(tData) is "00ff10", "nxHexEncode round-trips lowercase"
   nxtCheck nxHexDecode("ABCDEF") is nxHexDecode("abcdef"), "nxHexDecode accepts either case"
   nxtCheck nxHexDecode("abc") is empty, "odd-length hex refuses"
   nxtCheck nxHexDecode("zz") is empty, "non-hex characters refuse"
   nxtCheck nxIsHex(kNxVecPubkey, 64) is true, "nxIsHex accepts a 64-hex pubkey"
   nxtCheck nxIsHex("xyz", empty) is false, "nxIsHex refuses non-hex"
   nxtCheck nxIsHex(kNxVecPubkey, 32) is false, "nxIsHex enforces the length"
   nxtCheck nxCtEqualHex(kNxVecIdA, kNxVecIdA) is true, "nxCtEqualHex: equal"
   nxtCheck nxCtEqualHex(kNxVecIdA, kNxVecIdB) is false, "nxCtEqualHex: unequal"
   nxtCheck nxCtEqualHex("aa", "aaaa") is false, "nxCtEqualHex: length mismatch"
   put nxB64Encode(nxHexDecode("000102fdfeff")) into tB64Text
   nxtCheck nxHexEncode(nxB64Decode(tB64Text)) is "000102fdfeff", "base64 round-trips"
   nxtCheck not (tB64Text contains numToChar(10)), "nxB64Encode emits one line"
   nxtCheck nxB64Decode("a!b=") is empty, "nxB64Decode refuses foreign characters"
   nxtCheck nxB64Decode("abcde") is empty, "nxB64Decode refuses a bad length"
   nxtCheck nxB64Decode("AB===") is empty, "nxB64Decode refuses three pads"
   nxtCheck nxB64Decode(kNxVecN44Payload & "A===") is empty, "nxB64Decode refuses a one-data-char final group (the lenient-engine trap)"
   nxtCheck nxB64Decode("A=BC") is empty, "nxB64Decode refuses padding before the end"
   nxtCheck nxUnixNow() is an integer, "nxUnixNow is an integer"
   nxtCheck nxUnixNow() > 1700000000, "nxUnixNow is after the fixture era"
end nxtTestHexAndHelpers

-- ==========================================================================
-- 3. The NIP-01 escape set.
-- ==========================================================================

private command nxtTestJsonEscape
   local tInput, tExpected
   nxtSection "NIP-01 json escaping"
   put quote & "\" & numToChar(10) & numToChar(13) & tab & numToChar(8) & numToChar(12) into tInput
   put "\" & quote & "\\\n\r\t\b\f" into tExpected
   nxtCheck nxtBytesHex(nxJsonEscape(tInput)) is nxtBytesHex(tExpected), "the seven escapes, exactly"
   nxtCheck nxJsonEscape("plain text") is "plain text", "plain text passes through"
   nxtCheck nxtBytesHex(nxJsonEscape("a" & numToChar(1) & "b")) is "610162", "0x01 passes through VERBATIM (the rule json.dumps breaks)"
   nxtCheck nxJsonEscape(empty) is empty, "empty in, empty out"
end nxtTestJsonEscape

-- ==========================================================================
-- 4. The JSON parser.
-- ==========================================================================

private command nxtTestJsonParse
   local tJson, tDeep, tI
   nxtSection "json parser"
   put "{" & quote & "a" & quote & ":[1,2,{" & quote & "b" & quote & ":" & quote & "x" & quote & "}],  " & quote & "c" & quote & ":true," & quote & "d" & quote & ":null}" into tJson
   nxtCheck nxJsonType(tJson, empty) is "object", "root object types"
   nxtCheck nxJsonType(tJson, "a") is "array", "array member types"
   nxtCheck nxJsonCount(tJson, "a") is 3, "array count"
   nxtCheck nxJsonGet(tJson, "a/2") is "2", "array element by index"
   nxtCheck nxJsonGet(tJson, "a/3/b") is "x", "nested object member"
   nxtCheck nxJsonType(tJson, "c") is "boolean", "boolean types"
   nxtCheck nxJsonGet(tJson, "c") is "true", "boolean value"
   nxtCheck nxJsonType(tJson, "d") is "null", "null types"
   nxtCheck nxJsonType(tJson, "missing") is "missing", "an absent key is missing"
   nxtCheck nxJsonGet(tJson, "a/3") is "{" & quote & "b" & quote & ":" & quote & "x" & quote & "}", "a container returns its VERBATIM slice"
   -- string escapes, including \u and a surrogate pair
   put "[" & quote & "A\n" & quote & "," & quote & "\ud83d\udc9c" & quote & "]" into tJson
   nxtCheck nxtBytesHex(nxJsonGet(tJson, "1")) is "410a", "unicode escape and newline decode"
   nxtCheck nxtBytesHex(nxJsonGet(tJson, "2")) is "f09f929c", "a surrogate pair becomes 4 utf-8 bytes"
   -- refusals
   nxtCheck nxJsonType("[1,2] trailing", empty) is "missing", "trailing bytes refuse"
   nxtCheck nxJsonType("[tRUE]", empty) is "missing", "mixed-case true refuses (byte-exact words)"
   nxtCheck nxJsonType("[" & quote & "unterminated", empty) is "missing", "an unterminated string refuses"
   nxtCheck nxJsonType("[" & quote & "\ud83d" & quote & "]", empty) is "missing", "a lone high surrogate refuses"
   nxtCheck nxJsonType("[" & quote & "\q" & quote & "]", empty) is "missing", "an unknown escape refuses"
   nxtCheck nxJsonType("[07]", empty) is "missing", "a leading-zero number refuses (RFC 8259 grammar)"
   nxtCheck nxJsonType("[2e]", empty) is "missing", "an exponent with no digits refuses"
   nxtCheck nxJsonType("[+5]", empty) is "missing", "a leading plus refuses"
   nxtCheck nxJsonType("{" & quote & "a" & quote & ":1," & quote & "a" & quote & ":2}", empty) is "missing", "duplicate object keys refuse (the first-wins/last-wins desync)"
   nxtCheck nxJsonType("{" & quote & "NAME" & quote & ":1}", "name") is "missing", "object keys are case-sensitive (is folds; the walk must not)"
   nxtCheck nxJsonType("[1,2,3]", "2.0") is "missing", "array paths are digit runs, not numeric folds"
   put empty into tDeep
   repeat with tI = 1 to 70
      put "[" after tDeep
   end repeat
   put "1" after tDeep
   repeat with tI = 1 to 70
      put "]" after tDeep
   end repeat
   nxtCheck nxJsonType(tDeep, empty) is "missing", "nesting deeper than the cap refuses"
end nxtTestJsonParse

-- ==========================================================================
-- 5. Event shape, canonical serialization (no crypto needed), tags.
-- ==========================================================================

private command nxtTestEventShape
   local tEvent, tOther, tTagsText, tTags, tJson, tBack
   nxtSection "event shape and canonical serialization"
   put nxtEventA() into tEvent
   nxtCheck tEvent is an array, "nxEventBuild builds the fixture"
   nxtCheck nxEventHasValidShape(tEvent) is true, "the fixture has a valid shape"
   nxtCheck nxtBytesHex(nxEventSerialize(tEvent)) is kNxVecSerializedAHex, "event A serializes byte-exactly (all seven escapes)"
   put nxtEventB() into tEvent
   nxtCheck nxtBytesHex(nxEventSerialize(tEvent)) is kNxVecSerializedBHex, "event B serializes byte-exactly (empty tags, empty content)"
   -- shape refusals
   nxtCheck nxEventBuild(-1, empty, empty, 1) is empty, "kind -1 refuses"
   nxtCheck nxEventBuild(65536, empty, empty, 1) is empty, "kind 65536 refuses"
   nxtCheck nxEventBuild(1, empty, empty, -5) is empty, "a negative created_at refuses"
   nxtCheck nxEventBuild(1, empty, empty, "1e3") is empty, "a coerced created_at spelling refuses (1e3 is an integer to this dialect; the preimage must be canonical)"
   nxtCheck nxEventBuild("07", empty, empty, 1) is empty, "a leading-zero kind spelling refuses"
   put empty into tOther
   put "e" into tOther[2][1]
   put kNxVecTagEventId into tOther[2][2]
   nxtCheck nxEventBuild(1, empty, tOther, 1) is empty, "a gapped tags table refuses instead of silently dropping the unreachable tag"
   put nxtEventB() into tOther
   put empty into tOther["pubkey"]
   nxtCheck nxEventSerialize(tOther) is empty, "serializing without a pubkey refuses"
   put nxtEventB() into tOther
   put "zz" into tOther["id"]
   nxtCheck nxEventHasValidShape(tOther) is false, "a malformed id fails the shape check"
   -- tags text form and lookups
   put "e" & tab & kNxVecTagEventId & tab & "wss://nostr.example.com" & return & "p" & tab & kNxVecTagPubkey into tTagsText
   put nxTagsFromText(tTagsText) into tTags
   nxtCheck nxSeqLikeCount(tTags) is 2, "nxTagsFromText builds two tags"
   nxtCheck nxTagsToText(tTags) is tTagsText, "nxTagsToText round-trips"
   put nxtEventA() into tEvent
   nxtCheck nxTagCount(tEvent) is 2, "nxTagCount"
   nxtCheck nxTagItem(tEvent, 2) is "p" & tab & kNxVecTagPubkey, "nxTagItem joins with tabs"
   nxtCheck nxTagItem(tEvent, 9) is empty, "nxTagItem: out of range is a clean miss"
   nxtCheck nxTagFirst(tEvent, "e") is kNxVecTagEventId, "nxTagFirst finds the e tag"
   nxtCheck nxTagFirst(tEvent, "E") is empty, "tag names are case-sensitive (e is not E)"
   nxtCheck nxTagValues(tEvent, "p") is kNxVecTagPubkey, "nxTagValues lists p values"
   -- wire object round trip
   put nxtEventA() into tEvent
   put kNxVecIdA into tEvent["id"]
   put kNxVecSigA into tEvent["sig"]
   put nxEventToJson(tEvent) into tJson
   nxtCheck tJson is not empty, "nxEventToJson emits the object"
   put nxEventFromJson(tJson) into tBack
   nxtCheck tBack is not empty, "nxEventFromJson parses it back"
   nxtCheck nxtBytesHex(nxEventSerialize(tBack)) is kNxVecSerializedAHex, "the round trip preserves the canonical bytes"
   nxtCheck tBack["id"] is kNxVecIdA, "the round trip preserves the id"
   -- wire refusals
   nxtCheck nxEventFromJson("[1,2]") is empty, "a non-object refuses"
   put "{" & quote & "kind" & quote & ":1," & quote & "created_at" & quote & ":1e3," & quote & "content" & quote & ":" & quote & quote & "," & quote & "tags" & quote & ":[]}" into tJson
   nxtCheck nxEventFromJson(tJson) is empty, "a created_at of 1e3 refuses (non-canonical number)"
   put "{" & quote & "kind" & quote & ":1," & quote & "created_at" & quote & ":5," & quote & "content" & quote & ":" & quote & quote & "," & quote & "tags" & quote & ":[[1]]}" into tJson
   nxtCheck nxEventFromJson(tJson) is empty, "a non-string tag item refuses"
   put "{" & quote & "kind" & quote & ":1," & quote & "created_at" & quote & ":5," & quote & "content" & quote & ":" & quote & quote & "," & quote & "tags" & quote & ":[[]]}" into tJson
   nxtCheck nxEventFromJson(tJson) is empty, "an empty tag refuses (it would gap the rebuilt keys)"
   put "{" & quote & "kind" & quote & ":1," & quote & "created_at" & quote & ":5," & quote & "content" & quote & ":" & quote & quote & "," & quote & "tags" & quote & ":[]," & quote & "id" & quote & ":" & quote & "6EA6C7B5B5373CC1881DF20C8F80BB5F5577F3AC4C41747A55ACA40382436D46" & quote & "}" into tJson
   nxtCheck nxEventFromJson(tJson) is empty, "an UPPERCASE wire id refuses (NIP-01: lowercase hex on the wire)"
   -- the tags text form's one non-round-trippable shape
   put empty into tTags
   put "e" into tTags[1][1]
   put kNxVecTagEventId into tTags[1][2]
   put empty into tTags[1][3]
   nxtCheck nxTagsToText(tTags) is empty, "a trailing empty tag item refuses (the engine eats one trailing delimiter)"
   nxtCheck nxCtEqualHex("6ea6", "6EA6") is true, "nxCtEqualHex normalizes case identically on BOTH of its paths"
end nxtTestEventShape

private function nxSeqLikeCount pArray
   -- Local sequential count (the library's own is private to its file).
   local tN
   put 0 into tN
   repeat forever
      if (tN + 1) is among the keys of pArray then
         add 1 to tN
      else
         exit repeat
      end if
   end repeat
   return tN
end nxSeqLikeCount

-- ==========================================================================
-- 6. Event ids and signatures (CoinXT-guarded; deterministic aux).
-- ==========================================================================

private command nxtTestEventIdAndSign
   local tEvent, tSigned, tTampered, tKeyHex, tAuxHex
   nxtSection "event ids and BIP-340 signatures"
   if sNxtHasCoin is not true then
      nxtSkip "CoinXT is not installed; ids and signatures need cxSha256 / cxSchnorrSign"
      nxtSkip "install the CoinXT extension to run this section"
      exit nxtTestEventIdAndSign
   end if
   put nxtEventA() into tEvent
   nxtCheck nxEventId(tEvent) is kNxVecIdA, "event A id matches the oracle"
   put nxtEventB() into tEvent
   nxtCheck nxEventId(tEvent) is kNxVecIdB, "event B id matches the oracle"
   -- UTF-8 pass-through: the euro sign and an emoji, built from bytes so
   -- this file stays pure ASCII. A FAIL here on a real engine is a REAL
   -- finding about engine text round-tripping, not noise.
   put nxEventBuild(1, textDecode(nxHexDecode(kNxVecContentCHex), "UTF-8"), empty, 1700000002) into tEvent
   put kNxVecPubkey into tEvent["pubkey"]
   nxtCheck nxEventId(tEvent) is kNxVecIdC, "event C id matches (raw UTF-8 content)"
   -- keys
   nxtCheck nxKeyPublic(kNxVecSeckey) is kNxVecPubkey, "nxKeyPublic derives the x-only pubkey"
   nxtCheck nxKeyPublic("zz") is empty, "nxKeyPublic refuses malformed hex"
   nxtCheck nxKeyIsValid(kNxVecSeckey) is true, "nxKeyIsValid accepts the fixture key"
   nxtCheck nxKeyIsValid("0000000000000000000000000000000000000000000000000000000000000000") is false, "the zero scalar is invalid"
   -- deterministic signing (aux = 32 zero bytes)
   put "0000000000000000000000000000000000000000000000000000000000000000" into tAuxHex
   put nxEventSign(nxtEventA(), kNxVecSeckey, tAuxHex) into tSigned
   nxtCheck tSigned["id"] is kNxVecIdA, "nxEventSign fills the id"
   nxtCheck tSigned["pubkey"] is kNxVecPubkey, "nxEventSign fills the pubkey"
   nxtCheck tSigned["sig"] is kNxVecSigA, "the deterministic signature matches the oracle"
   nxtCheck nxEventVerify(tSigned) is true, "the signed fixture verifies"
   -- tampering
   put tSigned into tTampered
   put tTampered["content"] & "!" into tTampered["content"]
   nxtCheck nxEventVerify(tTampered) is false, "tampered content is refused"
   put tSigned into tTampered
   put kNxVecIdB into tTampered["id"]
   nxtCheck nxEventVerify(tTampered) is false, "a swapped id is refused"
   put tSigned into tTampered
   put "00" & char 3 to 128 of tTampered["sig"] into tTampered["sig"]
   nxtCheck nxEventVerify(tTampered) is false, "a corrupted signature is refused"
   nxtCheck nxEventSign(nxtEventA(), "zz", empty) is empty, "signing with malformed hex refuses"
   nxtCheck nxEventSign(nxtEventA(), kNxVecSeckey, "short") is empty, "a malformed aux refuses"
   -- generation needs SodiumXT randomness on top of CoinXT validation
   if sNxtHasSodium is not true then
      nxtSkip "SodiumXT is not installed; nxKeyGenerate needs sxRandomBytes"
   else
      put nxKeyGenerate() into tKeyHex
      nxtCheck nxIsHex(tKeyHex, 64), "nxKeyGenerate yields 64 hex"
      nxtCheck nxKeyIsValid(tKeyHex) is true, "the generated key is a valid scalar"
      nxtCheck nxIsHex(nxKeyPublic(tKeyHex), 64), "the generated key derives a pubkey"
   end if
end nxtTestEventIdAndSign

-- ==========================================================================
-- 7. NIP-19 bare entities and bech32 (pure; no crypto).
-- ==========================================================================

private command nxtTestNip19Bare
   local tDecoded, tTampered, tLastChar
   nxtSection "NIP-19 bare entities and bech32"
   nxtCheck nxNpubEncode(kNxVecNpubHex) is kNxVecNpub, "the published npub example encodes"
   nxtCheck nxNpubDecode(kNxVecNpub) is kNxVecNpubHex, "and decodes"
   nxtCheck nxNsecEncode(kNxVecNsecHex) is kNxVecNsec, "the published nsec example encodes"
   nxtCheck nxNsecDecode(kNxVecNsec) is kNxVecNsecHex, "and decodes"
   nxtCheck nxNoteEncode(kNxVecIdA) is kNxVecNote, "the fixture note encodes"
   nxtCheck nxNoteDecode(kNxVecNote) is kNxVecIdA, "and decodes"
   nxtCheck nxNpubDecode(kNxVecNsec) is empty, "an nsec into nxNpubDecode refuses (hrp check)"
   nxtCheck nxNsecEncode("abc") is empty, "a short payload refuses"
   -- checksum integrity: flip the last character to a DIFFERENT charset char
   local tNpubLen
   put the number of chars of kNxVecNpub into tNpubLen
   put char tNpubLen of kNxVecNpub into tLastChar
   if tLastChar is "q" then
      put char 1 to (tNpubLen - 1) of kNxVecNpub & "p" into tTampered
   else
      put char 1 to (tNpubLen - 1) of kNxVecNpub & "q" into tTampered
   end if
   nxtCheck nxNpubDecode(tTampered) is empty, "a flipped character fails the checksum"
   -- BIP-173 conformance spot checks (the KAT sweeps the full lists)
   put nxBech32Decode("A12UEL5L") into tDecoded
   nxtCheck tDecoded["hrp"] is "a", "BIP-173: uppercase-only input decodes, lowercased"
   nxtCheck tDecoded["spec"] is "bech32", "and reports its spec"
   nxtCheck nxBech32Decode("A1G7SGD8") is empty, "BIP-173: the uppercase-hrp-checksum trap refuses"
   nxtCheck nxBech32Decode("x1b4n0q5v") is empty, "BIP-173: a foreign data character refuses"
   nxtCheck nxBech32Decode("nPub1abc") is empty, "mixed case refuses"
   nxtCheck nxBech32Encode("NPUB", kNxVecNpubHex, "bech32") is empty, "an uppercase hrp refuses (uppercase the result instead)"
   -- bech32m round trip and spec detection
   put nxBech32Encode("nx", "0011ff", "bech32m") into tTampered
   put nxBech32Decode(tTampered) into tDecoded
   nxtCheck tDecoded["spec"] is "bech32m", "bech32m round-trips and self-identifies"
   nxtCheck tDecoded["hex"] is "0011ff", "and carries its payload"
   -- the empty-payload edge BIP-173's own vectors pin (the checksum IS the
   -- data part; the first cut's separator bound refused these)
   put nxBech32Encode("a", empty, "bech32") into tTampered
   put nxBech32Decode(tTampered) into tDecoded
   nxtCheck tDecoded["hrp"] is "a" and tDecoded["hex"] is empty, "an empty payload encodes and decodes (BIP-173's A12UEL5L class)"
end nxtTestNip19Bare

-- ==========================================================================
-- 8. NIP-19 TLV entities.
-- ==========================================================================

private command nxtTestNip19Tlv
   local tFields, tRelaysText, tEntity, tPayloadHex
   nxtSection "NIP-19 TLV entities"
   put "wss://r.x.com" & return & "wss://djbas.sadkb.com" into tRelaysText
   nxtCheck nxNprofileEncode(kNxVecNprofileHex, tRelaysText) is kNxVecNprofile, "the published nprofile example encodes"
   put nxNprofileDecode(kNxVecNprofile) into tFields
   nxtCheck tFields["pubkey"] is kNxVecNprofileHex, "nprofile decodes the pubkey"
   nxtCheck tFields["relays"] is tRelaysText, "nprofile decodes both relays in order"
   nxtCheck nxNeventEncode(kNxVecIdA, "wss://nostr.example.com", kNxVecPubkey, 1) is kNxVecNevent, "the fixture nevent encodes"
   put nxNeventDecode(kNxVecNevent) into tFields
   nxtCheck tFields["id"] is kNxVecIdA, "nevent decodes the id"
   nxtCheck tFields["relays"] is "wss://nostr.example.com", "nevent decodes the relay"
   nxtCheck tFields["pubkey"] is kNxVecPubkey, "nevent decodes the author"
   nxtCheck tFields["kind"] is 1, "nevent decodes the kind"
   nxtCheck nxNaddrEncode("nostrxt", kNxVecPubkey, 30023, empty) is kNxVecNaddr, "the fixture naddr encodes"
   put nxNaddrDecode(kNxVecNaddr) into tFields
   nxtCheck tFields["identifier"] is "nostrxt", "naddr decodes the identifier"
   nxtCheck tFields["kind"] is 30023, "naddr decodes the kind"
   put nxEntityDecode(kNxVecNpub) into tFields
   nxtCheck tFields["type"] is "npub", "nxEntityDecode dispatches bare entities"
   put nxEntityDecode("nostr:" & kNxVecNote) into tFields
   nxtCheck tFields["type"] is "note", "nxEntityDecode strips a nostr: prefix"
   -- unknown TLV types are ignored, per NIP-19: craft nevent = TLV0(id) +
   -- TLV type 99 (2 bytes), through the generic encoder
   put "00" & "20" & kNxVecIdA & "63" & "02" & "beef" into tPayloadHex
   put nxBech32Encode("nevent", tPayloadHex, "bech32") into tEntity
   put nxEntityDecode(tEntity) into tFields
   nxtCheck tFields["id"] is kNxVecIdA, "an unknown TLV type is ignored, not an error"
   -- truncation refuses
   put nxBech32Encode("nevent", "0020" & kNxVecIdA & "0105", "bech32") into tEntity
   nxtCheck nxEntityDecode(tEntity) is empty, "a truncated TLV refuses"
   nxtCheck nxNeventDecode(kNxVecNpub) is empty, "an npub into nxNeventDecode refuses"
   -- URIs
   nxtCheck nxUriEncode(kNxVecNpub) is "nostr:" & kNxVecNpub, "nxUriEncode wraps a shareable entity"
   nxtCheck nxUriEncode("nostr:" & kNxVecNpub) is "nostr:" & kNxVecNpub, "and is idempotent on an already-prefixed input"
   nxtCheck nxUriEncode(kNxVecNsec) is empty, "nxUriEncode REFUSES a secret key"
   put nxUriDecode("nostr:" & kNxVecNpub) into tFields
   nxtCheck tFields["pubkey"] is kNxVecNpubHex, "nxUriDecode yields the fields"
   nxtCheck nxUriDecode(kNxVecNpub) is empty, "nxUriDecode wants the prefix"
   nxtCheck nxUriDecode("nostr:" & kNxVecNsec) is empty, "nxUriDecode refuses a secret-key URI (the encode hygiene, inbound)"
   -- the identifier-refusal masking trap: an over-long naddr identifier
   -- must refuse even when relay TLVs would refill the payload
   local tLongIdent, tIdentIx
   put empty into tLongIdent
   repeat with tIdentIx = 1 to 256
      put "x" after tLongIdent
   end repeat
   nxtCheck nxNaddrEncode(tLongIdent, kNxVecPubkey, 1, "wss://r.io") is empty, "a 256-byte naddr identifier refuses, relays or not"
end nxtTestNip19Tlv

-- ==========================================================================
-- 9. The NIP-44 key schedule (CoinXT-guarded).
-- ==========================================================================

private command nxtTestNip44Schedule
   local tConvHex, tKeys, tPubOne
   nxtSection "NIP-44 conversation and message keys"
   if sNxtHasCoin is not true then
      nxtSkip "CoinXT is not installed; the key schedule needs cxEcdh / cxHmacSha256"
      nxtSkip "install the CoinXT extension to run this section"
      exit nxtTestNip44Schedule
   end if
   nxtCheck nxKeyPublic(kNxVecN44Sec2) is kNxVecN44Pub2, "the vector's pub2 derives from sec2"
   put nxNip44ConversationKey(kNxVecN44Sec1, kNxVecN44Pub2) into tConvHex
   nxtCheck tConvHex is kNxVecN44Conv, "the official conversation-key vector matches"
   put nxNip44ConversationKey(kNxVecN44Sec2, nxKeyPublic(kNxVecN44Sec1)) into tConvHex
   nxtCheck tConvHex is kNxVecN44Conv, "conv(a,B) equals conv(b,A) - the roles swap"
   nxtCheck nxNip44ConversationKey("zz", kNxVecN44Pub2) is empty, "malformed keys refuse"
   put nxNip44MessageKeys(kNxVecN44MkConv, kNxVecN44MkNonce) into tKeys
   nxtCheck tKeys["chachaKey"] is kNxVecN44MkChaKey, "message keys: chacha key matches the vector"
   nxtCheck tKeys["chachaNonce"] is kNxVecN44MkChaNonce, "message keys: chacha nonce matches"
   nxtCheck tKeys["hmacKey"] is kNxVecN44MkHmacKey, "message keys: hmac key matches"
   nxtCheck nxNip44MessageKeys(kNxVecN44MkConv, "beef") is empty, "a short nonce refuses"
end nxtTestNip44Schedule

-- ==========================================================================
-- 10. NIP-44 padding (pure arithmetic; the full official pair table).
-- ==========================================================================

private command nxtTestNip44Padding
   local tSavedItemDelim, tI, tCount, tIn, tWant, tAllOk, tBad
   nxtSection "NIP-44 padded lengths"
   put the itemDelimiter into tSavedItemDelim
   set the itemDelimiter to comma
   put the number of items of kNxVecN44PadIns into tCount
   put true into tAllOk
   put empty into tBad
   repeat with tI = 1 to tCount
      put item tI of kNxVecN44PadIns into tIn
      put item tI of kNxVecN44PadOuts into tWant
      if nxNip44PaddedLen(tIn) is not tWant + 0 then
         put false into tAllOk
         put tIn into tBad
         exit repeat
      end if
   end repeat
   set the itemDelimiter to tSavedItemDelim
   nxtCheck tAllOk, "all" && tCount && "official calc_padded_len pairs match (first miss:" && tBad & ")"
   nxtCheck nxNip44PaddedLen(1) is 32, "one byte pads to 32"
   nxtCheck nxNip44PaddedLen(0) is empty, "zero refuses"
   nxtCheck nxNip44PaddedLen(-4) is empty, "negative refuses"
end nxtTestNip44Padding

-- ==========================================================================
-- 11. The NIP-44 cipher seam. The MAC path is provable on any SodiumXT (it
-- runs before the cipher). sxChaCha20IetfXor shipped upstream in SodiumXT
-- ABI 10 (2026-08-23), so against a current package the official payload
-- vector round-trips here; against an older installed SodiumXT the cipher
-- still fails closed and this section asserts THAT instead - the branch is
-- the probe's answer, exactly as designed the day the seam was written.
-- ==========================================================================

private command nxtTestNip44Seam
   local tHasCipher, tOut, tTampered, tMiddle
   nxtSection "NIP-44 cipher seam (docs/07)"
   put nxNip44HasCipher() into tHasCipher
   nxtCheck tHasCipher is true or tHasCipher is false, "nxNip44HasCipher answers without throwing"
   -- refusals that need no crypto at all
   nxtCheck nxNip44Decrypt(kNxVecN44Sec1, kNxVecN44Pub2, "#future") is empty, "a future-format payload refuses"
   nxtCheck nxLastError() contains "version", "and says why"
   nxtCheck nxNip44Decrypt(kNxVecN44Sec1, kNxVecN44Pub2, "short") is empty, "a short payload refuses"
   nxtCheck nxNip44Encrypt(kNxVecN44Sec1, kNxVecN44Pub2, empty, kNxVecN44Nonce) is empty, "an empty plaintext refuses"
   if sNxtHasCoin is not true then
      nxtSkip "CoinXT is not installed; the MAC and seam paths need the key schedule"
      exit nxtTestNip44Seam
   end if
   -- Tamper INSIDE the ciphertext region: the MAC check runs BEFORE the
   -- cipher, so this proves the authenticate-then-decrypt order today.
   put kNxVecN44Payload into tTampered
   put char 60 of tTampered into tMiddle
   if tMiddle is "A" then
      put char 1 to 59 of tTampered & "B" & char 61 to (the number of chars of tTampered) of tTampered into tTampered
   else
      put char 1 to 59 of tTampered & "A" & char 61 to (the number of chars of tTampered) of tTampered into tTampered
   end if
   nxtCheck nxNip44Decrypt(kNxVecN44Sec1, kNxVecN44Pub2, tTampered) is empty, "a tampered payload refuses"
   nxtCheck nxLastError() contains "MAC", "at the MAC, before any cipher runs"
   if tHasCipher is true then
      -- The upstream primitive shipped (SodiumXT ABI 10, 2026-08-23): the
      -- official vector must round-trip. Compared through nxHexEncode on
      -- BOTH sides, because `is` folds case and base64 is case-significant -
      -- these two lines are the assertions that certify NIP-44 on an engine,
      -- so they enforce exactly what their labels claim (member rule 2).
      put nxNip44Decrypt(kNxVecN44Sec1, kNxVecN44Pub2, kNxVecN44Payload) into tOut
      nxtCheck nxHexEncode(tOut) is nxHexEncode("a"), "the official encrypt_decrypt vector decrypts"
      put nxNip44Encrypt(kNxVecN44Sec1, kNxVecN44Pub2, "a", kNxVecN44Nonce) into tOut
      nxtCheck nxHexEncode(tOut) is nxHexEncode(kNxVecN44Payload), "and re-encrypts byte-identically"
   else
      -- The pre-ABI-10 install: the MAC verifies, then the cipher fails
      -- CLOSED with the capability error naming the upstream primitive.
      put nxNip44Decrypt(kNxVecN44Sec1, kNxVecN44Pub2, kNxVecN44Payload) into tOut
      nxtCheck tOut is empty, "the untampered vector reaches the cipher and fails closed"
      nxtCheck nxLastError() contains "sxChaCha20IetfXor", "naming the primitive absent from the installed SodiumXT"
      nxtCheck nxNip44Encrypt(kNxVecN44Sec1, kNxVecN44Pub2, "a", kNxVecN44Nonce) is empty, "encrypt fails closed the same way"
   end if
end nxtTestNip44Seam

-- ==========================================================================
-- 12. Filters: building and client-side matching (no crypto).
-- ==========================================================================

private command nxtTestFilters
   local tFilter, tJson, tEvent, tEmptyFilter
   nxtSection "NIP-01 filters"
   put kNxVecTagPubkey into tFilter["authors"]
   put "1,7" into tFilter["kinds"]
   put 1600000000 into tFilter["since"]
   put 25 into tFilter["limit"]
   put kNxVecTagEventId into tFilter["#e"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck tJson is not empty, "nxFilterBuild builds"
   nxtCheck nxJsonType(tJson, empty) is "object", "the filter is a JSON object"
   nxtCheck nxJsonGet(tJson, "authors/1") is kNxVecTagPubkey, "authors carry through"
   nxtCheck nxJsonCount(tJson, "kinds") is 2, "both kinds carry through"
   nxtCheck nxJsonGet(tJson, "kinds/2") is "7", "as numbers"
   nxtCheck nxJsonGet(tJson, "since") is "1600000000", "since carries through"
   nxtCheck nxJsonGet(tJson, "#e/1") is kNxVecTagEventId, "tag filters carry through"
   put "not hex" into tEmptyFilter["authors"]
   nxtCheck nxFilterBuild(tEmptyFilter) is empty, "a non-hex author refuses"
   -- matching: the fixture event (id set by hand; matching is pure string
   -- and integer work, so this section runs without CoinXT)
   put nxtEventA() into tEvent
   put kNxVecIdA into tEvent["id"]
   nxtCheck nxFilterMatches(tJson, tEvent) is false, "the fixture fails this filter (wrong author)"
   put empty into tFilter
   put kNxVecPubkey into tFilter["authors"]
   put "1" into tFilter["kinds"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is true, "author + kind match"
   put empty into tFilter
   put kNxVecIdA into tFilter["ids"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is true, "an exact id matches"
   put empty into tFilter
   put kNxVecIdB into tFilter["ids"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is false, "a different id does not"
   put empty into tFilter
   put 1700000000 into tFilter["since"]
   put 1700000000 into tFilter["until"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is true, "since and until are inclusive at the boundary"
   put empty into tFilter
   put 1700000001 into tFilter["since"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is false, "since excludes older events"
   put empty into tFilter
   put kNxVecTagEventId into tFilter["#e"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is true, "a tag-value intersection matches"
   put empty into tFilter
   put kNxVecIdB into tFilter["#e"]
   put nxFilterBuild(tFilter) into tJson
   nxtCheck nxFilterMatches(tJson, tEvent) is false, "no intersection, no match"
end nxtTestFilters

-- ==========================================================================
-- 13. Client and relay wire messages.
-- ==========================================================================

private command nxtTestRelayMessages
   local tEvent, tWire, tParsed, tFilterJson, tLongId, tI
   nxtSection "client and relay messages"
   put "{" & quote & "kinds" & quote & ":[1]}" into tFilterJson
   put nxClientReq("sub1", tFilterJson) into tWire
   nxtCheck tWire is "[" & quote & "REQ" & quote & "," & quote & "sub1" & quote & "," & tFilterJson & "]", "REQ assembles"
   nxtCheck nxClientReq(empty, tFilterJson) is empty, "an empty subscription id refuses"
   put empty into tLongId
   repeat with tI = 1 to 65
      put "x" after tLongId
   end repeat
   nxtCheck nxClientReq(tLongId, tFilterJson) is empty, "a 65-character subscription id refuses"
   nxtCheck nxClientReq("sub1", "[1,2]") is empty, "a non-object filter refuses"
   nxtCheck nxClientClose("sub1") is "[" & quote & "CLOSE" & quote & "," & quote & "sub1" & quote & "]", "CLOSE assembles"
   put nxtEventA() into tEvent
   nxtCheck nxClientEvent(tEvent) is empty, "an unsigned event refuses to publish"
   put kNxVecIdA into tEvent["id"]
   put kNxVecSigA into tEvent["sig"]
   put nxClientEvent(tEvent) into tWire
   nxtCheck tWire begins with "[" & quote & "EVENT" & quote & ",{", "EVENT assembles around the object"
   nxtCheck nxClientAuth(tEvent) is empty, "nxClientAuth refuses a non-22242 event"
   -- relay-to-client parsing
   put "[" & quote & "EVENT" & quote & "," & quote & "sub1" & quote & ", {" & quote & "kind" & quote & ": 1} ]" into tWire
   put nxRelayParse(tWire) into tParsed
   nxtCheck tParsed["type"] is "EVENT", "EVENT parses"
   nxtCheck tParsed["subId"] is "sub1", "with its subscription id"
   nxtCheck tParsed["eventJson"] is "{" & quote & "kind" & quote & ": 1}", "and the VERBATIM object slice, whitespace intact"
   put "[" & quote & "OK" & quote & "," & quote & kNxVecIdA & quote & ",false," & quote & "pow: too low" & quote & "]" into tWire
   put nxRelayParse(tWire) into tParsed
   nxtCheck tParsed["type"] is "OK", "OK parses"
   nxtCheck tParsed["accepted"] is "false", "with its verdict"
   nxtCheck tParsed["reason"] is "pow: too low", "and its reason"
   put nxRelayParse("[" & quote & "EOSE" & quote & "," & quote & "sub1" & quote & "]") into tParsed
   nxtCheck tParsed["type"] is "EOSE", "EOSE parses"
   put nxRelayParse("[" & quote & "CLOSED" & quote & "," & quote & "sub1" & quote & "," & quote & "why" & quote & "]") into tParsed
   nxtCheck tParsed["reason"] is "why", "CLOSED carries its reason"
   put nxRelayParse("[" & quote & "NOTICE" & quote & "," & quote & "hello" & quote & "]") into tParsed
   nxtCheck tParsed["notice"] is "hello", "NOTICE carries its text"
   put nxRelayParse("[" & quote & "AUTH" & quote & "," & quote & "challenge-text" & quote & "]") into tParsed
   nxtCheck tParsed["challenge"] is "challenge-text", "AUTH carries its challenge"
   put nxRelayParse("[" & quote & "event" & quote & "," & quote & "s" & quote & ",{}]") into tParsed
   nxtCheck tParsed["type"] is "unknown", "a lowercase message type is NOT NIP-01 (byte-exact types)"
   nxtCheck nxRelayParse("{}") is empty, "a non-array message refuses"
   nxtCheck nxRelayParse("[" & quote & "EVENT" & quote & "]") is empty, "a truncated EVENT refuses"
end nxtTestRelayMessages

-- ==========================================================================
-- 14. The websocket pure half.
-- ==========================================================================

private command nxtTestWsPure
   local tParsed, tRequest, tFrame, tDecoded, tBuffer
   nxtSection "websocket helpers (RFC 6455, pure half)"
   put nxWsUrlParse("ws://relay.example.com") into tParsed
   nxtCheck tParsed["host"] is "relay.example.com", "ws url: host"
   nxtCheck tParsed["port"] is 80, "ws url: default port 80"
   nxtCheck tParsed["path"] is "/", "ws url: default path /"
   nxtCheck tParsed["secure"] is false, "ws url: not secure"
   put nxWsUrlParse("wss://r.io:7443/sub/path?x=1") into tParsed
   nxtCheck tParsed["port"] is 7443, "wss url: explicit port"
   nxtCheck tParsed["path"] is "/sub/path?x=1", "wss url: path with query"
   nxtCheck tParsed["secure"] is true, "wss url: secure flag"
   nxtCheck nxWsUrlParse("http://x.io") is empty, "an http url refuses"
   nxtCheck nxWsUrlParse("ws://") is empty, "an empty host refuses"
   nxtCheck nxWsUrlParse("ws://h:99999") is empty, "an out-of-range port refuses"
   nxtCheck nxWsUrlParse("ws://a b") is empty, "whitespace refuses"
   put nxWsHandshakeRequest("r.io", 80, "/", kNxVecWsKey, false) into tRequest
   nxtCheck tRequest begins with "GET / HTTP/1.1", "the request line"
   nxtCheck tRequest contains "Host: r.io" & numToChar(13), "the scheme's default port stays out of Host"
   nxtCheck tRequest contains "Sec-WebSocket-Version: 13", "protocol version 13"
   put nxWsHandshakeRequest("r.io", 7443, "/", kNxVecWsKey, false) into tRequest
   nxtCheck tRequest contains "Host: r.io:7443", "a non-default port joins Host"
   put nxWsHandshakeRequest("r.io", 443, "/", kNxVecWsKey, false) into tRequest
   nxtCheck tRequest contains "Host: r.io:443", "443 is NOT ws://'s default: it stays in Host (RFC 6455 4.1 is per scheme)"
   put nxWsHandshakeRequest("r.io", 443, "/", kNxVecWsKey, true) into tRequest
   nxtCheck tRequest contains "Host: r.io" & numToChar(13), "and IS wss://'s default, so there it comes out"
   nxtCheck nxWsAcceptFor(kNxVecWsKey) is kNxVecWsAccept, "the accept derivation matches the sample"
   -- frames
   put nxWsFrameEncode(1, textEncode("Hello", "UTF-8"), kNxVecWsMask) into tFrame
   nxtCheck nxHexEncode(tFrame) is kNxVecWsFrameHello, "the masked Hello frame is byte-exact"
   put nxWsFrameDecode(tFrame) into tDecoded
   nxtCheck tDecoded["complete"] is true, "and decodes"
   nxtCheck tDecoded["opcode"] is 1, "as a text frame"
   nxtCheck textDecode(tDecoded["payload"], "UTF-8") is "Hello", "unmasked back to Hello"
   nxtCheck tDecoded["consumed"] is 11, "consuming exactly its bytes"
   -- a server-style unmasked frame, built by hand: 81 05 Hello
   put nxHexDecode("810548656c6c6f") into tBuffer
   put nxWsFrameDecode(tBuffer) into tDecoded
   nxtCheck tDecoded["complete"] is true and tDecoded["masked"] is false, "an unmasked server frame decodes"
   -- 16-bit extended length round trip (a 300-byte binary payload)
   local tBig, tI
   put empty into tBig
   repeat with tI = 1 to 300
      put numToByte(nxLoopByte(tI)) after tBig
   end repeat
   put nxWsFrameEncode(2, tBig, kNxVecWsMask) into tFrame
   nxtCheck byteToNum(byte 2 of tFrame) is 254, "a 300-byte frame uses the 126 length marker, masked"
   nxtCheck byteToNum(byte 3 of tFrame) * 256 + byteToNum(byte 4 of tFrame) is 300, "with a big-endian 16-bit length"
   put nxWsFrameDecode(tFrame) into tDecoded
   nxtCheck tDecoded["complete"] is true and the number of bytes of tDecoded["payload"] is 300, "and decodes whole"
   nxtCheck nxHexEncode(tDecoded["payload"]) is nxHexEncode(tBig), "payload survives the mask round trip"
   put nxWsFrameDecode(nxHexDecode("88831122")) into tDecoded
   nxtCheck tDecoded["complete"] is false and tDecoded["error"] is empty, "a truncated frame asks for more"
   -- refusals
   put nxWsFrameDecode(nxHexDecode("c1050000000000")) into tDecoded
   nxtCheck tDecoded["error"] is not empty, "reserved bits refuse"
   put nxWsFrameDecode(nxHexDecode("887f00000000ffffffff")) into tDecoded
   nxtCheck tDecoded["error"] is not empty, "a hostile 64-bit length refuses"
   nxtCheck nxWsFrameEncode(1, empty, "zz") is empty, "a malformed mask refuses"
   nxtCheck nxWsFrameEncode(99, empty, kNxVecWsMask) is empty, "an out-of-range opcode refuses"
end nxtTestWsPure

-- ==========================================================================
-- 15. The convenience builders.
-- ==========================================================================

private command nxtTestBuilders
   local tEvent, tParent, tReply, tMeta, tListText, tBack
   nxtSection "event builders"
   put nxMetadataBuild("alice", "about text", "https://x/y.png", 1700000000) into tEvent
   nxtCheck tEvent["kind"] is 0, "metadata is kind 0"
   put nxMetadataParse(tEvent) into tMeta
   nxtCheck tMeta["name"] is "alice", "metadata round-trips the name"
   nxtCheck tMeta["about"] is "about text", "and the about"
   nxtCheck nxMetadataParse(nxtEventA()) is empty, "nxMetadataParse refuses a kind 1 event"
   -- reply threading (NIP-10 marked tags)
   put nxtEventA() into tParent
   put kNxVecIdA into tParent["id"]
   put nxReplyBuild(tParent, "a direct reply", 1700000100) into tReply
   nxtCheck nxTagFirst(tReply, "e") is kNxVecIdA, "a parent with no root becomes the root"
   nxtCheck nxTagValues(tReply, "p") is kNxVecPubkey & return & kNxVecTagPubkey, "reply p tags: author first, thread p kept, deduplicated"
   put "e" & tab & kNxVecIdB & tab & empty & tab & "root" into tListText
   put nxTagsFromText(tListText) into tParent["tags"]
   put nxReplyBuild(tParent, "deeper", 1700000101) into tReply
   nxtCheck nxTagFirst(tReply, "e") is kNxVecIdB, "a parent with a root tag threads under that root"
   nxtCheck nxTagValues(tReply, "e") is kNxVecIdB & return & kNxVecIdA, "root first, then the reply marker on the parent"
   -- reaction
   put nxReactionBuild(tParent, empty, 1700000102) into tEvent
   nxtCheck tEvent["kind"] is 7 and tEvent["content"] is "+", "a reaction defaults to +"
   nxtCheck nxTagFirst(tEvent, "k") is "1", "and carries the target kind as a k tag"
   -- deletion
   put nxDeleteBuild(kNxVecIdA & return & kNxVecIdB, "mistake", 1700000103) into tEvent
   nxtCheck nxTagValues(tEvent, "e") is kNxVecIdA & return & kNxVecIdB, "a deletion tags every id"
   nxtCheck nxDeleteBuild("nothex", empty, empty) is empty, "a malformed id refuses"
   -- contacts
   put nxContactsBuild(kNxVecPubkey & return & kNxVecTagPubkey, 1700000104) into tEvent
   nxtCheck tEvent["kind"] is 3, "contacts are kind 3"
   nxtCheck nxContactsParse(tEvent) is kNxVecPubkey & return & kNxVecTagPubkey, "and round-trip"
   -- relay list
   put nxRelayListBuild("wss://a.io" & return & "wss://b.io" & tab & "read", 1700000105) into tEvent
   nxtCheck tEvent["kind"] is 10002, "a relay list is kind 10002"
   put nxRelayListParse(tEvent) into tBack
   nxtCheck tBack is "wss://a.io" & return & "wss://b.io" & tab & "read", "and round-trips markers"
   nxtCheck nxRelayListBuild("wss://a.io" & tab & "both", empty) is empty, "a foreign marker refuses"
   -- auth
   put nxAuthBuild("wss://relay.example.com", "challenge-string", 1700000106) into tEvent
   nxtCheck tEvent["kind"] is 22242, "an auth event is kind 22242"
   nxtCheck nxTagFirst(tEvent, "relay") is "wss://relay.example.com", "with its relay tag"
   nxtCheck nxTagFirst(tEvent, "challenge") is "challenge-string", "and its challenge tag"
   nxtCheck nxAuthBuild(empty, "c", empty) is empty, "a missing relay url refuses"
end nxtTestBuilders

-- ==========================================================================
-- 16. Proof of work, NIP-05, NIP-11.
-- ==========================================================================

private command nxtTestPowAndDiscovery
   local tEvent, tBody, tInfo
   nxtSection "proof of work and discovery"
   nxtCheck nxPowDifficulty(kNxVecPowId) is 36, "the published NIP-13 example scores 36 bits"
   nxtCheck nxPowDifficulty("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") is 0, "an all-f id scores 0"
   nxtCheck nxPowDifficulty("nothex") is empty, "a malformed id refuses"
   put nxtEventA() into tEvent
   put kNxVecPowId into tEvent["id"]
   nxtCheck nxPowCheck(tEvent, 36) is true, "36 bits meets a 36-bit floor"
   nxtCheck nxPowCheck(tEvent, 37) is false, "but not 37"
   put "nonce" into tEvent["tags"][3][1]
   put "776797" into tEvent["tags"][3][2]
   put "20" into tEvent["tags"][3][3]
   nxtCheck nxPowCheck(tEvent, 30) is false, "a committed target below the floor refuses (NIP-13's lucky-miner rule)"
   put "40" into tEvent["tags"][3][3]
   nxtCheck nxPowCheck(tEvent, 30) is true, "a committed target at or above the floor passes"
   -- NIP-05
   nxtCheck nxNip05Url("bob@example.com") is "https://example.com/.well-known/nostr.json?name=bob", "a name@domain identifier"
   nxtCheck nxNip05Url("example.com") is "https://example.com/.well-known/nostr.json?name=_", "a bare domain maps to _"
   nxtCheck nxNip05Url("a@b@") is empty, "a malformed identifier refuses"
   put "{" & quote & "names" & quote & ":{" & quote & "bob" & quote & ":" & quote & kNxVecPubkey & quote & "}}" into tBody
   nxtCheck nxNip05Verify(tBody, "bob", kNxVecPubkey) is true, "a matching nostr.json verifies"
   nxtCheck nxNip05Verify(tBody, "bob", kNxVecTagPubkey) is false, "a different pubkey does not"
   nxtCheck nxNip05Verify(tBody, "alice", kNxVecPubkey) is false, "an absent name does not"
   -- NIP-11
   put "{" & quote & "name" & quote & ":" & quote & "test relay" & quote & "," & quote & "supported_nips" & quote & ":[1,11,42]}" into tBody
   put nxRelayInfoParse(tBody) into tInfo
   nxtCheck tInfo["name"] is "test relay", "NIP-11: the name field"
   nxtCheck tInfo["supportedNips"] is "1,11,42", "NIP-11: supported nips as a comma list"
   nxtCheck nxRelayInfoParse("[]") is empty, "NIP-11: a non-object refuses"
end nxtTestPowAndDiscovery

-- ==========================================================================
-- 17. The relay layer, offline: fail-closed refusals and clean misses. The
-- nxr* layer is probed (it is deliberately absent from the suite paste);
-- nothing here opens a socket - the live legs are the demo's and the
-- runbook's. CAUTION: nxrShutdown REALLY runs (idempotency is the test).
-- ==========================================================================

private function nxLoopByte pIndex
   -- A deterministic non-repeating-ish byte for bulk payload fixtures.
   local tValue
   put pIndex * 37 + 11 into tValue
   return tValue - 256 * trunc(tValue / 256)
end nxLoopByte

private command nxtTestRelayLayerOffline
   local tError, tHaveRelay, tVersionText
   nxtSection "relay layer, offline paths"
   put false into tHaveRelay
   try
      put nxrVersion() into tVersionText
      put true into tHaveRelay
   catch tError
      put false into tHaveRelay
   end try
   if tHaveRelay is not true then
      nxtSkip "the nxr* relay layer is not loaded (it is deliberately not in the suite paste)"
      nxtSkip "open the demo, or start using stack nostr-relay, to run this section"
      exit nxtTestRelayLayerOffline
   end if
   nxtCheck tVersionText begins with "NostrXT relay", "nxrVersion reports the layer"
   -- wiring: preserve whatever owner the surrounding app configured (the
   -- onionxt configuration-setters lesson: a test must not unconfigure the
   -- app it ships inside). Inside the demo, `me` IS the demo stack.
   nxrInit the long id of me
   nxtCheck the result is empty, "nxrInit accepts an owner"
   -- THE EMBEDDABLE SOCKET SPLIT (2026-08-24). nxrSocketError /
   -- nxrSocketClosed / nxrSocketTimeout carry what the three engine socket
   -- messages used to do inline, and answer one question: was that socket
   -- MINE, and did I handle it? An embedding app calls them where it would
   -- otherwise `pass`, so "false for a socket that is not ours" is not a
   -- detail - it IS the contract that keeps a co-embedded library's events
   -- flowing, and getting it wrong is a SILENT HANG rather than an error.
   -- Pinned offline with a socket id no relay owns; the true legs need a
   -- live relay and ride the live pass.
   nxtCheck nxrSocketError(999999, "boom") is false, \
         "nxrSocketError disowns a socket that is not ours"
   nxtCheck nxrSocketClosed(999999) is false, \
         "nxrSocketClosed disowns a socket that is not ours"
   nxtCheck nxrSocketTimeout(999999) is false, \
         "nxrSocketTimeout disowns a socket that is not ours"
   -- unknown handles are clean errors or clean no-ops, never crashes
   nxtCheck nxrState(999999) is "unknown", "an unknown handle has unknown state"
   nxtCheck nxrUrl(999999) is empty, "and no url"
   nxtCheck nxrChallenge(999999) is empty, "and no challenge"
   nxrSetCallback 999999, "onRelay"
   nxtCheck the result begins with "NostrXT relay:", "nxrSetCallback refuses an unknown handle"
   nxrSetVerify 999999, false
   nxtCheck the result begins with "NostrXT relay:", "nxrSetVerify refuses an unknown handle"
   nxrSubscribe 999999, "sub1", "{" & quote & "kinds" & quote & ":[1]}"
   nxtCheck the result begins with "NostrXT relay:", "nxrSubscribe refuses an unknown handle"
   nxrUnsubscribe 999999, "sub1"
   nxtCheck the result begins with "NostrXT relay:", "nxrUnsubscribe refuses an unknown handle"
   nxrPublish 999999, nxtEventA()
   nxtCheck the result begins with "NostrXT relay:", "nxrPublish refuses (unsigned event, unknown handle)"
   nxrAuth 999999, nxtEventA()
   nxtCheck the result begins with "NostrXT relay:", "nxrAuth refuses a non-auth event"
   nxrSendRaw 999999, "[]"
   nxtCheck the result begins with "NostrXT relay:", "nxrSendRaw refuses an unknown handle"
   nxrPing 999999
   nxtCheck the result begins with "NostrXT relay:", "nxrPing refuses an unknown handle"
   -- connect refusals (no socket is opened on a refused url)
   nxrConnect "http://not-a-relay.example"
   nxtCheck the result begins with "NostrXT relay:", "nxrConnect refuses a non-ws url"
   nxrConnect empty
   nxtCheck the result begins with "NostrXT relay:", "nxrConnect refuses an empty url"
   -- engine-armed callbacks with stale ids are clean misses
   nxrWsOpened "203.0.113.9:443|nxr-stale"
   nxtCheck true, "a stale socket id into nxrWsOpened is a clean miss"
   nxrWsData "203.0.113.9:443|nxr-stale", numToByte(0)
   nxtCheck true, "a stale socket id into nxrWsData is a clean miss"
   nxrDeadline 999999
   nxtCheck true, "a stale handle into nxrDeadline is a clean miss"
   nxrDisconnect 999999
   nxtCheck true, "a stale handle into nxrDisconnect is a clean no-op"
   -- teardown is idempotent (CAUTION: really closes any open relays)
   nxrShutdown
   nxrShutdown
   nxtCheck true, "nxrShutdown twice is safe"
   nxtCheck nxrOpenRelays() is empty, "no relays remain after shutdown"
end nxtTestRelayLayerOffline

-- <<< END EMBEDDED LIBRARIES <<<

-- ==========================================================================
-- Demo constants and state.
-- ==========================================================================

-- Bumped whenever the generated UI changes so a saved stack rebuilds.
constant kNdUiVersion = "nostrdemo-kit2-1"
constant kNdWinW = 980
constant kNdWinH = 620

local sNdRelay               -- the open relay handle, or empty
local sNdSeckey              -- the session secret key (hex), or empty
local sNdHaveCoin            -- capability flags from the boot probe
local sNdHaveSodium

-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====
-- The family look as one carried block: the kit owns colors, chrome, and
-- control construction; the adopting demo owns layout (explicit rects) and
-- logic. Builders are idempotent (create-if-missing), so a rebuild on
-- reopen is safe. Do not edit this block in place: change the master and
-- re-carry it.
constant kUiBg = "240,242,246"
constant kUiCard = "255,255,255"
constant kUiCardLine = "225,229,236"
constant kUiAccent = "44,90,160"
constant kUiAccentText = "255,255,255"
constant kUiAccentSub = "199,216,241"
constant kUiInk = "28,34,46"
constant kUiInkSoft = "95,104,118"
constant kUiMuted = "138,146,158"
constant kUiOk = "23,128,63"
constant kUiWarn = "150,110,40"
constant kUiBad = "176,58,46"
constant kUiFieldLine = "203,210,222"
constant kUiCodeBg = "244,246,250"
constant kUiCodeLine = "210,217,229"

-- The platform's own terminal face for codes, keys, tables and logs, so
-- the monospace surfaces look native instead of typewriter-Courier. A
-- missing face substitutes the engine default - a soft, safe failure.
function uiMonoFont
   if the platform is "MacOS" then
      return "Menlo"
   else if the platform is "Win32" then
      return "Consolas"
   end if
   return "DejaVu Sans Mono"
end uiMonoFont

-- The window chrome every adopter shares: stack size, page ground, the
-- title band, and the one status line under it (write it with uiStatus).
-- pBandH is optional (default 30); a taller band leaves room for an
-- adopter's tagline or status pill, placed by the adopter.
command uiChrome pTitle, pWidth, pHeight, pBandH
   local tFH
   if pBandH is empty then
      put 30 into pBandH
   end if
   set the width of this stack to pWidth
   set the height of this stack to pHeight
   set the backgroundColor of this card to kUiBg
   set the title of this stack to pTitle
   uiGfx "uiBand", "0,0," & pWidth & "," & pBandH
   set the style of graphic "uiBand" to "rectangle"
   set the filled of graphic "uiBand" to true
   set the backgroundColor of graphic "uiBand" to kUiAccent
   set the lineSize of graphic "uiBand" to 0
   uiLabel "uiTitle", "  " & pTitle, "0,0," & pWidth & "," & pBandH, 15
   set the foregroundColor of field "uiTitle" to kUiAccentText
   set the textStyle of field "uiTitle" to "bold"
   -- center the title on the band midline by MEASURED height (never guess
   -- font metrics - the family's OXT passes clipped hand-sized labels)
   put the formattedHeight of field "uiTitle" into tFH
   if tFH > 0 and tFH < pBandH then
      set the height of field "uiTitle" to tFH
      set the top of field "uiTitle" to ((pBandH - tFH) div 2)
   end if
   uiLabel "uiStatus", empty, "16," & (pBandH + 4) & "," & (pWidth - 16) & "," & (pBandH + 22), 11
end uiChrome

-- The status line, colored by what it reports: "ok", "warn", "bad", or
-- anything else for neutral/muted. Demos route probe results through this
-- so a stack that cannot run says so in red, at the top, immediately.
command uiStatus pText, pKind
   -- PIN THE STACK, THEN CHECK THE FIELD EXISTS. Both halves were missing and
   -- both are load-bearing on a TIMER-driven call.
   --
   -- An unqualified `field "uiStatus"` resolves against the DEFAULTSTACK, not
   -- against the stack whose script is running. Inside openStack those are the
   -- same thing, which is why every demo's startup status line always worked.
   -- A handler arriving from `send ... in` has no such guarantee: with a second
   -- stack in front, the write lands in the wrong stack or resolves to nothing.
   --
   -- THE PIN RESTS ON THE DOCUMENTED RESOLUTION RULE, NOT ON A THROW WE SAW.
   -- This comment used to cite enet-lan-chat's once-a-second dashboard throwing
   -- "Chunk: error in object expression" REPEATEDLY on 2026-08-18, and dht-chat
   -- hiding the same fault behind a guard. Neither half held up: that throw was
   -- the ARGUMENT at the call site (`the number of keys of sPeers`, which does
   -- not parse - OXT-ENGINE-NOTES 1.7) and never reached uiStatus at all, and
   -- the guard credited to the kit was dht-chat's own wxSetStatus wrapper - the
   -- master had no existence check until the same commit that added this pin.
   -- What a guarded call site WOULD do if the defaultStack diverged is fail
   -- silently, which is the argument for a gate rather than for more guards.
   -- See OXT-ENGINE-NOTES 5.3, now classed DOCUMENTED.
   --
   -- The pin is holde-em's idiom, engine-proven there, and its comment names
   -- this exact hazard. The existence check stays as well: a demo may call the
   -- status line before its chrome is built, and a cosmetic line must never
   -- take down a poll chain.
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      exit uiStatus
   end if
   put pText into field "uiStatus"
   if pKind is "ok" then
      set the foregroundColor of field "uiStatus" to kUiOk
   else if pKind is "warn" then
      set the foregroundColor of field "uiStatus" to kUiWarn
   else if pKind is "bad" then
      set the foregroundColor of field "uiStatus" to kUiBad
   else
      set the foregroundColor of field "uiStatus" to kUiInkSoft
   end if
end uiStatus

-- A static caption at a FIXED rect (idempotent, borderless, transparent).
-- Use uiWrap instead when the text may wrap or the exact height matters.
command uiLabel pName, pText, pRect, pSize
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the threeD of field pName to false
   set the textSize of field pName to pSize
   set the foregroundColor of field pName to kUiInk
   put pText into field pName
end uiLabel

-- A caption FIT to its measured text height (top pinned). The fit does
-- double duty: it prevents clipping (hand-sized rects clipped text on a
-- real Windows pass), and it makes `the height of field` equal the TEXT
-- height, which midline centering relies on. GUARD: only resize on a sane
-- measurement - a 0/blank formattedHeight (possible before the window is
-- fully realized) would collapse the label. Empty labels are skipped
-- (they receive their text later).
command uiWrap pName, pText, pRect, pSize
   local tOldDelim, tTop, tFH
   uiLabel pName, pText, pRect, pSize
   if pText is not empty then
      put the itemDelimiter into tOldDelim
      set the itemDelimiter to comma
      put item 2 of pRect into tTop
      set the itemDelimiter to tOldDelim
      put the formattedHeight of field pName into tFH
      if tFH > 0 then
         set the height of field pName to tFH
         set the top of field pName to tTop
      end if
   end if
end uiWrap

-- A small, muted caption (hints, toggle descriptions, empty states).
command uiCap pName, pText, pRect
   uiWrap pName, pText, pRect, 10
   set the foregroundColor of field pName to kUiMuted
end uiCap

-- A numbered bold section header with a hairline divider placed below the
-- label's ACTUAL (fit-to-text) bottom, so it tracks the real header
-- height on any platform's line metrics.
command uiSection pName, pText, pRect
   local tOldDelim, tL, tR, tB
   uiWrap pName, pText, pRect, 13
   set the textStyle of field pName to "bold"
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 1 of pRect into tL
   put item 3 of pRect into tR
   set the itemDelimiter to tOldDelim
   put the bottom of field pName into tB
   uiGfx (pName & "Line"), (tL & comma & (tB + 1) & comma & tR & comma & (tB + 2))
   set the style of graphic (pName & "Line") to "rectangle"
   set the filled of graphic (pName & "Line") to true
   set the backgroundColor of graphic (pName & "Line") to kUiCardLine
   set the lineSize of graphic (pName & "Line") to 0
end uiSection

-- A one-line entry field, mono and flat ("modern input" chrome instead of
-- the engine's sunken-3D default), because hex, addresses and paths are
-- what this suite's demos edit.
command uiInput pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to false
   set the traversalOn of field pName to true
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiFieldLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   -- 4-item margins form ONLY: OXT ignored the single-number form on a
   -- real engine pass
   set the margins of field pName to "6,6,6,6"
   set the textSize of field pName to 11
   set the textFont of field pName to uiMonoFont()
end uiInput

-- A read-only output/log area: mono, flat, scrolling, hairline-bordered.
command uiArea pName, pRect
   if there is no field pName then
      create field
      set the name of the last field to pName
   end if
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 1
   set the borderColor of field pName to kUiCardLine
   set the opaque of field pName to true
   set the backgroundColor of field pName to kUiCard
   set the margins of field pName to "6,6,6,6"
   set the vScrollbar of field pName to true
   set the textSize of field pName to 10
   set the textFont of field pName to uiMonoFont()
end uiArea

-- A row-selectable table: uiArea plus list behavior and tab stops
-- ("230,340"-style comma lists). Pair it with a uiLabel header carrying
-- the same tabStops, set by the adopter.
command uiTable pName, pRect, pTabStops
   uiArea pName, pRect
   set the listBehavior of field pName to true
   if pTabStops is not empty then
      set the tabStops of field pName to pTabStops
   end if
end uiTable

command uiButton pName, pLabel, pRect
   if there is no button pName then
      create button
      set the name of the last button to pName
   end if
   set the rect of button pName to pRect
   set the label of button pName to pLabel
end uiButton

-- A script-managed checkbox: autoHilite OFF because the family drives
-- toggle state from script locals (a mode the environment cannot honour
-- must never stay silently armed - the quickshare pill lesson), so the
-- hilite is set explicitly by the adopter's state machine.
command uiCheckbox pName, pLabel, pRect
   uiButton pName, pLabel, pRect
   set the style of button pName to "checkbox"
   set the autoHilite of button pName to false
end uiCheckbox

-- Create-or-reuse a named graphic: the chrome layer (cards, pills,
-- dividers, drop targets). Created BEFORE the controls that sit on it, so
-- it stays behind them in z-order. roundRect + antialiased by default;
-- callers restyle.
command uiGfx pName, pRect
   if there is no graphic pName then
      create graphic
      set the name of the last graphic to pName
   end if
   set the rect of graphic pName to pRect
   set the style of graphic pName to "roundRect"
   set the antialiased of graphic pName to true
end uiGfx

-- A dashboard card: a rounded, hairline-bordered, softly shadowed panel
-- placed BEHIND a group of controls. It only groups visually; clicks on
-- it fall through to the adopter's `default: pass mouseUp`.
command uiPanel pName, pRect
   local tShadow, tErr
   uiGfx pName, pRect
   set the roundRadius of graphic pName to 14
   set the filled of graphic pName to true
   set the backgroundColor of graphic pName to kUiCard
   set the lineSize of graphic pName to 1
   -- a graphic strokes its outline in the foregroundColor; borderColor is
   -- set too so whichever the engine honours, the hairline lands
   set the foregroundColor of graphic pName to kUiCardLine
   set the borderColor of graphic pName to kUiCardLine
   -- soft drop shadow is an LC-9-era feature, so it is a PURE
   -- enhancement: an engine without it just skips it (the try) and the
   -- hairline still separates the card from the page
   try
      put "90,98,114" into tShadow["color"]
      put 30 into tShadow["opacity"]
      put 10 into tShadow["size"]
      put 0 into tShadow["spread"]
      put 2 into tShadow["distance"]
      put 90 into tShadow["angle"]
      set the dropShadow of graphic pName to tShadow
   catch tErr
   end try
end uiPanel

-- A status pill: rounded chip + centered label, colored by state kind -
-- "ok" green, "wait" amber, "bad" red, anything else the muted on-band
-- blue. The adopter repaints it from ONE place so its handlers cannot
-- disagree about the colors (the nocloud Tor-pill discipline).
command uiPill pName, pText, pRect, pKind
   local tOldDelim, tTop, tBot, tFH
   put the itemDelimiter into tOldDelim
   set the itemDelimiter to comma
   put item 2 of pRect into tTop
   put item 4 of pRect into tBot
   set the itemDelimiter to tOldDelim
   uiGfx (pName & "Bg"), pRect
   set the roundRadius of graphic (pName & "Bg") to (tBot - tTop)
   set the filled of graphic (pName & "Bg") to true
   set the lineSize of graphic (pName & "Bg") to 0
   if pKind is "ok" then
      set the backgroundColor of graphic (pName & "Bg") to "205,240,214"
   else if pKind is "wait" then
      set the backgroundColor of graphic (pName & "Bg") to "250,240,199"
   else if pKind is "bad" then
      set the backgroundColor of graphic (pName & "Bg") to "243,215,213"
   else
      set the backgroundColor of graphic (pName & "Bg") to "31,64,116"
   end if
   uiLabel pName, pText, pRect, 10
   set the textAlign of field pName to "center"
   if pKind is "ok" then
      set the foregroundColor of field pName to "22,101,52"
   else if pKind is "wait" then
      set the foregroundColor of field pName to "133,98,14"
   else if pKind is "bad" then
      set the foregroundColor of field pName to "135,44,38"
   else
      set the foregroundColor of field pName to kUiAccentSub
   end if
   -- center the label on the chip midline by measured height
   put the formattedHeight of field pName into tFH
   if tFH > 0 and tFH < (tBot - tTop) then
      set the height of field pName to tFH
      set the top of field pName to (tTop + ((tBot - tTop - tFH) div 2))
   end if
end uiPill

-- Click-to-copy feedback: flash the button's label to "Copied!" for
-- 1200 ms, then restore the real label (stashed in uRealLabel).
command uiCopyFlash pBtn
   if there is no button pBtn then
      exit uiCopyFlash
   end if
   if the uRealLabel of button pBtn is empty then
      set the uRealLabel of button pBtn to the label of button pBtn
   end if
   set the label of button pBtn to "Copied!"
   send ("uiCopyFlashReset" && quote & pBtn & quote) to me in 1200 milliseconds
end uiCopyFlash

command uiCopyFlashReset pBtn
   -- Pinned for the same reason uiStatus is: this one arrives 1200ms later by
   -- `send`, so the defaultStack is whatever is current THEN, not the stack
   -- that flashed the button. Its existence guard means the failure is silent
   -- rather than loud - the label just never comes back, or comes back on
   -- another stack's button - which is why it needed finding rather than
   -- reporting itself.
   set the defaultStack to the short name of this stack
   if there is no button pBtn then
      exit uiCopyFlashReset
   end if
   if the uRealLabel of button pBtn is not empty then
      set the label of button pBtn to the uRealLabel of button pBtn
   end if
end uiCopyFlashReset

-- The honesty/custody footer every demo carries: what the stack is, what
-- it is not, and its engine-evidence state.
command uiFooter pText, pRect
   uiWrap "uiFooter", pText, pRect, 11
   set the textStyle of field "uiFooter" to "italic"
   set the foregroundColor of field "uiFooter" to kUiMuted
end uiFooter
-- ==== SUITE UI KIT v2 END ====

-- ==========================================================================
-- Lifecycle. The self-check runs LAST in openStack: it reads state ndStart
-- establishes (the enet-lan-chat ordering).
-- ==========================================================================

on openStack
   ndBuild
   ndStart
   ndScRun
end openStack

on closeStack
   ndStop
end closeStack

on mouseUp
   switch the short name of the target
      case "ndGen"
         ndDoGenerate
         break
      case "ndDerive"
         ndDoDerive
         break
      case "ndSign"
         ndDoSign
         break
      case "ndDecode"
         ndDoDecode
         break
      case "ndEncode"
         ndDoEncode
         break
      case "ndConnect"
         ndDoConnect
         break
      case "ndDisconnect"
         ndDoDisconnect
         break
      case "ndSub"
         ndDoSubscribe
         break
      case "ndPublish"
         ndDoPublish
         break
      case "ndTests"
         ndDoSelfTest
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ==========================================================================
-- Build: the whole window, in script, kit look, inside the 720p budget.
-- ==========================================================================

command ndBuild
   if the uNdUiVersion of this stack is kNdUiVersion and there is a field "ndLog" then
      exit ndBuild
   end if
   lock screen
   ndClearGeneratedUI
   uiChrome "NostrXT demo", kNdWinW, kNdWinH
   -- Panels first, for z-order (the kit rule).
   uiPanel "ndKeysPanel", "16,46,478,196"
   uiPanel "ndNotePanel", "16,206,478,330"
   uiPanel "ndCodecPanel", "16,340,478,464"
   uiPanel "ndToolsPanel", "16,474,478,530"
   uiPanel "ndRelayPanel", "494,46,964,530"
   -- Identity.
   uiSection "ndKeysCap", "Identity", "28,54,466,72"
   uiCap "ndNsecCap", "secret key (hex or nsec; kept in memory only)", "28,76,466,90"
   uiInput "ndNsec", "28,92,338,114"
   uiButton "ndGen", "Generate", "346,92,404,114"
   uiButton "ndDerive", "Use key", "408,92,466,114"
   uiCap "ndNpubCap", "npub", "28,120,466,134"
   uiInput "ndNpub", "28,136,466,158"
   uiCap "ndKeysNote", "generation needs SodiumXT; derivation needs CoinXT", "28,164,466,188"
   -- Compose.
   uiSection "ndNoteCap", "Text note (kind 1)", "28,214,466,232"
   uiInput "ndContent", "28,238,466,260"
   uiButton "ndSign", "Sign and verify", "28,268,150,290"
   uiCap "ndNoteNote", "the signed event JSON and its verdict land in the log", "28,296,466,322"
   -- Codec.
   uiSection "ndCodecCap", "NIP-19 entities", "28,348,466,366"
   uiInput "ndEntity", "28,372,466,394"
   uiButton "ndDecode", "Decode", "28,402,110,424"
   uiButton "ndEncode", "Hex to npub", "114,402,216,424"
   uiCap "ndCodecNote", "paste an npub / note / nprofile / nevent / naddr, or 64 hex", "28,430,466,456"
   -- Tools.
   uiSection "ndToolsCap", "Member self-test", "28,482,466,500"
   uiButton "ndTests", "Run nxSelfTest", "28,504,150,524"
   -- Relay.
   uiSection "ndRelayCap", "Relay", "506,54,952,72"
   uiInput "ndUrl", "506,78,832,100"
   uiButton "ndConnect", "Connect", "838,78,894,100"
   uiButton "ndDisconnect", "Close", "898,78,952,100"
   uiButton "ndSub", "Subscribe (kind 1)", "506,106,646,128"
   uiButton "ndPublish", "Publish note", "650,106,760,128"
   uiCap "ndRelayNote", "ws:// uses the proven socket idioms; wss:// is engine-unproven", "506,134,952,148"
   uiArea "ndLog", "506,152,952,522"
   uiFooter "This stack demonstrates NostrXT. It signs with CoinXT and randomizes with SodiumXT; it stores nothing, uploads nothing on its own, and holds keys in memory only. Verified statically; needs an OXT pass + a live-relay pass.", "16,538,964,600"
   set the uNdUiVersion of this stack to kNdUiVersion
   unlock screen
end ndBuild

command ndClearGeneratedUI
   -- Rebuild-proof: drop every control this script generates (grouped by
   -- our nd prefix and the kit's ui prefix), then let ndBuild remake them.
   repeat while the number of controls of this card > 0
      delete control 1 of this card
   end repeat
end ndClearGeneratedUI

command ndStart
   local tCaps
   set the defaultStack to the short name of this stack
   nxrInit the long id of me
   put nxProbeCapabilities() into tCaps
   put tCaps["hasCoin"] into sNdHaveCoin
   put tCaps["hasSodium"] into sNdHaveSodium
   put "ws://127.0.0.1:7777" into field "ndUrl"
   if sNdHaveCoin is not true then
      ndLog "CoinXT is not installed: ids, signing and NIP-44 will refuse with capability errors."
      uiStatus "CoinXT missing - crypto paths disabled (fail closed)", "warn"
   else if sNdHaveSodium is not true then
      ndLog "SodiumXT is not installed: key generation is disabled; signing still works with an imported key."
      uiStatus "Ready (SodiumXT missing: no key generation)", "warn"
   else
      uiStatus "Ready - " & nxVersion(), "ok"
   end if
end ndStart

command ndStop
   -- Guarded teardown: the relay layer owns the sockets; closing a closed
   -- shop is a clean no-op (family rule 5).
   local tError
   try
      nxrShutdown
   catch tError
      -- The layer is embedded, so this is unreachable; the guard is the
      -- family's teardown discipline anyway.
   end try
   put empty into sNdRelay
end ndStop

-- ==========================================================================
-- Identity.
-- ==========================================================================

command ndDoGenerate
   local tKeyHex
   set the defaultStack to the short name of this stack
   put nxKeyGenerate() into tKeyHex
   if tKeyHex is empty then
      uiStatus "key generation failed: " & nxLastError(), "bad"
      ndLog "nxKeyGenerate: " & nxLastError()
      exit ndDoGenerate
   end if
   put tKeyHex into field "ndNsec"
   ndAdoptKey tKeyHex
end ndDoGenerate

command ndDoDerive
   local tText, tFields, tKeyHex
   set the defaultStack to the short name of this stack
   put word 1 of field "ndNsec" into tText
   if tText begins with "nsec" then
      put nxNsecDecode(tText) into tKeyHex
      if tKeyHex is empty then
         uiStatus "not a valid nsec: " & nxLastError(), "bad"
         exit ndDoDerive
      end if
   else
      put tText into tKeyHex
   end if
   ndAdoptKey tKeyHex
end ndDoDerive

command ndAdoptKey pKeyHex
   local tPubHex, tNpub
   if not nxIsHex(pKeyHex, 64) then
      uiStatus "a secret key is 64 hex characters (or an nsec)", "bad"
      exit ndAdoptKey
   end if
   put nxKeyPublic(pKeyHex) into tPubHex
   if tPubHex is empty then
      uiStatus "key refused: " & nxLastError(), "bad"
      ndLog "nxKeyPublic: " & nxLastError()
      exit ndAdoptKey
   end if
   put pKeyHex into sNdSeckey
   put nxNpubEncode(tPubHex) into tNpub
   put tNpub into field "ndNpub"
   ndLog "identity ready: " & tNpub
   uiStatus "identity ready", "ok"
end ndAdoptKey

-- ==========================================================================
-- Compose, sign, verify.
-- ==========================================================================

command ndDoSign
   local tEvent, tSigned, tJson
   set the defaultStack to the short name of this stack
   if sNdSeckey is empty then
      uiStatus "no identity yet - generate or import a key first", "warn"
      exit ndDoSign
   end if
   if field "ndContent" is empty then
      uiStatus "write something to sign", "warn"
      exit ndDoSign
   end if
   put nxEventBuild(1, field "ndContent", empty, empty) into tEvent
   if tEvent is empty then
      uiStatus "build refused: " & nxLastError(), "bad"
      exit ndDoSign
   end if
   put nxEventSign(tEvent, sNdSeckey, empty) into tSigned
   if tSigned is empty then
      uiStatus "signing failed: " & nxLastError(), "bad"
      ndLog "nxEventSign: " & nxLastError()
      exit ndDoSign
   end if
   put nxEventToJson(tSigned) into tJson
   ndLog "signed event " & tSigned["id"]
   ndLog tJson
   if nxEventVerify(tSigned) is true then
      ndLog "nxEventVerify: the event verifies (id + signature)"
      uiStatus "signed and verified: " & char 1 to 16 of tSigned["id"] & "...", "ok"
   else
      ndLog "nxEventVerify REFUSED the event we just signed: " & nxLastError()
      uiStatus "verification failed - see the log", "bad"
   end if
end ndDoSign

-- ==========================================================================
-- NIP-19 codec.
-- ==========================================================================

command ndDoDecode
   local tFields, tKeyList, tI, tCount, tSavedLineDelim
   set the defaultStack to the short name of this stack
   put nxEntityDecode(word 1 of field "ndEntity") into tFields
   if tFields is empty then
      uiStatus "decode refused: " & nxLastError(), "bad"
      ndLog "nxEntityDecode: " & nxLastError()
      exit ndDoDecode
   end if
   ndLog "entity type: " & tFields["type"]
   put the lineDelimiter into tSavedLineDelim
   set the lineDelimiter to return
   put the keys of tFields into tKeyList
   sort lines of tKeyList
   put the number of lines of tKeyList into tCount
   repeat with tI = 1 to tCount
      if line tI of tKeyList is not "type" and tFields[line tI of tKeyList] is not empty then
         ndLog "  " & line tI of tKeyList & ": " & tFields[line tI of tKeyList]
      end if
   end repeat
   set the lineDelimiter to tSavedLineDelim
   uiStatus "decoded a " & tFields["type"], "ok"
end ndDoDecode

command ndDoEncode
   local tNpub
   set the defaultStack to the short name of this stack
   put nxNpubEncode(word 1 of field "ndEntity") into tNpub
   if tNpub is empty then
      uiStatus "encode refused: " & nxLastError(), "bad"
      exit ndDoEncode
   end if
   put tNpub into field "ndEntity"
   ndLog "npub: " & tNpub
   uiStatus "encoded", "ok"
end ndDoEncode

-- ==========================================================================
-- Relay.
-- ==========================================================================

command ndDoConnect
   local tHandle
   set the defaultStack to the short name of this stack
   if sNdRelay is not empty then
      uiStatus "already connected - close first", "warn"
      exit ndDoConnect
   end if
   nxrConnect word 1 of field "ndUrl"
   put the result into tHandle
   if tHandle is not an integer then
      uiStatus tHandle, "bad"
      ndLog tHandle
      exit ndDoConnect
   end if
   put tHandle into sNdRelay
   nxrSetCallback sNdRelay, "onRelay"
   ndLog "connecting to " & nxrUrl(sNdRelay) & " (handle " & sNdRelay & ")"
   uiStatus "connecting...", "wait"
end ndDoConnect

command ndDoDisconnect
   set the defaultStack to the short name of this stack
   if sNdRelay is empty then
      uiStatus "no relay is open", "warn"
      exit ndDoDisconnect
   end if
   nxrDisconnect sNdRelay
   put empty into sNdRelay
   uiStatus "closed", "ok"
end ndDoDisconnect

command ndDoSubscribe
   local tFilter, tFilterJson
   set the defaultStack to the short name of this stack
   if sNdRelay is empty then
      uiStatus "connect to a relay first", "warn"
      exit ndDoSubscribe
   end if
   put "1" into tFilter["kinds"]
   put 10 into tFilter["limit"]
   put nxFilterBuild(tFilter) into tFilterJson
   nxrSubscribe sNdRelay, "nd-notes", tFilterJson
   if the result is not empty then
      uiStatus the result, "bad"
      exit ndDoSubscribe
   end if
   ndLog "REQ nd-notes " & tFilterJson
   uiStatus "subscribed to recent notes", "ok"
end ndDoSubscribe

command ndDoPublish
   local tEvent, tSigned
   set the defaultStack to the short name of this stack
   if sNdRelay is empty then
      uiStatus "connect to a relay first", "warn"
      exit ndDoPublish
   end if
   if sNdSeckey is empty or field "ndContent" is empty then
      uiStatus "an identity and some content first", "warn"
      exit ndDoPublish
   end if
   put nxEventBuild(1, field "ndContent", empty, empty) into tEvent
   put nxEventSign(tEvent, sNdSeckey, empty) into tSigned
   if tSigned is empty then
      uiStatus "signing failed: " & nxLastError(), "bad"
      exit ndDoPublish
   end if
   nxrPublish sNdRelay, tSigned
   if the result is not empty then
      uiStatus the result, "bad"
      exit ndDoPublish
   end if
   ndLog "published " & tSigned["id"] & " (watch for the ok callback)"
   uiStatus "published - awaiting the relay's verdict", "wait"
end ndDoPublish

on onRelay pRelay, pKind, pArgOne, pArgTwo
   -- The whole nxr* callback contract in one switch. Reached from socket
   -- callbacks and the relay watchdog, so the defaultStack is pinned FIRST
   -- (engine notes 5.3: unqualified controls resolve against the
   -- defaultStack in delayed handlers).
   set the defaultStack to the short name of this stack
   switch pKind
      case "open"
         ndLog "relay " & pRelay & ": open"
         uiStatus "relay open", "ok"
         break
      case "event"
         ndLog "event (" & pArgOne & "): " & char 1 to 240 of pArgTwo
         break
      case "invalid"
         ndLog "REFUSED event (" & pArgOne & "): " & pArgTwo
         break
      case "eose"
         ndLog "end of stored events for " & pArgOne
         break
      case "ok"
         ndLog "ok " & pArgOne & ": " & pArgTwo
         break
      case "closed"
         ndLog "subscription " & pArgOne & " closed by the relay: " & pArgTwo
         break
      case "notice"
         ndLog "notice: " & pArgOne
         break
      case "auth"
         ndLog "auth challenge: " & pArgOne & " (answer with nxAuthBuild + nxEventSign + nxrAuth)"
         break
      case "error"
         ndLog "relay " & pRelay & " error: " & pArgOne
         uiStatus "relay error - see the log", "bad"
         put empty into sNdRelay
         break
      case "disconnected"
         ndLog "relay " & pRelay & " gone: " & pArgOne
         if pRelay is sNdRelay then
            put empty into sNdRelay
         end if
         uiStatus "disconnected", "warn"
         break
   end switch
end onRelay

-- ==========================================================================
-- The member self-test, into the log.
-- ==========================================================================

command ndDoSelfTest
   local tReport
   set the defaultStack to the short name of this stack
   uiStatus "running nxSelfTest...", "wait"
   put nxSelfTest() into tReport
   ndLog "== nxSelfTest =="
   ndLog tReport
   uiStatus "self-test: " & line 1 of tReport, "ok"
end ndDoSelfTest

command ndLog pText
   set the defaultStack to the short name of this stack
   put pText & return after field "ndLog"
   set the vScroll of field "ndLog" to the formattedHeight of field "ndLog"
end ndLog

-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: tools/demo-selfcheck.livecodescript; gate: tools/check-demo-selfcheck-drift.py) ====
-- The sentinel is a CONSTANT so the probe compares against one spelling; a
-- literal repeated at the write and the read is a check that can pass while
-- disagreeing with itself.
constant kScProbe = "self-check: delayed write reached the status line"
local sScLines          -- the whole block, kept so a Copy button has something
local sScPassed, sScFailed, sScSkipped
local sScLogField       -- the adopting demo's own log field, set by scBegin

command scBegin pLogField
   put pLogField into sScLogField
   put empty into sScLines
   put 0 into sScPassed
   put 0 into sScFailed
   put 0 into sScSkipped
   scLine "== boot self-check (nothing is hosted, connected, or bound) =="
end scBegin

-- Each line is LOGGED as it is made, not accumulated and flushed at the end.
-- The first draft did both - a flush after the synchronous half and another
-- after the probe - which printed every synchronous line twice.
command scLine pText
   put pText & return after sScLines
   -- pin the stack: scFinish reaches here from a `send ... in` tick, and the
   -- field is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sScLogField is empty or there is no field sScLogField then
      exit scLine
   end if
   put pText & return after field sScLogField
   set the vscroll of field sScLogField to the formattedHeight of field sScLogField
end scLine

command scAssert pName, pOk
   if pOk then
      add 1 to sScPassed
      scLine "PASS  " & pName
   else
      add 1 to sScFailed
      scLine "FAIL  " & pName
   end if
end scAssert

-- SKIP, never FAIL, for an absent extension: a missing member is an
-- environment, and only a present-and-broken member is a defect.
command scSkip pName, pReason
   add 1 to sScSkipped
   scLine "SKIP  " & pName & " (" & pReason & ")"
end scSkip

-- An empty value prints as nothing, which reads as a missing check rather than
-- an answer of empty; every observed value in a self-check goes through here.
-- This is the playLoudness lesson (OXT-ENGINE-NOTES 5.4) as a helper: a check
-- that reports only its own name costs a whole engine pass to diagnose.
function scShow pValue
   if pValue is empty then
      return "empty"
   end if
   return pValue
end scShow

-- Returns the comma-list of control names in pList that do not exist, or empty.
-- The adopter passes EVERY control name its own script references, derived from
-- the source rather than hand-picked: a missing control is not cosmetic, it is
-- the "Chunk: error in object expression" class, and finding it at boot beats
-- finding it when somebody clicks.
function scMissing pList
   local tName, tMissing
   set the defaultStack to the short name of this stack
   repeat for each item tName in pList
      -- ALL THREE CONTROL TYPES. The kit builds fields (uiLabel/uiWrap/uiCap/
      -- uiSection/uiInput/uiArea/uiTable), buttons (uiButton/uiCheckbox) AND
      -- GRAPHICS (uiGfx/uiPanel/uiPill). The first version of this asked only
      -- about fields and buttons, so every uiPill a demo builds - the Tor
      -- pills in both Quick Shares, for one - reported as a missing control on
      -- a stack where it exists.
      if there is no field tName and there is no button tName \
            and there is no graphic tName then
         put tName & comma after tMissing
      end if
   end repeat
   if tMissing is empty then
      return empty
   end if
   return char 1 to -2 of tMissing
end scMissing

-- Call LAST in <pfx>ScRun. It arms the probe below; 400ms lands it before the
-- usual 800ms dashboard tick, so nothing races for the status line.
--
-- SAY THAT THE REPORT IS UNFINISHED, for the reason the suite harness carries a
-- RUN NOT FINISHED trailer: a report that simply stops reads exactly like a
-- report that ended, and the difference cost that harness a round trip on
-- 2026-08-19. One line is cheaper than the ambiguity.
command scArmProbe
   scLine "      ...one delayed-write check still to come; the count line " \
         & "below it is the end of the block"
   send "scTickProbe" to me in 400 milliseconds
end scArmProbe

-- THE ONE CHECK THAT NEEDS A TIMER.
--
-- OXT-ENGINE-NOTES 5.3 says an unqualified control reference inside a delayed
-- handler resolves against THE DEFAULTSTACK, not the stack whose script is
-- running - and that entry is classed DOCUMENTED, not OBSERVED, because this
-- tree has never actually watched the unpinned form fail. It also names the run
-- that would settle it: open a second stack in front and let a `send ... in`
-- handler write an unqualified field.
--
-- So this probe READS the defaultStack before pinning and PRINTS what it found.
-- On an ordinary run that line is context. On a run with another window in front
-- it is the measurement 5.3 is missing, taken for free and at no risk, because
-- the pin lands immediately afterwards and the write is verified.
command scTickProbe
   local tWas, tPrev, tPrevColor, tGot, tErr
   put the defaultStack into tWas
   set the defaultStack to the short name of this stack
   if there is no field "uiStatus" then
      scSkip "a delayed handler writes the status line", "the chrome is not built"
      scFinish
      exit scTickProbe
   end if
   -- RESTORE THE COLOUR TOO, not just the text. uiStatus takes a KIND, and
   -- handing it back "ok" would repaint a "bad" line green - so a stack whose
   -- extension is missing would end this probe claiming to be fine.
   put field "uiStatus" into tPrev
   put the foregroundColor of field "uiStatus" into tPrevColor
   try
      uiStatus kScProbe, empty
      put field "uiStatus" into tGot
   catch tErr
      put "THREW:" && tErr into tGot
   end try
   uiStatus tPrev, empty
   set the foregroundColor of field "uiStatus" to tPrevColor
   scAssert "a delayed handler writes the status line " \
         & "(defaultStack on entry: " & scShow(tWas) & ")", (tGot is kScProbe)
   scFinish
end scTickProbe

command scFinish
   scLine "      " & sScPassed & " passed, " & sScFailed & " failed, " \
         & sScSkipped & " skipped - select this block and copy it into the " \
         & "OXT pass record"
   if sScFailed is 0 then
      scLine "      boot self-check GREEN (this is the single-machine claim; " \
            & "the live legs are the runbook's)"
      exit scFinish
   end if
   scLine "      boot self-check has FAILURES above - report them before " \
         & "running any live leg"
   -- ONLY ON FAILURE does this touch the status line, and the asymmetry is
   -- deliberate. Green, the demo's own "Ready ..." line is the more useful
   -- thing to be reading and the detail is in the log a few lines up. Red, the
   -- log may be on a tab nobody has clicked - so the one surface a person is
   -- certainly looking at has to say so. Fail loud, pass quiet.
   uiStatus "Boot self-check: " & sScFailed & " FAILED (see the log)", "bad"
end scFinish
-- ==== DEMO SELF-CHECK v1 END ====

-- ==========================================================================
-- The demo-owned self-check assertions. The control list is DERIVED from
-- this script by tools/check-demo-control-lists.py --write; never hand-pick
-- it. Non-destructive by rule: nothing here connects, binds or signs into
-- the world - pure answers and boot state only.
-- ==========================================================================

constant kNdScControls = "ndCodecCap,ndCodecNote,ndCodecPanel,ndConnect,ndContent,ndDecode,ndDerive,ndDisconnect,ndEncode,ndEntity,ndGen,ndKeysCap,ndKeysNote,ndKeysPanel,ndLog,ndNoteCap,ndNoteNote,ndNotePanel,ndNpub,ndNpubCap,ndNsec,ndNsecCap,ndPublish,ndRelayCap,ndRelayNote,ndRelayPanel,ndSign,ndSub,ndTests,ndToolsCap,ndToolsPanel,ndUrl,uiFooter,uiStatus,uiTitle"

command ndScRun
   local tMissing
   scBegin "ndLog"
   put scMissing(kNdScControls) into tMissing
   scAssert "all 35 controls this script names exist (missing: " & scShow(tMissing) & ")", tMissing is empty
   scAssert "no relay handle at boot", sNdRelay is empty
   scAssert "the relay table is empty at boot", nxrOpenRelays() is empty
   scAssert "nxVersion reports the member", nxVersion() begins with "NostrXT"
   scAssert "the published npub example encodes", nxNpubEncode(kNxVecNpubHex) is kNxVecNpub
   scAssert "the websocket accept sample derives", nxWsAcceptFor(kNxVecWsKey) is kNxVecWsAccept
   scAssert "the NIP-13 example id scores 36 bits", nxPowDifficulty(kNxVecPowId) is 36
   if sNdHaveCoin is true then
      scAssert "the fixture event id matches the oracle", nxEventId(nxtEventA()) is kNxVecIdA
   else
      scSkip "fixture event id", "CoinXT is not installed (cxSha256)"
   end if
   scArmProbe
end ndScRun
