# holde-em

**Serverless online no-limit Texas Hold'em for OpenXTalk (OXT) and the xTalk family**
(also LiveCode 9.6.3+). No accounts, no server: players meet over the BitTorrent DHT,
every action lives in a signed, hash-chained transcript, and the deal runs on a
security ladder that tops out at a **ristretto255 mental-poker shuffle** — nobody, not
even the table host, can see a card they are not entitled to, and every completed hand
is verifiable after the fact.

Built by composing the OXT extension family:

| Extension | Provides |
|---|---|
| [TorrentXT](https://github.com/SethMorrowSoftware/TorrentXT) | rp1 peer messaging, DHT rendezvous (the table code IS the invite), BEP44 signed standings |
| [SodiumXT](https://github.com/SethMorrowSoftware/SodiumXT) | identities, sealed lanes, commitments, randomness — and (planned) the ristretto255 surface the mental-poker deal needs |
| [OnionXT](https://github.com/SethMorrowSoftware/OnionXT) | optional: anonymous tables over Tor, and onion-hosted deck oracles |
| [Box2Dxt](https://github.com/SethMorrowSoftware/Box2Dxt) | the Kit: spritesheet card animation and physics chips |

## Status

**Pre-implementation.** This repo currently contains the design documents; code lands
per the phased plan.

- **[holdem-spec.md](holdem-spec.md)** — the design contract: threat model, the
  three-level deal protocol ladder, the transcript, settlement receipts, and the honest
  non-goals (read section 13 before ever thinking about real stakes).
- **[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)** — the build order, Phase 0
  (bootstrap) through Phase 5 (hardening), with exit criteria per phase.
- **[CLAUDE.md](CLAUDE.md)** — the engineering playbook: everything about OXT /
  LiveCodeScript / LCB, the required extensions and their APIs, and every carried
  lesson from the sibling repos.

## Development

There is no headless way to compile or run a `.livecodescript`; the automated safety
net is the static gate — run it after every script edit:

```sh
python3 tools/check-livecodescript.py
```

Everything else (anything visual, timed, or extension-touching) is "verified
statically; needs an OXT pass" until a human confirms it in the IDE. See CLAUDE.md for
the full workflow.

---

*Seeded from the [Box2Dxt](https://github.com/SethMorrowSoftware/Box2Dxt) repository
(`docs/holde-em/`), where the spec was first developed.*
