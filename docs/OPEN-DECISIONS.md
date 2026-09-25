# OPEN-DECISIONS.md - owner decisions: the log and the open brief

An **owner decision** is a call the tree cannot make for itself: product scope, a supply-chain or
assurance level, a user-facing claim, taste, or a resource only the owner holds (engine time,
hardware, accounts, a person's eye). Each one has a stable ID. D-01 to D-23 are taken; the next call
to be briefed takes D-24, and no ID is ever reused or renumbered, because code and docs cite them
(D-14 from `tools/check-shim-scaffold-drift.py`, D-22 from `tools/publish-members.py`, D-23 from
`tests/suite-selftest.core.livecodescript` and the tools that build and gate it).

1. **The ledger rule.** A decision is recorded at its PRIMARY source - the spec, plan section or
   member doc it governs - in the same change that acts on it. This file indexes those records and
   holds the brief of any decision still open. It is not a second ledger: when a decision lands,
   write it at its source and cut its row here to one line.
2. **Recommendations are advisory.** A brief's recommendation is the suite's reasoning, stated so it
   can be disagreed with. No document may cite one as a resolution.
3. **Provenance.** D-01, D-22 and D-23 are in the owner's own words (D-23's are a request and the
   option the owner picked when asked how to meet it, both quoted in its row). D-02, D-03 and D-05
   to D-21 were decided on 2026-08-27 under owner delegation (the open calls, to be decided for
   fastest shipping with fullest coverage; commit `a8a486c`), not one by one by the owner.
4. **Cite by anchor, not by line.** A citation is a file plus a quoted phrase that moves with the
   thing it names; `tools/check-doc-anchors.py` (in the gate set) fails when an anchor stops
   resolving. Line numbers in this tree go stale within a day.

The work a decision creates lives in [WORK-PLAN.md](WORK-PLAN.md). The full original briefs
(options, costs, recommendations) for every decided item are in git history.

## The open decision: D-04

### D-04. Which `.onion`-derivability claim ships?

**Question.** A Channels channel's `.onion` address can be derived from the channel card alone,
because one ed25519 seed keys both the DHT feed and the onion service. Do the suite's documents and
the app say so ("your channel card alone is the anon locator"), or do they rely on the `svc=` feed
line, which is already in the schema?

**Why it is the owner's.** Decision 14.3 in section 14 of
[ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) reserves it: the owner reads the VERIFY
result and chooses the wording that ships. It is a user-protective claim about what a card alone can
promise.

**Evidence, as of 2026-09-23.** Register item #27 has two halves. The offline half (`btDhtKeypair`
and `sxSignKeypairFromSeed` give the same key from one seed) ran green on an engine 2026-08-08, in
the suite paste's CROSS section, and has run natively in CI since 2026-08-17. The live half
(`oxServiceAddress == chChannelOnionAddr(pub)` on a real onion service) is open. It rides register
#32, the S4 two-machine Channels run (runbook row 21), which needs two machines and a live tor.

**Options.** If #27's live half passes, the strong wording ships. If it fails, the `svc=` line is the
source of truth and the derivability claim drops from every document. Publishing the strong claim
before the run is not an option: the honesty convention forbids it.

**Finding, 2026-09-23.** Channels' in-app copy is already ahead of the decision. The `chAnon`
tooltip, the help text and the `chSetAnon` dialog in
`torrentxt/examples/torrent-dht-channels.livecodescript` all say the channel is "reachable from the
channel card alone".

**Blocked until decided.** The strong claim in every suite document and in the Channels copy. No
code waits on it.

**Recommendation (advisory).** Pre-approve both wordings now, so the S4 #32 run flips a label
instead of waiting on copy. Meanwhile, bring the three in-app strings back to the `svc=`-safe
wording. That needs no decision: section 14 already says no UI publishes the strong claim before
#27's live half passes.

## The decision log

