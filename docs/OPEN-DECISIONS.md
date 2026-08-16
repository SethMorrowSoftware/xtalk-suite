# OPEN-DECISIONS.md - the owner decision briefs

**Compiled 2026-08-16.** Every owner decision recorded open anywhere in this
tree, each condensed to a brief an owner can read and act on in five minutes:
the question, why it is genuinely the owner's, the evidence (every citation
re-verified against the tree on the compile date), the options with their real
costs, what is blocked until it is decided, and the suite's recommendation.
The list was sourced from `REMAINING-WORK.md` section E, then each entry was
re-verified at its primary source and the tree was swept for owner-decision
language the audit missed; the finds and the already-decided entries are noted
in the closing section.

**The ledger rule.** A decision taken from this file gets recorded at its
PRIMARY source (the plan section, spec section, or member doc each brief
cites), in the same change that acts on it, exactly as `REMAINING-WORK.md`
strikes its items. This file is an INDEX of briefs, not a second ledger: when
a decision lands, strike its brief here and write the resolution where the
decision has always lived.

**The honesty note.** Every RECOMMENDATION below is advisory: it is the
suite's recommendation, stated with its reasoning so it can be disagreed with,
and it is not a decision. Nothing here commits the owner to anything, and no
suite document may cite a recommendation below as if it were a resolution.

**Ordering.** Most-blocking first: briefs whose absence blocks recorded build
or release work come first, then briefs that block only a wording, story, or
minor improvement, then the long tail where nothing is blocked and "decide
never" is an honest option. Where nothing is blocked, the brief says so
plainly.

---

## D-01. ~~Vendor secp256k1-zkp for coinxt Schnorr/BIP-340 + the Taproot tweak, or strike Taproot signing?~~ DECIDED 2026-08-16: VENDOR (and the library named here was WRONG)

