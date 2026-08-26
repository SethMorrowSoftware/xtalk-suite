# SodiumXT security model

SodiumXT is a thin binding to [libsodium](https://libsodium.org), an audited, widely used
cryptography library. SodiumXT adds no cryptography of its own: it marshals your data to
libsodium and back, and shapes the API so the easy way is the safe way. This page describes
what that gets you and the few rules you must follow to keep it.

## What you get

- **Authenticated encryption everywhere.** Every cipher carries an authentication tag, so a
  wrong key, a corrupted byte, or deliberate tampering is *detected and rejected* (the call
  throws) rather than decrypting to garbage. This is the main upgrade over the stock
  `encrypt ... using "aes-256-cbc"` path, which is unauthenticated.
- **Strong, memory-hard password hashing.** Passphrases are run through Argon2id, which is
  expensive to brute-force, not a fast hash.
- **Misuse-resistant nonces.** For everything that seals bytes, you never supply a nonce.
  One-shot ciphers generate a fresh random nonce and prepend it; the streaming cipher derives
  per-chunk nonces from a random header. Nonce reuse - the classic catastrophic mistake - is
  designed out of the sealing API. The single caller-supplied-nonce entry point on the whole
  surface is `sxChaCha20IetfXor`, a building block for published constructions that derive
  their nonces internally; its argued exception is below.
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
| Hashing (`sxHash`, `sxHashFile`) | BLAKE2b |
| Key derivation / exchange | BLAKE2b KDF / X25519 (crypto_kx) |
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
memory against swapping, or guarantee it is zeroed when you are done - the engine may copy or
retain it. Secure-memory guarantees stop at the boundary between libsodium and the script. In
practice this means: minimize how long keys live in script variables, do not write them to disk
or logs, and rely on the operating system's protections. For the highest-value secrets, keep
the sensitive operation (for example whole-file encryption) on the C side via `sxEncryptFile` /
`sxDecryptFile`, where the key is used and dropped without round-tripping through script any
more than necessary.

## What SodiumXT deliberately does not expose

To keep misuse hard, some libsodium features are intentionally omitted:

- **Raw, unauthenticated stream ciphers** (plain XSalsa20 / XChaCha20 / AES-CTR) - with ONE
  argued exception, `sxChaCha20IetfXor`, below. Everything that SEALS bytes here
  authenticates.
- **Bring-your-own-nonce variants of the sealing API.** Nonces are managed for you.
- **Raw scalar multiplication / unhashed Diffie-Hellman**, and other low-level primitives that
  are easy to hold wrong.

If you have a concrete need for one of these, that is a discussion for an issue, not something
to work around with hand-rolled crypto next to SodiumXT.

## The one argued exception: `sxChaCha20IetfXor` (ABI 10, 2026-08-23)

This member's own rules say never a raw unauthenticated stream cipher and never a
bring-your-own-nonce entry point without a very loud reason. `sxChaCha20IetfXor` (RFC 8439
ChaCha20: 32-byte key, 12-byte nonce, initial counter 0, length-preserving, its own inverse)
is BOTH, and it shipped anyway. This section is the loud reason, argued rather than waved
through, because the request that owed it
(`nostrxt/docs/07-capabilities-required.md`) named exactly what had to be established:

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
requester's capability ledger, shipped as a thin wrap of audited code. The evidence
standard is the house one: C KATs under ASan/UBSan cross-checked against an independent
RFC 8439 implementation (three implementations agree on the pinned vectors), verified
statically on the script side and then **OBSERVED ON AN ENGINE 2026-08-24** (Windows
x86_64, OXT 9.6.3, reporting ABI 10): the 7-check raw-ChaCha20 section ran green inside
the full 106-check `sxSelfTest()`, folded into the suite paste. This sentence said "still
needs an OXT pass" until 2026-08-26, which by then denied a dated run.

## Provenance and reporting

SodiumXT statically links a pinned release of libsodium, so the cryptography you run is the
upstream audited code, unmodified. On the Linux and macOS builds that release is fetched by exact
version and verified against a pinned SHA256 before it is compiled - and since the 2026-08-23
mingw cross-builds the COMMITTED Windows DLLs are built the same way, from the same pinned
tarball (the release workflow's own Windows lanes instead link the libsodium vcpkg provides,
held to the same 1.0.x line rather than the SHA256 pin; a dispatch of that workflow supersedes
the mingw pair, as `CLAUDE.md`'s platform table records). Every platform must pass the same
known-answer tests (BLAKE2b, Argon2id, ed25519,
KDF) before its binary ships, which is the functional guard against any drift. The committed native
binaries under `src/code/` carry a `MANIFEST.sha256` that the suite CI verifies on every push,
and the root `native sodiumxt` workflow rebuilds and tests all five platforms from the pinned
source. For the strongest assurance you can build from source yourself (see
`docs/building.md`).

If you believe you have found a security issue in SodiumXT's binding layer, report it privately to
the maintainer rather than opening a public issue. Vulnerabilities in libsodium itself should go to
the [libsodium project](https://github.com/jedisct1/libsodium).
