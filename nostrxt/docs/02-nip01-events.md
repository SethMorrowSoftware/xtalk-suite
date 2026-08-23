# 02 - NIP-01 Events, Byte for Byte

> STATUS: verified statically; needs an OXT pass. Every byte-level claim in this
> document is pinned headlessly: `tools/nostr-kat.py` derives the fixture
> serializations, ids and signatures through the independent oracle
> `tools/nostr_reference.py` (which sweeps the full published BIP-340 csv), and
> `tools/check-selftest-vectors.py` re-derives every constant the member harness
> pins, by name, on every build.

This is the one wire format where "close enough" produces a wrong answer that LOOKS
right: a serialization that differs by one byte yields a well-formed, plausible,
WRONG event id, and the signature over it verifies perfectly - against the wrong
event. So NostrXT owns the serializer byte for byte instead of borrowing a JSON
encoder, and this document is the as-implemented spec (`nxEventSerialize` and
`nxJsonEscape` in `src/nostrxt.livecodescript`).

## The event, as an xTalk array

The one record this library passes around. An event is an array with these keys:

| Key | Type on this API |
|---|---|
| `id` | 64 lowercase hex (sha256 of the canonical serialization) |
| `pubkey` | 64 lowercase hex (x-only secp256k1) |
| `created_at` | unix seconds, a non-negative integer |
| `kind` | integer 0..65535 |
| `content` | string (arbitrary, UTF-8 when serialized) |
| `sig` | 128 lowercase hex (BIP-340 Schnorr over the id bytes) |
| `tags` | a 1-based nested array, or empty when there are none |

Tags nest 1-based both ways: `tEvent["tags"][1][1]` is the first tag's name,
`tEvent["tags"][1][2]` its value, and so on. Ids, pubkeys, seckeys and sigs cross
this API as lowercase hex strings; binary stays internal. `nxEventBuild` returns an
UNSIGNED event (empty id/pubkey/sig); `nxEventSign` completes it.

## The canonical serialization

The id preimage is the UTF-8 encoding of this JSON array, with NO whitespace
anywhere:

```
[0,"<pubkey lowercase hex>",<created_at>,<kind>,<tags>,"<content>"]
```

`tags` serializes as an array of arrays of strings; every string in the document
(content and each tag item) is escaped by exactly the rule below.

### Exactly seven escapes

NIP-01 names seven characters that escape, and - this is the load-bearing half of
the rule - EVERY OTHER BYTE PASSES VERBATIM, control bytes included. `nxJsonEscape`
implements precisely this table and nothing else:

| Byte | Escapes to |
|---|---|
| 0x22 (double quote) | `\"` |
| 0x5C (backslash) | `\\` |
| 0x0A (line feed) | `\n` |
| 0x0D (carriage return) | `\r` |
| 0x09 (tab) | `\t` |
| 0x08 (backspace) | `\b` |
| 0x0C (form feed) | `\f` |

Why a stock JSON encoder produces wrong ids: JSON's own rules require escaping ALL
control characters below 0x20, so `json.dumps` (and nearly every library encoder)
emits the six-character text \u0001 for a 0x01 byte in content. NIP-01's
preimage carries that byte verbatim. Both outputs are valid JSON; they are different byte strings; they hash to
different ids. The escaping and JSON agree on ordinary text and diverge exactly on
the inputs nobody tests by hand, which is why the KAT asserts the divergence
directly: `tools/nostr-kat.py`'s NIP-01 sweep checks that a 0x01 passes through
verbatim, that the seven-character escape set matches, AND that on fixture events
without exotic controls the canonical string parses back as JSON with the exact
field values (an independent parse of our own serializer). Multi-byte UTF-8
sequences pass through untouched; the escaper walks bytes, and everything at or
above 0x80 is "every other byte".

Two more properties of the serializer worth knowing:

- **It refuses a half-built event.** Serializing before `pubkey` is filled in would
  produce a well-formed WRONG preimage, so `nxEventSerialize` returns empty (reason
  in `nxLastError()`) until sign fills it.
- **Integers serialize as plain digit runs.** `nxEventFromJson` enforces the inverse:
  an inbound `created_at` or `kind` spelled `1e3` or `1.5` refuses, because this
  dialect would coerce it to an integer and the re-serialization would silently
  change the id preimage.

## The id, and the signature

- **id** = lowercase hex of `cxSha256` over the canonical serialization's UTF-8
  bytes (`nxEventId`). CoinXT is the hard dependency; NostrXT ships no hash.
- **sig** = `cxSchnorrSign(seckey, id bytes, aux)` (`nxEventSign`), BIP-340. The
  third parameter is BIP-340's auxiliary randomness, and its semantics matter:
  - `pAuxHex` EMPTY: CoinXT's shim draws fresh OS randomness per signature. This is
    the production setting; signatures are non-deterministic and that is fine
    (verification does not care).
  - `pAuxHex` as 64 hex (32 bytes): the signature is fully deterministic, which is
    what makes it KAT-pinnable. The fixture signature `kNxVecSigA` in the harness is
    produced with the all-zero aux, matching the published BIP-340 vectors' own
    convention. Deterministic aux is for tests; in anger, pass empty.

