script "nostrxt"
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
-- on bytes; itemDelimiter and lineDelimiter are saved, set, used and restored
-- around every chunk read (the itemDelimiter is handler-local on Windows and
-- Linux, suite engine note 2.3, so the restore guards the rest of the handler
-- that set it; the lineDelimiter is unprobed and treated as global).
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
--     runs, is vector-pinned headlessly, and RAN ON AN ENGINE 2026-08-24
--     (the STATUS above; what exactly ran is at the NIP-44 section below).

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

/**
Title: NostrXT
Author: Seth Morrow Software
Description:
NostrXT is the client side of the Nostr protocol for OpenXTalk, written in
pure script: NIP-01 events (build, canonical serialization, id, BIP-340 sign
and verify), NIP-19 bech32 entities and NIP-21 nostr: URIs, NIP-44 v2
encrypted payloads, NIP-01 filters and relay messages, NIP-13 proof of
work, NIP-05 and NIP-11 parsing, and the pure-compute half of an RFC 6455
websocket client.

This core library does no I/O and holds no connection state. The relay
client (the NostrXT Relay Client library, nxr handlers) owns the sockets
and composes it, so load this library first.

It adds no cryptography of its own. SHA-256, Schnorr signatures, x-only
keys, ECDH and HMAC come from CoinXT; randomness, constant-time compare
and the NIP-44 cipher come from SodiumXT. A missing extension disables
exactly the features that need it (see <nxProbeCapabilities>).

No handler here ever throws. A function that fails returns empty (or
false for a predicate) and records the reason, which <nxLastError>
returns. Ids, pubkeys, secret keys and signatures cross this API as
lowercase hex strings.

Tags: Networking, Nostr
*/
/**
Summary: Returns the NostrXT name and version.

Returns: The text "NostrXT" followed by a space and the version number.

Example:
put nxVersion() into field "versionField"

Description:
Use <nxVersion> to confirm the core library is loaded and to show which
version an app is running.

References: nxrVersion (handler), nxProbeCapabilities (handler)
*/
function nxVersion
   return "NostrXT" && kNxVersion
end nxVersion

/**
Summary: Returns the reason the most recent failing nx call recorded.

Returns: The reason text, or empty when nothing has failed yet.

Example:
put nxNpubDecode(field "npubField") into tPubkey
if tPubkey is empty then answer "Not an npub:" && nxLastError()

Description:
Core handlers never throw. A function that fails returns empty (or false
for a predicate) and records why. Check the return first, then read
<nxLastError> straight away: any later failing call overwrites the
reason, and a successful call does not clear it.

A missing extension gives a reason that names the handler it needs, for
example "nxEventId needs CoinXT cxSha256".

References: nxProbeCapabilities (handler)
*/
function nxLastError
   return sNxLastError
end nxLastError

private command nxSetError pMessage
   put pMessage into sNxLastError
end nxSetError

/**
Summary: Reports which extensions NostrXT can use, as a cached array.

Returns: An array with keys "hasCoin", "hasSodium", "canSign",
"canNip44Cipher" (each true or false) and "version".

Example:
put nxProbeCapabilities() into tCaps
if tCaps["canSign"] is not true then answer "CoinXT is not installed: signing is unavailable"

Description:
Each extension is probed with a real round trip (a known hash, a real
random byte), not a version check. "hasCoin" and "canSign" need CoinXT;
"hasSodium" needs SodiumXT; "canNip44Cipher" is false when the installed
SodiumXT is older than ABI 10, which added the NIP-44 cipher.

The answer is cached for the session after the first call. To notice a
SodiumXT upgraded while the app runs, use <nxNip44HasCipher>, which
probes the cipher live.

References: nxNip44HasCipher (handler), nxLastError (handler)
*/
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

/**
Summary: Encodes binary data as standard base64 on one line.

pData: The bytes to encode.

Returns: The base64 text, with no line breaks.

Example:
put nxB64Encode(textEncode("hello", "UTF-8")) into tText

Description:
The engine's base64Encode can wrap its output across lines. Every wire
format NostrXT uses (NIP-44 payloads, the websocket key) is single-line,
so <nxB64Encode> removes both line-break characters.

References: nxB64Decode (handler)
*/
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

/**
Summary: Decodes strict standard base64 back to binary data.

pText: The base64 text, with padding.

Returns: The decoded bytes, or empty when the text is malformed.

Example:
put nxB64Decode("aGVsbG8=") into tData
if tData is empty then answer "not valid base64"

Description:
<nxB64Decode> refuses characters outside the base64 alphabet, data after
the padding, misplaced or extra padding, and a length that is not a
multiple of 4. A malformed payload is an error, never a partial decode.
Empty input returns empty.

References: nxB64Encode (handler)
*/
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

/**
Summary: Returns the current unix time in seconds.

Returns: The number of seconds since the unix epoch.

Example:
put nxUnixNow() into tNow

Description:
This is the timestamp the event builders use for "created_at" when you
pass an empty created-at argument.

References: nxEventBuild (handler)
*/
function nxUnixNow
   -- The unix timestamp (seconds) events stamp created_at with.
   return the seconds
end nxUnixNow

-- ==========================================================================
-- Hex. Lowercase out; mixed case in (0-9 a-f A-F); anything else refuses.
-- ==========================================================================

/**
Summary: Converts binary data to lowercase hex.

pData: The bytes to convert.

Returns: Two lowercase hex characters per byte.

Example:
put nxHexEncode(textEncode("abc", "UTF-8")) into tHex

Description:
Hex is the currency of the NostrXT API: ids, keys and signatures cross
it as lowercase hex strings, and binary stays inside the library.

References: nxHexDecode (handler), nxIsHex (handler)
*/
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

/**
Summary: Converts hex text (either case) to binary data.

pHex: The hex text.

Returns: The bytes, or empty when the text is not valid hex.

Example:
put nxHexDecode("616263") into tData

Description:
<nxHexDecode> accepts upper and lower case digits. Text of odd length or
with a character that is not a hex digit returns empty and records the
reason for <nxLastError>.

References: nxHexEncode (handler), nxIsHex (handler)
*/
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

/**
Summary: Tells whether text is all hex digits, optionally of an exact length.

pText: The text to test.

pLen: The required number of characters, or empty for any length.

Returns: true or false.

Example:
if not nxIsHex(tPubkey, 64) then answer "a pubkey is 64 hex characters"

Description:
Use <nxIsHex> to validate an id or pubkey (64 characters) or a signature
(128 characters). Either case is accepted. Empty text is never hex.

References: nxHexDecode (handler), nxCtEqualHex (handler)
*/
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

