# Riptide phase-1 API reference

The public surface of `src/riptide.livecodescript`. Everything here is
pure compute plus probed extension calls; nothing touches the network.

> Verified against `tools/riptide_reference.py`'s golden vectors and
> ENGINE-PASSED 2026-08-12 (Windows x64, folded into the suite harness):
> 89/89, 0 skipped, hasSha3 true, so the whole phase-1 surface below has
> run green on a real engine.

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
