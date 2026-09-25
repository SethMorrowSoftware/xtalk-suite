# 04 - NIP-44 v2 Encrypted Payloads

> STATUS: COMPLETE since 2026-08-23 (the raw ChaCha20 cipher shipped upstream as SodiumXT ABI
> 10's `sxChaCha20IetfXor`) and engine-proven 2026-08-24 with the rest of the `nx*` core
> (Windows x86_64, OXT 9.6.3), and again 2026-09-24 (Windows, the engine reports Win32). On an
> installed SodiumXT older than ABI 10, encrypt/decrypt fail closed by design (step 5).
> Relay-borne NIP-44 events (send one to a relay, read one back) keep "verified statically;
> needs a live-relay pass".

NIP-44 v2 is the encrypted-payload format that supersedes NIP-04: a versioned, padded,
authenticated construction whose keys derive from a static ECDH between two Nostr identities.
This document walks it step by step AS SHIPPED in `src/nostrxt.livecodescript`, says what
proves each step, and states the format's own documented limits so nothing here overpromises.

## The construction, step by step

### 1. Conversation key: ECDH, then HKDF-extract

`nxNip44ConversationKey(seckeyHex, pubkeyHex)`:

- The peer's key is x-only (32 bytes), but CoinXT's `cxEcdh` wants a full compressed point, so
  the x-only key **lifts even-y**: prefix byte `0x02`. This is the NIP-44 convention and it is
  what makes the key symmetric: conv(a, B) equals conv(b, A).
- `cxEcdh` returns the RAW 65-byte `0x04 || X || Y` point; the shared secret is the **x
  coordinate, UNHASHED** (bytes 2..33). This is where a borrowed ECDH goes wrong quietly: many
  libraries return sha256(compressed point), which is a perfectly good key and NOT the NIP-44
  one. The full valid AND invalid conversation-key vector sets pin this choice.
- Conversation key = HKDF-extract with salt `"nip44-v2"` over the shared x, which concretely is
  one `cxHmacSha256(salt bytes, shared x)`. 32 bytes, static per pair of identities - which is
  where the no-forward-secrecy limit below comes from.

### 2. Per-message nonce

32 fresh random bytes per message (`sxRandomBytes`). `nxNip44Encrypt`'s `pNonceHex` parameter
exists for KATs only: a 64-hex value makes the payload deterministic and pinnable; empty draws
fresh randomness. Never reuse a nonce in anger - the parameter is a test seam, not an API
invitation.

### 3. Message keys: HKDF-expand, L = 76, sliced three ways

`nxNip44MessageKeys(convKeyHex, nonceHex)` runs HKDF-expand with the conversation key as PRK and
the nonce as info, for exactly 76 bytes (three HMAC-SHA256 blocks, counter bytes 1..3, each block
feeding the next), then slices:

| Bytes | Key | Size |
|---|---|---|
| 1..32 | chacha key | 32 |
| 33..44 | chacha nonce | 12 |
| 45..76 | hmac key | 32 |

The official `get_message_keys` vectors pin all three slices; the harness pins row 0 by name
(`kNxVecN44Mk*` constants).

### 4. Padding: u16-BE length prefix, power-of-two buckets

The plaintext's UTF-8 bytes are framed as `[len u16 big-endian][plaintext][zeros]`, padded to
`nxNip44PaddedLen(len)`: 32 for anything up to 32 bytes, otherwise the next power of two, in
chunks of 32 (up to 256) or an eighth of that power (above). Padding hides the exact length
while leaking the bucket; the 24 published `calc_padded_len` pairs pin the arithmetic
(`kNxVecN44PadIns` / `kNxVecN44PadOuts`).

**Plaintext must be 1..65535 bytes, and longer REFUSES, fail closed.** The published vector set
pins the u16 length prefix only and lists 0 and 65536 as INVALID plaintext lengths. The newer
spec text sketches an extended 6-byte prefix for larger payloads, but with no published vectors
there is nothing to pin an implementation against, and an unpinned serialization is exactly how
two implementations quietly disagree. So NostrXT implements what the vectors prove and refuses
the rest; if upstream vectors for the extended form land, supporting it is a deliberate change
with new KAT rows, never a quiet edit. Unpadding is strict in the same spirit: the declared
length, the slice, and the recomputed padded length must all agree or the payload refuses.

### 5. ChaCha20, through the seam (the composed primitive)

The padded plaintext is XORed with a ChaCha20 keystream: RFC 8439 ChaCha20, the 12-byte nonce
from step 3, counter 0, unauthenticated stream xor, via SodiumXT's `sxChaCha20IetfXor` (ABI 10,
2026-08-23). The family law says a missing primitive is an upstream feature landed first, never
a cipher hand-rolled here (rule 1), and that is how it went (`07-capabilities-required.md`
gap #1). The core calls the seam inside a try, and on an installed SodiumXT older than ABI 10:

- `nxNip44Encrypt` and `nxNip44Decrypt` fail closed, returning empty with `nxLastError()`
  reading exactly:

  ```
  nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT ABI 10; the installed SodiumXT predates it - docs/07-capabilities-required.md)
  ```

- `nxNip44HasCipher()` is a LIVE probe of the seam (a 1-byte xor against the zero key), so an
  app can branch honestly and an upgraded SodiumXT is noticed without restarting - unlike the
  cached `nxProbeCapabilities` row (`canNip44Cipher`), which reports the state at first probe.

The primitive deliberately crossed two of SodiumXT's own safety rules: no bring-your-own-nonce
entry points (its rule 3) and no raw unauthenticated stream ciphers (its rule 4). The argued
reason is this construction - NIP-44 fixes authenticate-then-decrypt at the format level (step
6), and the ChaCha nonce is an HKDF output slice, not a caller's choice - and it landed with the
primitive, in `sodiumxt/docs/security.md` ("The one argued exception").

### 6. MAC: HMAC-SHA256 over nonce || ciphertext, verified BEFORE the cipher

The MAC is `cxHmacSha256(hmac key, nonce || ciphertext)` - the nonce is the MAC's AAD, so a
payload with a swapped nonce fails authentication rather than decrypting to garbage. On decrypt,
the MAC verifies **before the cipher runs**, compared constant-time (`nxCtEqualHex`: SodiumXT's
`sxMemEqual` when present, a never-exits-early accumulate loop when not). Authenticate-then-
decrypt is what makes an unauthenticated stream cipher safe to compose, which is why the harness
proves the ORDER on any install: `nxtTestNip44Seam` tampers a byte inside the ciphertext region
of the official payload vector and asserts the refusal happens AT THE MAC, with a MAC error, and
separately that the untampered vector gets PAST the MAC (then round-trips against a current
SodiumXT, or fails closed at the seam against an older one).

### 7. Payload: version byte, standard base64

The wire payload is `base64(0x02 || nonce(32) || ciphertext || mac(32))`, standard alphabet with
padding, single-line (`nxB64Encode` strips the engine encoder's line wrapping; `nxB64Decode`
refuses characters outside the alphabet before decoding, so a malformed payload is an error, not
a partial decode). Decrypt-side validation, all fail closed, in order:

- A payload starting `#` refuses: NIP-44 reserves the flag for a future non-base64 format, and
  an implementation that cannot decrypt must say "unsupported version", not "bad base64".
- Shorter than **132 characters** refuses (the smallest legal payload: version + nonce + the
  smallest ciphertext (a 2-byte length prefix plus 32 padded bytes) + mac, base64-encoded).
- Decoded payload shorter than **99 bytes** refuses (1 + 32 + 34 + 32).
- A version byte other than `0x02` refuses.

## What proves each step

Every step is swept headlessly by `tools/nostr-kat.py` against the complete official NIP-44 v2
vector set (conversation keys valid and invalid, message keys, the padding pairs,
encrypt/decrypt including the long-message sha256 rows, the invalid payloads and the invalid
plaintext lengths), and `tools/check-script-vectors.py` executes the shipped encrypt/decrypt
over the committed CoinXT and SodiumXT binaries. On an engine:

| Step | What the harness pins |
|---|---|
| Conversation key (ECDH lift, unhashed x, HKDF-extract) | the sec1/pub2 row, recomputed via CoinXT |
| Message keys (HKDF-expand 76, three slices) | row 0 |
| Padding and unpadding, the 1..65535 policy | all 24 pairs, plus the invalid lengths refusing |
| MAC-before-cipher order, constant-time compare | the tamper test on the official payload |
| Version byte, size floors, `#` flag, base64 strictness | the refusal checks |
| The ChaCha20 keystream, end-to-end encrypt/decrypt | the official vector decrypts and re-encrypts byte-identically against a current SodiumXT; the fail-closed error against an older one |

Every row ran green on 2026-08-24 (Windows x86_64, OXT 9.6.3) inside the suite paste, against a
SodiumXT whose own ABI 10 ChaCha20 section ran green the same day, and again on 2026-09-24
(Windows, the engine reports Win32), SodiumXT's ABI 10 ChaCha20 checks green in the same paste.
Both engines had ABI 10, so the last row ran its current-SodiumXT half; the other half, the
fail-closed error against an older SodiumXT, has run only headlessly: the family interpreter's
count of the whole harness in every CoinXT / SodiumXT configuration (2026-09-24, in the ledger
in `CLAUDE.md`).

## The limitations NIP-44 itself documents

Carried from the NIP's own security section, so no app built on this member presents the format
as more than it is (see also `00-overview.md`):

- **No forward secrecy.** The conversation key is static per key pair; compromise either secret
  key and every past and future payload between that pair opens.
- **Metadata stays public.** The event around the payload exposes both pubkeys, `created_at`,
  and `kind` to every relay and observer. NIP-44 encrypts content bytes, full stop.
- **No deniability, no post-compromise security.** It is an encryption format, not a messaging
  protocol with a ratchet; protocols wanting those properties build them above this layer.
- **Nonce reuse is catastrophic**, as for any stream cipher; that is why the nonce parameter on
  `nxNip44Encrypt` is KAT-only and production callers pass empty.

## NIP-04 is out of scope, and that is a decision, not a gap

NIP-04 (the older DM format) encrypts with AES-256-CBC. It is deliberately not implemented, for
three reasons that compound:

1. **No AES exists anywhere in the suite**, and libsodium - SodiumXT's substrate - will never
   provide CBC (it ships no CBC mode of anything). Implementing NIP-04 would mean hand-rolling a
   block cipher in exactly the place family law forbids it, for a format that is
2. **superseded**: NIP-44 exists BECAUSE of NIP-04's structural problems (unauthenticated CBC,
   no padding, metadata leaks), and the ecosystem's direction is NIP-44. Which makes NIP-04
3. **a compatibility feature with a shrinking constituency and a real attack surface** - the
   wrong trade for a new member with no legacy users.

An app that must READ old NIP-04 DMs needs a different tool; this member will not grow one. The
decision is also recorded in `07-capabilities-required.md` so it is re-arguable on its merits
rather than rediscovered as an omission.