/**
Summary: Compares two hex strings without exiting early on the first difference.

pAHex: The first hex string.

pBHex: The second hex string.

Returns: true when both strings hold the same hex value, false otherwise.

Example:
if nxCtEqualHex(tExpectedId, tEvent["id"]) then put "match" into tVerdict

Description:
Use <nxCtEqualHex> to compare MACs and ids, rather than a bare is, which
can compare number-like text as numbers. Case is ignored. With SodiumXT
the decoded bytes are compared by sxMemEqual; without it, a loop over
every character that never exits early stands in.

This guards against the gross early-exit timing leak, not a lab-grade
side channel: script timing is noisy either way. Strings of different
lengths return false at once.

References: nxIsHex (handler)
*/
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

/**
Summary: Escapes text for a JSON string the way NIP-01 requires.

pText: The text to escape.

Returns: The escaped text, without surrounding quotes.

Example:
put quote & nxJsonEscape(tContent) & quote into tJsonString

Description:
NIP-01 uses exactly seven escapes: quote, backslash, line feed, carriage
return, tab, backspace and form feed. Every other byte, other control
bytes included, passes through unchanged. A general JSON encoder escapes
more than that, which is why it produces wrong event ids.

The text is handled as UTF-8, so multi-byte characters pass through
untouched.

References: nxEventSerialize (handler), nxJsonGet (handler)
*/
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
         -- NESTED, not one `or` chain (2026-09-09). xTalk's `or` evaluates
         -- BOTH operands - there is no short-circuit (engine notes; coinxt
         -- paid for this at five sites before it was written down) - so
         -- `tStep + 0` ran even when nxIsDigits had already said no, and
         -- arithmetic on non-numeric text is a HARD engine error, not a
         -- coercion to 0. One hostile relay message with a path step like
         -- "abc" turned this never-throw library into an uncaught engine
         -- error, and OXT runs script on the UI thread.
         --
         -- The itemDelimiter restore is repeated in the new early-out: it is
         -- "/" at this point. When this was written the delimiter was taken
         -- for GLOBAL mutable state, so a missed restore read as corrupting
         -- every later `item` operation in the process; engine note 2.3 has
         -- since OBSERVED it handler-local on Windows and Linux (both
         -- directions; no Mac run), so there it would misparse only the rest
         -- of this handler. The restore stays: it costs nothing, macOS has not
         -- run the probe, and tools/check-script-vectors.py pins it under the
         -- interpreter, whose delimiter is global.
         if not nxIsDigits(tStep) then
            set the itemDelimiter to tSavedDelim
            nxSetError "nxJson: no element" && tStep
            return empty
         end if
         if tStep + 0 < 1 or tStep + 0 > nxSeqCount(tNode["c"]) then
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

/**
Summary: Returns the value at a path in a JSON document.

pJson: The JSON text.

pPath: A path of object keys and 1-based array indexes separated by /, or empty for the root.

Returns: The value, or empty when the path does not resolve.

Example:
put nxJsonGet(tJson, "tags/1/2") into tValue
put nxJsonGet(tInfoJson, "name") into tName

Description:
Strings come back decoded, numbers as their source text, booleans as
"true" or "false", and null as empty. An object or array at the path
comes back as its exact source text, so you can pass a sub-document on.

Because empty can mean null, an empty string or a miss, use <nxJsonType>
when the difference matters. The parser is strict (exact bare words, no
trailing bytes, a nesting limit, duplicate keys refused). A key that
contains / cannot be reached through a path.

References: nxJsonType (handler), nxJsonCount (handler)
*/
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

/**
Summary: Counts the elements of a JSON array or the members of a JSON object.

pJson: The JSON text.

pPath: The path to the array or object, or empty for the root.

Returns: The count, or empty when the path does not resolve or names a scalar.

Example:
put nxJsonCount(tInfoJson, "supported_nips") into tCount

Description:
An empty container returns 0. A scalar at the path returns empty and
records the reason for <nxLastError>.

References: nxJsonGet (handler), nxJsonType (handler)
*/
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

/**
Summary: Returns the JSON type of the value at a path.

pJson: The JSON text.

pPath: The path to test, or empty for the root.

Returns: "object", "array", "string", "number", "boolean", "null", or "missing".

Example:
if nxJsonType(tJson, "names/alice") is "string" then put nxJsonGet(tJson, "names/alice") into tPubkey

Description:
"missing" means the path does not resolve, which includes JSON that does
not parse; the parse error is recorded for <nxLastError>.

References: nxJsonGet (handler), nxJsonCount (handler)
*/
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

/**
Summary: Generates a new Nostr secret key.

Returns: The secret key as 64 lowercase hex characters, or empty.

Example:
put nxKeyGenerate() into tSeckey
if tSeckey is empty then answer "no key:" && nxLastError()

Description:
<nxKeyGenerate> draws 32 random bytes from SodiumXT and checks with
CoinXT that they form a valid secp256k1 secret key. It needs both
extensions and refuses without them: it never falls back to weaker
randomness.

The key is a plain script value. OXT variables are not locked memory, so
how and where to store a key is the app's decision.

References: nxKeyPublic (handler), nxKeyIsValid (handler), nxNsecEncode (handler)
*/
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

/**
Summary: Derives the Nostr public key for a secret key.

pSeckeyHex: The secret key as 64 hex characters.

Returns: The 64-hex x-only public key, or empty.

Example:
put nxKeyPublic(tSeckey) into tPubkey
put nxNpubEncode(tPubkey) into field "npubField"

Description:
Needs CoinXT (cxXOnlyPubkey). Returns empty, with the reason recorded,
when the secret key is not 64 hex characters or CoinXT refuses it.

References: nxKeyGenerate (handler), nxNpubEncode (handler)
*/
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

/**
Summary: Tells whether hex text is a valid secp256k1 secret key.

pSeckeyHex: The secret key as 64 hex characters.

Returns: true or false.

Example:
if not nxKeyIsValid(tSeckey) then answer "that is not a usable secret key"

Description:
Needs CoinXT (cxSeckeyIsValid). Text that is not 64 hex characters
returns false. Without CoinXT it returns false and records why.

References: nxKeyGenerate (handler), nxKeyPublic (handler)
*/
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

