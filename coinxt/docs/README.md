# CoinXT documentation

CoinXT gives an xTalk app Bitcoin and Ethereum primitives: hashes, the secp256k1
curve, encodings and addresses, HD wallets, transactions, and BIP-340 Schnorr
with the BIP-341 Taproot tweak. Start with
[getting-started.md](getting-started.md).

**This member keeps several documents at its ROOT rather than here**, and they
are listed below with the rest, because a reader looking for the spec should not
have to know that. Four gates read those paths by name
(`tools/check-doc-handlers.py`, `tools/package-extension.py`,
`.github/workflows/native-coinxt.yml`), which is why they have not been moved.

| Document | What it is |
|---|---|
| [getting-started.md](getting-started.md) | From zero: what CoinXT gives you and the first calls to make. Read this first. |
| [api-reference.md](api-reference.md) | The `cx*` handlers that exist today, and nothing else. All 94 public handlers are documented, and `tools/check-doc-handlers.py` fails the build if that stops being true in either direction. This file also ships inside the packaged extension. |
| [../SPEC.md](../SPEC.md) | The specification: what CoinXT is for, the phase boundaries, the naming rules, and the design decisions with their reasons. |
| [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) | The phased build plan. Phases 1 through 5 are closed and engine-passed; this is the record of the order and why. |
| [../MIGRATION.md](../MIGRATION.md) | What to change in an app when the ABI moves. |
| [../THIRD-PARTY-LICENSES.md](../THIRD-PARTY-LICENSES.md) | The per-file license map for the vendored trezor-crypto and libsecp256k1 code. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
