# 03 - NIP-19 Entities: bech32 for Humans

> STATUS: the `nx*` core is ENGINE-PROVEN 2026-08-24 (Windows x86_64, OXT
> 9.6.3; 274 passed, 0 failed, 2 deliberate skips in the suite paste, both of
> them the relay layer, which is not in the paste by design). The bech32 layer is additionally pinned
> headlessly by `tools/nostr-kat.py`, which sweeps the BIP-173 valid and invalid
> strings and the published NIP-19 examples through the independent oracle - and
> asserts the one deliberate BIP-173 deviation ON PURPOSE (below).

Hex keys and ids are the protocol's native currency; bech32 entities are their
human coat: typo-detecting (a BCH checksum that, at BIP-173's lengths, catches any
error touching up to four characters - the guarantee weakens as strings grow past
that, which matters below), prefix-labeled so a pasted string announces what it
is, and
double-click-selectable. NIP-19 says plainly that these encodings are for DISPLAY
and TRANSPORT between people, never for use inside events or filters - and this
member's API mirrors that: everything protocol-facing takes hex, and the `nx*Encode`
/ `nx*Decode` pairs live at the UI boundary.

## The bare entities

Three prefixes share one shape: exactly 32 bytes of payload, bech32 (not bech32m).

| Prefix | Payload | Encode / decode |
|---|---|---|
| `npub` | x-only public key | `nxNpubEncode` / `nxNpubDecode` |
| `nsec` | secret key | `nxNsecEncode` / `nxNsecDecode` |
| `note` | event id | `nxNoteEncode` / `nxNoteDecode` |

Each decoder enforces all three properties (the expected prefix, the bech32 spec,
the 32-byte payload), so an `nsec` pasted where an `npub` belongs is a clear
refusal with the reason in `nxLastError()`, never a silently accepted key.

## The TLV entities

The richer entities pack a TLV (type, one length byte, value) stream as the bech32
payload, so one string can carry an id plus routing hints:

| Prefix | Required | Optional | Handlers |
|---|---|---|---|
| `nprofile` | pubkey (type 0) | relays (type 1, repeatable) | `nxNprofileEncode` / `nxNprofileDecode` |
| `nevent` | event id (type 0) | relays (1), author (2), kind (3) | `nxNeventEncode` / `nxNeventDecode` |
| `naddr` | d identifier (type 0, may be empty), author (2), kind (3) | relays (1) | `nxNaddrEncode` / `nxNaddrDecode` |

The TLV types, as implemented (`nxEntityDecode` is the one generic decoder every
entity handler shares):

- **Type 0 (special):** 32 bytes for nprofile (the pubkey) and nevent (the id);
  for naddr it is the `d` tag identifier as UTF-8, any length up to the TLV's
  one-byte limit of 255.
- **Type 1 (relay):** an ASCII relay url; repeatable, one TLV per relay. The
  encoders refuse a non-ASCII url rather than guessing an encoding.
- **Type 2 (author):** 32 bytes, the author pubkey.
- **Type 3 (kind):** the kind as an unsigned 32-bit BIG-ENDIAN integer, exactly
  4 bytes. (Note the width: events cap kinds at 65535 but the TLV field is u32 by
  the NIP, and the decoder reads all four bytes.)
- **Unknown types are IGNORED**, as NIP-19 requires - the stream position advances
  past them and decoding continues. This is the NIP's forward-compatibility rule:
  a new optional TLV type must not break old decoders. Truncated TLVs (a header or
  value running past the payload) refuse; unknown types skip.

Decoded fields come back as an array keyed `type`, `pubkey`, `id`, `identifier`,
`kind`, `relays` (one per line). Each decoder checks its type's REQUIRED fields
after the walk (an nprofile without a pubkey, an nevent without an id, an naddr
without author and kind all refuse).

## Why NostrXT carries its OWN bech32

CoinXT already ships an engine-proven bech32, and this member deliberately does not
use it, for two reasons that are both structural rather than stylistic:

1. **CoinXT enforces BIP-173's 90-character cap in both directions** (its
   `kCxBech32MaxLen`), which is correct for Bitcoin addresses and fatal for NIP-19:
   a TLV entity with a couple of relay hints blows past 90 characters routinely
   (the fixture `nevent` in the harness is over 170). NIP-19 explicitly waives the
   cap for TLV entities.
2. **CoinXT's 8-to-5 bit converters are private** (`cxConvert8To5` /
   `cxConvert5To8` are `private function`s), and its public surface takes 5-bit
   value lists, so composing it would mean reimplementing the byte conversion here
   anyway - at which point the checksum arithmetic is the only shared part, and
   sharing it across a cap disagreement invites exactly the kind of quiet behaviour
   change the family's carried-block gates exist to prevent.

So `src/nostrxt.livecodescript` implements bech32 and bech32m whole (charset,
polymod, HRP expansion, strict padding rules on decode, mixed-case refusal). This
is the checksummed byte shuffling family law allows in pure script; it is not
cryptography, and rule 1 (compose, never hand-roll crypto) is untouched.

### The deliberate BIP-173 deviation, and the cap that replaces it

- **The 90-character cap is waived.** BIP-173's invalid-vector list includes an
  over-90 string ("overall max length exceeded"); NostrXT DECODES it. The KAT
  asserts exactly that, on purpose: `tools/nostr-kat.py`'s bech32 sweep fails if
  the over-long vector ever starts refusing, so the deviation is pinned and cannot
  drift silently back to BIP-173 behaviour (or be "fixed" by a well-meaning
  cleanup).
- **NIP-19's 5000-character SHOULD is enforced instead**, fail closed, in BOTH
  directions (`kNxBech32MaxLen`): `nxBech32Encode` refuses to emit a longer string
  and `nxBech32Decode` refuses to read one. A SHOULD enforced beats an unbounded
  input path; the checksum's error-detection guarantees also degrade with length,
  which is why BIP-173 capped it in the first place.

Everything else is BIP-173 strict: the charset, the checksum constants (bech32's 1,
bech32m's 0x2bc830a3), the last-separator rule (a `1` may appear inside the HRP),
strict decode padding (more than four leftover bits, or non-zero padding bits,
refuse), and **mixed case refuses** both ways (a bech32 string is all-lower or
all-upper, never both; NostrXT emits lowercase and refuses an uppercase HRP at
encode time - uppercase the finished string if a QR code wants it).

## nsec handling rules

An `nsec` is a secret key wearing a friendlier coat, and the coat makes it EASIER
to leak: it is recognizable, double-clickable, and looks like every other entity.
The rules, enforced in code where code can enforce them:

- **`nxUriEncode` REFUSES to wrap an nsec.** A `nostr:` URI is a sharing format;
  putting a secret key in one is how secret keys end up in chat logs, browser
  histories and link previews. The refusal is a hard error, not a warning.
- Never log an nsec, never echo one into an error message, never put one in a
  field the UI might screenshot. `nxLastError()` messages in this member name the
  PROBLEM ("the secret key must be 64 hex characters"), never the key material.
- Decoding an nsec (`nxNsecDecode`) is legitimate exactly once per import flow:
  user pastes their key, the app decodes it to hex, and the nsec string is
  discarded. The honest limit is documented in this member's CLAUDE.md: OXT script
  variables are not locked memory, so hygiene here limits exposure rather than
  eliminating it.

## The nostr: URI scheme (NIP-21)

`nostr:<entity>` is the deep-link form for SHAREABLE entities: `nostr:npub1...`,
`nostr:nevent1...`, and so on.

- `nxUriEncode` validates the entity by decoding it first, refuses `nsec` (above),
  and prefixes `nostr:`.
- `nxUriDecode` requires the `nostr:` prefix and returns the decoded entity
  fields; `nxEntityDecode` also strips a `nostr:` prefix when handed one, so a
  pasted URI works anywhere a bare entity does.