/**
Summary: Builds an unsigned Nostr event.

pKind: The event kind, an integer from 0 to 65535.

pContent: The event content text.

pTags: A nested tag array, or empty for no tags.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put "t" into tTags[1][1]
put "openxtalk" into tTags[1][2]
put nxEventBuild(1, "Hello, Nostr", tTags, empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
The event array has keys "kind", "created_at", "content", "tags", and
"id", "pubkey" and "sig", which stay empty until <nxEventSign> fills
them. Tags are 1-based both ways: tTags[1][1] is the first tag's name and
tTags[1][2] its value. <nxTagsFromText> builds the array from text.

The kind and created-at must be plain digit runs (no leading zero, no
exponent); the shape is checked by <nxEventHasValidShape>, and a refusal
returns empty with the reason recorded.

References: nxEventSign (handler), nxTagsFromText (handler), nxEventHasValidShape (handler)
*/
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

/**
Summary: Returns the canonical NIP-01 serialization of an event.

pEvent: The event array, with its pubkey filled in.

Returns: The canonical JSON array text, or empty.

Example:
put nxEventSerialize(tSigned) into tPreimage

Description:
This is the exact text NIP-01 hashes to make the event id:
[0,pubkey,created_at,kind,tags,content], with no whitespace and the
NIP-01 escapes. It refuses an event whose pubkey is not 64 lowercase hex
characters, because a half-built event would serialize to a well-formed
but wrong preimage.

Most apps never call this directly: <nxEventId> and <nxEventSign> use it.

References: nxEventId (handler), nxEventToJson (handler)
*/
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

/**
Summary: Computes the NIP-01 id of an event.

pEvent: The event array, with its pubkey filled in.

Returns: The 64-hex SHA-256 of the canonical serialization, or empty.

Example:
put nxEventId(tEvent) into tId

Description:
Needs CoinXT (cxSha256). The id is the hash of the UTF-8 bytes of
<nxEventSerialize>, so it never depends on the wire form <nxEventToJson>
emits.

References: nxEventSerialize (handler), nxEventSign (handler)
*/
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

/**
Summary: Signs an event, filling in its pubkey, id and signature.

pEvent: The unsigned event array.

pSeckeyHex: The secret key as 64 hex characters.

pAuxHex: Empty for fresh signing randomness, or 64 hex characters for a deterministic signature.

Returns: The completed event array, or empty.

Example:
put nxEventBuild(1, "Hello", empty, empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned
if tSigned is empty then answer "signing failed:" && nxLastError()

Description:
Needs CoinXT. <nxEventSign> derives the pubkey, computes the id and makes
a BIP-340 Schnorr signature over it. Pass empty for pAuxHex in an app; a
fixed value makes the signature repeatable, which is for test vectors.

References: nxEventBuild (handler), nxEventVerify (handler), nxrPublish (handler)
*/
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

/**
Summary: Checks an event's id and signature.

pEvent: The event array.

Returns: true only when the id and the signature both check out.

Example:
put nxEventFromJson(tJson) into tEvent
if tEvent is not empty then put nxEventVerify(tEvent) into tTrusted

Description:
Needs CoinXT. <nxEventVerify> recomputes the id from the event's fields,
compares it with the id the event carries, and verifies the BIP-340
signature over it. Anything else returns false with the reason recorded,
including a missing CoinXT.

An event from anywhere is untrusted text until this returns true.

References: nxEventFromJson (handler), nxEventSign (handler), nxEventId (handler)
*/
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

/**
Summary: Checks that an event array has the structure NIP-01 requires.

pEvent: The event array.

Returns: true or false.

Example:
if not nxEventHasValidShape(tEvent) then answer nxLastError()

Description:
Checks that the kind is a plain integer from 0 to 65535 and created_at a
plain non-negative integer, that id, pubkey and sig (when present) are
hex of the right length, that content is a string, and that tags is an
array of 1-based, gap-free arrays of strings, each with a name.

It checks structure only, not the id or signature: that is
<nxEventVerify>. A failure records the specific reason.

References: nxEventBuild (handler), nxEventVerify (handler)
*/
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

/**
Summary: Converts an event array to its wire-format JSON object.

pEvent: The event array.

Returns: The JSON object text, or empty.

Example:
put nxEventToJson(tSigned) into field "wireField"

Description:
Use it for storage or a transport of your own; <nxrPublish> and
<nxClientEvent> call it for you. The id never depends on this form,
only on <nxEventSerialize>. Refuses an event that fails
<nxEventHasValidShape>.

References: nxEventFromJson (handler), nxClientEvent (handler)
*/
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

/**
Summary: Parses a wire-format event object into an event array.

pJson: The event JSON object text.

Returns: The event array, or empty.

Example:
put nxEventFromJson(tJson) into tEvent
if tEvent is empty then answer "unparseable:" && nxLastError()

Description:
<nxEventFromJson> checks structure only. Call <nxEventVerify> before
trusting the result.

It is strict: hex fields must be lowercase and the right length,
created_at and kind must be plain digit runs, every tag must be a
non-empty array of strings, and duplicate keys are refused.

References: nxEventVerify (handler), nxEventToJson (handler), nxRelayParse (handler)
*/
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

/**
Summary: Builds a nested tag array from text, one tag per line.

pText: One tag per line, items separated by tabs.

Returns: The nested tag array, or empty.

Example:
put "t" & tab & "openxtalk" & return & "p" & tab & tPubkey into tText
put nxTagsFromText(tText) into tTags
put nxEventBuild(1, "Hello", tTags, empty) into tEvent

Description:
Empty lines are skipped. A line whose first item is empty refuses,
because a tag must have a name.

References: nxTagsToText (handler), nxEventBuild (handler)
*/
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

/**
Summary: Converts a nested tag array to text, one tag per line.

pTags: The nested tag array.

Returns: One tag per line, items separated by tabs, or empty.

Example:
put nxTagsToText(tEvent["tags"]) into field "tagsField"

Description:
The inverse of <nxTagsFromText>. A tag item that contains a tab or a line
break, or a tag that ends with an empty item, cannot survive the text
form, so it refuses rather than corrupt the tag. Use the array form for
such tags.

References: nxTagsFromText (handler), nxTagItem (handler)
*/
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

/**
Summary: Returns how many tags an event carries.

pEvent: The event array.

Returns: The number of tags.

Example:
put nxTagCount(tEvent) into tCount
put nxTagItem(tEvent, tCount) into tLastTag

Description:
Counts the 1-based tags of the event's "tags" array.

References: nxTagItem (handler), nxTagValues (handler)
*/
function nxTagCount pEvent
   return nxSeqCount(pEvent["tags"])
end nxTagCount

