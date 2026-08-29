script "RiptideSocial"
-- riptide.livecodescript - Riptide Social, phases 1-4 + 6 + 7: the identity
-- foundation, the pure-compute feed layer, the live feed layer, the media
-- layer, the DM layer, the LAN mesh admission + sync layer, and the
-- anonymous persona layer, as a pure-LiveCodeScript library over the
-- installed suite extensions (docs/RIPTIDE-SOCIAL-SPEC.md sections 3-9).
-- Phase 5 (live sessions) adds no library surface: its SDP offer/answer
-- ride the phase-4 DM message kinds "O"/"A" over the existing
-- secretstream, and its spec-6.2 typing lane is a second dc channel the
-- demo opens - both demo wiring.
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
-- 2026-08-14) CLOSED 2026-08-15 on TWO machines (recorded in
-- riptide/CLAUDE.md): a follower fetched and PLAYED an attached video
-- through the demo stack, the phase-3 done-criterion met - the one
-- unmeasured nuance is playback starting visibly MID-download, which a
-- fast complete transfer can mimic. The phase-4 DM layer (rsDm* /
-- rsBuildPrekey / rsBuildIntro, 2026-08-14) closed the SAME day, same
-- record: two machines exchanged authenticated encrypted DMs with no
-- server, chat both ways - the sealed RSI1 intro, the deterministic-role
-- crypto_kx session, and the pairwise secretstream over rp1 all carried
-- real traffic. The golden pins stand underneath (crypto_kx anchored
-- against a REAL libsodium - see tools/emit-kx-anchor.py), as do the
-- harness-covered refusal paths. The phase 5-7 LIVE flows (the call, the
-- mesh, tor) still await their passes; docs/two-machine-runbook.md
-- scripts each. The 8.2/8.3 onion SERVING seams (rsAnonFeedPage /
-- rsAnonPrekeyBody / rsAnonAcceptDm, 2026-08-15) are golden-pinned and
-- their COMPUTE half ran engine-green 2026-08-20 (Windows, in the suite
-- paste: the page bytes, the /prekey body, and rsAnonAcceptDm's accept
-- plus all five refusal legs; label synced 2026-08-23) - the live
-- done-criterion (a persona actually served over tor) still needs the
-- OXT + live-Tor pass. The phase-6 SYNC records' compute half ran
-- engine-green in that same 2026-08-20 run (riptide 338/0/2); the live
-- two-machine mesh remains. The 2026-08-23 additions - the kind-C
-- chunked-post rail (rsChunkPostText / rsPublishChunkedPost /
-- rsIngestBlob / rsAssembleChunkText / rsPostTextCapacity, backlog A2),
-- the BTXO receive-path stream machine (rsBtxoStreamStep, A3), and the
-- piece-deadline streaming plan (rsMediaStreamPlan, B7) - are verified
-- statically and vector-pinned headlessly; none has an engine pass yet.
--
-- WHAT THIS LAYER OWNS
--   - the master seed and the RIPTKEY1 sealed key file (Argon2id + secretbox,
--     the BTXPREF1 convention with riptide's own magic)
--   - the KDF subkey tree: one 32-byte master -> identity / DM / LAN / anon
--     subkeys via sxKdfDerive, context "riptide\0" (8 bytes exactly)
--   - identity -> handle (ed25519 public key, 64 hex) -> .onion address
--   - the rendezvous derivations: inboxId and roomId
--   - the RSH1 feed-head and RSP1 post-record framings, build + parse +
--     signature verification, caps enforced on BOTH sides - including,
--     since 2026-08-23 (backlog A2), the kind-C CHUNKED rail end to end:
--     the producer split (rsChunkPostText, full 1000-byte chunks by BYTE
--     - reassembly validates the concatenation, never a chunk alone),
--     the D-or-C capacity arithmetic (rsPostTextCapacity), the one-call
--     producer (rsPublishChunkedPost: chunks stored, then the signed
--     kind-C post naming them), the raw-blob ingest verifier
--     (rsIngestBlob: content addressing is what extends the authorSig
--     from the named targets to the fetched bytes), and the reassembling
--     verify (rsAssembleChunkText: every part re-hashed, the whole
--     decoded by UTF-8 round trip)
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
--   - the DM layer (phase 4): the crypto_kx prekey pair from the DM
--     subkey (rsDmKeys), the RSK1 signed prekey record a head's
--     prekeyTarget names, the RSI1 sealed-intro first contact (seal to a
--     VERIFIED prekey; sender signature + recipient binding inside the
--     seal), one deterministic-role crypto_kx session per pair
--     (rsDmSessionKeys: the lexically smaller handle is the client), the
--     RSM1 rp1 transport frames and the kind+timestamp+body message
--     records a secretstream carries, and the inbox-swarm join + framed
--     send over rp1 (rsDmJoinInbox / rsDmSend). The app owns the rp1
--     peer bookkeeping, the secretstream handles (sxFreeStream when
--     done), and the poll loop, as everywhere else. The message kinds
--     "O"/"A" carry phase-5 SDP signalling over this same rail.
--   - the LAN mesh admission layer (phase 6): the shared-master ed25519
--     keypair every one of your devices derives (rsLanKeys), and the
--     RSL1 challenge/response that proves a joiner holds the master
--     (rsLanBuildChallenge / rsLanBuildResponse / rsLanVerifyResponse) -
--     a stranger on the same Wi-Fi cannot sign it. The records ride enet
--     channel-0 messages; the app owns the enet host and the pump.
--   - the phase-6 SYNC records over the admitted mesh (2026-08-15, the
--     spec section 7 channel discipline): the "D" draft-sync record
--     (channel 0, reliable - draft text + a monotonic per-device seq +
--     the sender device name), the "F" feed-seq/read-receipt state
--     record (channel 0 - feedSeq applies as max so two devices never
--     publish a conflicting head), and the "P" presence/typing record
--     (channel 1, unreliable-unsequenced - absolute state with its own
--     monotonic tick, safely droppable and reorder-proof). All three
--     are signed under the SAME shared LAN key as the admission with a
--     distinct domain tag; verify-then-parse on every inbound record
--     (rsLanBuildDraft / rsLanVerifyDraft / rsLanBuildFeedState /
--     rsLanVerifyFeedState / rsLanBuildPresence / rsLanVerifyPresence).
--     Since 2026-08-16 a fourth kind settles spec section 7's channel 2:
--     the "M" MEDIA HANDOFF record (channel 0) - a signed POINTER at the
--     phase-3 torrent path (info-hash + file name + size), because a
--     draft's media essentially never fits enet's 60000-byte budget and
--     bulk over that seam IS a torrent in this suite (rsLanBuildHandoff /
--     rsLanVerifyHandoff). Channel 2 itself stays reserved, dark.
--   - the ANONYMOUS PERSONA layer (phase 7): a separate onion-only
--     identity from a subkey-100+n seed (rsAnonHandle / rsAnonOnion,
--     derivable offline), the probe-gated onion-service wrapper
--     (rsAnonCreateService), the BTXO framed-chunk protocol for files over
--     a Tor stream (rsBtxo* - build AND, since 2026-08-23, RECEIVE:
--     rsBtxoStreamStep is the pure length-prefix stream state machine,
--     nocloud's caps ported, fail-closed on hostile lengths), and
--     rsPersonaAllows - the pure-policy
--     DEANONYMIZATION GUARD (spec 9.3) every transport branch asserts
--     through, fail-closed: an anon persona may use ONLY the onion, a
--     public persona may use anything EXCEPT the anon onion, and an
--     unknown transport is refused for both. This is the highest-severity
--     invariant in the app; a hole in it is a deanonymization bug.
--   - the spec 8.2/8.3 onion SERVING seams (2026-08-15): the pure
--     payload builders and the acceptance path for the persona's
--     onion-httpd routes - rsAnonFeedPage (the deterministic HTML feed
--     page, entries escaped), rsAnonPrekeyBody (the signed RSK1 prekey
--     record as hex text for GET /prekey), and rsAnonAcceptDm (the
--     POST /dm body: a strict-hex refusal BEFORE any decode, then the
--     existing rsDmOpenIntro verify-then-parse under the persona's own
--     subkeys). The APP owns the oxh* routes and every stream; nothing
--     here does I/O, so all three are testable offline.
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
--   RSK1 prekey: magic(4) kxPub(64 hex) authorSig(64); exactly 132 bytes
--   RSI1 intro: magic(4) senderHandle(64 hex) senderKxPub(64 hex)
--     recipientHandle(64 hex) timestamp(u64 BE) authorSig(64); exactly
--     268 bytes; travels ONLY inside an sxSeal to the recipient's prekey
--   RSM1 frame: magic(4) kind(1: I/H/M, byte-exact) payload; the whole
--     frame fits the rp1 60000 cap
--   DM message (inside the secretstream): kind(1: T/O/A, byte-exact)
--     timestamp(u64 BE) body(UTF-8, non-empty); O/A carry SDP (phase 5)
--   RSL1 LAN challenge: magic(4) "C" nameLen(u8) name nonce(32)
--   RSL1 LAN response: magic(4) "R" nameLen(u8) name sig(64); sig is
--     ed25519 by the shared LAN key over "riptide-lan" || nonce || name
--   RSL1 LAN draft sync: magic(4) "D" nameLen(u8) name seq(u64 BE)
--     draftLen(u16 BE) draft(UTF-8, 0..4096; empty = cleared) sig(64)
--   RSL1 LAN feed state: magic(4) "F" nameLen(u8) name feedSeq(u64 BE)
--     readPeer(64 hex; all-zeros = none) readUpTo(u64 BE) sig(64)
--   RSL1 LAN presence: magic(4) "P" nameLen(u8) name flags(u8: bit0
--     typing, other bits refused) tick(u64 BE) sig(64)
--   RSL1 LAN media handoff: magic(4) "M" nameLen(u8) name seq(u64 BE)
--     infoHash(40 lowercase hex, non-zero) fileNameLen(u8) fileName
--     (UTF-8, 1..255) fileSize(u64 BE) sig(64); a POINTER at the
--     phase-3 torrent path, never the payload (the channel-2 decision)
--     ...the four sync sigs are ed25519 by the SAME shared LAN key over
--     "riptide-lan-s" || the whole record body, kind byte included
--   BTXO header: magic(4) ver(1) flags(1) nameLen(u16 BE) name total(u64)
--   BTXO data frame: len(u32 BE) bytes; the stream ends on a zero-len frame
--   Onion serving (spec 8.2/8.3, HTTP bodies over the persona's onion):
--     GET / -> the anon feed page, deterministic UTF-8 HTML (rsAnonFeedPage)
--     GET /prekey -> the persona's RSK1 record as 264 lowercase hex chars
--     POST /dm -> body IS the sealed RSI1 intro as EXACTLY 632 lowercase
--       hex chars (48 seal bytes + the 268-byte intro, times two); anything
--       else is refused before a byte is decoded
--   u64 travels as hi:u32 lo:u32 via binaryEncode("NN"), the BTXO discipline.
--   DHT targets travel as 40 ASCII hex; the all-zeros target means "none".
--   On the DHT (phase 2): the stored BEP44 v is the BENCODED byte string of
--     the record ("<len>:<bytes>"); the canonical signing buffer is
--     [4:salt<n>:<salt>] 3:seqi<seq>e 1:v <bencoded v> (BEP44, the exact
--     bytes btDhtBep44SignBuf returns and torrent_shim.cpp verifies); an
--     immutable item's target is SHA-1 of the bencoded value.

constant kRsVersion = "0.11.0"
constant kRsKeyMagic = "RIPTKEY1"
constant kRsHeadMagic = "RSH1"
constant kRsPostMagic = "RSP1"
constant kRsPrekeyMagic = "RSK1"
constant kRsIntroMagic = "RSI1"
constant kRsFrameMagic = "RSM1"
constant kRsFrameMax = 60000
constant kRsLanMagic = "RSL1"
constant kRsLanDomain = "riptide-lan"
constant kRsLanNonceLen = 32
constant kRsLanMaxName = 32
-- the phase-6 SYNC records over the admitted mesh: a distinct signature
-- domain (admission signs "riptide-lan", the welcome "riptide-lan-w"),
-- a draft-text cap (refused, never truncated - a draft over it still
-- lives locally, it just does not sync), and the all-zeros "no peer"
-- spelling for the feed-state record's optional read receipt
constant kRsLanSyncDomain = "riptide-lan-s"
constant kRsLanMaxDraft = 4096
-- the media-handoff record's file leaf name cap (the u8 length field;
-- refuse, never truncate - and every real platform's leaf cap anyway)
constant kRsLanMaxFile = 255
constant kRsZeroHandle = "0000000000000000000000000000000000000000000000000000000000000000"
constant kRsBtxoMagic = "BTXO"
constant kRsBtxoVer = 1
-- the BTXO RECEIVE path's stream caps (A3, 2026-08-23), PORTED from
-- nocloud's working receiver (kOnionMaxName / kOnionMaxTotal /
-- kOnionChunk in nocloudquickshare.livecodescript) rather than
-- re-derived: those three numbers have carried real Tor transfers, and
-- a re-derivation is exactly the class of constant that drifts. The
-- name cap refuses BEFORE the name is buffered (anti-DoS: a hostile
-- u16 nameLen must not make a receiver hold 65535 bytes hostage), the
-- total is the 8 GiB transfer ceiling, and the chunk cap bounds one
-- data frame - a length above it is hostile, not big
constant kRsBtxoMaxName = 1024
constant kRsBtxoMaxTotal = 8589934592
constant kRsBtxoChunk = 65536
-- the sequential-fetch streaming plan (B7, 2026-08-23): once metadata
-- arrives, the FRONT pieces get libtorrent deadlines (soonest deadlines
-- win) so the playback head is prioritized against stalls. Eight pieces
-- spaced a second apart is a PRIMER, not a schedule - sequential mode
-- already orders the rest, and a player seeking is the app's own re-plan
constant kRsMediaPlanPieces = 8
constant kRsMediaPlanSpacingMs = 1000
-- the POST /dm body: the sealed RSI1 intro as strict lowercase hex -
-- (48 sxSeal bytes + the 268-byte intro) * 2 hex chars = 632, exactly
constant kRsAnonDmBodyLen = 632
-- the anon feed page cap: a runaway compose must refuse, never build an
-- unbounded HTTP reply
constant kRsAnonPageMax = 65536
constant kRsAnonSubkeyBase = 100
constant kRsHeadSalt = "riptide-head"
constant kRsKdfContextText = "riptide"
constant kRsInboxSuffix = "riptide-inbox"
constant kRsZeroTarget = "0000000000000000000000000000000000000000"
constant kRsSubkeyIdentity = "1"
constant kRsSubkeyDm = "2"
constant kRsSubkeyLan = "3"
-- phase 8, the Nostr rail: subkey 4 is the secp256k1 secret key, subkey 5
-- the RIPTAPP1 app-state sealing key. Both are their own row for the reason
-- subkey 2 is separate from subkey 1 - one seed never feeds two schemes.
constant kRsSubkeyNostr = "4"
constant kRsSubkeyAppState = "5"
constant kRsSubkeyAnonBase = 100
constant kRsSubkeyAnonDmBase = 200
-- The RSN1 identity bridge (phase 8). The SIGNATURE domain and the BEP44
-- SALT are different strings on purpose: they live in different namespaces
-- and could safely collide, but the LAN rail already sets the house pattern
-- of a suffixed domain per record kind, and one string doing two jobs makes
-- a reader stop and work out that it is not a bug.
constant kRsNostrMagic = "RSN1"
constant kRsNostrDomain = "riptide-nostr-b"
constant kRsNostrSalt = "riptide-nostr"
constant kRsNostrBridgeLen = 276
constant kRsNostrBridgeBody = 148
-- the secp256k1 validity ladder's rung cap (see rsNostrSeckeyFrom)
constant kRsNostrLadderMax = 8
-- NIP-78 application-specific data, parameterized-replaceable: a bridge is
-- current state, not history, so a relay keeping only the newest is exactly
-- what the seq advancing should mean
constant kRsNostrBridgeKind = 30078
constant kRsNostrBridgeDTag = "riptide.bridge"
-- riptide's media convention on the Nostr wire: an `r` tag per attachment
-- carrying the magnet URI for its v1 info-hash. The bytes still ride the
-- phase-3 torrent rail; the tag is a POINTER, exactly as the LAN handoff
-- record is, and `r` because an ordinary Nostr client renders it as a link.
constant kRsMagnetPrefix = "magnet:?xt=urn:btih:"
-- the RIPTAPP1 app-state store: sealed under subkey 5, capped so a runaway
-- state blob refuses instead of writing an unbounded file
constant kRsAppMagic = "RIPTAPP1"
constant kRsAppStateMax = 1048576
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
         "(phase 7: identity, feed, media, DMs, LAN mesh, anon persona)"
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
   put false into tCaps["hasNostr"]
   put false into tCaps["hasNostrRelay"]
   put false into tCaps["canNostrSign"]
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
   -- The phase-8 Nostr rail probes in THREE parts, because the three things
   -- fail separately and each disables a different feature (rule 6):
   --   hasNostr      - the nx* CORE is loaded. A real round trip, not a
   --                   version sniff: hex-encode a known string and compare.
   --   canNostrSign  - the core can actually reach secp256k1 through CoinXT.
   --                   Deriving an x-only public key for a fixed valid
   --                   scalar exercises cxXOnlyPubkey, which is what every
   --                   signing path here needs; hasCoin alone does not
   --                   prove the nx* composition resolves.
   --   hasNostrRelay - the nxr* relay layer is loaded too. It is a SEPARATE
   --                   file that an app may legitimately not carry (it
   --                   cannot ride the suite paste beside onionxt), so the
   --                   whole compute rail must work without it.
   try
      put (nxHexEncode(textEncode("probe", "ASCII")) is "70726f6265") \
            into tCaps["hasNostr"]
   catch tIgnore
      put false into tCaps["hasNostr"]
   end try
   try
      put (the number of chars in nxKeyPublic( \
            "0000000000000000000000000000000000000000000000000000000000000001") \
            is 64) into tCaps["canNostrSign"]
   catch tIgnore
      put false into tCaps["canNostrSign"]
   end try
   try
      put (nxrVersion() is not empty) into tCaps["hasNostrRelay"]
   catch tIgnore
      put false into tCaps["hasNostrRelay"]
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

-- The anon persona's sealed-DM kx seed (spec 8.3): subkey 200+n, SEPARATE
-- from the persona's ed25519 identity for the same reason subkey 2 is
-- separate from subkey 1 - one seed never feeds two cipher schemes. This
-- one handler is all 8.3 needs from the library: the whole phase-4 record
-- machinery composes for anon personas unchanged - rsBuildPrekey(kxPub,
-- rsAnonSeed(...)) is the persona's prekey (served over its ONION, never
-- the DHT - the 9.3 guard), rsBuildIntro addressed to the anon handle
-- seals to it via rsDmSealIntro, and rsDmOpenIntro opens with THIS seed.
function rsAnonDmSeed pMaster, pIndex
   local tId
   if pIndex is not an integer or pIndex < 0 then
      rsSetError "rsAnonDmSeed: the persona index must be a non-negative" && \
            "integer"
      return empty
   end if
   put kRsSubkeyAnonDmBase + pIndex into tId
   return rsSubkey(pMaster, tId)
end rsAnonDmSeed

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
   -- pBytes is attacker-supplied, so a bad display name is a clean refusal.
   -- OXT's textDecode is LOSSY on malformed UTF-8, not throwing (see
   -- rsBytesAreUtf8 and the 2026-08-15 engine finding), so the refusal is a
   -- round-trip validity check, NOT a try - the try that used to sit here
   -- never fired and the head would have parsed with a mangled name.
   if not rsBytesAreUtf8(byte (tPos + 1) to (tPos + tNameLen) of pBytes) then
      rsSetError "rsParseHead: the display name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte (tPos + 1) to (tPos + tNameLen) of pBytes, "UTF-8") \
         into tHead["displayName"]
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
      -- Attacker-supplied bytes; malformed UTF-8 is a clean refusal. OXT's
      -- textDecode is lossy not throwing (see rsBytesAreUtf8), so validate
      -- by round-trip rather than a try that never fires.
      if not rsBytesAreUtf8(byte (tPos + 1) to (tPos + tTextLen) of pBytes) \
            then
         rsSetError "rsParsePost: the post text is not valid UTF-8"
         return empty
      end if
      put textDecode(byte (tPos + 1) to (tPos + tTextLen) of pBytes, \
            "UTF-8") into tPost["text"]
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

