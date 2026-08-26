# Riptide Social documentation

Riptide Social is a capstone APP, not an extension: a serverless social client
composed from five suite members. **The specification lives at suite level**, in
[`../../docs/RIPTIDE-SOCIAL-SPEC.md`](../../docs/RIPTIDE-SOCIAL-SPEC.md), because
it describes how five members compose; this folder documents what was built.

| Document | What it is |
|---|---|
| [api-reference.md](api-reference.md) | The public `rs*` surface of `src/riptide.livecodescript`: phases 1-7 plus the 8.2/8.3 onion serving seams and the phase-6 sync layer. All 90 public handlers are documented. |
| [two-machine-runbook.md](two-machine-runbook.md) | How to drive `examples/riptide-social.livecodescript` on two OXT machines, phase by phase, and what each result proves. Written after the first passes, so it records what actually happens rather than what was expected. |
| [../../docs/RIPTIDE-SOCIAL-SPEC.md](../../docs/RIPTIDE-SOCIAL-SPEC.md) | The capstone specification: the identity seed, the signed BEP44 feed with co-seeded torrent media, the rp1 and secretstream DMs, WebRTC live sessions, enet LAN device sync, and the onion-only anonymous persona. |

**Where else to look.** [`../README.md`](../README.md) is the member front door
(install, a short example, the honest status). [`../CLAUDE.md`](../CLAUDE.md) is
maintainer memory: the as-built record, the gotchas, and why each decision went
the way it did. Suite-wide documents that span more than one member live in
[`../../docs/`](../../docs/README.md), indexed there by kind.
