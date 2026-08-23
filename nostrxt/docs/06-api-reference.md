# 06 - Public API Reference (`nx*` and `nxr*`)

> **Status: verified statically; needs an OXT pass.** Every relay-facing handler
> additionally needs a live-relay pass. Nothing on this page has run on a real OXT
> engine. What IS machine-verified on every build: `tools/nostr-kat.py` sweeps the
> full published BIP-340, NIP-44 v2, BIP-173 and NIP-19 vector sets through the
> independent oracle `tools/nostr_reference.py`, and `tools/check-selftest-vectors.py`
> re-derives every constant the member harness pins, by name, in both directions.
> Claim nothing beyond that.

The public surface of both files, handler by handler: the pure-compute core
(`src/nostrxt.livecodescript`, `nx*`) and the relay client
(`src/nostr-relay.livecodescript`, `nxr*`). Private helpers are implementation, not
API, and stay off this page. The tables below are meant to be COMPLETE - every public
handler of both files appears exactly once - and `tools/check-doc-handlers.py` holds
this page and the source in agreement, so a handler added without its row (or a row
whose handler is gone) fails the build rather than drifting.

Naming and shapes: public `nxPascalCase` / `nxrPascalCase`. Commands are shown with
space-separated arguments (`nxrConnect pUrl`); functions with parentheses
(`nxVersion()`). Ids, pubkeys, seckeys and sigs cross this API as LOWERCASE HEX
STRINGS; binary stays internal.

## The shape every handler shares

The two files have DIFFERENT error conventions, both deliberate, and mixing them up
is the easiest way to mis-handle a failure:

- **Core `nx*` handlers NEVER throw.** Every one is a function; on failure it returns
  empty (or `false` for the predicates) and records the reason, which `nxLastError()`
  returns. Every `cx*`/`sx*` call inside the core sits in a `try`, so a missing
  extension surfaces as a clean capability error naming the handler it needs, never
  as an uncaught engine error. Check the return, then read `nxLastError()` - in that
  order, because a later successful call overwrites the reason.
- **Relay `nxr*` commands report through `the result`**: empty on success, a
  `"NostrXT relay: ..."` string on refusal. Handle-yielding commands (`nxrConnect`)
  return the integer handle instead, so callers test `the result is an integer`.
  Async outcomes never come back through a blocking return; they arrive through the
  registered callback (the contract is below, under "The relay callback contract").
- **Fail closed, everywhere.** A bad checksum, a truncated TLV, a MAC mismatch, a
  hostile frame length, an unparseable relay message: the core refuses with a
  recorded reason, and the relay layer additionally tears the connection down. There
  are no silent fallbacks and no truncated answers.

---

# The core: `src/nostrxt.livecodescript` (`nx*`)

Pure compute. No I/O, no sockets, no connection state; offline-testable and embedded
verbatim in the suite paste. Load it first - the relay layer composes it.

## Version, errors, capabilities

Dependencies are probed, never assumed: the probe does a REAL round-trip per
extension (a known hash, a real random byte) rather than a version sniff, caches the
answer for the session, and a missing extension disables exactly its feature.

| Handler | Kind | Purpose |
|---|---|---|
| `nxVersion()` | function | The member name and version string. |
| `nxLastError()` | function | The reason the most recent failing `nx*` call recorded. Read it immediately; any later failure overwrites it. |
| `nxProbeCapabilities()` | function | Cached capability array: `hasCoin`, `hasSodium`, `canSign`, `canNip44Cipher`, `version`. `canNip44Cipher` is false when the installed SodiumXT predates ABI 10, where the NIP-44 cipher shipped 2026-08-23 (`07-capabilities-required.md`); for a live re-probe of that one seam use `nxNip44HasCipher()`. |

## Hex and encoding helpers

Hex is the API's currency: lowercase out, either case in, anything else refuses.
`nxB64Encode` strips the line breaks the engine's `base64Encode` may wrap with,
because every wire format here (NIP-44 payloads, `Sec-WebSocket-Key`) is single-line
- the exact wrap behaviour is an on-engine VERIFY (`08-open-questions.md`).