Verification (`nxEventVerify`) recomputes the id from the fields, compares it to the
claimed `id` (constant-time-ish, `nxCtEqualHex`), then `cxSchnorrVerify`s the sig
over it. Both legs must hold; everything else is false with the reason recorded.

## Tags conventions

A tag is a 1-based list of strings whose first item is its name, and names compare
BYTE-EXACT: `p` and `P` are different tags, which is why every name comparison in
this library goes through a byte compare rather than `is` (this dialect's `is` folds
case). The conventions this member's builders and lookups actually use:

- `e` tags reference an event id (`["e", <id hex>, <relay url>, <marker>]`);
  `nxReplyBuild` writes NIP-10 marked `root`/`reply` e tags.
- `p` tags reference a pubkey; `nxReplyBuild` and `nxReactionBuild` carry the thread
  and target participants, `nxContactsBuild` (kind 3) uses one per follow.
- `a` tags reference an addressable-event coordinate (`kind:pubkey:d-identifier`);
  NostrXT encodes the same coordinate as an `naddr` entity (`03-nip19-entities.md`).
- **Single-letter tag names are the indexable ones.** Relays index them, and filters
  reach them as `#e`, `#p`, ... keys (`nxFilterBuild` accepts any `#x` key;
  `nxFilterMatches` checks all 52 single letters). A multi-letter tag name (`relay`,
  `challenge`, `nonce`) is data, not an index.

`nxTagsFromText` / `nxTagsToText` convert between the nested-array form and a
one-tag-per-line, tab-separated text form for convenience; the text form refuses
items containing tabs or line breaks rather than corrupting them.

## Kind ranges

`kind` tells a relay what storage semantics the event wants. `nxEventBuild` accepts
any integer 0..65535 and enforces no range policy (the ranges are RELAY retention
conventions, not client validity rules); the builders this member ships land where
NIP-01 says they should:

| Range | Semantics | This member's builders there |
|---|---|---|
| 1000..9999 (and 1, 2, 4..44) | regular: store all | `nxEventBuild(1,...)`, `nxReplyBuild` (1), `nxDeleteBuild` (5), `nxReactionBuild` (7) |
| 10000..19999 (and 0, 3) | replaceable: latest per pubkey+kind wins | `nxMetadataBuild` (0), `nxContactsBuild` (3), `nxRelayListBuild` (10002) |
| 20000..29999 | ephemeral: relayed, not stored | `nxAuthBuild` (22242, NIP-42) |
| 30000..39999 | addressable: latest per pubkey+kind+d-tag wins | none built here; `nxNaddrEncode` names their coordinates |

## The wire messages

Client to relay (all built by the core, sent by the relay layer):

| Message | Builder | Shape |
|---|---|---|
| `["REQ", <subid>, <filter>...]` | `nxClientReq` | subscribe; one or more filter objects (`nxFilterBuild`) |
| `["CLOSE", <subid>]` | `nxClientClose` | end a subscription |
| `["EVENT", {...}]` | `nxClientEvent` | publish; refuses an unsigned event |
| `["AUTH", {...}]` | `nxClientAuth` | answer a NIP-42 challenge; refuses anything but a signed kind 22242 |

Relay to client (all parsed by `nxRelayParse` into an array keyed by `"type"`):

| Message | Fields parsed |
|---|---|
| `["EVENT", <subid>, {...}]` | `subId`, `eventJson` - the VERBATIM object slice, byte for byte as the relay sent it |
| `["OK", <id>, <bool>, <msg>]` | `eventId`, `accepted`, `reason` - the relay's verdict on your publish |
| `["EOSE", <subid>]` | `subId` - stored events done; live events follow |
| `["CLOSED", <subid>, <msg>]` | `subId`, `reason` - the relay ended your subscription |
| `["NOTICE", <msg>]` | `notice` - human-readable |
| `["AUTH", <challenge>]` | `challenge` - a NIP-42 challenge (see `05-relay-client.md`) |

Two rules the parser holds that are easy to get wrong:

- **Message types compare byte-exact.** A relay saying `"event"` is not speaking
  NIP-01 and is not treated as if it were; it parses to type `"unknown"` with the
  raw text attached, and the relay layer surfaces it as a notice rather than
  guessing.
- **The inbound event object is sliced VERBATIM, then re-serialized canonically for
  checking.** `nxRelayParse` hands back the exact byte span of the event object;
  `nxEventFromJson` parses its structure; `nxEventVerify` then recomputes the id
  from the FIELDS through this member's own canonical serializer. The wire bytes
  are never trusted to be canonical - a relay could ship the same event with
  different whitespace or escaping, and the id must still check out.
