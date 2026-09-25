# SodiumXT security model

SodiumXT is a thin binding to [libsodium](https://libsodium.org), an audited, widely used
cryptography library. SodiumXT adds no cryptography of its own: it marshals your data to
libsodium and back, and shapes the API so the easy way is the safe way. This page describes
what that gets you and the few rules you must follow to keep it.

## What you get

- **Authenticated encryption everywhere a cipher seals.** Every sealing cipher carries an
  authentication tag, so a wrong key, a corrupted byte, or deliberate tampering is
  *detected and rejected* (the call throws) rather than decrypting to garbage: the main
  upgrade over the stock `encrypt ... using "aes-256-cbc"` path, which is unauthenticated.
- **Strong, memory-hard password hashing.** Passphrases are run through Argon2id, which is
  expensive to brute-force, not a fast hash.
- **Misuse-resistant nonces.** For everything that seals bytes, you never supply a nonce:
  one-shot ciphers generate a fresh random nonce and prepend it, and the streaming cipher
  derives per-chunk nonces from a random header, so nonce reuse is designed out. The single
  caller-supplied-nonce entry point is `sxChaCha20IetfXor`, argued below.
- **A real CSPRNG.** `sxRandomBytes` and `sxRandomUniform` come from the operating system
  cryptographic random source.

## The primitives

| Purpose | Primitive |
|---|---|
| Secret-key encryption (`sxSecretBox`) | XSalsa20-Poly1305 |
| AEAD (`sxAeadEncrypt`) | XChaCha20-Poly1305-IETF |
| Streaming / file encryption | XChaCha20-Poly1305 (secretstream) |
| Password hashing / key derivation (`sxPwHash`) | Argon2id |
| Public-key encryption (`sxBox`, `sxSeal`) | X25519 + XSalsa20-Poly1305 |
| Signatures (`sxSign*`) | ed25519 |
| Expanded ed25519 key for Tor v3 onion services (`sxSignSeedToExpandedKey`) | SHA-512(seed), clamped |
| Hashing (`sxHash`, `sxHashFile`) | BLAKE2b |
| Keyed MAC (`sxHmacSha256`) | HMAC-SHA256 |
| SHA-3 (`sxSha3_256`, for the v3 `.onion` checksum) | SHA3-256, vendored trezor-crypto / RHash (libsodium has no SHA-3) |
| Key derivation / exchange | BLAKE2b KDF / X25519 (crypto_kx) |
| Prime-order group arithmetic (`sxRistretto*`, ABI 8/9) | ristretto255 (RFC 9496) |
| Raw stream xor for MAC-carrying constructions (`sxChaCha20IetfXor`) | ChaCha20-IETF (RFC 8439), unauthenticated by design - see the exception below |

## Rules you must follow

These are the things SodiumXT cannot enforce for you. Following them keeps the guarantees
above intact.

1. **Compare secrets with `sxMemEqual`, never `is` or `=`.** Comparing a MAC, tag, hash, or
   token with the ordinary operators leaks timing information. `sxMemEqual` is constant time.
   (The verify handlers - `sxPwHashStrVerify`, `sxSignVerifyDetached` - already compare safely
   internally.)
2. **Use the CSPRNG for anything unguessable.** Salts, keys, nonces (where you handle them),
   tokens, and session identifiers come from `sxRandomBytes` / `sxRandomUniform`. Never use the
   engine `random()`.
3. **Store the salt, and choose a cost.** A passphrase-derived key needs its salt to be
   re-derived, so store the salt next to the ciphertext (it is not secret). Pick a cost preset
   for the threat: `sxPwMemInteractive()` + `"2"` for logins, `sxPwMemModerate()` + `"3"`, or
   `sxPwMemSensitive()` + `"4"` for high-value data. Record the ops/mem you used so you can
   raise it later without breaking old data.
4. **Pin passphrase encoding to UTF-8.** Always `textEncode(thePassphrase, "utf-8")` before
   hashing, so the same passphrase derives the same key on every machine and locale.
5. **Protect your keys.** SodiumXT cannot manage key lifetime for you (see the limitation
   below). Keep secret keys out of logs, stacks you ship, and version control; derive them when
   needed and discard your references promptly.
6. **Treat a thrown error as a real failure.** If `sxSecretBoxOpen`, `sxBoxOpen`, `sxSignOpen`,
   or `sxDecryptFile` throws, the data was wrong, tampered with, or corrupt. Do not fall back to
   using it - report the failure.

## An honest limitation: key material in memory

libsodium can lock and wipe its own secret buffers, but once a key crosses into a LiveCode
`Data` value it lives in the engine's managed memory. SodiumXT **cannot** reliably lock that
memory against swapping, or guarantee it is zeroed - the engine may copy or retain it.
Secure-memory guarantees stop at the boundary between libsodium and the script. So:
minimize how long keys live in script variables, keep them off disk and out of logs, and
for the highest-value secrets keep the whole operation C-side (`sxEncryptFile` /
`sxDecryptFile`), where the key is used and dropped without round-tripping through script.

## What SodiumXT deliberately does not expose

To keep misuse hard, some libsodium features are intentionally omitted:

- **Raw, unauthenticated stream ciphers** (plain XSalsa20 / XChaCha20 / AES-CTR) - with ONE
  argued exception, `sxChaCha20IetfXor`, below. Everything that SEALS bytes here
  authenticates.
- **Bring-your-own-nonce variants of the sealing API.** Nonces are managed for you.
- **Raw X25519 scalar multiplication / unhashed Diffie-Hellman** (`crypto_scalarmult`),
  and other low-level primitives that are easy to hold wrong. (The ristretto255 group
  arithmetic of ABI 8/9 IS exposed, as thin wraps for holde-em's mental-poker and DLEQ
  constructions.)

If you have a concrete need for one of these, that is a discussion for an issue, not something
to work around with hand-rolled crypto next to SodiumXT.

## The one argued exception: `sxChaCha20IetfXor` (ABI 10, 2026-08-23)

This member's own rules say never a raw unauthenticated stream cipher and never a
bring-your-own-nonce entry point without a very loud reason. `sxChaCha20IetfXor` (RFC 8439
ChaCha20: 32-byte key, 12-byte nonce, initial counter 0, length-preserving, its own inverse)
is BOTH, and it shipped anyway. This is the loud reason, point by point as the request that
owed it (NostrXT's `nostrxt/docs/07-capabilities-required.md`) asked:

1. **The nonce discipline lives in the construction, not the caller.** In the named
   consumer - the NIP-44 v2 encrypted-payload construction - the 12-byte ChaCha20 nonce is
   never chosen by an app: it is an HKDF-expand slice over a fresh random 32-byte
   per-message nonce drawn inside the construction. Nonce reuse would require an HKDF
   collision, not a caller mistake.
2. **Authentication is provided one layer up, per a published specification.** NIP-44 does
   not use Poly1305: its authentication is HMAC-SHA256 over nonce||ciphertext, keyed by a
   third HKDF slice and verified BEFORE the cipher runs on decrypt. That is the construction
   the official vector set pins byte for byte. An AEAD here would emit payloads no other
   Nostr client can read - sixteen tag bytes in the wrong place and a MAC the spec does not
   define. The property the never-a-raw-stream rule exists to guarantee is held; it is held
   by HMAC rather than Poly1305.
3. **The alternative is worse by the family's stronger rule.** Without this export the only
   path to NIP-44 conformance is a hand-rolled ChaCha20 in script, which the suite forbids
   outright (no member adds cryptography). A thin wrap of libsodium's audited
   `crypto_stream_chacha20_ietf_xor` is the rules being obeyed at the family level, not
   waived.
4. **Containment.** The handler is documented everywhere it appears as a BUILDING BLOCK for
   composed, spec-pinned constructions that carry their own MAC - never as a sealing API.
   To encrypt bytes, use `sxSecretBox` / `sxAeadEncrypt` / the secretstream family, which
   authenticate and mint nonces. If you find yourself calling `sxChaCha20IetfXor` outside a
   published construction with its own verified MAC and its own internal nonce derivation,
   you are holding it wrong, and the right tool is one line up this paragraph.

The precedent is `sxSha3_256` (ABI 7): a sibling-requested primitive, argued in the
requester's capability ledger, shipped as a thin wrap of audited code. The evidence is
the house standard: C KATs under ASan/UBSan cross-checked against an independent RFC 8439
implementation (three implementations agree on the pinned vectors), then **observed on
an engine 2026-08-24** (Windows x86_64, OXT 9.6.3, ABI 10): the 7-check raw-ChaCha20
section green inside the 106-check `sxSelfTest()`, folded into the suite paste, and green
again there 2026-09-24 (Windows) and 2026-09-25 (Linux x86_64).

## Provenance and reporting

SodiumXT statically links upstream libsodium, unmodified, so the cryptography you run is
the audited code. The Linux and macOS builds fetch libsodium 1.0.20 by exact version and
verify it against a pinned SHA256 before compiling. The committed Windows DLLs are MSVC
builds linking the libsodium vcpkg provides (1.0.22 in the DLLs committed 2026-08-27 and
2026-09-12): held to the 1.0.x line rather than to the SHA256 pin. That was accepted by
decision D-08 (2026-08-27), because every platform must pass the same known-answer tests
(BLAKE2b, Argon2id, ed25519, KDF) before its binary ships, and the release lane drives
them on a real Windows runner before any DLL is bundled. The committed binaries under
`src/code/` carry a `MANIFEST.sha256` that the gates verify on every push. For the
strongest assurance, build from source yourself (see `docs/building.md`).

If you believe you have found a security issue in SodiumXT's binding layer, report it privately to
the maintainer rather than opening a public issue. Vulnerabilities in libsodium itself should go to
the [libsodium project](https://github.com/jedisct1/libsodium).