| Handler | Kind | Purpose |
|---|---|---|
| `nxHexEncode(pData)` | function | Bytes to lowercase hex. |
| `nxHexDecode(pHex)` | function | Hex (either case) to bytes; odd length or a non-hex character refuses. |
| `nxIsHex(pText, pLen)` | function | True when `pText` is entirely hex and (when `pLen` is not empty) exactly `pLen` characters - the id/pubkey/sig validation everything uses. |
| `nxCtEqualHex(pAHex, pBHex)` | function | Constant-time-ish equality for hex strings (MACs, ids). Prefers SodiumXT `sxMemEqual` over the decoded bytes; a never-exits-early accumulate loop stands in without it. Guards the gross early-exit leak, not a lab-grade side channel. |
| `nxB64Encode(pData)` | function | Standard base64, one line (both break bytes stripped). |
| `nxB64Decode(pText)` | function | Standard base64 with padding; refuses characters outside the alphabet, data after padding, and a length that is not a multiple of 4 - a malformed payload is an error, not a partial decode. |
| `nxUnixNow()` | function | The unix timestamp (seconds) events stamp `created_at` with. |

## JSON

Owned, not borrowed, for two reasons: NIP-01's canonical form and JSON disagree
about control characters (see `02-nip01-events.md`), and nothing in the suite
encodes JSON at all. The parser walks UTF-8 bytes, is strict (byte-exact bare words,
surrogate-pair validation, a nesting-depth cap, no trailing bytes), and records byte
spans so a caller can slice a sub-document VERBATIM - which is what lets an inbound
event's id be recomputed from a canonical re-serialization instead of trusting the
wire bytes.

Paths are `/`-separated: object keys by name, array elements by 1-based index, the
empty path meaning the root. A key containing `/` is not addressable through this
convenience (documented limit).

| Handler | Kind | Purpose |
|---|---|---|
| `nxJsonEscape(pText)` | function | The NIP-01 escape set, exactly seven escapes; every other byte verbatim, control bytes included. This is the rule that makes borrowed JSON encoders produce wrong event ids. |
| `nxJsonGet(pJson, pPath)` | function | The scalar at `pPath` (strings decoded, numbers as source text, booleans `"true"`/`"false"`, null empty). An object or array at the path returns its VERBATIM source slice. |
| `nxJsonCount(pJson, pPath)` | function | Element count of the array (or member count of the object) at `pPath`; empty, with the reason, for a scalar or an error. |
| `nxJsonType(pJson, pPath)` | function | `"object"` / `"array"` / `"string"` / `"number"` / `"boolean"` / `"null"`, or `"missing"` when the path does not resolve. |

## Keys

Generation composes SodiumXT randomness and CoinXT validation; this member mints no
randomness and validates no scalar itself (CLAUDE.md rule 1). Secret keys cross as
hex strings by design, which carries an honest limit: OXT script variables are not
locked memory, and key storage is the app's job, not this library's.

| Handler | Kind | Purpose |
|---|---|---|
| `nxKeyGenerate()` | function | A fresh secret key as 64 hex. Refuses outright without SodiumXT (`sxRandomBytes`) or CoinXT (`cxSeckeyIsValid`) - it never degrades to weaker randomness. |
| `nxKeyPublic(pSeckeyHex)` | function | The 64-hex x-only public key (the Nostr pubkey) for a secret key, via CoinXT `cxXOnlyPubkey`. |
| `nxKeyIsValid(pSeckeyHex)` | function | True when the hex is a valid secp256k1 scalar (CoinXT `cxSeckeyIsValid`). |

## Events and tags

The heart of the member. The canonical serialization is the id preimage and is
byte-for-byte law (`02-nip01-events.md`); an inbound event is untrusted text until
`nxEventVerify(...)` says otherwise (rule 2). The event record itself is described
under "The event array shape" below.