> **DECIDED: vendor it** (owner: "we would definitely like to vendor the required
> software for taproot/schnorr"). SHIPPED the same day in commit `affdf1c`:
> coinxt ABI 6, BIP-340 Schnorr and the BIP-341 tweak, driven by all 19 published
> BIP-340 vectors (10 negative) and all 14 BIP-341 wallet vectors.
>
> **This brief named the wrong library, and the correction made the decision
> cheaper.** It says `secp256k1-zkp` throughout because coinxt's own notes said
> so, and the brief followed the note instead of checking. Upstream
> **bitcoin-core/secp256k1** carries the `schnorrsig` and `extrakeys` modules
> in-tree, which is everything BIP-340 and single-key BIP-341 need; the zkp fork's
> extra value is adaptor signatures and rangeproofs coinxt does not use. So the
> shipped answer is the canonical library Bitcoin Core itself ships rather than a
> fork - a better audit story on the highest-stakes member, at the same cost.
> The "second build system" cost this brief weighed was also overstated: coinxt
> vendors by copying pinned sources and compiling them directly, and
> libsecp256k1 supports that, so no build system was imported.
>
> **The option this brief recommended - hold the deferral - was NOT taken**, and
> that is the owner's call, correctly. Recorded because a recommendation that
> loses should stay visible: the reasoning was "no consumer needs Taproot spends
> today", which is an argument about timing, not about cost, and the owner
> weighed timing differently.
>
> What did NOT ship, and is now recorded in coinxt's own docs rather than here:
> there is no BIP-341 sighash builder. coinxt can receive to Taproot end to end
> and sign a sighash it is handed; it cannot compute one.

**(original brief follows, unedited)**

### D-01 (as written 2026-08-16, before the decision)

**Why it is the owner's:** vendoring `secp256k1-zkp` is "an order of magnitude
larger than everything above" (coinxt's words): a second library with its own
build system, added to a crypto member whose rule is that every curve op is
trezor-crypto's (`coinxt/SPEC.md:47-49`). Accepting that maintenance and audit
surface, or narrowing coinxt's scope instead, is a resource and risk call only
the owner can make.

**Evidence (verified 2026-08-16):** `coinxt/CLAUDE.md:528-535` records the
Schnorr deferral as "a scope decision, recorded here rather than left as a
silent omission" and defers the vendoring question to the Taproot phase.
`coinxt/SPEC.md:161-163` still specs `cnx_schnorr_sign/verify` and the x-only
helper. `docs/REMAINING-WORK.md:140-144` (A.10) marks the whole Schnorr +
Taproot item "Waits on a secp256k1-zkp vendoring decision". Today
`cxBtcAddressP2TR` encodes a pre-tweaked key and cannot compute the BIP-341
tweak (same A.10 entry).

**Options:**
- **Vendor secp256k1-zkp.** Buys BIP-340 sign/verify and the BIP-341 tweak,
  completing P2TR send-side. Costs: the large vendoring, a second build
  system inside the member, the 5-platform binary matrix rebuilt, and a
  bigger audit surface on the highest-stakes member.
- **A different C BIP-340 implementation.** Smaller, but breaks the
  "everything is trezor-crypto's" provenance rule; a rule change, not a
  shortcut.
- **Decide never.** Ship without Schnorr: P2TR stays receive-oriented with
  its documented unspendable-raw-key caveat, and SPEC strikes the schnorr
  entries. Honest, and free.

**Blocked until decided:** the whole of REMAINING-WORK A.10 (a large build
item). Nothing shipped is affected.

**RECOMMENDATION (the suite's, not a decision):** hold the deferral, and write
the trigger into SPEC: vendor secp256k1-zkp if and when a real consumer needs
Taproot spends; until then the schnorr lines in SPEC carry an explicit
"deferred pending the vendoring decision" mark. Reasoning: no suite consumer
signs Taproot today, and the deferral is already recorded honestly; paying the
vendoring cost ahead of a consumer buys nothing.

---

## D-02. nocloud HTTP host: standards polish or new capability - the deep-dive section 8 priority questions

**Why it is the owner's:** these are product-direction calls about nocloud's
users (what they need, how much integrity machinery they will value, what the
privacy defaults should be), and they order how the remaining phases spend the
app's complexity budget.

**Evidence (verified 2026-08-16):**
`nocloud/docs/http-server-deep-dive.md:417-431` (section 8, "Open questions
for you": priorities; public-vs-LAN introspection default; how far routes go;
integrity appetite; compression), `:356-389` (the phased plan whose ordering
hangs on question 1; Phase 3 at 380-381), `docs/REMAINING-WORK.md:154-157`
(A.13 names Phase 3 the one open ledger item).

**Options (per question, compressed):**
1. **Priorities:** polish-first (cheap, low risk, delays endpoints) vs
   capability-first (Phase 3 route machinery first: the large item, unlocks
   the section-4 endpoint menu). This one must be answered before Phases 3-5
   can be sequenced at all.
2. **Introspection default:** an option to keep a share's contents LIST
   private while serving known paths (small build, one more mode to explain)
   vs status quo (listings already show names/sizes).
3. **Routes:** thin demo surface vs "app platform" (streaming, params, KV);
   platform scope creep is the recorded risk.
4. **Integrity:** sha256 manifest + pre-download passphrase-verify endpoint
   (CPU + complexity for a real verification story) vs skip. "Skip" is a fine
   terminal answer.
5. **Compression:** gzip_static sidecar vs leave it (Tor is the bottleneck;
   text assets are small). "Leave it" is a fine terminal answer.

**Blocked until decided:** the sequencing of nocloud Phases 3-5
(REMAINING-WORK A.13 and the section-4 endpoint menu). The shipped app is
unaffected.

**RECOMMENDATION (the suite's, not a decision):** answer question 1
"capability-first" only if a concrete consumer exists (the bundled webapp or a
user request); otherwise leave Phases 3-5 unscheduled and let the polish tail
ride ordinary OXT passes. Take question 2 as a per-share toggle whenever Phase
3 lands anyway; hold routes thin (3); decide never on 4 and 5 for this app's
audience. Reasoning: the app's product is privacy plus simplicity, and every
section-4 endpoint is speculative until someone asks for it.

---

## D-03. box2dxt in the release lane: its own docker-run job, or raise the glibc floor to 2.28?

**Why it is the owner's:** moving box2dxt's Linux build to manylinux_2_28
would raise its glibc floor from 2.17 to 2.28, "a real portability regression,
the owner's call" (recorded in those words): dropping users on older distros
is a support promise only the owner can renegotiate.

**Evidence (verified 2026-08-16):** `box2dxt/CLAUDE.md:34-47`: box2dxt is not
in `release-binaries.yml`'s matrix; its known-good Linux recipe is `docker run
manylinux2014` inside a stock runner (node20 actions refuse to start in a
glibc-2.17 container), which cannot join the `cmake-members` job's
`container:` shape; `tools/install-release-binaries.py` also does not know
box2dxt's package layout; "Do this as a deliberate release-lane pass, not a
drive-by."

**Options:**
- **Port the docker-run job** from `native-box2dxt.yml` into
  release-binaries.yml (keeps the 2.17 floor; cost: a second job shape in the
  release workflow, plus teaching the installer the layout).
- **Move to manylinux_2_28** (uniform lane; cost: the 2.17-to-2.28 floor
  raise, i.e. dropping pre-2.28 hosts).
- **Decide never:** box2dxt stays out of the one-click release assembly and
  its binaries keep being refreshed manually per change under suite rule 5
  (the status quo; already gate-verified by its MANIFEST).

**Blocked until decided:** box2dxt joining the `release-binaries.yml` manual
assembly; every box2dxt release stays a hand-built binary refresh.

**RECOMMENDATION (the suite's, not a decision):** the docker-run port, taken
as the recorded deliberate release-lane pass. Reasoning: the 2.17 floor is the
oldest-lineage member's shipped promise, the recipe is already proven in
`native-box2dxt.yml`, and the port is mechanical; the floor raise buys only CI
uniformity.

---

## D-04. Which .onion-derivability claim ships (pending the ed25519 equivalence VERIFY)?

**Why it is the owner's:** the plan reserves it in terms: "You own reading the
VERIFY result and choosing the wording that ships." It is a user-protective
claim about what a channel card alone can promise.

**Evidence (verified 2026-08-16):**
`docs/ONIONXT-INTEGRATION-PLAN.md:1800-1803` (decision 14.3);
`docs/ONIONXT-INTEGRATION-PLAN.md:1683-1685` (#27, the hard Phase-2 gate: the
offline `btDhtKeypair` vs `sxSignKeypairFromSeed` byte-compare AND the live
`oxServiceAddress == chChannelOnionAddr` compare);
`docs/anon-transport-threat-model.md:93-100` (the docs already withhold the
claim and say so).

**Options:**
- **Byte-compare passes:** ship the strong "your channel card alone is the
  anon locator" wording.
- **Byte-compare fails:** ship the `svc=` feed-line fallback wording (already
  in the schema; the claim drops).
- Publishing the strong claim unverified is not an option; the honesty
  convention forbids it and the threat-model page enforces it today.

**Blocked until decided:** the strong claim in every suite document and the
Channels positioning copy. Note the decision cannot fully precede the engine
VERIFY (a B-section backlog item); what CAN be decided now is the wording for
each branch.

**RECOMMENDATION (the suite's, not a decision):** pre-approve BOTH wordings
now, so the two-machine engine session flips a label instead of waiting on
copy. Reasoning: the VERIFY is binary and both outcomes already have designed
landing zones; pre-approval converts an owner-plus-engine dependency into an
engine-only one.

---

## D-05. Sign off the anonymous-mode positioning copy

**Why it is the owner's:** the plan reserves it: the in-app wording of what
"anonymous" promises "should carry your explicit approval before it ships."
It is the suite's most user-protective sentence.

**Evidence (verified 2026-08-16):**
`docs/ONIONXT-INTEGRATION-PLAN.md:1805-1808` (decision 14.4);
`docs/anon-transport-threat-model.md:101-104` (the page names itself an input
to the sign-off, not the sign-off).

**Options:** approve the drafted copy as written (`docs/anon-transport.md`,
the threat-model page, the onboarding page were built to be the sign-off
packet); edit and approve; or defer, leaving every converted demo's copy
formally provisional.

**Blocked until decided:** the final anonymous-mode copy in QuickShare /
Channels / nocloud, and the onboarding doc's Phase-4 exit. Code is not
blocked; wording finality is.

**RECOMMENDATION (the suite's, not a decision):** read the three anon-
transport docs as one packet in one sitting and sign off, ideally in the same
session as D-04's branch wording. Reasoning: the copy exists and is
internally consistent; the only missing ingredient is the reserved approval.

---

## D-06. Riptide feed retention: does a follower republish followed heads?

**Why it is the owner's:** it spends followers' resources (DHT writes) to keep
OTHER people's feeds alive: a network-citizenship and abuse-surface tradeoff,
and the one spec-section-12 decision the build has not made by construction.

**Evidence (verified 2026-08-16):** `docs/RIPTIDE-SOCIAL-SPEC.md:724-726`
(decision 4: BEP44 items expire unless republished; how aggressively does a
follower re-seed a followee's head?). As built, only the OWN head republishes
on post (`riptide/examples/riptide-social.livecodescript:747,1541`); no
follower-republish code exists.

**Options:**
- **Follower republishes followed heads** on the DHT-channels demo's cadence
  (the spec's own recommendation; a BEP44 signed item can be re-put by anyone
  holding it). Cost: a few small puts per poll per followed feed; feeds
  survive while any follower is online.
- **No republish** (status quo): a head vanishes when its publisher has been
  offline past DHT expiry; simplest, weakest availability story.
- **Opportunistic:** republish only on read. Middle cost, partial liveness.

**Blocked until decided:** the follower-republish build, and any spec claim
that a feed outlives its publisher's session. The built demo is unaffected.

**RECOMMENDATION (the suite's, not a decision):** the spec's own: republish
heads the user actively follows, on the channels cadence. Reasoning: the cost
is a handful of tiny signed puts and it is precisely what makes the
"serverless feed" thesis true when the publisher sleeps.

---

## D-07. Tor delivery: document-install forever, or bundle a tor binary?

**Why it is the owner's:** bundling means shipping, signing/notarizing, and
UPDATING a security-critical third-party binary per platform: a standing
maintenance and trust commitment only the owner can take on. Recorded as the
owner's in three places.

**Evidence (verified 2026-08-16):**
`docs/ONIONXT-INTEGRATION-PLAN.md:1790-1793` (decision 14.1);
`onionxt/docs/09-open-questions.md:33-35` (question 7, "the default is
documented-install"); `docs/anon-transport-onboarding.md:27` ("an OPEN owner
decision"); the bundled path's mechanics at
`docs/ONIONXT-INTEGRATION-PLAN.md:1740-1743`.

**Options:**
- **Document-install** (shipped default): first-run friction, fail-closed
  when absent, zero distribution burden, the daemon stays the user's.
- **Bundle tor:** best first-run UX; heaviest package, code-signing and
  notarization per platform, an update duty forever, and the daemon-trust
  story shifts onto the suite.
- **Decide never:** document-install is a stable terminal state for the
  demos; the plan already recommends it there.

**Blocked until decided:** nothing for the demos (built and fail-closed). A
product-grade "anon just works" first run is what waits.

**RECOMMENDATION (the suite's, not a decision):** keep document-install
permanently for demos; commit to bundling only as part of a specific product
ship (nocloud is the natural first candidate), where the burden buys a real
audience. This is the plan's own recommendation, restated.

---

## D-08. sodiumxt Windows libsodium: pin the vcpkg baseline, build pinned source, or record the KAT-guarded status quo?

**Why it is the owner's:** it is a supply-chain assurance-level call (how much
provenance the Windows binary must carry) on the member every other member's
crypto composes, and the canonical Windows lane runs only on the release
workflow the owner dispatches.

**Evidence (verified 2026-08-16):**
`sodiumxt/docs/development/building.md:175-184`: Linux/macOS fetch libsodium
by exact version against a SHA256 pin; Windows links whatever libsodium vcpkg
supplies (same 1.0.x line, not covered by the pin); the KATs (BLAKE2b,
Argon2id, ed25519, KDF) are the recorded guard; the doc itself names the two
pinning options.

**Options:**
- **Pin the vcpkg baseline** (a `vcpkg.json` with `builtin-baseline`): small
  change, pins transitively; still vcpkg's build of it.
- **Build the pinned source on Windows too:** uniform with the other
  platforms' pin; more work in the Windows lane (the vcpkg+NMake recipe is
  the canonical one today).
- **Record the status quo as the decision:** zero work; the KATs already
  catch constant or behavior drift, and the doc says so.

**Blocked until decided:** nothing. An "exact-libsodium on every platform"
claim is what cannot be made today.

**RECOMMENDATION (the suite's, not a decision):** the vcpkg baseline pin,
taken the next time the Windows lane is touched; record the KAT-guarded
status quo explicitly until then (a one-line addition to the building doc).
Reasoning: the baseline pin is the cheapest end to the asymmetry, and the
status quo is already honest but deserves the word "decided" in front of it.

---

## D-09. nocloud Tor path: bring keep-alive, or record close-per-response as decided?

**Why it is the owner's:** the deep-dive marks it in terms ("an owner decision
this refactor did not make"): it trades transport complexity on the privacy
path against page-load latency over Tor, and the refactor that could have
smuggled it in deliberately refused to.

**Evidence (verified 2026-08-16):**
`nocloud/docs/http-server-deep-dive.md:376-379` (the keep-alive half "remains
deliberately OPEN"); `:74` (the section-1.1 contract table: clearweb
keep-alive, Tor `Connection: close` on every response);
`docs/REMAINING-WORK.md:68` (the audit carries it as the one owner decision
left from that refactor).

**Options:**
- **Bring keep-alive to the Tor path:** fewer per-request stream setups over
  high-latency circuits; costs idle-timeout bookkeeping per onion stream and
  complexity on the fail-closed path.
- **Record close-per-response as the decision:** zero code; section 1.1 gains
  the word "decided"; multi-request pages over Tor stay slightly slower.
- Leaving it an unrecorded as-built fact is the one option the doc argues
  against (that is drift, not a decision).

**Blocked until decided:** nothing; the shared head builder emits
`Connection: close` on every file head today, exactly as both halves always
did.

**RECOMMENDATION (the suite's, not a decision):** record close-per-response
as decided. Reasoning: an established onion stream has already paid the
circuit cost, per-response close keeps the bounded pump simple and auditable
on the path where auditability is the product, and the decision is reversible
if an OXT pass ever shows Tor page loads visibly stalling.

---

## D-10. Spend an engine-pass item probing for a cheap single-file mtime?

**Why it is the owner's:** engine time is the resource only the owner has, and
the probe is a checklist line in the pass they run. (This is an engine
QUESTION more than a judgment call; it is briefed here because it is recorded
open and only the owner can close it.)

**Evidence (verified 2026-08-16):** `nocloud/docs/oxt-pass-checklist.md:90-93`
("Would improve the validator": does the engine expose a cheap single-file
modification date without scanning the folder? Conditional GET shipped
without it; the `W/"size-seed-gen"` ETag stands in; a cheap mtime would let
ETags survive restarts. A folder-scan-only answer CONFIRMS the current
design).

**Options:** probe it (minutes inside an already-scheduled session; either
outcome is useful); or accept the current design as final (a restart
invalidates every ETag: correct, merely less efficient).

**Blocked until decided:** the restart-stable-validator improvement, and
nothing else.

**RECOMMENDATION (the suite's, not a decision):** keep it on the checklist
and let the next single-machine pass answer it; it costs minutes and both
answers close the question permanently.

---

## D-11. Ratify the large-file anon policy: warn at 256 MiB, never auto-downgrade

**Why it is the owner's:** the plan reserves the warn-vs-block choice and the
threshold; it balances user freedom (huge anon transfers are slow but legal)
against the risk of users being steered to clearnet.

**Evidence (verified 2026-08-16):**
`docs/ONIONXT-INTEGRATION-PLAN.md:1795-1798` (decision 14.2). The default is
BUILT and identical in all three carriers: `kAnonSizeWarn = 268435456` at
`torrentxt/examples/torrent-quickshare.livecodescript:193`,
`torrentxt/examples/torrent-dht-channels.livecodescript:242`, and
`nocloud/src/nocloudquickshare.livecodescript:285` (warn, never block, never
auto-downgrade).

**Options:** ratify the shipped default; switch to a hard block (pick a
threshold; removes the explicit clearnet steer at the cost of refusing
legitimate transfers); or move the threshold. "Decide never" here means the
default quietly hardens into policy without the reserved sign-off.

**Blocked until decided:** nothing; the default ships in three stacks.

**RECOMMENDATION (the suite's, not a decision):** ratify warn + 256 MiB +
never-auto-downgrade, the plan's own recommendation, and record the
ratification at plan section 14. Reasoning: the caveated steer respects the
user; a hard block protects nobody who was not already warned.

---

## D-12. Ratify Channels serve-map durability: prune-on-restart for demos

**Why it is the owner's:** the plan reserves it: persisting the anon serve map
writes a file to disk naming which releases were served anonymously, a
privacy-footprint-vs-convenience call.

**Evidence (verified 2026-08-16):**
`docs/ONIONXT-INTEGRATION-PLAN.md:1810-1813` (decision 14.5); the demo
default is BUILT: a publisher restart cleanly prunes stranded relIds via
`chPruneStrandedAnon` (`docs/ONIONXT-INTEGRATION-PLAN.md:1699-1702`, static-
only so far).

**Options:** ratify prune-on-load for the demos (shipped; a restarted
publisher re-publishes); persist `uOnionServe` for a product (no re-publish
step; the on-disk record is the cost); or both, exactly as the plan
recommends (prune for demos, persist for a product).

**Blocked until decided:** nothing.

**RECOMMENDATION (the suite's, not a decision):** the plan's own: prune for
demos, persist only in a product context where the disk footprint can be
stated in its privacy docs. Ratification is one line at plan section 14.

---

## D-13. The onionxt v2 design menu: rotation cadence, client auth, framing, multiplexing, subverted-tor detection

**Why it is the owner's:** each question trades unlinkability or robustness
against cost and complexity for onionxt's future consumers; v1 shipped
deliberate defaults, and doc 09's law is that each question is resolved in
docs and code in the same change, presented as unsolved until then.

**Evidence (verified 2026-08-16):** `onionxt/docs/09-open-questions.md`:
question 2 (`:12-16`, how much to invest detecting a subverted local tor),
question 3 (`:17-19`, descriptor/activity timing cadence "unsettled"),
question 4 (`:23-25`, epoch-scoped rotating onions: unlinkability vs seconds
of republish unreachability), question 5 (`:26-28`, v3 client auth by
default?), question 6 (`:29-32`, length-prefixed framing helper vs strict
byte-transparency; "leaning transparent"), question 8 (`:36-39`, multiplexing
vs one-socket-per-stream; "one-per-stream is ... the v1 default"). (Question
7 is D-07; questions 9-11 are recorded RESOLVED in the same file.)

**Options:** per question, invest (measure rotation latency and pick a
cadence; default client auth per channel sensitivity; add an optional framing
helper; build stream multiplexing; add Mode-B binary verification) or let the
recorded v1 default stand. "Decide never" is honest for every one: all five
defaults are shipped, labeled, and engine-proven where the engine could reach
them.

**Blocked until decided:** nothing. No consumer has hit any of these limits.

**RECOMMENDATION (the suite's, not a decision):** leave all five open with
the v1 defaults standing, and resolve each only when a real consumer (the
riptide anon persona, Channels anon, a chatty app) hits its limit, in the
docs-and-code-together shape doc 09 already mandates. On question 5
specifically: when Channels anon matures, default client auth OFF with a
per-channel opt-in for high-sensitivity contacts (key distribution is the
real cost, and it is per-relationship).

---

## D-14. oxtkit/ shared native scaffolding: execute or retire?

**Why it is the owner's:** it is an investment call: a cross-cutting refactor
of five proven, engine-verified shims to benefit hypothetical future wraps.
The moment the plan wrote it for ("do this once, on libsodium, before ENet
and libdatachannel") has passed; only the owner can say whether the payoff
still exists.

**Evidence (verified 2026-08-16):** `docs/NEXT-EXTENSIONS-PLAN.md:596-613`
(Part V.2: the extraction list); `docs/REMAINING-WORK.md:410-412` (E.6: never
extracted; the native C scaffolding remains N copies with no drift gate).

**Options:**
- **Execute now:** one tested implementation of the handle table, firewall
  macros, out-buffer helpers, poll-drain queue. Cost: churn across five
  stable members whose copies have legitimately DIVERGED per library (C vs
  C++, plain vs mutexed queue), each divergence engine-proven; the risk lands
  on working code, the benefit on unwritten code.
- **Retire the plan item:** record that the scaffolding stays per-member,
  guarded by each member's own tests. Zero cost; the drift risk continues at
  its current, so-far-harmless level.
- **Middle path:** no code moves; add a cross-member drift REPORT (not a
  gate) over the genuinely-identical blocks, the checker-unification lesson
  applied read-only.

**Blocked until decided:** nothing. Every extension the plan sequenced
shipped without it.

**RECOMMENDATION (the suite's, not a decision):** retire it with a written
note in Part V.2, revisiting only if an eighth native wrap is planned.
Reasoning: the checker unification paid off because those copies MUST be
byte-identical; the shim scaffolding must NOT be (the divergences are
per-library design), so byte-unification is not even the right goal, and the
extraction's window closed when the last planned member shipped.

---

## D-15. coinxt SLIP-39: commit to a phase, or strike "later"?

**Why it is the owner's:** SLIP-39 is a real new crypto surface (Shamir
shares, its own wordlist and vectors) on the highest-stakes member; whether
that soft promise stays in the SPEC is a scope call.

**Evidence (verified 2026-08-16):** `coinxt/SPEC.md:37` ("and SLIP-39 in a
later phase"); `coinxt/README.md:16` ("SLIP-39 later"). No phase, no consumer,
no code.

**Options:** schedule it (real work: shares, GF(256) arithmetic, vectors,
probably shim surface and an ABI bump); strike to "not planned; revisit on
demand" (docs-only); or leave the unscheduled "later" standing (the status
quo: a soft claim with no owner behind it).

**Blocked until decided:** nothing.

**RECOMMENDATION (the suite's, not a decision):** strike to "not planned;
revisit on demand". Reasoning: no suite consumer needs SLIP-39, and an
open-ended "later phase" in a SPEC is exactly the shape of unbacked claim the
honesty convention exists to retire.

---

## D-16. coinxt SHA3-512: ship it or strike it?

**Why it is the owner's:** the SPEC and README claim a hash that does not
exist as a handler; the doc marks it "ship it or strike it is an open call"
(and the audit reclassified it E-class, an owner call). Shipping means an ABI
bump; striking means narrowing the spec.

**Evidence (verified 2026-08-16):** `coinxt/SPEC.md:33-36` (the AS BUILT
mark: no `cnx_sha3_512`/`cxSha3_512` exists, section 5.1 never listed one,
the vendored `sha3.c` implements it); `coinxt/README.md:13-15` (same mark);
`docs/REMAINING-WORK.md:307` ("ship-or-strike SHA3-512 is now an owner call,
E-class").

**Options:**
- **Ship:** one shim export + wrapper + vectors; the real cost is the ABI
  bump, which means rebuilding every committed binary (including the stale
  universal-mac row's manual lipo problem).
- **Strike:** docs-only edit; SHA3-256 and Keccak-256 (what Ethereum
  actually needs) remain.
- **Decide never:** the standing AS BUILT mark is honest but permanent
  clutter in the spec's opening claims.

**Blocked until decided:** nothing; no consumer calls it.

**RECOMMENDATION (the suite's, not a decision):** strike now (free), and if a
consumer ever materializes, ship it bundled with the next planned ABI bump
(the recorded `cnx_memzero` fix at `coinxt/src/coinxt.lcb:124-134` wants one
too) so the binary-refresh cost is paid once.

---

## D-17. coinxt independent-decoder acceptance: give it an optional CI lane?

**Why it is the owner's:** the exclusion from the gate set is a recorded
policy (gates assume no external dependencies); overriding that policy for
one lane, and accepting pip-installed third-party packages into CI, is the
owner's supply-chain and policy call.

**Evidence (verified 2026-08-16):** `coinxt/CLAUDE.md:876-891`: the
independent-decoder run (python-bitcointx + eth-account accepting
script-built transactions in all four families) "is an ACCEPTANCE run, NOT a
CI gate", with the rationale at `:885-889` (pip packages the suite does not
vendor; the tool SKIPs loudly without them, `--require` hardens the skip);
`docs/REMAINING-WORK.md:416-417` (E.8 carries the question).

**Options:**
- **An opt-in, paths-scoped CI lane** (workflow_dispatch or on coinxt
  changes, non-required) that pip-installs the decoders and runs
  `--require`. Buys: the member's strongest correctness signal runs where it
  cannot be forgotten. Costs: pip supply-chain exposure in CI, network
  dependence, flake surface.
- **Status quo:** run it manually per release (documented). Risk: it goes
  silently stale between releases.
- **Decide never:** the status quo IS a recorded decision; re-affirming it
  costs nothing.

**Blocked until decided:** nothing.

**RECOMMENDATION (the suite's, not a decision):** add the opt-in lane,
non-required and paths-scoped to coinxt, keeping it out of `build-all.sh`
(the recorded local-gate rationale stands). Reasoning: "code we did not write
accepts our bytes" is the member's best claim short of a broadcast, and a
claim that strong deserves a machine that re-earns it.

---

## D-18. box2dxt/holde-em suite-kit chrome and scaffold: convert, or make the exemptions permanent?

**Why it is the owner's:** the record calls the chrome half "an aesthetic
call": whether form chrome belongs on game canvases is taste, and the
exemptions already argue it does not.

**Evidence (verified 2026-08-16):** `tools/check-ui-kit-drift.py:75-98`
(seven written exemptions: five box2dxt games + selftest, holde-em's table,
each with its reason; a stale entry fails the gate);
`box2dxt/CLAUDE.md:48-55` ("Phase-2 work, deliberately deferred: suite-kit
chrome for the game stacks (an aesthetic call ...), harness-scaffold adoption
for examples/box2dxt-selftest, and folding that selftest into the suite
harness"); holde-em's fold record carries the same phase-2 call.

**Options:**
- **Convert the games:** family-uniform chrome; risk it reads WORSE on a
  game canvas; real per-stack work plus OXT passes.
- **Make the exemptions permanent:** zero work; each already carries a
  written, gate-checked reason; the record changes "phase-2" to "permanent".
- **Split (partial):** keep the game-canvas exemptions, but adopt the
  harness scaffold for `box2dxt-selftest`; that half is fold machinery, not
  chrome, and it is a prerequisite of the eighth-member harness fold.

**Blocked until decided:** nothing for the chrome (the gate holds the
exemptions honestly). The box2dxt suite-harness fold waits on the
scaffold/report-mode half either way.

**RECOMMENDATION (the suite's, not a decision):** the split: record the
game-canvas chrome exemptions as permanent (their written reasons are
convincing) and take scaffold adoption for the selftest as ordinary
engineering when the fold happens, since it needs an OXT pass in the same
change anyway.

---

## D-19. The box2dxt roadmap menu: schedule anything, or let the recorded triggers stand?

**Why it is the owner's:** every item is play-value against effort on a
feature-frozen member; each already carries a written trigger or park reason,
so the only live question is whether the owner wants to schedule any of them.

**Evidence (verified 2026-08-16):**
- Wave 8 builder cross-pollination, "the only remaining roadmap item":
  `box2dxt/docs/archive/expansion-prep.md:241-243`.
- `b2kScene*` promotion "did NOT land ... Revisit only if a second game needs
  it": `box2dxt/docs/archive/expansion-prep.md:248-250`,
  `box2dxt/plan.md:204-210`.
- Enemy-pattern (`b2kFoe`) promotion waits for a second consumer:
  `box2dxt/plan.md:198-203`, `box2dxt/docs/archive/expansion-prep.md:235-237`.
- Streamed music via player objects "stay future work":
  `box2dxt/plan.md:188-197`.
- Multi-player controller keying "deferred with multi-player (the refactor is
  mechanical)": `box2dxt/plan.md:272`.
- Snake-audit extension (audit-platformer still ignores
  `pfMakeSnake`/`pfMakeSerpent`, recorded harmless):
  `box2dxt/docs/asset-expansion-plan.md:261-263`.
- True parallax parked on art (loaded scenes measured 100% opaque;
  single-layer drift is the ceiling until transparent overlay art exists):
  `box2dxt/docs/asset-expansion-plan.md:368-370,428-429`.

**Options:** schedule an item (each is a bounded, PR-sized pass with its own
plan already written); or let every trigger stand (zero cost; each trigger is
specific and self-executing when its condition arrives). "Decide never" is
effectively already recorded per item.

**Blocked until decided:** nothing.

**RECOMMENDATION (the suite's, not a decision):** let the triggers stand. The
one item with a live trigger candidate is the `b2kScene*`/`b2kFoe` promotion:
if holde-em or a future game becomes the second consumer, the recorded
condition fires on its own. Parallax additionally waits on art only the owner
can source.

---

## D-20. The channels brainstorm: promote anything further, including the flagged SodiumXT helpers?

**Why it is the owner's:** the document is a labeled menu of open problems
(metadata privacy, multi-hop, group messaging), and the two flagged SodiumXT
additions are ABI-bump-sized crypto surface on the member everything
composes; scope there is an owner call by suite law.

**Evidence (verified 2026-08-16):**
`docs/SODIUM-TORRENT-CHANNELS-BRAINSTORM.md:1-13` (the status: the core
substrate SHIPPED and runs as riptide; "the rest stays a menu to argue with");
`:89-97` (the identity-derivation passage: seeded kx keypairs SHIPPED, the
ed25519-to-X25519 conversion did not; the suite derives per-purpose seeds
instead); `:306` and `:407-409` (the flagged additions: the conversion, and
an optional k-of-n secret-sharing layer).

**Options:**
- **Add `crypto_sign_ed25519_pk_to_curve25519` to SodiumXT:** small shim
  add, but an ABI bump (the full binary-refresh ripple); buys encrypting to
  a signing-only public key you cannot ask for a prekey.
- **Add k-of-n secret sharing:** libsodium has no Shamir; it would need a
  vendored implementation, in tension with the family's no-new-cryptography
  rule.
- **Decide never (the standing default):** per-purpose derived seeds cover
  every shipped consumer (riptide ships on them), and the brainstorm stays a
  labeled menu.

**Blocked until decided:** nothing; riptide already realized the menu's
buildable core.

**RECOMMENDATION (the suite's, not a decision):** decide never for both
helpers until a consumer needs to encrypt to a signing-only key it cannot
exchange prekeys with (every shipped sealed-DM design exchanges prekeys);
bundle the conversion with a future planned ABI bump if that consumer
appears. The wider menu needs no decision at all: it is labeled brainstorm
and behaves like one.

---

## D-21. Hold'em: build a betting-blind oracle daemon, or keep the recorded no-stake property?

**Why it is the owner's:** it is a threat-model scope call on Level 1 (a
stopgap below Level 2 mental poker): whether "the oracle never sees betting"
is worth splitting the relay from the dealer, against spending that effort on
the level that removes the oracle entirely.

**Evidence (verified 2026-08-16):** `holde-em/holdem-spec.md:267-272`: the
recorded divergence: as built the oracle IS the relay host, so it handles the
(public, signed) betting wires; what Level 1 actually needs is the no-stake
property, which holds; "A betting-blind oracle daemon remains open work if it
ever earns its complexity."

**Options:**
- **Build the split daemon:** a second role and election path so the oracle
  handles deal-phase messages only. Buys betting-blindness for a party that
  still sees every card; real protocol complexity.
- **Keep as-built:** the no-stake property (no cards held, no chips, no
  receipt signature) is the recorded, honest promise.
- **Decide never once Level 2 plays:** the ristretto255 deal removes the
  oracle; the question dissolves.

**Blocked until decided:** nothing; Phase 4/5 is the recorded path past it.

**RECOMMENDATION (the suite's, not a decision):** decide never, contingent on
Level 2 landing, exactly as the spec's own conditional records. If Level 2
stalls permanently, revisit; until then the complexity has no buyer.

---

## Checked and found already decided (no briefs; verified 2026-08-16)

These were listed in or adjacent to REMAINING-WORK section E but turned out
to carry their written resolutions already:

- **torrentxt Phase-5 dashboard widget** (E.10 first half): decided
  2026-08-13, "out of v1 scope ... its absence is a decision with a date, not
  an open item" - `torrentxt/docs/TorrentXT-IMPLEMENTATION-PLAN.md:514-519`.
- **datachannelxt media tracks** (E.10 second half): a recorded deliberate
  Phase-1 exclusion with its revisit condition written ("if media ever lands
  it will be engine-side with a separate plan") -
  `datachannelxt/docs/architecture.md:106-110`.
- **Riptide spec section 12, decisions 1, 2, 3, and 5** (one stack vs a set;
  anon persona count; prekey rotation; which demo first): resolved by
  construction along the spec's own recommendations (one stack, one persona,
  long-term prekey, built through phase 7) - `docs/RIPTIDE-SOCIAL-SPEC.md:
  712-730` still lists them, but the as-built record supersedes; only
  decision 4 remains open (D-06). Annotating section 12 with the four
  by-construction resolutions would close the gap between the spec and the
  tree.
- **onionxt open-questions 9, 10, 11** are marked RESOLVED/answered in the
  file itself - `onionxt/docs/09-open-questions.md:41-57`.
- **coinxt Schnorr's "which upstream provides it"** (the phase-0 half of
  D-01's territory) is answered and recorded as a scope decision -
  `coinxt/CLAUDE.md:528-535`; what remains open is only the vendoring call
  D-01 briefs.
