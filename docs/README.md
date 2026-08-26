# Suite documentation

Cross-cutting documents that span more than one member live here. Documents
about a single extension live in that member's own `<member>/docs/`, and each
member now carries its own `docs/README.md` index.

## Which file do I want?

| If you are about to... | Read |
|---|---|
| sit down at an engine | [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md), then [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) |
| find out what an extension does | [EXTENSIONS-OVERVIEW.md](EXTENSIONS-OVERVIEW.md), then that member's `docs/README.md` |
| pick up open work | [REMAINING-WORK.md](REMAINING-WORK.md) |
| make a call only the owner can make | [OPEN-DECISIONS.md](OPEN-DECISIONS.md) |
| wrap a new native library for OXT | [NEXT-EXTENSIONS-PLAN.md](NEXT-EXTENSIONS-PLAN.md) Part I |
| work on the anonymous transport | [anon-transport.md](anon-transport.md), then [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) |

## The three KINDS, and why the column exists

This folder had grown to fifteen documents of which several are point-in-time
audits, and nothing on the page said which was which. A reader met a 43KB file
whose contents had largely been built weeks ago with the same weight as the
runbook. **Every row below is now typed**, and the type is the first thing to
read:

- **LIVE** — maintained, and the authority on its subject. If it disagrees with
  the tree, that is a bug in the document and it should be fixed.
- **RECORD** — a design document or plan that is still the authority for *why*
  something is shaped the way it is, and that carries dated "As built" notes.
  Current for design, historical for status.
- **SNAPSHOT** — a dated point-in-time audit. Correct on its compile date and
  **decaying from that day on**. Strike items as they close and re-audit rather
  than trusting it. A snapshot is never evidence that something is still open.

