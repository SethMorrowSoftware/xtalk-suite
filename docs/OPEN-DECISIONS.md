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

**CITATION CONVENTION, CHANGED 2026-08-17 - and why the old attestation was
retired.** This preamble used to say every citation had been "re-verified against
the tree on the compile date", and on that date it was true. It stopped being true
within a day, because **a line number is a fact about a file's current shape, and
this tree reshapes faster than its documents are re-read**: six citations here
landed in unrelated prose (A.10's Schnorr entry pointed at the punch list's summary
paragraph; the riptide feed-retention decision pointed three sections short of
§12; the `cnx_memzero` cite landed on a comment about `use com.livecode.foreign`).
An owner following one of those does not get a five-minute brief.

So citations here are being converted from `file:line` to **`file` plus a quoted
ANCHOR PHRASE** - text that moves WITH the thing it names - and
`tools/check-doc-anchors.py` re-resolves every anchor, failing when one no longer
appears in its file and printing the line where it now lives.

**This claim was false, then true, inside one day, and both halves are worth
keeping.** The sentence originally said the anchors were re-checked "on every
push", which was the intent and had never been the tree: the tool was invoked by
no script and no workflow, so an anchor that drifted drifted silently until
somebody typed the command. That was corrected on 2026-08-19 to say the tool is
run by hand - and then, later the same day, the tool was wired into the suite
gate block in `tools/build-all.sh`, above the `--gates` exit, so
`.github/workflows/suite-gates.yml` now runs it on every push. **It is a real
gate now.** The lesson that survives both corrections is the one this file keeps
catching in other people's numbers: a doc that describes what SHOULD happen reads
identically to one that describes what does. The
conversion is incremental: the six that had drifted are done, and any citation
touched from here on gets an anchor. An un-anchored `file:line` below has NOT been
re-verified since 2026-08-16 - treat it as a hint, not a fact.

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
helper. `docs/REMAINING-WORK.md` ("coinxt Schnorr/BIP-340 + the Taproot tweak", A.10) marks the whole Schnorr +
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

## D-02. ~~nocloud HTTP host: standards polish or new capability - the deep-dive section 8 priority questions~~ DEFERRED 2026-08-27

**DEFERRED 2026-08-27 (owner-delegated call).** The section-8 polish menu waits
for the first external user report: every item is standards nicety, none is a
defect, and no consumer has hit any of them. Revisit on the first real-world
report against the HTTP host.

**Why it is the owner's:** these are product-direction calls about nocloud's
users (what they need, how much integrity machinery they will value, what the
privacy defaults should be), and they order how the remaining phases spend the
app's complexity budget.

**Evidence (verified 2026-08-16):**
`nocloud/docs/http-server-deep-dive.md:417-431` (section 8, "Open questions
for you": priorities; public-vs-LAN introspection default; how far routes go;
integrity appetite; compression), `:356-389` (the phased plan whose ordering
hangs on question 1; Phase 3 at 380-381), `docs/REMAINING-WORK.md` ("nocloud HTTP-host Phase 3: per-route streaming/params")
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

## D-03. ~~box2dxt in the release lane: its own docker-run job, or raise the glibc floor to 2.28?~~ DECIDED 2026-08-27: RESOLVED BY EVENTS

**DECIDED 2026-08-27: resolved by events.** Release run 12 built and committed
box2dxt's Linux binaries from the same manylinux image as every other member -
the question ("its own docker-run job, or raise the glibc floor?") assumed the
shared lane could not carry it, and the lane now demonstrably does. No separate
job; the glibc floor stands as-is.

**Why it is the owner's:** moving box2dxt's Linux build to manylinux_2_28
would raise its glibc floor from 2.17 to 2.28, "a real portability regression,
the owner's call" (recorded in those words): dropping users on older distros
is a support promise only the owner can renegotiate.

