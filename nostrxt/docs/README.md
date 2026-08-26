# NostrXT documentation

NostrXT is the Nostr protocol in pure LiveCodeScript: a portable cryptographic
identity, signed events, and a websocket relay client. Its crypto is composed
from CoinXT (BIP-340, sha256, ECDH) and SodiumXT (randomness, ChaCha20), never
reimplemented.

These docs are a NUMBERED SERIES, readable in order: 00-01 orient you, 02-05 are
the per-NIP and relay specs, 06 is the API, and 09 is the from-zero guide.
**If you just want to use it, jump to [09-usage-guide.md](09-usage-guide.md).**

**Read the STATUS block at the top of each page.** The `nx*` core is
engine-proven since 2026-08-24; the relay layer is deliberately SPLIT, with the
receive leg, NIP-42 auth and every ws:// path still carrying "verified
statically; needs a live-relay pass".

| Document | What it is |
|---|---|
| [00-overview.md](00-overview.md) | Overview and architecture, plus the member's honesty status in one place. |
| [01-protocol-model.md](01-protocol-model.md) | The protocol and trust model: a keypair IS an identity, a signed event is the only object, and relays are dumb and untrusted. |
| [02-nip01-events.md](02-nip01-events.md) | NIP-01 events byte for byte. The one wire format where close enough produces a wrong answer that looks right, so this member owns its canonical serializer. |
| [03-nip19-entities.md](03-nip19-entities.md) | NIP-19 bech32 entities, including the one deliberate BIP-173 deviation and the NIP's own waiver for it. |
| [04-nip44-payloads.md](04-nip44-payloads.md) | The NIP-44 v2 encrypted payload construction, complete since 2026-08-23 over SodiumXT ABI 10, and fail-closed on an older install. |
| [05-relay-client.md](05-relay-client.md) | The `nxr*` websocket relay client, and the socket-handler split that lets an app co-embed this member with another socket library. |
| [06-api-reference.md](06-api-reference.md) | The public surface of both source files, handler by handler. `tools/check-doc-handlers.py` holds this page and the shipped handler set in agreement, both directions. |
| [07-capabilities-required.md](07-capabilities-required.md) | What this member needs from upstream, and what the engine still owes it - including the half-measured TLS question. |
| [08-open-questions.md](08-open-questions.md) | The numbered to-do list, with the ones the 2026-08-24 engine pass closed struck in place. |
| [09-usage-guide.md](09-usage-guide.md) | From zero to a signed event on a relay: task-oriented recipes in the order an app grows. The page most readers want. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