/**
Summary: Returns one tag of an event as tab-separated text.

pEvent: The event array.

pIndex: The 1-based tag number.

Returns: The tag's items joined by tabs, or empty when there is no such tag.

Example:
put nxTagItem(tEvent, 1) into tFirstTag

Description:
An index out of range returns empty and records the reason.

References: nxTagCount (handler), nxTagFirst (handler)
*/
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

/**
Summary: Returns the value of the first tag with a given name.

pEvent: The event array.

pTagName: The tag name, for example "e" or "p".

Returns: The tag's second item, or empty.

Example:
put nxTagFirst(tEvent, "d") into tIdentifier

Description:
Tag names compare byte for byte: "p" and "P" are different tags. Returns
empty when no tag has the name or the first one has no value.

References: nxTagValues (handler), nxTagItem (handler)
*/
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

/**
Summary: Returns the values of every tag with a given name.

pEvent: The event array.

pTagName: The tag name, for example "e" or "p".

Returns: The values, one per line.

Example:
put nxTagValues(tEvent, "p") into field "mentionsField"

Description:
Each matching tag contributes its second item. Names compare byte for
byte, so "p" and "P" are different tags.

References: nxTagFirst (handler), nxContactsParse (handler)
*/
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

/**
Summary: Builds an unsigned kind 0 user metadata event.

pName: The display name.

pAbout: The profile description.

pPicture: The picture URL.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxMetadataBuild("alice", "I write xTalk", "https://example.com/a.png", empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
The content is a JSON object with the "name", "about" and "picture"
fields. Sign the result with <nxEventSign>.

References: nxMetadataParse (handler), nxEventSign (handler)
*/
function nxMetadataBuild pName, pAbout, pPicture, pCreatedAt
   -- kind 0 user metadata; the content is the stringified JSON object.
   local tContent
   put "{" & quote & "name" & quote & ":" & quote & nxJsonEscape(pName) & quote into tContent
   put "," & quote & "about" & quote & ":" & quote & nxJsonEscape(pAbout) & quote after tContent
   put "," & quote & "picture" & quote & ":" & quote & nxJsonEscape(pPicture) & quote & "}" after tContent
   return nxEventBuild(0, tContent, empty, pCreatedAt)
end nxMetadataBuild

/**
Summary: Reads the common profile fields from a kind 0 event.

pEvent: A kind 0 event array.

Returns: An array of the profile fields, or empty for another kind.

Example:
put nxMetadataParse(tEvent) into tProfile
put tProfile["name"] into field "nameField"

Description:
The keys are "name", "about", "picture", "display_name", "nip05",
"website", "banner" and "lud16". A field that is absent, or is not a
string, is empty.

References: nxMetadataBuild (handler)
*/
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

/**
Summary: Builds an unsigned kind 1 reply with NIP-10 marked tags.

pParentEvent: The event being replied to, with its id and pubkey.

pContent: The reply text.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxReplyBuild(tParent, "Agreed!", empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
The reply carries an "e" tag marked "root" for the thread root (the
parent's own root tag, or the parent itself when it has none), an "e"
tag marked "reply" for the parent when it is not the root, and "p" tags
for the parent's author and the people the parent tagged, without
duplicates.

References: nxReactionBuild (handler), nxEventSign (handler)
*/
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

/**
Summary: Builds an unsigned kind 7 reaction (NIP-25).

pTargetEvent: The event being reacted to, with its id and pubkey.

pContent: The reaction, or empty for "+".

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxReactionBuild(tTarget, empty, empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
The reaction carries "e" and "p" tags for the target and its author, and
a "k" tag with the target's kind.

References: nxReplyBuild (handler), nxEventSign (handler)
*/
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

/**
Summary: Builds an unsigned kind 5 deletion request (NIP-09).

pIdLines: The ids of the events to delete, one 64-hex id per line.

pReason: The reason, or empty.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxDeleteBuild(tOldEvent["id"], "posted by mistake", empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
Each id becomes an "e" tag and the reason becomes the content. At least
one id is required, and a line that is not a 64-hex id refuses. Relays
may honour a deletion request; they are not obliged to.

References: nxEventSign (handler), nxrPublish (handler)
*/
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

/**
Summary: Builds an unsigned kind 3 contact list.

pPubkeyLines: The followed public keys, one 64-hex pubkey per line.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxContactsBuild(tFollowList, empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned

Description:
Each pubkey becomes a "p" tag. A line that is not a 64-hex pubkey
refuses. A kind 3 list replaces the previous one, so publish the whole
list every time.

References: nxContactsParse (handler), nxEventSign (handler)
*/
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

/**
Summary: Returns the followed public keys of a kind 3 contact list.

pEvent: A kind 3 event array.

Returns: The pubkeys, one per line, or empty for another kind.

Example:
put nxContactsParse(tEvent) into tFollowList

Description:
Reads the value of every "p" tag. Any other kind returns empty and
records the reason.

References: nxContactsBuild (handler), nxTagValues (handler)
*/
function nxContactsParse pEvent
   -- The followed pubkeys of a kind 3 event, one per line.
   if pEvent["kind"] is not 3 then
      nxSetError "nxContactsParse: not a kind 3 event"
      return empty
   end if
   return nxTagValues(pEvent, "p")
end nxContactsParse

/**
Summary: Builds an unsigned kind 10002 relay list (NIP-65).

pRelayLines: One relay per line: a URL, or a URL, a tab and "read" or "write".

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put "wss://relay.example.com" & return & "wss://inbox.example.com" & tab & "read" into tLines
put nxRelayListBuild(tLines, empty) into tEvent

Description:
Each line becomes an "r" tag. A URL with no marker means read and write.
At least one relay is required, and any marker other than "read" or
"write" refuses.

References: nxRelayListParse (handler), nxEventSign (handler)
*/
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

/**
Summary: Returns the relays of a kind 10002 relay list.

pEvent: A kind 10002 event array.

Returns: One relay per line, with a tab and its marker when it has one.

Example:
put nxRelayListParse(tEvent) into tRelayLines

Description:
Reads every "r" tag. Any other kind returns empty and records the
reason.

References: nxRelayListBuild (handler)
*/
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

