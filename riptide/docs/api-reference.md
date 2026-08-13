# Riptide API reference (phases 1-2)

The public surface of `src/riptide.livecodescript`: the phase-1 identity
and wire-format layer (pure compute plus probed extension calls), and the
phase-2 live feed layer (BEP44 puts and lookups through a torrent session
the app owns).

> **Phases 1 and 2** were ENGINE-PASSED 2026-08-12, folded into the suite
> harness: 133/133, 0 skipped, hasSha3 true. The phase-2 live layer below ran
> its real-session puts and accepted lookups plus its synthetic ingest
> verifier paths. The propagation half of phase 2 (a second machine walks the
> chain) closed 2026-08-13: `examples/riptide-social.livecodescript` ran on
> two machines, feeds published and received in both directions through the
> real DHT, every rendered post ingest-verified.

## Conventions

- **Functions return empty (or false) on failure** and record the reason;
  `rsLastError()` returns it. No handler in the library ever throws.
- **Bytes are `Data`; hex crosses as lowercase strings.** A "handle" is
  the 64-hex ed25519 public key; a "target" is 40 hex (a DHT target or
  torrent info-hash); the all-zeros target means "none", and building
  records with empty target arguments normalizes to it.
- **Lists cross as comma-separated strings** (media info-hashes, chunk
  targets), empty for none.
- **Caps refuse, never truncate**, on build and parse alike; parses are
  strict to the byte and refuse trailing data.

## Diagnostics and capabilities

| Handler | Returns |
|---|---|
| `rsVersion()` | version string |
| `rsLastError()` | the last recorded failure reason |
| `rsProbeCapabilities()` | array: `canCrypto` (SodiumXT, a real round-trip probe), `hasTorrent`, `hasOnion`, `hasDataChannel`, `hasEnet`, `hasCoin`, plus the derived `hasSha3` (either provider answered a real call) - probed once, cached |
| `rsHeadSalt()` | `"riptide-head"`, the fixed BEP44 salt of a feed head |
| `rsZeroTarget()` | the 40-zeros "none" target |

## Identity and the key file

