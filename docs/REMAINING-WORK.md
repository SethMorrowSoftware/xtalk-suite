# REMAINING-WORK.md — the suite's consolidated punch list

**Compiled 2026-08-15** from a full-tree audit at commit `2d49729`, then revised
the same day for the holde-em fold (`159a5a3`, the standalone hold-em repository
folded home as the tenth member at v0.18.0). Every item cites the file that
establishes it; each member's own `README.md` / `CLAUDE.md` stays the authority
for its layer — this document is an INDEX of the open work, not a second ledger.
Per the honesty convention it applies to itself: this is a dated, point-in-time
audit. When an item closes, strike it here in the same change (the truth-sync
discipline), and when this file's date grows old, re-audit or retire it rather
than trust it.

**The short version.** One big build is unstarted (Model C for DHT-Channels).
The second capstone turned out to be half-built already: holde-em folded home
with hotseat and online play written, leaving its oracle, mental-poker, and
hardening phases open. One code layer is missing from an otherwise-done Riptide
phase (onion serving). Everything else that is *built* mostly waits on three
environmental sessions `docs/OXT-PASS-RUNBOOK.md` already scripts: **one evening
with a Tor daemon**, **one two-machine session** (now including holde-em's
"two machines, one invite code" pass), and **cheap single-machine re-opens** of
every demo converted in the 2026-08-14 UI unification. The macOS binaries are
the one release gap. The rest is label/doc hygiene and recorded owner decisions.

---

## A. Unbuilt phases and features (16)

Code that does not exist yet: planned phases, designed-but-unshipped surfaces,
and one functional hole.

1. **Hold'em: the open phases — 2e remainder, 2f, 3, 4, 5** (large).
   Built and folded home at v0.18.0: the Phase 1 hotseat game (evaluator
   exhaustively verified over all 2,598,960 hands, settlement fuzzed over ~90k
   configs), the Phase 2 online lobby and 2d online play (netsim-pinned on one
   machine), the single-machine half of 2e (reconnect + adversarial hardening),
   and the auditable Level 0 committed shuffle. Remaining: the rest of 2e
   (street ckpt wires, show/muck, online-History folding — recorded deferrals),
   2f onion tables, Phase 3 (the onion deck oracle, host election), Phase 4
   (ristretto255 mental poker — blocked on item 2), Phase 5 (DLEQ proofs,
   hostile review, soak). The Level-0 cheating-dealer caveat closes only when
   online play carries independent per-player seeds.
   — `holde-em/IMPLEMENTATION-PLAN.md`, `holde-em/README.md` (Status),
   `holde-em/CLAUDE.md` (fold record)

2. **~~SodiumXT ristretto255 surface (Workstream U)~~ SHIPPED statically
   2026-08-15** (SodiumXT ABI 8: the five sxRistretto* handlers, no sxHash512
   needed, KATs cross-checked between libsodium and the independent RFC 9496
   reference now in `holde-em/tools/protocol-kat.py`, all four non-mac
   binaries rebuilt). Remaining from this item: the handlers' first OXT pass
   (they are engine-unexercised - the harness section SKIPs on a pre-ABI-8
   package), the Windows engine re-proof of the mingw cross-built DLLs, and
   the recorded Phase 5 follow-ons (ScalarMultBatch, point add/sub, base
   mult for DLEQ).
   — `sodiumxt/CLAUDE.md` ABI table, `holde-em/IMPLEMENTATION-PLAN.md` (Workstream U)

3. **Hold'em table 720p re-layout (1024x690 -> height <= 640)** (small). The
   overage is real — the status line (y 632-672) and quick-bet row (y 688) live
   below the fold — so this is a re-layout needing an OXT eye, not a number
   trim. Carries a written SKIP in `tools/check-stack-size.py` until it lands.
   — `tools/check-stack-size.py` SKIP entry, `holde-em/src/holdem.livecodescript:573,652`

4. **ONIONXT integration plan Phases 2-3: Model C for DHT-Channels** (large).
   The §6 design (identity unification, per-channel onion services, the svc=
   feed line, the BTXC/BTXF request layer, anonymous file delivery,
   badges/persistence) plus Phase 0's Tor toggle in the Channels UI has no
   code: `torrentxt/examples/torrent-dht-channels.livecodescript` contains zero
   onion/Tor references. Only the QuickShare side (Phase 1) was built.
   — `docs/ONIONXT-INTEGRATION-PLAN.md` §6, §10