/**
Summary: Builds an unsigned kind 22242 NIP-42 authentication event.

pRelayUrl: The URL of the relay that sent the challenge.

pChallenge: The challenge text the relay sent.

pCreatedAt: The unix time in seconds, or empty for now.

Returns: The unsigned event array, or empty.

Example:
put nxAuthBuild(nxrUrl(tRelay), nxrChallenge(tRelay), empty) into tEvent
put nxEventSign(tEvent, tSeckey, empty) into tSigned
nxrAuth tRelay, tSigned

Description:
The event carries "relay" and "challenge" tags. Both arguments are
required. Sign it with <nxEventSign>, then send it with <nxrAuth> or
wrap it yourself with <nxClientAuth>.

References: nxrAuth (handler), nxClientAuth (handler), nxrChallenge (handler)
*/
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

/**
Summary: Encodes hex data as a bech32 or bech32m string.

pHrp: The human-readable prefix, in lowercase.

pHex: The data bytes as hex.

pSpec: "bech32" (or empty) or "bech32m".

Returns: The encoded string in lowercase, or empty.

Example:
put nxBech32Encode("npub", tPubkey, "bech32") into tNpub

Description:
The generic encoder behind the NIP-19 handlers, which use bech32. An
uppercase prefix refuses: uppercase the finished string instead. Results
longer than the NIP-19 cap of 5000 characters refuse; the 90-character
limit of BIP-173 does not apply.

References: nxBech32Decode (handler), nxNpubEncode (handler)
*/
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

/**
Summary: Decodes a bech32 or bech32m string.

pText: The encoded string.

Returns: An array with keys "hrp", "spec" and "hex", or empty.

Example:
put nxBech32Decode(tText) into tDecoded
put tDecoded["hrp"] into tPrefix

Description:
Accepts either spec and reports which in "spec". "hex" holds the data
bytes, without the checksum, as lowercase hex. Mixed case, a bad
checksum, a character outside the charset, bad padding bits and strings
over 5000 characters all refuse.

References: nxBech32Encode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Encodes a public key as an npub.

pPubkeyHex: The public key as 64 hex characters.

Returns: The npub1 string, or empty.

Example:
put nxNpubEncode(nxKeyPublic(tSeckey)) into field "npubField"

Description:
The form to show users and share. The key must be 64 hex characters.

References: nxNpubDecode (handler), nxKeyPublic (handler)
*/
function nxNpubEncode pPubkeyHex
   return nxBareEncode("npub", pPubkeyHex)
end nxNpubEncode

/**
Summary: Decodes an npub to a hex public key.

pText: The npub1 string.

Returns: The public key as 64 hex characters, or empty.

Example:
put nxNpubDecode(field "npubField") into tPubkey

Description:
A string with another prefix, the bech32m spec or a payload that is not
32 bytes refuses. Use <nxEntityDecode> when the input could be any
entity.

References: nxNpubEncode (handler), nxEntityDecode (handler)
*/
function nxNpubDecode pText
   return nxBareDecode(pText, "npub")
end nxNpubDecode

/**
Summary: Encodes a secret key as an nsec.

pSeckeyHex: The secret key as 64 hex characters.

Returns: The nsec1 string, or empty.

Example:
put nxNsecEncode(tSeckey) into tBackupText

Description:
For explicit backup flows only. Never show or log an nsec casually, and
note that <nxUriEncode> refuses to wrap one.

References: nxNsecDecode (handler), nxKeyGenerate (handler)
*/
function nxNsecEncode pSeckeyHex
   return nxBareEncode("nsec", pSeckeyHex)
end nxNsecEncode

/**
Summary: Decodes an nsec to a hex secret key.

pText: The nsec1 string.

Returns: The secret key as 64 hex characters, or empty.

Example:
put nxNsecDecode(tBackupText) into tSeckey

Description:
A string with another prefix, the bech32m spec or a payload that is not
32 bytes refuses.

References: nxNsecEncode (handler), nxKeyIsValid (handler)
*/
function nxNsecDecode pText
   return nxBareDecode(pText, "nsec")
end nxNsecDecode

/**
Summary: Encodes an event id as a note.

pIdHex: The event id as 64 hex characters.

Returns: The note1 string, or empty.

Example:
put nxNoteEncode(tSigned["id"]) into tNote

Description:
A bare pointer to an event. To add relay hints, the author or the kind,
use <nxNeventEncode>.

References: nxNoteDecode (handler), nxNeventEncode (handler)
*/
function nxNoteEncode pIdHex
   return nxBareEncode("note", pIdHex)
end nxNoteEncode

/**
Summary: Decodes a note to a hex event id.

pText: The note1 string.

Returns: The event id as 64 hex characters, or empty.

Example:
put nxNoteDecode(tNote) into tId

Description:
A string with another prefix, the bech32m spec or a payload that is not
32 bytes refuses.

References: nxNoteEncode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Encodes a public key and relay hints as an nprofile.

pPubkeyHex: The public key as 64 hex characters.

pRelayLines: Relay URLs that may know the profile, one per line, or empty.

Returns: The nprofile1 string, or empty.

Example:
put nxNprofileEncode(tPubkey, "wss://relay.example.com") into tProfile

Description:
A NIP-19 TLV entity. The pubkey is required; the relay hints are
optional.

References: nxNprofileDecode (handler), nxNpubEncode (handler)
*/
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

/**
Summary: Decodes an nprofile.

pText: The nprofile1 string.

Returns: An array with keys "type", "pubkey" and "relays", or empty.

Example:
put nxNprofileDecode(tText) into tFields
put tFields["pubkey"] into tPubkey

Description:
"relays" holds the relay hints, one per line. Another entity type
refuses. Unknown TLV entries are ignored, as NIP-19 requires; a
truncated one refuses.

References: nxNprofileEncode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Encodes an event pointer as an nevent.

pIdHex: The event id as 64 hex characters.

pRelayLines: Relay URLs that may have the event, one per line, or empty.

pAuthorHex: The author's public key as 64 hex characters, or empty.

pKind: The event kind, or empty.

Returns: The nevent1 string, or empty.

Example:
put nxNeventEncode(tSigned["id"], "wss://relay.example.com", tSigned["pubkey"], 1) into tPointer
put nxUriEncode(tPointer) into tUri

Description:
A NIP-19 TLV entity. The id is required; relays, author and kind are
optional hints.

References: nxNeventDecode (handler), nxNoteEncode (handler), nxUriEncode (handler)
*/
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

