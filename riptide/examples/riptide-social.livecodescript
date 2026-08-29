script "riptideSocialApp"

-- riptide-social.livecodescript - the Riptide Social flagship stack, phases
-- 1-7: one identity, one public feed, one follow, media over torrents,
-- serverless encrypted DMs plus the call, the LAN device mesh, and the
-- anonymous persona, on four self-building cards (Feed, Messages, Devices,
-- Anon).
--
-- WHAT IT WALKS (RIPTIDE-SOCIAL-SPEC.md sections 10.3 phases 1-3): create or
-- unlock the Argon2id-sealed master seed (RIPTKEY1, a 97-byte file the APP
-- owns - the library does no file I/O), derive the identity, show the same
-- key as its two spellings (the 64-hex handle the feed publishes under, and
-- the .onion address), then publish signed posts + a signed BEP44 head over
-- the real DHT, follow another author - fetch their head, walk the post
-- chain back to the zero target, show every authorSig verdict - and MEDIA:
-- attach a file to a post (rsMediaCreate seeds it in place as a trackerless
-- torrent; the post carries only the 40-hex info-hash), and fetch a post's
-- media by hash (rsMediaFetch, sequential so a video can hand off to the
-- system player MID-download; fetching co-seeds, so followers are the CDN).
--
-- HONESTY (the suite convention): phases 1-2 HAVE THEIR PASS - and it was
-- the two-machine one. On 2026-08-13 the maintainer ran this stack on two
-- machines: identities created on both sides, feeds published and received
-- in BOTH directions through the real DHT. That run closed phase 2's
-- done-criterion (a second machine walks the chain and verifies every
-- authorSig - a post renders here only after rsIngestHead/rsIngestPost
-- verify it) and was the first to drive REAL btPoll DHT events into the
-- ingest verifiers, which the harness only ever fed synthetically. The
-- library underneath was already engine-passed (2026-08-12, 133/133).
-- Result text and machine environments were not captured with the report;
-- the record is the maintainer's dated account.
--
-- PHASE 3 IS DONE (2026-08-15, TWO MACHINES): a follower on the second
-- machine fetched and PLAYED an attached video, near instantly. A follower
-- cannot reach a video any other way, so this one result exercised the
-- whole stack end to end on real hardware: machine A published a head and
-- a media-bearing post to the DHT; machine B fetched that head, walked the
-- chain, VERIFIED the authorSig, surfaced the media info-hash from the
-- verified post, joined A's swarm, and played what came back. Phases 1-3
-- through the real UI, not the harness. (Not distinguished in the report:
-- whether playback began MID-download or after a fast complete transfer.)
--
-- PHASE 4 IS DONE TOO (2026-08-15, TWO MACHINES): chat worked BOTH WAYS -
-- the sealed RSI1 intro, the deterministic-role crypto_kx session, and the
-- pairwise secretstream over rp1 all carried real traffic between two
-- identities with NO SERVER anywhere. Reaching the Messages card to do it
-- also CONFIRMS the `go to card` navigation, which had been fixed but
-- unverified after the multi-card conversion shipped `... of me` object
-- references the engine rejects (reported and fixed the same day; see
-- riptide/CLAUDE.md).
--
-- STILL UNEXERCISED HERE (docs/two-machine-runbook.md is the script for
-- each): the CALL (phase 5, built 2026-08-15: a Call button on the
-- Messages card, one-blob SDP signalling as "O"/"A" messages over the
-- encrypted DM rail, then a DIRECT dc channel; STUN only, no TURN, by
-- design - and, since later the same day, the spec-6.2 TYPING LANE: a
-- second dc channel, unordered + maxRetransmits 0, carrying absolute
-- typing state), the DEVICES card (phase 6 - the admission handshake,
-- three-legged: challenge, response, and an RSL1 "W" WELCOME the host
-- signs over the joiner's own response signature, so the admission is
-- MUTUAL - plus, since 2026-08-15, the SYNC PAYLOAD over the admitted
-- mesh: a draft field debounced on the poll timer and broadcast as
-- signed channel-0 records, feed-seq claims applied as max, and
-- channel-1 presence/typing per peer, every inbound record
-- verify-then-apply with strangers refused and logged), and the ANON
-- card (phase 7, needs tor). The navigation and reference forms are the
-- ones the Feed and Messages cards proved; what has never run is these
-- flows themselves.
--
-- SETUP: install sodiumxt (REQUIRED - identity cannot exist without it) and
-- torrentxt (required for publish/fetch; identity still works without), then
-- put the riptide script library in the message path before opening:
--
--    (nothing - the Riptide library is embedded in this file)
--
-- ONE SESSION PER PROCESS (torrentxt's rule, runbook trap 5.1): this stack
-- takes THE TorrentXT session. Close every other torrent-flavoured stack
-- first, and restart OXT before re-pasting this script - a recompile orphans
-- the session for the rest of the engine launch.
--
-- THE LOOK is the suite UI kit, carried verbatim between the marker lines
-- (master: tools/ui-kit.livecodescript; tools/check-ui-kit-drift.py holds
-- every copy byte-identical). Change the look in the master, never here.
--
-- SCOPE, said loudly: phases 5-7 ARE built in this stack now (the Call
-- button, the Devices card, the Anon card - built 2026-08-15; see STILL
-- UNEXERCISED above for what has never run), and the anon persona's
-- ONION SERVING is built too (2026-08-15, same day): Publish + serve
-- registers onion-httpd routes for the feed page at /, the signed
-- prekey at /prekey, and a POST /dm sealed-intro drop, over the
-- persona's deterministic onion. The SEAMS underneath (the page bytes,
-- the /prekey body, the /dm acceptance and its refusal legs) ran
-- engine-green 2026-08-20 in the suite paste (label synced 2026-08-23);
-- what still needs the OXT + live-Tor pass is THIS STACK's route wiring
-- and the persona actually served over a real tor. The head's
-- profile-meta field names a display-name blob (spec 4.1), published at
-- post time and - since 2026-08-23 (remaining-work A.9) - READ back:
-- fetching a foreign head (Fetch, or Start DM) also fetches its
-- profile-meta target and shows the content-verified name, degrading
-- honestly when the blob is absent, refused, or late. Long posts now
-- ride the kind-C chunked rail end to end (backlog A2): over the direct
-- 1000-byte budget a post's text splits into content-addressed chunks,
-- and a walked kind-C post renders an honest placeholder until every
-- part is fetched and verified - never a verified post with blank text. The LAN mesh now carries the
-- phase-6 SYNC PAYLOAD past admission (drafts, feed seq, presence -
-- signed records, verify-then-apply) and, since 2026-08-16, the MEDIA
-- HANDOFF: a signed channel-0 "M" POINTER record (info-hash + file name
-- + size) at the phase-3 torrent path - Send media... seeds the file in
-- place and offers it; the receiving device fetches by hash and plays,
-- exactly the engine-proven media rail. Channel 2 itself stays
-- allocated, dark, ON PURPOSE: a draft's media essentially never fits
-- enet's 60000-byte packet budget, and bulk over that seam is a torrent
-- in this suite (the recorded channel-2 decision). Still genuinely
-- UNBUILT: the persona's REPLY rail (answering an accepted intro over
-- an onion stream); answering means a public-side DM to the proven
-- sender. DMs (phase 4, the Messages card) hold ONE conversation at a
-- time in this demo, in memory only - no history, no offline queue;
-- both ends must be running. Public feeds are PUBLIC: the DHT keeps
-- records until expiry, there is no deletion, and the public rails are not
-- anonymity (spec section 9) - media rides ORDINARY BitTorrent swarms and
-- rp1 DM peers connect DIRECTLY, so both show your IP to the other side,
-- exactly as any torrent peer does.
--
-- KEYRING honesty: while unlocked, the identity seed lives in a script
-- local (the spec's one-keyring pattern) and OXT script memory is not
-- locked or reliably zeroed. Lock when done; never use a passphrase that
-- guards anything real in a demo.

-- ---- constants ---------------------------------------------------------------
-- Tick cadence is the app's one latency/CPU knob and the spec (section
-- 10.1) names two tiers: ~33 ms while a live dc/enet session is active,
-- ~250 ms when only the feed and DMs are. Only the slow tier existed until
-- 2026-08-17, which meant phases 5 and 6 - the two an engine pass judges
-- BY FEEL, a call and a typing indicator - ran at 7.5x their designed
-- interval, and "sluggish" would have read as a transport problem instead
-- of a constant in this file. raPollDelay picks the tier; kPaintMs keeps
-- the UI repaint tier where it was, because raising the painters from 4 Hz
-- to 30 Hz alongside the transports would be a NEW performance defect, not
-- a fix.

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- riptide/src/riptide.livecodescript ----
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

constant kRsVersion = "0.12.0"
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
         "(phase 8: identity, feed, media, DMs, LAN mesh, anon persona," && \
         "Nostr bridge)"
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

-- SAVE AND RESTORE THE ITEM DELIMITER (2026-08-29). This handler set it to
-- comma twice and never put it back, so every caller of rsBuildPost got the
-- delimiter reset underneath it. That is the C10 defect exactly - the one
-- rsMediaCreate had, whose symptom on an engine was a mystery about the
-- media list rather than anything that named a delimiter - and it survived
-- the 2026-08-17 sweep for the same reason rsPersonaAllows's copy did:
-- comma IS the engine default, so it is invisible until some caller sets
-- something else.
--
-- Restored around the WHOLE body rather than at each exit, because there are
-- SEVEN refusal exits here and a restore per exit is the line the next
-- refusal path forgets. The narrow-span shape rsMediaCreate uses does not
-- fit: the delimiter is read in two separate stretches with refusals in
-- between, so one save at the top and one restore before each `return` of
-- the delimiter-using region would be the same trap in a different place.
private function rsPostBody pTimestamp, pPrevTarget, pKind, pTextContent, pChunkTargets, pMediaList
   local tPrev, tOut, tTextBytes, tChunkCount, tMediaCount, tItem, tNorm
   local tSavedDelim, tResult
   put the itemDelimiter into tSavedDelim
   put rsPostBodyInner(pTimestamp, pPrevTarget, pKind, pTextContent, \
         pChunkTargets, pMediaList) into tResult
   set the itemDelimiter to tSavedDelim
   return tResult
end rsPostBody

private function rsPostBodyInner pTimestamp, pPrevTarget, pKind, pTextContent, pChunkTargets, pMediaList
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
   if (the number of bytes in tOut) + 64 > kRsMaxRecord then
      rsSetError "rsPostBody: the post record is over" && kRsMaxRecord && \
            "bytes; move the text to chunks or drop media"
      return empty
   end if
   return tOut
end rsPostBodyInner

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
-- Same save-and-restore as rsPostBody, and for the same reason: this handler
-- set the itemDelimiter and never put it back, across five refusal exits.
-- Split rather than restored per exit, because a restore per exit is the
-- line the next refusal path forgets.
function rsAssembleChunkText pChunkTargets, pParts
   local tSavedDelim, tResult
   put the itemDelimiter into tSavedDelim
   put rsAssembleChunkTextInner(pChunkTargets, pParts) into tResult
   set the itemDelimiter to tSavedDelim
   return tResult
end rsAssembleChunkText

private function rsAssembleChunkTextInner pChunkTargets, pParts
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
end rsAssembleChunkTextInner

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
         if (the number of bytes in pValue) - tI is not tLen then return -1
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
   if (the number of bytes in pPayload) + 5 > kRsFrameMax then
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