| ID | Question | Outcome | Date | Where it is recorded |
|---|---|---|---|---|
| D-01 | Vendor a Schnorr/BIP-340 + BIP-341 tweak library into coinxt, or strike Taproot signing? | **Vendor** (owner: "we would definitely like to vendor the required software for taproot/schnorr"). Shipped the same day in `affdf1c` as coinxt ABI 6, on upstream bitcoin-core/secp256k1 rather than the secp256k1-zkp fork the brief named, and copied in with no second build system. The brief's own advice, to hold the deferral, lost. Lesson: a brief is only as good as its evidence. | 2026-08-16 (owner) | `coinxt/SPEC.md` section 2.1; `coinxt/CLAUDE.md`, ABI history |
| D-02 | nocloud HTTP host: standards polish or new capability? | **Deferred** until the first external user report against the HTTP host. Every item on the menu is polish or speculative capability; none is a defect. Its five questions stay live and would order the menu: (1) polish or capability first; (2) an introspection option that keeps a share's contents list private while known paths still serve; (3) how far routes go - params, header control and file-backed streaming were built 2026-08-16, while generated-body streaming/SSE and stateful paste/KV are open; (4) a sha256 manifest plus a passphrase-verify endpoint, or skip; (5) a `gzip_static` sidecar, or leave it. | 2026-08-27 | `nocloud/docs/http-server-deep-dive.md` (Status; section 4 closes with the five questions and the suite's advisory answers); `nocloud/CLAUDE.md`. The unbuilt endpoint menu is in the work plan |
| D-03 | box2dxt in the release lane: its own docker-run job, or raise the glibc floor to 2.28? | **Resolved by events.** Release run 12 built and committed box2dxt's Linux libraries in the shared release workflow, with no separate job. **Premise changed since:** that run's `x86-linux` library needs glibc 2.34 (it was 2.17); `x86_64-linux` still needs 2.17. A re-open candidate (below). | 2026-08-27 | `box2dxt/CLAUDE.md` section 13 |
| D-04 | Which `.onion`-derivability claim ships? | **OPEN.** Brief above. | - | `docs/ONIONXT-INTEGRATION-PLAN.md` section 14 (decision 14.3) |
| D-05 | Sign off the anonymous-mode positioning copy? | **Signed off as written.** It claims IP hiding and payload privacy, disclaims Tor-use visibility and timing/volume, and the unproven legs carry honesty labels. | 2026-08-27 | `docs/ONIONXT-INTEGRATION-PLAN.md` section 14 (decision 14.4; the threat-model page it cited was merged into that plan 2026-09-23) |
| D-06 | Riptide feed retention: does a follower republish followed heads? | **No.** Privacy-first: a republish keeps someone else's content alive without their consent. Retention is the author's own re-put. Revisit only as an explicit per-follow opt-in, never as a default. | 2026-08-27 | `docs/RIPTIDE-SOCIAL-SPEC.md` section 12 item 4 |
| D-07 | Tor delivery: document the install, or bundle a tor binary? | **Document-install, indefinitely.** Bundling would put packaging, update and trust duties on every release. Revisit only if a consumer app (nocloud) targets non-technical users as its primary audience. | 2026-08-27 | `docs/ONIONXT-INTEGRATION-PLAN.md` section 14 (decision 14.1); `onionxt/docs/07-tor-lifecycle.md`; `onionxt/docs/01-threat-model.md` |
| D-08 | sodiumxt Windows libsodium: pin the vcpkg baseline, build the pinned source, or record the KAT-guarded status quo? | **The status quo, recorded.** Windows links vcpkg's libsodium. The KATs gate every build, and the release lane's Windows job runs them before bundling. The committed Windows DLLs are MSVC builds carrying libsodium 1.0.22; Linux and mac carry the pinned 1.0.20. | 2026-08-27 | `sodiumxt/docs/building.md` (section "The pinned libsodium"); `sodiumxt/docs/security.md`; `sodiumxt/CLAUDE.md`, committed-binaries table |
| D-09 | nocloud Tor path: add keep-alive, or keep close-per-response? | **Close-per-response stands.** It is built, simple and auditable. The keep-alive gain over Tor is unmeasured, and circuit reuse cuts against stream unlinkability. | 2026-08-27 | `nocloud/docs/http-server-deep-dive.md` section 1.1; `nocloud/CLAUDE.md` |
| D-10 | Spend an engine minute probing for a cheap single-file mtime? | **Yes.** A folder-scan-only answer confirms the current weak `size-seed-gen` ETag; a cheap mtime would allow restart-stable validators. **The probe is still owed.** It was meant for the 2026-08-27 session and is now an S1 item. | 2026-08-27 | `nocloud/docs/oxt-pass-checklist.md` section 4; `nocloud/docs/http-server-deep-dive.md` section 1.5 |
| D-11 | Ratify the anon large-file policy? | **Ratified as built.** Warn above 256 MiB (`kAnonSizeWarn` = 268435456 in torrent-quickshare, torrent-dht-channels and nocloud). Never block, and never auto-downgrade to clearnet. | 2026-08-27 | `docs/ONIONXT-INTEGRATION-PLAN.md` section 14 (decision 14.2) |
| D-12 | Channels serve-map durability? | **Ratified as built.** The demos prune stranded anon releases on restart (`chPruneStrandedAnon`). `uOnionServe` is persisted only in a product whose privacy docs can state the on-disk footprint. | 2026-08-27 | `docs/ONIONXT-INTEGRATION-PLAN.md` section 14 (decision 14.5) |
| D-13 | The onionxt v2 menu: rotating onions, v3 client auth, a framing helper, multiplexing, subverted-tor detection? | **Deferred.** The v1 defaults stand. Each question is resolved in docs and code together when a consumer hits its limit. For client auth, once Channels anon matures, the default is off with a per-channel opt-in. The decision's banner expected v1 to be live-proven that night; the optional Mode B launch (closing-pass leg F) still has no engine record. | 2026-08-27 | `onionxt/docs/01-threat-model.md` (section "The deliberate v1 defaults") |
| D-14 | `oxtkit/` shared native scaffolding: extract it, or retire the plan? | **Retire.** The one property it would buy, the three C++ handle tables never drifting, is held by `tools/check-shim-scaffold-drift.py`. Amended 2026-08-17: the tables normalise to 89 code lines and one digest, while the record codecs genuinely diverge (275/198/202 lines). Revisit only if an eighth native wrap is planned. Written through in that tool's docstring and `tools/build-all.sh` 2026-09-24. | 2026-08-27 | `docs/BINDING-PLAYBOOK.md` section 6 |
| D-15 | coinxt SLIP-39: schedule it, or strike "later"? | **Not planned.** BIP-39 serves every suite consumer. Revisit only with a named consumer, bundled with a planned ABI bump. | 2026-08-27 | `coinxt/SPEC.md` section 1; `coinxt/README.md`; `coinxt/docs/api-reference.md` (applied 2026-09-23) |
| D-16 | coinxt SHA3-512: ship it or strike it? | **The 2026-08-17 deferral stands.** Ship only for a concrete consumer, bundled with the next planned ABI bump. | 2026-08-27 | `coinxt/SPEC.md` section 1 |
| D-17 | coinxt independent-decoder acceptance (python-bitcointx + eth-account): give it a CI lane? | **Manual and release-driven; no CI lane.** **Its premise is false.** The decision's reason, "The release lane already runs it before any binary is bundled", does not describe the tree: no workflow invokes `coinxt/tools/verify-independent-decoder.py`, and its last recorded run is 2026-08-13. A re-open candidate (below). | 2026-08-27 | `coinxt/CLAUDE.md`, "Independent acceptance" |
| D-18 | box2dxt's games and selftest, and holde-em's table: convert them to the suite kit chrome and scaffold, or make the exemptions permanent? | **Permanent.** The games are drawn by box2dxt's Kit, and the selftest matches the kit by value; converting would add a second 300-line block to every paste for no visual change. Written through in `tools/check-ui-kit-drift.py`'s exemption reasons 2026-09-24. The four member harness windows match the kit by value on the same reasoning; the suite paste adopted the kit under D-23. | 2026-08-27 | `box2dxt/CLAUDE.md` section 10; `holde-em/CLAUDE.md` ("The ui-kit gate EXEMPTS this stack"), rule 10 |
| D-19 | box2dxt roadmap: schedule anything, or let the recorded triggers stand? | **Schedule nothing; the triggers stand.** `b2kScene*` and `b2kFoe` get promoted when a second game consumes them. Parallax waits on transparent overlay art. Wave 8 builder cross-pollination, streamed music, multi-player keying and the snake-audit extension stay parked. | 2026-08-27 | `box2dxt/CLAUDE.md` section 8 |
| D-20 | The channels brainstorm: promote anything further, including two flagged SodiumXT helpers? | **Promote nothing.** That covers the ed25519-to-X25519 conversion, which is an ABI bump worth making only if a consumer must encrypt to a signing-only key it cannot exchange prekeys with. It also covers k-of-n secret sharing: libsodium has no Shamir, and adding one would breach the no-new-cryptography rule. | 2026-08-27 | This file, "Research concluded" below (the brainstorm was deleted 2026-09-23) |
| D-21 | Hold'em: build a betting-blind oracle daemon, or keep the recorded no-stake property? | **No daemon.** A standing daemon would reintroduce a trusted server. As built, the oracle is the relay host, and the no-stake property holds. Revisit only if Level 2 stalls permanently. | 2026-08-27 | `holde-em/holdem-spec.md` section 7.2 |
| D-22 | Member repositories: does development move out, or does the suite publish into them? | **Develop here, publish there** (owner: "push these extensions to their own repos, but keep development here"). Publishing is a first-parent replay, fast-forward only, with a `Suite-Commit:` trailer as the only watermark. Adoption is explicit, and divergence is refused until it is ported or accepted. Two options were rejected. Moving development out would lose every cross-member gate (archivext's departure turned thirteen gates red). A hand-run `git subtree split` was refused by every pre-suite repository, which share no history with it. The first adoption published all eleven members 2026-09-23. | 2026-09-22 (owner) | `docs/MEMBER-REPO-SPLIT.md`; `tools/publish-members.py` |
| D-23 | The suite paste: keep the harness look, or adopt the demos' card look and boot self-check, with controls per member? | **Adopt, in the paste only** (owner: "can you create a single livecodescript self building stack (like our demos), that will test every extension in the suite from a single stack, assuming that the current version of each extension is installed? this should be comprehensive, and follow strict LIVECODE SCRIPT conventions."; asked how, the owner chose "Upgrade the existing paste (Recommended)"). The paste stays the one generated stack, and the member harnesses stay authoritative for their own surfaces. It now carries UI kit v2 and the demo boot self-check: one row per `tools/member-registry.py` member (a pill, its counts, a Run for that member alone, Show; nocloud, with no in-engine harness, gets a caption), a results filter, Run all and Copy results. The core keeps the harness scaffold verbatim for its report plumbing: the kit builds the scaffold's four report controls under their own names, so the counters, the RUN NOT FINISHED trailer and Copy results run the code the dated engine records ran. The four member harness windows (the enetxt, datachannelxt, torrentxt and coinxt selftests) keep matching the kit by value, on D-18's reasoning: a second carried block would buy no visual change. The board's build, boot self-check, Run all and Copy results ran on an engine 2026-09-24 (runbook section 8); a row's Run, Show and the filters are verified statically; needs an OXT pass (runbook row 48). | 2026-09-24 (owner) | `tests/suite-selftest.core.livecodescript` ("THE BOARD (D-23)"): its header and THE BOARD section; the adopter lists of `tools/check-ui-kit-drift.py` ("since D-23") and `tools/check-demo-selfcheck-drift.py` ("since D-23") |

**Other recorded decisions**, taken outside this numbering:

- torrentxt's visual dashboard widget is out of v1 scope (2026-08-13): `torrentxt/docs/architecture.md`
  (section "A library, not a widget") and `torrentxt/README.md`.
- datachannelxt excludes media tracks (`NO_MEDIA`). If media ever lands it will be engine-side, with a
  separate plan: `datachannelxt/docs/architecture.md`.
- The mac dylibs ship unsigned and un-notarized, with the linker's ad-hoc signature (owner, 2026-08-23):
  `torrentxt/docs/building.md`, `torrentxt/README.md`.
- holde-em: spectators are deferred (owner, 2026-08-16: "we do not need spectators at this point"), and
  `kHeSeatLiveSecs` = 600 s is owner-accepted (2026-08-16): `holde-em/CLAUDE.md`.
- Riptide spec section 12, decisions 1, 2, 3 and 5, are settled by construction: one stack, one anon
  persona, one long-term prekey, and the build went through phase 8. Recorded in
  `docs/RIPTIDE-SOCIAL-SPEC.md` section 12.
- onionxt's upstream questions (the ed25519 expansion, HMAC-SHA256, SHA3-256 and the conformance vector)
  were resolved by SodiumXT ABI 6 and 7 and `onionxt/tools/onion-kat.py`:
  `onionxt/docs/08-capabilities-required.md`.

## Raised, not yet briefed

These are owner calls found by the 2026-09-23 audit and the consolidation that followed. None has a
brief or an ID yet. A call takes the next free ID when it is briefed. Its follow-up work stays in the
work plan.

**Re-open candidates**

- **D-17:** wire `verify-independent-decoder.py --require` into the release job, or re-decide on a true
  premise.
- **D-03:** box2dxt's `x86-linux` library regressed to glibc 2.34 in run 12. Either build that release
  row in a `manylinux2014_i686` container, as `native-box2dxt.yml` already does, or publish the floor.
  This is part of the suite-floor call below.

**Suite-wide**

- **Windows upstream pins.** torrentxt's Windows DLLs carry libtorrent 2.1.1 (vcpkg's unpinned port)
  against 2.0.11 on Linux and mac; it ran green on an engine on 2026-09-24 by the maintainer's
  account (106/106 in the suite paste; the report prints no library version), which informs the
  call without making it. datachannelxt's carry OpenSSL 3.6.4 (vcpkg's classic port) against
  a pinned 3.5.4 on mac. Pin each one, or accept it the way D-08 accepted sodiumxt's 1.0.22.