5. **ONIONXT plan Phase 4 docs** (small). `docs/anon-transport.md`, the
   threat-model page, and the §13 onboarding doc do not exist anywhere.
   — `docs/ONIONXT-INTEGRATION-PLAN.md:1493-1497`

6. **Riptide spec 8.2/8.3 onion transport serving** (medium). No oxh* call
   exists in riptide: serving the anon feed page, serving the persona prekey,
   and accepting sealed intros via POST /dm are unbuilt (the 8.3 crypto closed
   2026-08-15; the transport did not).
   — `riptide/README.md:131-140`, `riptide/CLAUDE.md:316-332`,
   `docs/RIPTIDE-SOCIAL-SPEC.md:370-395`

7. **Riptide phase 6's actual sync payload** (medium). Only the admission
   handshake exists; the spec's channel 0/1/2 traffic (keyring/drafts/feed
   seq/read receipts, presence, bulk media) is unbuilt, so the phase's
   draft-appears-on-another-device criterion cannot yet be met.
   — `docs/RIPTIDE-SOCIAL-SPEC.md:325-347`, `riptide/src/riptide.livecodescript:2074-2326`

8. **Riptide phase-5 typing presence has no recorded disposition** (small).
   Neither built nor recorded as a deliberate non-build (the way the
   DHT-dead-drop cold start was). Build it or write the decision down.
   — `docs/RIPTIDE-SOCIAL-SPEC.md:315-321,524-535`

9. **Riptide demo publishes profileMeta empty** (small). rsBuildHead carries the
   field; the demo never populates it. Demo-side wiring only.
   — `riptide/examples/riptide-social.livecodescript:78-79`

10. **coinxt Schnorr/BIP-340 + the Taproot tweak** (large; deferred with
    Taproot). Waits on a secp256k1-zkp vendoring decision; today
    cxBtcAddressP2TR encodes a pre-tweaked key and cannot compute the BIP-341
    tweak.
    — `coinxt/CLAUDE.md:528`, `coinxt/SPEC.md:158-160`

11. **coinxt WIF encode/decode** (small). Designed in SPEC, "handler not found"
    today; the Base58Check framing already exists.
    — `coinxt/README.md:15-17`

12. **coinxt cnx_memzero export** (small; ABI bump). The PBKDF2 seed out-buffer
    is freed unwiped; the source records the fix's shape.
    — `coinxt/src/coinxt.lcb:125-135`

13. **nocloud HTTP-host Phase 3: per-route streaming/params** (large). The
    deep-dive's own ledger names it the one open item; enabler for its §4
    endpoint ideas.
    — `nocloud/docs/http-server-deep-dive.md:27,213-226`

14. **nocloud residual Phase-2 duplication** (medium). qsFsServeFile and
    qsCwServeFile duplicate the whole ETag/304 branch and head assembly; the
    Tor keep-alive question is an as-built fact, not a recorded decision.
    — `nocloud/src/nocloudquickshare.livecodescript:5487-5535,6378-6421`

15. **nocloud token-mount redirect hole** (small). The shipped /go/gallery
    redirect emits Location: /gallery verbatim; under a /<token>/ web-link
    mount that lands outside the capability mount. Re-prefix server-side, or
    document the Tor-root-only limit and test the redirect from inside a mount.
    — `nocloud/webapp/.qsroutes.json:32-37`, `nocloud/src/nocloudquickshare.livecodescript:4522-4523`

16. **box2dxt platformer polish plan §9 passes** (medium). Scene composition
    (each biome deliberately dressed), audio + UX/chrome sweep, code/repo
    cleanup + packaging proof, cosmetic transition-card tuning. (The
    feel/facing/scale half is engine work — B.5.)
    — `box2dxt/docs/platformer-polish-plan.md` §3-§7, §9

## B. Verification backlog (12)

Built and statically verified; pending under the honesty convention.
`docs/OXT-PASS-RUNBOOK.md` scripts nearly all of it.

1. **Fleet-wide OXT re-pass of every kit-converted demo** (large). Every demo
   converted 2026-08-14 reads "UI unified 2026-08-14; needs an OXT re-pass";
   ~20 runnable stacks carry a live label; every DEMOS tick-sheet row except
   riptide-social is unchecked. The runbook says to start here.
   — `docs/OXT-PASS-RUNBOOK.md:101-124,1186-1196`

2. **Suite closing pass legs B-E (two machines)** (medium). enet LAN chat;
   torrent seed/leech + resume across an OXT restart; rp1 chat over a DHT
   rendezvous; dc chat signalled over the real DHT. Leg A closed 2026-08-15.
   — `tests/suite-closing-pass.livecodescript:3-36`, runbook tick sheet

