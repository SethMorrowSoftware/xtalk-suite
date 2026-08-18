# Suite documentation

Cross-cutting documents that span more than one member live here. Documents
about a single extension live in that member's own `<member>/docs/`.

| Document | Scope | What it is |
|---|---|---|
| [EXTENSIONS-OVERVIEW.md](EXTENSIONS-OVERVIEW.md) | whole suite | The per-member catalogue: one section per extension (and per app) — what it wraps, what it enables as bullet capabilities with representative handlers, committed platforms, and its honest status — compiled 2026-08-15 from each member's own docs, which remain the authority. |
| [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md) | whole suite | The operational runbook for an engine session: what is still unproven and why it matters (with the file each claim lives in), the install order and the exact Tor `torrc`, the run order shortest-feedback-first, what to record and which honesty labels each result flips, the known traps, and what to capture on a failure. Read this before sitting down at an engine. |
| [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) | whole suite | What the ENGINE actually does: every OXT behaviour that cost this project something to learn, with the symptom verbatim, what it broke, and the gate (if any) that now holds it. Each entry is marked OBSERVED (seen on a dated engine run), INFERRED, or DOCUMENTED - and the class is the point, because an unexecuted line is not evidence in either direction. Read it before an engine session and add to it after one. Member-specific gotchas stay in that member's CLAUDE.md; this is for engine behaviour, which is the same everywhere. |
| [NEXT-EXTENSIONS-PLAN.md](NEXT-EXTENSIONS-PLAN.md) | whole suite | The roadmap: which native capability becomes which extension, in what order, and why. The document that produced enetxt, datachannelxt, onionxt, and coinxt. |
| [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) | torrentxt + onionxt + sodiumxt | Model C — optional Tor onion transport for the QuickShare and DHT-Channels demos: file bytes travel peer-to-peer over an onion circuit, hiding both IPs, while BitTorrent/DHT stay the public default. |
| [anon-transport.md](anon-transport.md) | torrentxt + onionxt + sodiumxt | Model C for the suite user: what the anonymous path hides (both IPs, the payload, the name), what it does not (Tor use, timing/volume, the local daemon), and how the built QuickShare path works - code in, onion stream out, passphrase and downgrade-refusal semantics. Built and statically verified; the behavioural two-machine Tor run is pending (runbook item 5). |
| [anon-transport-threat-model.md](anon-transport-threat-model.md) | torrentxt + onionxt + sodiumxt | The Model C threat model by adversary tier - wire observer, malicious peer, hostile relay (exit-irrelevance), third-party DHT observers, GPA out of scope - with the plan's residual-risk caveats carried verbatim-or-equivalent and the section-14 wording decisions (derivability claim, copy sign-off) stated as open. |
| [anon-transport-onboarding.md](anon-transport-onboarding.md) | torrentxt + onionxt + sodiumxt | Fresh user, two machines, zero to an anonymous transfer: the Tor daemon per platform (document-install; bundling is an open owner decision), the extension prerequisites, the QuickShare walkthrough, and a fail-closed troubleshooting table. The walkthrough itself is verified statically; its Phase 4 exit - a fresh user completing it per OS - has not happened. |
| [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md) | five extensions | The capstone concept: a serverless social app composed from the suite (sodiumxt + torrentxt + onionxt + enetxt + datachannelxt) — one Argon2id-sealed identity seed, a signed BEP44 feed with co-seeded torrent media, rp1 + secretstream DMs, WebRTC live sessions, enet LAN device sync, and an onion-only anonymous persona. Built at `riptide/`; phases 1-4 two-machine-proven. |
| [holde-em spec](../holde-em/holdem-spec.md) | torrentxt + sodiumxt + box2dxt | The second capstone: serverless online no-limit Texas Hold'em - players meet over the BitTorrent DHT, every action lives in a signed hash-chained transcript, and the deal tops out at a ristretto255 mental-poker shuffle. BUILT through Phase 2 (hotseat + online play) at [`holde-em/`](../holde-em/), folded home 2026-08-15; the spec + plan live in the member (the seed copy this folder once carried was removed in the fold). |
| [SODIUM-TORRENT-CHANNELS-BRAINSTORM.md](SODIUM-TORRENT-CHANNELS-BRAINSTORM.md) | sodiumxt + torrentxt | An ideas document (labelled brainstorm, not a spec): secure communication channels that piggyback on the BitTorrent network, secured with SodiumXT. Moved here from `sodiumxt/` because it spans two members. |
| [REMAINING-WORK.md](REMAINING-WORK.md) | whole suite | The consolidated punch list: every open phase, deferred item, pending verification pass, release gap, and owner decision across the tree, each item source-cited. A dated point-in-time audit (2026-08-15, revised for the holde-em fold) - strike items here as they close, and re-audit rather than trust it stale. |
| [OPEN-DECISIONS.md](OPEN-DECISIONS.md) | whole suite | The owner decision briefs: every recorded open owner call as a five-minute brief (stable ID, the question, why it is the owner's, evidence cited file:line, options with real costs, what is blocked, an advisory recommendation), ordered most-blocking first. An index of briefs, not the ledger: a decision taken gets recorded at its primary source. Compiled 2026-08-16, citations verified that day. |
| [HEADLESS-BACKLOG-2026-08-17.md](HEADLESS-BACKLOG-2026-08-17.md) | whole suite | What is still buildable with NO engine, tor daemon, second machine, platform box, or owner decision - compiled 2026-08-17, the day after the five box2dxt/holde-em engine runs, from an eight-domain survey (95 candidates, 41 items). Findings are marked [M] measured in-session or [S] survey-sourced and spot-checked. Its subject is the tree's rate of self-description: the highest-ranked items convert a description into a check. A dated point-in-time audit - strike items as they close, re-audit rather than trust it stale. |

**Reading order for someone new to the suite:** the root `README.md` (what the
seven are and how they compose) → `EXTENSIONS-OVERVIEW.md` (each member's
capabilities at a glance) → `NEXT-EXTENSIONS-PLAN.md` (why they exist) →
`RIPTIDE-SOCIAL-SPEC.md` (what they build together). Then dive into any
member's own `docs/`.

> **Path caveat (swept 2026-08-15).** These documents were consolidated
> verbatim from the standalone repositories, and the tracked path-rewrite pass
> has now run over them: a present-tense cross-reference into a member spells
> the member prefix (`torrentxt/examples/…`, `coinxt/tools/…`). Dated records
> and quoted member accounts deliberately keep their original
> member-root-relative spellings; resolve those under the member their
> context names.