-- How many UTF-8 text bytes fit a DIRECT (kind-D) post beside pMediaCount
-- attachments. The arithmetic is the RSP1 layout itself against the BEP44
-- 1000-byte value cap, published as API so the app's D-or-C decision can
-- never drift from the builder's refusal - a hand-copied 880 in a demo is
-- exactly the class of constant this repo keeps finding stale. Returns
-- the byte budget, or empty on a media count outside 0..8.
function rsPostTextCapacity pMediaCount
   local tCount
   put pMediaCount into tCount
   if tCount is empty then put 0 into tCount
   if tCount is not an integer or tCount < 0 or tCount > kRsMaxMedia then
      rsSetError "rsPostTextCapacity: media count must be 0 to" && kRsMaxMedia
      return empty
   end if
   -- magic(4) + timestamp(8) + prevTarget(40) + kind(1) + textLen(2)
   -- + mediaCount(1) + 40 per media + authorSig(64), inside kRsMaxRecord
   return kRsMaxRecord - (4 + 8 + 40 + 1 + 2 + 1 + 64) - 40 * tCount
end rsPostTextCapacity

-- Split post text into kind-C chunk VALUES: full 1000-byte immutable
-- items in order, the last one carrying the remainder. The split is by
-- BYTE, deliberately - a boundary may fall inside a UTF-8 sequence, and
-- that is fine because reassembly validates and decodes the CONCATENATION,
-- never a chunk alone (rsAssembleChunkText). The split policy is
-- producer-local (any 1..16-chunk split of the same bytes reassembles
-- identically); the CAPS are the wire format's - at most 16 chunks of at
-- most 1000 bytes, so 16000 UTF-8 bytes is the most text a kind-C post
-- can carry, refused over (never truncated). Returns a numerically keyed
-- array (1..count) of chunk byte strings, or empty.
function rsChunkPostText pTextContent
   local tBytes, tLen, tPos, tTake, tI, tOut
   put textEncode(pTextContent, "UTF-8") into tBytes
   put the number of bytes in tBytes into tLen
   if tLen < 1 then
      rsSetError "rsChunkPostText: the text is empty"
      return empty
   end if
   if tLen > kRsMaxChunks * kRsMaxRecord then
      rsSetError "rsChunkPostText: the text is over" && \
            kRsMaxChunks * kRsMaxRecord && "UTF-8 bytes (" & kRsMaxChunks && \
            "chunks of" && kRsMaxRecord & "); refusing, not truncating"
      return empty
   end if
   put 0 into tPos
   put 0 into tI
   repeat while tPos < tLen
      put tLen - tPos into tTake
      if tTake > kRsMaxRecord then put kRsMaxRecord into tTake
      add 1 to tI
      put byte (tPos + 1) to (tPos + tTake) of tBytes into tOut[tI]
      add tTake to tPos
   end repeat
   return tOut
end rsChunkPostText