3. **The Tor evening** (medium). Runbook items 4 + 5 and closing-pass leg F:
   Mode B oxLaunchTor (onionxt's one remaining VERIFY), the live onion echo
   that closes the seven live-daemon coverage exemptions, the QuickShare
   Model C behavioural run, nocloud's Tor path, the two-instance onion round
   trip, the negative paths, then the §12.3 register ticks and label flips.
   — `docs/OXT-PASS-RUNBOOK.md:174-175,852-874`, `docs/ONIONXT-INTEGRATION-PLAN.md` §12.3

4. **Riptide phases 5-7 live passes** (large). The phase-5 call has NEVER
   executed (two machines, two networks); phase-6 live admission; phase-7
   persona over Tor (also blocked on A.6). Plus the phase-3 mid-download
   nuance and one engine re-run of the post-00:46 harness additions
   (LAN-welcome, 8.3 crypto).
   — `riptide/CLAUDE.md:35-57`, `riptide/docs/two-machine-runbook.md`

5. **box2dxt member-wide re-pass + platform verdicts** (large). The fold's
   ~1550-fix sweep re-opened the whole member; macOS/Linux verdicts (risk R1)
   and the polish plan's feel/facing/scale pass (incl. L7's vertical camera)
   ride the same sessions.
   — `box2dxt/CLAUDE.md:72-74`, `box2dxt/plan.md:46-47`

6. **datachannelxt browser interop + two-network NAT call** (medium). The
   member's two explicitly-open residuals; no session has ever left the host.
   — `datachannelxt/CLAUDE.md:162-164`

7. **torrentxt's four never-run plan gates** (medium). Real-swarm interop
   (legal ISO + hash), resume across a real restart, packaged fresh-install
   per platform, the destructive-handler manual pass.
   — `torrentxt/docs/TorrentXT-IMPLEMENTATION-PLAN.md:480-513`

8. **coinxt demo pass + live testnet broadcast** (medium). The phase-6 demo's
   engine pass, and the one bar left before "broadcastable": a CoinXT-built
   transaction accepted on a live testnet in each of the four families.
   — `coinxt/examples/coinxt-demo.livecodescript:14-18`, `coinxt/IMPLEMENTATION-PLAN.md:235`

9. **nocloud: the 48-item pass checklist at zero ticks + whole-stack re-pass**
   (large). Plus the checklist's own gaps: no ETag/304 section, no items for
   the webapp's runtime claims (SW-over-Tor, in-app Range, SPA refresh,
   HEAD-on-SPA), no redirect-under-token-mount test.
   — `nocloud/docs/oxt-pass-checklist.md`, `nocloud/src/nocloudquickshare.livecodescript:57-60`

10. **Suite-root stacks: start-here, ui-kit v2 assembly, closing-pass stack**
    (small). Each carries its own "verified statically" label; cheap
    single-machine opens.
    — `start-here.livecodescript:42-45`, `tools/ui-kit.livecodescript:59`

11. **holde-em's pending passes** (medium). The Phase 2d multi-machine pass
    ("two machines, one invite code" — netsim-pinned, never crossed real
    machines); the Phase 1 exit (a full 6-seat hotseat session in OXT, plus
    the 1d animation polish left for that pass); and a re-pass of
    heXorSeedsHex / heDeckFromStreamKey, which the fold rewrote after the
    unified checker found the stepped-pair-walk and throw-in-catch traps —
    that pass should also establish whether earlier on-engine Level 0 runs
    dealt from the stepped or 1-stepped stream (the Python KATs pin the
    correct semantics).
    — `holde-em/IMPLEMENTATION-PLAN.md` (Phase 1 exit, 2d status),
    `holde-em/CLAUDE.md` (fold record)

12. **onionxt's four inline on-engine hypotheses** (small). The
    duplicate-local-port refusal, oxGuessService's socket-id format,
    stale-socket-close tolerance, the topStack default callback owner.
    — `onionxt/src/onionxt.livecodescript:1018,1140,1713,1744`

## C. Release and CI (7)

1. **macOS universal binaries** (large). torrentxt, enetxt, datachannelxt,
   coinxt ship none; sodiumxt's is one ABI behind (sxSha3_256 dark on Macs; a
   Mac repackage throws an ABI mismatch on the first sx* call); torrentxt
   additionally needs codesign + notarization with credentials CI does not
   hold. Deliberately manual lipo builds on real hardware.
   — `docs/OXT-PASS-RUNBOOK.md` §2.1/§2.4, `sodiumxt/CLAUDE.md:54-59`