- **A suite Linux glibc floor.** The committed floors run from 2.14 to 2.38. datachannelxt (both rows)
  and torrentxt's `x86-linux` need 2.38, so they cannot load on Ubuntu 22.04, Debian 12 or RHEL 9.
  Choose a floor, then move rows into manylinux containers or publish each measured floor.
- **OpenSSL license notices.** OpenSSL (Apache-2.0) is statically linked into torrentxt's
  `x86_64-linux`, Windows and mac binaries and into datachannelxt's Windows and mac binaries.
  Neither `torrentxt/THIRD-PARTY-LICENSES.md` nor `datachannelxt/THIRD-PARTY-LICENSES.md` carries
  its notice, and the root `LICENSE` lists datachannelxt's OpenSSL as not bundled. Those files are
  owner-reviewed.
- **32-bit engines.** Arrange a 32-bit Windows OXT and a 32-bit Linux OXT for the `x86-win32` and
  `x86-linux` rows (runbook rows 23 and 47), or accept those rows as CI-only. coinxt's `x86-win32` DLL
  may never have executed anywhere (CI's Windows KAT step is x86_64 only, and the 2026-09-24 engine
  run did not record its bitness).
- **coinxt per-push Windows/mac CI** (with a 32-bit Python for the x86 DLL), or a written "dispatch-only
  is permanent".
