script "RiptideSocial"
-- riptide.livecodescript - Riptide Social, phases 1-3: the identity
-- foundation, the pure-compute feed layer, the live feed layer, and the
-- media layer, as a pure-LiveCodeScript library over the installed suite
-- extensions (docs/RIPTIDE-SOCIAL-SPEC.md sections 3-4).
--
-- STATUS (honesty convention): phases 1 and 2 had their OXT pass on
-- 2026-08-12 via the folded suite harness: 133/133, no skips, hasSha3 true.
-- The phase-2 run covered the pure helpers, synthetic ingest verifiers, and
-- real-session puts and accepted lookup requests. Its propagation half ("a
-- second machine walks the chain") CLOSED 2026-08-13: the maintainer ran
-- examples/riptide-social.livecodescript on two machines - identities
-- created on both, feeds published and received in both directions through
-- the real DHT (the stack renders a post only after rsIngestHead and
-- rsIngestPost verify it, so a received feed is a verified chain walk).
-- The phase-3 MEDIA layer (rsMediaCreate / rsMediaFetch / rsMediaStatus,
-- 2026-08-14) is verified statically and by the harness's refusal paths;
-- its live create/seed/fetch flow and the phase-3 done-criterion (a
-- follower plays a video mid-download) still NEED an OXT pass.
--
-- WHAT THIS LAYER OWNS
--   - the master seed and the RIPTKEY1 sealed key file (Argon2id + secretbox,
--     the BTXPREF1 convention with riptide's own magic)
--   - the KDF subkey tree: one 32-byte master -> identity / DM / LAN / anon
--     subkeys via sxKdfDerive, context "riptide\0" (8 bytes exactly)
--   - identity -> handle (ed25519 public key, 64 hex) -> .onion address
--   - the rendezvous derivations: inboxId and roomId
--   - the RSH1 feed-head and RSP1 post-record framings, build + parse +
--     signature verification, caps enforced on BOTH sides
--   - the LIVE feed layer (phase 2): head publish through the external-
--     signing seam (btDhtBep44SignBuf semantics rebuilt in script, signed by
--     sxSignDetached, stored by btDhtPutSigned - the identity secret never
--     enters libtorrent), post publish as content-addressed immutable items,
--     the async fetch requests, and the INGEST verifiers the app's poll loop
--     feeds each dhtMutableItem / dhtImmutableItem event through. The
--     library NEVER starts, stops, or polls a session: the app owns the one
--     session per process and its event loop, and passes the handle in.
--   - the MEDIA layer (phase 3): attach a file as a trackerless torrent
--     seeded in place (rsMediaCreate -> the 40-hex info-hash a post's
--     media list carries), fetch-and-co-seed by hash with an optional
--     sequential playback mode (rsMediaFetch), and the per-torrent status
--     snapshot a player paints from (rsMediaStatus, btTorrentStatus plus
--     the first file's on-disk path and per-file progress). Payload never
--     crosses the FFI: libtorrent moves the bytes engine-to-disk, script
--     only ever sees hashes, paths, and counters.
--
-- EXTENSION DEPENDENCIES (probed, never assumed; rsProbeCapabilities):
--   SodiumXT  HARD  the trust root; without it this library refuses to work.
--                   At ABI 7 it also serves sxSha3_256, the preferred SHA3
--                   provider for the OFFLINE .onion self-computation (shipped
--                   2026-08-11, closing onionxt docs/08 gap #2).
--   coinxt    soft  cxSha3_256 is the FALLBACK SHA3 provider (the same
--                   vendored FIPS-202 code; what this app composed before
--                   sodiumxt shipped it). With neither ABI 7 nor coinxt,
--                   rsOnionFromPublicKey returns empty with a clear error;
--                   the VERIFY direction below still works.
--   onionxt   soft  oxPublicKeyFromAddress verifies a CLAIMED onion against
--                   a handle offline (structural decode, no daemon needed)
--   torrentxt soft  the phase-2 live feed layer drives btDhtPutSigned /
--                   btDhtGetMutable / btDhtPutImmutable / btDhtGetImmutable,
--                   and the phase-3 media layer drives btCreateTorrent /
--                   btAddTorrentFile / btAddMagnet / btFindTorrent /
--                   btInfoHash / btSetSequentialDownload / btTorrentStatus /
--                   btFileList, all through a session the APP owns. Absent
--                   torrentxt (or a dead handle), every live handler refuses
--                   with a clear story; the pure-compute layer is untouched.
--   enetxt / datachannelxt: probed and reported for the app's capability
--                   matrix; nothing in phases 1-2 calls them.
--
-- ERROR CONVENTION: functions return empty (or false) on failure and record
-- the reason; rsLastError() returns it. sx* failures throw, so every foreign
-- call in here sits inside a try. No handler in this file ever throws.
--
-- WIRE FORMATS (pinned byte-for-byte by tests/riptide_golden_test.py; the
-- magic IS the version - any framing change bumps it, never a silent fix):
--   RIPTKEY1: "RIPTKEY1" "E" salt(16) sxSecretBox(seed32, argon2idKey)
--   RSH1 head: magic(4) seq(u64 BE) nameLen(u8) name latestPostTarget(40 hex)
--     prekeyTarget(40 hex) onionLen(u8: 0 or 62) onionAddr
--     profileMetaTarget(40 hex)
--   RSP1 post: magic(4) timestamp(u64 BE) prevPostTarget(40 hex) kind(1)
--     kind "D": textLen(u16 BE) text(UTF-8)
--     kind "C": chunkCount(u8, 1..16) then chunkCount * 40-hex targets
--     mediaCount(u8, 0..8) then mediaCount * 40-hex info-hashes
--     authorSig(64): ed25519 detached over every byte before it
--   u64 travels as hi:u32 lo:u32 via binaryEncode("NN"), the BTXO discipline.
--   DHT targets travel as 40 ASCII hex; the all-zeros target means "none".
--   On the DHT (phase 2): the stored BEP44 v is the BENCODED byte string of
--     the record ("<len>:<bytes>"); the canonical signing buffer is
--     [4:salt<n>:<salt>] 3:seqi<seq>e 1:v <bencoded v> (BEP44, the exact
--     bytes btDhtBep44SignBuf returns and torrent_shim.cpp verifies); an
--     immutable item's target is SHA-1 of the bencoded value.

constant kRsVersion = "0.3.0"
constant kRsKeyMagic = "RIPTKEY1"
constant kRsHeadMagic = "RSH1"
constant kRsPostMagic = "RSP1"
constant kRsHeadSalt = "riptide-head"
constant kRsKdfContextText = "riptide"
constant kRsInboxSuffix = "riptide-inbox"
constant kRsZeroTarget = "0000000000000000000000000000000000000000"
constant kRsSubkeyIdentity = "1"
constant kRsSubkeyDm = "2"
constant kRsSubkeyLan = "3"
constant kRsSubkeyAnonBase = 100
constant kRsMaxDisplayName = 64
constant kRsMaxMedia = 8
constant kRsMaxChunks = 16
constant kRsMaxRecord = 1000
constant kRsMaxSalt = 64
constant kRsOnionAddrLen = 62
constant kRsArgonOps = "2"
constant kRsBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
constant kRsChecksumPrefix = ".onion checksum"

local sRsLastError
local sRsProbed
local sRsCaps

--------------------------------------------------------------------------
-- diagnostics and capability probes
--------------------------------------------------------------------------

function rsVersion
   return "Riptide" && kRsVersion && \
         "(phase 3: identity, the live feed, media)"
end rsVersion

function rsLastError
   return sRsLastError
end rsLastError

private command rsSetError pMessage
   put pMessage into sRsLastError
end rsSetError

-- Probe each extension once, each in its own try, into a cached array.
-- SodiumXT gets a REAL round-trip (the family's chCanEncrypt pattern);
-- the rest are cheap presence probes. Fail-closed: a missing extension
-- disables exactly its feature and never another one.
function rsProbeCapabilities
   local tCaps, tKey, tBox, tOpened, tIgnore
   if sRsProbed is true then return sRsCaps
   put false into tCaps["canCrypto"]
   put false into tCaps["hasTorrent"]
   put false into tCaps["hasOnion"]
   put false into tCaps["hasDataChannel"]
   put false into tCaps["hasEnet"]
   put false into tCaps["hasCoin"]
   try
      put sxRandomBytes(32) into tKey
      put sxSecretBox(textEncode("probe", "ASCII"), tKey) into tBox
      put sxSecretBoxOpen(tBox, tKey) into tOpened
      put (textDecode(tOpened, "ASCII") is "probe") into tCaps["canCrypto"]
   catch tIgnore
      put false into tCaps["canCrypto"]
   end try
   try
      put btLastError() into tIgnore
      put true into tCaps["hasTorrent"]
   catch tIgnore
      put false into tCaps["hasTorrent"]
   end try
   try
      put (oxVersion() is not empty) into tCaps["hasOnion"]
   catch tIgnore
      put false into tCaps["hasOnion"]
   end try
   try
      put (dcLibraryVersion() is not empty) into tCaps["hasDataChannel"]
   catch tIgnore
      put false into tCaps["hasDataChannel"]
   end try
   try
      put (enLibraryVersion() is not empty) into tCaps["hasEnet"]
   catch tIgnore
      put false into tCaps["hasEnet"]
   end try
   try
      put (cxSha3_256Len() is 32) into tCaps["hasCoin"]
   catch tIgnore
      put false into tCaps["hasCoin"]
   end try
   -- Derived capability: SHA3-256 from EITHER provider (sodiumxt ABI 7's
   -- sxSha3_256, or coinxt's cxSha3_256) - what the offline onion
   -- self-computation actually needs. A real call, not a version sniff.
   put (the number of bytes in rsSha3(textEncode("probe", "ASCII")) is 32) \
         into tCaps["hasSha3"]
   put tCaps into sRsCaps
   put true into sRsProbed
   return sRsCaps
end rsProbeCapabilities

-- Constants are script-scoped in xTalk, so the two wire values an APP needs
-- are exposed as functions.
function rsHeadSalt
   return kRsHeadSalt
end rsHeadSalt

function rsZeroTarget
   return kRsZeroTarget
end rsZeroTarget

--------------------------------------------------------------------------
-- the master seed and the RIPTKEY1 sealed key file
--------------------------------------------------------------------------

function rsGenerateMasterSeed
   local tSeed, tErr
   try
      put sxRandomBytes(32) into tSeed
   catch tErr
      rsSetError "rsGenerateMasterSeed: SodiumXT is required:" && tErr
      return empty
   end try
   return tSeed
end rsGenerateMasterSeed

-- Seal the master seed under a passphrase: a fresh random 16-byte salt on
-- every save, Argon2id (opslimit "2", interactive memlimit - the parameters
-- every sealed file in the family uses; both ends must agree), then
-- secretbox. Layout: "RIPTKEY1" "E" salt(16) box(nonce24 ct32 mac16).
function rsSealMasterSeed pSeed, pPassphrase
   local tSalt, tKey, tOut, tErr
   if the number of bytes in pSeed is not 32 then
      rsSetError "rsSealMasterSeed: the master seed must be 32 bytes"
      return empty
   end if
   if pPassphrase is empty then
      rsSetError "rsSealMasterSeed: an empty passphrase is refused"
      return empty
   end if
   try
      put sxRandomBytes(16) into tSalt
      put sxPwHash(textEncode(pPassphrase, "UTF-8"), tSalt, 32, \
            kRsArgonOps, sxPwMemInteractive()) into tKey
      put textEncode(kRsKeyMagic & "E", "ASCII") & tSalt & \
            sxSecretBox(pSeed, tKey) into tOut
   catch tErr
      rsSetError "rsSealMasterSeed:" && tErr
      return empty
   end try
   return tOut
end rsSealMasterSeed

-- Unlock: parse the layout strictly, re-derive the wrap key, open the box.
-- A wrong passphrase fails the Poly1305 tag inside sxSecretBoxOpen - it
-- throws, we catch, and the caller gets empty plus a clear reason. It can
-- never silently mis-decrypt.
function rsOpenMasterSeed pFileBytes, pPassphrase
   local tSalt, tSealed, tKey, tSeed, tHeader, tErr
   -- A RIPTKEY1 file is EXACTLY 97 bytes: 9 (magic "RIPTKEY1E") + 16 (salt) +
   -- 72 (sxSecretBox of a 32-byte seed = nonce 24 + ct 32 + mac 16). Refuse a
   -- wrong length up front rather than leaning on the Poly1305 tag to catch a
   -- truncated file (it does catch it - this is just an honest, explicit gate).
   if the number of bytes in pFileBytes is not 97 then
      rsSetError "rsOpenMasterSeed: not a 97-byte RIPTKEY1 file"
      return empty
   end if
   put textDecode(byte 1 to 9 of pFileBytes, "ASCII") into tHeader
   if tHeader is not (kRsKeyMagic & "E") then
      rsSetError "rsOpenMasterSeed: not a RIPTKEY1 sealed key file"
      return empty
   end if
   put byte 10 to 25 of pFileBytes into tSalt
   put byte 26 to -1 of pFileBytes into tSealed
   try
      put sxPwHash(textEncode(pPassphrase, "UTF-8"), tSalt, 32, \
            kRsArgonOps, sxPwMemInteractive()) into tKey
      put sxSecretBoxOpen(tSealed, tKey) into tSeed
   catch tErr
      rsSetError "rsOpenMasterSeed: wrong passphrase or corrupted key file"
      return empty
   end try
   if the number of bytes in tSeed is not 32 then
      rsSetError "rsOpenMasterSeed: the sealed payload is not a 32-byte seed"
      return empty
   end if
   return tSeed
end rsOpenMasterSeed

--------------------------------------------------------------------------
-- the KDF subkey tree (spec section 3.2)
--------------------------------------------------------------------------

-- The context is the 8-byte string "riptide" plus one NUL - built here
-- because a constant cannot hold a NUL byte. sxKdfDerive requires exactly
-- 8 bytes (crypto_kdf_CONTEXTBYTES) and throws on any other length.
private function rsKdfContext
   return textEncode(kRsKdfContextText, "ASCII") & numToByte(0)
end rsKdfContext

private function rsSubkey pMaster, pSubkeyId
   local tOut, tErr
   if the number of bytes in pMaster is not 32 then
      rsSetError "rsSubkey: the master seed must be 32 bytes"
      return empty
   end if
   try
      put sxKdfDerive(pMaster, pSubkeyId, rsKdfContext(), 32) into tOut
   catch tErr
      rsSetError "rsSubkey:" && tErr
      return empty
   end try
   return tOut
end rsSubkey

function rsIdentitySeed pMaster
   return rsSubkey(pMaster, kRsSubkeyIdentity)
end rsIdentitySeed

function rsDmSeed pMaster
   return rsSubkey(pMaster, kRsSubkeyDm)
end rsDmSeed

function rsLanKey pMaster
   return rsSubkey(pMaster, kRsSubkeyLan)
end rsLanKey

function rsAnonSeed pMaster, pIndex
   local tId
   if pIndex is not an integer or pIndex < 0 then
      rsSetError "rsAnonSeed: the persona index must be a non-negative integer"
      return empty
   end if
   put kRsSubkeyAnonBase + pIndex into tId
   return rsSubkey(pMaster, tId)
end rsAnonSeed

--------------------------------------------------------------------------
-- identity -> handle -> onion
--------------------------------------------------------------------------

-- The handle IS the ed25519 public key of the identity seed, as 64 lowercase
-- hex. tests/cross-member-test.py pins sxSignKeypairFromSeed and libtorrent's
-- btDhtKeypair to the same public point, so this equals
-- btDhtKeypair(seedHex)["publicKey"] without the seed ever entering torrentxt.
function rsIdentityKeys pSeed
   local tPub, tSecret, tKeys, tErr
   if the number of bytes in pSeed is not 32 then
      rsSetError "rsIdentityKeys: the identity seed must be 32 bytes"
      return empty
   end if
   try
      sxSignKeypairFromSeed pSeed, tPub, tSecret
   catch tErr
      rsSetError "rsIdentityKeys:" && tErr
      return empty
   end try
   put tPub into tKeys["publicKey"]
   put tSecret into tKeys["secretKey"]
   put rsBinToHexString(tPub) into tKeys["handle"]
   if tKeys["handle"] is empty then return empty
   return tKeys
end rsIdentityKeys

function rsHandleFromSeed pSeed
   local tKeys
   put rsIdentityKeys(pSeed) into tKeys
   if tKeys is empty then return empty
   return tKeys["handle"]
end rsHandleFromSeed

-- SHA3-256 with two providers, preferred order fixed: sodiumxt ABI 7's
-- sxSha3_256 (shipped 2026-08-11 precisely for this checksum; the trust root
-- should serve its own hash), then coinxt's cxSha3_256 (the same vendored
-- FIPS-202 code; the provider this app composed before sodiumxt shipped it).
-- Empty when neither is installed. Both produce identical bytes, so nothing
-- downstream cares which answered - the golden vectors pin the output, not
-- the provider.
private function rsSha3 pData
   local tHash, tErr
   try
      put sxSha3_256(pData) into tHash
      if the number of bytes in tHash is 32 then return tHash
   catch tErr
      put empty into tHash
   end try
   try
      put cxSha3_256(pData) into tHash
      if the number of bytes in tHash is 32 then return tHash
   catch tErr
      put empty into tHash
   end try
   return empty
end rsSha3

-- The OFFLINE .onion self-computation: base32(pubkey || checksum || 0x03)
-- where checksum = SHA3-256(".onion checksum" || pubkey || 0x03)[1..2].
-- SHA3-256 comes from sodiumxt ABI 7 (sxSha3_256) or coinxt (cxSha3_256);
-- without either this returns empty with that story in rsLastError(). The
-- VERIFY direction (rsVerifyOnionClaim) does not need SHA3 at all.
function rsOnionFromPublicKey pPub
   local tHash
   if the number of bytes in pPub is not 32 then
      rsSetError "rsOnionFromPublicKey: the public key must be 32 bytes"
      return empty
   end if
   put rsSha3(textEncode(kRsChecksumPrefix, "UTF-8") & pPub & \
         numToByte(3)) into tHash
   if tHash is empty then
      rsSetError "rsOnionFromPublicKey: the offline .onion checksum needs" && \
            "SHA3-256 from sodiumxt ABI 7 (sxSha3_256) or coinxt" && \
            "(cxSha3_256); install either, or read the address from" && \
            "oxServiceAddress after publishing"
      return empty
   end if
   return rsBase32Encode(pPub & (byte 1 to 2 of tHash) & numToByte(3)) & \
         ".onion"
end rsOnionFromPublicKey

function rsOnionFromHandle pHandleHex
   local tPub
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsOnionFromHandle: the handle must be 64 hex chars"
      return empty
   end if
   return rsOnionFromPublicKey(tPub)
end rsOnionFromHandle

-- Verify a CLAIMED onion address (e.g. from a followee's RSH1 head) against
-- the handle you already trust: extract the embedded public key with
-- onionxt's offline decoder and compare constant-time. This is the
-- security-relevant direction - the checksum is only a typo guard - and it
-- works today with no SHA3 and no tor daemon.
function rsVerifyOnionClaim pOnionAddr, pHandleHex
   local tClaimed, tExpected, tErr
   try
      put oxPublicKeyFromAddress(pOnionAddr) into tClaimed
   catch tErr
      rsSetError "rsVerifyOnionClaim: needs onionxt (oxPublicKeyFromAddress)"
      return false
   end try
   if the number of bytes in tClaimed is not 32 then
      rsSetError "rsVerifyOnionClaim: not a structurally valid onion address"
      return false
   end if
   put rsHexToBin(pHandleHex) into tExpected
   if the number of bytes in tExpected is not 32 then
      rsSetError "rsVerifyOnionClaim: the handle must be 64 hex chars"
      return false
   end if
   try
      return sxMemEqual(tClaimed, tExpected)
   catch tErr
      rsSetError "rsVerifyOnionClaim:" && tErr
      return false
   end try
end rsVerifyOnionClaim

--------------------------------------------------------------------------
-- rendezvous derivations (spec sections 5.1, 5.2)
--------------------------------------------------------------------------

-- The deterministic inbox swarm id: BLAKE2b-20(pubkey || "riptide-inbox"),
-- as 40 hex - anyone who knows your handle can join the same phantom swarm.
function rsInboxId pHandleHex
   local tPub, tOut, tErr
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsInboxId: the handle must be 64 hex chars"
      return empty
   end if
   try
      put sxHash(tPub & textEncode(kRsInboxSuffix, "ASCII"), 20) into tOut
   catch tErr
      rsSetError "rsInboxId:" && tErr
      return empty
   end try
   return rsBinToHexString(tOut)
end rsInboxId

-- The pairwise room id: BLAKE2b-20(sortedConcat(pkA, pkB) || sessionSalt).
-- Sorted by lowercase hex order (equals raw byte order), so both peers
-- derive the same id no matter who computes it.
function rsRoomId pPkAHex, pPkBHex, pSessionSalt
   local tA, tB, tCat, tOut, tErr
   put toLower(pPkAHex) into tA
   put toLower(pPkBHex) into tB
   if not rsIsHexOfLen(tA, 64) or not rsIsHexOfLen(tB, 64) then
      rsSetError "rsRoomId: both public keys must be 64 hex chars"
      return empty
   end if
   if tA <= tB then
      put rsHexToBin(tA) & rsHexToBin(tB) into tCat
   else
      put rsHexToBin(tB) & rsHexToBin(tA) into tCat
   end if
   try
      put sxHash(tCat & pSessionSalt, 20) into tOut
   catch tErr
      rsSetError "rsRoomId:" && tErr
      return empty
   end try
   return rsBinToHexString(tOut)
end rsRoomId

--------------------------------------------------------------------------
-- RSH1 - the feed head record
--------------------------------------------------------------------------

-- Build the head. Targets may be passed empty (meaning "none": the all-zeros
-- target); the onion address may be empty (onionLen 0). Caps refuse, never
-- truncate. Max size 260 bytes, far under the 1000-byte BEP44 value cap.
function rsBuildHead pSeq, pDisplayName, pLatestPost, pPrekey, pOnionAddr, pProfileMeta
   local tNameBytes, tOnion, tOnionChars, tLatest, tPrekeyT, tProfile, tOut
   if pSeq is not an integer or pSeq < 0 then
      rsSetError "rsBuildHead: seq must be a non-negative integer"
      return empty
   end if
   -- The seq field is a u64 on the wire, but xTalk numbers are doubles, so only
   -- values below 2^53 round-trip exactly. Refuse anything at or above that
   -- rather than serialize a seq that re-parses to a different number (a BEP44
   -- monotonic-counter field silently changing value is a correctness bug).
   if pSeq >= 9007199254740992 then
      rsSetError "rsBuildHead: seq must be below 2^53 to round-trip exactly"
      return empty
   end if
   put textEncode(pDisplayName, "UTF-8") into tNameBytes
   if the number of bytes in tNameBytes > kRsMaxDisplayName then
      rsSetError "rsBuildHead: the display name is over" && \
            kRsMaxDisplayName && "bytes of UTF-8"
      return empty
   end if
   put rsNormalizeTarget(pLatestPost) into tLatest
   put rsNormalizeTarget(pPrekey) into tPrekeyT
   put rsNormalizeTarget(pProfileMeta) into tProfile
   if tLatest is empty or tPrekeyT is empty or tProfile is empty then
      rsSetError "rsBuildHead: a target must be empty or 40 hex chars"
      return empty
   end if
   put toLower(pOnionAddr) into tOnion
   put the number of chars in tOnion into tOnionChars
   if tOnion is not empty and tOnionChars is not kRsOnionAddrLen then
      rsSetError "rsBuildHead: an onion address must be" && \
            kRsOnionAddrLen && "chars"
      return empty
   end if
   put textEncode(kRsHeadMagic, "ASCII") into tOut
   put rsBEu64(pSeq) after tOut
   put numToByte(the number of bytes in tNameBytes) after tOut
   put tNameBytes after tOut
   put textEncode(tLatest, "ASCII") after tOut
   put textEncode(tPrekeyT, "ASCII") after tOut
   put numToByte(the number of chars in tOnion) after tOut
   put textEncode(tOnion, "ASCII") after tOut
   put textEncode(tProfile, "ASCII") after tOut
   if the number of bytes in tOut > kRsMaxRecord then
      rsSetError "rsBuildHead: the head record is over" && kRsMaxRecord && \
            "bytes"
      return empty
   end if
   return tOut
end rsBuildHead

-- Parse a head strictly: magic, caps, and EXACT total length. Anything
-- malformed returns empty - a truncated or padded record is refused, never
-- partially believed.
function rsParseHead pBytes
   local tLen, tPos, tNameLen, tOnionLen, tHead, tField, tErr
   put the number of bytes in pBytes into tLen
   if tLen < 13 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsHeadMagic then
      rsSetError "rsParseHead: bad magic, not an RSH1 record"
      return empty
   end if
   put rsReadBEu64(byte 5 to 12 of pBytes) into tHead["seq"]
   put byteToNum(byte 13 of pBytes) into tNameLen
   if tNameLen > kRsMaxDisplayName then
      rsSetError "rsParseHead: display name length over cap"
      return empty
   end if
   put 13 into tPos
   if tLen < tPos + tNameLen + 40 + 40 + 1 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   -- textDecode can throw on malformed UTF-8, and pBytes is attacker-supplied,
   -- so a bad display name must be a clean refusal - not a thrown error out of a
   -- parser the header promises never throws.
   try
      put textDecode(byte (tPos + 1) to (tPos + tNameLen) of pBytes, "UTF-8") \
            into tHead["displayName"]
   catch tErr
      rsSetError "rsParseHead: the display name is not valid UTF-8"
      return empty
   end try
   add tNameLen to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed latest-post target"
      return empty
   end if
   put tField into tHead["latestPostTarget"]
   add 40 to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed prekey target"
      return empty
   end if
   put tField into tHead["prekeyTarget"]
   add 40 to tPos
   put byteToNum(byte (tPos + 1) of pBytes) into tOnionLen
   add 1 to tPos
   if tOnionLen is not 0 and tOnionLen is not kRsOnionAddrLen then
      rsSetError "rsParseHead: bad onion address length"
      return empty
   end if
   if tLen < tPos + tOnionLen + 40 then
      rsSetError "rsParseHead: truncated head record"
      return empty
   end if
   if tOnionLen is 0 then
      put empty into tHead["onionAddr"]
   else
      put textDecode(byte (tPos + 1) to (tPos + tOnionLen) of pBytes, \
            "ASCII") into tHead["onionAddr"]
   end if
   add tOnionLen to tPos
   put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
         into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParseHead: malformed profile-meta target"
      return empty
   end if
   put tField into tHead["profileMetaTarget"]
   add 40 to tPos
   if tLen is not tPos then
      rsSetError "rsParseHead: trailing bytes after the head record"
      return empty
   end if
   return tHead
end rsParseHead

--------------------------------------------------------------------------
-- RSP1 - the post record and the tamper-evident chain
--------------------------------------------------------------------------

-- A kind-D (direct text) post, signed with the identity seed. pMediaList is
-- a comma-separated list of 40-hex torrent info-hashes, empty for none.
function rsBuildPost pTimestamp, pPrevTarget, pTextContent, pMediaList, pIdentitySeed
   local tBody
   put rsPostBody(pTimestamp, pPrevTarget, "D", pTextContent, empty, \
         pMediaList) into tBody
   if tBody is empty then return empty
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildPost

-- A kind-C post whose text lives in immutable chunks named in order.
-- pChunkTargets is a comma-separated list of 1..16 40-hex targets.
function rsBuildPostChunked pTimestamp, pPrevTarget, pChunkTargets, pMediaList, pIdentitySeed
   local tBody
   put rsPostBody(pTimestamp, pPrevTarget, "C", empty, pChunkTargets, \
         pMediaList) into tBody
   if tBody is empty then return empty
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildPostChunked

private function rsPostBody pTimestamp, pPrevTarget, pKind, pTextContent, pChunkTargets, pMediaList
   local tPrev, tOut, tTextBytes, tChunkCount, tMediaCount, tItem, tNorm
   if pTimestamp is an integer and pTimestamp >= 9007199254740992 then
      rsSetError "rsPostBody: the timestamp must be below 2^53 to round-trip exactly"
      return empty
   end if
   if pTimestamp is not an integer or pTimestamp < 0 then
      rsSetError "rsPostBody: the timestamp must be a non-negative integer"
      return empty
   end if
   put rsNormalizeTarget(pPrevTarget) into tPrev
   if tPrev is empty then
      rsSetError "rsPostBody: the previous-post target must be empty or 40 hex"
      return empty
   end if
   put textEncode(kRsPostMagic, "ASCII") into tOut
   put rsBEu64(pTimestamp) after tOut
   put textEncode(tPrev, "ASCII") after tOut
   put textEncode(pKind, "ASCII") after tOut
   if pKind is "D" then
      put textEncode(pTextContent, "UTF-8") into tTextBytes
      if the number of bytes in tTextBytes > 65535 then
         rsSetError "rsPostBody: the text is over the u16 length field"
         return empty
      end if
      put rsBEu16(the number of bytes in tTextBytes) after tOut
      put tTextBytes after tOut
   else
      set the itemDelimiter to comma
      put the number of items in pChunkTargets into tChunkCount
      if tChunkCount < 1 or tChunkCount > kRsMaxChunks then
         rsSetError "rsPostBody: chunk count must be 1 to" && kRsMaxChunks
         return empty
      end if
      put numToByte(tChunkCount) after tOut
      repeat for each item tItem in pChunkTargets
         put rsNormalizeTarget(tItem) into tNorm
         if tNorm is kRsZeroTarget or tNorm is empty then
            rsSetError "rsPostBody: a chunk target must be 40 non-zero hex"
            return empty
         end if
         put textEncode(tNorm, "ASCII") after tOut
      end repeat
   end if
   set the itemDelimiter to comma
   if pMediaList is empty then
      put 0 into tMediaCount
   else
      put the number of items in pMediaList into tMediaCount
   end if
   if tMediaCount > kRsMaxMedia then
      rsSetError "rsPostBody: media count over" && kRsMaxMedia
      return empty
   end if
   put numToByte(tMediaCount) after tOut
   if tMediaCount > 0 then
      repeat for each item tItem in pMediaList
         put rsNormalizeTarget(tItem) into tNorm
         if tNorm is kRsZeroTarget or tNorm is empty then
            rsSetError "rsPostBody: a media info-hash must be 40 non-zero hex"
            return empty
         end if
         put textEncode(tNorm, "ASCII") after tOut
      end repeat
   end if
   if the number of bytes in tOut + 64 > kRsMaxRecord then
      rsSetError "rsPostBody: the post record is over" && kRsMaxRecord && \
            "bytes; move the text to chunks or drop media"
      return empty
   end if
   return tOut
end rsPostBody

private function rsSignPost pBody, pIdentitySeed
   local tKeys, tSig, tErr
   put rsIdentityKeys(pIdentitySeed) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignDetached(pBody, tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsSignPost:" && tErr
      return empty
   end try
   return pBody & tSig
end rsSignPost

-- Parse a post strictly (magic, caps, exact length including the 64-byte
-- signature). Parsing does NOT verify the signature - that needs the
-- author's public key, which the caller trusts from elsewhere; call
-- rsVerifyPost for that.
function rsParsePost pBytes
   local tLen, tPos, tKind, tCount, tPost, tField, tI, tTextLen, tList, tErr
   put the number of bytes in pBytes into tLen
   if tLen < 4 + 8 + 40 + 1 + 1 + 64 then
      rsSetError "rsParsePost: truncated post record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsPostMagic then
      rsSetError "rsParsePost: bad magic, not an RSP1 record"
      return empty
   end if
   put rsReadBEu64(byte 5 to 12 of pBytes) into tPost["timestamp"]
   put textDecode(byte 13 to 52 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 40) then
      rsSetError "rsParsePost: malformed previous-post target"
      return empty
   end if
   put tField into tPost["prevPostTarget"]
   put textDecode(byte 53 of pBytes, "ASCII") into tKind
   put tKind into tPost["kind"]
   put 53 into tPos
   if tKind is "D" then
      if tLen < tPos + 2 + 1 + 64 then
         rsSetError "rsParsePost: truncated post record"
         return empty
      end if
      put rsReadBEu16(byte (tPos + 1) to (tPos + 2) of pBytes) into tTextLen
      add 2 to tPos
      if tLen < tPos + tTextLen + 1 + 64 then
         rsSetError "rsParsePost: text length runs past the record"
         return empty
      end if
      -- Attacker-supplied bytes; malformed UTF-8 is a clean refusal, not a throw
      -- (the header promises this parser never throws).
      try
         put textDecode(byte (tPos + 1) to (tPos + tTextLen) of pBytes, \
               "UTF-8") into tPost["text"]
      catch tErr
         rsSetError "rsParsePost: the post text is not valid UTF-8"
         return empty
      end try
      add tTextLen to tPos
   else if tKind is "C" then
      put byteToNum(byte (tPos + 1) of pBytes) into tCount
      add 1 to tPos
      if tCount < 1 or tCount > kRsMaxChunks then
         rsSetError "rsParsePost: chunk count out of range"
         return empty
      end if
      if tLen < tPos + tCount * 40 + 1 + 64 then
         rsSetError "rsParsePost: truncated chunk list"
         return empty
      end if
      put empty into tList
      repeat with tI = 1 to tCount
         put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
               into tField
         if not rsIsHexOfLen(tField, 40) then
            rsSetError "rsParsePost: malformed chunk target"
            return empty
         end if
         if tList is empty then
            put tField into tList
         else
            put comma & tField after tList
         end if
         add 40 to tPos
      end repeat
      put tList into tPost["chunkTargets"]
   else
      rsSetError "rsParsePost: unknown post kind"
      return empty
   end if
   put byteToNum(byte (tPos + 1) of pBytes) into tCount
   add 1 to tPos
   if tCount > kRsMaxMedia then
      rsSetError "rsParsePost: media count out of range"
      return empty
   end if
   if tLen is not tPos + tCount * 40 + 64 then
      rsSetError "rsParsePost: record length does not match its fields"
      return empty
   end if
   put empty into tList
   repeat with tI = 1 to tCount
      put textDecode(byte (tPos + 1) to (tPos + 40) of pBytes, "ASCII") \
            into tField
      if not rsIsHexOfLen(tField, 40) then
         rsSetError "rsParsePost: malformed media info-hash"
         return empty
      end if
      if tList is empty then
         put tField into tList
      else
         put comma & tField after tList
      end if
      add 40 to tPos
   end repeat
   put tList into tPost["mediaTargets"]
   return tPost
end rsParsePost

-- Verify a post's author signature: parse first (so a malformed buffer is
-- refused before any crypto), then check the trailing 64 bytes are a valid
-- ed25519 detached signature by the handle over everything before them.
function rsVerifyPost pBytes, pHandleHex
   local tPub, tParsed, tLen, tErr
   put rsParsePost(pBytes) into tParsed
   if tParsed is empty then return false
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsVerifyPost: the handle must be 64 hex chars"
      return false
   end if
   put the number of bytes in pBytes into tLen
   try
      return sxSignVerifyDetached(byte (tLen - 63) to tLen of pBytes, \
            byte 1 to (tLen - 64) of pBytes, tPub)
   catch tErr
      rsSetError "rsVerifyPost:" && tErr
      return false
   end try
end rsVerifyPost

--------------------------------------------------------------------------
-- BEP44 helpers
--------------------------------------------------------------------------

-- bencode of a byte string: <len>:<bytes>. The only bencode shape riptide
-- ever puts on the DHT (the v for btDhtBep44SignBuf / btDhtPutSigned and
-- the input whose SHA-1 is an immutable item's target).
function rsBencodeBytes pData
   local tLen
   put the number of bytes in pData into tLen
   return textEncode(tLen & ":", "ASCII") & pData
end rsBencodeBytes

--------------------------------------------------------------------------
-- phase 2 - the live feed layer, pure half (spec section 4)
--
-- Everything in this half is deterministic compute: the canonical BEP44
-- signing buffer, the content address of an immutable item, and the two
-- INGEST verifiers the app's poll loop feeds drained events through. None
-- of it touches a session, which is what keeps it testable offline and
-- lets ingest run its refusals even where torrentxt is not installed.
--------------------------------------------------------------------------

-- Strictly parse a bencoded byte string "<len>:<bytes>" and return len, or
-- -1 on anything else: a non-digit prefix, a missing colon, a non-canonical
-- leading zero, or a declared length that does not match the bytes that
-- follow. The live layer only ever stores this one bencode shape, so
-- anything else handed to rsBep44SignBuf is a caller bug to refuse loudly.
private function rsBencodedByteStringLen pValue
   local tI, tN, tLen, tDigits
   put 0 into tLen
   put 0 into tDigits
   repeat with tI = 1 to the number of bytes in pValue
      put byteToNum(byte tI of pValue) into tN
      if tN is 58 then
         if tDigits is 0 then return -1
         if the number of bytes in pValue - tI is not tLen then return -1
         return tLen
      end if
      if tN < 48 or tN > 57 then return -1
      if tDigits > 0 and tLen is 0 then return -1
      put tLen * 10 + (tN - 48) into tLen
      add 1 to tDigits
      if tDigits > 4 then return -1
   end repeat
   return -1
end rsBencodedByteStringLen

-- The canonical BEP44 signing buffer, rebuilt in pure script:
-- [4:salt<n>:<salt>] 3:seqi<seq>e 1:v <bencoded v>. Byte-identical to
-- torrentxt's btDhtBep44SignBuf (the folded suite harness cross-checks the
-- two implementations, and libtorrent's own verifier accepting the result
-- is the deeper proof) - built here rather than borrowed so rsIngestHead
-- can verify a head's signature even in a paste with no torrentxt at all.
function rsBep44SignBuf pSalt, pSeq, pValue
   local tSaltBytes, tRawLen, tOut
   if pSeq is not an integer or pSeq < 0 then
      rsSetError "rsBep44SignBuf: seq must be a non-negative integer"
      return empty
   end if
   if pSeq >= 9007199254740992 then
      rsSetError "rsBep44SignBuf: seq must be below 2^53 to round-trip exactly"
      return empty
   end if
   put textEncode(pSalt, "UTF-8") into tSaltBytes
   if the number of bytes in tSaltBytes > kRsMaxSalt then
      rsSetError "rsBep44SignBuf: the salt is over" && kRsMaxSalt && \
            "bytes (the BEP44 cap)"
      return empty
   end if
   put rsBencodedByteStringLen(pValue) into tRawLen
   if tRawLen < 1 or tRawLen > kRsMaxRecord then
      rsSetError "rsBep44SignBuf: the value must be a bencoded byte string" && \
            "of 1 to" && kRsMaxRecord && "raw bytes"
      return empty
   end if
   put empty into tOut
   if tSaltBytes is not empty then
      put textEncode("4:salt" & the number of bytes in tSaltBytes & ":", \
            "ASCII") & tSaltBytes into tOut
   end if
   put textEncode("3:seqi" & pSeq & "e1:v", "ASCII") after tOut
   put pValue after tOut
   return tOut
end rsBep44SignBuf

-- The 40-hex DHT target of an immutable item: SHA-1 of the BENCODED value
-- (BEP44). What btDhtPutImmutable returns for the same bytes; recomputable
-- offline, which is what makes the post chain walkable without trust.
function rsImmutableTarget pValue
   local tLen
   put the number of bytes in pValue into tLen
   if tLen < 1 or tLen > kRsMaxRecord then
      rsSetError "rsImmutableTarget: a BEP44 immutable value is 1 to" && \
            kRsMaxRecord && "bytes"
      return empty
   end if
   return rsBinToHexString(sha1Digest(rsBencodeBytes(pValue)))
end rsImmutableTarget

-- Verify and unpack a drained dhtMutableItem EVENT as a followee's feed
-- head. pEvent is the event array btPoll returned (publicKey, salt, seq,
-- value, signature); pExpectedHandleHex is the handle the app trusts (the
-- key it asked rsRequestHead about). Refuses: an event for another key or
-- salt, an insane seq, a value that is not a strict RSH1 record, a record
-- whose embedded seq disagrees with the BEP44 seq, and - the point - a
-- BEP44 signature that does not verify under the handle. libtorrent already
-- verified that signature once on receipt; re-verifying here in SodiumXT
-- costs one call and means the app's trust does not rest on the transport.
-- Returns the parsed head array (rsParseHead's shape), or empty.
function rsIngestHead pEvent, pExpectedHandleHex
   local tHandle, tEventKey, tSeq, tHead, tSigHex, tSig, tBuf, tOk, tErr
   put toLower(pExpectedHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsIngestHead: the expected handle must be 64 hex chars"
      return empty
   end if
   put toLower(pEvent["publicKey"]) into tEventKey
   if not rsIsHexOfLen(tEventKey, 64) or tEventKey is not tHandle then
      rsSetError "rsIngestHead: the event is not for this handle"
      return empty
   end if
   -- `is` folds case, so a case-mangled salt could pass this line; it then
   -- fails the signature below, because the buffer is rebuilt from the
   -- CANONICAL salt. The crypto backstops the string compare.
   if pEvent["salt"] is not kRsHeadSalt then
      rsSetError "rsIngestHead: the event is not a riptide-head item"
      return empty
   end if
   put pEvent["seq"] into tSeq
   if tSeq is not an integer or tSeq < 0 or tSeq >= 9007199254740992 then
      rsSetError "rsIngestHead: the event seq is not a sane integer"
      return empty
   end if
   put rsParseHead(pEvent["value"]) into tHead
   if tHead is empty then return empty
   if tHead["seq"] is not tSeq then
      -- rsPublishHead uses the head's own embedded seq as the BEP44 seq, so
      -- a disagreement means this record was not published by this layer
      -- (or was reassembled); refuse rather than guess which counter to
      -- believe - the app's replay protection reads the one true seq.
      rsSetError "rsIngestHead: the BEP44 seq and the head's embedded seq" && \
            "disagree"
      return empty
   end if
   put toLower(pEvent["signature"]) into tSigHex
   if not rsIsHexOfLen(tSigHex, 128) then
      rsSetError "rsIngestHead: the event signature is not 128 hex chars"
      return empty
   end if
   put rsHexToBin(tSigHex) into tSig
   if tSig is empty then return empty
   put rsBep44SignBuf(kRsHeadSalt, tSeq, rsBencodeBytes(pEvent["value"])) \
         into tBuf
   if tBuf is empty then return empty
   try
      put sxSignVerifyDetached(tSig, tBuf, rsHexToBin(tHandle)) into tOk
   catch tErr
      rsSetError "rsIngestHead:" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsIngestHead: the BEP44 signature does not verify under" && \
            "this handle"
      return empty
   end if
   return tHead
end rsIngestHead

-- Verify and unpack a drained dhtImmutableItem EVENT as one post in a
-- followee's chain. pExpectedTarget is the target the app asked for (the
-- head's latestPostTarget, or the previous post's prevPostTarget);
-- pAuthorHandleHex the author being walked. Three gates, in order: the
-- event answers the target the app is waiting on; the value's recomputed
-- SHA-1 IS that target (content addressing - a lying node is refused, and
-- everything downstream is then over exactly the named bytes); and the
-- author's ed25519 signature verifies. Returns rsParsePost's array, or
-- empty. The chain walk is these calls in a loop: request the head's
-- latest target, ingest, follow prevPostTarget until the zero target.
function rsIngestPost pEvent, pExpectedTarget, pAuthorHandleHex
   local tExpected, tEventTarget, tValue, tComputed
   put rsNormalizeTarget(pExpectedTarget) into tExpected
   if tExpected is empty or tExpected is kRsZeroTarget then
      rsSetError "rsIngestPost: the expected target must be 40 non-zero" && \
            "hex chars"
      return empty
   end if
   put toLower(pEvent["target"]) into tEventTarget
   if tEventTarget is not tExpected then
      rsSetError "rsIngestPost: the event names a different target"
      return empty
   end if
   put pEvent["value"] into tValue
   put rsImmutableTarget(tValue) into tComputed
   if tComputed is empty then return empty
   if tComputed is not tExpected then
      rsSetError "rsIngestPost: the value does not hash to its own target"
      return empty
   end if
   if rsVerifyPost(tValue, pAuthorHandleHex) is not true then
      return empty
   end if
   return rsParsePost(tValue)
end rsIngestPost

--------------------------------------------------------------------------
-- phase 2 - the live feed layer, session half (spec section 4)
--
-- Thin compositions over a torrent session the APP owns (TorrentXT allows
-- one per process; this library never starts, stops, or polls one). Every
-- input is validated BEFORE the session handle is touched, so the refusal
-- paths run - and are tested - with no torrentxt installed at all. The
-- fetches are asynchronous: they return true when the lookup is accepted,
-- and the value arrives later as a dhtMutableItem / dhtImmutableItem event
-- for rsIngestHead / rsIngestPost.
--------------------------------------------------------------------------

private function rsValidSession pSession
   return pSession is an integer and pSession > 0
end rsValidSession

-- Publish an RSH1 head under the identity key, through the external-signing
-- seam: the canonical buffer is assembled here, signed by SodiumXT, and
-- handed to btDhtPutSigned, which VERIFIES the signature against the public
-- key before anything touches the network - so the identity secret never
-- crosses into libtorrent, and a true return means libtorrent's own ed25519
-- agreed with SodiumXT's. The BEP44 seq is the head's embedded seq: one
-- counter, one source of truth (rsParseHead), never two arguments to skew.
function rsPublishHead pSession, pHeadBytes, pIdentitySeed
   local tHead, tKeys, tValue, tBuf, tSig, tSigHex, tCode, tWhy, tErr
   put rsParseHead(pHeadBytes) into tHead
   if tHead is empty then
      rsSetError "rsPublishHead: not a valid RSH1 head:" && rsLastError()
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsPublishHead: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   put rsIdentityKeys(pIdentitySeed) into tKeys
   if tKeys is empty then return false
   put rsBencodeBytes(pHeadBytes) into tValue
   put rsBep44SignBuf(kRsHeadSalt, tHead["seq"], tValue) into tBuf
   if tBuf is empty then return false
   try
      put sxSignDetached(tBuf, tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsPublishHead:" && tErr
      return false
   end try
   put rsBinToHexString(tSig) into tSigHex
   if tSigHex is empty then return false
   try
      btDhtPutSigned pSession, tKeys["handle"], kRsHeadSalt, \
            tHead["seq"], tValue, tSigHex
      put the result into tCode
   catch tErr
      rsSetError "rsPublishHead: needs torrentxt (btDhtPutSigned):" && tErr
      return false
   end try
   if tCode is not 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsPublishHead: btDhtPutSigned refused (" & tCode & ")" && tWhy
      return false
   end if
   return true
end rsPublishHead

-- Store any immutable value (a chunk, a profile-meta blob) and return its
-- 40-hex target. The target is recomputed here and compared against what
-- libtorrent returned: two independent SHA-1s over one bencoded value
-- disagreeing means one side is not hashing what it claims, and a feed
-- layer that shrugged at that would be publishing unfindable posts.
function rsPublishImmutable pSession, pValue
   local tExpected, tTarget, tWhy, tErr
   put rsImmutableTarget(pValue) into tExpected
   if tExpected is empty then return empty
   if not rsValidSession(pSession) then
      rsSetError "rsPublishImmutable: pSession is not a live torrent" && \
            "session handle"
      return empty
   end if
   try
      put btDhtPutImmutable(pSession, pValue) into tTarget
   catch tErr
      rsSetError "rsPublishImmutable: needs torrentxt" && \
            "(btDhtPutImmutable):" && tErr
      return empty
   end try
   if tTarget is empty then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsPublishImmutable: btDhtPutImmutable failed;" && tWhy
      return empty
   end if
   if toLower(tTarget) is not tExpected then
      rsSetError "rsPublishImmutable: libtorrent's target" && tTarget && \
            "disagrees with the recomputed" && tExpected
      return empty
   end if
   return tExpected
end rsPublishImmutable

-- Publish one RSP1 post. The strict parse runs first, so a malformed or
-- truncated record is refused before the network hears about it; the store
-- itself is rsPublishImmutable, because a post IS just a content-addressed
-- immutable item. Returns the post's 40-hex target (what the next post's
-- prevPostTarget and the head's latestPostTarget name), or empty.
function rsPublishPost pSession, pPostBytes
   local tParsed
   put rsParsePost(pPostBytes) into tParsed
   if tParsed is empty then
      rsSetError "rsPublishPost: not a valid RSP1 record:" && rsLastError()
      return empty
   end if
   return rsPublishImmutable(pSession, pPostBytes)
end rsPublishPost

-- Ask the DHT for a followee's current head. Asynchronous: true means the
-- lookup was accepted; the value arrives as a dhtMutableItem event, which
-- the app hands to rsIngestHead.
function rsRequestHead pSession, pHandleHex
   local tHandle, tCode, tErr
   put toLower(pHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsRequestHead: the handle must be 64 hex chars"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsRequestHead: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   try
      btDhtGetMutable pSession, tHandle, kRsHeadSalt
      put the result into tCode
   catch tErr
      rsSetError "rsRequestHead: needs torrentxt (btDhtGetMutable):" && tErr
      return false
   end try
   if tCode is not 0 then
      rsSetError "rsRequestHead: btDhtGetMutable refused (" & tCode & ")"
      return false
   end if
   return true
end rsRequestHead

-- Ask the DHT for one immutable item (a post, a chunk, a profile blob) by
-- its target. Asynchronous: the value arrives as a dhtImmutableItem event,
-- which the app hands to rsIngestPost (posts) or checks against
-- rsImmutableTarget itself (raw blobs). The zero target means "none" in
-- every record, so asking for it is always a caller bug.
function rsRequestImmutable pSession, pTarget
   local tT, tCode, tErr
   put rsNormalizeTarget(pTarget) into tT
   if tT is empty or tT is kRsZeroTarget then
      rsSetError "rsRequestImmutable: the target must be 40 non-zero hex" && \
            "chars"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsRequestImmutable: pSession is not a live torrent" && \
            "session handle"
      return false
   end if
   try
      btDhtGetImmutable pSession, tT
      put the result into tCode
   catch tErr
      rsSetError "rsRequestImmutable: needs torrentxt (btDhtGetImmutable):" \
            && tErr
      return false
   end try
   if tCode is not 0 then
      rsSetError "rsRequestImmutable: btDhtGetImmutable refused (" & tCode & ")"
      return false
   end if
   return true
end rsRequestImmutable

--------------------------------------------------------------------------
-- the media layer (phase 3) - followers are the CDN
--------------------------------------------------------------------------

-- Attach one file to the feed: build a TRACKERLESS torrent over it (DHT-only,
-- like everything else here) and seed it IN PLACE - the save path is the
-- file's own parent folder, so libtorrent finds the payload where it already
-- sits and no copy is made. Returns the 40-hex v1 info-hash, which is exactly
-- what rsBuildPost's pMediaList carries and what a follower's rsMediaFetch
-- takes. Media attachments are SINGLE FILES by design (a photo, a video);
-- folder shares are a file-sharing app's job (quickshare), not a feed's.
-- The torrent handle is deliberately not returned: posts name hashes, not
-- handles, and btFindTorrent(pSession, tHash) recovers the handle whenever
-- the app wants one (rsMediaFetch on your own hash does exactly that).
function rsMediaCreate pSession, pPath
   local tParent, tData, tH, tHash, tWhy, tErr
   if there is not a file pPath then
      rsSetError "rsMediaCreate: no file at" && pPath && \
            "(media attachments are single files)"
      return empty
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsMediaCreate: pSession is not a live torrent session" && \
            "handle"
      return empty
   end if
   set the itemDelimiter to "/"
   put item 1 to -2 of pPath into tParent
   if tParent is empty then put "/" into tParent
   try
      put btCreateTorrent(pPath, 0, 0, empty) into tData
   catch tErr
      rsSetError "rsMediaCreate: needs torrentxt (btCreateTorrent):" && tErr
      return empty
   end try
   if tData is empty then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsMediaCreate: btCreateTorrent failed;" && tWhy
      return empty
   end if
   try
      put btAddTorrentFile(pSession, tData, tParent) into tH
   catch tErr
      rsSetError "rsMediaCreate: needs torrentxt (btAddTorrentFile):" && tErr
      return empty
   end try
   if tH is 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsMediaCreate: btAddTorrentFile refused;" && tWhy
      return empty
   end if
   try
      put toLower(btInfoHash(tH)) into tHash
   catch tErr
      rsSetError "rsMediaCreate: needs torrentxt (btInfoHash):" && tErr
      return empty
   end try
   if not rsIsHexOfLen(tHash, 40) then
      rsSetError "rsMediaCreate: btInfoHash returned" && tHash & \
            ", not 40 hex"
      return empty
   end if
   return tHash
end rsMediaCreate

-- Fetch - and from then on co-seed - one media item a post names: join its
-- swarm by magnet, downloading under pSaveFolder. pSequential true is the
-- playback mode: pieces arrive in order, so a video can start playing while
-- its tail is still downloading (poll rsMediaStatus for the moment filePath
-- resolves). Idempotent on purpose: if the session already holds this hash
-- (a re-click, a restart's re-fetch, or the author's own seed), the existing
-- handle is returned instead of libtorrent's duplicate-add error - and the
-- sequential flag is still applied, because the caller asked for playback
-- NOW. Completion is not the end: libtorrent keeps seeding a finished
-- torrent, which is the whole followers-are-the-CDN design - fetching IS
-- co-seeding. Returns the positive torrent handle, or empty.
function rsMediaFetch pSession, pInfoHash, pSaveFolder, pSequential
   local tHash, tH, tCode, tWhy, tErr
   put rsNormalizeTarget(pInfoHash) into tHash
   if tHash is empty or tHash is kRsZeroTarget then
      rsSetError "rsMediaFetch: the info-hash must be 40 non-zero hex chars"
      return empty
   end if
   if there is not a folder pSaveFolder then
      rsSetError "rsMediaFetch: no folder at" && pSaveFolder
      return empty
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsMediaFetch: pSession is not a live torrent session" && \
            "handle"
      return empty
   end if
   try
      put btFindTorrent(pSession, tHash) into tH
   catch tErr
      rsSetError "rsMediaFetch: needs torrentxt (btFindTorrent):" && tErr
      return empty
   end try
   if tH is 0 then
      try
         put btAddMagnet(pSession, "magnet:?xt=urn:btih:" & tHash, \
               pSaveFolder) into tH
      catch tErr
         rsSetError "rsMediaFetch: needs torrentxt (btAddMagnet):" && tErr
         return empty
      end try
      if tH is 0 then
         try
            put btLastError() into tWhy
         catch tErr
            put empty into tWhy
         end try
         rsSetError "rsMediaFetch: btAddMagnet failed;" && tWhy
         return empty
      end if
   end if
   if pSequential is true then
      try
         btSetSequentialDownload tH, true
         put the result into tCode
      catch tErr
         rsSetError "rsMediaFetch: needs torrentxt" && \
               "(btSetSequentialDownload):" && tErr
         return empty
      end try
      if tCode is not 0 then
         -- The torrent stays added (progress is never thrown away over a
         -- flag); a retry lands on the btFindTorrent path and re-applies.
         rsSetError "rsMediaFetch: btSetSequentialDownload refused (" & \
               tCode & ")"
         return empty
      end if
   end if
   return tH
end rsMediaFetch

-- One status snapshot for a media torrent, shaped for a feed/player UI: the
-- btTorrentStatus record (name, state, progress 0..1, totalDone/totalSize,
-- isFinished/isSeeding, savePath, ...) with the PLAYER fields added on top:
-- filePath is the on-disk path of the torrent's first file - the one a
-- player opens - resolved from btFileList, with fileSize/fileProgress (bytes
-- done of THAT file) beside it. All three stay empty until metadata arrives
-- (a magnet fetches its file table over the swarm), so "filePath is empty"
-- doubles as the not-openable-yet probe; with a sequential fetch,
-- fileProgress is contiguous from the front, which is what makes playing
-- mid-download work. Takes the torrent handle (from rsMediaFetch or
-- btFindTorrent), not the session: the snapshot is per-torrent.
function rsMediaStatus pTorrent
   local tS, tFiles, tErr
   if pTorrent is not an integer or pTorrent <= 0 then
      rsSetError "rsMediaStatus: pTorrent is not a torrent handle"
      return empty
   end if
   try
      put btTorrentStatus(pTorrent) into tS
   catch tErr
      rsSetError "rsMediaStatus: needs torrentxt (btTorrentStatus):" && tErr
      return empty
   end try
   if the keys of tS is empty then
      rsSetError "rsMediaStatus: not a live torrent handle"
      return empty
   end if
   put empty into tS["filePath"]
   put empty into tS["fileSize"]
   put empty into tS["fileProgress"]
   try
      put btFileList(pTorrent) into tFiles
   catch tErr
      -- status just succeeded, so this cannot be "torrentxt missing";
      -- degrade to no-file-table (same as metadata-not-yet) rather than
      -- failing a snapshot the caller can still paint progress from
      put empty into tFiles
   end try
   if tFiles is an array and the number of elements in tFiles > 0 then
      put tS["savePath"] & "/" & tFiles[1]["path"] into tS["filePath"]
      put tFiles[1]["size"] into tS["fileSize"]
      put tFiles[1]["progress"] into tS["fileProgress"]
   end if
   return tS
end rsMediaStatus

--------------------------------------------------------------------------
-- private: hex, big-endian integers, base32
--------------------------------------------------------------------------

-- Strict LOWERCASE hex of an exact length. The check is by BYTE VALUE, not
-- `is in`: `is in` honours the caseSensitive (default FALSE), so "A" is in
-- "abcdef" would be true and an uppercase target would parse as valid - a
-- non-canonical record accepted (the malleability the strict parse exists to
-- refuse; the coinxt discipline-3 lesson). Digits 0-9 are bytes 48..57, lower
-- a-f are bytes 97..102; nothing else passes, whatever the caller set.
private function rsIsHexOfLen pValue, pLen
   local tI, tN
   if the number of chars in pValue is not pLen then return false
   repeat with tI = 1 to pLen
      put byteToNum(byte tI of pValue) into tN
      if not ((tN >= 48 and tN <= 57) or (tN >= 97 and tN <= 102)) then
         return false
      end if
   end repeat
   return true
end rsIsHexOfLen

-- Empty -> the all-zeros "none" target; otherwise require 40 hex chars.
-- Returns empty on anything else (callers refuse the whole record).
private function rsNormalizeTarget pTarget
   local tT
   if pTarget is empty then return kRsZeroTarget
   put toLower(pTarget) into tT
   if not rsIsHexOfLen(tT, 40) then return empty
   return tT
end rsNormalizeTarget

private function rsHexToBin pHex
   local tOut, tErr
   try
      put sxHex2Bin(textEncode(toLower(pHex), "ASCII")) into tOut
   catch tErr
      rsSetError "rsHexToBin: malformed hex"
      return empty
   end try
   return tOut
end rsHexToBin

private function rsBinToHexString pData
   local tOut, tErr
   try
      put textDecode(sxBin2Hex(pData), "ASCII") into tOut
   catch tErr
      rsSetError "rsBinToHexString:" && tErr
      return empty
   end try
   return tOut
end rsBinToHexString

private function rsBEu16 pNum
   return binaryEncode("n", pNum)
end rsBEu16

private function rsBEu64 pNum
   return binaryEncode("NN", pNum div 4294967296, pNum mod 4294967296)
end rsBEu64

private function rsReadBEu16 pBytes
   return byteToNum(byte 1 of pBytes) * 256 + byteToNum(byte 2 of pBytes)
end rsReadBEu16

private function rsReadBEu32 pBytes
   local tA, tB, tC, tD
   put byteToNum(byte 1 of pBytes) into tA
   put byteToNum(byte 2 of pBytes) into tB
   put byteToNum(byte 3 of pBytes) into tC
   put byteToNum(byte 4 of pBytes) into tD
   return ((tA * 256 + tB) * 256 + tC) * 256 + tD
end rsReadBEu32

private function rsReadBEu64 pBytes
   return rsReadBEu32(byte 1 to 4 of pBytes) * 4294967296 + \
         rsReadBEu32(byte 5 to 8 of pBytes)
end rsReadBEu64

-- Base32, RFC 4648 lowercase, no padding - the onionxt algorithm with the
-- same integer discipline (no caret, no bare div/mod on wide accumulators;
-- the accumulator is masked to its pending bits every step so it never
-- outgrows exact double precision).
private function rsPow2 pN
   local tOut, tI
   put 1 into tOut
   repeat pN times
      put tOut * 2 into tOut
   end repeat
   return tOut
end rsPow2

private function rsIntDiv pA, pB
   return trunc(pA / pB)
end rsIntDiv

private function rsIntMod pA, pB
   return pA - pB * trunc(pA / pB)
end rsIntMod

private function rsBase32Encode pData
   local tAcc, tBits, tOut, tI, tIndex
   put 0 into tAcc
   put 0 into tBits
   put empty into tOut
   repeat with tI = 1 to the number of bytes in pData
      put tAcc * 256 + byteToNum(byte tI of pData) into tAcc
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put rsIntMod(rsIntDiv(tAcc, rsPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kRsBase32Alphabet after tOut
         put rsIntMod(tAcc, rsPow2(tBits)) into tAcc
      end repeat
   end repeat
   if tBits > 0 then
      put rsIntMod(tAcc * rsPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kRsBase32Alphabet after tOut
   end if
   return tOut
end rsBase32Encode