-- ---- onionxt/src/onionxt.livecodescript ----
-- onionxt.livecodescript - the OnionXT library.
--
-- OnionXT is a Tor transport and rendezvous layer for OpenXTalk / the xTalk
-- family. It speaks SOCKS5 (RFC 1928 + Tor extensions) and the Tor control
-- protocol to a LOCALLY-RUNNING tor daemon; it does not embed or ship Tor. It
-- adds no cryptography (SodiumXT does that) and, in this form, no native code:
-- the SOCKS5 and control clients are engine socket I/O, and base32 / the
-- ed25519 scalar clamp are pure byte manipulation.
--
-- STATUS: implemented AND run on a real OXT engine against a live tor daemon.
-- The core paths are confirmed on-engine: dialing through the SOCKS proxy, the
-- control-port connect + SAFECOOKIE auth, GETINFO / SETEVENTS, publishing a v3
-- onion service, accepting an inbound (Tor-forwarded) connection, streaming data
-- both ways, and bootstrap/HS_DESC events. The only path NOT yet exercised is the
-- optional Mode B (launching a bundled tor via `open process`), still flagged
-- "VERIFY:" below. The pure-compute paths are pinned by tools/onion-kat.py.
--
-- Conventions (see CLAUDE.md): public API oxPascalCase; locals t..., params
-- p..., script-locals s..., constants k...; SOCKS5 is BINARY (byte / numToByte /
-- byteToNum), the control protocol is CRLF text; every socket op is async
-- (open / read / accept with message) so the one interpreter thread never blocks
-- on the network; loopback (127.0.0.1) only; every open has an idempotent close;
-- every wire error fails closed and tears the resource down.
--
-- The async model (CLAUDE.md): oxDial and oxCreateService return a HANDLE
-- immediately and complete later; the app learns the outcome through the
-- callbacks below, never by a blocking return. The callback contracts are:
--   status callback  <handler> pKind, pInfo
--       pKind = "control"   pInfo = "connected"|"authenticated"|"disconnected"
--                                   |"authfailed: <reason>"|"error: <reason>"
--       pKind = "bootstrap" pInfo = 0..100          (coalesced to <= ~4 Hz)
--       pKind = "ready"     pInfo = empty           (bootstrap reached 100)
--       pKind = "service"   pInfo = <address>.onion (ADD_ONION returned it)
--       pKind = "serviceReady" pInfo = <address>    (descriptor uploaded)
--       pKind = "notice"    pInfo = <diagnostic>    (e.g. an accepted peer's raw id)
--       pKind = "event"     pInfo = <raw 650 line>  (advanced; opt-in noise)
--   stream callback  <handler> pStream, pEvent, pData
--       pEvent = "open"   the SOCKS tunnel (or inbound peer) is live
--       pEvent = "data"   pData is an inbound Data chunk (app frames its own)
--       pEvent = "closed" the peer closed the stream
--       pEvent = "error"  pData is the error; the stream has been torn down
--   peer callback    <handler> pStream, pService, pPeerAddr
--       a remote peer reached a published service; pStream is a fresh inbound
--       stream handle (register a stream callback on it), pService its service
--       handle, pPeerAddr the (loopback) peer address Tor forwarded from.
--
-- Callbacks are delivered with `dispatch` to the callback owner (oxSetCallbackOwner,
-- default the topStack); a missing handler is a clean no-op, so an app wires only
-- the callbacks it needs.

-- ==========================================================================
-- Constants. Loopback host is fixed; only the ports are configurable (and
-- loopback-locked). Declared before first use (OXT resolves a constant by
-- lexical position; a forward reference silently evaluates to nothing).
-- ==========================================================================

constant kOxHost = "127.0.0.1"
constant kOxSocksPortDefault = 9050
constant kOxControlPortDefault = 9051
constant kOxVersion = "1.0.0"

-- A bootstrapping daemon accepts the TCP connection then stalls; bound every
-- handshake so a silent stall becomes a clean error (docs/02 state machine).
constant kOxHandshakeTimeout = 20000     -- milliseconds
-- Coalesce bootstrap/status updates so a flood of 650 lines cannot thrash a
-- field (CLAUDE.md: <= ~4 Hz). 250 ms = 4 Hz.
constant kOxStatusThrottle = 250         -- milliseconds
-- RFC 4648 base32, lowercase, no padding (docs/04). Pure bytes, no crypto.
constant kOxBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
-- The v3 address checksum preimage prefix and version byte (docs/04). SHA3-256
-- of (kOxChecksumPrefix & pubkey & version) gives the 2-byte checksum; the hash
-- itself is a SodiumXT call, never hand-rolled here.
constant kOxChecksumPrefix = ".onion checksum"
-- The two SAFECOOKIE HMAC key strings, verbatim from the Tor control-spec.
constant kOxSafeCookieServerKey = "Tor safe cookie authentication server-to-controller hash"
constant kOxSafeCookieClientKey = "Tor safe cookie authentication controller-to-server hash"

-- ==========================================================================
-- Script-local state. Handle tables are LiveCode associative arrays keyed by a
-- small integer handle or by the engine's socket id; a stale or closed id must
-- be a clean no-op / error, never a crash.
-- ==========================================================================

-- Configurable ports (default to a system tor; Tor Browser uses 9150 / 9151).
local sSocksPort
local sControlPort

-- Control connection and bootstrap state (see docs/03-control-port.md).
local sControlSocket        -- engine id of the open control socket, or empty
local sControlState         -- disconnected|connecting|protocolinfo|authenticating|authenticated|failed
local sControlMethods       -- offered auth methods (comma list) from PROTOCOLINFO
local sControlCookieFile     -- cookie-file path from PROTOCOLINFO (unescaped)
local sControlPassword       -- app-set password for HASHEDPASSWORD auth
local sControlCookieBytes    -- the 32 raw cookie bytes (SAFECOOKIE flow)
local sControlClientNonce    -- our SAFECOOKIE client nonce (raw bytes)
local sControlTorVersion     -- tor version string from GETINFO version
local sBootstrap             -- 0..100 bootstrap percent from STATUS_CLIENT

-- Control command pipeline. One command in flight at a time so replies match
-- commands (docs/03); further commands queue. Reply lines accumulate until the
-- space-separated final line terminates the reply.
local sCtlInFlight           -- label of the in-flight command, or empty
local sCtlReplyLines         -- accumulated reply text (newline-joined)
local sCtlInData             -- true while inside a 250+ CmdData block
local sCtlData               -- accumulated CmdData block text
local sCtlQueue              -- pending commands: lines of "label" & TAB & "command"

-- App-registered callback handler names and the object they dispatch to.
local sStatusCallback
local sPeerCallback
local sCallbackOwner         -- long id of the object whose script has the callbacks
local sLastStatusTick        -- `the milliseconds` of the last coalesced update

-- Handle tables.
local sStreams               -- keyed by integer stream handle (nested array)
local sSockToStream          -- keyed by socket id string -> stream handle
local sServices              -- keyed by integer service handle (nested array)
local sLocalToService        -- keyed by local port -> service handle
local sNextHandle            -- monotonic handle allocator (0 is never valid)

-- ==========================================================================
-- Configuration.
-- ==========================================================================

command oxSetSocksPort pPort
   -- Loopback-locked: only the port is settable, never the host (CLAUDE.md
   -- socket gotcha 6). Take effect on the next oxDial.
   put pPort into sSocksPort
end oxSetSocksPort

command oxSetControlPort pPort
   put pPort into sControlPort
end oxSetControlPort

command oxSetControlPassword pPassword
   -- Only used if the daemon offers HASHEDPASSWORD auth (docs/03 step 2).
   put pPassword into sControlPassword
end oxSetControlPassword

command oxSetCallbackOwner pObjectLongId
   -- The object whose script holds the app callbacks. If unset, callbacks
   -- dispatch to the topStack; setting this explicitly (as the demo does) removes
   -- any ambiguity about which stack. Confirmed on-engine: with an explicit owner,
   -- onStatus / onPeer / onStreamData all resolve and fire.
   put pObjectLongId into sCallbackOwner
end oxSetCallbackOwner

command oxSetStatusCallback pHandlerName
   put pHandlerName into sStatusCallback
end oxSetStatusCallback

command oxSetPeerCallback pHandlerName
   put pHandlerName into sPeerCallback
end oxSetPeerCallback

function oxVersion
   -- The library version, plus the tor version once the control connection has
   -- answered GETINFO version (docs/05).
   if sControlTorVersion is empty then
      return kOxVersion
   end if
   return kOxVersion & " (tor " & sControlTorVersion & ")"
end oxVersion

-- ==========================================================================
-- Control connection, authentication, and the command pipeline
-- (docs/03-control-port.md). The connection is opened and authenticated
-- asynchronously; the app learns the outcome through the status callback.
-- ==========================================================================

command oxConnectControl
   -- Idempotent-ish: refuse a second concurrent connect rather than leak a
   -- socket. Disconnect first to reconnect.
   if sControlSocket is not empty then
      return "OnionXT: control connection already open (oxDisconnectControl first)"
   end if
   local tSocketID
   -- A named connection (|oxctl) so the id is stable and distinct from streams.
   put kOxHost & ":" & effectiveControlPort() & "|oxctl" into tSocketID
   put tSocketID into sControlSocket
   put "connecting" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   -- Bound the connect/handshake so a stalled daemon fails cleanly.
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxCtlOpened"
   -- A watchdog independent of the (repeating) socketTimeout: if we are not
   -- authenticated within the deadline, tear the connection down.
   send ("oxCtlDeadline " & quote & tSocketID & quote) to me in kOxHandshakeTimeout milliseconds
   return empty
end oxConnectControl

command oxDisconnectControl
   -- Idempotent close of the control socket and reset of all control state.
   if sControlSocket is not empty then
      oxSafeCloseSocket sControlSocket
   end if
   put empty into sControlSocket
   put "disconnected" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   put empty into sControlCookieBytes
   put empty into sControlClientNonce
end oxDisconnectControl

function oxIsControlAuthenticated
   return (sControlState is "authenticated")
end oxIsControlAuthenticated

function oxBootstrapProgress
   if sBootstrap is empty then
      return 0
   end if
   return sBootstrap
end oxBootstrapProgress

function oxIsReady
   -- Ready to carry traffic once bootstrapped to 100 and the control port is
   -- authenticated. A published service's own reachability is reported
   -- separately via the "serviceReady" status (HS_DESC UPLOADED).
   return (sBootstrap is 100) and (sControlState is "authenticated")
end oxIsReady

command oxCtlOpened pSocketID
   -- The control TCP connection is up. Start the single persistent line reader
   -- and kick the auth dance with PROTOCOLINFO (allowed pre-auth).
   if pSocketID is not sControlSocket then
      exit oxCtlOpened          -- a stale socket; ignore
   end if
   put "protocolinfo" into sControlState
   oxStatusUpdate "control", "connected"
   -- One outstanding CRLF read at a time; re-armed at the end of oxCtlLine.
   read from socket pSocketID until crlf with message "oxCtlLine"
   oxCtlSend "PROTOCOLINFO 1", "protocolinfo"
end oxCtlOpened

private command oxCtlSend pCommand, pLabel
   -- Send a control command, or queue it if one is already in flight so replies
   -- always match commands (docs/03: keep a single in-flight command queue).
   if sControlSocket is empty then
      exit oxCtlSend
   end if
   if sCtlInFlight is not empty then
      put pLabel & tab & pCommand & return after sCtlQueue
      exit oxCtlSend
   end if
   put pLabel into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlData
   -- Commands are ASCII text; textEncode gives the exact wire bytes, then the
   -- CRLF terminator (docs/03 line framing).
   write textEncode(pCommand & oxCrlf(), "UTF-8") to socket sControlSocket
end oxCtlSend

private command oxCtlDrainQueue
   -- Send the next queued command, if any. Called when a reply completes.
   if sCtlQueue is empty then
      exit oxCtlDrainQueue
   end if
   local tLine, tLabel, tCommand, tSaved
   put line 1 of sCtlQueue into tLine
   delete line 1 of sCtlQueue
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tLine into tLabel
   put item 2 to -1 of tLine into tCommand
   set the itemDelimiter to tSaved
   oxCtlSend tCommand, tLabel
end oxCtlDrainQueue

command oxCtlLine pSocketID, pData
   -- The persistent control-port line reader. Demultiplexes unsolicited 650
   -- events from command replies, reassembles multi-line replies, and honours
   -- the 250-/250+/'.'/250 space framing (docs/03).
   if pSocketID is not sControlSocket then
      exit oxCtlLine            -- a stale socket; ignore
   end if
   local tLine
   -- Control replies are ASCII; decode as text, then strip the line terminator.
   -- Confirmed on-engine: `read until crlf` returns the trailing CRLF and
   -- oxStripLineEnd removes it, so auth / GETINFO / events all parse correctly.
   put textDecode(pData, "UTF-8") into tLine
   put oxStripLineEnd(tLine) into tLine

   if sCtlInData then
      -- Inside a 250+ CmdData block: a lone "." ends it; other lines are data
      -- with any doubled leading dot un-stuffed (docs/03, RFC 2821 dot-stuffing).
      if tLine is "." then
         put false into sCtlInData
      else
         if char 1 to 2 of tLine is ".." then
            delete char 1 of tLine
         end if
         put tLine & return after sCtlData
      end if
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   if the length of tLine < 3 then
      oxCtlRearm pSocketID      -- malformed / empty; skip
      exit oxCtlLine
   end if

   local tCode, tSep
   put char 1 to 3 of tLine into tCode
   put char 4 of tLine into tSep

   if tCode is "650" then
      -- An asynchronous event. Route it to the event handler, never to the
      -- pending-command continuation.
      oxHandleEvent tLine
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   -- A command-reply line. Accumulate it and act on the frame control byte.
   put tLine & return after sCtlReplyLines
   if tSep is "+" then
      put true into sCtlInData
   else if tSep is space or tSep is empty then
      -- Space (or a 3-char line) terminates the reply.
      oxCtlReplyComplete
      put empty into sCtlInFlight
      put empty into sCtlReplyLines
      oxCtlDrainQueue
   end if
   -- "-" continuation: just keep reading.
   oxCtlRearm pSocketID
end oxCtlLine

private command oxCtlRearm pSocketID
   -- Keep exactly one read outstanding, but only while the socket is still ours.
   if pSocketID is sControlSocket then
      read from socket pSocketID until crlf with message "oxCtlLine"
   end if
end oxCtlRearm

private command oxCtlReplyComplete
   -- Dispatch the just-completed reply to the continuation for the in-flight
   -- command. if/else-if, not switch (the static gate rejects `end switch`).
   -- tReplyOp, NOT tOp: a t-prefixed "tOp" lowercases to `top`, a reserved OXT
   -- property, and the engine would parse it as the keyword, not this variable
   -- (the prefixed-token-shadow trap, CLAUDE.md gotcha 2).
   local tLabel, tReplyOp, tArg, tSaved
   put sCtlInFlight into tLabel
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tLabel into tReplyOp
   put item 2 to -1 of tLabel into tArg
   set the itemDelimiter to tSaved

   if tReplyOp is "protocolinfo" then
      oxParseProtocolInfo sCtlReplyLines
      oxChooseAuthAndStart
   else if tReplyOp is "authchallenge" then
      oxHandleAuthChallenge sCtlReplyLines
   else if tReplyOp is "authenticate" then
      oxHandleAuthResult sCtlReplyLines
   else if tReplyOp is "setevents" then
      -- 250 OK expected; nothing to do on success.
   else if tReplyOp is "getinfo-version" then
      oxParseTorVersion sCtlReplyLines
   else if tReplyOp is "getinfo-bootstrap" then
      oxParseBootstrapPhase sCtlReplyLines
   else if tReplyOp is "add_onion" then
      oxHandleAddOnionReply tArg, sCtlReplyLines
   else if tReplyOp is "del_onion" then
      -- 250 OK on success, 552 if unknown; the removal already forgot local
      -- state, so nothing further is required here.
   end if
end oxCtlReplyComplete

private command oxParseProtocolInfo pReply
   -- Extract the offered auth methods and (for cookie auth) the cookie-file path
   -- from the PROTOCOLINFO reply (docs/03 step 1).
   put empty into sControlMethods
   put empty into sControlCookieFile
   local tLine
   repeat for each line tLine in pReply
      if "AUTH METHODS=" is in tLine then
         -- METHODS=<comma list> [COOKIEFILE="<quoted, C-escaped path>"]
         put oxFieldAfter(tLine, "METHODS=") into sControlMethods
         if "COOKIEFILE=" is in tLine then
            put oxCUnescape(oxQuotedValueAfter(tLine, "COOKIEFILE=")) into sControlCookieFile
         end if
      end if
   end repeat
end oxParseProtocolInfo

private command oxChooseAuthAndStart
   -- Priority SAFECOOKIE > COOKIE > NULL > HASHEDPASSWORD (docs/03), but degrade
   -- past any method whose prerequisite is missing rather than fail: SAFECOOKIE
   -- needs SodiumXT HMAC-SHA256 and randomness (docs/08), COOKIE needs the
   -- readable cookie file, HASHEDPASSWORD needs an app-set password.
   put "authenticating" into sControlState

   if oxMethodOffered("SAFECOOKIE") and oxSodiumHasHmac() and oxSodiumHasRandom() then
      if oxLoadCookie() then
         oxStartSafeCookie
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("COOKIE") then
      if oxLoadCookie() then
         local tHex
         put oxBytesToHex(sControlCookieBytes) into tHex
         oxCtlSend "AUTHENTICATE " & tHex, "authenticate"
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("NULL") then
      oxCtlSend "AUTHENTICATE", "authenticate"
      exit oxChooseAuthAndStart
   end if
   if oxMethodOffered("HASHEDPASSWORD") and sControlPassword is not empty then
      -- Quote the password; escape backslash and double-quote (docs/03).
      oxCtlSend "AUTHENTICATE " & quote & oxQuoteEscape(sControlPassword) & quote, "authenticate"
      exit oxChooseAuthAndStart
   end if

   put "failed" into sControlState
   oxStatusUpdate "control", "authfailed: no usable auth method (offered " & sControlMethods & ")"
   oxDisconnectControl
end oxChooseAuthAndStart

private command oxStartSafeCookie
   -- SAFECOOKIE step A: send a 32-byte client nonce as hex (docs/03 step 2).
   put oxRandomBytes(32) into sControlClientNonce
   oxCtlSend "AUTHCHALLENGE SAFECOOKIE " & oxBytesToHex(sControlClientNonce), "authchallenge"
end oxStartSafeCookie

private command oxHandleAuthChallenge pReply
   -- SAFECOOKIE step B/C/D. The reply is a SINGLE final line:
   -- 250 AUTHCHALLENGE SERVERHASH=<hex> SERVERNONCE=<hex> (docs/03; the reply is
   -- space-separated, not a 250- continuation).
   local tLine, tServerHashHex, tServerNonceHex
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is not "250" then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: AUTHCHALLENGE rejected (" & tLine & ")"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   put oxFieldAfter(tLine, "SERVERHASH=") into tServerHashHex
   put oxFieldAfter(tLine, "SERVERNONCE=") into tServerNonceHex

   local tServerNonce, tMessage, tExpected, tOk
   put oxHexToBytes(tServerNonceHex) into tServerNonce
   -- HMAC message = CookieBytes || ClientNonce || ServerNonce (docs/03).
   put sControlCookieBytes & sControlClientNonce & tServerNonce into tMessage
   put oxHmac(kOxSafeCookieServerKey, tMessage) into tExpected
   -- Verify the server hash in constant time; a mismatch means the far end does
   -- not hold the cookie (not the real Tor), so abort and do NOT authenticate.
   put oxConstantTimeEqual(tExpected, oxHexToBytes(tServerHashHex)) into tOk
   if not tOk then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: SAFECOOKIE server hash mismatch (not the real Tor?)"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   -- Step D: authenticate with the controller-to-server hash.
   local tClientHash
   put oxHmac(kOxSafeCookieClientKey, tMessage) into tClientHash
   oxCtlSend "AUTHENTICATE " & oxBytesToHex(tClientHash), "authenticate"
end oxHandleAuthChallenge

private command oxHandleAuthResult pReply
   -- 250 OK => authenticated; anything else (515 bad auth, 514 required) fails
   -- closed (docs/03; there is no unauthenticated fallback, CLAUDE.md rule 4).
   local tLine
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is "250" then
      put "authenticated" into sControlState
      oxStatusUpdate "control", "authenticated"
      -- Subscribe to the events we care about and learn the tor version.
      oxCtlSend "SETEVENTS STATUS_CLIENT HS_DESC CIRC STREAM", "setevents"
      oxCtlSend "GETINFO version", "getinfo-version"
      -- Query the CURRENT bootstrap phase once. STATUS_CLIENT BOOTSTRAP events
      -- only fire WHILE tor is bootstrapping, so a daemon already at 100% when we
      -- connect emits none and the UI would sit at 0. This one GETINFO seeds it.
      oxCtlSend "GETINFO status/bootstrap-phase", "getinfo-bootstrap"
   else
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: " & tLine
      oxDisconnectControl
   end if
end oxHandleAuthResult

private command oxParseTorVersion pReply
   -- 250-version=<x> then 250 OK (docs/03). Pull the version value.
   local tLine
   repeat for each line tLine in pReply
      if "version=" is in tLine then
         put oxFieldAfter(tLine, "version=") into sControlTorVersion
      end if
   end repeat
end oxParseTorVersion

private command oxParseBootstrapPhase pReply
   -- Reply to GETINFO status/bootstrap-phase, carrying the CURRENT bootstrap state
   -- (unlike the STATUS_CLIENT event, which only fires while bootstrapping). Line:
   --   250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="..."
   -- Parse PROGRESS= the same way as the live event so the UI is seeded on connect.
   local tLine, tProgress
   repeat for each line tLine in pReply
      if "PROGRESS=" is in tLine then
         put oxFieldAfter(tLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   end repeat
end oxParseBootstrapPhase

command oxCtlDeadline pSocketID
   -- Handshake watchdog: if this control socket never reached authenticated,
   -- tear it down with a clean error (docs/07: a stalled bootstrap must not hang).
   if pSocketID is not sControlSocket then
      exit oxCtlDeadline
   end if
   if sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control authentication timed out"
      oxDisconnectControl
   end if
end oxCtlDeadline

-- ==========================================================================
-- Event handling: bootstrap progress and onion-descriptor readiness
-- (docs/03 step 5). 650 lines are tolerant-parsed; never hard-fail on an
-- unrecognized token (the control-spec requires controllers to tolerate them).
-- ==========================================================================

private command oxHandleEvent pLine
   local tType
   put word 2 of pLine into tType
   if tType is "STATUS_CLIENT" then
      if "BOOTSTRAP" is in pLine then
         local tProgress
         put oxFieldAfter(pLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   else if tType is "HS_DESC" then
      -- Positional: HS_DESC <Action> <HSAddress> ... . Our service is reachable
      -- once we see UPLOADED for its address (docs/03 step 5).
      local tAction, tAddress
      put word 3 of pLine into tAction
      put word 4 of pLine into tAddress
      if tAction is "UPLOADED" then
         oxMarkServiceReady tAddress
         oxStatusUpdate "serviceReady", tAddress
      end if
   else
      -- CIRC / STREAM and anything else are diagnostic; surface raw for advanced
      -- apps that opted into an "event" status, otherwise ignored.
      oxStatusUpdate "event", pLine
   end if
end oxHandleEvent

private command oxMarkServiceReady pAddress
   local tKey, tCore
   -- The event carries the ServiceID (no ".onion"); match either spelling.
   put pAddress into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   repeat for each key tKey in sServices
      if sServices[tKey]["serviceID"] is tCore then
         put true into sServices[tKey]["ready"]
      end if
   end repeat
end oxMarkServiceReady

private command oxStatusUpdate pKind, pInfo
   -- Deliver a status update to the app, coalescing the high-frequency bootstrap
   -- stream to <= ~4 Hz (CLAUDE.md). Terminal/rare kinds are always delivered.
   if pKind is "bootstrap" and pInfo is not 100 then
      local tNow
      put the milliseconds into tNow
      if sLastStatusTick is not empty and (tNow - sLastStatusTick) < kOxStatusThrottle then
         exit oxStatusUpdate   -- coalesce: drop this intermediate tick
      end if
      put tNow into sLastStatusTick
   end if
   oxDispatch sStatusCallback, pKind, pInfo, empty
end oxStatusUpdate

-- ==========================================================================
-- Outbound: dialing through SOCKS5 (docs/02-socks5-client.md). A callback-driven
-- state machine: greet, CONNECT with ATYP=3 (Tor resolves the name; never a
-- local DNS lookup), parse the reply, hand up a raw byte-stream tunnel.
-- ==========================================================================

command oxDial pHost, pPort
   -- Reports a stream handle through `the result` immediately; the SOCKS
   -- handshake completes asynchronously and the stream's callback receives
   -- "open" or "error" (CLAUDE.md async model).
   if pHost is empty then
      return "OnionXT: oxDial needs a host (a .onion or clearnet name)"
   end if
   if pPort is not an integer or pPort < 1 or pPort > 65535 then
      return "OnionXT: oxDial needs a port in 1..65535"
   end if
   local tHandle, tConnName, tSocketID
   put oxAllocHandle() into tHandle
   -- A NON-numeric connection name so several streams to 127.0.0.1:9050 get
   -- distinct socket ids, and so they never collide with the numeric names the
   -- accept loop assigns (the id separator is a vertical bar, docs LiveCode ref).
   put "oxs" & tHandle into tConnName
   put kOxHost & ":" & effectiveSocksPort() & "|" & tConnName into tSocketID
   put tSocketID into sStreams[tHandle]["socketID"]
   put "connecting" into sStreams[tHandle]["state"]
   put pHost into sStreams[tHandle]["host"]
   put pPort into sStreams[tHandle]["port"]
   put "dial" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[tSocketID]
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxSocksOpened"
   send ("oxStreamDeadline " & tHandle) to me in kOxHandshakeTimeout milliseconds
   return tHandle
end oxDial

command oxSetStreamCallback pStream, pHandlerName
   if sStreams[pStream]["socketID"] is empty then
      return "OnionXT: unknown stream handle " & pStream
   end if
   put pHandlerName into sStreams[pStream]["callback"]
   return empty
end oxSetStreamCallback

command oxWrite pStream, pData
   -- Write app bytes (already sealed by the app via SodiumXT) to the
   -- tunnel. OnionXT does not encrypt (docs/02).
   if sStreams[pStream]["state"] is not "connected" then
      return "OnionXT: stream " & pStream & " is not open"
   end if
   write pData to socket sStreams[pStream]["socketID"]
   return empty
end oxWrite

command oxCloseStream pStream
   -- Idempotent close of the stream socket; forget the handle. A stale handle is
   -- a clean no-op.
   if sStreams[pStream]["socketID"] is empty then
      exit oxCloseStream
   end if
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxCloseStream

function oxStreamState pStream
   if sStreams[pStream]["socketID"] is empty then
      return "unknown"
   end if
   return sStreams[pStream]["state"]
end oxStreamState

command oxSocksOpened pSocketID
   -- TCP up: send the method-negotiation greeting 05 01 00 (VER=5, 1 method,
   -- method 00 = no auth) and read the 2-byte method selection (docs/02 step 1).
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksOpened        -- stale
   end if
   put "greeting" into sStreams[tHandle]["state"]
   write numToByte(5) & numToByte(1) & numToByte(0) to socket pSocketID
   read from socket pSocketID for 2 with message "oxSocksMethod"
end oxSocksOpened

command oxSocksMethod pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksMethod
   end if
   if the number of bytes of pData < 2 then
      oxStreamFail tHandle, "SOCKS greeting reply truncated"
      exit oxSocksMethod
   end if
   local tVer, tMethod
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tMethod
   if tVer is not 5 then
      oxStreamFail tHandle, "SOCKS server is not version 5"
      exit oxSocksMethod
   end if
   if tMethod is not 0 then
      -- 0xFF = no acceptable methods; anything non-zero we do not offer. Fail
      -- closed; on loopback no auth is needed and its absence is a misconfig to
      -- surface, not paper over (docs/02).
      oxStreamFail tHandle, "SOCKS server demands an auth method OnionXT does not offer (0x" & oxByteHex(tMethod) & ")"
      exit oxSocksMethod
   end if
   -- Method OK: send the CONNECT request with ATYP=3 (domain name) so TOR
   -- resolves pHost. This is the anonymity-critical choice (docs/02 step 2).
   put "connect" into sStreams[tHandle]["state"]
   local tHost, tHostBytes, tPort, tRequest
   put sStreams[tHandle]["host"] into tHost
   put textEncode(tHost, "UTF-8") into tHostBytes
   if the number of bytes of tHostBytes > 255 then
      oxStreamFail tHandle, "SOCKS host name exceeds 255 bytes"
      exit oxSocksMethod
   end if
   put sStreams[tHandle]["port"] into tPort
   -- 05 01 00 03 <len> <host bytes> <port-hi> <port-lo>. The port is 2 bytes
   -- big-endian; build it by hand so the wire bytes are self-evident (do not use
   -- binaryEncode "S", which is host order, docs LiveCode ref).
   put numToByte(5) & numToByte(1) & numToByte(0) & numToByte(3) into tRequest
   put numToByte(the number of bytes of tHostBytes) after tRequest
   put tHostBytes after tRequest
   put numToByte(tPort div 256) & numToByte(tPort mod 256) after tRequest
   write tRequest to socket pSocketID
   -- Read the fixed 4-byte reply head (VER REP RSV ATYP); the BND.ADDR that
   -- follows is variable and framed by ATYP (docs/02 step 3).
   put "replyhead" into sStreams[tHandle]["state"]
   read from socket pSocketID for 4 with message "oxSocksReplyHead"
end oxSocksMethod

command oxSocksReplyHead pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyHead
   end if
   if the number of bytes of pData < 4 then
      oxStreamFail tHandle, "SOCKS reply head truncated"
      exit oxSocksReplyHead
   end if
   local tVer, tRep, tAtyp
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tRep
   put byteToNum(byte 4 of pData) into tAtyp
   if tRep is not 0 then
      -- Any non-zero REP is failure. Map it (incl. Tor's onion 0xF0..0xF7) to a
      -- human message and tear down (docs/02 REP table; CLAUDE.md rule 4).
      oxStreamFail tHandle, oxSocksRepMessage(tRep)
      exit oxSocksReplyHead
   end if
   put tAtyp into sStreams[tHandle]["atyp"]
   -- Consume BND.ADDR + 2-byte BND.PORT. Length depends on ATYP: 01 -> 4, 04 ->
   -- 16, 03 -> one length byte then that many. We do not use BND.ADDR; we just
   -- frame past it so the socket is left at the start of the tunnel payload.
   if tAtyp is 1 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 6 with message "oxSocksReplyDone"     -- 4 + 2
   else if tAtyp is 4 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 18 with message "oxSocksReplyDone"    -- 16 + 2
   else if tAtyp is 3 then
      put "replylen" into sStreams[tHandle]["state"]
      read from socket pSocketID for 1 with message "oxSocksReplyLen"
   else
      oxStreamFail tHandle, "SOCKS reply has an unknown address type (" & tAtyp & ")"
   end if
end oxSocksReplyHead

command oxSocksReplyLen pSocketID, pData
   -- ATYP=3 domain BND.ADDR: one length byte, then that many, then 2 port bytes.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyLen
   end if
   if the number of bytes of pData < 1 then
      oxStreamFail tHandle, "SOCKS reply address length truncated"
      exit oxSocksReplyLen
   end if
   local tLen
   put byteToNum(byte 1 of pData) + 2 into tLen     -- address bytes + 2 port bytes
   put "replyrest" into sStreams[tHandle]["state"]
   read from socket pSocketID for tLen with message "oxSocksReplyDone"
end oxSocksReplyLen

command oxSocksReplyDone pSocketID, pData
   -- The SOCKS reply is fully consumed and REP was 0: the socket is now a
   -- transparent tunnel. Hand it up and start the streaming inbound reader.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyDone
   end if
   put "connected" into sStreams[tHandle]["state"]
   oxInvokeStreamCallback tHandle, "open", empty
   -- Begin the persistent read; each inbound chunk is delivered as "data".
   -- Confirmed on-engine: the no-quantifier `read ... with message` streams
   -- available bytes as they arrive (a dialed SOCKS tunnel and an inbound onion
   -- HTTP request both deliver chunk by chunk); it does not block to EOF.
   read from socket pSocketID with message "oxStreamData"
end oxSocksReplyDone

command oxStreamData pSocketID, pData
   -- Inbound bytes on a live stream (dialed OR inbound-accepted; both are unified
   -- through the stream tables). Deliver the chunk and re-arm the read.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxStreamData          -- stale / already torn down
   end if
   if the number of bytes of pData > 0 then
      oxInvokeStreamCallback tHandle, "data", pData
   end if
   -- Re-arm only if the stream is still live (the callback may have closed it).
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxStreamData

command oxStreamDeadline pStream
   -- Handshake watchdog for a dialed stream: if it never reached "connected",
   -- tear it down (docs/02: a silent stall is the worst failure).
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamDeadline
   end if
   local tState
   put sStreams[pStream]["state"] into tState
   if tState is not "connected" and tState is not "closed" then
      oxStreamFail pStream, "SOCKS handshake timed out"
   end if
end oxStreamDeadline

private command oxStreamFail pStream, pError
   -- Fail closed: report the error to the app, then close and forget the stream.
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamFail
   end if
   put "failed" into sStreams[pStream]["state"]
   oxInvokeStreamCallback pStream, "error", pError
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxStreamFail

private function oxSocksRepMessage pRep
   -- Map a SOCKS REP code to a clear message. Standard RFC 1928 0x00..0x08 plus
   -- Tor's onion extensions 0xF0..0xF7 (docs/02; the extended band only appears
   -- when the SocksPort has ExtendedErrors set, so 0x01/0x04 must map sensibly
   -- too, since without that flag Tor collapses onion failures onto them).
   if pRep is 1 then
      return "general SOCKS server failure"
   else if pRep is 2 then
      return "connection not allowed by ruleset"
   else if pRep is 3 then
      return "network unreachable"
   else if pRep is 4 then
      return "host unreachable"
   else if pRep is 5 then
      return "connection refused"
   else if pRep is 6 then
      return "TTL expired"
   else if pRep is 7 then
      return "command not supported"
   else if pRep is 8 then
      return "address type not supported"
   else if pRep is 240 then
      return "onion service not found (wrong or offline .onion address)"
   else if pRep is 241 then
      return "onion service descriptor is invalid"
   else if pRep is 242 then
      return "onion service introduction failed"
   else if pRep is 243 then
      return "onion service rendezvous failed"
   else if pRep is 244 then
      return "onion service missing client authorization"
   else if pRep is 245 then
      return "onion service wrong client authorization"
   else if pRep is 246 then
      return "onion service invalid address (malformed .onion)"
   else if pRep is 247 then
      return "onion service introduction timed out"
   end if
   return "SOCKS request failed (REP 0x" & oxByteHex(pRep) & ")"
end oxSocksRepMessage

-- ==========================================================================
-- Inbound: onion services (docs/03 step 3-4, docs/04). Listen on loopback
-- FIRST, then ADD_ONION, so a peer that connects the moment the descriptor
-- publishes is answered (CLAUDE.md socket gotcha 5).
-- ==========================================================================

command oxCreateService pVirtualPort, pLocalPort
   -- Ephemeral service, Tor generates the key. Reports a service handle through
   -- `the result`; the .onion address arrives asynchronously (status "service"
   -- and oxServiceAddress) once ADD_ONION replies.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach keeps the service published even if the control connection
   -- drops (a transient socketClosed/socketError, or a reconnect): without it, an
   -- ADD_ONION service dies with its control connection while its descriptor
   -- lingers in the DHT for ~3h, so a later visit hits "unable to find hidden
   -- service identity key" at rendezvous. oxRemoveService / oxShutdown DEL_ONION
   -- it explicitly; a hard crash leaves it until DEL_ONION or a tor restart.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateService

command oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   -- Deterministic, reproducible address: derive the ed25519 identity from pSeed
   -- and pass Tor the 64-byte ED25519-V3 expanded key (docs/04). The expansion is
   -- SodiumXT's sxSignSeedToExpandedKey (docs/08 gap #1, SHIPPED in ABI 6); we
   -- compose it and fail with a clear message if it is absent, never hand-roll
   -- SHA-512. Same seed -> same .onion on every run.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   if the number of bytes of pSeed is not 32 then
      return "OnionXT: oxCreateServiceFromSeed needs a 32-byte seed"
   end if
   local tExpanded
   put oxExpandedKeyFromSeed(pSeed) into tExpanded
   if the number of bytes of tExpanded is not 64 then
      return tExpanded          -- a capability error, surfaced verbatim
   end if
   -- Tor's ADD_ONION ED25519-V3: wants STANDARD RFC 4648 base64 (the +/ alphabet
   -- with = padding). The engine's base64Encode emits exactly that; do NOT use
   -- SodiumXT's sxBin2Base64, which is url-safe and unpadded and tor rejects.
   -- Strip any line-wrap whitespace the encoder may insert (docs/04 base64 note).
   local tBlob
   put oxStripWhitespace(base64Encode(tExpanded)) into tBlob
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach: keep the service alive across a control-connection drop (see
   -- oxCreateService); DEL_ONION on teardown still removes it.
   oxCtlSend "ADD_ONION ED25519-V3:" & tBlob & " Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateServiceFromSeed

command oxPublishService pVirtualPort, pLocalPort
   -- Publish an onion whose virtual port Tor forwards to a loopback port that
   -- SOMETHING ELSE is already accepting on (LiveCode's built-in HTTPD Library, or
   -- any local server). Unlike oxCreateService, OnionXT does NOT start its own
   -- accept loop: the external server owns the socket, parses the request, and
   -- replies. Teardown DEL_ONIONs the service but leaves that socket alone. Reports
   -- a service handle through `the result`; the .onion address arrives
   -- asynchronously (status "service", oxServiceAddress) once ADD_ONION replies.
   --
   -- SECURITY (the caller's responsibility): `accept connections on port` usually
   -- binds ALL interfaces, so the external server's local port may be reachable
   -- from the LAN, bypassing Tor. The external server MUST enforce loopback itself
   -- (reject any non-127.0.0.1 peer before responding), exactly as OnionXT's own
   -- oxPeerAccepted does. Bind the server to loopback if it supports it.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   -- Mark it external so oxRemoveService DEL_ONIONs it but does not close the
   -- socket (which OnionXT never opened; the external server owns it).
   put true into sServices[tHandle]["external"]
   -- No accept loop here (contrast oxStartService). Flags=Detach as in
   -- oxCreateService, so a control-connection blip does not un-publish it.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxPublishService

private function oxCheckServiceArgs pVirtualPort, pLocalPort
   if sControlState is not "authenticated" then
      return "OnionXT: connect and authenticate the control port first (oxConnectControl)"
   end if
   if pVirtualPort is not an integer or pVirtualPort < 1 or pVirtualPort > 65535 then
      return "OnionXT: virtual port must be 1..65535"
   end if
   if pLocalPort is not an integer or pLocalPort < 1 or pLocalPort > 65535 then
      return "OnionXT: local port must be 1..65535"
   end if
   return empty
end oxCheckServiceArgs

private function oxStartService pVirtualPort, pLocalPort
   -- Allocate the handle and START the loopback listener before ADD_ONION so a
   -- forwarded connection is never refused (docs/03 step 4, ordering gotcha).
   local tHandle, tPrior
   put sLocalToService[pLocalPort] into tPrior
   if tPrior is not empty and sServices[tPrior]["localPort"] is not empty then
      -- Fail closed: a second service on an in-use local port would overwrite
      -- the port-to-service mapping, and removing either service would then
      -- close (or orphan) the shared listener out from under the other, so Tor
      -- keeps forwarding to a dead port - which looks exactly like a broken
      -- onion. One local port, one service; pick another local port.
      -- (Verified statically; needs an OXT pass.)
      return "OnionXT: local port " & pLocalPort & " already forwards for another service (one service per local port; pick another local port)"
   end if
   if tPrior is not empty then
      -- The mapping is stale (its service is gone); reclaim it and rebind below.
      delete variable sLocalToService[pLocalPort]
   end if
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   if sLocalToService[pLocalPort] is empty then
      -- Bind loopback only. The classic `accept connections on port` has no
      -- bind-address argument (may listen on all interfaces), so oxPeerAccepted
      -- enforces loopback by rejecting any non-loopback peer before reading.
      -- Confirmed on-engine: Tor-forwarded onion connections are accepted here.
      accept connections on port pLocalPort with message "oxPeerAccepted"
      if the result is not empty then
         -- The listener did not bind (most often the local port is already in use
         -- by a prior run or another app). Fail closed: with no listener, Tor
         -- forwards inbound onion traffic to a dead port and the visitor gets an
         -- empty response, which looks exactly like a broken onion.
         delete variable sServices[tHandle]
         return "OnionXT: cannot listen on 127.0.0.1:" & pLocalPort & " (" & the result & ")"
      end if
      put true into sServices[tHandle]["listening"]
   end if
   put tHandle into sLocalToService[pLocalPort]
   return tHandle
end oxStartService

private command oxHandleAddOnionReply pHandle, pReply
   -- Parse ServiceID (and PrivateKey unless discarded) from the ADD_ONION reply
   -- (docs/03 step 3). On failure, fail closed and tear the half-built service.
   local tLine
   if char 1 to 3 of (line 1 of pReply) is not "250" and "ServiceID=" is not in pReply then
      oxRemoveService pHandle
      oxStatusUpdate "control", "error: ADD_ONION failed (" & (line 1 of pReply) & ")"
      exit oxHandleAddOnionReply
   end if
   repeat for each line tLine in pReply
      if "ServiceID=" is in tLine then
         put oxFieldAfter(tLine, "ServiceID=") into sServices[pHandle]["serviceID"]
      else if "PrivateKey=" is in tLine then
         put oxFieldAfter(tLine, "PrivateKey=") into sServices[pHandle]["privateKey"]
      end if
   end repeat
   if sServices[pHandle]["serviceID"] is not empty then
      put sServices[pHandle]["serviceID"] & ".onion" into sServices[pHandle]["address"]
      oxStatusUpdate "service", sServices[pHandle]["address"]
   end if
end oxHandleAddOnionReply

command oxRemoveService pService
   -- DEL_ONION and stop the listener. Idempotent: a stale handle is a no-op.
   if sServices[pService]["localPort"] is empty then
      exit oxRemoveService
   end if
   local tServiceID, tLocalPort
   put sServices[pService]["serviceID"] into tServiceID
   put sServices[pService]["localPort"] into tLocalPort
   if tServiceID is not empty and sControlState is "authenticated" then
      oxCtlSend "DEL_ONION " & tServiceID, "del_onion:" & pService
   end if
   -- Stop accepting on the loopback port, but ONLY if WE own the listener
   -- (oxCreateService / oxCreateServiceFromSeed). A publish-only service
   -- (oxPublishService) forwards to a socket an external server owns; leave it
   -- alone, or we would close it out from under that server.
   if sServices[pService]["external"] is not true then
      if sLocalToService[tLocalPort] is pService then
         oxSafeCloseSocket tLocalPort
         delete variable sLocalToService[tLocalPort]
      end if
   end if
   delete variable sServices[pService]
end oxRemoveService

function oxServiceAddress pService
   return sServices[pService]["address"]
end oxServiceAddress

function oxServiceIsReady pService
   return (sServices[pService]["ready"] is true)
end oxServiceIsReady

command oxPeerAccepted pSocketID
   -- Tor forwarded an inbound onion connection to our loopback listener. Enforce
   -- loopback (security-critical: reject any non-loopback peer before reading a
   -- byte), wrap the accepted socket as an inbound stream, and hand it to the app.
   -- Emit a diagnostic notice with the RAW accepted id so a misparse is visible.
   oxStatusUpdate "notice", "accepted connection id=[" & pSocketID & "]"
   local tPeerHost
   put oxHostOfSocket(pSocketID) into tPeerHost
   if not oxHostIsLoopback(tPeerHost) then
      -- Not a Tor-forwarded loopback connection: refuse it (docs LiveCode ref;
      -- the listener may be bound to all interfaces). Print the RAW id next to
      -- the parsed host, because since oxHostIsLoopback stopped treating an
      -- unparseable id as loopback this notice is also how a socket-id spelling
      -- oxHostOfSocket does not know announces itself (it arrives here with an
      -- empty host); one self-contained line is what a tester can act on.
      oxStatusUpdate "notice", "rejected non-loopback peer host [" & tPeerHost & \
         "] from id [" & pSocketID & "]"
      oxSafeCloseSocket pSocketID
      exit oxPeerAccepted
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pSocketID into sStreams[tHandle]["socketID"]
   put "connected" into sStreams[tHandle]["state"]
   put "inbound" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[pSocketID]
   -- Hand the stream to the app FIRST so it can register a stream callback (the
   -- dispatch is synchronous), THEN arm the read so no inbound chunk is delivered
   -- before there is a callback to receive it.
   oxDispatch sPeerCallback, tHandle, oxGuessService(pSocketID), tPeerHost
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxPeerAccepted

private function oxGuessService pSocketID
   -- Best-effort service association for the peer callback. The accept callback
   -- carries the PEER address, not our local port, so we cannot always know which
   -- service was reached (VERIFY the accepted-socket id format on-engine). If a
   -- single service is live, return it; otherwise return empty and let the app
   -- key on distinct local ports.
   local tKeys, tCount, tKey
   put the keys of sServices into tKeys
   put the number of lines of tKeys into tCount
   if tCount is 1 then
      return line 1 of tKeys
   end if
   return empty
end oxGuessService

private function oxHostIsLoopback pHost
   -- Accept a Tor-forwarded peer no matter how the engine spells the local
   -- address in the accepted-socket id, and NOTHING else: `accept connections on
   -- port` takes no bind address (see oxStartService), so the listener may be
   -- reachable from the network and this is the only thing standing between a
   -- routable peer and our stream tables. Takes the host oxHostOfSocket parsed,
   -- so the brackets of "[::1]" are already gone and there is exactly one
   -- spelling of each address to test. Comparisons are case-insensitive by
   -- default, so "::FFFF:" matches "::ffff:" without folding anything.
   --
   -- EMPTY IS A REFUSAL NOW, and that is the point of this change rather than a
   -- side effect. It used to return true, with "some engines report no host for
   -- a local accept" as the reason - but the old parser handed this guard an
   -- empty string for EVERY IPv6-shaped id, so "the engine reported no host" and
   -- "we could not parse this id" were indistinguishable, and the permissive
   -- branch let "::ffff:203.0.113.9:1234" - a routable peer wearing an
   -- IPv4-mapped hat - in as loopback. A guard whose default is accept is a
   -- fail-open guard; CLAUDE.md rule 4 says fail closed on anything we do not
   -- understand. So an unrecognized spelling is refused and oxPeerAccepted
   -- prints the RAW id alongside the parsed host: if a real engine is ever seen
   -- spelling an accepted id with no host at all (or with the fully expanded
   -- "0:0:0:0:0:0:0:1"), the fix is to teach oxHostOfSocket that spelling, never
   -- to re-open this branch.
   local tHost
   put pHost into tHost
   if tHost is empty then
      return false
   end if
   if tHost is kOxHost then
      return true
   end if
   if tHost begins with "127." then
      return true
   end if
   if tHost is "::1" then
      return true
   end if
   if tHost begins with "::ffff:" then
      -- The IPv4-mapped form a dual-stack listener can report. It is the SAME
      -- address with a prefix, so strip it and re-test the v4 rules: that admits
      -- "::ffff:127.0.0.1" (genuinely loopback, and unroutable) and refuses
      -- "::ffff:203.0.113.9" (genuinely routable), which the old empty-item-1
      -- parse could not tell apart.
      delete char 1 to 7 of tHost
      if tHost is kOxHost or tHost begins with "127." then
         return true
      end if
      return false
   end if
   if tHost is "localhost" then
      return true
   end if
   return false
end oxHostIsLoopback

-- ==========================================================================
-- Address helpers: a v3 .onion address IS an ed25519 public key
-- (docs/04-onion-rendezvous.md). base32 and the layout are pure byte work; only
-- the checksum needs SHA3-256, which is composed from SodiumXT (docs/08).
-- ==========================================================================

function oxPublicKeyFromAddress pOnionAddress
   -- Strip ".onion", base32-decode 56 chars -> 35 bytes, return the first 32 (the
   -- ed25519 public key). No crypto needed. Empty on a structural error.
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return empty
   end if
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return empty
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return empty            -- not a version-3 address
   end if
   return byte 1 to 32 of tRaw
end oxPublicKeyFromAddress

function oxAddressFromPublicKey pEd25519Pub
   -- base32( pubkey || checksum || 0x03 ) & ".onion" (docs/04). The checksum is
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2], composed from SodiumXT;
   -- absent that primitive, return a clear error rather than a wrong address.
   if the number of bytes of pEd25519Pub is not 32 then
      return "OnionXT: oxAddressFromPublicKey needs a 32-byte ed25519 public key"
   end if
   local tChecksum
   put oxOnionChecksum(pEd25519Pub) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return tChecksum         -- capability error, surfaced verbatim
   end if
   return oxBase32Encode(pEd25519Pub & tChecksum & numToByte(3)) & ".onion"
end oxAddressFromPublicKey

function oxIsValidAddress pOnionAddress
   -- Structural checks always (length, alphabet, version byte); checksum
   -- verification too when SodiumXT SHA3-256 is available (docs/04, docs/08).
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return false
   end if
   local tI, tCh
   repeat with tI = 1 to 56
      put char tI of tCore into tCh
      if offset(tCh, kOxBase32Alphabet) is 0 then
         return false
      end if
   end repeat
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return false
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return false
   end if
   -- Checksum verification when we can compute it; otherwise structural-only
   -- (the real authentication is Tor's connect-time descriptor-signature check).
   local tChecksum
   put oxOnionChecksum(byte 1 to 32 of tRaw) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return true             -- no SHA3-256 available; accept the structure
   end if
   return oxConstantTimeEqual(tChecksum, byte 33 to 34 of tRaw)
end oxIsValidAddress

private function oxNormalizeAddress pOnionAddress
   -- Trim, lowercase, and strip a trailing ".onion".
   local tCore
   put oxTrim(pOnionAddress) into tCore
   put toLower(tCore) into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   return tCore
end oxNormalizeAddress

private function oxPow2 pN
   -- 2 to the pN, as an exact integer, WITHOUT the ^ operator (some xTalk
   -- parsers reject `^` in a div/mod expression). pN is small in base32 (0..12),
   -- so this is a few multiplies and stays well within exact-integer range.
   local tR, tI
   put 1 into tR
   repeat with tI = 1 to pN
      multiply tR by 2
   end repeat
   return tR
end oxPow2

private function oxIntDiv pA, pB
   -- Integer division (floor, for the non-negative operands base32 uses) WITHOUT
   -- the `div` operator, to sidestep any xTalk parser that mishandles div/mod/^
   -- inside a compound expression. Operands here are small (base32 bit math).
   return trunc(pA / pB)
end oxIntDiv

private function oxIntMod pA, pB
   -- pA modulo pB WITHOUT the `mod` operator (see oxIntDiv).
   return pA - pB * oxIntDiv(pA, pB)
end oxIntMod

private function oxBase32Encode pData
   -- RFC 4648 base32, lowercase, no padding. Pure bit-packing: accumulate input
   -- bytes MSB-first into a small buffer and emit 5-bit groups. The buffer is
   -- masked to its pending bits each iteration so it never grows past ~13 bits
   -- (staying in exact-integer range; a 280-bit accumulator would lose precision).
   local tOut, tBits, tValue, tI, tN, tIndex
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kOxBase32Alphabet after tOut
      end repeat
      put oxIntMod(tValue, oxPow2(tBits)) into tValue        -- keep only the pending bits
   end repeat
   if tBits > 0 then
      -- Left-align the final partial group and emit it (canonical no-pad tail).
      put oxIntMod(tValue * oxPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kOxBase32Alphabet after tOut
   end if
   return tOut
end oxBase32Encode

private function oxBase32Decode pText
   -- Inverse of oxBase32Encode. Accumulate 5 bits per input char and emit a byte
   -- whenever 8 bits are available; leftover (< 5) bits of the final group are
   -- discarded (canonical). Returns empty on any character outside the alphabet.
   local tOut, tBits, tValue, tI, tN, tCh, tIndex, tByteOut
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of chars of pText into tN
   repeat with tI = 1 to tN
      put char tI of pText into tCh
      put offset(tCh, kOxBase32Alphabet) into tIndex     -- 1..32, or 0 if absent
      if tIndex is 0 then
         return empty
      end if
      put tValue * 32 + (tIndex - 1) into tValue
      add 5 to tBits
      if tBits >= 8 then
         subtract 8 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 256) into tByteOut
         put numToByte(tByteOut) after tOut
         put oxIntMod(tValue, oxPow2(tBits)) into tValue
      end if
   end repeat
   return tOut
end oxBase32Decode

private function oxOnionChecksum pEd25519Pub
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2] (docs/04). H = SHA3-256 is
   -- a SodiumXT primitive (docs/08); compose it and report a capability error if
   -- it is absent, never hand-roll a hash (CLAUDE.md rule 1).
   local tPreimage, tHash
   put textEncode(kOxChecksumPrefix, "UTF-8") & pEd25519Pub & numToByte(3) into tPreimage
   put oxSha3_256(tPreimage) into tHash
   -- A valid SHA3-256 is exactly 32 bytes; any other length is the capability
   -- error string from oxSha3_256, surfaced verbatim (robust against comparing a
   -- string prefix against binary data).
   if the number of bytes of tHash is not 32 then
      return tHash
   end if
   return byte 1 to 2 of tHash
end oxOnionChecksum

private function oxExpandedKeyFromSeed pSeed
   -- Compose SodiumXT's ABI-6 helper (docs/08 gap #1, now SHIPPED): a 32-byte seed
   -- becomes the 64-byte Tor ED25519-V3 expanded secret key (SHA-512(seed) with the
   -- ed25519 scalar clamp, all done inside SodiumXT so OnionXT hand-rolls nothing).
   -- This is exactly the key ADD_ONION ED25519-V3:<key> wants (docs/04), and its
   -- public key equals sxSignKeypairFromSeed(pSeed)'s, so the .onion address and the
   -- app's signing identity stay consistent. Requires SodiumXT ABI >= 6.
   local tExpanded
   try
      put sxSignSeedToExpandedKey(pSeed) into tExpanded
   catch tError
      return "OnionXT: oxCreateServiceFromSeed needs SodiumXT sxSignSeedToExpandedKey (requires SodiumXT ABI >= 6; see docs/08)"
   end try
   if the number of bytes of tExpanded is not 64 then
      return "OnionXT: sxSignSeedToExpandedKey returned " & the number of bytes of tExpanded & " bytes, expected 64"
   end if
   return tExpanded
end oxExpandedKeyFromSeed

-- ==========================================================================
-- Pluggable transport seam (docs/06). Thin wrappers so any higher-layer protocol
-- can treat OnionXT as a transport: dial by rendezvous address, listen at a
-- seed-derived address, send/recv bytes. OnionXT stays a transport: no crypto,
-- no framing opinion; the payload is sealed by the app via SodiumXT.
-- ==========================================================================

function oxTransportInfo
   -- Advertise the transport and which optional SodiumXT-backed capabilities are
   -- available, so a caller can negotiate transports and fall back visibly
   -- rather than silently (docs/06). Returns a LiveCode array.
   local tInfo
   put "ox" into tInfo["transport"]
   put kOxVersion into tInfo["version"]
   put (oxSodiumHasHmac() and oxSodiumHasRandom()) into tInfo["safeCookieAuth"]
   put oxSodiumHasExpansion() into tInfo["deterministicOnion"]
   put oxSodiumHasSha3() into tInfo["offlineAddress"]
   return tInfo
end oxTransportInfo

command oxTransportDial pAddress, pPort
   -- Dial a rendezvous address. Accepts a full <56>.onion, or a 32-byte ed25519
   -- public key / 64-hex string, which it maps to an address first (docs/06).
   local tPort, tHost
   if pPort is empty then
      put 80 into tPort
   else
      put pPort into tPort
   end if
   put pAddress into tHost
   if not (tHost ends with ".onion") then
      local tPub
      if the number of chars of tHost is 64 then
         put oxHexToBytes(tHost) into tPub
      else
         put tHost into tPub
      end if
      if the number of bytes of tPub is 32 then
         put oxAddressFromPublicKey(tPub) into tHost
         if tHost begins with "OnionXT:" then
            return tHost
         end if
      end if
   end if
   oxDial tHost, tPort
   return the result
end oxTransportDial

command oxTransportListen pSeed, pVirtualPort, pLocalPort
   -- Publish a reproducible rendezvous point from a seed (docs/06).
   oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   return the result
end oxTransportListen

command oxTransportSend pStream, pData
   oxWrite pStream, pData
   return the result
end oxTransportSend

command oxTransportRecv pStream, pHandlerName
   -- Register where inbound bytes are delivered (the stream callback).
   oxSetStreamCallback pStream, pHandlerName
   return the result
end oxTransportRecv

-- ==========================================================================
-- Lifecycle and teardown. Central socket-message handlers and a master
-- oxShutdown so an app can free everything it opened, e.g. on closeStack (there
-- is no deterministic unload hook in OXT; CLAUDE.md handles-and-state).
-- ==========================================================================

command oxShutdown
   -- Idempotent: close every stream, remove every service, disconnect control.
   -- Safe to call twice.
   local tKey, tKeys
   put the keys of sStreams into tKeys
   repeat for each line tKey in tKeys
      oxCloseStream tKey
   end repeat
   put the keys of sServices into tKeys
   repeat for each line tKey in tKeys
      oxRemoveService tKey
   end repeat
   oxDisconnectControl
end oxShutdown

-- THE ENGINE'S THREE SOCKET MESSAGES, SPLIT IN TWO (2026-08-24).
--
-- The LOGIC lives in oxSocketError / oxSocketClosed / oxSocketTimeout, which
-- are ordinary ox*-prefixed functions answering ONE question: was that socket
-- MINE, and did I handle it? The `on socketError` / `on socketClosed` /
-- `on socketTimeout` handlers below are now pure dispatch - call the named
-- one, exit if it consumed the event, otherwise pass.
--
-- WHY, because the split looks like ceremony until you need it: these three
-- names are the ENGINE's, so every socket library in the message path
-- declares the same three, and two scripts cannot define one name in ONE
-- script - which is exactly what embedding a library into an app's stack
-- script does (tools/sync-demo-embeds.py). That is what kept OnionXT out of
-- nocloud's paste and left its users a manual `start using` step. With the
-- logic behind a name of its OWN, an embedder drops these three thin
-- wrappers and calls oxSocketError(...) from its own handler instead of
-- passing - no copy of this logic anywhere, so nothing can go stale.
--
-- The own-socket branches are UNCHANGED and stay the engine-proven ones; the
-- split itself is verified statically and needs a live-Tor re-pass.

-- Was pSocketID one of OUR sockets, and did we handle the error? "true" when
-- consumed, "false" when it belongs to somebody else.
function oxSocketError pSocketID, pError
   -- The engine's socket-failure message. If the socket closes because of an
   -- error, this arrives instead of socketClosed. Look up the owner and fail
   -- closed (docs LiveCode ref). A message for an unknown id is a clean no-op.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxStreamFail tHandle, "socket error: " & pError
      return "true"
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "error: " & pError
      oxDisconnectControl
      return "true"
   end if
   return "false"
end oxSocketError

on socketError pSocketID, pError
   if oxSocketError(pSocketID, pError) then
      exit socketError
   end if
   -- NOT OURS: pass it on (2026-08-23). The family rule this file itself
   -- documents for apps (docs/05, docs/10) applies to the library too:
   -- swallowing another library's socket event is a silent HANG there. Found
   -- by the suite's cross-library name gate when nostrxt's relay layer became
   -- the second library defining these.
   pass socketError
end socketError

-- Was pSocketID one of OUR sockets, and did we handle the close?
function oxSocketClosed pSocketID
   -- The remote side closed cleanly. Deliver "closed" to a stream's app callback
   -- and forget it; for the control socket, mark disconnected.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxInvokeStreamCallback tHandle, "closed", empty
      delete variable sSockToStream[pSocketID]
      delete variable sStreams[tHandle]
      return "true"
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "disconnected"
      oxDisconnectControl
      return "true"
   end if
   return "false"
end oxSocketClosed

on socketClosed pSocketID
   if oxSocketClosed(pSocketID) then
      exit socketClosed
   end if
   -- NOT OURS: pass it on (see socketError above).
   pass socketClosed
end socketClosed

-- Was pSocketID one of OUR sockets, and did we handle the timeout?
function oxSocketTimeout pSocketID
   -- socketTimeout REPEATS every interval while a read/write is pending (docs
   -- LiveCode ref), so it is only fatal during a handshake; on a connected stream
   -- it is just an idle read and must be ignored. Tear down only handshakes.
   local tHandle, tState
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      put sStreams[tHandle]["state"] into tState
      if tState is not "connected" then
         oxStreamFail tHandle, "SOCKS handshake timed out"
      end if
      return "true"
   end if
   -- Control socket (ours even when authenticated - an idle timeout there
   -- is normal): only fatal before authentication completes.
   if pSocketID is sControlSocket then
      if sControlState is not "authenticated" then
         oxStatusUpdate "control", "error: control handshake timed out"
         oxDisconnectControl
      end if
      return "true"
   end if
   return "false"
end oxSocketTimeout

on socketTimeout pSocketID
   if oxSocketTimeout(pSocketID) then
      exit socketTimeout
   end if
   -- NOT OURS: pass it on (see socketError above).
   pass socketTimeout
end socketTimeout

-- ==========================================================================
-- Optional Mode B: launch and supervise a bundled tor (docs/07). This is a
-- CONVENIENCE layer, NOT the default and NOT the tested path; the assume-running
-- daemon (Mode A) is the trusted, recommended base. VERIFY every step on-engine.
-- ==========================================================================

command oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort
   -- Write a minimal torrc into pDataDir and launch pTorPath against it, so tor
   -- exits with the app (__OwningControllerProcess) and uses cookie auth. Returns
   -- empty on a clean launch attempt, or an error string. The caller then polls
   -- oxConnectControl / oxBootstrapProgress; this does not wait for bootstrap.
   if pTorPath is empty or pDataDir is empty then
      return "OnionXT: oxLaunchTor needs a tor binary path and a data directory"
   end if
   local tSocks, tControl, tTorrc, tRcPath
   if pSocksPort is empty then
      put kOxSocksPortDefault into tSocks
   else
      put pSocksPort into tSocks
   end if
   if pControlPort is empty then
      put kOxControlPortDefault into tControl
   else
      put pControlPort into tControl
   end if
   put "SocksPort " & tSocks & oxCrlf() after tTorrc
   put "ControlPort " & tControl & oxCrlf() after tTorrc
   put "CookieAuthentication 1" & oxCrlf() after tTorrc
   put "DataDirectory " & pDataDir & oxCrlf() after tTorrc
   -- Tie tor's lifetime to this process where the platform supports it.
   put "__OwningControllerProcess " & oxProcessId() & oxCrlf() after tTorrc
   put pDataDir & "/onionxt-torrc" into tRcPath
   put tTorrc into url ("binfile:" & tRcPath)
   oxSetSocksPort tSocks
   oxSetControlPort tControl
   -- open process is platform-specific; launch tor detached with -f <torrc>.
   -- QUOTE BOTH PATHS. The command line is split on whitespace, so an unquoted
   -- "C:/Program Files/Tor/tor.exe" arrives as the two arguments "C:/Program"
   -- and "Files/Tor/tor.exe" and the launch fails - and a data directory under
   -- "Application Support" or a user folder with a space in the name is the
   -- normal case on Windows and macOS, not an edge case. The same applies to
   -- the torrc path, which is derived from pDataDir.
   -- VERIFY: process launch and teardown on your target OXT build.
   open process (quote & pTorPath & quote & " -f " & quote & tRcPath & quote) for read
   return empty
end oxLaunchTor

command oxStopTor
   -- Ask tor to shut down over the control port, then disconnect. If Mode B was
   -- not used this simply disconnects control (idempotent).
   if sControlState is "authenticated" then
      oxCtlSend "SIGNAL SHUTDOWN", "signal"
   end if
   oxDisconnectControl
end oxStopTor

-- ==========================================================================
-- SodiumXT composition helpers (requires SodiumXT ABI >= 6 for the deterministic
-- onion and SAFECOOKIE paths). Each sx* primitive is called DIRECTLY and wrapped
-- in try/catch: an absent handler raises a catchable execution error, so a missing
-- primitive degrades to a clear capability error rather than crashing, and the
-- function's return value comes back unambiguously (CLAUDE.md rule 1; no crypto is
-- hand-rolled here). base32 and the base64 encode are pure byte ops, NOT here.
-- ==========================================================================

private function oxSha3_256 pData
   -- Composed since SodiumXT ABI 7 (docs/08 gap #2, closed 2026-08-11):
   -- sxSha3_256 is the vendored FIPS-202 primitive SodiumXT ships precisely
   -- for this checksum. Against an older installed SodiumXT the absent handler
   -- still raises here and degrades to the clear capability error below. The
   -- checksum is a nicety, not a security dependency (tor authenticates the
   -- onion at connect time), so callers degrade to structural-only checks.
   local tOut
   try
      put sxSha3_256(pData) into tOut
   catch tError
      return "OnionXT: the offline .onion checksum needs SodiumXT SHA3-256 (sxSha3_256, ABI 7+; this SodiumXT predates it - docs/08 #2)"
   end try
   return tOut
end oxSha3_256

private function oxHmac pKeyString, pMessage
   -- HMAC-SHA256 (SodiumXT ABI >= 6). The ASCII key string crosses as its bytes.
   local tOut
   try
      put sxHmacSha256(textEncode(pKeyString, "UTF-8"), pMessage) into tOut
   catch tError
      return "OnionXT: SAFECOOKIE auth needs SodiumXT HMAC-SHA256 (sxHmacSha256, SodiumXT ABI >= 6, docs/08)"
   end try
   return tOut
end oxHmac

private function oxRandomBytes pCount
   local tOut
   try
      put sxRandomBytes(pCount) into tOut
   catch tError
      return empty
   end try
   return tOut
end oxRandomBytes

private function oxConstantTimeEqual pA, pB
   -- Prefer SodiumXT's constant-time compare; fall back to a plain compare only
   -- when it is unavailable (acceptable on a loopback control port).
   local tOut
   try
      put sxMemEqual(pA, pB) into tOut
      return (tOut is true)
   catch tError
      return (pA is pB)
   end try
end oxConstantTimeEqual

private function oxSodiumHasHmac
   -- True if SodiumXT (ABI >= 6) provides HMAC-SHA256. A benign 1-byte probe.
   local tOut
   try
      put sxHmacSha256(numToByte(0), numToByte(0)) into tOut
      return (the number of bytes of tOut is 32)
   catch tError
      return false
   end try
end oxSodiumHasHmac

private function oxSodiumHasRandom
   local tOut
   try
      put sxRandomBytes(1) into tOut
      return (the number of bytes of tOut is 1)
   catch tError
      return false
   end try
end oxSodiumHasRandom

private function oxSodiumHasSha3
   -- Capability probe: true on SodiumXT ABI 7+ (sxSha3_256 shipped 2026-08-11,
   -- docs/08 #2 CLOSED); false only against an older installed SodiumXT.
   try
      get sxSha3_256(empty)
      return true
   catch tError
      return false
   end try
end oxSodiumHasSha3

private function oxSodiumHasExpansion
   -- True if SodiumXT (ABI >= 6) provides the seed -> expanded-key helper.
   local tOut
   try
      put sxSignSeedToExpandedKey(oxZeroBytes(32)) into tOut
      return (the number of bytes of tOut is 64)
   catch tError
      return false
   end try
end oxSodiumHasExpansion

private function oxLoadCookie
   -- Read the 32 raw cookie bytes from the authoritative PROTOCOLINFO path
   -- (docs/03). binfile is binary-safe. Returns true on a plausible 32-byte read.
   if sControlCookieFile is empty then
      return false
   end if
   local tBytes
   put url ("binfile:" & sControlCookieFile) into tBytes
   if the number of bytes of tBytes is not 32 then
      return false
   end if
   put tBytes into sControlCookieBytes
   return true
end oxLoadCookie

-- ==========================================================================
-- Small pure helpers.
-- ==========================================================================

private function effectiveSocksPort
   if sSocksPort is empty then
      return kOxSocksPortDefault
   end if
   return sSocksPort
end effectiveSocksPort

private function effectiveControlPort
   if sControlPort is empty then
      return kOxControlPortDefault
   end if
   return sControlPort
end effectiveControlPort

private function oxAllocHandle
   -- Monotonic; 0 is never a valid handle so a zero/empty is always a clean miss.
   if sNextHandle is empty then
      put 0 into sNextHandle
   end if
   add 1 to sNextHandle
   return sNextHandle
end oxAllocHandle

private command oxSafeCloseSocket pSocketID
   -- Idempotent close: only close ids the engine still lists as open, so closing
   -- a stale/unknown id is a clean no-op (VERIFY the engine tolerates it anyway).
   if pSocketID is empty then
      exit oxSafeCloseSocket
   end if
   if pSocketID is among the lines of the openSockets then
      close socket pSocketID
   end if
end oxSafeCloseSocket

private command oxInvokeStreamCallback pStream, pEvent, pData
   oxDispatch sStreams[pStream]["callback"], pStream, pEvent, pData
end oxInvokeStreamCallback

private command oxDispatch pHandlerName, pArg1, pArg2, pArg3
   -- Deliver to the app; a missing handler is a clean no-op so an app wires only
   -- the callbacks it uses. Guard the call so a throwing app handler cannot break
   -- the state machine.
   if pHandlerName is empty then
      exit oxDispatch
   end if
   local tTarget
   put oxCallbackTarget() into tTarget      -- a local, not a function call inline
   try
      dispatch pHandlerName to tTarget with pArg1, pArg2, pArg3
   catch tIgnore
      -- Swallow app-side callback errors; the transport must keep running.
   end try
end oxDispatch

private function oxCallbackTarget
   -- The object the app callbacks live in. Explicitly set is authoritative;
   -- otherwise the topStack is the best default (VERIFY it is the app's stack).
   if sCallbackOwner is not empty then
      return sCallbackOwner
   end if
   return the topStack
end oxCallbackTarget

private function oxCrlf
   -- The wire line terminator as explicit bytes-to-be (U+000D U+000A), so the
   -- byte value never depends on how the engine defines the `crlf` constant.
   return numToChar(13) & numToChar(10)
end oxCrlf

private function oxStripLineEnd pLine
   -- Strip a trailing LF and/or CR from a decoded reply line, in either order.
   -- A plain function (returns the trimmed line) rather than a @-by-reference
   -- command, to avoid the less-common reference-parameter construct.
   repeat while pLine is not empty and (the last char of pLine is numToChar(10) or the last char of pLine is numToChar(13))
      delete the last char of pLine
   end repeat
   return pLine
end oxStripLineEnd

private function oxFieldAfter pText, pMarker
   -- The whitespace-delimited token immediately following pMarker in pText, or
   -- empty. Used for METHODS=, PROGRESS=, ServiceID=, version=, SERVERHASH=, etc.
   -- itemDelimiter is global mutable state, so save and restore it (gotcha 7).
   local tPos, tRest, tSaved, tOut
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   -- Stop at the first space (values here are single tokens; quoted values use
   -- oxQuotedValueAfter instead).
   put the itemDelimiter into tSaved
   set the itemDelimiter to space
   put item 1 of tRest into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxFieldAfter

private function oxQuotedValueAfter pText, pMarker
   -- The C-quoted string value following pMarker (e.g. COOKIEFILE="..."). Returns
   -- the raw (still-escaped) inside of the quotes; the caller un-escapes.
   local tPos, tRest, tOut, tI, tCh, tEsc
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   if char 1 of tRest is not quote then
      -- Unquoted value: take up to the next space (save/restore itemDelimiter).
      -- tOut is already declared at the handler top; only tSaved is new here.
      local tSaved
      put the itemDelimiter into tSaved
      set the itemDelimiter to space
      put item 1 of tRest into tOut
      set the itemDelimiter to tSaved
      return tOut
   end if
   -- Walk from just after the opening quote to the matching unescaped quote.
   put empty into tOut
   put false into tEsc
   repeat with tI = 2 to the number of chars of tRest
      put char tI of tRest into tCh
      if tEsc then
         put tCh after tOut
         put false into tEsc
      else if tCh is "\" then
         put tCh after tOut
         put true into tEsc
      else if tCh is quote then
         exit repeat
      else
         put tCh after tOut
      end if
   end repeat
   return tOut
end oxQuotedValueAfter

private function oxCUnescape pStr
   -- Undo Tor's C-style string escapes (docs/03): \n \t \r, octal \0..\377, and
   -- backslash-before-any-other-char is that literal char.
   local tOut, tI, tN, tCh, tNext, tOct
   put empty into tOut
   put the number of chars of pStr into tN
   put 1 into tI
   repeat while tI <= tN
      put char tI of pStr into tCh
      if tCh is "\" and tI < tN then
         put char (tI + 1) of pStr into tNext
         if tNext is "n" then
            put numToChar(10) after tOut
            add 2 to tI
         else if tNext is "t" then
            put numToChar(9) after tOut
            add 2 to tI
         else if tNext is "r" then
            put numToChar(13) after tOut
            add 2 to tI
         else if tNext is in "01234567" then
            -- Up to 3 octal digits.
            put empty into tOct
            add 1 to tI
            repeat while tI <= tN and (the number of chars of tOct) < 3 and (char tI of pStr) is in "01234567"
               put char tI of pStr after tOct
               add 1 to tI
            end repeat
            put numToChar(oxOctalToNum(tOct)) after tOut
         else
            put tNext after tOut
            add 2 to tI
         end if
      else
         put tCh after tOut
         add 1 to tI
      end if
   end repeat
   return tOut
end oxCUnescape

private function oxOctalToNum pOct
   local tVal, tI
   put 0 into tVal
   repeat with tI = 1 to the number of chars of pOct
      put tVal * 8 + (charToNum(char tI of pOct) - 48) into tVal
   end repeat
   return tVal
end oxOctalToNum

private function oxQuoteEscape pStr
   -- Escape backslash and double-quote for a control-port QuotedString.
   local tOut
   put pStr into tOut
   replace "\" with "\\" in tOut
   replace quote with ("\" & quote) in tOut
   return tOut
end oxQuoteEscape

private function oxBytesToHex pData
   -- Lowercase hex (high nibble first). H* unpacks the whole run. binaryDecode is
   -- a FUNCTION (it returns the count decoded and fills the output variable, which
   -- must already exist), so it must be called as a function; `get` discards the
   -- count into `it` while tHex is filled.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end oxBytesToHex

private function oxHexToBytes pHex
   return binaryEncode("H*", pHex)
end oxHexToBytes

private function oxByteHex pNum
   -- Two-digit hex for one byte value (for error messages).
   return oxBytesToHex(numToByte(pNum))
end oxByteHex

private function oxHostOfSocket pSocketID
   -- The HOST part of an engine socket id: "host:port", optionally with a
   -- "|name" suffix (we mint "127.0.0.1:9050|oxs3" ourselves; an ACCEPTED id is
   -- whatever the engine spells the PEER address as, so its shape is the
   -- engine's choice, not ours).
   --
   -- This is security-critical input, not a display helper: oxPeerAccepted feeds
   -- the result straight to oxHostIsLoopback, which decides whether an inbound
   -- peer is let in. The obvious "item 1 with the itemDelimiter set to colon"
   -- was wrong in BOTH directions on an IPv6 id, and one of those directions
   -- FAILED OPEN:
   --   "::1:54321"                -> item 1 is EMPTY, and the guard's old
   --                                 empty-is-loopback branch accepted it;
   --   "::ffff:203.0.113.9:1234"  -> item 1 is EMPTY too, so a ROUTABLE peer in
   --                                 IPv4-mapped form was accepted as loopback;
   --   "[::1]:54321"              -> item 1 is "[", so a real loopback peer was
   --                                 refused (the harmless direction).
   -- Parse by SHAPE instead, which also makes the guard's "::1" branch reachable
   -- for the first time (it never could be: item 1 of anything containing a
   -- colon cannot itself contain one):
   --   1. drop any "|name" suffix - the name half is ours and never part of the
   --      host, and it can carry digits that would otherwise look like a port;
   --   2. a bracketed group IS the host, verbatim and unbracketed - the brackets
   --      exist precisely to separate an IPv6 host's colons from the port colon,
   --      and stripping them here means the guard sees ONE spelling of ::1;
   --   3. otherwise the host is everything up to the LAST colon, which is right
   --      for "127.0.0.1:9050" and for a bare "::1:54321" alike;
   --   4. a colon-less id has no port to strip, so it is all host.
   -- Anything this cannot make sense of comes back EMPTY, which oxHostIsLoopback
   -- now REFUSES (it used to accept it); that is the fail-closed direction.
   local tSaved, tRaw, tCut, tOut
   put pSocketID into tRaw
   put offset("|", tRaw) into tCut
   if tCut > 0 then
      delete char tCut to -1 of tRaw
   end if
   if char 1 of tRaw is "[" then
      put offset("]", tRaw) into tCut
      if tCut < 3 then
         return empty              -- unclosed or empty brackets: not a host
      end if
      return char 2 to (tCut - 1) of tRaw
   end if
   if ":" is not in tRaw then
      return tRaw
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   -- `item 1 to -2` REJOINS its items with the delimiter, which is exactly what
   -- a bare IPv6 host needs: the three empty/short items of "::1:54321" come
   -- back as "::1", while "127.0.0.1:9050" comes back unchanged.
   put item 1 to -2 of tRaw into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxHostOfSocket

private function oxMethodOffered pMethod
   -- sControlMethods is a comma list; force comma before testing membership.
   local tSaved, tResult
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put (pMethod is among the items of sControlMethods) into tResult
   set the itemDelimiter to tSaved
   return tResult
end oxMethodOffered

private function oxStripWhitespace pStr
   local tOut
   put pStr into tOut
   replace numToChar(10) with empty in tOut
   replace numToChar(13) with empty in tOut
   replace space with empty in tOut
   replace tab with empty in tOut
   return tOut
end oxStripWhitespace

private function oxTrim pStr
   -- The `tOut is not empty` guard is essential: the empty string is "in" every
   -- string, so without it an all-whitespace or empty input would loop forever
   -- (the first/last char of empty is empty, which `is in` any charset).
   local tOut, tWhite
   put pStr into tOut
   put space & tab & numToChar(10) & numToChar(13) into tWhite
   repeat while tOut is not empty and (the first char of tOut) is in tWhite
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut) is in tWhite
      delete the last char of tOut
   end repeat
   return tOut
end oxTrim

private function oxZeroBytes pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(0) after tOut
   end repeat
   return tOut
end oxZeroBytes

private function oxProcessId
   -- Best-effort current process id for __OwningControllerProcess (Mode B).
   -- VERIFY the available accessor on your OXT build; empty is tolerated by tor.
   return the processId
end oxProcessId

-- ---- onionxt/src/onion-httpd.livecodescript ----
-- onion-httpd.livecodescript - a small, self-contained HTTP/1.1 server for Tor
-- onion services, built ENTIRELY on OnionXT's accept loop (oxCreateService).
--
-- WHY this instead of the engine's HTTPD Library: LiveCode's built-in HTTPD
-- Library is not present on every OpenXTalk engine (httpdStart raised "handler
-- not found" on-engine). This module needs nothing but OnionXT, which already
-- owns the socket, enforces loopback, and streams inbound bytes - the path the
-- main demo proved works. So it runs wherever OnionXT runs.
--
-- USAGE (in an app that has `start using` onionxt.livecodescript AND this file):
--   oxSetCallbackOwner the long id of me     -- your stack owns onStatus + routes
--   oxSetStatusCallback "onStatus"
--   oxhInit the long id of me                -- where your route handlers live
--   oxhSetRoot "/path/to/site"               -- optional: serve static files
--   oxhRoute "GET", "/hello", "myHello"      -- optional: a dynamic route
--   ... oxConnectControl, and when authenticated:
--   oxhServe 80, 8090                         -- publish an onion + serve HTTP on it
-- A route handler:  command myHello pStream, pRequest ; oxhReply pStream, 200, "hi",
--   "Content-Type: text/plain" ; end myHello
--
-- Public API: oxhInit / oxhServe / oxhSetRoot / oxhServeFiles / oxhRoute /
-- oxhUnroute / oxhReply / oxhStop.
-- It composes OnionXT (ox*); it adds no cryptography and owns no long-lived socket
-- of its own (OnionXT does). Public API `oxhCamelCase`, matching the family style.

constant kOxhCloseDelay = 500     -- ms to let the response flush before closing
constant kOxhMaxRequest = 262144  -- refuse a request head bigger than 256 KB (abuse guard)

local sOxhRoot        -- static-file root folder, or empty
local sOxhAutoIndex   -- true: auto-generate a directory-listing page for folders
local sOxhRoutes      -- array: (METHOD & space & path) -> handler name
local sOxhReq         -- array: stream handle -> accumulated request bytes
local sOxhServed      -- array: stream handle -> true once answered
local sOxhOwner       -- object whose script holds the route handlers

-- ==========================================================================
-- Public API
-- ==========================================================================

command oxhInit pOwner
   -- Remember where the app's route handlers live (default: the topStack).
   put pOwner into sOxhOwner
end oxhInit

command oxhServe pVirtualPort, pLocalPort
   -- Publish an onion and serve HTTP on it via OnionXT's accept loop (OnionXT owns
   -- the socket and rejects non-loopback peers - the proven path). Point OnionXT's
   -- peer callback at this module first, then create the service. Reports the
   -- service handle through `the result` (an integer on success).
   oxSetPeerCallback "oxhPeer"
   oxCreateService pVirtualPort, pLocalPort
   return the result
end oxhServe

command oxhSetRoot pFolder
   -- Static-site mode: serve files from pFolder ("/" maps to /index.html); a folder
   -- with no index.html is a 404 (no directory listing - the safe default for a
   -- site). Empty disables static serving.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put false into sOxhAutoIndex
end oxhSetRoot

command oxhServeFiles pFolder
   -- File-sharing mode: serve every file under pFolder by path AND auto-generate a
   -- directory-listing page (names and download links; no sizes, because
   -- `the detailedFiles` is an OXT compile-time bad factor) for "/" and each
   -- subfolder, so a visitor can browse and download without you writing an index.
   -- A folder's own index.html, if present, still takes precedence over the listing.
   put oxhStripTrailingSlash(pFolder) into sOxhRoot
   put true into sOxhAutoIndex
end oxhServeFiles

command oxhRoute pMethod, pPath, pHandler
   -- Register a dynamic route (exact path match in v1). pHandler is a command in
   -- the owner's script, called as: pHandler pStream, pRequest.
   put pHandler into sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhRoute

command oxhUnroute pMethod, pPath
   -- Remove a route registered with oxhRoute. Lets an app switch what a path serves
   -- at runtime (e.g. drop the "/" route so a shared folder's listing shows there
   -- instead). Removing an unregistered route is a harmless no-op.
   delete variable sOxhRoutes[toUpper(pMethod) & space & pPath]
end oxhUnroute

command oxhStop pService
   -- Tear down one served onion (DEL_ONION + stop OnionXT's listener).
   oxRemoveService pService
end oxhStop

command oxhReply pStream, pCode, pBodyText, pHeaders
   -- Send a text response (HTML, JSON, plain) from a route handler. pBodyText is
   -- TEXT; it is UTF-8 encoded and its exact byte length becomes Content-Length.
   oxhSendBytes pStream, pCode, textEncode(pBodyText, "UTF-8"), pHeaders
end oxhReply

-- ==========================================================================
-- OnionXT callbacks (public: reached through the message path). OnionXT has
-- already enforced loopback before oxhPeer fires.
-- ==========================================================================

command oxhPeer pStream, pService, pPeerAddr
   oxSetStreamCallback pStream, "oxhStream"
   put empty into sOxhReq[pStream]
   put false into sOxhServed[pStream]
end oxhPeer

command oxhStream pStream, pEvent, pData
   if pEvent is "data" then
      if sOxhServed[pStream] is true then
         exit oxhStream           -- already answered; ignore the rest of the request
      end if
      put pData after sOxhReq[pStream]
      if the number of bytes of sOxhReq[pStream] > kOxhMaxRequest then
         put true into sOxhServed[pStream]
         delete variable sOxhReq[pStream]     -- free the buffer now; do not hold it
         oxhSendBytes pStream, 413, textEncode("Request too large", "UTF-8"), "Content-Type: text/plain"
         exit oxhStream
      end if
      if oxhRequestComplete(sOxhReq[pStream]) then
         put true into sOxhServed[pStream]
         oxhHandle pStream, sOxhReq[pStream]
         delete variable sOxhReq[pStream]
      end if
   else if pEvent is "closed" or pEvent is "error" then
      delete variable sOxhReq[pStream]
      delete variable sOxhServed[pStream]
   end if
end oxhStream

-- ==========================================================================
-- Request framing and parsing. Byte discipline on the raw request; text ops only
-- on the decoded (ASCII) header block.
-- ==========================================================================

private function oxhHeaderEnd pData
   -- 1-indexed byte position of the first CR of the CRLFCRLF that ends the header
   -- block, or 0 if not present yet. No char/line on binary (gotcha): scan bytes.
   -- Bytes go into locals so the match is a single-line `if` (the static gate does
   -- not join `\` continuations, and a long condition would look unbalanced).
   local tN, tI, tB1, tB2, tB3, tB4
   put the number of bytes of pData into tN
   if tN < 4 then
      return 0
   end if
   repeat with tI = 1 to tN - 3
      put byteToNum(byte tI of pData) into tB1
      if tB1 is 13 then
         put byteToNum(byte (tI + 1) of pData) into tB2
         put byteToNum(byte (tI + 2) of pData) into tB3
         put byteToNum(byte (tI + 3) of pData) into tB4
         if tB2 is 10 and tB3 is 13 and tB4 is 10 then
            return tI
         end if
      end if
   end repeat
   return 0
end oxhHeaderEnd

private function oxhRequestComplete pData
   local tHeadEnd, tHeaders, tContentLen, tBodyStart, tHave
   put oxhHeaderEnd(pData) into tHeadEnd
   if tHeadEnd is 0 then
      return false             -- headers not fully received yet
   end if
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   put tHeaders["content-length"] into tContentLen
   if tContentLen is empty or tContentLen is not an integer then
      return true              -- no declared body (typical GET)
   end if
   put tHeadEnd + 4 into tBodyStart
   put (the number of bytes of pData) - tBodyStart + 1 into tHave
   return (tHave >= tContentLen)
end oxhRequestComplete

private function oxhParseHeaders pHeaderBytes
   -- pHeaderBytes is the ASCII header block (request line + header lines, no body).
   -- Returns an array: lowercased header names -> values, plus __method / __path /
   -- __query / __resource from the request line. Save and restore the delimiters.
   local tText, tSavedLD, tSavedID, tReqLine, tRes, tI, tLine, tColon, tName, tValue, tOut
   put textDecode(pHeaderBytes, "UTF-8") into tText     -- headers are ASCII
   put the lineDelimiter into tSavedLD
   put the itemDelimiter into tSavedID
   set the lineDelimiter to (numToChar(13) & numToChar(10))
   put line 1 of tText into tReqLine
   put word 1 of tReqLine into tOut["__method"]
   put word 2 of tReqLine into tOut["__resource"]
   set the itemDelimiter to "?"
   put item 1 of tOut["__resource"] into tOut["__path"]
   if the number of items of tOut["__resource"] > 1 then
      put item 2 to -1 of tOut["__resource"] into tOut["__query"]
   end if
   repeat with tI = 2 to the number of lines of tText
      put line tI of tText into tLine
      if tLine is empty then
         next repeat
      end if
      put offset(":", tLine) into tColon
      if tColon > 1 then
         put toLower(oxhTrim(char 1 to (tColon - 1) of tLine)) into tName
         put oxhTrim(char (tColon + 1) to -1 of tLine) into tValue
         -- "__" IS OUR RESERVED PSEUDO-FIELD NAMESPACE, and until 2026-08-19
         -- a client could write into it. The request line is parsed ABOVE, so
         -- __method / __path / __query / __resource are already in this array
         -- when the header loop starts - and this line put an attacker-chosen
         -- name straight into the same array. A request carrying a header
         -- literally named `__path` therefore REPLACED the parsed path, which
         -- oxhHandle then uses both to select a route and as the argument to
         -- oxhServeStatic. On an inbound path reachable by anyone who has the
         -- onion address. (__body was never exposed: oxhHandle writes it after
         -- this parse returns, so it overwrote the client's value rather than
         -- the other way round - which is luck, not design.)
         --
         -- nocloud's qsHttpParseHead has carried this exact guard since it was
         -- written, in the same words. Real HTTP header names never begin
         -- "__", so refusing them costs nothing.
         if tName begins with "__" then
            next repeat
         end if
         put tValue into tOut[tName]
      end if
   end repeat
   set the lineDelimiter to tSavedLD
   set the itemDelimiter to tSavedID
   return tOut
end oxhParseHeaders

-- ==========================================================================
-- Routing: a registered route, else a static file, else 404.
-- ==========================================================================

private command oxhHandle pStream, pData
   local tHeadEnd, tHeaders, tKey, tBodyStart, tContentLen, tBodyEnd
   put oxhHeaderEnd(pData) into tHeadEnd
   put oxhParseHeaders(byte 1 to (tHeadEnd - 1) of pData) into tHeaders
   -- Attach the raw body bytes for a POST handler, CAPPED to the declared
   -- Content-Length. Without the cap, trailing or pipelined bytes in the same read
   -- would bleed into __body and a form/upload route would parse the next request
   -- as part of this body.
   put tHeadEnd + 4 into tBodyStart
   put tHeaders["content-length"] into tContentLen
   if tContentLen is an integer and tContentLen > 0 and (the number of bytes of pData) >= tBodyStart then
      put tBodyStart + tContentLen - 1 into tBodyEnd
      if tBodyEnd > the number of bytes of pData then
         put the number of bytes of pData into tBodyEnd   -- defensive clamp
      end if
      put byte tBodyStart to tBodyEnd of pData into tHeaders["__body"]
   else
      put empty into tHeaders["__body"]
   end if
   put toUpper(tHeaders["__method"]) & space & tHeaders["__path"] into tKey
   if sOxhRoutes[tKey] is not empty then
      dispatch sOxhRoutes[tKey] to oxhOwnerObject() with pStream, tHeaders
      exit oxhHandle
   end if
   if sOxhRoot is not empty and tHeaders["__method"] is "GET" then
      oxhServeStatic pStream, tHeaders["__path"]
      exit oxhHandle
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhHandle

private command oxhServeStatic pStream, pRawPath
   local tPath, tFile, tIndex
   put urlDecode(pRawPath) into tPath        -- %20 etc. -> real chars for disk mapping
   if tPath is empty then
      put "/" into tPath
   end if
   -- Path-traversal guard AFTER decoding (catches %2e%2e), before touching disk.
   if ".." is in tPath then
      oxhSendBytes pStream, 403, textEncode("Forbidden", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhServeStatic
   end if
   put sOxhRoot & tPath into tFile
   if there is a folder tFile then
      -- A folder URL must end in "/" so relative links in the listing resolve;
      -- redirect if it does not (send the browser back with the slash added).
      if the last char of tPath is not "/" then
         oxhSendBytes pStream, 301, empty, "Location: " & pRawPath & "/"
         exit oxhServeStatic
      end if
      put tFile & "index.html" into tIndex    -- tFile ends with "/" here
      if there is a file tIndex then
         oxhSendFile pStream, tIndex, "index.html"
      else if sOxhAutoIndex is true then
         oxhSendBytes pStream, 200, textEncode(oxhListingHtml(tFile, tPath), "UTF-8"), "Content-Type: text/html; charset=utf-8"
      else
         oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      end if
      exit oxhServeStatic
   end if
   if there is a file tFile then
      oxhSendFile pStream, tFile, tPath
      exit oxhServeStatic
   end if
   oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
end oxhServeStatic

private command oxhSendFile pStream, pDiskPath, pForMime
   -- Read a file as bytes and serve it with a MIME type from pForMime's extension.
   local tContent
   put url ("binfile:" & pDiskPath) into tContent
   if the result is not empty then
      oxhSendBytes pStream, 404, textEncode("Not found", "UTF-8"), "Content-Type: text/plain; charset=utf-8"
      exit oxhSendFile
   end if
   oxhSendBytes pStream, 200, tContent, "Content-Type: " & oxhMimeType(pForMime)
end oxhSendFile

private function oxhListingHtml pDiskFolder, pUrlPath
   -- Build a directory-listing page for pDiskFolder (a disk path ending in "/"),
   -- served at pUrlPath (a URL path ending in "/"). Uses `the files` / `the folders`
   -- (portable; `the detailedFiles` is not recognized on every OXT engine and is a
   -- compile-time "bad factor" there). Names are HTML-escaped (a file named
   -- "<script>" cannot inject) and path-encoded for the hrefs; links are relative
   -- to pUrlPath, so a subfolder link browses in and ".." goes up.
   local tSaved, tFiles, tFolders, tName, tOut
   put the defaultFolder into tSaved
   set the defaultFolder to pDiskFolder
   put the files into tFiles
   put the folders into tFolders
   set the defaultFolder to tSaved
   put "<!doctype html><html><head><meta charset='utf-8'><title>Shared files</title>" into tOut
   put "<style>body{font-family:system-ui,sans-serif;max-width:44em;margin:2em auto;padding:0 1em}h1{font-size:1.2em}ul{list-style:none;padding:0}li{padding:.3em 0;border-bottom:1px solid #eee}a{text-decoration:none}</style>" after tOut
   put "</head><body><h1>Shared files: " & oxhHtmlEscape(pUrlPath) & "</h1><ul>" after tOut
   if pUrlPath is not "/" then
      put "<li><a href='../'>.. (up)</a></li>" after tOut
   end if
   repeat for each line tName in tFolders
      if tName is "." or tName is ".." then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "/'>" & oxhHtmlEscape(tName) & "/</a></li>" after tOut
   end repeat
   repeat for each line tName in tFiles
      if tName is empty then
         next repeat
      end if
      put "<li><a href='" & oxhPathEncode(tName) & "'>" & oxhHtmlEscape(tName) & "</a></li>" after tOut
   end repeat
   put "</ul></body></html>" after tOut
   return tOut
end oxhListingHtml

-- ==========================================================================
-- Response building. The proven demo pattern: exact BYTE Content-Length,
-- Connection: close, then a delayed close so the write flushes cleanly.
-- ==========================================================================

private command oxhSendBytes pStream, pCode, pBodyBytes, pHeaders
   local tCrlf, tResp
   put (numToChar(13) & numToChar(10)) into tCrlf
   put "HTTP/1.1 " & pCode & space & oxhReason(pCode) & tCrlf into tResp
   if pHeaders is not empty then
      put oxhNormalizeHeaders(pHeaders) after tResp
   end if
   put "Content-Length: " & (the number of bytes of pBodyBytes) & tCrlf after tResp
   put "Connection: close" & tCrlf after tResp
   put tCrlf after tResp
   oxWrite pStream, (textEncode(tResp, "UTF-8") & pBodyBytes)
   send ("oxhClose " & pStream) to me in kOxhCloseDelay milliseconds
end oxhSendBytes

command oxhClose pStream
   -- Deferred, idempotent close of a served connection (public: reached via send).
   -- Clear BOTH per-stream tables here as the catch-all: oxCloseStream removes the
   -- OnionXT stream, so no later socketClosed/"closed" event will arrive to clean
   -- the HTTP state, and every response path (200/404/413/301/...) routes through
   -- oxhSendBytes which schedules this. A double-delete on the normal path is a
   -- harmless no-op.
   oxCloseStream pStream
   delete variable sOxhReq[pStream]
   delete variable sOxhServed[pStream]
end oxhClose

private function oxhNormalizeHeaders pHeaders
   -- Turn caller headers ("Name: value", LF- or CRLF-separated) into CRLF lines,
   -- dropping any Content-Length / Connection (this module sets those).
   local tCrlf, tSaved, tI, tLine, tOut, tLow
   put (numToChar(13) & numToChar(10)) into tCrlf
   put the lineDelimiter into tSaved
   set the lineDelimiter to lf
   put empty into tOut
   repeat with tI = 1 to the number of lines of pHeaders
      put line tI of pHeaders into tLine
      if the last char of tLine is (numToChar(13)) then
         delete the last char of tLine   -- tolerate CRLF-separated input
      end if
      if tLine is empty then
         next repeat
      end if
      put toLower(tLine) into tLow
      if tLow begins with "content-length" or tLow begins with "connection" then
         next repeat
      end if
      put tLine & tCrlf after tOut
   end repeat
   set the lineDelimiter to tSaved
   return tOut
end oxhNormalizeHeaders

-- ==========================================================================
-- Small helpers.
-- ==========================================================================

private function oxhMimeType pPath
   local tSaved, tExtn
   put the itemDelimiter into tSaved
   set the itemDelimiter to "."
   put toLower(the last item of pPath) into tExtn
   set the itemDelimiter to tSaved
   if tExtn is "html" or tExtn is "htm" then
      return "text/html; charset=utf-8"
   else if tExtn is "css" then
      return "text/css; charset=utf-8"
   else if tExtn is "js" then
      return "application/javascript; charset=utf-8"
   else if tExtn is "json" then
      return "application/json; charset=utf-8"
   else if tExtn is "txt" then
      return "text/plain; charset=utf-8"
   else if tExtn is "png" then
      return "image/png"
   else if tExtn is "jpg" or tExtn is "jpeg" then
      return "image/jpeg"
   else if tExtn is "gif" then
      return "image/gif"
   else if tExtn is "svg" then
      return "image/svg+xml"
   else if tExtn is "ico" then
      return "image/x-icon"
   else if tExtn is "wasm" then
      return "application/wasm"
   else if tExtn is "pdf" then
      return "application/pdf"
   end if
   return "application/octet-stream"
end oxhMimeType

private function oxhReason pCode
   if pCode is 200 then
      return "OK"
   else if pCode is 204 then
      return "No Content"
   else if pCode is 301 then
      return "Moved Permanently"
   else if pCode is 302 then
      return "Found"
   else if pCode is 400 then
      return "Bad Request"
   else if pCode is 403 then
      return "Forbidden"
   else if pCode is 404 then
      return "Not Found"
   else if pCode is 405 then
      return "Method Not Allowed"
   else if pCode is 413 then
      return "Payload Too Large"
   else if pCode is 500 then
      return "Internal Server Error"
   end if
   return "OK"
end oxhReason

private function oxhTrim pText
   -- Strip leading/trailing spaces and tabs. Guard the empty-string-is-in trap.
   local tOut, tTab
   put pText into tOut
   put numToChar(9) into tTab
   repeat while tOut is not empty and (the first char of tOut is space or the first char of tOut is tTab)
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut is space or the last char of tOut is tTab)
      delete the last char of tOut
   end repeat
   return tOut
end oxhTrim

private function oxhOwnerObject
   if sOxhOwner is not empty then
      return sOxhOwner
   end if
   return the topStack
end oxhOwnerObject

private function oxhStripTrailingSlash pFolder
   local tOut
   put pFolder into tOut
   if tOut is not empty and (the last char of tOut is "/" or the last char of tOut is "\") then
      delete the last char of tOut
   end if
   return tOut
end oxhStripTrailingSlash

private function oxhPathEncode pName
   -- Encode a name for a URL PATH segment. urlEncode uses "+" for space (form
   -- style); a path wants "%20", so fix that up.
   local tEnc
   put urlEncode(pName) into tEnc
   replace "+" with "%20" in tEnc
   return tEnc
end oxhPathEncode

private function oxhHtmlEscape pText
   -- Escape a value for HTML text/attribute context so a crafted file name cannot
   -- inject markup. `&` first, then the rest.
   local tOut
   put pText into tOut
   replace "&" with "&amp;" in tOut
   replace "<" with "&lt;" in tOut
   replace ">" with "&gt;" in tOut
   replace quote with "&quot;" in tOut
   return tOut
end oxhHtmlEscape

-- <<< END EMBEDDED LIBRARIES <<<

constant kPollMs = 250
constant kPollLiveMs = 33
constant kPaintMs = 250
constant kDhtWaitMs = 25000
constant kWalkMax = 12
constant kNameMax = 64
-- phase 6 (LAN): the device-mesh port and a u32 protocol tag the enConnect
-- rider carries, so a mismatched app is refused before the crypto handshake
constant kLanPort = 27099
constant kLanProto = 1
-- phase 6 sync cadence: draft edits are read on the poll timer and
-- broadcast at most once per debounce window (never per keystroke);
-- presence is ABSOLUTE state re-asserted on a cadence (channel 1 is
-- deliberately droppable, so it must be re-assertable), and a peer whose
-- presence goes quiet paints as such instead of lying fresh
constant kLanDraftDebounceMs = 900
constant kLanPresenceMs = 1000
constant kLanPresenceStaleMs = 5000
constant kLanTypingMs = 3000
-- phase 7 (anon persona): the onion's virtual + local forward ports
constant kAnonVirtualPort = 80
constant kAnonLocalPort = 8734
-- phase 5 (live sessions): the ICE server for the dc call. STUN only - a
-- TURN relay is a deliberate non-goal for the demo (spec 6); two peers
-- that need one will fail visibly instead of relaying silently.
constant kDmIce = "stun:stun.l.google.com:19302"
-- the intro freshness window (seconds either way): rsVerifyIntro leaves
-- timestamp policy to the app, and this is the app's policy - a captured
-- sealed intro replayed later is refused with its age named, bounding the
-- replay surface the recipient-binding already narrows
constant kDmIntroWindow = 600
-- phase 5 typing lane (spec 6.2): a SECOND dc channel opened at call
-- setup - unordered, maxRetransmits 0, deliberately lossy - carrying
-- ABSOLUTE typing state ("1"/"0"), re-sent on a cadence and expired
-- locally so a dropped "0" cannot stick
constant kDcTypingLabel = "riptide-typing"
constant kDcTypingMs = 3000
constant kDcTypingSendMs = 1000
-- the Play-now floor: the fraction of the FILE whose contiguous front must
-- be on disk before the demo hands it to a player (see raMediaFrontReady)
constant kRaPlayFloor = 0.05
-- bumped on any layout change so an existing stack rebuilds (the kit builders
-- re-rect existing controls by name, so no deletion pass is needed)
constant kRaUiVersion = "ra-ui-720p-9"

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

-- ---- state -------------------------------------------------------------------
local sCaps            -- rsProbeCapabilities() array, probed once at open
local sHaveLib         -- "true" once the riptide library answered at all
local sSession         -- THE TorrentXT session handle; this app owns it
local sIdSeed          -- identity seed Data(32) while unlocked (the keyring)
local sHandle          -- the identity's 64-hex public key
local sOnion           -- the identity as .onion (empty without a SHA3 provider)
local sSeq             -- monotonic head sequence (recovered from our own head)
local sMyLatest        -- our latest post's 40-hex target, or empty
local sPolling         -- "true" while the pump chain is armed
local sPaintAt         -- ms of the last UI repaint tier (kPaintMs gate)
local sAwaitOwn        -- "true" while our own head lookup is in flight
local sFollowHandle    -- the author a fetch is walking
local sAwaitHead       -- "true" while their head lookup is in flight
local sWalkNext        -- the post target the walk is waiting on, or empty
local sWalkCount       -- posts verified so far in this walk
local sWaitUntil       -- ms deadline for the outstanding DHT request
local sPendingMediaPath -- file waiting to ride the NEXT post (phase 3)
local sMediaWatch      -- torrent handle of the media item the strip watches
-- the kind-C reassembly walk (backlog A2, 2026-08-23): the demo holds
-- ONE reassembly at a time (the one-conversation precedent) and fetches
-- its parts through the same one-immutable-await discipline as the chain
-- walk; a second chunked post keeps its honest placeholder
local sChunkTargets    -- the pending kind-C post's chunk list (comma)
local sChunkNext       -- the chunk target currently awaited, or empty
local sChunkParts      -- target -> verified chunk bytes (rsIngestBlob)
local sChunkPostNum    -- the walk ordinal the reassembly reports under
-- the spec-4.1 profileMeta READER (remaining-work A.9, 2026-08-23): a
-- verified head names a display-name blob; fetch it, verify it by
-- content address, and show the name - degrading honestly when absent
local sProfileNext     -- the feed walk's awaited profile target, or empty
local sDmProfileNext   -- the DM head's awaited profile target, or empty
-- phase 4 (DMs). The demo holds ONE conversation at a time, loudly: the
-- library supports any number, but a first pass a maintainer can verify on
-- two machines beats a chat manager nobody has run.
local sDmSeed          -- the DM subkey Data(32) while unlocked
local sDmKeys          -- rsDmKeys array (kx publicKey/secretKey/publicKeyHex)
local sMyPrekeyTarget  -- where my RSK1 prekey record lives (40 hex)
local sDmInbox         -- torrent handle of MY inbox phantom swarm
local sDmTheirInbox    -- torrent handle of the OUTBOUND target's inbox swarm
local sDmTarget        -- the handle I am dialing (outbound), or empty
local sDmTargetKx      -- their VERIFIED prekey kx public (64 hex)
local sDmAwaitDmHead   -- "true" while the outbound head lookup is in flight
local sDmAwaitPrekey   -- the 40-hex prekey target awaited, or empty
local sDmTheirHandle   -- per-peer: the authenticated handle behind an rp1 peer
local sDmRxKey         -- per-peer: session receive key
local sDmTxKey         -- per-peer: session transmit key
local sDmPush          -- per-peer: secretstream push handle (my outbound)
local sDmPull          -- per-peer: secretstream pull handle (their inbound)
local sDmActivePeer    -- the rp1 peer id of the live conversation, or empty
-- phase 6 (LAN device mesh). The master seed is retained while unlocked
-- (the spec's one-keyring pattern: it reconstructs every subkey on demand -
-- the LAN and anon rails both need it), cleared on Lock/close.
local sMasterSeed      -- the 32-byte master while unlocked (the keyring)
local sLanHost         -- the enet host handle (server or client), or empty
local sLanIsServer     -- "true" when hosting the mesh
local sLanName         -- this device's name in the mesh
local sLanServerPeer   -- a client's peer handle to the host
local sLanChallenges   -- server: peer id -> the challenge bytes I sent it
local sLanMyResponse   -- joiner: the response I sent (the welcome binds to it)
local sLanDevices      -- peer id -> the admitted device name
local sLanInit         -- "true" once enInitialize succeeded (teardown guard)
-- phase 6 sync state. My side: the per-device counters are seeded from
-- the clock at Host/Join so a leave-and-rejoin still moves strictly
-- forward (the receivers' monotonic apply demands it; the phase-3
-- clock-salt precedent).
--
-- THEIR side is keyed by the SIGNING DEVICE NAME, not by the enet peer,
-- and that is the whole correctness of a mesh with more than two devices.
-- The mesh is hub-and-spoke: the host RELAYS every verified record to the
-- other admitted peers, so on a JOINER every device's record arrives over
-- the ONE peer that is the host. Keyed by peer, three devices' interleaved
-- seq counters - each seeded independently from `the seconds` - would
-- fight over one slot and the sequence guard would drop most of them
-- SILENTLY (its drop path is a deliberate silent exit, so nothing would be
-- logged), and the Devices panel, which paints from the admitted peers,
-- would never show a relayed device at all. The name is INSIDE the signed
-- span and read only after the signature verdict, and the library states
-- the contract at rsLanBuildDraft: apply only a seq strictly above the
-- last one applied FOR THAT DEVICE. It is deliberately not a per-device
-- IDENTITY - all your devices derive ONE LAN keypair, so any admitted
-- device can sign any name - but that is the recorded threat model (these
-- are your own devices), not a hole this keying opens.
local sLanSeq          -- my draft seq (monotonic per device)
local sLanTick         -- my presence tick (monotonic per device)
local sLanDraftLast    -- the draft text last BROADCAST (convergence compare)
local sLanDraftSeen    -- the draft text last SEEN by the tick (typing edge)
local sLanDraftNextOk  -- ms gate: the earliest next draft broadcast
local sLanPresenceAt   -- ms of my last presence broadcast
local sLanTypingUntil  -- ms deadline while my draft edits count as typing
local sLanFeedLast     -- the feed seq last broadcast (send only on change)
local sLanPeerSeq      -- device name -> highest draft seq applied
local sLanPeerDraft    -- device name -> that device's latest draft text
local sLanPeerTick     -- device name -> highest presence tick applied
local sLanPeerTyping   -- device name -> "true" while that device is typing
local sLanPeerSeen     -- device name -> ms of its last applied presence
-- ...and the one thing that still has to be per PEER: which device names
-- reached us over which enet link, so a disconnect drops exactly the state
-- that link fed us (on a host that is the one device it admitted; on a
-- joiner the host's link fed us every relayed device, and losing the host
-- loses all of them). Nested array, name -> "true", the set-of-names idiom
local sLanPeerNames    -- peer id -> array of device names it contributed
-- the channel-0 media handoff (the channel-2 decision: a signed POINTER
-- at the phase-3 torrent path; the offer outlives the mesh because the
-- swarm does - only the per-device replay tracking dies with its link)
local sLanPeerMediaSeq -- device name -> highest handoff seq applied
local sLanMediaHash    -- the latest verified offer's 40-hex info-hash
local sLanMediaName    -- ...its file leaf name (display only)
local sLanMediaSize    -- ...its claimed size in bytes (display only)
local sLanMediaFrom    -- ...the offering device's name
local sLanMediaWatch   -- torrent handle the Devices card strip watches
-- phase 7 (anon persona). A separate onion-only identity; the guard keeps
-- it from ever touching the DHT, a torrent, or rp1 (spec 9.3).
local sAnonService     -- the onionxt service handle while published, or empty
-- 8.2/8.3 serving state: the payloads are built ONCE at publish time (the
-- route handlers reply from these locals, never from a field read at
-- request time - a request must not depend on which card is open)
local sAnonPage        -- the served feed page (UTF-8 Data) while serving
local sAnonPrekeyBody  -- the served /prekey hex text while serving
local sAnonServing     -- "true" once the oxh* routes are registered
-- phase 5 (live sessions). ONE call at a time, riding the ACTIVE DM
-- conversation: the SDP offer/answer travel as kind-"O"/"A" messages
-- inside the established secretstream (the phase-4 rail), then the dc
-- channel is direct peer-to-peer.
local sDcInit          -- "true" once dcInit succeeded (teardown guard)
local sDcPeer          -- the dc peer handle while a call exists, or empty
local sDcChannel       -- the call's data-channel handle once known
local sDcAwaitLocal    -- "O"/"A" while waiting to ship our local SDP
-- the phase-5 typing lane (spec 6.2): a second, lossy dc channel
local sDcTypingChan    -- the typing channel handle once known, or empty
local sDcTypingSeen    -- the compose text at the last pump look
local sDcTypingUntil   -- ms deadline while my compose edits count as typing
local sDcTypingSent    -- the state last sent ("1"/"0")
local sDcTypingSentAt  -- ms of my last typing-state send
local sDcPeerTyping    -- "true" while the far side reports typing
local sDcPeerTypingAt  -- ms of the far side's last "typing" report

-- ---- lifecycle ---------------------------------------------------------------
on openStack
   raBuild
   raProbe
   -- LAST: the check reads the state the handlers above establish.
   raScRun
end openStack

on closeStack
   local tErr
   put empty into sPolling
   raDmTeardown
   raLanLeave
   raAnonStop
   if sSession is an integer and sSession > 0 then
      try
         btStopSession sSession
      catch tErr
         -- extension gone or session already dead; nothing to release
      end try
   end if
   -- the one mandatory enet teardown: destroys any surviving host and
   -- releases the socket layer. Bare command form, guarded so a missing
   -- extension cannot throw out of closeStack.
   if sLanInit is "true" then
      try
         enDeinitialize
      catch tErr
         -- extension not installed; nothing to release
      end try
      put empty into sLanInit
   end if
   -- and datachannelxt's mandatory quit call - BARE, never dcCleanup():
   -- the parenthesised statement spelling is the one-line bug that once
   -- took a whole 4400-line paste down (the suite CLAUDE.md story)
   if sDcInit is "true" then
      try
         dcCleanup
      catch tErr
         -- extension not installed; nothing to release
      end try
      put empty into sDcInit
   end if
   put empty into sSession
   put empty into sDmInbox
   put empty into sDmTheirInbox
   put empty into sMediaWatch
   put empty into sPendingMediaPath
   raClearKeys
end closeStack

on mouseUp
   switch the short name of the target
      case "raCreate"
         raCreate
         break
      case "raUnlock"
         raUnlock
         break
      case "raLock"
         raLock
         break
      case "raPost"
         raPost
         break
      case "raAttach"
         raAttach
         break
      case "raFetch"
         raFetch
         break
      case "raMediaGet"
         raMediaGet
         break
      case "raGoDm"
         go to card "raMessages"
         break
      case "raGoFeed"
         go to card 1
         break
      case "raGoLanFromFeed"
         go to card "raDevices"
         break
      case "raGoFeedFromLan"
         go to card 1
         break
      case "raLanHostBtn"
         raLanHost
         break
      case "raLanJoinBtn"
         raLanJoin
         break
      case "raLanLeaveBtn"
         raLanLeave
         break
      case "raLanSendMedia"
         raLanSendMedia
         break
      case "raLanMediaGet"
         raLanMediaGet
         break
      case "raGoAnonFromFeed"
         go to card "raAnon"
         break
      case "raGoFeedFromAnon"
         go to card 1
         break
      case "raAnonReveal"
         raAnonReveal
         break
      case "raAnonPublishBtn"
         raAnonPublish
         break
      case "raAnonStopBtn"
         raAnonStop
         break
      case "raDmStart"
         raDmStart
         break
      case "raDmSend"
         raDmSend
         break
      case "raDmCallBtn"
         raDmCall
         break
      default
         pass mouseUp
   end switch
end mouseUp

-- ---- self-building UI (idempotent; the kit owns the look) --------------------
-- Four CARDS since phases 5-7 landed (the spec's one-stack-rails-behind-
-- tabs answer): card 1 is the feed (phases 1-3), card "raMessages" the
-- DM + call rail (phases 4-5), card "raDevices" the LAN mesh (phase 6),
-- card "raAnon" the persona (phase 7). The stack script owns every
-- handler, so navigation is just `go to card`; the pump keeps running
-- wherever you are.
command raBuild
   if the uUiVersion of this stack is kRaUiVersion then
      exit raBuild
   end if
   lock screen
   raBuildFeedCard
   raBuildDmCard
   raBuildLanCard
   raBuildAnonCard
   go to card 1
   set the uUiVersion of this stack to kRaUiVersion
   unlock screen
end raBuild

command raBuildFeedCard
   go to card 1
   -- two columns inside the family's 720p budget (1200 x 640, the
   -- check-stack-size.py cap): identity + my feed left, the reading pane right
   uiChrome "Riptide Social - identity + public feed + media (phases 1-4)", 1200, 640
   uiButton "raGoDm", "Messages >", "1080,4,1192,26"
   uiButton "raGoLanFromFeed", "Devices >", "968,4,1074,26"
   uiButton "raGoAnonFromFeed", "Anon >", "872,4,962,26"

   -- 1. identity
   uiSection "raSec1", "1. Identity: one sealed seed, two spellings of one key", "16,58,592,76"
   uiLabel "raIdL1", "key file:", "16,80,90,98", 11
   uiInput "raKeyFile", "94,80,440,100"
   put raKeyPath() into field "raKeyFile"
   uiButton "raCreate", "Create", "446,80,592,104"
   uiLabel "raIdL2", "passphrase:", "16,104,90,122", 11
   uiInput "raPassphrase", "94,104,440,124"
   uiButton "raUnlock", "Unlock", "446,108,516,132"
   uiButton "raLock", "Lock", "524,108,592,132"
   uiArea "raIdOut", "16,130,592,240"

   -- 2. my feed
   uiSection "raSec2", "2. My feed: post, then the signed head republishes", "16,246,592,264"
   uiLabel "raNameL", "display name:", "16,268,110,286", 11
   uiInput "raName", "114,268,340,288"
   put "riptide user" into field "raName"
   uiInput "raCompose", "16,292,440,340"
   uiButton "raPost", "Post", "446,292,592,316"
   uiButton "raAttach", "Attach", "446,320,592,340"
   uiArea "raMyFeed", "16,346,592,562"

   -- 3. follow
   uiSection "raSec3", "3. Follow: fetch a head, walk the chain, verify every signature", "608,58,1184,76"
   uiLabel "raHandleL", "author handle (64 hex):", "608,80,772,98", 11
   uiInput "raHandle", "776,80,1050,100"
   uiButton "raFetch", "Fetch feed", "1056,80,1184,104"
   uiArea "raTheirFeed", "608,110,1184,508"

   -- the phase-3 media strip: a walked post auto-fills the hash; Fetch
   -- joins the swarm sequentially, and the button becomes Play the moment
   -- the on-disk file is openable (mid-download, by design)
   uiLabel "raMediaL", "media hash:", "608,514,694,532", 11
   uiInput "raMediaHash", "698,514,1050,534"
   uiButton "raMediaGet", "Fetch + play", "1056,510,1184,534"
   uiCap "raMediaProg", empty, "608,540,1184,566"

   uiFooter \
         "Phases 1-3: public feeds are public, the DHT keeps records" \
         & " until expiry, nothing here is deletion or anonymity - and" \
         & " media rides ordinary BitTorrent swarms, so seeding or" \
         & " fetching shows your IP to its peers. While unlocked, the" \
         & " identity seed lives in unlocked engine memory: Lock when" \
         & " done, and never reuse a real passphrase in a demo. Phase 3 is" \
         & " done when a follower on a SECOND machine plays a video" \
         & " mid-download.", \
         "16,572,1184,632"
end raBuildFeedCard

command raBuildDmCard
   if there is no card "raMessages" then
      create card
      set the name of this card to "raMessages"
   end if
   go to card "raMessages"
   uiChrome "Riptide Social - Messages (phase 4: encrypted DMs over rp1)", 1200, 640
   uiButton "raGoFeed", "< Feed", "1080,4,1192,26"

   uiSection "raDmSec1", "1. My inbox: the phantom swarm strangers reach you in", "16,58,592,76"
   uiCap "raDmMine", "Unlock on the Feed card first; the inbox derives from your identity.", "16,82,592,124"
   uiArea "raDmLog", "16,130,592,562"

   uiSection "raDmSec2", "2. Conversation: sealed first contact, then a private stream", "608,58,1184,76"
   uiLabel "raDmToL", "to handle (64 hex):", "608,80,748,98", 11
   uiInput "raDmTo", "752,80,1050,100"
   uiButton "raDmStart", "Start DM", "1056,80,1116,104"
   uiButton "raDmCallBtn", "Call", "1122,80,1184,104"
   uiArea "raDmChat", "608,110,1184,498"
   uiInput "raDmMsg", "608,506,1050,528"
   uiButton "raDmSend", "Send", "1056,504,1184,528"
   -- the phase-5 typing lane paints here during a call (spec 6.2):
   -- absolute state over a second, deliberately lossy dc channel
   uiCap "raDmTyping", empty, "608,534,1184,560"

   uiFooter \
         "DMs are end-to-end encrypted (a sealed RSI1 intro, then a" \
         & " secretstream in each direction) - but rp1 peers see your IP," \
         & " exactly as any torrent peer does, and this demo holds ONE" \
         & " conversation at a time. Sessions live in memory only: Lock" \
         & " or close ends them, there is no history. During a call a" \
         & " second lossy dc channel carries live typing state (spec" \
         & " 6.2). Phase 4 is done when TWO machines exchange" \
         & " authenticated encrypted DMs with no server.", \
         "16,572,1184,632"
end raBuildDmCard

-- Phase 6: the LAN device mesh. Your own devices (all sharing your master
-- seed) meet on the LAN and prove they are yours with the challenge/response
-- above; a stranger on the same Wi-Fi cannot answer. This is enet, not the
-- DHT: host on one device, Join by IP on the others.
command raBuildLanCard
   if there is no card "raDevices" then
      create card
      set the name of this card to "raDevices"
   end if
   go to card "raDevices"
   uiChrome "Riptide Social - Devices (phase 6: your own LAN device mesh)", 1200, 640
   uiButton "raGoFeedFromLan", "< Feed", "1080,4,1192,26"

   uiSection "raLanSec1", "1. This device: host the mesh, or join one on your LAN", "16,58,592,76"
   uiLabel "raLanNameL", "device name:", "16,80,110,98", 11
   uiInput "raLanName", "114,80,340,100"
   put "this device" into field "raLanName"
   uiButton "raLanHostBtn", "Host", "446,80,516,104"
   uiButton "raLanLeaveBtn", "Leave", "524,80,592,104"
   uiLabel "raLanToL", "host address (IP):", "16,108,130,126", 11
   uiInput "raLanTo", "134,108,340,128"
   uiButton "raLanJoinBtn", "Join", "446,108,592,132"
   uiArea "raLanLog", "16,138,592,336"

   -- the phase-6 sync payload: type here and every admitted device sees
   -- it (debounced on the poll timer, signed per record, absolute state)
   uiSection "raLanSec3", "3. My draft: synced to every admitted device as I type", "16,342,592,360"
   uiInput "raLanDraft", "16,366,592,562"

   -- "devices on the mesh", not "admitted devices": on a joiner most rows
   -- are devices the HOST admitted and relays to us, and we verified them
   -- per record rather than at a handshake of our own
   uiSection "raLanSec2", "2. Devices on the mesh (each proved it shares your master seed)", "608,58,1184,76"
   uiArea "raLanDevices", "608,80,1184,268"

   uiSection "raLanSec4", "4. Drafts from your other devices (signature-verified)", "608,274,1184,292"
   uiArea "raLanDrafts", "608,298,1184,428"

   -- the channel-2 decision made visible: media between your devices is
   -- a SIGNED POINTER on channel 0; the bytes ride the phase-3 torrent
   -- rail (seed in place, fetch by hash), and channel 2 stays dark
   uiSection "raLanSec5", "5. Media to your other devices (a signed pointer; bytes ride the torrent rail)", "608,434,1184,452"
   uiButton "raLanSendMedia", "Send media...", "608,458,756,482"
   uiButton "raLanMediaGet", "Fetch + play", "764,458,912,482"
   uiCap "raLanMediaOffer", "No media offered yet.", "608,488,1184,514"
   uiCap "raLanMediaProg", empty, "608,520,1184,546"

   uiFooter \
         "This is your OWN devices only, on one LAN: admission is a" \
         & " signature under a key only a holder of your master seed can" \
         & " derive, and every sync record (drafts + feed state + media" \
         & " offers on channel 0, presence/typing on channel 1) is signed" \
         & " under that key too - a stranger on the same Wi-Fi is refused" \
         & " at admission AND per record. Records are authenticated, NOT" \
         & " encrypted: the LAN sees draft plaintext. Sync records never" \
         & " touch the internet; offered media BYTES ride the phase-3" \
         & " torrent rail (swarm peers see your IP, discovery is the" \
         & " DHT). Unlock on the Feed card first. Phase 6 is done when a" \
         & " draft typed here appears on another device with a stranger" \
         & " refused. Verified statically; needs the two-machine pass.", \
         "16,572,1184,632"
end raBuildLanCard

-- Phase 7: the anonymous persona. A separate onion-only identity derived
-- from the same master. This card shows its two spellings and, loudly, the
-- deanonymization guard (spec 9.3): the transports it may and may NOT use.
command raBuildAnonCard
   if there is no card "raAnon" then
      create card
      set the name of this card to "raAnon"
   end if
   go to card "raAnon"
   uiChrome "Riptide Social - Anon persona (phase 7: onion-only identity)", 1200, 640
   uiButton "raGoFeedFromAnon", "< Feed", "1080,4,1192,26"

   uiSection "raAnonSec1", "1. Your anonymous persona (a separate key, same master seed)", "16,58,592,76"
   uiButton "raAnonReveal", "Reveal persona 0", "16,80,220,104"
   uiButton "raAnonPublishBtn", "Publish + serve", "228,80,432,104"
   uiButton "raAnonStopBtn", "Unpublish", "440,80,592,104"
   -- 8.2: what the persona's onion SERVES as its feed page - typed here,
   -- never taken from the public feed (cross-posting is the exact
   -- operator mistake spec 8.4 warns links the personas)
   uiLabel "raAnonEntriesL", "anon feed entries (one per line; served at / over the onion):", "16,110,592,128", 11
   uiInput "raAnonEntries", "16,130,592,224"
   uiArea "raAnonOut", "16,230,592,562"

   uiSection "raAnonSec2", "2. The deanonymization guard (9.3): what this persona may touch", "608,58,1184,76"
   uiArea "raAnonGuard", "608,80,1184,562"

   uiFooter \
         "The anon persona is a DIFFERENT key from your public identity," \
         & " reachable ONLY as an onion service - it never publishes to the" \
         & " DHT, seeds a torrent, or opens an rp1 peer (that would leak its" \
         & " IP and link it to your public feed). The guard enforces that at" \
         & " every transport branch. Publish + serve carries onionxt AND" \
         & " onion-httpd embedded in this file, so it needs only a running" \
         & " tor daemon (control port" \
         & " enabled); it serves the feed page at /, the signed prekey at" \
         & " /prekey, and accepts sealed intros POSTed to /dm. Serving is" \
         & " verified statically; needs an OXT + live-Tor pass." \
         & " Cross-posting or correlated timing can still link" \
         & " your personas: the tool removes the easy links, not the hard" \
         & " ones (spec 9).", \
         "16,572,1184,632"
end raBuildAnonCard

-- ---- probes (fail closed, name the missing piece) ----------------------------
command raProbe
   local tErr
   put empty into sHaveLib
   try
      put rsProbeCapabilities() into sCaps
      put "true" into sHaveLib
   catch tErr
      -- library absent; reported below
   end try
   if sHaveLib is not "true" then
      uiStatus "Riptide library missing. It is EMBEDDED in this demo, so this means the embedded copy is damaged - re-paste the whole file, or run tools/sync-demo-embeds.py.", "bad"
   else if sCaps["canCrypto"] is not true then
      uiStatus "SodiumXT missing, and identity cannot exist without it: install org.openxtalk.library.sodium.", "bad"
   else if sCaps["hasTorrent"] is not true then
      uiStatus "Offline mode (TorrentXT absent): identity works; publish and fetch are disabled.", "warn"
   else if sCaps["hasSha3"] is not true then
      uiStatus "Ready, minus the .onion spelling: no SHA3 provider is loaded (SodiumXT ABI 7 serves sxSha3_256; CoinXT's cxSha3_256 is the fallback).", "warn"
   else
      uiStatus "Ready: SodiumXT + TorrentXT + SHA3 all present.", "ok"
   end if
end raProbe

-- ---- 1. identity -------------------------------------------------------------
command raCreate
   local tPass, tPath, tFolder, tSeed, tSealed, tSaved, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot create an identity without the library and SodiumXT (see above).", "bad"
      exit raCreate
   end if
   put field "raPassphrase" into tPass
   if the number of chars of tPass < 8 then
      put "REFUSED: use a passphrase of at least 8 characters." & return into field "raIdOut"
      exit raCreate
   end if
   put field "raKeyFile" into tPath
   if there is a file tPath then
      put "REFUSED: a key file already exists at" && tPath & return \
            & "Unlock it, or point the key-file field somewhere new." & return into field "raIdOut"
      exit raCreate
   end if
   put false into tFailed
   try
      put rsGenerateMasterSeed() into tSeed
      if tSeed is empty then
         throw "rsGenerateMasterSeed:" && rsLastError()
      end if
      put rsSealMasterSeed(tSeed, tPass) into tSealed
      if tSealed is empty then
         throw "rsSealMasterSeed:" && rsLastError()
      end if
      -- the folder half of the write, itemDelimiter guarded (global state)
      put the itemDelimiter into tSaved
      set the itemDelimiter to "/"
      put item 1 to -2 of tPath into tFolder
      set the itemDelimiter to tSaved
      if tFolder is not empty and there is no folder tFolder then
         create folder tFolder
      end if
      put tSealed into url ("binfile:" & tPath)
      if there is no file tPath then
         throw "the key file did not write; check the path and permissions"
      end if
      put rsIdentitySeed(tSeed) into sIdSeed
      put rsDmSeed(tSeed) into sDmSeed
      put tSeed into sMasterSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tSeed
   put empty into tSealed
   if tFailed then
      put "Create failed:" && tErr & return into field "raIdOut"
      exit raCreate
   end if
   put "Identity CREATED and sealed (RIPTKEY1, Argon2id) at:" && tPath & return into field "raIdOut"
   put "Write the passphrase down; the seed cannot be recovered without it." & return after field "raIdOut"
   raIdentityReady
end raCreate

command raUnlock
   local tPass, tPath, tRaw, tMaster, tErr, tFailed
   if sHaveLib is not "true" or sCaps["canCrypto"] is not true then
      uiStatus "Cannot unlock without the library and SodiumXT (see above).", "bad"
      exit raUnlock
   end if
   put field "raPassphrase" into tPass
   put field "raKeyFile" into tPath
   if there is no file tPath then
      put "REFUSED: no key file at" && tPath & return into field "raIdOut"
      exit raUnlock
   end if
   put false into tFailed
   try
      put url ("binfile:" & tPath) into tRaw
      put rsOpenMasterSeed(tRaw, tPass) into tMaster
      if tMaster is empty then
         throw rsLastError()
      end if
      put rsIdentitySeed(tMaster) into sIdSeed
      put rsDmSeed(tMaster) into sDmSeed
      put tMaster into sMasterSeed
   catch tErr
      put true into tFailed
   end try
   put empty into tMaster
   put empty into tRaw
   if tFailed then
      put "Unlock failed:" && tErr & return into field "raIdOut"
      exit raUnlock
   end if
   put "Identity UNLOCKED from" && tPath & return into field "raIdOut"
   raIdentityReady
end raUnlock

-- The shared tail of create and unlock: derive the public spellings, start
-- the session, and recover our head sequence from the DHT rather than from
-- local guesswork (republishing under a LOWER seq than the network holds is
-- refused by BEP44, so the network's number is the truthful one).
command raIdentityReady
   local tOk
   put rsHandleFromSeed(sIdSeed) into sHandle
   put rsOnionFromHandle(sHandle) into sOnion
   put "handle (the key your feed publishes under):" & return & "  " & sHandle & return after field "raIdOut"
   if sOnion is empty then
      put "onion spelling: unavailable (no SHA3 provider; identity still works)" & return after field "raIdOut"
   else
      put "the SAME key as an onion identity:" & return & "  " & sOnion & return after field "raIdOut"
   end if
   put 0 into sSeq
   put empty into sMyLatest
   raStartSession
   if sSession is an integer and sSession > 0 then
      put rsRequestHead(sSession, sHandle) into tOk
      if tOk is true then
         put "true" into sAwaitOwn
         put the milliseconds + kDhtWaitMs into sWaitUntil
         put "recovering your head from the DHT (fresh identities start at seq 0)..." & return after field "raIdOut"
      end if
      raDmBringUp
   else
      put "no session: posts stay disabled until TorrentXT is available." & return after field "raIdOut"
   end if
end raIdentityReady

-- Phase 4 bring-up, run once per unlock: derive the kx prekey pair,
-- publish the signed RSK1 record (so the NEXT head names it and strangers
-- can seal to a key that provably belongs to you), and join your own
-- inbox swarm so intros can arrive. Degrades line by line with reasons -
-- an inbox that failed to join disables inbound DMs and nothing else.
command raDmBringUp
   local tPrekey, tH
   if sDmSeed is empty then
      exit raDmBringUp
   end if
   put rsDmKeys(sDmSeed) into sDmKeys
   if sDmKeys is empty then
      raDmLog "DM keys failed:" && rsLastError()
      exit raDmBringUp
   end if
   put rsBuildPrekey(sDmKeys["publicKeyHex"], sIdSeed) into tPrekey
   if tPrekey is empty then
      raDmLog "prekey record refused:" && rsLastError()
      exit raDmBringUp
   end if
   put rsPublishImmutable(sSession, tPrekey) into sMyPrekeyTarget
   if sMyPrekeyTarget is empty then
      raDmLog "prekey publish failed:" && rsLastError()
   else
      raDmLog "prekey published at" && sMyPrekeyTarget & \
            "; your next post's head will advertise it."
   end if
   put rsDmJoinInbox(sSession, sHandle, raMediaFolder()) into tH
   if tH is empty then
      raDmLog "inbox join failed (inbound DMs disabled):" && rsLastError()
      put empty into sDmInbox
   else
      put tH into sDmInbox
      raDmLog "inbox open at swarm" && rsInboxId(sHandle) & \
            "; strangers who follow you can now knock."
   end if
   raDmPaintMine
end raDmBringUp

-- The inbox status cap on the Messages card, painted on state change.
command raDmPaintMine
   local tLine
   if sHandle is empty then
      put "Unlock on the Feed card first; the inbox derives from your identity." into tLine
   else
      if sMyPrekeyTarget is empty then
         put "prekey: NOT published. " into tLine
      else
         put "prekey: published. " into tLine
      end if
      if sDmInbox is empty then
         put "inbox: NOT joined." after tLine
      else
         put "inbox: joined (swarm" && rsInboxId(sHandle) & ")." after tLine
      end if
   end if
   if there is a field "raDmMine" of card "raMessages" then
      if the text of field "raDmMine" of card "raMessages" \
            is not tLine then
         set the text of field "raDmMine" of card "raMessages" to tLine
      end if
   end if
end raDmPaintMine

command raDmLog pLine
   if there is a field "raDmLog" of card "raMessages" then
      put pLine & return after field "raDmLog" of card "raMessages"
   end if
end raDmLog

command raDmChatLine pLine
   if there is a field "raDmChat" of card "raMessages" then
      put pLine & return after field "raDmChat" of card "raMessages"
   end if
end raDmChatLine

private function raDmShort pHandleHex
   return char 1 to 8 of pHandleHex & "..."
end raDmShort

command raLock
   raClearKeys
   put "LOCKED: the identity seed left memory. Unlock to publish again." & return into field "raIdOut"
end raLock

command raClearKeys
   raDmTeardown
   raLanLeave
   raAnonStop
   put empty into sIdSeed
   put empty into sDmSeed
   put empty into sDmKeys
   put empty into sMasterSeed
   put empty into sHandle
   put empty into sOnion
   put 0 into sSeq
   put empty into sMyLatest
   put empty into sMyPrekeyTarget
   put empty into sAwaitOwn
end raClearKeys

-- The clean-close half of the secretstream, and the reason the far side
-- no longer sits under "-- channel open with ... --" forever after we hang
-- up. libsodium's FINAL tag IS the "this stream ended" signal (the spec's
-- section 5.3 names sxIsFinalTag for exactly this), so one last push with
-- final true turns a hang-up into a protocol event instead of silence.
-- Two properties worth stating because both are load-bearing: the body is
-- FILLER - the tag carries the meaning and the far side never renders it,
-- but rsDmMessageBody refuses an empty body so something must ride along -
-- and this is the LAST thing this push stream can ever do, because the
-- FINAL tag closes it. Best-effort throughout: the peer may already be
-- gone, and a goodbye that cannot be delivered must never block a
-- teardown or a Lock.
private command raDmPushClose pPeer
   local tMsg, tCipher, tFrame, tOk, tErr
   if sDmPush[pPeer] is empty then
      exit raDmPushClose
   end if
   put rsDmMessageBody("T", the seconds, "bye") into tMsg
   if tMsg is empty then
      exit raDmPushClose
   end if
   try
      put sxSecretStreamPush(sDmPush[pPeer], tMsg, empty, true) into tCipher
   catch tErr
      exit raDmPushClose
   end try
   put rsDmFrame("M", tCipher) into tFrame
   if tFrame is empty then
      exit raDmPushClose
   end if
   -- rsDmSend never throws (rule 5) and returns false on a dead session or
   -- a vanished peer, which is the whole expected failure set here
   put rsDmSend(sSession, pPeer, tFrame) into tOk
end raDmPushClose

-- End every DM conversation: say goodbye, then free the secretstream
-- handles (SodiumXT has no unload hook; sxFreeStream is idempotent) and
-- forget the per-peer state. The inbox swarms stay in the session - they
-- carry no secrets.
command raDmTeardown
   local tPeer, tErr
   raDcTeardown
   repeat for each key tPeer in sDmPush
      -- goodbye BEFORE the free: a freed stream can push nothing, and the
      -- FINAL tag is the only clean-close signal the far side gets
      raDmPushClose tPeer
      try
         sxFreeStream sDmPush[tPeer]
      catch tErr
         -- already gone; free is best-effort by design
      end try
   end repeat
   repeat for each key tPeer in sDmPull
      try
         sxFreeStream sDmPull[tPeer]
      catch tErr
         -- already gone
      end try
   end repeat
   put empty into sDmPush
   put empty into sDmPull
   put empty into sDmTheirHandle
   put empty into sDmRxKey
   put empty into sDmTxKey
   put empty into sDmActivePeer
   put empty into sDmTarget
   put empty into sDmTargetKx
   put empty into sDmAwaitDmHead
   put empty into sDmAwaitPrekey
end raDmTeardown

-- ---- the session + the pump --------------------------------------------------
-- The app owns THE one TorrentXT session (the library never does), pumps
-- btPoll on one standing timer chain, and hands DHT events to the ingest
-- verifiers. Each drain rides a try: a throw out of the pump would break
-- the chain and orphan the session (runbook trap 5.1.1).
command raStartSession
   local tSession, tErr
   if sSession is an integer and sSession > 0 then
      exit raStartSession
   end if
   if sHaveLib is not "true" or sCaps["hasTorrent"] is not true then
      exit raStartSession
   end if
   try
      put btStartSession() into tSession
      if tSession > 0 then
         put tSession into sSession
         btSetBool sSession, "enable_dht", true
         btDhtAddBootstrap sSession, "router.bittorrent.com", 6881
         btDhtAddBootstrap sSession, "router.utorrent.com", 6881
         btDhtAddBootstrap sSession, "dht.transmissionbt.com", 6881
      end if
   catch tErr
      uiStatus "TorrentXT session failed:" && tErr, "bad"
   end try
   if sSession is an integer and sSession > 0 and sPolling is not "true" then
      put "true" into sPolling
      -- the repaint gate is arithmetic on the very first tick, and an
      -- undeclared-shaped empty in a subtraction is not a number; seed it
      -- where the chain is armed, the sLanPresenceAt discipline
      put 0 into sPaintAt
      send "raPoll" to me in raPollDelay() milliseconds
   end if
end raStartSession

command raPoll
   local tEvents, tEvent, tErr, tNow
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if sPolling is not "true" then
      exit raPoll
   end if
   if sSession is an integer and sSession > 0 then
      try
         put btPoll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            raHandleEvent tEvent
         end repeat
      catch tErr
         -- one bad drain must not kill the chain; the next tick retries
      end try
      -- the rp1 stream (DM peers + frames) drains beside the DHT stream;
      -- inert until a swarm is joined, and guarded the same way
      try
         put btRp1Poll(sSession) into tEvents
         repeat for each element tEvent in tEvents
            raHandleRp1 tEvent
         end repeat
      catch tErr
         -- rp1 not enabled yet, or a bad drain; the next tick retries
      end try
   end if
   -- the enet mesh (phase 6) pumps on the SAME timer - enet is pump-or-
   -- nothing, so a missed drain is a stalled mesh; guarded like the others
   if sLanHost is not empty and sLanHost is not 0 then
      try
         put enPoll(sLanHost) into tEvents
         repeat for each element tEvent in tEvents
            raHandleEnet tEvent
         end repeat
      catch tErr
         -- host torn down mid-drain; the next tick sees it gone
      end try
      -- the phase-6 sync tick (drafts debounced, presence re-asserted);
      -- guarded on its own so a sync hiccup cannot kill the pump
      try
         raLanSyncTick
      catch tErr
         -- the next tick retries; the mesh survives one bad tick
      end try
   end if
   -- the dc call (phase 5): drain its events, and ship our one-blob SDP
   -- the moment gathering completes (non-trickle signalling over the DM
   -- stream); guarded like the others so a dc hiccup cannot kill the pump
   if sDcInit is "true" then
      try
         put dcPoll() into tEvents
         repeat for each element tEvent in tEvents
            raHandleDc tEvent
         end repeat
      catch tErr
         -- dc torn down mid-drain; the next tick sees it gone
      end try
   end if
   if sDcAwaitLocal is not empty and sDcPeer is not empty then
      try
         raDmCallShipLocal
      catch tErr
         -- a failed ship retries next tick; teardown clears the flag
      end try
   end if
   -- the phase-5 typing lane (spec 6.2): absolute state over the lossy
   -- channel, debounced here on the timer - never per keystroke
   if sDcPeer is not empty then
      try
         raDmTypingTick
      catch tErr
         -- the lane is optional; the call carries on without it
      end try
   end if
   -- the UI repaint tier, deliberately NOT on the pump's cadence. These
   -- read torrent status and rewrite fields; the fast tier exists for the
   -- TRANSPORTS (a dc call and the enet mesh are pump-or-nothing, so a
   -- missed drain is a stalled call), and dragging the painters from 4 Hz
   -- to 30 Hz with them would trade one slow slot for a sluggish window.
   -- raExpire rides here too: it is a deadline check, and one checked 4
   -- times a second is a deadline checked promptly enough. The devices
   -- panel joins them because its [typing]/[quiet] markers age against the
   -- clock, so it needs a periodic repaint and not a per-tick one.
   put the milliseconds into tNow
   if tNow - sPaintAt >= kPaintMs then
      put tNow into sPaintAt
      raExpire
      raMediaPaint
      raLanMediaPaint
      if sLanHost is not empty then
         raLanPaintDevices
      end if
   end if
   send "raPoll" to me in raPollDelay() milliseconds
end raPoll

-- Which tick tier are we in? The spec's section 10.1 knob: ~33 ms while a
-- live dc call or an enet mesh is running (both are pump-or-nothing and
-- both are judged BY FEEL on an engine pass - a call connecting, a typing
-- indicator appearing), ~250 ms when only the feed and DMs are live, which
-- are DHT-paced and gain nothing from a faster drain. Read on every tick
-- rather than latched at start/stop, so hanging up or leaving the mesh
-- drops straight back to the cheap tier with no state to keep in sync.
private function raPollDelay
   if sDcPeer is not empty then
      return kPollLiveMs
   end if
   if sLanHost is not empty and sLanHost is not 0 then
      return kPollLiveMs
   end if
   return kPollMs
end raPollDelay

-- Append a status line to a Feed-card (card 1) field from anywhere, safely.
-- The pump and its handlers run on whatever card the user is viewing, but
-- the feed status fields live only on card 1; a bare cross-card reference
-- throws, and several callers run outside raPoll's try, so a throw here
-- would kill the pump. Qualify to card 1 and guard existence, exactly as
-- raDmLog / raLanLog / raAnonLog do for their own cards.
command raFeedNote pFieldName, pLine
   if there is a field pFieldName of card 1 then
      put pLine & return after field pFieldName of card 1
   end if
end raFeedNote

-- The deadline half: the walk keys every request by the exact target it
-- awaits, so a DHT that never answers expires visibly instead of hanging.
command raExpire
   if the milliseconds <= sWaitUntil then
      exit raExpire
   end if
   -- The pump runs from every card since phase 4, but these status fields
   -- live on the Feed card (card 1). Clear the state flags UNCONDITIONALLY
   -- (they must expire wherever the user is), then land the message on card
   -- 1, guarded - a bare cross-card field reference throws "no such object"
   -- and, because raExpire runs OUTSIDE raPoll's try, that throw would kill
   -- the whole pump. raFeedNote qualifies + guards, like raDmLog et al.
   if sAwaitOwn is "true" then
      put empty into sAwaitOwn
      raFeedNote "raIdOut", "no head found for your key (fresh identity, or not yet propagated); starting at seq 0."
   end if
   if sAwaitHead is "true" then
      put empty into sAwaitHead
      raFeedNote "raTheirFeed", "the DHT did not answer for that head in time; try again in a minute (bootstrap takes a moment)."
   end if
   if sWalkNext is not empty then
      raFeedNote "raTheirFeed", "the DHT did not answer for post target" && sWalkNext && "in time; walk abandoned."
      put empty into sWalkNext
   end if
   if sChunkNext is not empty then
      raFeedNote "raTheirFeed", "chunk" && sChunkNext && "did not arrive in time; post" && sChunkPostNum && "keeps its (chunked) placeholder."
      raChunkAbandon
   end if
   if sProfileNext is not empty then
      raFeedNote "raTheirFeed", "the profile-name blob did not arrive in time; showing the head's own name."
      put empty into sProfileNext
   end if
   if sDmProfileNext is not empty then
      raDmLog "their profile-name blob did not arrive in time; showing the handle."
      put empty into sDmProfileNext
   end if
   if sDmAwaitDmHead is "true" then
      put empty into sDmAwaitDmHead
      raDmLog "no head arrived for" && raDmShort(sDmTarget) && \
            "in time; Start DM again in a minute."
   end if
   if sDmAwaitPrekey is not empty then
      raDmLog "their prekey record did not arrive in time; Start DM again."
      put empty into sDmAwaitPrekey
   end if
end raExpire

command raHandleEvent pEvent
   local tHead, tPost, tNext, tOk, tKeyCount
   switch pEvent["name"]
      case "dhtMutableItem"
         if sDmAwaitDmHead is "true" and sDmTarget is not empty then
            put rsIngestHead(pEvent, sDmTarget) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sDmAwaitDmHead
               if tHead["prekeyTarget"] is rsZeroTarget() then
                  raDmLog raDmShort(sDmTarget) && "publishes no prekey" && \
                        "(their app predates DMs); cannot open a channel."
               else
                  put tHead["prekeyTarget"] into sDmAwaitPrekey
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sDmAwaitPrekey) into tOk
                  if tOk is true then
                     raDmLog "head verified; fetching their prekey record..."
                  else
                     raDmLog "prekey lookup refused:" && rsLastError()
                     put empty into sDmAwaitPrekey
                  end if
                  -- A.9: the head also names a profileMeta blob (spec
                  -- 4.1's display name); fetch and show it beside the
                  -- handle, degrading honestly when it is absent
                  if tHead["profileMetaTarget"] is rsZeroTarget() then
                     raDmLog "they publish no profile-name blob;" && \
                           "showing the handle."
                  else
                     put tHead["profileMetaTarget"] into sDmProfileNext
                     put rsRequestImmutable(sSession, sDmProfileNext) \
                           into tOk
                     if tOk is not true then
                        raDmLog "profile-name lookup refused:" && \
                              rsLastError() && "- showing the handle."
                        put empty into sDmProfileNext
                     end if
                  end if
               end if
            end if
         end if
         if sAwaitOwn is "true" then
            put rsIngestHead(pEvent, sHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitOwn
               put tHead["seq"] into sSeq
               if tHead["latestPostTarget"] is not rsZeroTarget() then
                  put tHead["latestPostTarget"] into sMyLatest
               end if
               raFeedNote "raIdOut", "recovered your head: seq" && sSeq & comma && "latest post" && tHead["latestPostTarget"]
            end if
         end if
         if sAwaitHead is "true" then
            put rsIngestHead(pEvent, sFollowHandle) into tHead
            put the number of lines of the keys of tHead into tKeyCount
            if tKeyCount > 0 then
               put empty into sAwaitHead
               raFeedNote "raTheirFeed", "head VERIFIED for" && tHead["displayName"] && "(seq" && tHead["seq"] & ")"
               -- A.9 (2026-08-23): the profileMeta READER. The head
               -- names a display-name blob (spec 4.1: "so a reader can
               -- show a name without parsing the head's own name field
               -- out of band"); fetch it and show it, verified by its
               -- content address on arrival - and say so honestly when
               -- the head carries the none target instead.
               if tHead["profileMetaTarget"] is rsZeroTarget() then
                  raFeedNote "raTheirFeed", "no profile-name blob published (the head carries the none target)."
               else
                  put tHead["profileMetaTarget"] into sProfileNext
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sProfileNext) into tOk
                  if tOk is not true then
                     raFeedNote "raTheirFeed", "profile-name lookup refused:" && rsLastError() && "- showing the head's own name."
                     put empty into sProfileNext
                  end if
               end if
               if tHead["latestPostTarget"] is rsZeroTarget() then
                  raFeedNote "raTheirFeed", "no posts yet."
               else
                  put tHead["latestPostTarget"] into sWalkNext
                  put 0 into sWalkCount
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     raFeedNote "raTheirFeed", "lookup refused:" && rsLastError()
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtImmutableItem"
         if sDmAwaitPrekey is not empty and pEvent["target"] is sDmAwaitPrekey then
            raDmPrekeyArrived pEvent["value"]
         end if
         -- the kind-C reassembly walk (A2) and the profileMeta reader
         -- (A.9) ride the same event stream as the chain walk, each with
         -- its own await slot - independent ifs, the prekey-vs-walk
         -- pattern, so concurrent lookups never steal each other's answer
         if sChunkNext is not empty and pEvent["target"] is sChunkNext then
            raChunkArrived pEvent
         end if
         if sProfileNext is not empty and pEvent["target"] is sProfileNext then
            raFeedNote "raTheirFeed", raProfileLine(pEvent, sProfileNext)
            put empty into sProfileNext
         end if
         if sDmProfileNext is not empty and \
               pEvent["target"] is sDmProfileNext then
            raDmLog raProfileLine(pEvent, sDmProfileNext)
            put empty into sDmProfileNext
         end if
         if sWalkNext is not empty and pEvent["target"] is sWalkNext then
            put rsIngestPost(pEvent, sWalkNext, sFollowHandle) into tPost
            put the number of lines of the keys of tPost into tKeyCount
            if tKeyCount is 0 then
               raFeedNote "raTheirFeed", "post REFUSED (tamper or wrong author):" && rsLastError()
               put empty into sWalkNext
            else
               add 1 to sWalkCount
               -- THE KIND BRANCH (A2, 2026-08-23). Before it, this line
               -- rendered tPost["text"] unconditionally, and a kind-C
               -- post has no "text" key - so it displayed as a VERIFIED
               -- post with blank text, the worst failure shape, because
               -- authorSig passes and nothing looks wrong. A chunked
               -- post now renders an honest placeholder and starts the
               -- reassembly walk; the full text prints under the same
               -- post number once every part has verified.
               if tPost["kind"] is "C" then
                  set the itemDelimiter to comma
                  raFeedNote "raTheirFeed", "post" && sWalkCount && "[t=" & tPost["timestamp"] & "] authorSig VERIFIED: (chunked," && the number of items in tPost["chunkTargets"] && "part(s) - fetching the text...)"
                  raChunkStart tPost["chunkTargets"]
               else
                  raFeedNote "raTheirFeed", "post" && sWalkCount && "[t=" & tPost["timestamp"] & "] authorSig VERIFIED:" && tPost["text"]
               end if
               if tPost["mediaTargets"] is not empty then
                  -- a verified post's media list is trustworthy (it sat
                  -- under the authorSig); surface it and pre-fill the strip
                  -- with the first hash so Fetch + play is one click
                  raFeedNote "raTheirFeed", "  media attachment(s):" && tPost["mediaTargets"]
                  -- itemDelimiter is global mutable state; set it right
                  -- before the item read, and target card 1's field,
                  -- guarded. The handler that used to leave it as "/" was
                  -- the LIBRARY (rsMediaCreate), fixed at its source to
                  -- save and restore the narrowest span; this line stays
                  -- as defence in depth because the pump reaches here from
                  -- any card after any handler, and one line is cheaper
                  -- than trusting every caller in a file no harness runs.
                  set the itemDelimiter to comma
                  if there is a field "raMediaHash" of card 1 then
                     if field "raMediaHash" of card 1 is empty then
                        put item 1 of tPost["mediaTargets"] into \
                              field "raMediaHash" of card 1
                     end if
                  end if
               end if
               put tPost["prevPostTarget"] into tNext
               if tNext is rsZeroTarget() then
                  raFeedNote "raTheirFeed", "chain COMPLETE:" && sWalkCount && "post(s), every authorSig verified."
                  put empty into sWalkNext
               else if sWalkCount >= kWalkMax then
                  raFeedNote "raTheirFeed", "stopped at the" && kWalkMax & "-post demo cap; the chain continues at" && tNext
                  put empty into sWalkNext
               else
                  put tNext into sWalkNext
                  put the milliseconds + kDhtWaitMs into sWaitUntil
                  put rsRequestImmutable(sSession, sWalkNext) into tOk
                  if tOk is not true then
                     raFeedNote "raTheirFeed", "lookup refused:" && rsLastError()
                     put empty into sWalkNext
                  end if
               end if
            end if
         end if
         break
      case "dhtPut"
         -- store confirmations arrive here; the publish calls already
         -- validated synchronously, so these stay quiet in the demo
         break
      case "metadataReceived"
         -- B7 (2026-08-23): a sequential media fetch learns its piece
         -- table HERE, never at rsMediaFetch time (the fetch path is
         -- btAddMagnet - no metadata, no piece table - so a deadline
         -- set there would name pieces that do not exist). Arm the
         -- streaming plan on whichever watched fetch this event names.
         -- A refusal is NON-fatal on purpose: the fetch stays
         -- sequential without it (rsMediaStreamPlan's own contract),
         -- including on a torrentxt that predates btSetPieceDeadline.
         if sMediaWatch is an integer and sMediaWatch > 0 and \
               pEvent["torrent"] is sMediaWatch then
            put rsMediaStreamPlan(sMediaWatch) into tOk
            if tOk is empty then
               raFeedNote "raTheirFeed", "media metadata arrived; streaming plan skipped (" & rsLastError() & ") - the fetch stays sequential."
            else
               raFeedNote "raTheirFeed", "media metadata arrived; the front" && tOk && "piece(s) are deadline-prioritized for playback."
            end if
         end if
         if sLanMediaWatch is an integer and sLanMediaWatch > 0 and \
               pEvent["torrent"] is sLanMediaWatch then
            put rsMediaStreamPlan(sLanMediaWatch) into tOk
            if tOk is empty then
               raLanLog "handoff metadata arrived; streaming plan skipped (" & rsLastError() & ") - the fetch stays sequential."
            else
               raLanLog "handoff metadata arrived; the front" && tOk && "piece(s) are deadline-prioritized."
            end if
         end if
         break
   end switch
end raHandleEvent

-- ---- the kind-C reassembly walk (backlog A2) ---------------------------------
-- The chain walk verifies a kind-C post's SIGNATURE, but the signature
-- covers the chunk TARGETS, not the text; these helpers fetch each part,
-- verify it by content address (which is what extends the authorSig to
-- the bytes), and print the reassembled text under the post's own walk
-- number. One reassembly at a time, one immutable await at a time - the
-- chain walk's own discipline, run concurrently beside it.

private command raChunkStart pTargets
   if sChunkNext is not empty then
      raFeedNote "raTheirFeed", "  (another chunked post is still reassembling; this one keeps its placeholder - Fetch again for its text)"
      exit raChunkStart
   end if
   put pTargets into sChunkTargets
   put empty into sChunkParts
   put sWalkCount into sChunkPostNum
   raChunkRequestNext
end raChunkStart

-- Ask for the first part not yet verified; with none left, assemble.
-- Duplicate targets inside one post are legal wire and cost one fetch:
-- the parts array is keyed by target.
private command raChunkRequestNext
   local tItem, tWant, tOk
   put empty into tWant
   set the itemDelimiter to comma
   repeat for each item tItem in sChunkTargets
      if sChunkParts[tItem] is empty then
         put tItem into tWant
         exit repeat
      end if
   end repeat
   if tWant is empty then
      raChunkFinish
      exit raChunkRequestNext
   end if
   put tWant into sChunkNext
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put rsRequestImmutable(sSession, sChunkNext) into tOk
   if tOk is not true then
      raFeedNote "raTheirFeed", "  chunk lookup refused:" && rsLastError() && "- post" && sChunkPostNum && "keeps its placeholder."
      raChunkAbandon
   end if
end raChunkRequestNext

-- One part arrived: verify by content address BEFORE keeping a byte
-- (rsIngestBlob). A refused part abandons the reassembly LOUDLY - the
-- placeholder stands, and nothing unverified is ever rendered.
private command raChunkArrived pEvent
   local tBytes
   put rsIngestBlob(pEvent, sChunkNext) into tBytes
   if tBytes is empty then
      raFeedNote "raTheirFeed", "  chunk" && sChunkNext && "REFUSED:" && rsLastError() && "- post" && sChunkPostNum && "keeps its placeholder."
      raChunkAbandon
      exit raChunkArrived
   end if
   put tBytes into sChunkParts[sChunkNext]
   put empty into sChunkNext
   raChunkRequestNext
end raChunkArrived

-- Every part is in: the library re-verifies each against its target and
-- decodes the CONCATENATION (a producer may split inside a UTF-8
-- sequence, so only the whole is decodable) - then the text prints under
-- the post's own number.
private command raChunkFinish
   local tText
   put rsAssembleChunkText(sChunkTargets, sChunkParts) into tText
   if tText is empty then
      raFeedNote "raTheirFeed", "post" && sChunkPostNum && "(chunked) REFUSED at reassembly:" && rsLastError()
   else
      raFeedNote "raTheirFeed", "post" && sChunkPostNum && "(chunked) full text VERIFIED:" && tText
   end if
   raChunkAbandon
end raChunkFinish

private command raChunkAbandon
   put empty into sChunkNext
   put empty into sChunkTargets
   put empty into sChunkParts
end raChunkAbandon

-- ---- the profileMeta reader (remaining-work A.9) -----------------------------
-- One verified log line for an arrived profile blob: content address
-- first (rsIngestBlob), then the spec-4.1 shape - 1..64 bytes of valid
-- UTF-8, validated by ROUND TRIP because OXT's textDecode is lossy, not
-- throwing (the library's own 2026-08-15 engine finding; the demo cannot
-- reach its private rsBytesAreUtf8, so the idiom is restated here).
-- Always returns a printable line: the refusal shapes degrade to the
-- head's own name rather than rendering unverified bytes.
private function raProfileLine pEvent, pExpected
   local tBytes, tName
   put rsIngestBlob(pEvent, pExpected) into tBytes
   if tBytes is empty then
      return "profile-name blob REFUSED (" & rsLastError() & \
            ") - showing the head's own name."
   end if
   if the number of bytes in tBytes < 1 or \
         the number of bytes in tBytes > kNameMax then
      return "profile-name blob REFUSED (not 1.." & kNameMax && \
            "bytes) - showing the head's own name."
   end if
   put textDecode(tBytes, "UTF-8") into tName
   if textEncode(tName, "UTF-8") is not tBytes then
      return "profile-name blob REFUSED (not valid UTF-8) - showing the head's own name."
   end if
   return "profile name (spec 4.1, content-verified):" && tName
end raProfileLine

-- ---- 2. my feed --------------------------------------------------------------
command raPost
   local tText, tName, tPost, tTarget, tHead, tOk, tMediaHash, tProfile
   local tMediaCount, tCapacity, tKindNote
   if sIdSeed is empty then
      uiStatus "Unlock (or create) your identity before posting.", "warn"
      exit raPost
   end if
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot publish.", "bad"
      exit raPost
   end if
   put field "raCompose" into tText
   if tText is empty then
      uiStatus "Nothing to post: the compose field is empty.", "warn"
      exit raPost
   end if
   put field "raName" into tName
   if the number of chars of tName > kNameMax then
      uiStatus "The display name is over the 64-byte head budget; shorten it.", "warn"
      exit raPost
   end if
   -- the attachment seeds FIRST, so a refusal (file moved, torrent error)
   -- aborts the post rather than publishing a hash nobody can fetch
   put empty into tMediaHash
   if sPendingMediaPath is not empty then
      put rsMediaCreate(sSession, sPendingMediaPath) into tMediaHash
      if tMediaHash is empty then
         uiStatus "rsMediaCreate refused:" && rsLastError(), "bad"
         exit raPost
      end if
   end if
   -- A2 (2026-08-23): the D-or-C decision rides the library's OWN
   -- capacity arithmetic (rsPostTextCapacity), never a hand-copied
   -- number. Text over the direct budget moves into content-addressed
   -- chunks and publishes as a kind-C post (rsPublishChunkedPost:
   -- chunks stored first, then the signed post naming them); at or
   -- under it, the kind-D path is unchanged. Verified statically;
   -- needs an OXT pass.
   put 0 into tMediaCount
   if tMediaHash is not empty then
      put 1 into tMediaCount
   end if
   put empty into tKindNote
   put rsPostTextCapacity(tMediaCount) into tCapacity
   if tCapacity is not empty and \
         the number of bytes in textEncode(tText, "UTF-8") > tCapacity then
      put rsPublishChunkedPost(sSession, the seconds, sMyLatest, tText, \
            tMediaHash, sIdSeed) into tTarget
      if tTarget is empty then
         uiStatus "rsPublishChunkedPost refused:" && rsLastError(), "bad"
         exit raPost
      end if
      put " (chunked)" into tKindNote
   else
      put rsBuildPost(the seconds, sMyLatest, tText, tMediaHash, sIdSeed) into tPost
      if tPost is empty then
         uiStatus "rsBuildPost refused:" && rsLastError(), "bad"
         exit raPost
      end if
      put rsPublishPost(sSession, tPost) into tTarget
      if tTarget is empty then
         uiStatus "rsPublishPost failed:" && rsLastError(), "bad"
         exit raPost
      end if
   end if
   add 1 to sSeq
   -- the head's profileMeta names a display-name blob (spec 4.1): a small
   -- immutable item carrying the name's UTF-8 bytes, so a reader can show
   -- a name without parsing the head's own name field out of band. It is
   -- content-addressed, so republishing the same name is idempotent and a
   -- rename mints a new target. A refusal is NON-fatal: the head still
   -- publishes with the none target, and the reason lands in the feed log.
   put empty into tProfile
   if tName is not empty then
      put rsPublishImmutable(sSession, textEncode(tName, "UTF-8")) \
            into tProfile
      if tProfile is empty then
         put "profile-meta publish refused (the head carries the none" && \
               "target):" && rsLastError() & return before field "raMyFeed"
      end if
   end if
   -- since phase 4 the head advertises the prekey target, so a reader can
   -- open a DM to any author whose post they verified
   put rsBuildHead(sSeq, tName, tTarget, sMyPrekeyTarget, sOnion, tProfile) \
         into tHead
   if tHead is empty then
      subtract 1 from sSeq
      uiStatus "rsBuildHead refused:" && rsLastError(), "bad"
      exit raPost
   end if
   put rsPublishHead(sSession, tHead, sIdSeed) into tOk
   if tOk is not true then
      subtract 1 from sSeq
      uiStatus "rsPublishHead failed:" && rsLastError(), "bad"
      exit raPost
   end if
   put tTarget into sMyLatest
   if tMediaHash is empty then
      put "seq" && sSeq & tKindNote & ":" && tText & return & "  ->" && tTarget & return before field "raMyFeed"
   else
      put "seq" && sSeq & tKindNote & ":" && tText & return & "  ->" && tTarget & return & "  media seeding:" && tMediaHash & return before field "raMyFeed"
      put empty into sPendingMediaPath
      set the label of button "raAttach" to "Attach"
   end if
   put empty into field "raCompose"
   uiStatus "Posted, and the signed head republished at seq" && sSeq & ".", "ok"
end raPost

-- The attachment picker: choose now, seed at post time (the session is
-- guaranteed then, and a cancelled post leaves nothing seeding). A second
-- click clears the pending choice.
command raAttach
   local tShortName
   if sPendingMediaPath is not empty then
      put empty into sPendingMediaPath
      set the label of button "raAttach" to "Attach"
      uiStatus "Attachment cleared.", empty
      exit raAttach
   end if
   answer file "Choose a photo or video to attach (it seeds from where it is):"
   if it is empty then
      exit raAttach
   end if
   put it into sPendingMediaPath
   -- itemDelimiter is global mutable state; take the leaf, then RESTORE it
   -- to comma (the pump's raHandleEvent reads comma-joined media lists, and
   -- leaving it as "/" made item 1 return the whole list)
   set the itemDelimiter to "/"
   put item -1 of sPendingMediaPath into tShortName
   set the itemDelimiter to comma
   set the label of button "raAttach" to "Clear attach"
   uiStatus "Attached" && quote & tShortName & quote & \
         "- it rides the next post and seeds from its current location.", empty
end raAttach

-- ---- 3. follow ---------------------------------------------------------------
command raFetch
   local tHandle, tOk
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot fetch.", "bad"
      exit raFetch
   end if
   put toLower(word 1 of field "raHandle") into tHandle
   if the number of chars of tHandle is not 64 then
      uiStatus "A handle is 64 hex characters (the author's public key).", "warn"
      exit raFetch
   end if
   put tHandle into sFollowHandle
   put empty into sWalkNext
   put 0 into sWalkCount
   put "true" into sAwaitHead
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put empty into field "raTheirFeed"
   put rsRequestHead(sSession, sFollowHandle) into tOk
   if tOk is not true then
      put empty into sAwaitHead
      uiStatus "rsRequestHead refused:" && rsLastError(), "bad"
      exit raFetch
   end if
   uiStatus "Asking the DHT for" && sFollowHandle & "...", empty
end raFetch

-- ---- phase 4: DMs ------------------------------------------------------------
-- The outbound dance (Start DM): fetch their head -> fetch + VERIFY their
-- RSK1 prekey -> join their inbox swarm -> on each rp1-capable handshake
-- there, send the sealed intro plus my stream header. Only the real
-- recipient can open the seal; a bystander's stream never authenticates
-- (its first ciphertext fails the pull), so wrong peers fall away without
-- a byte of plaintext. Inbound is the mirror: an intro arrives in MY
-- inbox, is opened + verified, and I answer with my own header.

command raDmStart
   local tHandle, tOk
   if sIdSeed is empty or sDmKeys is empty then
      uiStatus "Unlock (or create) your identity before starting a DM.", "warn"
      exit raDmStart
   end if
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: DMs need the network.", "bad"
      exit raDmStart
   end if
   put toLower(word 1 of field "raDmTo" of card "raMessages") \
         into tHandle
   if the number of chars of tHandle is not 64 then
      uiStatus "A handle is 64 hex characters (from the author's Feed card).", "warn"
      exit raDmStart
   end if
   if tHandle is sHandle then
      uiStatus "That is your own handle; DM someone else.", "warn"
      exit raDmStart
   end if
   put tHandle into sDmTarget
   put empty into sDmTargetKx
   put "true" into sDmAwaitDmHead
   put the milliseconds + kDhtWaitMs into sWaitUntil
   put rsRequestHead(sSession, sDmTarget) into tOk
   if tOk is not true then
      put empty into sDmAwaitDmHead
      uiStatus "rsRequestHead refused:" && rsLastError(), "bad"
      exit raDmStart
   end if
   raDmLog "dialing" && raDmShort(sDmTarget) & ": fetching their head..."
   uiStatus "Fetching their head from the DHT...", empty
end raDmStart

-- Their prekey record arrived: check the content address, verify the
-- author signature, and only then join their inbox swarm. A prekey that
-- fails EITHER check is a swapped key - refusing it here is what keeps
-- first contact readable only by the person the post chain belongs to.
command raDmPrekeyArrived pValue
   local tParsed, tH
   if rsImmutableTarget(pValue) is not sDmAwaitPrekey then
      raDmLog "a prekey answer did not hash to its target; ignored."
      exit raDmPrekeyArrived
   end if
   put empty into sDmAwaitPrekey
   put rsVerifyPrekey(pValue, sDmTarget) into tParsed
   if tParsed is empty then
      raDmLog "their prekey record FAILED verification:" && rsLastError()
      exit raDmPrekeyArrived
   end if
   put tParsed["kxPub"] into sDmTargetKx
   put rsDmJoinInbox(sSession, sDmTarget, raMediaFolder()) into tH
   if tH is empty then
      raDmLog "could not join their inbox swarm:" && rsLastError()
      exit raDmPrekeyArrived
   end if
   put tH into sDmTheirInbox
   raDmLog "prekey VERIFIED; waiting in their inbox swarm for a peer" && \
         "(the DHT introduces you - give it a minute)..."
end raDmPrekeyArrived

-- One rp1 event. Peer ids are stable per connection (the rp1-chat rule);
-- everything DM-shaped is keyed by them.
command raHandleRp1 pEvent
   local tPeer, tFrame, tOpened, tParsed, tPlain, tTag, tFinal, tErr
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "rp1Handshake"
         if pEvent["supportsRp1"] is not "1" then
            break
         end if
         -- a capable peer in the OUTBOUND target's inbox swarm gets the
         -- sealed intro + my stream header; anyone else is inbound-side
         -- and speaks first
         if sDmTarget is not empty and sDmTargetKx is not empty then
            if pEvent["infoHashV1"] is rsInboxId(sDmTarget) then
               raDmIntroduceTo tPeer
            end if
         end if
         break
      case "rp1Message"
         put rsDmParseFrame(pEvent["payload"]) into tFrame
         if tFrame is empty then
            break
         end if
         switch tFrame["kind"]
            case "I"
               put rsDmOpenIntro(tFrame["payload"], sHandle, sDmSeed) \
                     into tOpened
               if tOpened is empty then
                  raDmLog "an intro arrived that is not for me; ignored" && \
                        "(" & rsLastError() & ")"
                  break
               end if
               -- the freshness window (app policy; the library verifies
               -- authorship and addressing, the app bounds replay in time)
               if tOpened["timestamp"] < the seconds - kDmIntroWindow or \
                     tOpened["timestamp"] > the seconds + kDmIntroWindow then
                  raDmLog "a STALE intro from" && \
                        raDmShort(tOpened["senderHandle"]) && "(" & \
                        the seconds - tOpened["timestamp"] && \
                        "seconds old) was refused - a replay, or a badly" && \
                        "skewed clock."
                  break
               end if
               raDmLog "DM intro from" && raDmShort(tOpened["senderHandle"]) \
                     && "- answering with my stream header."
               raDmSessionUp tPeer, tOpened["senderHandle"], \
                     tOpened["senderKxPub"]
               break
            case "H"
               if sDmRxKey[tPeer] is empty then
                  break
               end if
               try
                  put sxSecretStreamInitPull(sDmRxKey[tPeer], \
                        tFrame["payload"]) into sDmPull[tPeer]
               catch tErr
                  raDmLog "their stream header failed:" && tErr
                  break
               end try
               -- the channel-open moment is also when the compose box
               -- binds to this peer; a peer that never authenticates
               -- (first "M" pull fails) is dropped right back off it
               put tPeer into sDmActivePeer
               raDmChatLine "-- channel open with" && \
                     raDmShort(sDmTheirHandle[tPeer]) && "--"
               break
            case "M"
               if sDmPull[tPeer] is empty then
                  break
               end if
               try
                  put sxSecretStreamPull(sDmPull[tPeer], \
                        tFrame["payload"], empty, tTag) into tPlain
               catch tErr
                  -- wrong peer or tamper: this connection never becomes a
                  -- conversation; drop its DM state, keep the swarm
                  raDmLog "a stream message failed authentication;" && \
                        "dropping that peer."
                  raDmDropPeer tPeer
                  break
               end try
               -- the FINAL tag is the far side's clean close (spec 5.3):
               -- a hang-up is a protocol event, not silence. The body it
               -- rides is filler by construction (raDmPushClose), so it is
               -- deliberately NOT parsed or rendered - the close line IS
               -- the message. Foreign call, so it sits in a try (rule 5)
               -- and an unreadable verdict falls through as ordinary
               -- traffic rather than closing a live conversation.
               put false into tFinal
               try
                  put sxIsFinalTag(tTag) into tFinal
               catch tErr
                  put false into tFinal
               end try
               if tFinal is true then
                  raDmChatLine "-- " & raDmShort(sDmTheirHandle[tPeer]) && \
                        "closed the conversation --"
                  raDmDropPeer tPeer
                  break
               end if
               put rsDmParseMessage(tPlain) into tParsed
               if tParsed is empty then
                  raDmLog "an authenticated but malformed message;" && \
                        "dropping that peer."
                  raDmDropPeer tPeer
                  break
               end if
               if tParsed["kind"] is "T" then
                  raDmChatLine raDmShort(sDmTheirHandle[tPeer]) & ":" && \
                        tParsed["text"]
               else if tParsed["kind"] is "O" then
                  raDmCallIncoming tParsed["text"]
               else if tParsed["kind"] is "A" then
                  raDmCallAnswered tParsed["text"]
               end if
               break
         end switch
         break
      case "rp1PeerDisconnected"
         if sDmTheirHandle[tPeer] is not empty then
            raDmChatLine "-- " & raDmShort(sDmTheirHandle[tPeer]) && \
                  "disconnected --"
         end if
         raDmDropPeer tPeer
         break
   end switch
end raHandleRp1

-- Outbound first contact to one peer in the target's inbox swarm.
command raDmIntroduceTo pPeer
   local tIntro, tSealed, tFrame, tOk
   if sDmTheirHandle[pPeer] is not empty then
      exit raDmIntroduceTo
   end if
   put rsBuildIntro(the seconds, sDmTarget, sDmKeys["publicKeyHex"], \
         sIdSeed) into tIntro
   if tIntro is empty then
      raDmLog "intro build refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   put rsDmSealIntro(tIntro, sDmTargetKx) into tSealed
   if tSealed is empty then
      raDmLog "intro seal refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   put rsDmFrame("I", tSealed) into tFrame
   if tFrame is empty then
      exit raDmIntroduceTo
   end if
   put rsDmSend(sSession, pPeer, tFrame) into tOk
   if tOk is not true then
      raDmLog "intro send refused:" && rsLastError()
      exit raDmIntroduceTo
   end if
   raDmLog "sealed intro sent to peer" && pPeer & \
         "; opening my stream side..."
   raDmSessionUp pPeer, sDmTarget, sDmTargetKx
end raDmIntroduceTo

-- Shared by both directions: derive the pairwise session for this peer,
-- start MY push stream, and send its header. The pull side arrives as
-- their "H" frame and is inited in the dispatcher.
command raDmSessionUp pPeer, pTheirHandle, pTheirKxPub
   local tSess, tHeader, tFrame, tOk, tErr
   if sDmPush[pPeer] is not empty then
      exit raDmSessionUp
   end if
   put rsDmSessionKeys(sHandle, sDmKeys, pTheirHandle, pTheirKxPub) \
         into tSess
   if tSess is empty then
      raDmLog "session derivation refused:" && rsLastError()
      exit raDmSessionUp
   end if
   put pTheirHandle into sDmTheirHandle[pPeer]
   put tSess["rx"] into sDmRxKey[pPeer]
   put tSess["tx"] into sDmTxKey[pPeer]
   try
      put sxSecretStreamInitPush(sDmTxKey[pPeer], tHeader) into \
            sDmPush[pPeer]
   catch tErr
      raDmLog "stream init failed:" && tErr
      raDmDropPeer pPeer
      exit raDmSessionUp
   end try
   put rsDmFrame("H", tHeader) into tFrame
   if tFrame is empty then
      raDmLog "header frame refused:" && rsLastError()
      raDmDropPeer pPeer
      exit raDmSessionUp
   end if
   put rsDmSend(sSession, pPeer, tFrame) into tOk
   if tOk is not true then
      raDmLog "header send refused:" && rsLastError()
      raDmDropPeer pPeer
      exit raDmSessionUp
   end if
end raDmSessionUp

-- Forget one peer's DM state, freeing its stream handles (idempotent).
command raDmDropPeer pPeer
   local tErr
   if sDmPush[pPeer] is not empty then
      try
         sxFreeStream sDmPush[pPeer]
      catch tErr
      end try
   end if
   if sDmPull[pPeer] is not empty then
      try
         sxFreeStream sDmPull[pPeer]
      catch tErr
      end try
   end if
   delete variable sDmPush[pPeer]
   delete variable sDmPull[pPeer]
   delete variable sDmTheirHandle[pPeer]
   delete variable sDmRxKey[pPeer]
   delete variable sDmTxKey[pPeer]
   if sDmActivePeer is pPeer then
      put empty into sDmActivePeer
   end if
end raDmDropPeer

command raDmSend
   local tBody, tOk
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      uiStatus "No open conversation yet: Start DM and wait for the" && \
            "channel-open line.", "warn"
      exit raDmSend
   end if
   put field "raDmMsg" of card "raMessages" into tBody
   if tBody is empty then
      exit raDmSend
   end if
   put raDmSendMessage("T", tBody) into tOk
   if tOk is not true then
      uiStatus "send refused:" && rsLastError(), "bad"
      exit raDmSend
   end if
   raDmChatLine "you:" && tBody
   set the text of field "raDmMsg" of card "raMessages" to empty
end raDmSend

-- One message of any kind into the ACTIVE conversation's secretstream.
-- "T" is chat; "O"/"A" carry the phase-5 SDP signalling over the same
-- authenticated encrypted rail (the whole point of the kinds existing).
-- Returns true/false. rsSetError is PRIVATE to the library, so a failure
-- here that is not a library refusal logs its reason to the chat directly
-- (callers guard the no-conversation case before calling).
private function raDmSendMessage pKind, pBody
   local tMsg, tCipher, tFrame, tOk, tErr
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      return false
   end if
   put rsDmMessageBody(pKind, the seconds, pBody) into tMsg
   if tMsg is empty then
      return false
   end if
   -- final is FALSE on every ordinary message on purpose: the FINAL tag
   -- ends the stream for good, so it belongs to exactly one caller
   -- (raDmPushClose, at teardown) and nothing else may spend it
   try
      put sxSecretStreamPush(sDmPush[sDmActivePeer], tMsg, empty, false) \
            into tCipher
   catch tErr
      raDmChatLine "-- send failed: stream push:" && tErr && "--"
      return false
   end try
   put rsDmFrame("M", tCipher) into tFrame
   if tFrame is empty then
      return false
   end if
   put rsDmSend(sSession, sDmActivePeer, tFrame) into tOk
   return tOk is true
end raDmSendMessage

-- ---- phase 5: the live session (a dc call over the DM rail) ------------------
-- The cold-start problem phase 5 exists to solve is ALREADY solved by
-- phase 4: the secretstream is an authenticated, encrypted, ordered
-- channel between exactly the two of us, so the SDP offer/answer ride it
-- as kind-"O"/"A" messages (no dead drop needed - that design remains in
-- dht-chat for the no-prior-contact case). One-blob signalling: we wait
-- for ICE gathering to COMPLETE, then ship a single SDP carrying its
-- candidates; the far side does the same. libdatachannel auto-negotiates:
-- the caller's first dcCreateChannel triggers the offer, and applying an
-- offer auto-generates the answer. Once the channel opens, the payload
-- path is DIRECT peer-to-peer - the rp1 rail carried only the signalling.

-- Lazily bring datachannelxt up once. Returns "true" or logs why not.
private function raDcEnsureInit
   local tR, tErr
   if sDcInit is "true" then
      return "true"
   end if
   try
      put dcInit() into tR
   catch tErr
      raDmChatLine "-- calls need dataChannelXT (org.openxtalk.library.datachannel); not installed --"
      return "false"
   end try
   if tR is not 0 then
      raDmChatLine "-- dataChannelXT failed to initialise:" && dcLastError() && "--"
      return "false"
   end if
   put "true" into sDcInit
   return "true"
end raDcEnsureInit

-- The Call button: start a call on the active conversation, or hang up.
command raDmCall
   local tChan
   if sDcPeer is not empty then
      raDmChatLine "-- you hung up --"
      get raDmSendMessage("T", "(hung up)")
      raDcTeardown
      exit raDmCall
   end if
   if sDmActivePeer is empty or sDmPush[sDmActivePeer] is empty then
      uiStatus "Open a conversation first: a call rides the DM channel.", "warn"
      exit raDmCall
   end if
   -- the persona guard, at the one branch that opens a NEW transport
   if not rsPersonaAllows(false, "dc") then
      raDmChatLine "-- the guard refused a dc call; this is a bug --"
      exit raDmCall
   end if
   if raDcEnsureInit() is not "true" then
      exit raDmCall
   end if
   put dcCreatePeer(kDmIce) into sDcPeer
   if sDcPeer is 0 or sDcPeer is empty then
      raDmChatLine "-- dcCreatePeer failed:" && dcLastError() && "--"
      put empty into sDcPeer
      exit raDmCall
   end if
   raDcTypingReset
   -- the first channel triggers the offer (auto-negotiation)
   put dcCreateChannel(sDcPeer, "riptide-call") into tChan
   if tChan is 0 or tChan is empty then
      raDmChatLine "-- dcCreateChannel failed:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCall
   end if
   put tChan into sDcChannel
   -- the typing lane (spec 6.2), created BEFORE gathering so both
   -- channels ride the one offer: unordered, maxRetransmits 0 - a
   -- deliberately lossy sub-stream for absolute state you overwrite.
   -- A refusal is non-fatal: the call works without the lane.
   put dcCreateChannelEx(sDcPeer, kDcTypingLabel, "", true, 0, -1, \
         false, -1) into tChan
   if tChan is 0 or tChan is empty then
      raDmChatLine "-- no typing lane (dcCreateChannelEx refused:" && \
            dcLastError() & "); the call continues without it --"
   else
      put tChan into sDcTypingChan
   end if
   put "O" into sDcAwaitLocal
   raDmChatLine "-- calling: gathering ICE candidates... --"
end raDmCall

-- An SDP offer arrived inside the secretstream (the far side pressed Call).
command raDmCallIncoming pSdp
   local tR
   if sDcPeer is not empty then
      raDmChatLine "-- incoming call ignored: already in one --"
      exit raDmCallIncoming
   end if
   if raDcEnsureInit() is not "true" then
      exit raDmCallIncoming
   end if
   put dcCreatePeer(kDmIce) into sDcPeer
   if sDcPeer is 0 or sDcPeer is empty then
      raDmChatLine "-- dcCreatePeer failed:" && dcLastError() && "--"
      put empty into sDcPeer
      exit raDmCallIncoming
   end if
   -- the caller opens BOTH channels (call + typing lane); they arrive
   -- here as dcChannelIncoming events, routed by label
   raDcTypingReset
   put dcSetRemoteDescription(sDcPeer, pSdp, "offer") into tR
   if tR is not 0 then
      raDmChatLine "-- their offer was refused:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCallIncoming
   end if
   -- auto-negotiation generates our answer; ship it when gathering is done
   put "A" into sDcAwaitLocal
   raDmChatLine "-- incoming call: answering (gathering candidates)... --"
end raDmCallIncoming

-- Their answer arrived: apply it and let ICE connect.
command raDmCallAnswered pSdp
   local tR
   if sDcPeer is empty then
      exit raDmCallAnswered
   end if
   put dcSetRemoteDescription(sDcPeer, pSdp, "answer") into tR
   if tR is not 0 then
      raDmChatLine "-- their answer was refused:" && dcLastError() && "--"
      raDcTeardown
      exit raDmCallAnswered
   end if
   raDmChatLine "-- answer applied; connecting... --"
end raDmCallAnswered

-- Ship our one-blob local SDP once ICE gathering completes (called from
-- the pump while sDcAwaitLocal is armed). kGatheringComplete is 2.
command raDmCallShipLocal
   local tSdp, tKind
   if dcGatheringState(sDcPeer) is not 2 then
      exit raDmCallShipLocal
   end if
   put dcLocalDescription(sDcPeer) into tSdp
   if tSdp is empty then
      exit raDmCallShipLocal
   end if
   put sDcAwaitLocal into tKind
   put empty into sDcAwaitLocal
   if raDmSendMessage(tKind, tSdp) is true then
      if tKind is "O" then
         raDmChatLine "-- offer sent over the encrypted DM channel --"
      else
         raDmChatLine "-- answer sent; connecting... --"
      end if
   else
      raDmChatLine "-- could not send the SDP; hang up and retry --"
   end if
end raDmCallShipLocal

-- One dc event (drained by the pump).
command raHandleDc pEvent
   local tPair
   switch pEvent["name"]
      case "dcChannelIncoming"
         -- the callee learns the caller's channels here; TWO arrive since
         -- the typing lane landed (spec 6.2), so route by LABEL, never by
         -- arrival order
         if dcChannelLabel(pEvent["channel"]) is kDcTypingLabel then
            put pEvent["channel"] into sDcTypingChan
         else
            put pEvent["channel"] into sDcChannel
         end if
         break
      case "dcChannelOpen"
         if pEvent["channel"] is not sDcChannel then
            break
         end if
         put dcSelectedCandidatePair(sDcPeer) into tPair
         raDmChatLine "-- CALL CONNECTED: direct peer-to-peer channel open --"
         if tPair["localCandidate"] is not empty then
            raDmChatLine "--   via" && tPair["localCandidate"] && "--"
         end if
         -- one greeting proves the direct path carries data both ways
         get dcSendText(sDcChannel, "live from" && raDmShort(sHandle))
         break
      case "dcMessage"
         if sDcTypingChan is not empty and \
               pEvent["channel"] is sDcTypingChan then
            -- absolute typing state: "1" typing, anything else not; a
            -- lost "0" self-heals via the deadline in raDmTypingTick
            if pEvent["text"] is "1" then
               put "true" into sDcPeerTyping
               put the milliseconds into sDcPeerTypingAt
            else
               put empty into sDcPeerTyping
            end if
            raDmPaintTyping
         else if pEvent["text"] is not empty then
            raDmChatLine "-- call:" && pEvent["text"] && "--"
         end if
         break
      case "dcChannelClosed"
         if sDcTypingChan is not empty and \
               pEvent["channel"] is sDcTypingChan then
            -- the lane died alone; the call itself survives
            put empty into sDcTypingChan
            put empty into sDcPeerTyping
            raDmPaintTyping
         else if pEvent["channel"] is sDcChannel then
            raDmChatLine "-- call ended --"
            raDcTeardown
         end if
         break
      case "dcStateChange"
         -- kPeerStateFailed 4 / kPeerStateClosed 5 end the call; anything
         -- else is progress
         if sDcPeer is not empty and pEvent["peer"] is sDcPeer then
            if pEvent["state"] is 4 or pEvent["state"] is 5 then
               raDmChatLine "-- call failed or closed (state" && \
                     pEvent["state"] & ") --"
               raDcTeardown
            end if
         end if
         break
   end switch
end raHandleDc

-- End the call and free the dc handles (dcFreePeer frees its channels
-- too; idempotent). The DM conversation stays up - only the call dies.
command raDcTeardown
   local tErr
   if sDcPeer is not empty then
      try
         dcFreePeer sDcPeer
      catch tErr
         -- extension gone or peer already freed
      end try
   end if
   put empty into sDcPeer
   put empty into sDcChannel
   put empty into sDcAwaitLocal
   raDcTypingReset
   raDmPaintTyping
end raDcTeardown

-- Reset the typing lane's state (call setup and teardown). Numerics get
-- 0, not empty: the tick does arithmetic on them every pump pass.
private command raDcTypingReset
   put empty into sDcTypingChan
   put empty into sDcTypingSeen
   put 0 into sDcTypingUntil
   put empty into sDcTypingSent
   put 0 into sDcTypingSentAt
   put empty into sDcPeerTyping
   put 0 into sDcPeerTypingAt
end raDcTypingReset

-- The typing-lane tick (pump-driven, spec 6.2): watch the compose field,
-- send ABSOLUTE state on the lossy channel - "1" while edits are fresh,
-- "0" after the deadline - re-sent on a cadence because maxRetransmits-0
-- drops are expected, and expire the far side's "typing" locally so a
-- lost "0" cannot stick. Cross-card law: the compose field lives on the
-- Messages card and the pump runs anywhere - qualify and guard.
command raDmTypingTick
   local tNow, tText, tMine, tErr
   if sDcTypingChan is empty then
      exit raDmTypingTick
   end if
   set the caseSensitive to true
   put the milliseconds into tNow
   if there is a field "raDmMsg" of card "raMessages" then
      put the text of field "raDmMsg" of card "raMessages" into tText
      if tText is not sDcTypingSeen then
         put tText into sDcTypingSeen
         put tNow + kDcTypingMs into sDcTypingUntil
      end if
   end if
   if tNow < sDcTypingUntil then
      put "1" into tMine
   else
      put "0" into tMine
   end if
   if tMine is not sDcTypingSent or \
         tNow - sDcTypingSentAt >= kDcTypingSendMs then
      try
         if dcChannelIsOpen(sDcTypingChan) is true then
            get dcSendText(sDcTypingChan, tMine)
            put tMine into sDcTypingSent
            put tNow into sDcTypingSentAt
         end if
      catch tErr
         -- lane hiccup; absolute state means the next send repairs it
      end try
   end if
   if sDcPeerTyping is "true" and \
         tNow - sDcPeerTypingAt >= kDcTypingMs then
      put empty into sDcPeerTyping
      raDmPaintTyping
   end if
end raDmTypingTick

-- Paint the far side's typing state on the Messages card (guarded: the
-- pump runs from every card, and the field only exists once built).
command raDmPaintTyping
   local tLine
   if there is no field "raDmTyping" of card "raMessages" then
      exit raDmPaintTyping
   end if
   if sDcPeerTyping is "true" then
      put "the far side is typing..." into tLine
   else
      put empty into tLine
   end if
   if the text of field "raDmTyping" of card "raMessages" is not tLine then
      set the text of field "raDmTyping" of card "raMessages" to tLine
   end if
end raDmPaintTyping

-- ---- phase 6: the LAN device mesh --------------------------------------------
-- enet, not the DHT: your devices meet on the LAN and prove they share
-- your master seed. Admission is a first-message challenge/response (the
-- enConnect rider is only a u32 protocol tag). The host challenges every
-- new peer; a peer that answers with a signature the host's OWN master
-- verifies is admitted, everyone else is dropped. Past admission the
-- SYNC PAYLOAD flows (the raLanSync* half further down): signed drafts +
-- feed state on channel 0, signed presence/typing on channel 1. All the
-- crypto is the gated rsLan* layer; this is the enet transport around it.

-- Lazily bring enet up once (refcounted global init). Returns "true" on
-- success; fail-closed with a logged reason.
private function raLanEnsureInit
   local tR, tErr
   if sLanInit is "true" then
      return "true"
   end if
   try
      put enInitialize() into tR
   catch tErr
      raLanLog "enetxt is not installed (org.openxtalk.library.enet); the device mesh needs it."
      return "false"
   end try
   if tR is not 0 then
      raLanLog "enetxt failed to initialise:" && enLastError()
      return "false"
   end if
   put "true" into sLanInit
   return "true"
end raLanEnsureInit

command raLanHost
   local tHost, tErr
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the mesh admission needs your master seed.", "warn"
      exit raLanHost
   end if
   if sLanHost is not empty then
      raLanLog "Already on a mesh; Leave first."
      exit raLanHost
   end if
   if raLanEnsureInit() is not "true" then
      exit raLanHost
   end if
   put raLanMyName() into sLanName
   -- bind on EVERY interface ("" - the proven LAN spelling), a small peer
   -- cap, THREE channels (spec section 7: 0 control + drafts + feed
   -- state, 1 presence/typing, 2 reserved for bulk handoff - unbuilt,
   -- allocated so both sides already agree when it lands), unmetered
   try
      put enHostCreateServer("", kLanPort, 32, 3, 0, 0) into tHost
   catch tErr
      raLanLog "could not create the host:" && tErr
      exit raLanHost
   end try
   if tHost is empty or tHost is 0 then
      raLanLog "could not create the host:" && enLastError()
      exit raLanHost
   end if
   put tHost into sLanHost
   put "true" into sLanIsServer
   put empty into sLanChallenges
   put empty into sLanDevices
   raLanSyncReset
   raLanLog "Hosting the mesh on port" && kLanPort & \
         ". On your other devices, Join this device's LAN IP."
   raLanPaintDevices
end raLanHost

command raLanJoin
   local tIp, tHost, tPeer, tErr
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the mesh admission needs your master seed.", "warn"
      exit raLanJoin
   end if
   if sLanHost is not empty then
      raLanLog "Already on a mesh; Leave first."
      exit raLanJoin
   end if
   put word 1 of field "raLanTo" of card "raDevices" into tIp
   if tIp is empty then
      uiStatus "Type the host device's LAN IP address first.", "warn"
      exit raLanJoin
   end if
   if raLanEnsureInit() is not "true" then
      exit raLanJoin
   end if
   put raLanMyName() into sLanName
   try
      put enHostCreateClient(1, 3, 0, 0) into tHost
   catch tErr
      raLanLog "could not create the client host:" && tErr
      exit raLanJoin
   end try
   if tHost is empty or tHost is 0 then
      raLanLog "could not create the client host:" && enLastError()
      exit raLanJoin
   end if
   put tHost into sLanHost
   put "false" into sLanIsServer
   put empty into sLanDevices
   raLanSyncReset
   -- optimistic peer handle now; the enetConnect event confirms it. The
   -- rider is our u32 protocol tag, checked by the host before the crypto.
   try
      put enConnect(sLanHost, tIp, kLanPort, 3, kLanProto) into tPeer
   catch tErr
      raLanLog "connect failed:" && tErr
      raLanLeave
      exit raLanJoin
   end try
   if tPeer is empty or tPeer is 0 then
      raLanLog "connect failed:" && enLastError()
      raLanLeave
      exit raLanJoin
   end if
   put tPeer into sLanServerPeer
   raLanLog "connecting to" && tIp & "; waiting for the host's challenge..."
   raLanPaintDevices
end raLanJoin

command raLanLeave
   local tErr
   if sLanHost is not empty and sLanHost is not 0 then
      try
         enHostDestroy sLanHost
      catch tErr
         -- extension gone or host already dead
      end try
   end if
   put empty into sLanHost
   put empty into sLanIsServer
   put empty into sLanServerPeer
   put empty into sLanChallenges
   put empty into sLanMyResponse
   put empty into sLanDevices
   raLanSyncReset
   raLanPaintDevices
end raLanLeave

-- One enet event. The host challenges each new peer; the joiner answers
-- the challenge; the host verifies and admits or drops.
command raHandleEnet pEvent
   local tPeer, tName, tChallenge, tNonce, tResp, tRec, tKind, tErr
   put pEvent["peer"] into tPeer
   switch pEvent["name"]
      case "enetConnect"
         if sLanIsServer is "true" then
            -- refuse a mismatched protocol before spending a challenge
            if pEvent["data"] is not kLanProto then
               raLanLog "refused a peer speaking protocol" && \
                     pEvent["data"] & "; dropping."
               try
                  enDisconnectNow tPeer, 0
               catch tErr
               end try
               break
            end if
            put sxRandomBytes(32) into tNonce
            put rsLanBuildChallenge(sLanName, tNonce) into tChallenge
            if tChallenge is empty then
               raLanLog "challenge build refused:" && rsLastError()
               break
            end if
            put tChallenge into sLanChallenges[tPeer]
            raLanSend tPeer, tChallenge
         end if
         -- a client just waits for the challenge to arrive as a message
         break
      case "enetReceive"
         put rsLanRecordKind(pEvent["payload"]) into tKind
         if tKind is "C" and sLanIsServer is not "true" then
            -- joiner: sign the host's challenge under our master, and keep
            -- the response - the host's welcome must be bound to it
            put rsLanBuildResponse(pEvent["payload"], sLanName, \
                  sMasterSeed) into tResp
            if tResp is empty then
               raLanLog "response build refused:" && rsLastError()
               break
            end if
            put tResp into sLanMyResponse
            raLanSend tPeer, tResp
            raLanLog "answered the host's challenge; awaiting the welcome."
         else if tKind is "W" and sLanIsServer is not "true" then
            -- joiner: the host's welcome must prove IT shares the master,
            -- for THIS handshake (mutual auth - and the positive signal
            -- the joiner previously never got)
            put rsLanVerifyWelcome(pEvent["payload"], sLanMyResponse, \
                  sMasterSeed) into tName
            if tName is empty then
               raLanLog "the host FAILED to prove itself (not your" && \
                     "device):" && rsLastError() & "; leaving."
               raLanLeave
               break
            end if
            put tName into sLanDevices[tPeer]
            raLanLog "ADMITTED - the host" && quote & tName & quote && \
                  "proved it shares your master. Mesh is mutual."
            raLanPaintDevices
         else if tKind is "R" and sLanIsServer is "true" then
            -- host: verify against the challenge WE sent this peer
            put sLanChallenges[tPeer] into tChallenge
            if tChallenge is empty then
               break
            end if
            put rsLanVerifyResponse(pEvent["payload"], tChallenge, \
                  sMasterSeed) into tName
            if tName is empty then
               raLanLog "a peer FAILED admission (not your device):" && \
                     rsLastError() & "; dropping."
               try
                  enDisconnectNow tPeer, 0
               catch tErr
               end try
               delete variable sLanChallenges[tPeer]
               break
            end if
            put tName into sLanDevices[tPeer]
            delete variable sLanChallenges[tPeer]
            raLanLog "admitted" && quote & tName & quote & \
                  "(it proved it shares your master)."
            -- prove ourselves BACK (mutual auth): the welcome is bound to
            -- this joiner's response, so it admits no other session
            put rsLanBuildWelcome(pEvent["payload"], sLanName, sMasterSeed) \
                  into tChallenge
            if tChallenge is empty then
               raLanLog "welcome build refused:" && rsLastError()
            else
               raLanSend tPeer, tChallenge
            end if
            raLanPaintDevices
         else if tKind is "D" or tKind is "F" or tKind is "P" or \
               tKind is "M" then
            -- the phase-6 sync records: verify-then-apply, admitted
            -- peers only, refusals logged (the runbook's stranger line)
            raLanSyncReceive tPeer, tKind, pEvent["payload"]
         end if
         break
      case "enetDisconnect"
         if sLanDevices[tPeer] is not empty then
            raLanLog quote & sLanDevices[tPeer] & quote && "left the mesh."
            delete variable sLanDevices[tPeer]
            raLanPaintDevices
         end if
         -- drop the sync state this LINK fed us, by the device names it
         -- contributed - the state is keyed by signing device now, and one
         -- link can carry many devices (a joiner sees every relayed device
         -- over the host's single peer). A rejoin gets fresh monotonic
         -- tracking, exactly as before. The media OFFER deliberately
         -- survives - the swarm it points at outlives the mesh, and a
         -- mid-download must not lose its Fetch button.
         raLanDropPeerNames tPeer
         raLanPaintDrafts
         if tPeer is sLanServerPeer then
            raLanLog "the host went away; Leave and re-Join to reconnect."
            put empty into sLanServerPeer
         end if
         break
   end switch
end raHandleEnet

-- Which RSL1 record is this (by its 5th byte, the kind), or empty. A
-- lighter touch than a full parse just to route in the dispatcher.
private function rsLanRecordKind pBytes
   if the number of bytes in pBytes < 5 then return empty
   if textDecode(byte 1 to 4 of pBytes, "ASCII") is not "RSL1" then
      return empty
   end if
   return textDecode(byte 5 of pBytes, "ASCII")
end rsLanRecordKind

private command raLanSend pPeer, pBytes
   local tErr
   try
      enSend pPeer, 0, pBytes, 0
   catch tErr
      raLanLog "send to peer" && pPeer && "failed:" && tErr
   end try
end raLanSend

-- ---- the phase-6 sync payload over the admitted mesh -------------------------
-- Spec section 7's channel discipline on top of the admission above:
-- drafts + feed state ride channel 0 reliable, presence/typing rides
-- channel 1 unreliable-unsequenced (flag 2 - the record's own monotonic
-- tick makes it reorder-proof, so enet sequencing would only mask what
-- the record must survive anyway). Every record is signed under the
-- shared LAN key (the rsLan* sync layer); every inbound record is
-- verify-then-apply, admitted peers only, and every apply is monotonic
-- or absolute so replays and reorders are no-ops.

-- Reset the sync state (Host, Join, and Leave). The per-device counters
-- seed from the clock so a leave-and-rejoin still moves strictly forward
-- past anything a receiver already applied for an earlier session.
private command raLanSyncReset
   put the seconds into sLanSeq
   put the seconds into sLanTick
   put empty into sLanDraftLast
   put empty into sLanDraftSeen
   put 0 into sLanDraftNextOk
   put 0 into sLanPresenceAt
   put 0 into sLanTypingUntil
   put 0 into sLanFeedLast
   put empty into sLanPeerSeq
   put empty into sLanPeerDraft
   put empty into sLanPeerTick
   put empty into sLanPeerTyping
   put empty into sLanPeerSeen
   put empty into sLanPeerNames
   -- the media handoff: per-device replay tracking resets with the mesh
   -- (a new mesh may be a different set of devices); the OFFER itself and
   -- its watched fetch survive on purpose - the torrent rail outlives the
   -- mesh
   put empty into sLanPeerMediaSeq
   raLanPaintDrafts
end raLanSyncReset

-- Remember that this LINK carried this device, so a disconnect can drop
-- exactly the state it fed us. Called on every APPLIED record (a refused
-- one must leave no trace). Names are a nested set, never a delimited
-- list: a device name is arbitrary UTF-8 up to the library's cap and may
-- legitimately contain a return, which would corrupt a line list.
private command raLanNoteName pPeer, pName
   if pName is empty then
      exit raLanNoteName
   end if
   put "true" into sLanPeerNames[pPeer][pName]
end raLanNoteName

-- The disconnect half: forget every device this link contributed. On a
-- host that is the single device it admitted; on a joiner, losing the
-- host loses every device the host was relaying, which is the truth -
-- a joiner has no other link to hear them over.
private command raLanDropPeerNames pPeer
   local tNames, tDev
   put sLanPeerNames[pPeer] into tNames
   delete variable sLanPeerNames[pPeer]
   -- lifted out and type-guarded rather than iterated in place. The COMMON
   -- disconnect here is a peer that contributed nothing (a stranger the
   -- admission dropped, or an admitted device that never got a record in),
   -- so this element is usually ABSENT. Iterating an empty top-level array
   -- local is proven in this file - raDmTeardown walks an empty sDmPush on
   -- every quit that never opened a DM - but iterating a MISSING nested
   -- element is a different shape and nothing here has run it on an
   -- engine. The demo is this member's least-verified surface; guard.
   if tNames is not an array then
      exit raLanDropPeerNames
   end if
   repeat for each key tDev in tNames
      delete variable sLanPeerSeq[tDev]
      delete variable sLanPeerDraft[tDev]
      delete variable sLanPeerTick[tDev]
      delete variable sLanPeerTyping[tDev]
      delete variable sLanPeerSeen[tDev]
      delete variable sLanPeerMediaSeq[tDev]
   end repeat
end raLanDropPeerNames

-- One sync record to every ADMITTED peer - never enBroadcast: a
-- broadcast would also reach a connected-but-unadmitted stranger in its
-- pre-drop window, and drafts are plaintext.
private command raLanSyncSend pChannel, pBytes, pFlags
   local tPeer, tErr
   repeat for each key tPeer in sLanDevices
      try
         enSend tPeer, pChannel, pBytes, pFlags
      catch tErr
         raLanLog "sync send to peer" && tPeer && "failed:" && tErr
      end try
   end repeat
end raLanSyncSend

-- The host RELAYS a verified record to the other admitted devices, bytes
-- intact (hub-and-spoke: joiners only ever see the host). The signature
-- verifies anywhere - which is exactly why the sync signature carries no
-- per-handshake binder (the recorded library design).
private command raLanRelay pFromPeer, pKind, pBytes
   local tPeer, tErr
   if sLanIsServer is not "true" then
      exit raLanRelay
   end if
   repeat for each key tPeer in sLanDevices
      if tPeer is pFromPeer then
         next repeat
      end if
      try
         if pKind is "P" then
            enSend tPeer, 1, pBytes, 2
         else
            enSend tPeer, 0, pBytes, 0
         end if
      catch tErr
         raLanLog "relay to peer" && tPeer && "failed:" && tErr
      end try
   end repeat
end raLanRelay

-- The pump-driven sync tick: the draft field read on the timer and
-- broadcast at most once per debounce window (never per keystroke), the
-- feed seq broadcast on change, presence re-asserted on its cadence as
-- ABSOLUTE state. Cross-card law: the draft field lives on the Devices
-- card and the pump runs anywhere - qualify and guard every reference.
command raLanSyncTick
   local tNow, tText, tTyping, tBytes
   if sMasterSeed is empty or sLanName is empty then
      exit raLanSyncTick
   end if
   if the number of lines of the keys of sLanDevices is 0 then
      exit raLanSyncTick
   end if
   set the caseSensitive to true
   put the milliseconds into tNow
   -- the draft (channel 0, reliable): absolute state, converging - the
   -- record is re-sent on a later tick as long as the field differs from
   -- the last state actually broadcast
   if there is a field "raLanDraft" of card "raDevices" then
      put the text of field "raLanDraft" of card "raDevices" into tText
      if tText is not sLanDraftSeen then
         put tText into sLanDraftSeen
         put tNow + kLanTypingMs into sLanTypingUntil
      end if
      if tText is not sLanDraftLast and tNow >= sLanDraftNextOk then
         add 1 to sLanSeq
         put rsLanBuildDraft(sLanName, sLanSeq, tText, sMasterSeed) \
               into tBytes
         if tBytes is empty then
            raLanLog "draft sync refused:" && rsLastError()
            -- adopt the state anyway so one over-cap draft does not log
            -- on every tick; the next EDIT retries
            put tText into sLanDraftLast
         else
            raLanSyncSend 0, tBytes, 0
            put tText into sLanDraftLast
            put tNow + kLanDraftDebounceMs into sLanDraftNextOk
         end if
      end if
   end if
   -- the feed seq claim (channel 0): two devices must never publish a
   -- conflicting head, so each broadcasts its latest and adopts the max.
   -- The demo has no per-conversation read state to publish, so the
   -- record's read-receipt half travels as the none spelling (received
   -- receipts are still verified and logged).
   if sSeq is an integer and sSeq > 0 and sSeq is not sLanFeedLast then
      put rsLanBuildFeedState(sLanName, sSeq, empty, 0, sMasterSeed) \
            into tBytes
      if tBytes is not empty then
         raLanSyncSend 0, tBytes, 0
         put sSeq into sLanFeedLast
      end if
   end if
   -- presence/typing (channel 1, flag 2 - droppable by design, so it is
   -- re-asserted every interval whether or not anything changed)
   if tNow - sLanPresenceAt >= kLanPresenceMs then
      put tNow < sLanTypingUntil into tTyping
      add 1 to sLanTick
      put rsLanBuildPresence(sLanName, tTyping, sLanTick, sMasterSeed) \
            into tBytes
      if tBytes is not empty then
         raLanSyncSend 1, tBytes, 2
         put tNow into sLanPresenceAt
      end if
   end if
   -- the panel repaint used to hang off the end of this handler, which was
   -- fine while the pump only ran at 4 Hz. It rides raPoll's repaint tier
   -- now instead: the [typing]/[quiet] markers age against the clock and
   -- so need a PERIODIC repaint, not a per-tick one, and this handler runs
   -- 30 times a second whenever a mesh is up. The event-driven repaints
   -- (admission, welcome, disconnect, an applied presence record) are
   -- unchanged and still immediate.
end raLanSyncTick

-- One inbound sync record. Order of refusals, each logged distinctly:
-- an unadmitted sender first (nothing from a peer that never proved the
-- master is even verified), then the library's verify-then-parse (a bad
-- signature IS the stranger case the runbook watches for), then the
-- monotonic apply (a replay or reorder is a silent no-op, not an error).
command raLanSyncReceive pPeer, pKind, pBytes
   local tRec, tLast, tDev
   if sLanDevices[pPeer] is empty then
      raLanLog "stranger record refused (unadmitted peer): kind" && pKind
      exit raLanSyncReceive
   end if
   if sMasterSeed is empty then
      exit raLanSyncReceive
   end if
   if pKind is "D" then
      put rsLanVerifyDraft(pBytes, sMasterSeed) into tRec
      if tRec is empty then
         raLanLog "stranger record refused:" && rsLastError()
         exit raLanSyncReceive
      end if
      -- key by the SIGNING DEVICE, which the signature above just proved
      -- and which the library's contract names ("a seq strictly above the
      -- last one applied FOR THAT DEVICE"). The peer is only the LINK it
      -- came over, and on a joiner that link is the host for every device.
      put tRec["name"] into tDev
      put sLanPeerSeq[tDev] into tLast
      if tLast is empty then
         put -1 into tLast
      end if
      if tRec["seq"] <= tLast then
         exit raLanSyncReceive
      end if
      raLanNoteName pPeer, tDev
      put tRec["seq"] into sLanPeerSeq[tDev]
      put tRec["draft"] into sLanPeerDraft[tDev]
      raLanLog "draft from" && tDev && "seq" && tRec["seq"] && \
            "applied"
      raLanPaintDrafts
      raLanRelay pPeer, pKind, pBytes
   else if pKind is "F" then
      put rsLanVerifyFeedState(pBytes, sMasterSeed) into tRec
      if tRec is empty then
         raLanLog "stranger record refused:" && rsLastError()
         exit raLanSyncReceive
      end if
      if tRec["feedSeq"] > sSeq then
         put tRec["feedSeq"] into sSeq
         put sSeq into sLanFeedLast
         raLanLog "feed seq" && sSeq && "adopted from" && tRec["name"] & \
               "; the next post publishes above it"
      end if
      if tRec["readPeer"] is not empty then
         raLanLog "read receipt from" && tRec["name"] & ":" && \
               (char 1 to 12 of tRec["readPeer"]) & "... up to" && \
               tRec["readUpTo"]
      end if
      -- deliberately NOT keyed or noted: feed state is max-applied into
      -- ONE global seq, so there is no per-device slot to collide and
      -- nothing for a disconnect to drop
      raLanRelay pPeer, pKind, pBytes
   else if pKind is "P" then
      put rsLanVerifyPresence(pBytes, sMasterSeed) into tRec
      if tRec is empty then
         raLanLog "stranger record refused:" && rsLastError()
         exit raLanSyncReceive
      end if
      -- by device, not by link: presence is what the Devices panel paints
      -- from, so keyed by peer a joiner's relayed devices would overwrite
      -- the host's row instead of getting one of their own
      put tRec["name"] into tDev
      put sLanPeerTick[tDev] into tLast
      if tLast is empty then
         put -1 into tLast
      end if
      if tRec["tick"] <= tLast then
         exit raLanSyncReceive
      end if
      raLanNoteName pPeer, tDev
      put tRec["tick"] into sLanPeerTick[tDev]
      if tRec["typing"] is true then
         put "true" into sLanPeerTyping[tDev]
      else
         put empty into sLanPeerTyping[tDev]
      end if
      put the milliseconds into sLanPeerSeen[tDev]
      raLanPaintDevices
      raLanRelay pPeer, pKind, pBytes
   else if pKind is "M" then
      -- the media handoff POINTER: verify, replay-guard, then just
      -- REMEMBER it - fetching is the user's click (rsMediaFetch is
      -- idempotent, so a re-applied offer costs nothing), and the bytes
      -- themselves never touch the mesh (the channel-2 decision)
      put rsLanVerifyHandoff(pBytes, sMasterSeed) into tRec
      if tRec is empty then
         raLanLog "stranger record refused:" && rsLastError()
         exit raLanSyncReceive
      end if
      -- the handoff shares the draft record's per-device seq space, so it
      -- keys the same way (two devices offering media over one relaying
      -- host must not share one replay counter)
      put tRec["name"] into tDev
      put sLanPeerMediaSeq[tDev] into tLast
      if tLast is empty then
         put -1 into tLast
      end if
      if tRec["seq"] <= tLast then
         exit raLanSyncReceive
      end if
      raLanNoteName pPeer, tDev
      put tRec["seq"] into sLanPeerMediaSeq[tDev]
      put tRec["infoHash"] into sLanMediaHash
      put tRec["fileName"] into sLanMediaName
      put tRec["fileSize"] into sLanMediaSize
      put tDev into sLanMediaFrom
      raLanLog "media offer from" && quote & tDev & quote & ":" && \
            tRec["fileName"] && "(" & tRec["fileSize"] && "bytes) -" && \
            "Fetch + play below pulls it over the torrent rail."
      raLanPaintMediaOffer
      raLanRelay pPeer, pKind, pBytes
   end if
end raLanSyncReceive

-- The latest draft per device, ABSOLUTE state repainted whole (diffed so
-- the pump does not churn the field). Guarded: the pump runs anywhere.
command raLanPaintDrafts
   local tRows, tDev
   if there is no field "raLanDrafts" of card "raDevices" then
      exit raLanPaintDrafts
   end if
   set the caseSensitive to true
   if the number of lines of the keys of sLanPeerDraft is 0 then
      put "No drafts from your other devices yet." into tRows
   else
      put empty into tRows
      -- label from the key, which IS the device: looking the name up in
      -- sLanDevices would label every relayed draft with the HOST's name
      -- on a joiner, because that is the only peer a joiner ever has
      repeat for each key tDev in sLanPeerDraft
         put "--" && tDev && "(seq" && \
               sLanPeerSeq[tDev] & ") --" & return & \
               sLanPeerDraft[tDev] & return after tRows
      end repeat
   end if
   if the text of field "raLanDrafts" of card "raDevices" is not tRows then
      set the text of field "raLanDrafts" of card "raDevices" to tRows
   end if
end raLanPaintDrafts

private function raLanMyName
   local tName
   put word 1 to -1 of field "raLanName" of card "raDevices" into tName
   if tName is empty then put "device" into tName
   return char 1 to 32 of tName
end raLanMyName

command raLanLog pLine
   if there is a field "raLanLog" of card "raDevices" then
      put pLine & return after field "raLanLog" of card "raDevices"
   end if
end raLanLog

command raLanPaintDevices
   local tRows, tPeer, tRow, tNow, tSet, tDev, tLink
   if there is no field "raLanDevices" of card "raDevices" then
      exit raLanPaintDevices
   end if
   if sLanHost is empty then
      put "Not on a mesh. Host this device, or Join another by its LAN IP." into tRows
   else
      -- the panel lists DEVICES, not links: the names we admitted directly
      -- plus every name we have applied presence from. Painting from
      -- sLanDevices alone showed exactly ONE row on a joiner - the host -
      -- because a joiner's only peer IS the host and every other device
      -- reaches it relayed, under that same peer id
      put empty into tSet
      repeat for each key tPeer in sLanDevices
         put "true" into tSet[sLanDevices[tPeer]]
      end repeat
      repeat for each key tDev in sLanPeerSeen
         put "true" into tSet[tDev]
      end repeat
      if the number of lines of the keys of tSet is 0 then
         if sLanIsServer is "true" then
            put "Hosting. No devices admitted yet." into tRows
         else
            put "Joining. Waiting for admission..." into tRows
         end if
      else
         put the milliseconds into tNow
         put empty into tRows
         -- B4 (2026-08-23): reverse the DIRECT links (peer -> name) so a
         -- device with its own enet link carries the spec :360-362 live
         -- RTT/loss readout. Stats are a LINK property, so a RELAYED
         -- device's row stays bare on purpose - on a joiner its traffic
         -- rides the host's link, and printing the host's numbers under
         -- another device's name would be a lie.
         put empty into tLink
         repeat for each key tPeer in sLanDevices
            put tPeer into tLink[sLanDevices[tPeer]]
         end repeat
         -- deliberately unsorted: sorting would mean `the keys`, a
         -- RETURN-delimited list, and a device name is arbitrary UTF-8 to
         -- the library's cap - the one place a name carrying a return
         -- could garble the panel. Key order is stable for a given set.
         repeat for each key tDev in tSet
            put tDev into tRow
            -- the channel-1 presence lane: [typing] while fresh, [quiet]
            -- once its cadence has gone silent (a crashed or wedged device
            -- must not paint as live forever). A directly-admitted device
            -- we have heard no presence from yet gets neither marker.
            if sLanPeerSeen[tDev] is not empty then
               if tNow - sLanPeerSeen[tDev] >= kLanPresenceStaleMs then
                  put "  [quiet]" after tRow
               else if sLanPeerTyping[tDev] is "true" then
                  put "  [typing]" after tRow
               end if
            end if
            if tLink[tDev] is not empty then
               put raLanPeerStats(tLink[tDev]) after tRow
            end if
            put tRow & return after tRows
         end repeat
         if the last char of tRows is return then
            delete the last char of tRows
         end if
      end if
   end if
   if the text of field "raLanDevices" of card "raDevices" is not tRows then
      set the text of field "raLanDevices" of card "raDevices" to tRows
   end if
end raLanPaintDevices

-- B4 (2026-08-23): one device row's live link-stats suffix from
-- enPeerStatus (enet.lcb: `rtt` in ms, `packetLoss` 0..1, one FFI round
-- trip) - the spec :360-362 "your devices" RTT/loss readout. Probe-guarded
-- and try-wrapped, per the house rule: absent enetxt degrades to a
-- message, a stale peer answers {} ("gone, not an error" - the binding's
-- own contract) and degrades to nothing, and nothing here can throw out
-- of a paint the pump reaches from any card. Verified statically; needs
-- the phase-6 two-machine pass.
private function raLanPeerStats pPeer
   local tS, tErr
   if sCaps["hasEnet"] is not true then
      return "  (rtt/loss readout needs enetxt)"
   end if
   try
      put enPeerStatus(pPeer) into tS
   catch tErr
      return empty
   end try
   if the keys of tS is empty then
      return empty
   end if
   if tS["rtt"] is empty or tS["packetLoss"] is empty then
      return empty
   end if
   return "  rtt" && tS["rtt"] && "ms, loss" && \
         the round of (tS["packetLoss"] * 100) & "%"
end raLanPeerStats

-- ---- the channel-0 media handoff (the channel-2 decision) --------------------
-- Send media... seeds the picked file IN PLACE (rsMediaCreate, the
-- phase-3 path - no copy is made) and offers it to every admitted device
-- as a signed "M" pointer record; the receiving device fetches by hash
-- (rsMediaFetch, sequential) and plays mid-download, exactly the media
-- strip's two-mood discipline. The BYTES never touch the mesh: enet's
-- 60000-byte budget is the suite's message/bulk seam, and bulk is a
-- torrent - which also means swarm peers see your IP and discovery is
-- the DHT (said in the footer). Channel 2 stays allocated, dark.

command raLanSendMedia
   local tPath, tShortName, tHash, tH, tS, tSize, tBytes
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the handoff record signs under your master seed.", "warn"
      exit raLanSendMedia
   end if
   if the number of lines of the keys of sLanDevices is 0 then
      raLanLog "No admitted devices to offer media to; Host or Join first."
      exit raLanSendMedia
   end if
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      raLanLog "No TorrentXT session: the handoff points at the torrent rail, so it needs torrentxt."
      exit raLanSendMedia
   end if
   answer file "Choose a photo or video to offer your other devices (it seeds from where it is):"
   if it is empty then
      exit raLanSendMedia
   end if
   put it into tPath
   put rsMediaCreate(sSession, tPath) into tHash
   if tHash is empty then
      raLanLog "rsMediaCreate refused:" && rsLastError()
      exit raLanSendMedia
   end if
   -- itemDelimiter is global mutable state; take the leaf, then RESTORE
   -- it to comma (the raAttach lesson)
   set the itemDelimiter to "/"
   put item -1 of tPath into tShortName
   set the itemDelimiter to comma
   -- the size for the record comes from our own seed's metadata: fetching
   -- our own hash lands on the library's find path (no download, no copy)
   put 0 into tSize
   put rsMediaFetch(sSession, tHash, raMediaFolder(), false) into tH
   if tH is not empty then
      put rsMediaStatus(tH) into tS
      if tS is an array and tS["fileSize"] is an integer then
         put tS["fileSize"] into tSize
      end if
   end if
   add 1 to sLanSeq
   put rsLanBuildHandoff(sLanName, sLanSeq, tHash, tShortName, tSize, \
         sMasterSeed) into tBytes
   if tBytes is empty then
      raLanLog "media handoff refused:" && rsLastError()
      exit raLanSendMedia
   end if
   raLanSyncSend 0, tBytes, 0
   -- adopt our own offer locally too (absolute state, same as receivers)
   put tHash into sLanMediaHash
   put tShortName into sLanMediaName
   put tSize into sLanMediaSize
   put sLanName && "(this device)" into sLanMediaFrom
   raLanPaintMediaOffer
   raLanLog "offered" && quote & tShortName & quote && "(" & tSize && \
         "bytes) to" && the number of lines of the keys of sLanDevices && \
         "admitted device(s); it seeds from where it sits."
end raLanSendMedia

-- One button, two moods (the media strip's discipline): Fetch until the
-- offered hash's on-disk file exists, then Play - mid-download by design.
command raLanMediaGet
   local tHash, tH, tS, tPlayable, tWaitingFront
   if sLanMediaHash is empty then
      raLanLog "No media offer yet; Send media... on another admitted device first."
      exit raLanMediaGet
   end if
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      raLanLog "No TorrentXT session: cannot fetch (the bytes ride the torrent rail)."
      exit raLanMediaGet
   end if
   put sLanMediaHash into tHash
   put false into tPlayable
   put false into tWaitingFront
   if sLanMediaWatch is an integer and sLanMediaWatch > 0 then
      put rsMediaStatus(sLanMediaWatch) into tS
      if tS is an array then
         if toLower(tS["infoHashV1"]) is tHash and \
               tS["filePath"] is not empty then
            if there is a file tS["filePath"] then
               -- existence is not playability (raMediaFrontReady's story)
               if raMediaFrontReady(tS) then
                  put true into tPlayable
               else
                  put true into tWaitingFront
               end if
            end if
         end if
      end if
   end if
   if tPlayable is true then
      launch document tS["filePath"]
      raLanLog "handed" && tS["filePath"] && "to the system player" && \
            "(a non-faststart video keeps its index at the tail and only plays once complete)."
      exit raLanMediaGet
   end if
   if tWaitingFront is true then
      raLanLog "the front of the file is still arriving - Play unlocks once the first" && \
            (kRaPlayFloor * 100) & "% is on disk."
      exit raLanMediaGet
   end if
   put rsMediaFetch(sSession, tHash, raMediaFolder(), true) into tH
   if tH is empty then
      raLanLog "rsMediaFetch refused:" && rsLastError()
      exit raLanMediaGet
   end if
   put tH into sLanMediaWatch
   raLanLog "fetching" && quote & sLanMediaName & quote && \
         "over the torrent rail (sequential; playable mid-download)."
end raLanMediaGet

-- The latest verified offer, ABSOLUTE state repainted whole (diffed so
-- repeated paints do not churn the field). Guarded: callers run anywhere.
command raLanPaintMediaOffer
   local tLine
   if there is no field "raLanMediaOffer" of card "raDevices" then
      exit raLanPaintMediaOffer
   end if
   if sLanMediaHash is empty then
      put "No media offered yet." into tLine
   else
      put quote & sLanMediaName & quote && "(" & sLanMediaSize && \
            "bytes) from" && sLanMediaFrom && "-" && sLanMediaHash \
            into tLine
   end if
   if the text of field "raLanMediaOffer" of card "raDevices" \
         is not tLine then
      set the text of field "raLanMediaOffer" of card "raDevices" to tLine
   end if
end raLanPaintMediaOffer

-- The handoff progress line at the poll cadence, painted only on change
-- (raMediaPaint's discipline exactly). Devices-card controls, but the
-- pump runs from any card and OUTSIDE raPoll's try - qualify and guard
-- every reference, always (the multi-card law).
command raLanMediaPaint
   local tS, tLine, tPct, tLabel
   if sLanMediaWatch is not an integer or sLanMediaWatch <= 0 then
      exit raLanMediaPaint
   end if
   put rsMediaStatus(sLanMediaWatch) into tS
   if tS is not an array then
      -- the handle went stale (torrent removed, session gone): stop
      -- watching rather than stomping rsLastError four times a second
      put empty into sLanMediaWatch
      exit raLanMediaPaint
   end if
   put the round of (tS["progress"] * 100) into tPct
   put "handoff:" && tPct & "% -" && tS["numPeers"] && "peer(s)" into tLine
   if tS["isSeeding"] is 1 then
      put " - complete, now co-seeding" after tLine
   end if
   if tS["filePath"] is empty then
      put " - waiting for metadata from the swarm" after tLine
      put "Fetch + play" into tLabel
   else if raMediaFrontReady(tS) then
      put " -" && tS["filePath"] after tLine
      put "Play now" into tLabel
   else
      put " - front arriving (Play unlocks at" && (kRaPlayFloor * 100) & "%)" after tLine
      put "Fetch + play" into tLabel
   end if
   if there is a field "raLanMediaProg" of card "raDevices" then
      if the text of field "raLanMediaProg" of card "raDevices" \
            is not tLine then
         set the text of field "raLanMediaProg" of card "raDevices" \
               to tLine
      end if
   end if
   if there is a button "raLanMediaGet" of card "raDevices" then
      if the label of button "raLanMediaGet" of card "raDevices" \
            is not tLabel then
         set the label of button "raLanMediaGet" of card "raDevices" \
               to tLabel
      end if
   end if
end raLanMediaPaint

-- ---- phase 7: the anonymous persona ------------------------------------------
-- Everything here is the gated rsAnon*/rsPersonaAllows layer. Revealing is
-- pure and offline; publishing needs onionxt + tor. The guard panel is a
-- live read of rsPersonaAllows, so it can never drift from the policy the
-- library actually enforces.

command raAnonReveal
   local tHandle, tOnion, tOut
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first; the anon persona derives from your master seed.", "warn"
      exit raAnonReveal
   end if
   put rsAnonHandle(sMasterSeed, 0) into tHandle
   if tHandle is empty then
      put "Could not derive the anon persona:" && rsLastError() into tOut
   else
      put "anon persona 0 handle (a DIFFERENT key from your public one):" \
            & return & "  " & tHandle & return into tOut
      put rsAnonOnion(sMasterSeed, 0) into tOnion
      if tOnion is empty then
         put "onion address: unavailable (no SHA3 provider loaded)." & return \
               after tOut
      else
         put "reachable ONLY at this onion (share it out of band, never post it):" \
               & return & "  " & tOnion & return after tOut
      end if
      put return & "To an outside observer this key and your public handle" \
            && "are unlinkable - as long as you never cross-post or correlate" \
            && "their timing yourself." after tOut
   end if
   set the text of field "raAnonOut" of card "raAnon" to tOut
   raAnonPaintGuard
end raAnonReveal

-- The guard panel: a LIVE read of rsPersonaAllows for every transport, so
-- what the user sees is exactly what the library enforces.
command raAnonPaintGuard
   local tRows, tT, tList
   put "transport      anon persona   public persona" & return & \
         "---------      ------------   --------------" & return into tRows
   -- every transport the guard knows, so the panel is a TRUE full read (the
   -- feed and media rails were the two an anon persona most needs kept off)
   put "onion,dht,torrent,rp1,enet,dc,feed,media" into tList
   set the itemDelimiter to comma
   repeat for each item tT in tList
      put rsPadRight(tT, 15) after tRows
      if rsPersonaAllows(true, tT) then
         put rsPadRight("allowed", 15) after tRows
      else
         put rsPadRight("REFUSED", 15) after tRows
      end if
      if rsPersonaAllows(false, tT) then
         put "allowed" after tRows
      else
         put "REFUSED" after tRows
      end if
      put return after tRows
   end repeat
   put return & "The anon persona may use ONLY the onion. Every other" & \
         return & "transport is refused fail-closed - that is what keeps" & \
         return & "its .onion unlinkable from your public DHT presence." \
         after tRows
   if there is a field "raAnonGuard" of card "raAnon" then
      if the text of field "raAnonGuard" of card "raAnon" is not tRows \
            then
         set the text of field "raAnonGuard" of card "raAnon" to tRows
      end if
   end if
end raAnonPaintGuard

private function rsPadRight pText, pWidth
   local tOut
   put pText into tOut
   repeat while the number of chars in tOut < pWidth
      put space after tOut
   end repeat
   return tOut
end rsPadRight

-- Publish AND serve (spec 8.2/8.3): build the serving payloads first
-- (pure, fail-closed - a page that cannot build aborts before tor hears
-- anything), register the onion-httpd routes, then create the persona's
-- deterministic onion service. The control port must be authenticated
-- before ADD_ONION and connecting is ASYNC, so the first click may only
-- kick off oxConnectControl; the status callback re-enters here once
-- authenticated (idempotent - every early guard still holds).
command raAnonPublish
   local tService, tEntries, tPage, tPkBody, tOnion, tErr
   if sMasterSeed is empty then
      uiStatus "Unlock on the Feed card first.", "warn"
      exit raAnonPublish
   end if
   if sCaps["hasOnion"] is not true then
      raAnonLog "onionxt is not installed; the anon persona cannot be served. Install org.openxtalk.library.onion and run a tor daemon."
      exit raAnonPublish
   end if
   if sAnonService is not empty then
      raAnonLog "Already published; Unpublish first."
      exit raAnonPublish
   end if
   -- the guard, asserted at the one branch that could leak: publishing IS
   -- an onion action, which the anon persona is allowed - but we route it
   -- through the same policy the rest of the app uses, so this call site
   -- can never quietly become a non-onion one
   if not rsPersonaAllows(true, "onion") then
      raAnonLog "the guard refused an onion publish - this is a bug, not a normal path."
      exit raAnonPublish
   end if
   -- 8.2: the served payloads, built once and held in locals - a request
   -- must never depend on which card is open, so the route handlers reply
   -- from state, not from a field read at request time
   put empty into tEntries
   if there is a field "raAnonEntries" of card "raAnon" then
      put the text of field "raAnonEntries" of card "raAnon" into tEntries
   end if
   put rsAnonFeedPage("Riptide anon persona", tEntries) into tPage
   if tPage is empty then
      raAnonLog "feed page refused:" && rsLastError()
      exit raAnonPublish
   end if
   put rsAnonPrekeyBody(sMasterSeed, 0) into tPkBody
   if tPkBody is empty then
      raAnonLog "prekey body refused:" && rsLastError()
      exit raAnonPublish
   end if
   -- The onion-httpd routes, still fail-closed. NOTE the reason changed: this
   -- stack now EMBEDS onion-httpd (tools/sync-demo-embeds.py), so "the library
   -- is absent" is no longer a state a reader can be in by forgetting a
   -- `start using`. A throw here means the embedded copy is damaged or an oxh*
   -- call genuinely failed - and the refusal message has to say that, because
   -- telling somebody to load a file they already have sends them to look
   -- where there is nothing to find.
   try
      oxSetCallbackOwner the long id of me
      oxSetStatusCallback "raAnonStatus"
      oxhInit the long id of me
      oxhRoute "GET", "/", "raAnonRouteFeed"
      oxhRoute "GET", "/prekey", "raAnonRoutePrekey"
      oxhRoute "POST", "/dm", "raAnonRouteDm"
      oxSetPeerCallback "oxhPeer"
   catch tErr
      raAnonLog "The persona cannot serve: an onion-httpd call threw." && \
            "This stack EMBEDS onion-httpd, so this is not a missing" && \
            "`start using` - re-paste the whole file (or re-run" && \
            "tools/sync-demo-embeds.py) if the embedded copy looks damaged," && \
            "otherwise report the error text. (" & tErr & ")"
      exit raAnonPublish
   end try
   put tPage into sAnonPage
   put tPkBody into sAnonPrekeyBody
   put "true" into sAnonServing
   -- ADD_ONION needs an authenticated control port, and connecting is
   -- async: kick it off and let raAnonStatus finish the publish
   if oxIsControlAuthenticated() is not true then
      try
         oxConnectControl
      catch tErr
         raAnonLog "control connect failed:" && tErr
         exit raAnonPublish
      end try
      raAnonLog "connecting to tor's control port (watch the tor: lines);" && \
            "publishing continues automatically once authenticated."
      exit raAnonPublish
   end if
   put rsAnonCreateService(sMasterSeed, 0, kAnonVirtualPort, kAnonLocalPort) \
         into tService
   if tService is empty then
      raAnonLog "publish failed:" && rsLastError()
      exit raAnonPublish
   end if
   put tService into sAnonService
   raAnonLog "onion service requested (handle" && tService & "); tor" && \
         "publishes the descriptor in a few seconds. Serving: / (the anon" && \
         "feed page), GET /prekey (the signed prekey record, hex), and" && \
         "POST /dm (sealed intros)."
   put rsAnonOnion(sMasterSeed, 0) into tOnion
   if tOnion is not empty then
      raAnonLog "reachable at" && tOnion && "once the descriptor uploads" && \
            "(Tor Browser on this machine is the cheapest check)."
   end if
end raAnonPublish

-- Tor's status stream (oxSetStatusCallback), routed to the anon log.
-- Bootstrap ticks are already coalesced by onionxt but still chatty, so
-- only milestones land here; "control authenticated" resumes a publish
-- that was waiting on the async connect.
command raAnonStatus pKind, pInfo
   if pKind is "bootstrap" and pInfo is not 100 then
      exit raAnonStatus
   end if
   raAnonLog "tor:" && pKind && pInfo
   if pKind is "control" and pInfo is "authenticated" and \
         sAnonServing is "true" and sAnonService is empty then
      raAnonPublish
   end if
end raAnonStatus

-- The three route handlers (dispatched by onion-httpd's oxhHandle with
-- pStream, pRequest). They run from ENGINE socket callbacks - off the
-- raPoll try, on whatever card is open - so they reply from script
-- locals, write fields only through the guarded raAnonLog, and keep the
-- oxh reply inside a try (a dead stream must not throw into the accept
-- loop).
command raAnonRouteFeed pStream, pRequest
   local tErr
   try
      oxhReply pStream, 200, textDecode(sAnonPage, "UTF-8"), \
            "Content-Type: text/html; charset=utf-8"
   catch tErr
      -- stream already gone; nothing to serve
   end try
end raAnonRouteFeed

command raAnonRoutePrekey pStream, pRequest
   local tErr
   try
      oxhReply pStream, 200, sAnonPrekeyBody, \
            "Content-Type: text/plain; charset=utf-8"
   catch tErr
      -- stream already gone
   end try
end raAnonRoutePrekey

-- The POST /dm drop (spec 8.3). rsAnonAcceptDm refuses before decoding
-- and then verify-then-parses with the persona's own subkeys; every
-- refusal gets the SAME reply, so the route is not an oracle for a
-- prober. An accepted intro drains into the DM surfaces: the proven
-- sender is logged here and on the Messages card (the persona replies
-- over onion streams only - that reply rail is deliberately not built,
-- so answering means a PUBLIC-side DM to the proven sender).
command raAnonRouteDm pStream, pRequest
   local tOpened, tErr
   put empty into tOpened
   if sMasterSeed is not empty then
      put rsAnonAcceptDm(pRequest["__body"], sMasterSeed, 0) into tOpened
   end if
   -- the app's freshness policy, the same window as the rp1 inbox path
   if tOpened is not empty then
      if tOpened["timestamp"] < the seconds - kDmIntroWindow or \
            tOpened["timestamp"] > the seconds + kDmIntroWindow then
         raAnonLog "a STALE sealed intro was refused (replay, or a badly skewed clock)."
         put empty into tOpened
      end if
   end if
   if tOpened is empty then
      try
         oxhReply pStream, 400, "refused", \
               "Content-Type: text/plain; charset=utf-8"
      catch tErr
         -- stream already gone
      end try
      exit raAnonRouteDm
   end if
   raAnonLog "sealed intro ACCEPTED over the onion from" && \
         tOpened["senderHandle"] & return & "  its kx public:" && \
         tOpened["senderKxPub"] & return & \
         "  the sender PROVED that handle; to answer, open a public-side" && \
         "DM to it (the persona itself replies over onion streams only)."
   raDmLog "anon persona: a sealed intro arrived over the onion from" && \
         raDmShort(tOpened["senderHandle"]) && "- see the Anon card."
   try
      oxhReply pStream, 200, "accepted", \
            "Content-Type: text/plain; charset=utf-8"
   catch tErr
      -- stream already gone; the intro is still logged
   end try
end raAnonRouteDm

command raAnonStop
   local tErr
   if sAnonService is empty and sAnonServing is not "true" then
      exit raAnonStop
   end if
   if sAnonService is not empty then
      try
         oxRemoveService sAnonService
      catch tErr
         -- onionxt gone or service already down; nothing to release
      end try
   end if
   -- drop the routes so a later oxh user of this engine cannot serve a
   -- stale page; unrouting an unregistered route is a no-op, and an
   -- absent onion-httpd means nothing was ever routed
   try
      oxhUnroute "GET", "/"
      oxhUnroute "GET", "/prekey"
      oxhUnroute "POST", "/dm"
   catch tErr
      -- onion-httpd not loaded; nothing was routed
   end try
   put empty into sAnonService
   put empty into sAnonPage
   put empty into sAnonPrekeyBody
   put empty into sAnonServing
   raAnonLog "anon onion unpublished; the routes are dropped."
end raAnonStop

command raAnonLog pLine
   if there is a field "raAnonOut" of card "raAnon" then
      put pLine & return after field "raAnonOut" of card "raAnon"
   end if
end raAnonLog

-- ---- phase 3: the media strip ------------------------------------------------
-- One button, two moods. While the watched item is not yet openable the
-- click is Fetch: join the swarm for the hash in the field, sequentially
-- (pieces arrive front-first), and start watching. Once the on-disk file
-- exists for THAT hash the click is Play: hand the file to the system
-- player - mid-download on purpose, which is the phase-3 done-criterion.
-- Fetching your OWN hash lands on the library's find path and plays the
-- original file instantly (the seeder's copy is already complete).
command raMediaGet
   local tHash, tH, tS, tPlayable, tWaitingFront
   raStartSession
   if sSession is not an integer or sSession <= 0 then
      uiStatus "No TorrentXT session: cannot fetch media.", "bad"
      exit raMediaGet
   end if
   put toLower(word 1 of field "raMediaHash") into tHash
   if tHash is empty then
      uiStatus "Paste a 40-hex media info-hash first (a walked post fills it in).", "warn"
      exit raMediaGet
   end if
   put false into tPlayable
   put false into tWaitingFront
   if sMediaWatch is an integer and sMediaWatch > 0 then
      put rsMediaStatus(sMediaWatch) into tS
      if tS is an array then
         if toLower(tS["infoHashV1"]) is tHash and tS["filePath"] is not empty then
            if there is a file tS["filePath"] then
               -- file-EXISTENCE is not playability: libtorrent allocates
               -- the file the moment metadata arrives, so this used to
               -- unlock Play at ~0% real data and hand the player a
               -- hollow file (see raMediaFrontReady, the 2026-08-27 fix)
               if raMediaFrontReady(tS) then
                  put true into tPlayable
               else
                  put true into tWaitingFront
               end if
            end if
         end if
      end if
   end if
   if tPlayable is true then
      launch document tS["filePath"]
      uiStatus "Handed" && tS["filePath"] && "to the system player" && \
            "(sequential fetch: the front is on disk first; a non-faststart" && \
            "video keeps its index at the TAIL and only plays once complete).", "ok"
      exit raMediaGet
   end if
   if tWaitingFront is true then
      uiStatus "The front of the file is still arriving - Play unlocks once" && \
            "the first" && (kRaPlayFloor * 100) & "% is on disk (the fetch is sequential).", empty
      exit raMediaGet
   end if
   put rsMediaFetch(sSession, tHash, raMediaFolder(), true) into tH
   if tH is empty then
      uiStatus "rsMediaFetch refused:" && rsLastError(), "bad"
      exit raMediaGet
   end if
   put tH into sMediaWatch
   uiStatus "Fetching media" && tHash && "- sequential; co-seeding starts as pieces arrive.", empty
end raMediaGet

-- The media progress line, at the poll cadence and painted only on change
-- (the single-thread playbook): one rsMediaStatus snapshot per tick, one
-- repaint per actual difference.
command raMediaPaint
   local tS, tLine, tPct, tLabel
   if sMediaWatch is not an integer or sMediaWatch <= 0 then
      exit raMediaPaint
   end if
   put rsMediaStatus(sMediaWatch) into tS
   if tS is not an array then
      -- the handle went stale (torrent removed, session gone): stop
      -- watching rather than stomping rsLastError four times a second
      put empty into sMediaWatch
      exit raMediaPaint
   end if
   put the round of (tS["progress"] * 100) into tPct
   put "media:" && tPct & "% -" && tS["numPeers"] && "peer(s)" into tLine
   if tS["isSeeding"] is 1 then
      put " - complete, now co-seeding" after tLine
   end if
   if tS["filePath"] is empty then
      put " - waiting for metadata from the swarm" after tLine
      put "Fetch + play" into tLabel
   else if raMediaFrontReady(tS) then
      put " -" && tS["filePath"] after tLine
      put "Play now" into tLabel
   else
      put " - front arriving (Play unlocks at" && (kRaPlayFloor * 100) & "%)" after tLine
      put "Fetch + play" into tLabel
   end if
   -- card-1 controls, but raMediaPaint runs every tick from any card and
   -- OUTSIDE raPoll's try; a bare reference would throw off-card and kill
   -- the pump, so qualify to card 1 and guard existence
   if there is a field "raMediaProg" of card 1 then
      if the text of field "raMediaProg" of card 1 is not tLine then
         set the text of field "raMediaProg" of card 1 to tLine
      end if
   end if
   if there is a button "raMediaGet" of card 1 then
      if the label of button "raMediaGet" of card 1 is not tLabel then
         set the label of button "raMediaGet" of card 1 to tLabel
      end if
   end if
end raMediaPaint

-- Is enough of the FRONT of the file on disk to hand it to a player?
-- File-EXISTENCE is not that question: libtorrent ALLOCATES the file the
-- moment metadata arrives, so gating Play on `there is a file` unlocked
-- it at ~0% real data - the 2026-08-27 two-machine pass clicked it, the
-- system player got a hollow file, and the report read "streaming does
-- not work" while the feed and complete-then-play media worked fully.
-- The fetch is sequential and rsMediaStatus's fileProgress counts the
-- CONTIGUOUS front (the library's own contract), so a floor on it IS a
-- front-of-file guarantee. 5% is a primer, not a promise: a player that
-- needs the file's tail index (a non-faststart MP4 keeps its moov atom
-- at the END) cannot start until 100% whatever the fetch order, and the
-- launch messages say so now.
function raMediaFrontReady pS
   if pS["isSeeding"] is 1 then
      return true
   end if
   if pS["fileSize"] is not a number or pS["fileSize"] <= 0 then
      return false
   end if
   if pS["fileProgress"] is not a number then
      return false
   end if
   return pS["fileProgress"] >= pS["fileSize"] * kRaPlayFloor
end raMediaFrontReady

-- Where fetched media lands: a dedicated folder under documents, created
-- on demand - rsMediaFetch refuses a folder that does not exist, so a
-- failed create surfaces there with the path in the message.
function raMediaFolder
   local tBase
   put specialFolderPath("documents") into tBase
   if tBase is empty then
      put specialFolderPath("temporary") into tBase
   end if
   put tBase & "/Riptide-media" into tBase
   if there is no folder tBase then
      create folder tBase
   end if
   return tBase
end raMediaFolder

-- ---- helpers -----------------------------------------------------------------
-- The default key-file location, the family preferences idiom (fall back
-- rather than fail on a platform with no preferences folder). The field is
-- editable, so this is only the starting suggestion.
function raKeyPath
   local tBase
   put specialFolderPath("preferences") into tBase
   if tBase is empty then
      put specialFolderPath("application data") into tBase
   end if
   if tBase is empty then
      put specialFolderPath("documents") into tBase
   end if
   return tBase & "/Riptide/identity.riptkey"
end raKeyPath

-- ---- the boot self-check ------------------------------------------------------
-- The plumbing is CARRIED (master: tools/demo-selfcheck.livecodescript; gate:
-- tools/check-demo-selfcheck-drift.py). What this file owns is the list of
-- assertions below - what is true about THIS demo at boot.
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

-- Every control name this script names OR builds, derived from the source with
-- comments cut and string literals kept.
constant kRaScControls = "raAnonEntries,raAnonEntriesL,raAnonGuard,raAnonOut,raAnonPublishBtn,raAnonReveal,raAnonSec1,raAnonSec2,raAnonStopBtn,raAttach,raCompose,raCreate,raDmCallBtn,raDmChat,raDmLog,raDmMine,raDmMsg,raDmSec1,raDmSec2,raDmSend,raDmStart,raDmTo,raDmToL,raDmTyping,raFetch,raGoAnonFromFeed,raGoDm,raGoFeed,raGoFeedFromAnon,raGoFeedFromLan,raGoLanFromFeed,raHandle,raHandleL,raIdL1,raIdL2,raIdOut,raKeyFile,raLanDevices,raLanDraft,raLanDrafts,raLanHostBtn,raLanJoinBtn,raLanLeaveBtn,raLanLog,raLanMediaGet,raLanMediaOffer,raLanMediaProg,raLanName,raLanNameL,raLanSec1,raLanSec2,raLanSec3,raLanSec4,raLanSec5,raLanSendMedia,raLanTo,raLanToL,raLock,raMediaGet,raMediaHash,raMediaL,raMediaProg,raMyFeed,raName,raNameL,raPassphrase,raPost,raSec1,raSec2,raSec3,raTheirFeed,raUnlock,uiFooter,uiStatus,uiTitle"

command raScRun
   local tMissing, tVer, tErr
   scBegin "raIdOut"
   put scMissing(kRaScControls) into tMissing
   scAssert "all 75 controls this script names exist (missing: " \
         & scShow(tMissing) & ")", (tMissing is empty)

   if sHaveLib is not "true" then
      scSkip "the carried riptide layer", \
            "rsProbeCapabilities did not answer - the embedded copy is " \
            & "damaged; re-paste the file, or run tools/sync-demo-embeds.py"
   else
      try
         put rsVersion() into tVer
      catch tErr
         put empty into tVer
      end try
      scAssert "rsVersion names the library (" & scShow(tVer) & ")", \
            (tVer is not empty)
      -- The capability probe is what every card in this app branches on, so a
      -- missing KEY is worse than a false value: the guards would read empty
      -- and take the wrong branch silently.
      scAssert "the capability probe answered all seven keys", \
            (sCaps["canCrypto"] is not empty and sCaps["hasTorrent"] is not empty \
             and sCaps["hasOnion"] is not empty and sCaps["hasDataChannel"] is not empty \
             and sCaps["hasEnet"] is not empty and sCaps["hasCoin"] is not empty \
             and sCaps["hasSha3"] is not empty)
      -- SodiumXT is the one hard dependency: identity cannot exist without it,
      -- and raProbe already says so in red. Asserting it here puts that in the
      -- pasteable record rather than only on the status line.
      if sCaps["canCrypto"] is not true then
         scSkip "identity, publish and fetch", \
               "SodiumXT is absent - install org.openxtalk.library.sodium"
      else
         scAssert "SodiumXT is present, so identity is possible", \
               (sCaps["canCrypto"] is true)
      end if
      scLine "      capabilities: torrent " & scShow(sCaps["hasTorrent"]) \
            & ", onion " & scShow(sCaps["hasOnion"]) \
            & ", dataChannel " & scShow(sCaps["hasDataChannel"]) \
            & ", enet " & scShow(sCaps["hasEnet"]) \
            & ", coin " & scShow(sCaps["hasCoin"]) \
            & ", sha3 " & scShow(sCaps["hasSha3"])
   end if
   scArmProbe
end raScRun