/**
Summary: Decodes an nevent.

pText: The nevent1 string.

Returns: An array with keys "type", "id", "relays", "pubkey" and "kind", or empty.

Example:
put nxNeventDecode(tText) into tFields
put tFields["id"] into tId

Description:
Optional fields that the entity does not carry are empty. Another
entity type refuses.

References: nxNeventEncode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Encodes the coordinate of an addressable event as an naddr.

pIdentifier: The event's "d" tag value, which may be empty.

pPubkeyHex: The author's public key as 64 hex characters.

pKind: The event kind, an integer from 0 to 65535.

pRelayLines: Relay URLs that may have the event, one per line, or empty.

Returns: The naddr1 string, or empty.

Example:
put nxNaddrEncode("my-article", tPubkey, 30023, empty) into tAddr

Description:
The author and the kind are required. An identifier longer than 255
bytes refuses rather than being dropped.

References: nxNaddrDecode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Decodes an naddr.

pText: The naddr1 string.

Returns: An array with keys "type", "identifier", "pubkey", "kind" and "relays", or empty.

Example:
put nxNaddrDecode(tText) into tFields
put tFields["kind"] && tFields["identifier"] into field "coordField"

Description:
An naddr without an author or a kind refuses, as does another entity
type.

References: nxNaddrEncode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Decodes any NIP-19 entity, with or without a nostr: prefix.

pText: The entity, such as an npub, note, nprofile, nevent, naddr or nsec, optionally starting with nostr:.

Returns: An array keyed by "type" plus that entity's fields, or empty.

Example:
put nxEntityDecode(field "pasteField") into tFields
if tFields["type"] is "npub" then put tFields["pubkey"] into tPubkey

Description:
Use it for a paste box that accepts anything. The fields by type: npub
gives "pubkey", nsec "seckey", note "id"; nprofile gives "pubkey" and
"relays"; nevent "id", "relays", "pubkey" and "kind"; naddr
"identifier", "pubkey", "kind" and "relays".

Unknown TLV entries are ignored, as NIP-19 requires. A bech32m string, a
truncated TLV or a missing required field refuses. An nsec decodes here,
so handle a pasted secret key deliberately.

References: nxUriDecode (handler), nxBech32Decode (handler)
*/
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

/**
Summary: Builds a NIP-21 nostr: URI for a shareable entity.

pEntity: An npub, note, nprofile, nevent or naddr string.

Returns: The URI, or empty.

Example:
put nxUriEncode(nxNpubEncode(tPubkey)) into tUri

Description:
The entity is decoded first, so an invalid one refuses. An nsec
always refuses: a secret key in a URI ends up in somebody's chat
log. An input that already starts with nostr: comes back unchanged.

References: nxUriDecode (handler), nxEntityDecode (handler)
*/
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

/**
Summary: Decodes a NIP-21 nostr: URI.

pUri: The URI, starting with nostr:.

Returns: The entity fields, as from nxEntityDecode, or empty.

Example:
put nxUriDecode("nostr:" & tNpub) into tFields

Description:
Text without the nostr: prefix refuses, and so does a URI carrying an
nsec.

References: nxUriEncode (handler), nxEntityDecode (handler)
*/
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
-- way. ENGINE-PROVEN 2026-08-24 (Windows x86_64, OXT 9.6.3, the member
-- harness folded into the suite paste, 274/0/2), and exactly this much ran:
-- the official conversation-key and message-key vectors, all 24 official
-- padded-length pairs, the refusals that precede the cipher (the MAC is
-- checked before any cipher runs), and one official encrypt_decrypt vector
-- (a 1-byte plaintext at a pinned nonce) decrypted, then re-encrypted byte
-- for byte, through the real SodiumXT ABI-10 cipher. Do not read that
-- record as covering more: multi-block and non-ASCII plaintexts and the
-- oversized refusal have run HEADLESSLY only (tools/check-script-vectors.py
-- executes this file over the committed sibling binaries), the official
-- invalid-payload rows go through the oracle, not this file
-- (tools/nostr-kat.py), and an encrypt with a FRESH nonce (pNonceHex empty)
-- has run nowhere.
-- ==========================================================================

/**
Summary: Derives the NIP-44 v2 conversation key between two keys.

pSeckeyHex: Your secret key as 64 hex characters.

pPubkeyHex: The other party's public key as 64 hex characters.

Returns: The conversation key as 64 hex characters, or empty.

Example:
put nxNip44ConversationKey(tSeckey, tTheirPubkey) into tConvKey

Description:
Needs CoinXT (cxEcdh and cxHmacSha256). The key is HKDF-extract with the
salt "nip44-v2" over the shared ECDH x coordinate, and it is the same
from both sides. <nxNip44Encrypt> and <nxNip44Decrypt> derive it
themselves; call this to inspect or cache it.

References: nxNip44MessageKeys (handler), nxNip44Encrypt (handler)
*/
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

/**
Summary: Derives the NIP-44 v2 per-message keys from a conversation key and nonce.

pConvKeyHex: The conversation key as 64 hex characters.

pNonceHex: The message nonce as 64 hex characters.

Returns: An array with keys "chachaKey", "chachaNonce" and "hmacKey" (hex), or empty.

Example:
put nxNip44MessageKeys(tConvKey, tNonceHex) into tKeys
put tKeys["hmacKey"] into tMacKey

Description:
Needs CoinXT (cxHmacSha256). HKDF-expand to 76 bytes, split into a
32-byte ChaCha20 key, a 12-byte ChaCha20 nonce and a 32-byte HMAC key.
Exposed for test vectors and for building your own NIP-44 tooling.

References: nxNip44ConversationKey (handler), nxNip44Encrypt (handler)
*/
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

/**
Summary: Returns the NIP-44 v2 padded length for a plaintext length.

pLen: The plaintext length in bytes, a positive integer.

Returns: The padded length in bytes, or empty.

Example:
put nxNip44PaddedLen(100) into tPadded

Description:
Lengths up to 32 pad to 32; longer ones round up in chunks that grow
with the length, as NIP-44 defines. This is arithmetic only: the 1 to
65535 byte limit is enforced when <nxNip44Encrypt> pads.

References: nxNip44Encrypt (handler)
*/
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

/**
Summary: Tells whether the NIP-44 cipher is available right now.

Returns: true or false.

Example:
if not nxNip44HasCipher() then answer "Encrypted messages need SodiumXT ABI 10 or later"

Description:
A live probe of SodiumXT's sxChaCha20IetfXor, which shipped in SodiumXT
ABI 10. Unlike the cached "canNip44Cipher" of <nxProbeCapabilities>, it
notices an upgrade without a restart.

References: nxProbeCapabilities (handler), nxNip44Encrypt (handler)
*/
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

