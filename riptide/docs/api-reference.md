# Riptide API reference

The public `rs*` surface of `src/riptide.livecodescript` (library 0.8.0,
phases 1-7 plus the 8.2/8.3 onion serving seams). Pure LiveCodeScript over the installed suite extensions; the
byte-exact wire layouts are documented at the top of the library and
pinned by the oracle (`tools/riptide_reference.py`), the golden test, and
the harness constants, with `tools/check-selftest-vectors.py` holding the
three in agreement. The magic is the version: `RSH1`, `RSP1`, `RSK1`,
`RSI1`, `RSM1`, `RSL1`, `RIPTKEY1` change by minting a successor, never by
silent fix.

> **Engine evidence.** Phases 1-2 ENGINE-PASSED 2026-08-12 (133/133 folded
> into the suite harness); the propagation half closed 2026-08-13 (two
> machines, feeds both directions, every rendered post ingest-verified).
> Phase 3 (media) and phase 4 (DMs chatting both ways) passed on two
> machines 2026-08-15, the same day the whole phase 4-7 COMPUTE surface ran
> green in the suite selftest. The LAN welcome leg, the phase-5 call, and
> the anon flows are statically verified; `docs/two-machine-runbook.md`
> scripts their passes.

## Conventions

- **Nothing here throws.** A failure returns `empty` (or `false`) and
  `rsLastError()` says why. Every foreign `sx*`/`bt*`/`ox*` call is
  guarded, so a missing extension degrades to a clear message.
- **Bytes are `Data`; hex crosses as lowercase strings.** A "handle" is a
  64-hex ed25519 public key; a "target" is 40 hex (a DHT target or torrent
  info-hash); the all-zeros target means "none", and building records with
  empty target arguments normalizes to it. Strict parses refuse uppercase
  (non-canonical) spellings and trailing bytes.
- **Lists cross as comma-separated strings** (media info-hashes, chunk
  targets), empty for none.
- **Caps refuse, never truncate**, on build and parse alike. UTF-8 text
  fields are validated by round trip (OXT's `textDecode` is lossy, not
  throwing - see CLAUDE.md).
- `pSession` is the app-owned TorrentXT session handle; `pMaster` the
  32-byte master seed; seeds are 32-byte `Data`.

## Probe, version, errors

| Handler | Returns | Notes |
|---|---|---|
| `rsVersion()` | String | names the library, version, and built phases |
| `rsLastError()` | String | the last refusal's reason; "" if none |
| `rsProbeCapabilities()` | Array | booleans: `canCrypto` (SodiumXT, a real round-trip probe), `hasTorrent`, `hasOnion`, `hasDataChannel`, `hasEnet`, `hasCoin`, plus derived `hasSha3` (either provider answered a real call); probed once, cached |
| `rsHeadSalt()` | String | `"riptide-head"`, the fixed BEP44 salt of a feed head |
| `rsZeroTarget()` | String | the 40-zeros "none" target |

## The keyring (RIPTKEY1) and the KDF subkey tree