-- The reassembling half of the kind-C rail. pChunkTargets is the VERIFIED
-- post's chunk list (rsParsePost's comma-joined spelling - the order is
-- the wire's); pParts an array keyed by lowercase 40-hex target holding
-- the fetched chunk values (rsIngestBlob's output). Every part is
-- re-verified against its own content address BEFORE a byte of it is
-- believed - the chunks carry no signature of their own; the authorSig
-- covers the TARGETS, and the SHA-1 recompute is what extends it to the
-- bytes - and the CONCATENATION must round-trip as UTF-8 (per-part
-- validation would refuse valid posts split inside a sequence). Returns
-- the full text, or empty with the first missing target named - which is
-- how a caller renders an honest placeholder while parts are in flight.
function rsAssembleChunkText pChunkTargets, pParts
   local tCount, tItem, tNorm, tPart, tBytes, tErr
   set the itemDelimiter to comma
   put the number of items in pChunkTargets into tCount
   if tCount < 1 or tCount > kRsMaxChunks then
      rsSetError "rsAssembleChunkText: chunk count must be 1 to" && \
            kRsMaxChunks
      return empty
   end if
   put empty into tBytes
   repeat for each item tItem in pChunkTargets
      put rsNormalizeTarget(tItem) into tNorm
      if tNorm is empty or tNorm is kRsZeroTarget then
         rsSetError "rsAssembleChunkText: a chunk target must be 40" && \
               "non-zero hex"
         return empty
      end if
      put pParts[tNorm] into tPart
      if tPart is empty then
         rsSetError "rsAssembleChunkText: missing chunk" && tNorm
         return empty
      end if
      if rsImmutableTarget(tPart) is not tNorm then
         rsSetError "rsAssembleChunkText: chunk" && tNorm && \
               "does not hash to its own target"
         return empty
      end if
      put tPart after tBytes
   end repeat
   if not rsBytesAreUtf8(tBytes) then
      rsSetError "rsAssembleChunkText: the reassembled text is not" && \
            "valid UTF-8"
      return empty
   end if
   try
      return textDecode(tBytes, "UTF-8")
   catch tErr
      rsSetError "rsAssembleChunkText:" && tErr
      return empty
   end try
end rsAssembleChunkText

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

-- Verify one drained dhtImmutableItem EVENT as a raw content-addressed
-- blob (a kind-C text chunk, a profileMeta display-name blob): the event
-- must answer the awaited target, and the value's recomputed SHA-1 must
-- BE that target - a lying node is refused, and the returned bytes are
-- exactly the ones the (already verified) record named. This is
-- rsIngestPost minus the post parse: a blob carries no signature of its
-- own, and content addressing is what extends the author's signature
-- from the record that named the target to the fetched bytes. Returns
-- the value bytes, or empty.
function rsIngestBlob pEvent, pExpectedTarget
   local tExpected, tEventTarget, tValue, tComputed
   put rsNormalizeTarget(pExpectedTarget) into tExpected
   if tExpected is empty or tExpected is kRsZeroTarget then
      rsSetError "rsIngestBlob: the expected target must be 40 non-zero" && \
            "hex chars"
      return empty
   end if
   put toLower(pEvent["target"]) into tEventTarget
   if tEventTarget is not tExpected then
      rsSetError "rsIngestBlob: the event names a different target"
      return empty
   end if
   put pEvent["value"] into tValue
   put rsImmutableTarget(tValue) into tComputed
   if tComputed is empty then return empty
   if tComputed is not tExpected then
      rsSetError "rsIngestBlob: the value does not hash to its own target"
      return empty
   end if
   return tValue
end rsIngestBlob

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

-- The kind-C PRODUCER (backlog A2): split pTextContent into full
-- immutable chunks, store each, and publish the signed kind-C post that
-- names them in order. Everything is computed and signed BEFORE the
-- session is touched (chunk targets are content addresses, re-derivable
-- offline), so any refusal costs no network writes; a mid-publish
-- failure leaves already-stored chunks behind as harmless orphans -
-- content-addressed, author-anonymous immutable items nothing
-- references. Returns the post's 40-hex target (what the head's
-- latestPostTarget names, exactly rsPublishPost's contract), or empty.
function rsPublishChunkedPost pSession, pTimestamp, pPrevTarget, pTextContent, pMediaList, pIdentitySeed
   local tParts, tCount, tI, tTargets, tPost, tStored
   put rsChunkPostText(pTextContent) into tParts
   if tParts is empty then return empty
   put the number of elements in tParts into tCount
   put empty into tTargets
   repeat with tI = 1 to tCount
      if tTargets is not empty then put comma after tTargets
      put rsImmutableTarget(tParts[tI]) after tTargets
   end repeat
   put rsBuildPostChunked(pTimestamp, pPrevTarget, tTargets, pMediaList, \
         pIdentitySeed) into tPost
   if tPost is empty then return empty
   if not rsValidSession(pSession) then
      rsSetError "rsPublishChunkedPost: pSession is not a live torrent" && \
            "session handle"
      return empty
   end if
   repeat with tI = 1 to tCount
      put rsPublishImmutable(pSession, tParts[tI]) into tStored
      if tStored is empty then
         rsSetError "rsPublishChunkedPost: chunk" && tI && "of" && \
               tCount && "refused:" && rsLastError()
         return empty
      end if
   end repeat
   return rsPublishPost(pSession, tPost)
end rsPublishChunkedPost

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
   local tParent, tData, tH, tHash, tWhy, tErr, tSavedDelim
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
   -- itemDelimiter is GLOBAL mutable state and this is the library's only
   -- non-default set, so it is saved and restored around the NARROWEST
   -- possible span - the path split, nothing else. Restoring here rather
   -- than at each exit is not tidiness: this function has SEVEN exits, six
   -- of them refusals, and a restore per exit is a line a later refusal
   -- path forgets. The leak was real and its symptom was a mystery, not a
   -- delimiter: a caller's later comma-joined item read returned the whole
   -- list under "/" (the demo carried a point patch quoting exactly that).
   put the itemDelimiter into tSavedDelim
   set the itemDelimiter to "/"
   put item 1 to -2 of pPath into tParent
   set the itemDelimiter to tSavedDelim
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

-- The piece-deadline STREAMING PLAN (backlog B7, 2026-08-23), a SEPARATE
-- step from rsMediaFetch on purpose: the fetch path is btAddMagnet, and
-- a magnet has NO metadata and NO piece table at add time, so a deadline
-- set there would name pieces that do not exist. Call this once metadata
-- has arrived - the app's poll loop sees the metadataReceived event
-- (rsMediaStatus's filePath turning non-empty is the same moment). It
-- puts libtorrent deadlines on the FRONT pieces (btSetPieceDeadline:
-- soonest deadlines win), so the playback head is prioritized against
-- stalls that plain sequential ordering rides out slowly. A refusal is
-- always safe to ignore: the fetch stays sequential without it - which
-- is also the degrade for a torrentxt predating btSetPieceDeadline
-- (try-guarded, the probe-never-assume rule). Returns the number of
-- pieces planned, or empty.
function rsMediaStreamPlan pTorrent
   local tS, tPieces, tPlan, tI, tCode, tErr
   if pTorrent is not an integer or pTorrent <= 0 then
      rsSetError "rsMediaStreamPlan: pTorrent is not a torrent handle"
      return empty
   end if
   try
      put btTorrentStatus(pTorrent) into tS
   catch tErr
      rsSetError "rsMediaStreamPlan: needs torrentxt (btTorrentStatus):" && \
            tErr
      return empty
   end try
   if the keys of tS is empty then
      rsSetError "rsMediaStreamPlan: not a live torrent handle"
      return empty
   end if
   put tS["numPieces"] into tPieces
   if tPieces is not an integer or tPieces < 1 then
      rsSetError "rsMediaStreamPlan: metadata has not arrived yet (no" && \
            "piece table to set deadlines on)"
      return empty
   end if
   put tPieces into tPlan
   if tPlan > kRsMediaPlanPieces then put kRsMediaPlanPieces into tPlan
   repeat with tI = 0 to tPlan - 1
      try
         btSetPieceDeadline pTorrent, tI, (tI + 1) * kRsMediaPlanSpacingMs
         put the result into tCode
      catch tErr
         rsSetError "rsMediaStreamPlan: this torrentxt has no" && \
               "btSetPieceDeadline (the fetch stays sequential):" && tErr
         return empty
      end try
      if tCode is not 0 then
         rsSetError "rsMediaStreamPlan: btSetPieceDeadline refused (" & \
               tCode & ") at piece" && tI
         return empty
      end if
   end repeat
   return tPlan
end rsMediaStreamPlan

--------------------------------------------------------------------------
-- the DM layer (phase 4) - sealed first contact, then a pairwise
-- secretstream over rp1 (spec section 5)
--
-- The shape: your head's prekeyTarget names an RSK1 record (your crypto_kx
-- public, signed by your identity key). A stranger fetches it, seals an
-- RSI1 intro to that prekey (sxSeal: nobody on the inbox swarm learns the
-- contents, and the sender proves itself with an identity signature INSIDE
-- the sealed record), and sends it as an RSM1 "I" frame over rp1 in your
-- inbox phantom swarm. Both sides then derive one crypto_kx session
-- (deterministic roles: the lexically smaller handle is the kx CLIENT, the
-- same both-sides-agree discipline as the roomId sortedConcat), start a
-- secretstream in each direction ("H" header frame, then "M" ciphertext
-- frames), and every message inside the stream is a kind+timestamp+body
-- record. The library owns keys, records, and framing; the APP owns the
-- rp1 peer bookkeeping and the poll loop (the rp1-chat pattern), exactly
-- as it owns the DHT event loop in phase 2.
--------------------------------------------------------------------------

-- The crypto_kx keypair for the DM rail, from the DM subkey seed
-- (rsDmSeed of the master). Returns publicKey/secretKey as 32-byte Data
-- plus publicKeyHex - the spelling records carry.
function rsDmKeys pDmSeed
   local tPub, tSec, tKeys, tErr
   if the number of bytes in pDmSeed is not 32 then
      rsSetError "rsDmKeys: the DM seed must be 32 bytes (rsDmSeed of" && \
            "the master seed)"
      return empty
   end if
   try
      sxKeyExchangeKeypairFromSeed pDmSeed, tPub, tSec
   catch tErr
      rsSetError "rsDmKeys: needs SodiumXT" && \
            "(sxKeyExchangeKeypairFromSeed):" && tErr
      return empty
   end try
   if the number of bytes in tPub is not 32 then
      rsSetError "rsDmKeys: sxKeyExchangeKeypairFromSeed returned a" && \
            (the number of bytes in tPub) & "-byte public key"
      return empty
   end if
   put tPub into tKeys["publicKey"]
   put tSec into tKeys["secretKey"]
   put rsBinToHexString(tPub) into tKeys["publicKeyHex"]
   if tKeys["publicKeyHex"] is empty then return empty
   return tKeys
end rsDmKeys

-- One crypto_kx session for a pair, with the role decided by the SAME rule
-- on both machines: the peer whose HANDLE sorts lexically smaller (as
-- lowercase hex, which equals raw byte order) is the kx client. Returns
-- rx (receive key), tx (transmit key), and the role this side played -
-- my tx is the peer's rx, which the harness proves by deriving both sides.
function rsDmSessionKeys pMyHandleHex, pMyKxKeys, pTheirHandleHex, pTheirKxPubHex
   local tMine, tTheirs, tTheirPub, tRx, tTx, tOut, tErr
   put toLower(pMyHandleHex) into tMine
   put toLower(pTheirHandleHex) into tTheirs
   if not rsIsHexOfLen(tMine, 64) then
      rsSetError "rsDmSessionKeys: my handle must be 64 hex chars"
      return empty
   end if
   if not rsIsHexOfLen(tTheirs, 64) then
      rsSetError "rsDmSessionKeys: the peer handle must be 64 hex chars"
      return empty
   end if
   if tMine is tTheirs then
      rsSetError "rsDmSessionKeys: a DM session needs two DISTINCT handles"
      return empty
   end if
   if the number of bytes in pMyKxKeys["secretKey"] is not 32 then
      rsSetError "rsDmSessionKeys: pMyKxKeys must be the rsDmKeys array" && \
            "(32-byte secretKey)"
      return empty
   end if
   put rsHexToBin(pTheirKxPubHex) into tTheirPub
   if the number of bytes in tTheirPub is not 32 then
      rsSetError "rsDmSessionKeys: the peer kx public must be 64 hex chars"
      return empty
   end if
   try
      if tMine < tTheirs then
         sxKeyExchangeClient pMyKxKeys["publicKey"], \
               pMyKxKeys["secretKey"], tTheirPub, tRx, tTx
         put "client" into tOut["role"]
      else
         sxKeyExchangeServer pMyKxKeys["publicKey"], \
               pMyKxKeys["secretKey"], tTheirPub, tRx, tTx
         put "server" into tOut["role"]
      end if
   catch tErr
      rsSetError "rsDmSessionKeys: needs SodiumXT (sxKeyExchange):" && tErr
      return empty
   end try
   if the number of bytes in tRx is not 32 or \
         the number of bytes in tTx is not 32 then
      rsSetError "rsDmSessionKeys: sxKeyExchange returned session keys" && \
            "that are not 32 bytes"
      return empty
   end if
   put tRx into tOut["rx"]
   put tTx into tOut["tx"]
   return tOut
end rsDmSessionKeys

-- RSK1: the prekey record a head's prekeyTarget names. magic(4) then the
-- kx public as 64 hex, then the identity signature over every byte before
-- it - so a fetched prekey PROVES it belongs to the handle before anything
-- is sealed to it (a swapped prekey would make first contact readable by
-- the swapper; the signature is what refuses that).
function rsBuildPrekey pKxPubHex, pIdentitySeed
   local tPub, tBody
   put toLower(pKxPubHex) into tPub
   if not rsIsHexOfLen(tPub, 64) then
      rsSetError "rsBuildPrekey: the kx public must be 64 hex chars"
      return empty
   end if
   put textEncode(kRsPrekeyMagic, "ASCII") into tBody
   put textEncode(tPub, "ASCII") after tBody
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildPrekey

function rsParsePrekey pBytes
   local tOut, tField
   if the number of bytes in pBytes is not 132 then
      rsSetError "rsParsePrekey: an RSK1 record is exactly 132 bytes"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsPrekeyMagic then
      rsSetError "rsParsePrekey: bad magic, not an RSK1 record"
      return empty
   end if
   put textDecode(byte 5 to 68 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 64) then
      rsSetError "rsParsePrekey: malformed kx public key"
      return empty
   end if
   put tField into tOut["kxPub"]
   return tOut
end rsParsePrekey

-- Parse + verify in one refusal: the record's signature must be the
-- claimed author's. Returns the parsed array (kxPub) or empty.
function rsVerifyPrekey pBytes, pHandleHex
   local tOut
   put rsParsePrekey(pBytes) into tOut
   if tOut is empty then return empty
   return rsVerifyDmSigned(pBytes, pHandleHex, tOut)
end rsVerifyPrekey

-- Shared tail-signature check for the fixed-layout DM records (RSK1 and
-- RSI1): the last 64 bytes are ed25519 by pHandleHex over the rest.
-- Returns pParsed on success, empty on refusal.
private function rsVerifyDmSigned pBytes, pHandleHex, pParsed
   local tPub, tLen, tOk, tErr
   put rsHexToBin(pHandleHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsVerifyDmSigned: the handle must be 64 hex chars"
      return empty
   end if
   put the number of bytes in pBytes into tLen
   try
      put sxSignVerifyDetached(byte (tLen - 63) to tLen of pBytes, \
            byte 1 to (tLen - 64) of pBytes, tPub) into tOk
   catch tErr
      rsSetError "rsVerifyDmSigned: needs SodiumXT" && \
            "(sxSignVerifyDetached):" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsVerifyDmSigned: the signature does not verify under" && \
            pHandleHex
      return empty
   end if
   return pParsed
end rsVerifyDmSigned

-- RSI1: the intro record a stranger seals to your prekey. The recipient
-- handle sits INSIDE the signed body, which binds the intro to one inbox -
-- a third party replaying it to a different recipient fails the recipient
-- check rather than impersonating first contact. The sender handle is
-- derived from the signing seed, never passed, so a sender/signer mismatch
-- cannot be expressed.
function rsBuildIntro pTimestamp, pRecipientHandleHex, pSenderKxPubHex, pIdentitySeed
   local tRecipient, tKxPub, tSender, tBody
   if pTimestamp is not an integer or pTimestamp < 0 then
      rsSetError "rsBuildIntro: the timestamp must be a non-negative integer"
      return empty
   end if
   if pTimestamp >= 9007199254740992 then
      rsSetError "rsBuildIntro: the timestamp must be below 2^53"
      return empty
   end if
   put toLower(pRecipientHandleHex) into tRecipient
   if not rsIsHexOfLen(tRecipient, 64) then
      rsSetError "rsBuildIntro: the recipient handle must be 64 hex chars"
      return empty
   end if
   put toLower(pSenderKxPubHex) into tKxPub
   if not rsIsHexOfLen(tKxPub, 64) then
      rsSetError "rsBuildIntro: the sender kx public must be 64 hex chars"
      return empty
   end if
   put rsHandleFromSeed(pIdentitySeed) into tSender
   if tSender is empty then return empty
   put textEncode(kRsIntroMagic, "ASCII") into tBody
   put textEncode(tSender, "ASCII") after tBody
   put textEncode(tKxPub, "ASCII") after tBody
   put textEncode(tRecipient, "ASCII") after tBody
   put rsBEu64(pTimestamp) after tBody
   return rsSignPost(tBody, pIdentitySeed)
end rsBuildIntro

function rsParseIntro pBytes
   local tOut, tField
   if the number of bytes in pBytes is not 268 then
      rsSetError "rsParseIntro: an RSI1 record is exactly 268 bytes"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsIntroMagic then
      rsSetError "rsParseIntro: bad magic, not an RSI1 record"
      return empty
   end if
   put textDecode(byte 5 to 68 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 64) then
      rsSetError "rsParseIntro: malformed sender handle"
      return empty
   end if
   put tField into tOut["senderHandle"]
   put textDecode(byte 69 to 132 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 64) then
      rsSetError "rsParseIntro: malformed sender kx public"
      return empty
   end if
   put tField into tOut["senderKxPub"]
   put textDecode(byte 133 to 196 of pBytes, "ASCII") into tField
   if not rsIsHexOfLen(tField, 64) then
      rsSetError "rsParseIntro: malformed recipient handle"
      return empty
   end if
   put tField into tOut["recipientHandle"]
   put rsReadBEu64(byte 197 to 204 of pBytes) into tOut["timestamp"]
   return tOut
end rsParseIntro

-- Verify an intro FOR ME: the embedded sender's signature must hold, and
-- the embedded recipient must be my handle. Returns the parsed array
-- (senderHandle / senderKxPub / timestamp) or empty. Freshness windows on
-- the timestamp are the app's policy, not enforced here.
function rsVerifyIntro pBytes, pMyHandleHex
   local tOut
   put rsParseIntro(pBytes) into tOut
   if tOut is empty then return empty
   if tOut["recipientHandle"] is not toLower(pMyHandleHex) then
      rsSetError "rsVerifyIntro: this intro is addressed to" && \
            tOut["recipientHandle"] & ", not to me"
      return empty
   end if
   return rsVerifyDmSigned(pBytes, tOut["senderHandle"], tOut)
end rsVerifyIntro

-- Seal an intro to a recipient's prekey (verify the prekey against their
-- handle FIRST - rsVerifyPrekey - or you are sealing to an unproven key).
function rsDmSealIntro pIntroBytes, pRecipientKxPubHex
   local tPub, tOut, tErr
   if rsParseIntro(pIntroBytes) is empty then
      rsSetError "rsDmSealIntro: not a valid RSI1 record:" && rsLastError()
      return empty
   end if
   put rsHexToBin(pRecipientKxPubHex) into tPub
   if the number of bytes in tPub is not 32 then
      rsSetError "rsDmSealIntro: the recipient kx public must be 64 hex chars"
      return empty
   end if
   try
      put sxSeal(pIntroBytes, tPub) into tOut
   catch tErr
      rsSetError "rsDmSealIntro: needs SodiumXT (sxSeal):" && tErr
      return empty
   end try
   return tOut
end rsDmSealIntro

-- Open a sealed intro that arrived in my inbox: derive my kx keypair from
-- my DM seed, open the seal, then verify sender signature + recipient
-- binding. Returns the verified array or empty (wrong key, tamper, not
-- addressed to me, or a malformed record inside - one refusal for all).
function rsDmOpenIntro pSealedBytes, pMyHandleHex, pMyDmSeed
   local tKeys, tPlain, tErr
   if the number of bytes in pSealedBytes < 48 + 268 then
      rsSetError "rsDmOpenIntro: too short to be a sealed RSI1 intro"
      return empty
   end if
   put rsDmKeys(pMyDmSeed) into tKeys
   if tKeys is empty then return empty
   try
      put sxSealOpen(pSealedBytes, tKeys["publicKey"], \
            tKeys["secretKey"]) into tPlain
   catch tErr
      rsSetError "rsDmOpenIntro: the seal does not open with my prekey" && \
            "(wrong recipient or tampered):" && tErr
      return empty
   end try
   return rsVerifyIntro(tPlain, pMyHandleHex)
end rsDmOpenIntro

-- RSM1: the transport frame every rp1 payload wears. kind "I" carries a
-- sealed intro, "H" a secretstream header, "M" one ciphertext chunk. The
-- kind byte is checked by VALUE (73/72/77), not by `is` - `is` folds case,
-- and a non-canonical frame must be refused, not normalized.
function rsDmFrame pKind, pPayload
   local tKindByte, tOut
   if the number of chars in pKind is not 1 then
      rsSetError "rsDmFrame: the kind must be one of I, H, M"
      return empty
   end if
   put byteToNum(byte 1 of textEncode(pKind, "ASCII")) into tKindByte
   if tKindByte is not 73 and tKindByte is not 72 and tKindByte is not 77 then
      rsSetError "rsDmFrame: the kind must be one of I, H, M"
      return empty
   end if
   if the number of bytes in pPayload < 1 then
      rsSetError "rsDmFrame: the payload must be non-empty"
      return empty
   end if
   if the number of bytes in pPayload + 5 > kRsFrameMax then
      rsSetError "rsDmFrame: the frame is over the rp1" && kRsFrameMax && \
            "cap; a DM payload that size belongs in a torrent"
      return empty
   end if
   put textEncode(kRsFrameMagic, "ASCII") into tOut
   put numToByte(tKindByte) after tOut
   put pPayload after tOut
   return tOut
end rsDmFrame

function rsDmParseFrame pBytes
   local tOut, tKindByte
   if the number of bytes in pBytes < 6 then
      rsSetError "rsDmParseFrame: truncated frame"
      return empty
   end if
   if the number of bytes in pBytes > kRsFrameMax then
      rsSetError "rsDmParseFrame: frame over the rp1 cap"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsFrameMagic then
      rsSetError "rsDmParseFrame: bad magic, not an RSM1 frame"
      return empty
   end if
   put byteToNum(byte 5 of pBytes) into tKindByte
   if tKindByte is not 73 and tKindByte is not 72 and tKindByte is not 77 then
      rsSetError "rsDmParseFrame: unknown frame kind"
      return empty
   end if
   put textDecode(byte 5 of pBytes, "ASCII") into tOut["kind"]
   put byte 6 to -1 of pBytes into tOut["payload"]
   return tOut
end rsDmParseFrame

-- The plaintext INSIDE the secretstream: kind ("T" text, "O" sdp offer,
-- "A" sdp answer - the phase-5 signalling rides the same record), then the
-- timestamp, then the UTF-8 body. Encrypt the result with
-- sxSecretStreamPush; hand what sxSecretStreamPull returns back to
-- rsDmParseMessage.
function rsDmMessageBody pKind, pTimestamp, pBodyText
   local tKindByte, tBody, tOut
   if the number of chars in pKind is not 1 then
      rsSetError "rsDmMessageBody: the kind must be one of T, O, A"
      return empty
   end if
   put byteToNum(byte 1 of textEncode(pKind, "ASCII")) into tKindByte
   if tKindByte is not 84 and tKindByte is not 79 and tKindByte is not 65 then
      rsSetError "rsDmMessageBody: the kind must be one of T, O, A"
      return empty
   end if
   if pTimestamp is not an integer or pTimestamp < 0 then
      rsSetError "rsDmMessageBody: the timestamp must be a non-negative" && \
            "integer"
      return empty
   end if
   if pTimestamp >= 9007199254740992 then
      rsSetError "rsDmMessageBody: the timestamp must be below 2^53"
      return empty
   end if
   put textEncode(pBodyText, "UTF-8") into tBody
   if the number of bytes in tBody < 1 then
      rsSetError "rsDmMessageBody: the body must be non-empty"
      return empty
   end if
   put numToByte(tKindByte) into tOut
   put rsBEu64(pTimestamp) after tOut
   put tBody after tOut
   return tOut
end rsDmMessageBody

function rsDmParseMessage pBytes
   local tOut, tKindByte, tErr
   if the number of bytes in pBytes < 10 then
      rsSetError "rsDmParseMessage: truncated message record"
      return empty
   end if
   put byteToNum(byte 1 of pBytes) into tKindByte
   if tKindByte is not 84 and tKindByte is not 79 and tKindByte is not 65 then
      rsSetError "rsDmParseMessage: unknown message kind"
      return empty
   end if
   put textDecode(byte 1 of pBytes, "ASCII") into tOut["kind"]
   put rsReadBEu64(byte 2 to 9 of pBytes) into tOut["timestamp"]
   -- the body is authenticated (it came out of the secretstream) but is
   -- still declared UTF-8 text; OXT's textDecode is lossy not throwing (see
   -- rsBytesAreUtf8), so validate by round-trip rather than an inert try
   if not rsBytesAreUtf8(byte 10 to -1 of pBytes) then
      rsSetError "rsDmParseMessage: the body is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 10 to -1 of pBytes, "UTF-8") into tOut["text"]
   return tOut
end rsDmParseMessage

-- Join my inbox rendezvous swarm: enable rp1 (idempotent, and it must
-- happen BEFORE the swarm is added so the swarm advertises the extension -
-- the rp1-chat lesson), add the phantom swarm at rsInboxId(handle), and
-- announce. Returns the swarm's torrent handle, or empty. The announce
-- refusing is NON-fatal (the torrent's own DHT schedule still announces;
-- the explicit call just makes the first meeting faster).
function rsDmJoinInbox pSession, pHandleHex, pSavePath
   local tInbox, tCode, tH, tWhy, tErr
   put rsInboxId(pHandleHex) into tInbox
   if tInbox is empty then return empty
   if there is not a folder pSavePath then
      rsSetError "rsDmJoinInbox: no folder at" && pSavePath && \
            "(a phantom swarm still needs a valid save path)"
      return empty
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsDmJoinInbox: pSession is not a live torrent session" && \
            "handle"
      return empty
   end if
   try
      btRp1Enable pSession
      put the result into tCode
   catch tErr
      rsSetError "rsDmJoinInbox: needs torrentxt (btRp1Enable):" && tErr
      return empty
   end try
   if tCode is not empty and tCode < 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsDmJoinInbox: btRp1Enable refused (" & tCode & ")" && tWhy
      return empty
   end if
   try
      put btAddInfohash(pSession, tInbox, pSavePath) into tH
   catch tErr
      rsSetError "rsDmJoinInbox: needs torrentxt (btAddInfohash):" && tErr
      return empty
   end try
   if tH is 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsDmJoinInbox: btAddInfohash refused;" && tWhy
      return empty
   end if
   try
      btDhtAnnounce pSession, tInbox, 0
   catch tErr
      -- non-fatal: the swarm's own announce schedule still runs
   end try
   return tH
end rsDmJoinInbox

-- Send one RSM1 frame to one rp1 peer. The frame is re-parsed before it
-- leaves (nothing malformed goes on the wire), and the peer id must be
-- one the app learned from an rp1Handshake event with supportsRp1.
function rsDmSend pSession, pPeerId, pFrameBytes
   local tCode, tWhy, tErr
   if rsDmParseFrame(pFrameBytes) is empty then
      rsSetError "rsDmSend: not a valid RSM1 frame:" && rsLastError()
      return false
   end if
   if pPeerId is not an integer or pPeerId <= 0 then
      rsSetError "rsDmSend: pPeerId is not an rp1 peer id"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsDmSend: pSession is not a live torrent session handle"
      return false
   end if
   try
      btRp1Send pSession, pPeerId, pFrameBytes
      put the result into tCode
   catch tErr
      rsSetError "rsDmSend: needs torrentxt (btRp1Send):" && tErr
      return false
   end try
   if tCode is not empty and tCode < 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsDmSend: btRp1Send refused (" & tCode & ")" && tWhy && \
            "- the peer may be gone or its handshake incomplete"
      return false
   end if
   return true