| Handler | Kind | Purpose |
|---|---|---|
| `nxEventBuild(pKind, pContent, pTags, pCreatedAt)` | function | An UNSIGNED event array. `pTags` is a nested tag array (or empty); `pCreatedAt` empty means now. |
| `nxEventSerialize(pEvent)` | function | The canonical `[0,pubkey,created_at,kind,tags,content]` string NIP-01 hashes. Refuses an event with no pubkey: a half-built event would serialize to a well-formed WRONG preimage. |
| `nxEventId(pEvent)` | function | 64-hex SHA-256 (CoinXT `cxSha256`) of the canonical serialization's UTF-8 bytes. |
| `nxEventSign(pEvent, pSeckeyHex, pAuxHex)` | function | Fills pubkey, id and sig; returns the completed event. `pAuxHex` empty draws fresh BIP-340 auxiliary randomness; a 64-hex value makes the signature deterministic (KAT use). |
| `nxEventVerify(pEvent)` | function | True ONLY when the id recomputes from the fields AND the BIP-340 signature verifies over it. Everything else is false with the reason recorded. |
| `nxEventHasValidShape(pEvent)` | function | Structural validation with the reason recorded: integers in range, hex fields the right length, tags an array of arrays of strings each with a name. |
| `nxEventToJson(pEvent)` | function | The full wire-format event object (for `["EVENT", ...]` and storage). The id never depends on this form - only on `nxEventSerialize(...)`'s. |
| `nxEventFromJson(pJson)` | function | Parses a wire-format event object into the event array. STRUCTURE only - call `nxEventVerify(...)` before trusting it. Requires `created_at` and `kind` to be plain digit runs: `"1e3"` coerces to an integer in this dialect, and a non-canonical number spelling must never reach the serializer. |
| `nxTagsFromText(pText)` | function | One tag per line, items tab-separated, into the nested tag array. A line with an empty first item refuses (a tag must have a name). |
| `nxTagsToText(pTags)` | function | The inverse; refuses a tag item containing a tab or line break rather than silently corrupting (use the array form for those). |
| `nxTagCount(pEvent)` | function | How many tags the event carries. |
| `nxTagItem(pEvent, pIndex)` | function | Tag number `pIndex` (1-based) as tab-joined text; out of range is a clean miss. |
| `nxTagFirst(pEvent, pTagName)` | function | The VALUE (second item) of the first tag named `pTagName`. Byte-exact name compare: `"p"` and `"P"` are different tags, and `is` folds case in this dialect. |
| `nxTagValues(pEvent, pTagName)` | function | Every value of every tag named `pTagName`, one per line. |

## Builders (the core kinds)

Every builder returns an UNSIGNED event array - `nxEventSign(...)` completes it - so
key material never threads through code that does not need it.

| Handler | Kind | Purpose |
|---|---|---|
| `nxMetadataBuild(pName, pAbout, pPicture, pCreatedAt)` | function | Kind 0 user metadata; the content is the stringified JSON object. |
| `nxMetadataParse(pEvent)` | function | The common kind-0 content fields as an array (`name`, `about`, `picture`, `display_name`, `nip05`, `website`, `banner`, `lud16`); absent fields empty. |
| `nxReplyBuild(pParentEvent, pContent, pCreatedAt)` | function | A kind-1 reply with NIP-10 MARKED tags: the thread root (the parent's own root tag, or the parent itself), a reply marker on the parent, and deduplicated `p` tags for the people in the thread. |
| `nxReactionBuild(pTargetEvent, pContent, pCreatedAt)` | function | Kind 7 reaction (NIP-25); empty content means the conventional `"+"`; carries the target's kind as a `k` tag. |
| `nxDeleteBuild(pIdLines, pReason, pCreatedAt)` | function | Kind 5 deletion request (NIP-09): one `e` tag per 64-hex event id line. |
| `nxContactsBuild(pPubkeyLines, pCreatedAt)` | function | Kind 3 contact list: one `p` tag per followed 64-hex pubkey line. |
| `nxContactsParse(pEvent)` | function | The followed pubkeys of a kind 3 event, one per line. |
| `nxRelayListBuild(pRelayLines, pCreatedAt)` | function | Kind 10002 relay list (NIP-65): each line `url` (read and write) or `url<tab>read` / `url<tab>write`. |
| `nxRelayListParse(pEvent)` | function | The `r` tags of a kind 10002 event, one relay per line, marker preserved. |
| `nxAuthBuild(pRelayUrl, pChallenge, pCreatedAt)` | function | Kind 22242 NIP-42 authentication event. Sign it, then hand it to `nxrAuth` (or wrap it with `nxClientAuth(...)` yourself). |

## NIP-19 entities and bech32

bech32 is implemented IN this member, deliberately: CoinXT's engine-proven copy
enforces BIP-173's 90-character cap in both directions (correct for its Bitcoin
callers) and keeps its bit converters private, while NIP-19 waives the cap for TLV
entities. NostrXT enforces NIP-19's 5000-character SHOULD instead, and the KAT pins
full BIP-173 conformance INCLUDING asserting that deliberate deviation
(`03-nip19-entities.md`, and the declined-upstreaming record in
`07-capabilities-required.md`). Relay lists cross these handlers as
return-delimited lines.

