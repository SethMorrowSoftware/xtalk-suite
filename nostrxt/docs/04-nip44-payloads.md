# 04 - NIP-44 v2 Encrypted Payloads

> STATUS: verified statically; needs an OXT pass - and one step of the pipeline
> cannot run AT ALL yet: the raw ChaCha20 cipher exists nowhere in the suite, so
> `nxNip44Encrypt` / `nxNip44Decrypt` fail closed today (details below). Every
> OTHER step is vector-pinned headlessly: `tools/nostr-kat.py` sweeps the complete
> official NIP-44 v2 vector set (conversation keys valid and invalid, message keys,
> the padding pairs, encrypt/decrypt including the long-message sha256 rows, the
> invalid payloads, and the invalid plaintext lengths) through the independent
> oracle, and the member harness pins the derived constants.

NIP-44 v2 is the encrypted-payload format that supersedes NIP-04: a versioned,
padded, authenticated construction whose keys derive from a static ECDH between two
Nostr identities. This document walks it step by step AS SHIPPED in
`src/nostrxt.livecodescript`, names exactly which steps are proven today, and states
the format's own documented limits so nothing here overpromises.

## The construction, step by step

### 1. Conversation key: ECDH, then HKDF-extract

`nxNip44ConversationKey(seckeyHex, pubkeyHex)`:

- The peer's key is x-only (32 bytes), but CoinXT's `cxEcdh` wants a full
  compressed point, so the x-only key **lifts even-y**: prefix byte `0x02` onto it.
  This is the NIP-44 convention (every x-only key is treated as its even-y point)
  and it is what makes the key symmetric: conv(a, B) equals conv(b, A).
- `cxEcdh` returns the RAW 65-byte `0x04 || X || Y` point; the shared secret is the
  **x coordinate, UNHASHED** (bytes 2..33). This is the step where a borrowed ECDH
  goes wrong quietly: many libraries return sha256(compressed point) as the shared
  secret, which is a perfectly good key and NOT the NIP-44 one. The full valid AND
  invalid conversation-key vector sets pin this choice.
- Conversation key = HKDF-extract with salt `"nip44-v2"` over the shared x, which
  concretely is one `cxHmacSha256(salt bytes, shared x)`. 32 bytes, static per pair
  of identities - which is where the no-forward-secrecy limit below comes from.

### 2. Per-message nonce

32 fresh random bytes per message (`sxRandomBytes`). `nxNip44Encrypt`'s `pNonceHex`
parameter exists for KATs only: a 64-hex value makes the payload deterministic and
pinnable; empty draws fresh randomness. Never reuse a nonce in anger - the
parameter is a test seam, not an API invitation.

### 3. Message keys: HKDF-expand, L = 76, sliced three ways

`nxNip44MessageKeys(convKeyHex, nonceHex)` runs HKDF-expand with the conversation
key as PRK and the nonce as info, for exactly 76 bytes (three HMAC-SHA256 blocks,
counter bytes 1..3, each block feeding the next), then slices:

| Bytes | Key | Size |
|---|---|---|
| 1..32 | chacha key | 32 |
| 33..44 | chacha nonce | 12 |
| 45..76 | hmac key | 32 |

The official `get_message_keys` vectors pin all three slices; the harness pins row
0 by name (`kNxVecN44Mk*` constants).

### 4. Padding: u16-BE length prefix, power-of-two buckets

The plaintext's UTF-8 bytes are framed as `[len u16 big-endian][plaintext][zeros]`,
padded to `nxNip44PaddedLen(len)`: 32 for anything up to 32 bytes, otherwise the
next power of two, in chunks of 32 (up to 256) or an eighth of that power (above).
Padding hides the exact length while leaking the bucket; the 24 published
`calc_padded_len` pairs pin the arithmetic (`kNxVecN44PadIns` / `kNxVecN44PadOuts`).

**Plaintext must be 1..65535 bytes, and longer REFUSES, fail closed.** The reason
is a policy worth spelling out: the published vector set pins the u16 length prefix
only, and explicitly lists 0 and 65536 as INVALID plaintext lengths. The newer spec
text sketches an extended 6-byte prefix for larger payloads, but with no published
vectors there is nothing to pin an implementation against, and an unpinned
serialization is exactly how two implementations quietly disagree. So NostrXT
implements what the vectors prove and refuses the rest; if upstream vectors for the
extended form land, supporting it is a deliberate change with new KAT rows, never a
quiet edit. Unpadding is strict in the same spirit: the declared length, the slice,
and the recomputed padded length must all agree or the payload refuses.

### 5. ChaCha20, THROUGH THE SEAM (the one missing primitive)