end rsDmSend

--------------------------------------------------------------------------
-- the LAN mesh admission layer (phase 6) - device-to-device within ONE
-- identity (spec section 7)
--
-- Every device you own reconstructs the SAME master seed from your
-- passphrase, so every device derives the SAME LAN subkey ed25519 keypair
-- (rsLanKey -> sxSignKeypairFromSeed). Admission proves the joiner holds
-- the master: the host sends a random challenge, the joiner signs
-- "riptide-lan" || nonce || itsName under the LAN secret, and the host
-- verifies against the LAN public it derives from its OWN master. A
-- stranger on the same cafe Wi-Fi cannot produce that signature, so
-- cannot join the mesh. The records ride enet channel-0 messages (the
-- enConnect data rider is a u32 protocol tag, not a byte buffer, so the
-- proof is a first MESSAGE, not connect data). The APP owns the enet host
-- and the poll loop; the library owns the keypair and the two records.
--------------------------------------------------------------------------

-- The LAN mesh ed25519 keypair from the master seed. All your devices
-- derive the same one; publicKey/secretKey are 32/64 bytes as usual.
function rsLanKeys pMaster
   local tSeed
   put rsLanKey(pMaster) into tSeed
   if tSeed is empty then
      rsSetError "rsLanKeys: could not derive the LAN subkey:" && rsLastError()
      return empty
   end if
   return rsIdentityKeys(tSeed)
end rsLanKeys

-- Host -> joiner: magic(4) "C" nameLen(u8) name nonce(32). The nonce is
-- fresh randomness from the caller (sxRandomBytes(32)); a replayed
-- challenge would let a recorded response back in, so it must never be
-- reused. Names are UTF-8, 1..32 bytes.
function rsLanBuildChallenge pName, pNonce
   local tName, tOut
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildChallenge: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   if the number of bytes in pNonce is not kRsLanNonceLen then
      rsSetError "rsLanBuildChallenge: the nonce must be" && kRsLanNonceLen && \
            "bytes (use sxRandomBytes)"
      return empty
   end if
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("C", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put pNonce after tOut
   return tOut
end rsLanBuildChallenge

function rsLanParseChallenge pBytes
   local tLen, tNameLen, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 6 + kRsLanNonceLen then
      rsSetError "rsLanParseChallenge: truncated challenge"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "C" then
      rsSetError "rsLanParseChallenge: not an RSL1 challenge"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tLen is not 6 + tNameLen + kRsLanNonceLen then
      rsSetError "rsLanParseChallenge: length does not match its name field"
      return empty
   end if
   -- the name is attacker-controlled; OXT's textDecode is LOSSY, not throwing
   -- (see rsBytesAreUtf8), so validate by round-trip and REFUSE a malformed
   -- name rather than admit a mangled one into the poll pump (rule 5)
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanParseChallenge: the device name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put byte (7 + tNameLen) to tLen of pBytes into tOut["nonce"]
   return tOut
end rsLanParseChallenge

-- The bytes the admission signature covers: the domain tag, the challenge
-- nonce (freshness), and the joiner's OWN name (so a captured signature
-- cannot be replayed under a different device name).
private function rsLanSigMessage pNonce, pName
   local tOut
   put textEncode(kRsLanDomain, "ASCII") into tOut
   put pNonce after tOut
   put textEncode(pName, "UTF-8") after tOut
   return tOut
end rsLanSigMessage