| Handler | Kind | Purpose |
|---|---|---|
| `nxBech32Encode(pHrp, pHex, pSpec)` | function | Generic encoder; `pSpec` is `"bech32"` (default, what NIP-19 uses) or `"bech32m"`. Lowercase out; an uppercase HRP refuses (uppercase the finished string instead, as BIP-173 defines). |
| `nxBech32Decode(pText)` | function | Generic decoder, either spec, returning `hrp` / `spec` / `hex`. Mixed case refuses; padding is strict. |
| `nxNpubEncode(pPubkeyHex)` | function | Public key to `npub1...`. |
| `nxNpubDecode(pText)` | function | `npub1...` to 64-hex; wrong hrp, wrong spec or wrong payload length refuses. |
| `nxNsecEncode(pSeckeyHex)` | function | Secret key to `nsec1...` - for explicit backup flows only; see `nxUriEncode(...)`'s refusal. |
| `nxNsecDecode(pText)` | function | `nsec1...` to 64-hex. |
| `nxNoteEncode(pIdHex)` | function | Event id to `note1...`. |
| `nxNoteDecode(pText)` | function | `note1...` to 64-hex. |
| `nxNprofileEncode(pPubkeyHex, pRelayLines)` | function | TLV profile pointer: pubkey plus relay hints. |
| `nxNprofileDecode(pText)` | function | The fields of an `nprofile1...` (`pubkey`, `relays`). |
| `nxNeventEncode(pIdHex, pRelayLines, pAuthorHex, pKind)` | function | TLV event pointer: id plus optional relay hints, author and kind. |
| `nxNeventDecode(pText)` | function | The fields of an `nevent1...` (`id`, `relays`, `pubkey`, `kind`). |
| `nxNaddrEncode(pIdentifier, pPubkeyHex, pKind, pRelayLines)` | function | TLV addressable-event coordinate: the `d`-tag identifier (may be empty), author and kind REQUIRED, optional relay hints. |
| `nxNaddrDecode(pText)` | function | The fields of an `naddr1...` (`identifier`, `pubkey`, `kind`, `relays`). |
| `nxEntityDecode(pText)` | function | The generic decoder every entity handler shares: accepts ANY NIP-19 entity (a `nostr:` prefix is stripped first), returns an array keyed by `type` plus that entity's fields. Unknown TLV types are ignored, as NIP-19 requires; a truncated TLV refuses. |
| `nxUriEncode(pEntity)` | function | A NIP-21 `nostr:` URI for a SHAREABLE entity. REFUSES an nsec: a secret key in a URI is a secret key in somebody's chat log. |
| `nxUriDecode(pUri)` | function | The entity fields of a `nostr:` URI; wants the prefix (the spelling exists so intent reads at the call site). |

## NIP-44 v2 encrypted payloads

Every step is vector-pinned by the KAT, the cipher call included since 2026-08-23:
family law says a missing primitive is an upstream feature request, never a
hand-rolled cipher here, and the request shipped as SodiumXT ABI 10's
`sxChaCha20IetfXor` (`07-capabilities-required.md` is the closed record). On an
installed SodiumXT older than ABI 10, `nxNip44Encrypt(...)` / `nxNip44Decrypt(...)`
fail closed with a capability error naming it; the conversation key, message keys,
padding and the MAC path work either way. On decrypt the MAC verifies BEFORE the
cipher runs, over
nonce||ciphertext, compared constant-time - the member harness proves that order now,
cipher or no cipher.

Plaintext is 1 to 65535 bytes, fail closed: the published vectors pin the u16 length
prefix only (65536 and up is an invalid length there), and the newer spec text's
extended 6-byte prefix has no vectors yet (`08-open-questions.md`).