- **Supply-chain hygiene**, found by the 2026-09-08 research and re-verified 2026-09-23. Decide which
  of these to take on:
  - none of the 54 `uses:` lines in `.github/workflows` is SHA-pinned;
  - there is no root SECURITY.md or disclosure contact (only nocloud has one);
  - no gate checks coinxt's vendored sources against the commits
    `coinxt/native/vendor/VENDOR.md` names;
  - no external security review of any member is recorded.
- **Publishing, owner-only actions.** Watch each member repository's first generated `gates.yml` and
  `native.yml` runs and record them (this tree's automation cannot see those repositories). Put the
  `XTALK_PUBLISH_TOKEN` expiry date in a calendar.
- **Model C Phase 4 exit.** It needs a fresh person on each of macOS, Windows and Linux, following only
  section 13 of [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) through a two-machine anon
  transfer.
- **A blockchain or ledger direction.** The research concluded 2026-09-08 (below) but was never raised
  as a decision.

**Per member**

- **sodiumxt:** the tree does not record which platform and sodiumxt package the 2026-08-27
  two-machine suite paste (2440/2/3) ran on. Record it if it is known.
- **torrentxt:** acknowledge the positioning and distribution risk of shipping a BitTorrent client,
  which its design brief asked to have flagged before public release. TorrentXT was published
  2026-09-23; its legitimate framing is resilient distribution of large payloads.
- **torrentxt:** QuickShare's cross-action mixing guard. Re-dropping a file already shared anonymously
  seeds it publicly with no confirmation. Build the "also seed this publicly" confirmation, or record
  the guard as dropped.
- **datachannelxt:** when to remove the legacy `dcLocalDescription` transition shim in
  datachannel-helpers.
- **coinxt:** a sync never extends the address window (windows extend on demand since 2026-09-03), so a
  restored wallet whose whole window is used can miss funds. A gap-limit scan would change what a sync
  is.
- **coinxt:** the wallet takes "confirmed" on a backend's word; there is no merkle-proof or
  block-header check in any script. Decide whether to build chain-inclusion verification.
- **nostrxt:** the phase 9 scope. The candidates are:
  - NIP-17 private DMs over NIP-59 gift wrap (their blockers cleared 2026-08-23/24);
  - NIP-59 as its own layer;
  - NIP-65 outbox routing with a relay pool;
  - `.onion` relays through a transport seam in `nxrConnect`;
  - NIP-44's extended length, which waits on upstream vectors.
- **riptide:** the calls are:
  - whether the 2026-09-09 LAN domain-tag change should have minted a new `RSL1` magic (devices from
    before and after it silently fail admission with each other);
  - the author's own-head refresh cadence while online (BEP44 items expire, and D-06 rules out follower
    republish);
  - the scope of an in-app bridge reader (`rsRequestBridge`, `rsIngestBridge` and
    `rsNostrBridgeFromEvent` have no app caller);
  - whether to wire the pairwise room (`rsRoomId`) and the BTXO anon file transfer into the app, or
    record them as library-only;
  - whether followers-only sealed media gets a spec of its own.