/**
Summary: Encrypts a message for another Nostr key with NIP-44 v2.

pSeckeyHex: Your secret key as 64 hex characters.

pPubkeyHex: The recipient's public key as 64 hex characters.

pPlaintext: The message, 1 to 65535 bytes.

pNonceHex: Empty for a fresh random nonce, or 64 hex characters for test vectors only.

Returns: The versioned payload in standard base64, or empty.

Example:
put nxNip44Encrypt(tSeckey, tTheirPubkey, "meet at noon", empty) into tPayload
if tPayload is empty then answer "could not encrypt:" && nxLastError()

Description:
Needs CoinXT, and SodiumXT ABI 10 or later for the cipher and the nonce.
With an older SodiumXT it fails closed with a reason naming
sxChaCha20IetfXor. Plaintext longer than 65535 bytes refuses.

Always pass empty for pNonceHex in an app: reusing a nonce breaks the
encryption. A fixed nonce exists only to reproduce published vectors.

References: nxNip44Decrypt (handler), nxNip44HasCipher (handler)
*/
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

/**
Summary: Decrypts a NIP-44 v2 payload.

pSeckeyHex: Your secret key as 64 hex characters.

pPubkeyHex: The sender's public key as 64 hex characters.

pPayload: The base64 payload.

Returns: The plaintext, or empty.

Example:
put nxNip44Decrypt(tSeckey, tSenderPubkey, tPayload) into tMessage
if tMessage is empty then answer "could not decrypt:" && nxLastError()

Description:
Needs CoinXT, and SodiumXT ABI 10 or later. The MAC is checked first,
over the nonce and ciphertext, with a constant-time compare, and the
cipher runs only if it matches. Every step is strict: an unknown version,
a short payload, bad base64, a wrong key or tampering, or padding that
does not agree all refuse with the reason recorded.

References: nxNip44Encrypt (handler), nxNip44ConversationKey (handler)
*/
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

/**
Summary: Builds a NIP-01 filter object from an array.

pFilter: An array of filter fields (see the description).

Returns: The filter as one line of JSON, or empty.

Example:
put tAuthorPubkey into tFilter["authors"]
put "1,7" into tFilter["kinds"]
put 50 into tFilter["limit"]
put nxFilterBuild(tFilter) into tFilterJson
nxrSubscribe tRelay, "my-feed", tFilterJson

Description:
The keys: "ids" and "authors" (64-hex values, one per line), "kinds"
(a comma list of kind numbers), "since", "until" and "limit" (non-negative
integers), "search" (text), and any single-letter tag filter keyed "#e",
"#p" and so on (values one per line). Absent or empty keys are left out.

Fields come out in a fixed order, so the same array always gives the
same text. An invalid value refuses with the reason recorded.

References: nxClientReq (handler), nxrSubscribe (handler), nxFilterMatches (handler)
*/
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

/**
Summary: Tells whether an event matches a NIP-01 filter.

pFilterJson: The filter JSON object.

pEvent: The event array.

Returns: true or false.

Example:
if nxFilterMatches(tFilterJson, tEvent) then put tEvent["content"] & return after field "feedField"

Description:
Every condition in the filter must hold. List conditions (ids, authors,
kinds, tag filters) need one exact match; since and until are inclusive.
Anything doubtful, including a filter that is not a JSON object or an
event with a bad shape, returns false.

References: nxFilterBuild (handler)
*/
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

/**
Summary: Builds a NIP-01 REQ message.

pSubId: The subscription id, 1 to 64 characters.

pFiltersJson: One filter JSON object per line; at least one.

Returns: The REQ message text, or empty.

Example:
put nxClientReq("my-feed", nxFilterBuild(tFilter)) into tWire

Description:
<nxrSubscribe> builds and sends the same message itself; use this for a
transport of your own. Each line must be a JSON object.

References: nxFilterBuild (handler), nxClientClose (handler), nxrSubscribe (handler)
*/
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

/**
Summary: Builds a NIP-01 CLOSE message.

pSubId: The subscription id, 1 to 64 characters.

Returns: The CLOSE message text, or empty.

Example:
put nxClientClose("my-feed") into tWire

Description:
<nxrUnsubscribe> builds and sends the same message itself.

References: nxClientReq (handler), nxrUnsubscribe (handler)
*/
function nxClientClose pSubId
   if pSubId is empty or the number of chars of pSubId > kNxSubIdMax then
      nxSetError "nxClientClose: the subscription id must be 1 to" && kNxSubIdMax && "characters"
      return empty
   end if
   return "[" & quote & "CLOSE" & quote & "," & quote & nxJsonEscape(pSubId) & quote & "]"
end nxClientClose

/**
Summary: Builds a NIP-01 EVENT message for a signed event.

pEvent: The signed event array.

Returns: The EVENT message text, or empty.

Example:
put nxClientEvent(tSigned) into tWire

Description:
Refuses an event without an id and signature: sign it with
<nxEventSign> first. <nxrPublish> builds and sends the same message
itself.

References: nxEventSign (handler), nxrPublish (handler)
*/
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

/**
Summary: Builds a NIP-42 AUTH message for a signed authentication event.

pEvent: The signed kind 22242 event array.

Returns: The AUTH message text, or empty.

Example:
put nxClientAuth(tSignedAuth) into tWire

Description:
Refuses anything but a signed kind 22242 event, as built by
<nxAuthBuild> and signed by <nxEventSign>. <nxrAuth> builds and sends
the same message itself.

References: nxAuthBuild (handler), nxrAuth (handler)
*/
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

/**
Summary: Parses one relay-to-client message.

pWire: The message text, a JSON array.

Returns: An array keyed by "type" plus that message's fields, or empty.

Example:
put nxRelayParse(tWire) into tMsg
if tMsg["type"] is "EVENT" then put nxEventFromJson(tMsg["eventJson"]) into tEvent

Description:
Types and fields: EVENT ("subId", "eventJson", the event object's exact
text), OK ("eventId", "accepted", "reason"), EOSE ("subId"), CLOSED
("subId", "reason"), NOTICE ("notice") and AUTH ("challenge"). Any other
type gives "unknown" with the text in "raw".

Message types compare byte for byte, so "event" is not "EVENT". An
EVENT is not verified here: parse it with <nxEventFromJson> and check it
with <nxEventVerify>.

References: nxEventFromJson (handler), nxEventVerify (handler)
*/
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