2. **box2dxt as the eighth folded harness member** (large). Returned-report
   selftest line, Member row in build-suite-selftest.py, b2/b2k prefixes in
   check-suite-coverage.py AND check-handler-calls.py, then close what the
   coverage gate demands.
   — `box2dxt/CLAUDE.md:53-67`

3. **box2dxt into the release assembly lane** (medium). release-binaries.yml
   and install-release-binaries.py both omit it; needs the docker-run job
   ported or an owner-decided glibc-floor raise. "A deliberate release-lane
   pass, not a drive-by."
   — `box2dxt/CLAUDE.md:34-47`

4. **holde-em into the suite selftest and coverage gate** (medium).
   Deliberately not done in the fold: the member's harness lives EMBEDDED in
   the game stack (heRunSelftest), so the generator and coverage gate do not
   know it (the box2dxt precedent). Done = extract the harness or teach the
   fold machinery an embedded one, add the Member row and the he prefix, close
   the gaps the gate then demands.
   — `holde-em/CLAUDE.md` (fold record), `tools/build-suite-selftest.py`,
   `tools/check-suite-coverage.py`

5. **torrentxt portable-Linux lane never dispatched** (small). The committed
   x86_64 .so still carries the glibc-2.38 floor until one release-binaries
   dispatch re-commits from the wired manylinux_2_28 lane.
   — `torrentxt/docs/building.md:126-162`

6. **coinxt per-push CI is Linux-only** (medium). Windows only at manual
   release dispatch; macOS untried. Per-push lanes, or a written decision the
   dispatch path is permanent.
   — `.github/workflows/native-coinxt.yml:23-37`

7. **Inert member workflows carry stale pre-suite behavior, ungated** (small).
   coinxt's still describes the abandoned repo split; torrentxt's would
   auto-commit binaries if a mirror ran it; the three hand-kept copies of
   build config have a written mirror-by-hand obligation and no drift check.
   — `coinxt/.github/workflows/ci.yml:10-12`, `release-binaries.yml:106-114`

## D. Label and doc hygiene (9)

1. **Stale honesty labels lagging recorded passes — one sync pass** (medium).
   `sodiumxt/src/sodium.lcb:10-20` + `sodium-tests:18` (closed by the 71-check
   2026-08-12 pass); `coinxt/src/coinxt.livecodescript:1976-1979` phase-5
   STATUS (engine + decoder bars met); `riptide/src/riptide.livecodescript:21-29`
   phases 3-4 (closed 2026-08-15) plus the demo's "phases 5-7 are NOT here"
   scope block; onionxt's "SHA3-256 (deferred)" UI strings for a shipped gap
   (fix requires regenerating both standalones + the suite harness);
   box2dxt platformer's "remaining slice 3" comments for shipped slices.
   The convention only works if labels flip both ways.

2. **The tracked consolidation path-rewrite pass** (medium). Docs moved
   verbatim still cite member-root-relative paths; includes box2dxt's README
   badge, riptide/examples/README's runbook path, and suite-gates.yml's
   "tracked follow-up" header for a port that shipped.
   — root `CLAUDE.md` cross-reference caveat

3. **nocloud CONTRIBUTING still describes the standalone repo** (small). Names
   only the two member gates; the suite gate set has walked the directory
   since the fold. A contributor following it verbatim misses all of that.
   — `nocloud/CONTRIBUTING.md:5-15,32-58,127-135`

4. **The family engineering template is stale and ungated** (medium).
   `onionxt/templates/CLAUDE.md` (+ byte-identical coinxt twin): its checker
   section describes the retired pre-unification rule set; shipped-is-not-run,
   coverage-overstatement, and the carried-block conventions never flowed in;
   post-2026-08-13 gotchas (textDecode-is-lossy, stale-the-result,
   dangling-else, the falsified step-loop scale claim) are absent; no drift
   gate or master. Hoist one master with a drift gate, then sync.
   — `onionxt/templates/CLAUDE.md`, `coinxt/MIGRATION.md:105-109`

