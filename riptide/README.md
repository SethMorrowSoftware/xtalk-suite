# Riptide Social

The suite's capstone app, being built: a serverless social application
composed entirely from the installed OpenXTalk suite extensions, per the
design in `../docs/RIPTIDE-SOCIAL-SPEC.md`. No server, no account, no
hosting bill: your identity is an ed25519 key you hold, following someone
is knowing their key, and reaching them is verifying them.

## Status: phase 1 (of 7), offline-verifiable core

> **Honesty convention.** Everything in this directory is verified
> statically and against the pure-Python oracle; NONE of it has run on a
> real OXT engine yet. Needs an OXT pass. Networked behaviour (DHT puts,
> rp1 DMs, onion streams) is not written yet, so no networked claim is
> being made at all.

What ships today, per the spec's phased roadmap (section 10.3, phase 1,
plus the pure-compute half of phase 2):

- **`src/riptide.livecodescript`**, a pure-script library:
  - the master seed and the `RIPTKEY1` sealed key file (Argon2id +
    secretbox, the family's `BTXPREF1` convention with riptide's magic)
  - the KDF subkey tree: one 32-byte master derives the identity, DM,
    LAN, and anonymous-persona subkeys (`sxKdfDerive`, context
    `"riptide\0"`)
  - identity to handle (64-hex ed25519 public key) to `.onion` address,
    both directions
  - the rendezvous derivations: `inboxId` and `roomId`
  - the `RSH1` feed-head and `RSP1` post-record wire formats: build,
    strict parse, and author-signature verification, with the
    tamper-evident post chain
- **`tests/riptide-selftest.livecodescript`**, the offline harness: call
  `rsSelfTest()` on an engine with the extensions installed.
- **`tests/riptide_golden_test.py`** and **`tools/riptide_reference.py`**:
  the pure-Python oracle and the golden test that pins every vector.
  The oracle anchors to vectors from OUTSIDE this directory: the sodiumxt
  C KATs, torrentxt's cross-project BEP44 conformance vector, and a real
  published v3 onion address.
- **`tools/check-selftest-vectors.py`**: re-derives every golden constant
  in the harness from the oracle, with an honest coverage count.

Run the offline gates from this directory:

```sh
python3 tools/check-livecodescript.py       # the static script gate
python3 tests/riptide_golden_test.py        # the byte-for-byte goldens
python3 tools/check-selftest-vectors.py     # harness constants vs oracle
```

All three also run in `tools/build-all.sh --gates` at the repository root.

## Extension dependencies

Riptide probes, never assumes (`rsProbeCapabilities()`); a missing
extension disables exactly its feature, with a clear message, and never
another one.

| Extension | Need | Phase-1 role |
|---|---|---|
| SodiumXT | required | the trust root: KDF, sealing, signing, hashing |
| coinxt | optional | `cxSha3_256` powers the OFFLINE `.onion` self-computation |
| onionxt | optional | `oxPublicKeyFromAddress` verifies a claimed onion offline |
| torrentxt, enetxt, datachannelxt | later phases | probed and reported only |

A note on the onion address, because it is the one place the composition
is subtle: sodiumxt has no SHA-3, so onionxt's own `oxAddressFromPublicKey`
is a registered known-missing gap (`onionxt/docs/08`, gap 2) and returns a
capability error today. Riptide closes the gap by composition instead:
coinxt ships `cxSha3_256`, so `rsOnionFromPublicKey` computes your own
`.onion` offline when coinxt is installed, and degrades to a clear error
when it is not (the address is still available from `oxServiceAddress`
after publishing, via tor itself). The security-relevant VERIFY direction,
`rsVerifyOnionClaim`, needs no SHA-3 at all and works with onionxt alone.

## What phase 2+ adds (not yet written)

Transport wiring, in spec order: the signed feed head on the DHT
(`btDhtBep44SignBuf` + `sxSignDetached` + `btDhtPutSigned`, so the
identity key never enters libtorrent), post publishing and chain walking
against a live DHT, media torrents, then DMs over rp1 + secretstream.
Each phase lands with its own engine pass before its labels flip.