**Evidence (verified 2026-08-16):** `box2dxt/CLAUDE.md:34-47`: box2dxt is not
in `release-binaries.yml`'s matrix; its known-good Linux recipe is `docker run
manylinux2014` inside a stock runner (node20 actions refuse to start in a
glibc-2.17 container), which cannot join the `cmake-members` job's
`container:` shape; ~~`tools/install-release-binaries.py` also does not know
box2dxt's package layout~~ - **that half LANDED 2026-08-17, and the cost was
MISPRICED rather than paid: there was never a layout to learn.** box2dxt's
`src/code` is the identical family layout to sodiumxt's and torrentxt's, so the
installer needed ONE token; it is verification-only and inert until a lane
exists, and pinned by a committed `--selftest`. Only the WORKFLOW half remains,
which is the half that is genuinely this decision's. "Do this as a deliberate
release-lane pass, not a drive-by."

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

## D-05. ~~Sign off the anonymous-mode positioning copy~~ SIGNED OFF 2026-08-27

**SIGNED OFF 2026-08-27 (owner-delegated call).** The positioning copy ships as
written: it claims IP-hiding and payload privacy, disclaims Tor-use visibility
and timing/volume, and the honesty labels carry the unproven legs. No wording
change required before release.

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

## D-06. ~~Riptide feed retention: does a follower republish followed heads?~~ DECIDED 2026-08-27: NO REPUBLISH

**DECIDED 2026-08-27 (owner-delegated call): a follower does NOT republish
followed heads.** Privacy-first default, matching the suite's anon posture: a
republish amplifies retention of someone else's content without their consent,
and the failure mode of NOT republishing (a feed goes quiet when its author is
offline) is visible and explainable, while the failure mode of republishing
(content outliving its author's delete) is neither. Revisit only as an explicit
per-follow opt-in, never a default.

**Why it is the owner's:** it spends followers' resources (DHT writes) to keep
OTHER people's feeds alive: a network-citizenship and abuse-surface tradeoff,
and the one spec-section-12 decision the build has not made by construction.

**Evidence (verified 2026-08-16; citation re-anchored 2026-08-17):** `docs/RIPTIDE-SOCIAL-SPEC.md` ("## 12. Open decisions for the owner")
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

## D-07. ~~Tor delivery: document-install forever, or bundle a tor binary?~~ DECIDED 2026-08-27: DOCUMENT-INSTALL

**DECIDED 2026-08-27 (owner-delegated call): document-install, indefinitely.**
Bundling a tor binary imports packaging, update, and per-jurisdiction burdens
onto every release for a convenience the onboarding doc already provides in
four platform-specific steps. The decision is revisitable if a consumer app
(nocloud) ever targets non-technical users as its primary audience.

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

## D-08. ~~sodiumxt Windows libsodium: pin the vcpkg baseline, build pinned source, or record the KAT-guarded status quo?~~ DECIDED 2026-08-27: KAT-GUARDED STATUS QUO

**DECIDED 2026-08-27 (owner-delegated call): record the KAT-guarded status
quo.** The KATs gate correctness on every build and the release lane drives the
published vectors on a real Windows runner before any DLL is bundled - a silent
libsodium regression cannot reach a committed binary. A vcpkg baseline pin adds
maintenance without adding a check.

**Why it is the owner's:** it is a supply-chain assurance-level call (how much
provenance the Windows binary must carry) on the member every other member's
crypto composes, and the canonical Windows lane runs only on the release
workflow the owner dispatches.

**Evidence (verified 2026-08-16):**
`sodiumxt/docs/building.md:175-184`: Linux/macOS fetch libsodium
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

## D-09. ~~nocloud Tor path: bring keep-alive, or record close-per-response as decided?~~ DECIDED 2026-08-27: CLOSE-PER-RESPONSE

**DECIDED 2026-08-27 (owner-delegated call): close-per-response stands.** It is
built, proven, and simple; the keep-alive win over Tor is unmeasured and circuit
reuse cuts against stream unlinkability. Not worth a behaviour change to an
inbound path for an unproven latency gain.

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

## D-10. ~~Spend an engine-pass item probing for a cheap single-file mtime?~~ DECIDED 2026-08-27: YES, TONIGHT

**DECIDED 2026-08-27: yes - spend the engine minute.** The probe (`the detailed
files` on one file, is mtime cheap and stable?) rides tonight's nocloud
checklist leg; one line of findings decides the conditional-GET refinement.

**Why it is the owner's:** engine time is the resource only the owner has, and
the probe is a checklist line in the pass they run. (This is an engine
QUESTION more than a judgment call; it is briefed here because it is recorded
open and only the owner can close it.)

**Evidence (verified 2026-08-16; citation re-anchored 2026-08-17):** `nocloud/docs/oxt-pass-checklist.md` ("cheap single-file mtime")
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

## D-11. ~~Ratify the large-file anon policy: warn at 256 MiB, never auto-downgrade~~ RATIFIED 2026-08-27

**RATIFIED 2026-08-27 (owner-delegated call): as built.** Warn at 256 MiB;
never auto-downgrade an anon transfer to the clear path. Silent downgrade is
the one behaviour an anonymity feature must never have.

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

## D-12. ~~Ratify Channels serve-map durability: prune-on-restart for demos~~ RATIFIED 2026-08-27

**RATIFIED 2026-08-27 (owner-delegated call): as built.** Prune-on-restart for
demo serve-maps: a demo's job is a clean reproducible run, not durability, and
persistence would resurrect shares the operator believed gone.

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

## D-13. ~~The onionxt v2 design menu: rotation cadence, client auth, framing, multiplexing, subverted-tor detection~~ DEFERRED 2026-08-27

**DEFERRED 2026-08-27 (owner-delegated call): the whole v2 menu.** v1 is
complete, statically verified, and (after tonight) live-proven; every v2 item
(rotation cadence, client auth, framing, multiplexing, subverted-tor detection)
is scope growth with no consumer pulling it. The menu stays recorded here for
when one does.

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

## D-14. ~~oxtkit/ shared native scaffolding: execute or retire?~~ DECIDED 2026-08-27: RETIRE

**DECIDED 2026-08-27 (owner-delegated call): retire.** The extraction's entire
value - the three handle tables never drifting - is already delivered by
`check-shim-scaffold-drift.py` holding them byte-identical on every push.
Extraction now would be churn across three shims for a property the tree
already enforces. The scaffold comparison gate stays.

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

> **AMENDED 2026-08-17: half of that reasoning was measured, and half of it was
> wrong.** "The divergences are per-library design" HOLDS for the record codecs -
> `btx_record.h` / `enx_record.h` / `dcx_record.h` normalise to 275 / 198 / 202
> code lines over three different field registries. It does NOT hold for the
> HANDLE TABLE, which normalises to **89 code lines and ONE digest in all three
> C++ members**, the only surviving raw differences being the include guard, the
> `namespace` line and the comments. That is not three implementations that
> happen to resemble each other; it is one implementation in three files - and
> suite rule 4 ("a stale handle is a harmless no-op") IS that header, three
> times, so a fix landing in one copy left the other two members' stale-handle
> rule quietly weaker, with the symptom arriving on an engine as a touch of a
> recycled slot.
>
> `tools/check-shim-scaffold-drift.py` now holds those three byte-equivalent and
> **pre-empts none of the three options above**: it is scoped to the handle table
> ALONE, and this decision stays open over every other block. What changed is
> only that the recommendation's premise can no longer be stated unqualified.

---

## D-15. ~~coinxt SLIP-39: commit to a phase, or strike "later"?~~ DECIDED 2026-08-27: STRIKE "LATER"

**DECIDED 2026-08-27 (owner-delegated call): strike "later" - SLIP-39 is not
planned.** BIP-39 covers the suite's own consumers (holde-em, riptide, the
demos); SLIP-39's group shares serve a custody model nothing here implements.
Revisit only with a named consumer, bundled with a planned ABI bump.

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

## D-16. ~~coinxt SHA3-512: ship it or strike it?~~ DECIDED 2026-08-27: THE 2026-08-17 DEFERRAL STANDS

**DECIDED 2026-08-27 (owner-delegated call): the 2026-08-17 deferral is the
standing decision.** SHA3-512 ships only if a consumer materializes, and then
bundled with the next planned ABI bump (the recorded `cnx_memzero` fix wants
one too) so the five-platform refresh is paid once. SPEC.md section 1 already
records the full close; the docs stopped advertising 512 a week ago.

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
  universal-mac row - since 2026-08-23 a `release-binaries.yml` dispatch
  covers that too, so it is a button rather than the manual lipo problem
  this line was written about).
- **Strike:** docs-only edit; SHA3-256 and Keccak-256 (what Ethereum
  actually needs) remain.
- **Decide never:** the standing AS BUILT mark is honest but permanent
  clutter in the spec's opening claims.

**Blocked until decided:** nothing; no consumer calls it.

**RECOMMENDATION (the suite's, not a decision):** strike now (free), and if a
consumer ever materializes, ship it bundled with the next planned ABI bump
(the recorded `cnx_memzero` fix at `coinxt/src/coinxt.lcb` ("private foreign handler _cnx_memzero") wants one
too) so the binary-refresh cost is paid once.

---

## D-17. ~~coinxt independent-decoder acceptance: give it an optional CI lane?~~ DECIDED 2026-08-27: MANUAL-ONLY

**DECIDED 2026-08-27 (owner-delegated call): decoder acceptance stays
release-dispatch-driven.** The release lane already runs it before any binary
is bundled, which is the moment it protects. A per-push lane would spend a
Windows runner on every docs commit to re-prove an unchanged binary.

**Why it is the owner's:** the exclusion from the gate set is a recorded
policy (gates assume no external dependencies); overriding that policy for
one lane, and accepting pip-installed third-party packages into CI, is the
owner's supply-chain and policy call.

**Evidence (verified 2026-08-16; citation re-anchored 2026-08-17):** `coinxt/CLAUDE.md` ("THE ENGINE PASS LANDED 2026-08-12"): the
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

## D-18. ~~box2dxt/holde-em suite-kit chrome and scaffold: convert, or make the exemptions permanent?~~ DECIDED 2026-08-27: EXEMPTIONS PERMANENT

**DECIDED 2026-08-27 (owner-delegated call): the exemptions are permanent.**
The harness scaffold matches the kit BY VALUE and the kit gate's exemption
list records exactly that; converting the harnesses would add a second
300-line block to every paste for zero visual change. The exemption reasons
stop being provisional and become the design.

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

## D-19. ~~The box2dxt roadmap menu: schedule anything, or let the recorded triggers stand?~~ DECIDED 2026-08-27: TRIGGERS STAND

**DECIDED 2026-08-27 (owner-delegated call): schedule nothing.** The recorded
triggers ("build X when Y happens") are the roadmap; pre-scheduling any of it
would be planning theatre over a game layer that is already complete for its
consumers (holde-em's art, the demos).

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
  `box2dxt/docs/archive/asset-expansion-plan.md:261-263`.
- True parallax parked on art (loaded scenes measured 100% opaque;
  single-layer drift is the ceiling until transparent overlay art exists):
  `box2dxt/docs/archive/asset-expansion-plan.md:368-370,428-429`.

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

## D-20. ~~The channels brainstorm: promote anything further, including the flagged SodiumXT helpers?~~ DECIDED 2026-08-27: PROMOTE NOTHING FURTHER

**DECIDED 2026-08-27 (owner-delegated call): promote nothing further.** The
brainstorm's viable core (channels over BEP44, sealed feeds, quickshare) has
long since shipped as the built demos and nocloud; what remains in the document
is ideas whose costs are recorded beside them. It stays a SNAPSHOT idea bank,
not a backlog.

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

## D-21. ~~Hold'em: build a betting-blind oracle daemon, or keep the recorded no-stake property?~~ DECIDED 2026-08-27: NO DAEMON

**DECIDED 2026-08-27 (owner-delegated call): keep the recorded no-stake
property; build no betting-blind oracle daemon.** A standing daemon
reintroduces a trusted server into a design whose whole claim is
serverlessness, and Phase 3's in-protocol oracle role already covers the
Level-1 deal. The no-stake caveat stays documented where it is.

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

## D-22. coinxt Solana support: where does ed25519 come from, and does Solana belong in coinxt at all?

**Why it is the owner's:** every option changes something the owner has already
ruled on. Vendoring ed25519 into coinxt widens the audited native surface on the
highest-stakes member and costs an ABI bump plus a five-platform binary refresh -
the exact cost D-16 weighed and declined for SHA3-512. Taking ed25519 from
sodiumxt instead would make coinxt the FIRST native member with a cross-member
dependency, which changes what "self-contained extension" means suite-wide. A
third member would add a ninth extension to a suite whose member count is itself
a maintenance decision. And all three change coinxt's identity from "Bitcoin and
Ethereum" (its README's first line) to a multi-curve chain library. None of that
is a coding call.

**Evidence (measured 2026-08-31 by driving the real shim through ctypes, the way
`coinxt/tools/coin-kat.py` builds and loads it; the probe is scratch and is not
in the tree, so re-derive rather than cite it):**

- **Exactly ONE primitive is missing, and it is ed25519.** Measured leg by leg
  against Solana's requirements:
  - *SLIP-0010 ed25519 HD derivation* is `cnx_hmac_sha512` and nothing else.
    Driven through the shim against SLIP-0010's own published vector 1, the
    master node and `m/0'` reproduce the published private key and chain code
    byte for byte, and `m/44'/501'/0'/0'` (Phantom's path) walks. **No new
    native code.** Note it is hardened-only by construction, so there is no
    ed25519 analogue of `cxHdNeuter` / xpub watch-only.
  - *Addresses* are plain base58 of the 32-byte public key, no checksum -
    Satoshi's alphabet, which `coinxt/src/coinxt.livecodescript` already carries
    as `kCxBase58Alphabet`. `cxBase58Encode` / `cxBase58Decode` exist today but
    are PRIVATE (Base58Check is the public wrapper). Cross-check: 32 zero bytes
    encode to `11111111111111111111111111111111`, the System program id.
    **No new native code; two handlers change visibility.**
  - *PDA / `findProgramAddress`* is `cnx_sha256` over
    `seeds || programId || bump || "ProgramDerivedAddress"`, rejecting a
    candidate that lands ON the ed25519 curve. The hash half is the shim's
    today. **The on-curve test is the gap**, and it is load-bearing rather than
    exotic: the Associated Token Account address every SPL-token send needs is a
    PDA.
  - *Signing* is PureEdDSA over the whole serialized message, not over a digest.
    Every curve entry point coinxt ships is digest-in, so this is a genuinely
    new shape at the FFI seam - though a benign one, since the hash entry points
    already take a variable-length buffer.
  - *Transaction building* (compact-u16 shortvec, the legacy and v0 message
    layouts, account-ordering and dedup rules, System / SPL-Token / ATA
    instruction data) is byte-shuffling with no secret-dependent branch. By
    coinxt's own C-vs-script rule that is **script**, and it is strictly
    simpler than the base58 long division, bech32 and BIP-32 serialization
    already in that file. One difference from every encoding coinxt ships
    today is worth carrying: Solana's wire format is UNCHECKSUMMED, so a
    transcription slip in an account index or a shortvec length produces a
    well-formed transaction that moves the wrong lamports to the wrong
    account, with nothing on the wire to catch it. That is the
    valid-looking-wrong-address failure `check-script-vectors.py` was written
    for, one step worse, and it argues for the vector gate BEFORE the
    handlers, not after.
- **sodiumxt has three of the four ed25519 legs and not the fourth.**
  `sxSignKeypairFromSeed`, `sxSignDetached` and `sxSignVerifyDetached` are
  libsodium's ed25519 and are exactly what signing needs. There is no ed25519
  point-validity export: `sxRistrettoPointValid` is **ristretto255**, a
  different encoding, and cannot answer the PDA question. Closing that gap is a
  sodiumxt ABI bump and its own five-platform refresh, so "reuse sodiumxt" is
  not free either - it moves the native cost to a second member.
- **coinxt has ed25519-donna's HEADER vendored already and links none of its
  code.** `native/vendor/VENDOR.md` records it as headers-only: `secp256k1.h`
  needs `curve_info` from `bip32.h`, which includes the ed25519 typedefs. The
  same file records the reason BIP-32 was not vendored - `bip32.c` "drags in
  curves.c, nist256p1, ed25519-donna and the Cardano variants". Adding ed25519
  is therefore MORE OF THE FIRST UPSTREAM, not a third one: same MIT tree, same
  pin, same LICENSE row. That matters for the rule-1 argument, which D-01
  already changed once and would not need to change again.
- **The point-validity test looks reachable through donna's PUBLIC API.**
  `ed25519_scalarmult` is declared `int` in the vendored header, and upstream
  returns non-zero when the point fails to unpack, which is precisely the
  `decompress().is_some()` test Solana's `is_on_curve` performs. If that holds
  at the pin, no vendored internal header is needed and no new curve code is
  written. **VERIFY against the pinned source before costing on it**, and pin
  the equivalence with a differential KAT either way - a wrong answer here does
  not crash, it derives a valid-looking wrong ATA, which is the same failure
  class `check-script-vectors.py` exists for.
- **The script half can be proven offline before an engine is ever booked.**
  `coinxt/tools/lcs-interp.py` + `check-script-vectors.py` already drive the
  real shipped `.livecodescript` against published vectors with the real native
  library behind it. A Solana serializer is inside the subset that file already
  uses. So the pure-script ~80% of this work is CI-verifiable, and only the
  ed25519 seam needs engine time.
- **The ABI-bump cost is materially lower than when D-16 declined it on
  2026-08-17.** `release-binaries.yml` reached its commit stage for the first
  time on 2026-08-27 (run 12), landing universal-mac for four members and
  rebuilding every Linux/Windows binary. A five-platform refresh is now a
  dispatch and a review, not an unproven path. That is a change in the cost, not
  in the rule: rule 5 still wants a human decision behind every committed
  binary, and pressing "Run workflow" is that decision.

**Options:**

- **A. Vendor ed25519-donna into coinxt (ABI 7).** Roughly four new `cnx_`
  entry points plus their length accessors: pubkey-from-seed, sign, verify,
  point-is-valid. ed25519-donna is shaped as one implementation unit under a
  stack of headers, and `sha2.c` / `memzero.c` - the two things it needs from
  the rest of the tree - are vendored already; that shape is INFERRED from
  upstream's layout and the vendored header, not measured here, so treat the
  file count as unknown until the closure is found. `src/coinxt.map` needs no edit
  (`cnx_*` is a glob). Costs: the closure must be found the way phase 2's was
  (compile, read the undefined symbols, add the file, repeat) rather than
  guessed; the ABI bump in `CNX_ABI_VERSION` and `kABIVersion`; five committed
  binaries refreshed in the same change under suite rule 5; a KAT leg against
  RFC 8032; `tools/build-preflight.py` re-generated. Buys: coinxt stays a leaf
  with no cross-member dependency, PDAs work, and the "one vendored tree per
  curve family" story stays clean.
- **B. Take ed25519 from sodiumxt, script-only in coinxt.** No coinxt ABI bump
  and no binary refresh for the signing legs. Costs: coinxt becomes the first
  native member that cannot run standalone, which contradicts "each member stays
  a self-contained extension"; a `start using` / co-embed ordering constraint
  appears in every carrier (the embed registry already orders providers by
  dependency, so this is mechanism that exists, not new machinery); and PDAs
  still need a sodiumxt ABI bump for an ed25519 point-validity export, so the
  native cost is deferred rather than avoided. Realistically this is "A, but
  paid by sodiumxt", plus a new coupling.
- **C. A new member (`solanaxt`), pure script over coinxt + sodiumxt.** The
  nostrxt shape exactly, and it keeps coinxt's Bitcoin+Ethereum identity intact.
  Costs: a ninth extension with its own CLAUDE.md, gates, docs, demo, harness
  and fold row; it inherits option B's PDA gap unchanged; and it splits the
  base58 encoder from its only other user, or re-implements it.
- **D. Decide never.** Record that coinxt is a secp256k1 library and that
  ed25519 chains are out of scope, with a written trigger. Honest, and free.

**Blocked until decided:** nothing. No suite member, app or recorded item needs
Solana today; this brief exists because the question was asked, not because
something is waiting.

**RECOMMENDATION (the suite's, not a decision):** **option A, gated on a real
consumer** - which is the same shape D-16 gave SHA3-512, with one difference
worth stating plainly. SHA3-512 was one export nothing needed. This is four
exports that unlock an entire chain, and the analysis above says the expensive
half is smaller than it looks: the HD layer, the addresses and the whole
transaction builder need no native code at all and are provable in CI today.

So the recommendation is to keep it in coinxt rather than to split it out
(option C buys nothing that coinxt's own prefix does not, and pays a member's
overhead for it), to prefer A over B (B's saving is temporary, and it trades a
one-time ABI bump for a permanent dependency edge on the member that most
benefits from having none), and NOT to build it before a caller exists. If a
caller does appear, the honest first slice is the script layer alone, driven
through `check-script-vectors.py`, with `cxEd25519*` failing closed against an
ABI-6 binary - the same fail-closed-on-an-older-library seam nostrxt already
uses for NIP-44 over sodiumxt ABI 10.

**Status of the measurements above: the SLIP-0010, base58 and PDA-hash legs
were executed headlessly against the real native shim through ctypes on
2026-08-31 and agree with the published vectors; every proposed handler is
UNBUILT, so no `cxSol*` or `cxEd25519*` leg has been executed anywhere, on an
engine or off one.** The ed25519 point-validity route through
`ed25519_scalarmult` is the one claim here that is INFERRED from the vendored
header and upstream's documented behaviour rather than measured, and it is
marked VERIFY above for that reason.

---

## Checked and found already decided (no briefs; verified 2026-08-16)

These were listed in or adjacent to REMAINING-WORK section E but turned out
to carry their written resolutions already:

- **torrentxt Phase-5 dashboard widget** (E.10 first half): decided
  2026-08-13, "out of v1 scope ... its absence is a decision with a date, not
  an open item" - `torrentxt/docs/archive/TorrentXT-IMPLEMENTATION-PLAN.md:514-519`.
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