- **holde-em:** the calls are:
  - build or strike BEP44 profiles and standings, seven to nine seats, and the optional direct-TCP lane;
  - schedule the Level 2 played-hand wiring;
  - name the non-author who does the Phase 5 hostile review;
  - close runbook row 14 at inference strength (its asserts ran green in every folded run from
    2026-08-17 on, and engine note 3.1 is OBSERVED);
  - allow the one-word fix to the frozen `holde-em/assets/sounds/NOTICE.md`, whose cardShuffle row
    reads as wired when it is not.
- **box2dxt:** the platformer polish pass needs the owner's eye on an engine: feel, facing, scenery,
  audio and onboarding. Only its headless half is recorded (2026-09-10).

## Research concluded, no decision taken

**Blockchain feasibility (researched 2026-09-08; the report was deleted 2026-09-23 and is in git
history).**

- **Method.** A ten-area survey of the tree, six candidate architectures, four judge lenses and an
  adversarial verification pass.
- **Conclusion.** A permissionless chain built here would be a demonstration, not a security system:
  - its security budget is zero, and the economics of majority attacks on young chains are published;
  - every `.lcb` and `.livecodescript` needs a GUI engine, so there is no headless validator or daemon
    mode;
  - there is no bounded execution or preemption;
  - there is no sybil resistance.