-- Joiner -> host: magic(4) "R" nameLen(u8) name sig(64). Takes the host's
-- challenge bytes (for the nonce) and the joiner's master (for the LAN
-- secret). Returns the response record or empty.
function rsLanBuildResponse pChallengeBytes, pName, pMaster
   local tChallenge, tName, tKeys, tSig, tOut, tErr
   put rsLanParseChallenge(pChallengeBytes) into tChallenge
   if tChallenge is empty then
      rsSetError "rsLanBuildResponse: bad challenge:" && rsLastError()
      return empty
   end if
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildResponse: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignDetached(rsLanSigMessage(tChallenge["nonce"], pName), \
            tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsLanBuildResponse: needs SodiumXT (sxSignDetached):" && tErr
      return empty
   end try
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("R", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put tSig after tOut
   return tOut
end rsLanBuildResponse

function rsLanParseResponse pBytes
   local tLen, tNameLen, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 6 + 64 then
      rsSetError "rsLanParseResponse: truncated response"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "R" then
      rsSetError "rsLanParseResponse: not an RSL1 response"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tLen is not 6 + tNameLen + 64 then
      rsSetError "rsLanParseResponse: length does not match its name field"
      return empty
   end if
   -- attacker-controlled name; OXT's textDecode is lossy not throwing, so
   -- validate by round-trip and refuse a malformed name (a host draining an
   -- enet batch must not be handed a mangled one) - see rsBytesAreUtf8
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanParseResponse: the device name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put byte (7 + tNameLen) to tLen of pBytes into tOut["signature"]
   return tOut
end rsLanParseResponse

-- The host's verdict: does this response prove the joiner shares my
-- master? Rebuild the signed bytes from MY challenge's nonce and the
-- response's claimed name, and verify against the LAN public MY master
-- derives. Returns the joiner's device name on success, empty on refusal
-- (a stranger, a replayed response for a different nonce, or tamper).
function rsLanVerifyResponse pResponseBytes, pChallengeBytes, pMaster
   local tResp, tChallenge, tKeys, tOk, tErr
   put rsLanParseResponse(pResponseBytes) into tResp
   if tResp is empty then return empty
   put rsLanParseChallenge(pChallengeBytes) into tChallenge
   if tChallenge is empty then
      rsSetError "rsLanVerifyResponse: bad challenge:" && rsLastError()
      return empty
   end if
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignVerifyDetached(tResp["signature"], \
            rsLanSigMessage(tChallenge["nonce"], tResp["name"]), \
            tKeys["publicKey"]) into tOk
   catch tErr
      rsSetError "rsLanVerifyResponse: needs SodiumXT" && \
            "(sxSignVerifyDetached):" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsLanVerifyResponse: the response does not prove the" && \
            "shared master (a stranger, a stale nonce, or tamper)"
      return empty
   end if
   return tResp["name"]
end rsLanVerifyResponse

-- The bytes the welcome signature covers: a DISTINCT domain tag, the
-- joiner's own response signature (unique per challenge nonce, so the
-- welcome replays to no other handshake), and the host's name.
private function rsLanWelcomeSigMessage pResponseSig, pHostName
   local tOut
   put textEncode("riptide-lan-w", "ASCII") into tOut
   put pResponseSig after tOut
   put textEncode(pHostName, "UTF-8") after tOut
   return tOut
end rsLanWelcomeSigMessage

-- Host -> joiner after admission: magic(4) "W" nameLen(u8) hostName
-- sig(64). MUTUAL auth: the admission proved the joiner to the host; this
-- proves the host back to the joiner (only a master-holder can sign it),
-- and gives the joiner its positive "you are in" signal.
function rsLanBuildWelcome pResponseBytes, pHostName, pMaster
   local tResp, tName, tKeys, tSig, tOut, tErr
   put rsLanParseResponse(pResponseBytes) into tResp
   if tResp is empty then
      rsSetError "rsLanBuildWelcome: bad response:" && rsLastError()
      return empty
   end if
   put textEncode(pHostName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildWelcome: the host name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignDetached(rsLanWelcomeSigMessage(tResp["signature"], \
            pHostName), tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsLanBuildWelcome: needs SodiumXT (sxSignDetached):" && tErr
      return empty
   end try
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("W", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put tSig after tOut
   return tOut
end rsLanBuildWelcome

function rsLanParseWelcome pBytes
   local tLen, tNameLen, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 6 + 64 then
      rsSetError "rsLanParseWelcome: truncated welcome"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "W" then
      rsSetError "rsLanParseWelcome: not an RSL1 welcome"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tLen is not 6 + tNameLen + 64 then
      rsSetError "rsLanParseWelcome: length does not match its name field"
      return empty
   end if
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanParseWelcome: the host name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put byte (7 + tNameLen) to tLen of pBytes into tOut["signature"]
   return tOut
end rsLanParseWelcome

-- The joiner's verdict on the host: does this welcome prove the host
-- shares my master, for THIS handshake? Takes the response I MYSELF sent
-- (its signature is what the welcome must be bound to). Returns the host's
-- device name, or empty (a rogue host, a replayed welcome from another
-- handshake, or tamper).
function rsLanVerifyWelcome pWelcomeBytes, pMyResponseBytes, pMaster
   local tWelcome, tResp, tKeys, tOk, tErr
   put rsLanParseWelcome(pWelcomeBytes) into tWelcome
   if tWelcome is empty then return empty
   put rsLanParseResponse(pMyResponseBytes) into tResp
   if tResp is empty then
      rsSetError "rsLanVerifyWelcome: bad own-response bytes:" && rsLastError()
      return empty
   end if
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignVerifyDetached(tWelcome["signature"], \
            rsLanWelcomeSigMessage(tResp["signature"], tWelcome["name"]), \
            tKeys["publicKey"]) into tOk
   catch tErr
      rsSetError "rsLanVerifyWelcome: needs SodiumXT" && \
            "(sxSignVerifyDetached):" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsLanVerifyWelcome: the welcome does not prove the" && \
            "shared master for this handshake (a rogue host, a replay," && \
            "or tamper)"
      return empty
   end if
   return tWelcome["name"]
end rsLanVerifyWelcome

--------------------------------------------------------------------------
-- the phase-6 SYNC records over the ADMITTED mesh (spec section 7's
-- channel discipline: drafts + feed state on channel 0 reliable,
-- presence/typing on channel 1 unreliable-unsequenced)
--
-- THE AUTHENTICATION CHOICE, recorded (do not re-litigate). Every sync
-- record is SIGNED under the SAME shared LAN ed25519 key the admission
-- uses, with a DISTINCT domain tag - "riptide-lan-s"; admission signs
-- "riptide-lan", the welcome "riptide-lan-w" - over the WHOLE record
-- body, kind byte included, so an admission signature can never be
-- replayed as a sync record, and one sync kind can never be read as
-- another (the case-folded-kind trick dies on the signature too: the
-- sig covers the raw bytes). The admission WELCOME leaves no fresh
-- session secret behind - it is mutual signature verification, not a
-- key exchange - so the only secret material both sides hold afterwards
-- is the master-derived LAN keypair itself, and deriving a per-handshake
-- MAC key from that ed25519 seed would feed one seed to two cipher
-- schemes (the registry rule that made subkey 2 separate from subkey 1).
-- A per-handshake session binder was considered and REJECTED: a record
-- the host relays hub-and-spoke must verify identically at EVERY
-- admitted peer, and the replay a binder would stop is already neutral
-- because every record's APPLY semantics are monotonic or absolute (a
-- draft's per-device seq only moves forward, feed/read state applies as
-- max, a presence tick only moves forward) and only ADMITTED peers'
-- records are applied at all. Two honest limits, also recorded: the
-- records are authenticated, NOT encrypted - a LAN observer reads draft
-- plaintext (the spec's admission-only design; confidentiality would
-- need a new traffic subkey and is not claimed) - and the device NAME
-- is a cooperative label among your own devices, not an identity (all
-- of them share the one keypair, the phase-6 decision): a signature
-- proves "a master-holder said this", the name says which device
-- claims to have said it.
--------------------------------------------------------------------------

-- A wire counter (seq / tick / timestamp): a non-negative integer below
-- 2^53, the exact-double cap (the rsDmMessageBody discipline).
private function rsLanValidCount pValue
   if pValue is not an integer then return false
   if pValue < 0 then return false
   if pValue >= 9007199254740992 then return false
   return true
end rsLanValidCount

-- Sign a sync-record body under the shared LAN key, domain-tagged.
private function rsLanSyncSign pBody, pMaster
   local tKeys, tSig, tErr
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignDetached(textEncode(kRsLanSyncDomain, "ASCII") & pBody, \
            tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsLanSyncSign: needs SodiumXT (sxSignDetached):" && tErr
      return empty
   end try
   return tSig
end rsLanSyncSign

-- The shared-master verdict on a sync record: "true" / "false", or empty
-- on an environment failure (no SodiumXT, a bad master) with the reason
-- recorded - callers must treat only "true" as proof.
private function rsLanSyncSigOk pBody, pSig, pMaster
   local tKeys, tOk, tErr
   put rsLanKeys(pMaster) into tKeys
   if tKeys is empty then return empty
   try
      put sxSignVerifyDetached(pSig, \
            textEncode(kRsLanSyncDomain, "ASCII") & pBody, \
            tKeys["publicKey"]) into tOk
   catch tErr
      rsSetError "rsLanSyncSigOk: needs SodiumXT" && \
            "(sxSignVerifyDetached):" && tErr
      return empty
   end try
   if tOk is true then return "true"
   return "false"
end rsLanSyncSigOk

-- Channel-0 draft sync: magic(4) "D" nameLen(u8) name seq(u64 BE)
-- draftLen(u16 BE) draft sig(64). The draft is ABSOLUTE state (the whole
-- current text, empty meaning cleared), and the per-device seq is what
-- lets a receiver refuse a replayed or reordered draft: apply only a seq
-- strictly above the last one applied for that device.
function rsLanBuildDraft pName, pSeq, pDraftText, pMaster
   local tName, tDraft, tOut, tSig
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildDraft: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   if not rsLanValidCount(pSeq) then
      rsSetError "rsLanBuildDraft: the seq must be a non-negative" && \
            "integer below 2^53"
      return empty
   end if
   put textEncode(pDraftText, "UTF-8") into tDraft
   if the number of bytes in tDraft > kRsLanMaxDraft then
      rsSetError "rsLanBuildDraft: the draft is over the" && \
            kRsLanMaxDraft & "-byte sync cap (refused, never truncated)"
      return empty
   end if
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("D", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put rsBEu64(pSeq) after tOut
   put rsBEu16(the number of bytes in tDraft) after tOut
   put tDraft after tOut
   put rsLanSyncSign(tOut, pMaster) into tSig
   if tSig is empty then return empty
   put tSig after tOut
   return tOut
end rsLanBuildDraft

-- Verify-then-parse a draft record: structure first (exact length, to
-- the byte), then the shared-master signature, and only THEN believe a
-- field. Returns name / seq / draft, or empty with a distinct refusal.
function rsLanVerifyDraft pBytes, pMaster
   local tLen, tNameLen, tDraftLen, tVerdict, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 81 then
      rsSetError "rsLanVerifyDraft: truncated draft record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "D" then
      rsSetError "rsLanVerifyDraft: not an RSL1 draft record"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tNameLen < 1 or tNameLen > kRsLanMaxName then
      rsSetError "rsLanVerifyDraft: bad device-name length"
      return empty
   end if
   if tLen < 80 + tNameLen then
      rsSetError "rsLanVerifyDraft: length does not match its name field"
      return empty
   end if
   put rsReadBEu16(byte (15 + tNameLen) to (16 + tNameLen) of pBytes) \
         into tDraftLen
   if tDraftLen > kRsLanMaxDraft then
      rsSetError "rsLanVerifyDraft: the draft field is over the" && \
            kRsLanMaxDraft & "-byte cap"
      return empty
   end if
   if tLen is not 80 + tNameLen + tDraftLen then
      rsSetError "rsLanVerifyDraft: length does not match its draft field"
      return empty
   end if
   put rsLanSyncSigOk(byte 1 to (tLen - 64) of pBytes, \
         byte (tLen - 63) to tLen of pBytes, pMaster) into tVerdict
   if tVerdict is empty then return empty
   if tVerdict is not "true" then
      rsSetError "rsLanVerifyDraft: the record does not prove the" && \
            "shared master (a stranger, or tamper)"
      return empty
   end if
   -- decode AFTER the proof; OXT's textDecode is lossy not throwing, so
   -- UTF-8 validity is a round-trip check (rsBytesAreUtf8), refused clean
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanVerifyDraft: the device name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put rsReadBEu64(byte (7 + tNameLen) to (14 + tNameLen) of pBytes) \
         into tOut["seq"]
   if tDraftLen is 0 then
      put empty into tOut["draft"]
   else
      if not rsBytesAreUtf8(byte (17 + tNameLen) to \
            (16 + tNameLen + tDraftLen) of pBytes) then
         rsSetError "rsLanVerifyDraft: the draft text is not valid UTF-8"
         return empty
      end if
      put textDecode(byte (17 + tNameLen) to (16 + tNameLen + tDraftLen) \
            of pBytes, "UTF-8") into tOut["draft"]
   end if
   return tOut
end rsLanVerifyDraft

-- Channel-0 feed-seq / read-receipt state: magic(4) "F" nameLen(u8) name
-- feedSeq(u64 BE) readPeer(64 hex; all-zeros = none) readUpTo(u64 BE)
-- sig(64). Absolute state, applied as MAX on both halves: feedSeq is the
-- device's latest published head seq (so two devices never publish a
-- conflicting head), and readPeer/readUpTo say "I have read the DM
-- conversation with that handle up to that timestamp". Pass pReadPeerHex
-- empty (and pReadUpTo 0) for a pure feed-seq claim.
function rsLanBuildFeedState pName, pFeedSeq, pReadPeerHex, pReadUpTo, pMaster
   local tName, tPeer, tOut, tSig
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildFeedState: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   if not rsLanValidCount(pFeedSeq) then
      rsSetError "rsLanBuildFeedState: the feed seq must be a" && \
            "non-negative integer below 2^53"
      return empty
   end if
   if pReadPeerHex is empty then
      put kRsZeroHandle into tPeer
   else
      put toLower(pReadPeerHex) into tPeer
      if not rsIsHexOfLen(tPeer, 64) then
         rsSetError "rsLanBuildFeedState: the read-receipt peer must be" && \
               "empty or a 64-hex handle"
         return empty
      end if
   end if
   if not rsLanValidCount(pReadUpTo) then
      rsSetError "rsLanBuildFeedState: the read-up-to timestamp must be" && \
            "a non-negative integer below 2^53"
      return empty
   end if
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("F", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put rsBEu64(pFeedSeq) after tOut
   put textEncode(tPeer, "ASCII") after tOut
   put rsBEu64(pReadUpTo) after tOut
   put rsLanSyncSign(tOut, pMaster) into tSig
   if tSig is empty then return empty
   put tSig after tOut
   return tOut
end rsLanBuildFeedState

-- Verify-then-parse a feed-state record. Returns name / feedSeq /
-- readPeer (empty for the all-zeros "none") / readUpTo, or empty.
function rsLanVerifyFeedState pBytes, pMaster
   local tLen, tNameLen, tPeer, tVerdict, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 151 then
      rsSetError "rsLanVerifyFeedState: truncated feed-state record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "F" then
      rsSetError "rsLanVerifyFeedState: not an RSL1 feed-state record"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tNameLen < 1 or tNameLen > kRsLanMaxName then
      rsSetError "rsLanVerifyFeedState: bad device-name length"
      return empty
   end if
   if tLen is not 150 + tNameLen then
      rsSetError "rsLanVerifyFeedState: length does not match its name" && \
            "field"
      return empty
   end if
   put rsLanSyncSigOk(byte 1 to (tLen - 64) of pBytes, \
         byte (tLen - 63) to tLen of pBytes, pMaster) into tVerdict
   if tVerdict is empty then return empty
   if tVerdict is not "true" then
      rsSetError "rsLanVerifyFeedState: the record does not prove the" && \
            "shared master (a stranger, or tamper)"
      return empty
   end if
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanVerifyFeedState: the device name is not valid UTF-8"
      return empty
   end if
   -- the peer travels as 64 ASCII hex; strict lowercase, by byte value
   put textDecode(byte (15 + tNameLen) to (78 + tNameLen) of pBytes, \
         "ASCII") into tPeer
   if not rsIsHexOfLen(tPeer, 64) then
      rsSetError "rsLanVerifyFeedState: the read-receipt peer is not" && \
            "64 lowercase hex chars"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put rsReadBEu64(byte (7 + tNameLen) to (14 + tNameLen) of pBytes) \
         into tOut["feedSeq"]
   if tPeer is kRsZeroHandle then
      put empty into tOut["readPeer"]
   else
      put tPeer into tOut["readPeer"]
   end if
   put rsReadBEu64(byte (79 + tNameLen) to (86 + tNameLen) of pBytes) \
         into tOut["readUpTo"]
   return tOut
end rsLanVerifyFeedState

-- Channel-1 presence/typing: magic(4) "P" nameLen(u8) name flags(u8:
-- bit0 typing, every other bit refused fail-closed) tick(u64 BE) sig(64).
-- ABSOLUTE state, engineered to be safely droppable: the record says
-- "as of tick N this device is (not) typing", the per-device tick makes
-- it reorder-proof without enet sequencing (apply only a tick strictly
-- above the last applied), and any lost record is repaired by the next
-- one - senders re-assert on a cadence, they never send deltas.
function rsLanBuildPresence pName, pTyping, pTick, pMaster
   local tName, tFlags, tOut, tSig
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildPresence: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   if pTyping is not true and pTyping is not false then
      rsSetError "rsLanBuildPresence: typing must be true or false"
      return empty
   end if
   if not rsLanValidCount(pTick) then
      rsSetError "rsLanBuildPresence: the tick must be a non-negative" && \
            "integer below 2^53"
      return empty
   end if
   if pTyping is true then
      put 1 into tFlags
   else
      put 0 into tFlags
   end if
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("P", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put numToByte(tFlags) after tOut
   put rsBEu64(pTick) after tOut
   put rsLanSyncSign(tOut, pMaster) into tSig
   if tSig is empty then return empty
   put tSig after tOut
   return tOut
end rsLanBuildPresence

-- Verify-then-parse a presence record. Returns name / typing (true or
-- false) / tick, or empty with a distinct refusal. Unknown flag bits are
-- refused fail-closed - a newer record format must never half-parse.
function rsLanVerifyPresence pBytes, pMaster
   local tLen, tNameLen, tFlags, tVerdict, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 80 then
      rsSetError "rsLanVerifyPresence: truncated presence record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "P" then
      rsSetError "rsLanVerifyPresence: not an RSL1 presence record"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tNameLen < 1 or tNameLen > kRsLanMaxName then
      rsSetError "rsLanVerifyPresence: bad device-name length"
      return empty
   end if
   if tLen is not 79 + tNameLen then
      rsSetError "rsLanVerifyPresence: length does not match its name" && \
            "field"
      return empty
   end if
   put byteToNum(byte (7 + tNameLen) of pBytes) into tFlags
   if tFlags is not 0 and tFlags is not 1 then
      rsSetError "rsLanVerifyPresence: unknown flag bits (refused" && \
            "fail-closed)"
      return empty
   end if
   put rsLanSyncSigOk(byte 1 to (tLen - 64) of pBytes, \
         byte (tLen - 63) to tLen of pBytes, pMaster) into tVerdict
   if tVerdict is empty then return empty
   if tVerdict is not "true" then
      rsSetError "rsLanVerifyPresence: the record does not prove the" && \
            "shared master (a stranger, or tamper)"
      return empty
   end if
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanVerifyPresence: the device name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   if tFlags is 1 then
      put true into tOut["typing"]
   else
      put false into tOut["typing"]
   end if
   put rsReadBEu64(byte (8 + tNameLen) to (15 + tNameLen) of pBytes) \
         into tOut["tick"]
   return tOut
end rsLanVerifyPresence

-- Channel-0 media handoff: magic(4) "M" nameLen(u8) name seq(u64 BE)
-- infoHash(40 lowercase hex) fileNameLen(u8) fileName fileSize(u64 BE)
-- sig(64). THE CHANNEL-2 DECISION, recorded (2026-08-16; do not
-- re-litigate): spec section 7 reserves channel 2 for bulk handoff BELOW
-- the 60000-byte packet budget, and a draft's media (a photo, a video)
-- essentially never fits it - the suite's seam law (enetxt) is that a
-- payload over the budget stops being a message and becomes a torrent.
-- So the handoff is this small channel-0 POINTER at the phase-3 media
-- machinery (rsMediaCreate seeds in place on the sender; rsMediaFetch
-- joins the swarm on the receiver - the one rail of this app already
-- proven end to end on two machines), and channel 2 stays RESERVED,
-- dark, until a genuinely sub-budget bulk case exists (none does today:
-- drafts already ride channel 0, capped at 4096). A chunked enet lane
-- was considered and REJECTED - it would reimplement libtorrent's
-- per-piece integrity, resume, and backpressure with none of its proof.
-- The 40-hex v1 info-hash is deliberately BOTH fields the design needs:
-- the content address libtorrent verifies piece-by-piece against (the
-- receiver cannot be fed different bytes than the hash names) and the
-- torrent linkage a magnet fetch takes. fileName/fileSize are for the
-- receiving UI only - the torrent's own metadata is the authority once
-- fetched. ABSOLUTE state (the device's LATEST offer), the draft
-- record's replay guard (apply only a strictly higher seq per device);
-- a duplicate apply is harmless anyway, because rsMediaFetch finds
-- before it adds.
function rsLanBuildHandoff pName, pSeq, pInfoHash, pFileName, pFileSize, pMaster
   local tName, tHash, tFile, tOut, tSig
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or \
         the number of bytes in tName > kRsLanMaxName then
      rsSetError "rsLanBuildHandoff: the device name must be 1 to" && \
            kRsLanMaxName && "bytes"
      return empty
   end if
   if not rsLanValidCount(pSeq) then
      rsSetError "rsLanBuildHandoff: the seq must be a non-negative" && \
            "integer below 2^53"
      return empty
   end if
   put toLower(pInfoHash) into tHash
   if not rsIsHexOfLen(tHash, 40) or tHash is kRsZeroTarget then
      rsSetError "rsLanBuildHandoff: the info-hash must be 40 non-zero" && \
            "hex chars (what rsMediaCreate returned)"
      return empty
   end if
   put textEncode(pFileName, "UTF-8") into tFile
   if the number of bytes in tFile < 1 or \
         the number of bytes in tFile > kRsLanMaxFile then
      rsSetError "rsLanBuildHandoff: the file name must be 1 to" && \
            kRsLanMaxFile && "bytes (refused, never truncated)"
      return empty
   end if
   if not rsLanValidCount(pFileSize) then
      rsSetError "rsLanBuildHandoff: the file size must be a" && \
            "non-negative integer below 2^53"
      return empty
   end if
   put textEncode(kRsLanMagic, "ASCII") into tOut
   put textEncode("M", "ASCII") after tOut
   put numToByte(the number of bytes in tName) after tOut
   put tName after tOut
   put rsBEu64(pSeq) after tOut
   put textEncode(tHash, "ASCII") after tOut
   put numToByte(the number of bytes in tFile) after tOut
   put tFile after tOut
   put rsBEu64(pFileSize) after tOut
   put rsLanSyncSign(tOut, pMaster) into tSig
   if tSig is empty then return empty
   put tSig after tOut
   return tOut
end rsLanBuildHandoff

-- Verify-then-parse a media-handoff record: structure first (exact
-- length, to the byte), then the shared-master signature, and only THEN
-- believe a field. Returns name / seq / infoHash / fileName / fileSize,
-- or empty with a distinct refusal. The hash is checked strict lowercase
-- by byte value post-proof (the feed-state peer discipline), and the
-- all-zeros hash is refused - a handoff must name real content.
function rsLanVerifyHandoff pBytes, pMaster
   local tLen, tNameLen, tFileLen, tHash, tVerdict, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 129 then
      rsSetError "rsLanVerifyHandoff: truncated handoff record"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsLanMagic or \
         textDecode(byte 5 of pBytes, "ASCII") is not "M" then
      rsSetError "rsLanVerifyHandoff: not an RSL1 media-handoff record"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tNameLen
   if tNameLen < 1 or tNameLen > kRsLanMaxName then
      rsSetError "rsLanVerifyHandoff: bad device-name length"
      return empty
   end if
   if tLen < 128 + tNameLen then
      rsSetError "rsLanVerifyHandoff: length does not match its name field"
      return empty
   end if
   put byteToNum(byte (55 + tNameLen) of pBytes) into tFileLen
   if tFileLen < 1 then
      rsSetError "rsLanVerifyHandoff: bad file-name length"
      return empty
   end if
   if tLen is not 127 + tNameLen + tFileLen then
      rsSetError "rsLanVerifyHandoff: length does not match its" && \
            "file-name field"
      return empty
   end if
   put rsLanSyncSigOk(byte 1 to (tLen - 64) of pBytes, \
         byte (tLen - 63) to tLen of pBytes, pMaster) into tVerdict
   if tVerdict is empty then return empty
   if tVerdict is not "true" then
      rsSetError "rsLanVerifyHandoff: the record does not prove the" && \
            "shared master (a stranger, or tamper)"
      return empty
   end if
   if not rsBytesAreUtf8(byte 7 to (6 + tNameLen) of pBytes) then
      rsSetError "rsLanVerifyHandoff: the device name is not valid UTF-8"
      return empty
   end if
   -- the hash travels as 40 ASCII hex; strict lowercase, by byte value
   put textDecode(byte (15 + tNameLen) to (54 + tNameLen) of pBytes, \
         "ASCII") into tHash
   if not rsIsHexOfLen(tHash, 40) or tHash is kRsZeroTarget then
      rsSetError "rsLanVerifyHandoff: the info-hash is not 40 non-zero" && \
            "lowercase hex chars"
      return empty
   end if
   if not rsBytesAreUtf8(byte (56 + tNameLen) to \
         (55 + tNameLen + tFileLen) of pBytes) then
      rsSetError "rsLanVerifyHandoff: the file name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 7 to (6 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put rsReadBEu64(byte (7 + tNameLen) to (14 + tNameLen) of pBytes) \
         into tOut["seq"]
   put tHash into tOut["infoHash"]
   put textDecode(byte (56 + tNameLen) to (55 + tNameLen + tFileLen) \
         of pBytes, "UTF-8") into tOut["fileName"]
   put rsReadBEu64(byte (56 + tNameLen + tFileLen) to \
         (63 + tNameLen + tFileLen) of pBytes) into tOut["fileSize"]
   return tOut
end rsLanVerifyHandoff

--------------------------------------------------------------------------
-- the anonymous persona (phase 7) - a separate identity that lives ONLY
-- as an onion service (spec section 8), and the deanonymization guard
-- (section 9.3, the highest-severity invariant in the app)
--
-- An anon persona is the ed25519 identity of a subkey-100+n seed. Its
-- .onion is that key the same way the public identity's is, so it is
-- derivable offline (rsAnonOnion), and it NEVER touches the DHT, a
-- torrent, or rp1: publishing a BEP44 head or announcing a swarm under
-- the anon key would emit its IP and let anyone link its onion to its DHT
-- presence. rsPersonaAllows is the pure policy every transport branch
-- asserts through, fail-closed. The BTXO framing (shared with the Model C
-- onion file transfer) moves files over a Tor stream, never as a torrent -
-- anonymity's honest cost.
--------------------------------------------------------------------------

-- The anon persona's 64-hex handle: the ed25519 public of its subkey.
function rsAnonHandle pMaster, pIndex
   local tSeed
   put rsAnonSeed(pMaster, pIndex) into tSeed
   if tSeed is empty then
      rsSetError "rsAnonHandle: could not derive the anon subkey:" && \
            rsLastError()
      return empty
   end if
   return rsHandleFromSeed(tSeed)
end rsAnonHandle

-- The anon persona's .onion address (the SAME key as a v3 onion). Needs a
-- SHA3 provider for the offline checksum, exactly like the public onion;
-- returns empty with a clear error when neither provider is present.
function rsAnonOnion pMaster, pIndex
   local tHandle
   put rsAnonHandle(pMaster, pIndex) into tHandle
   if tHandle is empty then return empty
   return rsOnionFromHandle(tHandle)
end rsAnonOnion

-- THE deanonymization guard (spec 9.3). Pure policy, no I/O: given the
-- active persona's isAnon flag and a named transport, may this persona use
-- it? An anon persona may use ONLY the onion; a public persona may use
-- anything EXCEPT the anon onion route. An unknown transport name is
-- refused for BOTH (fail-closed: a typo must never read as "allowed").
-- Every send/publish branch in the app asserts through this before it
-- selects a transport, so a violation is a refusal with a message, never a
-- silent clearnet leak.
-- 2026-08-28: "nostr" joins the vocabulary with the phase-8 rail, and it is
-- the transport this guard most obviously exists for. A Nostr relay is a
-- CLEARNET websocket to somebody else's server: it sees your IP, it sees
-- every event you publish, and NIP-42 auth would name you to it. So an anon
-- persona may never take it - which the existing rule already says (anon
-- gets onion and nothing else), and which the harness now asserts as its
-- own cell rather than leaving it to be inferred from the rule's shape.
function rsPersonaAllows pIsAnon, pTransport
   local tKnown, tSaved, tKnownTransport
   put "onion,dht,torrent,rp1,enet,dc,feed,media,nostr" into tKnown
   -- SAVE AND RESTORE, and this one is a fix rather than a habit: this
   -- handler set the itemDelimiter and never put it back, leaking comma to
   -- everything that ran after it. That is the C10 defect (rsMediaCreate
   -- leaking "/" for the rest of the session) in the one handler where it
   -- reads worst - the app's Anon card paints the guard panel by calling
   -- this nine times in a row, so a card repaint silently reset the
   -- delimiter under whatever the pump was doing next. Benign in practice
   -- only because comma IS the engine default, which is exactly why it
   -- survived the 2026-08-17 sweep that found the other one. Fixed the same
   -- way that one was: restore around the NARROWEST span, not at each exit,
   -- because a restore per exit is the line the next refusal path forgets.
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put (pTransport is among the items of tKnown) into tKnownTransport
   set the itemDelimiter to tSaved
   if not tKnownTransport then
      rsSetError "rsPersonaAllows: unknown transport" && quote & pTransport & \
            quote & " - refusing fail-closed"
      return false
   end if
   if pIsAnon is true then
      return pTransport is "onion"
   end if
   return pTransport is not "onion"
end rsPersonaAllows

-- Create the anon persona's onion service (probe-gated: needs onionxt +
-- a live tor daemon). oxCreateServiceFromSeed derives the same address
-- rsAnonOnion computes offline, so the returned service serves the
-- persona's own key. Returns the onionxt service handle (a positive
-- integer) or empty; the address arrives via onionxt's status callback
-- once tor publishes the descriptor, or synchronously from
-- oxServiceAddress on the returned handle once ready.
function rsAnonCreateService pMaster, pIndex, pVirtualPort, pLocalPort
   local tSeed, tHandle, tErr
   put rsAnonSeed(pMaster, pIndex) into tSeed
   if the number of bytes in tSeed is not 32 then
      rsSetError "rsAnonCreateService: could not derive a 32-byte anon" && \
            "subkey:" && rsLastError()
      return empty
   end if
   if pVirtualPort is not an integer or pVirtualPort < 1 or \
         pVirtualPort > 65535 then
      rsSetError "rsAnonCreateService: the virtual port must be 1..65535"
      return empty
   end if
   if pLocalPort is not an integer or pLocalPort < 1 or pLocalPort > 65535 then
      rsSetError "rsAnonCreateService: the local port must be 1..65535"
      return empty
   end if
   try
      oxCreateServiceFromSeed tSeed, pVirtualPort, pLocalPort
      put the result into tHandle
   catch tErr
      rsSetError "rsAnonCreateService: needs onionxt" && \
            "(oxCreateServiceFromSeed):" && tErr
      return empty
   end try
   if tHandle is not an integer then
      -- onionxt reports a capability/bind failure as an "OnionXT: ..." string
      rsSetError "rsAnonCreateService:" && tHandle
      return empty
   end if
   return tHandle
end rsAnonCreateService

-- The spec 8.2/8.3 onion SERVING seams: what the persona's onion-httpd
-- routes reply with, and how a POSTed sealed intro is accepted. All
-- three are pure (no I/O, no session, no stream), so the harness proves
-- them offline; the APP registers the oxh* routes and owns the streams.

-- The anon feed page (spec 8.2), as UTF-8 HTML bytes: a title plus
-- line-delimited entries, each HTML-escaped so a crafted entry cannot
-- inject markup into the persona's own page. Line breaks are normalized
-- (CRLF and CR become LF) BEFORE the split, so the page bytes do not
-- depend on which spelling the engine's `return` or a pasted text
-- carries; blank lines are skipped. The title shares the head's
-- display-name budget; the finished page caps at kRsAnonPageMax.
-- Deterministic bytes in, deterministic bytes out - the golden pins the
-- page, so the served feed is a wire format, not a template someone
-- restyles by accident (a look change bumps the golden).
function rsAnonFeedPage pTitle, pEntries
   local tTitleBytes, tEsc, tOut, tList, tLine, tSavedDelim
   put textEncode(pTitle, "UTF-8") into tTitleBytes
   if the number of bytes in tTitleBytes < 1 or \
         the number of bytes in tTitleBytes > kRsMaxDisplayName then
      rsSetError "rsAnonFeedPage: the title must be 1 to" && \
            kRsMaxDisplayName && "bytes of UTF-8"
      return empty
   end if
   put rsHtmlEscape(pTitle) into tEsc
   put "<!doctype html><html><head><meta charset='utf-8'><title>" & \
         tEsc & "</title></head><body><h1>" & tEsc & "</h1><ul>" into tOut
   put pEntries into tList
   replace numToChar(13) & numToChar(10) with numToChar(10) in tList
   replace numToChar(13) with numToChar(10) in tList
   -- the same save/restore discipline as rsMediaCreate's itemDelimiter,
   -- applied uniformly rather than only where it bit. Be honest about what
   -- this one is: LF IS the engine default, so this set leaks nothing
   -- observable today - it is defence in depth against a caller who set
   -- something else, not a second live bug fixed.
   put the lineDelimiter into tSavedDelim
   set the lineDelimiter to numToChar(10)
   repeat for each line tLine in tList
      if tLine is empty then
         next repeat
      end if
      put "<li>" & rsHtmlEscape(tLine) & "</li>" after tOut
   end repeat
   set the lineDelimiter to tSavedDelim
   put "</ul><p>Sealed DMs: GET /prekey (my signed RSK1 prekey record," && \
         "hex), then POST your sealed intro as hex to /dm.</p>" & \
         "</body></html>" after tOut
   put textEncode(tOut, "UTF-8") into tOut
   if the number of bytes in tOut > kRsAnonPageMax then
      rsSetError "rsAnonFeedPage: the page is over" && kRsAnonPageMax && \
            "bytes; trim the entries"
      return empty
   end if
   return tOut
end rsAnonFeedPage

-- The GET /prekey response body (spec 8.3): the persona's signed RSK1
-- prekey record as 264 lowercase hex chars of TEXT - hex because the
-- record is binary and a text body survives every HTTP client untouched.
-- The record is rsBuildPrekey of the subkey-200+n kx public, SIGNED by
-- the subkey-100+n ANON identity, so a follower who fetched this over
-- the persona's onion verifies it against the very key they dialed:
-- rsVerifyPrekey(decoded, anonHandle). Served over the onion ONLY, never
-- the DHT (the 9.3 guard).
function rsAnonPrekeyBody pMaster, pIndex
   local tSeed, tKeys, tRec
   put rsAnonDmSeed(pMaster, pIndex) into tSeed
   if tSeed is empty then
      rsSetError "rsAnonPrekeyBody: could not derive the persona's DM" && \
            "subkey:" && rsLastError()
      return empty
   end if
   put rsDmKeys(tSeed) into tKeys
   if tKeys is empty then return empty
   put rsBuildPrekey(tKeys["publicKeyHex"], rsAnonSeed(pMaster, pIndex)) \
         into tRec
   if tRec is empty then return empty
   return rsBinToHexString(tRec)
end rsAnonPrekeyBody

-- Accept a POST /dm body (spec 8.3): the sealed RSI1 intro as STRICT
-- lowercase hex, exactly kRsAnonDmBodyLen chars. REFUSE BEFORE DECODE:
-- the exact-length and per-byte-hex gates run first, so a hostile body
-- is turned away before any decode or crypto touches it (uppercase is
-- refused too - the canonical-form discipline). Then the EXISTING 8.3
-- machinery does verify-then-parse: rsDmOpenIntro opens the seal with
-- the persona's subkey-200+n kx pair and verifies sender signature and
-- recipient binding before a field is believed. One refusal covers
-- every failure mode - the route must not be an oracle for a prober.
-- Freshness stays the APP's policy, exactly as on the rp1 inbox path.
function rsAnonAcceptDm pBody, pMaster, pIndex
   local tLen, tI, tB, tSealed, tHandle, tErr
   put the number of bytes in pBody into tLen
   if tLen is not kRsAnonDmBodyLen then
      rsSetError "rsAnonAcceptDm: a sealed-intro body is exactly" && \
            kRsAnonDmBodyLen && "hex chars"
      return empty
   end if
   repeat with tI = 1 to tLen
      put byteToNum(byte tI of pBody) into tB
      if not ((tB >= 48 and tB <= 57) or (tB >= 97 and tB <= 102)) then
         rsSetError "rsAnonAcceptDm: the body is not strict lowercase hex"
         return empty
      end if
   end repeat
   try
      put sxHex2Bin(textEncode(pBody, "ASCII")) into tSealed
   catch tErr
      rsSetError "rsAnonAcceptDm: needs SodiumXT (sxHex2Bin):" && tErr
      return empty
   end try
   put rsAnonHandle(pMaster, pIndex) into tHandle
   if tHandle is empty then return empty
   return rsDmOpenIntro(tSealed, tHandle, rsAnonDmSeed(pMaster, pIndex))
end rsAnonAcceptDm

-- Escape a value for HTML text context (the oxhHtmlEscape algorithm,
-- mirrored in the oracle): `&` first, then the rest.
private function rsHtmlEscape pText
   local tOut
   put pText into tOut
   replace "&" with "&amp;" in tOut
   replace "<" with "&lt;" in tOut
   replace ">" with "&gt;" in tOut
   replace quote with "&quot;" in tOut
   return tOut
end rsHtmlEscape

-- BTXO framing (Model C, shared with the quickshare onion transfer): the
-- header, then u32-length-prefixed DATA frames, then a zero-length
-- terminator, all over one Tor stream. The library builds and parses the
-- frames; the app owns the oxWrite/oxStreamData I/O.
function rsBtxoHeader pName, pTotalSize, pFlags
   local tName, tOut
   put textEncode(pName, "UTF-8") into tName
   if the number of bytes in tName < 1 or the number of bytes in tName > 65535 \
         then
      rsSetError "rsBtxoHeader: the name must be 1..65535 UTF-8 bytes"
      return empty
   end if
   if pTotalSize is not an integer or pTotalSize < 0 then
      rsSetError "rsBtxoHeader: the total size must be a non-negative integer"
      return empty
   end if
   if pFlags is not an integer or pFlags < 0 or pFlags > 255 then
      rsSetError "rsBtxoHeader: flags is a single byte (0..255)"
      return empty
   end if
   put textEncode(kRsBtxoMagic, "ASCII") into tOut
   put numToByte(kRsBtxoVer) after tOut
   put numToByte(pFlags) after tOut
   put rsBEu16(the number of bytes in tName) after tOut
   put tName after tOut
   put rsBEu64(pTotalSize) after tOut
   return tOut
end rsBtxoHeader

function rsBtxoParseHeader pBytes
   local tLen, tNameLen, tOut
   put the number of bytes in pBytes into tLen
   if tLen < 8 then
      rsSetError "rsBtxoParseHeader: truncated header"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsBtxoMagic then
      rsSetError "rsBtxoParseHeader: bad magic, not a BTXO stream"
      return empty
   end if
   if byteToNum(byte 5 of pBytes) is not kRsBtxoVer then
      rsSetError "rsBtxoParseHeader: unsupported BTXO version"
      return empty
   end if
   put byteToNum(byte 6 of pBytes) into tOut["flags"]
   put rsReadBEu16(byte 7 to 8 of pBytes) into tNameLen
   if tLen is not 8 + tNameLen + 8 then
      rsSetError "rsBtxoParseHeader: length does not match its name field"
      return empty
   end if
   -- attacker-controlled file name; OXT's textDecode is lossy not throwing,
   -- so validate by round-trip and refuse a malformed name - see
   -- rsBytesAreUtf8 (the never-throw contract, rule 5)
   if not rsBytesAreUtf8(byte 9 to (8 + tNameLen) of pBytes) then
      rsSetError "rsBtxoParseHeader: the file name is not valid UTF-8"
      return empty
   end if
   put textDecode(byte 9 to (8 + tNameLen) of pBytes, "UTF-8") into \
         tOut["name"]
   put rsReadBEu64(byte (9 + tNameLen) to tLen of pBytes) into tOut["total"]
   return tOut
end rsBtxoParseHeader

-- One content frame: a u32 big-endian length then the bytes. Non-empty
-- (the zero-length frame is the terminator, built separately).
function rsBtxoDataFrame pPayload
   local tOut
   if the number of bytes in pPayload < 1 then
      rsSetError "rsBtxoDataFrame: a data frame carries at least one byte" && \
            "(use rsBtxoTerminator to end the stream)"
      return empty
   end if
   put binaryEncode("N", the number of bytes in pPayload) into tOut
   put pPayload after tOut
   return tOut
end rsBtxoDataFrame

function rsBtxoTerminator
   return binaryEncode("N", 0)
end rsBtxoTerminator

-- THE RECEIVE PATH (backlog A3, 2026-08-23): the length-prefix stream
-- state machine the four builders above never had. Without it a stream
-- reader cannot find a frame boundary - rsBtxoParseHeader refuses unless
-- handed EXACTLY the header's bytes, and nothing in this library owns a
-- socket. So the machine is PURE and single-step, and the APP owns the
-- buffer: accumulate incoming bytes, call this with the buffer and the
-- phase ("header" until the header has been consumed, "body" after),
-- act on the status, delete the consumed bytes from the front, repeat
-- until "need". One call extracts at most ONE thing - the header, one
-- data frame, or the terminator - which is what makes reassembly
-- provable at every byte boundary offline (the harness splits a stream
-- at every offset and requires identical results).
--
-- Returns an array, or empty only on a CALLER bug (a phase this machine
-- does not have):
--   status  "need"    - not enough bytes yet; used is 0, wait for more
--           "header"  - a strict header was consumed; name/total/flags
--                       ride alongside, used names its byte count
--           "frame"   - one data frame was consumed; payload alongside
--           "end"     - the zero-length terminator; the stream is over
--           "refused" - hostile or malformed; used is 0 and
--                       rsLastError() says why. ABORT the stream: a
--                       refused stream has no next boundary to find.
--   used    bytes consumed from the FRONT of the buffer (0 unless
--           something was extracted) - `delete byte 1 to used` is the
--           caller's compaction, nocloud's drain-and-compact discipline.
--
-- The caps are nocloud's, ported not re-derived (see kRsBtxoMaxName and
-- friends above): a nameLen over 1024 refuses BEFORE the name is
-- awaited, a total over 8 GiB refuses the transfer, and a frame length
-- over 65536 is hostile - fail closed, never buffer toward a liar's
-- number.
function rsBtxoStreamStep pBuffer, pPhase
   local tLen, tNameLen, tHeaderLen, tParsed, tFrameLen, tOut
   put the number of bytes in pBuffer into tLen
   put 0 into tOut["used"]
   if pPhase is "header" then
      if tLen < 8 then
         put "need" into tOut["status"]
         return tOut
      end if
      if textDecode(byte 1 to 4 of pBuffer, "ASCII") is not kRsBtxoMagic then
         rsSetError "rsBtxoStreamStep: bad magic, not a BTXO stream"
         put "refused" into tOut["status"]
         return tOut
      end if
      if byteToNum(byte 5 of pBuffer) is not kRsBtxoVer then
         rsSetError "rsBtxoStreamStep: unsupported BTXO version"
         put "refused" into tOut["status"]
         return tOut
      end if
      put rsReadBEu16(byte 7 to 8 of pBuffer) into tNameLen
      if tNameLen > kRsBtxoMaxName then
         rsSetError "rsBtxoStreamStep: header name length" && tNameLen && \
               "is over the" && kRsBtxoMaxName && "cap (refused before" && \
               "buffering toward it)"
         put "refused" into tOut["status"]
         return tOut
      end if
      put 8 + tNameLen + 8 into tHeaderLen
      if tLen < tHeaderLen then
         put "need" into tOut["status"]
         return tOut
      end if
      -- the strict whole-header parse (magic, version, exact length,
      -- the UTF-8 round trip on the name) is the EXISTING parser's:
      -- reuse it on exactly the header's bytes, never re-derive it
      put rsBtxoParseHeader(byte 1 to tHeaderLen of pBuffer) into tParsed
      if tParsed is empty then
         put "refused" into tOut["status"]
         return tOut
      end if
      if tParsed["total"] > kRsBtxoMaxTotal then
         rsSetError "rsBtxoStreamStep: total size" && tParsed["total"] && \
               "is over the" && kRsBtxoMaxTotal && "transfer ceiling"
         put "refused" into tOut["status"]
         return tOut
      end if
      put "header" into tOut["status"]
      put tHeaderLen into tOut["used"]
      put tParsed["name"] into tOut["name"]
      put tParsed["total"] into tOut["total"]
      put tParsed["flags"] into tOut["flags"]
      return tOut
   end if
   if pPhase is "body" then
      if tLen < 4 then
         put "need" into tOut["status"]
         return tOut
      end if
      put rsReadBEu32(byte 1 to 4 of pBuffer) into tFrameLen
      if tFrameLen is 0 then
         put "end" into tOut["status"]
         put 4 into tOut["used"]
         return tOut
      end if
      if tFrameLen > kRsBtxoChunk then
         rsSetError "rsBtxoStreamStep: frame length" && tFrameLen && \
               "is over the" && kRsBtxoChunk && "cap - hostile; abort" && \
               "the stream"
         put "refused" into tOut["status"]
         return tOut
      end if
      if tLen < 4 + tFrameLen then
         put "need" into tOut["status"]
         return tOut
      end if
      put "frame" into tOut["status"]
      put 4 + tFrameLen into tOut["used"]
      put byte 5 to (4 + tFrameLen) of pBuffer into tOut["payload"]
      return tOut
   end if
   rsSetError "rsBtxoStreamStep: pPhase must be" && quote & "header" & \
         quote && "or" && quote & "body" & quote
   return empty
end rsBtxoStreamStep

--------------------------------------------------------------------------
-- phase 8 - the Nostr rail (spec section 8A)
--
-- WHAT THIS RAIL IS FOR. Every other rail here is sovereign: the DHT feed,
-- rp1 DMs, the LAN mesh and the onion persona all work with nobody's server
-- in the middle, and that is the point of the app. What they do not have is
-- REACH - a riptide handle is meaningless to anyone who does not run
-- riptide. Nostr is the opposite trade: somebody else's relays, an IP they
-- can see, and an audience already there. So this rail is deliberately a
-- BRIDGE and never a dependency. Nothing here is on the path of any other
-- rail; with no CoinXT, no relay, or every relay down, riptide is exactly
-- the app it was before.
--
-- THREE THINGS THIS LAYER OWNS, and nothing else:
--   1. The KEY. Subkey 4 through a bounded validity ladder, so one unlock
--      still reconstructs the whole keyring (the spec's identity-first
--      decision) and no separate Nostr key has to be stored or backed up.
--   2. The BRIDGE. An RSN1 record signed by BOTH keys, so "this handle and
--      this npub are one person" is a two-sided statement rather than a
--      claim either key-holder could make about a stranger's key.
--   3. The MEDIA CONVENTION. riptide attachments as `r`-tag magnet URIs, in
--      both directions, so a note keeps its media across the boundary.
--
-- Everything else - canonical serialization, ids, BIP-340, NIP-19, filters,
-- the relay socket machine - is NostrXT's, called through nx*/nxr* and never
-- re-implemented (the family's compose-never-reinvent law). Every one of
-- those calls sits in a try, so a missing NostrXT is a clean capability
-- refusal naming what it needs, exactly like a missing torrentxt is.
--
-- THE SECRET KEY IS NOT HANDED OUT CASUALLY. rsNostrKeys returns only the
-- public halves; the secret has its own handler with "Export" in its name,
-- so every call site that touches it reads as the deliberate act it is
-- (a backup, or an import into another Nostr client). rsNostrSignEvent
-- derives, signs and drops it, so ordinary publishing never holds it.
--
-- DELIBERATELY NOT BUILT: Nostr DMs. NIP-04 is deprecated and needs AES,
-- which exists nowhere in this suite; NIP-17 gift wrap needs an ephemeral
-- key layer and a metadata analysis this pass has not done. riptide already
-- has a private DM rail that answers to nobody, and a half-built encrypted
-- rail beside it would be worse than none. Recorded as a scope cut, not a
-- gap to be quietly filled later.
--------------------------------------------------------------------------

-- THE SECP256K1 VALIDITY LADDER, and why it is a function of a CANDIDATE.
--
-- A KDF output is 32 uniform bytes; a secp256k1 secret key must be in
-- 1..n-1. The two are not the same set, and the gap is about 2^-128 wide -
-- which is exactly what makes the design decision easy to get wrong. No
-- real master seed will ever land in it, so whatever rule goes here will
-- never run in anger and can never be observed. That is an argument for
-- making it SIMPLE and TESTABLE, not for hand-waving it.
--
-- Refusing outright would leave a user with an underivable identity and
-- nothing they could do about it. Re-deriving "with the next subkey id"
-- would silently walk into a registry row belonging to another rail. So:
-- re-hash the candidate with SHA-256 and try again, at most
-- kRsNostrLadderMax times, then refuse. SHA-256 adds no dependency (the
-- rail needs CoinXT for BIP-340 anyway), the rung count is bounded so it
-- can never spin, and the refusal is a refusal and never a weaker key.
--
-- Taking a CANDIDATE rather than a master is what makes it provable: no
-- master reaches rung 2, but the all-zeros candidate and the group order n
-- both do, and the harness pins both.
function rsNostrSeckeyFrom pCandidateHex
   local tCandidate, tBin, tOk, tRung, tErr
   put toLower(pCandidateHex) into tCandidate
   if not rsIsHexOfLen(tCandidate, 64) then
      rsSetError "rsNostrSeckeyFrom: the candidate must be 64 hex chars"
      return empty
   end if
   put rsHexToBin(tCandidate) into tBin
   if tBin is empty then return empty
   repeat with tRung = 1 to kRsNostrLadderMax
      try
         put cxSeckeyIsValid(tBin) into tOk
      catch tErr
         rsSetError "rsNostrSeckeyFrom needs CoinXT (cxSeckeyIsValid):" && tErr
         return empty
      end try
      if tOk is true then
         return rsBinToHexString(tBin)
      end if
      try
         put cxSha256(tBin) into tBin
      catch tErr
         rsSetError "rsNostrSeckeyFrom needs CoinXT (cxSha256):" && tErr
         return empty
      end try
   end repeat
   rsSetError "rsNostrSeckeyFrom: no valid secp256k1 scalar within" && \
         kRsNostrLadderMax && "rungs"
   return empty
end rsNostrSeckeyFrom

-- The 64-hex Nostr secret key for a master seed. PRIVATE on purpose: the
-- two public doors are rsNostrKeys (public halves only) and
-- rsNostrExportSeckey (named so the call site reads as a deliberate act).
private function rsNostrSeckeyHex pMaster
   local tSub, tHex
   put rsSubkey(pMaster, kRsSubkeyNostr) into tSub
   if tSub is empty then return empty
   put rsBinToHexString(tSub) into tHex
   if tHex is empty then return empty
   return rsNostrSeckeyFrom(tHex)
end rsNostrSeckeyHex

-- The PUBLIC halves of the Nostr identity: the 64-hex BIP-340 x-only public
-- key and its npub. No secret in the result, so an app can paint this
-- anywhere without deciding whether the array is safe to log.
function rsNostrKeys pMaster
   local tSecHex, tPub, tNpub, tOut, tErr
   put rsNostrSeckeyHex(pMaster) into tSecHex
   if tSecHex is empty then return empty
   try
      put nxKeyPublic(tSecHex) into tPub
   catch tErr
      rsSetError "rsNostrKeys needs NostrXT (nxKeyPublic):" && tErr
      return empty
   end try
   if not rsIsHexOfLen(tPub, 64) then
      rsSetError "rsNostrKeys: nxKeyPublic did not return a 64-hex key"
      return empty
   end if
   try
      put nxNpubEncode(tPub) into tNpub
   catch tErr
      rsSetError "rsNostrKeys needs NostrXT (nxNpubEncode):" && tErr
      return empty
   end try
   if tNpub is empty then
      rsSetError "rsNostrKeys: nxNpubEncode refused the public key"
      return empty
   end if
   put tPub into tOut["pubkey"]
   put tNpub into tOut["npub"]
   return tOut
end rsNostrKeys

-- The secret key as 64 hex, for a BACKUP or an import into another Nostr
-- client. Named for what it is: the one handler here that hands a caller
-- key material, so a reader of a call site does not have to know the KDF
-- tree to notice. The honest limit is the family's standing one - OXT
-- script variables are not locked memory - and it belongs to whoever calls
-- this, not to this library.
function rsNostrExportSeckey pMaster
   return rsNostrSeckeyHex(pMaster)
end rsNostrExportSeckey

-- Sign an event under the Nostr identity, deriving the key inside and
-- dropping it on the way out. This is the ONLY signing seam, so ordinary
-- publishing never has the secret in a caller's variable.
--
-- pAuxHex empty draws fresh BIP-340 auxiliary randomness (the recommended
-- default; BIP-340 signatures are not unique and every one of them
-- verifies). A 64-hex pAuxHex makes the signature a pure function of key,
-- message and aux - which is what the golden vectors pin, and what the
-- fixed LAN nonce is to the admission records.
function rsNostrSignEvent pEvent, pMaster, pAuxHex
   local tSecHex, tSigned, tErr
   put rsNostrSeckeyHex(pMaster) into tSecHex
   if tSecHex is empty then return empty
   try
      put nxEventSign(pEvent, tSecHex, pAuxHex) into tSigned
   catch tErr
      rsSetError "rsNostrSignEvent needs NostrXT (nxEventSign):" && tErr
      return empty
   end try
   if tSigned is empty then
      rsSetError "rsNostrSignEvent: nxEventSign refused the event"
      return empty
   end if
   return tSigned
end rsNostrSignEvent

-- An UNSIGNED kind-1 note carrying riptide's media attachments as `r`-tag
-- magnet URIs. Pure: no key, no I/O, so the harness proves the tag shape
-- offline. rsNostrSignEvent completes it.
--
-- The media list is the same comma list rsParsePost returns, and each entry
-- is validated as a non-zero 40-hex info-hash before it becomes a tag - a
-- note must never advertise content nobody can fetch (the rsPublishImmutable
-- discipline, applied to a pointer that leaves the app).
function rsNostrNoteEvent pTimestamp, pText, pMediaList
   local tTags, tCount, tI, tHash, tSaved, tEvent, tErr
   if pTimestamp is not an integer or pTimestamp < 0 then
      rsSetError "rsNostrNoteEvent: the timestamp must be a non-negative" && \
            "integer"
      return empty
   end if
   if pTimestamp >= 9007199254740992 then
      rsSetError "rsNostrNoteEvent: the timestamp is out of range"
      return empty
   end if
   if pText is empty then
      rsSetError "rsNostrNoteEvent: an empty note is refused"
      return empty
   end if
   put 0 into tCount
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   if pMediaList is not empty then
      repeat with tI = 1 to the number of items in pMediaList
         put rsNormalizeTarget(item tI of pMediaList) into tHash
         if tHash is empty or tHash is kRsZeroTarget then
            set the itemDelimiter to tSaved
            rsSetError "rsNostrNoteEvent: media item" && tI && \
                  "is not a 40-hex non-zero info-hash"
            return empty
         end if
         add 1 to tCount
         put "r" into tTags[tCount][1]
         put kRsMagnetPrefix & tHash into tTags[tCount][2]
      end repeat
   end if
   set the itemDelimiter to tSaved
   if tCount > kRsMaxMedia then
      rsSetError "rsNostrNoteEvent: at most" && kRsMaxMedia && \
            "media attachments"
      return empty
   end if
   try
      put nxEventBuild(1, pText, tTags, pTimestamp) into tEvent
   catch tErr
      rsSetError "rsNostrNoteEvent needs NostrXT (nxEventBuild):" && tErr
      return empty
   end try
   if tEvent is empty then
      rsSetError "rsNostrNoteEvent: nxEventBuild refused the note"
      return empty
   end if
   return tEvent
end rsNostrNoteEvent

-- The RECEIVE half of the media convention: the 40-hex info-hashes an
-- inbound event advertises, as a comma list ready for rsMediaFetch.
--
-- Strict on the way in, exactly as on the way out: an `r` tag that is not a
-- magnet URI is somebody else's link and is skipped silently, and one that
-- looks like a magnet but does not carry a lowercase non-zero 40-hex hash
-- is skipped too rather than reaching the torrent layer. A tag is untrusted
-- text; this returns only what it could fully validate.
function rsNostrMediaTags pEvent
   local tValues, tSavedLine, tSavedItem, tI, tLine, tTail, tHash, tOut, tErr
   local tPrefixLen
   try
      put nxTagValues(pEvent, "r") into tValues
   catch tErr
      rsSetError "rsNostrMediaTags needs NostrXT (nxTagValues):" && tErr
      return empty
   end try
   if tValues is empty then return empty
   put the number of chars in kRsMagnetPrefix into tPrefixLen
   put the lineDelimiter into tSavedLine
   put the itemDelimiter into tSavedItem
   set the lineDelimiter to return
   set the itemDelimiter to comma
   repeat with tI = 1 to the number of lines in tValues
      put line tI of tValues into tLine
      -- POSITIVE indices on purpose. `char -40 to -1` reads naturally and is
      -- a form the headless interpreter mis-models, so it could not be
      -- checked offline; the length is already pinned one line above, which
      -- makes the explicit span both exact and verifiable.
      if the number of chars in tLine is tPrefixLen + 40 then
         if char 1 to tPrefixLen of tLine is kRsMagnetPrefix then
            put char (tPrefixLen + 1) to (tPrefixLen + 40) of tLine into tTail
            put rsNormalizeTarget(tTail) into tHash
            if tHash is not empty and tHash is not kRsZeroTarget then
               if tOut is empty then
                  put tHash into tOut
               else
                  put comma & tHash after tOut
               end if
            end if
         end if
      end if
   end repeat
   set the lineDelimiter to tSavedLine
   set the itemDelimiter to tSavedItem
   return tOut
end rsNostrMediaTags

-- THE RSN1 IDENTITY BRIDGE - the record that makes "this handle and this
-- npub are one person" checkable rather than asserted.
--
-- A riptide handle is ed25519 and an npub is secp256k1. Neither key can
-- sign for the other, so a one-signature claim is a claim ANY holder of
-- that one key can make about somebody else's other key - which is not a
-- linkage, it is an accusation. Both signatures over one preimage make it a
-- two-sided statement, and either half alone is worthless.
--
-- Layout, 276 bytes exactly:
--   magic(4) handle(64 ascii hex) nostrPub(64 ascii hex) seq(u64 BE)
--   timestamp(u64 BE) edSig(64) schnorrSig(64)
-- The signed span is the first 148 bytes, prefixed by kRsNostrDomain: the
-- magic is INSIDE it, so a signature minted for this record can never be
-- read as a signature for another kind, and the domain keeps it out of the
-- LAN rail's namespace (the "riptide-lan-s" discipline).
--
-- The ed25519 half signs the preimage bytes; the BIP-340 half signs SHA-256
-- OF the preimage, because CoinXT's cxSchnorrSign takes a 32-byte digest -
-- deliberately restricted there so a caller cannot sign a blob it has not
-- decoded.
function rsBuildBridge pSeq, pTimestamp, pMaster, pAuxHex
   local tIdSeed, tIdKeys, tNostr, tBody, tPre, tEdSig, tDigest
   local tSecHex, tSchSig, tAux, tErr
   if pSeq is not an integer or pSeq < 0 or pSeq >= 9007199254740992 then
      rsSetError "rsBuildBridge: the seq must be a non-negative integer"
      return empty
   end if
   if pTimestamp is not an integer or pTimestamp < 0 or \
         pTimestamp >= 9007199254740992 then
      rsSetError "rsBuildBridge: the timestamp must be a non-negative integer"
      return empty
   end if
   if pAuxHex is not empty and not rsIsHexOfLen(toLower(pAuxHex), 64) then
      rsSetError "rsBuildBridge: aux randomness must be empty or 64 hex chars"
      return empty
   end if
   put rsIdentitySeed(pMaster) into tIdSeed
   if tIdSeed is empty then return empty
   put rsIdentityKeys(tIdSeed) into tIdKeys
   if tIdKeys is empty then return empty
   put rsNostrKeys(pMaster) into tNostr
   if tNostr is empty then return empty
   put rsNostrSeckeyHex(pMaster) into tSecHex
   if tSecHex is empty then return empty
   put textEncode(kRsNostrMagic, "ASCII") into tBody
   put textEncode(tIdKeys["handle"], "ASCII") after tBody
   put textEncode(tNostr["pubkey"], "ASCII") after tBody
   put rsBEu64(pSeq) after tBody
   put rsBEu64(pTimestamp) after tBody
   if the number of bytes in tBody is not kRsNostrBridgeBody then
      rsSetError "rsBuildBridge: assembled body is not" && \
            kRsNostrBridgeBody && "bytes"
      return empty
   end if
   put textEncode(kRsNostrDomain, "ASCII") & tBody into tPre
   try
      put sxSignDetached(tPre, tIdKeys["secretKey"]) into tEdSig
   catch tErr
      rsSetError "rsBuildBridge needs SodiumXT (sxSignDetached):" && tErr
      return empty
   end try
   if pAuxHex is empty then
      put empty into tAux
   else
      put rsHexToBin(toLower(pAuxHex)) into tAux
      if tAux is empty then return empty
   end if
   try
      put cxSha256(tPre) into tDigest
      put cxSchnorrSign(rsHexToBin(tSecHex), tDigest, tAux) into tSchSig
   catch tErr
      rsSetError "rsBuildBridge needs CoinXT (cxSha256/cxSchnorrSign):" && tErr
      return empty
   end try
   if the number of bytes in tEdSig is not 64 or \
         the number of bytes in tSchSig is not 64 then
      rsSetError "rsBuildBridge: a signature is not 64 bytes"
      return empty
   end if
   return tBody & tEdSig & tSchSig
end rsBuildBridge

-- Strict parse: exact length, exact magic, both key fields canonical
-- lowercase hex. STRUCTURE ONLY - nothing here is believed until
-- rsVerifyBridge has checked both signatures.
function rsParseBridge pBytes
   local tOut, tHandle, tPub
   if the number of bytes in pBytes is not kRsNostrBridgeLen then
      rsSetError "rsParseBridge: an RSN1 record is exactly" && \
            kRsNostrBridgeLen && "bytes"
      return empty
   end if
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not kRsNostrMagic then
      rsSetError "rsParseBridge: bad magic, not an RSN1 record"
      return empty
   end if
   put textDecode(byte 5 to 68 of pBytes, "ASCII") into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsParseBridge: malformed riptide handle"
      return empty
   end if
   put textDecode(byte 69 to 132 of pBytes, "ASCII") into tPub
   if not rsIsHexOfLen(tPub, 64) then
      rsSetError "rsParseBridge: malformed nostr public key"
      return empty
   end if
   put tHandle into tOut["handle"]
   put tPub into tOut["nostrPub"]
   put rsReadBEu64(byte 133 to 140 of pBytes) into tOut["seq"]
   put rsReadBEu64(byte 141 to 148 of pBytes) into tOut["timestamp"]
   return tOut
end rsParseBridge

-- Verify BOTH signatures, then (optionally) that the record names the keys
-- the caller expected. Returns rsParseBridge's array or empty.
--
-- An empty expectation means "do not check that side", which is what a
-- reader who found the record BY one of the keys wants: pulling it from the
-- DHT under a handle already fixes the handle, and pulling it out of a
-- Nostr event already fixes the npub. Passing both is the strictest form
-- and is what an app comparing two independently-obtained copies uses.
function rsVerifyBridge pBytes, pExpectHandleHex, pExpectNostrPubHex
   local tRec, tPre, tOk, tPub, tDigest, tErr, tWantHandle, tWantPub
   put rsParseBridge(pBytes) into tRec
   if tRec is empty then return empty
   put toLower(pExpectHandleHex) into tWantHandle
   if tWantHandle is not empty then
      if not rsIsHexOfLen(tWantHandle, 64) then
         rsSetError "rsVerifyBridge: the expected handle must be 64 hex chars"
         return empty
      end if
      if tRec["handle"] is not tWantHandle then
         rsSetError "rsVerifyBridge: the record names a different handle"
         return empty
      end if
   end if
   put toLower(pExpectNostrPubHex) into tWantPub
   if tWantPub is not empty then
      if not rsIsHexOfLen(tWantPub, 64) then
         rsSetError "rsVerifyBridge: the expected nostr key must be 64 hex" && \
               "chars"
         return empty
      end if
      if tRec["nostrPub"] is not tWantPub then
         rsSetError "rsVerifyBridge: the record names a different nostr key"
         return empty
      end if
   end if
   put textEncode(kRsNostrDomain, "ASCII") & \
         (byte 1 to kRsNostrBridgeBody of pBytes) into tPre
   put rsHexToBin(tRec["handle"]) into tPub
   if tPub is empty then return empty
   try
      put sxSignVerifyDetached(byte 149 to 212 of pBytes, tPre, tPub) into tOk
   catch tErr
      rsSetError "rsVerifyBridge needs SodiumXT (sxSignVerifyDetached):" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsVerifyBridge: the riptide handle signature does not verify"
      return empty
   end if
   try
      put cxSha256(tPre) into tDigest
      put cxSchnorrVerify(rsHexToBin(tRec["nostrPub"]), tDigest, \
            byte 213 to 276 of pBytes) into tOk
   catch tErr
      rsSetError "rsVerifyBridge needs CoinXT (cxSha256/cxSchnorrVerify):" && \
            tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsVerifyBridge: the nostr signature does not verify"
      return empty
   end if
   return tRec
end rsVerifyBridge

-- The bridge as a NIP-78 parameterized-replaceable event (kind 30078,
-- d-tag "riptide.bridge"), content = the record as lowercase hex.
--
-- Hex rather than base64 for the reason the anon /dm route already gives:
-- it survives every client untouched and gives a reader an exact spelling
-- to refuse against. Signed by the SAME Nostr key the record names, which
-- is what rsNostrBridgeFromEvent checks - an event carrying somebody else's
-- bridge is refused rather than relayed.
function rsNostrBridgeEvent pBridgeBytes, pMaster, pTimestamp, pAuxHex
   local tRec, tHex, tTags, tEvent, tErr
   put rsParseBridge(pBridgeBytes) into tRec
   if tRec is empty then return empty
   if pTimestamp is not an integer or pTimestamp < 0 or \
         pTimestamp >= 9007199254740992 then
      rsSetError "rsNostrBridgeEvent: the timestamp must be a non-negative" && \
            "integer"
      return empty
   end if
   put rsBinToHexString(pBridgeBytes) into tHex
   if tHex is empty then return empty
   put "d" into tTags[1][1]
   put kRsNostrBridgeDTag into tTags[1][2]
   try
      put nxEventBuild(kRsNostrBridgeKind, tHex, tTags, pTimestamp) into tEvent
   catch tErr
      rsSetError "rsNostrBridgeEvent needs NostrXT (nxEventBuild):" && tErr
      return empty
   end try
   if tEvent is empty then
      rsSetError "rsNostrBridgeEvent: nxEventBuild refused the event"
      return empty
   end if
   return rsNostrSignEvent(tEvent, pMaster, pAuxHex)
end rsNostrBridgeEvent

-- The inbound half: a wire-format kind-30078 event JSON in, a VERIFIED
-- bridge out. Four gates, in order, and the order is the point:
--   1. structure (nxEventFromJson - untrusted text becomes an event array)
--   2. the event's own BIP-340 signature (nxEventVerify)
--   3. the kind and the d-tag - this is a riptide bridge, not some other
--      app's NIP-78 blob that happens to be hex
--   4. both bridge signatures, with the event's OWN author pinned as the
--      expected nostr key
--
-- Gate 4 is what stops the obvious attack: anyone can copy somebody else's
-- bridge record into their own signed event. Requiring the record's
-- nostrPub to BE the event's author makes that copy verify as what it is -
-- the original author's bridge - and never as the republisher's.
function rsNostrBridgeFromEvent pEventJson
   local tEvent, tOk, tKind, tDTag, tHex, tBytes, tErr
   try
      put nxEventFromJson(pEventJson) into tEvent
   catch tErr
      rsSetError "rsNostrBridgeFromEvent needs NostrXT (nxEventFromJson):" && \
            tErr
      return empty
   end try
   if tEvent is empty then
      rsSetError "rsNostrBridgeFromEvent: the event JSON did not parse"
      return empty
   end if
   try
      put nxEventVerify(tEvent) into tOk
   catch tErr
      rsSetError "rsNostrBridgeFromEvent needs NostrXT (nxEventVerify):" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsNostrBridgeFromEvent: the event signature does not verify"
      return empty
   end if
   put tEvent["kind"] into tKind
   if tKind is not kRsNostrBridgeKind then
      rsSetError "rsNostrBridgeFromEvent: not a kind" && kRsNostrBridgeKind && \
            "event"
      return empty
   end if
   try
      put nxTagFirst(tEvent, "d") into tDTag
   catch tErr
      rsSetError "rsNostrBridgeFromEvent needs NostrXT (nxTagFirst):" && tErr
      return empty
   end try
   -- byte-exact, because `is` folds case and a d-tag is a wire identifier
   if not rsBytesEqual(tDTag, kRsNostrBridgeDTag) then
      rsSetError "rsNostrBridgeFromEvent: the d tag is not" && \
            kRsNostrBridgeDTag
      return empty
   end if
   put toLower(tEvent["content"]) into tHex
   if not rsIsHexOfLen(tHex, kRsNostrBridgeLen * 2) then
      rsSetError "rsNostrBridgeFromEvent: the content is not" && \
            (kRsNostrBridgeLen * 2) && "hex chars"
      return empty
   end if
   put rsHexToBin(tHex) into tBytes
   if tBytes is empty then return empty
   return rsVerifyBridge(tBytes, empty, tEvent["pubkey"])
end rsNostrBridgeFromEvent

-- Publish the bridge to the DHT under the identity key, at its own salt.
-- The head format is untouched: a new rail gets a new salt, never a new
-- field in a record whose magic would then have to be bumped (rule 3). The
-- BEP44 seq is the bridge's own embedded seq, the rsPublishHead discipline
-- of one counter with one source of truth.
function rsPublishBridge pSession, pBridgeBytes, pIdentitySeed
   local tRec, tKeys, tValue, tBuf, tSig, tSigHex, tCode, tWhy, tErr
   -- EVERY OTHER INPUT IS VALIDATED BEFORE THE SESSION IS TOUCHED - the
   -- phase-2 decision this library records and then has to keep: it is
   -- what lets these refusal paths run, and be tested, on a machine with
   -- no torrentxt installed. The seed/handle check in particular has to
   -- sit above the session check or it can only ever be reached on a
   -- machine that has a live session, which is exactly where a harness
   -- assertion quietly starts passing for the wrong reason.
   put rsParseBridge(pBridgeBytes) into tRec
   if tRec is empty then
      rsSetError "rsPublishBridge: not a valid RSN1 bridge:" && rsLastError()
      return false
   end if
   put rsIdentityKeys(pIdentitySeed) into tKeys
   if tKeys is empty then return false
   -- A bridge names its handle INSIDE the signed span, so publishing one
   -- under a different key would put a record on the DHT that verifies as
   -- somebody else's linkage at a target nobody looks for. Refuse loudly.
   if tKeys["handle"] is not tRec["handle"] then
      rsSetError "rsPublishBridge: the signing seed is not the handle the" && \
            "bridge names"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsPublishBridge: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   put rsBencodeBytes(pBridgeBytes) into tValue
   put rsBep44SignBuf(kRsNostrSalt, tRec["seq"], tValue) into tBuf
   if tBuf is empty then return false
   try
      put sxSignDetached(tBuf, tKeys["secretKey"]) into tSig
   catch tErr
      rsSetError "rsPublishBridge:" && tErr
      return false
   end try
   put rsBinToHexString(tSig) into tSigHex
   if tSigHex is empty then return false
   try
      btDhtPutSigned pSession, tKeys["handle"], kRsNostrSalt, \
            tRec["seq"], tValue, tSigHex
      put the result into tCode
   catch tErr
      rsSetError "rsPublishBridge: needs torrentxt (btDhtPutSigned):" && tErr
      return false
   end try
   if tCode is not 0 then
      try
         put btLastError() into tWhy
      catch tErr
         put empty into tWhy
      end try
      rsSetError "rsPublishBridge: btDhtPutSigned refused (" & tCode & ")" && \
            tWhy
      return false
   end if
   return true
end rsPublishBridge

-- Ask the DHT for a handle's bridge. Asynchronous, exactly like
-- rsRequestHead: the value arrives as a dhtMutableItem event for
-- rsIngestBridge.
function rsRequestBridge pSession, pHandleHex
   local tHandle, tCode, tErr
   put toLower(pHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsRequestBridge: the handle must be 64 hex chars"
      return false
   end if
   if not rsValidSession(pSession) then
      rsSetError "rsRequestBridge: pSession is not a live torrent session" && \
            "handle"
      return false
   end if
   try
      btDhtGetMutable pSession, tHandle, kRsNostrSalt
      put the result into tCode
   catch tErr
      rsSetError "rsRequestBridge: needs torrentxt (btDhtGetMutable):" && tErr
      return false
   end try
   if tCode is not 0 then
      rsSetError "rsRequestBridge: btDhtGetMutable refused (" & tCode & ")"
      return false
   end if
   return true
end rsRequestBridge

-- Verify a drained dhtMutableItem EVENT as a handle's bridge. The same
-- three-layer discipline rsIngestHead uses - the event is for this handle
-- and this salt, the BEP44 signature re-verifies in SodiumXT, and the
-- embedded seq agrees with the event's - and then, because this record
-- carries a second signature libtorrent knows nothing about, the FULL
-- rsVerifyBridge on top. Returns the bridge array, or empty.
function rsIngestBridge pEvent, pExpectedHandleHex
   local tHandle, tEventKey, tSeq, tRec, tSigHex, tSig, tBuf, tOk, tErr
   put toLower(pExpectedHandleHex) into tHandle
   if not rsIsHexOfLen(tHandle, 64) then
      rsSetError "rsIngestBridge: the expected handle must be 64 hex chars"
      return empty
   end if
   put toLower(pEvent["publicKey"]) into tEventKey
   if not rsIsHexOfLen(tEventKey, 64) or tEventKey is not tHandle then
      rsSetError "rsIngestBridge: the event is not for this handle"
      return empty
   end if
   -- `is` folds case here too; the rebuilt-canonical-buffer signature below
   -- is what actually backstops a case-mangled salt (the rsIngestHead note)
   if pEvent["salt"] is not kRsNostrSalt then
      rsSetError "rsIngestBridge: the event is not a riptide-nostr item"
      return empty
   end if
   put pEvent["seq"] into tSeq
   if tSeq is not an integer or tSeq < 0 or tSeq >= 9007199254740992 then
      rsSetError "rsIngestBridge: the event seq is not a sane integer"
      return empty
   end if
   put toLower(pEvent["signature"]) into tSigHex
   if not rsIsHexOfLen(tSigHex, 128) then
      rsSetError "rsIngestBridge: the event signature is not 128 hex chars"
      return empty
   end if
   put rsHexToBin(tSigHex) into tSig
   if tSig is empty then return empty
   put rsBep44SignBuf(kRsNostrSalt, tSeq, rsBencodeBytes(pEvent["value"])) \
         into tBuf
   if tBuf is empty then return empty
   try
      put sxSignVerifyDetached(tSig, tBuf, rsHexToBin(tHandle)) into tOk
   catch tErr
      rsSetError "rsIngestBridge:" && tErr
      return empty
   end try
   if tOk is not true then
      rsSetError "rsIngestBridge: the BEP44 signature does not verify under" && \
            "this handle"
      return empty
   end if
   put rsVerifyBridge(pEvent["value"], tHandle, empty) into tRec
   if tRec is empty then return empty
   if tRec["seq"] is not tSeq then
      rsSetError "rsIngestBridge: the BEP44 seq and the bridge's embedded" && \
            "seq disagree"
      return empty
   end if
   return tRec
end rsIngestBridge

--------------------------------------------------------------------------
-- the RIPTAPP1 app-state store
--
-- WHY THE LIBRARY OWNS THIS. Everything riptide knew about you used to die
-- at quit: who you follow, which relays you use, the display names you had
-- resolved, your own head seq. That is defensible in a phase demo and is
-- not defensible in an app - a lost seq counter alone means the next head
-- you publish is refused by every follower who already saw a higher one.
--
-- SEALED, NOT PLAIN, and the reason is not that a follow list is secret in
-- the way a key is. It is that a follow list IS the social graph: who you
-- read, which relays you talk to, which npub is yours. That is the exact
-- material the anon persona exists to keep unlinked, so leaving it in the
-- clear beside a sealed key file would put the interesting half of the
-- threat model on disk in plaintext.
--
-- The key is subkey 5 - its own row, never a signing key - so the store
-- opens only while unlocked, which is the same property the rest of the
-- keyring has. The payload is opaque TEXT: the library fixes the envelope
-- and the app owns the format inside it, because what belongs in app state
-- is an app question and a wire format here would freeze it.
--------------------------------------------------------------------------

-- "RIPTAPP1" "S" then sxSecretBox(UTF-8 state, subkey-5 key). The box
-- carries its own random nonce, so two seals of one state differ - which is
-- correct and is also why no golden vector pins these bytes; what the
-- goldens pin is the KEY, and the harness proves the round trip.
function rsSealAppState pStateText, pMaster
   local tKey, tBytes, tOut, tErr
   put rsSubkey(pMaster, kRsSubkeyAppState) into tKey
   if tKey is empty then return empty
   put textEncode(pStateText, "UTF-8") into tBytes
   if the number of bytes in tBytes > kRsAppStateMax then
      rsSetError "rsSealAppState: the state is over the" && kRsAppStateMax && \
            "byte cap"
      return empty
   end if
   try
      put textEncode(kRsAppMagic & "S", "ASCII") & sxSecretBox(tBytes, tKey) \
            into tOut
   catch tErr
      rsSetError "rsSealAppState needs SodiumXT (sxSecretBox):" && tErr
      return empty
   end try
   return tOut
end rsSealAppState

-- Open it. A file from a different master fails the Poly1305 tag inside
-- sxSecretBoxOpen - it cannot silently mis-decrypt - and a truncated or
-- foreign file is refused on the header before any crypto runs. The
-- decoded payload is UTF-8 round-tripped, because textDecode is LOSSY on
-- this engine and a mangled state file must refuse rather than load as
-- replacement characters (the 2026-08-15 finding).
function rsOpenAppState pFileBytes, pMaster
   local tKey, tHeader, tSealed, tBytes, tErr
   if the number of bytes in pFileBytes < 10 then
      rsSetError "rsOpenAppState: too short to be a RIPTAPP1 file"
      return empty
   end if
   put textDecode(byte 1 to 9 of pFileBytes, "ASCII") into tHeader
   if tHeader is not (kRsAppMagic & "S") then
      rsSetError "rsOpenAppState: not a RIPTAPP1 sealed state file"
      return empty
   end if
   put byte 10 to -1 of pFileBytes into tSealed
   put rsSubkey(pMaster, kRsSubkeyAppState) into tKey
   if tKey is empty then return empty
   try
      put sxSecretBoxOpen(tSealed, tKey) into tBytes
   catch tErr
      rsSetError "rsOpenAppState: wrong master seed or corrupted state file"
      return empty
   end try
   if the number of bytes in tBytes > kRsAppStateMax then
      rsSetError "rsOpenAppState: the sealed state is over the" && \
            kRsAppStateMax && "byte cap"
      return empty
   end if
   if not rsBytesAreUtf8(tBytes) then
      rsSetError "rsOpenAppState: the sealed state is not valid UTF-8"
      return empty
   end if
   if the number of bytes in tBytes is 0 then return empty
   return textDecode(tBytes, "UTF-8")
end rsOpenAppState

--------------------------------------------------------------------------
-- private: hex, big-endian integers, base32
--------------------------------------------------------------------------

-- Byte-exact string equality. `is` FOLDS CASE in this dialect, so every
-- comparison of a wire identifier - a tag name, a magic, a d-tag - has to
-- go through something like this or a non-conforming spelling is silently
-- accepted (the coinxt canonical-form lesson, and nostrxt's own rule 2).
private function rsBytesEqual pA, pB
   local tI, tN
   put the number of chars in pA into tN
   if tN is not the number of chars in pB then return false
   repeat with tI = 1 to tN
      if byteToNum(byte tI of pA) is not byteToNum(byte tI of pB) then
         return false
      end if
   end repeat
   return true
end rsBytesEqual

-- Is pBytes a valid UTF-8 sequence?
--
-- THE ENGINE FINDING (first two-machine pass, 2026-08-15). Every parser
-- here used to guard its name/text decode with a `try`, on the belief -
-- stated in six comments - that textDecode(...,"UTF-8") THROWS on
-- malformed UTF-8. On a real OXT engine it does NOT: it is LOSSY, decoding
-- invalid bytes to replacement characters and returning a non-empty
-- string, so the try never fired and the parsers handed back a mangled
-- name instead of refusing. The suite selftest's new "non-UTF-8 name is
-- refused" checks are what caught it - the first inputs that ever
-- exercised the path. The robust test for validity is a ROUND TRIP:
-- re-encode the decoded string and require it to reproduce the original
-- bytes exactly (only a valid UTF-8 sequence does). The inner try stays as
-- belt-and-suspenders for any engine that DOES throw.
private function rsBytesAreUtf8 pBytes
   local tDecoded, tErr
   if the number of bytes in pBytes is 0 then return true
   try
      put textDecode(pBytes, "UTF-8") into tDecoded
   catch tErr
      return false
   end try
   return textEncode(tDecoded, "UTF-8") is pBytes
end rsBytesAreUtf8

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