5. **Union the eight holde-em idiom checks into the unified checker** (medium).
   (Replaces the resolved stale-seed-checker item — the fold removed
   `docs/holde-em/` and registered the member's unified copy.)
   `holde-em/tools/check-holdem-idioms.py` survives because eight checks with
   shipped-defect provenance (chunk-of-array H6, bitwise H7, engine-token
   names, undeclared catch vars, command-with-parens, dynamic property names,
   message-box prose, never-declared k-constants) have no unified counterpart.
   The 2026-08-12 precedent says they belong in the ONE checker, propagated to
   all ten members with fixtures — a deliberate pass, since each firing on
   another member's code is itself a latent-bug find; then retire the idioms
   gate.
   — `holde-em/tools/check-holdem-idioms.py` docstring, root `CLAUDE.md`
   checker-unification passage

6. **nocloud doc surface lagging the newest features** (medium). SECURITY.md's
   unfilled contact placeholder and missing .qsroutes.json model bullet;
   CONTRIBUTING's half-stale golden-mirror table; webapp docs/demo omitting
   .qsroutes.json, config.json, ETag/304; sw.js's now-conditionally-wrong
   "can never serve a stale file" claim.
   — `nocloud/SECURITY.md:8,18-98`, `nocloud/webapp/sw.js:6-8`

7. **coinxt SPEC/README claim SHA3-512; only SHA3-256 exists, unmarked**
   (small). Ship it (sha3.c already vendors it) or mark the two mentions.
   — `coinxt/SPEC.md:33` vs `:164`

8. **torrentxt api-reference "fields not yet populated" reconcile** (small).
   — `torrentxt/docs/api-reference.md:10-14,734-736`

9. **Two riptide gate scripts want hardening** (small).
   check-selftest-vectors.py silently skips constants its regex cannot parse
   (fail loudly instead); check-docs-style.py's SCOPE docstring omits riptide,
   which runs the gate without declaring the rule.
   — `riptide/tools/check-selftest-vectors.py:30-38`, `riptide/tools/check-docs-style.py:11-17`

## E. Open decisions and roadmap (10)

Recorded owner calls and explicitly-uncommitted future work; each wants either
execution or a written resolution.

1. **ONIONXT plan §14: five reserved decisions.** Tor delivery; large-file
   warn-vs-block + threshold; which .onion-derivability claim ships; sign-off
   on positioning copy; Channels serve-map durability.
   — `docs/ONIONXT-INTEGRATION-PLAN.md:1704-1731`
2. **onionxt docs/09: five design questions** (+ subverted-tor detection
   investment). — `onionxt/docs/09-open-questions.md:12-39`
3. **Riptide feed retention** — the one unresolved spec-§12 decision (follower
   republish of followed heads). — `docs/RIPTIDE-SOCIAL-SPEC.md:637-640`
4. **sodiumxt Windows libsodium pin** — vcpkg baseline, pinned source on
   Windows, or record the KAT-guarded status quo.
   — `sodiumxt/docs/development/building.md:177-184`
5. **nocloud mtime probe + Phases 4-5 endpoints** — the engine finding gates
   the real conditional-GET validator; the endpoint menu waits on the §8
   priority questions and Phase 3. — `nocloud/docs/oxt-pass-checklist.md:80-83`
6. **oxtkit/ shared native scaffolding: execute or retire.** Never extracted;
   the native C scaffolding remains N copies with no drift gate.
   — `docs/NEXT-EXTENSIONS-PLAN.md:596-613`
7. **Channels brainstorm menu + flagged SodiumXT helpers** (ed25519->X25519,
   k-of-n secret sharing). Roadmap only.
   — `docs/SODIUM-TORRENT-CHANNELS-BRAINSTORM.md`
8. **coinxt SLIP-39 scope; decoder acceptance as an optional CI lane.**
   — `coinxt/SPEC.md:35`, `coinxt/CLAUDE.md:886-891`
9. **box2dxt's recorded open calls.** Suite-kit chrome exemptions (keep or
   convert); dormant b2kScene*/enemy-pattern promotions; Wave 8 builder
   cross-pollination; streamed music; multi-player keying; snake-audit
   extension; parallax parked on art.
   — `box2dxt/plan.md`, `tools/check-ui-kit-drift.py:64-92`
10. **Recorded optional milestones.** torrentxt's Phase-5 dashboard widget
    (out of v1 by decision); datachannelxt's media tracks (optional, NO_MEDIA).
    — `torrentxt/docs/TorrentXT-IMPLEMENTATION-PLAN.md:514-519`,
    `datachannelxt/docs/architecture.md:106-114`

---

**Permanent, structural exemptions** (recorded, not actionable): onionxt's 11
engine-socket-callback coverage exemptions (only the engine can mint a socket
id); release-binaries.yml's manual dispatch (rule 5: a committed binary traces
to a human decision); the harness scaffold's non-adoption of the UI kit
(written exemption). The 7 live-daemon exemptions retire with the Tor evening
(B.3).