The padded plaintext is XORed with a ChaCha20 keystream: RFC 8439 ChaCha20, the
12-byte nonce from step 3, counter 0, unauthenticated stream xor. **That cipher
exists nowhere in the suite today.** The family's split-the-change law says a
missing primitive is an upstream feature landed first, never a cipher hand-rolled
here (this member's rule 1), so the core calls the seam `sxChaCha20IetfXor` - the
requested SodiumXT primitive - inside a try, and until SodiumXT ships it:

- `nxNip44Encrypt` and `nxNip44Decrypt` fail closed, returning empty with
  `nxLastError()` reading exactly:

  ```
  nxNip44 needs SodiumXT sxChaCha20IetfXor (not yet shipped upstream; docs/07-capabilities-required.md)
  ```

- `nxNip44HasCipher()` is a LIVE probe of the seam (a 1-byte xor against the zero
  key), so an app can branch honestly, and an upgraded SodiumXT is noticed without
  restarting - unlike the cached `nxProbeCapabilities` row (`canNip44Cipher`),
  which reports the state at first probe.

The upstream request is tracked in `docs/07-capabilities-required.md`, and it will
need a written loud reason when proposed, because it deliberately crosses two of
SodiumXT's own safety rules: no raw unauthenticated stream ciphers (its rule 4) and
no bring-your-own-nonce entry points (its rule 3). The reason exists and is this
construction: NIP-44 fixes authenticate-then-decrypt at the format level (the MAC
below), and the nonce is not caller-chosen in any meaningful sense - it is an HKDF
output slice from a vector-pinned schedule. The tension is documented here rather
than discovered in review.

### 6. MAC: HMAC-SHA256 over nonce || ciphertext, verified BEFORE the cipher

The MAC is `cxHmacSha256(hmac key, nonce || ciphertext)` - the nonce is the MAC's
AAD, so a payload with a swapped nonce fails authentication rather than decrypting
to garbage. On decrypt, the MAC verifies **before the cipher runs**, compared
constant-time (`nxCtEqualHex`: SodiumXT's `sxMemEqual` when present, a
never-exits-early accumulate loop when not). Authenticate-then-decrypt is the
property that makes an unauthenticated stream cipher safe to compose, which is why
the harness proves the ORDER today, cipher or no cipher: `nxtTestNip44Seam` tampers
a byte inside the ciphertext region of the official payload vector and asserts the
refusal happens AT THE MAC, with a MAC error - and separately that the untampered
vector gets PAST the MAC and fails at the cipher seam with the capability error.

### 7. Payload: version byte, standard base64

The wire payload is `base64(0x02 || nonce(32) || ciphertext || mac(32))`, standard
alphabet with padding, single-line (`nxB64Encode` strips the engine encoder's line
wrapping; `nxB64Decode` refuses characters outside the alphabet before decoding, so
a malformed payload is an error, not a partial decode). Decrypt-side validation,
all fail closed, in order:

- A payload starting `#` refuses: NIP-44 reserves the flag for a future
  non-base64 format, and an implementation that cannot decrypt must say
  "unsupported version", not "bad base64".
- Shorter than **132 characters** refuses (the smallest legal payload: version +
  nonce + the smallest ciphertext (a 2-byte length prefix plus 32 padded bytes) +
  mac, base64-encoded).
- Decoded payload shorter than **99 bytes** refuses (1 + 32 + 34 + 32).
- A version byte other than `0x02` refuses.

## What is proven today, and what awaits the cipher

| Step | Status |
|---|---|
| Conversation key (ECDH lift, unhashed x, HKDF-extract) | vector-pinned today: the full official valid and invalid sets sweep in the KAT; the harness pins and recomputes the sec1/pub2 row via CoinXT |
| Message keys (HKDF-expand 76, three slices) | vector-pinned today, KAT sweep + harness row 0 |
| Padding and unpadding, the 1..65535 policy | vector-pinned today: all 24 pairs, plus the invalid lengths refusing |
| MAC-before-cipher order, constant-time compare | proven today by the harness's tamper test on the official payload |
| Version byte, size floors, `#` flag, base64 strictness | exercised today by the harness's refusal checks |
| The ChaCha20 keystream itself, end-to-end encrypt/decrypt through nx* | **fails closed today**; the oracle proves the construction against the full published encrypt/decrypt vectors (long-message rows included), so the day `sxChaCha20IetfXor` ships, the harness's seam section stops expecting the capability error and starts asserting that the official payload vector decrypts and re-encrypts byte-identically - that branch is already written |

And the standing labels: every "today" above means machine-verified headlessly;
the whole pipeline still needs an OXT pass, because none of it has run on an
engine.

## The limitations NIP-44 itself documents

Carried from the NIP's own security section, so no app built on this member
presents the format as more than it is (see also `01-protocol-model.md`):

- **No forward secrecy.** The conversation key is static per key pair; compromise
  either secret key and every past and future payload between that pair opens.
- **Metadata stays public.** The event around the payload exposes both pubkeys,
  `created_at`, and `kind` to every relay and observer. NIP-44 encrypts content
  bytes, full stop.
- **No deniability, no post-compromise security.** It is an encryption format, not
  a messaging protocol with a ratchet; protocols wanting those properties build
  them above this layer.
- **Nonce reuse is catastrophic**, as for any stream cipher; that is why the nonce
  parameter on `nxNip44Encrypt` is documented as KAT-only and production callers
  pass empty.

## NIP-04 is out of scope, and that is a decision, not a gap

NIP-04 (the older DM format) encrypts with AES-256-CBC. It is deliberately not
implemented, for three reasons that compound:

1. **No AES exists anywhere in the suite**, and libsodium - SodiumXT's substrate -
   will never provide CBC (its authors consider unauthenticated CBC a design error,
   and libsodium ships no CBC mode of anything). Implementing NIP-04 would mean
   hand-rolling a block cipher in exactly the place family law forbids it, for a
   format that is
2. **superseded**: NIP-44 exists BECAUSE of NIP-04's structural problems
   (unauthenticated CBC, no padding, metadata leaks), and the ecosystem's own
   direction is NIP-44. Which makes NIP-04 support
3. **a compatibility feature with a shrinking constituency and a real attack
   surface** - the wrong trade for a new member with no legacy users.

An app that must READ old NIP-04 DMs needs a different tool; this member will not
grow one. The decision is recorded here and in `docs/07-capabilities-required.md`
so it is re-arguable on its merits rather than rediscovered as an omission.