- **If a ledger were ever pursued.** The recommendation was a pair that is deliberately not a chain,
  estimated at 14-19 person-weeks of pure script with no ABI bump:
  - "Counterfoil": a signed, monotone, hash-linked record layer with a reader-enforced watermark and
    an atomic store;
  - "Rootline": merkle-aggregates Counterfoil's tree heads, anchors them into Bitcoin through coinxt's
    engine-proven transaction path, and checks them with a checkpointed header verifier.
- **An optional extra.** A stateless libbitcoinkernel binding would turn
  `coinxt/tools/verify-independent-decoder.py` into an in-tree CI gate.
- **The cheapest correct route.** An xTalk app joins a chain by being the client of an external
  daemon. The suite already does this for tor, for Electrum, Esplora and bitcoin-cli, and for Nostr
  relays.
- **The report's own defect list** was fixed 2026-09-09/10: riptide's reader watermark, the rp1 queue
  bound, the BEP44 996-byte cap and the interpreter's 2^53 refusal.
- **Findings still true on 2026-09-23** are the chain-inclusion and supply-chain items above, and
  durability:
  - no `fsync`, `fdatasync` or `FlushFileBuffers` in any `.c`, `.cpp`, `.h` or `.livecodescript`,
    and no atomic replace (`rename file` appears at three sites, one download helper's copies, and no
    state-writing path uses it);
  - the house safe-write is delete-then-recreate, motivated by the claim that `open file ... for
    binary write` does not truncate. That claim is UNEVIDENCED, and the LiveCode reference and
    engine source say the opposite (engine note 6.14, 2026-09-24); delete-first is right under both
    readings, and neither in-place form is crash-safe, so the durability finding stands;
  - so persistence is best-effort. The report named a small native `fsync` + atomic-replace export
    from an existing shim as the one change that would move that label, a D-NN-shaped call;
  - the restart-and-read-back check is open (runbook row 6, closing-pass leg C in S3: resume
    saved to disk and re-added across an OXT restart), and no code touches SQLite or revDB (the
    work plan's optional S1 measurements ask whether OXT exposes it).
- **Measured once, if header work ever starts:** exact Bitcoin chainwork, floor(2^256/(T+1)), is
  computable in script with a big-by-small divmod for nBits exponents from 0x13 up, with zero
  mismatches over 176,134 samples.

**The channels brainstorm, closed by D-20.** It was deleted 2026-09-23 and is in git history.

- **Its thesis:** one ed25519 seed is both the BitTorrent/DHT identity and the cryptographic name.
- **What shipped:** its core (signed BEP44 feeds, phantom-swarm rendezvous, secretstream over a BEP10
  peer-wire extension). It became torrentxt v9-v11 plus sodiumxt's seeded kx keypairs, and it runs as
  riptide.
- **What is not planned:** cover-seed channels, group rooms with sender keys, time-locked messages,
  multi-hop relay, covert micro-channels and proof-of-work inbox anti-spam.