/**
Summary: Splits a ws:// or wss:// URL into its parts.

pUrl: The websocket URL.

Returns: An array with keys "scheme", "secure", "host", "port" and "path", or empty.

Example:
put nxWsUrlParse("wss://relay.example.com/") into tParts
put tParts["host"] into tHost

Description:
A missing port defaults to 80 for ws and 443 for wss, and a missing path
to /. Whitespace, another scheme, a missing host, a port outside 1 to
65535 and IPv6 bracket addresses refuse.

References: nxWsHandshakeRequest (handler), nxrConnect (handler)
*/
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
      -- Nested for the same reason as nxJsonPathNode: `or` evaluates both
      -- operands, so `tPortText + 0` on a non-numeric port ("wss://h:abc/")
      -- was a hard engine error rather than this clean refusal.
      if not nxIsDigits(tPortText) then
         nxSetError "nxWsUrlParse: the port must be 1 to 65535"
         return empty
      end if
      if tPortText + 0 < 1 or tPortText + 0 > 65535 then
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

/**
Summary: Builds the HTTP upgrade request that opens a websocket.

pHost: The host name.

pPort: The port number.

pPath: The request path, such as /.

pKeyB64: The Sec-WebSocket-Key, base64.

pSecure: true for wss, false for ws.

Returns: The request text with CRLF line endings, or empty.

Example:
put nxWsHandshakeRequest("relay.example.com", 443, "/", tKeyB64, true) into tRequest

Description:
The Host header leaves out the port only when it is the default for the
scheme (80 for ws, 443 for wss), which is why the secure flag is an
argument. Host, path and key are required. Only needed for a transport
of your own; the relay client calls it for you.

References: nxWsAcceptFor (handler), nxWsUrlParse (handler)
*/
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

/**
Summary: Returns the Sec-WebSocket-Accept value a server must answer with.

pKeyB64: The Sec-WebSocket-Key the client sent, base64.

Returns: The expected accept value, base64.

Example:
put nxWsAcceptFor(tKeyB64) into tExpected

Description:
Base64 of SHA-1 over the key followed by the RFC 6455 GUID, using the
engine's own sha1Digest. Compare the server's answer with it byte for
byte.

References: nxWsHandshakeRequest (handler)
*/
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

/**
Summary: Builds one masked client websocket frame.

pOpcode: The frame opcode, 0 to 15 (1 for text, 8 close, 9 ping, 10 pong).

pPayload: The payload bytes.

pMaskHex: The 4-byte mask as 8 hex characters.

Returns: The frame bytes, or empty.

Example:
put nxWsFrameEncode(1, textEncode(tText, "UTF-8"), "1a2b3c4d") into tFrame

Description:
FIN is set, the payload is masked as RFC 6455 requires of a client, and
nothing is fragmented. A control frame (opcode 8 and up) carries at most
125 bytes, and any payload is capped at 8 MB. Draw a fresh random mask
for every frame; a fixed mask is for test vectors.

References: nxWsFrameDecode (handler)
*/
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

/**
Summary: Parses one websocket frame at the start of a buffer.

pBuffer: The received bytes.

Returns: An array describing the frame (see the description).

Example:
put nxWsFrameDecode(tBuffer) into tFrame
if tFrame["complete"] is true then put byte (tFrame["consumed"] + 1) to -1 of tBuffer into tBuffer

Description:
When "complete" is false, read more: "needMore" says how many bytes are
missing, or 0 when not yet known. When it is true, "fin", "opcode",
"masked", "payload" (unmasked) and "consumed" (the bytes to drop from
the buffer) are set.

A non-empty "error" means the stream cannot recover (reserved bits, a
length over the 8 MB cap, an oversized or fragmented control frame):
close the connection.

References: nxWsFrameEncode (handler)
*/
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

/**
Summary: Returns the NIP-13 proof-of-work difficulty of an event id.

pIdHex: The event id as 64 hex characters.

Returns: The number of leading zero bits, or empty.

Example:
put nxPowDifficulty(tEvent["id"]) into tBits

Description:
NIP-13 measures work as the leading zero bits of the id.

References: nxPowCheck (handler)
*/
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

/**
Summary: Tells whether an event meets a NIP-13 proof-of-work target.

pEvent: The event array.

pMinBits: The minimum number of leading zero bits, 0 to 256.

Returns: true or false.

Example:
if not nxPowCheck(tEvent, 20) then put "not enough work" into tVerdict

Description:
The id must have at least pMinBits leading zero bits, and a target the
event committed to in its "nonce" tag must itself be at least pMinBits,
so a low-target miner that got lucky is refused, as NIP-13 asks. A
committed target that is not a number refuses.

References: nxPowDifficulty (handler)
*/
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
         -- Nested, same `or` rule. This one has no caller in the tree today,
         -- so it is not reachable now - but the tag value is straight off the
         -- relay, and a future caller would inherit the hard error.
         if not nxIsDigits(tTarget) then
            nxSetError "nxPowCheck: the committed target" && tTarget && "is below" && pMinBits
            return false
         end if
         if tTarget + 0 < pMinBits then
            nxSetError "nxPowCheck: the committed target" && tTarget && "is below" && pMinBits
            return false
         end if
      end if
   end repeat
   return true
end nxPowCheck

/**
Summary: Returns the URL to fetch to check a NIP-05 identifier.

pIdentifier: The identifier, name@domain, or a bare domain.

Returns: The https URL of the domain's nostr.json, or empty.

Example:
put nxNip05Url("alice@example.com") into tUrl
put URL tUrl into tBody
put nxNip05Verify(tBody, "alice", tPubkey) into tVerified

Description:
A bare domain means the name "_". This library does no I/O, so the
fetch is yours. A malformed identifier, or a domain containing /, ?, #
or @, refuses.

References: nxNip05Verify (handler)
*/
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

/**
Summary: Tells whether a fetched nostr.json maps a name to a public key.

pJsonBody: The nostr.json document the app fetched.

pUserName: The name part of the identifier.

pPubkeyHex: The expected public key as 64 hex characters.

Returns: true or false.

Example:
put nxNip05Verify(tBody, "alice", tPubkey) into tVerified

Description:
The hex comparison ignores case. A name containing / cannot be looked up
and refuses, as does a pubkey that is not 64 hex characters.

References: nxNip05Url (handler)
*/
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

/**
Summary: Reads the common NIP-11 relay information fields.

pJsonBody: The relay information document the app fetched.

Returns: An array of the fields, or empty.

Example:
put nxRelayInfoParse(tBody) into tInfo
put tInfo["name"] && tInfo["supportedNips"] into field "relayField"

Description:
The keys are "name", "description", "pubkey", "contact", "software",
"version" and "supportedNips", a comma list. An absent field is empty. A
body that is not a JSON object refuses. The fetch is yours: this
library does no I/O.

References: nxJsonGet (handler)
*/
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