| Document | Kind | Scope | What it is |
|---|---|---|---|
| [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md) | LIVE | whole suite | The operational runbook for an engine session: what is unproven and why, the install order and the exact Tor `torrc`, the run order shortest-feedback-first, what to record and which honesty labels each result flips, the known traps. Read before sitting down at an engine. Its opening "sparse-access session plan" is dated 2026-08-15; the numbered sections below it are the live part. |
| [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) | LIVE | whole suite | What the ENGINE actually does: every OXT behaviour that cost this project something, with the symptom verbatim, what it broke, and the gate (if any) that now holds it. Each entry marked OBSERVED / INFERRED / DOCUMENTED / UNEVIDENCED, because the class is the point. Read before an engine session and add to it after one. |
| [EXTENSIONS-OVERVIEW.md](EXTENSIONS-OVERVIEW.md) | LIVE | whole suite | The per-member catalogue: one section per extension and per app — what it wraps, what it enables, committed platforms, honest status. Covers all eight extensions and all three apps. Each member's own docs remain the authority. |
| [REMAINING-WORK.md](REMAINING-WORK.md) | LIVE | whole suite | The consolidated punch list: every open phase, deferred item, pending verification pass, release gap and owner decision, each item source-cited. Compiled 2026-08-15 and maintained since by striking items in place — check an item against the tree before spending an engine minute on it. |
| [OPEN-DECISIONS.md](OPEN-DECISIONS.md) | LIVE | whole suite | The owner decision briefs: every open owner call as a five-minute brief (stable ID, the question, why it is the owner's, evidence, options with real costs, what is blocked, an advisory recommendation), most-blocking first. An index of briefs, not the ledger: a decision taken is recorded at its primary source. Citations are migrating from `file:line` to a file plus a quoted ANCHOR PHRASE; `python3 tools/check-doc-anchors.py` re-resolves the anchored ones and reports how many bare citations it deliberately did not check. **That migration is early — as of 2026-08-26 the gate re-resolves 14 anchors against 647 bare citations it deliberately does not check — so treat an un-anchored `file:line` as a hint, not a fact. Run the gate for the current split rather than trusting this sentence.** |
| [NEXT-EXTENSIONS-PLAN.md](NEXT-EXTENSIONS-PLAN.md) | RECORD | whole suite | Two documents in one, and worth knowing which half you are in. **Part I is LIVE**: the reusable OXT/LiveCode engine playbook for wrapping a native library — the three rules, the `.livecodescript` and `.lcb` gotchas, the FFI marshalling contract, handles and the record codec, lifecycle and threading, the toolchain traps. **Parts II-V are executed history**: the per-library plans that produced sodiumxt, enetxt and datachannelxt. |
| [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) | RECORD | torrentxt + onionxt + sodiumxt | Model C, the optional Tor onion transport for QuickShare and DHT-Channels: file bytes travel peer-to-peer over an onion circuit, hiding both IPs, while BitTorrent/DHT stay the public default. Still the design authority; its phase sections carry dated "As built" blockquotes, and the remaining gates are live pending items waiting on a two-machine live-Tor pass. |
| [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md) | RECORD | five extensions | The capstone concept: a serverless social app composed from sodiumxt + torrentxt + onionxt + enetxt + datachannelxt — one Argon2id-sealed identity seed, a signed BEP44 feed with co-seeded torrent media, rp1 + secretstream DMs, WebRTC live sessions, enet LAN device sync, and an onion-only anonymous persona. Built at [`riptide/`](../riptide/); phases 1-4 two-machine-proven. |
| [holde-em spec](../holde-em/holdem-spec.md) | RECORD | torrentxt + sodiumxt + box2dxt | The second capstone: serverless online no-limit Texas Hold'em — players meet over the BitTorrent DHT, every action lives in a signed hash-chained transcript, and the deal tops out at a ristretto255 mental-poker shuffle. Built through Phase 2 at [`holde-em/`](../holde-em/); the spec and plan live in the member. |
| [anon-transport.md](anon-transport.md) | LIVE | torrentxt + onionxt + sodiumxt | Model C for the suite user: what the anonymous path hides (both IPs, the payload, the name), what it does not (Tor use, timing/volume, the local daemon), and how the built QuickShare path works. Built and statically verified; the behavioural two-machine Tor run is pending (runbook item 5). |
| [anon-transport-threat-model.md](anon-transport-threat-model.md) | LIVE | torrentxt + onionxt + sodiumxt | The Model C threat model by adversary tier — wire observer, malicious peer, hostile relay, third-party DHT observers, GPA out of scope — with the plan's residual-risk caveats carried and the section-14 wording decisions stated as open. |
| [anon-transport-onboarding.md](anon-transport-onboarding.md) | LIVE | torrentxt + onionxt + sodiumxt | Fresh user, two machines, zero to an anonymous transfer: the Tor daemon per platform, the extension prerequisites, the QuickShare walkthrough, and a fail-closed troubleshooting table. Verified statically; its Phase 4 exit — a fresh user completing it per OS — has not happened. |
| [SODIUM-TORRENT-CHANNELS-BRAINSTORM.md](SODIUM-TORRENT-CHANNELS-BRAINSTORM.md) | SNAPSHOT | sodiumxt + torrentxt | An ideas document, labelled brainstorm and not a spec: secure communication channels piggybacking on the BitTorrent network, secured with SodiumXT. Parts of it have since been built; OPEN-DECISIONS D-20 is the standing question of whether to promote anything further from it. |
| [HEADLESS-BACKLOG-2026-08-17.md](HEADLESS-BACKLOG-2026-08-17.md) | SNAPSHOT | whole suite | What was buildable with no engine, tor daemon, second machine, platform box or owner decision, compiled 2026-08-17 from an eight-domain survey (95 candidates, 41 items). Its own banners record what closed on the day and on 2026-08-23. **Much of the rest has closed since without being struck** — spot-checked 2026-08-26, its section D doc-truth items D3-D15 are mostly done. Take open work from REMAINING-WORK.md; read this one for the reasoning behind an item, not for its status. |

**Reading order for someone new to the suite:** the root [`README.md`](../README.md)
(what the eight extensions and three apps are, and how they compose) →
[EXTENSIONS-OVERVIEW.md](EXTENSIONS-OVERVIEW.md) (each member's capabilities at
a glance) → [NEXT-EXTENSIONS-PLAN.md](NEXT-EXTENSIONS-PLAN.md) Part I (how a
binding is built here) → [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md) (what
they build together). Then dive into any member's own `docs/README.md`.

> **Path caveat (swept 2026-08-15).** These documents were consolidated
> verbatim from the standalone repositories, and the tracked path-rewrite pass
> has now run over them: a present-tense cross-reference into a member spells
> the member prefix (`torrentxt/examples/…`, `coinxt/tools/…`). Dated records
> and quoted member accounts deliberately keep their original
> member-root-relative spellings; resolve those under the member their
> context names.