| Handler | Returns | Notes |
|---|---|---|
| `rsGenerateMasterSeed()` | Data | 32 bytes from the CSPRNG |
| `rsSealMasterSeed(pSeed, pPassphrase)` | Data | the RIPTKEY1 file: magic, mode "E", 16-byte salt, `sxSecretBox` of the seed under an Argon2id key (opslimit "2", interactive memlimit - the family's parameters; both ends must agree). Exactly 97 bytes; fresh salt/nonce each call |
| `rsOpenMasterSeed(pFileBytes, pPassphrase)` | Data | the 32-byte master, or empty (wrong passphrase, tamper, truncation) |
| `rsIdentitySeed(pMaster)` | Data | subkey 1: the public identity ed25519 seed |
| `rsDmSeed(pMaster)` | Data | subkey 2: the DM key-exchange seed |
| `rsLanKey(pMaster)` | Data | subkey 3: the LAN mesh key |
| `rsAnonSeed(pMaster, pIndex)` | Data | subkey 100+n: anon persona n's ed25519 seed |
| `rsAnonDmSeed(pMaster, pIndex)` | Data | subkey 200+n: anon persona n's sealed-DM kx seed (spec 8.3) |

The KDF context is the 8-byte `"riptide\0"`; subkey ids are decimal
strings, matching `sxKdfDerive`.

## Identity, onion spelling, rendezvous

| Handler | Returns | Notes |
|---|---|---|
| `rsIdentityKeys(pSeed)` | Array | `publicKey` (32 B), `secretKey` (64 B), `handle` (64 hex); equals `btDhtKeypair(seedHex)["publicKey"]` for the same seed without the seed ever entering torrentxt |
| `rsHandleFromSeed(pSeed)` | String | the 64-hex handle |
| `rsOnionFromPublicKey(pPub)` | String | the v3 .onion of a 32-byte key. Needs SHA3-256 from sodiumxt ABI 7 (`sxSha3_256`, preferred) or coinxt (`cxSha3_256`, fallback); empty with a clear reason without either |
| `rsOnionFromHandle(pHandleHex)` | String | convenience over the above |
| `rsVerifyOnionClaim(pOnionAddr, pHandleHex)` | Boolean | true only if the address structurally decodes (onionxt's offline `oxPublicKeyFromAddress`) AND its embedded key equals the handle, compared constant-time. The security-relevant direction; needs no SHA-3 |
| `rsInboxId(pHandleHex)` | String | 40-hex phantom-swarm id: BLAKE2b-20(pubkey and `"riptide-inbox"`) |
| `rsRoomId(pPkAHex, pPkBHex, pSessionSalt)` | String | 40-hex pairwise room id: BLAKE2b-20(sortedConcat(pkA, pkB) and salt); symmetric in its peers |

## The feed records (RSH1 heads, RSP1 posts)

| Handler | Returns | Notes |
|---|---|---|
| `rsBuildHead(pSeq, pDisplayName, pLatestPost, pPrekey, pOnionAddr, pProfileMeta)` | Data | the RSH1 record (max 260 bytes; display name max 64 bytes UTF-8; onion empty or 62 chars) |
| `rsParseHead(pBytes)` | Array | `seq`, `displayName`, `latestPostTarget`, `prekeyTarget`, `onionAddr` (empty if absent), `profileMetaTarget` |
| `rsBuildPost(pTimestamp, pPrevTarget, pTextContent, pMediaList, pIdentitySeed)` | Data | a signed kind-D post (direct UTF-8 text; media max 8) |
| `rsBuildPostChunked(pTimestamp, pPrevTarget, pChunkTargets, pMediaList, pIdentitySeed)` | Data | a signed kind-C post naming 1..16 immutable text chunks in order |
| `rsParsePost(pBytes)` | Array | `timestamp`, `prevPostTarget`, `kind`, `text` (D) or `chunkTargets` (C), `mediaTargets`. Parsing does not verify the signature |
| `rsVerifyPost(pBytes, pHandleHex)` | Boolean | true only if the record parses strictly AND its trailing 64 bytes are a valid ed25519 signature by the handle over everything before them |

## BEP44 plumbing and ingest verifiers

| Handler | Returns | Notes |
|---|---|---|
| `rsBencodeBytes(pData)` | Data | `<len>:<bytes>`, the BEP44 value shape (the only bencode riptide puts on the DHT) |
| `rsBep44SignBuf(pSalt, pSeq, pValue)` | Data | the canonical signing buffer `[4:salt<n>:<salt>] 3:seqi<seq>e 1:v <value>`, byte-identical to torrentxt's `btDhtBep44SignBuf`. `pValue` must be strictly well-formed bencode of 1..1000 raw bytes; salt max 64 bytes; seq a non-negative integer below 2^53 |
| `rsImmutableTarget(pValue)` | String | SHA-1 of the bencoded value: the immutable item's 40-hex target (what `btDhtPutImmutable` returns for the same bytes) |
| `rsIngestHead(pEvent, pExpectedHandleHex)` | Array | the parsed head, only if the drained `dhtMutableItem` event is for that handle and salt, the value is a strict RSH1 record, the embedded and BEP44 seqs agree, and the BEP44 signature verifies under the handle |
| `rsIngestPost(pEvent, pExpectedTarget, pAuthorHandleHex)` | Array | the parsed post, only if the event answers the expected target, the value's recomputed SHA-1 IS that target, and the author's signature verifies |

## The live feed layer (session-taking)

TorrentXT allows one session per process; the app starts it
(`btStartSession`) and polls it (`btPoll`), and this library never starts,
stops, or polls one. Every input is validated before the handle is
touched, so the refusal paths work - and are tested - without torrentxt.
Fetches are asynchronous: true means the lookup was accepted, and the
value arrives later through the app's poll loop as a `dhtMutableItem` /
`dhtImmutableItem` event for the matching ingest verifier. Nothing is
believed on arrival: ingest re-verifies the BEP44 signature (heads), the
content address (posts), and the author signature (posts) in SodiumXT, so
trust never rests on the transport.

| Handler | Returns | Notes |
|---|---|---|
| `rsPublishHead(pSession, pHeadBytes, pIdentitySeed)` | Boolean | the external-signing seam: the head's own embedded `seq` becomes the BEP44 seq (one counter, one source of truth), the canonical buffer is signed by `sxSignDetached`, and `btDhtPutSigned` re-verifies that signature against the handle before queueing - the identity secret never enters libtorrent |
| `rsPublishImmutable(pSession, pValue)` | String | the stored item's 40-hex target, recomputed locally; a disagreement is refused loudly |
| `rsPublishPost(pSession, pPostBytes)` | String | a strict RSP1 parse refuses malformed records before the network hears about them, then `rsPublishImmutable` |
| `rsRequestHead(pSession, pHandleHex)` | Boolean | queue the mutable lookup (handle + salt `"riptide-head"`) |
| `rsRequestImmutable(pSession, pTarget)` | Boolean | queue the immutable lookup; the zero target is refused |

The tamper-evident chain walk is these calls in the app's event loop, no
more:

```
-- ask for the head, then on its dhtMutableItem event:
put rsIngestHead(tEvent, tHandle) into tHead
put tHead["latestPostTarget"] into tNext
-- then, until tNext is rsZeroTarget():
--   rsRequestImmutable sSession, tNext ... on its dhtImmutableItem event:
put rsIngestPost(tEvent, tNext, tHandle) into tPost
put tPost["prevPostTarget"] into tNext
```

Content addressing carries the integrity: each post names its
predecessor's SHA-1, so one altered byte anywhere breaks the walk (or the
author signature) at that link.

## Media (phase 3)

| Handler | Returns | Notes |
|---|---|---|
| `rsMediaCreate(pSession, pPath)` | String | seed a file in place as a trackerless torrent; its 40-hex info-hash (what a post's media list carries) |
| `rsMediaFetch(pSession, pInfoHash, pSaveFolder, pSequential)` | Integer | fetch-and-co-seed by hash; sequential mode for playback; the torrent handle |
| `rsMediaStatus(pTorrent)` | Array | `btTorrentStatus` plus the first file's resolved `filePath`, `fileSize`, `fileProgress` - what a player paints from |

## DMs (phase 4): keys, records, transport

The flow: your head's `prekeyTarget` names your RSK1 prekey; a stranger
verifies it, seals an RSI1 intro to it, and sends it as an RSM1 "I" frame
over rp1 in your inbox swarm; both sides derive one kx session
(deterministic roles) and run a secretstream each way ("H" header, then
"M" ciphertext frames carrying kind+timestamp+body messages).

| Handler | Returns | Notes |
|---|---|---|
| `rsDmKeys(pDmSeed)` | Array | the crypto_kx pair: `publicKey`, `secretKey` (32 B each), `publicKeyHex` |
| `rsDmSessionKeys(pMyHandleHex, pMyKxKeys, pTheirHandleHex, pTheirKxPubHex)` | Array | `rx`, `tx`, `role`; the lexically smaller handle is the kx CLIENT, so both ends agree with no negotiation; my tx is the peer's rx |
| `rsBuildPrekey(pKxPubHex, pIdentitySeed)` | Data | RSK1: the kx public signed by the identity key (132 B) |
| `rsParsePrekey(pBytes)` | Array | `kxPub` |
| `rsVerifyPrekey(pBytes, pHandleHex)` | Array | parse + signature under that handle, or empty; verify BEFORE sealing to it |
| `rsBuildIntro(pTimestamp, pRecipientHandleHex, pSenderKxPubHex, pIdentitySeed)` | Data | RSI1 (268 B); the sender handle derives from the signing seed (a sender/signer mismatch cannot be expressed); the recipient handle sits INSIDE the signed body, so replay to a third party dies on the recipient check |
| `rsParseIntro(pBytes)` | Array | `senderHandle`, `senderKxPub`, `recipientHandle`, `timestamp` |
| `rsVerifyIntro(pBytes, pMyHandleHex)` | Array | signature + addressed-to-me, or empty; timestamp windows are the APP's policy (the demo refuses outside +-600 s) |
| `rsDmSealIntro(pIntroBytes, pRecipientKxPubHex)` | Data | `sxSeal` to the (verified!) prekey |
| `rsDmOpenIntro(pSealedBytes, pMyHandleHex, pMyDmSeed)` | Array | derive my kx pair, open, verify; one refusal for wrong-recipient/tamper/malformed |
| `rsDmFrame(pKind, pPayload)` | Data | RSM1: kind "I"/"H"/"M" (byte-exact, case NOT folded) + payload; whole frame within the rp1 60000 cap |
| `rsDmParseFrame(pBytes)` | Array | `kind`, `payload` |
| `rsDmMessageBody(pKind, pTimestamp, pBodyText)` | Data | the plaintext INSIDE the secretstream: kind "T" text / "O" sdp offer / "A" sdp answer (phase 5 rides here) |
| `rsDmParseMessage(pBytes)` | Array | `kind`, `timestamp`, `text` |
| `rsDmJoinInbox(pSession, pHandleHex, pSavePath)` | Integer | enable rp1 (BEFORE the swarm - it must advertise), join `rsInboxId(handle)`, announce (a refused announce is non-fatal); the swarm's torrent handle |
| `rsDmSend(pSession, pPeerId, pFrameBytes)` | Boolean | re-parse the frame (nothing malformed goes on the wire), `btRp1Send` to a peer learned from an `rp1Handshake` event |

## LAN mesh admission (phase 6)

Three RSL1 legs over enet channel 0, all pure crypto (testable offline):
the host's challenge, the joiner's response (proves the joiner holds the
master), and the host's welcome (proves the host BACK, bound to this
handshake by the joiner's own response signature - mutual auth).

| Handler | Returns | Notes |
|---|---|---|
| `rsLanKeys(pMaster)` | Array | the shared mesh ed25519 pair every one of your devices derives |
| `rsLanBuildChallenge(pName, pNonce)` | Data | host -> joiner; pNonce is 32 FRESH bytes (`sxRandomBytes`) - never reuse one |
| `rsLanParseChallenge(pBytes)` | Array | `name`, `nonce` |
| `rsLanBuildResponse(pChallengeBytes, pName, pMaster)` | Data | joiner -> host: sig over `"riptide-lan" \|\| nonce \|\| name` |
| `rsLanParseResponse(pBytes)` | Array | `name`, `signature` |
| `rsLanVerifyResponse(pResponseBytes, pChallengeBytes, pMaster)` | String | the joiner's device name, or empty (a stranger, a stale nonce, tamper) |
| `rsLanBuildWelcome(pResponseBytes, pHostName, pMaster)` | Data | host -> joiner after admitting: sig over `"riptide-lan-w" \|\| responseSig \|\| hostName` |
| `rsLanParseWelcome(pBytes)` | Array | `name`, `signature` |
| `rsLanVerifyWelcome(pWelcomeBytes, pMyResponseBytes, pMaster)` | String | the HOST's device name, or empty (a rogue host, a cross-handshake replay, tamper) |

## The anon persona and the guard (phase 7)

| Handler | Returns | Notes |
|---|---|---|
| `rsAnonHandle(pMaster, pIndex)` | String | persona n's 64-hex handle (a DIFFERENT key from the public identity) |
| `rsAnonOnion(pMaster, pIndex)` | String | its .onion, derivable offline; equals what `rsAnonCreateService` publishes |
| `rsPersonaAllows(pIsAnon, pTransport)` | Boolean | THE 9.3 deanonymization guard, pure policy: anon may use ONLY `onion`; public anything BUT `onion`; unknown transports refused for both. Known transports: `onion,dht,torrent,rp1,enet,dc,feed,media`. Route every transport branch through it |
| `rsAnonCreateService(pMaster, pIndex, pVirtualPort, pLocalPort)` | Integer | probe-gated `oxCreateServiceFromSeed`; the onionxt service handle |
| `rsBtxoHeader(pName, pTotalSize, pFlags)` | Data | the Model C framed-file header (magic/ver/flags/nameLen/name/total) |
| `rsBtxoParseHeader(pBytes)` | Array | `name`, `total`, `flags` |
| `rsBtxoDataFrame(pPayload)` | Data | u32-BE length + bytes (non-empty) |
| `rsBtxoTerminator()` | Data | the 4-byte zero-length end-of-stream frame |

Sealed DMs TO a persona (spec 8.3) are the phase-4 machinery composed with
the anon subkeys - no separate crypto handlers: `rsBuildPrekey(kxPub,
rsAnonSeed(...))` is the persona's prekey (served over its ONION, never
the DHT - the guard), `rsBuildIntro` addressed to the anon handle seals to
it via `rsDmSealIntro`, and the persona opens with
`rsDmOpenIntro(sealed, anonHandle, rsAnonDmSeed(...))`.

## The onion serving seams (spec 8.2/8.3, added 2026-08-15)

Pure payload builders and the acceptance path for the persona's
onion-httpd routes; the APP registers the `oxh*` routes and owns every
stream. Verified statically; needs an OXT + live-Tor pass.

| Handler | Returns | Notes |
|---|---|---|
| `rsAnonFeedPage(pTitle, pEntries)` | Data | the anon feed page as UTF-8 HTML bytes: title (1..64 UTF-8 bytes, the display-name budget) plus line-delimited entries, each HTML-escaped (no markup injection); blank lines skipped, one trailing CR per line tolerated; the finished page caps at 65536 bytes. Deterministic and golden-pinned - the page is a wire format, and a look change re-pins deliberately |
| `rsAnonPrekeyBody(pMaster, pIndex)` | String | the GET `/prekey` response body: persona n's RSK1 prekey record (subkey-200+n kx public, signed by the subkey-100+n anon identity) as 264 lowercase hex chars of text. A follower decodes and MUST verify: `rsVerifyPrekey(decoded, anonHandle)` |
| `rsAnonAcceptDm(pBody, pMaster, pIndex)` | Array | accept a POST `/dm` body: EXACTLY 632 strict lowercase hex chars (the 48-byte seal + the 268-byte RSI1 intro, times two), refused BEFORE any decode on length or a non-hex byte; then the existing `rsDmOpenIntro` verify-then-parse under the persona's subkeys. Returns the verified intro array or empty - one refusal for every failure mode (the route must not be an oracle). Freshness stays the app's policy |

## What the library deliberately does NOT own

The app owns the ONE TorrentXT session and every poll loop (`btPoll`,
`btRp1Poll`, `enPoll`, `dcPoll`), the rp1/enet/dc peer bookkeeping, the
secretstream handles (free them with `sxFreeStream` - SodiumXT has no
unload hook), intro freshness policy, and all UI.
`examples/riptide-social.livecodescript` is the reference app;
`docs/two-machine-runbook.md` scripts its verification.