| Handler | Kind | Purpose |
|---|---|---|
| `nxNip44ConversationKey(pSeckeyHex, pPubkeyHex)` | function | HKDF-extract(salt `"nip44-v2"`, ECDH shared x) as 64 hex, via CoinXT `cxEcdh` / `cxHmacSha256`. Symmetric in the roles: conv(a, B) equals conv(b, A). |
| `nxNip44MessageKeys(pConvKeyHex, pNonceHex)` | function | HKDF-expand to 76 bytes, sliced into `chachaKey` (32B), `chachaNonce` (12B), `hmacKey` (32B), all hex. |
| `nxNip44PaddedLen(pLen)` | function | The padded length of a `pLen`-byte plaintext (the vectors' pair table pins it). |
| `nxNip44HasCipher()` | function | A LIVE probe of the cipher seam, so an upgraded SodiumXT is noticed without restarting (unlike the cached `nxProbeCapabilities()` row). |
| `nxNip44Encrypt(pSeckeyHex, pPubkeyHex, pPlaintext, pNonceHex)` | function | The full versioned payload, standard base64. `pNonceHex` empty draws 32 fresh SodiumXT bytes; a fixed nonce is for KATs ONLY - never reuse one in anger. Fails closed on a SodiumXT older than ABI 10. |
| `nxNip44Decrypt(pSeckeyHex, pPubkeyHex, pPayload)` | function | MAC-verify, then decrypt and unpad, strict at every step (version byte, length floors, padding agreement). Fails closed on a SodiumXT older than ABI 10. |

## Filters and the wire messages

Client-to-relay messages assemble; relay-to-client messages parse. Message types
compare BYTE-EXACT (`"EVENT"`, not `"event"`): `is` folds case in this dialect, and a
relay speaking lowercase is not speaking NIP-01.

| Handler | Kind | Purpose |
|---|---|---|
| `nxFilterBuild(pFilter)` | function | A NIP-01 filter object from an array: `ids` / `authors` (lines of 64-hex), `kinds` (comma list), `since` / `until` / `limit` (integers), `search`, and any single-letter tag filter keyed `#e`, `#p`, ... (lines of values). Deterministic field order. |
| `nxFilterMatches(pFilterJson, pEvent)` | function | Client-side NIP-01 matching: every present condition must hold (AND); list conditions need one exact member; `since` / `until` inclusive. False on any doubt. |
| `nxClientReq(pSubId, pFiltersJson)` | function | `["REQ", subid, filter, ...]` - one filter object per line of `pFiltersJson` (what `nxFilterBuild(...)` emits); at least one required. |
| `nxClientClose(pSubId)` | function | `["CLOSE", subid]`. |
| `nxClientEvent(pEvent)` | function | `["EVENT", {...}]`; refuses an unsigned event. |
| `nxClientAuth(pEvent)` | function | `["AUTH", {...}]`; refuses anything but a SIGNED kind-22242 event. |
| `nxRelayParse(pWire)` | function | One relay-to-client message into an array keyed by `type`: `EVENT` (`subId`, `eventJson` - the VERBATIM object slice), `OK` (`eventId`, `accepted`, `reason`), `EOSE` (`subId`), `CLOSED` (`subId`, `reason`), `NOTICE` (`notice`), `AUTH` (`challenge`); anything else is `unknown` with `raw`. |

## Websocket pure helpers (RFC 6455, the compute half)

The stateful socket machine lives in the relay layer; these are the pieces it
composes, and they are what make the protocol math offline-testable. An app only
needs them directly to build its own transport.

| Handler | Kind | Purpose |
|---|---|---|
| `nxWsUrlParse(pUrl)` | function | `ws://` / `wss://` into `scheme`, `secure`, `host`, `port` (default 80 / 443), `path`. IPv6 bracket literals refuse (documented limit). |
| `nxWsHandshakeRequest(pHost, pPort, pPath, pKeyB64, pSecure)` | function | The client upgrade request, CRLF-terminated; the Host header omits the port only at the SCHEME'S default (80 for ws, 443 for wss, per RFC 6455 section 4.1), which is why the secure flag is an argument. |
| `nxWsAcceptFor(pKeyB64)` | function | The `Sec-WebSocket-Accept` a compliant server must answer: base64 of SHA-1 over the key then the RFC GUID. `sha1Digest` is the engine's own builtin - the one engine-proven builtin hash in this tree. |
| `nxWsFrameEncode(pOpcode, pPayload, pMaskHex)` | function | One client frame: FIN set, MASKED (RFC 6455 requires a client to mask), no fragmentation. `pMaskHex` is 8 hex chars; the relay layer draws it fresh per frame - a fixed mask is for KATs. |
| `nxWsFrameDecode(pBuffer)` | function | Parse ONE frame at the head of a buffer. `complete` false means read more (`needMore` says how much when known); `error` non-empty means the stream is unrecoverable - fail closed and close the socket (hostile length, reserved bits, oversized control frame). When complete: `fin`, `opcode`, `masked`, `payload` (unmasked), `consumed`. |

## Proof of work, NIP-05, NIP-11

The two `pJsonBody` handlers parse a document the APP fetched: this file does no
I/O, so the HTTPS GET (libURL or whatever proxy the app prefers) is the caller's.

| Handler | Kind | Purpose |
|---|---|---|
| `nxPowDifficulty(pIdHex)` | function | Leading zero BITS of an event id (NIP-13's definition). |
| `nxPowCheck(pEvent, pMinBits)` | function | True when the id meets `pMinBits` AND any committed target (the third entry of a `nonce` tag) is itself at least `pMinBits` - NIP-13's lucky-miner rule. |
| `nxNip05Url(pIdentifier)` | function | The `.well-known/nostr.json` url for `name@domain` (a bare domain means `_@domain`). The fetch is the app's. |
| `nxNip05Verify(pJsonBody, pUserName, pPubkeyHex)` | function | True when the fetched document maps `pUserName` to `pPubkeyHex` (case-folded hex compare). |
| `nxRelayInfoParse(pJsonBody)` | function | The common NIP-11 relay-information fields as an array; `supportedNips` as a comma list. |

---

# The relay client: `src/nostr-relay.livecodescript` (`nxr*`)

The stateful half: an RFC 6455 client over engine sockets speaking the NIP-01 relay
protocol. It composes the core and owns only sockets, buffers and handles. Handles
are small integers; a stale handle or socket id is a clean no-op or a clean error,
never a crash, and every open has an idempotent close.

**This file is deliberately NOT in the suite paste**: it defines the engine's
`socketError` / `socketClosed` / `socketTimeout` handlers, which the embedded OnionXT
layer also defines, and the suite generator refuses (as it must) an assembly defining
one handler twice. It ships in the demo embed instead (the `onion-httpd` precedent;
see `00-overview.md`).

## Wiring

| Handler | Kind | Purpose |
|---|---|---|
| `nxrVersion()` | function | The relay layer's version string (composes `nxVersion()`, so it also proves the core is loaded). |
| `nxrInit pOwner` | command | Set the object whose script receives the callbacks (the demo passes `the long id of me` in `preOpenStack`). Unset, callbacks dispatch to the topStack. Idempotent. |
| `nxrSetCallback pRelay, pHandlerName` | command | Register the per-relay callback handler (the contract below). |
| `nxrSetVerify pRelay, pVerify` | command | Event verification is ON by default and fails closed: without CoinXT, inbound events arrive as `"invalid"`, never as unverified `"event"`s. Turning it off is a per-relay, eyes-open act. |

## Connect and the client verbs

`nxrConnect` returns the handle immediately; the handshake completes asynchronously
and the callback receives `"open"` or `"error"`. Everything that writes requires the
relay to be in the `"open"` state and says so otherwise.

| Handler | Kind | Purpose |
|---|---|---|
| `nxrConnect pUrl` | command | Open a relay (`ws://` today; `wss://` written but engine-unproven, `07-capabilities-required.md`). Returns the integer handle in `the result`; a handshake watchdog fails a stalled connection closed. |
| `nxrSubscribe pRelay, pSubId, pFiltersJson` | command | Send a REQ (one filter object per line, the `nxClientReq(...)` shape) and remember the subscription. |
| `nxrUnsubscribe pRelay, pSubId` | command | Send a CLOSE and forget the subscription. |
| `nxrPublish pRelay, pEvent` | command | Send a SIGNED event; the relay's verdict arrives as the `"ok"` callback keyed by the event id. |
| `nxrAuth pRelay, pSignedEvent` | command | Answer a NIP-42 challenge with a signed kind-22242 event (`nxAuthBuild(...)` + `nxEventSign(...)` built it). |
| `nxrSendRaw pRelay, pText` | command | The escape hatch for NIPs this layer does not speak yet: one text frame, verbatim; the caller owns the JSON. |
| `nxrPing pRelay` | command | An RFC 6455 ping (liveness probe); the pong is consumed silently on arrival. |

## State functions

| Handler | Kind | Purpose |
|---|---|---|
| `nxrState(pRelay)` | function | `"connecting"` / `"handshake"` / `"open"` / `"closing"`, or `"unknown"` for a stale handle. |
| `nxrUrl(pRelay)` | function | The url the relay was opened with. |
| `nxrChallenge(pRelay)` | function | The most recent NIP-42 challenge this relay sent, or empty. |
| `nxrOpenRelays()` | function | Every live relay handle, one per line. |

## Teardown

There is no deterministic unload hook in OXT, so the app frees what it opens: call
`nxrShutdown` from `closeStack`. Every teardown is idempotent and safe to call twice.

| Handler | Kind | Purpose |
|---|---|---|
| `nxrDisconnect pRelay` | command | App-initiated close: a close frame when the link is up, then teardown. A stale handle is a clean no-op. |
| `nxrShutdown` | command | Close every relay. |

## The relay callback contract

`nxrSetCallback pRelay, pHandlerName` registers one handler per relay; it is
dispatched (try-guarded - a throwing app handler must not break the socket state
machine, and a missing handler is a clean miss) to the owner set by `nxrInit` as:

```
<handler> pRelay, pKind, pArgOne, pArgTwo
```

| `pKind` | `pArgOne` | `pArgTwo` |
|---|---|---|
| `"open"` | - | - (handshake complete; the relay is usable) |
| `"event"` | subscription id | the raw event JSON, VERIFIED (id + signature) before delivery unless `nxrSetVerify` turned that off |
| `"invalid"` | subscription id | why the event was refused (failed verify, or CoinXT absent while verification is on - fail closed) |
| `"eose"` | subscription id | - |
| `"ok"` | event id | `"true"` or `"false"`, then a tab, then the relay's reason |
| `"closed"` | subscription id | the relay's reason |
| `"notice"` | the notice text | - |
| `"auth"` | the NIP-42 challenge (also kept for `nxrChallenge(...)`) | - |
| `"error"` | the failure | - (the relay is torn down) |
| `"disconnected"` | the reason | - (the relay is gone) |

A worked example with every branch is in `09-usage-guide.md`.

## Handlers the ENGINE calls

The relay layer defines six handlers that appear in none of the tables above and
that an app must never call by hand. They are documented because "absent from the
API reference" is, in practice, indistinguishable from "does not exist" - and the
last three carry the one integration hazard in this member whose symptom is a hang
rather than an error.

**Three `nxr*` handlers the layer arms and the engine (or a watchdog) calls back.**
Each opens by testing its argument against the live tables and exits on a miss, so a
stale id is a clean no-op. Note `nxrDeadline`'s argument is a RELAY HANDLE, not a
socket id - it is self-sent, not engine-sent:

| Handler | Armed by | Called when |
|---|---|---|
| `nxrWsOpened pSocketID` | `open socket` / `open secure socket ... with message` | TCP (or TLS) is up; sends the upgrade request and starts the one persistent read. |
| `nxrWsData pSocketID, pData` | `read from socket ... with message` (no quantifier) | a chunk arrived; appends to the relay's buffer, runs the state machine, re-arms only if the relay still exists. |
| `nxrDeadline pRelay` | `send ... to me in` (watchdog; takes a RELAY HANDLE) | the handshake watchdog expires; a connection not yet `"open"` fails closed. |

**Three engine socket MESSAGES, whose names are the engine's and so carry no `nxr`
prefix.** The relay layer acts only on socket ids it owns and PASSES the rest:

| Message | What the relay layer does with it |
|---|---|
| `socketError pSocketID, pError` | a socket failed: the owning relay fails closed (`"error"` callback, teardown). Not ours: passed. |
| `socketClosed pSocketID` | the far side closed: teardown with the `"disconnected"` callback. Not ours: passed. |
| `socketTimeout pSocketID` | REPEATS while a read is pending, so it is fatal only during the handshake; on an open relay an idle read is normal. Not ours: passed. |

> **Integration rule: if your stack defines any of these three messages, it must
> `pass` the ones that are not its own.** Those three names are shared by every
> socket user in a process, and a stack script that handles one without forwarding
> it can swallow another library's copy before it runs. Nothing errors: the failed
> dial never reports, the closed stream never delivers, the stalled handshake never
> times out. **The symptom is a HANG, and no gate in this repo can see it.** This is
> the family's standing socket rule - two shipping apps re-derived it independently
> before it was written down - and it is the reason this file stays out of the suite
> paste (the embedded OnionXT layer defines the same three names). The relay layer
> holds up its own end: it acts only on its own socket ids and passes everything
> else, so it coexists with OnionXT or any other socket library in the same app.

## The event array shape

The one record this library passes around. An event is an xTalk array:

| Key | Type | Meaning |
|---|---|---|
| `id` | 64 lowercase hex | SHA-256 of the canonical serialization (empty until signed). |
| `pubkey` | 64 lowercase hex | The author's x-only public key (empty until signed). |
| `created_at` | integer | Unix seconds. |
| `kind` | integer 0..65535 | The event kind. |
| `content` | string | The payload; arbitrary UTF-8 text. |
| `sig` | 128 lowercase hex | The BIP-340 signature over the id (empty until signed). |
| `tags` | nested array | 1-based both ways: `tEvent["tags"][1][1]` is the first tag's name, `tEvent["tags"][1][2]` its value, and so on. Empty when there are no tags. |

`nxEventHasValidShape(...)` is the executable form of this table;
`nxEventToJson(...)` / `nxEventFromJson(...)` convert to and from the wire object.
Everything hex is LOWERCASE on this API; binary never crosses it.

## Error model

- **Core `nx*`:** functions never throw. Failure returns empty (or `false`), and
  `nxLastError()` carries a human-readable reason that names the handler and the
  refusal (`"nxHexDecode: hex text has odd length"`,
  `"nxEventVerify: the signature does not verify"`).
- **Relay `nxr*`:** commands set `the result` to empty on success or to a
  `"NostrXT relay: ..."` string on refusal; handle-yielding commands return the
  integer handle, so callers test `the result is an integer`. Wire errors
  additionally tear the relay down and surface through the `"error"` callback.
- **Capability errors are a named shape, not a generic failure.** A missing
  extension produces a reason naming exactly the handler it needs, so an app can
  branch on the probe rather than parse the string:
  `"nxEventId needs CoinXT cxSha256: ..."`,
  `"nxKeyGenerate needs SodiumXT sxRandomBytes"`, and the pre-ABI-10-SodiumXT one,
  `"nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT ABI 10; the
  installed SodiumXT predates it - docs/07-capabilities-required.md)"`. Probe with
  `nxProbeCapabilities()` (cached) and `nxNip44HasCipher()` (live).

## What is deliberately NOT here

- **NIP-04 (`AES-256-CBC` DMs).** A decision, not a gap: no AES exists anywhere in
  this suite, libsodium will never provide CBC, and NIP-04 is superseded by NIP-44.
  The full reasoning is in `07-capabilities-required.md`, under "Non-gaps".
- **No key storage.** Keys cross this API as hex strings and live wherever the app
  puts them; NostrXT is not a vault, and OXT script variables are not locked memory.
  The honest limit is documented, not papered over (`01-protocol-model.md`).
- **No relay pool management yet.** One handle is one relay; multi-relay strategy
  (outbox routing, deduplication across relays) is an open protocol-scope question
  (`08-open-questions.md`), deliberately not guessed at in v0.1.
- **No engine JSON dependency.** The core parses and emits its own JSON over UTF-8
  bytes, because NIP-01's canonical form and stock JSON encoders disagree about
  control characters, and because depending on an engine JSON library would put the
  id preimage - the one thing this member must never get wrong - behind behaviour no
  gate here can pin.
- **No blocking network calls.** The whole relay surface is callback-driven so the
  one interpreter thread never blocks on the network; the NIP-05 / NIP-11 fetches
  are the app's for the same reason.