| Handler | Returns |
|---|---|
| `rsGenerateMasterSeed()` | 32 random bytes (SodiumXT) |
| `rsSealMasterSeed(pSeed, pPassphrase)` | the `RIPTKEY1` file bytes: magic, mode `"E"`, 16-byte salt, `sxSecretBox` of the seed under an Argon2id key (opslimit `"2"`, interactive memlimit - the family's parameters; both ends must agree) |
| `rsOpenMasterSeed(pFileBytes, pPassphrase)` | the 32-byte seed, or empty on wrong passphrase / tamper / malformed file |
| `rsIdentitySeed(pMaster)` | KDF subkey 1 (32 bytes) |
| `rsDmSeed(pMaster)` | KDF subkey 2 |
| `rsLanKey(pMaster)` | KDF subkey 3 |
| `rsAnonSeed(pMaster, pIndex)` | KDF subkey 100 + pIndex |
| `rsIdentityKeys(pSeed)` | array: `publicKey` (32 bytes), `secretKey` (64 bytes), `handle` (64 hex) |
| `rsHandleFromSeed(pSeed)` | the 64-hex handle |

The KDF context is the 8-byte `"riptide\0"`; subkey ids are decimal
strings, matching `sxKdfDerive`. The handle equals
`btDhtKeypair(seedHex)["publicKey"]` for the same seed without the seed
ever entering torrentxt.

## Onion addresses

| Handler | Returns |
|---|---|
| `rsOnionFromPublicKey(pPub)` | the `.onion` of a 32-byte ed25519 key. Needs SHA3-256 from sodiumxt ABI 7 (`sxSha3_256`, preferred) or coinxt (`cxSha3_256`, fallback); empty with a clear reason without either |
| `rsOnionFromHandle(pHandleHex)` | convenience over the above |
| `rsVerifyOnionClaim(pOnionAddr, pHandleHex)` | true only if the address structurally decodes (onionxt's offline `oxPublicKeyFromAddress`) AND its embedded key equals the handle, compared constant-time. This is the security-relevant direction and needs no SHA-3 |

## Rendezvous derivations

| Handler | Returns |
|---|---|
| `rsInboxId(pHandleHex)` | 40-hex phantom-swarm id: BLAKE2b-20(pubkey and `"riptide-inbox"`) |
| `rsRoomId(pPkAHex, pPkBHex, pSessionSalt)` | 40-hex pairwise room id: BLAKE2b-20(sortedConcat(pkA, pkB) and salt); symmetric in its peers |

## The feed wire formats

| Handler | Returns |
|---|---|
| `rsBuildHead(pSeq, pDisplayName, pLatestPost, pPrekey, pOnionAddr, pProfileMeta)` | the `RSH1` head record (max 260 bytes; display name max 64 bytes UTF-8; onion empty or 62 chars) |
| `rsParseHead(pBytes)` | array: `seq`, `displayName`, `latestPostTarget`, `prekeyTarget`, `onionAddr` (empty if absent), `profileMetaTarget` |
| `rsBuildPost(pTimestamp, pPrevTarget, pTextContent, pMediaList, pIdentitySeed)` | a signed kind-D `RSP1` post (direct UTF-8 text; media max 8) |
| `rsBuildPostChunked(pTimestamp, pPrevTarget, pChunkTargets, pMediaList, pIdentitySeed)` | a signed kind-C post naming 1..16 immutable text chunks in order |
| `rsParsePost(pBytes)` | array: `timestamp`, `prevPostTarget`, `kind`, `text` (D) or `chunkTargets` (C), `mediaTargets`. Parsing does not verify the signature |
| `rsVerifyPost(pBytes, pHandleHex)` | true only if the record parses strictly AND its trailing 64 bytes are a valid ed25519 signature by the handle over everything before them |
| `rsBencodeBytes(pData)` | `<len>:<bytes>`, the BEP44 value shape; SHA-1 of it is an immutable item's target |

Byte-exact layouts are documented at the top of
`src/riptide.livecodescript` and pinned by `tests/riptide_golden_test.py`.
The magic is the version: `RSH1`, `RSP1`, and `RIPTKEY1` change by
minting a successor, never by silent fix.

## The live feed layer (phase 2)

The session handle in every `pSession` parameter is the app's: TorrentXT
allows one session per process, the app starts it (`btStartSession`) and
polls it (`btPoll`), and this library never starts, stops, or polls one.
Every input is validated before the handle is touched, so the refusal
paths work - and are tested - without torrentxt installed.

### Pure helpers

| Handler | Returns |
|---|---|
| `rsBep44SignBuf(pSalt, pSeq, pValue)` | the canonical BEP44 signing buffer `[4:salt<n>:<salt>] 3:seqi<seq>e 1:v <value>`, rebuilt in pure script (byte-identical to torrentxt's `btDhtBep44SignBuf`). `pValue` must be a strictly well-formed bencoded byte string of 1..1000 raw bytes; salt max 64 bytes; seq a non-negative integer below 2^53 |
| `rsImmutableTarget(pValue)` | the 40-hex DHT target of an immutable item: SHA-1 of the bencoded value (what `btDhtPutImmutable` returns for the same bytes) |

### Publishing (your own feed)

| Handler | Returns |
|---|---|
| `rsPublishHead(pSession, pHeadBytes, pIdentitySeed)` | true when the head was accepted. The external-signing seam: the head's own embedded `seq` becomes the BEP44 seq (one counter, one source of truth), the canonical buffer is signed by `sxSignDetached`, and `btDhtPutSigned` re-verifies that signature against the handle before queueing - the identity secret never enters libtorrent |
| `rsPublishPost(pSession, pPostBytes)` | the post's 40-hex target, after a strict `RSP1` parse refuses malformed records before the network hears about them |
| `rsPublishImmutable(pSession, pValue)` | the 40-hex target of any immutable value (a text chunk, a profile-meta blob); the returned target is recomputed locally and a disagreement is refused loudly |

### Fetching and ingesting (a followee's feed)

Fetches are asynchronous: true means the lookup was accepted, and the
value arrives later through the app's poll loop as a `dhtMutableItem` /
`dhtImmutableItem` event, which the app hands to the matching ingest
verifier. Nothing is believed on arrival: ingest re-verifies the BEP44
signature (heads), the content address (posts), and the author signature
(posts) in SodiumXT, so trust never rests on the transport.

| Handler | Returns |
|---|---|
| `rsRequestHead(pSession, pHandleHex)` | true when the mutable lookup (handle + salt `"riptide-head"`) was accepted |
| `rsRequestImmutable(pSession, pTarget)` | true when the immutable lookup was accepted; the zero target is refused |
| `rsIngestHead(pEvent, pExpectedHandleHex)` | the parsed head array, only if the event is for that handle and salt, the value is a strict `RSH1` record, the embedded and BEP44 seqs agree, and the BEP44 signature verifies under the handle |
| `rsIngestPost(pEvent, pExpectedTarget, pAuthorHandleHex)` | the parsed post array, only if the event answers the expected target, the value's recomputed SHA-1 IS that target, and the author's signature verifies |

### The chain walk

The tamper-evident feed walk is these calls in the app's event loop, no
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
