# Suite documentation

Cross-cutting documents that span more than one member live here. Documents
about a single extension live in that member's own `<member>/docs/`.

| Document | Scope | What it is |
|---|---|---|
| [EXTENSIONS-OVERVIEW.md](EXTENSIONS-OVERVIEW.md) | whole suite | The per-member catalogue: one section per extension (and per app) — what it wraps, what it enables as bullet capabilities with representative handlers, committed platforms, and its honest status — compiled 2026-08-15 from each member's own docs, which remain the authority. |
| [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md) | whole suite | The operational runbook for an engine session: what is still unproven and why it matters (with the file each claim lives in), the install order and the exact Tor `torrc`, the run order shortest-feedback-first, what to record and which honesty labels each result flips, the known traps, and what to capture on a failure. Read this before sitting down at an engine. |
| [NEXT-EXTENSIONS-PLAN.md](NEXT-EXTENSIONS-PLAN.md) | whole suite | The roadmap: which native capability becomes which extension, in what order, and why. The document that produced enetxt, datachannelxt, onionxt, and coinxt. |
| [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) | torrentxt + onionxt + sodiumxt | Model C — optional Tor onion transport for the QuickShare and DHT-Channels demos: file bytes travel peer-to-peer over an onion circuit, hiding both IPs, while BitTorrent/DHT stay the public default. |
| [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md) | five extensions | The capstone concept: a serverless social app composed from the suite (sodiumxt + torrentxt + onionxt + enetxt + datachannelxt) — one Argon2id-sealed identity seed, a signed BEP44 feed with co-seeded torrent media, rp1 + secretstream DMs, WebRTC live sessions, enet LAN device sync, and an onion-only anonymous persona. Built at `riptide/`; phases 1-4 two-machine-proven. |
| [holde-em/](holde-em/) | torrentxt + sodiumxt + box2dxt | The second capstone design (spec + implementation plan, pre-build): serverless online no-limit Texas Hold'em - players meet over the BitTorrent DHT, every action lives in a signed hash-chained transcript, and the deal tops out at a ristretto255 mental-poker shuffle. Moved up from `box2dxt/docs/` in the 2026-08-14 fold because it composes three members. |
| [SODIUM-TORRENT-CHANNELS-BRAINSTORM.md](SODIUM-TORRENT-CHANNELS-BRAINSTORM.md) | sodiumxt + torrentxt | An ideas document (labelled brainstorm, not a spec): secure communication channels that piggyback on the BitTorrent network, secured with SodiumXT. Moved here from `sodiumxt/` because it spans two members. |

**Reading order for someone new to the suite:** the root `README.md` (what the
seven are and how they compose) → `EXTENSIONS-OVERVIEW.md` (each member's
capabilities at a glance) → `NEXT-EXTENSIONS-PLAN.md` (why they exist) →
`RIPTIDE-SOCIAL-SPEC.md` (what they build together). Then dive into any
member's own `docs/`.

> **Path caveat.** These documents were consolidated verbatim from the
> standalone repositories. Where one cites a member-relative path (e.g.
> `examples/…`, `src/…`) or another project by name, resolve it under that
> member's directory (`torrentxt/examples/…`, `sodiumxt/src/…`). Rewriting the
> cross-references to suite-relative paths is a tracked cleanup, not a code bug.
